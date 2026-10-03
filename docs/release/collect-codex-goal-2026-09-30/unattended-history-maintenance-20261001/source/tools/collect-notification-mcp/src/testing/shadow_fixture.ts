import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {operationalSample} from "./operational_fixture.ts";
import {healthRules} from "../operational_health.ts";
export const shadowRequestId = "22222222-2222-4222-8222-222222222222";
export const shadowRunId = "11111111-1111-4111-8111-111111111111";
export const shadowSampleId = "33333333-3333-4333-8333-333333333333";
export const shadowBase = {contract_version: 1, mode: "shadow", scope: "collect_platform"};
export function publishedShadowFixture() {
  return JSON.parse(readFileSync(fileURLToPath(new URL("../../../../contracts/collect-shadow-supervisor-v1.lifecycle.fixture.json", import.meta.url)), "utf8"));
}
export function shadowFixture(at = Date.now()) {
  const queue = {enabled: false, queued: 0, awaiting_confirmation: 0, send_started: 0, uncertain: 0, suppressed: 0, active_workers: 0};
  const health = operationalSample(at);
  const summary = {health_status: "ok", alert_counts: {ok: 8, unknown: 0, attention: 0, not_applicable: 5}, sms_queue: queue,
    checks_recorded: Object.keys(healthRules).length, samples_recorded: 1, business_mutations: 0, provider_sends: 0};
  const run = {run_id: shadowRunId, request_id: shadowRequestId, fence_version: 1, status: "running", started_at: new Date(at - 1000).toISOString(),
    lease_expires_at: new Date(at + 119_000).toISOString(), sampled_at: null as string | null, completed_at: null as string | null, summary: null as typeof summary | null};
  const completed = {...run, status: "completed", sampled_at: new Date(at).toISOString(), completed_at: new Date(at + 1).toISOString(), summary};
  return {
    begin: {...shadowBase, ok: true, outcome: "started", replayed: false, run},
    busy: {...shadowBase, ok: false, outcome: "busy", reason_code: "shadow_run_busy", request_id: shadowRequestId, retry_after_seconds: 30},
    sample: {...shadowBase, ok: true, outcome: "sampled", replayed: false, run_id: shadowRunId, fence_version: 1,
      sample: {sample_id: shadowSampleId, checked_at: new Date(at).toISOString(), system_health: health,
        sms_queue: {...queue, oldest_queued_at: null, observed_at: new Date(at).toISOString()}, summary, content_sha256: "a".repeat(64)}},
    complete: {...shadowBase, ok: true, outcome: "completed", replayed: false, run: completed},
    get: {...shadowBase, found: true, run: completed},
  };
}
