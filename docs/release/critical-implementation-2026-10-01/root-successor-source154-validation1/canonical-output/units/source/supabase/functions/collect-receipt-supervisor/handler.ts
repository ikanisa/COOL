type Json = Record<string, unknown>;
type Action = "prove_key" | "shadow_health" | "reconcile";
export interface SupervisorDependencies {
  rpc(
    name: string,
    args: Json,
    signal: AbortSignal,
  ): Promise<{ data: unknown; error: { code?: string } | null }>;
  now?: () => number;
  timeoutMs?: number;
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH = /^[0-9a-f]{64}$/;
class Refusal extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string) {
    super(code);
    this.status = status;
    this.code = code;
  }
}
function object(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function keys(value: unknown, expected: string[]): value is Json {
  return object(value) && Object.keys(value).length === expected.length &&
    expected.every((k) => Object.hasOwn(value, k));
}
function uuid(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}
function hash(value: unknown): value is string {
  return typeof value === "string" && HASH.test(value);
}
function integer(value: unknown, min: number, max: number): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) &&
    value >= min && value <= max;
}
function utc(value: unknown): value is string {
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(value)
  ) return false;
  const ms = Date.parse(value);
  return Number.isFinite(ms) &&
    new Date(ms).toISOString().slice(0, 19) === value.slice(0, 19);
}
function require(condition: unknown): asserts condition {
  if (!condition) throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID");
}
function base64(value: unknown, max: number): Uint8Array {
  require(
    typeof value === "string" && value.length <= max &&
      /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
        value,
      ),
  );
  let decoded: string;
  try {
    decoded = atob(value);
  } catch {
    throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID");
  }
  require(btoa(decoded) === value);
  return Uint8Array.from(decoded, (c) => c.charCodeAt(0));
}
function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}
async function digest(bytes: Uint8Array): Promise<string> {
  return hex(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
    ),
  );
}
// Android emits canonical DER; WebCrypto expects fixed-width P1363 r||s.
export function derToP1363(der: Uint8Array): Uint8Array {
  require(
    der.length >= 8 && der.length <= 72 && der[0] === 0x30 &&
      der[1] === der.length - 2,
  );
  let offset = 2;
  const output = new Uint8Array(64);
  for (let component = 0; component < 2; component++) {
    require(der[offset++] === 0x02);
    const size = der[offset++];
    require(typeof size === "number" && size >= 1 && size <= 33 && offset + size <= der.length);
    let value = der.slice(offset, offset + size);
    offset += size;
    require(value[0] !== undefined && !(value[0] & 0x80));
    require(value.length === 1 || value[0] !== 0 || !!((value[1] ?? 0) & 0x80));
    if (value[0] === 0) value = value.slice(1);
    require(value.length <= 32 && value.length > 0);
    const number = BigInt("0x" + hex(value));
    require(
      number > 0n &&
        number <
          0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n,
    );
    output.set(value, component * 32 + 32 - value.length);
  }
  require(offset === der.length);
  return output;
}
// Reject duplicate keys before JSON.parse loses them; impose a shallow bound.
function parseStrict(text: string): unknown {
  let at = 0;
  const ws = () => {
    while (/[\t\n\r ]/.test(text[at] ?? "x")) at++;
  };
  const string = (): string => {
    require(text[at] === '"');
    const start = at++;
    while (at < text.length) {
      if (text[at++] === "\\") {
        at++;
        continue;
      }
      if (text[at - 1] === '"') {
        try { return JSON.parse(text.slice(start, at)); }
        catch { throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID"); }
      }
    }
    throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID");
  };
  const value = (depth: number): void => {
    require(depth <= 8);
    ws();
    if (text[at] === "{") {
      at++;
      ws();
      const seen = new Set<string>();
      if (text[at] === "}") {
        at++;
        return;
      }
      while (true) {
        ws();
        const key = string();
        require(!seen.has(key));
        seen.add(key);
        ws();
        require(text[at++] === ":");
        value(depth + 1);
        ws();
        if (text[at] === "}") {
          at++;
          return;
        }
        require(text[at++] === ",");
      }
    } else if (text[at] === "[") {
      at++;
      ws();
      if (text[at] === "]") {
        at++;
        return;
      }
      while (true) {
        value(depth + 1);
        ws();
        if (text[at] === "]") {
          at++;
          return;
        }
        require(text[at++] === ",");
      }
    } else if (text[at] === '"') string();
    else {
      const token =
        /^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(
          text.slice(at),
        );
      require(token);
      at += token[0].length;
    }
  };
  value(0);
  ws();
  require(at === text.length);
  try {
    return JSON.parse(text);
  } catch {
    throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID");
  }
}
async function body(request: Request, timeout: number): Promise<Uint8Array> {
  require(
    /^application\/json(?:;\s*charset=utf-8)?$/i.test(
      request.headers.get("content-type") ?? "",
    ),
  );
  require(!request.headers.has("content-encoding"));
  const length = request.headers.get("content-length");
  if (length !== null) require(/^\d+$/.test(length) && Number(length) <= 8192);
  require(request.body);
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let count = 0;
  const deadline = Date.now() + timeout;
  try {
    while (true) {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const chunk = await Promise.race([
        reader.read(),
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => {
            reader.cancel().catch(() => {});
            reject(new Refusal(408, "SUPERVISOR_REQUEST_INVALID"));
          }, Math.max(1, deadline - Date.now()));
        }),
      ]).finally(() => {
        if (timer !== undefined) clearTimeout(timer);
      });
      if (chunk.done) break;
      count += chunk.value.length;
      if (count > 8192) {
        await reader.cancel().catch(() => {});
        throw new Refusal(413, "SUPERVISOR_BODY_TOO_LARGE");
      }
      chunks.push(chunk.value);
    }
  } finally {
    reader.releaseLock();
  }
  require(count > 0 && (length === null || Number(length) === count));
  const result = new Uint8Array(count);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  require(!(result[0] === 0xef && result[1] === 0xbb && result[2] === 0xbf));
  return result;
}

const AUDIENCE = "collect.receipt-supervisor.v1/lhbowpbcpwoiparwnwgt";
function payload(action: Action, value: unknown): asserts value is Json {
  if (action === "reconcile") {
    require(keys(value, ["target_request_id"]) && uuid(value.target_request_id));
  } else require(keys(value, []));
}
function observation(
  value: unknown, principal: string, request: string, action?: Action,
): value is Json {
  const base = ["contract_version", "principal_id", "request_id", "action",
    "observed_at", "expires_at", "scope", "mode", "business_handled",
    "financial_action", "send_action"];
  if (!object(value)) return false;
  const expected = value.action === "shadow_health"
    ? [...base, "sample_valid_until", "queued_count", "unknown_count",
      "failed_no_send_count", "dispatch_enabled"] : base;
  if (!keys(value, expected) || value.contract_version !== 1 ||
    value.principal_id !== principal || value.request_id !== request ||
    !["prove_key", "shadow_health"].includes(value.action as string) ||
    (action !== undefined && value.action !== action) ||
    !utc(value.observed_at) || !utc(value.expires_at) ||
    Date.parse(value.expires_at) <= Date.parse(value.observed_at) ||
    value.scope !== "rw_receipt_shadow" || value.mode !== "Shadow" ||
    value.business_handled !== false || value.financial_action !== false ||
    value.send_action !== false) return false;
  if (value.action === "shadow_health") {
    if (!utc(value.sample_valid_until) ||
      Date.parse(value.sample_valid_until) <= Date.parse(value.observed_at) ||
      Date.parse(value.sample_valid_until) > Date.parse(value.observed_at) + 60000 ||
      Date.parse(value.sample_valid_until) > Date.parse(value.expires_at) ||
      !integer(value.queued_count, 0, 1e9) || !integer(value.unknown_count, 0, 1e9) ||
      !integer(value.failed_no_send_count, 0, 1e9) ||
      typeof value.dispatch_enabled !== "boolean") return false;
  }
  return true;
}
export function validateSupervisorResult(
  value: unknown, principal: string, request: string, action: Action, p: Json,
): value is Json {
  if (action !== "reconcile") return observation(value, principal, request, action);
  if (!keys(value, ["contract_version", "target_request_id", "status", "receipt"]) ||
    value.contract_version !== 1 || value.target_request_id !== p.target_request_id ||
    !["recorded", "not_recorded", "in_progress"].includes(value.status as string)) return false;
  if (value.status === "recorded") {
    return observation(value.receipt, principal, p.target_request_id as string);
  }
  return value.receipt === null;
}
function response(status: number, value: Json): Response {
  return new Response(JSON.stringify(value), {status, headers: {
    "content-type": "application/json; charset=utf-8", "cache-control": "no-store",
    "x-content-type-options": "nosniff", "referrer-policy": "no-referrer",
  }});
}

/** Exact signed bytes, fixed audience and three narrowly scoped actions.
 * DB authority is rechecked after signature validation and request lock waits. */
export function createSupervisorHandler(dependencies: SupervisorDependencies) {
  const now = dependencies.now ?? Date.now;
  const timeout = Math.min(15000, Math.max(1, dependencies.timeoutMs ?? 5000));
  return async (request: Request): Promise<Response> => {
    let authenticated = false;
    let operational = false;
    const started = Date.now();
    const rpc = async (name: string, args: Json): Promise<unknown> => {
      const remaining = timeout - (Date.now() - started);
      if (remaining <= 0) throw new Refusal(503, authenticated
        ? "SUPERVISOR_OUTCOME_UNKNOWN" : "SUPERVISOR_AUTH_UNAVAILABLE");
      const controller = new AbortController();
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        const r = await Promise.race([
          dependencies.rpc(name, args, controller.signal),
          new Promise<never>((_, reject) => {
            timer = setTimeout(() => {
              controller.abort();
              reject(new Refusal(503, authenticated
                ? "SUPERVISOR_OUTCOME_UNKNOWN" : "SUPERVISOR_AUTH_UNAVAILABLE"));
            }, remaining);
          }),
        ]);
        if (r.error) {
          if (r.error.code === "55P03") throw new Refusal(409, "SUPERVISOR_AUTHORITY_BUSY");
          if (r.error.code === "42501") throw new Refusal(403, "SUPERVISOR_AUTHORITY_REFUSED");
          if (r.error.code === "22023" || r.error.code === "23505") {
            throw new Refusal(409, "SUPERVISOR_REQUEST_REFUSED");
          }
          if (operational && ["55000", "40001"].includes(r.error.code ?? "")) throw new Refusal(409, "SUPERVISOR_REQUEST_REFUSED");
          throw new Refusal(503, authenticated
            ? "SUPERVISOR_OUTCOME_UNKNOWN" : "SUPERVISOR_AUTH_UNAVAILABLE");
        }
        return r.data;
      } finally { if (timer !== undefined) clearTimeout(timer); }
    };
    try {
      if (request.method !== "POST") throw new Refusal(405, "SUPERVISOR_METHOD_REFUSED");
      require(new URL(request.url).search === "");
      const raw = await body(request, timeout);
      let text: string;
      try { text = new TextDecoder("utf-8", {fatal: true}).decode(raw); }
      catch { throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID"); }
      const envelope = parseStrict(text);
      require(keys(envelope, ["contract_version", "audience", "action", "principal_id",
        "request_id", "issued_at", "payload"]));
      operational = envelope.contract_version === 2;
      require(operational ? envelope.audience === "collect.receipt-supervisor.v2/lhbowpbcpwoiparwnwgt" && operationActions.includes(envelope.action as OperationAction)
        : envelope.contract_version === 1 && envelope.audience === AUDIENCE && ["prove_key", "shadow_health", "reconcile"].includes(envelope.action as string));
      require(uuid(envelope.principal_id) && uuid(envelope.request_id) && utc(envelope.issued_at));
      require(Date.parse(envelope.issued_at) >= now() - 30000 &&
        Date.parse(envelope.issued_at) <= now() + 10000);
      const action = envelope.action as Action | OperationAction;
      if (operational) require(validateOperationPayload(action as OperationAction, envelope.payload));
      else payload(action as Action, envelope.payload);
      const keyHash = request.headers.get("X-Collect-Supervisor-Key-Id");
      require(hash(keyHash));
      const signature = derToP1363(base64(request.headers.get("X-Collect-Supervisor-Signature"), 100));
      const key = await rpc("receipt_supervisor_key_v1", {p_principal_id: envelope.principal_id});
      if (!keys(key, ["contract_version", "principal_id", "state", "scope",
        "public_key_spki_base64", "key_sha256", "expires_at"]) ||
        key.contract_version !== 1 || key.principal_id !== envelope.principal_id ||
        key.scope !== (operational ? "rw_receipt_operations" : "rw_receipt_shadow") || !["pending", "active"].includes(key.state as string) ||
        !utc(key.expires_at) || Date.parse(key.expires_at) <= now() || key.key_sha256 !== keyHash) {
        throw new Refusal(401, "SUPERVISOR_KEY_REFUSED");
      }
      let spki: Uint8Array;
      try { spki = base64(key.public_key_spki_base64, 124); }
      catch { throw new Refusal(401, "SUPERVISOR_KEY_REFUSED"); }
      if (spki.length !== 91 || await digest(spki) !== keyHash) {
        throw new Refusal(401, "SUPERVISOR_KEY_REFUSED");
      }
      let verified = false;
      try {
        const imported = await crypto.subtle.importKey("spki", new Uint8Array(spki),
          {name: "ECDSA", namedCurve: "P-256"}, false, ["verify"]);
        verified = await crypto.subtle.verify({name: "ECDSA", hash: "SHA-256"},
          imported, new Uint8Array(signature), new Uint8Array(raw));
      } catch { verified = false; }
      if (!verified) throw new Refusal(401, "SUPERVISOR_SIGNATURE_REFUSED");
      authenticated = true;
      if (action !== "prove_key" && key.state !== "active") {
        throw new Refusal(403, "SUPERVISOR_PRINCIPAL_PENDING");
      }
      const args: Json = {p_principal_id: envelope.principal_id,
        p_request_id: envelope.request_id, p_key_sha256: keyHash,
        p_request_sha256: await digest(raw), p_issued_at: envelope.issued_at};
      const name = operational ? "receipt_operations_execute_v2" : action === "reconcile" ? "receipt_supervisor_reconcile_v1" : "receipt_supervisor_observe_v1";
      if (operational) { args.p_action = action; args.p_payload = envelope.payload; }
      else if (action === "reconcile") args.p_target_request_id = envelope.payload.target_request_id;
      else args.p_action = action;
      const result = await rpc(name, args);
      const valid = operational
        ? validateOperationResult(result, envelope.principal_id, envelope.request_id, action as OperationAction, envelope.payload)
        : validateSupervisorResult(result, envelope.principal_id, envelope.request_id, action as Action, envelope.payload);
      if (operational) {
        if (!valid || !object(result) || (action !== "reconcile_request" &&
            (!utc(result.observed_at) || Date.parse(result.observed_at) < Date.parse(envelope.issued_at) - 10000 || Date.parse(result.observed_at) > now() + 10000)) ||
            (action === "prove_key" && result.expires_at !== key.expires_at) ||
            (action === "begin_run" && result.ok === true && (!utc(result.expires_at) || Date.parse(result.expires_at) > Date.parse(key.expires_at))) ||
            (action === "reconcile_request" && object(result.receipt) && (!utc(result.receipt.observed_at) || Date.parse(result.receipt.observed_at) > now() + 10000))) throw new Refusal(502, "SUPERVISOR_OUTCOME_UNKNOWN");
      } else if (!valid || !object(result) ||
        (action !== "reconcile" && (result.expires_at !== key.expires_at ||
          Date.parse(result.observed_at as string) < Date.parse(envelope.issued_at) - 10000 ||
          Date.parse(result.observed_at as string) > now() + 10000)) ||
        (action === "reconcile" && object(result.receipt) &&
          (result.receipt.expires_at !== key.expires_at ||
            Date.parse(result.receipt.observed_at as string) > now() + 10000))) {
        throw new Refusal(502, "SUPERVISOR_OUTCOME_UNKNOWN");
      }
      return response(200, {contract_version: operational ? 2 : 1, principal_id: envelope.principal_id,
        request_id: envelope.request_id, action, result});
    } catch (error) {
      if (error instanceof Refusal) return response(error.status, {ok: false, code: error.code});
      return response(503, {ok: false, code: authenticated
        ? "SUPERVISOR_OUTCOME_UNKNOWN" : "SUPERVISOR_AUTH_UNAVAILABLE"});
    }
  };
}
import { operationActions, validateOperationPayload, validateOperationResult, type OperationAction } from "./operations_contract.ts";
