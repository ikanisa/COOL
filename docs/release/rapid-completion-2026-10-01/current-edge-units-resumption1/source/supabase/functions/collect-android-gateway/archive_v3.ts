type Json = Record<string, unknown>;
export type ArchiveAction = "archive_attempt" | "archive_lookup";
export const ARCHIVE_RPC: Record<ArchiveAction, string> = {
  archive_attempt: "gateway_archive_attempt_v3",
  archive_lookup: "gateway_archive_lookup_v3",
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HASH = /^[0-9a-f]{64}$/;
function keys(v: unknown, fields: string[]): v is Json {
  return typeof v === "object" && v !== null && !Array.isArray(v) &&
    Object.keys(v).length === fields.length &&
    fields.every((k) => Object.hasOwn(v, k));
}
function uuid(v: unknown): v is string {
  return typeof v === "string" && UUID.test(v);
}
function same(a: unknown, b: unknown): boolean {
  return uuid(a) && uuid(b) && a.toLowerCase() === b.toLowerCase();
}
function hash(v: unknown): boolean {
  return typeof v === "string" && HASH.test(v);
}
function integer(v: unknown, min: number, max: number): v is number {
  return typeof v === "number" && Number.isSafeInteger(v) && v >= min &&
    v <= max;
}
function utc(v: unknown): boolean {
  if (
    typeof v !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(v)
  ) return false;
  const t = Date.parse(v);
  return Number.isFinite(t) &&
    new Date(t).toISOString().slice(0, 19) === v.slice(0, 19);
}
function references(v: unknown): v is Json[] {
  if (
    !Array.isArray(v) || v.length < 2 || v.length > 20 || v.length % 2 !== 0
  ) return false;
  const callbacks = new Set<string>();
  const requests = new Set<string>();
  for (const r of v) {
    if (
      !keys(r, ["callback_id", "request_id", "request_sha256"]) ||
      !uuid(r.callback_id) || !uuid(r.request_id) || !hash(r.request_sha256)
    ) return false;
    const c = r.callback_id.toLowerCase();
    const q = r.request_id.toLowerCase();
    if (callbacks.has(c) || requests.has(q)) return false;
    callbacks.add(c);
    requests.add(q);
  }
  return true;
}
export function archivePayload(
  action: ArchiveAction,
  value: unknown,
  request: string,
): value is Json {
  if (action === "archive_lookup") {
    return keys(value, ["target_request_id"]) &&
      uuid(value.target_request_id) && !same(value.target_request_id, request);
  }
  return keys(value, [
    "attempt_id",
    "fence_version",
    "body_sha256",
    "destination_sha256",
    "callback_requests",
  ]) &&
    uuid(value.attempt_id) && integer(value.fence_version, 1, 1e9) &&
    hash(value.body_sha256) && hash(value.destination_sha256) &&
    references(value.callback_requests) &&
    value.callback_requests.every((r) => !same(r.request_id, request));
}
function equalReferences(a: Json[], b: unknown): boolean {
  return references(b) && a.length === b.length &&
    a.every((r, i) =>
      same(r.callback_id, b[i].callback_id) &&
      same(r.request_id, b[i].request_id) &&
      r.request_sha256 === b[i].request_sha256
    );
}
function acknowledgement(
  data: unknown,
  device: string,
  request: string,
  p?: Json,
): data is Json {
  if (
    !keys(data, [
      "request_id",
      "device_id",
      "attempt_id",
      "fence_version",
      "ok",
      "code",
      "archive_ack_id",
      "receipt_id",
      "body_sha256",
      "destination_sha256",
      "segment_count",
      "callback_requests",
      "recorded_at",
      "replay",
      "evidence_kind",
      "carrier_proof",
      "delivery_proven",
      "send_authority",
    ]) ||
    !same(data.request_id, request) || !same(data.device_id, device) ||
    !uuid(data.attempt_id) || !integer(data.fence_version, 1, 1e9) ||
    !hash(data.body_sha256) || !hash(data.destination_sha256) ||
    !integer(data.segment_count, 1, 10) || !utc(data.recorded_at) ||
    typeof data.replay !== "boolean" || data.carrier_proof !== false ||
    data.delivery_proven !== false || data.send_authority !== false
  ) return false;
  if (
    p &&
    (!same(data.attempt_id, p.attempt_id) ||
      data.fence_version !== p.fence_version ||
      data.body_sha256 !== p.body_sha256 ||
      data.destination_sha256 !== p.destination_sha256)
  ) return false;
  if (data.ok === true) {
    return data.code === null && uuid(data.archive_ack_id) &&
      uuid(data.receipt_id) && references(data.callback_requests) &&
      data.callback_requests.length === data.segment_count * 2 &&
      data.evidence_kind === "complete_framework_callback_observations" &&
      (!p || equalReferences(data.callback_requests, p.callback_requests));
  }
  return data.ok === false &&
    [
      "CALLBACK_EVIDENCE_INCOMPLETE",
      "CALLBACK_EVIDENCE_UNCERTAIN",
      "ATTEMPT_ALREADY_ACKNOWLEDGED",
    ].includes(data.code as string) &&
    data.archive_ack_id === null && data.receipt_id === null &&
    data.callback_requests === null && data.evidence_kind === null;
}
export function archiveResult(
  action: ArchiveAction,
  value: unknown,
  device: string,
  request: string,
  p: Json,
): boolean {
  if (action === "archive_attempt") {
    return acknowledgement(value, device, request, p);
  }
  if (
    !keys(value, ["target_request_id", "outcome", "recorded_result"]) ||
    !same(value.target_request_id, p.target_request_id)
  ) return false;
  if (value.outcome === "unknown") return value.recorded_result === null;
  return value.outcome === "recorded" &&
    acknowledgement(
      value.recorded_result,
      device,
      value.target_request_id as string,
    );
}
