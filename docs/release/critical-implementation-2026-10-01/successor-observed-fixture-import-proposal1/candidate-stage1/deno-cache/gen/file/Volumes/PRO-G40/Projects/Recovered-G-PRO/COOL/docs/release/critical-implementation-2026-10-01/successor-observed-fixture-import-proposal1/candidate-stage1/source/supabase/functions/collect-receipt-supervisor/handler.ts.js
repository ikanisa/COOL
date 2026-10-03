const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HASH = /^[0-9a-f]{64}$/;
class Refusal extends Error {
  status;
  code;
  constructor(status, code){
    super(code);
    this.status = status;
    this.code = code;
  }
}
function object(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function keys(value, expected) {
  return object(value) && Object.keys(value).length === expected.length && expected.every((k)=>Object.hasOwn(value, k));
}
function uuid(value) {
  return typeof value === "string" && UUID.test(value);
}
function hash(value) {
  return typeof value === "string" && HASH.test(value);
}
function integer(value, min, max) {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max;
}
function utc(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(value)) return false;
  const ms = Date.parse(value);
  return Number.isFinite(ms) && new Date(ms).toISOString().slice(0, 19) === value.slice(0, 19);
}
function require(condition) {
  if (!condition) throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID");
}
function base64(value, max) {
  require(typeof value === "string" && value.length <= max && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value));
  let decoded;
  try {
    decoded = atob(value);
  } catch  {
    throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID");
  }
  require(btoa(decoded) === value);
  return Uint8Array.from(decoded, (c)=>c.charCodeAt(0));
}
function hex(bytes) {
  return Array.from(bytes, (b)=>b.toString(16).padStart(2, "0")).join("");
}
async function digest(bytes) {
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes))));
}
// Android emits canonical DER; WebCrypto expects fixed-width P1363 r||s.
export function derToP1363(der) {
  require(der.length >= 8 && der.length <= 72 && der[0] === 0x30 && der[1] === der.length - 2);
  let offset = 2;
  const output = new Uint8Array(64);
  for(let component = 0; component < 2; component++){
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
    require(number > 0n && number < 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n);
    output.set(value, component * 32 + 32 - value.length);
  }
  require(offset === der.length);
  return output;
}
// Reject duplicate keys before JSON.parse loses them; impose a shallow bound.
function parseStrict(text) {
  let at = 0;
  const ws = ()=>{
    while(/[\t\n\r ]/.test(text[at] ?? "x"))at++;
  };
  const string = ()=>{
    require(text[at] === '"');
    const start = at++;
    while(at < text.length){
      if (text[at++] === "\\") {
        at++;
        continue;
      }
      if (text[at - 1] === '"') {
        try {
          return JSON.parse(text.slice(start, at));
        } catch  {
          throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID");
        }
      }
    }
    throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID");
  };
  const value = (depth)=>{
    require(depth <= 8);
    ws();
    if (text[at] === "{") {
      at++;
      ws();
      const seen = new Set();
      if (text[at] === "}") {
        at++;
        return;
      }
      while(true){
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
      while(true){
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
      const token = /^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(text.slice(at));
      require(token);
      at += token[0].length;
    }
  };
  value(0);
  ws();
  require(at === text.length);
  try {
    return JSON.parse(text);
  } catch  {
    throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID");
  }
}
async function body(request, timeout) {
  require(/^application\/json(?:;\s*charset=utf-8)?$/i.test(request.headers.get("content-type") ?? ""));
  require(!request.headers.has("content-encoding"));
  const length = request.headers.get("content-length");
  if (length !== null) require(/^\d+$/.test(length) && Number(length) <= 8192);
  require(request.body);
  const reader = request.body.getReader();
  const chunks = [];
  let count = 0;
  const deadline = Date.now() + timeout;
  try {
    while(true){
      let timer;
      const chunk = await Promise.race([
        reader.read(),
        new Promise((_, reject)=>{
          timer = setTimeout(()=>{
            reader.cancel().catch(()=>{});
            reject(new Refusal(408, "SUPERVISOR_REQUEST_INVALID"));
          }, Math.max(1, deadline - Date.now()));
        })
      ]).finally(()=>{
        if (timer !== undefined) clearTimeout(timer);
      });
      if (chunk.done) break;
      count += chunk.value.length;
      if (count > 8192) {
        await reader.cancel().catch(()=>{});
        throw new Refusal(413, "SUPERVISOR_BODY_TOO_LARGE");
      }
      chunks.push(chunk.value);
    }
  } finally{
    reader.releaseLock();
  }
  require(count > 0 && (length === null || Number(length) === count));
  const result = new Uint8Array(count);
  let offset = 0;
  for (const chunk of chunks){
    result.set(chunk, offset);
    offset += chunk.length;
  }
  require(!(result[0] === 0xef && result[1] === 0xbb && result[2] === 0xbf));
  return result;
}
const AUDIENCE = "collect.receipt-supervisor.v1/lhbowpbcpwoiparwnwgt";
function payload(action, value) {
  if (action === "reconcile") {
    require(keys(value, [
      "target_request_id"
    ]) && uuid(value.target_request_id));
  } else require(keys(value, []));
}
function observation(value, principal, request, action) {
  const base = [
    "contract_version",
    "principal_id",
    "request_id",
    "action",
    "observed_at",
    "expires_at",
    "scope",
    "mode",
    "business_handled",
    "financial_action",
    "send_action"
  ];
  if (!object(value)) return false;
  const expected = value.action === "shadow_health" ? [
    ...base,
    "sample_valid_until",
    "queued_count",
    "unknown_count",
    "failed_no_send_count",
    "dispatch_enabled"
  ] : base;
  if (!keys(value, expected) || value.contract_version !== 1 || value.principal_id !== principal || value.request_id !== request || ![
    "prove_key",
    "shadow_health"
  ].includes(value.action) || action !== undefined && value.action !== action || !utc(value.observed_at) || !utc(value.expires_at) || Date.parse(value.expires_at) <= Date.parse(value.observed_at) || value.scope !== "rw_receipt_shadow" || value.mode !== "Shadow" || value.business_handled !== false || value.financial_action !== false || value.send_action !== false) return false;
  if (value.action === "shadow_health") {
    if (!utc(value.sample_valid_until) || Date.parse(value.sample_valid_until) <= Date.parse(value.observed_at) || Date.parse(value.sample_valid_until) > Date.parse(value.observed_at) + 60000 || Date.parse(value.sample_valid_until) > Date.parse(value.expires_at) || !integer(value.queued_count, 0, 1e9) || !integer(value.unknown_count, 0, 1e9) || !integer(value.failed_no_send_count, 0, 1e9) || typeof value.dispatch_enabled !== "boolean") return false;
  }
  return true;
}
export function validateSupervisorResult(value, principal, request, action, p) {
  if (action !== "reconcile") return observation(value, principal, request, action);
  if (!keys(value, [
    "contract_version",
    "target_request_id",
    "status",
    "receipt"
  ]) || value.contract_version !== 1 || value.target_request_id !== p.target_request_id || ![
    "recorded",
    "not_recorded",
    "in_progress"
  ].includes(value.status)) return false;
  if (value.status === "recorded") {
    return observation(value.receipt, principal, p.target_request_id);
  }
  return value.receipt === null;
}
function response(status, value) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
      "referrer-policy": "no-referrer"
    }
  });
}
/** Exact signed bytes, fixed audience and three narrowly scoped actions.
 * DB authority is rechecked after signature validation and request lock waits. */ export function createSupervisorHandler(dependencies) {
  const now = dependencies.now ?? Date.now;
  const timeout = Math.min(15000, Math.max(1, dependencies.timeoutMs ?? 5000));
  return async (request)=>{
    let authenticated = false;
    let operational = false;
    const started = Date.now();
    const rpc = async (name, args)=>{
      const remaining = timeout - (Date.now() - started);
      if (remaining <= 0) throw new Refusal(503, authenticated ? "SUPERVISOR_OUTCOME_UNKNOWN" : "SUPERVISOR_AUTH_UNAVAILABLE");
      const controller = new AbortController();
      let timer;
      try {
        const r = await Promise.race([
          dependencies.rpc(name, args, controller.signal),
          new Promise((_, reject)=>{
            timer = setTimeout(()=>{
              controller.abort();
              reject(new Refusal(503, authenticated ? "SUPERVISOR_OUTCOME_UNKNOWN" : "SUPERVISOR_AUTH_UNAVAILABLE"));
            }, remaining);
          })
        ]);
        if (r.error) {
          if (r.error.code === "55P03") throw new Refusal(409, "SUPERVISOR_AUTHORITY_BUSY");
          if (r.error.code === "42501") throw new Refusal(403, "SUPERVISOR_AUTHORITY_REFUSED");
          if (r.error.code === "22023" || r.error.code === "23505") {
            throw new Refusal(409, "SUPERVISOR_REQUEST_REFUSED");
          }
          if (operational && [
            "55000",
            "40001"
          ].includes(r.error.code ?? "")) throw new Refusal(409, "SUPERVISOR_REQUEST_REFUSED");
          throw new Refusal(503, authenticated ? "SUPERVISOR_OUTCOME_UNKNOWN" : "SUPERVISOR_AUTH_UNAVAILABLE");
        }
        return r.data;
      } finally{
        if (timer !== undefined) clearTimeout(timer);
      }
    };
    try {
      if (request.method !== "POST") throw new Refusal(405, "SUPERVISOR_METHOD_REFUSED");
      require(new URL(request.url).search === "");
      const raw = await body(request, timeout);
      let text;
      try {
        text = new TextDecoder("utf-8", {
          fatal: true
        }).decode(raw);
      } catch  {
        throw new Refusal(400, "SUPERVISOR_REQUEST_INVALID");
      }
      const envelope = parseStrict(text);
      require(keys(envelope, [
        "contract_version",
        "audience",
        "action",
        "principal_id",
        "request_id",
        "issued_at",
        "payload"
      ]));
      operational = envelope.contract_version === 2;
      require(operational ? envelope.audience === "collect.receipt-supervisor.v2/lhbowpbcpwoiparwnwgt" && operationActions.includes(envelope.action) : envelope.contract_version === 1 && envelope.audience === AUDIENCE && [
        "prove_key",
        "shadow_health",
        "reconcile"
      ].includes(envelope.action));
      require(uuid(envelope.principal_id) && uuid(envelope.request_id) && utc(envelope.issued_at));
      require(Date.parse(envelope.issued_at) >= now() - 30000 && Date.parse(envelope.issued_at) <= now() + 10000);
      const action = envelope.action;
      if (operational) require(validateOperationPayload(action, envelope.payload));
      else payload(action, envelope.payload);
      const keyHash = request.headers.get("X-Collect-Supervisor-Key-Id");
      require(hash(keyHash));
      const signature = derToP1363(base64(request.headers.get("X-Collect-Supervisor-Signature"), 100));
      const key = await rpc("receipt_supervisor_key_v1", {
        p_principal_id: envelope.principal_id
      });
      if (!keys(key, [
        "contract_version",
        "principal_id",
        "state",
        "scope",
        "public_key_spki_base64",
        "key_sha256",
        "expires_at"
      ]) || key.contract_version !== 1 || key.principal_id !== envelope.principal_id || key.scope !== (operational ? "rw_receipt_operations" : "rw_receipt_shadow") || ![
        "pending",
        "active"
      ].includes(key.state) || !utc(key.expires_at) || Date.parse(key.expires_at) <= now() || key.key_sha256 !== keyHash) {
        throw new Refusal(401, "SUPERVISOR_KEY_REFUSED");
      }
      let spki;
      try {
        spki = base64(key.public_key_spki_base64, 124);
      } catch  {
        throw new Refusal(401, "SUPERVISOR_KEY_REFUSED");
      }
      if (spki.length !== 91 || await digest(spki) !== keyHash) {
        throw new Refusal(401, "SUPERVISOR_KEY_REFUSED");
      }
      let verified = false;
      try {
        const imported = await crypto.subtle.importKey("spki", new Uint8Array(spki), {
          name: "ECDSA",
          namedCurve: "P-256"
        }, false, [
          "verify"
        ]);
        verified = await crypto.subtle.verify({
          name: "ECDSA",
          hash: "SHA-256"
        }, imported, new Uint8Array(signature), new Uint8Array(raw));
      } catch  {
        verified = false;
      }
      if (!verified) throw new Refusal(401, "SUPERVISOR_SIGNATURE_REFUSED");
      authenticated = true;
      if (action !== "prove_key" && key.state !== "active") {
        throw new Refusal(403, "SUPERVISOR_PRINCIPAL_PENDING");
      }
      const args = {
        p_principal_id: envelope.principal_id,
        p_request_id: envelope.request_id,
        p_key_sha256: keyHash,
        p_request_sha256: await digest(raw),
        p_issued_at: envelope.issued_at
      };
      const name = operational ? "receipt_operations_execute_v2" : action === "reconcile" ? "receipt_supervisor_reconcile_v1" : "receipt_supervisor_observe_v1";
      if (operational) {
        args.p_action = action;
        args.p_payload = envelope.payload;
      } else if (action === "reconcile") args.p_target_request_id = envelope.payload.target_request_id;
      else args.p_action = action;
      const result = await rpc(name, args);
      const valid = operational ? validateOperationResult(result, envelope.principal_id, envelope.request_id, action, envelope.payload) : validateSupervisorResult(result, envelope.principal_id, envelope.request_id, action, envelope.payload);
      if (operational) {
        if (!valid || !object(result) || action !== "reconcile_request" && (!utc(result.observed_at) || Date.parse(result.observed_at) < Date.parse(envelope.issued_at) - 10000 || Date.parse(result.observed_at) > now() + 10000) || action === "prove_key" && result.expires_at !== key.expires_at || action === "begin_run" && result.ok === true && (!utc(result.expires_at) || Date.parse(result.expires_at) > Date.parse(key.expires_at)) || action === "reconcile_request" && object(result.receipt) && (!utc(result.receipt.observed_at) || Date.parse(result.receipt.observed_at) > now() + 10000)) throw new Refusal(502, "SUPERVISOR_OUTCOME_UNKNOWN");
      } else if (!valid || !object(result) || action !== "reconcile" && (result.expires_at !== key.expires_at || Date.parse(result.observed_at) < Date.parse(envelope.issued_at) - 10000 || Date.parse(result.observed_at) > now() + 10000) || action === "reconcile" && object(result.receipt) && (result.receipt.expires_at !== key.expires_at || Date.parse(result.receipt.observed_at) > now() + 10000)) {
        throw new Refusal(502, "SUPERVISOR_OUTCOME_UNKNOWN");
      }
      return response(200, {
        contract_version: operational ? 2 : 1,
        principal_id: envelope.principal_id,
        request_id: envelope.request_id,
        action,
        result
      });
    } catch (error) {
      if (error instanceof Refusal) return response(error.status, {
        ok: false,
        code: error.code
      });
      return response(503, {
        ok: false,
        code: authenticated ? "SUPERVISOR_OUTCOME_UNKNOWN" : "SUPERVISOR_AUTH_UNAVAILABLE"
      });
    }
  };
}
import { operationActions, validateOperationPayload, validateOperationResult } from "./operations_contract.ts";
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtcmVjZWlwdC1zdXBlcnZpc29yL2hhbmRsZXIudHMiXSwic291cmNlc0NvbnRlbnQiOlsidHlwZSBKc29uID0gUmVjb3JkPHN0cmluZywgdW5rbm93bj47XG50eXBlIEFjdGlvbiA9IFwicHJvdmVfa2V5XCIgfCBcInNoYWRvd19oZWFsdGhcIiB8IFwicmVjb25jaWxlXCI7XG5leHBvcnQgaW50ZXJmYWNlIFN1cGVydmlzb3JEZXBlbmRlbmNpZXMge1xuICBycGMoXG4gICAgbmFtZTogc3RyaW5nLFxuICAgIGFyZ3M6IEpzb24sXG4gICAgc2lnbmFsOiBBYm9ydFNpZ25hbCxcbiAgKTogUHJvbWlzZTx7IGRhdGE6IHVua25vd247IGVycm9yOiB7IGNvZGU/OiBzdHJpbmcgfSB8IG51bGwgfT47XG4gIG5vdz86ICgpID0+IG51bWJlcjtcbiAgdGltZW91dE1zPzogbnVtYmVyO1xufVxuY29uc3QgVVVJRCA9IC9eWzAtOWEtZl17OH0tWzAtOWEtZl17NH0tWzAtOWEtZl17NH0tWzAtOWEtZl17NH0tWzAtOWEtZl17MTJ9JC87XG5jb25zdCBIQVNIID0gL15bMC05YS1mXXs2NH0kLztcbmNsYXNzIFJlZnVzYWwgZXh0ZW5kcyBFcnJvciB7XG4gIHJlYWRvbmx5IHN0YXR1czogbnVtYmVyO1xuICByZWFkb25seSBjb2RlOiBzdHJpbmc7XG4gIGNvbnN0cnVjdG9yKHN0YXR1czogbnVtYmVyLCBjb2RlOiBzdHJpbmcpIHtcbiAgICBzdXBlcihjb2RlKTtcbiAgICB0aGlzLnN0YXR1cyA9IHN0YXR1cztcbiAgICB0aGlzLmNvZGUgPSBjb2RlO1xuICB9XG59XG5mdW5jdGlvbiBvYmplY3QodmFsdWU6IHVua25vd24pOiB2YWx1ZSBpcyBKc29uIHtcbiAgcmV0dXJuIHR5cGVvZiB2YWx1ZSA9PT0gXCJvYmplY3RcIiAmJiB2YWx1ZSAhPT0gbnVsbCAmJiAhQXJyYXkuaXNBcnJheSh2YWx1ZSk7XG59XG5mdW5jdGlvbiBrZXlzKHZhbHVlOiB1bmtub3duLCBleHBlY3RlZDogc3RyaW5nW10pOiB2YWx1ZSBpcyBKc29uIHtcbiAgcmV0dXJuIG9iamVjdCh2YWx1ZSkgJiYgT2JqZWN0LmtleXModmFsdWUpLmxlbmd0aCA9PT0gZXhwZWN0ZWQubGVuZ3RoICYmXG4gICAgZXhwZWN0ZWQuZXZlcnkoKGspID0+IE9iamVjdC5oYXNPd24odmFsdWUsIGspKTtcbn1cbmZ1bmN0aW9uIHV1aWQodmFsdWU6IHVua25vd24pOiB2YWx1ZSBpcyBzdHJpbmcge1xuICByZXR1cm4gdHlwZW9mIHZhbHVlID09PSBcInN0cmluZ1wiICYmIFVVSUQudGVzdCh2YWx1ZSk7XG59XG5mdW5jdGlvbiBoYXNoKHZhbHVlOiB1bmtub3duKTogdmFsdWUgaXMgc3RyaW5nIHtcbiAgcmV0dXJuIHR5cGVvZiB2YWx1ZSA9PT0gXCJzdHJpbmdcIiAmJiBIQVNILnRlc3QodmFsdWUpO1xufVxuZnVuY3Rpb24gaW50ZWdlcih2YWx1ZTogdW5rbm93biwgbWluOiBudW1iZXIsIG1heDogbnVtYmVyKTogdmFsdWUgaXMgbnVtYmVyIHtcbiAgcmV0dXJuIHR5cGVvZiB2YWx1ZSA9PT0gXCJudW1iZXJcIiAmJiBOdW1iZXIuaXNTYWZlSW50ZWdlcih2YWx1ZSkgJiZcbiAgICB2YWx1ZSA+PSBtaW4gJiYgdmFsdWUgPD0gbWF4O1xufVxuZnVuY3Rpb24gdXRjKHZhbHVlOiB1bmtub3duKTogdmFsdWUgaXMgc3RyaW5nIHtcbiAgaWYgKFxuICAgIHR5cGVvZiB2YWx1ZSAhPT0gXCJzdHJpbmdcIiB8fFxuICAgICEvXlxcZHs0fS1cXGR7Mn0tXFxkezJ9VFxcZHsyfTpcXGR7Mn06XFxkezJ9KFxcLlxcZHsxLDZ9KT9aJC8udGVzdCh2YWx1ZSlcbiAgKSByZXR1cm4gZmFsc2U7XG4gIGNvbnN0IG1zID0gRGF0ZS5wYXJzZSh2YWx1ZSk7XG4gIHJldHVybiBOdW1iZXIuaXNGaW5pdGUobXMpICYmXG4gICAgbmV3IERhdGUobXMpLnRvSVNPU3RyaW5nKCkuc2xpY2UoMCwgMTkpID09PSB2YWx1ZS5zbGljZSgwLCAxOSk7XG59XG5mdW5jdGlvbiByZXF1aXJlKGNvbmRpdGlvbjogdW5rbm93bik6IGFzc2VydHMgY29uZGl0aW9uIHtcbiAgaWYgKCFjb25kaXRpb24pIHRocm93IG5ldyBSZWZ1c2FsKDQwMCwgXCJTVVBFUlZJU09SX1JFUVVFU1RfSU5WQUxJRFwiKTtcbn1cbmZ1bmN0aW9uIGJhc2U2NCh2YWx1ZTogdW5rbm93biwgbWF4OiBudW1iZXIpOiBVaW50OEFycmF5IHtcbiAgcmVxdWlyZShcbiAgICB0eXBlb2YgdmFsdWUgPT09IFwic3RyaW5nXCIgJiYgdmFsdWUubGVuZ3RoIDw9IG1heCAmJlxuICAgICAgL14oPzpbQS1aYS16MC05Ky9dezR9KSooPzpbQS1aYS16MC05Ky9dezJ9PT18W0EtWmEtejAtOSsvXXszfT0pPyQvLnRlc3QoXG4gICAgICAgIHZhbHVlLFxuICAgICAgKSxcbiAgKTtcbiAgbGV0IGRlY29kZWQ6IHN0cmluZztcbiAgdHJ5IHtcbiAgICBkZWNvZGVkID0gYXRvYih2YWx1ZSk7XG4gIH0gY2F0Y2gge1xuICAgIHRocm93IG5ldyBSZWZ1c2FsKDQwMCwgXCJTVVBFUlZJU09SX1JFUVVFU1RfSU5WQUxJRFwiKTtcbiAgfVxuICByZXF1aXJlKGJ0b2EoZGVjb2RlZCkgPT09IHZhbHVlKTtcbiAgcmV0dXJuIFVpbnQ4QXJyYXkuZnJvbShkZWNvZGVkLCAoYykgPT4gYy5jaGFyQ29kZUF0KDApKTtcbn1cbmZ1bmN0aW9uIGhleChieXRlczogVWludDhBcnJheSk6IHN0cmluZyB7XG4gIHJldHVybiBBcnJheS5mcm9tKGJ5dGVzLCAoYikgPT4gYi50b1N0cmluZygxNikucGFkU3RhcnQoMiwgXCIwXCIpKS5qb2luKFwiXCIpO1xufVxuYXN5bmMgZnVuY3Rpb24gZGlnZXN0KGJ5dGVzOiBVaW50OEFycmF5KTogUHJvbWlzZTxzdHJpbmc+IHtcbiAgcmV0dXJuIGhleChcbiAgICBuZXcgVWludDhBcnJheShcbiAgICAgIGF3YWl0IGNyeXB0by5zdWJ0bGUuZGlnZXN0KFwiU0hBLTI1NlwiLCBuZXcgVWludDhBcnJheShieXRlcykpLFxuICAgICksXG4gICk7XG59XG4vLyBBbmRyb2lkIGVtaXRzIGNhbm9uaWNhbCBERVI7IFdlYkNyeXB0byBleHBlY3RzIGZpeGVkLXdpZHRoIFAxMzYzIHJ8fHMuXG5leHBvcnQgZnVuY3Rpb24gZGVyVG9QMTM2MyhkZXI6IFVpbnQ4QXJyYXkpOiBVaW50OEFycmF5IHtcbiAgcmVxdWlyZShcbiAgICBkZXIubGVuZ3RoID49IDggJiYgZGVyLmxlbmd0aCA8PSA3MiAmJiBkZXJbMF0gPT09IDB4MzAgJiZcbiAgICAgIGRlclsxXSA9PT0gZGVyLmxlbmd0aCAtIDIsXG4gICk7XG4gIGxldCBvZmZzZXQgPSAyO1xuICBjb25zdCBvdXRwdXQgPSBuZXcgVWludDhBcnJheSg2NCk7XG4gIGZvciAobGV0IGNvbXBvbmVudCA9IDA7IGNvbXBvbmVudCA8IDI7IGNvbXBvbmVudCsrKSB7XG4gICAgcmVxdWlyZShkZXJbb2Zmc2V0KytdID09PSAweDAyKTtcbiAgICBjb25zdCBzaXplID0gZGVyW29mZnNldCsrXTtcbiAgICByZXF1aXJlKHR5cGVvZiBzaXplID09PSBcIm51bWJlclwiICYmIHNpemUgPj0gMSAmJiBzaXplIDw9IDMzICYmIG9mZnNldCArIHNpemUgPD0gZGVyLmxlbmd0aCk7XG4gICAgbGV0IHZhbHVlID0gZGVyLnNsaWNlKG9mZnNldCwgb2Zmc2V0ICsgc2l6ZSk7XG4gICAgb2Zmc2V0ICs9IHNpemU7XG4gICAgcmVxdWlyZSh2YWx1ZVswXSAhPT0gdW5kZWZpbmVkICYmICEodmFsdWVbMF0gJiAweDgwKSk7XG4gICAgcmVxdWlyZSh2YWx1ZS5sZW5ndGggPT09IDEgfHwgdmFsdWVbMF0gIT09IDAgfHwgISEoKHZhbHVlWzFdID8/IDApICYgMHg4MCkpO1xuICAgIGlmICh2YWx1ZVswXSA9PT0gMCkgdmFsdWUgPSB2YWx1ZS5zbGljZSgxKTtcbiAgICByZXF1aXJlKHZhbHVlLmxlbmd0aCA8PSAzMiAmJiB2YWx1ZS5sZW5ndGggPiAwKTtcbiAgICBjb25zdCBudW1iZXIgPSBCaWdJbnQoXCIweFwiICsgaGV4KHZhbHVlKSk7XG4gICAgcmVxdWlyZShcbiAgICAgIG51bWJlciA+IDBuICYmXG4gICAgICAgIG51bWJlciA8XG4gICAgICAgICAgMHhmZmZmZmZmZjAwMDAwMDAwZmZmZmZmZmZmZmZmZmZmZmJjZTZmYWFkYTcxNzllODRmM2I5Y2FjMmZjNjMyNTUxbixcbiAgICApO1xuICAgIG91dHB1dC5zZXQodmFsdWUsIGNvbXBvbmVudCAqIDMyICsgMzIgLSB2YWx1ZS5sZW5ndGgpO1xuICB9XG4gIHJlcXVpcmUob2Zmc2V0ID09PSBkZXIubGVuZ3RoKTtcbiAgcmV0dXJuIG91dHB1dDtcbn1cbi8vIFJlamVjdCBkdXBsaWNhdGUga2V5cyBiZWZvcmUgSlNPTi5wYXJzZSBsb3NlcyB0aGVtOyBpbXBvc2UgYSBzaGFsbG93IGJvdW5kLlxuZnVuY3Rpb24gcGFyc2VTdHJpY3QodGV4dDogc3RyaW5nKTogdW5rbm93biB7XG4gIGxldCBhdCA9IDA7XG4gIGNvbnN0IHdzID0gKCkgPT4ge1xuICAgIHdoaWxlICgvW1xcdFxcblxcciBdLy50ZXN0KHRleHRbYXRdID8/IFwieFwiKSkgYXQrKztcbiAgfTtcbiAgY29uc3Qgc3RyaW5nID0gKCk6IHN0cmluZyA9PiB7XG4gICAgcmVxdWlyZSh0ZXh0W2F0XSA9PT0gJ1wiJyk7XG4gICAgY29uc3Qgc3RhcnQgPSBhdCsrO1xuICAgIHdoaWxlIChhdCA8IHRleHQubGVuZ3RoKSB7XG4gICAgICBpZiAodGV4dFthdCsrXSA9PT0gXCJcXFxcXCIpIHtcbiAgICAgICAgYXQrKztcbiAgICAgICAgY29udGludWU7XG4gICAgICB9XG4gICAgICBpZiAodGV4dFthdCAtIDFdID09PSAnXCInKSB7XG4gICAgICAgIHRyeSB7IHJldHVybiBKU09OLnBhcnNlKHRleHQuc2xpY2Uoc3RhcnQsIGF0KSk7IH1cbiAgICAgICAgY2F0Y2ggeyB0aHJvdyBuZXcgUmVmdXNhbCg0MDAsIFwiU1VQRVJWSVNPUl9SRVFVRVNUX0lOVkFMSURcIik7IH1cbiAgICAgIH1cbiAgICB9XG4gICAgdGhyb3cgbmV3IFJlZnVzYWwoNDAwLCBcIlNVUEVSVklTT1JfUkVRVUVTVF9JTlZBTElEXCIpO1xuICB9O1xuICBjb25zdCB2YWx1ZSA9IChkZXB0aDogbnVtYmVyKTogdm9pZCA9PiB7XG4gICAgcmVxdWlyZShkZXB0aCA8PSA4KTtcbiAgICB3cygpO1xuICAgIGlmICh0ZXh0W2F0XSA9PT0gXCJ7XCIpIHtcbiAgICAgIGF0Kys7XG4gICAgICB3cygpO1xuICAgICAgY29uc3Qgc2VlbiA9IG5ldyBTZXQ8c3RyaW5nPigpO1xuICAgICAgaWYgKHRleHRbYXRdID09PSBcIn1cIikge1xuICAgICAgICBhdCsrO1xuICAgICAgICByZXR1cm47XG4gICAgICB9XG4gICAgICB3aGlsZSAodHJ1ZSkge1xuICAgICAgICB3cygpO1xuICAgICAgICBjb25zdCBrZXkgPSBzdHJpbmcoKTtcbiAgICAgICAgcmVxdWlyZSghc2Vlbi5oYXMoa2V5KSk7XG4gICAgICAgIHNlZW4uYWRkKGtleSk7XG4gICAgICAgIHdzKCk7XG4gICAgICAgIHJlcXVpcmUodGV4dFthdCsrXSA9PT0gXCI6XCIpO1xuICAgICAgICB2YWx1ZShkZXB0aCArIDEpO1xuICAgICAgICB3cygpO1xuICAgICAgICBpZiAodGV4dFthdF0gPT09IFwifVwiKSB7XG4gICAgICAgICAgYXQrKztcbiAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cbiAgICAgICAgcmVxdWlyZSh0ZXh0W2F0KytdID09PSBcIixcIik7XG4gICAgICB9XG4gICAgfSBlbHNlIGlmICh0ZXh0W2F0XSA9PT0gXCJbXCIpIHtcbiAgICAgIGF0Kys7XG4gICAgICB3cygpO1xuICAgICAgaWYgKHRleHRbYXRdID09PSBcIl1cIikge1xuICAgICAgICBhdCsrO1xuICAgICAgICByZXR1cm47XG4gICAgICB9XG4gICAgICB3aGlsZSAodHJ1ZSkge1xuICAgICAgICB2YWx1ZShkZXB0aCArIDEpO1xuICAgICAgICB3cygpO1xuICAgICAgICBpZiAodGV4dFthdF0gPT09IFwiXVwiKSB7XG4gICAgICAgICAgYXQrKztcbiAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cbiAgICAgICAgcmVxdWlyZSh0ZXh0W2F0KytdID09PSBcIixcIik7XG4gICAgICB9XG4gICAgfSBlbHNlIGlmICh0ZXh0W2F0XSA9PT0gJ1wiJykgc3RyaW5nKCk7XG4gICAgZWxzZSB7XG4gICAgICBjb25zdCB0b2tlbiA9XG4gICAgICAgIC9eKD86dHJ1ZXxmYWxzZXxudWxsfC0/KD86MHxbMS05XVxcZCopKD86XFwuXFxkKyk/KD86W2VFXVsrLV0/XFxkKyk/KS8uZXhlYyhcbiAgICAgICAgICB0ZXh0LnNsaWNlKGF0KSxcbiAgICAgICAgKTtcbiAgICAgIHJlcXVpcmUodG9rZW4pO1xuICAgICAgYXQgKz0gdG9rZW5bMF0ubGVuZ3RoO1xuICAgIH1cbiAgfTtcbiAgdmFsdWUoMCk7XG4gIHdzKCk7XG4gIHJlcXVpcmUoYXQgPT09IHRleHQubGVuZ3RoKTtcbiAgdHJ5IHtcbiAgICByZXR1cm4gSlNPTi5wYXJzZSh0ZXh0KTtcbiAgfSBjYXRjaCB7XG4gICAgdGhyb3cgbmV3IFJlZnVzYWwoNDAwLCBcIlNVUEVSVklTT1JfUkVRVUVTVF9JTlZBTElEXCIpO1xuICB9XG59XG5hc3luYyBmdW5jdGlvbiBib2R5KHJlcXVlc3Q6IFJlcXVlc3QsIHRpbWVvdXQ6IG51bWJlcik6IFByb21pc2U8VWludDhBcnJheT4ge1xuICByZXF1aXJlKFxuICAgIC9eYXBwbGljYXRpb25cXC9qc29uKD86O1xccypjaGFyc2V0PXV0Zi04KT8kL2kudGVzdChcbiAgICAgIHJlcXVlc3QuaGVhZGVycy5nZXQoXCJjb250ZW50LXR5cGVcIikgPz8gXCJcIixcbiAgICApLFxuICApO1xuICByZXF1aXJlKCFyZXF1ZXN0LmhlYWRlcnMuaGFzKFwiY29udGVudC1lbmNvZGluZ1wiKSk7XG4gIGNvbnN0IGxlbmd0aCA9IHJlcXVlc3QuaGVhZGVycy5nZXQoXCJjb250ZW50LWxlbmd0aFwiKTtcbiAgaWYgKGxlbmd0aCAhPT0gbnVsbCkgcmVxdWlyZSgvXlxcZCskLy50ZXN0KGxlbmd0aCkgJiYgTnVtYmVyKGxlbmd0aCkgPD0gODE5Mik7XG4gIHJlcXVpcmUocmVxdWVzdC5ib2R5KTtcbiAgY29uc3QgcmVhZGVyID0gcmVxdWVzdC5ib2R5LmdldFJlYWRlcigpO1xuICBjb25zdCBjaHVua3M6IFVpbnQ4QXJyYXlbXSA9IFtdO1xuICBsZXQgY291bnQgPSAwO1xuICBjb25zdCBkZWFkbGluZSA9IERhdGUubm93KCkgKyB0aW1lb3V0O1xuICB0cnkge1xuICAgIHdoaWxlICh0cnVlKSB7XG4gICAgICBsZXQgdGltZXI6IFJldHVyblR5cGU8dHlwZW9mIHNldFRpbWVvdXQ+IHwgdW5kZWZpbmVkO1xuICAgICAgY29uc3QgY2h1bmsgPSBhd2FpdCBQcm9taXNlLnJhY2UoW1xuICAgICAgICByZWFkZXIucmVhZCgpLFxuICAgICAgICBuZXcgUHJvbWlzZTxuZXZlcj4oKF8sIHJlamVjdCkgPT4ge1xuICAgICAgICAgIHRpbWVyID0gc2V0VGltZW91dCgoKSA9PiB7XG4gICAgICAgICAgICByZWFkZXIuY2FuY2VsKCkuY2F0Y2goKCkgPT4ge30pO1xuICAgICAgICAgICAgcmVqZWN0KG5ldyBSZWZ1c2FsKDQwOCwgXCJTVVBFUlZJU09SX1JFUVVFU1RfSU5WQUxJRFwiKSk7XG4gICAgICAgICAgfSwgTWF0aC5tYXgoMSwgZGVhZGxpbmUgLSBEYXRlLm5vdygpKSk7XG4gICAgICAgIH0pLFxuICAgICAgXSkuZmluYWxseSgoKSA9PiB7XG4gICAgICAgIGlmICh0aW1lciAhPT0gdW5kZWZpbmVkKSBjbGVhclRpbWVvdXQodGltZXIpO1xuICAgICAgfSk7XG4gICAgICBpZiAoY2h1bmsuZG9uZSkgYnJlYWs7XG4gICAgICBjb3VudCArPSBjaHVuay52YWx1ZS5sZW5ndGg7XG4gICAgICBpZiAoY291bnQgPiA4MTkyKSB7XG4gICAgICAgIGF3YWl0IHJlYWRlci5jYW5jZWwoKS5jYXRjaCgoKSA9PiB7fSk7XG4gICAgICAgIHRocm93IG5ldyBSZWZ1c2FsKDQxMywgXCJTVVBFUlZJU09SX0JPRFlfVE9PX0xBUkdFXCIpO1xuICAgICAgfVxuICAgICAgY2h1bmtzLnB1c2goY2h1bmsudmFsdWUpO1xuICAgIH1cbiAgfSBmaW5hbGx5IHtcbiAgICByZWFkZXIucmVsZWFzZUxvY2soKTtcbiAgfVxuICByZXF1aXJlKGNvdW50ID4gMCAmJiAobGVuZ3RoID09PSBudWxsIHx8IE51bWJlcihsZW5ndGgpID09PSBjb3VudCkpO1xuICBjb25zdCByZXN1bHQgPSBuZXcgVWludDhBcnJheShjb3VudCk7XG4gIGxldCBvZmZzZXQgPSAwO1xuICBmb3IgKGNvbnN0IGNodW5rIG9mIGNodW5rcykge1xuICAgIHJlc3VsdC5zZXQoY2h1bmssIG9mZnNldCk7XG4gICAgb2Zmc2V0ICs9IGNodW5rLmxlbmd0aDtcbiAgfVxuICByZXF1aXJlKCEocmVzdWx0WzBdID09PSAweGVmICYmIHJlc3VsdFsxXSA9PT0gMHhiYiAmJiByZXN1bHRbMl0gPT09IDB4YmYpKTtcbiAgcmV0dXJuIHJlc3VsdDtcbn1cblxuY29uc3QgQVVESUVOQ0UgPSBcImNvbGxlY3QucmVjZWlwdC1zdXBlcnZpc29yLnYxL2xoYm93cGJjcHdvaXBhcndud2d0XCI7XG5mdW5jdGlvbiBwYXlsb2FkKGFjdGlvbjogQWN0aW9uLCB2YWx1ZTogdW5rbm93bik6IGFzc2VydHMgdmFsdWUgaXMgSnNvbiB7XG4gIGlmIChhY3Rpb24gPT09IFwicmVjb25jaWxlXCIpIHtcbiAgICByZXF1aXJlKGtleXModmFsdWUsIFtcInRhcmdldF9yZXF1ZXN0X2lkXCJdKSAmJiB1dWlkKHZhbHVlLnRhcmdldF9yZXF1ZXN0X2lkKSk7XG4gIH0gZWxzZSByZXF1aXJlKGtleXModmFsdWUsIFtdKSk7XG59XG5mdW5jdGlvbiBvYnNlcnZhdGlvbihcbiAgdmFsdWU6IHVua25vd24sIHByaW5jaXBhbDogc3RyaW5nLCByZXF1ZXN0OiBzdHJpbmcsIGFjdGlvbj86IEFjdGlvbixcbik6IHZhbHVlIGlzIEpzb24ge1xuICBjb25zdCBiYXNlID0gW1wiY29udHJhY3RfdmVyc2lvblwiLCBcInByaW5jaXBhbF9pZFwiLCBcInJlcXVlc3RfaWRcIiwgXCJhY3Rpb25cIixcbiAgICBcIm9ic2VydmVkX2F0XCIsIFwiZXhwaXJlc19hdFwiLCBcInNjb3BlXCIsIFwibW9kZVwiLCBcImJ1c2luZXNzX2hhbmRsZWRcIixcbiAgICBcImZpbmFuY2lhbF9hY3Rpb25cIiwgXCJzZW5kX2FjdGlvblwiXTtcbiAgaWYgKCFvYmplY3QodmFsdWUpKSByZXR1cm4gZmFsc2U7XG4gIGNvbnN0IGV4cGVjdGVkID0gdmFsdWUuYWN0aW9uID09PSBcInNoYWRvd19oZWFsdGhcIlxuICAgID8gWy4uLmJhc2UsIFwic2FtcGxlX3ZhbGlkX3VudGlsXCIsIFwicXVldWVkX2NvdW50XCIsIFwidW5rbm93bl9jb3VudFwiLFxuICAgICAgXCJmYWlsZWRfbm9fc2VuZF9jb3VudFwiLCBcImRpc3BhdGNoX2VuYWJsZWRcIl0gOiBiYXNlO1xuICBpZiAoIWtleXModmFsdWUsIGV4cGVjdGVkKSB8fCB2YWx1ZS5jb250cmFjdF92ZXJzaW9uICE9PSAxIHx8XG4gICAgdmFsdWUucHJpbmNpcGFsX2lkICE9PSBwcmluY2lwYWwgfHwgdmFsdWUucmVxdWVzdF9pZCAhPT0gcmVxdWVzdCB8fFxuICAgICFbXCJwcm92ZV9rZXlcIiwgXCJzaGFkb3dfaGVhbHRoXCJdLmluY2x1ZGVzKHZhbHVlLmFjdGlvbiBhcyBzdHJpbmcpIHx8XG4gICAgKGFjdGlvbiAhPT0gdW5kZWZpbmVkICYmIHZhbHVlLmFjdGlvbiAhPT0gYWN0aW9uKSB8fFxuICAgICF1dGModmFsdWUub2JzZXJ2ZWRfYXQpIHx8ICF1dGModmFsdWUuZXhwaXJlc19hdCkgfHxcbiAgICBEYXRlLnBhcnNlKHZhbHVlLmV4cGlyZXNfYXQpIDw9IERhdGUucGFyc2UodmFsdWUub2JzZXJ2ZWRfYXQpIHx8XG4gICAgdmFsdWUuc2NvcGUgIT09IFwicndfcmVjZWlwdF9zaGFkb3dcIiB8fCB2YWx1ZS5tb2RlICE9PSBcIlNoYWRvd1wiIHx8XG4gICAgdmFsdWUuYnVzaW5lc3NfaGFuZGxlZCAhPT0gZmFsc2UgfHwgdmFsdWUuZmluYW5jaWFsX2FjdGlvbiAhPT0gZmFsc2UgfHxcbiAgICB2YWx1ZS5zZW5kX2FjdGlvbiAhPT0gZmFsc2UpIHJldHVybiBmYWxzZTtcbiAgaWYgKHZhbHVlLmFjdGlvbiA9PT0gXCJzaGFkb3dfaGVhbHRoXCIpIHtcbiAgICBpZiAoIXV0Yyh2YWx1ZS5zYW1wbGVfdmFsaWRfdW50aWwpIHx8XG4gICAgICBEYXRlLnBhcnNlKHZhbHVlLnNhbXBsZV92YWxpZF91bnRpbCkgPD0gRGF0ZS5wYXJzZSh2YWx1ZS5vYnNlcnZlZF9hdCkgfHxcbiAgICAgIERhdGUucGFyc2UodmFsdWUuc2FtcGxlX3ZhbGlkX3VudGlsKSA+IERhdGUucGFyc2UodmFsdWUub2JzZXJ2ZWRfYXQpICsgNjAwMDAgfHxcbiAgICAgIERhdGUucGFyc2UodmFsdWUuc2FtcGxlX3ZhbGlkX3VudGlsKSA+IERhdGUucGFyc2UodmFsdWUuZXhwaXJlc19hdCkgfHxcbiAgICAgICFpbnRlZ2VyKHZhbHVlLnF1ZXVlZF9jb3VudCwgMCwgMWU5KSB8fCAhaW50ZWdlcih2YWx1ZS51bmtub3duX2NvdW50LCAwLCAxZTkpIHx8XG4gICAgICAhaW50ZWdlcih2YWx1ZS5mYWlsZWRfbm9fc2VuZF9jb3VudCwgMCwgMWU5KSB8fFxuICAgICAgdHlwZW9mIHZhbHVlLmRpc3BhdGNoX2VuYWJsZWQgIT09IFwiYm9vbGVhblwiKSByZXR1cm4gZmFsc2U7XG4gIH1cbiAgcmV0dXJuIHRydWU7XG59XG5leHBvcnQgZnVuY3Rpb24gdmFsaWRhdGVTdXBlcnZpc29yUmVzdWx0KFxuICB2YWx1ZTogdW5rbm93biwgcHJpbmNpcGFsOiBzdHJpbmcsIHJlcXVlc3Q6IHN0cmluZywgYWN0aW9uOiBBY3Rpb24sIHA6IEpzb24sXG4pOiB2YWx1ZSBpcyBKc29uIHtcbiAgaWYgKGFjdGlvbiAhPT0gXCJyZWNvbmNpbGVcIikgcmV0dXJuIG9ic2VydmF0aW9uKHZhbHVlLCBwcmluY2lwYWwsIHJlcXVlc3QsIGFjdGlvbik7XG4gIGlmICgha2V5cyh2YWx1ZSwgW1wiY29udHJhY3RfdmVyc2lvblwiLCBcInRhcmdldF9yZXF1ZXN0X2lkXCIsIFwic3RhdHVzXCIsIFwicmVjZWlwdFwiXSkgfHxcbiAgICB2YWx1ZS5jb250cmFjdF92ZXJzaW9uICE9PSAxIHx8IHZhbHVlLnRhcmdldF9yZXF1ZXN0X2lkICE9PSBwLnRhcmdldF9yZXF1ZXN0X2lkIHx8XG4gICAgIVtcInJlY29yZGVkXCIsIFwibm90X3JlY29yZGVkXCIsIFwiaW5fcHJvZ3Jlc3NcIl0uaW5jbHVkZXModmFsdWUuc3RhdHVzIGFzIHN0cmluZykpIHJldHVybiBmYWxzZTtcbiAgaWYgKHZhbHVlLnN0YXR1cyA9PT0gXCJyZWNvcmRlZFwiKSB7XG4gICAgcmV0dXJuIG9ic2VydmF0aW9uKHZhbHVlLnJlY2VpcHQsIHByaW5jaXBhbCwgcC50YXJnZXRfcmVxdWVzdF9pZCBhcyBzdHJpbmcpO1xuICB9XG4gIHJldHVybiB2YWx1ZS5yZWNlaXB0ID09PSBudWxsO1xufVxuZnVuY3Rpb24gcmVzcG9uc2Uoc3RhdHVzOiBudW1iZXIsIHZhbHVlOiBKc29uKTogUmVzcG9uc2Uge1xuICByZXR1cm4gbmV3IFJlc3BvbnNlKEpTT04uc3RyaW5naWZ5KHZhbHVlKSwge3N0YXR1cywgaGVhZGVyczoge1xuICAgIFwiY29udGVudC10eXBlXCI6IFwiYXBwbGljYXRpb24vanNvbjsgY2hhcnNldD11dGYtOFwiLCBcImNhY2hlLWNvbnRyb2xcIjogXCJuby1zdG9yZVwiLFxuICAgIFwieC1jb250ZW50LXR5cGUtb3B0aW9uc1wiOiBcIm5vc25pZmZcIiwgXCJyZWZlcnJlci1wb2xpY3lcIjogXCJuby1yZWZlcnJlclwiLFxuICB9fSk7XG59XG5cbi8qKiBFeGFjdCBzaWduZWQgYnl0ZXMsIGZpeGVkIGF1ZGllbmNlIGFuZCB0aHJlZSBuYXJyb3dseSBzY29wZWQgYWN0aW9ucy5cbiAqIERCIGF1dGhvcml0eSBpcyByZWNoZWNrZWQgYWZ0ZXIgc2lnbmF0dXJlIHZhbGlkYXRpb24gYW5kIHJlcXVlc3QgbG9jayB3YWl0cy4gKi9cbmV4cG9ydCBmdW5jdGlvbiBjcmVhdGVTdXBlcnZpc29ySGFuZGxlcihkZXBlbmRlbmNpZXM6IFN1cGVydmlzb3JEZXBlbmRlbmNpZXMpIHtcbiAgY29uc3Qgbm93ID0gZGVwZW5kZW5jaWVzLm5vdyA/PyBEYXRlLm5vdztcbiAgY29uc3QgdGltZW91dCA9IE1hdGgubWluKDE1MDAwLCBNYXRoLm1heCgxLCBkZXBlbmRlbmNpZXMudGltZW91dE1zID8/IDUwMDApKTtcbiAgcmV0dXJuIGFzeW5jIChyZXF1ZXN0OiBSZXF1ZXN0KTogUHJvbWlzZTxSZXNwb25zZT4gPT4ge1xuICAgIGxldCBhdXRoZW50aWNhdGVkID0gZmFsc2U7XG4gICAgbGV0IG9wZXJhdGlvbmFsID0gZmFsc2U7XG4gICAgY29uc3Qgc3RhcnRlZCA9IERhdGUubm93KCk7XG4gICAgY29uc3QgcnBjID0gYXN5bmMgKG5hbWU6IHN0cmluZywgYXJnczogSnNvbik6IFByb21pc2U8dW5rbm93bj4gPT4ge1xuICAgICAgY29uc3QgcmVtYWluaW5nID0gdGltZW91dCAtIChEYXRlLm5vdygpIC0gc3RhcnRlZCk7XG4gICAgICBpZiAocmVtYWluaW5nIDw9IDApIHRocm93IG5ldyBSZWZ1c2FsKDUwMywgYXV0aGVudGljYXRlZFxuICAgICAgICA/IFwiU1VQRVJWSVNPUl9PVVRDT01FX1VOS05PV05cIiA6IFwiU1VQRVJWSVNPUl9BVVRIX1VOQVZBSUxBQkxFXCIpO1xuICAgICAgY29uc3QgY29udHJvbGxlciA9IG5ldyBBYm9ydENvbnRyb2xsZXIoKTtcbiAgICAgIGxldCB0aW1lcjogUmV0dXJuVHlwZTx0eXBlb2Ygc2V0VGltZW91dD4gfCB1bmRlZmluZWQ7XG4gICAgICB0cnkge1xuICAgICAgICBjb25zdCByID0gYXdhaXQgUHJvbWlzZS5yYWNlKFtcbiAgICAgICAgICBkZXBlbmRlbmNpZXMucnBjKG5hbWUsIGFyZ3MsIGNvbnRyb2xsZXIuc2lnbmFsKSxcbiAgICAgICAgICBuZXcgUHJvbWlzZTxuZXZlcj4oKF8sIHJlamVjdCkgPT4ge1xuICAgICAgICAgICAgdGltZXIgPSBzZXRUaW1lb3V0KCgpID0+IHtcbiAgICAgICAgICAgICAgY29udHJvbGxlci5hYm9ydCgpO1xuICAgICAgICAgICAgICByZWplY3QobmV3IFJlZnVzYWwoNTAzLCBhdXRoZW50aWNhdGVkXG4gICAgICAgICAgICAgICAgPyBcIlNVUEVSVklTT1JfT1VUQ09NRV9VTktOT1dOXCIgOiBcIlNVUEVSVklTT1JfQVVUSF9VTkFWQUlMQUJMRVwiKSk7XG4gICAgICAgICAgICB9LCByZW1haW5pbmcpO1xuICAgICAgICAgIH0pLFxuICAgICAgICBdKTtcbiAgICAgICAgaWYgKHIuZXJyb3IpIHtcbiAgICAgICAgICBpZiAoci5lcnJvci5jb2RlID09PSBcIjU1UDAzXCIpIHRocm93IG5ldyBSZWZ1c2FsKDQwOSwgXCJTVVBFUlZJU09SX0FVVEhPUklUWV9CVVNZXCIpO1xuICAgICAgICAgIGlmIChyLmVycm9yLmNvZGUgPT09IFwiNDI1MDFcIikgdGhyb3cgbmV3IFJlZnVzYWwoNDAzLCBcIlNVUEVSVklTT1JfQVVUSE9SSVRZX1JFRlVTRURcIik7XG4gICAgICAgICAgaWYgKHIuZXJyb3IuY29kZSA9PT0gXCIyMjAyM1wiIHx8IHIuZXJyb3IuY29kZSA9PT0gXCIyMzUwNVwiKSB7XG4gICAgICAgICAgICB0aHJvdyBuZXcgUmVmdXNhbCg0MDksIFwiU1VQRVJWSVNPUl9SRVFVRVNUX1JFRlVTRURcIik7XG4gICAgICAgICAgfVxuICAgICAgICAgIGlmIChvcGVyYXRpb25hbCAmJiBbXCI1NTAwMFwiLCBcIjQwMDAxXCJdLmluY2x1ZGVzKHIuZXJyb3IuY29kZSA/PyBcIlwiKSkgdGhyb3cgbmV3IFJlZnVzYWwoNDA5LCBcIlNVUEVSVklTT1JfUkVRVUVTVF9SRUZVU0VEXCIpO1xuICAgICAgICAgIHRocm93IG5ldyBSZWZ1c2FsKDUwMywgYXV0aGVudGljYXRlZFxuICAgICAgICAgICAgPyBcIlNVUEVSVklTT1JfT1VUQ09NRV9VTktOT1dOXCIgOiBcIlNVUEVSVklTT1JfQVVUSF9VTkFWQUlMQUJMRVwiKTtcbiAgICAgICAgfVxuICAgICAgICByZXR1cm4gci5kYXRhO1xuICAgICAgfSBmaW5hbGx5IHsgaWYgKHRpbWVyICE9PSB1bmRlZmluZWQpIGNsZWFyVGltZW91dCh0aW1lcik7IH1cbiAgICB9O1xuICAgIHRyeSB7XG4gICAgICBpZiAocmVxdWVzdC5tZXRob2QgIT09IFwiUE9TVFwiKSB0aHJvdyBuZXcgUmVmdXNhbCg0MDUsIFwiU1VQRVJWSVNPUl9NRVRIT0RfUkVGVVNFRFwiKTtcbiAgICAgIHJlcXVpcmUobmV3IFVSTChyZXF1ZXN0LnVybCkuc2VhcmNoID09PSBcIlwiKTtcbiAgICAgIGNvbnN0IHJhdyA9IGF3YWl0IGJvZHkocmVxdWVzdCwgdGltZW91dCk7XG4gICAgICBsZXQgdGV4dDogc3RyaW5nO1xuICAgICAgdHJ5IHsgdGV4dCA9IG5ldyBUZXh0RGVjb2RlcihcInV0Zi04XCIsIHtmYXRhbDogdHJ1ZX0pLmRlY29kZShyYXcpOyB9XG4gICAgICBjYXRjaCB7IHRocm93IG5ldyBSZWZ1c2FsKDQwMCwgXCJTVVBFUlZJU09SX1JFUVVFU1RfSU5WQUxJRFwiKTsgfVxuICAgICAgY29uc3QgZW52ZWxvcGUgPSBwYXJzZVN0cmljdCh0ZXh0KTtcbiAgICAgIHJlcXVpcmUoa2V5cyhlbnZlbG9wZSwgW1wiY29udHJhY3RfdmVyc2lvblwiLCBcImF1ZGllbmNlXCIsIFwiYWN0aW9uXCIsIFwicHJpbmNpcGFsX2lkXCIsXG4gICAgICAgIFwicmVxdWVzdF9pZFwiLCBcImlzc3VlZF9hdFwiLCBcInBheWxvYWRcIl0pKTtcbiAgICAgIG9wZXJhdGlvbmFsID0gZW52ZWxvcGUuY29udHJhY3RfdmVyc2lvbiA9PT0gMjtcbiAgICAgIHJlcXVpcmUob3BlcmF0aW9uYWwgPyBlbnZlbG9wZS5hdWRpZW5jZSA9PT0gXCJjb2xsZWN0LnJlY2VpcHQtc3VwZXJ2aXNvci52Mi9saGJvd3BiY3B3b2lwYXJ3bndndFwiICYmIG9wZXJhdGlvbkFjdGlvbnMuaW5jbHVkZXMoZW52ZWxvcGUuYWN0aW9uIGFzIE9wZXJhdGlvbkFjdGlvbilcbiAgICAgICAgOiBlbnZlbG9wZS5jb250cmFjdF92ZXJzaW9uID09PSAxICYmIGVudmVsb3BlLmF1ZGllbmNlID09PSBBVURJRU5DRSAmJiBbXCJwcm92ZV9rZXlcIiwgXCJzaGFkb3dfaGVhbHRoXCIsIFwicmVjb25jaWxlXCJdLmluY2x1ZGVzKGVudmVsb3BlLmFjdGlvbiBhcyBzdHJpbmcpKTtcbiAgICAgIHJlcXVpcmUodXVpZChlbnZlbG9wZS5wcmluY2lwYWxfaWQpICYmIHV1aWQoZW52ZWxvcGUucmVxdWVzdF9pZCkgJiYgdXRjKGVudmVsb3BlLmlzc3VlZF9hdCkpO1xuICAgICAgcmVxdWlyZShEYXRlLnBhcnNlKGVudmVsb3BlLmlzc3VlZF9hdCkgPj0gbm93KCkgLSAzMDAwMCAmJlxuICAgICAgICBEYXRlLnBhcnNlKGVudmVsb3BlLmlzc3VlZF9hdCkgPD0gbm93KCkgKyAxMDAwMCk7XG4gICAgICBjb25zdCBhY3Rpb24gPSBlbnZlbG9wZS5hY3Rpb24gYXMgQWN0aW9uIHwgT3BlcmF0aW9uQWN0aW9uO1xuICAgICAgaWYgKG9wZXJhdGlvbmFsKSByZXF1aXJlKHZhbGlkYXRlT3BlcmF0aW9uUGF5bG9hZChhY3Rpb24gYXMgT3BlcmF0aW9uQWN0aW9uLCBlbnZlbG9wZS5wYXlsb2FkKSk7XG4gICAgICBlbHNlIHBheWxvYWQoYWN0aW9uIGFzIEFjdGlvbiwgZW52ZWxvcGUucGF5bG9hZCk7XG4gICAgICBjb25zdCBrZXlIYXNoID0gcmVxdWVzdC5oZWFkZXJzLmdldChcIlgtQ29sbGVjdC1TdXBlcnZpc29yLUtleS1JZFwiKTtcbiAgICAgIHJlcXVpcmUoaGFzaChrZXlIYXNoKSk7XG4gICAgICBjb25zdCBzaWduYXR1cmUgPSBkZXJUb1AxMzYzKGJhc2U2NChyZXF1ZXN0LmhlYWRlcnMuZ2V0KFwiWC1Db2xsZWN0LVN1cGVydmlzb3ItU2lnbmF0dXJlXCIpLCAxMDApKTtcbiAgICAgIGNvbnN0IGtleSA9IGF3YWl0IHJwYyhcInJlY2VpcHRfc3VwZXJ2aXNvcl9rZXlfdjFcIiwge3BfcHJpbmNpcGFsX2lkOiBlbnZlbG9wZS5wcmluY2lwYWxfaWR9KTtcbiAgICAgIGlmICgha2V5cyhrZXksIFtcImNvbnRyYWN0X3ZlcnNpb25cIiwgXCJwcmluY2lwYWxfaWRcIiwgXCJzdGF0ZVwiLCBcInNjb3BlXCIsXG4gICAgICAgIFwicHVibGljX2tleV9zcGtpX2Jhc2U2NFwiLCBcImtleV9zaGEyNTZcIiwgXCJleHBpcmVzX2F0XCJdKSB8fFxuICAgICAgICBrZXkuY29udHJhY3RfdmVyc2lvbiAhPT0gMSB8fCBrZXkucHJpbmNpcGFsX2lkICE9PSBlbnZlbG9wZS5wcmluY2lwYWxfaWQgfHxcbiAgICAgICAga2V5LnNjb3BlICE9PSAob3BlcmF0aW9uYWwgPyBcInJ3X3JlY2VpcHRfb3BlcmF0aW9uc1wiIDogXCJyd19yZWNlaXB0X3NoYWRvd1wiKSB8fCAhW1wicGVuZGluZ1wiLCBcImFjdGl2ZVwiXS5pbmNsdWRlcyhrZXkuc3RhdGUgYXMgc3RyaW5nKSB8fFxuICAgICAgICAhdXRjKGtleS5leHBpcmVzX2F0KSB8fCBEYXRlLnBhcnNlKGtleS5leHBpcmVzX2F0KSA8PSBub3coKSB8fCBrZXkua2V5X3NoYTI1NiAhPT0ga2V5SGFzaCkge1xuICAgICAgICB0aHJvdyBuZXcgUmVmdXNhbCg0MDEsIFwiU1VQRVJWSVNPUl9LRVlfUkVGVVNFRFwiKTtcbiAgICAgIH1cbiAgICAgIGxldCBzcGtpOiBVaW50OEFycmF5O1xuICAgICAgdHJ5IHsgc3BraSA9IGJhc2U2NChrZXkucHVibGljX2tleV9zcGtpX2Jhc2U2NCwgMTI0KTsgfVxuICAgICAgY2F0Y2ggeyB0aHJvdyBuZXcgUmVmdXNhbCg0MDEsIFwiU1VQRVJWSVNPUl9LRVlfUkVGVVNFRFwiKTsgfVxuICAgICAgaWYgKHNwa2kubGVuZ3RoICE9PSA5MSB8fCBhd2FpdCBkaWdlc3Qoc3BraSkgIT09IGtleUhhc2gpIHtcbiAgICAgICAgdGhyb3cgbmV3IFJlZnVzYWwoNDAxLCBcIlNVUEVSVklTT1JfS0VZX1JFRlVTRURcIik7XG4gICAgICB9XG4gICAgICBsZXQgdmVyaWZpZWQgPSBmYWxzZTtcbiAgICAgIHRyeSB7XG4gICAgICAgIGNvbnN0IGltcG9ydGVkID0gYXdhaXQgY3J5cHRvLnN1YnRsZS5pbXBvcnRLZXkoXCJzcGtpXCIsIG5ldyBVaW50OEFycmF5KHNwa2kpLFxuICAgICAgICAgIHtuYW1lOiBcIkVDRFNBXCIsIG5hbWVkQ3VydmU6IFwiUC0yNTZcIn0sIGZhbHNlLCBbXCJ2ZXJpZnlcIl0pO1xuICAgICAgICB2ZXJpZmllZCA9IGF3YWl0IGNyeXB0by5zdWJ0bGUudmVyaWZ5KHtuYW1lOiBcIkVDRFNBXCIsIGhhc2g6IFwiU0hBLTI1NlwifSxcbiAgICAgICAgICBpbXBvcnRlZCwgbmV3IFVpbnQ4QXJyYXkoc2lnbmF0dXJlKSwgbmV3IFVpbnQ4QXJyYXkocmF3KSk7XG4gICAgICB9IGNhdGNoIHsgdmVyaWZpZWQgPSBmYWxzZTsgfVxuICAgICAgaWYgKCF2ZXJpZmllZCkgdGhyb3cgbmV3IFJlZnVzYWwoNDAxLCBcIlNVUEVSVklTT1JfU0lHTkFUVVJFX1JFRlVTRURcIik7XG4gICAgICBhdXRoZW50aWNhdGVkID0gdHJ1ZTtcbiAgICAgIGlmIChhY3Rpb24gIT09IFwicHJvdmVfa2V5XCIgJiYga2V5LnN0YXRlICE9PSBcImFjdGl2ZVwiKSB7XG4gICAgICAgIHRocm93IG5ldyBSZWZ1c2FsKDQwMywgXCJTVVBFUlZJU09SX1BSSU5DSVBBTF9QRU5ESU5HXCIpO1xuICAgICAgfVxuICAgICAgY29uc3QgYXJnczogSnNvbiA9IHtwX3ByaW5jaXBhbF9pZDogZW52ZWxvcGUucHJpbmNpcGFsX2lkLFxuICAgICAgICBwX3JlcXVlc3RfaWQ6IGVudmVsb3BlLnJlcXVlc3RfaWQsIHBfa2V5X3NoYTI1Njoga2V5SGFzaCxcbiAgICAgICAgcF9yZXF1ZXN0X3NoYTI1NjogYXdhaXQgZGlnZXN0KHJhdyksIHBfaXNzdWVkX2F0OiBlbnZlbG9wZS5pc3N1ZWRfYXR9O1xuICAgICAgY29uc3QgbmFtZSA9IG9wZXJhdGlvbmFsID8gXCJyZWNlaXB0X29wZXJhdGlvbnNfZXhlY3V0ZV92MlwiIDogYWN0aW9uID09PSBcInJlY29uY2lsZVwiID8gXCJyZWNlaXB0X3N1cGVydmlzb3JfcmVjb25jaWxlX3YxXCIgOiBcInJlY2VpcHRfc3VwZXJ2aXNvcl9vYnNlcnZlX3YxXCI7XG4gICAgICBpZiAob3BlcmF0aW9uYWwpIHsgYXJncy5wX2FjdGlvbiA9IGFjdGlvbjsgYXJncy5wX3BheWxvYWQgPSBlbnZlbG9wZS5wYXlsb2FkOyB9XG4gICAgICBlbHNlIGlmIChhY3Rpb24gPT09IFwicmVjb25jaWxlXCIpIGFyZ3MucF90YXJnZXRfcmVxdWVzdF9pZCA9IGVudmVsb3BlLnBheWxvYWQudGFyZ2V0X3JlcXVlc3RfaWQ7XG4gICAgICBlbHNlIGFyZ3MucF9hY3Rpb24gPSBhY3Rpb247XG4gICAgICBjb25zdCByZXN1bHQgPSBhd2FpdCBycGMobmFtZSwgYXJncyk7XG4gICAgICBjb25zdCB2YWxpZCA9IG9wZXJhdGlvbmFsXG4gICAgICAgID8gdmFsaWRhdGVPcGVyYXRpb25SZXN1bHQocmVzdWx0LCBlbnZlbG9wZS5wcmluY2lwYWxfaWQsIGVudmVsb3BlLnJlcXVlc3RfaWQsIGFjdGlvbiBhcyBPcGVyYXRpb25BY3Rpb24sIGVudmVsb3BlLnBheWxvYWQpXG4gICAgICAgIDogdmFsaWRhdGVTdXBlcnZpc29yUmVzdWx0KHJlc3VsdCwgZW52ZWxvcGUucHJpbmNpcGFsX2lkLCBlbnZlbG9wZS5yZXF1ZXN0X2lkLCBhY3Rpb24gYXMgQWN0aW9uLCBlbnZlbG9wZS5wYXlsb2FkKTtcbiAgICAgIGlmIChvcGVyYXRpb25hbCkge1xuICAgICAgICBpZiAoIXZhbGlkIHx8ICFvYmplY3QocmVzdWx0KSB8fCAoYWN0aW9uICE9PSBcInJlY29uY2lsZV9yZXF1ZXN0XCIgJiZcbiAgICAgICAgICAgICghdXRjKHJlc3VsdC5vYnNlcnZlZF9hdCkgfHwgRGF0ZS5wYXJzZShyZXN1bHQub2JzZXJ2ZWRfYXQpIDwgRGF0ZS5wYXJzZShlbnZlbG9wZS5pc3N1ZWRfYXQpIC0gMTAwMDAgfHwgRGF0ZS5wYXJzZShyZXN1bHQub2JzZXJ2ZWRfYXQpID4gbm93KCkgKyAxMDAwMCkpIHx8XG4gICAgICAgICAgICAoYWN0aW9uID09PSBcInByb3ZlX2tleVwiICYmIHJlc3VsdC5leHBpcmVzX2F0ICE9PSBrZXkuZXhwaXJlc19hdCkgfHxcbiAgICAgICAgICAgIChhY3Rpb24gPT09IFwiYmVnaW5fcnVuXCIgJiYgcmVzdWx0Lm9rID09PSB0cnVlICYmICghdXRjKHJlc3VsdC5leHBpcmVzX2F0KSB8fCBEYXRlLnBhcnNlKHJlc3VsdC5leHBpcmVzX2F0KSA+IERhdGUucGFyc2Uoa2V5LmV4cGlyZXNfYXQpKSkgfHxcbiAgICAgICAgICAgIChhY3Rpb24gPT09IFwicmVjb25jaWxlX3JlcXVlc3RcIiAmJiBvYmplY3QocmVzdWx0LnJlY2VpcHQpICYmICghdXRjKHJlc3VsdC5yZWNlaXB0Lm9ic2VydmVkX2F0KSB8fCBEYXRlLnBhcnNlKHJlc3VsdC5yZWNlaXB0Lm9ic2VydmVkX2F0KSA+IG5vdygpICsgMTAwMDApKSkgdGhyb3cgbmV3IFJlZnVzYWwoNTAyLCBcIlNVUEVSVklTT1JfT1VUQ09NRV9VTktOT1dOXCIpO1xuICAgICAgfSBlbHNlIGlmICghdmFsaWQgfHwgIW9iamVjdChyZXN1bHQpIHx8XG4gICAgICAgIChhY3Rpb24gIT09IFwicmVjb25jaWxlXCIgJiYgKHJlc3VsdC5leHBpcmVzX2F0ICE9PSBrZXkuZXhwaXJlc19hdCB8fFxuICAgICAgICAgIERhdGUucGFyc2UocmVzdWx0Lm9ic2VydmVkX2F0IGFzIHN0cmluZykgPCBEYXRlLnBhcnNlKGVudmVsb3BlLmlzc3VlZF9hdCkgLSAxMDAwMCB8fFxuICAgICAgICAgIERhdGUucGFyc2UocmVzdWx0Lm9ic2VydmVkX2F0IGFzIHN0cmluZykgPiBub3coKSArIDEwMDAwKSkgfHxcbiAgICAgICAgKGFjdGlvbiA9PT0gXCJyZWNvbmNpbGVcIiAmJiBvYmplY3QocmVzdWx0LnJlY2VpcHQpICYmXG4gICAgICAgICAgKHJlc3VsdC5yZWNlaXB0LmV4cGlyZXNfYXQgIT09IGtleS5leHBpcmVzX2F0IHx8XG4gICAgICAgICAgICBEYXRlLnBhcnNlKHJlc3VsdC5yZWNlaXB0Lm9ic2VydmVkX2F0IGFzIHN0cmluZykgPiBub3coKSArIDEwMDAwKSkpIHtcbiAgICAgICAgdGhyb3cgbmV3IFJlZnVzYWwoNTAyLCBcIlNVUEVSVklTT1JfT1VUQ09NRV9VTktOT1dOXCIpO1xuICAgICAgfVxuICAgICAgcmV0dXJuIHJlc3BvbnNlKDIwMCwge2NvbnRyYWN0X3ZlcnNpb246IG9wZXJhdGlvbmFsID8gMiA6IDEsIHByaW5jaXBhbF9pZDogZW52ZWxvcGUucHJpbmNpcGFsX2lkLFxuICAgICAgICByZXF1ZXN0X2lkOiBlbnZlbG9wZS5yZXF1ZXN0X2lkLCBhY3Rpb24sIHJlc3VsdH0pO1xuICAgIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgICBpZiAoZXJyb3IgaW5zdGFuY2VvZiBSZWZ1c2FsKSByZXR1cm4gcmVzcG9uc2UoZXJyb3Iuc3RhdHVzLCB7b2s6IGZhbHNlLCBjb2RlOiBlcnJvci5jb2RlfSk7XG4gICAgICByZXR1cm4gcmVzcG9uc2UoNTAzLCB7b2s6IGZhbHNlLCBjb2RlOiBhdXRoZW50aWNhdGVkXG4gICAgICAgID8gXCJTVVBFUlZJU09SX09VVENPTUVfVU5LTk9XTlwiIDogXCJTVVBFUlZJU09SX0FVVEhfVU5BVkFJTEFCTEVcIn0pO1xuICAgIH1cbiAgfTtcbn1cbmltcG9ydCB7IG9wZXJhdGlvbkFjdGlvbnMsIHZhbGlkYXRlT3BlcmF0aW9uUGF5bG9hZCwgdmFsaWRhdGVPcGVyYXRpb25SZXN1bHQsIHR5cGUgT3BlcmF0aW9uQWN0aW9uIH0gZnJvbSBcIi4vb3BlcmF0aW9uc19jb250cmFjdC50c1wiO1xuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQVdBLE1BQU0sT0FBTztBQUNiLE1BQU0sT0FBTztBQUNiLE1BQU0sZ0JBQWdCO0VBQ1gsT0FBZTtFQUNmLEtBQWE7RUFDdEIsWUFBWSxNQUFjLEVBQUUsSUFBWSxDQUFFO0lBQ3hDLEtBQUssQ0FBQztJQUNOLElBQUksQ0FBQyxNQUFNLEdBQUc7SUFDZCxJQUFJLENBQUMsSUFBSSxHQUFHO0VBQ2Q7QUFDRjtBQUNBLFNBQVMsT0FBTyxLQUFjO0VBQzVCLE9BQU8sT0FBTyxVQUFVLFlBQVksVUFBVSxRQUFRLENBQUMsTUFBTSxPQUFPLENBQUM7QUFDdkU7QUFDQSxTQUFTLEtBQUssS0FBYyxFQUFFLFFBQWtCO0VBQzlDLE9BQU8sT0FBTyxVQUFVLE9BQU8sSUFBSSxDQUFDLE9BQU8sTUFBTSxLQUFLLFNBQVMsTUFBTSxJQUNuRSxTQUFTLEtBQUssQ0FBQyxDQUFDLElBQU0sT0FBTyxNQUFNLENBQUMsT0FBTztBQUMvQztBQUNBLFNBQVMsS0FBSyxLQUFjO0VBQzFCLE9BQU8sT0FBTyxVQUFVLFlBQVksS0FBSyxJQUFJLENBQUM7QUFDaEQ7QUFDQSxTQUFTLEtBQUssS0FBYztFQUMxQixPQUFPLE9BQU8sVUFBVSxZQUFZLEtBQUssSUFBSSxDQUFDO0FBQ2hEO0FBQ0EsU0FBUyxRQUFRLEtBQWMsRUFBRSxHQUFXLEVBQUUsR0FBVztFQUN2RCxPQUFPLE9BQU8sVUFBVSxZQUFZLE9BQU8sYUFBYSxDQUFDLFVBQ3ZELFNBQVMsT0FBTyxTQUFTO0FBQzdCO0FBQ0Es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
// denoCacheMetadata=13762079618193698557,15927803297792018224