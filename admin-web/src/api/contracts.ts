export type JsonObject = Record<string, unknown>;
export type AdminBackend = 'cloudflare' | 'supabase';

export function isJsonObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

const verificationUuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

export function isVerificationUuid(value: unknown): value is string {
  return typeof value === 'string' && verificationUuid.test(value);
}

export function isAdminPublishableKey(value: unknown): value is string {
  return typeof value === 'string' && /^sb_publishable_[A-Za-z0-9_-]{10,300}$/.test(value);
}

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
