import { SafeError, UUID, object, unavailable, loadCredential } from './config.mjs';

const MAX_RESPONSE = 512 * 1024;
const API_TIMEOUT = 12_000;
const authError = () => { throw new SafeError('session_unavailable', 'The local Admin session ended or changed. Sign in again; no request was replayed.'); };
// Canonical grants include three-part names such as auth.mfa.enroll. This
// validates bounded response syntax only; authority still requires exact grants.
export const capabilityName = value => typeof value === 'string' && value.length <= 128 &&
  !/[^a-z_.]/.test(value) && /^[a-z_]+(?:\.[a-z_]+){1,2}$/.test(value);

/** Shared bounded HTTPS transport. There is no generic MCP fetch tool. */
export async function requestJson(config, path, { cookie, method = 'GET', body, signal, csrfToken } = {}) {
  if (!path.startsWith('/api/admin/') || path.split(/[/?]/).includes('..') || path.includes('#') || path.includes('\\') ||
      !['GET', 'POST'].includes(method) || method === 'GET' && body !== undefined) unavailable();
  if (csrfToken !== undefined && (method !== 'POST' || !cookie || typeof csrfToken !== 'string' || !/^[a-f0-9]{64}$/.test(csrfToken))) unavailable();
  const url = new URL(path, config.origin);
  if (url.origin !== config.origin || url.protocol !== 'https:' || url.username || url.password) unavailable();
  const timeout = AbortSignal.timeout(API_TIMEOUT);
  let response;
  try {
    response = await fetch(url, {
      method, redirect: 'error', signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
      headers: { Accept: 'application/json', Origin: config.origin,
        ...(cookie ? { Cookie: cookie } : {}), ...(body ? { 'Content-Type': 'application/json',
          'X-Collect-Admin': '1', 'X-Collect-Requested-With': 'collect-admin' } : {}),
        ...(csrfToken ? { 'X-Collect-CSRF': csrfToken } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (response.redirected || response.url && new URL(response.url).origin !== config.origin) unavailable();
    const length = response.headers.get('content-length');
    if (length && (!/^\d+$/.test(length) || Number(length) > MAX_RESPONSE)) { await response.body?.cancel(); unavailable(); }
    if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') || '')) { await response.body?.cancel(); unavailable(); }
    const reader = response.body?.getReader();
    if (!reader) unavailable();
    const buffers = []; let size = 0;
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.length;
      if (size > MAX_RESPONSE) { await reader.cancel(); unavailable(); }
      buffers.push(chunk.value);
    }
    const bytes = Buffer.concat(buffers, size);
    let value;
    try { value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); } catch { unavailable(); }
    if (!object(value)) unavailable();
    if (response.status === 401) authError();
    if (response.status === 403) throw new SafeError('permission_denied', 'Your current Admin account cannot read this information.');
    if (response.status === 404) throw new SafeError('record_unavailable', 'This record is unavailable for the current account.');
    if (response.status === 429) throw new SafeError('rate_limited', 'The Admin service rate limit was reached. Wait before making another request.');
    if (response.status < 200 || response.status >= 300) unavailable();
    return { value, headers: response.headers };
  } catch (error) {
    if (error instanceof SafeError) throw error;
    if (signal?.aborted) throw new SafeError('cancelled', 'The read was cancelled. No action was retried.');
    unavailable();
  }
}
export function parseSession(value) {
  const user = value.user;
  if (user === null) authError();
  if (!object(user) || !UUID.test(user.id) || !UUID.test(user.sessionId) || !UUID.test(user.principalId) ||
      typeof user.email !== 'string' || user.email.length > 254 || !['owner', 'admin', 'staff'].includes(user.role) ||
      user.financialModel !== 'canonical_evidence_ledger' || !Array.isArray(user.permissions) || user.permissions.length > 256 ||
      user.permissions.some(p => !capabilityName(p)) ||
      ![1, 2].includes(user.assuranceLevel) || typeof value.expiresAt !== 'string' ||
      !Number.isFinite(Date.parse(value.expiresAt)) || Date.parse(value.expiresAt) <= Date.now()) unavailable();
  return { id: user.id, email: user.email, role: user.role, sessionId: user.sessionId, principalId: user.principalId,
    permissions: [...new Set(user.permissions)].sort(), assuranceLevel: user.assuranceLevel,
    mfaAt: user.mfaAt ?? null, financialModel: user.financialModel, expiresAt: value.expiresAt };
}
function credentialOwns(credential, user) {
  if (credential.accountId !== user.id || credential.sessionId !== user.sessionId || credential.principalId !== user.principalId) authError();
}
export class AdminApi {
  constructor(config) { this.config = config; }
  async withAuthority(permission, read, signal) {
    const credential = await loadCredential(this.config);
    const before = parseSession((await requestJson(this.config, '/api/admin/auth/session', { cookie: credential.cookie, signal })).value);
    credentialOwns(credential, before);
    const required = permission == null ? [] : Array.isArray(permission) ? permission : [permission];
    if (required.some(value => !before.permissions.includes(value))) throw new SafeError('permission_denied', 'Your current Admin account cannot read this information.');
    const value = await read({ user: before,
      get: async path => (await requestJson(this.config, path, { cookie: credential.cookie, signal })).value });
    const latestCredential = await loadCredential(this.config);
    if (credential.fingerprint !== latestCredential.fingerprint) authError();
    const after = parseSession((await requestJson(this.config, '/api/admin/auth/session', { cookie: credential.cookie, signal })).value);
    credentialOwns(credential, after);
    if (JSON.stringify(before) !== JSON.stringify(after)) authError();
    return value;
  }
}
