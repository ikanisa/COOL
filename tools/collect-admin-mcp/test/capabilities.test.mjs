import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, realpath, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { ADMIN_ORIGIN, saveCredential } from '../src/config.mjs';
import { AdminApi, parseSession } from '../src/api.mjs';
import { callTool } from '../src/tools.mjs';

const ACCOUNT = '11111111-1111-4111-8111-111111111111';
const SESSION = '22222222-2222-4222-8222-222222222222';
const PRINCIPAL = '33333333-3333-4333-8333-333333333333';
const RESOURCE = '44444444-4444-4444-8444-444444444444';
const expiresAt = new Date(Date.now() + 3_600_000).toISOString();
const marker = { contract_version: 2, model: 'canonical_evidence_ledger' };
const baseline = await readFile(new URL('../../../supabase/migrations/20261020134444_collect_curated_platform_baseline.sql', import.meta.url), 'utf8');
const permissionsByRole = Object.fromEntries(['owner', 'admin', 'staff'].map(role => [role,
  [...baseline.matchAll(/INSERT INTO app\.admin_account_role_capabilities\(role,permission\) VALUES\('(owner|admin|staff)','([^']+)'\);/g)]
    .filter(match => match[1] === role).map(match => match[2]),
]));
const session = (permissions = ['admin_users.read', 'users.read', 'auth.mfa.enroll'], role = 'admin') => ({
  user: { id: ACCOUNT, sessionId: SESSION, principalId: PRINCIPAL, email: 'admin@example.test', role,
    permissions, assuranceLevel: 2, mfaAt: null, financialModel: 'canonical_evidence_ledger' }, expiresAt,
});
const team = () => ({ currentEmail: 'admin@example.test', canManage: false, permissionsByRole: structuredClone(permissionsByRole),
  members: [{ id: ACCOUNT, email: 'admin@example.test', role: 'admin', status: 'active' }] });
const malformed = [null, 7, {}, '', 'users', '.users.read', 'users..read', 'users.read.',
  'auth.mfa.enroll.extra', 'Users.read', 'users.read-write', 'users.*', 'users.read\n',
  'users.read\u0000', `users.${'r'.repeat(123)}`];

async function fixture(t, respond) {
  const directory = await mkdtemp(join(await realpath(tmpdir()), 'collect-mcp-capabilities-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const config = { origin: ADMIN_ORIGIN, credentialFile: join(directory, 'session.json') };
  await saveCredential(config, { version: 1, origin: ADMIN_ORIGIN, cookie: `__Host-collect_admin=${'a'.repeat(64)}`,
    accountId: ACCOUNT, sessionId: SESSION, principalId: PRINCIPAL, expiresAt });
  const requests = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    assert.equal(url.origin, ADMIN_ORIGIN);
    assert.equal(options.method, 'GET');
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.Authorization, undefined);
    assert.equal(options.headers.Cookie, `__Host-collect_admin=${'a'.repeat(64)}`);
    requests.push(url.pathname);
    return Response.json(await respond(url.pathname, requests));
  });
  return { api: new AdminApi(config), requests };
}

test('all three current baseline role matrices parse, including canonical nested grants', () => {
  assert.ok(permissionsByRole.staff.includes('auth.mfa.enroll'));
  assert.ok(permissionsByRole.admin.includes('payments.evidence.read'));
  for (const [role, permissions] of Object.entries(permissionsByRole)) {
    assert.ok(permissions.length > 0);
    const value = parseSession(session(permissions, role));
    assert.equal(value.role, role);
    assert.deepEqual(value.permissions, [...new Set(permissions)].sort());
  }
});

test('session and team reads accept the same actual nested capability matrix with independent cookie authority', async t => {
  const f = await fixture(t, path => path.endsWith('/auth/session') ? session(permissionsByRole.admin) : team());
  const result = await callTool(f.api, 'collect_admin_team_access');
  for (const role of ['owner', 'admin', 'staff']) {
    assert.deepEqual(result.data.permissionsByRole[role], permissionsByRole[role]);
  }
  assert.equal(result.read_only, true);
  assert.deepEqual(f.requests, ['/api/admin/auth/session', '/api/admin/team', '/api/admin/auth/session']);
});

test('malformed or oversized capability names fail closed in both session and team DTOs', async t => {
  let bad;
  const f = await fixture(t, path => path.endsWith('/auth/session') ? session() :
    { ...team(), permissionsByRole: { ...permissionsByRole, staff: [bad] } });
  for (const value of malformed) {
    assert.throws(() => parseSession(session([value])), { code: 'service_unavailable' });
    bad = value;
    await assert.rejects(() => callTool(f.api, 'collect_admin_team_access'), { code: 'service_unavailable' });
  }
  assert.equal(f.requests.filter(path => path.endsWith('/team')).length, malformed.length);
});

test('nested grant support preserves exact required permissions and does not infer rights from role or prefixes', async t => {
  const f = await fixture(t, () => session(['users.read_extra', 'auth.mfa.enroll'], 'owner'));
  await assert.rejects(() => callTool(f.api, 'collect_admin_list_records', { area: 'users' }), { code: 'permission_denied' });
  assert.deepEqual(f.requests, ['/api/admin/auth/session']);
});

test('a nested capability change after the read withholds the result even when the required grant remains', async t => {
  let sessionReads = 0;
  const f = await fixture(t, path => path.endsWith('/auth/session') ?
    session(++sessionReads === 1 ? ['users.read', 'auth.mfa.enroll'] : ['users.read']) :
    { ...marker, rows: [{ id: RESOURCE, name: 'withhold-after-authority-change' }], total: 1 });
  await assert.rejects(() => callTool(f.api, 'collect_admin_list_records', { area: 'users' }), { code: 'session_unavailable' });
  assert.equal(f.requests.length, 3);
});

test('malformed current authority stops before a record read and unknown roles remain rejected', async t => {
  const f = await fixture(t, () => session(['users.read', 'auth.mfa.enroll.extra']));
  await assert.rejects(() => callTool(f.api, 'collect_admin_list_records', { area: 'users' }), { code: 'service_unavailable' });
  assert.deepEqual(f.requests, ['/api/admin/auth/session']);
  assert.throws(() => parseSession(session(['users.read'], 'root')), { code: 'service_unavailable' });
  assert.throws(() => parseSession(session(Array(257).fill('users.read'))), { code: 'service_unavailable' });
});
