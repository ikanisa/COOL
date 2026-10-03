/** Separate operations v2 scope. These contracts authorize governed receipt
 * preparation only; no sender, recipient, message or financial mutation input. */
export const unattendedAudience = "collect.receipt-supervisor.v2/lhbowpbcpwoiparwnwgt";
export const unattendedScope = "rw_receipt_operations";
export const unattendedEndpoint = "https://lhbowpbcpwoiparwnwgt.supabase.co/functions/v1/collect-receipt-supervisor";
export const unattendedActions = ["prove_key", "begin_run", "list_events", "ensure_receipt", "reconcile_backlog", "complete_run", "reconcile_request"] as const;
export type UnattendedAction = typeof unattendedActions[number];
export type Json = Record<string, unknown>;
export interface UnattendedIdentity {principalId: string; keySha256: string; expiresAt: string}
export interface UnattendedRequest {action: UnattendedAction; requestId: string; payload: Json}
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export function uuid(value: unknown): value is string {return typeof value === "string" && uuidPattern.test(value);}
export function hash(value: unknown): value is string {return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);}
export function object(value: unknown): value is Json {return value !== null && typeof value === "object" && !Array.isArray(value);}
export function keys(value: unknown, names: readonly string[]): value is Json {
  return object(value) && Object.keys(value).length === names.length && names.every(name => Object.hasOwn(value, name));
}
export function integer(value: unknown, min = 0, max = 1_000_000_000): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max;
}
export function utc(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(value) &&
    Number.isFinite(Date.parse(value)) && new Date(Date.parse(value)).toISOString().slice(0, 19) === value.slice(0, 19);
}
export function validIdentity(value: unknown, now: number): value is UnattendedIdentity {
  return keys(value, ["principalId", "keySha256", "expiresAt"]) && uuid(value.principalId) && hash(value.keySha256) &&
    utc(value.expiresAt) && integer(now, 0, 253402300799999) && Date.parse(value.expiresAt) > now + 15_000;
}
export function validRequest(value: unknown): value is UnattendedRequest {
  if (!keys(value, ["action", "requestId", "payload"]) || !uuid(value.requestId) || typeof value.action !== "string" ||
      !unattendedActions.includes(value.action as UnattendedAction)) return false;
  const p = value.payload;
  if (value.action === "begin_run" || value.action === "prove_key") return keys(p, []);
  if (value.action === "reconcile_request") return keys(p, ["target_request_id"]) && uuid(p.target_request_id) && p.target_request_id !== value.requestId;
  if (!object(p) || !uuid(p.run_id) || !integer(p.fence_version, 1)) return false;
  if (value.action === "complete_run") return keys(p, ["run_id", "fence_version"]);
  if (value.action === "ensure_receipt") return keys(p, ["run_id", "fence_version", "event_id", "expected_source_version"]) &&
    uuid(p.event_id) && integer(p.expected_source_version, 1);
  return keys(p, ["run_id", "fence_version", "limit"]) && integer(p.limit, 1, 25);
}
export function envelope(identity: UnattendedIdentity, request: UnattendedRequest, now: number) {
  if (!validIdentity(identity, now) || !validRequest(request)) throw new Error("UNATTENDED_ARGUMENTS_INVALID");
  // Top-level and payload keys are sorted: the separate hardware helper checks
  // exact bytes, rejecting duplicate/ambiguous JSON and every unsupported action.
  const payload = Object.fromEntries(Object.entries(request.payload).sort(([a], [b]) => a.localeCompare(b, "en")));
  return {action: request.action, audience: unattendedAudience, contract_version: 2,
    issued_at: new Date(now).toISOString(), payload, principal_id: identity.principalId, request_id: request.requestId};
}
const baseKeys = ["contract_version", "principal_id", "request_id", "action", "observed_at"];
const modes = ["Shadow", "Dry-run", "Live-limited", "Live", "Paused"];
const eventKinds = ["payment_posted", "payment_reversed", "allocation_changed", "receipt_created", "receipt_failed_no_send", "receipt_uncertain", "receipt_suppressed"];
const sourceStates = ["posted", "reversed", "unallocated", "allocated", "ambiguous", "needs_review", "ignored", "queued", "awaiting_confirmation", "send_started", "observed_sent", "failed_no_send", "uncertain", "suppressed"];
// Populated from the operations server's finite contract; no free-form codes.
export const ensureCodes = ["RECEIPT_ENQUEUED", "RECEIPT_EXISTS", "PAYMENT_REVERSED", "SOURCE_SUPERSEDED", "SOURCE_CHANGED", "PAYMENT_NOT_POSTED", "SNAPSHOT_MISSING", "RECIPIENT_INELIGIBLE", "POLICY_DISABLED", "CONSENT_MISSING", "CONTACT_MISSING", "CONTACT_HISTORY_UNPROVEN", "POLICY_HISTORY_UNPROVEN", "CONSENT_HISTORY_UNPROVEN", "CATCHUP_DISABLED", "CATCHUP_WINDOW_EXCEEDED", "CONTENT_REFUSED", "LEGACY_CONTENT_REVIEW_REQUIRED", "SHADOW_OBSERVED", "DRY_RUN_ELIGIBLE", "QUOTA_EXHAUSTED"] as const;
function normalResult(value: unknown, principal: string, requestId: string, action: UnattendedAction, payload: Json): value is Json {
  if (!object(value) || value.contract_version !== 2 || value.principal_id !== principal || value.request_id !== requestId ||
      value.action !== action || !utc(value.observed_at)) return false;
  if (action === "prove_key") return keys(value, [...baseKeys, "expires_at", "scope", "business_handled", "financial_action", "send_action"]) &&
    utc(value.expires_at) && Date.parse(value.expires_at) > Date.parse(value.observed_at) && value.scope === unattendedScope && value.business_handled === false && value.financial_action === false && value.send_action === false;
  if (action === "begin_run") {
    if (!keys(value, [...baseKeys, "ok", "code", "run_id", "fence_version", "mode", "expires_at"]) ||
        typeof value.ok !== "boolean" || typeof value.mode !== "string" || !modes.includes(value.mode)) return false;
    if (value.ok) return value.code === "RUN_STARTED" && uuid(value.run_id) && integer(value.fence_version, 1) &&
      value.mode !== "Paused" && utc(value.expires_at) && Date.parse(value.expires_at) > Date.parse(value.observed_at) &&
      Date.parse(value.expires_at) <= Date.parse(value.observed_at) + 120_000;
    return typeof value.code === "string" && ["OPERATIONS_PAUSED", "RUN_BUSY", "PRINCIPAL_SCOPE_UNCONFIGURED"].includes(value.code) &&
      value.run_id === null && value.fence_version === null && value.expires_at === null;
  }
  if (value.run_id !== payload.run_id || value.fence_version !== payload.fence_version) return false;
  if (action === "list_events") {
    if (!keys(value, [...baseKeys, "run_id", "fence_version", "events", "more"]) || !Array.isArray(value.events) ||
        value.events.length > Number(payload.limit) || typeof value.more !== "boolean") return false;
    const seen = new Set<string>();
    return value.events.every(event => {
      if (!keys(event, ["event_id", "source_version", "event_kind", "payment_id", "collection_id", "source_state"]) ||
          !uuid(event.event_id) || seen.has(event.event_id) || !integer(event.source_version, 1) ||
          typeof event.event_kind !== "string" || !eventKinds.includes(event.event_kind) ||
          typeof event.source_state !== "string" || !sourceStates.includes(event.source_state) ||
          (event.payment_id !== null && !uuid(event.payment_id)) || !uuid(event.collection_id)) return false;
      seen.add(event.event_id); return true;
    });
  }
  if (action === "ensure_receipt") return keys(value, [...baseKeys, "run_id", "fence_version", "event_id", "source_version", "ok", "code", "business_handled", "receipt_id"]) &&
    value.event_id === payload.event_id && value.source_version === payload.expected_source_version &&
    typeof value.ok === "boolean" && typeof value.code === "string" && ensureCodes.includes(value.code as typeof ensureCodes[number]) &&
    typeof value.business_handled === "boolean" && value.ok === value.business_handled && value.business_handled === ["RECEIPT_ENQUEUED", "RECEIPT_EXISTS", "PAYMENT_REVERSED", "SOURCE_SUPERSEDED"].includes(value.code) &&
    (value.receipt_id === null || uuid(value.receipt_id)) &&
    (!["RECEIPT_ENQUEUED", "RECEIPT_EXISTS"].includes(value.code) || uuid(value.receipt_id));
  if (action === "reconcile_backlog") return keys(value, [...baseKeys, "run_id", "fence_version", "examined", "handled", "deferred"]) &&
    integer(value.examined, 0, Number(payload.limit)) && integer(value.handled, 0, Number(payload.limit)) &&
    integer(value.deferred, 0, Number(payload.limit)) && value.handled + value.deferred === value.examined;
  if (action === "complete_run") return keys(value, [...baseKeys, "run_id", "fence_version", "status", "handled_count", "deferred_count", "action_count", "sms_segments", "business_handled"]) &&
    value.status === "completed" && integer(value.handled_count) && integer(value.deferred_count) && integer(value.action_count) &&
    integer(value.sms_segments) && typeof value.business_handled === "boolean" && (value.business_handled === false || value.deferred_count === 0);
  return false;
}
/** No opaque extras or private fields are projected from a successful response. */
export function validResult(value: unknown, identity: UnattendedIdentity, request: UnattendedRequest): value is Json {
  if (request.action !== "reconcile_request") return normalResult(value, identity.principalId, request.requestId, request.action, request.payload);
  if (!keys(value, ["contract_version", "target_request_id", "status", "receipt"]) || value.contract_version !== 2 ||
      value.target_request_id !== request.payload.target_request_id || typeof value.status !== "string" ||
      !["recorded", "not_recorded", "in_progress"].includes(value.status)) return false;
  if (value.status !== "recorded") return value.receipt === null;
  const receipt = value.receipt;
  if (!object(receipt) || typeof receipt.action !== "string" || !unattendedActions.includes(receipt.action as UnattendedAction) || receipt.action === "reconcile_request") return false;
  // A lookup has no caller-supplied run/event payload. Reconstruct only the
  // strictly validated opaque binding fields, then validate the entire receipt.
  const payload: Json = ["begin_run", "prove_key"].includes(receipt.action) ? {} :
    receipt.action === "ensure_receipt" ? {run_id: receipt.run_id, fence_version: receipt.fence_version, event_id: receipt.event_id, expected_source_version: receipt.source_version} :
      receipt.action === "list_events" || receipt.action === "reconcile_backlog" ? {run_id: receipt.run_id, fence_version: receipt.fence_version, limit: 25} :
        {run_id: receipt.run_id, fence_version: receipt.fence_version};
  return validRequest({action: receipt.action, requestId: value.target_request_id, payload}) &&
    normalResult(receipt, identity.principalId, String(value.target_request_id), receipt.action as UnattendedAction, payload);
}
