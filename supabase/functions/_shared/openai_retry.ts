export type OpenAIErrorKind =
  | "quota"
  | "rate_limit"
  | "server"
  | "request";

export type OpenAIFailureDiagnostic = {
  status: number;
  code: string | null;
  requestId: string | null;
  kind: OpenAIErrorKind;
  retryable: boolean;
  attempt: number;
};

export class OpenAIHttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string | null,
    readonly requestId: string | null,
    readonly kind: OpenAIErrorKind,
    readonly retryable: boolean,
  ) {
    super(
      kind === "quota"
        ? "OpenAI SMS parsing unavailable (quota)"
        : kind === "rate_limit"
        ? "OpenAI SMS parsing unavailable (rate_limit)"
        : kind === "server"
        ? "OpenAI SMS parsing unavailable (upstream)"
        : `OpenAI SMS parsing unavailable (${status})`,
    );
    this.name = "OpenAIHttpError";
  }
}

const quotaCodes = new Set([
  "credit_balance_exhausted",
  "insufficient_quota",
]);
const rateLimitCodes = new Set([
  "rate_limit_exceeded",
  "requests_rate_limit_exceeded",
  "tokens_rate_limit_exceeded",
]);

function cleanCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const code = value.trim().toLowerCase();
  return /^[a-z0-9_.-]{1,80}$/.test(code) ? code : null;
}

async function classifyOpenAIError(
  response: Response,
): Promise<OpenAIHttpError> {
  let code: string | null = null;
  try {
    const body = await response.json() as Record<string, unknown>;
    const error = typeof body.error === "object" && body.error != null
      ? body.error as Record<string, unknown>
      : {};
    code = cleanCode(error.code) ?? cleanCode(error.type);
  } catch {
    // Classification remains safe and status-based when OpenAI returns a
    // non-JSON proxy response. Never copy the upstream body into logs/errors.
  }

  const requestId = cleanCode(response.headers.get("x-request-id"));
  const quota = code != null && quotaCodes.has(code);
  const rateLimit = !quota &&
    (response.status === 429 || (code != null && rateLimitCodes.has(code)));
  const server = response.status >= 500;
  const kind: OpenAIErrorKind = quota
    ? "quota"
    : rateLimit
    ? "rate_limit"
    : server
    ? "server"
    : "request";
  return new OpenAIHttpError(
    response.status,
    code,
    requestId,
    kind,
    rateLimit || server,
  );
}

function retryAfterMs(response: Response, nowMs: number): number | null {
  const value = response.headers.get("retry-after")?.trim();
  if (!value) return null;
  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds >= 0) return seconds * 1_000;
  const dateMs = Date.parse(value);
  return Number.isFinite(dateMs) ? Math.max(0, dateMs - nowMs) : null;
}

export type OpenAIRetryOptions = {
  maxAttempts?: number;
  maxDelayMs?: number;
  random?: () => number;
  now?: () => number;
  wait?: (milliseconds: number) => Promise<void>;
  onFailure?: (diagnostic: OpenAIFailureDiagnostic) => void;
};

export async function fetchOpenAIWithRetry(
  request: () => Promise<Response>,
  options: OpenAIRetryOptions = {},
): Promise<Response> {
  const maxAttempts = Math.max(1, Math.min(options.maxAttempts ?? 3, 5));
  const maxDelayMs = Math.max(0, Math.min(options.maxDelayMs ?? 2_500, 10_000));
  const random = options.random ?? Math.random;
  const now = options.now ?? Date.now;
  const wait = options.wait ??
    ((milliseconds) =>
      new Promise((resolve) => setTimeout(resolve, milliseconds)));

  let lastError: OpenAIHttpError | null = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const response = await request();
    if (response.ok) return response;

    const error = await classifyOpenAIError(response);
    lastError = error;
    options.onFailure?.({
      status: error.status,
      code: error.code,
      requestId: error.requestId,
      kind: error.kind,
      retryable: error.retryable,
      attempt,
    });
    if (!error.retryable || attempt === maxAttempts) throw error;

    const exponentialMs = 300 * 2 ** (attempt - 1);
    const jitterMs = Math.floor(Math.max(0, Math.min(random(), 1)) * 200);
    const delayMs = Math.min(
      maxDelayMs,
      retryAfterMs(response, now()) ?? exponentialMs + jitterMs,
    );
    await wait(delayMs);
  }
  throw lastError ?? new Error("OpenAI SMS parsing unavailable");
}
