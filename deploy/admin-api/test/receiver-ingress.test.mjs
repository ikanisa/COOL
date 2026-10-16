import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign, createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { digest, randomToken } from '../src/security.mjs';
import { handleReceiverIngress } from '../src/receiver-ingress.mjs';

const origin = 'https://admin.collect.ikanisa.com', root = fileURLToPath(new URL('..', import.meta.url));
const cert = 'a'.repeat(64), app = 'app.cool.mobile.gateway', reason = 'Reviewed this receiver capture account and device.', uuid = () => crypto.randomUUID(), now = () => Math.floor(Date.now() / 1000);
const policy = JSON.stringify([{ app_id: app, signing_certificate_sha256: cert }]);
let mf, db, bucket, owner, admin, staff;
const q = (sql, ...values) => db.prepare(sql).bind(...values), run = (sql, ...values) => q(sql, ...values).run(), first = (sql, ...values) => q(sql, ...values).first();
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const env = overrides => ({ ADMIN_ORIGIN: origin, GATEWAY_ALLOWED_IDENTITIES: policy, ADMIN_DB: db, RECEIPT_PAYLOADS: bucket, ...overrides });
function pair() { const keys = generateKeyPairSync('ec', { namedCurve: 'prime256v1' }), spki = keys.publicKey.export({ type: 'spki', format: 'der' }); return { ...keys, installation_id: uuid(), public_key_spki_base64: spki.toString('base64'), key_sha256: hash(spki) }; }
async function actor(role) {
  const id = uuid(), token = randomToken(), at = now(), tokenHash = await digest(token);
  await run("INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(?,?,?,'active','test-only',?,?)", id, role === 'owner' ? 'info@ikanisa.com' : `${id}@example.com`, role, at, at);
  await run('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,1,?,?)', tokenHash, uuid(), id, at, at + 3600);
  return { id, role, status: 'active', auth_version: 1, token_hash: tokenHash, cookie: `__Host-collect_admin=${token}`, permissions: ['gateway.read', ...(role === 'staff' ? [] : ['gateway.manage'])] };
}
async function api(path, method = 'GET', data = null, user = owner, key = uuid(), headers = {}) {
  const response = await mf.dispatchFetch(`${origin}/api/admin/gateway/${path}`, { method, headers: { Origin: origin, 'Content-Type': 'application/json', 'Idempotency-Key': key, ...(user ? { Cookie: user.cookie } : {}), ...headers }, ...(data === null ? {} : { body: JSON.stringify({ reason, ...data }) }) });
  return { status: response.status, body: await response.json() };
}
async function ok(...args) { const result = await api(...args); assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body; }
async function fixture({ grant = true } = {}) {
  const key = pair(), enrolled = await ok('devices', 'POST', { label: 'Test receiver device', app_id: app, installation_id: key.installation_id, public_key_spki_base64: key.public_key_spki_base64, key_sha256: key.key_sha256, signing_certificate_sha256: cert });
  await ok(`devices/${enrolled.resource_id}/activate`, 'POST', { expected_version: 1, expected_key_sha256: key.key_sha256, expected_signing_certificate_sha256: cert });
  const group = uuid(), payee = uuid(), at = now();
  await run("INSERT INTO collect_groups(id,slug,title,collection_type,status,created_by_admin_id,created_at,updated_at) VALUES(?,?,'Receiver Group','ikimina','active',?,?,?)", group, `receiver-${group}`, owner.id, at, at);
  await run("INSERT INTO collect_payees(id,group_id,label,network,momo_number_or_code,created_by_admin_id,creation_reason,created_at) VALUES(?,?,'Recorded Receiver','mtn_momo','0788123456',?,?,?)", payee, group, owner.id, reason, at);
  const value = { key, device: enrolled.resource_id, group, payee };
  value.grantBody = { device_id: value.device, expected_device_version: 2, payee_id: payee, expected_payee_version: 1 };
  if (grant) value.grant = (await ok('receiver-grants', 'POST', value.grantBody)).resource_id;
  return value;
}
function envelope(f, overrides = {}) { return { contract_version: 1, action: 'capture_receipt', device_id: f.device, request_id: uuid(), issued_at: new Date().toISOString(), payload: { installation_id: f.key.installation_id, client_sms_id: uuid(), raw_sender: 'MTN MoMo', raw_body: 'You have received 1,000 RWF from TEST PAYER (***321). Transaction Id: TEST-RECEIVER.\nYour balance is 2,000 RWF.', received_at: new Date(Date.now() - 1000).toISOString() }, ...overrides }; }
function signed(f, value, { raw = null, headers = {}, url = `${origin}/api/gateway/receiver-receipts`, signingKey = f.key } = {}) {
  const bytes = raw === null ? Buffer.from(JSON.stringify(value)) : Buffer.from(raw);
  return new Request(url, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=utf-8', 'X-Collect-Gateway-Key-Id': f.key.key_sha256, 'X-Collect-Gateway-Signature': sign('sha256', bytes, signingKey.privateKey).toString('base64'), ...headers }, body: bytes });
}
async function send(f, value, options) { const request = signed(f, value, options), response = await mf.dispatchFetch(request.url, { method: request.method, headers: Object.fromEntries(request.headers), body: await request.arrayBuffer() }); return { status: response.status, body: await response.json() }; }
async function captureOk(f, value = envelope(f)) { const result = await send(f, value); assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body; }
const objectKey = (f, value) => `receiver/v1/${f.grant}/${f.device}/${value.payload.client_sms_id}.json`;
before(async () => {
  const bundle = await build({ entryPoints: [`${root}/src/worker.mjs`], bundle: true, write: false, format: 'esm', platform: 'browser', target: 'es2022' });
  mf = new Miniflare(convertV4MiniflareOptions({ modules: true, script: bundle.outputFiles[0].text, compatibilityDate: '2026-10-04', bindings: { ADMIN_ORIGIN: origin, GATEWAY_ALLOWED_IDENTITIES: policy }, d1Databases: ['ADMIN_DB'], r2Buckets: ['RECEIPT_PAYLOADS', 'MEMBER_MEDIA'] }));
  db = await mf.getD1Database('ADMIN_DB'); bucket = await mf.getR2Bucket('RECEIPT_PAYLOADS');
  for (const name of ['0001_admin_accounts.sql', '0002_collect_core.sql', '0003_posted_verification_guard.sql', '0004_operating_actions.sql', '0005_member_cloudflare.sql', '0006_gateway_cloudflare.sql', '0007_email_only_dispatch.sql', '0008_admin_people.sql', '0009_admin_reconciliation.sql', '0010_admin_sms_facts.sql', '0011_admin_transaction_sms_lineage.sql', '0012_gateway_receiver_ingress.sql']) {
    const sql = await readFile(new URL(`../migrations/${name}`, import.meta.url), 'utf8');
    const split = spawnSync(process.execPath, ['-e', "const w=require('wrangler');process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(require('node:fs').readFileSync(0,'utf8'))));"], { cwd: root, input: sql, encoding: 'utf8', timeout: 15000 });
    assert.equal(split.status, 0, split.stderr); await db.batch(JSON.parse(split.stdout).map(sql => db.prepare(sql)));
  }
  owner = await actor('owner'); admin = await actor('admin'); staff = await actor('staff');
});
after(async () => { await mf?.dispose(); });

test('receiver grant creation is Admin/Owner only and requires active current device/payee versions', async () => {
  const f = await fixture({ grant: false });
  assert.equal((await api('receiver-grants', 'POST', f.grantBody, null)).status, 401);
  assert.equal((await api('receiver-grants', 'POST', f.grantBody, staff)).status, 403);
  assert.equal((await api('receiver-grants', 'POST', { ...f.grantBody, expected_device_version: 1 })).status, 409);
  assert.equal((await api('receiver-grants', 'POST', { ...f.grantBody, expected_payee_version: 2 })).status, 409);
  assert.equal((await api('receiver-grants', 'POST', f.grantBody, owner, uuid(), { Origin: 'https://untrusted.invalid' })).status, 403);
  const result = await ok('receiver-grants', 'POST', f.grantBody, admin); assert.equal(result.version, 1);
  assert.equal((await api('receiver-grants', 'POST', f.grantBody)).status, 409);
  const detail = await ok(`receiver-grants/${result.resource_id}`, 'GET', null, staff);
  assert.equal(detail.resource.device_label, 'Test receiver device'); assert.equal(detail.resource.payee_momo_number_or_code, '0788123456'); assert.equal(detail.can_manage, false);
  assert.equal(detail.resource.send_authority, false); assert.equal(detail.resource.financial_authority, false);
});
test('concurrent Admin keys replay one audited grant and actor-scoped recovery rejects changed intent', async () => {
  const f = await fixture({ grant: false }), key = uuid();
  const both = await Promise.all([api('receiver-grants', 'POST', f.grantBody, owner, key), api('receiver-grants', 'POST', f.grantBody, owner, key)]);
  assert.ok(both.every(result => result.status === 200), JSON.stringify(both)); assert.deepEqual(both[0].body, both[1].body);
  assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_receiver_grants WHERE device_id=?', f.device)).n, 1);
  assert.equal((await first('SELECT count(*) AS n FROM collect_operations_audit WHERE operation_request_id=?', both[0].body.request_id)).n, 1);
  assert.equal((await api('receiver-grants', 'POST', { ...f.grantBody, reason: 'Different reason for the same requested binding.' }, owner, key)).status, 409);
  assert.deepEqual(await ok(`receiver-requests/${key}`), { found: true, receipt: both[0].body });
  assert.deepEqual(await ok(`receiver-requests/${key}`, 'GET', null, admin), { found: false });
  assert.deepEqual(await ok('receiver-requests/not-yet-known'), { found: false });
  const expired = await actor('admin'); await run('UPDATE admin_users SET auth_version=2 WHERE id=?', expired.id);
  assert.equal((await api('receiver-grants', 'POST', f.grantBody, expired)).status, 401);
});
test('grant and revocation audit failures roll back state, while successful immutable revocation is recoverable', async () => {
  const f = await fixture({ grant: false }), key = uuid();
  await run("CREATE TRIGGER test_receiver_audit_failure BEFORE INSERT ON collect_operations_audit WHEN NEW.action IN ('gateway.receiver.grant','gateway.receiver.revoke') BEGIN SELECT RAISE(ABORT,'test audit constraint'); END");
  assert.equal((await api('receiver-grants', 'POST', f.grantBody, owner, key)).status, 409);
  assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_receiver_grants WHERE device_id=?', f.device)).n, 0);
  assert.equal((await first('SELECT count(*) AS n FROM collect_operation_requests WHERE idempotency_key=?', key)).n, 0);
  await run('DROP TRIGGER test_receiver_audit_failure');
  f.grant = (await ok('receiver-grants', 'POST', f.grantBody, owner, key)).resource_id;
  await run("CREATE TRIGGER test_receiver_revoke_failure BEFORE INSERT ON collect_operations_audit WHEN NEW.action='gateway.receiver.revoke' BEGIN SELECT RAISE(ABORT,'test audit constraint'); END");
  const revokeKey = uuid(); assert.equal((await api(`receiver-grants/${f.grant}/revoke`, 'POST', { expected_version: 1 }, owner, revokeKey)).status, 409);
  assert.equal((await first('SELECT status FROM collect_gateway_receiver_grants WHERE id=?', f.grant)).status, 'active');
  await run('DROP TRIGGER test_receiver_revoke_failure');
  assert.equal((await api(`receiver-grants/${f.grant}/revoke`, 'POST', { expected_version: 2 })).status, 409);
  const receipt = await ok(`receiver-grants/${f.grant}/revoke`, 'POST', { expected_version: 1 }, owner, revokeKey);
  assert.deepEqual(await ok(`receiver-grants/${f.grant}/revoke`, 'POST', { expected_version: 1 }, owner, revokeKey), receipt);
  const revoked = await ok(`receiver-grants/${f.grant}`); assert.equal(revoked.resource.status, 'revoked'); assert.equal(revoked.resource.capture_authority, false);
  await assert.rejects(run('UPDATE collect_gateway_receiver_grants SET payee_id=? WHERE id=?', uuid(), f.grant), /immutable/);
  await assert.rejects(run('DELETE FROM collect_gateway_receiver_grants WHERE id=?', f.grant), /cannot be deleted/);
  assert.equal((await send(f, envelope(f))).status, 403);
});
test('signed receiver capture binds only grant payee and preserves canonical source plus private exact request/signature', async () => {
  const f = await fixture(), value = envelope(f), request = signed(f, value), signature = request.headers.get('X-Collect-Gateway-Signature'), raw = Buffer.from(await request.arrayBuffer());
  const response = await mf.dispatchFetch(request.url, { method: 'POST', headers: Object.fromEntries(request.headers), body: raw }); assert.equal(response.status, 200); const receipt = await response.json();
  const canonical = JSON.stringify({ raw_body: value.payload.raw_body, raw_sender: value.payload.raw_sender });
  assert.equal(await (await bucket.get(objectKey(f, value))).text(), canonical); assert.equal(receipt.result.payload_sha256, hash(canonical));
  const retained = await first('SELECT * FROM collect_gateway_receiver_requests WHERE device_id=? AND request_id=?', f.device, value.request_id);
  assert.equal(retained.signed_request_base64, raw.toString('base64')); assert.equal(retained.signature_base64, signature); assert.equal(retained.request_sha256, hash(raw));
  const source = await first('SELECT * FROM collect_receipt_ingress WHERE id=?', receipt.result.ingress_id); assert.equal(source.payee_id, f.payee); assert.equal(source.parse_status, 'pending'); assert.equal(source.transaction_id, null);
  assert.equal(source.source_key, `gateway:${f.grant}:${f.device}`); assert.equal(source.external_message_id, value.payload.client_sms_id);
  assert.equal(receipt.result.provider_confirmation, false); assert.equal(receipt.result.send_authority, false); assert.equal(receipt.result.financial_authority, false);
  const detail = await ok(`receiver-grants/${f.grant}`), listed = JSON.stringify(detail);
  for (const secret of ['signed_request_base64', 'signature_base64', 'raw_sender', 'raw_body', 'payload_object_key']) assert.ok(!listed.includes(secret));
  assert.equal(detail.related_total, 1); assert.equal(detail.related.captures[0].ingress_id, source.id);
  for (const table of ['collect_transactions', 'collect_payment_allocations', 'collect_journals']) assert.equal((await first(`SELECT count(*) AS n FROM ${table}`)).n, 0);
});
test('exact-byte replay and concurrent replay return the original receipt; changed byte formatting conflicts', async () => {
  const f = await fixture(), value = envelope(f), both = await Promise.all([send(f, value), send(f, value)]);
  assert.ok(both.every(result => result.status === 200), JSON.stringify(both)); assert.deepEqual(both[0].body, both[1].body);
  const again = await captureOk(f, value); assert.deepEqual(again, both[0].body);
  assert.equal((await send(f, value, { raw: ` ${JSON.stringify(value)}` })).status, 409);
  assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_receiver_requests WHERE device_id=?', f.device)).n, 1);
  assert.equal((await first('SELECT count(*) AS n FROM collect_receipt_ingress WHERE payee_id=?', f.payee)).n, 1);
});
test('stable SMS UUID deduplicates new request IDs while content or received-time changes cannot reroute source evidence', async () => {
  const f = await fixture(), value = envelope(f), original = await captureOk(f, value), second = await captureOk(f, { ...value, request_id: uuid() });
  assert.equal(second.result.ingress_id, original.result.ingress_id); assert.notEqual(second.result.receipt_id, original.result.receipt_id);
  assert.equal((await send(f, { ...value, request_id: uuid(), payload: { ...value.payload, raw_body: 'A different retained SMS body' } })).status, 409);
  assert.equal((await send(f, { ...value, request_id: uuid(), payload: { ...value.payload, received_at: new Date(Date.now() - 60000).toISOString() } })).status, 409);
  assert.equal((await first('SELECT count(*) AS n FROM collect_receipt_ingress WHERE payee_id=?', f.payee)).n, 1);
  assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_receiver_requests WHERE device_id=?', f.device)).n, 2);
});
test('signatures, installation, shape, UTF8, time, policy and origin fences fail before retaining source', async () => {
  const f = await fixture(), value = envelope(f);
  assert.equal((await send(f, value, { signingKey: pair() })).status, 401);
  assert.equal((await send(f, { ...value, payload: { ...value.payload, installation_id: uuid() } })).status, 401);
  assert.equal((await send(f, { ...value, payee_id: f.payee })).status, 400);
  assert.equal((await send(f, { ...value, payload: { ...value.payload, payee_id: f.payee } })).status, 400);
  assert.equal((await send(f, { ...value, action: 'dispatch_grant' })).status, 400);
  assert.equal((await send(f, value, { raw: JSON.stringify(value).replace('"contract_version":1', '"contract_version":1,"contract_version":1') })).status, 400);
  assert.equal((await send(f, value, { raw: Buffer.from([0xff]) })).status, 400);
  assert.equal((await send(f, value, { raw: Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(JSON.stringify(value))]) })).status, 400);
  assert.equal((await send(f, { ...value, issued_at: new Date(Date.now() - 180000).toISOString() })).status, 400);
  assert.equal((await send(f, { ...value, payload: { ...value.payload, received_at: new Date(Date.now() + 60000).toISOString() } })).status, 400);
  assert.equal((await send(f, value, { headers: { Origin: 'https://untrusted.invalid' } })).status, 403);
  assert.equal((await send(f, value, { raw: ' '.repeat(131073) })).status, 413);
  await assert.rejects(handleReceiverIngress(signed(f, value), env({ GATEWAY_ALLOWED_IDENTITIES: '[]' })), error => error.status === 503 && error.code === 'gateway_identity_policy_unavailable');
  await assert.rejects(handleReceiverIngress(signed(f, value), env({ GATEWAY_ALLOWED_IDENTITIES: JSON.stringify([{ app_id: app, signing_certificate_sha256: 'b'.repeat(64) }]) })), error => error.status === 403);
  assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_receiver_requests WHERE device_id=?', f.device)).n, 0);
});
test('no capture grant, inactive payee/group or revoked device confers no receiver acceptance', async () => {
  const missing = await fixture({ grant: false }); assert.equal((await send(missing, envelope(missing))).status, 403);
  const inactive = await fixture(); await run("UPDATE collect_payees SET status='inactive',version=2 WHERE id=?", inactive.payee); assert.equal((await send(inactive, envelope(inactive))).status, 403);
  const group = await fixture(); await run("UPDATE collect_groups SET status='archived',version=2 WHERE id=?", group.group); assert.equal((await send(group, envelope(group))).status, 403);
  const revoked = await fixture(); await run("UPDATE collect_gateway_devices SET state='revoked',version=3,revoked_at=?,revoked_by_admin_id=? WHERE id=?", now(), owner.id, revoked.device); assert.equal((await send(revoked, envelope(revoked))).status, 403);
});
test('device or capture-grant revocation racing the atomic batch leaves no ingress/request acceptance', async () => {
  for (const revokeDevice of [false, true]) {
    const f = await fixture(), value = envelope(f); let hit = false;
    const wrapped = { prepare: sql => db.prepare(sql), batch: async statements => {
      if (!hit && statements.length > 4) { hit = true;
        if (revokeDevice) await run("UPDATE collect_gateway_devices SET state='revoked',version=3,revoked_at=?,revoked_by_admin_id=? WHERE id=?", now(), owner.id, f.device);
        else await ok(`receiver-grants/${f.grant}/revoke`, 'POST', { expected_version: 1 });
      } return db.batch(statements);
    } };
    await assert.rejects(handleReceiverIngress(signed(f, value), env({ ADMIN_DB: wrapped })), error => error.status === 403 && error.code === (revokeDevice ? 'gateway_device_inactive' : 'receiver_grant_inactive'));
    assert.ok(hit); assert.equal((await first('SELECT count(*) AS n FROM collect_receipt_ingress WHERE payee_id=?', f.payee)).n, 0); assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_receiver_requests WHERE device_id=?', f.device)).n, 0);
    assert.equal((await send(f, value)).status, 403);
    assert.ok(await bucket.get(objectKey(f, value)), 'Private orphan is preserved, never accepted or overwritten.');
  }
});
test('D1 receipt retention failure rolls back ingress and retry reconciles the exact private orphan', async () => {
  const f = await fixture(), value = envelope(f);
  await run("CREATE TRIGGER test_receiver_retention_failure BEFORE INSERT ON collect_gateway_receiver_requests BEGIN SELECT RAISE(ABORT,'test retention constraint'); END");
  assert.equal((await send(f, value)).status, 409); assert.equal((await first('SELECT count(*) AS n FROM collect_receipt_ingress WHERE payee_id=?', f.payee)).n, 0);
  await run('DROP TRIGGER test_receiver_retention_failure');
  const stored = await (await bucket.get(objectKey(f, value))).text(), result = await captureOk(f, value); assert.equal(await (await bucket.get(objectKey(f, value))).text(), stored);
  assert.equal(result.result.payload_sha256, hash(stored));
  await assert.rejects(run('UPDATE collect_gateway_receiver_requests SET signature_base64=? WHERE id=?', 'not-a-signature', result.result.receipt_id), /immutable/);
  await assert.rejects(run('DELETE FROM collect_gateway_receiver_requests WHERE id=?', result.result.receipt_id), /cannot be deleted/);
});
test('lost successful D1 response returns unknown then exact signed retry recovers original receipt without duplicate', async () => {
  const f = await fixture(), value = envelope(f); let lost = false;
  const wrapped = { prepare: sql => db.prepare(sql), batch: async statements => { const rows = await db.batch(statements); if (!lost && statements.length > 4) { lost = true; throw new Error('simulated lost D1 response'); } return rows; } };
  await assert.rejects(handleReceiverIngress(signed(f, value), env({ ADMIN_DB: wrapped })), error => error.status === 503 && error.code === 'receiver_outcome_unknown');
  const saved = await first('SELECT response_json FROM collect_gateway_receiver_requests WHERE device_id=? AND request_id=?', f.device, value.request_id), result = await captureOk(f, value); assert.deepEqual(result, JSON.parse(saved.response_json));
  assert.equal((await first('SELECT count(*) AS n FROM collect_receipt_ingress WHERE payee_id=?', f.payee)).n, 1);
  assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_receiver_requests WHERE device_id=?', f.device)).n, 1);
});
test('private R2 missing/failing storage fails closed; lost conditional write is recoverable only by exact readback', async () => {
  const f = await fixture(), value = envelope(f);
  await assert.rejects(handleReceiverIngress(signed(f, value), env({ RECEIPT_PAYLOADS: undefined })), error => error.status === 503 && error.code === 'receiver_storage_unavailable');
  await assert.rejects(handleReceiverIngress(signed(f, value), env({ RECEIPT_PAYLOADS: { get: async () => null, put: async () => { throw new Error('not written'); } } })), error => error.status === 503 && error.code === 'receiver_storage_unknown');
  assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_receiver_requests WHERE device_id=?', f.device)).n, 0);
  let lost = false; const wrapped = { get: (...args) => bucket.get(...args), put: async (...args) => { assert.equal(args[2].onlyIf.etagDoesNotMatch, '*'); const value = await bucket.put(...args); if (!lost) { lost = true; throw new Error('lost conditional storage response'); } return value; } };
  const result = await handleReceiverIngress(signed(f, value), env({ RECEIPT_PAYLOADS: wrapped })); assert.equal(result.result.metadata_accepted, true); assert.ok(lost);
});
test('conflicting orphan or a concurrent conditional winner is never overwritten or accepted', async () => {
  const f = await fixture(), value = envelope(f), key = objectKey(f, value), conflicting = JSON.stringify({ raw_body: 'Conflicting orphan bytes', raw_sender: 'MTN MoMo' });
  await bucket.put(key, conflicting); assert.equal((await send(f, value)).status, 409); assert.equal(await (await bucket.get(key)).text(), conflicting);
  const race = envelope(f), raceKey = objectKey(f, race); let inserted = false;
  const wrapped = { get: (...args) => bucket.get(...args), put: async (...args) => { if (!inserted) { inserted = true; await bucket.put(args[0], conflicting); } return bucket.put(...args); } };
  await assert.rejects(handleReceiverIngress(signed(f, race), env({ RECEIPT_PAYLOADS: wrapped })), error => error.status === 409 && error.code === 'receiver_storage_conflict');
  assert.equal(await (await bucket.get(raceKey)).text(), conflicting); assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_receiver_requests WHERE device_id=?', f.device)).n, 0);
});
test('safe capture detail is paged beyond first rows and rate fence blocks further signed requests', async () => {
  const f = await fixture(); await captureOk(f); await captureOk(f); await captureOk(f);
  const firstPage = await ok(`receiver-grants/${f.grant}?limit=2&offset=0`, 'GET', null, staff), secondPage = await ok(`receiver-grants/${f.grant}?limit=2&offset=2`, 'GET', null, staff);
  assert.equal(firstPage.related_total, 3); assert.equal(firstPage.related.captures.length, 2); assert.equal(secondPage.related.captures.length, 1);
  assert.ok(!firstPage.related.captures.some(row => row.id === secondPage.related.captures[0].id));
  assert.equal((await api('receiver-grants?limit=101')).status, 400); assert.equal((await api(`receiver-grants/${f.grant}?status=active`)).status, 400);
  assert.equal((await ok(`receiver-grants?device_id=${f.device}&payee_id=${f.payee}&status=active&limit=1`)).total, 1);
  await run('INSERT INTO admin_rate_limits(key_hash,bucket,count,expires_at) VALUES(?,?,120,?) ON CONFLICT(key_hash,bucket) DO UPDATE SET count=120', await digest(`gateway:device:${f.device}`), Math.floor(now() / 60), now() + 120);
  assert.equal((await send(f, envelope(f))).status, 429);
  assert.equal((await first('SELECT count(*) AS n FROM collect_mutation_guards')).n, 0);
});

test('lost Admin grant/revoke acknowledgments recover actor receipts without duplicating grant or audit', async () => {
  const f = await fixture({ grant: false });
  for (const revoke of [false, true]) {
    const key = uuid(), path = revoke ? `receiver-grants/${f.grant}/revoke` : 'receiver-grants';
    const data = { reason, ...(revoke ? { expected_version: 1 } : f.grantBody) }; let lost = false;
    const wrapped = { prepare: sql => db.prepare(sql), batch: async statements => { const result = await db.batch(statements); if (!lost && statements.length > 4) { lost = true; throw new Error('lost Admin mutation response'); } return result; } };
    const request = new Request(`${origin}/api/admin/gateway/${path}`, { method: 'POST', headers: { Origin: origin, 'Content-Type': 'application/json', 'Idempotency-Key': key }, body: JSON.stringify(data) });
    await assert.rejects(handleReceiverIngress(request, env({ ADMIN_DB: wrapped }), owner), error => error.status === 503 && error.code === 'receiver_outcome_unknown');
    const recovered = await ok(`receiver-requests/${key}`); assert.equal(recovered.found, true); assert.deepEqual(await ok(path, 'POST', data, owner, key), recovered.receipt);
    if (!revoke) f.grant = recovered.receipt.resource_id;
    assert.equal((await first('SELECT count(*) AS n FROM collect_operations_audit WHERE operation_request_id=?', recovered.receipt.request_id)).n, 1);
  }
  assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_receiver_grants WHERE device_id=?', f.device)).n, 1);
  assert.equal((await first('SELECT status FROM collect_gateway_receiver_grants WHERE id=?', f.grant)).status, 'revoked');
});

test('capture grant activation respects signing policy and atomic fresh Admin authority', async () => {
  const f = await fixture({ grant: false }), user = await actor('admin');
  const request = key => new Request(`${origin}/api/admin/gateway/receiver-grants`, { method: 'POST', headers: { Origin: origin, 'Content-Type': 'application/json', 'Idempotency-Key': key }, body: JSON.stringify({ ...f.grantBody, reason }) });
  await assert.rejects(handleReceiverIngress(request(uuid()), env({ GATEWAY_ALLOWED_IDENTITIES: '[]' }), owner), error => error.status === 503 && error.code === 'gateway_identity_policy_unavailable');
  let intercepted = false; const key = uuid(), wrapped = { prepare: sql => db.prepare(sql), batch: async statements => {
    if (!intercepted && statements.length > 4) { intercepted = true; await run("UPDATE admin_users SET role='staff',auth_version=2 WHERE id=?", user.id); }
    return db.batch(statements);
  } };
  await assert.rejects(handleReceiverIngress(request(key), env({ ADMIN_DB: wrapped }), user), error => error.status === 401 && error.code === 'unauthenticated');
  assert.ok(intercepted); assert.equal((await first('SELECT count(*) AS n FROM collect_gateway_receiver_grants WHERE device_id=?', f.device)).n, 0);
  assert.equal((await first('SELECT count(*) AS n FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', user.id, key)).n, 0);
  assert.equal((await first('SELECT count(*) AS n FROM collect_mutation_guards')).n, 0);
});
