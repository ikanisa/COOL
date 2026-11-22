import { ORIGINS, OperatorError, need, sha } from './contract.mjs';

const MAX_RESPONSE_BYTES = 256 * 1024;
const JSON_MEDIA_TYPE = 'application/json';
const COOKIE = '__Host-collect_admin';

export const ADMIN_ROUTES = Object.freeze({
  session: { path: 'auth/session', method: 'GET' },
  passwordLogin: { path: 'auth/login', method: 'POST', successStatus: 200, cookie: 'login' },
  signInChallenge: { path: 'auth/otp', method: 'POST', successStatus: 200, cookie: 'none' },
  signInVerification: { path: 'auth/verify', method: 'POST', successStatus: 200, cookie: 'login' },
  emailStatus: { path: 'auth/email-verification', method: 'GET', successStatus: 200, cookie: 'none' },
  emailChallenge: { path: 'auth/email/request', method: 'POST', successStatus: 202, cookie: 'none' },
  emailVerification: { path: 'auth/email/verify', method: 'POST', successStatus: 200, cookie: 'none' },
  logout: { path: 'auth/logout', method: 'POST', cookie: 'remove' },
  notificationOperator: { path: 'notification-operator', method: 'POST' },
});

export function csrfFor(cookie) {
  return sha('collect-admin-csrf:' + cookie);
}

function isAdminCookie(line) {
  return line.startsWith(COOKIE + '=');
}

export function hasUnexpectedCookie(headers, policy) {
  return (headers.getSetCookie?.() ?? []).some(line => policy === 'none' || isAdminCookie(line));
}

export function adminCookie(headers, { deletion = false } = {}) {
  const matches = (headers.getSetCookie?.() ?? []).filter(isAdminCookie);
  need(matches.length === 1, 'auth_cookie_missing_or_ambiguous');

  const [pair, ...parts] = matches[0].split(';').map(part => part.trim());
  const token = pair.slice(COOKIE.length + 1);
  const attributes = new Map();
  for (const part of parts) {
    const delimiter = part.indexOf('=');
    const name = (delimiter === -1 ? part : part.slice(0, delimiter)).toLowerCase();
    need(!attributes.has(name), 'auth_cookie_constraints_invalid');
    attributes.set(name, delimiter === -1 ? '' : part.slice(delimiter + 1));
  }

  const maxAge = attributes.get('max-age');
  const validToken = deletion
    ? token === '' && maxAge === '0'
    : /^[a-f0-9]{64}$/.test(token) && /^[1-9][0-9]{0,5}$/.test(maxAge ?? '');
  need(validToken && attributes.has('secure') && attributes.has('httponly') &&
    attributes.get('path') === '/' && attributes.get('samesite')?.toLowerCase() === 'strict' &&
    !attributes.has('domain'), 'auth_cookie_constraints_invalid');
  return token;
}

async function readJson(response) {
  const mediaType = response.headers.get('content-type')?.split(';', 1)[0].trim().toLowerCase();
  need(mediaType === JSON_MEDIA_TYPE, 'non_json_response');

  const chunks = [];
  let bytes = 0;
  for await (const chunk of response.body ?? []) {
    bytes += chunk.byteLength;
    need(bytes <= MAX_RESPONSE_BYTES, 'response_too_large');
    chunks.push(chunk);
  }

  try {
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks, bytes)));
  } catch {
    throw new OperatorError('invalid_json_response');
  }
}

/** The fixed routes and current in-memory cookie are the only transport inputs. */
export function createAdminTransport({ origin, fetchImpl, timeoutMs }) {
  need(ORIGINS.includes(origin), 'independently_approved_frontend_origin_required');
  need(typeof fetchImpl === 'function' && Number.isSafeInteger(timeoutMs) &&
    timeoutMs >= 100 && timeoutMs <= 30000, 'invalid_transport_configuration');

  return async function send({ path, method }, body, { cookie, csrf, signal, assertCurrent }) {
    const headers = {
      Accept: JSON_MEDIA_TYPE,
      Origin: origin,
      'X-Collect-Admin': '1',
      'X-Collect-Requested-With': 'collect-admin',
      'Sec-Fetch-Site': 'same-origin',
    };
    if (body !== undefined) headers['Content-Type'] = JSON_MEDIA_TYPE;
    if (cookie) {
      headers.Cookie = COOKIE + '=' + cookie;
      if (method === 'POST') {
        need(csrf === csrfFor(cookie), 'current_csrf_required');
        headers['X-Collect-CSRF'] = csrf;
      }
    }
    need(!signal?.aborted, 'request_cancelled_before_dispatch');

    let response;
    try {
      const timeout = AbortSignal.timeout(timeoutMs);
      response = await fetchImpl(origin + '/api/admin/' + path, {
        method,
        headers,
        redirect: 'manual',
        cache: 'no-store',
        signal: signal ? AbortSignal.any([signal, timeout]) : timeout,
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
      assertCurrent();
      need(!response.redirected && (response.ok || response.status >= 400), 'redirect_refused');
      const value = await readJson(response);
      assertCurrent();
      return { value, headers: response.headers, status: response.status, ok: response.ok };
    } catch (error) {
      if (error instanceof OperatorError && method !== 'POST') throw error;
      const code = error instanceof OperatorError ? error.code : 'transport_outcome_unknown';
      throw new OperatorError(code, { unknown: method === 'POST' });
    } finally {
      if (response?.body && !response.bodyUsed) void response.body.cancel().catch(() => {});
    }
  };
}
