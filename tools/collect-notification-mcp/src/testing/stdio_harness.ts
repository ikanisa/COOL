import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

export const healthyQueue = {
  enabled: false, queued: 1, awaiting_confirmation: 0, send_started: 0,
  uncertain: 0, suppressed: 0, active_workers: 0,
};

export type RequestRecord = {
  path: string; method: string | undefined; body: Record<string, unknown>;
  authorization: string | undefined; apikey: string | string[] | undefined;
};

// Real stdio and loopback HTTP, synthetic credentials/backend only. Never load
// the caller's environment, Keychain helper, linked project or provider client.
export async function operatorFixture(
  respond: (record: RequestRecord, response: ServerResponse) => void,
) {
  const requests: RequestRecord[] = [];
  const server = createServer(async (request: IncomingMessage, response) => {
    try {
      let body = "";
      for await (const chunk of request) body += chunk;
      const record: RequestRecord = {
        path: request.url ?? "", method: request.method,
        body: JSON.parse(body), authorization: request.headers.authorization,
        apikey: request.headers.apikey,
      };
      requests.push(record);
      response.setHeader("content-type", "application/json");
      respond(record, response);
    } catch {
      response.writeHead(500).end(JSON.stringify({error: "QA_FIXTURE_FAILURE"}));
    }
  });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  return {
    requests, origin: `http://127.0.0.1:${address.port}`,
    environment: {
      COLLECT_SUPABASE_URL: `http://127.0.0.1:${address.port}`,
      COLLECT_SUPABASE_ANON_KEY: "qa-public-anon-no-authority",
      COLLECT_OPERATOR_ACCESS_TOKEN: "qa-operator-no-authority",
    },
    close: async () => {
      server.closeAllConnections();
      await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      assert.equal(server.listening, false);
    },
  };
}

export function startMcp(environment: NodeJS.ProcessEnv) {
  const child = spawn(process.execPath, ["--experimental-strip-types", fileURLToPath(new URL("../server.ts", import.meta.url))], {
    env: environment, stdio: ["pipe", "pipe", "pipe"],
  });
  const closed = new Promise<void>(resolve => child.once("close", () => resolve()));
  const lines = createInterface({input: child.stdout});
  const pending = new Map<number, {resolve: (value: any) => void; reject: (error: Error) => void; timer: NodeJS.Timeout}>();
  let id = 0, stderr = "";
  const protocolErrors: string[] = [];
  child.stderr.on("data", chunk => { stderr += chunk; });
  lines.on("line", line => {
    try {
      const value = JSON.parse(line);
      const waiter = pending.get(value.id);
      if (waiter) { clearTimeout(waiter.timer); pending.delete(value.id); waiter.resolve(value); }
    } catch { protocolErrors.push("NON_JSON_STDOUT"); }
  });
  const rejectPending = () => {
    for (const waiter of pending.values()) { clearTimeout(waiter.timer); waiter.reject(new Error("MCP_CHILD_CLOSED")); }
    pending.clear();
  };
  child.on("error", rejectPending);
  child.on("close", rejectPending);
  child.stdin.on("error", rejectPending);
  const request = (method: string, params: Record<string, unknown>, timeout = 5000) => new Promise<any>((resolve, reject) => {
    const requestId = ++id;
    const timer = setTimeout(() => { pending.delete(requestId); reject(new Error("MCP_RESPONSE_TIMEOUT")); }, timeout);
    pending.set(requestId, {resolve, reject, timer});
    child.stdin.write(JSON.stringify({jsonrpc: "2.0", id: requestId, method, params}) + "\n");
  });
  return {
    request, protocolErrors, stderr: () => stderr,
    initialize: async () => {
      const result = await request("initialize", {protocolVersion: "2025-11-25", capabilities: {}, clientInfo: {name: "collect-synthetic-transport-qa", version: "1"}});
      assert.equal(result.result.serverInfo.name, "collect-notification-operator");
      child.stdin.write(JSON.stringify({jsonrpc: "2.0", method: "notifications/initialized"}) + "\n");
    },
    close: async () => {
      child.stdin.end();
      const terminate = setTimeout(() => child.kill("SIGTERM"), 1000);
      const kill = setTimeout(() => child.kill("SIGKILL"), 3000);
      try { await closed; }
      finally { clearTimeout(terminate); clearTimeout(kill); lines.close(); }
      assert.ok(child.exitCode !== null || child.signalCode !== null);
    },
  };
}

export async function runStdioPreflight(environment: NodeJS.ProcessEnv) {
  const child = spawn(process.execPath, ["--experimental-strip-types", fileURLToPath(new URL("../stdio_preflight.ts", import.meta.url))], {
    env: environment, stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "", stderr = "";
  const terminate = setTimeout(() => child.kill("SIGTERM"), 25_000);
  const kill = setTimeout(() => child.kill("SIGKILL"), 28_000);
  child.stdout.on("data", chunk => { stdout += chunk; });
  child.stderr.on("data", chunk => { stderr += chunk; });
  const code = await new Promise<number | null>((resolve, reject) => {
    child.on("error", reject); child.on("close", resolve);
  }).finally(() => { clearTimeout(terminate); clearTimeout(kill); });
  return {code, stdout, stderr, report: JSON.parse(stdout)};
}
