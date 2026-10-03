import assert from "node:assert/strict";
import test from "node:test";
import {spawn} from "node:child_process";
import {fileURLToPath} from "node:url";
import {runShadowSupervisor} from "./shadow_supervisor.ts";
import {shadowStdio} from "./shadow_stdio.ts";
import {shadowResult} from "./shadow_contract.ts";
import {operationalEnvironment} from "./testing/operational_fixture.ts";
import {operatorFixture, startMcp} from "./testing/stdio_harness.ts";
import {shadowFixture, shadowRequestId, shadowRunId} from "./testing/shadow_fixture.ts";

const argv = ["--once", "--request-id", shadowRequestId];
const fenced = {run_id: shadowRunId, fence_version: 1};
function toolReply(value: unknown) {return {result: {structuredContent: {result: value}, content: [{type: "text", text: JSON.stringify(value)}]}};}
function mockTransport(respond: (name: string, args: Record<string, unknown>) => unknown) {
  const calls: Array<{name: string; args: Record<string, unknown>}> = [];
  let closed = false;
  return {calls, factory: () => ({initialize: async () => {}, call: async (name: string, args: Record<string, unknown>) => {
    calls.push({name, args}); return respond(name, args) as Record<string, unknown>;
  }, close: async () => {closed = true;}}), closed: () => closed};
}
test("bad manual CLI inputs perform no process, auth or telemetry work", async () => {
  let processes = 0;
  const report = await runShadowSupervisor(["--once", "--request-id", shadowRequestId, "--recipient", "SECRET"], () => {
    processes++; throw new Error("MUST_NOT_START");
  });
  assert.equal(report.status, "SHADOW_ARGUMENTS_INVALID");
  assert.equal(processes, 0);
  assert.doesNotMatch(JSON.stringify(report), /SECRET|recipient/);
});
test("manual CLI makes exactly three sequential telemetry calls with retained identity and safe aggregates", async () => {
  const fixture = shadowFixture();
  const transport = mockTransport(name => toolReply(name === "begin_supervisor_run" ? fixture.begin : name === "sample_supervisor_run" ?
    shadowResult("sample", fixture.sample, fenced) : fixture.complete));
  const report = await runShadowSupervisor(argv, transport.factory);
  assert.equal(report.status, "SHADOW_COMPLETED");
  assert.equal(report.request_id, shadowRequestId);
  assert.equal(report.checks_recorded, 13);
  assert.equal(report.samples_recorded, 1);
  assert.equal(report.business_mutations, 0);
  assert.equal(report.provider_sends, 0);
  assert.deepEqual(transport.calls, [{name: "begin_supervisor_run", args: {request_id: shadowRequestId}},
    {name: "sample_supervisor_run", args: fenced}, {name: "complete_supervisor_run", args: fenced}]);
  assert.equal(transport.closed(), true);
});
test("BUSY and terminal request replay never sample, complete or restart", async () => {
  for (const state of ["busy", "completed", "expired"]) {
    const fixture = shadowFixture();
    const raw = state === "busy" ? fixture.busy : {...fixture.begin, replayed: true, outcome: "replayed",
      run: state === "completed" ? fixture.complete.run : {...fixture.begin.run, status: "expired"}};
    const transport = mockTransport(() => toolReply(raw));
    const report = await runShadowSupervisor(argv, transport.factory);
    assert.equal(report.status, state === "busy" ? "SHADOW_BUSY" : state === "completed" ? "SHADOW_ALREADY_COMPLETED" : "SHADOW_EXPIRED");
    assert.equal(transport.calls.length, 1);
  }
});
test("deadline, malformed success and stale/fenced refusals never retry or complete after uncertainty", async () => {
  for (const failure of ["SHADOW_REQUEST_DEADLINE", "SHADOW_FENCE_LOST", "SHADOW_LEASE_EXPIRED", "SHADOW_HEALTH_STALE", "SHADOW_PERMISSION_REQUIRED", "malformed", "false_fresh"]) {
    const fixture = shadowFixture();
    const transport = mockTransport(name => {
      if (name === "begin_supervisor_run") return toolReply(fixture.begin);
      if (failure === "SHADOW_REQUEST_DEADLINE") throw new Error(failure);
      if (failure === "malformed") return toolReply({ok: true, unexpected: "SECRET_RESPONSE"});
      if (failure === "false_fresh") {
        const projected = shadowResult("sample", fixture.sample, fenced);
        assert.ok("sample" in projected);
        projected.sample.sample_fresh = false;
        return toolReply(projected);
      }
      return {result: {isError: true, content: [{type: "text", text: failure}]}};
    });
    const report = await runShadowSupervisor(argv, transport.factory);
    assert.equal(report.status, failure === "SHADOW_REQUEST_DEADLINE" || failure === "malformed" ? "SHADOW_OUTCOME_UNKNOWN" :
      failure === "false_fresh" ? "SHADOW_HEALTH_STALE" : failure);
    assert.equal(report.request_id, shadowRequestId);
    assert.equal(report.run_id, shadowRunId);
    assert.equal(report.reconciliation_required, true);
    assert.equal(transport.calls.length, 2);
    assert.equal(transport.closed(), true);
    assert.doesNotMatch(JSON.stringify(report), /SECRET_RESPONSE/);
  }
});
test("malformed success at every lifecycle stage remains unknown with the supplied request retained", async () => {
  const phases = ["begin_supervisor_run", "sample_supervisor_run", "complete_supervisor_run"];
  for (const [index, phase] of phases.entries()) {
    const fixture = shadowFixture();
    const transport = mockTransport(name => toolReply(name === phase ? {ok: true, secret: "SECRET_SUCCESS"} :
      name === phases[0] ? fixture.begin : name === phases[1] ? shadowResult("sample", fixture.sample, fenced) : fixture.complete));
    const report = await runShadowSupervisor(argv, transport.factory);
    assert.equal(report.status, "SHADOW_OUTCOME_UNKNOWN");
    assert.equal(report.request_id, shadowRequestId);
    assert.equal(report.reconciliation_required, true);
    assert.equal(transport.calls.length, index + 1);
    assert.doesNotMatch(JSON.stringify(report), /SECRET_SUCCESS/);
  }
});
test("status mode reconciles one request by read only and does not acquire a lease", async () => {
  const fixture = shadowFixture(Date.now() - 3600_000);
  const transport = mockTransport(() => toolReply(fixture.get));
  const report = await runShadowSupervisor(["--status", "--request-id", shadowRequestId], transport.factory);
  assert.equal(report.status, "SHADOW_STATUS_FOUND");
  assert.equal(report.summary_evidence, "historical");
  assert.equal(Object.hasOwn(report, "sample_fresh"), false);
  assert.equal(report.recorded_health_status, "ok");
  assert.deepEqual(transport.calls, [{name: "get_supervisor_run", args: {request_id: shadowRequestId}}]);
});
test("actual SDK MCP lifecycle tools enforce annotations, strict inputs and three fixed RPC routes", {timeout: 20_000}, async () => {
  const fixture = shadowFixture();
  const backend = await operatorFixture((record, response) => {
    const result = record.path.includes("begin_collect") ? fixture.begin : record.path.includes("sample_collect") ? fixture.sample :
      record.path.includes("finish_collect") ? fixture.complete : fixture.get;
    response.end(JSON.stringify(result));
  });
  const env = operationalEnvironment(backend.origin);
  const catalog = startMcp(env);
  try {
    await catalog.initialize();
    const listed = await catalog.request("tools/list", {});
    for (const name of ["begin_supervisor_run", "sample_supervisor_run", "complete_supervisor_run", "get_supervisor_run"]) {
      const tool = listed.result.tools.find((row: {name: string}) => row.name === name);
      assert.deepEqual(tool.annotations, {readOnlyHint: name === "get_supervisor_run", destructiveHint: false, idempotentHint: true, openWorldHint: true});
      assert.equal(tool.inputSchema.additionalProperties, false);
    }
    for (const call of [{name: "begin_supervisor_run", arguments: {request_id: shadowRequestId, tenant: "other"}},
      {name: "sample_supervisor_run", arguments: {...fenced, checks_recorded: 13}},
      {name: "complete_supervisor_run", arguments: {...fenced, fence_version: 1_000_000_001}}]) {
      const response = await catalog.request("tools/call", call);
      assert.ok(response.error || response.result?.isError);
    }
    assert.equal(backend.requests.length, 0);
  } finally {await catalog.close();}
  try {
    const report = await runShadowSupervisor(argv, () => shadowStdio(env));
    assert.equal(report.status, "SHADOW_COMPLETED");
    assert.equal(backend.requests.length, 3);
    assert.deepEqual(backend.requests.map(row => row.path), ["begin", "sample", "finish"].map(action => `/rest/v1/rpc/${action}_collect_shadow_run_v1`));
    assert.doesNotMatch(JSON.stringify(report), /sb_publishable_|synthetic_signature|amount|body|destination|content_sha256/);
  } finally {await backend.close();}
});
test("actual CLI process rejects unsafe arguments and status reads expose no raw credentials", {timeout: 15_000}, async () => {
  const fixture = shadowFixture();
  const backend = await operatorFixture((record, response) => response.end(JSON.stringify(
    record.path.includes("begin_collect") ? fixture.begin : record.path.includes("sample_collect") ? fixture.sample :
      record.path.includes("finish_collect") ? fixture.complete : fixture.get)));
  async function run(args: string[], env: NodeJS.ProcessEnv) {
    const child = spawn(process.execPath, ["--experimental-strip-types", fileURLToPath(new URL("./shadow_supervisor.ts", import.meta.url)), ...args],
      {env, stdio: ["ignore", "pipe", "pipe"]});
    let output = "", stderr = "";
    child.stdout.on("data", data => {output += data;}); child.stderr.on("data", data => {stderr += data;});
    const timer = setTimeout(() => child.kill("SIGKILL"), 7000);
    const code = await new Promise(resolve => child.once("close", resolve)).finally(() => clearTimeout(timer));
    return {code, report: JSON.parse(output), stderr};
  }
  try {
    const invalid = await run([...argv, "--loop"], operationalEnvironment(backend.origin));
    assert.equal(invalid.code, 2);
    assert.equal(invalid.report.status, "SHADOW_ARGUMENTS_INVALID");
    assert.equal(backend.requests.length, 0);
    const status = await run(["--status", "--request-id", shadowRequestId], operationalEnvironment(backend.origin));
    assert.equal(status.code, 0);
    assert.equal(status.report.status, "SHADOW_STATUS_FOUND");
    assert.equal(backend.requests.length, 1);
    assert.equal(backend.requests[0]?.path, "/rest/v1/rpc/get_collect_shadow_run_v1");
    assert.doesNotMatch(JSON.stringify(status.report) + status.stderr, /synthetic_signature|sb_publishable_|amount_rwf|destination/);
    const once = await run(argv, operationalEnvironment(backend.origin));
    assert.equal(once.code, 0);
    assert.equal(once.report.status, "SHADOW_COMPLETED");
    assert.equal(backend.requests.length, 4);
    assert.deepEqual(backend.requests.slice(1).map(row => row.path), ["begin", "sample", "finish"].map(action => `/rest/v1/rpc/${action}_collect_shadow_run_v1`));
    assert.doesNotMatch(JSON.stringify(once.report) + once.stderr, /synthetic_signature|sb_publishable_|amount_rwf|destination|message_body/);
  } finally {await backend.close();}
});
test("actual MCP timeout after begin retains request identity without a replay or later mutation", {timeout: 15_000}, async () => {
  const backend = await operatorFixture((_record, _response) => {});
  try {
    const report = await runShadowSupervisor(argv, () => shadowStdio(operationalEnvironment(backend.origin), {requestTimeoutMs: 5000}));
    assert.equal(report.status, "SHADOW_OUTCOME_UNKNOWN");
    assert.equal(report.request_id, shadowRequestId);
    assert.equal(report.reconciliation_required, true);
    assert.equal(report.blocked_phase, "begin");
    assert.deepEqual(backend.requests.map(row => row.path), ["/rest/v1/rpc/begin_collect_shadow_run_v1"]);
  } finally {await backend.close();}
});
test("actual MCP authority refusal is safe and stops before sampling", {timeout: 15_000}, async () => {
  const backend = await operatorFixture((_record, response) => response.writeHead(403).end(JSON.stringify({code: "42501", message: "shadow_permission_required", details: "SECRET_DIAGNOSTIC +250788123456"})));
  try {
    const report = await runShadowSupervisor(argv, () => shadowStdio(operationalEnvironment(backend.origin)));
    assert.equal(report.status, "SHADOW_PERMISSION_REQUIRED");
    assert.equal(backend.requests.length, 1);
    assert.doesNotMatch(JSON.stringify(report), /SECRET|250788/);
  } finally {await backend.close();}
});
