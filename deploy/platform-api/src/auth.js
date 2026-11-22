import {ApiError, auditStatement, digest, json, now, readJson, uuid} from './core.js';
import {decrypt, encrypt} from './encryption.js';
import {identityKeyRing, identityHashes} from './identity_keys.js';
import {handleGoogleAuth} from './google_auth.js';
import {sendTransactionalEmail, transactionalEmailAvailable} from './email_delivery.js';

const ACCESS_SECONDS = 900;
const OTP_SECONDS = 300;
const MFA_SECONDS = 300;
const MAX_BODY = 8192;
const SITEVERIFY = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';
const encoder = new TextEncoder();
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const hex = bytes => [...new Uint8Array(bytes)].map(v => v.toString(16).padStart(2, '0')).join('');
const unix = () => Math.floor(Date.now() / 1000);

function unavailable(code = 'auth_unavailable') {
  throw new ApiError(503, code, 'Sign-in is unavailable. Please try again later or contact support.');
}
function invalid(code = 'invalid_credentials') {
  throw new ApiError(401, code, 'The sign-in details are invalid or expired.');
}
function requireFields(body, allowed) {
  if (Object.keys(body).some(k => !allowed.includes(k)))
    throw new ApiError(400, 'invalid_request', 'The request contains an unsupported field.');
}
function flag(value, fallback) {
  if (value === undefined || value === '') return fallback;
  if (value === true || value === 'true') return true;
  if (value === false || value === 'false') return false;
  unavailable('auth_configuration_invalid');
}
function boundedInteger(value, fallback, min, max) {
  if (value === undefined || value === '') return fallback;
  const number = typeof value === 'number' ? value : /^[0-9]+$/.test(value) ? Number(value) : NaN;
  if (!Number.isSafeInteger(number) || number < min || number > max) unavailable('auth_configuration_invalid');
  return number;
}
function secret(value, minimum = 32) {
  if (typeof value !== 'string' || encoder.encode(value).length < minimum || value.length > 4096)
    unavailable('auth_configuration_missing');
  return value;
}
function configuration(env) {
  if (!env.DB?.prepare || !env.DB?.batch) unavailable('auth_database_unavailable');
  const jwtSecret = secret(env.AUTH_JWT_SECRET);
  const hashSecret = secret(env.AUTH_TOKEN_HASH_SECRET);
  if (jwtSecret === hashSecret) unavailable('auth_configuration_invalid');
  const issuer = env.AUTH_ISSUER;
  if (typeof issuer !== 'string' || issuer.length > 256 || !issuer.trim() || /[\s\u0000-\u001f]/.test(issuer))
    unavailable('auth_configuration_missing');
  const audience = env.AUTH_AUDIENCE ?? 'authenticated';
  if (typeof audience !== 'string' || !/^[A-Za-z0-9._:-]{1,128}$/.test(audience))
    unavailable('auth_configuration_invalid');
  return Object.freeze({jwtSecret, hashSecret, issuer, audience,
    refreshSeconds: boundedInteger(env.AUTH_REFRESH_TTL_SECONDS, 2592000, 3600, 2592000),
    memberRegistration: flag(env.AUTH_MEMBER_REGISTRATION_ENABLED, false),
    turnstileRequired: flag(env.TURNSTILE_REQUIRED, true),
    identityLimit: boundedInteger(env.AUTH_OTP_IDENTITY_PER_HOUR, 5, 1, 100),
    ipLimit: boundedInteger(env.AUTH_OTP_IP_PER_HOUR, 30, 1, 1000),
    globalLimit: boundedInteger(env.AUTH_OTP_GLOBAL_PER_DAY, 1000, 1, 100000),
    cooldown: boundedInteger(env.AUTH_OTP_COOLDOWN_SECONDS, 60, 60, 3600)});
}
function primary(env) {
  // D1 without Sessions also reads only the primary. A first-primary session
  // keeps sequential consistency for all subsequent queries in this operation.
  return env.DB.withSession ? env.DB.withSession('first-primary') : env.DB;
}
function identity(body) {
  const surface = body.surface ?? 'member';
  if (!['member', 'admin'].includes(surface)) throw new ApiError(400, 'invalid_request', 'Invalid sign-in surface.');
  if ((body.phone == null) === (body.email == null))
    throw new ApiError(400, 'invalid_request', 'Supply one phone number or email address.');
  if (body.phone != null) {
    if (surface === 'admin') throw new ApiError(400, 'invalid_request', 'Admin sign-in requires email.');
    if (typeof body.phone !== 'string' || !/^\+2507[2389][0-9]{7}$/.test(body.phone))
      throw new ApiError(400, 'invalid_phone', 'Enter a valid Rwanda phone number.');
    return {type: 'phone', value: body.phone, channel: 'whatsapp', surface};
  }
  if (typeof body.email !== 'string' || body.email.length > 254 ||
      !/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,63}$/.test(body.email.trim()))
    throw new ApiError(400, 'invalid_email', 'Enter a valid email address.');
  return {type: 'email', value: body.email.trim().toLowerCase(), channel: 'email', surface};
}
async function hmacKey(value, usages) {
  return crypto.subtle.importKey('raw', encoder.encode(value), {name: 'HMAC', hash: 'SHA-256'}, false, usages);
}
async function mac(value, data) {
  return hex(await crypto.subtle.sign('HMAC', await hmacKey(value, ['sign']), encoder.encode(data)));
}
async function validMac(value, data, signature) {
  if (typeof signature !== 'string' || !/^[0-9a-f]{64}$/.test(signature)) return false;
  const bytes = Uint8Array.from(signature.match(/../g), v => parseInt(v, 16));
  return crypto.subtle.verify('HMAC', await hmacKey(value, ['verify']), bytes, encoder.encode(data));
}
function randomCode() {
  // Rejection sampling avoids modulo bias. Neither OTP nor public IDs come
  // from Math.random(), client metadata, fixture identities or dev mappings.
  const values = new Uint32Array(1);
  do { crypto.getRandomValues(values); } while (values[0] >= 4294000000);
  return (values[0] % 1000000).toString().padStart(6, '0');
}
function base64url(bytes) {
  let binary = ''; for (const byte of new Uint8Array(bytes)) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}
function decode64(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]+$/.test(value)) invalid('invalid_token');
  let bytes;
  try { bytes = Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), v => v.charCodeAt(0)); }
  catch { invalid('invalid_token'); }
  if (base64url(bytes) !== value) invalid('invalid_token');
  return bytes;
}
function refreshToken() { return base64url(crypto.getRandomValues(new Uint8Array(32))); }
async function signToken(config, session) {
  const issued = unix(), expiresAt = Math.min(issued + ACCESS_SECONDS, session.expires_at);
  if (expiresAt <= issued) invalid('access_revoked');
  const header = base64url(encoder.encode(JSON.stringify({alg: 'HS256', typ: 'JWT'})));
  const payload = base64url(encoder.encode(JSON.stringify({iss: config.issuer, aud: config.audience,
    sub: session.user_id, session_id: session.id, iat: issued, exp: expiresAt,
    auth_time: session.auth_at, role: 'authenticated',
    aal: session.assurance_level === 2 ? 'aal2' : 'aal1',
    ...(session.assurance_level === 2 ? {mfa_at: session.mfa_at, mfa_factor_id: session.mfa_factor_id} : {})})));
  const signature = await crypto.subtle.sign('HMAC', await hmacKey(config.jwtSecret, ['sign']), encoder.encode(`${header}.${payload}`));
  return {token: `${header}.${payload}.${base64url(signature)}`, expiresAt};
}
async function verifyToken(token, config) {
  if (typeof token !== 'string' || token.length > 4096 || token.split('.').length !== 3) invalid('invalid_token');
  const [head, body, signed] = token.split('.');
  let header, claims;
  try {
    header = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(decode64(head)));
    claims = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(decode64(body)));
  } catch { invalid('invalid_token'); }
  if (!header || header.alg !== 'HS256' || header.typ !== 'JWT' || Object.keys(header).length !== 2)
    invalid('invalid_token');
  if (!await crypto.subtle.verify('HMAC', await hmacKey(config.jwtSecret, ['verify']), decode64(signed), encoder.encode(`${head}.${body}`)))
    invalid('invalid_token');
  const current = unix();
  if (!claims || claims.iss !== config.issuer || claims.aud !== config.audience ||
      !UUID.test(claims.sub ?? '') || !UUID.test(claims.session_id ?? '') ||
      !Number.isSafeInteger(claims.iat) || !Number.isSafeInteger(claims.exp) || !Number.isSafeInteger(claims.auth_time) ||
      claims.exp > claims.iat + ACCESS_SECONDS || claims.exp <= claims.iat || claims.exp <= current || claims.iat > current + 30 ||
      claims.auth_time < 1 || claims.auth_time > claims.iat || claims.role !== 'authenticated' || !['aal1','aal2'].includes(claims.aal) ||
      (claims.aal === 'aal2' && (!Number.isSafeInteger(claims.mfa_at) || claims.mfa_at < claims.auth_time ||
        claims.mfa_at > claims.iat || !UUID.test(claims.mfa_factor_id ?? ''))))
    invalid('invalid_token');
  return claims;
}
async function grants(db, userId, surface) {
  if (surface !== 'admin') return new Set();
  const rows = await db.prepare('SELECT permission FROM admin_grants WHERE user_id=? ORDER BY permission').bind(userId).all();
  return new Set(rows.results.map(row => row.permission));
}
function userJson(user, permissions) {
  return {id: user.id, aud: 'authenticated', role: 'authenticated', phone: user.phone ?? '', email: user.email ?? '',
    created_at: user.created_at, updated_at: user.updated_at,
    app_metadata: {provider: user.phone ? 'phone' : 'email', providers: [user.phone ? 'phone' : 'email'],
      roles: permissions.size ? ['admin'] : ['member'], permissions: [...permissions]},
    user_metadata: {full_name: user.full_name, public_id: user.public_id, country_code: user.country_code,
      currency_code: user.currency_code, momo_provider: user.momo_provider, momo_number: user.momo_number,
      momo_pay_code: user.momo_pay_code}, identities: []};
}
async function sessionJson(config, db, session, user) {
  const permissions = await grants(db, user.id, session.surface);
  if (session.surface === 'admin' && permissions.size === 0) invalid('access_revoked');
  if (session.assurance_level === 2 && !await db.prepare("SELECT id FROM auth_mfa_factors WHERE id=? AND user_id=? AND status='verified'")
    .bind(session.mfa_factor_id, user.id).first()) invalid('access_revoked');
  const jwt = await signToken(config, session);
  return {access_token: jwt.token, token_type: 'bearer', expires_in: Math.max(0, jwt.expiresAt - unix()),
    expires_at: jwt.expiresAt, user: userJson(user, permissions)};
}

/** Current primary authorization. Mutating callers must also check this session
 * and active user in their own atomic SQL operation after intervening awaits. */
export async function requireSession(request, env) {
  requireOrigin(request, env);
  const config = configuration(env);
  const authorization = request.headers.get('authorization') ?? '';
  if (!/^Bearer [A-Za-z0-9_.-]+$/i.test(authorization)) invalid('authentication_required');
  const claims = await verifyToken(authorization.slice(7), config);
  const db = primary(env);
  const row = await db.prepare(`SELECT s.id AS session_id,s.surface,s.auth_at,s.expires_at,s.revoked_at,
    s.assurance_level,s.mfa_at,s.mfa_factor_id,u.*
    FROM auth_sessions s JOIN users u ON u.id=s.user_id
    WHERE s.id=? AND s.user_id=? AND s.revoked_at IS NULL AND s.expires_at>?
      AND u.access_status='active'`).bind(claims.session_id, claims.sub, unix()).first();
  if (!row || row.auth_at !== claims.auth_time) invalid('access_revoked');
  const permissions = await grants(db, row.id, row.surface);
  if (row.surface === 'admin' && permissions.size === 0) invalid('access_revoked');
  let assuranceLevel = 1;
  if (claims.aal === 'aal2') {
    const factor = await db.prepare("SELECT id FROM auth_mfa_factors WHERE id=? AND user_id=? AND status='verified'")
      .bind(row.mfa_factor_id, row.id).first();
    if (row.assurance_level !== 2 || row.mfa_at !== claims.mfa_at || row.mfa_factor_id !== claims.mfa_factor_id || !factor)
      invalid('access_revoked');
    assuranceLevel = 2;
  }
  return {userId: row.id, sessionId: row.session_id, authAt: assuranceLevel === 2 ? row.mfa_at : row.auth_at,
    assuranceLevel, aal: assuranceLevel === 2 ? 'aal2' : 'aal1', mfaAt: assuranceLevel === 2 ? row.mfa_at : null,
    mfaFactorId: assuranceLevel === 2 ? row.mfa_factor_id : null, surface: row.surface,
    user: userJson(row, permissions), permissions};
}

async function boundedReply(response, maximum = 8192) {
  const reader = response.body?.getReader();
  if (!reader) throw new Error('missing_acknowledgement');
  let size = 0; const chunks = [];
  try {
    while (true) {
      const {done, value} = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > maximum) { await reader.cancel(); throw new Error('oversized_acknowledgement'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
}
async function turnstile(request, env, config, body) {
  if (!config.turnstileRequired) return;
  const key = secret(env.TURNSTILE_SECRET, 16);
  const hostname = env.TURNSTILE_HOSTNAME;
  const action = env.TURNSTILE_ACTION;
  if (typeof hostname !== 'string' || !/^[A-Za-z0-9.-]{1,253}$/.test(hostname) ||
      typeof action !== 'string' || !/^[A-Za-z0-9_-]{1,32}$/.test(action)) unavailable('captcha_configuration_missing');
  const value = body.captcha_token;
  if (typeof value !== 'string' || value.length < 1 || value.length > 2048)
    throw new ApiError(400, 'captcha_required', 'Complete verification before continuing.');
  let reply;
  try {
    const form = new URLSearchParams({secret: key, response: value});
    const ip = request.headers.get('CF-Connecting-IP'); if (ip) form.set('remoteip', ip);
    const response = await fetch(SITEVERIFY, {method: 'POST', body: form, redirect: 'manual', signal: AbortSignal.timeout(10000)});
    if (!response.ok) throw new Error('verification_unavailable');
    reply = await boundedReply(response);
  } catch { unavailable('captcha_unavailable'); }
  const issued = typeof reply?.challenge_ts === 'string' ? Date.parse(reply.challenge_ts) : NaN;
  if (reply?.success !== true || reply.hostname !== hostname || reply.action !== action ||
      !Number.isFinite(issued) || Date.now() - issued > 300000 || issued > Date.now() + 30000)
    throw new ApiError(400, 'captcha_failed', 'Verification failed or expired. Please try again.');
}
function deliveryConfiguration(env, channel = 'whatsapp') {
  if (channel === 'email' && ![undefined, '', 'relay', 'cloudflare'].includes(env.AUTH_EMAIL_DELIVERY))
    unavailable('otp_delivery_unavailable');
  if (channel === 'email' && (env.AUTH_EMAIL_DELIVERY === 'cloudflare' ||
      ([undefined, ''].includes(env.AUTH_EMAIL_DELIVERY) && (env.AUTH_EMAIL || env.EMAIL)))) {
    if (!transactionalEmailAvailable(env)) unavailable('otp_delivery_unavailable');
    return {email: true};
  }
  const token = secret(env.OTP_DELIVERY_TOKEN, 16);
  let url;
  try { url = new URL(env.OTP_DELIVERY_URL); } catch { unavailable('otp_delivery_unavailable'); }
  if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.hash || url.search ||
      url.hostname === 'localhost' || url.hostname.endsWith('.localhost') || /^[0-9.]+$/.test(url.hostname) || url.hostname.includes(':'))
    unavailable('otp_delivery_unavailable');
  return {url: url.toString(), token};
}
// Presentation may expose availability, never the provider URL or credential.
export function otpDeliveryAvailable(env) {
  try { deliveryConfiguration(env); return true; } catch { return false; }
}
function otpMessage(challenge, code) {
  return `collect-otp-v1:${challenge.id}:${challenge.identity_hash}:${challenge.surface}:${code}`;
}
function unknownDelivery(challengeId, cooldown) {
  return json({error: {code: 'otp_delivery_unknown', message: 'Delivery could not be confirmed. If a code arrives, verify it before requesting another.'},
    challenge_id: challengeId, request_id: challengeId, retry_after: cooldown}, 503);
}
function acknowledgement(challengeId, channel, cooldown = 60) {
  return json({challenge_id: challengeId, request_id: challengeId, accepted: true,
    channel, retry_after: cooldown, message: 'If this account can sign in, a code will be sent.'}, 202);
}
function challengeIdentityHash(challenge, aliases) {
  const candidate = aliases.find(value => value.key_id === challenge.identity_key_id);
  if (!candidate) unavailable('auth_identity_key_unavailable');
  return candidate.identity_hash;
}
async function requireIdentityKeyCoverage(db, target, aliases, timestamp, cooldown) {
  const keys = JSON.stringify(aliases.map(value => value.key_id));
  const missing = await db.prepare(`SELECT 1 AS unavailable FROM auth_otp_challenges c
    WHERE c.identity_type=? AND c.identity_value=? AND c.expires_at>?
      AND c.status IN ('dispatching','accepted','delivery_unknown')
      AND c.identity_key_id NOT IN(SELECT value FROM json_each(?))
    UNION ALL SELECT 1 FROM auth_identity_rate_aliases a
      JOIN auth_otp_challenges c ON c.id=a.request_id
    WHERE c.identity_type=? AND c.identity_value=?
      AND (a.hourly_window_ends_at>? OR a.requested_at+?>?)
      AND a.identity_key_id NOT IN(SELECT value FROM json_each(?)) LIMIT 1`)
    .bind(target.type, target.value, timestamp, keys,
      target.type, target.value, timestamp, cooldown, timestamp, keys).first();
  if (missing) unavailable('auth_identity_key_unavailable');
}
async function requestOtp(request, env, config) {
  const body = await readJson(request, MAX_BODY);
  requireFields(body, ['phone', 'email', 'surface', 'captcha_token', 'request_id', 'create_account']);
  const target = identity(body);
  if (body.create_account !== undefined && typeof body.create_account !== 'boolean')
    throw new ApiError(400, 'invalid_request', 'Choose a valid sign-in request.');
  // A privacy request must never register an unknown account. This restriction
  // is retained in the challenge and also survives an ordinary verify request.
  const allowRegistration = body.create_account !== false;
  const registrationAllowed = target.surface === 'member' && config.memberRegistration && allowRegistration;
  const delivery = deliveryConfiguration(env, target.channel);
  const db = primary(env);
  const ring = identityKeyRing(env, config.hashSecret);
  const aliases = await identityHashes(ring, target);
  const identityHash = aliases.find(value => value.key_id === ring.currentId).identity_hash;
  const id = body.request_id === undefined ? crypto.randomUUID() : uuid(body.request_id, 'request_id');
  const existing = await db.prepare('SELECT * FROM auth_otp_challenges WHERE id=?').bind(id).first();
  if (existing) {
    if (existing.identity_hash !== challengeIdentityHash(existing, aliases) || existing.surface !== target.surface ||
        (!allowRegistration && existing.registration_allowed !== 0))
      throw new ApiError(409, 'request_conflict', 'This sign-in request has different details.');
    // A retry is a readback of the same attempt. It never sends another OTP.
    return existing.status === 'delivery_unknown' ? unknownDelivery(id, config.cooldown) : acknowledgement(id, target.channel, config.cooldown);
  }
  await turnstile(request, env, config, body);
  const current = unix();
  await requireIdentityKeyCoverage(db, target, aliases, current, config.cooldown);
  const ipHash = await mac(config.hashSecret, `collect-source-v1:${request.headers.get('CF-Connecting-IP') ?? 'unknown-source'}`);
  const hour = Math.floor(current / 3600), day = Math.floor(current / 86400);
  const code = randomCode();
  const challenge = {id, identity_hash: identityHash, surface: target.surface};
  const codeHash = await mac(config.hashSecret, otpMessage(challenge, code));
  try {
    await db.batch([
      db.prepare(`INSERT INTO auth_rate_claims(request_id,identity_hash,identity_bucket,ip_bucket,global_bucket,
        requested_at,hourly_window_ends_at,daily_window_ends_at,identity_limit,ip_limit,global_limit,cooldown_seconds,
        identity_key_id,identity_aliases_json)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).bind(id, identityHash, `identity:${identityHash}:${hour}`, `source:${ipHash}:${hour}`,
          `global:${day}`, current, (hour + 1) * 3600, (day + 1) * 86400, config.identityLimit, config.ipLimit, config.globalLimit, config.cooldown,
          ring.currentId, JSON.stringify(aliases)),
      db.prepare(`UPDATE auth_otp_challenges SET status='superseded' WHERE identity_hash=? AND surface=?
        AND status IN ('dispatching','accepted','delivery_unknown')`).bind(identityHash, target.surface),
      db.prepare(`INSERT INTO auth_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,
        code_hash,created_at,expires_at,status,identity_key_id) VALUES(?,?,?,?,?,?,?,?,?,'dispatching',?)`).bind(id, identityHash, target.type,
          target.value, target.surface, registrationAllowed ? 1 : 0, codeHash, current, current + OTP_SECONDS, ring.currentId),
      auditStatement(env, null, 'auth.otp.requested', 'auth_challenge', id,
        {surface: target.surface, channel: target.channel, registration_allowed: registrationAllowed}, id),
    ]);
  } catch (error) {
    const rateLimited = String(error?.message).includes('auth_rate_limited');
    if (rateLimited || String(error?.message).includes('auth_rate_claims.request_id')) {
      // A BEFORE INSERT throttle can run before SQLite detects a duplicate
      // key. Reconcile that exact request before reporting an unrelated 429.
      const retry = await db.prepare('SELECT * FROM auth_otp_challenges WHERE id=?').bind(id).first();
      if (retry) {
        if (retry.identity_hash !== challengeIdentityHash(retry, aliases) || retry.surface !== target.surface ||
            (!allowRegistration && retry.registration_allowed !== 0))
          throw new ApiError(409, 'request_conflict', 'This sign-in request has different details.');
        return retry.status === 'delivery_unknown' ? unknownDelivery(id, config.cooldown) : acknowledgement(id, target.channel, config.cooldown);
      }
      if (rateLimited) throw new ApiError(429, 'auth_rate_limited', 'Wait before requesting another code.');
    }
    throw error;
  }
  const user = await db.prepare(`SELECT id,access_status FROM users WHERE ${target.type}=?`).bind(target.value).first();
  const permitted = user?.access_status === 'active' &&
    (target.surface !== 'admin' || (await grants(db, user.id, 'admin')).size > 0);
  if (!permitted && !(registrationAllowed && !user)) {
    // Same public response for unknown, disabled and unenrolled Admin accounts.
    await db.prepare("UPDATE auth_otp_challenges SET status='superseded' WHERE id=? AND status='dispatching'").bind(id).run();
    return acknowledgement(id, target.channel, config.cooldown);
  }
  try {
    if (delivery.email) {
      const result = await sendTransactionalEmail(env, {to: target.value,
        subject: 'Your Collect sign-in code',
        text: `Your Collect sign-in code is ${code}. It expires in 5 minutes. Do not share this code. If you did not request it, you can ignore this email.`});
      if (typeof result?.messageId !== 'string' || !result.messageId) throw new Error('delivery_not_acknowledged');
    } else {
    const response = await fetch(delivery.url, {method: 'POST', headers: {'Content-Type': 'application/json',
      Authorization: `Bearer ${delivery.token}`}, body: JSON.stringify({request_id: id, channel: target.channel,
      recipient: target.value, code, expires_at: current + OTP_SECONDS, purpose: 'collect_sign_in'}),
      redirect: 'manual', signal: AbortSignal.timeout(10000)});
    if (!response.ok) throw new Error('delivery_not_acknowledged');
    const reply = await boundedReply(response);
    if (reply?.accepted !== true || reply.request_id !== id) throw new Error('delivery_not_acknowledged');
    }
    await db.prepare("UPDATE auth_otp_challenges SET status='accepted' WHERE id=? AND status='dispatching'").bind(id).run();
    return acknowledgement(id, target.channel, config.cooldown);
  } catch {
    // A lost acknowledgement does not prove the provider stopped. The original
    // challenge can still verify an actually received code; it is never resent.
    await db.prepare("UPDATE auth_otp_challenges SET status='delivery_unknown' WHERE id=? AND status='dispatching'").bind(id).run();
    return unknownDelivery(id, config.cooldown);
  }
}

async function verifyOtp(request, env, config) {
  const body = await readJson(request, MAX_BODY);
  requireFields(body, ['phone', 'email', 'surface', 'captcha_token', 'challenge_id', 'code']);
  const target = identity(body);
  const challengeId = uuid(body.challenge_id, 'challenge_id');
  if (typeof body.code !== 'string' || !/^[0-9]{6}$/.test(body.code)) invalid();
  await turnstile(request, env, config, body);
  const db = primary(env);
  const aliases = await identityHashes(identityKeyRing(env, config.hashSecret), target);
  const observed = await db.prepare('SELECT identity_key_id FROM auth_otp_challenges WHERE id=? AND surface=?')
    .bind(challengeId, target.surface).first();
  if (!observed) invalid();
  const hash = challengeIdentityHash(observed, aliases);
  const challenge = await db.prepare(`UPDATE auth_otp_challenges SET attempts=attempts+1
    WHERE id=? AND identity_hash=? AND identity_key_id=? AND surface=? AND status IN ('accepted','delivery_unknown')
      AND consumed_at IS NULL AND expires_at>? AND attempts<5 RETURNING *`)
    .bind(challengeId, hash, observed.identity_key_id, target.surface, unix()).first();
  if (!challenge || !await validMac(config.hashSecret, otpMessage(challenge, body.code), challenge.code_hash)) invalid();
  const operation = crypto.randomUUID(), sessionId = crypto.randomUUID(), newUserId = crypto.randomUUID();
  const rawRefresh = refreshToken(), refreshHash = await digest(rawRefresh);
  let session, user;
  for (let attempt = 0; attempt < 5; attempt++) {
    const timestamp = unix(), date = now(), publicId = randomCode();
    const isPhone = target.type === 'phone';
    try {
      const results = await db.batch([
        db.prepare(`UPDATE auth_otp_challenges SET status='consumed',consumed_at=?,consumed_operation_id=?
          WHERE id=? AND code_hash=? AND status IN ('accepted','delivery_unknown')
            AND consumed_at IS NULL AND expires_at>? AND attempts<=5`).bind(timestamp, operation, challengeId, challenge.code_hash, timestamp),
        db.prepare(`INSERT INTO users(id,phone,email,public_id,created_at,updated_at)
          SELECT ?,?,?,?, ?,? FROM auth_otp_challenges c WHERE c.id=? AND c.consumed_operation_id=?
            AND c.surface='member' AND c.registration_allowed=1
            AND NOT EXISTS(SELECT 1 FROM users WHERE ${target.type}=?)
          ON CONFLICT(${target.type}) DO NOTHING`).bind(newUserId, isPhone ? target.value : null, isPhone ? null : target.value,
            publicId, date, date, challengeId, operation, target.value),
        db.prepare(`INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)
          SELECT ?,u.id,c.surface,?,?,? FROM users u JOIN auth_otp_challenges c ON c.identity_value=u.${target.type}
          WHERE c.id=? AND c.consumed_operation_id=? AND u.access_status='active'
            AND (c.surface='member' OR EXISTS(SELECT 1 FROM admin_grants g WHERE g.user_id=u.id))`).bind(sessionId,
            timestamp, timestamp, timestamp + config.refreshSeconds, challengeId, operation),
        db.prepare(`INSERT INTO auth_refresh_tokens(token_hash,session_id,created_at,expires_at)
          SELECT ?,id,created_at,expires_at FROM auth_sessions WHERE id=?`).bind(refreshHash, sessionId),
        db.prepare(`INSERT INTO auth_otp_verifications(operation_id,challenge_id,user_id,session_id,verified_at)
          SELECT ?,?,user_id,id,auth_at FROM auth_sessions WHERE id=?`).bind(operation, challengeId, sessionId),
        db.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
          SELECT user_id,id,'auth.session.created','auth_session',id,?,'{}',? FROM auth_sessions WHERE id=?`).bind(operation, date, sessionId),
        db.prepare('SELECT * FROM auth_sessions WHERE id=?').bind(sessionId),
        db.prepare('SELECT u.* FROM users u JOIN auth_sessions s ON s.user_id=u.id WHERE s.id=?').bind(sessionId),
      ]);
      session = results[6].results[0]; user = results[7].results[0]; break;
    } catch (error) {
      // Only the six-digit public ID can be retried. D1 batch rollback leaves
      // the single-use claim and every auth row untouched on this collision.
      if (!String(error?.message).includes('users.public_id') || attempt === 4) throw error;
    }
  }
  if (!session || !user) invalid('access_revoked');
  return json({...await sessionJson(config, db, session, user), refresh_token: rawRefresh});
}

async function revokeReplay(env, db, sessionId) {
  await db.batch([
    db.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,details_json,created_at)
      SELECT user_id,id,'auth.refresh.replay','auth_session',id,'{}',? FROM auth_sessions WHERE id=? AND revoked_at IS NULL`).bind(now(), sessionId),
    db.prepare(`UPDATE auth_sessions SET revoked_at=?,revocation_reason='refresh_replay'
      WHERE id=? AND revoked_at IS NULL`).bind(unix(), sessionId),
  ]);
}
async function rotate(request, env, config) {
  const body = await readJson(request, MAX_BODY); requireFields(body, ['refresh_token']);
  if (typeof body.refresh_token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(body.refresh_token)) invalid();
  const oldHash = await digest(body.refresh_token), db = primary(env);
  const old = await db.prepare('SELECT * FROM auth_refresh_tokens WHERE token_hash=?').bind(oldHash).first();
  if (!old) invalid();
  if (old.used_at !== null) { await revokeReplay(env, db, old.session_id); invalid('refresh_replay'); }
  const rawRefresh = refreshToken(), newHash = await digest(rawRefresh), timestamp = unix();
  const result = await db.batch([
    db.prepare(`UPDATE auth_refresh_tokens SET used_at=?,replaced_by_hash=? WHERE token_hash=?
      AND used_at IS NULL AND expires_at>? AND EXISTS(SELECT 1 FROM auth_sessions s JOIN users u ON u.id=s.user_id
        WHERE s.id=auth_refresh_tokens.session_id AND s.revoked_at IS NULL AND s.expires_at>?
        AND u.access_status='active' AND (s.surface='member' OR EXISTS(SELECT 1 FROM admin_grants g WHERE g.user_id=u.id)))`)
      .bind(timestamp, newHash, oldHash, timestamp, timestamp),
    db.prepare(`INSERT INTO auth_refresh_tokens(token_hash,session_id,created_at,expires_at)
      SELECT ?,r.session_id,?,r.expires_at FROM auth_refresh_tokens r JOIN auth_sessions s ON s.id=r.session_id
      WHERE r.token_hash=? AND r.replaced_by_hash=? AND r.used_at=? AND s.revoked_at IS NULL`).bind(newHash, timestamp, oldHash, newHash, timestamp),
    db.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,details_json,created_at)
      SELECT s.user_id,s.id,'auth.refresh.rotated','auth_session',s.id,'{}',? FROM auth_sessions s
      JOIN auth_refresh_tokens r ON r.session_id=s.id WHERE r.token_hash=?`).bind(now(), newHash),
    db.prepare(`SELECT s.* FROM auth_sessions s JOIN auth_refresh_tokens r ON r.session_id=s.id
      WHERE r.token_hash=? AND s.revoked_at IS NULL AND s.expires_at>?`).bind(newHash, unix()),
    db.prepare(`SELECT u.* FROM users u JOIN auth_sessions s ON s.user_id=u.id
      JOIN auth_refresh_tokens r ON r.session_id=s.id WHERE r.token_hash=?`).bind(newHash),
  ]);
  const session = result[3].results[0], user = result[4].results[0];
  if (!session || !user) {
    const latest = await db.prepare('SELECT used_at,session_id FROM auth_refresh_tokens WHERE token_hash=?').bind(oldHash).first();
    if (latest?.used_at !== null && latest?.used_at !== undefined) await revokeReplay(env, db, latest.session_id);
    invalid();
  }
  return json({...await sessionJson(config, db, session, user), refresh_token: rawRefresh});
}
async function logout(request, env) {
  const actor = await requireSession(request, env), db = primary(env);
  await db.batch([
    db.prepare(`UPDATE auth_sessions SET revoked_at=?,revocation_reason='logout'
      WHERE id=? AND user_id=? AND revoked_at IS NULL`).bind(unix(), actor.sessionId, actor.userId),
    auditStatement(env, actor, 'auth.session.logout', 'auth_session', actor.sessionId, {}),
  ]);
  return json({ok: true});
}

function requireOrigin(request, env) {
  if (request.headers.has('cookie'))
    throw new ApiError(400, 'cookie_auth_unavailable', 'Use the current sign-in session.');
  if (request.headers.get('sec-fetch-site') === 'cross-site' && !request.headers.get('origin'))
    throw new ApiError(403, 'origin_denied', 'This request origin is not allowed.');
  const origin = request.headers.get('origin');
  if (!origin) return; // Native clients have no ambient browser credential.
  let allowed;
  try {
    allowed = (env.ALLOWED_ORIGINS ?? '').split(',').filter(Boolean).map(value => {
      const url = new URL(value);
      if (url.protocol !== 'https:' || url.origin !== value || url.username || url.password) throw new Error();
      return url.origin;
    });
  } catch { unavailable('auth_configuration_invalid'); }
  if (!allowed.includes(origin)) throw new ApiError(403, 'origin_denied', 'This request origin is not allowed.');
}
function requireAdmin(actor, {fresh = false, mfa = false} = {}) {
  if (actor.surface !== 'admin' || actor.permissions.size === 0)
    throw new ApiError(403, 'admin_required', 'Admin sign-in is required.');
  if (fresh && unix() - actor.authAt > 300)
    throw new ApiError(403, 'fresh_auth_required', 'Verify your sign-in before continuing.');
  if (mfa && actor.assuranceLevel !== 2)
    throw new ApiError(403, 'mfa_required', 'Verify your authenticator before continuing.');
}
function factorJson(row, sessionId = null) {
  return {id: row.id, factor_type: 'totp', status: row.status === 'pending' ? 'unverified' : row.status,
    friendly_name: row.friendly_name, created_at: new Date(row.created_at * 1000).toISOString(),
    updated_at: new Date((row.verified_at ?? row.created_at) * 1000).toISOString(),
    ...(row.status === 'pending' ? {enrollment_expires_at: new Date((row.created_at + 600) * 1000).toISOString(),
      enrollment_expired: row.created_at + 600 <= unix(), enrollment_current_session: row.enrollment_session_id === sessionId} : {})};
}
async function userEndpoint(request, env) {
  const actor = await requireSession(request, env), db = primary(env);
  const result = {...actor.user};
  result.factors = (await db.prepare("SELECT * FROM auth_mfa_factors WHERE user_id=? AND status IN ('pending','verified') ORDER BY created_at,id")
    .bind(actor.userId).all()).results.map(row => factorJson(row, actor.sessionId));
  return json(result);
}
function base32(bytes) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; let result = '', bits = 0, value = 0;
  for (const byte of bytes) {
    value = (value << 8) | byte; bits += 8;
    while (bits >= 5) { bits -= 5; result += alphabet[(value >>> bits) & 31]; }
  }
  if (bits > 0) result += alphabet[(value << (5 - bits)) & 31];
  return result;
}
async function totpCode(bytes, counter) {
  const message = new Uint8Array(8), view = new DataView(message.buffer);
  view.setBigUint64(0, BigInt(counter));
  const key = await crypto.subtle.importKey('raw', bytes, {name: 'HMAC', hash: 'SHA-1'}, false, ['sign']);
  const value = new Uint8Array(await crypto.subtle.sign('HMAC', key, message));
  const offset = value[19] & 15;
  const binary = ((value[offset] & 127) << 24) | (value[offset+1] << 16) | (value[offset+2] << 8) | value[offset+3];
  return (binary % 1000000).toString().padStart(6, '0');
}
async function matchedTotp(bytes, code) {
  const current = Math.floor(unix() / 30); let match = null;
  // All permitted windows are evaluated; the client cannot select a counter.
  for (const counter of [current - 1, current, current + 1]) {
    const expected = await totpCode(bytes, counter);
    let mismatch = 0;
    for (let i = 0; i < 6; i++) mismatch |= expected.charCodeAt(i) ^ code.charCodeAt(i);
    if (!mismatch) match = counter;
  }
  return match;
}
async function enrollMfa(request, env) {
  const actor = await requireSession(request, env); requireAdmin(actor, {fresh: true});
  if (!actor.permissions.has('auth.mfa.enroll')) throw new ApiError(403, 'permission_denied', 'Owner-approved authenticator setup is required.');
  const body = await readJson(request, MAX_BODY); requireFields(body, ['friendly_name', 'factor_type']);
  if (body.factor_type !== undefined && body.factor_type !== 'totp') throw new ApiError(400, 'invalid_request', 'Use an authenticator.');
  const name = body.friendly_name ?? 'Authenticator';
  if (typeof name !== 'string' || name.length < 1 || name.length > 64 || /[\u0000-\u001f]/.test(name))
    throw new ApiError(400, 'invalid_request', 'Enter a valid authenticator name.');
  const db = primary(env), id = crypto.randomUUID(), timestamp = unix();
  const existing = await db.prepare("SELECT id FROM auth_mfa_factors WHERE user_id=? AND status='verified'").bind(actor.userId).first();
  if (existing) requireAdmin(actor, {mfa: true});
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  const ciphertext = await encrypt(env, bytes, `collect-mfa-factor:${actor.userId}:${id}`);
  try {
    await db.batch([
      db.prepare(`INSERT INTO auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id)
        SELECT ?,?,?,?,'pending',?,s.id FROM auth_sessions s JOIN users u ON u.id=s.user_id
        WHERE s.id=? AND s.user_id=? AND s.surface='admin' AND s.revoked_at IS NULL AND s.expires_at>?
          AND u.access_status='active' AND EXISTS(SELECT 1 FROM admin_grants WHERE user_id=u.id AND permission='auth.mfa.enroll')
          AND ((NOT EXISTS(SELECT 1 FROM auth_mfa_factors WHERE user_id=u.id AND status='verified') AND s.auth_at>=?-300)
            OR (s.assurance_level=2 AND s.mfa_at=? AND s.mfa_at>=?-300 AND EXISTS(SELECT 1 FROM auth_mfa_factors f
              WHERE f.id=s.mfa_factor_id AND f.user_id=u.id AND f.status='verified')))`)
        .bind(id, actor.userId, name, ciphertext, timestamp, actor.sessionId, actor.userId, timestamp, timestamp,
          actor.assuranceLevel === 2 ? actor.mfaAt : null, timestamp),
      db.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,details_json,created_at)
        SELECT user_id,enrollment_session_id,'auth.mfa.enrollment.created','auth_factor',id,'{}',? FROM auth_mfa_factors WHERE id=?`)
        .bind(now(), id),
    ]);
  } catch (error) {
    if (String(error?.message).includes('auth_mfa_factors.user_id')) throw new ApiError(409, 'enrollment_pending', 'Complete the pending authenticator setup.');
    throw error;
  }
  if (!await db.prepare('SELECT id FROM auth_mfa_factors WHERE id=?').bind(id).first()) invalid('access_revoked');
  const value = base32(bytes), label = encodeURIComponent(`Collect:${actor.user.email || actor.user.phone}`);
  return json({id, factor_type: 'totp', status: 'unverified', friendly_name: name,
    totp: {secret: value, uri: `otpauth://totp/${label}?secret=${value}&issuer=Collect&algorithm=SHA1&digits=6&period=30`}});
}
async function challengeMfa(request, env) {
  const actor = await requireSession(request, env); requireAdmin(actor);
  const body = await readJson(request, MAX_BODY); requireFields(body, ['factor_id']);
  const factorId = uuid(body.factor_id, 'factor_id'), db = primary(env), id = crypto.randomUUID(), timestamp = unix();
  const window = Math.floor(timestamp / 300) * 300;
  let result;
  try {
    result = await db.batch([
      db.prepare(`INSERT INTO auth_mfa_budgets(user_id,window_start,kind,used) VALUES(?,?,'challenge',1)
        ON CONFLICT(user_id,window_start,kind) DO UPDATE SET used=used+1`).bind(actor.userId, window),
      db.prepare(`INSERT INTO auth_mfa_challenges(id,user_id,session_id,factor_id,created_at,expires_at)
        SELECT ?,s.user_id,s.id,f.id,?,? FROM auth_sessions s JOIN auth_mfa_factors f ON f.user_id=s.user_id
        JOIN users u ON u.id=s.user_id WHERE s.id=? AND s.user_id=? AND s.surface='admin'
          AND s.revoked_at IS NULL AND s.expires_at>? AND u.access_status='active' AND f.id=?
          AND (f.status='verified' OR (f.status='pending' AND f.enrollment_session_id=s.id AND f.created_at>=?-600))
          AND EXISTS(SELECT 1 FROM admin_grants WHERE user_id=u.id)`)
        .bind(id, timestamp, timestamp + MFA_SECONDS, actor.sessionId, actor.userId, timestamp, factorId, timestamp),
      db.prepare('SELECT id,expires_at FROM auth_mfa_challenges WHERE id=?').bind(id),
    ]);
  } catch (error) {
    if (String(error?.message).includes('used<=10')) throw new ApiError(429, 'mfa_rate_limited', 'Wait before verifying your authenticator again.');
    throw error;
  }
  const row = result[2].results[0]; if (!row) invalid('mfa_challenge_unavailable');
  return json({id: row.id, challenge_id: row.id, expires_at: row.expires_at});
}
async function verifyMfa(request, env, config) {
  const actor = await requireSession(request, env); requireAdmin(actor);
  const body = await readJson(request, MAX_BODY); requireFields(body, ['factor_id','challenge_id','code']);
  const factorId = uuid(body.factor_id, 'factor_id'), challengeId = uuid(body.challenge_id, 'challenge_id');
  if (typeof body.code !== 'string' || !/^[0-9]{6}$/.test(body.code)) invalid('mfa_verification_failed');
  const db = primary(env), timestamp = unix(), window = Math.floor(timestamp / 300) * 300;
  let rows;
  try {
    rows = await db.batch([
      db.prepare(`INSERT INTO auth_mfa_budgets(user_id,window_start,kind,used) VALUES(?,?,'verification',1)
        ON CONFLICT(user_id,window_start,kind) DO UPDATE SET used=used+1`).bind(actor.userId, window),
      db.prepare(`UPDATE auth_mfa_challenges SET attempts=attempts+1 WHERE id=? AND factor_id=? AND user_id=? AND session_id=?
        AND consumed_at IS NULL AND expires_at>? AND attempts<5 RETURNING *`)
        .bind(challengeId, factorId, actor.userId, actor.sessionId, timestamp),
      db.prepare("SELECT * FROM auth_mfa_factors WHERE id=? AND user_id=? AND status IN ('pending','verified')")
        .bind(factorId, actor.userId),
    ]);
  } catch (error) {
    if (String(error?.message).includes('used<=10')) throw new ApiError(429, 'mfa_rate_limited', 'Wait before verifying your authenticator again.');
    throw error;
  }
  const challenge = rows[1].results[0], factor = rows[2].results[0];
  if (!challenge || !factor || (factor.status === 'pending' && (factor.enrollment_session_id !== actor.sessionId || factor.created_at < timestamp-600)))
    invalid('mfa_challenge_expired');
  const bytes = await decrypt(env, factor.secret_ciphertext, `collect-mfa-factor:${actor.userId}:${factorId}`);
  if (bytes.length !== 20) unavailable('mfa_configuration_invalid');
  const counter = await matchedTotp(bytes, body.code); if (counter === null) invalid('mfa_verification_failed');
  const operation = crypto.randomUUID(), rawRefresh = refreshToken(), hash = await digest(rawRefresh), current = unix();
  const result = await db.batch([
    db.prepare(`INSERT INTO auth_mfa_claims(operation_id,challenge_id,factor_id,user_id,session_id,totp_counter,verified_at)
      SELECT ?,c.id,f.id,s.user_id,s.id,?,? FROM auth_mfa_challenges c JOIN auth_mfa_factors f ON f.id=c.factor_id
      JOIN auth_sessions s ON s.id=c.session_id JOIN users u ON u.id=s.user_id WHERE c.id=? AND f.id=? AND s.id=?
        AND c.user_id=? AND c.consumed_at IS NULL AND c.expires_at>? AND c.attempts<=5 AND s.revoked_at IS NULL
        AND s.expires_at>? AND s.surface='admin' AND u.access_status='active' AND (f.last_totp_counter IS NULL OR f.last_totp_counter<?)
        AND EXISTS(SELECT 1 FROM admin_grants WHERE user_id=u.id)
        AND (f.status='verified' OR (f.status='pending' AND f.enrollment_session_id=s.id AND f.created_at>=?-600))`)
      .bind(operation, counter, current, challengeId, factorId, actor.sessionId, actor.userId, current, current, counter, current),
    db.prepare(`UPDATE auth_mfa_challenges SET consumed_at=?,consumed_operation_id=? WHERE id=?
      AND EXISTS(SELECT 1 FROM auth_mfa_claims WHERE operation_id=?)`).bind(current, operation, challengeId, operation),
    db.prepare(`UPDATE auth_mfa_factors SET status='verified',verified_at=COALESCE(verified_at,?),last_totp_counter=?
      WHERE id=? AND EXISTS(SELECT 1 FROM auth_mfa_claims WHERE operation_id=?)`).bind(current, counter, factorId, operation),
    db.prepare(`UPDATE auth_sessions SET assurance_level=2,mfa_at=?,mfa_factor_id=? WHERE id=?
      AND EXISTS(SELECT 1 FROM auth_mfa_claims WHERE operation_id=?)`).bind(current, factorId, actor.sessionId, operation),
    db.prepare(`UPDATE auth_refresh_tokens SET used_at=?,replaced_by_hash=? WHERE session_id=? AND used_at IS NULL
      AND EXISTS(SELECT 1 FROM auth_mfa_claims WHERE operation_id=?)`).bind(current, hash, actor.sessionId, operation),
    db.prepare(`INSERT INTO auth_refresh_tokens(token_hash,session_id,created_at,expires_at)
      SELECT ?,s.id,?,s.expires_at FROM auth_sessions s JOIN auth_mfa_claims c ON c.session_id=s.id
      WHERE c.operation_id=?`).bind(hash, current, operation),
    db.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
      SELECT user_id,session_id,'auth.mfa.verified','auth_factor',factor_id,operation_id,'{}',? FROM auth_mfa_claims
      WHERE operation_id=?`).bind(now(), operation),
    db.prepare(`SELECT s.* FROM auth_sessions s JOIN auth_mfa_claims c ON c.session_id=s.id WHERE c.operation_id=?`).bind(operation),
    db.prepare(`SELECT u.* FROM users u JOIN auth_mfa_claims c ON c.user_id=u.id WHERE c.operation_id=?`).bind(operation),
  ]);
  const session = result[7].results[0], user = result[8].results[0];
  if (!session || !user) invalid('mfa_verification_rejected');
  return json({...await sessionJson(config, db, session, user), refresh_token: rawRefresh});
}
async function cancelEnrollment(request, env) {
  const actor = await requireSession(request, env); requireAdmin(actor, {fresh: true});
  if (!actor.permissions.has('auth.mfa.enroll')) throw new ApiError(403, 'permission_denied', 'Owner-approved authenticator setup is required.');
  const body = await readJson(request, MAX_BODY); requireFields(body, ['factor_id']);
  const factorId = uuid(body.factor_id, 'factor_id'), db = primary(env), timestamp = unix(), operation = crypto.randomUUID();
  // Only an owned pending factor can be cancelled. A new genuine sign-in may
  // recover a lost/expired enrollment, without replacing a verified factor.
  // All cookie/account/session guards are included by the caller's D1 adapter.
  const result = await db.batch([
    db.prepare(`INSERT INTO auth_mfa_revocations(operation_id,factor_id,user_id,session_id,revoked_at)
      SELECT ?,f.id,u.id,s.id,? FROM auth_mfa_factors f JOIN users u ON u.id=f.user_id
      JOIN auth_sessions original ON original.id=f.enrollment_session_id AND original.user_id=f.user_id AND original.surface='admin'
      JOIN auth_sessions s ON s.user_id=u.id WHERE f.id=? AND f.status='pending' AND u.id=? AND s.id=?
      AND s.surface='admin' AND s.revoked_at IS NULL AND s.expires_at>? AND s.auth_at>=?-300 AND s.auth_at<=?
      AND u.access_status='active' AND EXISTS(SELECT 1 FROM admin_grants WHERE user_id=u.id AND permission='auth.mfa.enroll')`)
      .bind(operation,timestamp,factorId,actor.userId,actor.sessionId,timestamp,timestamp,timestamp),
    db.prepare(`UPDATE auth_mfa_factors SET status='revoked',revoked_at=? WHERE id=? AND status='pending'
      AND EXISTS(SELECT 1 FROM auth_mfa_revocations WHERE operation_id=?)`).bind(timestamp,factorId,operation),
    db.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
      SELECT c.user_id,c.session_id,'auth.mfa.enrollment.cancelled','auth_factor',c.factor_id,c.operation_id,
      json_object('enrollment_session_id',f.enrollment_session_id,'recovery_session_id',c.session_id),?
      FROM auth_mfa_revocations c JOIN auth_mfa_factors f ON f.id=c.factor_id WHERE c.operation_id=?`).bind(now(),operation),
    db.prepare('SELECT operation_id FROM auth_mfa_revocations WHERE operation_id=?').bind(operation),
  ]);
  if (!result[3].results[0]) throw new ApiError(409, 'pending_enrollment_unavailable', 'Recheck the pending authenticator setup.');
  return json({id:factorId, factor_type:'totp', status:'revoked'});
}
async function unenrollMfa(request, env) {
  const actor = await requireSession(request, env); requireAdmin(actor, {fresh: true});
  if (!actor.permissions.has('auth.mfa.enroll')) throw new ApiError(403, 'permission_denied', 'Owner-approved authenticator setup is required.');
  const body = await readJson(request, MAX_BODY); requireFields(body, ['factor_id']);
  const factorId = uuid(body.factor_id, 'factor_id'), db = primary(env), timestamp = unix();
  const factor = await db.prepare('SELECT * FROM auth_mfa_factors WHERE id=? AND user_id=?').bind(factorId, actor.userId).first();
  if (!factor || factor.status === 'revoked') invalid('mfa_factor_unavailable');
  if (factor.status === 'verified') {
    requireAdmin(actor, {mfa: true});
    if (!await db.prepare("SELECT id FROM auth_mfa_factors WHERE user_id=? AND status='verified' AND id!=?")
      .bind(actor.userId, factorId).first()) throw new ApiError(409, 'last_authenticator_required', 'Keep a verified authenticator. Contact the owner for account recovery.');
  }
  const operation = crypto.randomUUID();
  const result = await db.batch([
    db.prepare(`INSERT INTO auth_mfa_revocations(operation_id,factor_id,user_id,session_id,revoked_at)
      SELECT ?,f.id,u.id,s.id,? FROM auth_mfa_factors f JOIN users u ON u.id=f.user_id JOIN auth_sessions s ON s.user_id=u.id
      WHERE f.id=? AND u.id=? AND s.id=? AND s.revoked_at IS NULL AND s.expires_at>? AND u.access_status='active'
        AND s.surface='admin' AND EXISTS(SELECT 1 FROM admin_grants WHERE user_id=u.id AND permission='auth.mfa.enroll')
        AND ((f.status='pending' AND s.auth_at>=?-300) OR (f.status='verified' AND s.assurance_level=2 AND s.mfa_at=? AND s.mfa_at>=?-300
          AND EXISTS(SELECT 1 FROM auth_mfa_factors other WHERE other.user_id=u.id AND other.status='verified' AND other.id!=f.id)))`)
      .bind(operation, timestamp, factorId, actor.userId, actor.sessionId, timestamp, timestamp, actor.assuranceLevel === 2 ? actor.mfaAt : null, timestamp),
    db.prepare(`UPDATE auth_mfa_factors SET status='revoked',revoked_at=? WHERE id=?
      AND EXISTS(SELECT 1 FROM auth_mfa_revocations WHERE operation_id=?)`).bind(timestamp, factorId, operation),
    db.prepare(`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
      SELECT user_id,session_id,'auth.mfa.revoked','auth_factor',factor_id,operation_id,'{}',? FROM auth_mfa_revocations WHERE operation_id=?`)
      .bind(now(), operation),
    db.prepare(`UPDATE auth_sessions SET revoked_at=?,revocation_reason='mfa_factor_revoked'
      WHERE mfa_factor_id=? AND revoked_at IS NULL AND EXISTS(SELECT 1 FROM auth_mfa_revocations WHERE operation_id=?)`)
      .bind(timestamp, factorId, operation),
    db.prepare('SELECT operation_id FROM auth_mfa_revocations WHERE operation_id=?').bind(operation),
  ]);
  if (!result[4].results[0]) invalid('access_revoked');
  return json({id: factorId, status: 'revoked'});
}

export async function handleAuth(request, env) {
  const path = new URL(request.url).pathname;
  const routes = ['/v1/auth/otp','/v1/auth/verify','/v1/auth/refresh','/v1/auth/logout','/v1/auth/user',
    '/v1/auth/google/start','/v1/auth/google/callback','/v1/auth/google/exchange',
    '/v1/auth/mfa/enroll','/v1/auth/mfa/cancel-enrollment','/v1/auth/mfa/challenge','/v1/auth/mfa/verify','/v1/auth/mfa/unenroll'];
  if (!routes.includes(path)) return null;
  const method = path === '/v1/auth/user' || path === '/v1/auth/google/callback' ? 'GET' : 'POST';
  if (request.method !== method) return json({error: {code: 'method_not_allowed', message: `Use ${method}.`}}, 405, {Allow: method});
  try {
    // Google navigates back cross-site. The callback has no ambient session:
    // single-use state, nonce and two PKCE bindings authenticate this handoff.
    if (path !== '/v1/auth/google/callback') requireOrigin(request, env);
    const config = configuration(env);
    if (path.startsWith('/v1/auth/google/')) return await handleGoogleAuth(request, env, config,
      {primary, turnstile, sessionJson, randomCode, refreshToken, requireFields, mac, boundedReply});
    if (path === '/v1/auth/otp') return await requestOtp(request, env, config);
    if (path === '/v1/auth/verify') return await verifyOtp(request, env, config);
    if (path === '/v1/auth/refresh') return await rotate(request, env, config);
    if (path === '/v1/auth/logout') return await logout(request, env);
    if (path === '/v1/auth/user') return await userEndpoint(request, env);
    if (path === '/v1/auth/mfa/enroll') return await enrollMfa(request, env);
    if (path === '/v1/auth/mfa/cancel-enrollment') return await cancelEnrollment(request, env);
    if (path === '/v1/auth/mfa/challenge') return await challengeMfa(request, env);
    if (path === '/v1/auth/mfa/verify') return await verifyMfa(request, env, config);
    return await unenrollMfa(request, env);
  } catch (error) {
    if (error instanceof ApiError) return json({error: {code: error.code, message: error.message}}, error.status);
    // SQL, transport messages, codes, identities, keys and token values never
    // enter a public error response or an application log.
    return json({error: {code: 'auth_unavailable', message: 'Sign-in is unavailable. Please try again later or contact support.'}}, 503);
  }
}
