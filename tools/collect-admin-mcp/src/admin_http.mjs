import { ADMIN_ORIGIN, object, unavailable } from './config.mjs';

const MAX_RESPONSE = 512 * 1024;
const API_TIMEOUT = 12_000;
const responseHeaders = new WeakMap();

export class UnconfirmedAdminResponse extends Error {
  constructor(headers, cancelled = false) {
    super('The Admin response could not be verified.');
    this.cancelled = cancelled;
    responseHeaders.set(this, headers);
  }
}

// A sign-in POST may have succeeded before its reply was lost. Only a
// narrowly qualified response may supply the cookie for one session readback.
export const originalResponseHeaders = error => responseHeaders.get(error);

function adminUrl(config, path, method, body, cookie, csrfToken) {
  if (config?.origin !== ADMIN_ORIGIN || typeof path !== 'string' || !path.startsWith('/api/admin/') ||
      path.split(/[/?]/).includes('..') || path.includes('#') || path.includes('\\') ||
      !['GET', 'POST'].includes(method) || method === 'GET' && body !== undefined) unavailable();
  if (csrfToken !== undefined && (method !== 'POST' || !cookie || typeof csrfToken !== 'string' || !/^[a-f0-9]{64}$/.test(csrfToken))) unavailable();
  const url = new URL(path, config.origin);
  if (url.origin !== config.origin || !url.pathname.startsWith('/api/admin/') || url.username || url.password) unavailable();
  return url;
}

async function readJson(response) {
  const length = response.headers.get('content-length');
  if (length && (!/^\d+$/.test(length) || Number(length) > MAX_RESPONSE) ||
      !/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') || '')) {
    await response.body?.cancel().catch(() => {});
    throw new UnconfirmedAdminResponse();
  }
  const reader = response.body?.getReader();
  if (!reader) throw new UnconfirmedAdminResponse(response.headers);
  const buffers = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > MAX_RESPONSE) {
        await reader.cancel().catch(() => {});
        throw new UnconfirmedAdminResponse();
      }
      buffers.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  let value;
  try {
    value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(buffers, size)));
  } catch {
    throw new UnconfirmedAdminResponse(response.headers);
  }
  if (!object(value)) throw new UnconfirmedAdminResponse();
  return value;
}

/** Submit one bounded, origin-pinned JSON request. Callers own status policy. */
export async function sendAdminJson(config, path, { cookie, method = 'GET', body, signal, csrfToken } = {}) {
  const url = adminUrl(config, path, method, body, cookie, csrfToken);
  const timeout = AbortSignal.timeout(API_TIMEOUT);
  let response;
  try {
    response = await fetch(url, {
      method, redirect: 'error', signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
      headers: { Accept: 'application/json', Origin: config.origin,
        ...(cookie ? { Cookie: cookie } : {}),
        ...(body ? { 'Content-Type': 'application/json',
          'X-Collect-Admin': '1', 'X-Collect-Requested-With': 'collect-admin' } : {}),
        ...(csrfToken ? { 'X-Collect-CSRF': csrfToken } : {}) },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (response.redirected || response.url && new URL(response.url).origin !== config.origin) {
      throw new UnconfirmedAdminResponse();
    }
    return { status: response.status, headers: response.headers, value: await readJson(response) };
  } catch (error) {
    if (error instanceof UnconfirmedAdminResponse) throw error;
    throw new UnconfirmedAdminResponse(response?.headers, signal?.aborted);
  }
}
