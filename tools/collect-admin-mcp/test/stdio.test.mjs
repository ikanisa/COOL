import test from 'node:test';
import assert from 'node:assert/strict';
import { PassThrough, Writable } from 'node:stream';
import { serveStdio } from '../src/stdio.mjs';
import { createFrameReader } from '../src/stdio-frames.mjs';
import { TOOLS } from '../src/tools.mjs';

async function exchange(requests, { initialized = true } = {}) {
  const stdin = new PassThrough(), stdout = new PassThrough();
  let output = '', calls = 0;
  stdout.on('data', chunk => { output += chunk.toString(); });
  const server = serveStdio({
    tools: TOOLS,
    callTool: () => { calls++; throw new Error('Discovery must not call the Admin API.'); },
    serverInfo: { name: 'collect-admin-mcp', version: 'test' },
    instructions: 'Protocol fixture only.',
    toolError: () => { throw new Error('No tool error is expected during discovery.'); },
    isInvalidArguments: () => false,
    cancellationError: () => new Error('cancelled'),
    stdin, stdout,
  });
  const messages = initialized ? [
    { jsonrpc: '2.0', id: 1, method: 'initialize', params: {
      protocolVersion: '2025-11-25', capabilities: {},
      clientInfo: { name: 'discovery-fixture', version: '1' },
    } },
    { jsonrpc: '2.0', method: 'notifications/initialized' },
  ] : [];
  stdin.end([...messages, ...requests].map(value => JSON.stringify(value) + '\n').join(''));
  await server.closed;
  assert.equal(calls, 0);
  return output.trim().split('\n').map(line => JSON.parse(line));
}

const list = params => ({ jsonrpc: '2.0', id: 2, method: 'tools/list', ...(params === undefined ? {} : { params }) });

test('fixed catalogue discovery accepts omitted and empty request parameters', async () => {
  for (const params of [undefined, {}]) {
    const replies = await exchange([list(params)]);
    assert.deepEqual(replies.at(-1).result, { tools: TOOLS });
    assert.equal(replies.at(-1).result.tools.length, 15);
    assert.equal('nextCursor' in replies.at(-1).result, false);
  }
});

test('fixed catalogue accepts standard request metadata without forwarding it to a tool', async () => {
  const replies = await exchange([list({ _meta: { progressToken: 'discovery', 'example/client': { enabled: true } } })]);
  assert.deepEqual(replies.at(-1).result, { tools: TOOLS });
});

test('fixed catalogue accepts empty metadata', async () => {
  const replies = await exchange([list({ _meta: {} })]);
  assert.deepEqual(replies.at(-1).result, { tools: TOOLS });
});

test('malformed discovery metadata is rejected without poisoning the next request', async () => {
  for (const _meta of [null, [], 1, 'metadata']) {
    const replies = await exchange([list({ _meta }), { ...list({ _meta: {} }), id: 3 }]);
    assert.equal(replies.at(-2).error.code, -32602);
    assert.deepEqual(replies.at(-1).result, { tools: TOOLS });
  }
});

test('fixed catalogue still rejects unissued cursors and unknown discovery parameters', async () => {
  for (const params of [{ cursor: 'not-issued' }, { cursor: null }, { _meta: {}, unknown: true }]) {
    const replies = await exchange([list(params)]);
    assert.equal(replies.at(-1).error.code, -32602);
  }
});

test('request metadata does not bypass initialization', async () => {
  const replies = await exchange([list({ _meta: { progressToken: 7 } })], { initialized: false });
  assert.equal(replies.at(-1).error.code, -32002);
});

test('the frame reader drops an oversized fragmented message and decodes the next message', () => {
  const messages = [], errors = [];
  const reader = createFrameReader(value => messages.push(value), message => errors.push(message));
  reader.read(Buffer.alloc(65536, 0x20));
  reader.read(Buffer.from('extra'));
  reader.read(Buffer.from(' ignored\n{"method":"ping"}\n'));
  reader.end();
  assert.deepEqual(errors, ['Message exceeds the supported size.']);
  assert.deepEqual(messages, [{ method: 'ping' }]);
});

test('an abrupt input disconnect cancels active and queued calls before cleanup', async () => {
  const stdin = new PassThrough(), stdout = new PassThrough();
  const replies = [];
  stdout.setEncoding('utf8');
  stdout.on('data', packet => replies.push(JSON.parse(packet)));
  let calls = 0, cleanup = false;
  const started = Promise.withResolvers();
  const server = serveStdio({
    tools: [{ name: 'read' }],
    callTool(_name, _args, signal) {
      calls++;
      const pending = new Promise((_, reject) => {
        signal.addEventListener('abort', () => reject(new Error('cancelled')), { once: true });
      });
      started.resolve();
      return pending;
    },
    serverInfo: { name: 'disconnect-fixture', version: 'test' },
    instructions: 'Transport fixture only.',
    toolError: error => ({ isError: true, message: error.message }),
    isInvalidArguments: () => false,
    cancellationError: () => new Error('cancelled'),
    onClose: () => { cleanup = true; },
    stdin, stdout,
  });
  const requests = [
    { id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'fixture', version: '1' } } },
    { method: 'notifications/initialized' },
    { id: 2, method: 'tools/call', params: { name: 'read' } },
    { id: 3, method: 'tools/call', params: { name: 'read' } },
  ];
  stdin.write(requests.map(message => JSON.stringify({ jsonrpc: '2.0', ...message }) + '\n').join(''));
  await started.promise;
  stdin.destroy();
  await server.closed;
  assert.equal(calls, 1);
  assert.equal(cleanup, true);
  assert.deepEqual(replies.slice(1).map(reply => [reply.id, reply.result.message]), [[2, 'cancelled'], [3, 'cancelled']]);
});

test('a closed output unblocks cleanup during a pending write', async t => {
  const previousExitCode = process.exitCode;
  t.after(() => { process.exitCode = previousExitCode; });
  const stdin = new PassThrough();
  const writing = Promise.withResolvers();
  const stdout = new Writable({
    highWaterMark: 1,
    write() { writing.resolve(); },
  });
  let cleaned = false;
  const server = serveStdio({
    tools: [],
    callTool: () => assert.fail('Ping must not call any tool.'),
    serverInfo: { name: 'output-fixture', version: 'test' },
    instructions: 'Transport fixture only.',
    toolError: () => assert.fail('Ping must not run a tool.'),
    isInvalidArguments: () => false,
    cancellationError: () => new Error('cancelled'),
    onClose: () => { cleaned = true; },
    stdin, stdout,
  });
  stdin.write('{"jsonrpc":"2.0","id":1,"method":"ping"}\n');
  await writing.promise;
  stdout.destroy();
  await server.closed;
  assert.equal(cleaned, true);
  assert.equal(process.exitCode, 1);
});
