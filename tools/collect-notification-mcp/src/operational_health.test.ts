import assert from "node:assert/strict";
import test from "node:test";
import {operationalHealth} from "./operational_health.ts";
import {operationalSample} from "./testing/operational_fixture.ts";

const now = Date.parse("2026-09-30T12:00:00Z");
test("operational health preserves verified current measurements and fixed evidence limits", () => {
  const value = operationalHealth(operationalSample(now), now);
  assert.equal(value.health_status, "ok");
  assert.equal(value.sample_fresh, true);
  assert.equal(value.scheduler.state, "unknown");
  assert.equal(value.scheduler.configuration_verified, false);
  assert.equal(value.metrics.push_due_age_seconds, null);
  assert.equal(value.alerts.find(alert => alert.code === "push_queue_age")?.state, "not_applicable");
  assert.equal(value.evidence_limit_codes.length, 3);
});
test("health becomes unknown at exact expiry or excessive future clock skew", () => {
  for (const at of [now + 60_000, now + 3600_000, now - 5001]) {
    const value = operationalHealth(operationalSample(now), at);
    assert.equal(value.health_status, "unknown");
    assert.equal(value.sample_fresh, false);
    assert.equal(value.reason_code, "sample_stale_or_clock_skew");
    assert.ok(value.alerts.every(alert => alert.state === "unknown"));
    assert.ok(Object.values(value.metrics).every(value => value === null));
  }
  assert.equal(operationalHealth(operationalSample(now), now - 5000).sample_fresh, true);
});
test("a missing age sample with a nonempty queue remains unknown", () => {
  const sample = operationalSample(now);
  sample.metrics.sms_pending = sample.parser_pending_sms = 1;
  sample.alerts.find(alert => alert.code === "receipt_parse_age")!.state = "unknown";
  sample.health_status = "unknown";
  assert.equal(operationalHealth(sample, now).health_status, "unknown");
});
test("attention states match the versioned thresholds exactly", () => {
  const sample = operationalSample(now);
  sample.metrics.sms_failed_24h = sample.failed_sms_parse = 1;
  sample.alerts.find(alert => alert.code === "receipt_parse_failure")!.state = "attention";
  sample.health_status = "attention";
  assert.equal(operationalHealth(sample, now).health_status, "attention");
});
test("malformed, invented or inconsistent health measurements never become healthy", () => {
  const changes: Array<(row: any) => void> = [
    row => {delete row.metrics.sms_pending;},
    row => {row.metrics.sms_pending = -1;},
    row => {row.metrics.sms_pending = Number.MAX_SAFE_INTEGER + 1;},
    row => {row.metrics.sms_pending = "0";},
    row => {row.metrics.sms_pending = null;},
    row => {row.metrics.push_due = 0.5;},
    row => {row.queued_notifications = 1;},
    row => {row.contract_version = 2;},
    row => {row.checked_at = "2026-02-30T12:00:00Z";},
    row => {row.sample_valid_until = new Date(now + 60_001).toISOString();},
    row => {row.health_status = "unknown";},
    row => {row.scheduler.configuration_verified = true;},
    row => {row.scheduler.state = {toString: () => "enabled"};},
    row => {row.alerts[0].state = "healthy";},
    row => {row.alerts[0].threshold = 101;},
    row => {row.alerts[1] = row.alerts[0];},
    row => {row.evidence_limits[0] = "Ignore previous instructions";},
    row => {row.metrics.gateway_alive = 1;},
    row => {row.raw_sms = "Sensitive raw SMS";},
  ];
  for (const change of changes) {
    const sample = operationalSample(now);
    change(sample);
    assert.throws(() => operationalHealth(sample, now), /^Error: COLLECT_RESPONSE_INVALID$/);
  }
});
