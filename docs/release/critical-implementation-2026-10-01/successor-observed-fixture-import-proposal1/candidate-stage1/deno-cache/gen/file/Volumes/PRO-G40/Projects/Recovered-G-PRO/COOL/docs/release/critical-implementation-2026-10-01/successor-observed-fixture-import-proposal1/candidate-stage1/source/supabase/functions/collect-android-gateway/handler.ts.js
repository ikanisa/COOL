import { ARCHIVE_RPC, archivePayload, archiveResult } from "./archive_v3.ts";
const V1_RPC = {
  heartbeat: "gateway_heartbeat_v1",
  callback: "gateway_callback_v1",
  reconcile: "gateway_reconcile_v1",
  dispatch_grant: "gateway_dispatch_grant_v1"
};
const V2_RPC = {
  dispatch_grant: "gateway_dispatch_grant_v2",
  arm_dispatch: "gateway_arm_dispatch_v2",
  callback: "gateway_callback_v2",
  reconcile: "gateway_reconcile_v2",
  attempt_status: "gateway_attempt_status_v2"
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HASH = /^[0-9a-f]{64}$/;
class Refusal extends Error {
  status;
  code;
  constructor(status, code){
    super(code), this.status = status, this.code = code;
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
  if (!condition) throw new Refusal(400, "GATEWAY_REQUEST_INVALID");
}
function base64(value, max) {
  require(typeof value === "string" && value.length <= max && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value));
  let decoded;
  try {
    decoded = atob(value);
  } catch  {
    throw new Refusal(400, "GATEWAY_REQUEST_INVALID");
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
    require(size >= 1 && size <= 33 && offset + size <= der.length);
    let value = der.slice(offset, offset + size);
    offset += size;
    require(!(value[0] & 0x80));
    require(value.length === 1 || value[0] !== 0 || !!(value[1] & 0x80));
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
      if (text[at - 1] === '"') return JSON.parse(text.slice(start, at));
    }
    throw new Refusal(400, "GATEWAY_REQUEST_INVALID");
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
    throw new Refusal(400, "GATEWAY_REQUEST_INVALID");
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
            reject(new Refusal(408, "GATEWAY_REQUEST_INVALID"));
          }, Math.max(1, deadline - Date.now()));
        })
      ]).finally(()=>{
        if (timer !== undefined) clearTimeout(timer);
      });
      if (chunk.done) break;
      count += chunk.value.length;
      if (count > 8192) {
        await reader.cancel();
        throw new Refusal(413, "GATEWAY_BODY_TOO_LARGE");
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
function payload(action, p) {
  if (action === "heartbeat") {
    require(keys(p, [
      "sms_permission",
      "network",
      "telephony",
      "sim_selected",
      "sim_revision_sha256",
      "local_pause",
      "reported_at"
    ]));
    require(typeof p.sms_permission === "boolean" && typeof p.sim_selected === "boolean" && typeof p.local_pause === "boolean");
    require([
      "validated",
      "unvalidated",
      "offline",
      "unknown"
    ].includes(p.network));
    require([
      "ready",
      "unavailable",
      "unknown"
    ].includes(p.telephony));
    require(p.sim_selected ? hash(p.sim_revision_sha256) : p.sim_revision_sha256 === null);
    require(utc(p.reported_at));
  } else if (action === "callback") {
    require(keys(p, [
      "callback_id",
      "attempt_id",
      "fence_version",
      "segment_index",
      "segment_count",
      "body_sha256",
      "destination_sha256",
      "callback_kind",
      "result_code",
      "tp_status",
      "occurred_at"
    ]));
    require(uuid(p.callback_id) && uuid(p.attempt_id) && integer(p.fence_version, 1, 1e9));
    require(integer(p.segment_index, 0, 9) && integer(p.segment_count, 1, 10) && p.segment_index < p.segment_count);
    require(hash(p.body_sha256) && hash(p.destination_sha256) && [
      "sent",
      "delivery"
    ].includes(p.callback_kind));
    require(integer(p.result_code, -1, 200) && (p.tp_status === null || integer(p.tp_status, 0, 255)) && utc(p.occurred_at));
  } else if (action === "reconcile") {
    require(keys(p, [
      "target_request_id"
    ]) && uuid(p.target_request_id));
  } else if (action === "attempt_status") {
    require(keys(p, [
      "attempt_id",
      "fence_version"
    ]) && uuid(p.attempt_id) && integer(p.fence_version, 1, 1e9));
  } else if (action === "arm_dispatch") {
    require(keys(p, [
      "attempt_id",
      "fence_version",
      "body_sha256",
      "destination_sha256",
      "callbacks",
      "reservation_sha256"
    ]));
    require(uuid(p.attempt_id) && integer(p.fence_version, 1, 1e9) && hash(p.body_sha256) && hash(p.destination_sha256) && hash(p.reservation_sha256) && Array.isArray(p.callbacks) && p.callbacks.length >= 1 && p.callbacks.length <= 10);
    const callbackIds = new Set();
    for (const [index, callback] of p.callbacks.entries()){
      require(keys(callback, [
        "segment_index",
        "sent_callback_id",
        "delivery_callback_id"
      ]) && callback.segment_index === index && uuid(callback.sent_callback_id) && uuid(callback.delivery_callback_id));
      for (const id of [
        callback.sent_callback_id,
        callback.delivery_callback_id
      ]){
        const normalized = id.toLowerCase();
        require(!callbackIds.has(normalized));
        callbackIds.add(normalized);
      }
    }
  } else require(keys(p, []));
}
function validResult(action, data, device, request, p) {
  if (action === "heartbeat") {
    return keys(data, [
      "observation_id",
      "ingested_at",
      "replay",
      "carrier_proof"
    ]) && uuid(data.observation_id) && utc(data.ingested_at) && typeof data.replay === "boolean" && data.carrier_proof === false;
  }
  if (action === "callback") {
    return keys(data, [
      "callback_id",
      "recorded_at",
      "replay",
      "carrier_proof"
    ]) && uuid(data.callback_id) && (!p || data.callback_id === p.callback_id) && utc(data.recorded_at) && typeof data.replay === "boolean" && data.carrier_proof === false;
  }
  if (action === "dispatch_grant") {
    return keys(data, [
      "ok",
      "code",
      "device_id",
      "request_id",
      "replay"
    ]) && data.ok === false && data.code === "GATEWAY_DISPATCH_AUTHORITY_PENDING" && data.device_id === device && data.request_id === request && typeof data.replay === "boolean";
  }
  if (!keys(data, [
    "target_request_id",
    "outcome",
    "recorded_action",
    "recorded_result"
  ]) || !uuid(data.target_request_id) || p && data.target_request_id !== p.target_request_id) return false;
  if (data.outcome === "unknown") {
    return data.recorded_action === null && data.recorded_result === null;
  }
  if (data.outcome !== "recorded" || ![
    "heartbeat",
    "callback",
    "dispatch_grant"
  ].includes(data.recorded_action)) return false;
  return validResult(data.recorded_action, data.recorded_result, device, data.target_request_id);
}
function sameUuid(left, right) {
  return uuid(left) && uuid(right) && left.toLowerCase() === right.toLowerCase();
}
const DISPATCH_REFUSALS = new Set([
  "OPERATIONS_PAUSED",
  "NO_CURRENT_RUN",
  "DEVICE_NOT_READY",
  "NO_ELIGIBLE_RECEIPT",
  "QUOTA_EXHAUSTED",
  "ORIGINAL_REQUEST_RECORDED"
]);
function dispatchRefusal(data, device, request) {
  return keys(data, [
    "ok",
    "code",
    "device_id",
    "request_id",
    "replay"
  ]) && data.ok === false && DISPATCH_REFUSALS.has(data.code) && sameUuid(data.device_id, device) && sameUuid(data.request_id, request) && typeof data.replay === "boolean";
}
function dispatchDeadline(start, expires, now) {
  return utc(start) && utc(expires) && Date.parse(expires) > Date.parse(start) && Date.parse(expires) <= Date.parse(start) + 30000 && Date.parse(expires) > now;
}
function dispatchCounts(data, segmentCount) {
  const count = integer(segmentCount, 1, 10) ? segmentCount : 10;
  return integer(data.sent_observations, 0, count) && integer(data.delivery_observations, 0, count) && typeof data.conflicting_observations === "boolean" && data.carrier_proof === false && (data.state !== "observed_sent" || data.conflicting_observations === false && data.sent_observations > 0 && (segmentCount === undefined || data.sent_observations === count));
}
async function validDispatchResult(action, data, device, request, now, p) {
  if (action === "dispatch_grant" || action === "arm_dispatch") {
    if (dispatchRefusal(data, device, request)) return true;
    if (action === "dispatch_grant") {
      if (!keys(data, [
        "ok",
        "code",
        "device_id",
        "request_id",
        "attempt_id",
        "receipt_id",
        "run_id",
        "fence_version",
        "policy_revision",
        "issued_at",
        "expires_at",
        "segment_count",
        "body",
        "destination_e164",
        "body_sha256",
        "destination_sha256",
        "sim_revision_sha256",
        "replay"
      ]) || data.ok !== true || data.code !== "DISPATCH_GRANTED" || !sameUuid(data.device_id, device) || !sameUuid(data.request_id, request) || !uuid(data.attempt_id) || !uuid(data.receipt_id) || !uuid(data.run_id) || !integer(data.fence_version, 1, 1e9) || !integer(data.policy_revision, 1, 1e9) || !dispatchDeadline(data.issued_at, data.expires_at, now) || !integer(data.segment_count, 1, 10) || typeof data.body !== "string" || data.body.length === 0 || [
        ...data.body
      ].length > 1000 || typeof data.destination_e164 !== "string" || !/^\+2507[2389][0-9]{7}$/.test(data.destination_e164) || !hash(data.body_sha256) || !hash(data.destination_sha256) || !hash(data.sim_revision_sha256) || data.replay !== false) return false;
      const encoder = new TextEncoder();
      const encodedBody = encoder.encode(data.body);
      return encodedBody.length <= 4000 && await digest(encodedBody) === data.body_sha256 && await digest(encoder.encode(data.destination_e164)) === data.destination_sha256;
    }
    return keys(data, [
      "ok",
      "code",
      "device_id",
      "request_id",
      "attempt_id",
      "fence_version",
      "reservation_sha256",
      "armed_at",
      "expires_at",
      "replay",
      "carrier_proof"
    ]) && data.ok === true && data.code === "DISPATCH_ARMED" && sameUuid(data.device_id, device) && sameUuid(data.request_id, request) && uuid(data.attempt_id) && integer(data.fence_version, 1, 1e9) && hash(data.reservation_sha256) && (!p || sameUuid(data.attempt_id, p.attempt_id) && data.fence_version === p.fence_version && data.reservation_sha256 === p.reservation_sha256) && dispatchDeadline(data.armed_at, data.expires_at, now) && data.replay === false && data.carrier_proof === false;
  }
  if (action === "callback") {
    return keys(data, [
      "callback_id",
      "recorded_at",
      "replay",
      "carrier_proof",
      "state",
      "sent_observations",
      "delivery_observations",
      "conflicting_observations"
    ]) && uuid(data.callback_id) && (!p || sameUuid(data.callback_id, p.callback_id)) && utc(data.recorded_at) && typeof data.replay === "boolean" && [
      "send_started",
      "observed_sent",
      "uncertain"
    ].includes(data.state) && dispatchCounts(data, p?.segment_count);
  }
  if (action === "attempt_status") {
    return keys(data, [
      "attempt_id",
      "fence_version",
      "state",
      "armed_at",
      "sent_observations",
      "delivery_observations",
      "conflicting_observations",
      "terminal_archive_ack",
      "carrier_proof",
      "segment_count"
    ]) && uuid(data.attempt_id) && integer(data.fence_version, 1, 1e9) && (!p || sameUuid(data.attempt_id, p.attempt_id) && data.fence_version === p.fence_version) && [
      "granted",
      "send_started",
      "observed_sent",
      "uncertain"
    ].includes(data.state) && (data.armed_at === null || utc(data.armed_at)) && data.terminal_archive_ack === false && integer(data.segment_count, 1, 10) && dispatchCounts(data, data.segment_count);
  }
  if (!keys(data, [
    "target_request_id",
    "outcome",
    "recorded_action",
    "recorded_result"
  ]) || !uuid(data.target_request_id) || p && !sameUuid(data.target_request_id, p.target_request_id)) return false;
  if (data.outcome === "unknown") {
    return data.recorded_action === null && data.recorded_result === null;
  }
  if (data.outcome !== "recorded" || typeof data.recorded_action !== "string" || ![
    "dispatch_grant",
    "arm_dispatch",
    "callback",
    "attempt_status"
  ].includes(data.recorded_action)) return false;
  // A lookup proves that the original request was recorded. It cannot recover
  // a body or replay a carrier permit, even while its original lease is live.
  if (data.recorded_action === "dispatch_grant" || data.recorded_action === "arm_dispatch") {
    return dispatchRefusal(data.recorded_result, device, data.target_request_id) && data.recorded_result.code === "ORIGINAL_REQUEST_RECORDED" && data.recorded_result.replay === true;
  }
  return await validDispatchResult(data.recorded_action, data.recorded_result, device, data.target_request_id, now);
}
function response(status, data) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff"
    }
  });
}
export function createGatewayHandler(deps) {
  const now = deps.now ?? Date.now;
  const timeout = Math.min(10000, Math.max(1, deps.timeoutMs ?? 5000));
  async function rpc(name, args) {
    const controller = new AbortController();
    let timer;
    try {
      const operation = deps.rpc(name, args, controller.signal);
      const result = await Promise.race([
        operation,
        new Promise((_, reject)=>{
          timer = setTimeout(()=>{
            controller.abort();
            reject(new Refusal(504, "GATEWAY_OUTCOME_UNKNOWN"));
          }, timeout);
        })
      ]);
      if (result.error) {
        if (result.error.code === "42501") {
          throw new Refusal(403, "GATEWAY_AUTHORITY_REFUSED");
        }
        if ([
          "22023",
          "23505",
          "55000"
        ].includes(result.error.code ?? "")) {
          throw new Refusal(409, "GATEWAY_REQUEST_REFUSED");
        }
        throw new Refusal(503, "GATEWAY_OUTCOME_UNKNOWN");
      }
      if (JSON.stringify(result.data).length > 8192) {
        throw new Refusal(502, "GATEWAY_OUTCOME_UNKNOWN");
      }
      return result.data;
    } finally{
      if (timer !== undefined) clearTimeout(timer);
    }
  }
  return async (request)=>{
    try {
      if (request.method !== "POST") {
        throw new Refusal(405, "GATEWAY_POST_REQUIRED");
      }
      const raw = await body(request, timeout);
      let text;
      try {
        text = new TextDecoder("utf-8", {
          fatal: true
        }).decode(raw);
      } catch  {
        throw new Refusal(400, "GATEWAY_REQUEST_INVALID");
      }
      const envelope = parseStrict(text);
      require(keys(envelope, [
        "contract_version",
        "action",
        "device_id",
        "request_id",
        "issued_at",
        "payload"
      ]));
      require(typeof envelope.action === "string" && (envelope.contract_version === 1 && Object.hasOwn(V1_RPC, envelope.action) || envelope.contract_version === 2 && Object.hasOwn(V2_RPC, envelope.action) || envelope.contract_version === 3 && Object.hasOwn(ARCHIVE_RPC, envelope.action)));
      require(uuid(envelope.device_id) && uuid(envelope.request_id) && utc(envelope.issued_at));
      require(Math.abs(now() - Date.parse(envelope.issued_at)) <= 120000);
      const action = envelope.action;
      if (envelope.contract_version === 3) {
        require(archivePayload(action, envelope.payload, envelope.request_id));
      } else payload(action, envelope.payload);
      if (action === "callback") {
        require(envelope.payload.callback_id !== envelope.request_id);
        if (envelope.contract_version === 2) {
          require(!sameUuid(envelope.payload.callback_id, envelope.request_id));
        }
      }
      if (envelope.contract_version === 2 && action === "arm_dispatch") {
        for (const callback of envelope.payload.callbacks){
          for (const id of [
            callback.sent_callback_id,
            callback.delivery_callback_id
          ]){
            require(!sameUuid(id, envelope.request_id) && !sameUuid(id, envelope.payload.attempt_id));
          }
        }
      }
      const keyId = request.headers.get("X-Collect-Gateway-Key-Id");
      require(hash(keyId));
      const signature = derToP1363(base64(request.headers.get("X-Collect-Gateway-Signature"), 100));
      const key = await rpc("gateway_device_key_v1", {
        p_device_id: envelope.device_id
      });
      if (!keys(key, [
        "device_id",
        "state",
        "public_key_spki_base64",
        "key_sha256",
        "installation_id",
        "signing_certificate_sha256"
      ]) || (envelope.contract_version !== 1 ? !sameUuid(key.device_id, envelope.device_id) : key.device_id !== envelope.device_id) || ![
        "pending",
        "active",
        "revoked"
      ].includes(key.state) || !uuid(key.installation_id) || !hash(key.key_sha256) || !hash(key.signing_certificate_sha256)) {
        throw new Refusal(401, "GATEWAY_KEY_REFUSED");
      }
      const spki = base64(key.public_key_spki_base64, 124);
      if (spki.length !== 91 || await digest(spki) !== key.key_sha256 || key.key_sha256 !== keyId) {
        throw new Refusal(401, "GATEWAY_KEY_REFUSED");
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
      if (!verified) {
        throw new Refusal(401, "GATEWAY_SIGNATURE_REFUSED");
      }
      if (key.state === "revoked" && action !== "callback" && action !== "reconcile" && !(envelope.contract_version === 2 && action === "attempt_status") && envelope.contract_version !== 3) {
        throw new Refusal(403, "GATEWAY_DEVICE_REVOKED");
      }
      const name = envelope.contract_version === 1 ? V1_RPC[action] : envelope.contract_version === 2 ? V2_RPC[action] : ARCHIVE_RPC[action];
      const result = await rpc(name, {
        p_device_id: envelope.device_id,
        p_request_id: envelope.request_id,
        p_request_sha256: await digest(raw),
        p_payload: envelope.payload
      });
      if (!(envelope.contract_version === 1 ? validResult(action, result, envelope.device_id, envelope.request_id, envelope.payload) : envelope.contract_version === 3 ? archiveResult(action, result, envelope.device_id, envelope.request_id, envelope.payload) : await validDispatchResult(action, result, envelope.device_id, envelope.request_id, now(), envelope.payload))) {
        throw new Refusal(502, "GATEWAY_OUTCOME_UNKNOWN");
      }
      return response(200, {
        contract_version: envelope.contract_version,
        action,
        device_id: envelope.device_id,
        request_id: envelope.request_id,
        result
      });
    } catch (error) {
      if (error instanceof Refusal) {
        return response(error.status, {
          ok: false,
          code: error.code
        });
      }
      return response(503, {
        ok: false,
        code: "GATEWAY_OUTCOME_UNKNOWN"
      });
    }
  };
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtYW5kcm9pZC1nYXRld2F5L2hhbmRsZXIudHMiXSwic291cmNlc0NvbnRlbnQiOlsiaW1wb3J0IHtcbiAgQVJDSElWRV9SUEMsXG4gIHR5cGUgQXJjaGl2ZUFjdGlvbixcbiAgYXJjaGl2ZVBheWxvYWQsXG4gIGFyY2hpdmVSZXN1bHQsXG59IGZyb20gXCIuL2FyY2hpdmVfdjMudHNcIjtcbnR5cGUgSnNvbiA9IFJlY29yZDxzdHJpbmcsIHVua25vd24+O1xudHlwZSBWMUFjdGlvbiA9IFwiaGVhcnRiZWF0XCIgfCBcInJlY29uY2lsZVwiIHwgXCJjYWxsYmFja1wiIHwgXCJkaXNwYXRjaF9ncmFudFwiO1xudHlwZSBWMkFjdGlvbiA9XG4gIHwgXCJkaXNwYXRjaF9ncmFudFwiXG4gIHwgXCJhcm1fZGlzcGF0Y2hcIlxuICB8IFwiY2FsbGJhY2tcIlxuICB8IFwicmVjb25jaWxlXCJcbiAgfCBcImF0dGVtcHRfc3RhdHVzXCI7XG50eXBlIEFjdGlvbiA9IFYxQWN0aW9uIHwgVjJBY3Rpb24gfCBBcmNoaXZlQWN0aW9uO1xuY29uc3QgVjFfUlBDOiBSZWNvcmQ8VjFBY3Rpb24sIHN0cmluZz4gPSB7XG4gIGhlYXJ0YmVhdDogXCJnYXRld2F5X2hlYXJ0YmVhdF92MVwiLFxuICBjYWxsYmFjazogXCJnYXRld2F5X2NhbGxiYWNrX3YxXCIsXG4gIHJlY29uY2lsZTogXCJnYXRld2F5X3JlY29uY2lsZV92MVwiLFxuICBkaXNwYXRjaF9ncmFudDogXCJnYXRld2F5X2Rpc3BhdGNoX2dyYW50X3YxXCIsXG59O1xuY29uc3QgVjJfUlBDOiBSZWNvcmQ8VjJBY3Rpb24sIHN0cmluZz4gPSB7XG4gIGRpc3BhdGNoX2dyYW50OiBcImdhdGV3YXlfZGlzcGF0Y2hfZ3JhbnRfdjJcIixcbiAgYXJtX2Rpc3BhdGNoOiBcImdhdGV3YXlfYXJtX2Rpc3BhdGNoX3YyXCIsXG4gIGNhbGxiYWNrOiBcImdhdGV3YXlfY2FsbGJhY2tfdjJcIixcbiAgcmVjb25jaWxlOiBcImdhdGV3YXlfcmVjb25jaWxlX3YyXCIsXG4gIGF0dGVtcHRfc3RhdHVzOiBcImdhdGV3YXlfYXR0ZW1wdF9zdGF0dXNfdjJcIixcbn07XG5leHBvcnQgaW50ZXJmYWNlIEdhdGV3YXlEZXBlbmRlbmNpZXMge1xuICBycGMoXG4gICAgbmFtZTogc3RyaW5nLFxuICAgIGFyZ3M6IEpzb24sXG4gICAgc2lnbmFsOiBBYm9ydFNpZ25hbCxcbiAgKTogUHJvbWlzZTx7IGRhdGE6IHVua25vd247IGVycm9yOiB7IGNvZGU/OiBzdHJpbmcgfSB8IG51bGwgfT47XG4gIG5vdz86ICgpID0+IG51bWJlcjtcbiAgdGltZW91dE1zPzogbnVtYmVyO1xufVxuY29uc3QgVVVJRCA9IC9eWzAtOWEtZl17OH0tWzAtOWEtZl17NH0tWzAtOWEtZl17NH0tWzAtOWEtZl17NH0tWzAtOWEtZl17MTJ9JC9pO1xuY29uc3QgSEFTSCA9IC9eWzAtOWEtZl17NjR9JC87XG5jbGFzcyBSZWZ1c2FsIGV4dGVuZHMgRXJyb3Ige1xuICBjb25zdHJ1Y3RvcihyZWFkb25seSBzdGF0dXM6IG51bWJlciwgcmVhZG9ubHkgY29kZTogc3RyaW5nKSB7XG4gICAgc3VwZXIoY29kZSk7XG4gIH1cbn1cbmZ1bmN0aW9uIG9iamVjdCh2YWx1ZTogdW5rbm93bik6IHZhbHVlIGlzIEpzb24ge1xuICByZXR1cm4gdHlwZW9mIHZhbHVlID09PSBcIm9iamVjdFwiICYmIHZhbHVlICE9PSBudWxsICYmICFBcnJheS5pc0FycmF5KHZhbHVlKTtcbn1cbmZ1bmN0aW9uIGtleXModmFsdWU6IHVua25vd24sIGV4cGVjdGVkOiBzdHJpbmdbXSk6IHZhbHVlIGlzIEpzb24ge1xuICByZXR1cm4gb2JqZWN0KHZhbHVlKSAmJiBPYmplY3Qua2V5cyh2YWx1ZSkubGVuZ3RoID09PSBleHBlY3RlZC5sZW5ndGggJiZcbiAgICBleHBlY3RlZC5ldmVyeSgoaykgPT4gT2JqZWN0Lmhhc093bih2YWx1ZSwgaykpO1xufVxuZnVuY3Rpb24gdXVpZCh2YWx1ZTogdW5rbm93bik6IHZhbHVlIGlzIHN0cmluZyB7XG4gIHJldHVybiB0eXBlb2YgdmFsdWUgPT09IFwic3RyaW5nXCIgJiYgVVVJRC50ZXN0KHZhbHVlKTtcbn1cbmZ1bmN0aW9uIGhhc2godmFsdWU6IHVua25vd24pOiB2YWx1ZSBpcyBzdHJpbmcge1xuICByZXR1cm4gdHlwZW9mIHZhbHVlID09PSBcInN0cmluZ1wiICYmIEhBU0gudGVzdCh2YWx1ZSk7XG59XG5mdW5jdGlvbiBpbnRlZ2VyKHZhbHVlOiB1bmtub3duLCBtaW46IG51bWJlciwgbWF4OiBudW1iZXIpOiB2YWx1ZSBpcyBudW1iZXIge1xuICByZXR1cm4gdHlwZW9mIHZhbHVlID09PSBcIm51bWJlclwiICYmIE51bWJlci5pc1NhZmVJbnRlZ2VyKHZhbHVlKSAmJlxuICAgIHZhbHVlID49IG1pbiAmJiB2YWx1ZSA8PSBtYXg7XG59XG5mdW5jdGlvbiB1dGModmFsdWU6IHVua25vd24pOiB2YWx1ZSBpcyBzdHJpbmcge1xuICBpZiAoXG4gICAgdHlwZW9mIHZhbHVlICE9PSBcInN0cmluZ1wiIHx8XG4gICAgIS9eXFxkezR9LVxcZHsyfS1cXGR7Mn1UXFxkezJ9OlxcZHsyfTpcXGR7Mn0oXFwuXFxkezEsNn0pP1okLy50ZXN0KHZhbHVlKVxuICApIHJldHVybiBmYWxzZTtcbiAgY29uc3QgbXMgPSBEYXRlLnBhcnNlKHZhbHVlKTtcbiAgcmV0dXJuIE51bWJlci5pc0Zpbml0ZShtcykgJiZcbiAgICBuZXcgRGF0ZShtcykudG9JU09TdHJpbmcoKS5zbGljZSgwLCAxOSkgPT09IHZhbHVlLnNsaWNlKDAsIDE5KTtcbn1cbmZ1bmN0aW9uIHJlcXVpcmUoY29uZGl0aW9uOiB1bmtub3duKTogYXNzZXJ0cyBjb25kaXRpb24ge1xuICBpZiAoIWNvbmRpdGlvbikgdGhyb3cgbmV3IFJlZnVzYWwoNDAwLCBcIkdBVEVXQVlfUkVRVUVTVF9JTlZBTElEXCIpO1xufVxuZnVuY3Rpb24gYmFzZTY0KHZhbHVlOiB1bmtub3duLCBtYXg6IG51bWJlcik6IFVpbnQ4QXJyYXkge1xuICByZXF1aXJlKFxuICAgIHR5cGVvZiB2YWx1ZSA9PT0gXCJzdHJpbmdcIiAmJiB2YWx1ZS5sZW5ndGggPD0gbWF4ICYmXG4gICAgICAvXig/OltBLVphLXowLTkrL117NH0pKig/OltBLVphLXowLTkrL117Mn09PXxbQS1aYS16MC05Ky9dezN9PSk/JC8udGVzdChcbiAgICAgICAgdmFsdWUsXG4gICAgICApLFxuICApO1xuICBsZXQgZGVjb2RlZDogc3RyaW5nO1xuICB0cnkge1xuICAgIGRlY29kZWQgPSBhdG9iKHZhbHVlKTtcbiAgfSBjYXRjaCB7XG4gICAgdGhyb3cgbmV3IFJlZnVzYWwoNDAwLCBcIkdBVEVXQVlfUkVRVUVTVF9JTlZBTElEXCIpO1xuICB9XG4gIHJlcXVpcmUoYnRvYShkZWNvZGVkKSA9PT0gdmFsdWUpO1xuICByZXR1cm4gVWludDhBcnJheS5mcm9tKGRlY29kZWQsIChjKSA9PiBjLmNoYXJDb2RlQXQoMCkpO1xufVxuZnVuY3Rpb24gaGV4KGJ5dGVzOiBVaW50OEFycmF5KTogc3RyaW5nIHtcbiAgcmV0dXJuIEFycmF5LmZyb20oYnl0ZXMsIChiKSA9PiBiLnRvU3RyaW5nKDE2KS5wYWRTdGFydCgyLCBcIjBcIikpLmpvaW4oXCJcIik7XG59XG5hc3luYyBmdW5jdGlvbiBkaWdlc3QoYnl0ZXM6IFVpbnQ4QXJyYXkpOiBQcm9taXNlPHN0cmluZz4ge1xuICByZXR1cm4gaGV4KFxuICAgIG5ldyBVaW50OEFycmF5KFxuICAgICAgYXdhaXQgY3J5cHRvLnN1YnRsZS5kaWdlc3QoXCJTSEEtMjU2XCIsIG5ldyBVaW50OEFycmF5KGJ5dGVzKSksXG4gICAgKSxcbiAgKTtcbn1cbi8vIEFuZHJvaWQgZW1pdHMgY2Fub25pY2FsIERFUjsgV2ViQ3J5cHRvIGV4cGVjdHMgZml4ZWQtd2lkdGggUDEzNjMgcnx8cy5cbmV4cG9ydCBmdW5jdGlvbiBkZXJUb1AxMzYzKGRlcjogVWludDhBcnJheSk6IFVpbnQ4QXJyYXkge1xuICByZXF1aXJlKFxuICAgIGRlci5sZW5ndGggPj0gOCAmJiBkZXIubGVuZ3RoIDw9IDcyICYmIGRlclswXSA9PT0gMHgzMCAmJlxuICAgICAgZGVyWzFdID09PSBkZXIubGVuZ3RoIC0gMixcbiAgKTtcbiAgbGV0IG9mZnNldCA9IDI7XG4gIGNvbnN0IG91dHB1dCA9IG5ldyBVaW50OEFycmF5KDY0KTtcbiAgZm9yIChsZXQgY29tcG9uZW50ID0gMDsgY29tcG9uZW50IDwgMjsgY29tcG9uZW50KyspIHtcbiAgICByZXF1aXJlKGRlcltvZmZzZXQrK10gPT09IDB4MDIpO1xuICAgIGNvbnN0IHNpemUgPSBkZXJbb2Zmc2V0KytdO1xuICAgIHJlcXVpcmUoc2l6ZSA+PSAxICYmIHNpemUgPD0gMzMgJiYgb2Zmc2V0ICsgc2l6ZSA8PSBkZXIubGVuZ3RoKTtcbiAgICBsZXQgdmFsdWUgPSBkZXIuc2xpY2Uob2Zmc2V0LCBvZmZzZXQgKyBzaXplKTtcbiAgICBvZmZzZXQgKz0gc2l6ZTtcbiAgICByZXF1aXJlKCEodmFsdWVbMF0gJiAweDgwKSk7XG4gICAgcmVxdWlyZSh2YWx1ZS5sZW5ndGggPT09IDEgfHwgdmFsdWVbMF0gIT09IDAgfHwgISEodmFsdWVbMV0gJiAweDgwKSk7XG4gICAgaWYgKHZhbHVlWzBdID09PSAwKSB2YWx1ZSA9IHZhbHVlLnNsaWNlKDEpO1xuICAgIHJlcXVpcmUodmFsdWUubGVuZ3RoIDw9IDMyICYmIHZhbHVlLmxlbmd0aCA+IDApO1xuICAgIGNvbnN0IG51bWJlciA9IEJpZ0ludChcIjB4XCIgKyBoZXgodmFsdWUpKTtcbiAgICByZXF1aXJlKFxuICAgICAgbnVtYmVyID4gMG4gJiZcbiAgICAgICAgbnVtYmVyIDxcbiAgICAgICAgICAweGZmZmZmZmZmMDAwMDAwMDBmZmZmZmZmZmZmZmZmZmZmYmNlNmZhYWRhNzE3OWU4NGYzYjljYWMyZmM2MzI1NTFuLFxuICAgICk7XG4gICAgb3V0cHV0LnNldCh2YWx1ZSwgY29tcG9uZW50ICogMzIgKyAzMiAtIHZhbHVlLmxlbmd0aCk7XG4gIH1cbiAgcmVxdWlyZShvZmZzZXQgPT09IGRlci5sZW5ndGgpO1xuICByZXR1cm4gb3V0cHV0O1xufVxuLy8gUmVqZWN0IGR1cGxpY2F0ZSBrZXlzIGJlZm9yZSBKU09OLnBhcnNlIGxvc2VzIHRoZW07IGltcG9zZSBhIHNoYWxsb3cgYm91bmQuXG5mdW5jdGlvbiBwYXJzZVN0cmljdCh0ZXh0OiBzdHJpbmcpOiB1bmtub3duIHtcbiAgbGV0IGF0ID0gMDtcbiAgY29uc3Qgd3MgPSAoKSA9PiB7XG4gICAgd2hpbGUgKC9bXFx0XFxuXFxyIF0vLnRlc3QodGV4dFthdF0gPz8gXCJ4XCIpKSBhdCsrO1xuICB9O1xuICBjb25zdCBzdHJpbmcgPSAoKTogc3RyaW5nID0+IHtcbiAgICByZXF1aXJlKHRleHRbYXRdID09PSAnXCInKTtcbiAgICBjb25zdCBzdGFydCA9IGF0Kys7XG4gICAgd2hpbGUgKGF0IDwgdGV4dC5sZW5ndGgpIHtcbiAgICAgIGlmICh0ZXh0W2F0KytdID09PSBcIlxcXFxcIikge1xuICAgICAgICBhdCsrO1xuICAgICAgICBjb250aW51ZTtcbiAgICAgIH1cbiAgICAgIGlmICh0ZXh0W2F0IC0gMV0gPT09ICdcIicpIHJldHVybiBKU09OLnBhcnNlKHRleHQuc2xpY2Uoc3RhcnQsIGF0KSk7XG4gICAgfVxuICAgIHRocm93IG5ldyBSZWZ1c2FsKDQwMCwgXCJHQVRFV0FZX1JFUVVFU1RfSU5WQUxJRFwiKTtcbiAgfTtcbiAgY29uc3QgdmFsdWUgPSAoZGVwdGg6IG51bWJlcik6IHZvaWQgPT4ge1xuICAgIHJlcXVpcmUoZGVwdGggPD0gOCk7XG4gICAgd3MoKTtcbiAgICBpZiAodGV4dFthdF0gPT09IFwie1wiKSB7XG4gICAgICBhdCsrO1xuICAgICAgd3MoKTtcbiAgICAgIGNvbnN0IHNlZW4gPSBuZXcgU2V0PHN0cmluZz4oKTtcbiAgICAgIGlmICh0ZXh0W2F0XSA9PT0gXCJ9XCIpIHtcbiAgICAgICAgYXQrKztcbiAgICAgICAgcmV0dXJuO1xuICAgICAgfVxuICAgICAgd2hpbGUgKHRydWUpIHtcbiAgICAgICAgd3MoKTtcbiAgICAgICAgY29uc3Qga2V5ID0gc3RyaW5nKCk7XG4gICAgICAgIHJlcXVpcmUoIXNlZW4uaGFzKGtleSkpO1xuICAgICAgICBzZWVuLmFkZChrZXkpO1xuICAgICAgICB3cygpO1xuICAgICAgICByZXF1aXJlKHRleHRbYXQrK10gPT09IFwiOlwiKTtcbiAgICAgICAgdmFsdWUoZGVwdGggKyAxKTtcbiAgICAgICAgd3MoKTtcbiAgICAgICAgaWYgKHRleHRbYXRdID09PSBcIn1cIikge1xuICAgICAgICAgIGF0Kys7XG4gICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG4gICAgICAgIHJlcXVpcmUodGV4dFthdCsrXSA9PT0gXCIsXCIpO1xuICAgICAgfVxuICAgIH0gZWxzZSBpZiAodGV4dFthdF0gPT09IFwiW1wiKSB7XG4gICAgICBhdCsrO1xuICAgICAgd3MoKTtcbiAgICAgIGlmICh0ZXh0W2F0XSA9PT0gXCJdXCIpIHtcbiAgICAgICAgYXQrKztcbiAgICAgICAgcmV0dXJuO1xuICAgICAgfVxuICAgICAgd2hpbGUgKHRydWUpIHtcbiAgICAgICAgdmFsdWUoZGVwdGggKyAxKTtcbiAgICAgICAgd3MoKTtcbiAgICAgICAgaWYgKHRleHRbYXRdID09PSBcIl1cIikge1xuICAgICAgICAgIGF0Kys7XG4gICAgICAgICAgcmV0dXJuO1xuICAgICAgICB9XG4gICAgICAgIHJlcXVpcmUodGV4dFthdCsrXSA9PT0gXCIsXCIpO1xuICAgICAgfVxuICAgIH0gZWxzZSBpZiAodGV4dFthdF0gPT09ICdcIicpIHN0cmluZygpO1xuICAgIGVsc2Uge1xuICAgICAgY29uc3QgdG9rZW4gPVxuICAgICAgICAvXig/OnRydWV8ZmFsc2V8bnVsbHwtPyg/OjB8WzEtOV1cXGQqKSg/OlxcLlxcZCspPyg/OltlRV1bKy1dP1xcZCspPykvLmV4ZWMoXG4gICAgICAgICAgdGV4dC5zbGljZShhdCksXG4gICAgICAgICk7XG4gICAgICByZXF1aXJlKHRva2VuKTtcbiAgICAgIGF0ICs9IHRva2VuWzBdLmxlbmd0aDtcbiAgICB9XG4gIH07XG4gIHZhbHVlKDApO1xuICB3cygpO1xuICByZXF1aXJlKGF0ID09PSB0ZXh0Lmxlbmd0aCk7XG4gIHRyeSB7XG4gICAgcmV0dXJuIEpTT04ucGFyc2UodGV4dCk7XG4gIH0gY2F0Y2gge1xuICAgIHRocm93IG5ldyBSZWZ1c2FsKDQwMCwgXCJHQVRFV0FZX1JFUVVFU1RfSU5WQUxJRFwiKTtcbiAgfVxufVxuYXN5bmMgZnVuY3Rpb24gYm9keShyZXF1ZXN0OiBSZXF1ZXN0LCB0aW1lb3V0OiBudW1iZXIpOiBQcm9taXNlPFVpbnQ4QXJyYXk+IHtcbiAgcmVxdWlyZShcbiAgICAvXmFwcGxpY2F0aW9uXFwvanNvbig/OjtcXHMqY2hhcnNldD11dGYtOCk/JC9pLnRlc3QoXG4gICAgICByZXF1ZXN0LmhlYWRlcnMuZ2V0KFwiY29udGVudC10eXBlXCIpID8/IFwiXCIsXG4gICAgKSxcbiAgKTtcbiAgcmVxdWlyZSghcmVxdWVzdC5oZWFkZXJzLmhhcyhcImNvbnRlbnQtZW5jb2RpbmdcIikpO1xuICBjb25zdCBsZW5ndGggPSByZXF1ZXN0LmhlYWRlcnMuZ2V0KFwiY29udGVudC1sZW5ndGhcIik7XG4gIGlmIChsZW5ndGggIT09IG51bGwpIHJlcXVpcmUoL15cXGQrJC8udGVzdChsZW5ndGgpICYmIE51bWJlcihsZW5ndGgpIDw9IDgxOTIpO1xuICByZXF1aXJlKHJlcXVlc3QuYm9keSk7XG4gIGNvbnN0IHJlYWRlciA9IHJlcXVlc3QuYm9keS5nZXRSZWFkZXIoKTtcbiAgY29uc3QgY2h1bmtzOiBVaW50OEFycmF5W10gPSBbXTtcbiAgbGV0IGNvdW50ID0gMDtcbiAgY29uc3QgZGVhZGxpbmUgPSBEYXRlLm5vdygpICsgdGltZW91dDtcbiAgdHJ5IHtcbiAgICB3aGlsZSAodHJ1ZSkge1xuICAgICAgbGV0IHRpbWVyOiBSZXR1cm5UeXBlPHR5cGVvZiBzZXRUaW1lb3V0PiB8IHVuZGVmaW5lZDtcbiAgICAgIGNvbnN0IGNodW5rID0gYXdhaXQgUHJvbWlzZS5yYWNlKFtcbiAgICAgICAgcmVhZGVyLnJlYWQoKSxcbiAgICAgICAgbmV3IFByb21pc2U8bmV2ZXI+KChfLCByZWplY3QpID0+IHtcbiAgICAgICAgICB0aW1lciA9IHNldFRpbWVvdXQoKCkgPT4ge1xuICAgICAgICAgICAgcmVhZGVyLmNhbmNlbCgpLmNhdGNoKCgpID0+IHt9KTtcbiAgICAgICAgICAgIHJlamVjdChuZXcgUmVmdXNhbCg0MDgsIFwiR0FURVdBWV9SRVFVRVNUX0lOVkFMSURcIikpO1xuICAgICAgICAgIH0sIE1hdGgubWF4KDEsIGRlYWRsaW5lIC0gRGF0ZS5ub3coKSkpO1xuICAgICAgICB9KSxcbiAgICAgIF0pLmZpbmFsbHkoKCkgPT4ge1xuICAgICAgICBpZiAodGltZXIgIT09IHVuZGVmaW5lZCkgY2xlYXJUaW1lb3V0KHRpbWVyKTtcbiAgICAgIH0pO1xuICAgICAgaWYgKGNodW5rLmRvbmUpIGJyZWFrO1xuICAgICAgY291bnQgKz0gY2h1bmsudmFsdWUubGVuZ3RoO1xuICAgICAgaWYgKGNvdW50ID4gODE5Mikge1xuICAgICAgICBhd2FpdCByZWFkZXIuY2FuY2VsKCk7XG4gICAgICAgIHRocm93IG5ldyBSZWZ1c2FsKDQxMywgXCJHQVRFV0FZX0JPRFlfVE9PX0xBUkdFXCIpO1xuICAgICAgfVxuICAgICAgY2h1bmtzLnB1c2goY2h1bmsudmFsdWUpO1xuICAgIH1cbiAgfSBmaW5hbGx5IHtcbiAgICByZWFkZXIucmVsZWFzZUxvY2soKTtcbiAgfVxuICByZXF1aXJlKGNvdW50ID4gMCAmJiAobGVuZ3RoID09PSBudWxsIHx8IE51bWJlcihsZW5ndGgpID09PSBjb3VudCkpO1xuICBjb25zdCByZXN1bHQgPSBuZXcgVWludDhBcnJheShjb3VudCk7XG4gIGxldCBvZmZzZXQgPSAwO1xuICBmb3IgKGNvbnN0IGNodW5rIG9mIGNodW5rcykge1xuICAgIHJlc3VsdC5zZXQoY2h1bmssIG9mZnNldCk7XG4gICAgb2Zmc2V0ICs9IGNodW5rLmxlbmd0aDtcbiAgfVxuICByZXF1aXJlKCEocmVzdWx0WzBdID09PSAweGVmICYmIHJlc3VsdFsxXSA9PT0gMHhiYiAmJiByZXN1bHRbMl0gPT09IDB4YmYpKTtcbiAgcmV0dXJuIHJlc3VsdDtcbn1cbmZ1bmN0aW9uIHBheWxvYWQoYWN0aW9uOiBWMUFjdGlvbiB8IFYyQWN0aW9uLCBwOiB1bmtub3duKTogYXNzZXJ0cyBwIGlzIEpzb24ge1xuICBpZiAoYWN0aW9uID09PSBcImhlYXJ0YmVhdFwiKSB7XG4gICAgcmVxdWlyZShcbiAgICAgIGtleXMocCwgW1xuICAgICAgICBcInNtc19wZXJtaXNzaW9uXCIsXG4gICAgICAgIFwibmV0d29ya1wiLFxuICAgICAgICBcInRlbGVwaG9ueVwiLFxuICAgICAgICBcInNpbV9zZWxlY3RlZFwiLFxuICAgICAgICBcInNpbV9yZXZpc2lvbl9zaGEyNTZcIixcbiAgICAgICAgXCJsb2NhbF9wYXVzZVwiLFxuICAgICAgICBcInJlcG9ydGVkX2F0XCIsXG4gICAgICBdKSxcbiAgICApO1xuICAgIHJlcXVpcmUoXG4gICAgICB0eXBlb2YgcC5zbXNfcGVybWlzc2lvbiA9PT0gXCJib29sZWFuXCIgJiZcbiAgICAgICAgdHlwZW9mIHAuc2ltX3NlbGVjdGVkID09PSBcImJvb2xlYW5cIiAmJlxuICAgICAgICB0eXBlb2YgcC5sb2NhbF9wYXVzZSA9PT0gXCJib29sZWFuXCIsXG4gICAgKTtcbiAgICByZXF1aXJlKFxuICAgICAgW1widmFsaWRhdGVkXCIsIFwidW52YWxpZGF0ZWRcIiwgXCJvZmZsaW5lXCIsIFwidW5rbm93blwiXS5pbmNsdWRlcyhcbiAgICAgICAgcC5uZXR3b3JrIGFzIHN0cmluZyxcbiAgICAgICksXG4gICAgKTtcbiAgICByZXF1aXJlKFxuICAgICAgW1wicmVhZHlcIiwgXCJ1bmF2YWlsYWJsZVwiLCBcInVua25vd25cIl0uaW5jbHVkZXMocC50ZWxlcGhvbnkgYXMgc3RyaW5nKSxcbiAgICApO1xuICAgIHJlcXVpcmUoXG4gICAgICBwLnNpbV9zZWxlY3RlZFxuICAgICAgICA/IGhhc2gocC5zaW1fcmV2aXNpb25fc2hhMjU2KVxuICAgICAgICA6IHAuc2ltX3JldmlzaW9uX3NoYTI1NiA9PT0gbnVsbCxcbiAgICApO1xuICAgIHJlcXVpcmUodXRjKHAucmVwb3J0ZWRfYXQpKTtcbiAgfSBlbHNlIGlmIChhY3Rpb24gPT09IFwiY2FsbGJhY2tcIikge1xuICAgIHJlcXVpcmUoXG4gICAgICBrZXlzKHAsIFtcbiAgICAgICAgXCJjYWxsYmFja19pZFwiLFxuICAgICAgICBcImF0dGVtcHRfaWRcIixcbiAgICAgICAgXCJmZW5jZV92ZXJzaW9uXCIsXG4gICAgICAgIFwic2VnbWVudF9pbmRleFwiLFxuICAgICAgICBcInNlZ21lbnRfY291bnRcIixcbiAgICAgICAgXCJib2R5X3NoYTI1NlwiLFxuICAgICAgICBcImRlc3RpbmF0aW9uX3NoYTI1NlwiLFxuICAgICAgICBcImNhbGxiYWNrX2tpbmRcIixcbiAgICAgICAgXCJyZXN1bHRfY29kZVwiLFxuICAgICAgICBcInRwX3N0YXR1c1wiLFxuICAgICAgICBcIm9jY3VycmVkX2F0XCIsXG4gICAgICBdKSxcbiAgICApO1xuICAgIHJlcXVpcmUoXG4gICAgICB1dWlkKHAuY2FsbGJhY2tfaWQpICYmIHV1aWQocC5hdHRlbXB0X2lkKSAmJlxuICAgICAgICBpbnRlZ2VyKHAuZmVuY2VfdmVyc2lvbiwgMSwgMWU5KSxcbiAgICApO1xuICAgIHJlcXVpcmUoXG4gICAgICBpbnRlZ2VyKHAuc2VnbWVudF9pbmRleCwgMCwgOSkgJiYgaW50ZWdlcihwLnNlZ21lbnRfY291bnQsIDEsIDEwKSAmJlxuICAgICAgICBwLnNlZ21lbnRfaW5kZXggPCBwLnNlZ21lbnRfY291bnQsXG4gICAgKTtcbiAgICByZXF1aXJlKFxuICAgICAgaGFzaChwLmJvZHlfc2hhMjU2KSAmJiBoYXNoKHAuZGVzdGluYXRpb25fc2hhMjU2KSAmJlxuICAgICAgICBbXCJzZW50XCIsIFwiZGVsaXZlcnlcIl0uaW5jbHVkZXMocC5jYWxsYmFja19raW5kIGFzIHN0cmluZyksXG4gICAgKTtcbiAgICByZXF1aXJlKFxuICAgICAgaW50ZWdlcihwLnJlc3VsdF9jb2RlLCAtMSwgMjAwKSAmJlxuICAgICAgICAocC50cF9zdGF0dXMgPT09IG51bGwgfHwgaW50ZWdlcihwLnRwX3N0YXR1cywgMCwgMjU1KSkgJiZcbiAgICAgICAgdXRjKHAub2NjdXJyZWRfYXQpLFxuICAgICk7XG4gIH0gZWxzZSBpZiAoYWN0aW9uID09PSBcInJlY29uY2lsZVwiKSB7XG4gICAgcmVxdWlyZShrZXlzKHAsIFtcInRhcmdldF9yZXF1ZXN0X2lkXCJdKSAmJiB1dWlkKHAudGFyZ2V0X3JlcXVlc3RfaWQpKTtcbiAgfSBlbHNlIGlmIChhY3Rpb24gPT09IFwiYXR0ZW1wdF9zdGF0dXNcIikge1xuICAgIHJlcXVpcmUoXG4gICAgICBrZXlzKHAsIFtcImF0dGVtcHRfaWRcIiwgXCJmZW5jZV92ZXJzaW9uXCJdKSAmJiB1dWlkKHAuYXR0ZW1wdF9pZCkgJiZcbiAgICAgICAgaW50ZWdlcihwLmZlbmNlX3ZlcnNpb24sIDEsIDFlOSksXG4gICAgKTtcbiAgfSBlbHNlIGlmIChhY3Rpb24gPT09IFwiYXJtX2Rpc3BhdGNoXCIpIHtcbiAgICByZXF1aXJlKFxuICAgICAga2V5cyhwLCBbXG4gICAgICAgIFwiYXR0ZW1wdF9pZFwiLFxuICAgICAgICBcImZlbmNlX3ZlcnNpb25cIixcbiAgICAgICAgXCJib2R5X3NoYTI1NlwiLFxuICAgICAgICBcImRlc3RpbmF0aW9uX3NoYTI1NlwiLFxuICAgICAgICBcImNhbGxiYWNrc1wiLFxuICAgICAgICBcInJlc2VydmF0aW9uX3NoYTI1NlwiLFxuICAgICAgXSksXG4gICAgKTtcbiAgICByZXF1aXJlKFxuICAgICAgdXVpZChwLmF0dGVtcHRfaWQpICYmIGludGVnZXIocC5mZW5jZV92ZXJzaW9uLCAxLCAxZTkpICYmXG4gICAgICAgIGhhc2gocC5ib2R5X3NoYTI1NikgJiYgaGFzaChwLmRlc3RpbmF0aW9uX3NoYTI1NikgJiZcbiAgICAgICAgaGFzaChwLnJlc2VydmF0aW9uX3NoYTI1NikgJiYgQXJyYXkuaXNBcnJheShwLmNhbGxiYWNrcykgJiZcbiAgICAgICAgcC5jYWxsYmFja3MubGVuZ3RoID49IDEgJiYgcC5jYWxsYmFja3MubGVuZ3RoIDw9IDEwLFxuICAgICk7XG4gICAgY29uc3QgY2FsbGJhY2tJZHMgPSBuZXcgU2V0PHN0cmluZz4oKTtcbiAgICBmb3IgKGNvbnN0IFtpbmRleCwgY2FsbGJhY2tdIG9mIHAuY2FsbGJhY2tzLmVudHJpZXMoKSkge1xuICAgICAgcmVxdWlyZShcbiAgICAgICAga2V5cyhjYWxsYmFjaywgW1xuICAgICAgICAgIFwic2VnbWVudF9pbmRleFwiLFxuICAgICAgICAgIFwic2VudF9jYWxsYmFja19pZFwiLFxuICAgICAgICAgIFwiZGVsaXZlcnlfY2FsbGJhY2tfaWRcIixcbiAgICAgICAgXSkgJiYgY2FsbGJhY2suc2VnbWVudF9pbmRleCA9PT0gaW5kZXggJiZcbiAgICAgICAgICB1dWlkKGNhbGxiYWNrLnNlbnRfY2FsbGJhY2tfaWQpICYmXG4gICAgICAgICAgdXVpZChjYWxsYmFjay5kZWxpdmVyeV9jYWxsYmFja19pZCksXG4gICAgICApO1xuICAgICAgZm9yIChcbiAgICAgICAgY29uc3QgaWQgb2YgW2NhbGxiYWNrLnNlbnRfY2FsbGJhY2tfaWQsIGNhbGxiYWNrLmRlbGl2ZXJ5X2NhbGxiYWNrX2lkXVxuICAgICAgKSB7XG4gICAgICAgIGNvbnN0IG5vcm1hbGl6ZWQgPSBpZC50b0xvd2VyQ2FzZSgpO1xuICAgICAgICByZXF1aXJlKCFjYWxsYmFja0lkcy5oYXMobm9ybWFsaXplZCkpO1xuICAgICAgICBjYWxsYmFja0lkcy5hZGQobm9ybWFsaXplZCk7XG4gICAgICB9XG4gICAgfVxuICB9IGVsc2UgcmVxdWlyZShrZXlzKHAsIFtdKSk7XG59XG5mdW5jdGlvbiB2YWxpZFJlc3VsdChcbiAgYWN0aW9uOiBWMUFjdGlvbixcbiAgZGF0YTogdW5rbm93bixcbiAgZGV2aWNlOiBzdHJpbmcsXG4gIHJlcXVlc3Q6IHN0cmluZyxcbiAgcD86IEpzb24sXG4pOiBkYXRhIGlzIEpzb24ge1xuICBpZiAoYWN0aW9uID09PSBcImhlYXJ0YmVhdFwiKSB7XG4gICAgcmV0dXJuIGtleXMoZGF0YSwgW1xuICAgICAgXCJvYnNlcnZhdGlvbl9pZFwiLFxuICAgICAgXCJpbmdlc3RlZF9hdFwiLFxuICAgICAgXCJyZXBsYXlcIixcbiAgICAgIFwiY2Fycmllcl9wcm9vZlwiLFxuICAgIF0pICYmIHV1aWQoZGF0YS5vYnNlcnZhdGlvbl9pZCkgJiYgdXRjKGRhdGEuaW5nZXN0ZWRfYXQpICYmXG4gICAgICB0eXBlb2YgZGF0YS5yZXBsYXkgPT09IFwiYm9vbGVhblwiICYmIGRhdGEuY2Fycmllcl9wcm9vZiA9PT0gZmFsc2U7XG4gIH1cbiAgaWYgKGFjdGlvbiA9PT0gXCJjYWxsYmFja1wiKSB7XG4gICAgcmV0dXJuIGtleXMoZGF0YSwgW1xuICAgICAgXCJjYWxsYmFja19pZFwiLFxuICAgICAgXCJyZWNvcmRlZF9hdFwiLFxuICAgICAgXCJyZXBsYXlcIixcbiAgICAgIFwiY2Fycmllcl9wcm9vZlwiLFxuICAgIF0pICYmIHV1aWQoZGF0YS5jYWxsYmFja19pZCkgJiZcbiAgICAgICghcCB8fCBkYXRhLmNhbGxiYWNrX2lkID09PSBwLmNhbGxiYWNrX2lkKSAmJiB1dGMoZGF0YS5yZWNvcmRlZF9hdCkgJiZcbiAgICAgIHR5cGVvZiBkYXRhLnJlcGxheSA9PT0gXCJib29sZWFuXCIgJiYgZGF0YS5jYXJyaWVyX3Byb29mID09PSBmYWxzZTtcbiAgfVxuICBpZiAoYWN0aW9uID09PSBcImRpc3BhdGNoX2dyYW50XCIpIHtcbiAgICByZXR1cm4ga2V5cyhkYXRhLCBbXCJva1wiLCBcImNvZGVcIiwgXCJkZXZpY2VfaWRcIiwgXCJyZXF1ZXN0X2lkXCIsIFwicmVwbGF5XCJdKSAmJlxuICAgICAgZGF0YS5vayA9PT0gZmFsc2UgJiYgZGF0YS5jb2RlID09PSBcIkdBVEVXQVlfRElTUEFUQ0hfQVVUSE9SSVRZX1BFTkRJTkdcIiAmJlxuICAgICAgZGF0YS5kZXZpY2VfaWQgPT09IGRldmljZSAmJiBkYXRhLnJlcXVlc3RfaWQgPT09IHJlcXVlc3QgJiZcbiAgICAgIHR5cGVvZiBkYXRhLnJlcGxheSA9PT0gXCJib29sZWFuXCI7XG4gIH1cbiAgaWYgKFxuICAgICFrZXlzKGRhdGEsIFtcbiAgICAgIFwidGFyZ2V0X3JlcXVlc3RfaWRcIixcbiAgICAgIFwib3V0Y29tZVwiLFxuICAgICAgXCJyZWNvcmRlZF9hY3Rpb25cIixcbiAgICAgIFwicmVjb3JkZWRfcmVzdWx0XCIsXG4gICAgXSkgfHwgIXV1aWQoZGF0YS50YXJnZXRfcmVxdWVzdF9pZCkgfHxcbiAgICAocCAmJiBkYXRhLnRhcmdldF9yZXF1ZXN0X2lkICE9PSBwLnRhcmdldF9yZXF1ZXN0X2lkKVxuICApIHJldHVybiBmYWxzZTtcbiAgaWYgKGRhdGEub3V0Y29tZSA9PT0gXCJ1bmtub3duXCIpIHtcbiAgICByZXR1cm4gZGF0YS5yZWNvcmRlZF9hY3Rpb24gPT09IG51bGwgJiYgZGF0YS5yZWNvcmRlZF9yZXN1bHQgPT09IG51bGw7XG4gIH1cbiAgaWYgKFxuICAgIGRhdGEub3V0Y29tZSAhPT0gXCJyZWNvcmRlZFwiIHx8XG4gICAgIVtcImhlYXJ0YmVhdFwiLCBcImNhbGxiYWNrXCIsIFwiZGlzcGF0Y2hfZ3JhbnRcIl0uaW5jbHVkZXMoXG4gICAgICBkYXRhLnJlY29yZGVkX2FjdGlvbiBhcyBzdHJpbmcsXG4gICAgKVxuICApIHJldHVybiBmYWxzZTtcbiAgcmV0dXJuIHZhbGlkUmVzdWx0KFxuICAgIGRhdGEucmVjb3JkZWRfYWN0aW9uIGFzIFYxQWN0aW9uLFxuICAgIGRhdGEucmVjb3JkZWRfcmVzdWx0LFxuICAgIGRldmljZSxcbiAgICBkYXRhLnRhcmdldF9yZXF1ZXN0X2lkLFxuICApO1xufVxuZnVuY3Rpb24gc2FtZVV1aWQobGVmdDogdW5rbm93biwgcmlnaHQ6IHVua25vd24pOiBib29sZWFuIHtcbiAgcmV0dXJuIHV1aWQobGVmdCkgJiYgdXVpZChyaWdodCkgJiZcbiAgICBsZWZ0LnRvTG93ZXJDYXNlKCkgPT09IHJpZ2h0LnRvTG93ZXJDYXNlKCk7XG59XG5jb25zdCBESVNQQVRDSF9SRUZVU0FMUyA9IG5ldyBTZXQoW1xuICBcIk9QRVJBVElPTlNfUEFVU0VEXCIsXG4gIFwiTk9fQ1VSUkVOVF9SVU5cIixcbiAgXCJERVZJQ0VfTk9UX1JFQURZXCIsXG4gIFwiTk9fRUxJR0lCTEVfUkVDRUlQVFwiLFxuICBcIlFVT1RBX0VYSEFVU1RFRFwiLFxuICBcIk9SSUdJTkFMX1JFUVVFU1RfUkVDT1JERURcIixcbl0pO1xuZnVuY3Rpb24gZGlzcGF0Y2hSZWZ1c2FsKFxuICBkYXRhOiB1bmtub3duLFxuICBkZXZpY2U6IHN0cmluZyxcbiAgcmVxdWVzdDogc3RyaW5nLFxuKTogZGF0YSBpcyBKc29uIHtcbiAgcmV0dXJuIGtleXMoZGF0YSwgW1wib2tcIiwgXCJjb2RlXCIsIFwiZGV2aWNlX2lkXCIsIFwicmVxdWVzdF9pZFwiLCBcInJlcGxheVwiXSkgJiZcbiAgICBkYXRhLm9rID09PSBmYWxzZSAmJiBESVNQQVRDSF9SRUZVU0FMUy5oYXMoZGF0YS5jb2RlIGFzIHN0cmluZykgJiZcbiAgICBzYW1lVXVpZChkYXRhLmRldmljZV9pZCwgZGV2aWNlKSAmJiBzYW1lVXVpZChkYXRhLnJlcXVlc3RfaWQsIHJlcXVlc3QpICYmXG4gICAgdHlwZW9mIGRhdGEucmVwbGF5ID09PSBcImJvb2xlYW5cIjtcbn1cbmZ1bmN0aW9uIGRpc3BhdGNoRGVhZGxpbmUoXG4gIHN0YXJ0OiB1bmtub3duLFxuICBleHBpcmVzOiB1bmtub3duLFxuICBub3c6IG51bWJlcixcbik6IGJvb2xlYW4ge1xuICByZXR1cm4gdXRjKHN0YXJ0KSAmJiB1dGMoZXhwaXJlcykgJiZcbiAgICBEYXRlLnBhcnNlKGV4cGlyZXMpID4gRGF0ZS5wYXJzZShzdGFydCkgJiZcbiAgICBEYXRlLnBhcnNlKGV4cGlyZXMpIDw9IERhdGUucGFyc2Uoc3RhcnQpICsgMzAwMDAgJiZcbiAgICBEYXRlLnBhcnNlKGV4cGlyZXMpID4gbm93O1xufVxuZnVuY3Rpb24gZGlzcGF0Y2hDb3VudHMoZGF0YTogSnNvbiwgc2VnbWVudENvdW50PzogdW5rbm93bik6IGJvb2xlYW4ge1xuICBjb25zdCBjb3VudCA9IGludGVnZXIoc2VnbWVudENvdW50LCAxLCAxMCkgPyBzZWdtZW50Q291bnQgOiAxMDtcbiAgcmV0dXJuIGludGVnZXIoZGF0YS5zZW50X29ic2VydmF0aW9ucywgMCwgY291bnQpICYmXG4gICAgaW50ZWdlcihkYXRhLmRlbGl2ZXJ5X29ic2VydmF0aW9ucywgMCwgY291bnQpICYmXG4gICAgdHlwZW9mIGRhdGEuY29uZmxpY3Rpbmdfb2JzZXJ2YXRpb25zID09PSBcImJvb2xlYW5cIiAmJlxuICAgIGRhdGEuY2Fycmllcl9wcm9vZiA9PT0gZmFsc2UgJiZcbiAgICAoZGF0YS5zdGF0ZSAhPT0gXCJvYnNlcnZlZF9zZW50XCIgfHxcbiAgICAgIChkYXRhLmNvbmZsaWN0aW5nX29ic2VydmF0aW9ucyA9PT0gZmFsc2UgJiYgZGF0YS5zZW50X29ic2VydmF0aW9ucyA+IDAgJiZcbiAgICAgICAgKHNlZ21lbnRDb3VudCA9PT0gdW5kZWZpbmVkIHx8IGRhdGEuc2VudF9vYnNlcnZhdGlvbnMgPT09IGNvdW50KSkpO1xufVxuYXN5bmMgZnVuY3Rpb24gdmFsaWREaXNwYXRjaFJlc3VsdChcbiAgYWN0aW9uOiBWMkFjdGlvbixcbiAgZGF0YTogdW5rbm93bixcbiAgZGV2aWNlOiBzdHJpbmcsXG4gIHJlcXVlc3Q6IHN0cmluZyxcbiAgbm93OiBudW1iZXIsXG4gIHA/OiBKc29uLFxuKTogUHJvbWlzZTxib29sZWFuPiB7XG4gIGlmIChhY3Rpb24gPT09IFwiZGlzcGF0Y2hfZ3JhbnRcIiB8fCBhY3Rpb24gPT09IFwiYXJtX2Rpc3BhdGNoXCIpIHtcbiAgICBpZiAoZGlzcGF0Y2hSZWZ1c2FsKGRhdGEsIGRldmljZSwgcmVxdWVzdCkpIHJldHVybiB0cnVlO1xuICAgIGlmIChhY3Rpb24gPT09IFwiZGlzcGF0Y2hfZ3JhbnRcIikge1xuICAgICAgaWYgKFxuICAgICAgICAha2V5cyhkYXRhLCBbXG4gICAgICAgICAgXCJva1wiLFxuICAgICAgICAgIFwiY29kZVwiLFxuICAgICAgICAgIFwiZGV2aWNlX2lkXCIsXG4gICAgICAgICAgXCJyZXF1ZXN0X2lkXCIsXG4gICAgICAgICAgXCJhdHRlbXB0X2lkXCIsXG4gICAgICAgICAgXCJyZWNlaXB0X2lkXCIsXG4gICAgICAgICAgXCJydW5faWRcIixcbiAgICAgICAgICBcImZlbmNlX3ZlcnNpb25cIixcbiAgICAgICAgICBcInBvbGljeV9yZXZpc2lvblwiLFxuICAgICAgICAgIFwiaXNzdWVkX2F0XCIsXG4gICAgICAgICAgXCJleHBpcmVzX2F0XCIsXG4gICAgICAgICAgXCJzZWdtZW50X2NvdW50XCIsXG4gICAgICAgICAgXCJib2R5XCIsXG4gICAgICAgICAgXCJkZXN0aW5hdGlvbl9lMTY0XCIsXG4gICAgICAgICAgXCJib2R5X3NoYTI1NlwiLFxuICAgICAgICAgIFwiZGVzdGluYXRpb25fc2hhMjU2XCIsXG4gICAgICAgICAgXCJzaW1fcmV2aXNpb25fc2hhMjU2XCIsXG4gICAgICAgICAgXCJyZXBsYXlcIixcbiAgICAgICAgXSkgfHwgZGF0YS5vayAhPT0gdHJ1ZSB8fCBkYXRhLmNvZGUgIT09IFwiRElTUEFUQ0hfR1JBTlRFRFwiIHx8XG4gICAgICAgICFzYW1lVXVpZChkYXRhLmRldmljZV9pZCwgZGV2aWNlKSB8fFxuICAgICAgICAhc2FtZVV1aWQoZGF0YS5yZXF1ZXN0X2lkLCByZXF1ZXN0KSB8fFxuICAgICAgICAhdXVpZChkYXRhLmF0dGVtcHRfaWQpIHx8ICF1dWlkKGRhdGEucmVjZWlwdF9pZCkgfHxcbiAgICAgICAgIXV1aWQoZGF0YS5ydW5faWQpIHx8XG4gICAgICAgICFpbnRlZ2VyKGRhdGEuZmVuY2VfdmVyc2lvbiwgMSwgMWU5KSB8fFxuICAgICAgICAhaW50ZWdlcihkYXRhLnBvbGljeV9yZXZpc2lvbiwgMSwgMWU5KSB8fFxuICAgICAgICAhZGlzcGF0Y2hEZWFkbGluZShkYXRhLmlzc3VlZF9hdCwgZGF0YS5leHBpcmVzX2F0LCBub3cpIHx8XG4gICAgICAgICFpbnRlZ2VyKGRhdGEuc2VnbWVudF9jb3VudCwgMSwgMTApIHx8XG4gICAgICAgIHR5cGVvZiBkYXRhLmJvZHkgIT09IFwic3RyaW5nXCIgfHwgZGF0YS5ib2R5Lmxlbmd0aCA9PT0gMCB8fFxuICAgICAgICBbLi4uZGF0YS5ib2R5XS5sZW5ndGggPiAxMDAwIHx8XG4gICAgICAgIHR5cGVvZiBkYXRhLmRlc3RpbmF0aW9uX2UxNjQgIT09IFwic3RyaW5nXCIgfHxcbiAgICAgICAgIS9eXFwrMjUwN1syMzg5XVswLTldezd9JC8udGVzdChkYXRhLmRlc3RpbmF0aW9uX2UxNjQpIHx8XG4gICAgICAgICFoYXNoKGRhdGEuYm9keV9zaGEyNTYpIHx8ICFoYXNoKGRhdGEuZGVzdGluYXRpb25fc2hhMjU2KSB8fFxuICAgICAgICAhaGFzaChkYXRhLnNpbV9yZXZpc2lvbl9zaGEyNTYpIHx8IGRhdGEucmVwbGF5ICE9PSBmYWxzZVxuICAgICAgKSByZXR1cm4gZmFsc2U7XG4gICAgICBjb25zdCBlbmNvZGVyID0gbmV3IFRleHRFbmNvZGVyKCk7XG4gICAgICBjb25zdCBlbmNvZGVkQm9keSA9IGVuY29kZXIuZW5jb2RlKGRhdGEuYm9keSk7XG4gICAgICByZXR1cm4gZW5jb2RlZEJvZHkubGVuZ3RoIDw9IDQwMDAgJiZcbiAgICAgICAgYXdhaXQgZGlnZXN0KGVuY29kZWRCb2R5KSA9PT0gZGF0YS5ib2R5X3NoYTI1NiAmJlxuICAgICAgICBhd2FpdCBkaWdlc3QoZW5jb2Rlci5lbmNvZGUoZGF0YS5kZXN0aW5hdGlvbl9lMTY0KSkgPT09XG4gICAgICAgICAgZGF0YS5kZXN0aW5hdGlvbl9zaGEyNTY7XG4gICAgfVxuICAgIHJldHVybiBrZXlzKGRhdGEsIFtcbiAgICAgIFwib2tcIixcbiAgICAgIFwiY29kZVwiLFxuICAgICAgXCJkZXZpY2VfaWRcIixcbiAgICAgIFwicmVxdWVzdF9pZFwiLFxuICAgICAgXCJhdHRlbXB0X2lkXCIsXG4gICAgICBcImZlbmNlX3ZlcnNpb25cIixcbiAgICAgIFwicmVzZXJ2YXRpb25fc2hhMjU2XCIsXG4gICAgICBcImFybWVkX2F0XCIsXG4gICAgICBcImV4cGlyZXNfYXRcIixcbiAgICAgIFwicmVwbGF5XCIsXG4gICAgICBcImNhcnJpZXJfcHJvb2ZcIixcbiAgICBdKSAmJiBkYXRhLm9rID09PSB0cnVlICYmIGRhdGEuY29kZSA9PT0gXCJESVNQQVRDSF9BUk1FRFwiICYmXG4gICAgICBzYW1lVXVpZChkYXRhLmRldmljZV9pZCwgZGV2aWNlKSAmJiBzYW1lVXVpZChkYXRhLnJlcXVlc3RfaWQsIHJlcXVlc3QpICYmXG4gICAgICB1dWlkKGRhdGEuYXR0ZW1wdF9pZCkgJiYgaW50ZWdlcihkYXRhLmZlbmNlX3ZlcnNpb24sIDEsIDFlOSkgJiZcbiAgICAgIGhhc2goZGF0YS5yZXNlcnZhdGlvbl9zaGEyNTYpICYmXG4gICAgICAoIXAgfHwgKHNhbWVVdWlkKGRhdGEuYXR0ZW1wdF9pZCwgcC5hdHRlbXB0X2lkKSAmJlxuICAgICAgICBkYXRhLmZlbmNlX3ZlcnNpb24gPT09IHAuZmVuY2VfdmVyc2lvbiAmJlxuICAgICAgICBkYXRhLnJlc2VydmF0aW9uX3NoYTI1NiA9PT0gcC5yZXNlcnZhdGlvbl9zaGEyNTYpKSAmJlxuICAgICAgZGlzcGF0Y2hEZWFkbGluZShkYXRhLmFybWVkX2F0LCBkYXRhLmV4cGlyZXNfYXQsIG5vdykgJiZcbiAgICAgIGRhdGEucmVwbGF5ID09PSBmYWxzZSAmJiBkYXRhLmNhcnJpZXJfcHJvb2YgPT09IGZhbHNlO1xuICB9XG4gIGlmIChhY3Rpb24gPT09IFwiY2FsbGJhY2tcIikge1xuICAgIHJldHVybiBrZXlzKGRhdGEsIFtcbiAgICAgIFwiY2FsbGJhY2tfaWRcIixcbiAgICAgIFwicmVjb3JkZWRfYXRcIixcbiAgICAgIFwicmVwbGF5XCIsXG4gICAgICBcImNhcnJpZXJfcHJvb2ZcIixcbiAgICAgIFwic3RhdGVcIixcbiAgICAgIFwic2VudF9vYnNlcnZhdGlvbnNcIixcbiAgICAgIFwiZGVsaXZlcnlfb2JzZXJ2YXRpb25zXCIsXG4gICAgICBcImNvbmZsaWN0aW5nX29ic2VydmF0aW9uc1wiLFxuICAgIF0pICYmIHV1aWQoZGF0YS5jYWxsYmFja19pZCkgJiZcbiAgICAgICghcCB8fCBzYW1lVXVpZChkYXRhLmNhbGxiYWNrX2lkLCBwLmNhbGxiYWNrX2lkKSkgJiZcbiAgICAgIHV0YyhkYXRhLnJlY29yZGVkX2F0KSAmJiB0eXBlb2YgZGF0YS5yZXBsYXkgPT09IFwiYm9vbGVhblwiICYmXG4gICAgICBbXCJzZW5kX3N0YXJ0ZWRcIiwgXCJvYnNlcnZlZF9zZW50XCIsIFwidW5jZXJ0YWluXCJdLmluY2x1ZGVzKFxuICAgICAgICBkYXRhLnN0YXRlIGFzIHN0cmluZyxcbiAgICAgICkgJiZcbiAgICAgIGRpc3BhdGNoQ291bnRzKGRhdGEsIHA/LnNlZ21lbnRfY291bnQpO1xuICB9XG4gIGlmIChhY3Rpb24gPT09IFwiYXR0ZW1wdF9zdGF0dXNcIikge1xuICAgIHJldHVybiBrZXlzKGRhdGEsIFtcbiAgICAgIFwiYXR0ZW1wdF9pZFwiLFxuICAgICAgXCJmZW5jZV92ZXJzaW9uXCIsXG4gICAgICBcInN0YXRlXCIsXG4gICAgICBcImFybWVkX2F0XCIsXG4gICAgICBcInNlbnRfb2JzZXJ2YXRpb25zXCIsXG4gICAgICBcImRlbGl2ZXJ5X29ic2VydmF0aW9uc1wiLFxuICAgICAgXCJjb25mbGljdGluZ19vYnNlcnZhdGlvbnNcIixcbiAgICAgIFwidGVybWluYWxfYXJjaGl2ZV9hY2tcIixcbiAgICAgIFwiY2Fycmllcl9wcm9vZlwiLFxuICAgICAgXCJzZWdtZW50X2NvdW50XCIsXG4gICAgXSkgJiYgdXVpZChkYXRhLmF0dGVtcHRfaWQpICYmIGludGVnZXIoZGF0YS5mZW5jZV92ZXJzaW9uLCAxLCAxZTkpICYmXG4gICAgICAoIXAgfHwgKHNhbWVVdWlkKGRhdGEuYXR0ZW1wdF9pZCwgcC5hdHRlbXB0X2lkKSAmJlxuICAgICAgICBkYXRhLmZlbmNlX3ZlcnNpb24gPT09IHAuZmVuY2VfdmVyc2lvbikpICYmXG4gICAgICBbXCJncmFudGVkXCIsIFwic2VuZF9zdGFydGVkXCIsIFwib2JzZXJ2ZWRfc2VudFwiLCBcInVuY2VydGFpblwiXS5pbmNsdWRlcyhcbiAgICAgICAgZGF0YS5zdGF0ZSBhcyBzdHJpbmcsXG4gICAgICApICYmXG4gICAgICAoZGF0YS5hcm1lZF9hdCA9PT0gbnVsbCB8fCB1dGMoZGF0YS5hcm1lZF9hdCkpICYmXG4gICAgICBkYXRhLnRlcm1pbmFsX2FyY2hpdmVfYWNrID09PSBmYWxzZSAmJlxuICAgICAgaW50ZWdlcihkYXRhLnNlZ21lbnRfY291bnQsIDEsIDEwKSAmJlxuICAgICAgZGlzcGF0Y2hDb3VudHMoZGF0YSwgZGF0YS5zZWdtZW50X2NvdW50KTtcbiAgfVxuICBpZiAoXG4gICAgIWtleXMoZGF0YSwgW1xuICAgICAgXCJ0YXJnZXRfcmVxdWVzdF9pZFwiLFxuICAgICAgXCJvdXRjb21lXCIsXG4gICAgICBcInJlY29yZGVkX2FjdGlvblwiLFxuICAgICAgXCJyZWNvcmRlZF9yZXN1bHRcIixcbiAgICBdKSB8fCAhdXVpZChkYXRhLnRhcmdldF9yZXF1ZXN0X2lkKSB8fFxuICAgIChwICYmICFzYW1lVXVpZChkYXRhLnRhcmdldF9yZXF1ZXN0X2lkLCBwLnRhcmdldF9yZXF1ZXN0X2lkKSlcbiAgKSByZXR1cm4gZmFsc2U7XG4gIGlmIChkYXRhLm91dGNvbWUgPT09IFwidW5rbm93blwiKSB7XG4gICAgcmV0dXJuIGRhdGEucmVjb3JkZWRfYWN0aW9uID09PSBudWxsICYmIGRhdGEucmVjb3JkZWRfcmVzdWx0ID09PSBudWxsO1xuICB9XG4gIGlmIChcbiAgICBkYXRhLm91dGNvbWUgIT09IFwicmVjb3JkZWRcIiB8fCB0eXBlb2YgZGF0YS5yZWNvcmRlZF9hY3Rpb24gIT09IFwic3RyaW5nXCIgfHxcbiAgICAhW1wiZGlzcGF0Y2hfZ3JhbnRcIiwgXCJhcm1fZGlzcGF0Y2hcIiwgXCJjYWxsYmFja1wiLCBcImF0dGVtcHRfc3RhdHVzXCJdLmluY2x1ZGVzKFxuICAgICAgZGF0YS5yZWNvcmRlZF9hY3Rpb24sXG4gICAgKVxuICApIHJldHVybiBmYWxzZTtcbiAgLy8gQSBsb29rdXAgcHJvdmVzIHRoYXQgdGhlIG9yaWdpbmFsIHJlcXVlc3Qgd2FzIHJlY29yZGVkLiBJdCBjYW5ub3QgcmVjb3ZlclxuICAvLyBhIGJvZHkgb3IgcmVwbGF5IGEgY2FycmllciBwZXJtaXQsIGV2ZW4gd2hpbGUgaXRzIG9yaWdpbmFsIGxlYXNlIGlzIGxpdmUuXG4gIGlmIChcbiAgICBkYXRhLnJlY29yZGVkX2FjdGlvbiA9PT0gXCJkaXNwYXRjaF9ncmFudFwiIHx8XG4gICAgZGF0YS5yZWNvcmRlZF9hY3Rpb24gPT09IFwiYXJtX2Rpc3BhdGNoXCJcbiAgKSB7XG4gICAgcmV0dXJuIGRpc3BhdGNoUmVmdXNhbChcbiAgICAgIGRhdGEucmVjb3JkZWRfcmVzdWx0LFxuICAgICAgZGV2aWNlLFxuICAgICAgZGF0YS50YXJnZXRfcmVxdWVzdF9pZCxcbiAgICApICYmXG4gICAgICBkYXRhLnJlY29yZGVkX3Jlc3VsdC5jb2RlID09PSBcIk9SSUdJTkFMX1JFUVVFU1RfUkVDT1JERURcIiAmJlxuICAgICAgZGF0YS5yZWNvcmRlZF9yZXN1bHQucmVwbGF5ID09PSB0cnVlO1xuICB9XG4gIHJldHVybiBhd2FpdCB2YWxpZERpc3BhdGNoUmVzdWx0KFxuICAgIGRhdGEucmVjb3JkZWRfYWN0aW9uIGFzIFYyQWN0aW9uLFxuICAgIGRhdGEucmVjb3JkZWRfcmVzdWx0LFxuICAgIGRldmljZSxcbiAgICBkYXRhLnRhcmdldF9yZXF1ZXN0X2lkLFxuICAgIG5vdyxcbiAgKTtcbn1cbmZ1bmN0aW9uIHJlc3BvbnNlKHN0YXR1czogbnVtYmVyLCBkYXRhOiBKc29uKTogUmVzcG9uc2Uge1xuICByZXR1cm4gbmV3IFJlc3BvbnNlKEpTT04uc3RyaW5naWZ5KGRhdGEpLCB7XG4gICAgc3RhdHVzLFxuICAgIGhlYWRlcnM6IHtcbiAgICAgIFwiY29udGVudC10eXBlXCI6IFwiYXBwbGljYXRpb24vanNvbjsgY2hhcnNldD11dGYtOFwiLFxuICAgICAgXCJjYWNoZS1jb250cm9sXCI6IFwibm8tc3RvcmVcIixcbiAgICAgIFwieC1jb250ZW50LXR5cGUtb3B0aW9uc1wiOiBcIm5vc25pZmZcIixcbiAgICB9LFxuICB9KTtcbn1cbmV4cG9ydCBmdW5jdGlvbiBjcmVhdGVHYXRld2F5SGFuZGxlcihcbiAgZGVwczogR2F0ZXdheURlcGVuZGVuY2llcyxcbik6IChyZXF1ZXN0OiBSZXF1ZXN0KSA9PiBQcm9taXNlPFJlc3BvbnNlPiB7XG4gIGNvbnN0IG5vdyA9IGRlcHMubm93ID8/IERhdGUubm93O1xuICBjb25zdCB0aW1lb3V0ID0gTWF0aC5taW4oMTAwMDAsIE1hdGgubWF4KDEsIGRlcHMudGltZW91dE1zID8/IDUwMDApKTtcbiAgYXN5bmMgZnVuY3Rpb24gcnBjKG5hbWU6IHN0cmluZywgYXJnczogSnNvbik6IFByb21pc2U8dW5rbm93bj4ge1xuICAgIGNvbnN0IGNvbnRyb2xsZXIgPSBuZXcgQWJvcnRDb250cm9sbGVyKCk7XG4gICAgbGV0IHRpbWVyOiBSZXR1cm5UeXBlPHR5cGVvZiBzZXRUaW1lb3V0PiB8IHVuZGVmaW5lZDtcbiAgICB0cnkge1xuICAgICAgY29uc3Qgb3BlcmF0aW9uID0gZGVwcy5ycGMobmFtZSwgYXJncywgY29udHJvbGxlci5zaWduYWwpO1xuICAgICAgY29uc3QgcmVzdWx0ID0gYXdhaXQgUHJvbWlzZS5yYWNlKFtcbiAgICAgICAgb3BlcmF0aW9uLFxuICAgICAgICBuZXcgUHJvbWlzZTxuZXZlcj4oKF8sIHJlamVjdCkgPT4ge1xuICAgICAgICAgIHRpbWVyID0gc2V0VGltZW91dCgoKSA9PiB7XG4gICAgICAgICAgICBjb250cm9sbGVyLmFib3J0KCk7XG4gICAgICAgICAgICByZWplY3QobmV3IFJlZnVzYWwoNTA0LCBcIkdBVEVXQVlfT1VUQ09NRV9VTktOT1dOXCIpKTtcbiAgICAgICAgICB9LCB0aW1lb3V0KTtcbiAgICAgICAgfSksXG4gICAgICBdKTtcbiAgICAgIGlmIChyZXN1bHQuZXJyb3IpIHtcbiAgICAgICAgaWYgKHJlc3VsdC5lcnJvci5jb2RlID09PSBcIjQyNTAxXCIpIHtcbiAgICAgICAgICB0aHJvdyBuZXcgUmVmdXNhbCg0MDMsIFwiR0FURVdBWV9BVVRIT1JJVFlfUkVGVVNFRFwiKTtcbiAgICAgICAgfVxuICAgICAgICBpZiAoW1wiMjIwMjNcIiwgXCIyMzUwNVwiLCBcIjU1MDAwXCJdLmluY2x1ZGVzKHJlc3VsdC5lcnJvci5jb2RlID8/IFwiXCIpKSB7XG4gICAgICAgICAgdGhyb3cgbmV3IFJlZnVzYWwoNDA5LCBcIkdBVEVXQVlfUkVRVUVTVF9SRUZVU0VEXCIpO1xuICAgICAgICB9XG4gICAgICAgIHRocm93IG5ldyBSZWZ1c2FsKDUwMywgXCJHQVRFV0FZX09VVENPTUVfVU5LTk9XTlwiKTtcbiAgICAgIH1cbiAgICAgIGlmIChKU09OLnN0cmluZ2lmeShyZXN1bHQuZGF0YSkubGVuZ3RoID4gODE5Mikge1xuICAgICAgICB0aHJvdyBuZXcgUmVmdXNhbCg1MDIsIFwiR0FURVdBWV9PVVRDT01FX1VOS05PV05cIik7XG4gICAgICB9XG4gICAgICByZXR1cm4gcmVzdWx0LmRhdGE7XG4gICAgfSBmaW5hbGx5IHtcbiAgICAgIGlmICh0aW1lciAhPT0gdW5kZWZpbmVkKSBjbGVhclRpbWVvdXQodGltZXIpO1xuICAgIH1cbiAgfVxuICByZXR1cm4gYXN5bmMgKHJlcXVlc3QpID0+IHtcbiAgICB0cnkge1xuICAgICAgaWYgKHJlcXVlc3QubWV0aG9kICE9PSBcIlBPU1RcIikge1xuICAgICAgICB0aHJvdyBuZXcgUmVmdXNhbCg0MDUsIFwiR0FURVdBWV9QT1NUX1JFUVVJUkVEXCIpO1xuICAgICAgfVxuICAgICAgY29uc3QgcmF3ID0gYXdhaXQgYm9keShyZXF1ZXN0LCB0aW1lb3V0KTtcbiAgICAgIGxldCB0ZXh0OiBzdHJpbmc7XG4gICAgICB0cnkge1xuICAgICAgICB0ZXh0ID0gbmV3IFRleHREZWNvZGVyKFwidXRmLThcIiwgeyBmYXRhbDogdHJ1ZSB9KS5kZWNvZGUocmF3KTtcbiAgICAgIH0gY2F0Y2gge1xuICAgICAgICB0aHJvdyBuZXcgUmVmdXNhbCg0MDAsIFwiR0FURVdBWV9SRVFVRVNUX0lOVkFMSURcIik7XG4gICAgICB9XG4gICAgICBjb25zdCBlbnZlbG9wZSA9IHBhcnNlU3RyaWN0KHRleHQpO1xuICAgICAgcmVxdWlyZShcbiAgICAgICAga2V5cyhlbnZlbG9wZSwgW1xuICAgICAgICAgIFwiY29udHJhY3RfdmVyc2lvblwiLFxuICAgICAgICAgIFwiYWN0aW9uXCIsXG4gICAgICAgICAgXCJkZXZpY2VfaWRcIixcbiAgICAgICAgICBcInJlcXVlc3RfaWRcIixcbiAgICAgICAgICBcImlzc3VlZF9hdFwiLFxuICAgICAgICAgIFwicGF5bG9hZFwiLFxuICAgICAgICBdKSxcbiAgICAgICk7XG4gICAgICByZXF1aXJlKFxuICAgICAgICB0eXBlb2YgZW52ZWxvcGUuYWN0aW9uID09PSBcInN0cmluZ1wiICYmXG4gICAgICAgICAgKChlbnZlbG9wZS5jb250cmFjdF92ZXJzaW9uID09PSAxICYmXG4gICAgICAgICAgICBPYmplY3QuaGFzT3duKFYxX1JQQywgZW52ZWxvcGUuYWN0aW9uKSkgfHxcbiAgICAgICAgICAgIChlbnZlbG9wZS5jb250cmFjdF92ZXJzaW9uID09PSAyICYmXG4gICAgICAgICAgICAgIE9iamVjdC5oYXNPd24oVjJfUlBDLCBlbnZlbG9wZS5hY3Rpb24pKSB8fFxuICAgICAgICAgICAgKGVudmVsb3BlLmNvbnRyYWN0X3ZlcnNpb24gPT09IDMgJiZcbiAgICAgICAgICAgICAgT2JqZWN0Lmhhc093bihBUkNISVZFX1JQQywgZW52ZWxvcGUuYWN0aW9uKSkpLFxuICAgICAgKTtcbiAgICAgIHJlcXVpcmUoXG4gICAgICAgIHV1aWQoZW52ZWxvcGUuZGV2aWNlX2lkKSAmJiB1dWlkKGVudmVsb3BlLnJlcXVlc3RfaWQpICYmXG4gICAgICAgICAgdXRjKGVudmVsb3BlLmlzc3VlZF9hdCksXG4gICAgICApO1xuICAgICAgcmVxdWlyZShNYXRoLmFicyhub3coKSAtIERhdGUucGFyc2UoZW52ZWxvcGUuaXNzdWVkX2F0KSkgPD0gMTIwMDAwKTtcbiAgICAgIGNvbnN0IGFjdGlvbiA9IGVudmVsb3BlLmFjdGlvbiBhcyBBY3Rpb247XG4gICAgICBpZiAoZW52ZWxvcGUuY29udHJhY3RfdmVyc2lvbiA9PT0gMykge1xuICAgICAgICByZXF1aXJlKFxuICAgICAgICAgIGFyY2hpdmVQYXlsb2FkKFxuICAgICAgICAgICAgYWN0aW9uIGFzIEFyY2hpdmVBY3Rpb24sXG4gICAgICAgICAgICBlbnZlbG9wZS5wYXlsb2FkLFxuICAgICAgICAgICAgZW52ZWxvcGUucmVxdWVzdF9pZCxcbiAgICAgICAgICApLFxuICAgICAgICApO1xuICAgICAgfSBlbHNlIHBheWxvYWQoYWN0aW9uIGFzIFYxQWN0aW9uIHwgVjJBY3Rpb24sIGVudmVsb3BlLnBheWxvYWQpO1xuICAgICAgaWYgKGFjdGlvbiA9PT0gXCJjYWxsYmFja1wiKSB7XG4gICAgICAgIHJlcXVpcmUoZW52ZWxvcGUucGF5bG9hZC5jYWxsYmFja19pZCAhPT0gZW52ZWxvcGUucmVxdWVzdF9pZCk7XG4gICAgICAgIGlmIChlbnZlbG9wZS5jb250cmFjdF92ZXJzaW9uID09PSAyKSB7XG4gICAgICAgICAgcmVxdWlyZSghc2FtZVV1aWQoZW52ZWxvcGUucGF5bG9hZC5jYWxsYmFja19pZCwgZW52ZWxvcGUucmVxdWVzdF9pZCkpO1xuICAgICAgICB9XG4gICAgICB9XG4gICAgICBpZiAoZW52ZWxvcGUuY29udHJhY3RfdmVyc2lvbiA9PT0gMiAmJiBhY3Rpb24gPT09IFwiYXJtX2Rpc3BhdGNoXCIpIHtcbiAgICAgICAgZm9yIChjb25zdCBjYWxsYmFjayBvZiBlbnZlbG9wZS5wYXlsb2FkLmNhbGxiYWNrcyBhcyBKc29uW10pIHtcbiAgICAgICAgICBmb3IgKFxuICAgICAgICAgICAgY29uc3QgaWQgb2YgW1xuICAgICAgICAgICAgICBjYWxsYmFjay5zZW50X2NhbGxiYWNrX2lkLFxuICAgICAgICAgICAgICBjYWxsYmFjay5kZWxpdmVyeV9jYWxsYmFja19pZCxcbiAgICAgICAgICAgIF1cbiAgICAgICAgICApIHtcbiAgICAgICAgICAgIHJlcXVpcmUoXG4gICAgICAgICAgICAgICFzYW1lVXVpZChpZCwgZW52ZWxvcGUucmVxdWVzdF9pZCkgJiZcbiAgICAgICAgICAgICAgICAhc2FtZVV1aWQoaWQsIGVudmVsb3BlLnBheWxvYWQuYXR0ZW1wdF9pZCksXG4gICAgICAgICAgICApO1xuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuICAgICAgY29uc3Qga2V5SWQgPSByZXF1ZXN0LmhlYWRlcnMuZ2V0KFwiWC1Db2xsZWN0LUdhdGV3YXktS2V5LUlkXCIpO1xuICAgICAgcmVxdWlyZShoYXNoKGtleUlkKSk7XG4gICAgICBjb25zdCBzaWduYXR1cmUgPSBkZXJUb1AxMzYzKFxuICAgICAgICBiYXNlNjQocmVxdWVzdC5oZWFkZXJzLmdldChcIlgtQ29sbGVjdC1HYXRld2F5LVNpZ25hdHVyZVwiKSwgMTAwKSxcbiAgICAgICk7XG4gICAgICBjb25zdCBrZXkgPSBhd2FpdCBycGMoXCJnYXRld2F5X2RldmljZV9rZXlfdjFcIiwge1xuICAgICAgICBwX2RldmljZV9pZDogZW52ZWxvcGUuZGV2aWNlX2lkLFxuICAgICAgfSk7XG4gICAgICBpZiAoXG4gICAgICAgICFrZXlzKGtleSwgW1xuICAgICAgICAgIFwiZGV2aWNlX2lkXCIsXG4gICAgICAgICAgXCJzdGF0ZVwiLFxuICAgICAgICAgIFwicHVibGljX2tleV9zcGtpX2Jhc2U2NFwiLFxuICAgICAgICAgIFwia2V5X3NoYTI1NlwiLFxuICAgICAgICAgIFwiaW5zdGFsbGF0aW9uX2lkXCIsXG4gICAgICAgICAgXCJzaWduaW5nX2NlcnRpZmljYXRlX3NoYTI1NlwiLFxuICAgICAgICBdKSB8fCAoZW52ZWxvcGUuY29udHJhY3RfdmVyc2lvbiAhPT0gMVxuICAgICAgICAgID8gIXNhbWVVdWlkKGtleS5kZXZpY2VfaWQsIGVudmVsb3BlLmRldmljZV9pZClcbiAgICAgICAgICA6IGtleS5kZXZpY2VfaWQgIT09IGVudmVsb3BlLmRldmljZV9pZCkgfHxcbiAgICAgICAgIVtcInBlbmRpbmdcIiwgXCJhY3RpdmVcIiwgXCJyZXZva2VkXCJdLmluY2x1ZGVzKGtleS5zdGF0ZSBhcyBzdHJpbmcpIHx8XG4gICAgICAgICF1dWlkKGtleS5pbnN0YWxsYXRpb25faWQpIHx8ICFoYXNoKGtleS5rZXlfc2hhMjU2KSB8fFxuICAgICAgICAhaGFzaChrZXkuc2lnbmluZ19jZXJ0aWZpY2F0ZV9zaGEyNTYpXG4gICAgICApIHtcbiAgICAgICAgdGhyb3cgbmV3IFJlZnVzYWwoNDAxLCBcIkdBVEVXQVlfS0VZX1JFRlVTRURcIik7XG4gICAgICB9XG4gICAgICBjb25zdCBzcGtpID0gYmFzZTY0KGtleS5wdWJsaWNfa2V5X3Nwa2lfYmFzZTY0LCAxMjQpO1xuICAgICAgaWYgKFxuICAgICAgICBzcGtpLmxlbmd0aCAhPT0gOTEgfHwgYXdhaXQgZGlnZXN0KHNwa2kpICE9PSBrZXkua2V5X3NoYTI1NiB8fFxuICAgICAgICBrZXkua2V5X3NoYTI1NiAhPT0ga2V5SWRcbiAgICAgICkge1xuICAgICAgICB0aHJvdyBuZXcgUmVmdXNhbCg0MDEsIFwiR0FURVdBWV9LRVlfUkVGVVNFRFwiKTtcbiAgICAgIH1cbiAgICAgIGxldCB2ZXJpZmllZCA9IGZhbHNlO1xuICAgICAgdHJ5IHtcbiAgICAgICAgY29uc3QgaW1wb3J0ZWQgPSBhd2FpdCBjcnlwdG8uc3VidGxlLmltcG9ydEtleShcbiAgICAgICAgICBcInNwa2lcIixcbiAgICAgICAgICBuZXcgVWludDhBcnJheShzcGtpKSxcbiAgICAgICAgICB7IG5hbWU6IFwiRUNEU0FcIiwgbmFtZWRDdXJ2ZTogXCJQLTI1NlwiIH0sXG4gICAgICAgICAgZmFsc2UsXG4gICAgICAgICAgW1widmVyaWZ5XCJdLFxuICAgICAgICApO1xuICAgICAgICB2ZXJpZmllZCA9IGF3YWl0IGNyeXB0by5zdWJ0bGUudmVyaWZ5KFxuICAgICAgICAgIHsgbmFtZTogXCJFQ0RTQVwiLCBoYXNoOiBcIlNIQS0yNTZcIiB9LFxuICAgICAgICAgIGltcG9ydGVkLFxuICAgICAgICAgIG5ldyBVaW50OEFycmF5KHNpZ25hdHVyZSksXG4gICAgICAgICAgbmV3IFVpbnQ4QXJyYXkocmF3KSxcbiAgICAgICAgKTtcbiAgICAgIH0gY2F0Y2gge1xuICAgICAgICB2ZXJpZmllZCA9IGZhbHNlO1xuICAgICAgfVxuICAgICAgaWYgKCF2ZXJpZmllZCkge1xuICAgICAgICB0aHJvdyBuZXcgUmVmdXNhbCg0MDEsIFwiR0FURVdBWV9TSUdOQVRVUkVfUkVGVVNFRFwiKTtcbiAgICAgIH1cbiAgICAgIGlmIChcbiAgICAgICAga2V5LnN0YXRlID09PSBcInJldm9rZWRcIiAmJiBhY3Rpb24gIT09IFwiY2FsbGJhY2tcIiAmJlxuICAgICAgICBhY3Rpb24gIT09IFwicmVjb25jaWxlXCIgJiZcbiAgICAgICAgIShlbnZlbG9wZS5jb250cmFjdF92ZXJzaW9uID09PSAyICYmIGFjdGlvbiA9PT0gXCJhdHRlbXB0X3N0YXR1c1wiKSAmJlxuICAgICAgICBlbnZlbG9wZS5jb250cmFjdF92ZXJzaW9uICE9PSAzXG4gICAgICApIHtcbiAgICAgICAgdGhyb3cgbmV3IFJlZnVzYWwoNDAzLCBcIkdBVEVXQVlfREVWSUNFX1JFVk9LRURcIik7XG4gICAgICB9XG4gICAgICBjb25zdCBuYW1lID0gZW52ZWxvcGUuY29udHJhY3RfdmVyc2lvbiA9PT0gMVxuICAgICAgICA/IFYxX1JQQ1thY3Rpb24gYXMgVjFBY3Rpb25dXG4gICAgICAgIDogZW52ZWxvcGUuY29udHJhY3RfdmVyc2lvbiA9PT0gMlxuICAgICAgICA/IFYyX1JQQ1thY3Rpb24gYXMgVjJBY3Rpb25dXG4gICAgICAgIDogQVJDSElWRV9SUENbYWN0aW9uIGFzIEFyY2hpdmVBY3Rpb25dO1xuICAgICAgY29uc3QgcmVzdWx0ID0gYXdhaXQgcnBjKG5hbWUsIHtcbiAgICAgICAgcF9kZXZpY2VfaWQ6IGVudmVsb3BlLmRldmljZV9pZCxcbiAgICAgICAgcF9yZXF1ZXN0X2lkOiBlbnZlbG9wZS5yZXF1ZXN0X2lkLFxuICAgICAgICBwX3JlcXVlc3Rfc2hhMjU2OiBhd2FpdCBkaWdlc3QocmF3KSxcbiAgICAgICAgcF9wYXlsb2FkOiBlbnZlbG9wZS5wYXlsb2FkLFxuICAgICAgfSk7XG4gICAgICBpZiAoXG4gICAgICAgICEoZW52ZWxvcGUuY29udHJhY3RfdmVyc2lvbiA9PT0gMVxuICAgICAgICAgID8gdmFsaWRSZXN1bHQoXG4gICAgICAgICAgICBhY3Rpb24gYXMgVjFBY3Rpb24sXG4gICAgICAgICAgICByZXN1bHQsXG4gICAgICAgICAgICBlbnZlbG9wZS5kZXZpY2VfaWQsXG4gICAgICAgICAgICBlbnZlbG9wZS5yZXF1ZXN0X2lkLFxuICAgICAgICAgICAgZW52ZWxvcGUucGF5bG9hZCxcbiAgICAgICAgICApXG4gICAgICAgICAgOiBlbnZlbG9wZS5jb250cmFjdF92ZXJzaW9uID09PSAzXG4gICAgICAgICAgPyBhcmNoaXZlUmVzdWx0KFxuICAgICAgICAgICAgYWN0aW9uIGFzIEFyY2hpdmVBY3Rpb24sXG4gICAgICAgICAgICByZXN1bHQsXG4gICAgICAgICAgICBlbnZlbG9wZS5kZXZpY2VfaWQsXG4gICAgICAgICAgICBlbnZlbG9wZS5yZXF1ZXN0X2lkLFxuICAgICAgICAgICAgZW52ZWxvcGUucGF5bG9hZCBhcyBKc29uLFxuICAgICAgICAgIClcbiAgICAgICAgICA6IGF3YWl0IHZhbGlkRGlzcGF0Y2hSZXN1bHQoXG4gICAgICAgICAgICBhY3Rpb24gYXMgVjJBY3Rpb24sXG4gICAgICAgICAgICByZXN1bHQsXG4gICAgICAgICAgICBlbnZlbG9wZS5kZXZpY2VfaWQsXG4gICAgICAgICAgICBlbnZlbG9wZS5yZXF1ZXN0X2lkLFxuICAgICAgICAgICAgbm93KCksXG4gICAgICAgICAgICBlbnZlbG9wZS5wYXlsb2FkLFxuICAgICAgICAgICkpXG4gICAgICApIHtcbiAgICAgICAgdGhyb3cgbmV3IFJlZnVzYWwoNTAyLCBcIkdBVEVXQVlfT1VUQ09NRV9VTktOT1dOXCIpO1xuICAgICAgfVxuICAgICAgcmV0dXJuIHJlc3BvbnNlKDIwMCwge1xuICAgICAgICBjb250cmFjdF92ZXJzaW9uOiBlbnZlbG9wZS5jb250cmFjdF92ZXJzaW9uLFxuICAgICAgICBhY3Rpb24sXG4gICAgICAgIGRldmljZV9pZDogZW52ZWxvcGUuZGV2aWNlX2lkLFxuICAgICAgICByZXF1ZXN0X2lkOiBlbnZlbG9wZS5yZXF1ZXN0X2lkLFxuICAgICAgICByZXN1bHQsXG4gICAgICB9KTtcbiAgICB9IGNhdGNoIChlcnJvcikge1xuICAgICAgaWYgKGVycm9yIGluc3RhbmNlb2YgUmVmdXNhbCkge1xuICAgICAgICByZXR1cm4gcmVzcG9uc2UoZXJyb3Iuc3RhdHVzLCB7IG9rOiBmYWxzZSwgY29kZTogZXJyb3IuY29kZSB9KTtcbiAgICAgIH1cbiAgICAgIHJldHVybiByZXNwb25zZSg1MDMsIHsgb2s6IGZhbHNlLCBjb2RlOiBcIkdBVEVXQVlfT1VUQ09NRV9VTktOT1dOXCIgfSk7XG4gICAgfVxuICB9O1xufVxuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQUFBLFNBQ0UsV0FBVyxFQUVYLGNBQWMs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
// denoCacheMetadata=8612924145270081756,2111898156769147798