import { fileURLToPath } from 'node:url';
import test, { after, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { passwordHash, passwordMatches, PASSWORD_ITERATIONS, digest } from '../src/security.mjs';
import worker from '../src/worker.mjs';

const ORIGIN = 'https://admin.collect.ikanisa.com';
const PASSWORD = 'A strong collect password 2026';
const NEW_PASSWORD = 'Another strong collect password 2026';
let mf, db, hashedPassword, ownerId, ownerCookie;
let mailFails = false;
const mail = [];
let nextIp = 0;
const ip = () => `192.0.2.${++nextIp}`;

async function request(path, { method = 'POST', data = {}, cookie, origin = ORIGIN, address = ip(), headers = {} } = {}) {
  const response = await mf.dispatchFetch(`${ORIGIN}/api/admin${path}`, {
    method, headers: { Origin: origin, 'Content-Type': 'application/json', 'CF-Connecting-IP': address, ...(cookie ? { Cookie: cookie } : {}), ...headers },
    ...(method === 'GET' ? {} : { body: JSON.stringify(data) }),
  });
  return { response, status: response.status, body: await response.json(), cookie: response.headers.get('Set-Cookie')?.split(';')[0] };
}
async function member(email, role = 'staff', status = 'active') {
  const id = crypto.randomUUID(); const time = Math.floor(Date.now() / 1000);
  await db.prepare('INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(?,?,?,?,?,?,?)')
    .bind(id, email, role, status, status === 'active' ? hashedPassword : null, time, time).run();
  return id;
}
async function login(email = 'info@ikanisa.com', password = PASSWORD) {
  const result = await request('/auth/login', { data: { email, password } });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  return result;
}
function setupToken(message) {
  const link = message.text.match(/https:\/\/\S+\/\#\/admin\/setup\?\S+/)?.[0];
  assert.ok(link);
  assert.equal(new URL(link).search, '', 'Token stays out of URL query sent to server');
  return new URLSearchParams(new URL(link).hash.split('?')[1]).get('token');
}
async function settleMail(expected) {
  for (let attempt = 0; attempt < 50 && mail.length < expected; attempt++) await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(mail.length, expected);
  // Provider response is followed by two awaited D1 writes.
  for (let attempt = 0; attempt < 50; attempt++) {
    const pending = await db.prepare("SELECT count(*) AS count FROM admin_email_events WHERE status='pending'").first();
    if (!pending.count) return;
    await new Promise(resolve => setTimeout(resolve, 20));
  }
  assert.fail('Email metadata did not settle');
}

before(async () => {
  const bundle = await build({
    stdin: { contents: `import worker from './src/worker.mjs';
      export default { ...worker, fetch(request, env, ctx) {
        return worker.fetch(request, { ...env, EMAIL: { send: async message => {
          const r = await env.TEST_EMAIL.fetch('https://mail.invalid', { method: 'POST', body: JSON.stringify(message) });
          if (!r.ok) throw new Error('Simulated provider refusal'); return r.json();
        } } }, ctx);
      } };`, resolveDir: fileURLToPath(new URL('..', import.meta.url)) },
    bundle: true, write: false, format: 'esm', target: 'es2022', platform: 'browser',
  });
  mf = new Miniflare(convertV4MiniflareOptions({
    modules: true, script: bundle.outputFiles[0].text, compatibilityDate: '2026-10-04',
    bindings: { ADMIN_ORIGIN: ORIGIN, ENVIRONMENT: 'test' }, d1Databases: ['ADMIN_DB'],
    serviceBindings: { TEST_EMAIL: async req => {
      const message = await req.json();
      if (mailFails) return new Response('refused', { status: 503 });
      mail.push(message);
      return Response.json({ messageId: crypto.randomUUID() });
    } },
  }));
  db = await mf.getD1Database('ADMIN_DB');
  for (const name of ['0001_admin_accounts.sql','0002_collect_core.sql','0003_posted_verification_guard.sql','0004_operating_actions.sql','0005_member_cloudflare.sql','0006_gateway_cloudflare.sql','0007_email_only_dispatch.sql','0008_admin_people.sql','0009_admin_reconciliation.sql','0010_admin_sms_facts.sql','0011_admin_transaction_sms_lineage.sql','0012_gateway_receiver_ingress.sql']) {
    const sql = await readFile(new URL(`../migrations/${name}`, import.meta.url), 'utf8');
    const split = spawnSync(process.execPath, ['-e', "const w=require('wrangler');process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(require('node:fs').readFileSync(0,'utf8'))));"], {
      cwd: fileURLToPath(new URL('..', import.meta.url)), input: sql, encoding: 'utf8',
    });
    assert.equal(split.status, 0, split.stderr);
    await db.batch(JSON.parse(split.stdout).map(query => db.prepare(query)));
  }
  hashedPassword = await passwordHash(PASSWORD);
  ownerId = await member('info@ikanisa.com', 'owner');
  ownerCookie = (await login()).cookie;
});
after(async () => { await mf?.dispose(); });

test('portable password work factor matches native PBKDF2 and rejects wrong passwords', async () => {
  const salt = 'ab'.repeat(32);
  const stored = await passwordHash(PASSWORD, salt);
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(PASSWORD), 'PBKDF2', false, ['deriveBits']);
  const result = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: Buffer.from(salt, 'hex'), iterations: PASSWORD_ITERATIONS }, key, 256);
  assert.equal(stored.split('$')[3], Buffer.from(result).toString('hex'));
  assert.equal(await passwordMatches(NEW_PASSWORD, stored), false);
});

test('session cookie is secure, expires, and never exposes its bearer token', async () => {
  const result = await login();
  const header = result.response.headers.get('Set-Cookie');
  for (const marker of ['__Host-collect_admin=', 'HttpOnly', 'Secure', 'SameSite=Strict', 'Path=/', 'Max-Age=28800']) assert.ok(header.includes(marker));
  assert.notEqual(result.body.user.sessionId, result.cookie.split('=')[1]);
  assert.ok(result.body.user.permissions.includes('admin_users.manage'));
  const token = result.cookie.split('=')[1];
  assert.ok(!JSON.stringify(result.body).includes(token));
  const sessionRow = await db.prepare('SELECT * FROM admin_sessions WHERE token_hash=?').bind(await digest(token)).first();
  assert.ok(sessionRow);
  assert.equal((await request('/auth/session', { method: 'GET', cookie: result.cookie })).body.user.email, 'info@ikanisa.com');
  await db.prepare('UPDATE admin_sessions SET expires_at=1 WHERE token_hash=?').bind(await digest(token)).run();
  assert.equal((await request('/auth/session', { method: 'GET', cookie: result.cookie })).body.user, null);
});

test('cross-origin, missing-origin, client-selected role and invalid JSON fields are rejected', async () => {
  assert.equal((await request('/auth/login', { origin: 'https://attacker.invalid', data: { email: 'info@ikanisa.com', password: PASSWORD } })).status, 403);
  const missing = await mf.dispatchFetch(`${ORIGIN}/api/admin/auth/login`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
  assert.equal(missing.status, 403);
  assert.equal((await request('/auth/login', { data: { email: 'info@ikanisa.com', password: PASSWORD, role: 'owner' } })).status, 400);
  assert.equal((await request('/auth/bootstrap', { data: {} })).status, 404);
  assert.equal((await request('/team/invite', { cookie: ownerCookie, data: { email: 'role@example.com', role: 'owner' } })).status, 400);
});

test('owner invitation arrives from correct sender; pending user cannot sign in; only hash is stored', async () => {
  const beforeMail = mail.length;
  const invite = await request('/team/invite', { cookie: ownerCookie, data: { email: 'invite@example.com', role: 'admin' } });
  assert.equal(invite.status, 201);
  await settleMail(beforeMail + 1);
  assert.equal(mail.at(-1).from.email, 'info@ikanisa.com');
  assert.equal(mail.at(-1).from.name, 'Collect');
  assert.equal(mail.at(-1).subject, 'Your invitation to Collect');
  assert.match(mail.at(-1).html, />Set your password<\/a>/);
  assert.ok(!mail.at(-1).html.includes('Collect Admin'));
  const token = setupToken(mail.at(-1));
  assert.ok(!JSON.stringify(invite.body).includes(token));
  const stored = await db.prepare('SELECT * FROM admin_challenges WHERE token_hash=?').bind(await digest(token)).first();
  assert.ok(stored);
  assert.equal(stored.delivery_status, 'accepted');
  assert.equal((await request('/auth/login', { data: { email: 'invite@example.com', password: PASSWORD } })).status, 401);
  const complete = await request('/auth/complete-password', { data: { token, password: PASSWORD, invite: true } });
  assert.equal(complete.status, 200);
  assert.equal((await request('/auth/complete-password', { data: { token, password: NEW_PASSWORD, invite: true } })).status, 400);
  const signedIn = await login('invite@example.com');
  assert.equal(signedIn.body.user.role, 'admin');
  assert.deepEqual(signedIn.body.user.permissions, ['overview.read', 'account.manage', 'collections.read', 'users.read', 'receivers.read', 'payments.read', 'ledger.read', 'email.read', 'gateway.read', 'collections.create', 'reconciliations.read', 'reconciliations.propose', 'sms.read', 'collections.manage', 'users.manage', 'receivers.manage', 'payments.manage', 'ledger.manage', 'email.manage', 'gateway.manage', 'reconciliations.review', 'sms.extract', 'sms.reveal', 'admin_users.read']);
  const access = await request('/team', { method: 'GET', cookie: signedIn.cookie });
  assert.equal(access.status, 200);
  assert.equal(access.body.canManage, false);
  assert.deepEqual(access.body.permissionsByRole.admin, signedIn.body.user.permissions);
  assert.ok(access.body.members.every(value => /^[0-9]{6}$/.test(value.publicId)));
  assert.ok(!access.body.permissionsByRole.staff.includes('reconciliations.review'));
  assert.ok(!access.body.permissionsByRole.staff.includes('sms.reveal'));
  assert.ok(access.body.permissionsByRole.staff.includes('collections.create'));
  assert.equal((await request('/team/invite', { cookie: signedIn.cookie, data: { email: 'unauthorized@example.com', role: 'staff' } })).status, 403);
});

test('provider failure stays pending, invalidates its link and records failure without false success', async () => {
  mailFails = true;
  try {
    const result = await request('/team/invite', { cookie: ownerCookie, data: { email: 'failure@example.com', role: 'staff' } });
    assert.equal(result.status, 503);
    assert.equal(result.body.error.code, 'email_unavailable');
    const user = await db.prepare('SELECT * FROM admin_users WHERE email=?').bind('failure@example.com').first();
    assert.equal(user.status, 'invited');
    const token = await db.prepare('SELECT * FROM admin_challenges WHERE user_id=?').bind(user.id).first();
    assert.equal(token.delivery_status, 'failed');
    assert.ok(token.used_at);
    const team = await request('/team', { method: 'GET', cookie: ownerCookie });
    assert.equal(team.body.members.find(x => x.email === user.email).emailStatus, 'failed');
  } finally { mailFails = false; }
});

test('resend replaces older invitation, wrong-kind and expired links fail', async () => {
  await request('/team/invite', { cookie: ownerCookie, data: { email: 'resend@example.com', role: 'staff' } });
  const firstToken = setupToken(mail.at(-1));
  const user = await db.prepare('SELECT * FROM admin_users WHERE email=?').bind('resend@example.com').first();
  assert.equal((await request(`/team/${user.id}/resend`, { cookie: ownerCookie })).status, 200);
  const token = setupToken(mail.at(-1));
  assert.notEqual(token, firstToken);
  assert.equal((await request('/auth/complete-password', { data: { token: firstToken, password: PASSWORD, invite: true } })).status, 400);
  assert.equal((await request('/auth/complete-password', { data: { token, password: PASSWORD, invite: false } })).status, 400);
  await db.prepare('UPDATE admin_challenges SET expires_at=1 WHERE token_hash=?').bind(await digest(token)).run();
  assert.equal((await request('/auth/complete-password', { data: { token, password: PASSWORD, invite: true } })).status, 400);
});

test('forgot-password stays enumeration resistant and reset revokes all sessions', async () => {
  await member('reset@example.com');
  const oldSession = await login('reset@example.com');
  const beforeMail = mail.length;
  const existing = await request('/auth/forgot-password', { data: { email: 'reset@example.com' } });
  const missing = await request('/auth/forgot-password', { data: { email: 'unknown@example.com' } });
  assert.equal(existing.status, 202); assert.deepEqual(existing.body, missing.body);
  await settleMail(beforeMail + 1);
  const token = setupToken(mail.at(-1));
  assert.equal((await request('/auth/complete-password', { data: { token, password: NEW_PASSWORD, invite: false } })).status, 200);
  assert.equal((await request('/auth/session', { method: 'GET', cookie: oldSession.cookie })).body.user, null);
  assert.equal((await request('/auth/login', { data: { email: 'reset@example.com', password: PASSWORD } })).status, 401);
  await login('reset@example.com', NEW_PASSWORD);
});

test('concurrent acceptance allows one winner; access revoke fences session and outstanding links', async () => {
  await request('/team/invite', { cookie: ownerCookie, data: { email: 'race@example.com', role: 'staff' } });
  const token = setupToken(mail.at(-1));
  const results = await Promise.all([1, 2].map(() => request('/auth/complete-password', { data: { token, password: PASSWORD, invite: true } })));
  assert.deepEqual(results.map(x => x.status).sort(), [200, 400]);
  const accepted = await db.prepare('SELECT id FROM admin_users WHERE email=?').bind('race@example.com').first();
  assert.equal((await db.prepare("SELECT count(*) AS n FROM admin_account_audit WHERE subject_id=? AND action='invitation_accepted'").bind(accepted.id).first()).n, 1);
  const signedIn = await login('race@example.com');
  const beforeMail = mail.length;
  await request('/auth/forgot-password', { data: { email: 'race@example.com' } });
  await settleMail(beforeMail + 1);
  const resetToken = setupToken(mail.at(-1));
  assert.equal((await request(`/team/${signedIn.body.user.id}/revoke`, { cookie: ownerCookie })).status, 200);
  assert.equal((await request('/auth/session', { method: 'GET', cookie: signedIn.cookie })).body.user, null);
  assert.equal((await request('/auth/complete-password', { data: { token: resetToken, password: NEW_PASSWORD, invite: false } })).status, 400);
  assert.equal((await request(`/team/${ownerId}/revoke`, { cookie: ownerCookie })).status, 409);
  assert.equal((await request('/team/invite', { cookie: ownerCookie, data: { email: 'race@example.com', role: 'admin' } })).status, 201);
  const reinvited = await db.prepare('SELECT status,role,accepted_at,password_hash FROM admin_users WHERE id=?').bind(signedIn.body.user.id).first();
  assert.deepEqual(reinvited, { status: 'invited', role: 'admin', accepted_at: null, password_hash: null });
  assert.equal((await request('/auth/session', { method: 'GET', cookie: signedIn.cookie })).body.user, null);
});

test('password change requires current password and revokes all old sessions; logout revokes current', async () => {
  await member('change@example.com');
  const first = await login('change@example.com'); const second = await login('change@example.com');
  assert.equal((await request('/auth/change-password', { cookie: first.cookie, data: { currentPassword: 'incorrect', newPassword: NEW_PASSWORD } })).status, 400);
  assert.equal((await request('/auth/change-password', { cookie: first.cookie, data: { currentPassword: PASSWORD, newPassword: NEW_PASSWORD } })).status, 200);
  for (const result of [first, second]) assert.equal((await request('/auth/session', { method: 'GET', cookie: result.cookie })).body.user, null);
  const fresh = await login('change@example.com', NEW_PASSWORD);
  assert.equal((await request('/auth/logout', { cookie: fresh.cookie })).status, 200);
  assert.equal((await request('/auth/session', { method: 'GET', cookie: fresh.cookie })).body.user, null);
});

const securityFlows = ['change', 'reset', 'invite'];
const securityAction = flow => flow === 'change' ? 'password_changed' : flow === 'reset' ? 'password_reset' : 'invitation_accepted';
async function securityFixture(flow) {
  const email = `security-${flow}-${crypto.randomUUID()}@example.com`;
  const id = await member(email, 'staff', flow === 'invite' ? 'invited' : 'active');
  const at = Math.floor(Date.now() / 1000);
  await db.prepare('UPDATE admin_users SET challenge_version=2 WHERE id=?').bind(id).run();
  const token = crypto.randomUUID().replaceAll('-', '') + crypto.randomUUID().replaceAll('-', '');
  const older = crypto.randomUUID().replaceAll('-', '') + crypto.randomUUID().replaceAll('-', '');
  for (const [value, version] of [[older, 1], [token, 2]]) {
    await db.prepare(`INSERT INTO admin_challenges(token_hash,user_id,kind,auth_version,challenge_version,delivery_status,created_at,expires_at)
      VALUES(?,?,?,1,?,'accepted',?,?)`).bind(await digest(value), id, flow === 'invite' ? 'invite' : 'reset', version, at, at + 3600).run();
  }
  let cookie;
  for (let index = 0; index < 2; index++) {
    const secret = crypto.randomUUID().replaceAll('-', '') + crypto.randomUUID().replaceAll('-', '');
    await db.prepare('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,1,?,?)')
      .bind(await digest(secret), crypto.randomUUID(), id, at, at + 3600).run();
    cookie ??= `__Host-collect_admin=${secret}`;
  }
  return { id, email, flow, path: flow === 'change' ? '/auth/change-password' : '/auth/complete-password',
    options: { cookie, data: flow === 'change' ? { currentPassword: PASSWORD, newPassword: NEW_PASSWORD }
      : { token, password: NEW_PASSWORD, invite: flow === 'invite' } } };
}
const securitySnapshot = async id => ({
  user: await db.prepare('SELECT * FROM admin_users WHERE id=?').bind(id).first(),
  challenges: (await db.prepare('SELECT * FROM admin_challenges WHERE user_id=? ORDER BY token_hash').bind(id).all()).results,
  sessions: (await db.prepare('SELECT * FROM admin_sessions WHERE user_id=? ORDER BY token_hash').bind(id).all()).results,
  audit: (await db.prepare('SELECT * FROM admin_account_audit WHERE subject_id=? ORDER BY id').bind(id).all()).results,
  mailCount: mail.length,
});
function securityRequest(fixture) {
  return new Request(`${ORIGIN}/api/admin${fixture.path}`, { method: 'POST',
    headers: { Origin: ORIGIN, Cookie: fixture.options.cookie, 'Content-Type': 'application/json', 'CF-Connecting-IP': ip() },
    body: JSON.stringify(fixture.options.data) });
}
function assertSecurityCommit(saved, before, fixture) {
  assert.equal(saved.user.status, 'active');
  assert.equal(saved.user.auth_version, before.user.auth_version + 1);
  assert.notEqual(saved.user.password_hash, before.user.password_hash);
  assert.equal(saved.challenges.length, before.challenges.length, 'No duplicate challenges are created');
  assert.ok(saved.challenges.every(challenge => challenge.used_at !== null));
  assert.equal(saved.sessions.length, 0);
  assert.equal(saved.audit.length, 1);
  assert.equal(saved.audit[0].action, securityAction(fixture.flow));
  assert.equal(saved.audit[0].actor_id, fixture.id);
  assert.equal(saved.mailCount, before.mailCount, 'Security completion cannot send another email');
}

test('password change, reset and invitation security state roll back with a failed success audit', async () => {
  for (const flow of securityFlows) {
    const fixture = await securityFixture(flow); const before = await securitySnapshot(fixture.id);
    await db.prepare(`CREATE TRIGGER test_security_audit_failure BEFORE INSERT ON admin_account_audit
      WHEN NEW.action='${securityAction(flow)}' BEGIN SELECT RAISE(ABORT,'test security audit storage failure'); END`).run();
    try {
      const failed = await request(fixture.path, fixture.options);
      assert.equal(failed.status, 503);
      assert.equal(failed.body.error.code, 'service_unavailable');
      assert.deepEqual(await securitySnapshot(fixture.id), before, `${flow} must roll back every security change`);
    } finally { await db.prepare('DROP TRIGGER test_security_audit_failure').run(); }
    const success = await request(fixture.path, fixture.options);
    assert.equal(success.status, 200);
    assert.deepEqual(success.body, { ok: true });
    const saved = await securitySnapshot(fixture.id); assertSecurityCommit(saved, before, fixture);
    assert.equal((await request(fixture.path, fixture.options)).status, flow === 'change' ? 401 : 400);
    assert.deepEqual(await securitySnapshot(fixture.id), saved, 'Replaying the consumed authority cannot mutate state or duplicate audit');
    assert.equal((await login(fixture.email, NEW_PASSWORD)).body.user.id, fixture.id);
  }
});

test('lost security batch acknowledgement preserves one audited commit and recovers through sign-in', async () => {
  for (const flow of securityFlows) {
    const fixture = await securityFixture(flow); const before = await securitySnapshot(fixture.id);
    let committed = 0;
    const env = { ...directEnv(), ADMIN_DB: { prepare: db.prepare.bind(db), batch: async queries => {
      const result = await db.batch(queries); committed++;
      throw new Error('Test lost acknowledgement after a committed D1 security batch');
    } } };
    const unknown = await worker.fetch(securityRequest(fixture), env, {});
    assert.equal(unknown.status, 503);
    assert.equal((await unknown.json()).error.code, 'service_unavailable');
    assert.equal(committed, 1);
    const saved = await securitySnapshot(fixture.id); assertSecurityCommit(saved, before, fixture);
    assert.equal((await request(fixture.path, fixture.options)).status, flow === 'change' ? 401 : 400);
    assert.deepEqual(await securitySnapshot(fixture.id), saved, 'Lost-response retries must not repeat a credential change');
    assert.equal((await login(fixture.email, NEW_PASSWORD)).body.user.id, fixture.id, 'The chosen password provides authoritative recovery without a new challenge');
  }
});

test('a revoked credential version between eligibility and mutation cannot create a success audit', async () => {
  for (const flow of securityFlows) {
    const fixture = await securityFixture(flow); let revoked;
    const env = { ...directEnv(), ADMIN_DB: { prepare: db.prepare.bind(db), batch: async queries => {
      await db.prepare('UPDATE admin_users SET auth_version=auth_version+1 WHERE id=?').bind(fixture.id).run();
      revoked = await securitySnapshot(fixture.id);
      return db.batch(queries);
    } } };
    const response = await worker.fetch(securityRequest(fixture), env, {});
    assert.equal(response.status, flow === 'change' ? 401 : 400);
    assert.deepEqual(await securitySnapshot(fixture.id), revoked, 'A losing guarded mutation cannot consume challenges/sessions or insert an audit');
  }
});

test('durable IP throttles, request limits, staff authorization and database owner constraints', async () => {
  const address = ip();
  const results = await Promise.all(Array.from({ length: 11 }, () => request('/auth/complete-password', { address, data: { token: '0'.repeat(64), password: PASSWORD, invite: true } })));
  assert.equal(results.filter(x => x.status === 429).length, 1);
  assert.equal((await request('/auth/login', { data: { email: 'a'.repeat(5000), password: PASSWORD } })).status, 413);
  await member('staff@example.com');
  const staff = await login('staff@example.com');
  assert.equal((await request('/team', { method: 'GET', cookie: staff.cookie })).status, 403);
  assert.equal((await request(`/team/${ownerId}/revoke`, { cookie: staff.cookie })).status, 403);
  await assert.rejects(member('attacker@example.com', 'owner'), /constraint/i);
  await assert.rejects(member('info@ikanisa.com', 'staff'), /constraint/i);
});

async function ownerSession() {
  const secret = 'a' + crypto.randomUUID().replaceAll('-', '') + crypto.randomUUID().replaceAll('-', '').slice(0, 31);
  const actor = await db.prepare('SELECT auth_version FROM admin_users WHERE id=?').bind(ownerId).first();
  const at = Math.floor(Date.now() / 1000);
  await db.prepare('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,?,?,?)')
    .bind(await digest(secret), crypto.randomUUID(), ownerId, actor.auth_version, at, at + 3600).run();
  return `__Host-collect_admin=${secret}`;
}
const directEnv = () => ({ ADMIN_DB: db, ADMIN_ORIGIN: ORIGIN, ENVIRONMENT: 'test', EMAIL: { send: async message => {
  mail.push(message); return { messageId: crypto.randomUUID() };
} } });
const teamSnapshot = async subject => ({
  user: subject ? await db.prepare('SELECT * FROM admin_users WHERE id=?').bind(subject).first() : null,
  challenges: (await db.prepare('SELECT * FROM admin_challenges ORDER BY token_hash').all()).results,
  events: (await db.prepare('SELECT * FROM admin_email_events ORDER BY id').all()).results,
  audit: (await db.prepare('SELECT * FROM admin_account_audit ORDER BY id').all()).results,
  mailCount: mail.length,
});

test('paused invitation, resend and revoke requests fail after owner logout or auth-version revocation', async () => {
  for (const action of ['invite', 'resend', 'revoke']) for (const revocation of ['logout', 'auth_version']) {
    const cookie = await ownerSession();
    const email = `paused-${action}-${revocation}@example.com`;
    const target = action === 'invite' ? null : await member(email, 'staff', action === 'revoke' ? 'active' : 'invited');
    const path = action === 'invite' ? '/team/invite' : `/team/${target}/${action}`;
    const data = action === 'invite' ? { email, role: 'admin' } : {};
    let controller, entered;
    const bodyEntered = new Promise(resolve => { entered = resolve; });
    const stream = new ReadableStream({ start(value) { controller = value; } });
    const incoming = new Request(`${ORIGIN}/api/admin${path}`, { method: 'POST', duplex: 'half',
      headers: { Origin: ORIGIN, Cookie: cookie, 'Content-Type': 'application/json', 'CF-Connecting-IP': ip() }, body: stream });
    const reader = incoming.body.getReader.bind(incoming.body);
    // This callback happens inside body(), after the handler's initial session read.
    incoming.body.getReader = () => { entered(); return reader(); };
    const before = await teamSnapshot(target);
    const pending = worker.fetch(incoming, directEnv(), {});
    let timeout;
    try {
      await Promise.race([bodyEntered, new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('Handler did not read the body')), 3000); })]);
      if (revocation === 'logout') assert.equal((await request('/auth/logout', { cookie })).status, 200);
      else await db.prepare('UPDATE admin_users SET auth_version=auth_version+1 WHERE id=?').bind(ownerId).run();
    } finally {
      clearTimeout(timeout);
      controller.enqueue(new TextEncoder().encode(JSON.stringify(data))); controller.close();
    }
    const result = await pending;
    assert.equal(result.status, 401, `${action}/${revocation}: ${await result.clone().text()}`);
    assert.equal((await result.json()).error.code, 'unauthenticated');
    assert.deepEqual(await teamSnapshot(target), before, `${action}/${revocation} changed protected state`);
    if (action === 'invite') assert.equal(await db.prepare('SELECT id FROM admin_users WHERE email=?').bind(email).first(), null);
    assert.equal((await db.prepare('SELECT count(*) AS n FROM collect_mutation_guards').first()).n, 0);
  }
  ownerCookie = await ownerSession();
});

test('team state and its audit roll back together when audit persistence fails', async () => {
  for (const action of ['invite', 'resend', 'revoke']) {
    const email = `audit-${action}@example.com`;
    const target = action === 'invite' ? null : await member(email, 'staff', action === 'revoke' ? 'active' : 'invited');
    const event = action === 'invite' ? 'invitation_created' : action === 'resend' ? 'invitation_resent' : 'access_revoked';
    const path = action === 'invite' ? '/team/invite' : `/team/${target}/${action}`;
    const options = { cookie: ownerCookie, data: action === 'invite' ? { email, role: 'staff' } : {} };
    const before = await teamSnapshot(target);
    await db.prepare(`CREATE TRIGGER test_team_audit_failure BEFORE INSERT ON admin_account_audit WHEN NEW.action='${event}' BEGIN SELECT RAISE(ABORT,'test audit storage failure'); END`).run();
    try { assert.equal((await request(path, options)).status, 503); }
    finally { await db.prepare('DROP TRIGGER test_team_audit_failure').run(); }
    assert.deepEqual(await teamSnapshot(target), before);
    if (action === 'invite') assert.equal(await db.prepare('SELECT id FROM admin_users WHERE email=?').bind(email).first(), null);
    assert.equal((await request(path, options)).status, action === 'invite' ? 201 : 200);
    const saved = await db.prepare('SELECT id FROM admin_users WHERE email=?').bind(email).first();
    assert.equal((await db.prepare('SELECT count(*) AS n FROM admin_account_audit WHERE action=? AND actor_id=? AND subject_id=?').bind(event, ownerId, saved.id).first()).n, 1);
    if (action === 'invite') {
      assert.equal((await request(path, options)).status, 409);
      assert.equal((await db.prepare('SELECT count(*) AS n FROM admin_account_audit WHERE action=? AND subject_id=?').bind(event, saved.id).first()).n, 1);
    }
  }
});

test('invitation challenge issuance rechecks owner authority after the account batch commits', async () => {
  const cookie = await ownerSession(); const tokenHash = await digest(cookie.split('=')[1]);
  const email = 'challenge-fence@example.com'; const beforeMail = mail.length;
  let batches = 0;
  const env = { ...directEnv(), ADMIN_DB: { prepare: db.prepare.bind(db), batch: async queries => {
    const result = await db.batch(queries);
    if (++batches === 1) await db.prepare('DELETE FROM admin_sessions WHERE token_hash=?').bind(tokenHash).run();
    return result;
  } } };
  const result = await worker.fetch(new Request(`${ORIGIN}/api/admin/team/invite`, { method: 'POST',
    headers: { Origin: ORIGIN, Cookie: cookie, 'Content-Type': 'application/json', 'CF-Connecting-IP': ip() },
    body: JSON.stringify({ email, role: 'staff' }),
  }), env, {});
  assert.equal(result.status, 401);
  const pending = await db.prepare('SELECT * FROM admin_users WHERE email=?').bind(email).first();
  assert.equal(pending.status, 'invited');
  assert.equal((await db.prepare('SELECT count(*) AS n FROM admin_challenges WHERE user_id=?').bind(pending.id).first()).n, 0);
  assert.equal((await db.prepare('SELECT count(*) AS n FROM admin_email_events WHERE user_id=?').bind(pending.id).first()).n, 0);
  assert.equal((await db.prepare("SELECT count(*) AS n FROM admin_account_audit WHERE subject_id=? AND action='invitation_created'").bind(pending.id).first()).n, 1);
  assert.equal(mail.length, beforeMail);
});

test('team reads recheck the owner session atomically after logout, expiry or password-version change', async () => {
  for (const mode of ['logout', 'expiry', 'auth_version']) {
    const cookie = await ownerSession(); const tokenHash = await digest(cookie.split('=')[1]);
    let interrupted = false;
    const env = { ...directEnv(), ADMIN_DB: {
      batch: db.batch.bind(db),
      prepare(sql) {
        const prepared = db.prepare(sql);
        if (!sql.includes('SELECT u.*,s.public_id')) return prepared;
        return { bind(...values) { const bound = prepared.bind(...values); return { first: async () => {
          const actor = await bound.first(); interrupted = true;
          if (mode === 'logout') await db.prepare('DELETE FROM admin_sessions WHERE token_hash=?').bind(tokenHash).run();
          if (mode === 'expiry') await db.prepare('UPDATE admin_sessions SET expires_at=1 WHERE token_hash=?').bind(tokenHash).run();
          if (mode === 'auth_version') await db.prepare('UPDATE admin_users SET auth_version=auth_version+1 WHERE id=?').bind(ownerId).run();
          return actor;
        } }; } };
      },
    } };
    const result = await worker.fetch(new Request(`${ORIGIN}/api/admin/team`, { headers: { Cookie: cookie } }), env, {});
    assert.equal(interrupted, true);
    assert.equal(result.status, 401, `${mode} must not expose team rows`);
    assert.equal((await result.json()).members, undefined);
  }
  ownerCookie = await ownerSession();
});

test('bootstrapped owner activates only through inbox setup; local preview cannot emit email or print links', async () => {
  await db.prepare("UPDATE admin_users SET status='invited',password_hash=NULL,auth_version=auth_version+1 WHERE id=?").bind(ownerId).run();
  assert.equal((await request('/auth/login', { data: { email: 'info@ikanisa.com', password: PASSWORD } })).status, 401);
  const pending = []; let localSends = 0;
  const localRequest = new Request('http://localhost:8795/api/admin/auth/forgot-password', {
    method: 'POST', headers: { Origin: 'http://localhost:8795', 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'info@ikanisa.com' }),
  });
  const localResponse = await worker.fetch(localRequest, {
    ADMIN_DB: db, ADMIN_ORIGIN: 'http://localhost:8795', ENVIRONMENT: 'local',
    EMAIL: { send: () => { localSends++; throw new Error('Must not invoke local simulator'); } },
  }, { waitUntil: promise => pending.push(promise) });
  assert.equal(localResponse.status, 202);
  await Promise.all(pending);
  assert.equal(localSends, 0);
  const beforeMail = mail.length;
  await request('/auth/forgot-password', { data: { email: 'info@ikanisa.com' } });
  await settleMail(beforeMail + 1);
  assert.equal(mail.at(-1).to, 'info@ikanisa.com');
  const token = setupToken(mail.at(-1));
  assert.equal((await request('/auth/complete-password', { data: { token, password: NEW_PASSWORD, invite: true } })).status, 200);
  const activated = await login('info@ikanisa.com', NEW_PASSWORD);
  assert.equal(activated.body.user.role, 'owner');
});
