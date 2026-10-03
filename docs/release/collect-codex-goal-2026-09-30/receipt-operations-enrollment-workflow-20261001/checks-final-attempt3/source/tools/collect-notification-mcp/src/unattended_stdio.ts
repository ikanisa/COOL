import {spawn, type ChildProcessWithoutNullStreams} from "node:child_process";
import {fileURLToPath} from "node:url";

type Reply = Record<string, unknown>;
type Pending = {resolve: (value: Reply) => void; reject: (error: Error) => void; timer: NodeJS.Timeout};
export type UnattendedTransport = {
  initialize(): Promise<void>;
  call(name: string, args: Record<string, unknown>): Promise<Reply>;
  close(): Promise<void>;
};

// Production callers use fixed defaults. Injection is for isolated process
// fixtures, never user-supplied executable/URL/deadline CLI arguments.
export function unattendedStdio(
  profilePath: string,
  options: {serverPath?: string; totalTimeoutMs?: number; requestTimeoutMs?: number} = {},
): UnattendedTransport {
  if (typeof profilePath !== "string" || !profilePath.startsWith("/")) throw new Error("UNATTENDED_ARGUMENTS_INVALID");
  const totalTimeoutMs = options.totalTimeoutMs ?? 60_000, requestTimeoutMs = options.requestTimeoutMs ?? 15_000;
  if (!Number.isSafeInteger(totalTimeoutMs) || totalTimeoutMs < 1 || totalTimeoutMs > 60_000 ||
      !Number.isSafeInteger(requestTimeoutMs) || requestTimeoutMs < 1 || requestTimeoutMs > 15_000) throw new Error("UNATTENDED_ARGUMENTS_INVALID");
  const child: ChildProcessWithoutNullStreams = spawn(process.execPath, ["--experimental-strip-types",
    options.serverPath ?? fileURLToPath(new URL("./unattended_server.ts", import.meta.url))], {env: {PATH: "/usr/bin:/bin", LANG: "C", COLLECT_UNATTENDED_PROFILE: profilePath}, stdio: ["pipe", "pipe", "pipe"]});
  const pending = new Map<number, Pending>();
  let nextId = 0, ready = false, failure: Error | undefined, closing = false, buffer = Buffer.alloc(0);
  const maximum = 256 * 1024;
  const exited = new Promise<void>(resolve => child.once("close", () => resolve()));
  const fail = (code: string) => {
    if (!failure) failure = new Error(code);
    for (const [id, waiter] of pending) {clearTimeout(waiter.timer); pending.delete(id); waiter.reject(failure);}
  };
  const totalTimer = setTimeout(() => {fail("UNATTENDED_TOTAL_DEADLINE"); child.kill("SIGTERM");}, totalTimeoutMs);
  child.stderr.resume(); // Never capture or forward server/Keychain diagnostics.
  child.on("error", () => fail("UNATTENDED_MCP_PROCESS_FAILURE"));
  child.on("close", () => {clearTimeout(totalTimer); if (!closing) fail("UNATTENDED_MCP_PROCESS_CLOSED");});
  child.stdin.on("error", () => fail("UNATTENDED_MCP_PROCESS_FAILURE"));
  child.stdout.on("data", (chunk: Buffer) => {
    if (failure || closing) return;
    // Bound before concatenation even when one hostile chunk is very large.
    if (buffer.byteLength + chunk.byteLength > maximum) {fail("UNATTENDED_MCP_RESPONSE_INVALID"); child.kill("SIGTERM"); return;}
    buffer = Buffer.concat([buffer, chunk]);
    for (;;) {
      const newline = buffer.indexOf(10);
      if (newline === -1) break;
      const line = buffer.subarray(0, newline); buffer = buffer.subarray(newline + 1);
      try {
        const raw: unknown = JSON.parse(line.toString("utf8"));
        if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error();
        const reply = raw as Reply;
        if (reply.jsonrpc !== "2.0") throw new Error();
        // Server notifications are ignored, never rendered or interpreted.
        if (!Object.hasOwn(reply, "id") && typeof reply.method === "string") continue;
        if (!Number.isSafeInteger(reply.id) || Object.hasOwn(reply, "result") === Object.hasOwn(reply, "error")) throw new Error();
        const waiter = pending.get(Number(reply.id));
        if (!waiter) throw new Error();
        clearTimeout(waiter.timer); pending.delete(Number(reply.id)); waiter.resolve(reply);
      } catch {fail("UNATTENDED_MCP_RESPONSE_INVALID"); child.kill("SIGTERM"); break;}
    }
  });
  const request = (method: string, params: Record<string, unknown>): Promise<Reply> => {
    if (failure || closing) return Promise.reject(failure ?? new Error("UNATTENDED_MCP_PROCESS_CLOSED"));
    const id = ++nextId;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(id); reject(new Error("UNATTENDED_REQUEST_DEADLINE"));
        fail("UNATTENDED_REQUEST_DEADLINE"); child.kill("SIGTERM");
      }, requestTimeoutMs);
      pending.set(id, {resolve, reject, timer});
      child.stdin.write(JSON.stringify({jsonrpc: "2.0", id, method, params}) + "\n");
    });
  };
  return {
    initialize: async () => {
      if (ready) throw new Error("UNATTENDED_MCP_RESPONSE_INVALID");
      const reply = await request("initialize", {protocolVersion: "2025-11-25", capabilities: {},
        clientInfo: {name: "collect-unattended-operations", version: "1"}});
      const result = reply.result as Record<string, unknown> | undefined;
      const server = result?.serverInfo as Record<string, unknown> | undefined;
      const capabilities = result?.capabilities as Record<string, unknown> | undefined;
      if (reply.error || result?.protocolVersion !== "2025-11-25" || server?.name !== "collect-unattended-operations" || !capabilities?.tools) {
        fail("UNATTENDED_MCP_RESPONSE_INVALID"); throw failure;
      }
      child.stdin.write(JSON.stringify({jsonrpc: "2.0", method: "notifications/initialized"}) + "\n");
      ready = true;
    },
    call: async (name, args) => {
      if (!ready) throw new Error("UNATTENDED_MCP_NOT_INITIALIZED");
      return request("tools/call", {name, arguments: args});
    },
    close: async () => {
      if (closing) return exited;
      closing = true; clearTimeout(totalTimer);
      fail("UNATTENDED_MCP_PROCESS_CLOSED");
      child.stdin.end();
      const terminate = setTimeout(() => child.kill("SIGTERM"), 100);
      const kill = setTimeout(() => child.kill("SIGKILL"), 1000);
      try {await exited;} finally {clearTimeout(terminate); clearTimeout(kill); child.stdout.removeAllListeners("data");}
    },
  };
}
