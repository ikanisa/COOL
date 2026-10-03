import assert from "node:assert/strict";
import test from "node:test";
import {healthyQueue, operatorFixture, runStdioPreflight, startMcp} from "./testing/stdio_harness.ts";
import {failureSample, fixtureNotificationId, operationalEnvironment, operationalSample, statusSample} from "./testing/operational_fixture.ts";

const names = ["get_collect_health", "get_notification_status", "list_notification_failures"];
test("actual MCP initialize/catalog/read calls use fixed public RPCs and redact sensitive rows", {timeout: 15_000}, async () => {
  const fixture = await operatorFixture((record, response) => {
    const result = record.path.endsWith("admin_system_health") ? operationalSample() :
      record.path.endsWith("admin_get_hybrid_sms_receipt") ? statusSample() : failureSample("uncertain");
    response.end(JSON.stringify(result));
  });
  const mcp = startMcp(operationalEnvironment(fixture.origin));
  try {
    await mcp.initialize();
    assert.deepEqual((await mcp.request("ping", {})).result, {});
    const catalog = await mcp.request("tools/list", {});
    for (const name of names) {
      const tool = catalog.result.tools.find((entry: {name: string}) => entry.name === name);
      assert.deepEqual(tool.annotations, {readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true});
      assert.equal(tool.inputSchema.additionalProperties, false);
    }
    assert.equal(fixture.requests.length, 0);
    const calls = [
      {name: names[0], arguments: {}, path: "admin_system_health", body: {p_id: "system"}},
      {name: names[1], arguments: {notification_id: fixtureNotificationId}, path: "admin_get_hybrid_sms_receipt", body: {p_id: fixtureNotificationId}},
      {name: names[2], arguments: {status: "uncertain", limit: 1, offset: 0}, path: "admin_list_hybrid_sms_receipts",
        body: {p_search: null, p_status: "uncertain", p_limit: 1, p_offset: 0, p_sort: "created_at_desc"}},
    ];
    for (const call of calls) {
      const result = await mcp.request("tools/call", {name: call.name, arguments: call.arguments});
      assert.equal(result.error, undefined);
      assert.notEqual(result.result.isError, true);
      assert.deepEqual(JSON.parse(result.result.content[0].text), result.result.structuredContent.result);
      assert.doesNotMatch(JSON.stringify(result), /Sensitive Member|999999999|SECRET|250788|Ignore previous|amount_rwf|member_balance|message_body|destination_masked/);
      assert.equal(fixture.requests.at(-1)?.path, `/rest/v1/rpc/${call.path}`);
      assert.deepEqual(fixture.requests.at(-1)?.body, call.body);
      assert.equal(fixture.requests.at(-1)?.method, "POST");
    }
    assert.deepEqual(mcp.protocolErrors, []);
    assert.doesNotMatch(mcp.stderr(), /synthetic_signature|sb_publishable|SECRET/);
  } finally {await mcp.close(); await fixture.close();}
});
test("operational tool schemas reject overrides, recipients, write statuses and invalid paging before HTTP", {timeout: 15_000}, async () => {
  const fixture = await operatorFixture((_record, response) => response.end("{}"));
  const mcp = startMcp(operationalEnvironment(fixture.origin));
  try {
    await mcp.initialize();
    for (const input of [
      {name: "get_collect_health", arguments: {p_id: "tenant"}},
      {name: "get_collect_health", arguments: {sql: "select 1"}},
      {name: "get_notification_status", arguments: {notification_id: "not-a-uuid"}},
      {name: "get_notification_status", arguments: {notification_id: fixtureNotificationId, recipient: "+250788123456"}},
      {name: "list_notification_failures", arguments: {status: "queued"}},
      {name: "list_notification_failures", arguments: {limit: 26}},
      {name: "list_notification_failures", arguments: {offset: 10001}},
      {name: "list_notification_failures", arguments: {action: "claim"}},
    ]) {
      const result = await mcp.request("tools/call", input);
      assert.ok(result.error || result.result?.isError);
    }
    assert.equal(fixture.requests.length, 0);
  } finally {await mcp.close(); await fixture.close();}
});
test("live-shaped transport preserves stale health as unknown and hides denied backend errors", {timeout: 15_000}, async () => {
  let mode = "stale";
  const fixture = await operatorFixture((_record, response) => {
    if (mode === "denied") response.writeHead(403).end(JSON.stringify({error: "SECRET_BACKEND_DIAGNOSTIC +250788123456"}));
    else response.end(JSON.stringify(mode === "malformed" ? {health_status: "ok"} : operationalSample(Date.now() - 120_000)));
  });
  const mcp = startMcp(operationalEnvironment(fixture.origin));
  try {
    await mcp.initialize();
    const stale = await mcp.request("tools/call", {name: "get_collect_health", arguments: {}});
    assert.equal(stale.result.structuredContent.result.health_status, "unknown");
    assert.equal(stale.result.structuredContent.result.sample_fresh, false);
    assert.ok(Object.values(stale.result.structuredContent.result.metrics).every(value=>value===null));
    mode = "denied";
    const denied = await mcp.request("tools/call", {name: "get_collect_health", arguments: {}});
    assert.equal(denied.result.isError, true);
    assert.match(JSON.stringify(denied), /COLLECT_AUTHORIZATION_REQUIRED/);
    assert.doesNotMatch(JSON.stringify(denied), /SECRET|250788/);
    mode = "malformed";
    const invalid = await mcp.request("tools/call", {name: "get_collect_health", arguments: {}});
    assert.equal(invalid.result.isError, true);
    assert.match(JSON.stringify(invalid), /COLLECT_RESPONSE_INVALID/);
    assert.equal(fixture.requests.length, 3);
  } finally {await mcp.close(); await fixture.close();}
});
test("operational RPC redirects cannot forward current-user authorization", {timeout: 15_000}, async () => {
  const target = await operatorFixture((_record, response) => response.end(JSON.stringify(operationalSample())));
  const fixture = await operatorFixture((_record, response) => response.writeHead(302, {location: target.origin}).end());
  const mcp = startMcp(operationalEnvironment(fixture.origin));
  try {
    await mcp.initialize();
    const result = await mcp.request("tools/call", {name: "get_collect_health", arguments: {}});
    assert.equal(result.result.isError, true);
    assert.equal(target.requests.length, 0);
    assert.equal(fixture.requests.length, 1);
    assert.doesNotMatch(JSON.stringify(result), /synthetic_signature|sb_publishable/);
  } finally {await mcp.close(); await fixture.close(); await target.close();}
});
test("actual stdio health RPC has a bounded 15-second deadline and no replay", {timeout: 22_000}, async () => {
  const fixture = await operatorFixture((_record, response) => {
    response.writeHead(200, {"content-type": "application/json"});
    response.write('{"id":"system",'); // Headers arrive, body deliberately stalls.
  });
  const mcp = startMcp(operationalEnvironment(fixture.origin));
  try {
    await mcp.initialize();
    const result = await mcp.request("tools/call", {name: "get_collect_health", arguments: {}}, 19_000);
    assert.equal(result.result.isError, true);
    assert.match(JSON.stringify(result), /COLLECT_REQUEST_TIMEOUT/);
    assert.equal(fixture.requests.length, 1);
  } finally {await mcp.close(); await fixture.close();}
});
test("optional operations stdio preflight prints only validated aggregates", {timeout: 15_000}, async () => {
  const fixture=await operatorFixture((record,response)=>{
    const result=record.path.endsWith("admin_system_health")?operationalSample():
      record.path.endsWith("admin_get_hybrid_sms_receipt")?statusSample():
      record.path.endsWith("admin_list_hybrid_sms_receipts")?failureSample():
      {ok:true,result:record.body.action==="health"?healthyQueue:[]};
    response.end(JSON.stringify(result));
  });
  try{
    const result=await runStdioPreflight(operationalEnvironment(fixture.origin),["--operations"]);
    assert.equal(result.code,0);
    assert.equal(result.report.status,"PASS_AUTHENTICATED_STDIO_MCP");
    assert.equal(result.report.operational_health_status,"ok");
    assert.equal(result.report.operational_sample_fresh,true);
    assert.equal(result.report.notification_failure_page_count,1);
    assert.equal(result.report.notification_status_checked,true);
    assert.equal(result.report.queue_mutations,0);
    assert.equal(result.report.provider_sends,0);
    assert.deepEqual(result.report.tools_called,["collect_notification_health","collect_list_pending_receipts",...names.filter(name=>name!=="get_notification_status"),"get_notification_status"]);
    assert.equal(fixture.requests.length,5);
    assert.doesNotMatch(result.stdout+result.stderr,/11111111|SECRET|Sensitive Member|250788|synthetic_signature|sb_publishable/);
  }finally{await fixture.close();}
});
