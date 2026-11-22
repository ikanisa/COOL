import { ADMIN_ORIGIN, configuration, object, SafeError, isUuid } from './config.mjs';
import { readAdminSession } from './api.mjs';
import { originalResponseHeaders, sendAdminJson, UnconfirmedAdminResponse } from './admin_http.mjs';
import { loginCookie, normalizeLoginEmail, saveVerifiedLogin, verifyAndSaveLogin } from './login_session.mjs';
import { isHumanChallengeToken } from './human_challenge_protocol.mjs';

const challenges = new WeakMap(), uncertainHeaders = new WeakMap();
function fixed(config) {
  if (!config || config.origin !== ADMIN_ORIGIN) throw new SafeError('invalid_configuration', 'Only the reviewed Admin origin is supported.');
  return configuration({ COLLECT_ADMIN_MCP_ORIGIN: config.origin, COLLECT_ADMIN_MCP_SESSION_FILE: config.credentialFile });
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
  if (!isHumanChallengeToken(token)) refused();
  return { captcha_token: token };
}
function unknown(headers) {
  const error = new SafeError('login_response_unknown', 'The sign-in response could not be confirmed. No request was replayed.');
  uncertainHeaders.set(error, headers);
  return error;
}
async function authPost(config, path, body) {
  if (!['/api/admin/auth/otp', '/api/admin/auth/verify'].includes(path)) {
    throw new SafeError('invalid_login', 'Unsupported sign-in operation.');
  }
  try {
    return await sendAdminJson(config, path, { method: 'POST', body });
  } catch (error) {
    if (error instanceof UnconfirmedAdminResponse) throw unknown(originalResponseHeaders(error));
    throw error;
  }
}

function responseError(reply) {
  if (reply.status === 403 && reply.value.error?.code === 'admin_access_not_approved')
    return new SafeError('admin_access_not_approved', 'This email does not have Admin access. Contact the super admin to be added.');
  if (reply.status === 429) return new SafeError('rate_limited', 'Wait before starting another sign-in. No code was resent.');
  if ([400, 401, 403].includes(reply.status)) return new SafeError('invalid_login', 'The email code was not accepted. No request was retried.');
  return unknown(reply.headers);
}
export async function requestEmailCode(config, email, options = {}) {
  config = fixed(config); email = normalizeLoginEmail(email);
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
  if (!isUuid(value.challenge_id) || !Number.isInteger(value.expires_in) ||
      value.expires_in < 1 || value.expires_in > 1800 || value.retry_after !== 60 ||
      (reply.headers.getSetCookie?.() ?? []).some(value => /^__Host-collect_admin=/.test(value))) {
    throw new SafeError('invalid_login_response', 'The code request could not be verified. No code was resent.');
  }
  const expires = started + value.expires_in * 1000;
  const challenge = Object.freeze({ challengeId: value.challenge_id, expiresAt: new Date(expires).toISOString(), retryAfter: 60, delivery: deliveryUnknown ? 'unknown' : 'accepted' });
  challenges.set(challenge, { config, email, expires, attempted: false,
    codePattern: managedEmail ? /^[0-9]{6,10}$/ : /^[0-9]{6}$/ });
  return challenge;
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
    if (headers) cookie = loginCookie(headers);
    try {
      // A Node helper has no browser cookie jar. Without a returned cookie this
      // single read cannot invent or adopt a session created by an unknown reply.
      const user = await readAdminSession(config, cookie);
      if (!cookie) throw error;
      return await saveVerifiedLogin(config, cookie, user, state.email);
    } catch { throw new SafeError('verification_unconfirmed', 'Sign-in could not be reconciled. Keep this original attempt; no code was replayed and no local credential was saved.'); }
  }
  return verifyAndSaveLogin(config, reply, state.email);
}
