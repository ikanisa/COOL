import {createInterface} from "node:readline";
const lines = createInterface({input: process.stdin});
const reply = (id: number, result: unknown) => process.stdout.write(JSON.stringify({jsonrpc: "2.0", id, result}) + "\n");
lines.on("line", line => {
  const request = JSON.parse(line);
  if (request.method === "notifications/initialized") return;
  const mode = process.env.SHADOW_TEST_MODE;
  if (mode === "hang") return;
  if (mode === "malformed") {process.stdout.write("SECRET_INVALID_FRAME\n"); return;}
  if (mode === "oversized") {process.stdout.write("s".repeat(300 * 1024)); return;}
  if (mode === "exit") {process.exit(3);}
  if (mode === "wrong-server") {reply(request.id, {protocolVersion: "2025-11-25", serverInfo: {name: "unexpected"}, capabilities: {tools: {}}}); return;}
  process.stderr.write("SECRET_IGNORED_STDERR\n");
  if (request.method === "initialize") reply(request.id, {protocolVersion: "2025-11-25", serverInfo: {name: "collect-notification-operator"}, capabilities: {tools: {}}});
  else reply(request.id, {content: [{type: "text", text: "fixture"}], structuredContent: {result: {fixture: true}}});
});
