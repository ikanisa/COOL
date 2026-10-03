import assert from "node:assert/strict";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {shadowStdio} from "./shadow_stdio.ts";
const serverPath = fileURLToPath(new URL("./testing/shadow_stdio_fixture.ts", import.meta.url));
test("manual shadow transport initializes actual newline stdio and closes its isolated process", async () => {
  const transport = shadowStdio({}, {serverPath});
  try {
    await assert.rejects(transport.call("fixture", {}), /^Error: SHADOW_MCP_NOT_INITIALIZED$/);
    await transport.initialize();
    const reply = await transport.call("fixture", {});
    assert.deepEqual(reply.result, {content: [{type: "text", text: "fixture"}], structuredContent: {result: {fixture: true}}});
    await assert.rejects(transport.initialize(), /^Error: SHADOW_MCP_RESPONSE_INVALID$/);
  } finally {await transport.close();}
});
test("malformed, oversized, foreign and terminated stdio replies never expose raw diagnostics", async () => {
  for (const mode of ["malformed", "oversized", "wrong-server", "exit"]) {
    const transport = shadowStdio({SHADOW_TEST_MODE: mode}, {serverPath});
    try {await assert.rejects(transport.initialize(), /^Error: SHADOW_MCP_(?:RESPONSE_INVALID|PROCESS_CLOSED)$/);}
    finally {await transport.close();}
  }
});
test("request and whole-run stdio deadlines close safely without replay", async () => {
  for (const options of [{totalTimeoutMs: 500, requestTimeoutMs: 150}, {totalTimeoutMs: 150, requestTimeoutMs: 500}]) {
    const transport = shadowStdio({SHADOW_TEST_MODE: "hang"}, {serverPath, ...options});
    try {await assert.rejects(transport.initialize(), /^Error: SHADOW_(?:REQUEST_DEADLINE|TOTAL_DEADLINE)$/);}
    finally {await transport.close();}
  }
});
