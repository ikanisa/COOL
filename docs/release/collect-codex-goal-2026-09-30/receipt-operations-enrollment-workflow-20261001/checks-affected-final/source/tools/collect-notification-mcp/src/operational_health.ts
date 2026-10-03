// Mirrors the versioned, redacted admin_system_health contract. Backend text
// and arbitrary extras never become tool instructions or apparent healthy data.
export const healthMetricNames = [
  "durable_receipts_24h", "sms_pending", "sms_pending_age_seconds", "sms_failed_24h",
  "sms_parsed_24h", "sms_expired_parse_leases", "unallocated_events", "payments_review",
  "payment_review_age_seconds", "payments_posted_24h", "reconciliation_open", "reversals_24h",
  "finality_processing", "finality_processed_24h", "push_queued", "push_due", "push_due_age_seconds",
  "push_processing", "push_expired_leases", "push_missing_leases", "push_failed", "push_attempts_24h",
  "push_failed_24h", "push_provider_accepts_24h", "push_retry_24h", "push_latency_p95_ms",
  "receipt_ack_generated_24h", "receipt_rejected_24h", "receipt_telemetry_age_seconds",
  "receipt_ack_latency_mean_ms", "push_scheduler_age_seconds",
] as const;
export const healthRules = {
  receipt_parse_backlog: ["sms_pending", 100, null],
  receipt_parse_age: ["sms_pending_age_seconds", 300, "sms_pending"],
  receipt_parse_failure: ["sms_failed_24h", 1, null],
  receipt_parser_lease_expired: ["sms_expired_parse_leases", 1, null],
  payment_unmatched: ["unallocated_events", 1, null],
  payment_review_age: ["payment_review_age_seconds", 3600, "payments_review"],
  reconciliation_exception: ["reconciliation_open", 1, null],
  push_queue_age: ["push_due_age_seconds", 120, "push_due"],
  push_expired_lease: ["push_expired_leases", 1, null],
  push_missing_lease: ["push_missing_leases", 1, null],
  push_attempt_failure: ["push_failed_24h", 5, null],
  receipt_telemetry_stale: ["receipt_telemetry_age_seconds", 300, "durable_receipts_24h"],
  push_scheduler_stale: ["push_scheduler_age_seconds", 180, "push_due"],
} as const;
export const healthEvidenceLimits = [
  "ACK generation does not prove device receipt.",
  "Provider acceptance does not prove user delivery.",
  "Scheduler activation does not prove provider configuration.",
] as const;
const invalid = (): never => { throw new Error("COLLECT_RESPONSE_INVALID"); };

export function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return invalid();
  return value as Record<string, unknown>;
}
export function exactObject(value: unknown, keys: readonly string[]) {
  const row = object(value);
  if (Object.keys(row).length !== keys.length || keys.some(key => !Object.hasOwn(row, key))) return invalid();
  return row;
}
export function nonnegativeInteger(value: unknown): number {
  if (!Number.isSafeInteger(value) || Number(value) < 0) return invalid();
  return value as number;
}
export function instant(value: unknown): string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$/.test(value)) return invalid();
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 19) !== value.slice(0, 19)) return invalid();
  return date.toISOString();
}

export function operationalHealth(value: unknown, now = Date.now()) {
  const row = exactObject(value, [
    "id", "contract_version", "database", "auth", "parser_pending_sms", "failed_sms_parse",
    "unallocated_events", "queued_notifications", "processing_notifications", "failed_notifications",
    "checked_at", "metrics", "alerts", "health_status", "sample_valid_until", "window_seconds",
    "threshold_version", "scheduler", "evidence_limits",
  ]);
  if (row.id !== "system" || row.contract_version !== 1 || row.database !== "reachable" ||
      row.auth !== "authenticated" || row.window_seconds !== 86400 || row.threshold_version !== 1) return invalid();
  const checkedAt = instant(row.checked_at), validUntil = instant(row.sample_valid_until);
  if (Date.parse(validUntil) - Date.parse(checkedAt) !== 60_000) return invalid();
  const source = exactObject(row.metrics, healthMetricNames);
  const metrics: Record<string, number | null> = {};
  for (const name of healthMetricNames) {
    const nullable = name.endsWith("_seconds") || name.endsWith("_ms");
    metrics[name] = nullable && source[name] === null ? null : nonnegativeInteger(source[name]);
  }
  for (const [alias, metric] of Object.entries({
    parser_pending_sms: "sms_pending", failed_sms_parse: "sms_failed_24h", unallocated_events: "unallocated_events",
    queued_notifications: "push_queued", processing_notifications: "push_processing", failed_notifications: "push_failed",
  })) if (row[alias] !== metrics[metric]) return invalid();
  const scheduler = exactObject(row.scheduler, ["state", "configuration_verified"]);
  if (typeof scheduler.state !== "string" || !["enabled", "disabled", "unknown"].includes(scheduler.state) || scheduler.configuration_verified !== false) return invalid();
  if (!Array.isArray(row.evidence_limits) || row.evidence_limits.length !== healthEvidenceLimits.length ||
      row.evidence_limits.some((limit, i) => limit !== healthEvidenceLimits[i])) return invalid();
  if (!Array.isArray(row.alerts) || row.alerts.length !== Object.keys(healthRules).length) return invalid();
  const alerts: Record<string, string> = {};
  for (const raw of row.alerts) {
    const alert = exactObject(raw, ["code", "metric", "threshold", "state"]);
    if (typeof alert.code !== "string" || !Object.hasOwn(healthRules, alert.code) || Object.hasOwn(alerts, alert.code)) return invalid();
    const [metric, threshold, queue] = healthRules[alert.code as keyof typeof healthRules];
    const value = metrics[metric];
    const expected = queue !== null && metrics[queue] === 0 ? "not_applicable" : value === null ? "unknown" :
      typeof value === "number" && value >= threshold ? "attention" : "ok";
    if (alert.metric !== metric || alert.threshold !== threshold || alert.state !== expected) return invalid();
    alerts[alert.code] = expected;
  }
  const reportedStatus = Object.values(alerts).includes("attention") ? "attention" :
    Object.values(alerts).includes("unknown") ? "unknown" : "ok";
  if (row.health_status !== reportedStatus) return invalid();
  const fresh = now >= Date.parse(checkedAt) - 5000 && now < Date.parse(validUntil);
  return {
    contract_version: 1, health_status: fresh ? reportedStatus : "unknown",
    reason_code: fresh ? "current_database_sample" : "sample_stale_or_clock_skew",
    sample_fresh: fresh, checked_at: checkedAt, sample_valid_until: validUntil,
    window_seconds: 86400, threshold_version: 1,
    metrics: fresh ? metrics : Object.fromEntries(healthMetricNames.map(name => [name, null])) as Record<string, number | null>,
    alerts: Object.entries(alerts).map(([code, state]) => ({code, state: fresh ? state : "unknown"})),
    scheduler: {state: fresh ? scheduler.state : "unknown", configuration_verified: false},
    evidence_limit_codes: ["ack_generation_not_device_receipt", "provider_acceptance_not_user_delivery", "scheduler_activation_not_provider_configuration"],
  };
}
