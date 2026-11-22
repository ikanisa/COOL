import { parseSession, readAdminSession, sameAdminSession } from './api.mjs';
import { SafeError, saveCredential } from './config.mjs';

const privateSessionMessage = 'A private origin-bound session could not be verified. No local credential was saved.';
const sessionChanged = () => {
  throw new SafeError('session_changed', 'The Admin account changed during sign-in. No local credential was saved.');
};

export function normalizeLoginEmail(email) {
  if (typeof email === 'string' && email.length <= 254) {
    const normalized = email.trim().toLowerCase();
    if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) return normalized;
  }
  throw new SafeError('invalid_login', 'Enter the approved Admin account email.');
}

export function loginCookie(headers, message = privateSessionMessage) {
  const values = headers?.getSetCookie?.() ?? [];
  const matches = values.filter(value => /^__Host-collect_admin=[a-f0-9]{64};/.test(value));
  if (matches.length !== 1) throw new SafeError('invalid_login_response', message);
  const [cookie] = matches;
  if (!/(?:^|;)\s*Secure(?:;|$)/i.test(cookie) || !/(?:^|;)\s*HttpOnly(?:;|$)/i.test(cookie) ||
      !/(?:^|;)\s*SameSite=Strict(?:;|$)/i.test(cookie) || !/(?:^|;)\s*Path=\/(?:;|$)/i.test(cookie) ||
      /(?:^|;)\s*Domain=/i.test(cookie)) throw new SafeError('invalid_login_response', message);
  return cookie.split(';')[0];
}

export async function saveVerifiedLogin(config, cookie, user, expectedEmail) {
  if (normalizeLoginEmail(user.email) !== normalizeLoginEmail(expectedEmail)) sessionChanged();
  await saveCredential(config, { version: 1, origin: config.origin, cookie, accountId: user.id,
    principalId: user.principalId, sessionId: user.sessionId, expiresAt: user.expiresAt });
  return { role: user.role, expiresAt: user.expiresAt };
}

export async function verifyAndSaveLogin(config, reply, expectedEmail, cookieErrorMessage) {
  const cookie = loginCookie(reply.headers, cookieErrorMessage);
  const initial = parseSession(reply.value);
  if (normalizeLoginEmail(initial.email) !== normalizeLoginEmail(expectedEmail)) sessionChanged();
  const verified = await readAdminSession(config, cookie);
  if (!sameAdminSession(initial, verified)) sessionChanged();
  return saveVerifiedLogin(config, cookie, verified, expectedEmail);
}
