import assert from "node:assert/strict";
import test from "node:test";
import {operatorFixture, startMcp} from "./testing/stdio_harness.ts";

const job = "11111111-1111-4111-8111-111111111111";
const claim = "22222222-2222-4222-8222-222222222222";
const requestId = "33333333-3333-4333-8333-333333333333";
const fenced = {job_id: job, claim_token: claim, fence_version: 7};
const tools = [
  {name: "collect_notification_health", action: "health", input: {}},
  {name: "collect_list_pending_receipts", action: "list_pending", input: {limit: 5, after_created_at: "2026-09-15T00:00:00Z"}},
  {name: "collect_claim_receipt", action: "claim", input: {job_id: job, worker_id: "qa-worker", request_id: requestId}},
  {name: "collect_get_claimed_receipt", action: "get_claimed", input: fenced},
  {name: "collect_confirm_receipt", action: "confirm", input: {...fenced, destination_revision: 3, body_sha256: "a".repeat(64), confirmation_id: requestId, user_confirmation: true}},
  {name: "collect_record_send_start", action: "record_send_start", input: {...fenced, confirmation_id: requestId}},
  {name: "collect_record_observed_outcome", action: "record_outcome", input: {attempt_id: requestId, outcome: "uncertain", evidence_reference: "qa://synthetic-observation"}},
  {name: "collect_release_unsent_claim", action: "release_claim", input: {...fenced, reason: "Synthetic user cancelled"}},
  {name: "collect_worker_heartbeat", action: "heartbeat", input: {worker_id: "qa-worker", run_id: requestId, mode: "no_send", queue_checked: true}},
];

test("all nine tools preserve command and fencing fields over real stdio and HTTP", {timeout: 20_000}, async () => {
  const fixture = await operatorFixture((record, response) => response.end(JSON.stringify({ok: true, result: {fixture_action: record.body.action}})));
  const mcp = startMcp(fixture.environment);
  try {
    await mcp.initialize();
    const catalog = await mcp.request("tools/list", {});
    assert.deepEqual(catalog.result.tools.map((x: {name: string}) => x.name).sort(),
      [...tools.map(x => x.name), "get_collect_health", "get_notification_status", "list_notification_failures",
        "begin_supervisor_run", "sample_supervisor_run", "complete_supervisor_run", "get_supervisor_run"].sort());
    assert.equal(fixture.requests.length, 0);
    for (const item of tools) {
      const result = await mcp.request("tools/call", {name: item.name, arguments: item.input});
      assert.equal(result.error, undefined);
      assert.notEqual(result.result.isError, true);
      assert.deepEqual(result.result.structuredContent, {result: {fixture_action: item.action}});
      assert.deepEqual(JSON.parse(result.result.content[0].text), {fixture_action: item.action});
      assert.deepEqual(fixture.requests.at(-1)?.body, {...item.input, action: item.action});
    }
    const defaultPage = await mcp.request("tools/call", {name: "collect_list_pending_receipts", arguments: {action: "record_send_start"}});
    assert.notEqual(defaultPage.result.isError, true);
    assert.deepEqual(fixture.requests.at(-1)?.body, {limit: 20, action: "list_pending"});
    assert.equal(fixture.requests.length, 10);
    for (const request of fixture.requests) {
      assert.equal(request.path, "/functions/v1/collect-notification-operator");
      assert.equal(request.method, "POST");
      assert.equal(request.authorization, "Bearer qa-operator-no-authority");
      assert.equal(request.apikey, "qa-public-anon-no-authority");
    }
    assert.deepEqual(mcp.protocolErrors, []);
    assert.doesNotMatch(mcp.stderr(), /qa-operator-no-authority|qa-public-anon-no-authority/);
  } finally { await mcp.close(); await fixture.close(); }
});

test("invalid tool names, unconfirmed receipts and invalid fencing never reach HTTP", {timeout: 15_000}, async () => {
  const fixture = await operatorFixture((_request, response) => response.end(JSON.stringify({ok: true, result: {}})));
  const mcp = startMcp(fixture.environment);
  try {
    await mcp.initialize();
    const invalid = [
      {name: "execute_sql", arguments: {}},
      {name: "collect_claim_receipt", arguments: {job_id: "not-a-uuid", worker_id: "qa-worker", request_id: requestId}},
      {name: "collect_get_claimed_receipt", arguments: {...fenced, fence_version: 0}},
      {name: "collect_confirm_receipt", arguments: {...tools[4]!.input, user_confirmation: false}},
      {name: "collect_confirm_receipt", arguments: {...tools[4]!.input, body_sha256: "not-a-hash"}},
      {name: "collect_list_pending_receipts", arguments: {limit: 51}},
      {name: "collect_record_observed_outcome", arguments: {attempt_id: requestId, outcome: "delivered", evidence_reference: "qa://synthetic-observation"}},
      {name: "collect_worker_heartbeat", arguments: {worker_id: "qa-worker", run_id: requestId, mode: "automatic_send", queue_checked: true}},
    ];
    for (const input of invalid) {
      const result = await mcp.request("tools/call", input);
      assert.ok(result.error || result.result?.isError === true, input.name);
    }
    assert.equal(fixture.requests.length, 0);
  } finally { await mcp.close(); await fixture.close(); }
});

test("real transport refuses redirects and preserves backend failure without retry", {timeout: 15_000}, async () => {
  let status = 403;
  const redirect = await operatorFixture((_request, response) => response.end(JSON.stringify({ok: true, result: {unexpected: true}})));
  const fixture = await operatorFixture((_request, response) => {
    if (status === 302) response.setHeader("location", redirect.origin);
    response.writeHead(status).end(status === 200 ? "invalid-json" : JSON.stringify({error: "Synthetic permission or fence denial"}));
  });
  const mcp = startMcp(fixture.environment);
  try {
    await mcp.initialize();
    for (const code of [401, 403, 409, 503, 302, 200]) {
      status = code;
      const before = fixture.requests.length;
      const result = await mcp.request("tools/call", {name: "collect_record_send_start", arguments: tools[5]!.input});
      assert.equal(result.result.isError, true);
      assert.equal(fixture.requests.length, before + 1);
    }
    assert.equal(redirect.requests.length, 0);
    assert.deepEqual(mcp.protocolErrors, []);
  } finally { await mcp.close(); await fixture.close(); await redirect.close(); }
});

test("a slow mutating command times out once without replaying the HTTP request", {timeout: 22_000}, async () => {
  const fixture = await operatorFixture(() => { /* Intentionally leave the one response pending. */ });
  const mcp = startMcp(fixture.environment);
  try {
    await mcp.initialize();
    const result = await mcp.request("tools/call", {name: "collect_record_send_start", arguments: tools[5]!.input}, 19_000);
    assert.equal(result.result.isError, true);
    assert.equal(fixture.requests.length, 1);
    assert.equal(fixture.requests[0]?.body.action, "record_send_start");
  } finally { await mcp.close(); await fixture.close(); }
});
