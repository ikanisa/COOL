import { OWNER_EMAIL, digest, normalizeEmail, passwordHash, passwordMatches, randomToken, validPassword } from './security.mjs';
import { CORE_READ_PERMISSIONS, CoreReadError, handleCoreRead } from './core.mjs';
import { buildAccountEmail } from './emails.mjs';
import { OPERATIONS_MANAGE_PERMISSIONS, OPERATIONS_CREATE_PERMISSIONS, OperationsError, handleOperations } from './operations.mjs';
import { EmailDispatchError, dispatchEmailBatch, handleEmailAdmin } from './email-dispatch.mjs';
import { GatewayError, GATEWAY_READ_PERMISSION, GATEWAY_MANAGE_PERMISSION, handleGateway } from './gateway.mjs';
import { handleReconciliation, ReconciliationError } from './reconciliation.mjs';
import { handleAdminSms, AdminSmsError } from './admin-sms.mjs';
import { recordAdminHealth, adminHealthComponent } from './observability.mjs';
import { handleReceiverIngress, ReceiverIngressError } from './receiver-ingress.mjs';

const PREFIX = '/api/admin';
const SESSION_SECONDS = 8 * 60 * 60;
const RESET_SECONDS = 30 * 60;
const INVITE_SECONDS = 24 * 60 * 60;
const now = () => Math.floor(Date.now() / 1000);
const iso = seconds => seconds == null ? null : new Date(seconds * 1000).toISOString();
const statement = (env, sql, ...args) => env.ADMIN_DB.prepare(sql).bind(...args);

class ApiError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const fail = (status, code, message) => { throw new ApiError(status, code, message); };
function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), { status, headers: {
    'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store',
    'Pragma': 'no-cache', 'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer', 'Cross-Origin-Resource-Policy': 'same-origin', ...headers,
  } });
}
function local(env, url) {
  return env.ENVIRONMENT === 'local' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
}
function validateOrigin(request, env) {
  const url = new URL(request.url);
  if (!env.ADMIN_DB || !env.ADMIN_ORIGIN) fail(503, 'service_unavailable', 'Account service is not configured.');
  const origin = new URL(env.ADMIN_ORIGIN);
  if (env.ADMIN_ORIGIN !== origin.origin) fail(503, 'service_unavailable', 'Account service is not configured.');
  if (url.origin !== origin.origin || (url.protocol !== 'https:' && !local(env, url))) fail(403, 'origin_rejected', 'Open the configured admin website to continue.');
  if (request.headers.get('Sec-Fetch-Site') === 'cross-site') fail(403, 'origin_rejected', 'This request is not allowed.');
  const supplied = request.headers.get('Origin');
  if ((request.method !== 'GET' && supplied !== origin.origin) || (supplied && supplied !== origin.origin)) fail(403, 'origin_rejected', 'This request is not allowed.');
}
function cookieName(env, request) { return local(env, new URL(request.url)) ? 'collect_admin_dev' : '__Host-collect_admin'; }
function cookie(env, request, token = '', age = 0) {
  const secure = local(env, new URL(request.url)) ? '' : '; Secure';
  return `${cookieName(env, request)}=${token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${age}${secure}`;
}
async function body(request, keys) {
  if (!request.headers.get('Content-Type')?.toLowerCase().startsWith('application/json')) fail(415, 'invalid_content_type', 'Send a JSON request.');
  if (Number(request.headers.get('Content-Length') || 0) > 4096) fail(413, 'request_too_large', 'Request is too large.');
  let raw = '';
  const reader = request.body?.getReader();
  if (!reader) fail(400, 'invalid_request', 'Request is invalid.');
  let size = 0; const decoder = new TextDecoder();
  while (true) {
    const chunk = await reader.read(); if (chunk.done) break;
    size += chunk.value.byteLength;
    if (size > 4096) { await reader.cancel(); fail(413, 'request_too_large', 'Request is too large.'); }
    raw += decoder.decode(chunk.value, { stream: true });
  }
  raw += decoder.decode();
  let parsed; try { parsed = JSON.parse(raw); } catch { fail(400, 'invalid_request', 'Request is invalid.'); }
  if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object' || Object.keys(parsed).some(key => !keys.includes(key))) fail(400, 'invalid_request', 'Request has unsupported fields.');
  return parsed;
}
function emailOrFail(value) { const email = normalizeEmail(value); if (!email) fail(400, 'invalid_email', 'Enter a valid email address.'); return email; }
function passwordOrFail(value) { if (!validPassword(value)) fail(400, 'invalid_password', 'Use a password of 12 to 128 characters.'); return value; }
async function limited(env, key, maximum, window) {
  const time = now(); const bucket = Math.floor(time / window);
  const row = await statement(env, `INSERT INTO admin_rate_limits(key_hash,bucket,count,expires_at) VALUES(?,?,1,?)
    ON CONFLICT(key_hash,bucket) DO UPDATE SET count=count+1 RETURNING count`, await digest(key), bucket, time + window * 2).first();
  return row.count > maximum;
}
async function rate(request, env, action, max = 20, window = 900) {
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  if (await limited(env, `${action}:ip:${ip}`, max, window)) fail(429, 'rate_limited', 'Too many attempts. Please try again later.');
}
async function session(request, env, required = true) {
  const name = cookieName(env, request);
  const tokens = (request.headers.get('Cookie') || '').split(';').map(x => x.trim()).filter(x => x.startsWith(`${name}=`));
  if (tokens.length !== 1 || !new RegExp(`^${name}=[a-f0-9]{64}$`).test(tokens[0])) {
    if (required) fail(401, 'unauthenticated', 'Sign in to continue.'); return null;
  }
  const tokenHash = await digest(tokens[0].slice(name.length + 1));
  const user = await statement(env, `SELECT u.*,s.public_id,s.expires_at,s.token_hash FROM admin_sessions s
    JOIN admin_users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires_at>? AND u.status='active'
    AND u.auth_version=s.auth_version`, tokenHash, now()).first();
  if (!user && required) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.');
  return user;
}
const permissionsForRole = role => [...new Set([
  'overview.read', 'account.manage', ...CORE_READ_PERMISSIONS,
  'email.read', GATEWAY_READ_PERMISSION, ...OPERATIONS_CREATE_PERMISSIONS,
  'reconciliations.read', 'reconciliations.propose', 'sms.read',
  ...(['owner', 'admin'].includes(role) ? [...OPERATIONS_MANAGE_PERMISSIONS, 'email.manage', GATEWAY_MANAGE_PERMISSION,
    'reconciliations.review', 'sms.extract', 'sms.reveal', 'admin_users.read'] : []),
  ...(role === 'owner' ? ['admin_users.manage'] : []),
])];
const publicUser = user => user ? { id: user.id, email: user.email, role: user.role,
  sessionId: user.public_id, expiresAt: iso(user.expires_at), permissions: permissionsForRole(user.role) } : null;
const teamReadSessionExists = `EXISTS(SELECT 1 FROM admin_sessions s JOIN admin_users u ON u.id=s.user_id
  WHERE s.token_hash=? AND s.public_id=? AND u.id=? AND s.auth_version=?
    AND u.auth_version=s.auth_version AND u.status='active' AND u.role=?
    AND u.role IN ('owner','admin') AND s.expires_at>unixepoch())`;
const teamReadSessionArgs = actor => [actor.token_hash, actor.public_id, actor.id, actor.auth_version, actor.role];
function owner(user) { if (user.role !== 'owner' || user.email !== OWNER_EMAIL) fail(403, 'owner_required', 'Only the main administrator can manage team access.'); }
const ownerSessionExists = `EXISTS(SELECT 1 FROM admin_sessions s JOIN admin_users u ON u.id=s.user_id
  WHERE s.token_hash=? AND s.public_id=? AND u.id=? AND s.auth_version=?
    AND u.auth_version=s.auth_version AND u.status='active' AND u.role='owner'
    AND u.email=? AND s.expires_at>unixepoch())`;
const ownerSessionArgs = actor => [actor.token_hash, actor.public_id, actor.id, actor.auth_version, OWNER_EMAIL];

async function ownerBatch(env, actor, queries) {
  const guardId = crypto.randomUUID();
  try {
    const rows = await env.ADMIN_DB.batch([
      statement(env, `INSERT INTO collect_mutation_guards(id,passed) VALUES(?,CASE WHEN ${ownerSessionExists} THEN 1 ELSE 0 END)`, guardId, ...ownerSessionArgs(actor)),
      ...queries,
      statement(env, 'DELETE FROM collect_mutation_guards WHERE id=?', guardId),
    ]);
    return rows.slice(1, -1);
  } catch (error) {
    if (String(error).includes('collect_operation_guard_failed')) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.');
    throw error;
  }
}

async function sendChallenge(env, user, kind, actor = null, auditAction = null) {
  const time = now(); const token = randomToken(); const tokenHash = await digest(token);
  const eventId = crypto.randomUUID();
  const queries = [
    statement(env, `UPDATE admin_users SET challenge_version=challenge_version+1,updated_at=?
      WHERE id=? AND status=? AND auth_version=? RETURNING challenge_version`, time, user.id, user.status, user.auth_version),
    statement(env, `INSERT INTO admin_challenges(token_hash,user_id,kind,auth_version,challenge_version,created_at,expires_at)
      SELECT ?,id,?,auth_version,challenge_version,?,? FROM admin_users WHERE id=? AND status=? AND auth_version=?`,
    tokenHash, kind, time, time + (kind === 'invite' ? INVITE_SECONDS : RESET_SECONDS), user.id, user.status, user.auth_version),
    statement(env, `INSERT INTO admin_email_events(id,user_id,kind,status,created_at,updated_at)
      SELECT ?,user_id,kind,'pending',?,? FROM admin_challenges WHERE token_hash=?`, eventId, time, time, tokenHash),
  ];
  if (actor && auditAction) queries.push(statement(env, `INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at)
    SELECT ?,?,user_id,?,? FROM admin_challenges WHERE token_hash=?`, crypto.randomUUID(), actor.id, auditAction, time, tokenHash));
  const rows = actor ? await ownerBatch(env, actor, queries) : await env.ADMIN_DB.batch(queries);
  if (!rows[0].meta.changes) fail(409, 'account_changed', 'The account changed. Refresh and try again.');
  const link = `${env.ADMIN_ORIGIN}/#/admin/setup?token=${token}&invite=${kind === 'invite'}`;
  try {
    // Never invoke the local Wrangler email simulator: it prints secret links.
    // Tests supply an in-memory EMAIL service binding and never contact a provider.
    if (env.ENVIRONMENT === 'local') fail(503, 'email_unavailable', 'Email delivery is disabled in the local preview.');
    if (!env.EMAIL?.send) fail(503, 'email_unavailable', 'Cloudflare Email Service is not configured.');
    const result = await env.EMAIL.send({
      from: { email: OWNER_EMAIL, name: 'Collect' }, to: user.email,
      ...buildAccountEmail({ kind, link }),
    });
    if (!result || typeof result.messageId !== 'string' || !result.messageId) throw new Error('Email not accepted');
    await env.ADMIN_DB.batch([
      statement(env, "UPDATE admin_challenges SET delivery_status='accepted' WHERE token_hash=?", tokenHash),
      statement(env, "UPDATE admin_email_events SET status='accepted',provider_message_id=?,updated_at=? WHERE id=?", result.messageId.slice(0, 256), now(), eventId),
    ]);
    return { emailStatus: 'accepted' };
  } catch {
    await env.ADMIN_DB.batch([
      statement(env, "UPDATE admin_challenges SET delivery_status='failed',used_at=? WHERE token_hash=?", now(), tokenHash),
      statement(env, "UPDATE admin_email_events SET status='failed',updated_at=? WHERE id=?", now(), eventId),
    ]);
    fail(503, 'email_unavailable', 'Email delivery could not be confirmed. The account remains pending; try resending the invitation.');
  }
}

async function route(request, env, ctx) {
  validateOrigin(request, env);
  const path = new URL(request.url).pathname.slice(PREFIX.length);
  if (path === '/sms' || path.startsWith('/sms/')) {
    const user = await session(request, env);
    return json(await handleAdminSms(request, env, { ...user, permissions: publicUser(user).permissions }));
  }
  if (path === '/reconciliations' || path.startsWith('/reconciliations/')) {
    const user = await session(request, env);
    return json(await handleReconciliation(request, env, { ...user, permissions: publicUser(user).permissions }));
  }
  if (path === '/gateway' || path.startsWith('/gateway/')) {
    const user = await session(request, env);
    if (path === '/gateway/receiver-grants' || path.startsWith('/gateway/receiver-grants/') || path.startsWith('/gateway/receiver-requests/')) {
      return json(await handleReceiverIngress(request, env, { ...user, permissions: publicUser(user).permissions }));
    }
    return json(await handleGateway(request, env, { ...user, permissions: publicUser(user).permissions }));
  }
  if (path === '/email' || path.startsWith('/email/')) {
    const user = await session(request, env);
    return json(await handleEmailAdmin(request, env, user));
  }
  if (path === '/operations' || path.startsWith('/operations/')) {
    const user = await session(request, env);
    return json(await handleOperations(request, env, { ...user, permissions: publicUser(user).permissions }));
  }
  if (path === '/core' || path.startsWith('/core/')) {
    const user = await session(request, env);
    return json(await handleCoreRead(request, env, { ...user, permissions: publicUser(user).permissions }));
  }
  if (request.method === 'GET' && path === '/auth/session') {
    const user = publicUser(await session(request, env, false));
    return json({ user, expiresAt: user?.expiresAt ?? null });
  }
  if (request.method === 'GET' && path === '/team') {
    const user = await session(request, env);
    if (!['owner', 'admin'].includes(user.role)) fail(403, 'permission_required', 'Only administrators can review team access.');
    const [access, result] = await env.ADMIN_DB.batch([
      statement(env, `SELECT ${teamReadSessionExists} AS allowed`, ...teamReadSessionArgs(user)),
      statement(env, `SELECT u.id,u.email,u.role,u.status,u.display_name,i.public_id AS person_public_id,u.created_at,u.invited_at,u.accepted_at,
      (SELECT e.status FROM admin_email_events e WHERE e.user_id=u.id ORDER BY e.created_at DESC,e.rowid DESC LIMIT 1) AS email_status
      FROM admin_users u JOIN collect_public_identities i ON i.admin_user_id=u.id ORDER BY CASE u.role WHEN 'owner' THEN 0 ELSE 1 END,u.created_at,u.email`),
    ]);
    if (access.results[0]?.allowed !== 1) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.');
    return json({ currentEmail: user.email, canManage: user.role === 'owner' && user.email === OWNER_EMAIL, permissionsByRole: Object.fromEntries(['owner','admin','staff'].map(role => [role, permissionsForRole(role)])), members: result.results.map(member => ({
      id: member.id, email: member.email, role: member.role, status: member.status, publicId: member.person_public_id, displayName: member.display_name,
      createdAt: iso(member.created_at), invitedAt: iso(member.invited_at), acceptedAt: iso(member.accepted_at), emailStatus: member.email_status,
    })) });
  }
  if (request.method !== 'POST') fail(405, 'method_not_allowed', 'This request method is not supported.');
  if (path === '/auth/login') {
    await rate(request, env, 'login', 30);
    const data = await body(request, ['email', 'password']); const email = emailOrFail(data.email);
    if (typeof data.password !== 'string' || data.password.length > 512) fail(401, 'invalid_credentials', 'Email or password is incorrect.');
    if (await limited(env, `login:email:${email}`, 10, 900)) fail(429, 'rate_limited', 'Too many attempts. Please try again later.');
    const user = await statement(env, 'SELECT * FROM admin_users WHERE email=?', email).first();
    const matches = await passwordMatches(data.password, user?.status === 'active' ? user.password_hash : null);
    if (!user || !matches || user.status !== 'active') fail(401, 'invalid_credentials', 'Email or password is incorrect.');
    const time = now(); const token = randomToken(); const publicId = crypto.randomUUID();
    const result = await statement(env, `INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,created_at,expires_at)
      SELECT ?,?,id,auth_version,?,? FROM admin_users WHERE id=? AND status='active' AND auth_version=? AND password_hash=?`,
    await digest(token), publicId, time, time + SESSION_SECONDS, user.id, user.auth_version, user.password_hash).run();
    if (!result.meta.changes) fail(401, 'invalid_credentials', 'Email or password is incorrect.');
    return json({ user: publicUser({ ...user, public_id: publicId, expires_at: time + SESSION_SECONDS }), expiresAt: iso(time + SESSION_SECONDS) }, 200, { 'Set-Cookie': cookie(env, request, token, SESSION_SECONDS) });
  }
  if (path === '/auth/logout') {
    await body(request, []);
    const user = await session(request, env, false);
    if (user) await statement(env, 'DELETE FROM admin_sessions WHERE token_hash=?', user.token_hash).run();
    return json({ ok: true }, 200, { 'Set-Cookie': cookie(env, request) });
  }
  if (path === '/auth/forgot-password') {
    await rate(request, env, 'forgot', 10, 3600);
    const data = await body(request, ['email']); const email = emailOrFail(data.email);
    const throttled = await limited(env, `forgot:email:${email}`, 3, 3600);
    if (!throttled) {
      // Background delivery keeps account existence, status and provider failures
      // out of the unauthenticated response. Never claim that email was delivered.
      ctx.waitUntil((async () => {
        const user = await statement(env, 'SELECT * FROM admin_users WHERE email=?', email).first();
        if (user?.status === 'active' || (user?.status === 'invited' && user.role === 'owner')) {
          try { await sendChallenge(env, user, user.status === 'invited' ? 'invite' : 'reset'); } catch { /* Metadata records failure; no secret logs. */ }
        }
      })());
    }
    return json({ ok: true, message: 'Request received. If this account is eligible, check its inbox for a password link.' }, 202);
  }
  if (path === '/auth/complete-password') {
    await rate(request, env, 'complete', 10);
    const data = await body(request, ['token', 'password', 'invite']); const password = passwordOrFail(data.password);
    if (typeof data.token !== 'string' || !/^[a-f0-9]{64}$/.test(data.token) || typeof data.invite !== 'boolean') fail(400, 'invalid_link', 'This password link is invalid or expired.');
    const tokenHash = await digest(data.token); const kind = data.invite ? 'invite' : 'reset'; const time = now();
    const challenge = await statement(env, `SELECT c.*,u.status FROM admin_challenges c JOIN admin_users u ON u.id=c.user_id
      WHERE c.token_hash=? AND c.kind=? AND c.delivery_status='accepted' AND c.used_at IS NULL AND c.expires_at>?
      AND c.auth_version=u.auth_version AND c.challenge_version=u.challenge_version AND u.status=?`,
    tokenHash, kind, time, kind === 'invite' ? 'invited' : 'active').first();
    if (!challenge) fail(400, 'invalid_link', 'This password link is invalid or expired.');
    const hashed = await passwordHash(password);
    const rows = await env.ADMIN_DB.batch([
      statement(env, `UPDATE admin_users SET password_hash=?,status='active',auth_version=auth_version+1,updated_at=?,accepted_at=COALESCE(accepted_at,?)
        WHERE id=? AND auth_version=? AND challenge_version=? AND status=? AND EXISTS
        (SELECT 1 FROM admin_challenges WHERE token_hash=? AND used_at IS NULL AND delivery_status='accepted' AND expires_at>?)`,
      hashed, now(), now(), challenge.user_id, challenge.auth_version, challenge.challenge_version, challenge.status, tokenHash, now()),
      // This audit follows the guarded UPDATE in the same atomic batch. A losing
      // request must not record success or consume any challenge/session.
      statement(env, `INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at)
        SELECT ?,?,?,?,? WHERE changes()=1`, crypto.randomUUID(), challenge.user_id, challenge.user_id,
      kind === 'invite' ? 'invitation_accepted' : 'password_reset', now()),
      statement(env, `UPDATE admin_challenges SET used_at=? WHERE user_id=? AND used_at IS NULL
        AND EXISTS(SELECT 1 FROM admin_users WHERE id=? AND password_hash=?)`, now(), challenge.user_id, challenge.user_id, hashed),
      statement(env, `DELETE FROM admin_sessions WHERE user_id=? AND EXISTS(SELECT 1 FROM admin_users WHERE id=? AND password_hash=?)`, challenge.user_id, challenge.user_id, hashed),
    ]);
    if (!rows[0].meta.changes) fail(400, 'invalid_link', 'This password link is invalid or expired.');
    return json({ ok: true }, 200, { 'Set-Cookie': cookie(env, request) });
  }
  if (path === '/auth/change-password') {
    const user = await session(request, env); await rate(request, env, 'change', 10);
    const data = await body(request, ['currentPassword', 'newPassword']); passwordOrFail(data.newPassword);
    if (typeof data.currentPassword !== 'string' || data.currentPassword.length > 512 || !await passwordMatches(data.currentPassword, user.password_hash)) fail(400, 'invalid_password', 'Your current password is incorrect.');
    const hashed = await passwordHash(data.newPassword); const time = now();
    const rows = await env.ADMIN_DB.batch([
      statement(env, `UPDATE admin_users SET password_hash=?,auth_version=auth_version+1,updated_at=? WHERE id=? AND auth_version=? AND status='active'
        AND EXISTS(SELECT 1 FROM admin_sessions WHERE token_hash=? AND expires_at>?)`, hashed, time, user.id, user.auth_version, user.token_hash, time),
      statement(env, `INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at)
        SELECT ?,?,?,'password_changed',? WHERE changes()=1`, crypto.randomUUID(), user.id, user.id, time),
      statement(env, 'UPDATE admin_challenges SET used_at=? WHERE user_id=? AND EXISTS(SELECT 1 FROM admin_users WHERE id=? AND password_hash=?)', time, user.id, user.id, hashed),
      statement(env, 'DELETE FROM admin_sessions WHERE user_id=? AND EXISTS(SELECT 1 FROM admin_users WHERE id=? AND password_hash=?)', user.id, user.id, hashed),
    ]);
    if (!rows[0].meta.changes) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.');
    return json({ ok: true }, 200, { 'Set-Cookie': cookie(env, request) });
  }
  if (path === '/team/invite') {
    const user = await session(request, env); owner(user); await rate(request, env, 'invite', 30, 3600);
    const data = await body(request, ['email', 'role', 'displayName']); const email = emailOrFail(data.email);
    const displayName = data.displayName ?? '';
    if (typeof displayName !== 'string' || displayName.trim().length > 120 || /[\u0000-\u001f\u007f]/.test(displayName) || (displayName.trim() && displayName.trim().length < 2)) fail(400, 'invalid_name', 'Enter a recorded full name.');
    if (!['admin', 'staff'].includes(data.role)) fail(400, 'invalid_role', 'Choose administrator or staff.');
    if (email === OWNER_EMAIL) fail(409, 'owner_protected', 'The main administrator already owns this account.');
    const time = now(); const id = crypto.randomUUID();
    const rows = await ownerBatch(env, user, [statement(env, `INSERT INTO admin_users(id,email,role,display_name,status,created_at,invited_at,updated_at)
      VALUES(?,?,?,?,'invited',?,?,?) ON CONFLICT(email) DO UPDATE SET role=excluded.role,display_name=excluded.display_name,status='invited',password_hash=NULL,
      auth_version=admin_users.auth_version+1,challenge_version=admin_users.challenge_version+1,accepted_at=NULL,invited_at=excluded.invited_at,updated_at=excluded.updated_at
      WHERE admin_users.status='revoked' RETURNING *`, id, email, data.role, displayName.trim(), time, time, time),
    // changes() refers to the immediately preceding invite/upsert in this batch.
    statement(env, `INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at)
      SELECT ?,?,id,'invitation_created',? FROM admin_users WHERE email=? AND changes()=1`, crypto.randomUUID(), user.id, time, email),
    ]);
    const invited = rows[0].results[0];
    if (!invited) fail(409, 'member_exists', 'This person already has access or a pending invitation.');
    const delivery = await sendChallenge(env, invited, 'invite', user);
    return json({ ok: true, ...delivery }, 201);
  }
  const teamAction = path.match(/^\/team\/([a-f0-9-]{36})\/(resend|revoke)$/);
  if (teamAction) {
    const user = await session(request, env); owner(user); await body(request, []);
    await rate(request, env, 'team-action', 30, 3600);
    const member = await statement(env, 'SELECT * FROM admin_users WHERE id=?', teamAction[1]).first();
    if (!member) fail(404, 'member_not_found', 'The team member was not found.');
    if (member.role === 'owner' || member.email === OWNER_EMAIL) fail(409, 'owner_protected', 'The main administrator cannot be changed here.');
    if (teamAction[2] === 'resend') {
      if (member.status !== 'invited') fail(409, 'not_pending', 'Only pending invitations can be resent.');
      if (await limited(env, `resend:${member.id}`, 3, 3600)) fail(429, 'rate_limited', 'Too many attempts. Please try again later.');
      const delivery = await sendChallenge(env, member, 'invite', user, 'invitation_resent');
      return json({ ok: true, ...delivery });
    }
    await ownerBatch(env, user, [
      statement(env, "UPDATE admin_users SET status='revoked',password_hash=NULL,auth_version=auth_version+1,challenge_version=challenge_version+1,updated_at=? WHERE id=? AND role!='owner'", now(), member.id),
      statement(env, 'DELETE FROM admin_sessions WHERE user_id=?', member.id),
      statement(env, 'UPDATE admin_challenges SET used_at=? WHERE user_id=? AND used_at IS NULL', now(), member.id),
      statement(env, "INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at) VALUES(?,?,?,'access_revoked',?)", crypto.randomUUID(), user.id, member.id, now()),
    ]);
    return json({ ok: true });
  }
  fail(404, 'not_found', 'This account action does not exist.');
}

export default {
  async fetch(request, env, ctx) {
    const path = new URL(request.url).pathname;
    if (path === '/api/gateway' || path.startsWith('/api/gateway/')) {
      try {
        if (new URL(request.url).origin !== env.ADMIN_ORIGIN) fail(403, 'origin_rejected', 'This gateway origin is unavailable.');
        return json(await (path === '/api/gateway/receiver-receipts' ? handleReceiverIngress(request, env) : handleGateway(request, env)));
      } catch (error) {
        if (error?.status >= 500 || error?.status === 429) recordAdminHealth(error.status === 429 ? 'rate_limited' : 'service_degraded', 'gateway');
        if (error instanceof GatewayError || error instanceof ReceiverIngressError || error instanceof ApiError) return json({ error: error.code, message: error.message }, error.status);
        recordAdminHealth('unexpected_failure', 'gateway');
        return json({ error: 'service_unavailable', message: 'Gateway service is temporarily unavailable.' }, 503);
      }
    }
    if (!path.startsWith(`${PREFIX}/`)) return env.ASSETS ? env.ASSETS.fetch(request) : json({ error: { code: 'not_found', message: 'Page not found.' } }, 404);
    try { return await route(request, env, ctx); }
    catch (error) {
      const component = adminHealthComponent(path);
      if (error?.status >= 500 || error?.status === 429) recordAdminHealth(error.status === 429 ? 'rate_limited' : 'service_degraded', component);
      if (error instanceof OperationsError || error instanceof EmailDispatchError || error instanceof GatewayError || error instanceof ReceiverIngressError || error instanceof ReconciliationError || error instanceof AdminSmsError) return json({ error: error.code, message: error.message }, error.status);
      if (error instanceof ApiError || error instanceof CoreReadError) return json({ error: { code: error.code, message: error.message } }, error.status, error.status === 429 ? { 'Retry-After': '900' } : {});
      recordAdminHealth('unexpected_failure', component);
      return json({ error: { code: 'service_unavailable', message: 'Account service is temporarily unavailable. Please try again.' } }, 503);
    }
  },
  async scheduled(_event, env) {
    let dispatchFailed = false;
    if (env.ENVIRONMENT !== 'local' && env.EMAIL?.send) {
      try { await dispatchEmailBatch(env); }
      catch { dispatchFailed = true; recordAdminHealth('email_dispatch_failed', 'email'); }
    }
    const time = now();
    try { await env.ADMIN_DB.batch([
      statement(env, 'DELETE FROM admin_sessions WHERE expires_at<?', time),
      statement(env, 'DELETE FROM admin_rate_limits WHERE expires_at<?', time),
      statement(env, 'DELETE FROM admin_challenges WHERE expires_at<?', time - 7 * 86400),
    ]); } catch {
      recordAdminHealth('cron_cleanup_failed', 'cron');
      throw new Error('Admin scheduled cleanup unavailable');
    }
    if (dispatchFailed) throw new Error('Admin scheduled email dispatch unavailable');
  },
};
