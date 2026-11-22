import { SafeError, isUuid, object, unavailable, loadCredential } from './config.mjs';
import { sendAdminJson, UnconfirmedAdminResponse } from './admin_http.mjs';

const authError = () => { throw new SafeError('session_unavailable', 'The local Admin session ended or changed. Sign in again; no request was replayed.'); };
// Canonical grants include three-part names such as auth.mfa.enroll. This
// validates bounded response syntax only; authority still requires exact grants.
export const capabilityName = value => typeof value === 'string' && value.length <= 128 &&
  !/[^a-z_.]/.test(value) && /^[a-z_]+(?:\.[a-z_]+){1,2}$/.test(value);

/** Read or submit a fixed Admin operation and expose safe errors only. */
export async function requestJson(config, path, options) {
  let reply;
  try {
    reply = await sendAdminJson(config, path, options);
  } catch (error) {
    if (error instanceof SafeError) throw error;
    if (error instanceof UnconfirmedAdminResponse && error.cancelled) {
      throw new SafeError('cancelled', 'The read was cancelled. No action was retried.');
    }
    unavailable();
  }
  const { status, value, headers } = reply;
  if (status === 401) authError();
  if (status === 403) throw new SafeError('permission_denied', 'Your current Admin account cannot read this information.');
  if (status === 404) throw new SafeError('record_unavailable', 'This record is unavailable for the current account.');
  if (status === 429) throw new SafeError('rate_limited', 'The Admin service rate limit was reached. Wait before making another request.');
  if (status < 200 || status >= 300) unavailable();
  return { value, headers };
}

export function parseSession(value) {
  const user = value.user;
  if (user === null) authError();
  if (!object(user) || !isUuid(user.id) || !isUuid(user.sessionId) || !isUuid(user.principalId) ||
      typeof user.email !== 'string' || user.email.length > 254 || !['owner', 'admin', 'staff'].includes(user.role) ||
      user.financialModel !== 'canonical_evidence_ledger' || !Array.isArray(user.permissions) || user.permissions.length > 256 ||
      user.permissions.some(p => !capabilityName(p)) ||
      ![1, 2].includes(user.assuranceLevel) || typeof value.expiresAt !== 'string' ||
      !Number.isFinite(Date.parse(value.expiresAt)) || Date.parse(value.expiresAt) <= Date.now()) unavailable();
  return { id: user.id, email: user.email, role: user.role, sessionId: user.sessionId, principalId: user.principalId,
    permissions: [...new Set(user.permissions)].sort(), assuranceLevel: user.assuranceLevel,
    mfaAt: user.mfaAt ?? null, financialModel: user.financialModel, expiresAt: value.expiresAt };
}
export async function readAdminSession(config, cookie, signal) {
  return parseSession((await requestJson(config, '/api/admin/auth/session', { cookie, signal })).value);
}

export const sameAdminSession = (before, after) => JSON.stringify(before) === JSON.stringify(after);

function credentialOwns(credential, user) {
  if (credential.accountId !== user.id || credential.sessionId !== user.sessionId || credential.principalId !== user.principalId) authError();
}
export class AdminApi {
  constructor(config) { this.config = config; }
  async withAuthority(permission, read, signal) {
    const credential = await loadCredential(this.config);
    const before = await readAdminSession(this.config, credential.cookie, signal);
    credentialOwns(credential, before);
    const required = permission == null ? [] : Array.isArray(permission) ? permission : [permission];
    if (required.some(value => !before.permissions.includes(value))) throw new SafeError('permission_denied', 'Your current Admin account cannot read this information.');
    const value = await read({ user: before,
      get: async path => (await requestJson(this.config, path, { cookie: credential.cookie, signal })).value });
    const latestCredential = await loadCredential(this.config);
    if (credential.fingerprint !== latestCredential.fingerprint) authError();
    const after = await readAdminSession(this.config, credential.cookie, signal);
    credentialOwns(credential, after);
    if (!sameAdminSession(before, after) || credential.fingerprint !== (await loadCredential(this.config)).fingerprint) authError();
    return value;
  }
}
