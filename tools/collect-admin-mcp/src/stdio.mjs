import { createFrameReader } from './stdio-frames.mjs';

const VERSIONS = ['2025-11-25', '2025-06-18', '2025-03-26'];
const MAX_PENDING = 16;
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

function writeFrame(stream, value) {
  const line = JSON.stringify(value) + '\n';
  return new Promise((resolve, reject) => {
    function settled(error) {
      stream.off('close', closed);
      if (error) reject(error);
      else resolve();
    }
    const closed = () => settled(new Error('MCP output closed before write completion.'));
    if (stream.destroyed || stream.writableEnded) return closed();
    stream.once('close', closed);
    stream.write(line, settled);
  });
}

export function serveStdio({ tools, callTool, serverInfo, instructions, toolError, isInvalidArguments,
  cancellationError, priorityTool, pendingMessage = 'Too many pending reads.', onClose,
  stdin = process.stdin, stdout = process.stdout }) {
  let state = 'new', queue = Promise.resolve(), pending = 0;
  let output = Promise.resolve(), priorityPending = 0, finishing = false, outputFailed = false;
  let finished;
  const closed = new Promise(resolve => { finished = resolve; });
  const active = new Map(), priorityTasks = new Set();
  const cancelAll = () => { for (const abort of active.values()) abort.abort(); };

  function send(value) {
    output = output.then(() => {
      if (!outputFailed) return writeFrame(stdout, value);
    }).catch(failOutput);
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
  const frames = createFrameReader(accept, message => rpcError(null, -32700, message));

  async function finish() {
    if (finishing) return closed;
    finishing = true;
    try { await queue; await Promise.all(priorityTasks); await output; await onClose?.(); }
    catch { process.exitCode = 1; }
    finally {
      stdin.off('data', frames.read);
      stdin.off('end', endInput);
      stdin.off('close', closeInput);
      stdin.off('error', failInput);
      stdout.off('error', failOutput);
      stdout.off('close', failOutput);
      for (const signal of ['SIGINT', 'SIGTERM']) process.off(signal, interrupt);
      finished();
    }
  }

  function endInput() {
    frames.end();
    void finish();
  }

  function closeInput() {
    if (!stdin.readableEnded) cancelAll();
    void finish();
  }

  function failInput() {
    process.exitCode = 1;
    interrupt();
  }

  function failOutput() {
    outputFailed = true;
    process.exitCode = 1;
    interrupt();
  }

  function interrupt() {
    cancelAll();
    stdin.destroy();
    void finish();
  }

  stdin.on('data', frames.read);
  stdin.on('end', endInput);
  stdin.on('close', closeInput);
  stdin.on('error', failInput);
  stdout.on('error', failOutput);
  stdout.on('close', failOutput);
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, interrupt);
  return { closed };
}
