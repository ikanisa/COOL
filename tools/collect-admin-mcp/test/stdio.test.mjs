import test from 'node:test';
import assert from 'node:assert/strict';
import { PassThrough } from 'node:stream';
import { serveStdio } from '../src/stdio.mjs';
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
    assert.equal(replies.at(-1).result.tools.length, 12);
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
