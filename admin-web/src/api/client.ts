/* eslint-disable no-control-regex -- Reject ASCII control characters in untrusted input. */
export type JsonObject = Record<string, unknown>;
export type AdminBackend = 'cloudflare' | 'supabase';

export interface AdminClientConfig {
  backend: AdminBackend;
  /** A public publishable key, never a service-role or secret key. */
  publishableKey?: string;
  captchaEnabled: boolean;
  acquireCaptcha?: () => Promise<string>;
  cancelCaptcha?: () => void;
  googleEnabled: boolean;
  supabaseProjectOrigin?: string;
  fetchImpl?: typeof fetch;
  deadlineMs?: number;
  maxResponseBytes?: number;
}

export interface AdminRequestOptions {
  method?: 'GET' | 'POST' | 'PATCH';
  body?: JsonObject;
  authenticated?: boolean;
  idempotencyKey?: string;
  reviewReason?: string;
  expectedStatus?: number;
  signal?: AbortSignal;
  /** Use only the exact per-tab Supabase MFA intent to recover or sign out. */
  mfaRecovery?: boolean;
}

export type AdminRequest = (path: string, options?: AdminRequestOptions) => Promise<JsonObject>;

export interface AuthoritySnapshot {
  epoch: number;
  key: string | null;
  csrfToken: string | null;
}

export class AdminRequestError extends Error {
  readonly statusCode?: number;
  readonly code?: string;
  readonly outcomeUnknown: boolean;
  readonly otpReceiptBody?: JsonObject;

  constructor(message: string, details: {statusCode?: number; code?: string; outcomeUnknown?: boolean; otpReceiptBody?: JsonObject} = {}) {
    super(message);
    this.name = 'AdminRequestError';
    this.statusCode = details.statusCode;
    this.code = details.code;
    this.outcomeUnknown = details.outcomeUnknown ?? false;
    this.otpReceiptBody = details.otpReceiptBody;
  }
}

const KEY = /^[A-Za-z0-9._:-]{8,200}$/;
const CSRF = /^[A-Za-z0-9_-]{32,200}$/;
const CAPTCHA_PATHS = new Set(['auth/otp', 'auth/login', 'auth/forgot-password', 'auth/email/request']);
const EMAIL_PROOF_PATHS = new Set(['auth/email-verification', 'auth/email/request', 'auth/email/verify']);
const SESSION_AUTH_PATHS = new Set(['auth/session', 'auth/email-verification', 'auth/otp', 'auth/verify', 'auth/login', 'auth/logout', 'auth/forgot-password', 'auth/complete-password', 'auth/google/start', 'auth/google/exchange', 'auth/mfa/recover']);
const MFA_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function validMfaRecovery(body: JsonObject | undefined): boolean {
  return !!body && typeof body === 'object' && !Array.isArray(body) &&
    Object.keys(body).sort().join(',') === 'challenge_id,factor_id,verification_id' &&
    typeof body.factor_id === 'string' && MFA_UUID.test(body.factor_id) &&
    typeof body.challenge_id === 'string' && MFA_UUID.test(body.challenge_id) &&
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

function errorCode(body: JsonObject): string | undefined {
  const value = body.error;
  if (typeof value === 'string') return value;
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    const code = (value as JsonObject).code;
    if (typeof code === 'string') return code;
  }
  return typeof body.code === 'string' ? body.code : undefined;
}

async function boundedBody(response: Response, maximumBytes: number): Promise<string> {
  const declared = response.headers.get('content-length');
  if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > maximumBytes)) {
    throw new Error('Response too large.');
  }
  if (!response.body) return '';
  const reader = response.body.getReader();
  const parts: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maximumBytes) throw new Error('Response too large.');
      parts.push(value);
    }
  } catch (error) {
    await reader.cancel().catch(() => undefined);
    throw error;
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) { bytes.set(part, offset); offset += part.byteLength; }
  return new TextDecoder('utf-8', {fatal: true}).decode(bytes);
}

function safeErrorMessage(status: number, code: string | undefined, mutation: boolean, path: string): string {
  if (code === 'proxy_outcome_unknown') return 'The result is unknown. Check the original request before continuing.';
  if (code === 'recent_email_sign_in_required') return 'Verify your email before making this change.';
  if (code === 'password_recovery_required') return 'Use the email password recovery link to set or recover your password.';
  if (code === 'admin_access_not_approved') return 'This email does not have Admin access. Contact your super admin.';
  if (code === 'invalid_credentials' && (path === 'auth/verify' || path === 'auth/email/verify')) return 'That code is invalid or expired. Use the latest email code.';
  if (status === 401) return path === 'auth/login' ? 'The email or password is incorrect.' : 'Sign in again to continue.';
  if (status === 403) return mutation ? 'You do not have permission to make this change.' : 'You do not have permission to view these records.';
  if (status === 409) return 'The request conflicts with the current state. Check the original request and refresh the details.';
  if (status === 426) return 'This Admin version needs to be updated. Close Admin tabs and open it again.';
  if (status === 429) return 'Too many attempts. Please wait before trying again.';
  if (path === 'auth/complete-password') return 'This link is invalid or expired. Request a new email.';
  return mutation ? 'The request was not confirmed. Check its status before continuing.' : 'The records could not be loaded. Refresh and try again.';
}

/** Cookie transport: never stores bearer/session tokens or automatically retries. */
export class AdminApiClient {
  readonly config: AdminClientConfig;
  private readonly authority: () => AuthoritySnapshot;
  private readonly setCsrf: (token: string | null) => void;
  private readonly onUnauthorized: () => void;
  private readonly fetchImpl: typeof fetch;

  constructor(
    config: AdminClientConfig,
    authority: () => AuthoritySnapshot,
    setCsrf: (token: string | null) => void,
    onUnauthorized: () => void,
  ) {
    if (config.backend !== 'cloudflare' && config.backend !== 'supabase') throw new TypeError('Select a supported Admin backend.');
    if (typeof config.captchaEnabled !== 'boolean') throw new TypeError('Admin challenge policy must be configured.');
    if (typeof config.googleEnabled !== 'boolean') throw new TypeError('Admin Google sign-in policy must be configured.');
    if (config.backend === 'supabase' && !/^sb_publishable_[A-Za-z0-9_-]{10,300}$/.test(config.publishableKey ?? '')) {
      throw new TypeError('Supabase Admin requires its public publishable key.');
    }
    if (config.backend === 'cloudflare' && config.publishableKey) throw new TypeError('Unexpected Supabase configuration.');
    if (config.backend === 'cloudflare' && config.captchaEnabled) throw new TypeError('The configured Admin challenge is unavailable for this backend.');
    this.config = config;
    this.authority = authority;
    this.setCsrf = setCsrf;
    this.onUnauthorized = onUnauthorized;
    // Native Window.fetch can reject an unbound/class-method receiver.
    this.fetchImpl = config.fetchImpl ?? globalThis.fetch.bind(globalThis);
  }

  readonly request: AdminRequest = async (path, options = {}) => {
    const target = checkedPath(path);
    const method = options.method ?? (options.body === undefined ? 'GET' : 'POST');
    const mutation = method !== 'GET';
    const authenticated = options.authenticated ?? true;
    const mfaRecovery = options.mfaRecovery === true;
    if (mfaRecovery && (this.config.backend !== 'supabase' || method !== 'POST' || !['auth/mfa/recover', 'auth/logout'].includes(path) ||
        !validMfaRecovery(options.body) || options.idempotencyKey !== undefined || options.reviewReason !== undefined)) throw new TypeError('Invalid MFA recovery request.');
    if (path === 'auth/mfa/recover' && !mfaRecovery) throw new TypeError('MFA recovery requires the original intent.');
    if (!authenticated && !SESSION_AUTH_PATHS.has(path)) throw new TypeError('The request requires an authenticated session.');
    if (!['GET', 'POST', 'PATCH'].includes(method) || (method === 'GET' && options.body !== undefined)) throw new TypeError('Invalid Admin request method.');
    if (options.idempotencyKey !== undefined && !KEY.test(options.idempotencyKey)) throw new TypeError('Invalid request reference.');
    if (options.reviewReason !== undefined && (options.reviewReason.trim().length < 8 || options.reviewReason.length > 1000 || /[\r\n]/.test(options.reviewReason))) throw new TypeError('Invalid review reason.');
    const before = this.authority();
    if (authenticated && !before.key) throw new AdminRequestError('Sign in again to continue.');
    if (authenticated && mutation && this.config.backend === 'supabase' && !before.csrfToken && !mfaRecovery) throw new AdminRequestError('Refresh your session before continuing.');

    let body = options.body;
    if (mutation && this.config.captchaEnabled && CAPTCHA_PATHS.has(path)) {
      if (!this.config.acquireCaptcha) throw new AdminRequestError('Security verification is unavailable. Try again later.');
      const captcha = await this.config.acquireCaptcha();
      if (!captcha || captcha.length > 8192 || /[\x00-\x1f\x7f]/.test(captcha)) throw new AdminRequestError('Security verification could not finish.');
      body = {...body, captcha_token: captcha};
    }
    const current = () => {
      const now = this.authority();
      return now.epoch === before.epoch && (!authenticated || now.key === before.key);
    };
    if (!current()) throw new AdminRequestError('Your sign-in changed. Try again.');

    const headers: Record<string, string> = {Accept: 'application/json'};
    if (mutation) {
      headers['Content-Type'] = 'application/json';
      headers['X-Collect-Admin'] = '1';
      if (this.config.backend === 'supabase') headers['X-Collect-Requested-With'] = 'collect-admin';
      if (this.config.backend === 'supabase' && before.csrfToken && !mfaRecovery) headers['X-Collect-CSRF'] = before.csrfToken;
    }
    if (this.config.backend === 'supabase' && path === 'auth/session' && method === 'GET') headers['X-Collect-Owner-Identity-Version'] = '1';
    if (this.config.backend === 'supabase') headers.apikey = this.config.publishableKey!;
    if (options.idempotencyKey) headers['Idempotency-Key'] = options.idempotencyKey;
    if (options.reviewReason) headers['X-Collect-Review-Reason'] = options.reviewReason.trim();

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.config.deadlineMs ?? 30_000);
    const abort = () => controller.abort();
    options.signal?.addEventListener('abort', abort, {once: true});
    if (options.signal?.aborted) controller.abort();
    let response: Response;
    let raw: string;
    try {
      response = await this.fetchImpl(target, {
        method, headers, body: body === undefined ? undefined : JSON.stringify(body),
        credentials: 'same-origin', redirect: 'error', cache: 'no-store', signal: controller.signal,
      });
      raw = await boundedBody(response, this.config.maxResponseBytes ?? 2_097_152);
    } catch {
      throw new AdminRequestError(mutation ? 'The result is unknown. Check the original request before continuing.' : 'The workspace could not be reached. Check your session before trying again.', {outcomeUnknown: true});
    } finally {
      clearTimeout(timeout);
      options.signal?.removeEventListener('abort', abort);
    }
    if (!current()) throw new AdminRequestError('Your session changed. Reopen this page before continuing.', {outcomeUnknown: mutation});
    if (response.status === 401 && mfaRecovery) throw new AdminRequestError('Authenticator recovery could not be confirmed. Keep the original recovery reference.', {statusCode: 401, outcomeUnknown: true});
    if (response.status === 401 && path !== 'auth/verify' && path !== 'auth/login') {
      if (path === 'auth/session' && options.expectedStatus === undefined) return {user: null};
      this.onUnauthorized();
      throw new AdminRequestError('Sign in again to continue.', {statusCode: 401, code: 'unauthenticated'});
    }
    let parsed: unknown;
    try { parsed = JSON.parse(raw); } catch {
      throw new AdminRequestError('The service response could not be verified.', {statusCode: response.status, outcomeUnknown: mutation || response.status >= 500});
    }
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new AdminRequestError('The service response could not be verified.', {statusCode: response.status, outcomeUnknown: mutation});
    const result = parsed as JsonObject;
    const code = errorCode(result);
    if (!response.ok) throw new AdminRequestError(safeErrorMessage(response.status, code, mutation, path), {statusCode: response.status, code, outcomeUnknown: code === 'proxy_outcome_unknown' || (mutation && response.status >= 500), otpReceiptBody: path === 'auth/otp' && code === 'email_delivery_unknown' ? result : undefined});
    if (options.expectedStatus !== undefined && response.status !== options.expectedStatus) throw new AdminRequestError('The current response could not be confirmed.', {statusCode: response.status, outcomeUnknown: mutation});
    if (this.config.backend === 'supabase' && !EMAIL_PROOF_PATHS.has(path) && Object.hasOwn(result, 'csrfToken')) {
      const token = result.csrfToken;
      if (token === null && path === 'auth/session' && result.user === null) this.setCsrf(null);
      else if (typeof token === 'string' && CSRF.test(token)) this.setCsrf(token);
      else throw new AdminRequestError('Session verification could not finish.', {outcomeUnknown: mutation});
    }
    return result;
  };
}
