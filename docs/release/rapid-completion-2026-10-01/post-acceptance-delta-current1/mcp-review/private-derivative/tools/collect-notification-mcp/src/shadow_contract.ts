import {exactObject, instant, nonnegativeInteger, operationalHealth} from "./operational_health.ts";

const invalid = (): never => {throw new Error("SHADOW_RESPONSE_INVALID");};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const counts = ["queued", "awaiting_confirmation", "send_started", "uncertain", "suppressed", "active_workers"] as const;
const alertStates = ["ok", "unknown", "attention", "not_applicable"] as const;
export type ShadowAction = "begin" | "sample" | "complete" | "get";
export function shadowUuid(value: unknown): string {
  if (typeof value !== "string" || !uuid.test(value)) return invalid();
  return value.toLowerCase();
}
export function fence(value: unknown): number {
  const version = nonnegativeInteger(value);
  if (version < 1 || version > 1_000_000_000) return invalid();
  return version;
}
function nullableInstant(value: unknown) {return value === null ? null : instant(value);}
function common(row: Record<string, unknown>) {
  if (row.contract_version !== 1 || row.mode !== "shadow" || row.scope !== "collect_platform") return invalid();
  return {contract_version: 1 as const, mode: "shadow" as const, scope: "collect_platform" as const};
}
function summaryQueue(value: unknown) {
  const row = exactObject(value, ["enabled", ...counts]);
  if (typeof row.enabled !== "boolean") return invalid();
  return {enabled: row.enabled, ...Object.fromEntries(counts.map(key => [key, nonnegativeInteger(row[key])]))} as
    {enabled: boolean} & Record<typeof counts[number], number>;
}
export function shadowSummary(value: unknown) {
  const row = exactObject(value, ["health_status", "alert_counts", "sms_queue", "checks_recorded", "samples_recorded", "business_mutations", "provider_sends"]);
  if (typeof row.health_status !== "string" || !["ok", "unknown", "attention"].includes(row.health_status) ||
      row.checks_recorded !== 13 || row.samples_recorded !== 1 || row.business_mutations !== 0 || row.provider_sends !== 0) return invalid();
  const source = exactObject(row.alert_counts, alertStates);
  const alertCounts = Object.fromEntries(alertStates.map(key => [key, nonnegativeInteger(source[key])])) as Record<typeof alertStates[number], number>;
  if (Object.values(alertCounts).some(value => value > 13) || Object.values(alertCounts).reduce((sum, value) => sum + value, 0) !== 13) return invalid();
  const queue = summaryQueue(row.sms_queue);
  const status = alertCounts.attention > 0 || queue.uncertain > 0 || queue.send_started > 0 ? "attention" : alertCounts.unknown > 0 ? "unknown" : "ok";
  if (row.health_status !== status) return invalid();
  return {health_status: status, alert_counts: alertCounts, sms_queue: queue,
    checks_recorded: 13, samples_recorded: 1, business_mutations: 0, provider_sends: 0};
}
export function shadowRun(value: unknown) {
  const row = exactObject(value, ["run_id", "request_id", "fence_version", "status", "started_at", "lease_expires_at", "sampled_at", "completed_at", "summary"]);
  if (typeof row.status !== "string" || !["running", "completed", "expired"].includes(row.status)) return invalid();
  const startedAt = instant(row.started_at), leaseExpiresAt = instant(row.lease_expires_at);
  const sampledAt = nullableInstant(row.sampled_at), completedAt = nullableInstant(row.completed_at);
  if (Date.parse(leaseExpiresAt) - Date.parse(startedAt) !== 120_000 ||
      (sampledAt !== null && (Date.parse(sampledAt) < Date.parse(startedAt) || Date.parse(sampledAt) >= Date.parse(leaseExpiresAt))) ||
      (completedAt !== null && (sampledAt === null || Date.parse(completedAt) < Date.parse(sampledAt) || Date.parse(completedAt) >= Date.parse(leaseExpiresAt))) ||
      (row.status === "completed") !== (completedAt !== null) ||
      (sampledAt === null) !== (row.summary === null)) return invalid();
  return {run_id: shadowUuid(row.run_id), request_id: shadowUuid(row.request_id), fence_version: fence(row.fence_version), status: row.status,
    started_at: startedAt, lease_expires_at: leaseExpiresAt, sampled_at: sampledAt, completed_at: completedAt,
    summary: row.summary === null ? null : shadowSummary(row.summary)};
}

export function projectedShadowSample(value: unknown, expected: Record<string, unknown>, now = Date.now()) {
  try {
    const row = exactObject(value, ["contract_version", "mode", "scope", "ok", "outcome", "replayed", "run_id", "fence_version", "sample"]);
    if (row.ok !== true || row.outcome !== "sampled" || typeof row.replayed !== "boolean" ||
        shadowUuid(row.run_id) !== expected.run_id || fence(row.fence_version) !== expected.fence_version) return invalid();
    const sample = exactObject(row.sample, ["sample_id", "checked_at", "sample_valid_until", "sample_fresh", "summary"]);
    const checkedAt = instant(sample.checked_at), validUntil = instant(sample.sample_valid_until);
    if (typeof sample.sample_fresh !== "boolean" || Date.parse(validUntil) <= Date.parse(checkedAt) ||
        Date.parse(validUntil) > Date.parse(checkedAt) + 60_000) return invalid();
    return {...common(row), ok: true as const, outcome: "sampled" as const, replayed: row.replayed,
      run_id: shadowUuid(row.run_id), fence_version: fence(row.fence_version), sample: {sample_id: shadowUuid(sample.sample_id),
        checked_at: checkedAt, sample_valid_until: validUntil, sample_fresh: sample.sample_fresh && now >= Date.parse(checkedAt) - 5000 && now < Date.parse(validUntil),
        summary: shadowSummary(sample.summary)}};
  } catch {return invalid();}
}

export function shadowResult(action: ShadowAction, value: unknown, expected: Record<string, unknown>, now = Date.now()) {
  try {
    if (action === "begin") {
      const source = value as Record<string, unknown> | null;
      if (source?.outcome === "busy") {
        const row = exactObject(value, ["contract_version", "mode", "scope", "ok", "outcome", "reason_code", "retry_after_seconds", "request_id"]);
        const retryAfter = nonnegativeInteger(row.retry_after_seconds), requestId = shadowUuid(row.request_id);
        if (row.ok !== false || row.reason_code !== "shadow_run_busy" || retryAfter < 1 || retryAfter > 120 || requestId !== expected.request_id) return invalid();
        return {...common(row), ok: false as const, outcome: "busy" as const, reason_code: "shadow_run_busy", retry_after_seconds: retryAfter, request_id: requestId};
      }
      const row = exactObject(value, ["contract_version", "mode", "scope", "ok", "outcome", "replayed", "run"]);
      if (row.ok !== true || typeof row.replayed !== "boolean" || (row.outcome !== "started" && row.outcome !== "replayed") ||
          row.replayed !== (row.outcome === "replayed")) return invalid();
      const run = shadowRun(row.run);
      if (run.request_id !== expected.request_id || (row.outcome === "started" && run.status !== "running")) return invalid();
      return {...common(row), ok: true as const, outcome: row.outcome, replayed: row.replayed, run};
    }
    if (action === "get") {
      const row = exactObject(value, ["contract_version", "mode", "scope", "found", "run"]);
      if (typeof row.found !== "boolean" || row.found !== (row.run !== null)) return invalid();
      const run = row.run === null ? null : shadowRun(row.run);
      if (run !== null && run.request_id !== expected.request_id) return invalid();
      return {...common(row), found: row.found, run};
    }
    if (action === "complete") {
      const row = exactObject(value, ["contract_version", "mode", "scope", "ok", "outcome", "replayed", "run"]);
      if (row.ok !== true || row.outcome !== "completed" || typeof row.replayed !== "boolean") return invalid();
      const run = shadowRun(row.run);
      if (run.run_id !== expected.run_id || run.fence_version !== expected.fence_version || run.status !== "completed") return invalid();
      return {...common(row), ok: true as const, outcome: "completed" as const, replayed: row.replayed, run};
    }
    const row = exactObject(value, ["contract_version", "mode", "scope", "ok", "outcome", "replayed", "run_id", "fence_version", "sample"]);
    if (row.ok !== true || row.outcome !== "sampled" || typeof row.replayed !== "boolean" ||
        shadowUuid(row.run_id) !== expected.run_id || fence(row.fence_version) !== expected.fence_version) return invalid();
    const sample = exactObject(row.sample, ["sample_id", "checked_at", "system_health", "sms_queue", "summary", "content_sha256"]);
    if (typeof sample.content_sha256 !== "string" || !/^[0-9a-f]{64}$/.test(sample.content_sha256)) return invalid();
    const rawQueue = exactObject(sample.sms_queue, ["enabled", ...counts, "oldest_queued_at", "observed_at"]);
    const queue = summaryQueue(Object.fromEntries(["enabled", ...counts].map(key => [key, rawQueue[key]])));
    const oldest = nullableInstant(rawQueue.oldest_queued_at), observedAt = instant(rawQueue.observed_at);
    if ((queue.queued === 0) !== (oldest === null) || (oldest !== null && Date.parse(oldest) > Date.parse(observedAt))) return invalid();
    const rawHealth = sample.system_health as Record<string, unknown>;
    const recorded = operationalHealth(rawHealth, Date.parse(instant(rawHealth.checked_at)));
    const summary = shadowSummary(sample.summary);
    const expectedCounts = Object.fromEntries(alertStates.map(state => [state, recorded.alerts.filter(alert => alert.state === state).length]));
    const severity = recorded.health_status === "attention" || queue.uncertain > 0 || queue.send_started > 0 ? "attention" : recorded.health_status;
    if (summary.health_status !== severity || alertStates.some(state => summary.alert_counts[state] !== expectedCounts[state]) ||
        summary.sms_queue.enabled !== queue.enabled || counts.some(key => summary.sms_queue[key] !== queue[key])) return invalid();
    const checkedAt = instant(sample.checked_at);
    const validUntil = new Date(Math.min(Date.parse(recorded.sample_valid_until), Date.parse(observedAt) + 60_000)).toISOString();
    if (Date.parse(validUntil) <= Date.parse(checkedAt) || Date.parse(validUntil) > Date.parse(checkedAt) + 60_000) return invalid();
    return {...common(row), ok: true as const, outcome: "sampled" as const, replayed: row.replayed,
      run_id: shadowUuid(row.run_id), fence_version: fence(row.fence_version), sample: {
        sample_id: shadowUuid(sample.sample_id), checked_at: checkedAt, sample_valid_until: validUntil,
        sample_fresh: now >= Date.parse(checkedAt) - 5000 && now < Date.parse(validUntil), summary,
      }};
  } catch {return invalid();}
}
