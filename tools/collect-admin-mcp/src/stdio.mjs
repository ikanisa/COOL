import { once } from 'node:events';

const VERSIONS = ['2025-11-25', '2025-06-18', '2025-03-26'];
const MAX_FRAME = 64 * 1024, MAX_PENDING = 16;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

export function serveStdio({ tools, callTool, serverInfo, instructions, toolError, isInvalidArguments,
  cancellationError, priorityTool, pendingMessage = 'Too many pending reads.', onClose,
  stdin = process.stdin, stdout = process.stdout }) {
  let state = 'new', input = Buffer.alloc(0), discarding = false, queue = Promise.resolve(), pending = 0;
  let output = Promise.resolve(), priorityPending = 0, finishing = false;
  let finished;
  const closed = new Promise(resolve => { finished = resolve; });
  const active = new Map(), priorityTasks = new Set();
  function send(value) {
    output = output.then(async () => {
      if (!stdout.write(JSON.stringify(value) + '\n')) await once(stdout, 'drain');
    }).catch(() => { process.exitCode = 1; stdin.destroy(); });
    return output;
  }
  const rpcError = (id, code, message) => send({ jsonrpc: '2.0', id, error: { code, message } });
  function idValid(id) { return typeof id === 'string' && id.length > 0 && id.length <= 128 || Number.isSafeInteger(id); }
  function accept(message) {
    const request = object(message) && Object.hasOwn(message, 'id');
    if (!object(message) || message.jsonrpc !== '2.0' || typeof message.method !== 'string' ||
        message.params !== undefined && !object(message.params) || request && !idValid(message.id) ||
        Object.keys(message).some(key => !['jsonrpc', 'id', 'method', 'params'].includes(key))) {
      return rpcError(request && idValid(message.id) ? message.id : null, -32600, 'Invalid JSON-RPC request.');
    }
    if (!request) {
      if (message.method === 'notifications/initialized' && state === 'initializing') state = 'ready';
      if (message.method === 'notifications/cancelled' && idValid(message.params?.requestId)) active.get(message.params.requestId)?.abort();
      return;
    }
    if (message.method === 'initialize') {
      const value = message.params;
      if (state !== 'new' || !object(value) || typeof value.protocolVersion !== 'string' ||
          !object(value.capabilities) || !object(value.clientInfo) || typeof value.clientInfo.name !== 'string' ||
          typeof value.clientInfo.version !== 'string') return rpcError(message.id, -32602, 'Invalid initialization.');
      state = 'initializing';
      return send({ jsonrpc: '2.0', id: message.id, result: {
        protocolVersion: VERSIONS.includes(value.protocolVersion) ? value.protocolVersion : VERSIONS[0],
        capabilities: { tools: { listChanged: false } }, serverInfo, instructions,
      } });
    }
    if (message.method === 'ping') return send({ jsonrpc: '2.0', id: message.id, result: {} });
    if (state !== 'ready') return rpcError(message.id, -32002, 'Complete initialization before using tools.');
    if (message.method === 'tools/list') {
      const params = message.params;
      if (params && (Object.keys(params).some(key => key !== '_meta') ||
          params._meta !== undefined && !object(params._meta))) {
        return rpcError(message.id, -32602, 'Use optional request metadata without a cursor for this fixed tool catalogue.');
      }
      return send({ jsonrpc: '2.0', id: message.id, result: { tools } });
    }
    if (message.method !== 'tools/call') return rpcError(message.id, -32601, 'Method not found.');
    const params = message.params;
    if (!object(params) || typeof params.name !== 'string' || !tools.some(tool => tool.name === params.name) ||
        Object.keys(params).some(key => !['name', 'arguments', '_meta'].includes(key)) ||
        params.arguments !== undefined && !object(params.arguments) || params._meta !== undefined && !object(params._meta)) {
      return rpcError(message.id, -32602, 'Unknown tool or invalid tool call.');
    }
    if (active.has(message.id)) return rpcError(message.id, -32600, 'A request with this identifier is already pending.');
    const priority = params.name === priorityTool;
    if ((priority ? priorityPending : pending) >= MAX_PENDING) return rpcError(message.id, -32000, pendingMessage);
    const abort = new AbortController(); active.set(message.id, abort);
    if (priority) priorityPending++; else pending++;
    const execute = async () => {
      try {
        if (abort.signal.aborted) throw cancellationError();
        const value = await callTool(params.name, params.arguments ?? {}, abort.signal);
        await send({ jsonrpc: '2.0', id: message.id, result: { content: [{ type: 'text', text: JSON.stringify(value) }], structuredContent: value } });
      } catch (error) {
        if (isInvalidArguments(error)) await rpcError(message.id, -32602, error.message);
        else await send({ jsonrpc: '2.0', id: message.id, result: toolError(error) });
      } finally {
        active.delete(message.id);
        if (priority) priorityPending--; else pending--;
      }
    };
    if (priority) {
      // A desktop emergency stop must not wait for a native action to return.
      const task = Promise.resolve().then(execute);
      priorityTasks.add(task);
      task.finally(() => priorityTasks.delete(task));
    } else queue = queue.then(execute);
  }
  function frame(bytes) {
    try { accept(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes))); }
    catch { rpcError(null, -32700, 'Invalid UTF-8 JSON message.'); }
  }
  stdin.on('data', chunk => {
    let start = 0;
    for (let index = 0; index < chunk.length; index++) {
      if (chunk[index] !== 10) continue;
      const part = chunk.subarray(start, index); start = index + 1;
      if (!discarding && input.length + part.length <= MAX_FRAME) frame(Buffer.concat([input, part]));
      else if (!discarding) rpcError(null, -32700, 'Message exceeds the supported size.');
      input = Buffer.alloc(0); discarding = false;
    }
    const tail = chunk.subarray(start);
    if (!discarding && input.length + tail.length > MAX_FRAME) {
      rpcError(null, -32700, 'Message exceeds the supported size.'); input = Buffer.alloc(0); discarding = true;
    } else if (!discarding) input = Buffer.concat([input, tail]);
  });
  async function finish() {
    if (finishing) return closed;
    finishing = true;
    try { await queue; await Promise.all(priorityTasks); await output; await onClose?.(); }
    catch { process.exitCode = 1; }
    finally {
      for (const signal of ['SIGINT', 'SIGTERM']) process.off(signal, interrupt);
      finished();
    }
  }
  const cancelAll = () => { for (const abort of active.values()) abort.abort(); };
  const interrupt = () => { cancelAll(); stdin.destroy(); void finish(); };
  stdin.on('end', async () => {
    if (input.length && !discarding) await rpcError(null, -32700, 'An MCP message must end with a newline.');
    await finish();
  });
  stdin.on('close', () => { void finish(); });
  stdin.on('error', () => { cancelAll(); process.exitCode = 1; void finish(); });
  stdout.on('error', () => { cancelAll(); stdin.destroy(); process.exitCode = 1; });
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, interrupt);
  return { closed };
}
