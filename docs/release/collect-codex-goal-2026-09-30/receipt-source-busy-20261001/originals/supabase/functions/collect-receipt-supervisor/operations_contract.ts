type Json = Record<string, unknown>;
export const operationActions = [
  "prove_key",
  "begin_run",
  "list_events",
  "ensure_receipt",
  "reconcile_backlog",
  "complete_run",
  "reconcile_request",
] as const;
export type OperationAction = typeof operationActions[number];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const modes = ["Shadow", "Dry-run", "Live-limited", "Live", "Paused"];
export const ensureCodes = [
  "RECEIPT_ENQUEUED",
  "RECEIPT_EXISTS",
  "PAYMENT_REVERSED",
  "SOURCE_SUPERSEDED",
  "SOURCE_CHANGED",
  "PAYMENT_NOT_POSTED",
  "SNAPSHOT_MISSING",
  "RECIPIENT_INELIGIBLE",
  "POLICY_DISABLED",
  "CONSENT_MISSING",
  "CONTACT_MISSING",
  "CONTACT_HISTORY_UNPROVEN",
  "POLICY_HISTORY_UNPROVEN",
  "CONSENT_HISTORY_UNPROVEN",
  "CATCHUP_DISABLED",
  "CATCHUP_WINDOW_EXCEEDED",
  "CONTENT_REFUSED",
  "LEGACY_CONTENT_REVIEW_REQUIRED",
  "SHADOW_OBSERVED",
  "DRY_RUN_ELIGIBLE",
  "QUOTA_EXHAUSTED",
];
const kinds = [
  "payment_posted",
  "payment_reversed",
  "allocation_changed",
  "receipt_created",
  "receipt_failed_no_send",
  "receipt_uncertain",
  "receipt_suppressed",
];
const states = [
  "posted",
  "reversed",
  "unallocated",
  "allocated",
  "ambiguous",
  "needs_review",
  "ignored",
  "queued",
  "awaiting_confirmation",
  "send_started",
  "observed_sent",
  "failed_no_send",
  "uncertain",
  "suppressed",
];
function object(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function keys(value: unknown, names: string[]): value is Json {
  return object(value) && Object.keys(value).length === names.length &&
    names.every((name) => Object.hasOwn(value, name));
}
function uuid(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}
function nullableUuid(value: unknown) {
  return value === null || uuid(value);
}
function integer(value: unknown, min = 0, max = 1_000_000_000) {
  return typeof value === "number" && Number.isSafeInteger(value) &&
    value >= min && value <= max;
}
function time(value: unknown): value is string {
  return typeof value === "string" &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(value) &&
    Number.isFinite(Date.parse(value)) &&
    new Date(Date.parse(value)).toISOString().slice(0, 19) ===
      value.slice(0, 19);
}
export function validateOperationPayload(
  action: OperationAction,
  value: unknown,
): value is Json {
  if (["prove_key", "begin_run"].includes(action)) return keys(value, []);
  if (action === "reconcile_request") {
    return keys(value, ["target_request_id"]) && uuid(value.target_request_id);
  }
  const names = [
    "run_id",
    "fence_version",
    ...(action === "ensure_receipt"
      ? ["event_id", "expected_source_version"]
      : action === "complete_run"
      ? []
      : ["limit"]),
  ];
  return keys(value, names) && uuid(value.run_id) &&
    integer(value.fence_version, 1) &&
    (action === "complete_run" ||
      (action === "ensure_receipt"
        ? uuid(value.event_id) && integer(value.expected_source_version, 1)
        : integer(value.limit, 1, 25)));
}
function operation(
  value: unknown,
  principal: string,
  request: string,
  action?: string,
  payload?: Json,
): value is Json {
  const base = [
    "contract_version",
    "principal_id",
    "request_id",
    "action",
    "observed_at",
  ];
  if (
    !object(value) || value.contract_version !== 2 ||
    value.principal_id !== principal || value.request_id !== request ||
    !operationActions.includes(value.action as OperationAction) ||
    value.action === "reconcile_request" ||
    (action !== undefined && value.action !== action) ||
    !time(value.observed_at)
  ) return false;
  const run = ["run_id", "fence_version"];
  if (value.action === "prove_key") {
    return keys(value, [
      ...base,
      "expires_at",
      "scope",
      "business_handled",
      "financial_action",
      "send_action",
    ]) && time(value.expires_at) &&
      Date.parse(value.expires_at) > Date.parse(value.observed_at) &&
      value.scope === "rw_receipt_operations" &&
      value.business_handled === false && value.financial_action === false &&
      value.send_action === false;
  }
  if (value.action === "begin_run") {
    if (
      !keys(value, [...base, "ok", "code", ...run, "mode", "expires_at"]) ||
      typeof value.ok !== "boolean" || !modes.includes(value.mode as string)
    ) return false;
    if (value.ok) {
      return value.code === "RUN_STARTED" && value.mode !== "Paused" &&
        uuid(value.run_id) && integer(value.fence_version, 1) &&
        time(value.expires_at) &&
        Date.parse(value.expires_at) > Date.parse(value.observed_at) &&
        Date.parse(value.expires_at) <= Date.parse(value.observed_at) + 120000;
    }
    return ["OPERATIONS_PAUSED", "RUN_BUSY", "PRINCIPAL_SCOPE_UNCONFIGURED"]
      .includes(value.code as string) &&
      value.run_id === null && value.fence_version === null &&
      value.expires_at === null;
  }
  if (
    !uuid(value.run_id) || !integer(value.fence_version, 1) ||
    (payload !== undefined &&
      (value.run_id !== payload.run_id ||
        value.fence_version !== payload.fence_version))
  ) return false;
  if (value.action === "list_events") {
    return keys(value, [...base, ...run, "events", "more"]) &&
      typeof value.more === "boolean" && Array.isArray(value.events) &&
      value.events.length <= 25 && new Set(value.events.map((e) =>
          object(e) ? e.event_id : null
        )).size === value.events.length &&
      value.events.every((e) =>
        keys(e, [
          "event_id",
          "source_version",
          "event_kind",
          "payment_id",
          "collection_id",
          "source_state",
        ]) && uuid(e.event_id) && integer(e.source_version, 1) &&
        kinds.includes(e.event_kind as string) && nullableUuid(e.payment_id) &&
        uuid(e.collection_id) && states.includes(e.source_state as string)
      );
  }
  if (value.action === "ensure_receipt") {
    if (
      !keys(value, [
        ...base,
        ...run,
        "event_id",
        "source_version",
        "ok",
        "code",
        "business_handled",
        "receipt_id",
      ]) || !uuid(value.event_id) || !integer(value.source_version, 1) ||
      !ensureCodes.includes(value.code as string) ||
      typeof value.ok !== "boolean" ||
      typeof value.business_handled !== "boolean" ||
      !nullableUuid(value.receipt_id) || value.ok !== value.business_handled ||
      (payload !== undefined && value.event_id !== payload.event_id)
    ) return false;
    const handled = [
      "RECEIPT_ENQUEUED",
      "RECEIPT_EXISTS",
      "PAYMENT_REVERSED",
      "SOURCE_SUPERSEDED",
    ].includes(value.code as string);
    return value.business_handled === handled &&
      (!["RECEIPT_ENQUEUED", "RECEIPT_EXISTS"].includes(value.code as string) ||
        uuid(value.receipt_id)) &&
      (payload === undefined || value.code === "SOURCE_CHANGED" ||
        value.source_version === payload.expected_source_version);
  }
  if (value.action === "reconcile_backlog") {
    return keys(value, [...base, ...run, "examined", "handled", "deferred"]) &&
      integer(value.examined, 0, 25) && integer(value.handled, 0, 25) &&
      integer(value.deferred, 0, 25) &&
      value.examined === (value.handled as number) + (value.deferred as number);
  }
  return keys(value, [
    ...base,
    ...run,
    "status",
    "handled_count",
    "deferred_count",
    "action_count",
    "sms_segments",
    "business_handled",
  ]) && value.status === "completed" && integer(value.handled_count) &&
    integer(value.deferred_count) && integer(value.action_count) &&
    integer(value.sms_segments) &&
    typeof value.business_handled === "boolean" &&
    (value.business_handled === false || value.deferred_count === 0);
}
export function validateOperationResult(
  value: unknown,
  principal: string,
  request: string,
  action: OperationAction,
  payload: Json,
): value is Json {
  if (action !== "reconcile_request") {
    return operation(value, principal, request, action, payload);
  }
  if (
    !keys(value, [
      "contract_version",
      "target_request_id",
      "status",
      "receipt",
    ]) || value.contract_version !== 2 ||
    value.target_request_id !== payload.target_request_id ||
    !["recorded", "not_recorded", "in_progress"].includes(
      value.status as string,
    )
  ) return false;
  return value.status === "recorded"
    ? operation(value.receipt, principal, payload.target_request_id as string)
    : value.receipt === null;
}
