import type { Job, Kind } from "./types.ts";
import { KINDS } from "./types.ts";
export class ApiError extends Error {
  constructor(
    public status: 400 | 401 | 403 | 404 | 409 | 413 | 429 | 500 | 503,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}
export const isoNow = () => new Date().toISOString();
export const after = (ms: number, now = Date.now()) =>
  new Date(now + ms).toISOString();
export const uid = (prefix: string) => `${prefix}_${crypto.randomUUID()}`;
export function string(
  value: unknown,
  field: string,
  min = 1,
  max = 256,
): string {
  if (typeof value !== "string" || value.length < min || value.length > max)
    throw new ApiError(
      400,
      "invalid_request",
      `${field} must be a string of ${min}..${max} characters`,
    );
  return value;
}
export function integer(
  value: unknown,
  field: string,
  min = 0,
  max = Number.MAX_SAFE_INTEGER,
): number {
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < min ||
    (value as number) > max
  )
    throw new ApiError(
      400,
      "invalid_request",
      `${field} must be an integer in ${min}..${max}`,
    );
  return value as number;
}
export function kind(value: unknown): Kind {
  if (!KINDS.includes(value as Kind))
    throw new ApiError(400, "invalid_request", "Unsupported message kind");
  return value as Kind;
}
export function phone(value: unknown): string {
  const v = string(value, "phone", 8, 16);
  if (!/^\+[1-9][0-9]{7,14}$/.test(v))
    throw new ApiError(
      400,
      "invalid_phone",
      "Use an E.164 phone number, for example +2507XXXXXXXX",
    );
  return v;
}
export function timestamp(value: unknown, field: string): string {
  const v = string(value, field, 20, 35);
  const parts = /^(\d{4})-(\d\d)-(\d\d)T\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.exec(v);
  const year = parts ? Number(parts[1]) : 0;
  const month = parts ? Number(parts[2]) : 0;
  const day = parts ? Number(parts[3]) : 0;
  const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const daysInMonth = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (
    !parts ||
    month < 1 || month > 12 || day < 1 || day > daysInMonth[month - 1] ||
    !Number.isFinite(Date.parse(v))
  )
    throw new ApiError(
      400,
      "invalid_request",
      `${field} must be a valid UTC ISO8601 timestamp`,
    );
  return new Date(v).toISOString();
}
export function object(
  value: unknown,
  field = "body",
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new ApiError(400, "invalid_request", `${field} must be an object`);
  return value as Record<string, unknown>;
}
export function array(value: unknown, field: string, max: number): unknown[] {
  if (!Array.isArray(value) || value.length > max)
    throw new ApiError(
      400,
      "invalid_request",
      `${field} must be an array with at most ${max} entries`,
    );
  return value;
}
export function canonical(value: unknown): string {
  if (value === null || typeof value !== "object")
    return JSON.stringify(value) ?? "null";
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  return `{${Object.keys(value as object)
    .sort()
    .filter((k) => (value as Record<string, unknown>)[k] !== undefined)
    .map(
      (k) =>
        `${JSON.stringify(k)}:${canonical((value as Record<string, unknown>)[k])}`,
    )
    .join(",")}}`;
}
const utf8 = new TextEncoder();
export async function sha256(value: string): Promise<string> {
  return [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", utf8.encode(value)),
    ),
  ]
    .map((v) => v.toString(16).padStart(2, "0"))
    .join("");
}
export async function payloadDigest(
  job: Pick<
    Job,
    | "message_id"
    | "application_id"
    | "kind"
    | "to"
    | "text"
    | "priority"
    | "not_after"
    | "available_at"
    | "campaign_id"
  >,
): Promise<string> {
  const fields = [
    job.message_id,
    job.application_id,
    job.kind,
    job.to,
    job.text,
    String(job.priority),
    job.not_after,
    job.available_at,
    job.campaign_id ?? "",
  ];
  return sha256(
    "collect-sms-payload-v1\n" +
      fields.map((v) => `${utf8.encode(v).byteLength}:${v}`).join(""),
  );
}
export async function hmac(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    utf8.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return [
    ...new Uint8Array(
      await crypto.subtle.sign("HMAC", key, utf8.encode(value)),
    ),
  ]
    .map((v) => v.toString(16).padStart(2, "0"))
    .join("");
}
export function safeEqual(a: string, b: string): boolean {
  const aa = utf8.encode(a),
    bb = utf8.encode(b);
  let diff = aa.length ^ bb.length;
  for (let i = 0; i < Math.max(aa.length, bb.length); i++)
    diff |= (aa[i] ?? 0) ^ (bb[i] ?? 0);
  return diff === 0;
}
export function randomToken(prefix: string): string {
  return (
    prefix +
    [...crypto.getRandomValues(new Uint8Array(32))]
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("")
  );
}
export function randomCode(): string {
  const ceiling = Math.floor(0x100000000 / 1_000_000) * 1_000_000;
  let n: number;
  do {
    n = crypto.getRandomValues(new Uint32Array(1))[0]!;
  } while (n >= ceiling);
  return String(n % 1_000_000).padStart(6, "0");
}
export function segmentEstimate(text: string): number {
  const gsm =
    /^[A-Za-z0-9 @£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&'()*+,\-./:;<=>?¡ÄÖÑÜ§¿äöñüà^{}\\\[~\]|€]*$/u.test(
      text,
    );
  const length = gsm
    ? [...text].reduce((n, ch) => n + ("^{}\\[~]|€".includes(ch) ? 2 : 1), 0)
    : text.length;
  return Math.max(
    1,
    Math.ceil(
      length / (gsm ? (length <= 160 ? 160 : 153) : length <= 70 ? 70 : 67),
    ),
  );
}
