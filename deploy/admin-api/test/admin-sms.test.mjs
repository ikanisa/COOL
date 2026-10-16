import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { digest, randomToken } from '../src/security.mjs';
import { parseAdminSmsFacts, prepareTransactionPublicReference, generateTransactionPublicReference, handleAdminSms, AdminSmsError, SMS_PARSER_VERSION } from '../src/admin-sms.mjs';
import { handleGateway } from '../src/gateway.mjs';
import { TRANSACTION_SMS_FACT_JOIN_SQL,TRANSACTION_SMS_FACT_COLUMNS_SQL,transactionSourceRow } from '../src/core.mjs';
import { TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL,TRANSACTION_PUBLIC_REFERENCE_COLUMNS_SQL } from '../src/admin-sms.mjs';

const root = fileURLToPath(new URL('..', import.meta.url)), origin = 'https://admin.collect.ikanisa.com', uuid = () => crypto.randomUUID();
const at = Math.floor(Date.now() / 1000), reason = 'Reviewed the preserved SMS source evidence.';
let runtime, db, memberBucket, receiverBucket, owner, admin, staff, legacy, sequence = 400000;
const q = (query, ...values) => db.prepare(query).bind(...values), run = (query, ...values) => q(query, ...values).run(), first = (query, ...values) => q(query, ...values).first();
async function actor(role = 'admin') {
  const id = uuid(), token = randomToken(), token_hash = await digest(token);
  await run("INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(?,?,?,'active','local-test-only',?,?)", id, role === 'owner' ? 'info@ikanisa.com' : `${id}@example.com`, role, at, at);
  await run('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,1,?,?)', token_hash, uuid(), id, at, at + 3600);
  return { id, role, status: 'active', auth_version: 1, token_hash, cookie: `__Host-collect_admin=${token}`, permissions: ['sms.read', ...(role === 'staff' ? [] : ['sms.extract', 'sms.reveal'])] };
}
async function operating({ transaction = true, reference = `QA-${uuid()}`, amount = 12500, route='0041258' } = {}) {
  const f = { member: uuid(), group: uuid(), payee: uuid(), tx: uuid(), reference, amount };
  await run("INSERT INTO collect_users(id,email,status,created_at,updated_at) VALUES(?,?,'active',?,?)", f.member, `${f.member}@example.com`, at, at);
  await run("INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) VALUES(?,?,'QA member',?,?)", f.member, String(++sequence), at, at);
  await run("INSERT INTO collect_groups(id,slug,title,collection_type,status,created_by_admin_id,created_at,updated_at) VALUES(?,?,'QA receipt group','ikimina','active',?,?,?)", f.group, `qa-${f.group}`, owner.id, at, at);
  await run("INSERT INTO collect_memberships(group_id,user_id,role,status,joined_at,created_at,updated_at) VALUES(?,?,'owner','active',?,?,?)", f.group, f.member, at, at, at);
  await run("INSERT INTO collect_payees(id,group_id,label,network,momo_number_or_code,created_by_admin_id,creation_reason,created_at) VALUES(?,?,'QA receiver','mtn_momo',?,?,?,?)", f.payee, f.group, route, owner.id, reason, at);
  if (transaction) await insertTransaction(f); return f;
}
const transactionStatement = f => q("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at,recorded_by_admin_id) VALUES(?,?,?,'mtn_momo',?,?, ?,?,?)", f.tx, f.group, f.payee, f.reference, f.amount, at, at, owner.id);
const insertTransaction = f => transactionStatement(f).run();
const sms = (reference = '12345678901', amount = '12,500', extra = '') => `You have received RWF ${amount} from ALICE UMUHOZA (***456). Financial Transaction Id: ${reference}. Your new balance is RWF 50,000. at 2026-10-05 12:35:45 ${extra}`;
async function receipt(sourceKind = 'member', { f = null, body = sms(), sender = 'M-Money', bytes = null } = {}) {
  f ??= await operating({ transaction: false });
  const id = uuid(), objectKey = `qa-receipts/${id}`, raw = bytes ?? JSON.stringify({ raw_sender: sender, raw_body: body }), bodyHash = await digest(body), payloadHash = await digest(raw);
  const bucket = sourceKind === 'member' ? memberBucket : receiverBucket; await bucket.put(objectKey, raw);
  if (sourceKind === 'member') await run('INSERT INTO member_receipt_submissions(id,user_id,body_hash,raw_sender,payload_object_key,received_at,created_at) VALUES(?,?,?,?,?,?,?)', id, f.member, bodyHash, sender, objectKey, at, at);
  else await run('INSERT INTO collect_receipt_ingress(id,source_key,external_message_id,payee_id,payload_sha256,payload_object_key,received_at) VALUES(?,?,?,?,?,?,?)', id, 'qa_receiver_ingress', uuid(), f.payee, payloadHash, objectKey, at);
  return { id, sourceKind, f, objectKey, body, sender, bodyHash, payloadHash, sourceHash: sourceKind === 'member' ? bodyHash : payloadHash };
}
async function api(path = 'receipts', method = 'GET', data = null, user = owner, key = uuid(), headers = {}) {
  const response = await runtime.dispatchFetch(`${origin}/api/admin/sms/${path}`, { method, headers: { Origin: origin, ...(user ? { Cookie: user.cookie } : {}), 'Content-Type': 'application/json', 'Idempotency-Key': key, ...headers }, ...(data === null ? {} : { body: JSON.stringify({ reason, ...data }) }) });
  return { status: response.status, body: await response.json() };
}
async function ok(...args) { const result = await api(...args); assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body; }
const sourcePath = r => `receipts/${r.sourceKind}/${r.id}`;
const extract = (r, user = owner, key = uuid()) => ok(`${sourcePath(r)}/extract`, 'POST', { expected_source_sha256: r.sourceHash }, user, key);
const direct = (r, key = uuid(), reasonValue = reason) => new Request(`${origin}/api/admin/sms/${sourcePath(r)}/extract`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key }, body: JSON.stringify({ reason: reasonValue, expected_source_sha256: r.sourceHash }) });
async function migrate(name) {
  const source = await readFile(new URL(`../migrations/${name}`, import.meta.url), 'utf8'), split = spawnSync(process.execPath, ['-e', "const w=require('wrangler');process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(require('node:fs').readFileSync(0,'utf8'))));"], { cwd: root, input: source, encoding: 'utf8', timeout: 15000 });
  assert.equal(split.status, 0, split.stderr); await db.batch(JSON.parse(split.stdout).map(query => db.prepare(query)));
}
before(async () => {
  const bundle = await build({ stdin: { resolveDir: root, contents: `
    import {handleAdminSms} from './src/admin-sms.mjs'; import {digest} from './src/security.mjs';
    export default {async fetch(request,env){try{
      if(request.headers.get('Origin')!==env.ADMIN_ORIGIN)return Response.json({error:'origin_rejected'},{status:403});
      const token=(request.headers.get('Cookie')||'').split('=')[1]; const user=token?await env.ADMIN_DB.prepare("SELECT a.*,s.token_hash FROM admin_users a JOIN admin_sessions s ON s.user_id=a.id WHERE s.token_hash=? AND a.status='active' AND s.auth_version=a.auth_version AND s.expires_at>unixepoch()").bind(await digest(token)).first():null;
      if(user)user.permissions=['sms.read',...(['owner','admin'].includes(user.role)?['sms.extract','sms.reveal']:[])];
      return Response.json(await handleAdminSms(request,env,user));
    }catch(error){return Response.json({error:error.code||'unexpected',message:error.message},{status:error.status||500});}}};` }, bundle: true, write: false, format: 'esm', platform: 'browser', target: 'es2022' });
  runtime = new Miniflare(convertV4MiniflareOptions({ modules: true, script: bundle.outputFiles[0].text, compatibilityDate: '2026-10-04', bindings: { ADMIN_ORIGIN: origin }, d1Databases: ['ADMIN_DB'], r2Buckets: ['MEMBER_MEDIA', 'RECEIPT_PAYLOADS'], d1Persist: false, r2Persist: false }));
  db = await runtime.getD1Database('ADMIN_DB'); memberBucket = await runtime.getR2Bucket('MEMBER_MEDIA'); receiverBucket = await runtime.getR2Bucket('RECEIPT_PAYLOADS');
  for (const name of ['0001_admin_accounts.sql', '0002_collect_core.sql', '0003_posted_verification_guard.sql', '0004_operating_actions.sql', '0005_member_cloudflare.sql', '0006_gateway_cloudflare.sql', '0007_email_only_dispatch.sql', '0008_admin_people.sql', '0009_admin_reconciliation.sql']) await migrate(name);
  owner = await actor('owner'); admin = await actor(); staff = await actor('staff'); legacy = await operating();
  await migrate('0010_admin_sms_facts.sql');
  await migrate('0011_admin_transaction_sms_lineage.sql');
});
after(async () => { await runtime?.dispose(); });

test('strict parser preserves full/masked phone facts, names, leading-zero codes and only explicitly present timestamps/zones', () => {
  const masked = parseAdminSmsFacts('M-Money', sms('12345678901', '12,500', '+02:00 Receiver code: 0041258'));
  assert.equal(masked.payer_name, 'ALICE UMUHOZA'); assert.equal(masked.payer_phone, null); assert.equal(masked.payer_masked_phone, '***456'); assert.equal(masked.payer_last3, '456');
  assert.equal(masked.payee_momo_code, '0041258'); assert.equal(masked.momo_timestamp_local, '2026-10-05T12:35:45'); assert.equal(masked.momo_timezone_offset, '+02:00');
  assert.equal(masked.amount_rwf, 12500); assert.equal(masked.wallet_balance_rwf, 50000); assert.equal(masked.momo_transaction_reference, '12345678901');
  const full = parseAdminSmsFacts('M-Money', 'You have received 2,500 RWF from 0788123000. Transaction id: FULL-0001. Receiver number: +250788765432.');
  assert.equal(full.payer_phone, '0788123000'); assert.equal(full.payer_last3, '000'); assert.equal(full.payee_momo_number, '+250788765432'); assert.equal(full.momo_timezone_offset, null);
  const local = parseAdminSmsFacts('M-Money', sms()); assert.equal(local.momo_timestamp_local, '2026-10-05T12:35:45'); assert.equal(local.momo_timezone_offset, null); assert.equal(local.payee_momo_number, null); assert.equal(local.payee_momo_code, null);
});

test('ambiguous/fractional/overflow/reversed/promo/unknown-network source facts never invent a completed payment', () => {
  for (const amount of ['1.50', '1,50', '9,007,199,254,740,992', '0']) assert.equal(parseAdminSmsFacts('M-Money', sms('INVALID-0001', amount)).is_payment, 0);
  for (const prefix of ['Transaction reversed.', 'Transaction failed.', 'OTP verification code.', 'Payment pending.']) assert.equal(parseAdminSmsFacts('M-Money', `${prefix} ${sms()}`).is_payment, 0);
  const ambiguous = parseAdminSmsFacts('M-Money', `${sms()} You have received RWF 12,500 from 0788000000. Transaction id: SECOND-0001.`); assert.equal(ambiguous.amount_rwf, null); assert.equal(ambiguous.momo_transaction_reference, null);
  const unknown = parseAdminSmsFacts('Unrecognized', 'received RWF 500 from 0788123456. Ref: UNKNOWN-0001'); assert.equal(unknown.network, null); assert.equal(unknown.is_payment, 0);
  const malformedDate = parseAdminSmsFacts('M-Money', sms().replace('2026-10-05', '2026-02-31')); assert.equal(malformedDate.momo_timestamp_local, null);
  const outgoing = parseAdminSmsFacts('AirtelMoney', 'You have sent RWF 500 to 0732123456. Txn OUT-0001.'); assert.equal(outgoing.direction, 'outgoing'); assert.equal(outgoing.network, 'airtel_money');
  const conflictingPayers = parseAdminSmsFacts('M-Money', `${sms()} Payer number: 0788999000.`); assert.equal(conflictingPayers.payer_name, null); assert.equal(conflictingPayers.payer_phone, null); assert.equal(conflictingPayers.payer_last3, null);
  assert.equal(parseAdminSmsFacts('AirtelMoney', 'You have received RWF 500 from 0732123456. Txn AIR-0001. MoMo code: 0042.').network, 'airtel_money');
});

test('existing and future transactions always receive stable unique numeric18 references with honest unknown prefixes', async () => {
  const reference = await first('SELECT * FROM collect_transaction_public_references WHERE transaction_id=?', legacy.tx); assert.match(reference.public_reference, /^000000[0-9]{12}$/);
  assert.equal(reference.payer_last3_known, 0); assert.equal(reference.payee_last3_known, 0); assert.equal(reference.random_source, 'sqlite_prng');
  const fresh = await operating(), next = await first('SELECT * FROM collect_transaction_public_references WHERE transaction_id=?', fresh.tx); assert.match(next.public_reference, /^000000[0-9]{12}$/); assert.notEqual(reference.public_reference, next.public_reference);
  await run('UPDATE collect_transactions SET version=version+1 WHERE id=?', fresh.tx); assert.equal((await first('SELECT public_reference FROM collect_transaction_public_references WHERE transaction_id=?', fresh.tx)).public_reference, next.public_reference);
  await assert.rejects(run("UPDATE collect_transaction_public_references SET public_reference='000000123456789012' WHERE transaction_id=?", fresh.tx), /immutable/);
  await assert.rejects(run('DELETE FROM collect_transaction_public_references WHERE transaction_id=?', fresh.tx), /immutable/);
  const ids = new Set(); for (let i = 0; i < 100; i++) { const value = generateTransactionPublicReference({ payer_last3: '000', payee_last3: '258' }); assert.match(value.public_reference, /^000258[0-9]{12}$/); assert.equal(value.payer_last3_known, 1); ids.add(value.public_reference); } assert.equal(ids.size, 100);
});

test('SMS list/detail are paged actual source records with separate source provenance and no Staff plaintext leak or write authority', async () => {
  const member = await receipt(), receiver = await receipt('receiver');
  const list = await ok('receipts?limit=1', 'GET', null, staff); assert.equal(list.rows.length, 1); assert.ok(list.total >= 2); assert.equal(list.next_offset, 1);
  const row = (await ok(sourcePath(member), 'GET', null, staff)).resource; assert.equal(row.evidence_level, 'member_submitted'); assert.equal(row.extraction_status, 'not_extracted'); assert.equal(row.raw_body, undefined); assert.equal(row.payload_object_key, undefined); assert.equal(row.provider_confirmation, false);
  assert.equal((await ok(sourcePath(receiver), 'GET', null, staff)).resource.evidence_level, 'receiver_ingress_unverified');
  assert.equal((await api(`${sourcePath(member)}/extract`, 'POST', { expected_source_sha256: member.sourceHash }, staff)).status, 403);
  assert.equal((await api(`${sourcePath(member)}/content`, 'GET', null, staff, uuid(), { 'X-Collect-Review-Reason': reason })).status, 403);
  assert.equal((await api('receipts', 'GET', null, null)).status, 401);
  await run('UPDATE collect_profiles SET display_name_recorded=0 WHERE user_id=?', member.f.member);
  assert.equal((await ok(sourcePath(member), 'GET', null, staff)).resource.display_name, null);
  for (const query of ['?limit=101', '?offset=-1', '?source_kind=official', '?status=settled', '?search=x&search=y']) assert.equal((await api(`receipts${query}`)).status, 400);
});

test('bounded private R2 source extraction verifies member body/sender and receiver exact-byte hashes before durable facts', async () => {
  for (const sourceKind of ['member', 'receiver']) { const r = await receipt(sourceKind), parsed = await extract(r);
    const row = (await ok(sourcePath(r), 'GET', null, staff)).resource; assert.equal(parsed.resource_id, row.source_fact_id); assert.equal(row.parser_version, SMS_PARSER_VERSION); assert.equal(row.source_body_sha256, r.bodyHash); assert.equal(row.source_payload_sha256, r.payloadHash);
    assert.equal(row.payer_last3, '456'); assert.equal(row.payer_phone, null); assert.equal(row.timezone_known, false); assert.equal(row.payee_momo_code, null); assert.equal(row.transaction_id, null);
    assert.equal((await first(`SELECT ${sourceKind === 'member' ? 'status' : 'parse_status'} AS status FROM ${sourceKind === 'member' ? 'member_receipt_submissions' : 'collect_receipt_ingress'} WHERE id=?`, r.id)).status, sourceKind === 'member' ? 'needs_review' : 'pending');
  }
  const corrupt = await receipt(); await memberBucket.put(corrupt.objectKey, JSON.stringify({ raw_sender: corrupt.sender, raw_body: 'replaced source' })); assert.equal((await api(`${sourcePath(corrupt)}/extract`, 'POST', { expected_source_sha256: corrupt.sourceHash })).status, 503);
  const spoofSender = await receipt(); await memberBucket.put(spoofSender.objectKey, JSON.stringify({ raw_sender: 'DifferentSender', raw_body: spoofSender.body })); assert.equal((await api(`${sourcePath(spoofSender)}/extract`, 'POST', { expected_source_sha256: spoofSender.sourceHash })).status, 503);
  const receiver = await receipt('receiver'); await receiverBucket.put(receiver.objectKey, JSON.stringify({ raw_sender: receiver.sender, raw_body: receiver.body }) + '\n'); assert.equal((await api(`${sourcePath(receiver)}/extract`, 'POST', { expected_source_sha256: receiver.sourceHash })).status, 503);
  const missing = await receipt('receiver'); await receiverBucket.delete(missing.objectKey); assert.equal((await api(`${sourcePath(missing)}/extract`, 'POST', { expected_source_sha256: missing.sourceHash })).status, 503);
  const wrongDigest = await receipt(); assert.equal((await api(`${sourcePath(wrongDigest)}/extract`, 'POST', { expected_source_sha256: 'f'.repeat(64) })).status, 409);
  assert.equal((await first('SELECT count(*) AS total FROM collect_sms_facts WHERE member_submission_id IN (?,?)', corrupt.id, spoofSender.id)).total, 0);
  const failClosed = await receipt('receiver'); await assert.rejects(handleAdminSms(direct(failClosed), { ADMIN_DB: db, MEMBER_MEDIA: memberBucket }, owner), error => error.code === 'receipt_source_unavailable');
});

test('source content is returned only after durable reason audit and revocation fence', async () => {
  const r = await receipt(); assert.equal((await api(`${sourcePath(r)}/content`)).status, 400);
  const revealed = await ok(`${sourcePath(r)}/content`, 'GET', null, admin, uuid(), { 'X-Collect-Review-Reason': reason }); assert.equal(revealed.raw_body, r.body); assert.equal(revealed.provider_confirmation, false);
  assert.equal((await first("SELECT count(*) AS total FROM collect_operations_audit WHERE action='sms.source.reveal' AND subject_id=?", `${r.sourceKind}/${r.id}`)).total, 1);
  await run("CREATE TRIGGER qa_sms_reveal_audit BEFORE INSERT ON collect_operations_audit WHEN NEW.action='sms.source.reveal' BEGIN SELECT RAISE(ABORT,'QA reveal audit unavailable'); END");
  try { const result = await api(`${sourcePath(r)}/content`, 'GET', null, admin, uuid(), { 'X-Collect-Review-Reason': reason }); assert.equal(result.status, 503); assert.equal(result.body.raw_body, undefined); }
  finally { await run('DROP TRIGGER qa_sms_reveal_audit'); }
  const user = await actor(), wrapped = { prepare: query => db.prepare(query), batch: async statements => { if (statements.length === 3) await run('DELETE FROM admin_sessions WHERE token_hash=?', user.token_hash); return db.batch(statements); } };
  const request = new Request(`${origin}/api/admin/sms/${sourcePath(r)}/content`, { headers: { 'X-Collect-Review-Reason': reason } });
  await assert.rejects(handleAdminSms(request, { ADMIN_DB: wrapped, MEMBER_MEDIA: memberBucket }, user), error => error.status === 401);
});

test('extraction is deterministic across keys and concurrency, with actor receipts and no duplicate facts/financial mutations', async () => {
  const r = await receipt(), key = uuid(), before = (await first('SELECT count(*) AS total FROM collect_transactions')).total;
  const responses = await Promise.all([api(`${sourcePath(r)}/extract`, 'POST', { expected_source_sha256: r.sourceHash }, owner, key), api(`${sourcePath(r)}/extract`, 'POST', { expected_source_sha256: r.sourceHash }, owner, key)]);
  assert.ok(responses.every(result => result.status === 200), JSON.stringify(responses)); assert.deepEqual(responses[0].body, responses[1].body);
  assert.equal((await extract(r, admin)).resource_id, responses[0].body.resource_id);
  assert.equal((await first('SELECT count(*) AS total FROM collect_sms_facts WHERE member_submission_id=?', r.id)).total, 1);
  assert.equal((await first('SELECT count(*) AS total FROM collect_transactions')).total, before);
  assert.equal((await first('SELECT count(*) AS total FROM collect_payment_allocations')).total, 0);
  assert.equal((await first('SELECT count(*) AS total FROM collect_operations_audit WHERE operation_request_id=?', responses[0].body.request_id)).total, 1);
  assert.equal((await api(`${sourcePath(r)}/extract`, 'POST', { expected_source_sha256: r.sourceHash, reason: 'Different review reason.' }, owner, key)).status, 409);
  assert.deepEqual(await ok(`requests/${key}`, 'GET', null, owner), { status: 'succeeded', request_id: responses[0].body.request_id, receipt: responses[0].body }); assert.deepEqual(await ok(`requests/${key}`, 'GET', null, staff), { status: 'not_found' });
  await assert.rejects(run('UPDATE collect_sms_facts SET payer_name=? WHERE id=?', 'Changed', responses[0].body.resource_id), /immutable/);
});

test('duplicate provider references preserve each source, expose cross-record conflicts and never auto-link accounts or settle', async () => {
  const reference = `DUP-${uuid()}`, r1 = await receipt('member', { body: sms(reference, '1,000') }), r2 = await receipt('member', { body: sms(reference, '2,000') }), r3 = await receipt('receiver', { body: sms(reference, '1,000') });
  await extract(r1); await extract(r2); await extract(r3);
  const detail = await ok(`${sourcePath(r1)}?limit=1`, 'GET', null, staff); assert.equal(detail.resource.duplicate_reference_count, 2); assert.equal(detail.resource.conflicting_reference_count, 1); assert.equal(detail.related.duplicate_references.total, 2); assert.equal(detail.related.duplicate_references.next_offset, 1);
  assert.ok(detail.related.duplicate_references.rows.every(row => row.transaction_id === null && !row.provider_confirmation));
  const conflicts = await ok(`receipts?duplicates=conflicting&search=${reference}`, 'GET', null, staff); assert.equal(conflicts.total, 3);
  const f = { ...r3.f, reference, amount: 1000 }, plan = await prepareTransactionPublicReference({ ADMIN_DB: db }, { transaction_id: f.tx, payee_id: f.payee, source_fact_id: (await first('SELECT id FROM collect_sms_facts WHERE receiver_ingress_id=?', r3.id)).id });
  await assert.rejects(db.batch([...plan.statements, transactionStatement(f)]), /matched receipt evidence/); assert.equal(await first('SELECT id FROM collect_transactions WHERE id=?', f.tx), null);
});

test('cryptographic reference preinsert and new transaction commit atomically under real D1 deferred FK with explicit receiver facts', async () => {
  const f = await operating({ transaction: false, reference: `KNOWN-${uuid()}` }), r = await receipt('receiver', { f, body: sms(f.reference) }), facts = await extract(r);
  const plan = await prepareTransactionPublicReference({ ADMIN_DB: db }, { transaction_id: f.tx, payee_id: f.payee, source_fact_id: facts.resource_id });
  assert.match(plan.reference.public_reference, /^456258[0-9]{12}$/); await db.batch([...plan.statements, transactionStatement(f)]);
  const stored = await first('SELECT * FROM collect_transaction_public_references WHERE transaction_id=?', f.tx); assert.equal(stored.public_reference, plan.reference.public_reference); assert.equal(stored.source_fact_id, facts.resource_id); assert.equal(stored.random_source, 'crypto_get_random_values'); assert.equal(stored.payer_last3_known, 1); assert.equal(stored.payee_last3_known, 1);
  const referenceOnly = await prepareTransactionPublicReference({ ADMIN_DB: db }, { transaction_id: uuid(), payee_id: f.payee });
  await assert.rejects(db.batch(referenceOnly.statements), /FOREIGN KEY/); assert.equal((await first('SELECT count(*) AS total FROM collect_transaction_public_references WHERE public_reference=?', referenceOnly.reference.public_reference)).total, 0);
});

test('wrong amount/network/ref/payee or unreviewed member source cannot supply known reference prefixes; every failed batch rolls back', async () => {
  const f = await operating({ transaction: false, reference: `GUARD-${uuid()}` }), r = await receipt('receiver', { f, body: sms(f.reference) }), facts = await extract(r);
  const other = await operating({ transaction: false });
  for (const change of [{ amount: 12501 }, { reference: `WRONG-${uuid()}` }, { payee: other.payee, group: other.group }]) {
    const tx = { ...f, ...change, tx: uuid() }, plan = await prepareTransactionPublicReference({ ADMIN_DB: db }, { transaction_id: tx.tx, payee_id: tx.payee, source_fact_id: facts.resource_id });
    await assert.rejects(db.batch([...plan.statements, transactionStatement(tx)]), /matched receipt evidence/); assert.equal(await first('SELECT transaction_id FROM collect_transaction_public_references WHERE transaction_id=?', tx.tx), null);
  }
  const member = await receipt('member', { f, body: sms(f.reference) }), memberFacts = await extract(member), tx = { ...f, tx: uuid() }, plan = await prepareTransactionPublicReference({ ADMIN_DB: db }, { transaction_id: tx.tx, payee_id: tx.payee, source_fact_id: memberFacts.resource_id });
  await assert.rejects(db.batch([...plan.statements, transactionStatement(tx)]), /matched receipt evidence/); assert.equal(await first('SELECT id FROM collect_transactions WHERE id=?', tx.tx), null);
  const wrongNetwork = await receipt('receiver', { f, body: sms(f.reference), sender: 'AirtelMoney' }), wrongNetworkFacts = await extract(wrongNetwork), wrongTx = { ...f, tx: uuid() }, wrongPlan = await prepareTransactionPublicReference({ ADMIN_DB: db }, { transaction_id: wrongTx.tx, payee_id: wrongTx.payee, source_fact_id: wrongNetworkFacts.resource_id });
  await assert.rejects(db.batch([...wrongPlan.statements, transactionStatement(wrongTx)]), /matched receipt evidence/); assert.equal(await first('SELECT id FROM collect_transactions WHERE id=?', wrongTx.tx), null);
});

test('unique reference collision and financial insert failures leave neither dangling reference nor partial transaction', async () => {
  const f = await operating({ transaction: false }), old = await first('SELECT public_reference FROM collect_transaction_public_references WHERE transaction_id=?', legacy.tx);
  const collided = q("INSERT INTO collect_transaction_public_references(transaction_id,public_reference,payer_last3_known,payee_last3_known,random_source,created_at) VALUES(?,?,0,0,'crypto_get_random_values',?)", f.tx, old.public_reference, at);
  await assert.rejects(db.batch([collided, transactionStatement(f)]), /UNIQUE/); assert.equal(await first('SELECT id FROM collect_transactions WHERE id=?', f.tx), null);
  const plan = await prepareTransactionPublicReference({ ADMIN_DB: db }, { transaction_id: f.tx, payee_id: f.payee });
  await assert.rejects(db.batch([...plan.statements, transactionStatement({ ...f, amount: 0 })]), /CHECK/); assert.equal(await first('SELECT transaction_id FROM collect_transaction_public_references WHERE transaction_id=?', f.tx), null);
  await db.batch([...plan.statements, transactionStatement(f)]); assert.match((await first('SELECT public_reference FROM collect_transaction_public_references WHERE transaction_id=?', f.tx)).public_reference, /^000000[0-9]{12}$/);
});

test('guarded reference preparation skips replay loser without an orphan and exposes exact values for operation plans', async () => {
  const f = await operating({ transaction: false }), losingRequest = uuid();
  const plan = await prepareTransactionPublicReference({ ADMIN_DB: db }, { transaction_id: f.tx, payee_id: f.payee, operation_request_id: losingRequest });
  assert.deepEqual(Object.keys(plan.values), ['transaction_id','public_reference','payer_last3_known','payee_last3_known','source_fact_id','random_source','created_at']);
  const skipTransaction = q("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at,recorded_by_admin_id) SELECT ?,?,?,'mtn_momo',?,?, ?,?,? WHERE EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)", f.tx, f.group, f.payee, f.reference, f.amount, at, at, owner.id, losingRequest);
  await db.batch([...plan.statements, skipTransaction]); assert.equal(await first('SELECT id FROM collect_transactions WHERE id=?', f.tx), null);
  assert.equal(await first('SELECT transaction_id FROM collect_transaction_public_references WHERE transaction_id=?', f.tx), null);
  await run("INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,'qa.fixture',?,?,?)", losingRequest, owner.id, uuid(), 'a'.repeat(64), at);
  await db.batch([...plan.statements, skipTransaction]); assert.equal((await first('SELECT public_reference FROM collect_transaction_public_references WHERE transaction_id=?', f.tx)).public_reference, plan.values.public_reference);
});

test('extract audit failure, lost acknowledgment and auth revocation preserve atomic facts/receipts and honest recovery', async () => {
  const r = await receipt(), key = uuid(); await run("CREATE TRIGGER qa_sms_extract_audit BEFORE INSERT ON collect_operations_audit WHEN NEW.action='sms.extract' BEGIN SELECT RAISE(ABORT,'QA extraction audit unavailable'); END");
  try { assert.equal((await api(`${sourcePath(r)}/extract`, 'POST', { expected_source_sha256: r.sourceHash }, owner, key)).status, 409); assert.equal(await first('SELECT id FROM collect_sms_facts WHERE member_submission_id=?', r.id), null); assert.deepEqual(await ok(`requests/${key}`), { status: 'not_found' }); }
  finally { await run('DROP TRIGGER qa_sms_extract_audit'); }
  let lost = false; const wrapped = { prepare: query => db.prepare(query), batch: async statements => { const result = await db.batch(statements); if (!lost && statements.length > 8) { lost = true; throw new Error('QA lost D1 acknowledgement after commit'); } return result; } };
  await assert.rejects(handleAdminSms(direct(r, key), { ADMIN_DB: wrapped, MEMBER_MEDIA: memberBucket }, owner), error => error instanceof AdminSmsError && error.status === 503);
  const recovered = await ok(`requests/${key}`); assert.equal(recovered.status, 'succeeded'); assert.deepEqual(await extract(r, owner, key), recovered.receipt);
  const user = await actor(), other = await receipt(), revoke = { prepare: query => db.prepare(query), batch: async statements => { if (statements.length > 8) await run('DELETE FROM admin_sessions WHERE token_hash=?', user.token_hash); return db.batch(statements); } };
  await assert.rejects(handleAdminSms(direct(other), { ADMIN_DB: revoke, MEMBER_MEDIA: memberBucket }, user), error => error.status === 401); assert.equal(await first('SELECT id FROM collect_sms_facts WHERE member_submission_id=?', other.id), null);
  assert.equal((await first('SELECT count(*) AS total FROM collect_mutation_guards')).total, 0);
});

const reviewRequest=(r,key=uuid(),transaction=r.f.tx)=>new Request(`${origin}/api/admin/gateway/receipts/${r.id}/review`,{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify({expected_version:1,outcome:'reviewed',transaction_id:transaction,reason})});
const review=(r,user=owner,key=uuid(),env={ADMIN_DB:db,MEMBER_MEDIA:memberBucket})=>handleGateway(reviewRequest(r,key),env,{...user,permissions:[...user.permissions,'payments.read','payments.manage']});
async function sourceProjection(transaction) {
  const row=await first(`SELECT t.*,y.momo_number_or_code AS payee_momo_number_or_code,${TRANSACTION_PUBLIC_REFERENCE_COLUMNS_SQL},${TRANSACTION_SMS_FACT_COLUMNS_SQL}
    FROM collect_transactions t JOIN collect_payees y ON y.id=t.payee_id ${TRANSACTION_PUBLIC_REFERENCE_JOIN_SQL} ${TRANSACTION_SMS_FACT_JOIN_SQL} WHERE t.id=?`,transaction);
  return transactionSourceRow(row);
}

test('extraction before explicit member review attaches exact facts atomically without rewriting public reference origin',async()=>{
  const f=await operating({reference:`MEMBER-BEFORE-${uuid()}`}),r=await receipt('member',{f,body:sms(f.reference,'12,500','+02:00 Receiver code 0041258')});
  const original=await first('SELECT * FROM collect_transaction_public_references WHERE transaction_id=?',f.tx),fact=await extract(r);
  assert.equal((await sourceProjection(f.tx)).source_fact_id,null,'Extraction alone cannot attribute a source to an existing transaction');
  const key=uuid(),responses=await Promise.all([review(r,owner,key),review(r,owner,key)]);assert.deepEqual(responses[0],responses[1]);
  const link=await first('SELECT * FROM collect_transaction_sms_sources WHERE transaction_id=?',f.tx),reviewRow=await first('SELECT * FROM collect_member_receipt_reviews WHERE submission_id=?',r.id),dto=await sourceProjection(f.tx);
  assert.equal(link.source_fact_id,fact.resource_id);assert.equal(link.review_id,reviewRow.id);assert.equal(link.operation_request_id,responses[0].request_id);
  assert.equal(dto.source_fact_id,fact.resource_id);assert.equal(dto.source_kind,'member');assert.equal(dto.source_link_basis,'reviewed_member_receipt');assert.equal(dto.source_review_id,reviewRow.id);
  assert.equal(dto.reference_source_fact_id,null);assert.equal(dto.reference_payer_last3_known,false);assert.equal(dto.transaction_reference,original.public_reference);assert.equal(dto.payer_last3,'456');
  assert.equal(dto.provider_confirmation,false);assert.equal(dto.settlement_status,'not_asserted');assert.equal(dto.source_amount_rwf,12500);
  assert.deepEqual(await first('SELECT * FROM collect_transaction_public_references WHERE transaction_id=?',f.tx),original);
  assert.equal((await first('SELECT count(*) AS n FROM collect_transaction_sms_sources WHERE transaction_id=?',f.tx)).n,1);
  assert.equal((await first('SELECT count(*) AS n FROM collect_operations_audit WHERE operation_request_id=?',responses[0].request_id)).n,1);
  assert.equal((await first('SELECT verification_status FROM collect_transactions WHERE id=?',f.tx)).verification_status,'pending');
  await assert.rejects(run('UPDATE collect_transaction_sms_sources SET source_fact_id=? WHERE transaction_id=?',uuid(),f.tx),/immutable/);
  await assert.rejects(run('DELETE FROM collect_transaction_sms_sources WHERE transaction_id=?',f.tx),/cannot be deleted/);
});

test('extraction after recorded member review attaches the validated fact in its own claim-guarded batch and recovers the same source',async()=>{
  const f=await operating({reference:`MEMBER-AFTER-${uuid()}`,route:'0782501234'}),r=await receipt('member',{f,body:sms(f.reference,'12,500','Receiver number +250782501234')});
  const original=await first('SELECT public_reference FROM collect_transaction_public_references WHERE transaction_id=?',f.tx);
  await review(r,admin);assert.equal((await sourceProjection(f.tx)).source_fact_id,null);
  const key=uuid(),facts=await extract(r,owner,key),link=await first('SELECT * FROM collect_transaction_sms_sources WHERE transaction_id=?',f.tx);
  assert.equal(link.operation_request_id,facts.request_id);assert.equal(link.source_fact_id,facts.resource_id);
  assert.deepEqual(await extract(r,owner,key),facts);assert.equal((await extract(r,admin)).resource_id,facts.resource_id);
  const projected=await sourceProjection(f.tx);assert.equal(projected.source_link_basis,'reviewed_member_receipt');assert.equal(projected.payee_momo_number,'+250782501234');assert.equal(projected.transaction_reference,original.public_reference);
  assert.equal((await first('SELECT count(*) AS n FROM collect_transaction_sms_sources WHERE transaction_id=?',f.tx)).n,1);
});

test('missing or unparsed member facts remain absent despite an explicit review and never gain provider finality',async()=>{
  const f=await operating(),r=await receipt('member',{f,body:'Payment pending. OTP verification code 123456.'});
  await review(r);await extract(r);const projection=await sourceProjection(f.tx);
  assert.equal(projection.source_fact_id,null);assert.equal(projection.source_link_basis,'not_recorded');assert.equal(projection.source_review_id,null);assert.equal(projection.payer_name,null);
  assert.equal(projection.provider_confirmation,false);assert.equal(projection.settlement_status,'not_asserted');
  assert.equal(await first('SELECT transaction_id FROM collect_transaction_sms_sources WHERE transaction_id=?',f.tx),null);
});

test('known amount/reference/recipient contradictions roll back review or later extraction rather than creating member lineage',async()=>{
  for(const stage of ['before','after'])for(const mismatch of ['amount','reference','code','phone']){
    const f=await operating({reference:`BAD-${stage}-${mismatch}-${uuid()}`,route:mismatch==='phone'?'0782501234':'0041258'});
    const r=await receipt('member',{f,body:sms(mismatch==='reference'?`OTHER-${uuid()}`:f.reference,mismatch==='amount'?'12,501':'12,500',mismatch==='code'?'Receiver code 008000':mismatch==='phone'?'Receiver number +250782509999':'')});
    if(stage==='before')await extract(r);else await review(r);
    const count=()=>first('SELECT (SELECT count(*) FROM collect_transaction_sms_sources) AS links,(SELECT count(*) FROM collect_transaction_evidence) AS evidence,(SELECT count(*) FROM collect_member_receipt_reviews) AS reviews,(SELECT count(*) FROM collect_sms_facts) AS facts,(SELECT count(*) FROM collect_operations_audit) AS audits,(SELECT count(*) FROM collect_operation_requests) AS requests');
    const original=await first('SELECT * FROM collect_transaction_public_references WHERE transaction_id=?',f.tx),before=await count(),key=uuid();
    if(stage==='before')await assert.rejects(review(r,owner,key),error=>error.status===409);
    else{const result=await api(`${sourcePath(r)}/extract`,'POST',{expected_source_sha256:r.sourceHash},owner,key);assert.equal(result.status,409,JSON.stringify(result.body));assert.equal(result.body.error,'source_conflict');}
    assert.deepEqual(await count(),before,`${stage}/${mismatch}`);assert.deepEqual(await first('SELECT * FROM collect_transaction_public_references WHERE transaction_id=?',f.tx),original);
    assert.equal(await first('SELECT transaction_id FROM collect_transaction_sms_sources WHERE transaction_id=?',f.tx),null);
    assert.equal((await first('SELECT status FROM member_receipt_submissions WHERE id=?',r.id)).status,stage==='before'?'needs_review':'reviewed');
    assert.equal((await first('SELECT verification_status FROM collect_transactions WHERE id=?',f.tx)).verification_status,'pending');
  }
});

test('conflicting parsed sources and session revocation cannot partially attach reviewed-member lineage',async()=>{
  const f=await operating({reference:`MEMBER-CONFLICT-${uuid()}`}),r=await receipt('member',{f,body:sms(f.reference)}),other=await receipt('receiver',{f,body:sms(f.reference,'12,501')});
  await extract(r);await extract(other);await assert.rejects(review(r),error=>error.status===409);
  assert.equal((await first('SELECT status FROM member_receipt_submissions WHERE id=?',r.id)).status,'needs_review');assert.equal(await first('SELECT transaction_id FROM collect_transaction_sms_sources WHERE transaction_id=?',f.tx),null);
  const clean=await operating({reference:`MEMBER-REVOKE-${uuid()}`}),receiptNow=await receipt('member',{f:clean,body:sms(clean.reference)});await extract(receiptNow);
  const user=await actor(),wrapped={prepare:sql=>db.prepare(sql),batch:async statements=>{if(statements.length>5)await run('DELETE FROM admin_sessions WHERE token_hash=?',user.token_hash);return db.batch(statements);}};
  await assert.rejects(review(receiptNow,user,uuid(),{ADMIN_DB:wrapped,MEMBER_MEDIA:memberBucket}),error=>error.status===401);
  assert.equal((await first('SELECT status FROM member_receipt_submissions WHERE id=?',receiptNow.id)).status,'needs_review');assert.equal(await first('SELECT transaction_id FROM collect_transaction_sms_sources WHERE transaction_id=?',clean.tx),null);
  assert.equal((await first('SELECT count(*) AS n FROM collect_mutation_guards')).n,0);
});

test('known same-kind recipient mismatch rejects both public-reference binding paths while absent/different-kind facts stay unknown',async()=>{
  for(const existing of [false,true])for(const [route,extra,valid] of [['0041258','Receiver code 008000',false],['0782501234','Receiver number +250782509999',false],['0782501234','Receiver number +250782501234',true],['0041258','Receiver number +250782509999',true]]){
    const f=await operating({transaction:false,reference:`RECIPIENT-${uuid()}`,route}),r=await receipt('receiver',{f,body:sms(f.reference,'12,500',extra)}),facts=await extract(r);
    if(existing){const trigger=(await first("SELECT sql FROM sqlite_master WHERE type='trigger' AND name='collect_transaction_public_reference_default'")).sql;await run('DROP TRIGGER collect_transaction_public_reference_default');try{await insertTransaction(f);}finally{await run(trigger);}}
    const plan=await prepareTransactionPublicReference({ADMIN_DB:db},{transaction_id:f.tx,payee_id:f.payee,source_fact_id:facts.resource_id}),batch=[...plan.statements,...(existing?[]:[transactionStatement(f)])];
    if(valid){await db.batch(batch);assert.equal((await first('SELECT source_fact_id FROM collect_transaction_public_references WHERE transaction_id=?',f.tx)).source_fact_id,facts.resource_id);}
    else{await assert.rejects(db.batch(batch),/matched receipt evidence/);assert.equal(await first('SELECT transaction_id FROM collect_transaction_public_references WHERE transaction_id=?',f.tx),null);if(!existing)assert.equal(await first('SELECT id FROM collect_transactions WHERE id=?',f.tx),null);}
  }
});
