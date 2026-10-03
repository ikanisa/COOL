import test from "node:test";
import assert from "node:assert/strict";
import {spawn} from "node:child_process";
import {createInterface} from "node:readline";
import {fileURLToPath} from "node:url";
import {unattendedStdio} from "./unattended_stdio.ts";
async function server() {
  const child = spawn(process.execPath, ["--experimental-strip-types", fileURLToPath(new URL("./unattended_server.ts", import.meta.url))],
    {env: {PATH: "/usr/bin:/bin", LANG: "C"}, stdio: ["pipe", "pipe", "pipe"]});
  child.stderr.resume(); const closed = new Promise<void>(resolve => child.once("close", () => resolve()));
  const pending = new Map<number, {resolve: (value: Record<string, any>) => void; reject: (error: Error) => void; timer: NodeJS.Timeout}>(); let id = 0;
  const lines = createInterface({input: child.stdout});
  lines.on("line", line => {try {const value = JSON.parse(line); const waiter = pending.get(value.id); if (waiter) {clearTimeout(waiter.timer); pending.delete(value.id); waiter.resolve(value);}} catch {assert.fail("Invalid stdio JSON");}});
  return {child, request: (method: string, params: Record<string, unknown>) => new Promise<Record<string, any>>((resolve, reject) => {
    const requestId = ++id, timer = setTimeout(() => {pending.delete(requestId); reject(Error("Test response deadline"));}, 5000);
    pending.set(requestId, {resolve, reject, timer}); child.stdin.write(JSON.stringify({jsonrpc: "2.0", id: requestId, method, params}) + "\n");
  }), close: async () => {child.stdin.end(); const kill = setTimeout(() => child.kill("SIGKILL"), 1000); try {await closed;} finally {clearTimeout(kill); lines.close(); for (const item of pending.values()) {clearTimeout(item.timer); item.reject(Error("Closed"));}}}};
}
async function initialized() {
  const s = await server(); const reply = await s.request("initialize", {protocolVersion: "2025-11-25", capabilities: {}, clientInfo: {name: "unattended-qa", version: "2"}});
  assert.equal(reply.result.serverInfo.name, "collect-unattended-operations"); assert.equal(reply.result.protocolVersion, "2025-11-25");
  s.child.stdin.write(JSON.stringify({jsonrpc: "2.0", method: "notifications/initialized"}) + "\n"); return s;
}
test("separate real stdio handshake and eight tools discover with no profile/credential", async () => {
  const s = await initialized(); try {
    const listed = await s.request("tools/list", {}), tools = listed.result.tools as Record<string, any>[];
    assert.equal(tools.length, 8);
    assert.deepEqual(tools.map(t => t.name).sort(), ["prove_key", "begin_run", "list_events", "ensure_receipt", "reconcile_backlog", "complete_run", "reconcile_request", "status"].map(a => `collect_unattended_${a}`).sort());
    assert.equal(tools.some(t => /send|dispatch|claim|heartbeat/.test(t.name)), false);
    for (const tool of tools) {assert.equal(tool.inputSchema.additionalProperties, false); assert.equal(tool.annotations.destructiveHint, false); assert.equal(tool.annotations.idempotentHint, true);}
    assert.equal(tools.find(t => t.name.endsWith("ensure_receipt"))?.annotations.readOnlyHint, false);
    assert.equal(tools.find(t => t.name.endsWith("status"))?.annotations.openWorldHint, false);
  } finally {await s.close();}
});
test("invalid scoped input and unknown send tool fail without profile or HTTP", async () => {
  const s = await initialized(); try {
    const bad = await s.request("tools/call", {name: "collect_unattended_ensure_receipt", arguments: {request_id: "invalid", body: "private"}});
    assert.ok(bad.error || bad.result?.isError);
    const unknown = await s.request("tools/call", {name: "collect_unattended_send", arguments: {}}); assert.ok(unknown.error || unknown.result?.isError);
    const absent = await s.request("tools/call", {name: "collect_unattended_begin_run", arguments: {request_id: "99800000-0000-4000-8000-000000000001"}});
    assert.equal(absent.result.isError, true); assert.equal(absent.result.content[0].text, "UNATTENDED_ACTION_UNAVAILABLE");
  } finally {await s.close();}
});
test("dedicated production transport initializes a separate server and refuses missing profile safely", async () => {
  const transport = unattendedStdio("/nonexistent-public-profile", {totalTimeoutMs: 10000, requestTimeoutMs: 5000});
  try {
    await transport.initialize(); const reply = await transport.call("collect_unattended_begin_run", {request_id: "99800000-0000-4000-8000-000000000001"});
    assert.equal((reply.result as any).isError, true); assert.equal((reply.result as any).content[0].text, "UNATTENDED_ACTION_UNAVAILABLE");
  } finally {await transport.close();}
});
test("dedicated transport rejects unsafe limits before starting a process", () => {
  assert.throws(() => unattendedStdio("relative"), /UNATTENDED_ARGUMENTS_INVALID/);
  assert.throws(() => unattendedStdio("/p", {totalTimeoutMs: 60001}), /UNATTENDED_ARGUMENTS_INVALID/);
  assert.throws(() => unattendedStdio("/p", {requestTimeoutMs: 15001}), /UNATTENDED_ARGUMENTS_INVALID/);
});
