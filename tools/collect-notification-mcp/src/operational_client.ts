import { runtimeCredentials } from "./runtime_credentials.ts";
import { operatorEnvironment, validatedSupabaseUrl, type OperatorEnvironment, type FetchLike } from "./operator_client.ts";
import { instant, nonnegativeInteger, object, operationalHealth } from "./operational_health.ts";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const states = ["queued", "awaiting_confirmation", "send_started", "observed_sent", "failed_no_send", "uncertain", "suppressed"];
const attempts = ["send_started", "observed_sent", "failed_no_send", "uncertain"];
const suppressionCodes: Record<string, string> = {
  "Member authenticated the app with the exact verified MoMo number": "verified_member_app_active",
  "Consent, collection policy, destination or payment state changed before claim": "receipt_authorization_changed",
};
const responseInvalid = (): never => {throw new Error("COLLECT_RESPONSE_INVALID");};
function identifier(value: unknown): string {
  if (typeof value !== "string" || !uuid.test(value)) return responseInvalid();
  return value.toLowerCase();
}
function optionalInstant(value: unknown) {return value === null ? null : instant(value);}

// Intentionally omit names, Collect IDs, amounts, telephone numbers (including
// masks), bodies, hashes, transaction references and arbitrary error strings.
export function notificationStatus(value: unknown, expectedId: string) {
  const row = object(value);
  if (Object.keys(row).length === 0) return {found: false, notification_id: expectedId, reason_code: "receipt_not_found"};
  const id = identifier(row.id);
  if (id !== expectedId.toLowerCase() || typeof row.state !== "string" || !states.includes(row.state) || row.channel !== "Assisted SMS operator" ||
      typeof row.authorization_current !== "boolean" || row.template_key !== "buri_munsi.payment_received" ||
      row.template_version !== 1 || nonnegativeInteger(row.consent_revision) < 1 ||
      (row.latest_attempt_state !== null && (typeof row.latest_attempt_state !== "string" || !attempts.includes(row.latest_attempt_state)))) return responseInvalid();
  if (row.suppression_reason !== null && typeof row.suppression_reason !== "string") return responseInvalid();
  return {
    found: true, notification_id: id, state: row.state, channel: "assisted_sms",
    authorization_current: row.authorization_current, attempt_count: nonnegativeInteger(row.attempt_count),
    created_at: instant(row.created_at), claim_expires_at: optionalInstant(row.claim_expires_at),
    observed_sent_at: optionalInstant(row.observed_sent_at), latest_attempt_state: row.latest_attempt_state,
    reason_code: row.state === "suppressed" ? typeof row.suppression_reason === "string" && Object.hasOwn(suppressionCodes, row.suppression_reason) ? suppressionCodes[row.suppression_reason] : "suppression_reason_unclassified" : `receipt_${row.state}`,
    delivery_evidence_code: "operator_observation_not_handset_delivery",
  };
}
export function notificationFailures(value: unknown, limit: number, offset: number, status: string) {
  const source = object(value);
  const total = nonnegativeInteger(source.total);
  if (!Array.isArray(source.rows) || source.rows.length > limit || total < source.rows.length ||
      (source.rows.length > 0 && total < offset + source.rows.length)) return responseInvalid();
  const seen = new Set<string>();
  const rows = source.rows.map(raw => {
    const row = object(raw), id = identifier(row.id);
    if (seen.has(id) || row.status !== status || row.channel !== "assisted_sms" || row.country_code !== "RW" ||
        typeof row.authorization_current !== "boolean" || row.template_key !== "buri_munsi.payment_received" ||
        row.template_version !== 1 || nonnegativeInteger(row.consent_revision) < 1) return responseInvalid();
    seen.add(id);
    return {
      notification_id: id, state: status, channel: "assisted_sms", country_code: "RW",
      authorization_current: row.authorization_current, attempt_count: nonnegativeInteger(row.attempt_count),
      created_at: instant(row.created_at), claim_expires_at: optionalInstant(row.claim_expires_at),
      reason_code: `receipt_${status}`, delivery_evidence_code: "operator_observation_not_handset_delivery",
    };
  });
  const next = offset + rows.length;
  return {rows, total, limit, offset, status, next_offset: next < total && rows.length > 0 && next <= 10_000 ? next : null,
    pagination_limit_reached: next < total && next > 10_000};
}

function validateCredentials(environment: OperatorEnvironment, now: number) {
  try {
    const origin = validatedSupabaseUrl(environment.supabaseUrl);
    const parts = environment.accessToken.split(".");
    if (parts.length !== 3 || !parts.every(part => /^[A-Za-z0-9_-]+$/.test(part)) || environment.accessToken.length > 16_384) throw new Error();
    const claims = object(JSON.parse(Buffer.from(parts[1]!, "base64url").toString("utf8")));
    const header = object(JSON.parse(Buffer.from(parts[0]!, "base64url").toString("utf8")));
    const key = environment.anonKey.startsWith("sb_publishable_") ? {role: "anon"} :
      object(JSON.parse(Buffer.from(environment.anonKey.split(".")[1] ?? "", "base64url").toString("utf8")));
    if (typeof header.alg !== "string" || !["HS256", "RS256", "ES256", "EdDSA"].includes(header.alg) || key.role !== "anon" || claims.role !== "authenticated" || claims.iss !== `${origin}/auth/v1` ||
        typeof claims.sub !== "string" || !uuid.test(claims.sub) || typeof claims.session_id !== "string" || !uuid.test(claims.session_id) ||
        !Number.isSafeInteger(claims.exp) || Number(claims.exp) <= Math.floor(now / 1000) + 60) throw new Error();
  } catch {throw new Error("COLLECT_CURRENT_USER_SESSION_REQUIRED");}
}

async function withinDeadline<T>(operation: Promise<T>, signal: AbortSignal): Promise<T> {
  signal.throwIfAborted();
  let rejectAborted: () => void = () => {};
  const aborted = new Promise<never>((_resolve, reject) => {
    rejectAborted = () => reject(new Error("COLLECT_REQUEST_TIMEOUT"));
    signal.addEventListener("abort", rejectAborted, {once: true});
  });
  try {return await Promise.race([operation, aborted]);}
  finally {signal.removeEventListener("abort", rejectAborted);}
}

async function boundedJson(response: Response, signal: AbortSignal) {
  const maximum = 256 * 1024;
  const length = response.headers.get("content-length");
  if ((length !== null && (!/^\d+$/.test(length) || Number(length) > maximum)) ||
      !response.headers.get("content-type")?.toLowerCase().startsWith("application/json") || !response.body) {
    void response.body?.cancel().catch(() => {});
    return responseInvalid();
  }
  const reader = response.body.getReader();
  let bytes = 0;
  const chunks: Uint8Array[] = [];
  try {
    for (;;) {
      signal.throwIfAborted();
      const {value, done} = await withinDeadline(reader.read(), signal);
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maximum) return responseInvalid();
      chunks.push(value);
    }
    return JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
  } finally {void reader.cancel().catch(() => {});}
}

export async function callOperationalRead(
  action: "health" | "status" | "failures",
  input: Record<string, unknown>,
  environment?: OperatorEnvironment,
  fetcher: FetchLike = fetch,
  now: () => number = Date.now,
  timeoutMs = 15_000,
) {
  // Also validate direct calls, not only the exposed tool schema.
  let rpc: string, args: Record<string, unknown>;
  if (action === "health" && Object.keys(input).length === 0) {
    rpc = "admin_system_health"; args = {p_id: "system"};
  } else if (action === "status" && Object.keys(input).length === 1 && typeof input.notification_id === "string" && uuid.test(input.notification_id)) {
    rpc = "admin_get_hybrid_sms_receipt"; args = {p_id: input.notification_id};
  } else if (action === "failures" && Object.keys(input).every(key => ["limit", "offset", "status"].includes(key))) {
    const limit = input.limit ?? 20, offset = input.offset ?? 0, status = input.status ?? "failed_no_send";
    if (!Number.isSafeInteger(limit) || Number(limit) < 1 || Number(limit) > 25 ||
        !Number.isSafeInteger(offset) || Number(offset) < 0 || Number(offset) > 10_000 ||
        typeof status !== "string" || !["failed_no_send", "uncertain"].includes(status)) throw new Error("COLLECT_ARGUMENTS_INVALID");
    rpc = "admin_list_hybrid_sms_receipts"; args = {p_search: null, p_status: status, p_limit: limit, p_offset: offset, p_sort: "created_at_desc"};
  } else throw new Error("COLLECT_ARGUMENTS_INVALID");
  let resolved: OperatorEnvironment;
  try {resolved = environment ?? operatorEnvironment(await runtimeCredentials());}
  catch {throw new Error("COLLECT_CURRENT_USER_SESSION_REQUIRED");}
  validateCredentials(resolved, now());
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15_000) throw new Error("COLLECT_ARGUMENTS_INVALID");
  const deadline = new AbortController(), signal = deadline.signal;
  const timer = setTimeout(() => deadline.abort(), timeoutMs);
  try {
    const response = await withinDeadline(fetcher(`${validatedSupabaseUrl(resolved.supabaseUrl)}/rest/v1/rpc/${rpc}`, {
      method: "POST", redirect: "error", cache: "no-store", signal,
      headers: {Authorization: `Bearer ${resolved.accessToken}`, apikey: resolved.anonKey,
        "Content-Type": "application/json", Accept: "application/json", "Accept-Profile": "public", "Content-Profile": "public"},
      body: JSON.stringify(args),
    }), signal);
    if (!response.ok || response.redirected) {
      void response.body?.cancel().catch(() => {});
      throw new Error(response.status === 401 || response.status === 403 ? "COLLECT_AUTHORIZATION_REQUIRED" : "COLLECT_BACKEND_UNAVAILABLE");
    }
    const value = await boundedJson(response, signal);
    return action === "health" ? operationalHealth(value, now()) : action === "status" ? notificationStatus(value, String(input.notification_id)) :
      notificationFailures(value, Number(args.p_limit), Number(args.p_offset), String(args.p_status));
  } catch (error) {
    if (signal.aborted) throw new Error("COLLECT_REQUEST_TIMEOUT");
    const safe = error instanceof Error && ["COLLECT_RESPONSE_INVALID", "COLLECT_AUTHORIZATION_REQUIRED", "COLLECT_BACKEND_UNAVAILABLE"].includes(error.message);
    throw new Error(safe ? error.message : "COLLECT_TRANSPORT_OR_RESPONSE_FAILURE");
  } finally {clearTimeout(timer);}
}
