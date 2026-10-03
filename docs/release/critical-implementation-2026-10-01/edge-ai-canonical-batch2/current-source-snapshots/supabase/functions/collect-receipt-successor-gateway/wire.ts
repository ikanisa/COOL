export type Json = Record<string, unknown>;
export const FAMILY = "receipt_successor";
export const AUDIENCE = "collect-receipt-successor-gateway";
export const RPC = {
  dispatch_grant: "gateway_receipt_successor_grant_v1",
  arm_dispatch: "gateway_receipt_successor_arm_v1",
  reconcile: "gateway_receipt_successor_reconcile_v1",
  callback: "gateway_receipt_successor_callback_v1",
  attempt_status: "gateway_receipt_successor_attempt_status_v1",
  archive_attempt: "gateway_receipt_successor_archive_v1",
} as const;
export type Action = keyof typeof RPC;
export const object = (v: unknown): v is Json => typeof v === "object" && v !== null && !Array.isArray(v);
export const keys = (v: unknown, names: string[]): v is Json => object(v) && Object.keys(v).length === names.length && names.every(n => Object.hasOwn(v, n));
export const uuid = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export const hash = (v: unknown): v is string => typeof v === "string" && /^[0-9a-f]{64}$/.test(v);
export const sameUuid = (a: unknown, b: unknown) => uuid(a) && uuid(b) && a.toLowerCase() === b.toLowerCase();
export const integer = (v: unknown, min: number, max: number): v is number => typeof v === "number" && Number.isSafeInteger(v) && v >= min && v <= max;
export const utc = (v: unknown): v is string => {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(v)) return false;
  const ms = Date.parse(v); return Number.isFinite(ms) && new Date(ms).toISOString().slice(0, 19) === v.slice(0, 19);
};
export const route = (v: unknown): v is Json => keys(v, ["route_version", "route_kind", "primary_receipt_id", "dispatch_job_id", "approval_id"]) && v.route_version === 1 && v.route_kind === FAMILY && uuid(v.primary_receipt_id) && uuid(v.dispatch_job_id) && uuid(v.approval_id) && !sameUuid(v.primary_receipt_id, v.dispatch_job_id);
export const sameRoute = (a: unknown, b: unknown) => route(a) && route(b) && ["primary_receipt_id", "dispatch_job_id", "approval_id"].every(n => sameUuid(a[n], b[n]));
export async function digest(bytes: Uint8Array): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes))), b => b.toString(16).padStart(2, "0")).join("");
}
export function payload(action: Action, v: unknown, requestId: string): v is Json {
  if (action === "dispatch_grant") return keys(v, []);
  if (action === "reconcile") return keys(v, ["target_request_id"]) && uuid(v.target_request_id) && !sameUuid(requestId, v.target_request_id);
  const names = action === "arm_dispatch" ? ["route", "attempt_id", "fence_version", "body_sha256", "destination_sha256", "reservation_sha256", "callbacks"] : action === "callback" ? ["route", "callback_id", "attempt_id", "fence_version", "segment_index", "segment_count", "body_sha256", "destination_sha256", "callback_kind", "result_code", "tp_status", "occurred_at"] : action === "attempt_status" ? ["route", "attempt_id", "fence_version"] : ["route", "attempt_id", "fence_version", "body_sha256", "destination_sha256", "callback_requests"];
  if (!keys(v, names) || !route(v.route) || !uuid(v.attempt_id) || !integer(v.fence_version, 1, 1e9)) return false;
  if (action === "attempt_status") return true;
  if (!hash(v.body_sha256) || !hash(v.destination_sha256)) return false;
  if (action === "callback") return uuid(v.callback_id) && !sameUuid(v.callback_id, requestId) && integer(v.segment_count, 1, 10) && integer(v.segment_index, 0, v.segment_count - 1) && ["sent", "delivery"].includes(v.callback_kind as string) && integer(v.result_code, -1, 200) && (v.tp_status === null || integer(v.tp_status, 0, 255)) && utc(v.occurred_at);
  const seen = new Set([requestId.toLowerCase(), v.attempt_id.toLowerCase(), (v.route.dispatch_job_id as string).toLowerCase()]);
  if (action === "arm_dispatch") {
    if (!hash(v.reservation_sha256) || !Array.isArray(v.callbacks) || v.callbacks.length < 1 || v.callbacks.length > 10) return false;
    return v.callbacks.every((cb, index) => {
      if (!keys(cb, ["segment_index", "sent_callback_id", "delivery_callback_id"]) || cb.segment_index !== index || !uuid(cb.sent_callback_id) || !uuid(cb.delivery_callback_id)) return false;
      for (const id of [cb.sent_callback_id, cb.delivery_callback_id]) { const normalized = id.toLowerCase(); if (seen.has(normalized)) return false; seen.add(normalized); }
      return true;
    });
  }
  return refs(v.callback_requests, seen);
}
const refs = (v: unknown, seen: Set<string> = new Set()): v is Json[] => {
  if (!Array.isArray(v) || v.length < 2 || v.length > 20 || v.length % 2) return false;
  const ids = new Set<string>();
  return v.every(r => { if (!keys(r, ["callback_id", "request_id", "request_sha256"]) || !uuid(r.callback_id) || !uuid(r.request_id) || !hash(r.request_sha256) || seen.has(r.callback_id.toLowerCase()) || ids.has(r.request_id.toLowerCase())) return false; seen.add(r.callback_id.toLowerCase()); ids.add(r.request_id.toLowerCase()); return true; });
};
const equalRefs = (a: unknown, b: unknown): boolean => refs(a) && refs(b) && a.length === b.length && a.every((r, i) => sameUuid(r.callback_id, b[i].callback_id) && sameUuid(r.request_id, b[i].request_id) && r.request_sha256 === b[i].request_sha256);
const counts = (v: Json, count: number): boolean => integer(v.sent_observations, 0, count) && integer(v.delivery_observations, 0, count) && typeof v.conflicting_observations === "boolean" && typeof v.failed_observations === "boolean" && (v.state !== "observed_sent" || (v.sent_observations === count && !v.conflicting_observations && !v.failed_observations));
const callbackFact = (v: unknown): v is Json => keys(v, ["contract_version", "protocol_family", "route", "callback_id", "attempt_id", "recorded_at", "replay", "state", "sent_observations", "delivery_observations", "conflicting_observations", "failed_observations", "send_authority", "carrier_proof", "delivery_proven"]) && base(v) && route(v.route) && uuid(v.callback_id) && uuid(v.attempt_id) && utc(v.recorded_at) && typeof v.replay === "boolean" && ["armed_unknown", "observed_sent", "uncertain"].includes(v.state as string) && v.send_authority === false && integer(v.sent_observations, 0, 10) && integer(v.delivery_observations, 0, 10) && typeof v.conflicting_observations === "boolean" && typeof v.failed_observations === "boolean";
const archiveFact = (v: unknown, device: string, request: string): v is Json => keys(v, ["contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "route", "attempt_id", "fence_version", "body_sha256", "destination_sha256", "archive_ack_id", "evidence_sha256", "callback_requests", "recorded_at", "replay", "journal_ack", "send_authority", "carrier_proof", "delivery_proven"]) && base(v) && v.ok === true && v.code === "SUCCESSOR_JOURNAL_ARCHIVE_ACKNOWLEDGED" && sameUuid(v.device_id, device) && sameUuid(v.request_id, request) && route(v.route) && uuid(v.attempt_id) && integer(v.fence_version, 1, 1e9) && hash(v.body_sha256) && hash(v.destination_sha256) && uuid(v.archive_ack_id) && hash(v.evidence_sha256) && refs(v.callback_requests) && utc(v.recorded_at) && typeof v.replay === "boolean" && v.journal_ack === true && v.send_authority === false;

const refusals = new Set(["SUCCESSORS_DISABLED", "OPERATIONS_PAUSED", "NO_CURRENT_RUN", "SUCCESSOR_EXECUTION_PRESENT", "APPROVAL_REVIEW_REQUIRED", "NO_SUCCESSOR_INTENT", "DEVICE_NOT_READY", "QUOTA_EXHAUSTED", "ORIGINAL_REQUEST_RECORDED", "CALLBACK_EVIDENCE_INCOMPLETE"]);
const base = (v: Json) => v.contract_version === 1 && v.protocol_family === FAMILY && v.carrier_proof === false && v.delivery_proven === false;
export function refusal(v: unknown, device: string, request: string): v is Json {
  return keys(v, ["contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "replay", "send_authority", "carrier_proof", "delivery_proven"]) && base(v) && v.ok === false && refusals.has(v.code as string) && sameUuid(v.device_id, device) && sameUuid(v.request_id, request) && typeof v.replay === "boolean" && v.send_authority === false && (v.code !== "ORIGINAL_REQUEST_RECORDED" || v.replay === true);
}
const deadline = (issued: unknown, expiry: unknown, now: number) => utc(issued) && utc(expiry) && Date.parse(issued) <= now + 10000 && Date.parse(expiry) > Date.parse(issued) && Date.parse(expiry) <= Date.parse(issued) + 30000 && Date.parse(expiry) > now;
export async function result(action: Action, v: unknown, device: string, request: string, p: Json, now: number): Promise<boolean> {
  if (action !== "reconcile" && refusal(v, device, request)) return true;
  if (action === "dispatch_grant") {
    if (!keys(v, ["contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "route", "attempt_id", "run_id", "fence_version", "policy_revision", "issued_at", "expires_at", "segment_count", "body", "destination_e164", "body_sha256", "destination_sha256", "sim_revision_sha256", "replay", "send_authority", "carrier_proof", "delivery_proven"]) || !base(v) || v.ok !== true || v.code !== "SUCCESSOR_GRANTED" || !sameUuid(v.device_id, device) || !sameUuid(v.request_id, request) || !route(v.route) || !uuid(v.attempt_id) || !uuid(v.run_id) || !integer(v.fence_version, 1, 1e9) || !integer(v.policy_revision, 1, 1e9) || !deadline(v.issued_at, v.expires_at, now) || !integer(v.segment_count, 1, 10) || typeof v.body !== "string" || !v.body.length || [...v.body].length > 1000 || /\r|\0|[\u0001-\u0008\u000b\u000c\u000e-\u001f]/.test(v.body) || typeof v.destination_e164 !== "string" || !/^\+2507[2389][0-9]{7}$/.test(v.destination_e164) || !hash(v.body_sha256) || !hash(v.destination_sha256) || !hash(v.sim_revision_sha256) || v.replay !== false || v.send_authority !== false) return false;
    const bytes = new TextEncoder().encode(v.body); return bytes.length <= 4000 && await digest(bytes) === v.body_sha256 && await digest(new TextEncoder().encode(v.destination_e164)) === v.destination_sha256;
  }
  if (action === "arm_dispatch") {
    return keys(v, ["contract_version", "protocol_family", "ok", "code", "device_id", "request_id", "route", "attempt_id", "fence_version", "reservation_sha256", "armed_at", "expires_at", "replay", "send_authority", "carrier_proof", "delivery_proven"]) && base(v) && v.ok === true && v.code === "SUCCESSOR_ARMED" && sameUuid(v.device_id, device) && sameUuid(v.request_id, request) && sameRoute(v.route, p.route) && sameUuid(v.attempt_id, p.attempt_id) && integer(v.fence_version, 1, 1e9) && v.fence_version === p.fence_version && hash(v.reservation_sha256) && v.reservation_sha256 === p.reservation_sha256 && deadline(v.armed_at, v.expires_at, now) && v.replay === false && v.send_authority === true;
  }
  if (action === "callback") return callbackFact(v) && sameRoute(v.route, p.route) && sameUuid(v.callback_id, p.callback_id) && sameUuid(v.attempt_id, p.attempt_id) && counts(v, p.segment_count as number);
  if (action === "attempt_status") return keys(v, ["contract_version", "protocol_family", "route", "attempt_id", "fence_version", "state", "segment_count", "armed_at", "sent_observations", "delivery_observations", "conflicting_observations", "failed_observations", "terminal_archive_ack", "send_authority", "carrier_proof", "delivery_proven"]) && base(v) && sameRoute(v.route, p.route) && sameUuid(v.attempt_id, p.attempt_id) && v.fence_version === p.fence_version && ["unarmed_granted", "unarmed_revoked", "unarmed_expired", "armed_unknown", "observed_sent", "uncertain"].includes(v.state as string) && integer(v.segment_count, 1, 10) && (v.armed_at === null || utc(v.armed_at)) && typeof v.terminal_archive_ack === "boolean" && v.send_authority === false && counts(v, v.segment_count);
  if (action === "archive_attempt") return archiveFact(v, device, request) && sameRoute(v.route, p.route) && sameUuid(v.attempt_id, p.attempt_id) && v.fence_version === p.fence_version && v.body_sha256 === p.body_sha256 && v.destination_sha256 === p.destination_sha256 && equalRefs(v.callback_requests, p.callback_requests);
  if (!keys(v, ["contract_version", "protocol_family", "target_request_id", "outcome", "recorded_action", "recorded_route", "recorded_result", "send_authority", "carrier_proof", "delivery_proven"]) || !base(v) || !sameUuid(v.target_request_id, p.target_request_id) || v.send_authority !== false) return false;
  if (v.outcome === "unknown") return v.recorded_action === null && v.recorded_route === null && v.recorded_result === null;
  if (v.outcome !== "recorded" || !["dispatch_grant", "arm_dispatch", "callback", "archive_attempt"].includes(v.recorded_action as string)) return false;
  if (["dispatch_grant", "arm_dispatch"].includes(v.recorded_action as string)) return refusal(v.recorded_result, device, p.target_request_id as string) && (v.recorded_result.code === "ORIGINAL_REQUEST_RECORDED" ? route(v.recorded_route) : v.recorded_route === null);
  if (!route(v.recorded_route)) return false;
  if (v.recorded_action === "callback") return callbackFact(v.recorded_result) && sameRoute(v.recorded_route, v.recorded_result.route);
  if (refusal(v.recorded_result, device, p.target_request_id as string)) return true;
  return archiveFact(v.recorded_result, device, p.target_request_id as string) && sameRoute(v.recorded_route, v.recorded_result.route);
}
