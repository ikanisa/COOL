import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, readFile, writeFile, chmod, rm, realpath, symlink, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { once } from 'node:events';
import { ADMIN_ORIGIN, saveCredential, loadCredential, configuration } from '../src/config.mjs';
import { canonicalRequestId } from '../src/tools.mjs';

const ROOT = resolve(import.meta.dirname, '..');
const ACCOUNT = '11111111-1111-4111-8111-111111111111';
const SESSION = '22222222-2222-4222-8222-222222222222';
const PRINCIPAL = '33333333-3333-4333-8333-333333333333';
const RESOURCE = '44444444-4444-4444-8444-444444444444';
const COOKIE = `__Host-collect_admin=${'a'.repeat(64)}`;
const KEY = 'review-original-1234';
const MARKER = { contract_version: 2, model: 'canonical_evidence_ledger' };
const expiresAt = new Date(Date.now() + 3_600_000).toISOString();
const credential = { version: 1, origin: ADMIN_ORIGIN, cookie: COOKIE, accountId: ACCOUNT, sessionId: SESSION, principalId: PRINCIPAL, expiresAt };
function session(permissions = ['overview.read', 'users.read', 'collections.read', 'payments.read', 'receivers.read', 'ledger.read', 'account.manage', 'reconciliations.read', 'admin_users.read'], role = 'admin') {
  return { user: { id: ACCOUNT, email: 'admin@example.test', role, sessionId: SESSION, principalId: PRINCIPAL,
    financialModel: 'canonical_evidence_ledger', permissions, assuranceLevel: 1, mfaAt: null }, expiresAt };
}
const retainedReceipt = () => ({ status: 'succeeded', request_id: canonicalRequestId(PRINCIPAL, KEY), resource_type: 'groups', resource_id: RESOURCE, version: 1 });
const childEnvironment = overrides => ({ PATH: '/usr/bin:/bin', TMPDIR: process.env.TMPDIR, LANG: 'C', TZ: 'UTC', ...overrides });
async function harness(t, handler = () => ({ ...MARKER, rows: [], total: 0 }), testCredential = credential) {
  const directory = await mkdtemp(join(await realpath(tmpdir()), 'collect-mcp-test-'));
  const config = { origin: ADMIN_ORIGIN, credentialFile: join(directory, 'session.json') };
  await saveCredential(config, testCredential);
  let sessions = 0;
  const requests = [];
  const server = createServer(async (request, reply) => {
    const chunks = []; for await (const chunk of request) chunks.push(chunk);
    const incoming = { url: new URL(request.url, ADMIN_ORIGIN), method: request.method, headers: request.headers, body: Buffer.concat(chunks).toString() };
    requests.push(incoming);
    let result;
    try { result = await handler(incoming, incoming.url.pathname.endsWith('/auth/session') ? ++sessions : sessions); } catch { result = { status: 500, data: { error: 'fixture_failed' } }; }
    if (result === undefined && incoming.url.pathname.endsWith('/auth/session')) result = session();
    const status = typeof result?.status === 'number' ? result.status : 200, data = result?.data ?? result;
    reply.writeHead(status, { 'content-type': 'application/json', ...(result?.headers ?? {}) });
    reply.end(typeof result?.raw === 'string' ? result.raw : JSON.stringify(data));
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  const child = spawn(process.execPath, ['--import', pathToFileURL(join(ROOT, 'test/fixture-preload.mjs')).href, join(ROOT, 'src/server.mjs')], {
    cwd: ROOT, env: childEnvironment({ COLLECT_ADMIN_MCP_SESSION_FILE: config.credentialFile,
      COLLECT_ADMIN_MCP_ORIGIN: ADMIN_ORIGIN, COLLECT_MCP_FIXTURE_URL: `http://127.0.0.1:${server.address().port}` }), stdio: ['pipe', 'pipe', 'pipe'],
  });
  let stdout = '', stderr = '', sequence = 0, partial = '';
  const waiting = new Map(), responses = [];
  child.stdout.on('data', chunk => {
    stdout += chunk.toString(); partial += chunk.toString();
    while (partial.includes('\n')) {
      const end = partial.indexOf('\n'), line = partial.slice(0, end); partial = partial.slice(end + 1);
      let message;
      try { message = JSON.parse(line); } catch { assert.fail('Non-protocol stdout'); }
      responses.push(message);
      const receive = waiting.get(message.id); if (receive) { waiting.delete(message.id); receive(message); }
    }
  });
  child.stderr.on('data', chunk => { stderr += chunk; });
  t.after(async () => {
    child.stdin.end();
    if (child.exitCode === null && child.signalCode === null) {
      const done = once(child, 'exit');
      const timeout = setTimeout(() => child.kill('SIGKILL'), 1000);
      await done; clearTimeout(timeout);
    }
    await new Promise(resolve => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
    assert.equal(stdout.includes(COOKIE), false); assert.equal(stderr.includes(COOKIE), false);
  });
  function call(method, params) {
    const id = ++sequence;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { waiting.delete(id); reject(new Error(`Protocol request timed out: ${method}`)); }, 8000);
      waiting.set(id, result => { clearTimeout(timer); resolve(result); });
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, ...(params ? { params } : {}) }) + '\n');
    });
  }
  return { child, config, requests, responses, fixtureOrigin: `http://127.0.0.1:${server.address().port}`,
    call, tool: (name, args = {}) => call('tools/call', { name, arguments: args }),
    notify: (method, params) => child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, ...(params ? { params } : {}) }) + '\n'),
    initialize: async (version = '2025-11-25') => {
      const result = await call('initialize', { protocolVersion: version, capabilities: {}, clientInfo: { name: 'collect-fixture', version: '1.0' } });
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
      return result;
    },
  };
}
function authOr(incoming, response) { return incoming.url.pathname.endsWith('/auth/session') ? undefined : response; }
function safeCode(value) { return value.result?.structuredContent?.error?.code; }

test('actual stdio lifecycle negotiates versions and advertises exactly fifteen read-only tools without signing in', async t => {
  const f = await harness(t);
  assert.equal((await f.call('tools/list')).error.code, -32002);
  const init = await f.initialize('2025-06-18'); assert.equal(init.result.protocolVersion, '2025-06-18');
  const listed = await f.call('tools/list'); assert.equal(listed.result.tools.length, 15);
  for (const tool of listed.result.tools) { assert.equal(tool.annotations.readOnlyHint, true); assert.equal(tool.inputSchema.additionalProperties, false); }
  assert.deepEqual((await f.call('ping')).result, {});
  assert.equal(f.requests.length, 0);
  assert.equal((await f.call('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'x', version: '1' } })).error.code, -32602);
});

test('unsupported protocol version returns the latest supported version', async t => {
  const f = await harness(t); assert.equal((await f.initialize('2099-01-01')).result.protocolVersion, '2025-11-25');
});

test('process reads bounded canonical Users with real origin/cookie authority checks before and after', async t => {
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, rows: [{ id: RESOURCE, title: 'Synthetic person', password_hash: 'must-never-return', details: { access_token: 'must-never-return' } }], total: 51 }));
  await f.initialize();
  const result = await f.tool('collect_admin_list_records', { area: 'users', search: 'type:direct "Jane Doe"', limit: 1, offset: 50, sort: 'public_id_asc' });
  assert.equal(result.result.isError, undefined);
  const value = result.result.structuredContent;
  assert.equal(value.data.rows.length, 1); assert.equal(value.data.page.next_offset, null);
  assert.equal(JSON.stringify(value).includes('must-never-return'), false);
  assert.equal(f.requests.length, 3);
  const request = f.requests[1];
  assert.equal(request.url.pathname, '/api/admin/core/users'); assert.equal(request.url.searchParams.get('limit'), '1');
  assert.equal(request.url.searchParams.get('search'), 'type:direct "Jane Doe"');
  assert.equal(request.headers.origin, ADMIN_ORIGIN); assert.equal(request.headers.cookie, COOKIE);
  assert.equal(request.method, 'GET'); assert.equal(request.headers.authorization, undefined);
});

test('unlinked Operator stays a read-only recorded identity without invented Admin linkage', async t => {
  const person = { id: RESOURCE, collect_user_id: RESOURCE, public_id: '123456',
    member_type: 'operator', user_types: ['Operator'], operator_admin_id: null,
    operator_role: null, operator_status: null, operator_public_id: null };
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, rows: [person], total: 1 }));
  await f.initialize();
  const result = await f.tool('collect_admin_list_records', { area: 'users', limit: 1 });
  assert.equal(result.result.isError, undefined);
  assert.deepEqual(JSON.parse(JSON.stringify(result.result.structuredContent.data.rows[0])), person);
  assert.equal(f.requests.length, 3);
  assert.equal(f.requests.every(request => request.method === 'GET'), true);
  const tools = (await f.call('tools/list')).result.tools;
  assert.equal(tools.every(tool => tool.annotations.readOnlyHint === true), true);
  assert.equal(tools.some(tool => /create|update|grant|replay|cancel/.test(tool.name)), false);
});

test('Staff cannot bypass an absent read capability using a role label or extra URL argument', async t => {
  const f = await harness(t, incoming => incoming.url.pathname.endsWith('/auth/session') ? session(['overview.read'], 'staff') : { ...MARKER, rows: [], total: 0 });
  await f.initialize();
  assert.equal(safeCode(await f.tool('collect_admin_list_records', { area: 'users' })), 'permission_denied');
  assert.equal(f.requests.every(r => r.url.pathname.endsWith('/auth/session')), true);
  assert.equal((await f.tool('collect_admin_overview', { url: 'https://attacker.test' })).error.code, -32602);
});

test('all input bounds and arbitrary RPC/path/write calls fail before any HTTP request', async t => {
  const f = await harness(t); await f.initialize();
  for (const args of [
    { area: '../team' }, { area: 'users', limit: 51 }, { area: 'users', offset: -1 },
    { area: 'users', search: 'a'.repeat(201) }, { area: 'users', sort: 'password_hash_asc' },
    { area: 'users', status: 'private' }, { area: 'users', search: 'a\nb' }, { area: 'users', origin: ADMIN_ORIGIN },
  ]) assert.equal((await f.tool('collect_admin_list_records', args)).error.code, -32602);
  assert.equal((await f.tool('collect_admin_get_record', { area: 'groups', id: RESOURCE, limit: 1 })).error.code, -32602);
  assert.equal((await f.tool('collect_admin_get_record', { area: 'users', id: RESOURCE, relation: 'evidence' })).error.code, -32602);
  assert.equal((await f.tool('collect_admin_get_request_status', { idempotency_key: '../arbitrary' })).error.code, -32602);
  for (const name of ['fetch', 'rpc', 'execute_sql', 'collect_admin_create_group', 'collect_admin_retry_request']) assert.equal((await f.tool(name)).error.code, -32602);
  assert.equal(f.requests.length, 0);
});

test('a role/capability change during a read withholds its data', async t => {
  const f = await harness(t, (incoming, count) => incoming.url.pathname.endsWith('/auth/session') ? session(count > 1 ? ['overview.read'] : undefined) : { ...MARKER, rows: [{ id: RESOURCE, title: 'must-withhold-record' }], total: 1 });
  await f.initialize(); const result = await f.tool('collect_admin_list_records', { area: 'users' });
  assert.equal(safeCode(result), 'session_unavailable'); assert.equal(JSON.stringify(result).includes('must-withhold-record'), false);
});

test('a replaced credential file during a read cannot transfer a result to another local session', async t => {
  let file;
  const f = await harness(t, async incoming => {
    if (incoming.url.pathname.endsWith('/auth/session')) return undefined;
    const current = JSON.parse(await readFile(file, 'utf8')); current.cookie = `__Host-collect_admin=${'b'.repeat(64)}`;
    await writeFile(file, JSON.stringify(current), { mode: 0o600 });
    return { ...MARKER, rows: [], total: 0 };
  }); file = f.config.credentialFile;
  await f.initialize(); assert.equal(safeCode(await f.tool('collect_admin_list_records', { area: 'users' })), 'session_unavailable');
});

test('revoked sessions, upstream permission denial, HTML and secret error text are redacted without retry', async t => {
  let mode = 'revoked';
  const f = await harness(t, incoming => {
    if (mode === 'revoked') return { status: 401, data: { error: { message: 'sensitive-cookie-value' } } };
    if (incoming.url.pathname.endsWith('/auth/session')) return undefined;
    if (mode === 'forbidden') return { status: 403, data: { error: { message: 'sensitive-cookie-value' } } };
    return { raw: '<html>sensitive-cookie-value</html>', headers: { 'content-type': 'text/html' } };
  }); await f.initialize();
  assert.equal(safeCode(await f.tool('collect_admin_overview')), 'session_unavailable');
  mode = 'forbidden'; assert.equal(safeCode(await f.tool('collect_admin_overview')), 'permission_denied');
  mode = 'html'; const failed = await f.tool('collect_admin_overview'); assert.equal(safeCode(failed), 'service_unavailable');
  assert.equal(JSON.stringify(failed).includes('sensitive-cookie-value'), false);
  assert.equal(f.requests.filter(r => r.url.pathname.endsWith('/core/overview')).length, 2);
});

test('redirect responses are never followed and oversized responses fail closed', async t => {
  let mode = 'redirect';
  const f = await harness(t, incoming => {
    if (incoming.url.pathname.endsWith('/auth/session')) return undefined;
    return mode === 'redirect' ? { status: 302, headers: { location: '/leak' }, data: {} } : { raw: JSON.stringify({ padding: 'x'.repeat(600_000) }) };
  }); await f.initialize();
  assert.equal(safeCode(await f.tool('collect_admin_overview')), 'service_unavailable');
  mode = 'large'; assert.equal(safeCode(await f.tool('collect_admin_overview')), 'service_unavailable');
  assert.equal(f.requests.some(r => r.url.pathname === '/leak'), false);
});

test('exact request recovery binds original key and principal, distinguishes all outcomes and never writes', async t => {
  let status = 'succeeded';
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, status,
    ...(status === 'not_found' ? {} : { request_id: canonicalRequestId(PRINCIPAL, KEY), receipt: status === 'succeeded' ? retainedReceipt() : null }) }));
  await f.initialize();
  for (status of ['succeeded', 'unconfirmed', 'cancelled', 'not_found']) {
    const reply = await f.tool('collect_admin_get_request_status', { idempotency_key: KEY });
    assert.equal(reply.result.structuredContent.data.status, status);
    assert.equal(reply.result.structuredContent.data.recovery.write_permitted, false);
  }
  assert.equal(f.requests.every(r => r.method === 'GET'), true);
  assert.equal(f.requests.filter(r => r.url.pathname === `/api/admin/operations/requests/${KEY}`).length, 4);
});

test('a receipt for another principal or mismatched resource outcome never confirms recovery', async t => {
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, status: 'succeeded', request_id: canonicalRequestId(ACCOUNT, KEY), receipt: retainedReceipt() }));
  await f.initialize(); assert.equal(safeCode(await f.tool('collect_admin_get_request_status', { idempotency_key: KEY })), 'service_unavailable');
});

test('valid original request keys containing repeated dots remain exact without path traversal', async t => {
  const key = 'original..key-123';
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, status: 'unconfirmed', request_id: canonicalRequestId(PRINCIPAL, key), receipt: null }));
  await f.initialize(); const reply = await f.tool('collect_admin_get_request_status', { idempotency_key: key });
  assert.equal(reply.result.structuredContent.data.status, 'unconfirmed');
  assert.equal(f.requests[1].url.pathname, `/api/admin/operations/requests/${key}`);
});

test('history remains current-account scoped with bounded pagination and retained identities', async t => {
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, total: 1, rows: [{ id: canonicalRequestId(PRINCIPAL, KEY), idempotency_key: KEY,
    scope: 'groups.post', status: 'succeeded', receipt: retainedReceipt(), created_at: new Date().toISOString() }] }));
  await f.initialize(); const reply = await f.tool('collect_admin_list_requests', { limit: 1 });
  assert.equal(reply.result.structuredContent.data.rows.length, 1);
  assert.equal(f.requests[1].url.pathname, '/api/admin/operations/requests');
  assert.equal(f.requests[1].url.searchParams.has('account_id'), false);
});

test('detail reads use exact UUID and a valid related-page allowlist', async t => {
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, resource_type: 'groups', resource: { id: RESOURCE, title: 'Synthetic group' },
    related: { memberships: [] }, related_pages: { memberships: { total: 0, limit: 5, offset: 0, next_offset: null } } }));
  await f.initialize();
  const reply = await f.tool('collect_admin_get_record', { area: 'groups', id: RESOURCE, relation: 'memberships', limit: 5 });
  assert.equal(reply.result.structuredContent.data.resource.id, RESOURCE);
  assert.equal(f.requests[1].url.pathname, `/api/admin/operations/groups/${RESOURCE}`);
  assert.equal(f.requests[1].url.searchParams.get('relation'), 'memberships');
});

test('inconsistent pagination and old data contracts are rejected, never relabelled as canonical', async t => {
  let canonical = false;
  const f = await harness(t, incoming => authOr(incoming, { ...(canonical ? MARKER : {}), rows: [], total: 1 }));
  await f.initialize();
  assert.equal(safeCode(await f.tool('collect_admin_list_records', { area: 'users', limit: 1 })), 'service_unavailable');
  canonical = true; assert.equal(safeCode(await f.tool('collect_admin_list_records', { area: 'users', limit: 1 })), 'service_unavailable');
});

test('private credential checks reject broad modes, linked files and cross-origin copies', async t => {
  const f = await harness(t); await f.initialize();
  await chmod(f.config.credentialFile, 0o644);
  assert.equal(safeCode(await f.tool('collect_admin_session')), 'session_unavailable');
  await chmod(f.config.credentialFile, 0o600);
  const target = `${f.config.credentialFile}.target`;
  await writeFile(target, JSON.stringify(credential), { mode: 0o600 });
  await rm(f.config.credentialFile); await symlink(target, f.config.credentialFile);
  assert.equal(safeCode(await f.tool('collect_admin_session')), 'session_unavailable');
  await rm(f.config.credentialFile); await writeFile(f.config.credentialFile, JSON.stringify({ ...credential, origin: 'https://admin.collect.ikanisa.com' }), { mode: 0o600 });
  assert.equal(safeCode(await f.tool('collect_admin_session')), 'session_unavailable');
  assert.equal(f.requests.length, 0);
});

test('configuration rejects an arbitrary remote origin and a credential inside the repository', () => {
  assert.throws(() => configuration({ COLLECT_ADMIN_MCP_ORIGIN: 'https://attacker.test' }), /reviewed/);
  assert.throws(() => configuration({ COLLECT_ADMIN_MCP_SESSION_FILE: join(ROOT, 'session.json') }), /outside/);
});

test('atomic credential save is owner-only, readable and expiry-bound', async t => {
  const f = await harness(t);
  assert.equal((await stat(f.config.credentialFile)).mode & 0o777, 0o600);
  assert.equal((await loadCredential(f.config)).sessionId, SESSION);
  await assert.rejects(saveCredential(f.config, { ...credential, expiresAt: '2000-01-01T00:00:00.000Z' }), /Sign in/);
});

test('login refuses pipes and password arguments without network access or echo', async () => {
  const child = spawn(process.execPath, [join(ROOT, 'src/login.mjs'), 'do-not-echo-this-password'], { env: childEnvironment(), stdio: ['pipe', 'pipe', 'pipe'] });
  let output = ''; child.stdout.on('data', v => { output += v; }); child.stderr.on('data', v => { output += v; });
  child.stdin.end(); const [code] = await once(child, 'exit');
  assert.equal(code, 1); assert.match(output, /directly in a terminal/); assert.equal(output.includes('do-not-echo-this-password'), false);
});

async function loginProcess(f) {
  const script = `import {loginWithCredentials} from ${JSON.stringify(pathToFileURL(join(ROOT, 'src/login.mjs')).href)};
    import {configuration} from ${JSON.stringify(pathToFileURL(join(ROOT, 'src/config.mjs')).href)};
    try { const result = await loginWithCredentials(configuration(), 'operator@example.test', 'Synthetic-password-for-fixture'); process.stdout.write(JSON.stringify(result)); }
    catch { process.stderr.write('LOGIN_NOT_CONFIRMED'); process.exitCode=1; }`;
  const child = spawn(process.execPath, ['--import', pathToFileURL(join(ROOT, 'test/fixture-preload.mjs')).href, '--input-type=module', '-e', script], {
    cwd: ROOT, env: childEnvironment({ COLLECT_ADMIN_MCP_ORIGIN: ADMIN_ORIGIN,
      COLLECT_ADMIN_MCP_SESSION_FILE: f.config.credentialFile, COLLECT_MCP_FIXTURE_URL: f.fixtureOrigin }), stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '', stderr = '';
  child.stdout.on('data', value => { stdout += value; }); child.stderr.on('data', value => { stderr += value; });
  const [code] = await once(child, 'exit');
  assert.equal((stdout + stderr).includes(COOKIE), false);
  assert.equal((stdout + stderr).includes('Synthetic-password-for-fixture'), false);
  return { code, stdout, stderr };
}

test('separate login exchanges one human credential attempt for a verified origin-bound private session', async t => {
  const f = await harness(t, incoming => {
    if (incoming.url.pathname.endsWith('/auth/session')) return undefined;
    assert.equal(incoming.url.pathname, '/api/admin/auth/login');
    assert.equal(incoming.method, 'POST'); assert.equal(incoming.headers.origin, ADMIN_ORIGIN);
    assert.equal(incoming.headers.cookie, undefined);
    assert.deepEqual(JSON.parse(incoming.body), { email: 'operator@example.test', password: 'Synthetic-password-for-fixture' });
    return { data: session(), headers: { 'set-cookie': `${COOKIE}; Path=/; HttpOnly; SameSite=Strict; Max-Age=3600; Secure` } };
  });
  const result = await loginProcess(f); assert.equal(result.code, 0); assert.equal(JSON.parse(result.stdout).role, 'admin');
  assert.equal((await loadCredential(f.config)).accountId, ACCOUNT);
  assert.equal(f.requests.filter(r => r.method === 'POST').length, 1);
  assert.equal(f.requests.filter(r => r.url.pathname.endsWith('/auth/session')).length, 1);
});

test('login never stores an insecure cookie or retries an uncertain authentication response', async t => {
  let mode = 'cookie';
  const f = await harness(t, () => mode === 'cookie'
    ? { data: session(), headers: { 'set-cookie': `${COOKIE}; Path=/; Secure; SameSite=Strict` } }
    : { status: 503, data: { error: 'private provider diagnostic' } });
  const before = await readFile(f.config.credentialFile);
  assert.equal((await loginProcess(f)).code, 1);
  mode = 'uncertain'; assert.equal((await loginProcess(f)).code, 1);
  assert.deepEqual(await readFile(f.config.credentialFile), before);
  assert.equal(f.requests.filter(r => r.method === 'POST').length, 2);
});

test('cancel notification aborts a live read and never starts a replacement HTTP call', async t => {
  let started;
  const arrival = new Promise(resolve => { started = resolve; });
  const f = await harness(t, async incoming => {
    if (incoming.url.pathname.endsWith('/auth/session')) return undefined;
    started(); await new Promise(resolve => setTimeout(resolve, 100));
    return { ...MARKER, metrics: [] };
  });
  await f.initialize();
  const pending = f.tool('collect_admin_overview');
  await arrival; f.notify('notifications/cancelled', { requestId: 2 });
  assert.equal(safeCode(await pending), 'cancelled');
  assert.equal(f.requests.filter(r => r.url.pathname.endsWith('/core/overview')).length, 1);
});

test('malformed and oversized frames cannot corrupt a later valid MCP request', async t => {
  const f = await harness(t); await f.initialize();
  f.child.stdin.write('{invalid json}\n');
  f.child.stdin.write(Buffer.from([0xc3, 0x28, 0x0a]));
  f.child.stdin.write('x'.repeat(70_000) + '\n');
  assert.deepEqual((await f.call('ping')).result, {});
  assert.equal(f.responses.filter(v => v.error?.code === -32700).length, 3);
  assert.equal(f.requests.length, 0);
});

test('reconciliation queue preserves actual transaction ordering and bounded pagination', async t => {
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, total: 0, rows: [], limit: 5, offset: 10, next_offset: null }));
  await f.initialize(); const reply = await f.tool('collect_admin_list_reconciliations', { search: 'unallocated transactions', limit: 5, offset: 10, sort: 'amount_minor_desc' });
  assert.equal(reply.result.structuredContent.data.rows.length, 0);
  assert.equal(f.requests[1].url.pathname, '/api/admin/reconciliations');
  assert.equal(f.requests[1].url.searchParams.get('sort'), 'amount_minor_desc');
  assert.equal(f.requests[1].url.searchParams.get('search'), 'unallocated transactions');
});

test('reconciliation detail retains the exact actor and scoped proposal page without enabling a review', async t => {
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, resource_type: 'reconciliations', resource: { id: RESOURCE },
    current_actor_id: ACCOUNT, current_principal_id: PRINCIPAL, can_review: true,
    related: { proposals: { rows: [], total: 0, limit: 5, offset: 0, next_offset: null } } }));
  await f.initialize(); const reply = await f.tool('collect_admin_get_reconciliation', { transaction_id: RESOURCE, relation: 'proposals', limit: 5 });
  assert.equal(reply.result.structuredContent.data.resource.id, RESOURCE);
  assert.equal(reply.result.structuredContent.read_only, true);
  assert.equal(f.requests[1].url.pathname, `/api/admin/reconciliations/${RESOURCE}`);
  assert.equal(f.requests.every(r => r.method === 'GET'), true);
});

test('reconciliation candidates stay transaction-scoped and preserve reviewed identity versions', async t => {
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, transaction_id: RESOURCE,
    rows: [{ member_user_id: PRINCIPAL, member_version: 3, membership_version: 2, group_version: 1, group_id: ACCOUNT,
      payment_identity: { display_name: 'Synthetic payer', momo_number: '+250788000000', momo_provider: 'mtn_momo', momo_pay_code: null } }],
    total: 1, limit: 5, offset: 0, next_offset: null }));
  await f.initialize(); const reply = await f.tool('collect_admin_list_reconciliation_members', { transaction_id: RESOURCE, search: 'Synthetic', limit: 5 });
  assert.equal(reply.result.structuredContent.data.rows[0].member_version, 3);
  assert.equal(f.requests[1].url.pathname, '/api/admin/reconciliations/members');
  assert.equal(f.requests[1].url.searchParams.get('transaction_id'), RESOURCE);
  assert.equal((await f.tool('collect_admin_list_reconciliation_members', { transaction_id: RESOURCE, group_id: ACCOUNT })).error.code, -32602);
});

test('each reconciliation permission is required and Staff cannot request an ungranted ledger relation', async t => {
  let permissions = ['reconciliations.read', 'payments.read'];
  const f = await harness(t, incoming => incoming.url.pathname.endsWith('/auth/session') ? session(permissions, 'staff') : {});
  await f.initialize();
  assert.equal(safeCode(await f.tool('collect_admin_get_reconciliation', { transaction_id: RESOURCE })), 'permission_denied');
  assert.equal(safeCode(await f.tool('collect_admin_list_reconciliation_members', { transaction_id: RESOURCE })), 'permission_denied');
  permissions = ['reconciliations.read', 'users.read'];
  assert.equal(safeCode(await f.tool('collect_admin_list_reconciliations')), 'permission_denied');
  permissions = ['reconciliations.read', 'payments.read', 'users.read'];
  assert.equal(safeCode(await f.tool('collect_admin_get_reconciliation', { transaction_id: RESOURCE, relation: 'ledger_entries' })), 'permission_denied');
  assert.equal(f.requests.every(r => r.url.pathname.endsWith('/auth/session')), true);
});

function team() {
  return { currentEmail: 'admin@example.test', canManage: false, permissionsByRole: { owner: ['admin_users.read'], admin: ['users.read'], staff: ['users.read'] },
    members: [{ id: ACCOUNT, email: 'admin@example.test', role: 'admin', status: 'active', displayName: 'Synthetic administrator' }] };
}
test('team access review reads the real capability matrix and never exposes a management tool', async t => {
  const f = await harness(t, incoming => authOr(incoming, team()));
  await f.initialize(); const reply = await f.tool('collect_admin_team_access');
  assert.deepEqual(reply.result.structuredContent.data.permissionsByRole.staff, ['users.read']);
  assert.equal(f.requests[1].url.pathname, '/api/admin/team');
  assert.equal((await f.tool('collect_admin_invite_staff')).error.code, -32602);
  assert.equal(f.requests.every(r => r.method === 'GET'), true);
});

test('Staff team denial and a principal change withhold access-review data', async t => {
  let mode = 'staff';
  const f = await harness(t, (incoming, count) => {
    if (!incoming.url.pathname.endsWith('/auth/session')) return team();
    if (mode === 'staff') return session(['overview.read'], 'staff');
    const value = session(); if (count > 2) value.user.principalId = RESOURCE; return value;
  }); await f.initialize();
  assert.equal(safeCode(await f.tool('collect_admin_team_access')), 'permission_denied');
  mode = 'changed'; const result = await f.tool('collect_admin_team_access');
  assert.equal(safeCode(result), 'session_unavailable');
  assert.equal(JSON.stringify(result).includes('Synthetic administrator'), false);
});

test('oversized team results and a cross-actor reconciliation response fail without truncation', async t => {
  let mode = 'team';
  const f = await harness(t, incoming => {
    if (incoming.url.pathname.endsWith('/auth/session')) return undefined;
    if (mode === 'team') return { ...team(), members: Array.from({ length: 201 }, () => team().members[0]) };
    return { ...MARKER, resource_type: 'reconciliations', resource: { id: RESOURCE }, current_actor_id: RESOURCE, current_principal_id: PRINCIPAL, related: {} };
  }); await f.initialize();
  assert.equal(safeCode(await f.tool('collect_admin_team_access')), 'service_unavailable');
  mode = 'actor'; assert.equal(safeCode(await f.tool('collect_admin_get_reconciliation', { transaction_id: RESOURCE })), 'service_unavailable');
});

test('financial integer strings remain exact while unsafe or fractional numeric money is withheld', async t => {
  let amount = '900719925474099312345';
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, rows: [{ id: RESOURCE, amount_rwf: amount }], total: 1 }));
  await f.initialize();
  assert.equal((await f.tool('collect_admin_list_records', { area: 'transactions' })).result.structuredContent.data.rows[0].amount_rwf, amount);
  amount = 1.25; assert.equal(safeCode(await f.tool('collect_admin_list_records', { area: 'transactions' })), 'service_unavailable');
  amount = 9_007_199_254_740_992; assert.equal(safeCode(await f.tool('collect_admin_list_records', { area: 'transactions' })), 'service_unavailable');
});


// These metadata envelopes are the exact exported real D1/router synthetic
// capture responses. Authentication below is fresh controlled loopback state.
const SMS_DTO = JSON.parse(await readFile(new URL('./fixtures/admin-sms-capture-dto-examples.json', import.meta.url), 'utf8'));
const smsSession = permissions => ({ ...SMS_DTO.session, expiresAt,
  user: { ...SMS_DTO.session.user, expiresAt, permissions: permissions ?? ['sms.read'] } });
const smsCredential = { ...credential, accountId: SMS_DTO.session.user.id,
  sessionId: SMS_DTO.session.user.sessionId, principalId: SMS_DTO.session.user.principalId };
const smsTool = (f, detail = false, args = {}) => f.tool(detail ? 'collect_admin_get_sms_receipt' : 'collect_admin_list_sms_receipts',
  detail ? { source_kind: 'capture', id: SMS_DTO.detail.resource.id, ...args } : args);
const smsAuthOr = (incoming, result) => incoming.url.pathname.endsWith('/auth/session') ? smsSession() : result;

test('the current catalogue retains exactly two capture metadata reads with explicit bounded schemas', async t => {
  const f = await harness(t); await f.initialize();
  const tools = (await f.call('tools/list')).result.tools;
  const sms = tools.filter(tool => tool.name.includes('sms'));
  assert.deepEqual(sms.map(tool => tool.name), ['collect_admin_list_sms_receipts', 'collect_admin_get_sms_receipt']);
  for (const tool of sms) {
    assert.equal(tool.annotations.readOnlyHint, true); assert.equal(tool.annotations.destructiveHint, false);
    assert.equal(tool.inputSchema.additionalProperties, false);
    assert.equal(tool.inputSchema.properties.limit.maximum, 100);
    assert.equal(tool.inputSchema.properties.offset.maximum, 2_147_483_647);
  }
  assert.deepEqual(sms[1].inputSchema.required, ['source_kind', 'id']);
  assert.deepEqual(sms[1].inputSchema.properties.source_kind.enum, ['capture']);
  assert.equal(f.requests.length, 0);
});

test('exact real D1 capture list pages pass through actual stdio with live sms.read and unchanged source time', async t => {
  const f = await harness(t, incoming => smsAuthOr(incoming,
    incoming.url.searchParams.get('offset') === '2' ? SMS_DTO.list_next : SMS_DTO.list), smsCredential);
  await f.initialize();
  const first = await smsTool(f, false, { limit: 2 });
  const next = await smsTool(f, false, { limit: 2, offset: 2 });
  assert.deepEqual(first.result.structuredContent.data, SMS_DTO.list);
  assert.deepEqual(next.result.structuredContent.data, SMS_DTO.list_next);
  assert.equal(first.result.structuredContent.read_only, true);
  assert.match(first.result.structuredContent.content_trust, /untrusted data/);
  assert.equal(next.result.structuredContent.data.rows[1].received_at, -1);
  assert.equal(first.result.structuredContent.data.rows[1].received_at, null);
  assert.equal(first.result.structuredContent.data.rows[1].received_at_device, '2026-10-15T12:00:00');
  assert.equal(f.requests.length, 6);
  for (const request of f.requests) {
    assert.equal(request.method, 'GET'); assert.equal(request.headers.origin, ADMIN_ORIGIN);
    assert.equal(request.headers.cookie, COOKIE); assert.equal(request.headers.authorization, undefined);
  }
  assert.equal(f.requests[1].url.pathname, '/api/admin/sms/receipts');
  assert.equal(f.requests[1].url.searchParams.get('source_kind'), 'capture');
});

test('exact real D1 capture detail correlates the UUID and current actor without exposing content or extraction', async t => {
  const f = await harness(t, incoming => smsAuthOr(incoming, SMS_DTO.detail), smsCredential);
  await f.initialize(); const result = await smsTool(f, true);
  assert.deepEqual(result.result.structuredContent.data, SMS_DTO.detail);
  assert.equal(f.requests[1].url.pathname, `/api/admin/sms/receipts/capture/${SMS_DTO.detail.resource.id}`);
  assert.equal(f.requests[1].url.searchParams.get('limit'), '25');
  assert.equal(result.result.structuredContent.data.can_extract, false);
  assert.equal(result.result.structuredContent.data.resource.provider_confirmation, false);
  assert.equal(result.result.structuredContent.data.resource.settlement_status, 'not_asserted');
  assert.equal(f.requests.length, 3);
});

test('SMS filter types, bounds and capture-only detail reject arbitrary paths, raw content and write arguments before HTTP', async t => {
  const f = await harness(t); await f.initialize();
  for (const args of [
    { limit: 101 }, { limit: 0 }, { limit: null }, { limit: '1' }, { offset: 2_147_483_648 }, { offset: -1 }, { offset: 0.5 },
    { search: 'x'.repeat(201) }, { search: 'a\nb' }, { search: null }, { status: 'unknown' }, { status: [] },
    { source_kind: 'raw' }, { source_kind: null }, { extraction_status: 'failed' }, { duplicates: 'yes' },
    { sort: 'created_at_asc' }, { url: 'https://attacker.test' }, { include_body: true }, { raw_sms: true },
  ]) assert.equal((await smsTool(f, false, args)).error.code, -32602);
  for (const args of [
    { id: RESOURCE }, { source_kind: 'member', id: RESOURCE }, { source_kind: 'receiver', id: RESOURCE },
    { source_kind: 'capture', id: '../content' }, { source_kind: 'capture', id: [RESOURCE] },
    { source_kind: 'capture', id: '44444444-4444-0444-0444-444444444444' },
    { source_kind: 'capture', id: RESOURCE, limit: null }, { source_kind: 'capture', id: RESOURCE, relation: 'content' },
  ]) assert.equal((await f.tool('collect_admin_get_sms_receipt', args)).error.code, -32602);
  for (const name of ['collect_admin_get_sms_body', 'collect_admin_extract_sms_receipt', 'collect_admin_retry_sms', 'collect_admin_send_sms']) {
    assert.equal((await f.tool(name)).error.code, -32602);
  }
  assert.equal(f.requests.length, 0);
});

test('SMS sends only actual typed literal filters and accepts bounded valid-empty legacy filter results', async t => {
  const f = await harness(t, incoming => smsAuthOr(incoming, { rows: [], total: 0,
    limit: Number(incoming.url.searchParams.get('limit')), offset: Number(incoming.url.searchParams.get('offset')), next_offset: null }), smsCredential);
  await f.initialize();
  for (const args of [
    { search: '  %_ "Owner"  ', limit: 100, offset: 2_147_483_647 },
    ...['received', 'under_review', 'rejected', 'linked', 'pending', 'parsed', 'parse_failed', 'needs_review', 'reviewed'].map(status => ({ status })),
    { source_kind: 'member' }, { source_kind: 'receiver' }, { extraction_status: 'parsed' },
    { extraction_status: 'needs_review' }, { duplicates: 'all' }, { duplicates: 'conflicting' },
  ]) {
    const result = await smsTool(f, false, args); assert.equal(result.result.isError, undefined);
    assert.deepEqual(result.result.structuredContent.data.rows, []);
  }
  const request = f.requests[1];
  assert.equal(request.url.searchParams.get('search'), '%_ "Owner"');
  assert.equal(request.url.searchParams.get('limit'), '100');
  assert.equal(request.url.searchParams.get('offset'), '2147483647');
  assert.deepEqual([...request.url.searchParams.keys()].sort(), ['duplicates', 'extraction_status', 'limit', 'offset', 'search', 'source_kind', 'status']);
  assert.equal(f.requests.every(request => request.method === 'GET'), true);
});

test('actual sms.read is required independently of Owner, Admin, Staff and unrelated notifications grants', async t => {
  let role = 'owner';
  const f = await harness(t, incoming => incoming.url.pathname.endsWith('/auth/session')
    ? { ...smsSession(['users.read', 'notifications.read', 'assisted_sms.read']), user: {
      ...smsSession(['users.read', 'notifications.read', 'assisted_sms.read']).user, role } } : SMS_DTO.list, smsCredential);
  await f.initialize();
  for (role of ['owner', 'admin', 'staff']) {
    assert.equal(safeCode(await smsTool(f)), 'permission_denied');
    assert.equal(safeCode(await smsTool(f, true)), 'permission_denied');
  }
  assert.equal(f.requests.length, 6);
  assert.equal(f.requests.every(request => request.url.pathname.endsWith('/auth/session')), true);
});

test('SMS permission revocation after dispatch withholds exact capture metadata', async t => {
  const f = await harness(t, (incoming, count) => incoming.url.pathname.endsWith('/auth/session')
    ? smsSession(count > 1 ? [] : ['sms.read']) : SMS_DTO.detail, smsCredential);
  await f.initialize();
  const result = await smsTool(f, true);
  assert.equal(safeCode(result), 'session_unavailable');
  assert.equal(JSON.stringify(result).includes(SMS_DTO.detail.resource.source_sha256), false);
  assert.equal(f.requests.length, 3); assert.equal(f.requests.every(request => request.method === 'GET'), true);
});

test('SMS metadata projection withholds arbitrary source body, storage, command and credential additions', async t => {
  const extra = { body: 'must-withhold-source-body', content: 'must-withhold-source-body', storage_locator: 'must-withhold-source-body',
    can_send: true, password: 'must-withhold-source-body', extract_url: 'must-withhold-source-body' };
  const f = await harness(t, incoming => smsAuthOr(incoming, incoming.url.pathname.endsWith('/receipts')
    ? { ...SMS_DTO.list, ...extra, rows: SMS_DTO.list.rows.map(row => ({ ...row, ...extra })) }
    : { ...SMS_DTO.detail, ...extra, resource: { ...SMS_DTO.detail.resource, ...extra }, related: {
      ...SMS_DTO.detail.related, content: { ...extra } } }), smsCredential);
  await f.initialize();
  const listed = await smsTool(f, false, { limit: 2 }), detail = await smsTool(f, true);
  assert.deepEqual(listed.result.structuredContent.data, SMS_DTO.list);
  assert.deepEqual(detail.result.structuredContent.data, SMS_DTO.detail);
  assert.equal(JSON.stringify([listed, detail]).includes('must-withhold-source-body'), false);
  assert.equal(f.requests.filter(request => !request.url.pathname.endsWith('/auth/session')).length, 2);
});

test('malformed SMS pages, source facts and cross-actor or cross-UUID details fail closed', async t => {
  let value = SMS_DTO.list;
  const f = await harness(t, incoming => smsAuthOr(incoming, value), smsCredential); await f.initialize();
  for (value of [
    { ...SMS_DTO.list, offset: 1 }, { ...SMS_DTO.list, total: 4.5 }, { ...SMS_DTO.list, next_offset: null },
    { ...SMS_DTO.list, rows: [SMS_DTO.list.rows[0], SMS_DTO.list.rows[0]] },
    ...[
      { source_kind: 'member' }, { id: [SMS_DTO.detail.resource.id] }, { user_id: null },
      { version: 2 }, { provider_confirmation: true }, { payer_name: 'invented extracted payer' },
      { received_at: 1.25 }, { received_at_device: undefined }, { received_at_device: 'x'.repeat(65) },
      { created_at: 9_007_199_254_740_992 }, { source_sha256: 'bad' },
    ].map(change => ({ ...SMS_DTO.list, rows: [{ ...SMS_DTO.list.rows[0], ...change }, SMS_DTO.list.rows[1]] })),
  ]) assert.equal(safeCode(await smsTool(f, false, { limit: 2 })), 'service_unavailable');
  for (value of [
    { ...SMS_DTO.detail, current_actor_id: ACCOUNT }, { ...SMS_DTO.detail, can_extract: true },
    { ...SMS_DTO.detail, resource: { ...SMS_DTO.detail.resource, id: RESOURCE } },
    { ...SMS_DTO.detail, related: { duplicate_references: { ...SMS_DTO.detail.related.duplicate_references, rows: [{ id: RESOURCE }] } } },
  ]) assert.equal(safeCode(await smsTool(f, true)), 'service_unavailable');
  value = SMS_DTO.list;
  assert.equal(safeCode(await smsTool(f, false, { limit: 2, source_kind: 'member' })), 'service_unavailable');
});

test('SMS upstream errors and raw HTML are safe errors with no content fetch or retry', async t => {
  let status = 404;
  const f = await harness(t, incoming => incoming.url.pathname.endsWith('/auth/session') ? smsSession()
    : status === 'html' ? { raw: '<html>private-source-diagnostic</html>', headers: { 'content-type': 'text/html' } }
      : { status, data: { error: 'private-source-diagnostic' } }, smsCredential);
  await f.initialize();
  for (status of [403, 404, 429, 503, 'html']) {
    const result = await smsTool(f, true);
    assert.equal(safeCode(result), status === 403 ? 'permission_denied' : status === 404 ? 'record_unavailable' : status === 429 ? 'rate_limited' : 'service_unavailable');
    assert.equal(JSON.stringify(result).includes('private-source-diagnostic'), false);
  }
  assert.equal(f.requests.filter(request => !request.url.pathname.endsWith('/auth/session')).length, 5);
  assert.equal(f.requests.every(request => request.method === 'GET'), true);
});


test('SMS source-time projection preserves explicit offsets, leap dates and signed whole seconds', async t => {
  let pair;
  const f = await harness(t, incoming => smsAuthOr(incoming, { ...SMS_DTO.detail,
    resource: { ...SMS_DTO.detail.resource, received_at_device: pair[0], received_at: pair[1] } }), smsCredential);
  await f.initialize();
  for (pair of [
    ['2026-10-05T08:25:00+02:00', 1791181500], ['2026-10-05T06:25:00Z', 1791181500],
    ['1970-01-01T00:00:00Z', 0], ['1969-12-31T23:59:59.999999999Z', -1],
    ['0000-01-01T00:00:00Z', -62167219200], ['2000-02-29T00:00:00Z', 951782400],
    ['1970-01-01T00:00:00+23:59', -86340], ['1970-01-01T00:00:00-23:59', 86340],
  ]) {
    const result = (await smsTool(f, true)).result.structuredContent.data.resource;
    assert.equal(result.received_at_device, pair[0]); assert.equal(result.received_at, pair[1]);
    pair = [pair[0], pair[1] + 1];
    assert.equal(safeCode(await smsTool(f, true)), 'service_unavailable');
  }
});

test('SMS opaque, absent and invalid source-time text stays exact and never acquires an invented epoch', async t => {
  let source, epoch = null;
  const f = await harness(t, incoming => smsAuthOr(incoming, { ...SMS_DTO.detail,
    resource: { ...SMS_DTO.detail.resource, received_at_device: source, received_at: epoch } }), smsCredential);
  await f.initialize();
  for (source of [null, '2026-10-05', '2026-10-05T08:25:00', 'not a timestamp', 'untrusted\nsource\u0000text',
    '2026-02-31T08:25:00Z', '1900-02-29T00:00:00Z', '2026-00-01T00:00:00Z', '2026-01-00T00:00:00Z',
    '2026-10-05T24:00:00Z', '2026-10-05T08:25:60Z', '2026-10-05T08:25:00+24:00',
    '2026-10-05T08:25:00+02:60', '2026-10-05T08:25:00.1234567890Z']) {
    epoch = null;
    const result = (await smsTool(f, true)).result.structuredContent.data.resource;
    assert.equal(result.received_at_device, source); assert.equal(result.received_at, null);
    epoch = 1791181500;
    assert.equal(safeCode(await smsTool(f, true)), 'service_unavailable');
  }
});

test('SMS source-time shape and server creation validity fail closed in both list and detail', async t => {
  let change = {}, detail = false;
  const f = await harness(t, incoming => smsAuthOr(incoming, detail
    ? { ...SMS_DTO.detail, resource: { ...SMS_DTO.detail.resource, ...change } }
    : { ...SMS_DTO.list, rows: [{ ...SMS_DTO.list.rows[0], ...change }, SMS_DTO.list.rows[1]] }), smsCredential);
  await f.initialize();
  for (detail of [false, true]) for (change of [
    { received_at_device: '', received_at: null }, { received_at_device: 1791181500 },
    { received_at: null }, { received_at: SMS_DTO.detail.resource.received_at + 1 },
    { received_at_device: null }, { created_at: 0 }, { created_at: -1 },
  ]) assert.equal(safeCode(await smsTool(f, detail, detail ? {} : { limit: 2 })), 'service_unavailable');
});


test('stdio request recovery accepts a canonical membership composite without replaying it', async t => {
  const membership = { ...retainedReceipt(), resource_type: 'memberships', resource_id: `${RESOURCE}/${ACCOUNT}` };
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, status: 'succeeded', request_id: membership.request_id, receipt: membership }));
  await f.initialize(); const reply = await f.tool('collect_admin_get_request_status', { idempotency_key: KEY });
  assert.equal(reply.result.structuredContent.data.receipt.resource_id, membership.resource_id);
  assert.equal(reply.result.structuredContent.data.recovery.automatic_retry, false);
  assert.equal(reply.result.structuredContent.data.recovery.write_permitted, false);
  assert.equal(f.requests.every(r => r.method === 'GET'), true);
});

test('stdio membership history accepts the pair and rejects a single or malformed pair', async t => {
  let resourceId = `${RESOURCE}/${ACCOUNT}`;
  const f = await harness(t, incoming => authOr(incoming, { ...MARKER, total: 1, rows: [{ id: canonicalRequestId(PRINCIPAL, KEY), idempotency_key: KEY,
    scope: 'memberships.post', status: 'succeeded', receipt: { ...retainedReceipt(), resource_type: 'memberships', resource_id: resourceId } }] }));
  await f.initialize(); assert.equal((await f.tool('collect_admin_list_requests', { limit: 1 })).result.structuredContent.data.rows[0].receipt.resource_id, resourceId);
  for (resourceId of [RESOURCE, `${RESOURCE}/${ACCOUNT}/${RESOURCE}`, [RESOURCE, ACCOUNT]]) assert.equal(safeCode(await f.tool('collect_admin_list_requests', { limit: 1 })), 'service_unavailable');
  assert.equal(f.requests.every(r => r.method === 'GET'), true);
});

test('stdio cross-operator audit reads the guarded cookie collection with numeric cursor and audit.read',async t=>{
 const f=await harness(t,incoming=>incoming.url.pathname.endsWith('/auth/session')?session(['audit.read']):{
  contract_version:1,scope:'cross_operator_audit_metadata',source:'domain',actor_reference:'canonical_principal',limit:1,next_cursor:{before_id:'9223372036854775806'},rows:[{id:'9223372036854775806',actor_id:RESOURCE,action:'sms.raw.revealed',entity_type:'sms_receipt',entity_id:RESOURCE,request_id:null,created_at:new Date().toISOString()}],details_included:false,checked_at:new Date().toISOString()});
 await f.initialize();const reply=await f.tool('collect_admin_audit',{limit:1,actor_id:RESOURCE,cursor:{before_id:'9223372036854775807'}});
 assert.equal(reply.result.isError,undefined);assert.equal(reply.result.structuredContent.data.rows[0].actor_id,RESOURCE);assert.equal(f.requests[1].url.pathname,'/api/admin/oversight/audit/domain');assert.equal(f.requests[1].headers.cookie,COOKIE);assert.equal(f.requests[1].url.searchParams.get('before_id'),'9223372036854775807');
});

test('stdio health and diagnostics preserve actual aggregate meanings and reject extra sensitive response fields',async t=>{
 const {healthFixture,diagnosticFixture}=await import('./oversight-fixture.mjs');let poisoned=false;
 const f=await harness(t,incoming=>incoming.url.pathname.endsWith('/auth/session')?session(['system_health.read']):incoming.url.pathname.endsWith('/health')?healthFixture():{...diagnosticFixture(),...(poisoned?{raw_error:'secret-not-returned'}:{})});
 await f.initialize();const health=await f.tool('collect_admin_health',{expected_source_revision:'a'.repeat(64)});assert.equal(health.result.structuredContent.data.source_matches,true);assert.equal(health.result.structuredContent.data.queues.assisted_sms.automatic_retry,false);
 const diagnostics=await f.tool('collect_admin_diagnostics');assert.equal(diagnostics.result.structuredContent.data.groups.length,1);poisoned=true;
 const denied=await f.tool('collect_admin_diagnostics');assert.equal(denied.result.isError,true);assert.equal(JSON.stringify(denied).includes('secret-not-returned'),false);
});

test('stdio oversight never substitutes a role or another read grant and withholds changed-grant data',async t=>{
 const {diagnosticFixture}=await import('./oversight-fixture.mjs');
 const f=await harness(t,(incoming,n)=>incoming.url.pathname.endsWith('/auth/session')?session(n===1?['system_health.read']:[]):diagnosticFixture());
 await f.initialize();const revoked=await f.tool('collect_admin_diagnostics');assert.equal(revoked.result.isError,true);assert.equal(JSON.stringify(revoked).includes('frameworkFailure'),false);
 const before=f.requests.length,denied=await f.tool('collect_admin_audit');assert.equal(safeCode(denied),'permission_denied');assert.equal(f.requests.length,before+1);
});
