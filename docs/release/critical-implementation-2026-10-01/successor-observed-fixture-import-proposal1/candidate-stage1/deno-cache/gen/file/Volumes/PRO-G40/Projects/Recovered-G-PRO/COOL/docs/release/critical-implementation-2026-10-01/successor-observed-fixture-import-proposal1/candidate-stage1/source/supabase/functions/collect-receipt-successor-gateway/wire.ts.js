export const FAMILY = "receipt_successor";
export const AUDIENCE = "collect-receipt-successor-gateway";
export const RPC = {
  dispatch_grant: "gateway_receipt_successor_grant_v1",
  arm_dispatch: "gateway_receipt_successor_arm_v1",
  reconcile: "gateway_receipt_successor_reconcile_v1",
  callback: "gateway_receipt_successor_callback_v1",
  attempt_status: "gateway_receipt_successor_attempt_status_v1",
  archive_attempt: "gateway_receipt_successor_archive_v1"
};
export const object = (v)=>typeof v === "object" && v !== null && !Array.isArray(v);
export const keys = (v, names)=>object(v) && Object.keys(v).length === names.length && names.every((n)=>Object.hasOwn(v, n));
export const uuid = (v)=>typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export const hash = (v)=>typeof v === "string" && /^[0-9a-f]{64}$/.test(v);
export const sameUuid = (a, b)=>uuid(a) && uuid(b) && a.toLowerCase() === b.toLowerCase();
export const integer = (v, min, max)=>typeof v === "number" && Number.isSafeInteger(v) && v >= min && v <= max;
export const utc = (v)=>{
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(v)) return false;
  const ms = Date.parse(v);
  return Number.isFinite(ms) && new Date(ms).toISOString().slice(0, 19) === v.slice(0, 19);
};
export const route = (v)=>keys(v, [
    "route_version",
    "route_kind",
    "primary_receipt_id",
    "dispatch_job_id",
    "approval_id"
  ]) && v.route_version === 1 && v.route_kind === FAMILY && uuid(v.primary_receipt_id) && uuid(v.dispatch_job_id) && uuid(v.approval_id) && !sameUuid(v.primary_receipt_id, v.dispatch_job_id);
export const sameRoute = (a, b)=>route(a) && route(b) && [
    "primary_receipt_id",
    "dispatch_job_id",
    "approval_id"
  ].every((n)=>sameUuid(a[n], b[n]));
export async function digest(bytes) {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes))), (b)=>b.toString(16).padStart(2, "0")).join("");
}
export function payload(action, v, requestId) {
  if (action === "dispatch_grant") return keys(v, []);
  if (action === "reconcile") return keys(v, [
    "target_request_id"
  ]) && uuid(v.target_request_id) && !sameUuid(requestId, v.target_request_id);
  const names = action === "arm_dispatch" ? [
    "route",
    "attempt_id",
    "fence_version",
    "body_sha256",
    "destination_sha256",
    "reservation_sha256",
    "callbacks"
  ] : action === "callback" ? [
    "route",
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
  ] : action === "attempt_status" ? [
    "route",
    "attempt_id",
    "fence_version"
  ] : [
    "route",
    "attempt_id",
    "fence_version",
    "body_sha256",
    "destination_sha256",
    "callback_requests"
  ];
  if (!keys(v, names) || !route(v.route) || !uuid(v.attempt_id) || !integer(v.fence_version, 1, 1e9)) return false;
  if (action === "attempt_status") return true;
  if (!hash(v.body_sha256) || !hash(v.destination_sha256)) return false;
  if (action === "callback") return uuid(v.callback_id) && !sameUuid(v.callback_id, requestId) && integer(v.segment_count, 1, 10) && integer(v.segment_index, 0, v.segment_count - 1) && [
    "sent",
    "delivery"
  ].includes(v.callback_kind) && integer(v.result_code, -1, 200) && (v.tp_status === null || integer(v.tp_status, 0, 255)) && utc(v.occurred_at);
  const seen = new Set([
    requestId.toLowerCase(),
    v.attempt_id.toLowerCase(),
    v.route.dispatch_job_id.toLowerCase()
  ]);
  if (action === "arm_dispatch") {
    if (!hash(v.reservation_sha256) || !Array.isArray(v.callbacks) || v.callbacks.length < 1 || v.callbacks.length > 10) return false;
    return v.callbacks.every((cb, index)=>{
      if (!keys(cb, [
        "segment_index",
        "sent_callback_id",
        "delivery_callback_id"
      ]) || cb.segment_index !== index || !uuid(cb.sent_callback_id) || !uuid(cb.delivery_callback_id)) return false;
      for (const id of [
        cb.sent_callback_id,
        cb.delivery_callback_id
      ]){
        const normalized = id.toLowerCase();
        if (seen.has(normalized)) return false;
        seen.add(normalized);
      }
      return true;
    });
  }
  return refs(v.callback_requests, seen);
}
const refs = (v, seen = new Set())=>{
  if (!Array.isArray(v) || v.length < 2 || v.length > 20 || v.length % 2) return false;
  const ids = new Set();
  return v.every((r)=>{
    if (!keys(r, [
      "callback_id",
      "request_id",
      "request_sha256"
    ]) || !uuid(r.callback_id) || !uuid(r.request_id) || !hash(r.request_sha256) || seen.has(r.callback_id.toLowerCase()) || ids.has(r.request_id.toLowerCase())) return false;
    seen.add(r.callback_id.toLowerCase());
    ids.add(r.request_id.toLowerCase());
    return true;
  });
};
const equalRefs = (a, b)=>refs(a) && refs(b) && a.length === b.length && a.every((r, i)=>sameUuid(r.callback_id, b[i].callback_id) && sameUuid(r.request_id, b[i].request_id) && r.request_sha256 === b[i].request_sha256);
const counts = (v, count)=>integer(v.sent_observations, 0, count) && integer(v.delivery_observations, 0, count) && typeof v.conflicting_observations === "boolean" && typeof v.failed_observations === "boolean" && (v.state !== "observed_sent" || v.sent_observations === count && !v.conflicting_observations && !v.failed_observations);
const callbackFact = (v)=>keys(v, [
    "contract_version",
    "protocol_family",
    "route",
    "callback_id",
    "attempt_id",
    "recorded_at",
    "replay",
    "state",
    "sent_observations",
    "delivery_observations",
    "conflicting_observations",
    "failed_observations",
    "send_authority",
    "carrier_proof",
    "delivery_proven"
  ]) && base(v) && route(v.route) && uuid(v.callback_id) && uuid(v.attempt_id) && utc(v.recorded_at) && typeof v.replay === "boolean" && [
    "armed_unknown",
    "observed_sent",
    "uncertain"
  ].includes(v.state) && v.send_authority === false && integer(v.sent_observations, 0, 10) && integer(v.delivery_observations, 0, 10) && typeof v.conflicting_observations === "boolean" && typeof v.failed_observations === "boolean";
const archiveFact = (v, device, request)=>keys(v, [
    "contract_version",
    "protocol_family",
    "ok",
    "code",
    "device_id",
    "request_id",
    "route",
    "attempt_id",
    "fence_version",
    "body_sha256",
    "destination_sha256",
    "archive_ack_id",
    "evidence_sha256",
    "callback_requests",
    "recorded_at",
    "replay",
    "journal_ack",
    "send_authority",
    "carrier_proof",
    "delivery_proven"
  ]) && base(v) && v.ok === true && v.code === "SUCCESSOR_JOURNAL_ARCHIVE_ACKNOWLEDGED" && sameUuid(v.device_id, device) && sameUuid(v.request_id, request) && route(v.route) && uuid(v.attempt_id) && integer(v.fence_version, 1, 1e9) && hash(v.body_sha256) && hash(v.destination_sha256) && uuid(v.archive_ack_id) && hash(v.evidence_sha256) && refs(v.callback_requests) && utc(v.recorded_at) && typeof v.replay === "boolean" && v.journal_ack === true && v.send_authority === false;
const refusals = new Set([
  "SUCCESSORS_DISABLED",
  "OPERATIONS_PAUSED",
  "NO_CURRENT_RUN",
  "SUCCESSOR_EXECUTION_PRESENT",
  "APPROVAL_REVIEW_REQUIRED",
  "NO_SUCCESSOR_INTENT",
  "DEVICE_NOT_READY",
  "QUOTA_EXHAUSTED",
  "ORIGINAL_REQUEST_RECORDED",
  "CALLBACK_EVIDENCE_INCOMPLETE"
]);
const base = (v)=>v.contract_version === 1 && v.protocol_family === FAMILY && v.carrier_proof === false && v.delivery_proven === false;
export function refusal(v, device, request) {
  return keys(v, [
    "contract_version",
    "protocol_family",
    "ok",
    "code",
    "device_id",
    "request_id",
    "replay",
    "send_authority",
    "carrier_proof",
    "delivery_proven"
  ]) && base(v) && v.ok === false && refusals.has(v.code) && sameUuid(v.device_id, device) && sameUuid(v.request_id, request) && typeof v.replay === "boolean" && v.send_authority === false && (v.code !== "ORIGINAL_REQUEST_RECORDED" || v.replay === true);
}
const deadline = (issued, expiry, now)=>utc(issued) && utc(expiry) && Date.parse(issued) <= now + 10000 && Date.parse(expiry) > Date.parse(issued) && Date.parse(expiry) <= Date.parse(issued) + 30000 && Date.parse(expiry) > now;
export async function result(action, v, device, request, p, now) {
  if (action !== "reconcile" && refusal(v, device, request)) return true;
  if (action === "dispatch_grant") {
    if (!keys(v, [
      "contract_version",
      "protocol_family",
      "ok",
      "code",
      "device_id",
      "request_id",
      "route",
      "attempt_id",
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
      "replay",
      "send_authority",
      "carrier_proof",
      "delivery_proven"
    ]) || !base(v) || v.ok !== true || v.code !== "SUCCESSOR_GRANTED" || !sameUuid(v.device_id, device) || !sameUuid(v.request_id, request) || !route(v.route) || !uuid(v.attempt_id) || !uuid(v.run_id) || !integer(v.fence_version, 1, 1e9) || !integer(v.policy_revision, 1, 1e9) || !deadline(v.issued_at, v.expires_at, now) || !integer(v.segment_count, 1, 10) || typeof v.body !== "string" || !v.body.length || [
      ...v.body
    ].length > 1000 || /\r|\0|[\u0001-\u0008\u000b\u000c\u000e-\u001f]/.test(v.body) || typeof v.destination_e164 !== "string" || !/^\+2507[2389][0-9]{7}$/.test(v.destination_e164) || !hash(v.body_sha256) || !hash(v.destination_sha256) || !hash(v.sim_revision_sha256) || v.replay !== false || v.send_authority !== false) return false;
    const bytes = new TextEncoder().encode(v.body);
    return bytes.length <= 4000 && await digest(bytes) === v.body_sha256 && await digest(new TextEncoder().encode(v.destination_e164)) === v.destination_sha256;
  }
  if (action === "arm_dispatch") {
    return keys(v, [
      "contract_version",
      "protocol_family",
      "ok",
      "code",
      "device_id",
      "request_id",
      "route",
      "attempt_id",
      "fence_version",
      "reservation_sha256",
      "armed_at",
      "expires_at",
      "replay",
      "send_authority",
      "carrier_proof",
      "delivery_proven"
    ]) && base(v) && v.ok === true && v.code === "SUCCESSOR_ARMED" && sameUuid(v.device_id, device) && sameUuid(v.request_id, request) && sameRoute(v.route, p.route) && sameUuid(v.attempt_id, p.attempt_id) && integer(v.fence_version, 1, 1e9) && v.fence_version === p.fence_version && hash(v.reservation_sha256) && v.reservation_sha256 === p.reservation_sha256 && deadline(v.armed_at, v.expires_at, now) && v.replay === false && v.send_authority === true;
  }
  if (action === "callback") return callbackFact(v) && sameRoute(v.route, p.route) && sameUuid(v.callback_id, p.callback_id) && sameUuid(v.attempt_id, p.attempt_id) && counts(v, p.segment_count);
  if (action === "attempt_status") return keys(v, [
    "contract_version",
    "protocol_family",
    "route",
    "attempt_id",
    "fence_version",
    "state",
    "segment_count",
    "armed_at",
    "sent_observations",
    "delivery_observations",
    "conflicting_observations",
    "failed_observations",
    "terminal_archive_ack",
    "send_authority",
    "carrier_proof",
    "delivery_proven"
  ]) && base(v) && sameRoute(v.route, p.route) && sameUuid(v.attempt_id, p.attempt_id) && v.fence_version === p.fence_version && [
    "unarmed_granted",
    "unarmed_revoked",
    "unarmed_expired",
    "armed_unknown",
    "observed_sent",
    "uncertain"
  ].includes(v.state) && integer(v.segment_count, 1, 10) && (v.armed_at === null || utc(v.armed_at)) && typeof v.terminal_archive_ack === "boolean" && v.send_authority === false && counts(v, v.segment_count);
  if (action === "archive_attempt") return archiveFact(v, device, request) && sameRoute(v.route, p.route) && sameUuid(v.attempt_id, p.attempt_id) && v.fence_version === p.fence_version && v.body_sha256 === p.body_sha256 && v.destination_sha256 === p.destination_sha256 && equalRefs(v.callback_requests, p.callback_requests);
  if (!keys(v, [
    "contract_version",
    "protocol_family",
    "target_request_id",
    "outcome",
    "recorded_action",
    "recorded_route",
    "recorded_result",
    "send_authority",
    "carrier_proof",
    "delivery_proven"
  ]) || !base(v) || !sameUuid(v.target_request_id, p.target_request_id) || v.send_authority !== false) return false;
  if (v.outcome === "unknown") return v.recorded_action === null && v.recorded_route === null && v.recorded_result === null;
  if (v.outcome !== "recorded" || ![
    "dispatch_grant",
    "arm_dispatch",
    "callback",
    "archive_attempt"
  ].includes(v.recorded_action)) return false;
  if ([
    "dispatch_grant",
    "arm_dispatch"
  ].includes(v.recorded_action)) return refusal(v.recorded_result, device, p.target_request_id) && (v.recorded_result.code === "ORIGINAL_REQUEST_RECORDED" ? route(v.recorded_route) : v.recorded_route === null);
  if (!route(v.recorded_route)) return false;
  if (v.recorded_action === "callback") return callbackFact(v.recorded_result) && sameRoute(v.recorded_route, v.recorded_result.route);
  if (refusal(v.recorded_result, device, p.target_request_id)) return true;
  return archiveFact(v.recorded_result, device, p.target_request_id) && sameRoute(v.recorded_route, v.recorded_result.route);
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3QtcmVjZWlwdC1zdWNjZXNzb3ItZ2F0ZXdheS93aXJlLnRzIl0sInNvdXJjZXNDb250ZW50IjpbImV4cG9ydCB0eXBlIEpzb24gPSBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPjtcbmV4cG9ydCBjb25zdCBGQU1JTFkgPSBcInJlY2VpcHRfc3VjY2Vzc29yXCI7XG5leHBvcnQgY29uc3QgQVVESUVOQ0UgPSBcImNvbGxlY3QtcmVjZWlwdC1zdWNjZXNzb3ItZ2F0ZXdheVwiO1xuZXhwb3J0IGNvbnN0IFJQQyA9IHtcbiAgZGlzcGF0Y2hfZ3JhbnQ6IFwiZ2F0ZXdheV9yZWNlaXB0X3N1Y2Nlc3Nvcl9ncmFudF92MVwiLFxuICBhcm1fZGlzcGF0Y2g6IFwiZ2F0ZXdheV9yZWNlaXB0X3N1Y2Nlc3Nvcl9hcm1fdjFcIixcbiAgcmVjb25jaWxlOiBcImdhdGV3YXlfcmVjZWlwdF9zdWNjZXNzb3JfcmVjb25jaWxlX3YxXCIsXG4gIGNhbGxiYWNrOiBcImdhdGV3YXlfcmVjZWlwdF9zdWNjZXNzb3JfY2FsbGJhY2tfdjFcIixcbiAgYXR0ZW1wdF9zdGF0dXM6IFwiZ2F0ZXdheV9yZWNlaXB0X3N1Y2Nlc3Nvcl9hdHRlbXB0X3N0YXR1c192MVwiLFxuICBhcmNoaXZlX2F0dGVtcHQ6IFwiZ2F0ZXdheV9yZWNlaXB0X3N1Y2Nlc3Nvcl9hcmNoaXZlX3YxXCIsXG59IGFzIGNvbnN0O1xuZXhwb3J0IHR5cGUgQWN0aW9uID0ga2V5b2YgdHlwZW9mIFJQQztcbmV4cG9ydCBjb25zdCBvYmplY3QgPSAodjogdW5rbm93bik6IHYgaXMgSnNvbiA9PiB0eXBlb2YgdiA9PT0gXCJvYmplY3RcIiAmJiB2ICE9PSBudWxsICYmICFBcnJheS5pc0FycmF5KHYpO1xuZXhwb3J0IGNvbnN0IGtleXMgPSAodjogdW5rbm93biwgbmFtZXM6IHN0cmluZ1tdKTogdiBpcyBKc29uID0+IG9iamVjdCh2KSAmJiBPYmplY3Qua2V5cyh2KS5sZW5ndGggPT09IG5hbWVzLmxlbmd0aCAmJiBuYW1lcy5ldmVyeShuID0+IE9iamVjdC5oYXNPd24odiwgbikpO1xuZXhwb3J0IGNvbnN0IHV1aWQgPSAodjogdW5rbm93bik6IHYgaXMgc3RyaW5nID0+IHR5cGVvZiB2ID09PSBcInN0cmluZ1wiICYmIC9eWzAtOWEtZl17OH0tWzAtOWEtZl17NH0tWzAtOWEtZl17NH0tWzAtOWEtZl17NH0tWzAtOWEtZl17MTJ9JC9pLnRlc3Qodik7XG5leHBvcnQgY29uc3QgaGFzaCA9ICh2OiB1bmtub3duKTogdiBpcyBzdHJpbmcgPT4gdHlwZW9mIHYgPT09IFwic3RyaW5nXCIgJiYgL15bMC05YS1mXXs2NH0kLy50ZXN0KHYpO1xuZXhwb3J0IGNvbnN0IHNhbWVVdWlkID0gKGE6IHVua25vd24sIGI6IHVua25vd24pID0+IHV1aWQoYSkgJiYgdXVpZChiKSAmJiBhLnRvTG93ZXJDYXNlKCkgPT09IGIudG9Mb3dlckNhc2UoKTtcbmV4cG9ydCBjb25zdCBpbnRlZ2VyID0gKHY6IHVua25vd24sIG1pbjogbnVtYmVyLCBtYXg6IG51bWJlcik6IHYgaXMgbnVtYmVyID0+IHR5cGVvZiB2ID09PSBcIm51bWJlclwiICYmIE51bWJlci5pc1NhZmVJbnRlZ2VyKHYpICYmIHYgPj0gbWluICYmIHYgPD0gbWF4O1xuZXhwb3J0IGNvbnN0IHV0YyA9ICh2OiB1bmtub3duKTogdiBpcyBzdHJpbmcgPT4ge1xuICBpZiAodHlwZW9mIHYgIT09IFwic3RyaW5nXCIgfHwgIS9eXFxkezR9LVxcZHsyfS1cXGR7Mn1UXFxkezJ9OlxcZHsyfTpcXGR7Mn0oXFwuXFxkezEsNn0pP1okLy50ZXN0KHYpKSByZXR1cm4gZmFsc2U7XG4gIGNvbnN0IG1zID0gRGF0ZS5wYXJzZSh2KTsgcmV0dXJuIE51bWJlci5pc0Zpbml0ZShtcykgJiYgbmV3IERhdGUobXMpLnRvSVNPU3RyaW5nKCkuc2xpY2UoMCwgMTkpID09PSB2LnNsaWNlKDAsIDE5KTtcbn07XG5leHBvcnQgY29uc3Qgcm91dGUgPSAodjogdW5rbm93bik6IHYgaXMgSnNvbiA9PiBrZXlzKHYsIFtcInJvdXRlX3ZlcnNpb25cIiwgXCJyb3V0ZV9raW5kXCIsIFwicHJpbWFyeV9yZWNlaXB0X2lkXCIsIFwiZGlzcGF0Y2hfam9iX2lkXCIsIFwiYXBwcm92YWxfaWRcIl0pICYmIHYucm91dGVfdmVyc2lvbiA9PT0gMSAmJiB2LnJvdXRlX2tpbmQgPT09IEZBTUlMWSAmJiB1dWlkKHYucHJpbWFyeV9yZWNlaXB0X2lkKSAmJiB1dWlkKHYuZGlzcGF0Y2hfam9iX2lkKSAmJiB1dWlkKHYuYXBwcm92YWxfaWQpICYmICFzYW1lVXVpZCh2LnByaW1hcnlfcmVjZWlwdF9pZCwgdi5kaXNwYXRjaF9qb2JfaWQpO1xuZXhwb3J0IGNvbnN0IHNhbWVSb3V0ZSA9IChhOiB1bmtub3duLCBiOiB1bmtub3duKSA9PiByb3V0ZShhKSAmJiByb3V0ZShiKSAmJiBbXCJwcmltYXJ5X3JlY2VpcHRfaWRcIiwgXCJkaXNwYXRjaF9qb2JfaWRcIiwgXCJhcHByb3ZhbF9pZFwiXS5ldmVyeShuID0+IHNhbWVVdWlkKGFbbl0sIGJbbl0pKTtcbmV4cG9ydCBhc3luYyBmdW5jdGlvbiBkaWdlc3QoYnl0ZXM6IFVpbnQ4QXJyYXkpOiBQcm9taXNlPHN0cmluZz4ge1xuICByZXR1cm4gQXJyYXkuZnJvbShuZXcgVWludDhBcnJheShhd2FpdCBjcnlwdG8uc3VidGxlLmRpZ2VzdChcIlNIQS0yNTZcIiwgbmV3IFVpbnQ4QXJyYXkoYnl0ZXMpKSksIGIgPT4gYi50b1N0cmluZygxNikucGFkU3RhcnQoMiwgXCIwXCIpKS5qb2luKFwiXCIpO1xufVxuZXhwb3J0IGZ1bmN0aW9uIHBheWxvYWQoYWN0aW9uOiBBY3Rpb24sIHY6IHVua25vd24sIHJlcXVlc3RJZDogc3RyaW5nKTogdiBpcyBKc29uIHtcbiAgaWYgKGFjdGlvbiA9PT0gXCJkaXNwYXRjaF9ncmFudFwiKSByZXR1cm4ga2V5cyh2LCBbXSk7XG4gIGlmIChhY3Rpb24gPT09IFwicmVjb25jaWxlXCIpIHJldHVybiBrZXlzKHYsIFtcInRhcmdldF9yZXF1ZXN0X2lkXCJdKSAmJiB1dWlkKHYudGFyZ2V0X3JlcXVlc3RfaWQpICYmICFzYW1lVXVpZChyZXF1ZXN0SWQsIHYudGFyZ2V0X3JlcXVlc3RfaWQpO1xuICBjb25zdCBuYW1lcyA9IGFjdGlvbiA9PT0gXCJhcm1fZGlzcGF0Y2hcIiA/IFtcInJvdXRlXCIsIFwiYXR0ZW1wdF9pZFwiLCBcImZlbmNlX3ZlcnNpb25cIiwgXCJib2R5X3NoYTI1NlwiLCBcImRlc3RpbmF0aW9uX3NoYTI1NlwiLCBcInJlc2VydmF0aW9uX3NoYTI1NlwiLCBcImNhbGxiYWNrc1wiXSA6IGFjdGlvbiA9PT0gXCJjYWxsYmFja1wiID8gW1wicm91dGVcIiwgXCJjYWxsYmFja19pZFwiLCBcImF0dGVtcHRfaWRcIiwgXCJmZW5jZV92ZXJzaW9uXCIsIFwic2VnbWVudF9pbmRleFwiLCBcInNlZ21lbnRfY291bnRcIiwgXCJib2R5X3NoYTI1NlwiLCBcImRlc3RpbmF0aW9uX3NoYTI1NlwiLCBcImNhbGxiYWNrX2tpbmRcIiwgXCJyZXN1bHRfY29kZVwiLCBcInRwX3N0YXR1c1wiLCBcIm9jY3VycmVkX2F0XCJdIDogYWN0aW9uID09PSBcImF0dGVtcHRfc3RhdHVzXCIgPyBbXCJyb3V0ZVwiLCBcImF0dGVtcHRfaWRcIiwgXCJmZW5jZV92ZXJzaW9uXCJdIDogW1wicm91dGVcIiwgXCJhdHRlbXB0X2lkXCIsIFwiZmVuY2VfdmVyc2lvblwiLCBcImJvZHlfc2hhMjU2XCIsIFwiZGVzdGluYXRpb25fc2hhMjU2XCIsIFwiY2FsbGJhY2tfcmVxdWVzdHNcIl07XG4gIGlmICgha2V5cyh2LCBuYW1lcykgfHwgIXJvdXRlKHYucm91dGUpIHx8ICF1dWlkKHYuYXR0ZW1wdF9pZCkgfHwgIWludGVnZXIodi5mZW5jZV92ZXJzaW9uLCAxLCAxZTkpKSByZXR1cm4gZmFsc2U7XG4gIGlmIChhY3Rpb24gPT09IFwiYXR0ZW1wdF9zdGF0dXNcIikgcmV0dXJuIHRydWU7XG4gIGlmICghaGFzaCh2LmJvZHlfc2hhMjU2KSB8fCAhaGFzaCh2LmRlc3RpbmF0aW9uX3NoYTI1NikpIHJldHVybiBmYWxzZTtcbiAgaWYgKGFjdGlvbiA9PT0gXCJjYWxsYmFja1wiKSByZXR1cm4gdXVpZCh2LmNhbGxiYWNrX2lkKSAmJiAhc2FtZVV1aWQodi5jYWxsYmFja19pZCwgcmVxdWVzdElkKSAmJiBpbnRlZ2VyKHYuc2VnbWVudF9jb3VudCwgMSwgMTApICYmIGludGVnZXIodi5zZWdtZW50X2luZGV4LCAwLCB2LnNlZ21lbnRfY291bnQgLSAxKSAmJiBbXCJzZW50XCIsIFwiZGVsaXZlcnlcIl0uaW5jbHVkZXModi5jYWxsYmFja19raW5kIGFzIHN0cmluZykgJiYgaW50ZWdlcih2LnJlc3VsdF9jb2RlLCAtMSwgMjAwKSAmJiAodi50cF9zdGF0dXMgPT09IG51bGwgfHwgaW50ZWdlcih2LnRwX3N0YXR1cywgMCwgMjU1KSkgJiYgdXRjKHYub2NjdXJyZWRfYXQpO1xuICBjb25zdCBzZWVuID0gbmV3IFNldChbcmVxdWVzdElkLnRvTG93ZXJDYXNlKCksIHYuYXR0ZW1wdF9pZC50b0xvd2VyQ2FzZSgpLCAodi5yb3V0ZS5kaXNwYXRjaF9qb2JfaWQgYXMgc3RyaW5nKS50b0xvd2VyQ2FzZSgpXSk7XG4gIGlmIChhY3Rpb24gPT09IFwiYXJtX2Rpc3BhdGNoXCIpIHtcbiAgICBpZiAoIWhhc2godi5yZXNlcnZhdGlvbl9zaGEyNTYpIHx8ICFBcnJheS5pc0FycmF5KHYuY2FsbGJhY2tzKSB8fCB2LmNhbGxiYWNrcy5sZW5ndGggPCAxIHx8IHYuY2FsbGJhY2tzLmxlbmd0aCA+IDEwKSByZXR1cm4gZmFsc2U7XG4gICAgcmV0dXJuIHYuY2FsbGJhY2tzLmV2ZXJ5KChjYiwgaW5kZXgpID0+IHtcbiAgICAgIGlmICgha2V5cyhjYiwgW1wic2VnbWVudF9pbmRleFwiLCBcInNlbnRfY2FsbGJhY2tfaWRcIiwgXCJkZWxpdmVyeV9jYWxsYmFja19pZFwiXSkgfHwgY2Iuc2VnbWVudF9pbmRleCAhPT0gaW5kZXggfHwgIXV1aWQoY2Iuc2VudF9jYWxsYmFja19pZCkgfHwgIXV1aWQoY2IuZGVsaXZlcnlfY2FsbGJhY2tfaWQpKSByZXR1cm4gZmFsc2U7XG4gICAgICBmb3IgKGNvbnN0IGlkIG9mIFtjYi5zZW50X2NhbGxiYWNrX2lkLCBjYi5kZWxpdmVyeV9jYWxsYmFja19pZF0pIHsgY29uc3Qgbm9ybWFsaXplZCA9IGlkLnRvTG93ZXJDYXNlKCk7IGlmIChzZWVuLmhhcyhub3JtYWxpemVkKSkgcmV0dXJuIGZhbHNlOyBzZWVuLmFkZChub3JtYWxpemVkKTsgfVxuICAgICAgcmV0dXJuIHRydWU7XG4gICAgfSk7XG4gIH1cbiAgcmV0dXJuIHJlZnModi5jYWxsYmFja19yZXF1ZXN0cywgc2Vlbik7XG59XG5jb25zdCByZWZzID0gKHY6IHVua25vd24sIHNlZW46IFNldDxzdHJpbmc+ID0gbmV3IFNldCgpKTogdiBpcyBKc29uW10gPT4ge1xuICBpZiAoIUFycmF5LmlzQXJyYXkodikgfHwgdi5sZW5ndGggPCAyIHx8IHYubGVuZ3RoID4gMjAgfHwgdi5sZW5ndGggJSAyKSByZXR1cm4gZmFsc2U7XG4gIGNvbnN0IGlkcyA9IG5ldyBTZXQ8c3RyaW5nPigpO1xuICByZXR1cm4gdi5ldmVyeShyID0+IHsgaWYgKCFrZXlzKHIsIFtcImNhbGxiYWNrX2lkXCIsIFwicmVxdWVzdF9pZFwiLCBcInJlcXVlc3Rfc2hhMjU2XCJdKSB8fCAhdXVpZChyLmNhbGxiYWNrX2lkKSB8fCAhdXVpZChyLnJlcXVlc3RfaWQpIHx8ICFoYXNoKHIucmVxdWVzdF9zaGEyNTYpIHx8IHNlZW4uaGFzKHIuY2FsbGJhY2tfaWQudG9Mb3dlckNhc2UoKSkgfHwgaWRzLmhhcyhyLnJlcXVlc3RfaWQudG9Mb3dlckNhc2UoKSkpIHJldHVybiBmYWxzZTsgc2Vlbi5hZGQoci5jYWxsYmFja19pZC50b0xvd2VyQ2FzZSgpKTsgaWRzLmFkZChyLnJlcXVlc3RfaWQudG9Mb3dlckNhc2UoKSk7IHJldHVybiB0cnVlOyB9KTtcbn07XG5jb25zdCBlcXVhbFJlZnMgPSAoYTogdW5rbm93biwgYjogdW5rbm93bik6IGJvb2xlYW4gPT4gcmVmcyhhKSAmJiByZWZzKGIpICYmIGEubGVuZ3RoID09PSBiLmxlbmd0aCAmJiBhLmV2ZXJ5KChyLCBpKSA9PiBzYW1lVXVpZChyLmNhbGxiYWNrX2lkLCBiW2ldLmNhbGxiYWNrX2lkKSAmJiBzYW1lVXVpZChyLnJlcXVlc3RfaWQsIGJbaV0ucmVxdWVzdF9pZCkgJiYgci5yZXF1ZXN0X3NoYTI1NiA9PT0gYltpXS5yZXF1ZXN0X3NoYTI1Nik7XG5jb25zdCBjb3VudHMgPSAodjogSnNvbiwgY291bnQ6IG51bWJlcik6IGJvb2xlYW4gPT4gaW50ZWdlcih2LnNlbnRfb2JzZXJ2YXRpb25zLCAwLCBjb3VudCkgJiYgaW50ZWdlcih2LmRlbGl2ZXJ5X29ic2VydmF0aW9ucywgMCwgY291bnQpICYmIHR5cGVvZiB2LmNvbmZsaWN0aW5nX29ic2VydmF0aW9ucyA9PT0gXCJib29sZWFuXCIgJiYgdHlwZW9mIHYuZmFpbGVkX29ic2VydmF0aW9ucyA9PT0gXCJib29sZWFuXCIgJiYgKHYuc3RhdGUgIT09IFwib2JzZXJ2ZWRfc2VudFwiIHx8ICh2LnNlbnRfb2JzZXJ2YXRpb25zID09PSBjb3VudCAmJiAhdi5jb25mbGljdGluZ19vYnNlcnZhdGlvbnMgJiYgIXYuZmFpbGVkX29ic2VydmF0aW9ucykpO1xuY29uc3QgY2FsbGJhY2tGYWN0ID0gKHY6IHVua25vd24pOiB2IGlzIEpzb24gPT4ga2V5cyh2LCBbXCJjb250cmFjdF92ZXJzaW9uXCIsIFwicHJvdG9jb2xfZmFtaWx5XCIsIFwicm91dGVcIiwgXCJjYWxsYmFja19pZFwiLCBcImF0dGVtcHRfaWRcIiwgXCJyZWNvcmRlZF9hdFwiLCBcInJlcGxheVwiLCBcInN0YXRlXCIsIFwic2VudF9vYnNlcnZhdGlvbnNcIiwgXCJkZWxpdmVyeV9vYnNlcnZhdGlvbnNcIiwgXCJjb25mbGljdGluZ19vYnNlcnZhdGlvbnNcIiwgXCJmYWlsZWRfb2JzZXJ2YXRpb25zXCIsIFwic2VuZF9hdXRob3JpdHlcIiwgXCJjYXJyaWVyX3Byb29mXCIsIFwiZGVsaXZlcnlfcHJvdmVuXCJdKSAmJiBiYXNlKHYpICYmIHJvdXRlKHYucm91dGUpICYmIHV1aWQodi5jYWxsYmFja19pZCkgJiYgdXVpZCh2LmF0dGVtcHRfaWQpICYmIHV0Yyh2LnJlY29yZGVkX2F0KSAmJiB0eXBlb2Ygdi5yZXBsYXkgPT09IFwiYm9vbGVhblwiICYmIFtcImFybWVkX3Vua25vd25cIiwgXCJvYnNlcnZlZF9zZW50XCIsIFwidW5jZXJ0YWluXCJdLmluY2x1ZGVzKHYuc3RhdGUgYXMgc3RyaW5nKSAmJiB2LnNlbmRfYXV0aG9yaXR5ID09PSBmYWxzZSAmJiBpbnRlZ2VyKHYuc2VudF9vYnNlcnZhdGlvbnMsIDAsIDEwKSAmJiBpbnRlZ2VyKHYuZGVsaXZlcnlfb2JzZXJ2YXRpb25zLCAwLCAxMCkgJiYgdHlwZW9mIHYuY29uZmxpY3Rpbmdfb2JzZXJ2YXRpb25zID09PSBcImJvb2xlYW5cIiAmJiB0eXBlb2Ygdi5mYWlsZWRfb2JzZXJ2YXRpb25zID09PSBcImJvb2xlYW5cIjtcbmNvbnN0IGFyY2hpdmVGYWN0ID0gKHY6IHVua25vd24sIGRldmljZTogc3RyaW5nLCByZXF1ZXN0OiBzdHJpbmcpOiB2IGlzIEpzb24gPT4ga2V5cyh2LCBbXCJjb250cmFjdF92ZXJzaW9uXCIsIFwicHJvdG9jb2xfZmFtaWx5XCIsIFwib2tcIiwgXCJjb2RlXCIsIFwiZGV2aWNlX2lkXCIsIFwicmVxdWVzdF9pZFwiLCBcInJvdXRlXCIsIFwiYXR0ZW1wdF9pZFwiLCBcImZlbmNlX3ZlcnNpb25cIiwgXCJib2R5X3NoYTI1NlwiLCBcImRlc3RpbmF0aW9uX3NoYTI1NlwiLCBcImFyY2hpdmVfYWNrX2lkXCIsIFwiZXZpZGVuY2Vfc2hhMjU2XCIsIFwiY2FsbGJhY2tfcmVxdWVzdHNcIiwgXCJyZWNvcmRlZF9hdFwiLCBcInJlcGxheVwiLCBcImpvdXJuYWxfYWNrXCIsIFwic2VuZF9hdXRob3JpdHlcIiwgXCJjYXJyaWVyX3Byb29mXCIsIFwiZGVsaXZlcnlfcHJvdmVuXCJdKSAmJiBiYXNlKHYpICYmIHYub2sgPT09IHRydWUgJiYgdi5jb2RlID09PSBcIlNVQ0NFU1NPUl9KT1VSTkFMX0FSQ0hJVkVfQUNLTk9XTEVER0VEXCIgJiYgc2FtZVV1aWQodi5kZXZpY2VfaWQsIGRldmljZSkgJiYgc2FtZVV1aWQodi5yZXF1ZXN0X2lkLCByZXF1ZXN0KSAmJiByb3V0ZSh2LnJvdXRlKSAmJiB1dWlkKHYuYXR0ZW1wdF9pZCkgJiYgaW50ZWdlcih2LmZlbmNlX3ZlcnNpb24sIDEsIDFlOSkgJiYgaGFzaCh2LmJvZHlfc2hhMjU2KSAmJiBoYXNoKHYuZGVzdGluYXRpb25fc2hhMjU2KSAmJiB1dWlkKHYuYXJjaGl2ZV9hY2tfaWQpICYmIGhhc2godi5ldmlkZW5jZV9zaGEyNTYpICYmIHJlZnModi5jYWxsYmFja19yZXF1ZXN0cykgJiYgdXRjKHYucmVjb3JkZWRfYXQpICYmIHR5cGVvZiB2LnJlcGxheSA9PT0gXCJib29sZWFuXCIgJiYgdi5qb3VybmFsX2FjayA9PT0gdHJ1ZSAmJiB2LnNlbmRfYXV0aG9yaXR5ID09PSBmYWxzZTtcblxuY29uc3QgcmVmdXNhbHMgPSBuZXcgU2V0KFtcIlNVQ0NFU1NPUlNfRElTQUJMRURcIiwgXCJPUEVSQVRJT05TX1BBVVNFRFwiLCBcIk5PX0NVUlJFTlRfUlVOXCIsIFwiU1VDQ0VTU09SX0VYRUNVVElPTl9QUkVTRU5UXCIsIFwiQVBQUk9WQUxfUkVWSUVXX1JFUVVJUkVEXCIsIFwiTk9fU1VDQ0VTU09SX0lOVEVOVFwiLCBcIkRFVklDRV9OT1RfUkVBRFlcIiwgXCJRVU9UQV9FWEhBVVNURURcIiwgXCJPUklHSU5BTF9SRVFVRVNUX1JFQ09SREVEXCIsIFwiQ0FMTEJBQ0tfRVZJREVOQ0VfSU5DT01QTEVURVwiXSk7XG5jb25zdCBiYXNlID0gKHY6IEpzb24pID0+IHYuY29udHJhY3RfdmVyc2lvbiA9PT0gMSAmJiB2LnByb3RvY29sX2ZhbWlseSA9PT0gRkFNSUxZICYmIHYuY2Fycmllcl9wcm9vZiA9PT0gZmFsc2UgJiYgdi5kZWxpdmVyeV9wcm92ZW4gPT09IGZhbHNlO1xuZXhwb3J0IGZ1bmN0aW9uIHJlZnVzYWwodjogdW5rbm93biwgZGV2aWNlOiBzdHJpbmcsIHJlcXVlc3Q6IHN0cmluZyk6IHYgaXMgSnNvbiB7XG4gIHJldHVybiBrZXlzKHYsIFtcImNvbnRyYWN0X3ZlcnNpb25cIiwgXCJwcm90b2NvbF9mYW1pbHlcIiwgXCJva1wiLCBcImNvZGVcIiwgXCJkZXZpY2VfaWRcIiwgXCJyZXF1ZXN0X2lkXCIsIFwicmVwbGF5XCIsIFwic2VuZF9hdXRob3JpdHlcIiwgXCJjYXJyaWVyX3Byb29mXCIsIFwiZGVsaXZlcnlfcHJvdmVuXCJdKSAmJiBiYXNlKHYpICYmIHYub2sgPT09IGZhbHNlICYmIHJlZnVzYWxzLmhhcyh2LmNvZGUgYXMgc3RyaW5nKSAmJiBzYW1lVXVpZCh2LmRldmljZV9pZCwgZGV2aWNlKSAmJiBzYW1lVXVpZCh2LnJlcXVlc3RfaWQsIHJlcXVlc3QpICYmIHR5cGVvZiB2LnJlcGxheSA9PT0gXCJib29sZWFuXCIgJiYgdi5zZW5kX2F1dGhvcml0eSA9PT0gZmFsc2UgJiYgKHYuY29kZSAhPT0gXCJPUklHSU5BTF9SRVFVRVNUX1JFQ09SREVEXCIgfHwgdi5yZXBsYXkgPT09IHRydWUpO1xufVxuY29uc3QgZGVhZGxpbmUgPSAoaXNzdWVkOiB1bmtub3duLCBleHBpcnk6IHVua25vd24sIG5vdzogbnVtYmVyKSA9PiB1dGMoaXNzdWVkKSAmJiB1dGMoZXhwaXJ5KSAmJiBEYXRlLnBhcnNlKGlzc3VlZCkgPD0gbm93ICsgMTAwMDAgJiYgRGF0ZS5wYXJzZShleHBpcnkpID4gRGF0ZS5wYXJzZShpc3N1ZWQpICYmIERhdGUucGFyc2UoZXhwaXJ5KSA8PSBEYXRlLnBhcnNlKGlzc3VlZCkgKyAzMDAwMCAmJiBEYXRlLnBhcnNlKGV4cGlyeSkgPiBub3c7XG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gcmVzdWx0KGFjdGlvbjogQWN0aW9uLCB2OiB1bmtub3duLCBkZXZpY2U6IHN0cmluZywgcmVxdWVzdDogc3RyaW5nLCBwOiBKc29uLCBub3c6IG51bWJlcik6IFByb21pc2U8Ym9vbGVhbj4ge1xuICBpZiAoYWN0aW9uICE9PSBcInJlY29uY2lsZVwiICYmIHJlZnVzYWwodiwgZGV2aWNlLCByZXF1ZXN0KSkgcmV0dXJuIHRydWU7XG4gIGlmIChhY3Rpb24gPT09IFwiZGlzcGF0Y2hfZ3JhbnRcIikge1xuICAgIGlmICgha2V5cyh2LCBbXCJjb250cmFjdF92ZXJzaW9uXCIsIFwicHJvdG9jb2xfZmFtaWx5XCIsIFwib2tcIiwgXCJjb2RlXCIsIFwiZGV2aWNlX2lkXCIsIFwicmVxdWVzdF9pZFwiLCBcInJvdXRlXCIsIFwiYXR0ZW1wdF9pZFwiLCBcInJ1bl9pZFwiLCBcImZlbmNlX3ZlcnNpb25cIiwgXCJwb2xpY3lfcmV2aXNpb25cIiwgXCJpc3N1ZWRfYXRcIiwgXCJleHBpcmVzX2F0XCIsIFwic2VnbWVudF9jb3VudFwiLCBcImJvZHlcIiwgXCJkZXN0aW5hdGlvbl9lMTY0XCIsIFwiYm9keV9zaGEyNTZcIiwgXCJkZXN0aW5hdGlvbl9zaGEyNTZcIiwgXCJzaW1fcmV2aXNpb25fc2hhMjU2XCIsIFwicmVwbGF5XCIsIFwic2VuZF9hdXRob3JpdHlcIiwgXCJjYXJyaWVyX3Byb29mXCIsIFwiZGVsaXZlcnlfcHJvdmVuXCJdKSB8fCAhYmFzZSh2KSB8fCB2Lm9rICE9PSB0cnVlIHx8IHYuY29kZSAhPT0gXCJTVUNDRVNTT1JfR1JBTlRFRFwiIHx8ICFzYW1lVXVpZCh2LmRldmljZV9pZCwgZGV2aWNlKSB8fCAhc2FtZVV1aWQodi5yZXF1ZXN0X2lkLCByZXF1ZXN0KSB8fCAhcm91dGUodi5yb3V0ZSkgfHwgIXV1aWQodi5hdHRlbXB0X2lkKSB8fCAhdXVpZCh2LnJ1bl9pZCkgfHwgIWludGVnZXIodi5mZW5jZV92ZXJzaW9uLCAxLCAxZTkpIHx8ICFpbnRlZ2VyKHYucG9saWN5X3JldmlzaW9uLCAxLCAxZTkpIHx8ICFkZWFkbGluZSh2Lmlzc3VlZF9hdCwgdi5leHBpcmVzX2F0LCBub3cpIHx8ICFpbnRlZ2VyKHYuc2VnbWVudF9jb3VudCwgMSwgMTApIHx8IHR5cGVvZiB2LmJvZHkgIT09IFwic3RyaW5nXCIgfHwgIXYuYm9keS5sZW5ndGggfHwgWy4uLnYuYm9keV0ubGVuZ3RoID4gMTAwMCB8fCAvXFxyfFxcMHxbXFx1MDAwMS1cXHUwMDA4XFx1MDAwYlxcdTAwMGNcXHUwMDBlLVxcdTAwMWZdLy50ZXN0KHYuYm9keSkgfHwgdHlwZW9mIHYuZGVzdGluYXRpb25fZTE2NCAhPT0gXCJzdHJpbmdcIiB8fCAhL15cXCsyNTA3WzIzODldWzAtOV17N30kLy50ZXN0KHYuZGVzdGluYXRpb25fZTE2NCkgfHwgIWhhc2godi5ib2R5X3NoYTI1NikgfHwgIWhhc2godi5kZXN0aW5hdGlvbl9zaGEyNTYpIHx8ICFoYXNoKHYuc2ltX3JldmlzaW9uX3NoYTI1NikgfHwgdi5yZXBsYXkgIT09IGZhbHNlIHx8IHYuc2VuZF9hdXRob3JpdHkgIT09IGZhbHNlKSByZXR1cm4gZmFsc2U7XG4gICAgY29uc3QgYnl0ZXMgPSBuZXcgVGV4dEVuY29kZXIoKS5lbmNvZGUodi5ib2R5KTsgcmV0dXJuIGJ5dGVzLmxlbmd0aCA8PSA0MDAwICYmIGF3YWl0IGRpZ2VzdChieXRlcykgPT09IHYuYm9keV9zaGEyNTYgJiYgYXdhaXQgZGlnZXN0KG5ldyBUZXh0RW5jb2RlcigpLmVuY29kZSh2LmRlc3RpbmF0aW9uX2UxNjQpKSA9PT0gdi5kZXN0aW5hdGlvbl9zaGEyNTY7XG4gIH1cbiAgaWYgKGFjdGlvbiA9PT0gXCJhcm1fZGlzcGF0Y2hcIikge1xuICAgIHJldHVybiBrZXlzKHYsIFtcImNvbnRyYWN0X3ZlcnNpb25cIiwgXCJwcm90b2NvbF9mYW1pbHlcIiwgXCJva1wiLCBcImNvZGVcIiwgXCJkZXZpY2VfaWRcIiwgXCJyZXF1ZXN0X2lkXCIsIFwicm91dGVcIiwgXCJhdHRlbXB0X2lkXCIsIFwiZmVuY2VfdmVyc2lvblwiLCBcInJlc2VydmF0aW9uX3NoYTI1NlwiLCBcImFybWVkX2F0XCIsIFwiZXhwaXJlc19hdFwiLCBcInJlcGxheVwiLCBcInNlbmRfYXV0aG9yaXR5XCIsIFwiY2Fycmllcl9wcm9vZlwiLCBcImRlbGl2ZXJ5X3Byb3ZlblwiXSkgJiYgYmFzZSh2KSAmJiB2Lm9rID09PSB0cnVlICYmIHYuY29kZSA9PT0gXCJTVUNDRVNTT1JfQVJNRURcIiAmJiBzYW1lVXVpZCh2LmRldmljZV9pZCwgZGV2aWNlKSAmJiBzYW1lVXVpZCh2LnJlcXVlc3RfaWQsIHJlcXVlc3QpICYmIHNhbWVSb3V0ZSh2LnJvdXRlLCBwLnJvdXRlKSAmJiBzYW1lVXVpZCh2LmF0dGVtcHRfaWQsIHAuYXR0ZW1wdF9pZCkgJiYgaW50ZWdlcih2LmZlbmNlX3ZlcnNpb24sIDEsIDFlOSkgJiYgdi5mZW5jZV92ZXJzaW9uID09PSBwLmZlbmNlX3ZlcnNpb24gJiYgaGFzaCh2LnJlc2VydmF0aW9uX3NoYTI1NikgJiYgdi5yZXNlcnZhdGlvbl9zaGEyNTYgPT09IHAucmVzZXJ2YXRpb25fc2hhMjU2ICYmIGRlYWRsaW5lKHYuYXJtZWRfYXQsIHYuZXhwaXJlc19hdCwgbm93KSAmJiB2LnJlcGxheSA9PT0gZmFsc2UgJiYgdi5zZW5kX2F1dGhvcml0eSA9PT0gdHJ1ZTtcbiAgfVxuICBpZiAoYWN0aW9uID09PSBcImNhbGxiYWNrXCIpIHJldHVybiBjYWxsYmFja0ZhY3QodikgJiYgc2FtZVJvdXRlKHYucm91dGUsIHAucm91dGUpICYmIHNhbWVVdWlkKHYuY2FsbGJhY2tfaWQsIHAuY2FsbGJhY2tfaWQpICYmIHNhbWVVdWlkKHYuYXR0ZW1wdF9pZCwgcC5hdHRlbXB0X2lkKSAmJiBjb3VudHModiwgcC5zZWdtZW50X2NvdW50IGFzIG51bWJlcik7XG4gIGlmIChhY3Rpb24gPT09IFwiYXR0ZW1wdF9zdGF0dXNcIikgcmV0dXJuIGtleXModiwgW1wiY29udHJhY3RfdmVyc2lvblwiLCBcInByb3RvY29sX2ZhbWlseVwiLCBcInJvdXRlXCIsIFwiYXR0ZW1wdF9pZFwiLCBcImZlbmNlX3ZlcnNpb25cIiwgXCJzdGF0ZVwiLCBcInNlZ21lbnRfY291bnRcIiwgXCJhcm1lZF9hdFwiLCBcInNlbnRfb2JzZXJ2YXRpb25zXCIsIFwiZGVsaXZlcnlfb2JzZXJ2YXRpb25zXCIsIFwiY29uZmxpY3Rpbmdfb2JzZXJ2YXRpb25zXCIsIFwiZmFpbGVkX29ic2VydmF0aW9uc1wiLCBcInRlcm1pbmFsX2FyY2hpdmVfYWNrXCIsIFwic2VuZF9hdXRob3JpdHlcIiwgXCJjYXJyaWVyX3Byb29mXCIsIFwiZGVsaXZlcnlfcHJvdmVuXCJdKSAmJiBiYXNlKHYpICYmIHNhbWVSb3V0ZSh2LnJvdXRlLCBwLnJvdXRlKSAmJiBzYW1lVXVpZCh2LmF0dGVtcHRfaWQsIHAuYXR0ZW1wdF9pZCkgJiYgdi5mZW5jZV92ZXJzaW9uID09PSBwLmZlbmNlX3ZlcnNpb24gJiYgW1widW5hcm1lZF9ncmFudGVkXCIsIFwidW5hcm1lZF9yZXZva2VkXCIsIFwidW5hcm1lZF9leHBpcmVkXCIsIFwiYXJtZWRfdW5rbm93blwiLCBcIm9ic2VydmVkX3NlbnRcIiwgXCJ1bmNlcnRhaW5cIl0uaW5jbHVkZXModi5zdGF0ZSBhcyBzdHJpbmcpICYmIGludGVnZXIodi5zZWdtZW50X2NvdW50LCAxLCAxMCkgJiYgKHYuYXJtZWRfYXQgPT09IG51bGwgfHwgdXRjKHYuYXJtZWRfYXQpKSAmJiB0eXBlb2Ygdi50ZXJtaW5hbF9hcmNoaXZlX2FjayA9PT0gXCJib29sZWFuXCIgJiYgdi5zZW5kX2F1dGhvcml0eSA9PT0gZmFsc2UgJiYgY291bnRzKHYsIHYuc2VnbWVudF9jb3VudCk7XG4gIGlmIChhY3Rpb24gPT09IFwiYXJjaGl2ZV9hdHRlbXB0XCIpIHJldHVybiBhcmNoaXZlRmFjdCh2LCBkZXZpY2UsIHJlcXVlc3QpICYmIHNhbWVSb3V0ZSh2LnJvdXRlLCBwLnJvdXRlKSAmJiBzYW1lVXVpZCh2LmF0dGVtcHRfaWQsIHAuYXR0ZW1wdF9pZCkgJiYgdi5mZW5jZV92ZXJzaW9uID09PSBwLmZlbmNlX3ZlcnNpb24gJiYgdi5ib2R5X3NoYTI1NiA9PT0gcC5ib2R5X3NoYTI1NiAmJiB2LmRlc3RpbmF0aW9uX3NoYTI1NiA9PT0gcC5kZXN0aW5hdGlvbl9zaGEyNTYgJiYgZXF1YWxSZWZzKHYuY2FsbGJhY2tfcmVxdWVzdHMsIHAuY2FsbGJhY2tfcmVxdWVzdHMpO1xuICBpZiAoIWtleXModiwgW1wiY29udHJhY3RfdmVyc2lvblwiLCBcInByb3RvY29sX2ZhbWlseVwiLCBcInRhcmdldF9yZXF1ZXN0X2lkXCIsIFwib3V0Y29tZVwiLCBcInJlY29yZGVkX2FjdGlvblwiLCBcInJlY29yZGVkX3JvdXRlXCIsIFwicmVjb3JkZWRfcmVzdWx0XCIsIFwic2VuZF9hdXRob3JpdHlcIiwgXCJjYXJyaWVyX3Byb29mXCIsIFwiZGVsaXZlcnlfcHJvdmVuXCJdKSB8fCAhYmFzZSh2KSB8fCAhc2FtZVV1aWQodi50YXJnZXRfcmVxdWVzdF9pZCwgcC50YXJnZXRfcmVxdWVzdF9pZCkgfHwgdi5zZW5kX2F1dGhvcml0eSAhPT0gZmFsc2UpIHJldHVybiBmYWxzZTtcbiAgaWYgKHYub3V0Y29tZSA9PT0gXCJ1bmtub3duXCIpIHJldHVybiB2LnJlY29yZGVkX2FjdGlvbiA9PT0gbnVsbCAmJiB2LnJlY29yZGVkX3JvdXRlID09PSBudWxsICYmIHYucmVjb3JkZWRfcmVzdWx0ID09PSBudWxsO1xuICBpZiAodi5vdXRjb21lICE9PSBcInJlY29yZGVkXCIgfHwgIVtcImRpc3BhdGNoX2dyYW50XCIsIFwiYXJtX2Rpc3BhdGNoXCIsIFwiY2FsbGJhY2tcIiwgXCJhcmNoaXZlX2F0dGVtcHRcIl0uaW5jbHVkZXModi5yZWNvcmRlZF9hY3Rpb24gYXMgc3RyaW5nKSkgcmV0dXJuIGZhbHNlO1xuICBpZiAoW1wiZGlzcGF0Y2hfZ3JhbnRcIiwgXCJhcm1fZGlzcGF0Y2hcIl0uaW5jbHVkZXModi5yZWNvcmRlZF9hY3Rpb24gYXMgc3RyaW5nKSkgcmV0dXJuIHJlZnVzYWwodi5yZWNvcmRlZF9yZXN1bHQsIGRldmljZSwgcC50YXJnZXRfcmVxdWVzdF9pZCBhcyBzdHJpbmcpICYmICh2LnJlY29yZGVkX3Jlc3VsdC5jb2RlID09PSBcIk9SSUdJTkFMX1JFUVVFU1RfUkVDT1JERURcIiA/IHJvdXRlKHYucmVjb3JkZWRfcm91dGUpIDogdi5yZWNvcmRlZF9yb3V0ZSA9PT0gbnVsbCk7XG4gIGlmICghcm91dGUodi5yZWNvcmRlZF9yb3V0ZSkpIHJldHVybiBmYWxzZTtcbiAgaWYgKHYucmVjb3JkZWRfYWN0aW9uID09PSBcImNhbGxiYWNrXCIpIHJldHVybiBjYWxsYmFja0ZhY3Qodi5yZWNvcmRlZF9yZXN1bHQpICYmIHNhbWVSb3V0ZSh2LnJlY29yZGVkX3JvdXRlLCB2LnJlY29yZGVkX3Jlc3VsdC5yb3V0ZSk7XG4gIGlmIChyZWZ1c2FsKHYucmVjb3JkZWRfcmVzdWx0LCBkZXZpY2UsIHAudGFyZ2V0X3JlcXVlc3RfaWQgYXMgc3RyaW5nKSkgcmV0dXJuIHRydWU7XG4gIHJldHVybiBhcmNoaXZlRmFjdCh2LnJlY29yZGVkX3Jlc3VsdCwgZGV2aWNlLCBwLnRhcmdldF9yZXF1ZXN0X2lkIGFzIHN0cmluZykgJiYgc2FtZVJvdXRlKHYucmVjb3JkZWRfcm91dGUsIHYucmVjb3JkZWRfcmVzdWx0LnJvdXRlKTtcbn1cbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFDQSxPQUFPLE1BQU0sU0FBUyxvQkFBb0I7QUFDMUMsT0FBTyxNQUFNLFdBQVcsb0NBQW9DO0FBQzVELE9BQU8sTUFBTSxNQUFNO0VBQ2pCLGdCQUFnQjtFQUNoQixjQUFjO0VBQ2QsV0FBVztFQUNYLFVBQVU7RUFDVixnQkFBZ0I7RUFDaEIsaUJBQWlCO0FBQ25CLEVBQVc7QUFFWCxPQUFP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
// denoCacheMetadata=6989006643980174748,14545160448606997609