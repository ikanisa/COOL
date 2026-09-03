import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import test from "node:test";
import { fileURLToPath } from "node:url";

test("real stdio server exposes exactly nine tools and fails closed without credentials", { timeout: 15_000 }, async (t) => {
  const child = spawn(process.execPath, ["--experimental-strip-types", fileURLToPath(new URL("./server.ts", import.meta.url))], {
    env: {}, stdio: ["pipe", "pipe", "pipe"],
  });
  t.after(() => child.kill());
  child.stderr.resume();
  const lines = createInterface({ input: child.stdout });
  t.after(() => lines.close());
  const pending = new Map<number, (value: any) => void>();
  lines.on("line", line => {
    const value = JSON.parse(line);
    if (typeof value.id === "number") pending.get(value.id)?.(value);
  });
  let id = 0;
  const request = (method: string, params: Record<string, unknown>) => new Promise<any>((resolve, reject) => {
    const requestId = ++id;
    const timer = setTimeout(() => { pending.delete(requestId); reject(new Error("MCP response timeout")); }, 5_000);
    pending.set(requestId, value => { clearTimeout(timer); pending.delete(requestId); resolve(value); });
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: requestId, method, params }) + "\n");
  });
  const initialized = await request("initialize", {
    protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "collect-local-uat", version: "1" },
  });
  assert.equal(initialized.result.serverInfo.name, "collect-notification-operator");
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");
  const listed = await request("tools/list", {});
  assert.deepEqual(listed.result.tools.map((tool: { name: string }) => tool.name).sort(), [
    "collect_notification_health", "collect_list_pending_receipts", "collect_claim_receipt",
    "collect_get_claimed_receipt", "collect_confirm_receipt", "collect_record_send_start",
    "collect_record_observed_outcome", "collect_release_unsent_claim", "collect_worker_heartbeat",
  ].sort());
  const health = await request("tools/call", { name: "collect_notification_health", arguments: {} });
  assert.equal(health.result.isError, true);
  assert.match(JSON.stringify(health.result.content), /Missing required environment variable/);
});
