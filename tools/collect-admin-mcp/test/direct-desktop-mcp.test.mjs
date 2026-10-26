import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, writeFile, chmod, rm, realpath, mkdir, copyFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { PassThrough } from 'node:stream';
import { DesktopError, DEFAULT_POLICY, PREPARE_SCHEMA, EMPTY_SCHEMA, EXECUTE_SCHEMA,
  ATTEMPT_SCHEMA, RECONCILE_SCHEMA, STOP_SCHEMA, EXCEPTIONS_SCHEMA } from '../src/direct-desktop/contract.mjs';
import { DESKTOP_TOOLS, callDesktopTool } from '../src/direct-desktop/tools.mjs';
import { serveDesktop } from '../src/direct-desktop/server.mjs';

const ROOT = resolve(import.meta.dirname, '..');
const NAMES = ['operator_health', 'observe_admin_queue', 'prepare_notification', 'dispatch_prepared_notification',
  'reconcile_attempt', 'write_admin_outcome', 'prepare_call', 'start_prepared_call', 'inspect_call_state',
  'end_current_call', 'get_pending_exceptions', 'stop_all'];
const CALLS = ['prepare_call', 'start_prepared_call', 'inspect_call_state', 'end_current_call'];
const SECRET = 'must-not-expose-desktop-diagnostics';
const valueOf = reply => { assert.equal(reply.error, undefined); assert.equal(reply.result.isError, undefined); return reply.result.structuredContent; };
const errorCode = reply => reply.result?.structuredContent?.error?.code;
const preparation = () => {
  const source = { source_namespace: 'visible-admin', tenant_id: 'synthetic-tenant', transaction_reference: 'synthetic-reference',
    notification_kind: 'payment_receipt', source_version: '1', observed_at: new Date().toISOString(),
    payment_state: 'confirmed', amount_label: '1,000 RWF', balance_label: '2,000 RWF' };
  return { source, recipient: { recipient_key: 'synthetic-recipient', channel: 'messages_native', destination_e164: '+250788000001',
    country_context: 'RW', single_recipient: true, recipient_visible: true },
  message: { template_key: 'payment_receipt_v1', purpose: 'payment_receipt',
    body: `Payment confirmed. Reference: ${source.transaction_reference}. Amount: ${source.amount_label}. Balance: ${source.balance_label}.`, source_derived: true },
  checks: { source_visible: true, previous_attempt_checked: true, consent_or_authority_visible: true } };
};

function protocolClient(stdin, stdout, exited) {
  let sequence = 0, partial = '';
  const waiting = new Map(), responses = [];
  stdout.on('data', bytes => {
    partial += bytes.toString();
    while (partial.includes('\n')) {
      const end = partial.indexOf('\n'), line = partial.slice(0, end); partial = partial.slice(end + 1);
      let message;
      try { message = JSON.parse(line); } catch { assert.fail('Non-protocol stdout'); }
      responses.push(message);
      const receiver = waiting.get(message.id);
      if (receiver) { waiting.delete(message.id); clearTimeout(receiver.timer); receiver.resolve(message); }
    }
  });
  exited?.then(() => {
    for (const receiver of waiting.values()) { clearTimeout(receiver.timer); receiver.reject(new Error('Desktop MCP exited before replying.')); }
    waiting.clear();
  });
  const write = value => stdin.write(JSON.stringify(value) + '\n');
  function call(method, params) {
    const id = ++sequence;
    const response = new Promise((resolve, reject) => {
      const timer = setTimeout(() => { waiting.delete(id); reject(new Error(`Desktop MCP timed out: ${method}`)); }, 5000);
      waiting.set(id, { resolve, reject, timer });
      write({ jsonrpc: '2.0', id, method, ...(params === undefined ? {} : { params }) });
    });
    return Object.assign(response, { id });
  }
  const notify = (method, params) => write({ jsonrpc: '2.0', method, ...(params === undefined ? {} : { params }) });
  return { call, notify, responses, tool: (name, args = {}) => call('tools/call', { name, arguments: args }),
    initialize: async (version = '2025-11-25') => {
      const reply = await call('initialize', { protocolVersion: version, capabilities: {}, clientInfo: { name: 'desktop-fixture', version: '1' } });
      notify('notifications/initialized'); return reply;
    } };
}

async function fixture(t) {
  const directory = await mkdtemp(join(await realpath(tmpdir()), 'collect-desktop-mcp-'));
  await chmod(directory, 0o700);
  const journal = join(directory, 'journal.sqlite'), violations = join(directory, 'violations.txt');
  const credential = join(directory, 'invalid-admin-session.json'), preload = join(directory, 'guard.mjs');
  await writeFile(credential, SECRET, { mode: 0o600 });
  const loader = `import { appendFileSync } from 'node:fs';
export async function load(url, context, nextLoad) {
  if (/\\/src\\/(?:api|config|tools|server|login)\\.mjs$/.test(new URL(url).pathname)) {
    appendFileSync(${JSON.stringify(violations)}, 'forbidden Admin import\\n');
    throw new Error('Forbidden Admin import');
  }
  return nextLoad(url, context);
}`;
  await writeFile(preload, `import { register, syncBuiltinESMExports } from 'node:module';
import { appendFileSync } from 'node:fs';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import net from 'node:net';
import tls from 'node:tls';
import http from 'node:http';
import https from 'node:https';
import http2 from 'node:http2';
import dns from 'node:dns';
import dgram from 'node:dgram';
const deny = label => { appendFileSync(${JSON.stringify(violations)}, label + '\\n'); throw new Error('Forbidden desktop IO'); };
const guard = (target, names) => { for (const name of names) if (typeof target[name] === 'function') target[name] = () => deny(name); };
guard(net, ['connect', 'createConnection']); guard(net.Socket.prototype, ['connect']); guard(net.Server.prototype, ['listen']);
guard(tls, ['connect']); guard(http, ['request', 'get']); guard(https, ['request', 'get']); guard(http2, ['connect']);
guard(dgram.Socket.prototype, ['bind', 'connect', 'send']);
const lookups = ['lookup', 'lookupService', 'resolve', 'resolve4', 'resolve6', 'resolveAny', 'resolveCname', 'resolveMx', 'resolveTxt', 'reverse'];
guard(dns, lookups); guard(dns.promises, lookups);
globalThis.fetch = () => deny('fetch'); globalThis.WebSocket = class { constructor() { deny('WebSocket'); } };
for (const [target, names] of [[fs, ['readFile', 'readFileSync', 'open', 'openSync', 'createReadStream', 'stat', 'statSync', 'lstat', 'lstatSync']],
  [fsp, ['readFile', 'open', 'stat', 'lstat']]]) {
  for (const name of names) {
    const original = target[name];
    target[name] = function(path, ...args) {
      if (String(path) === ${JSON.stringify(credential)} || String(path) === ${JSON.stringify(pathToFileURL(credential).href)}) deny('Admin credential read');
      return original.call(this, path, ...args);
    };
  }
}
syncBuiltinESMExports();
register('data:text/javascript,' + encodeURIComponent(${JSON.stringify(loader)}), import.meta.url);
`, { mode: 0o600 });
  const children = [];
  t.after(async () => {
    try {
      for (const child of children) {
        await child.close();
        assert.equal(child.stdout().includes(SECRET), false); assert.equal(child.stderr().includes(SECRET), false);
      }
      assert.equal(await readFile(violations, 'utf8').catch(error => { if (error.code === 'ENOENT') return ''; throw error; }), '');
    } finally { await rm(directory, { recursive: true, force: true }); }
  });
  function start(overrides = {}, entrypoint = join(ROOT, 'src/direct-desktop/server.mjs')) {
    const child = spawn(process.execPath, ['--import', pathToFileURL(preload).href, entrypoint], {
      cwd: ROOT, env: { PATH: process.env.PATH, TMPDIR: process.env.TMPDIR, LANG: 'C', TZ: 'UTC',
        COLLECT_DESKTOP_JOURNAL: journal, COLLECT_ADMIN_MCP_ORIGIN: 'https://invalid.example.test',
        COLLECT_ADMIN_MCP_SESSION_FILE: credential, ...overrides }, stdio: ['pipe', 'pipe', 'pipe'],
    });
    let stdout = '', stderr = '';
    child.stdout.on('data', bytes => { stdout += bytes; }); child.stderr.on('data', bytes => { stderr += bytes; });
    const exited = new Promise((resolve, reject) => { child.once('error', reject); child.once('close', (code, signal) => resolve({ code, signal })); });
    const client = protocolClient(child.stdin, child.stdout, exited);
    let closing;
    const result = { ...client, child, exited, stdout: () => stdout, stderr: () => stderr,
      close: () => closing ??= (async () => {
        child.stdin.end();
        const timer = setTimeout(() => child.kill('SIGKILL'), 1500);
        try { return await exited; } finally { clearTimeout(timer); }
      })() };
    children.push(result); return result;
  }
  return { directory, journal, start };
}

function localTransport(t, core) {
  const stdin = new PassThrough(), stdout = new PassThrough();
  const client = protocolClient(stdin, stdout), server = serveDesktop(core, { stdin, stdout });
  t.after(async () => { stdin.end(); await server.closed; });
  return { ...client, stdin };
}

test('desktop catalogue uses the shared strict schemas for exactly the twelve native tools', () => {
  assert.deepEqual(DESKTOP_TOOLS.map(tool => tool.name), NAMES);
  const expected = [EMPTY_SCHEMA, EMPTY_SCHEMA, PREPARE_SCHEMA, EXECUTE_SCHEMA, RECONCILE_SCHEMA, ATTEMPT_SCHEMA,
    EMPTY_SCHEMA, EMPTY_SCHEMA, EMPTY_SCHEMA, EMPTY_SCHEMA, EXCEPTIONS_SCHEMA, STOP_SCHEMA];
  DESKTOP_TOOLS.forEach((tool, index) => {
    assert.equal(tool.inputSchema, expected[index]); assert.equal(tool.inputSchema.additionalProperties, false);
  });
  for (const nested of Object.values(PREPARE_SCHEMA.properties)) assert.equal(nested.additionalProperties, false);
  assert.equal(RECONCILE_SCHEMA.properties.recovery.additionalProperties, false);
});

test('desktop arguments and cancelled signals are rejected before invoking the core', async () => {
  const core = new Proxy({}, { get() { assert.fail('Invalid or cancelled arguments reached the core.'); } });
  const invalid = [
    ['operator_health', { url: 'https://invalid.example.test' }], ['observe_admin_queue', { snapshot: [] }],
    ['prepare_notification', { ...preparation(), extra: true }],
    ...['source', 'recipient', 'message', 'checks'].map(key => {
      const input = preparation(); input[key].extra = true; return ['prepare_notification', input];
    }),
    ...[false, 'true', null].map(value => {
      const input = preparation(); input.checks.source_visible = value; return ['prepare_notification', input];
    }),
    ...['sms', 'whatsapp_api'].map(value => {
      const input = preparation(); input.recipient.channel = value; return ['prepare_notification', input];
    }),
    ['dispatch_prepared_notification', { ticket_id: 'ticket', executor_id: 'executor', url: '/api/admin' }],
    ['reconcile_attempt', { attempt_id: 'attempt' }], ['write_admin_outcome', { attempt_id: 'attempt', executor_id: '' }],
    ...CALLS.map(name => [name, { recipient_key: 'recipient', channel: 'messages_native' }]),
    ...[0, 101, 1.5, '1', null].map(limit => ['get_pending_exceptions', { limit }]),
    ['stop_all', {}], ['stop_all', { reason: 'stop', force: true }], ['fetch', {}], ['operator_health', null], ['operator_health', []],
  ];
  for (const [name, args] of invalid) await assert.rejects(callDesktopTool(core, name, args), error => error instanceof DesktopError && error.code === 'invalid_arguments');
  const controller = new AbortController(); controller.abort();
  for (const [name, args] of [['prepare_notification', preparation()], ['dispatch_prepared_notification', { ticket_id: 'ticket', executor_id: 'executor' }],
    ['write_admin_outcome', { attempt_id: 'attempt', executor_id: 'executor' }]]) {
    await assert.rejects(callDesktopTool(core, name, args, controller.signal), error => error instanceof DesktopError && error.code === 'cancelled');
  }
});

test('reconciliation recovery rejects malformed arguments before core and forwards valid recovery unchanged', async () => {
  const recovery = { lease_token: 'retained-lease-token', lease_fence: 7, owner_review_ref: 'owner-review-reference' };
  const args = { attempt_id: 'attempt', executor_id: 'executor', recovery };
  const noCore = new Proxy({}, { get() { assert.fail('Malformed recovery arguments reached the core.'); } });
  const invalidRecoveries = [null, [], true, 'recovery', {},
    ...Object.keys(recovery).map(omitted => Object.fromEntries(Object.entries(recovery).filter(([key]) => key !== omitted))),
    ...['lease_token', 'owner_review_ref'].flatMap(key => [null, 1, true, '', 'x'.repeat(513)].map(value => ({ ...recovery, [key]: value }))),
    ...[0, -1, 1.5, '1', null, true, Number.MAX_SAFE_INTEGER + 1].map(lease_fence => ({ ...recovery, lease_fence })),
    { ...recovery, quiescence_verified: true }, { ...recovery, native_driver: 'caller-supplied' },
  ];
  const invalidArgs = [
    ...invalidRecoveries.map(recovery => ({ ...args, recovery })),
    { executor_id: 'executor', recovery }, { attempt_id: 'attempt', recovery },
    { ...args, quiescence_verified: true }, { ...args, quiescence_verifier: { status: 'verified' } },
  ];
  const invalid = error => error instanceof DesktopError && error.code === 'invalid_arguments';
  for (const input of invalidArgs) await assert.rejects(callDesktopTool(noCore, 'reconcile_attempt', input), invalid);
  await assert.rejects(callDesktopTool(noCore, 'write_admin_outcome', args), invalid);

  const unavailable = { status: 'unavailable', reason_code: 'native_adapter_unavailable' };
  const calls = [], signal = new AbortController().signal, original = structuredClone(args);
  const result = await callDesktopTool({ async reconcileAttempt(input, receivedSignal) {
    calls.push({ input, signal: receivedSignal }); return unavailable;
  } }, 'reconcile_attempt', args, signal);
  assert.equal(result, unavailable); assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].input, original); assert.equal(calls[0].signal, signal);
  assert.deepEqual(args, original);
});

test('desktop transport returns honest blocked data and withholds arbitrary exception diagnostics', async t => {
  const client = localTransport(t, {
    health: async () => ({ status: 'blocked', reason_code: 'native_adapter_unavailable' }),
    observeAdminQueue: () => { throw new Error(SECRET); },
    prepareCall: () => { throw new DesktopError('native_call_workflow_unverified'); }, close() {},
  });
  await client.initialize();
  assert.equal(valueOf(await client.tool('operator_health')).status, 'blocked');
  const result = await client.tool('observe_admin_queue');
  assert.equal(errorCode(result), 'unavailable'); assert.equal(JSON.stringify(result).includes(SECRET), false);
  assert.equal(result.result.isError, true);
  const safe = await client.tool('prepare_call');
  assert.equal(errorCode(safe), 'native_call_workflow_unverified');
  assert.deepEqual(JSON.parse(safe.result.content[0].text), safe.result.structuredContent);
});

test('all desktop handlers accept asynchronous core methods and preserve arguments and dispatch signals', async () => {
  const calls = [], signal = new AbortController().signal;
  const handlers = ['health', 'observeAdminQueue', 'prepareNotification', 'dispatchPreparedNotification', 'reconcileAttempt',
    'writeAdminOutcome', 'prepareCall', 'startPreparedCall', 'inspectCallState', 'endCurrentCall', 'getPendingExceptions', 'stopAll'];
  const core = Object.fromEntries(handlers.map(name => [name, async (...args) => {
    calls.push({ name, args }); return { status: 'unavailable', reason_code: 'synthetic_handler_probe' };
  }]));
  const args = [{}, {}, preparation(), { ticket_id: 'ticket', executor_id: 'executor' },
    { attempt_id: 'attempt', executor_id: 'executor' }, { attempt_id: 'attempt', executor_id: 'executor' },
    {}, {}, {}, {}, { limit: 2 }, { reason: 'synthetic stop' }];
  for (const [index, name] of NAMES.entries()) {
    assert.equal((await callDesktopTool(core, name, args[index], signal)).status, 'unavailable');
    assert.equal(calls[index].name, handlers[index]);
    if (index === 0) assert.deepEqual(calls[index].args, []);
    else { assert.deepEqual(calls[index].args[0], args[index]); assert.equal(calls[index].args[1], signal); }
  }
});

test('desktop stop bypasses a saturated queue while other methods remain serialized and queued side effects cancel', async t => {
  let started, release;
  const arrival = new Promise(resolve => { started = resolve; }), gate = new Promise(resolve => { release = resolve; });
  let finished = false, prepared = 0, healthCalls = 0, stopped = 0;
  const controllerSeen = [];
  t.after(() => release());
  const client = localTransport(t, {
    dispatchPreparedNotification: async (args, signal) => {
      controllerSeen.push(signal); started(); await gate; finished = true;
      return { status: 'blocked', reason_code: 'operator_stopped' };
    },
    prepareNotification: () => { prepared++; return { status: 'blocked' }; },
    health: () => { healthCalls++; return { status: 'blocked' }; },
    stopAll: () => { stopped++; return { status: 'stopped', new_dispatch_inhibited: true }; }, close() {},
  });
  await client.initialize();
  const dispatch = client.tool('dispatch_prepared_notification', { ticket_id: 'ticket', executor_id: 'executor' });
  await arrival;
  const queued = client.tool('prepare_notification', preparation());
  client.notify('notifications/cancelled', { requestId: queued.id });
  const reads = Array.from({ length: 14 }, () => client.tool('operator_health'));
  assert.equal((await client.tool('operator_health')).error.code, -32000);
  assert.equal(valueOf(await client.tool('stop_all', { reason: 'synthetic emergency stop' })).status, 'stopped');
  assert.equal(stopped, 1); assert.equal(finished, false); assert.equal(healthCalls, 0); assert.equal(prepared, 0);
  client.notify('notifications/cancelled', { requestId: dispatch.id });
  release();
  assert.equal(valueOf(await dispatch).status, 'blocked'); assert.equal(controllerSeen[0].aborted, true);
  assert.equal(errorCode(await queued), 'cancelled');
  await Promise.all(reads); assert.equal(healthCalls, 14); assert.equal(prepared, 0);
});

test('native-only process negotiates versions and exposes twelve tools with invalid Admin environment and no network', async t => {
  const f = await fixture(t), client = f.start();
  assert.equal((await client.call('tools/list')).error.code, -32002);
  const initialized = await client.initialize('2025-06-18');
  assert.equal(initialized.result.protocolVersion, '2025-06-18');
  assert.equal(initialized.result.serverInfo.name, 'collect-direct-desktop-mcp');
  const tools = (await client.call('tools/list')).result.tools;
  assert.deepEqual(tools.map(tool => tool.name), NAMES);
  const health = valueOf(await client.tool('operator_health'));
  assert.equal(health.status, 'ready_dry_run'); assert.equal(health.live_dispatch_enabled, false);
  assert.equal(health.native_adapter, 'unconfigured'); assert.equal(health.evidence_label, 'unverified');
  assert.deepEqual(health.voice, { dialing: 'unavailable', assisted_conversation: 'unavailable', unattended_lifecycle: 'unavailable' });
  for (const name of ['observe_admin_queue', ...CALLS]) assert.equal(valueOf(await client.tool(name)).status, 'unavailable');
  assert.deepEqual((await client.call('ping')).result, {});
  assert.deepEqual(await client.close(), { code: 0, signal: null });
  const policy = join(f.directory, 'dry-policy.json');
  await writeFile(policy, JSON.stringify({ ...structuredClone(DEFAULT_POLICY), policy_revision: 'process-dry-policy' }), { mode: 0o600 });
  for (const [version, expected] of [['2025-03-26', '2025-03-26'], ['2099-01-01', '2025-11-25']]) {
    const next = f.start({ COLLECT_DESKTOP_POLICY: policy });
    assert.equal((await next.initialize(version)).result.protocolVersion, expected);
    assert.equal(valueOf(await next.tool('operator_health')).policy_revision, 'process-dry-policy');
    assert.deepEqual(await next.close(), { code: 0, signal: null });
  }
});

test('desktop process rejects strict and hidden API arguments before journal mutation', async t => {
  const f = await fixture(t), client = f.start(); await client.initialize(); await client.tool('operator_health');
  const bytes = path => readFile(path).catch(error => { if (error.code === 'ENOENT') return Buffer.alloc(0); throw error; });
  const before = [await bytes(f.journal), await bytes(f.journal + '-wal')];
  const inputs = [
    ['prepare_notification', {}], ['observe_admin_queue', { url: '/api/admin/core' }],
    ['operator_health', { credentials: SECRET }], ['get_pending_exceptions', { limit: 101 }],
    ['dispatch_prepared_notification', { ticket_id: 'ticket', executor_id: 'executor', send: true }],
    ...CALLS.map(name => [name, { recipient_key: 'recipient' }]),
    ...['source', 'recipient', 'message', 'checks'].map(key => {
      const input = preparation(); input[key].hidden = '/api/admin/core'; return ['prepare_notification', input];
    }),
  ];
  for (const [name, args] of inputs) assert.equal((await client.tool(name, args)).error.code, -32602);
  for (const name of ['collect_admin_session', 'collect_admin_list_records', 'fetch', 'rpc', 'execute_sql', 'login', 'send_message']) {
    assert.equal((await client.tool(name)).error.code, -32602);
  }
  assert.equal((await client.call('tools/list', { cursor: 'hidden' })).error.code, -32602);
  assert.deepEqual([await bytes(f.journal), await bytes(f.journal + '-wal')], before);
});

test('desktop dry dispatch creates no attempt or native success and stop persists across restart', async t => {
  const f = await fixture(t), client = f.start(); await client.initialize();
  const input = preparation(), prepared = valueOf(await client.tool('prepare_notification', input));
  assert.equal(prepared.status, 'prepared'); assert.equal(prepared.evidence_label, 'unverified');
  for (let index = 0; index < 2; index++) {
    const dispatched = valueOf(await client.tool('dispatch_prepared_notification', { ticket_id: prepared.ticket.id, executor_id: 'fixture-executor' }));
    assert.equal(dispatched.status, 'blocked'); assert.equal(dispatched.reason_code, 'live_dispatch_disabled');
    assert.equal(dispatched.external_action, 'not_started');
  }
  assert.equal(valueOf(await client.tool('operator_health')).attempts, 0);
  const pending = valueOf(await client.tool('get_pending_exceptions', { limit: 1 }));
  assert.equal(pending.total, 1); assert.equal(pending.rows.length, 1);
  assert.equal(pending.rows[0].kind, 'blocked_job');
  assert.equal(pending.rows[0].blocked_reason_code, 'live_dispatch_disabled');
  assert.equal(pending.rows[0].ticket_id, prepared.ticket.id);
  assert.equal(errorCode(await client.tool('reconcile_attempt', { attempt_id: 'unknown-attempt', executor_id: 'fixture-executor' })), 'attempt_not_found');
  assert.equal(valueOf(await client.tool('write_admin_outcome', { attempt_id: 'unknown-attempt', executor_id: 'fixture-executor' })).status, 'blocked');
  const stopped = valueOf(await client.tool('stop_all', { reason: 'synthetic restart test' }));
  assert.equal(stopped.status, 'stopped'); assert.equal(stopped.new_dispatch_inhibited, true);
  assert.deepEqual(await client.close(), { code: 0, signal: null });
  const restarted = f.start(); await restarted.initialize();
  const health = valueOf(await restarted.tool('operator_health'));
  assert.equal(health.status, 'stopped'); assert.deepEqual(health.stop, { stopped: true, reason: 'synthetic restart test' });
  assert.equal(valueOf(await restarted.tool('get_pending_exceptions')).total, 1);
  const blocked = valueOf(await restarted.tool('prepare_notification', input));
  assert.equal(blocked.status, 'blocked'); assert.equal(blocked.reason_code, 'operator_stopped');
  assert.equal(valueOf(await restarted.tool('operator_health')).attempts, 0);
});

test('desktop policy cannot enable mock or live native support and startup errors contain no diagnostics', async t => {
  const f = await fixture(t), policy = join(f.directory, 'policy.json');
  for (const change of [{ mode: 'assisted' }, { live_dispatch_enabled: true }, { native_adapter: 'mock' }, { native_adapter: 'computer_use' }]) {
    await writeFile(policy, JSON.stringify({ ...structuredClone(DEFAULT_POLICY), ...change }), { mode: 0o600 });
    const child = f.start({ COLLECT_DESKTOP_POLICY: policy });
    assert.deepEqual(await child.exited, { code: 1, signal: null });
    assert.equal(child.stdout(), ''); assert.match(child.stderr(), /^Collect desktop MCP is unavailable\./);
    assert.equal(child.stderr().includes('Error:'), false);
  }
  await writeFile(policy, SECRET, { mode: 0o600 });
  const invalid = f.start({ COLLECT_DESKTOP_POLICY: policy });
  assert.equal((await invalid.exited).code, 1); assert.equal(invalid.stdout(), '');
  const relative = f.start({ COLLECT_DESKTOP_JOURNAL: 'relative.sqlite' });
  assert.equal((await relative.exited).code, 1); assert.equal(relative.stdout(), '');
  const relativePolicy = f.start({ COLLECT_DESKTOP_POLICY: 'relative-policy.json' });
  assert.equal((await relativePolicy.exited).code, 1); assert.equal(relativePolicy.stdout(), '');
});

test('desktop process preserves malformed-frame recovery and newline termination checks', async t => {
  const f = await fixture(t), client = f.start(); await client.initialize();
  client.child.stdin.write('{invalid json}\n'); client.child.stdin.write(Buffer.from([0xc3, 0x28, 0x0a]));
  client.child.stdin.write('x'.repeat(70_000)); client.child.stdin.write('\n');
  client.child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: null, method: 'ping' }) + '\n');
  assert.deepEqual((await client.call('ping')).result, {});
  assert.equal(client.responses.filter(reply => reply.error?.code === -32700).length, 3);
  assert.equal(client.responses.filter(reply => reply.error?.code === -32600).length, 1);
  client.child.stdin.end('{');
  assert.equal((await client.exited).code, 0);
  assert.match(client.responses.at(-1).error.message, /end with a newline/);
});

test('desktop missing runtime fails closed with one fixed diagnostic', async t => {
  const f = await fixture(t), src = join(f.directory, 'isolated/src'), desktop = join(src, 'direct-desktop');
  await mkdir(desktop, { recursive: true, mode: 0o700 });
  for (const name of ['server.mjs', 'tools.mjs', 'contract.mjs']) await copyFile(join(ROOT, 'src/direct-desktop', name), join(desktop, name));
  await copyFile(join(ROOT, 'src/stdio.mjs'), join(src, 'stdio.mjs'));
  const client = f.start({}, join(desktop, 'server.mjs'));
  assert.deepEqual(await client.exited, { code: 1, signal: null }); assert.equal(client.stdout(), '');
  assert.equal(client.stderr(), 'Collect desktop MCP is unavailable. Check the documented private journal and policy configuration.\n');
});
