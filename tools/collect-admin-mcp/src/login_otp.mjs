import { ADMIN_ORIGIN, configuration, object, SafeError, UUID, saveCredential } from './config.mjs';
import { parseSession, requestJson } from './api.mjs';

const challenges = new WeakMap(), uncertainHeaders = new WeakMap();
const MAX_BYTES = 512 * 1024;
function fixed(config) {
  if (!config || config.origin !== ADMIN_ORIGIN) throw new SafeError('invalid_configuration', 'Only the reviewed Admin origin is supported.');
  return configuration({ COLLECT_ADMIN_MCP_ORIGIN: config.origin, COLLECT_ADMIN_MCP_SESSION_FILE: config.credentialFile });
}
function normalized(email) {
  if (typeof email !== 'string' || email.length > 254) throw new SafeError('invalid_login', 'Enter the approved Admin account email.');
  const value = email.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) throw new SafeError('invalid_login', 'Enter the approved Admin account email.');
  return value;
}
/** Private human-only auth input, never persisted in an email challenge. */
export function captchaFields(options = {}) {
  const refused = () => { throw new SafeError('invalid_challenge', 'Complete the current human verification before continuing.'); };
  if (!object(options) || Object.keys(options).some(key => key !== 'captchaToken')) refused();
  const field = Object.getOwnPropertyDescriptor(options, 'captchaToken');
  if (!field) return {};
  if (!Object.hasOwn(field, 'value')) refused();
  const token = field.value;
  if (token === undefined) return {};
  if (typeof token !== 'string' || token.length < 1 || token.length > 2048 || /[\u0000-\u0020\u007f]/.test(token)) refused();
  return { captcha_token: token };
}
function unknown(headers) {
  const error = new SafeError('login_response_unknown', 'The sign-in response could not be confirmed. No request was replayed.');
  uncertainHeaders.set(error, headers);
  return error;
}
/** Auth-only bounded transport: fixed paths and origin; no retry or generic fetch tool. */
async function authPost(config, path, body) {
  if (!['/api/admin/auth/otp', '/api/admin/auth/verify'].includes(path)) throw new SafeError('invalid_login', 'Unsupported sign-in operation.');
  let response;
  try {
    response = await fetch(new URL(path, config.origin), {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(12_000),
      headers: { Accept: 'application/json', Origin: config.origin, 'Content-Type': 'application/json',
        'X-Collect-Admin': '1', 'X-Collect-Requested-With': 'collect-admin' },
      body: JSON.stringify(body),
    });
    if (response.redirected || response.url && new URL(response.url).origin !== config.origin) throw unknown();
    const length = response.headers.get('content-length');
    if (length && (!/^\d+$/.test(length) || Number(length) > MAX_BYTES)) { await response.body?.cancel(); throw unknown(); }
    if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') || '')) { await response.body?.cancel(); throw unknown(); }
    const reader = response.body?.getReader();
    if (!reader) throw unknown(response.headers);
    const buffers = []; let size = 0;
    while (true) {
      const next = await reader.read(); if (next.done) break;
      size += next.value.length; if (size > MAX_BYTES) { await reader.cancel(); throw unknown(); }
      buffers.push(next.value);
    }
    let value;
    try { value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(buffers, size))); }
    catch { throw unknown(response.headers); }
    if (!object(value)) throw unknown();
    return { status: response.status, headers: response.headers, value };
  } catch (error) {
    if (uncertainHeaders.has(error)) throw error;
    throw unknown(response?.headers);
  }
}
function cookieFrom(headers) {
  const values = headers?.getSetCookie?.() ?? [];
  const matches = values.filter(value => /^__Host-collect_admin=[a-f0-9]{64};/.test(value));
  if (matches.length !== 1 || !/(?:^|;)\s*Secure(?:;|$)/i.test(matches[0]) ||
      !/(?:^|;)\s*HttpOnly(?:;|$)/i.test(matches[0]) || !/(?:^|;)\s*SameSite=Strict(?:;|$)/i.test(matches[0]) ||
      !/(?:^|;)\s*Path=\/(?:;|$)/i.test(matches[0]) || /(?:^|;)\s*Domain=/i.test(matches[0])) {
    throw new SafeError('invalid_login_response', 'A private origin-bound session could not be verified. No local credential was saved.');
  }
  return matches[0].split(';')[0];
}
function responseError(reply) {
  if (reply.status === 403 && reply.value.error?.code === 'admin_access_not_approved')
    return new SafeError('admin_access_not_approved', 'This email does not have Admin access. Contact the super admin to be added.');
  if (reply.status === 429) return new SafeError('rate_limited', 'Wait before starting another sign-in. No code was resent.');
  if ([400, 401, 403].includes(reply.status)) return new SafeError('invalid_login', 'The email code was not accepted. No request was retried.');
  return unknown(reply.headers);
}
export async function requestEmailCode(config, email, options = {}) {
  config = fixed(config); email = normalized(email);
  const captcha = captchaFields(options), started = Date.now();
  let reply;
  try { reply = await authPost(config, '/api/admin/auth/otp', { email, ...captcha }); }
  catch { throw new SafeError('otp_request_unconfirmed', 'The code request could not be confirmed. No new code was requested automatically. Wait before starting another sign-in.'); }
  const { value } = reply;
  const managedEmail = reply.status === 200 && value.channel === 'email' &&
    ['accepted', 'unknown'].includes(value.delivery_status);
  const accepted = managedEmail ? value.delivery_status === 'accepted'
    : reply.status === 202 && value.accepted === true && value.emailStatus === 'accepted';
  const deliveryUnknown = managedEmail ? value.delivery_status === 'unknown'
    : reply.status === 503 && value.error?.code === 'email_delivery_unknown';
  if (!accepted && !deliveryUnknown) throw responseError(reply);
  if (!UUID.test(value.challenge_id) || value.expires_in !== 300 || value.retry_after !== 60 ||
      (reply.headers.getSetCookie?.() ?? []).some(value => /^__Host-collect_admin=/.test(value))) {
    throw new SafeError('invalid_login_response', 'The code request could not be verified. No code was resent.');
  }
  const challenge = Object.freeze({ challengeId: value.challenge_id, expiresAt: new Date(started + 300_000).toISOString(), retryAfter: 60, delivery: deliveryUnknown ? 'unknown' : 'accepted' });
  challenges.set(challenge, { config, email, expires: started + 300_000, attempted: false,
    codePattern: managedEmail ? /^[0-9]{6,10}$/ : /^[0-9]{6}$/ });
  return challenge;
}
async function store(config, cookie, user, email) {
  if (normalized(user.email) !== email) throw new SafeError('session_changed', 'The Admin account changed during sign-in. No local credential was saved.');
  await saveCredential(config, { version: 1, origin: config.origin, cookie, accountId: user.id,
    principalId: user.principalId, sessionId: user.sessionId, expiresAt: user.expiresAt });
  return { role: user.role, expiresAt: user.expiresAt };
}
/** Exactly one human verification attempt. An unknown reply is looked up once, never replayed. */
export async function verifyEmailCode(config, challenge, code, options = {}) {
  config = fixed(config); const captcha = captchaFields(options), state = challenges.get(challenge);
  if (!state || state.config.origin !== config.origin || state.config.credentialFile !== config.credentialFile ||
      state.attempted || Date.now() >= state.expires || typeof code !== 'string' || !state.codePattern.test(code)) {
    throw new SafeError('invalid_login', 'Use the current unexpired email-code attempt. No code was resent or replayed.');
  }
  state.attempted = true;
  let reply;
  try {
    reply = await authPost(config, '/api/admin/auth/verify', { email: state.email, challenge_id: challenge.challengeId, code, ...captcha });
    if (reply.status !== 200) throw responseError(reply);
  } catch (error) {
    if (!uncertainHeaders.has(error)) throw error;
    const headers = uncertainHeaders.get(error); let cookie;
    if (headers) cookie = cookieFrom(headers);
    try {
      // A Node helper has no browser cookie jar. Without a returned cookie this
      // single read cannot invent or adopt a session created by an unknown reply.
      const user = parseSession((await requestJson(config, '/api/admin/auth/session', cookie ? { cookie } : {})).value);
      if (!cookie) throw error;
      return await store(config, cookie, user, state.email);
    } catch { throw new SafeError('verification_unconfirmed', 'Sign-in could not be reconciled. Keep this original attempt; no code was replayed and no local credential was saved.'); }
  }
  const cookie = cookieFrom(reply.headers), initial = parseSession(reply.value);
  if (normalized(initial.email) !== state.email) throw new SafeError('session_changed', 'The Admin account changed during sign-in. No local credential was saved.');
  const verified = parseSession((await requestJson(config, '/api/admin/auth/session', { cookie })).value);
  if (JSON.stringify(initial) !== JSON.stringify(verified)) throw new SafeError('session_changed', 'The Admin account changed during sign-in. No local credential was saved.');
  return store(config, cookie, verified, state.email);
}
