import {AdminRequestError, isJsonObject, type AdminBackend, type AdminRequestOptions, type JsonObject} from './contracts';

const CSRF = /^[A-Za-z0-9_-]{32,200}$/;
const EMAIL_PROOF_PATHS = new Set(['auth/email-verification', 'auth/email/request', 'auth/email/verify']);

function errorCode(body: JsonObject): string | undefined {
  const value = body.error;
  if (typeof value === 'string') return value;
  if (isJsonObject(value)) {
    const code = value.code;
    if (typeof code === 'string') return code;
  }
  return typeof body.code === 'string' ? body.code : undefined;
}

export async function boundedResponseBody(response: Response, maximumBytes: number): Promise<string> {
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

export function decodeResponse(
  response: Response,
  raw: string | undefined,
  path: string,
  options: AdminRequestOptions,
  statusPolicy: {mutation: boolean; checksCredentials: boolean; mfaRecovery: boolean},
  onUnauthorized: () => void,
): JsonObject {
  const {mutation, checksCredentials, mfaRecovery} = statusPolicy;
  if (response.status === 401 && mfaRecovery) throw new AdminRequestError('Authenticator recovery could not be confirmed. Keep the original recovery reference.', {statusCode: 401, outcomeUnknown: true});
  if (response.status === 401 && !checksCredentials) {
    if (path === 'auth/session' && options.expectedStatus === undefined) return {user: null};
    onUnauthorized();
    throw new AdminRequestError('Sign in again to continue.', {statusCode: 401, code: 'unauthenticated'});
  }
  if (raw === undefined) {
    const message = response.status === 426 ? safeErrorMessage(response.status, undefined, mutation, path) : 'The service response could not be verified.';
    throw new AdminRequestError(message, {statusCode: response.status, outcomeUnknown: true});
  }
  let parsed: unknown;
  try { parsed = JSON.parse(raw); } catch {
    throw new AdminRequestError('The service response could not be verified.', {statusCode: response.status, outcomeUnknown: mutation || response.status >= 500});
  }
  if (!isJsonObject(parsed)) throw new AdminRequestError('The service response could not be verified.', {statusCode: response.status, outcomeUnknown: mutation});
  const result = parsed;
  const code = errorCode(result);
  if (!response.ok) throw new AdminRequestError(safeErrorMessage(response.status, code, mutation, path), {statusCode: response.status, code, outcomeUnknown: code === 'proxy_outcome_unknown' || (mutation && response.status >= 500), otpReceiptBody: path === 'auth/otp' && code === 'email_delivery_unknown' ? result : undefined});
  if (options.expectedStatus !== undefined && response.status !== options.expectedStatus) throw new AdminRequestError('The current response could not be confirmed.', {statusCode: response.status, outcomeUnknown: mutation});
  return result;
}

export function acceptedCsrf(backend: AdminBackend, path: string, result: JsonObject, mutation: boolean): string | null | undefined {
  if (backend !== 'supabase' || EMAIL_PROOF_PATHS.has(path) || !Object.hasOwn(result, 'csrfToken')) return;
  const token = result.csrfToken;
  if (token === null && path === 'auth/session' && result.user === null) return null;
  if (typeof token === 'string' && CSRF.test(token)) return token;
  throw new AdminRequestError('Session verification could not finish.', {outcomeUnknown: mutation});
}
