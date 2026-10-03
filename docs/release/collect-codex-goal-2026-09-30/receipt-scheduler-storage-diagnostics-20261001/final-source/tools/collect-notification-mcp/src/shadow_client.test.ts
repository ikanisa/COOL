import assert from "node:assert/strict";
import test from "node:test";
import {callShadowRpc} from "./shadow_client.ts";
import {operatorEnvironment} from "./operator_client.ts";
import {projectedShadowSample, shadowResult, type ShadowAction} from "./shadow_contract.ts";
import {operationalEnvironment} from "./testing/operational_fixture.ts";
import {publishedShadowFixture, shadowFixture, shadowRequestId, shadowRunId} from "./testing/shadow_fixture.ts";
const now = Date.parse("2026-09-30T18:00:03Z");
const environment = operatorEnvironment(operationalEnvironment("https://synthetic.supabase.co", now));
const fenced = {run_id: shadowRunId, fence_version: 1};
test("shadow bridge accepts the backend-owned lifecycle fixture with bounded safe projection", () => {
  const fixture = publishedShadowFixture();
  for (const [action, raw, expected] of [["begin", fixture.begin, {request_id: shadowRequestId}], ["sample", fixture.sample, fenced],
    ["complete", fixture.finish, fenced], ["get", fixture.get, {request_id: shadowRequestId}]] as const) {
    const value = shadowResult(action, raw, expected, now);
    assert.equal(value.contract_version, 1);
    assert.equal(value.scope, "collect_platform");
    assert.doesNotMatch(JSON.stringify(value), /system_health|content_sha256|phone|amount|message_body|actor_user|session_id/);
    if (action === "sample") assert.equal(projectedShadowSample(value, fenced, now).sample.sample_fresh, true);
  }
});
test("all shadow actions use fixed public RPCs and refuse caller-supplied scope, count, content and fences", async () => {
  const fixture = shadowFixture(now);
  const calls: Array<Record<string, unknown>> = [];
  for (const action of ["begin", "sample", "complete", "get"] as ShadowAction[]) {
    const input = action === "begin" || action === "get" ? {request_id: shadowRequestId} : fenced;
    await callShadowRpc(action, input, environment, async (url, init) => {
      calls.push({url: String(url), body: JSON.parse(String(init?.body)), redirect: init?.redirect});
      return Response.json(fixture[action]);
    }, () => now);
  }
  assert.deepEqual(calls.map(x => x.url), ["begin", "sample", "finish", "get"].map(x => `https://synthetic.supabase.co/rest/v1/rpc/${x}_collect_shadow_run_v1`));
  assert.deepEqual(calls.map(x => x.body), [{p_request_id: shadowRequestId}, {p_run_id: shadowRunId, p_fence_version: 1},
    {p_run_id: shadowRunId, p_fence_version: 1}, {p_request_id: shadowRequestId}]);
  assert.ok(calls.every(x => x.redirect === "error"));
  for (const input of [{...fenced, fence_version: 0}, {...fenced, fence_version: 1_000_000_001}, {...fenced, tenant: "other"},
    {...fenced, summary: {}}, {...fenced, phone: "+250788123456"}, {run_id: shadowRunId}]) {
    await assert.rejects(callShadowRpc("sample", input, environment, async () => {throw new Error("MUST_NOT_FETCH");}, () => now), /^Error: SHADOW_ARGUMENTS_INVALID$/);
  }
});
test("strict shadow results reject inconsistent counts, identities, leases, states and injected fields", () => {
  const changes: Array<(fixture: any) => void> = [
    x => {x.begin.run.request_id = shadowRunId;}, x => {x.begin.run.fence_version = 1_000_000_001;},
    x => {x.begin.run.lease_expires_at = new Date(now + 999_000).toISOString();}, x => {x.begin.run.status = "healthy";},
    x => {x.begin.scope = "tenant_provided";}, x => {x.begin.actor = "SECRET";},
    x => {x.begin.run.sampled_at = x.begin.run.lease_expires_at; x.begin.run.summary = x.complete.run.summary;},
  ];
  for (const change of changes) {const fixture = shadowFixture(now); change(fixture); assert.throws(() => shadowResult("begin", fixture.begin, {request_id: shadowRequestId}, now), /^Error: SHADOW_RESPONSE_INVALID$/);}
  const atExpiry = shadowFixture(now);
  atExpiry.complete.run.completed_at = atExpiry.complete.run.lease_expires_at;
  assert.throws(() => shadowResult("complete", atExpiry.complete, fenced, now), /^Error: SHADOW_RESPONSE_INVALID$/);
  const sampleChanges: Array<(x: any) => void> = [
    x => {x.sample.summary.business_mutations = 1;}, x => {x.sample.summary.provider_sends = 1;},
    x => {x.sample.summary.alert_counts.ok = 13;}, x => {x.sample.summary.sms_queue.queued = 1;},
    x => {x.sample.system_health.metrics.sms_pending = -1;}, x => {x.sample.content_sha256 = "SECRET";},
    x => {x.sample.sms_queue.oldest_queued_at = "2026-09-30T17:00:00Z";}, x => {x.sample.message_body = "SECRET";},
  ];
  for (const change of sampleChanges) {const fixture = shadowFixture(now); change(fixture.sample); assert.throws(() => shadowResult("sample", fixture.sample, fenced, now), /^Error: SHADOW_RESPONSE_INVALID$/);}
});
test("projected freshness can expire in transit and an explicit false never becomes true", () => {
  const projected = shadowResult("sample", shadowFixture(now).sample, fenced, now);
  assert.ok("sample" in projected);
  assert.equal(projected.sample.sample_fresh, true);
  assert.equal(projectedShadowSample(projected, fenced, now + 60_000).sample.sample_fresh, false);
  projected.sample.sample_fresh = false;
  assert.equal(projectedShadowSample(projected, fenced, now).sample.sample_fresh, false);
});
test("assisted-SMS uncertainty or send-start elevates shadow summary independently of database alert counts", () => {
  for (const state of ["uncertain", "send_started"] as const) {
    const fixture = shadowFixture(now);
    fixture.sample.sample.sms_queue[state] = 1;
    fixture.sample.sample.summary.sms_queue[state] = 1;
    fixture.sample.sample.summary.health_status = "attention";
    const value = shadowResult("sample", fixture.sample, fenced, now);
    assert.ok("sample" in value);
    assert.equal(value.sample.summary.health_status, "attention");
    assert.equal(value.sample.summary.alert_counts.attention, 0);
  }
});
test("known revocation, expired/stale fence and SQL conflict responses are safe and never retried", async () => {
  const guards = [
    ["shadow_session_required", "42501", 403, "SHADOW_SESSION_REQUIRED"],
    ["shadow_permission_required", "42501", 403, "SHADOW_PERMISSION_REQUIRED"],
    ["shadow_request_conflict", "40001", 500, "SHADOW_REQUEST_CONFLICT"],
    ["shadow_fence_lost", "40001", 500, "SHADOW_FENCE_LOST"],
    ["shadow_lease_expired", "55000", 500, "SHADOW_LEASE_EXPIRED"],
    ["shadow_health_stale", "55000", 500, "SHADOW_HEALTH_STALE"],
    ["SECRET_SERIALIZATION_TEXT", "40001", 500, "SHADOW_RECONCILIATION_REQUIRED"],
    ["SECRET_DEADLOCK_TEXT", "40P01", 500, "SHADOW_RECONCILIATION_REQUIRED"],
  ] as const;
  for (const [message, code, status, expected] of guards) {
    let calls = 0;
    await assert.rejects(callShadowRpc("sample", fenced, environment, async () => {
      calls++; return Response.json({message, code, details: "SECRET +250788123456"}, {status});
    }, () => now), error => error instanceof Error && error.message === expected);
    assert.equal(calls, 1);
  }
});
test("timeout, redirect, malformed success and unknown transport failures preserve mutation uncertainty", async () => {
  for (const fetcher of [async () => Response.json({unexpected: true}), async () => new Response("SECRET_BODY", {status: 503}),
    async () => new Response(null, {status: 302}), async () => {throw new Error("SECRET_FETCH_ERROR");},
    async () => new Response("SECRET_OVERSIZED".repeat(256 * 1024)),
    async () => new Response(new ReadableStream({start(controller) {controller.enqueue(new TextEncoder().encode('{"secret":"'));}})),
    () => new Promise<Response>(() => {})]) {
    await assert.rejects(callShadowRpc("begin", {request_id: shadowRequestId}, environment, fetcher, () => now, 25), /^Error: SHADOW_OUTCOME_UNKNOWN$/);
  }
  await assert.rejects(callShadowRpc("get", {request_id: shadowRequestId}, environment, async () => {throw new Error("SECRET");}, () => now), /^Error: SHADOW_READ_UNAVAILABLE$/);
});
