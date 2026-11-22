/* eslint-disable no-control-regex -- Reject ASCII control characters in untrusted input. */
import {AdminRequestError, isAdminPublishableKey, isVerificationUuid, type AdminClientConfig, type AdminRequestOptions, type AuthoritySnapshot, type JsonObject} from './contracts';

const KEY = /^[A-Za-z0-9._:-]{8,200}$/;
const CAPTCHA_PATHS = new Set(['auth/otp', 'auth/login', 'auth/forgot-password', 'auth/email/request']);
const SESSION_AUTH_PATHS = new Set(['auth/session', 'auth/email-verification', 'auth/otp', 'auth/verify', 'auth/login', 'auth/logout', 'auth/forgot-password', 'auth/complete-password', 'auth/google/start', 'auth/google/exchange', 'auth/mfa/recover']);

function validMfaRecovery(body: JsonObject | undefined): boolean {
  return !!body && typeof body === 'object' && !Array.isArray(body) &&
    Object.keys(body).sort().join(',') === 'challenge_id,factor_id,verification_id' &&
    isVerificationUuid(body.factor_id) && isVerificationUuid(body.challenge_id) &&
    typeof body.verification_id === 'string' && /^[a-f0-9]{64}$/.test(body.verification_id);
}

function checkedPath(path: string): string {
  if (typeof path !== 'string' || path.length === 0 || path.length > 8192 || /[\x00-\x20\\#]/.test(path)) {
    throw new TypeError('Invalid Admin request path.');
  }
  const question = path.indexOf('?');
  const pathname = question < 0 ? path : path.slice(0, question);
  if (!/^[A-Za-z0-9._~/-]+$/.test(pathname) || pathname.startsWith('/') ||
      pathname.endsWith('/') || pathname.split('/').some((segment) => !segment || segment === '.' || segment === '..')) {
    throw new TypeError('Invalid Admin request path.');
  }
  return '/api/admin/' + path;
}

export function validateAdminConfig(config: AdminClientConfig): void {
  if (config.backend !== 'cloudflare' && config.backend !== 'supabase') throw new TypeError('Select a supported Admin backend.');
  if (typeof config.captchaEnabled !== 'boolean') throw new TypeError('Admin challenge policy must be configured.');
  if (typeof config.googleEnabled !== 'boolean') throw new TypeError('Admin Google sign-in policy must be configured.');
  if (config.backend === 'supabase' && !isAdminPublishableKey(config.publishableKey)) {
    throw new TypeError('Supabase Admin requires its public publishable key.');
  }
  if (config.backend === 'cloudflare' && config.publishableKey) throw new TypeError('Unexpected Supabase configuration.');
  if (config.backend === 'cloudflare' && config.captchaEnabled) throw new TypeError('The configured Admin challenge is unavailable for this backend.');
}

export function admitRequest(config: AdminClientConfig, path: string, options: AdminRequestOptions) {
  const target = checkedPath(path);
  const method = options.method ?? (options.body === undefined ? 'GET' : 'POST');
  const mutation = method !== 'GET';
  const authenticated = options.authenticated ?? true;
  const mfaRecovery = options.mfaRecovery === true;
  if (mfaRecovery && (config.backend !== 'supabase' || method !== 'POST' || !['auth/mfa/recover', 'auth/logout'].includes(path) ||
      !validMfaRecovery(options.body) || options.idempotencyKey !== undefined || options.reviewReason !== undefined)) throw new TypeError('Invalid MFA recovery request.');
  if (path === 'auth/mfa/recover' && !mfaRecovery) throw new TypeError('MFA recovery requires the original intent.');
  if (!authenticated && !SESSION_AUTH_PATHS.has(path)) throw new TypeError('The request requires an authenticated session.');
  if (!['GET', 'POST', 'PATCH'].includes(method) || (method === 'GET' && options.body !== undefined)) throw new TypeError('Invalid Admin request method.');
  if (options.idempotencyKey !== undefined && !KEY.test(options.idempotencyKey)) throw new TypeError('Invalid request reference.');
  if (options.reviewReason !== undefined && (options.reviewReason.trim().length < 8 || options.reviewReason.length > 1000 || /[\r\n]/.test(options.reviewReason))) throw new TypeError('Invalid review reason.');
  return {target, method, mutation, authenticated, mfaRecovery, checksCredentials: path === 'auth/verify' || path === 'auth/login'};
}

type AdmittedRequest = ReturnType<typeof admitRequest>;

export function requireRequestAuthority(config: AdminClientConfig, request: AdmittedRequest, before: AuthoritySnapshot): void {
  if (!request.authenticated) return;
  if (!before.key) throw new AdminRequestError('Sign in again to continue.');
  if (request.mutation && config.backend === 'supabase' && !before.csrfToken && !request.mfaRecovery) {
    throw new AdminRequestError('Refresh your session before continuing.');
  }
}

export function requestNeedsCaptcha(config: AdminClientConfig, path: string, request: AdmittedRequest): boolean {
  return request.mutation && config.captchaEnabled && CAPTCHA_PATHS.has(path);
}

export async function withCaptcha(config: AdminClientConfig, body?: JsonObject): Promise<JsonObject> {
  if (!config.acquireCaptcha) throw new AdminRequestError('Security verification is unavailable. Try again later.');
  const captcha = await config.acquireCaptcha();
  if (!captcha || captcha.length > 8192 || /[\x00-\x1f\x7f]/.test(captcha)) {
    throw new AdminRequestError('Security verification could not finish.');
  }
  return {...body, captcha_token: captcha};
}

export function requestHeaders(config: AdminClientConfig, path: string, options: AdminRequestOptions, request: AdmittedRequest, before: AuthoritySnapshot) {
  const {mutation, method, mfaRecovery} = request;
  const headers: Record<string, string> = {Accept: 'application/json'};
  if (mutation) {
    headers['Content-Type'] = 'application/json';
    headers['X-Collect-Admin'] = '1';
    if (config.backend === 'supabase') headers['X-Collect-Requested-With'] = 'collect-admin';
    if (config.backend === 'supabase' && before.csrfToken && !mfaRecovery) headers['X-Collect-CSRF'] = before.csrfToken;
  }
  if (config.backend === 'supabase' && path === 'auth/session' && method === 'GET') headers['X-Collect-Owner-Identity-Version'] = '1';
  if (config.backend === 'supabase') headers.apikey = config.publishableKey!;
  if (options.idempotencyKey) headers['Idempotency-Key'] = options.idempotencyKey;
  if (options.reviewReason) headers['X-Collect-Review-Reason'] = options.reviewReason.trim();
  return headers;
}
