import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { digest, randomToken } from '../src/security.mjs';
import { handleReconciliation, ReconciliationError, RECONCILIATION_QUEUE_COUNT_SQL } from '../src/reconciliation.mjs';

const root = fileURLToPath(new URL('..', import.meta.url)), origin = 'https://admin.collect.ikanisa.com';
const timestamp = Math.floor(Date.now() / 1000), uuid = () => crypto.randomUUID(), reason = 'Reviewed the recorded member and payment evidence.';
let runtime, db, owner, admin, staff, counter = 100000;
const q = (query, ...args) => db.prepare(query).bind(...args), run = (query, ...args) => q(query, ...args).run(), first = (query, ...args) => q(query, ...args).first();
async function actor(role = 'admin') {
  const id = uuid(), token = randomToken(), token_hash = await digest(token);
  await run("INSERT INTO admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(?,?,?,'active','local-test-only',?,?)", id, role === 'owner' ? 'info@ikanisa.com' : `${id}@example.com`, role, timestamp, timestamp);
  await run('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,created_at,expires_at) VALUES(?,?,?,1,?,?)', token_hash, uuid(), id, timestamp, timestamp + 3600);
  return { id, role, token_hash, auth_version: 1, status: 'active', cookie: `__Host-collect_admin=${token}`,
    permissions: ['reconciliations.read', 'reconciliations.propose', ...(role === 'staff' ? [] : ['reconciliations.review'])] };
}
async function requestRecord(actorId = owner.id) {
  const id = uuid(); await run("INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,'qa.fixture',?,?,?)", id, actorId, uuid(), 'a'.repeat(64), timestamp); return id;
}
async function confirm(f, outcome = 'confirmation_recorded') {
  const version = (await first('SELECT version FROM collect_transactions WHERE id=?', f.tx)).version + 1;
  const evidenceId = uuid(), evidenceRequest = await requestRecord(), reviewRequest = await requestRecord(admin.id);
  await run("INSERT INTO collect_transaction_evidence(id,transaction_id,kind,reference,artifact_sha256,recorded_by_admin_id,operation_request_id,recorded_at) VALUES(?,?,'provider_statement','Local provider evidence fixture',?,?,?,?)", evidenceId, f.tx, await digest(uuid()), owner.id, evidenceRequest, timestamp);
  await db.batch([q('INSERT INTO collect_transaction_reviews(id,transaction_id,evidence_id,outcome,transaction_version,reviewed_by_admin_id,operation_request_id,reason,reviewed_at) VALUES(?,?,?,?,?,?,?,?,?)', uuid(), f.tx, evidenceId, outcome, version, admin.id, reviewRequest, reason, timestamp),
    q('UPDATE collect_transactions SET version=?,verification_status=?,verified_by_admin_id=?,verified_at=? WHERE id=?', version, outcome, admin.id, timestamp, f.tx)]);
  f.transactionVersion = version;
}
async function fixture({ confirmed = true, memberType = 'app', number = '0788123456', code = '008001', name = 'Alice Umuhoza' } = {}) {
  const f = { group: uuid(), member: uuid(), payee: uuid(), tx: uuid(), publicId: String(++counter), transactionVersion: 1, identity: { display_name: name, momo_provider: 'mtn_momo', momo_number: number, momo_pay_code: code } };
  await run("INSERT INTO collect_users(id,email,status,member_type,created_by_admin_id,created_at,updated_at) VALUES(?,?,'active',?,?,?,?)", f.member, `${f.member}@example.com`, memberType, owner.id, timestamp, timestamp);
  await run('INSERT INTO collect_profiles(user_id,public_id,display_name,momo_provider,momo_number,momo_pay_code,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)', f.member, f.publicId, name, f.identity.momo_provider, number, code, timestamp, timestamp);
  await run("INSERT INTO collect_groups(id,slug,title,collection_type,status,created_by_admin_id,created_at,updated_at) VALUES(?,?,'QA savings group','ikimina','active',?,?,?)", f.group, `qa-${f.group}`, owner.id, timestamp, timestamp);
  await run("INSERT INTO collect_memberships(group_id,user_id,role,status,joined_at,created_at,updated_at) VALUES(?,?,'owner','active',?,?,?)", f.group, f.member, timestamp, timestamp, timestamp);
  await run("INSERT INTO collect_payees(id,group_id,label,network,momo_number_or_code,created_by_admin_id,creation_reason,created_at) VALUES(?,?,'QA receiver','mtn_momo','0041258',?,?,?)", f.payee, f.group, owner.id, reason, timestamp);
  await run("INSERT INTO collect_transactions(id,group_id,payee_id,network,provider_reference,amount_rwf,observed_at,created_at,recorded_by_admin_id) VALUES(?,?,?,'mtn_momo',?,1000,?,?,?)", f.tx, f.group, f.payee, `QA-${f.tx}`, timestamp, timestamp, owner.id);
  if (confirmed) await confirm(f); return f;
}
async function api(path = '', method = 'GET', data = null, user = staff, key = uuid(), overrides = {}) {
  const response = await runtime.dispatchFetch(`${origin}/api/admin/reconciliations${path ? `/${path}` : ''}`, { method,
    headers: { Origin: origin, ...(user ? { Cookie: user.cookie } : {}), 'Content-Type': 'application/json', 'Idempotency-Key': key, ...overrides.headers },
    ...(data === null ? {} : { body: typeof data === 'string' ? data : JSON.stringify({ reason, ...data }) }) });
  return { status: response.status, body: await response.json(), key };
}
async function ok(...args) { const result = await api(...args); assert.equal(result.status, 200, JSON.stringify(result.body)); return result.body; }
const proposalBody = (f, extra = {}) => ({ member_user_id: f.member, amount_rwf: 400, expected_transaction_version: f.transactionVersion,
  expected_member_version: 1, expected_membership_version: 1, expected_payment_identity: f.identity, ...extra });
async function propose(f, user = staff, extra = {}, key = uuid()) { return ok(`${f.tx}/proposals`, 'POST', proposalBody(f, extra), user, key); }
const reviewBody = (f, extra = {}) => ({ outcome: 'approved', expected_proposal_version: 1, expected_transaction_version: f.transactionVersion, ...extra });
async function approve(f, proposal, user = admin, extra = {}, key = uuid()) { return ok(`proposals/${proposal.resource_id}/reviews`, 'POST', reviewBody(f, extra), user, key); }
function directRequest(path, data, user, key = uuid()) {
  return new Request(`${origin}/api/admin/reconciliations/${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key }, body: JSON.stringify({ reason, ...data }) });
}
before(async () => {
  // Ephemeral D1 only. No Wrangler persistence, provider, product Worker edits,
  // or mocked domain responses. Resolve real local sessions before the handler.
  const bundle = await build({ stdin: { resolveDir: root, contents: `
    import {handleReconciliation} from './src/reconciliation.mjs'; import {digest} from './src/security.mjs';
    export default {async fetch(request,env){try{
      if(request.headers.get('Origin')!==env.ADMIN_ORIGIN)return Response.json({error:'origin_rejected'},{status:403});
      const token=(request.headers.get('Cookie')||'').split('=')[1];
      const user=token?await env.ADMIN_DB.prepare("SELECT a.*,s.token_hash FROM admin_users a JOIN admin_sessions s ON s.user_id=a.id WHERE s.token_hash=? AND a.status='active' AND s.auth_version=a.auth_version AND s.expires_at>unixepoch()").bind(await digest(token)).first():null;
      if(user)user.permissions=['reconciliations.read','reconciliations.propose',...(['owner','admin'].includes(user.role)?['reconciliations.review']:[])];
      return Response.json(await handleReconciliation(request,env,user));
    }catch(error){return Response.json({error:error.code||'unexpected',message:error.message},{status:error.status||500});}}};` }, bundle: true, write: false, format: 'esm', platform: 'browser', target: 'es2022' });
  runtime = new Miniflare(convertV4MiniflareOptions({ modules: true, script: bundle.outputFiles[0].text, compatibilityDate: '2026-10-04', bindings: { ADMIN_ORIGIN: origin }, d1Databases: ['ADMIN_DB'], d1Persist: false }));
  db = await runtime.getD1Database('ADMIN_DB');
  for (const name of ['0001_admin_accounts.sql', '0002_collect_core.sql', '0003_posted_verification_guard.sql', '0004_operating_actions.sql', '0005_member_cloudflare.sql', '0006_gateway_cloudflare.sql', '0007_email_only_dispatch.sql', '0008_admin_people.sql', '0009_admin_reconciliation.sql','0010_admin_sms_facts.sql','0011_admin_transaction_sms_lineage.sql','0012_gateway_receiver_ingress.sql']) {
    const source = await readFile(new URL(`../migrations/${name}`, import.meta.url), 'utf8');
    const split = spawnSync(process.execPath, ['-e', "const w=require('wrangler');process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(require('node:fs').readFileSync(0,'utf8'))));"], { cwd: root, input: source, encoding: 'utf8', timeout: 15000 });
    assert.equal(split.status, 0, split.stderr); await db.batch(JSON.parse(split.stdout).map(query => db.prepare(query)));
  }
  owner = await actor('owner'); admin = await actor(); staff = await actor('staff');
});
after(async () => { await runtime?.dispose(); });

test('staff may create durable proposals only; anonymous, privilege spoofing and unrelated write paths are denied', async () => {
  const f = await fixture(), proposal = await propose(f);
  assert.equal(proposal.proposal_status, 'pending');
  assert.equal((await first('SELECT count(*) AS total FROM collect_payment_allocations WHERE transaction_id=?', f.tx)).total, 0);
  assert.equal((await api(`${f.tx}/proposals`, 'POST', proposalBody(f), null)).status, 401);
  assert.equal((await api(`proposals/${proposal.resource_id}/reviews`, 'POST', reviewBody(f))).status, 403);
  const spoofed = { ...staff, permissions: [...staff.permissions, 'reconciliations.review'] };
  await assert.rejects(handleReconciliation(directRequest(`proposals/${proposal.resource_id}/reviews`, reviewBody(f), spoofed), { ADMIN_DB: db }, spoofed), error => error.status === 403);
  for (const path of [`${f.tx}/verification`, `${f.tx}/allocations`, 'journals', 'groups']) assert.equal((await api(path, 'POST', {})).status, 405);
  assert.equal((await api(`${f.tx}/proposals`, 'POST', { ...proposalBody(f), role: 'owner' })).status, 400);
  assert.equal((await api(f.tx, 'GET', null, staff, uuid(), { headers: { Origin: 'https://attacker.example' } })).status, 403);
});

test('queue includes pending and confirmed unallocated balances, excludes rejected/full allocations, and supports bounded filters', async () => {
  const pending = await fixture({ confirmed: false }), confirmed = await fixture(), rejected = await fixture({ confirmed: false });
  await confirm(rejected, 'rejection_recorded');
  const p = await propose(confirmed); await approve(confirmed, p);
  const full = await fixture(); await approve(full, await propose(full, staff, { amount_rwf: 1000 }));
  const rows = await ok('?limit=100');
  assert.equal(rows.rows.find(row => row.id === pending.tx).verification_status, 'pending');
  assert.equal(rows.rows.find(row => row.id === confirmed.tx).unallocated_amount_rwf, 600);
  assert.equal(rows.rows.find(row => row.id === confirmed.tx).allocation_status, 'partially_allocated');
  assert.equal(rows.rows.find(row => row.id === confirmed.tx).settlement_status, 'not_asserted');
  assert.ok(!rows.rows.some(row => [rejected.tx, full.tx].includes(row.id)));
  assert.equal((await first(RECONCILIATION_QUEUE_COUNT_SQL)).total, rows.total);
  const filtered = await ok('?allocation_status=partially_allocated&verification_status=confirmation_recorded'); assert.ok(filtered.rows.every(row => row.allocation_status === 'partially_allocated'));
  assert.equal((await ok(`?search=${encodeURIComponent(`QA-${pending.tx}`)}`)).total, 1);
  const paged = await ok('?limit=1&offset=0'); assert.equal(paged.rows.length, 1); assert.equal(paged.next_offset, 1);
  for (const query of ['?limit=101', '?limit=1&limit=2', '?offset=-1', '?verification_status=rejection_recorded', '?allocation_status=allocated', '?sql=1']) assert.equal((await api(query)).status, 400);
});

test('member-first lookup uses recorded names/full numbers/codes and current active memberships, including Direct members', async () => {
  const f = await fixture(), direct = await fixture({ memberType: 'direct', number: '0787654321', code: '000042', name: 'Jean Niyonzima' });
  for (const search of ['Umuhoza', '+250788123456', '008001', f.publicId]) {
    const result = await ok(`members?transaction_id=${f.tx}&search=${encodeURIComponent(search)}`); assert.equal(result.total, 1); assert.deepEqual(result.rows[0].payment_identity, f.identity);
  }
  const row = (await ok(`members?search=000042`)).rows.find(row => row.member_user_id === direct.member); assert.equal(row.member_type, 'direct'); assert.equal(row.momo_number, '0787654321'); assert.equal(row.momo_pay_code, '000042');
  assert.equal((await ok(`members?transaction_id=${f.tx}&search=Niyonzima`)).total, 0);
  await run("UPDATE collect_memberships SET status='left',version=version+1 WHERE group_id=? AND user_id=?", f.group, f.member);
  assert.equal((await ok(`members?transaction_id=${f.tx}`)).total, 0);
  assert.equal((await api(`members?transaction_id=${uuid()}`)).status, 404);
  assert.equal((await api(`members?group_id=${direct.group}`)).status, 400);
});

test('unrecorded App name cannot be selected or proposed, and approval rejects a revoked recorded-name flag', async () => {
  const f = await fixture();
  await run('UPDATE collect_profiles SET display_name_recorded=0 WHERE user_id=?', f.member);
  assert.equal((await ok(`members?transaction_id=${f.tx}`)).total, 0);
  assert.equal((await api(`${f.tx}/proposals`, 'POST', proposalBody(f))).status, 409);
  await run('UPDATE collect_profiles SET display_name_recorded=1 WHERE user_id=?', f.member);
  const proposal = await propose(f);
  await run('UPDATE collect_profiles SET display_name_recorded=0 WHERE user_id=?', f.member);
  assert.equal((await api(`proposals/${proposal.resource_id}/reviews`, 'POST', reviewBody(f), admin)).status, 409);
  assert.equal((await first('SELECT count(*) AS total FROM collect_payment_allocations WHERE transaction_id=?', f.tx)).total, 0);
});

test('proposals have strict numeric wire/identity/version/reason contracts and never accept pasted group IDs', async () => {
  const f = await fixture();
  for (const extra of [{ group_id: f.group }, { amount_rwf: 0 }, { amount_rwf: 1.5 }, { expected_member_version: 0 }, { reason: 'short' }, { expected_payment_identity: { ...f.identity, momo_number: 'App account' } }, { expected_payment_identity: { ...f.identity, momo_number: '', momo_pay_code: '' } }]) assert.equal((await api(`${f.tx}/proposals`, 'POST', proposalBody(f, extra))).status, 400);
  assert.equal((await api(`${f.tx}/proposals`, 'POST', proposalBody(f), staff, 'short')).status, 400);
  for (const amount of ['1.0000000000000001', '1e3', '9007199254740992']) {
    const raw = JSON.stringify({ reason, ...proposalBody(f) }).replace('"amount_rwf":400', `"amount_rwf":${amount}`); assert.equal((await api(`${f.tx}/proposals`, 'POST', raw)).status, 400);
  }
  assert.equal((await api(`${f.tx}/proposals`, 'POST', { ...proposalBody(f), reason: 'x'.repeat(70000) })).status, 413);
  assert.equal((await first('SELECT count(*) AS total FROM collect_reconciliation_proposals WHERE transaction_id=?', f.tx)).total, 0);
});

test('pending proposals require independent verified-evidence review before approval; approval allocates once without posting or settlement', async () => {
  const f = await fixture({ confirmed: false }), p = await propose(f);
  assert.equal((await api(`proposals/${p.resource_id}/reviews`, 'POST', reviewBody(f), admin)).status, 409);
  await confirm(f); const approved = await approve(f, p);
  assert.equal(approved.version, 2); assert.equal(approved.proposal_status, 'approved'); assert.equal(approved.transaction_version, 3);
  const detail = await ok(f.tx); assert.equal(detail.resource.verification_status, 'confirmation_recorded'); assert.equal(detail.resource.unallocated_amount_rwf, 600);
  assert.equal(detail.related.allocations.total, 1); assert.equal(detail.related.verification_reviews.total, 1); assert.equal(detail.related.journals.total, 0);
  assert.equal(detail.related.proposals.rows[0].allocation_id, approved.allocation_id);
  assert.equal(detail.related.proposals.rows[0].payment_identity.momo_pay_code, '008001');
  const ownProposal = await propose(await fixture(), admin), ownTx = (await first('SELECT transaction_id FROM collect_reconciliation_proposals WHERE id=?', ownProposal.resource_id)).transaction_id;
  assert.equal((await api(`proposals/${ownProposal.resource_id}/reviews`, 'POST', { outcome: 'approved', expected_proposal_version: 1, expected_transaction_version: 2 }, admin)).status, 409);
  assert.equal((await first('SELECT count(*) AS total FROM collect_payment_allocations WHERE transaction_id=?', ownTx)).total, 0);
  await assert.rejects(run('UPDATE collect_payment_allocations SET amount_rwf=399 WHERE id=?', approved.allocation_id), /immutable/);
  await assert.rejects(run('DELETE FROM collect_reconciliation_reviews WHERE proposal_id=?', p.resource_id), /immutable/);
  await assert.rejects(run('UPDATE collect_reconciliation_proposals SET reason=? WHERE id=?', reason, p.resource_id), /immutable/);
});

test('stale person/name/number/code/membership/group/payee/version/amount evidence never creates an allocation or success audit', async () => {
  const mutations = [
    f => run("UPDATE collect_users SET status='suspended',version=version+1 WHERE id=?", f.member),
    f => run('UPDATE collect_users SET version=version+1 WHERE id=?', f.member),
    f => run("UPDATE collect_profiles SET display_name='Changed recorded name' WHERE user_id=?", f.member),
    f => run("UPDATE collect_profiles SET momo_number='0788123457' WHERE user_id=?", f.member),
    f => run("UPDATE collect_profiles SET momo_pay_code='008002' WHERE user_id=?", f.member),
    f => run("UPDATE collect_memberships SET status='left',version=version+1 WHERE group_id=? AND user_id=?", f.group, f.member),
    f => run('UPDATE collect_memberships SET version=version+1 WHERE group_id=? AND user_id=?', f.group, f.member),
    f => run("UPDATE collect_groups SET status='suspended',version=version+1 WHERE id=?", f.group),
    f => run('UPDATE collect_groups SET version=version+1 WHERE id=?', f.group),
    f => run("UPDATE collect_payees SET status='inactive',version=version+1 WHERE id=?", f.payee),
    f => run('UPDATE collect_transactions SET version=version+1 WHERE id=?', f.tx),
  ];
  for (const mutate of mutations) {
    const f = await fixture(), p = await propose(f), key = uuid(); await mutate(f);
    const result = await api(`proposals/${p.resource_id}/reviews`, 'POST', reviewBody(f), admin, key); assert.equal(result.status, 409, JSON.stringify(result));
    assert.equal((await first('SELECT count(*) AS total FROM collect_payment_allocations WHERE transaction_id=?', f.tx)).total, 0);
    assert.equal((await first('SELECT count(*) AS total FROM collect_reconciliation_reviews WHERE proposal_id=?', p.resource_id)).total, 0);
    assert.deepEqual(await ok(`requests/${key}`, 'GET', null, admin), { status: 'not_found' });
  }
  const f = await fixture(), p = await propose(f, staff, { amount_rwf: 900 }), other = await propose(f, owner, { amount_rwf: 200 }); await approve(f, other);
  assert.equal((await api(`proposals/${p.resource_id}/reviews`, 'POST', reviewBody(f, { expected_transaction_version: 3 }), admin)).status, 409);
  assert.equal((await first('SELECT sum(amount_rwf) AS total FROM collect_payment_allocations WHERE transaction_id=?', f.tx)).total, 200);
  const unrelated = await fixture(); assert.equal((await api(`${f.tx}/proposals`, 'POST', proposalBody(f, { member_user_id: unrelated.member, expected_payment_identity: unrelated.identity, expected_transaction_version: 3 }))).status, 409);
  const retracted = await fixture(), retractedProposal = await propose(retracted); await confirm(retracted, 'rejection_recorded');
  assert.equal((await api(`proposals/${retractedProposal.resource_id}/reviews`, 'POST', reviewBody(retracted), admin)).status, 409);
  const fresh = await fixture(), freshProposal = await propose(fresh);
  assert.equal((await api(`proposals/${freshProposal.resource_id}/reviews`, 'POST', reviewBody(fresh, { expected_proposal_version: 2 }), admin)).status, 409);
});

test('independent rejection can close stale proposals without any financial/verification effects; terminal reviews cannot be overwritten', async () => {
  const f = await fixture(), p = await propose(f); await run("UPDATE collect_users SET status='suspended' WHERE id=?", f.member);
  const rejected = await approve(f, p, admin, { outcome: 'rejected' }); assert.equal(rejected.proposal_status, 'rejected'); assert.equal(rejected.allocation_id, null);
  assert.equal((await first('SELECT version FROM collect_transactions WHERE id=?', f.tx)).version, 2);
  assert.equal((await api(`proposals/${p.resource_id}/reviews`, 'POST', reviewBody(f), owner)).status, 409);
  assert.equal((await first('SELECT count(*) AS total FROM collect_payment_allocations WHERE transaction_id=?', f.tx)).total, 0);
});

test('same-key concurrent proposals/reviews replay one durable receipt; key content is globally immutable and actor-scoped', async () => {
  const f = await fixture(), key = uuid();
  const proposals = await Promise.all([api(`${f.tx}/proposals`, 'POST', proposalBody(f), staff, key), api(`${f.tx}/proposals`, 'POST', proposalBody(f), staff, key)]);
  assert.ok(proposals.every(result => result.status === 200), JSON.stringify(proposals)); assert.deepEqual(proposals[0].body, proposals[1].body);
  assert.equal((await first('SELECT count(*) AS total FROM collect_reconciliation_proposals WHERE transaction_id=?', f.tx)).total, 1);
  assert.equal((await api(`${f.tx}/proposals`, 'POST', proposalBody(f, { amount_rwf: 401 }), staff, key)).status, 409);
  assert.equal((await api(`${f.tx}/proposals`, 'POST', proposalBody(f), admin, key)).status, 200);
  const p = proposals[0].body, reviewKey = uuid(), reviews = await Promise.all([api(`proposals/${p.resource_id}/reviews`, 'POST', reviewBody(f), admin, reviewKey), api(`proposals/${p.resource_id}/reviews`, 'POST', reviewBody(f), admin, reviewKey)]);
  assert.ok(reviews.every(result => result.status === 200), JSON.stringify(reviews)); assert.deepEqual(reviews[0].body, reviews[1].body);
  assert.equal((await first('SELECT count(*) AS total FROM collect_payment_allocations WHERE transaction_id=?', f.tx)).total, 1);
  assert.equal((await first('SELECT count(*) AS total FROM collect_operations_audit WHERE operation_request_id=?', reviews[0].body.request_id)).total, 1);
  assert.deepEqual(await ok(`requests/${reviewKey}`, 'GET', null, admin), { status: 'succeeded', request_id: reviews[0].body.request_id, receipt: reviews[0].body });
  assert.deepEqual(await ok(`requests/${reviewKey}`, 'GET', null, staff), { status: 'not_found' });
  await run("INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at,status,response_json,completed_at) VALUES(?,?,'other.operation',?,?,?,'succeeded','{}',?)", uuid(), staff.id, 'global-other-key', 'b'.repeat(64), timestamp, timestamp);
  assert.equal((await api(`${f.tx}/proposals`, 'POST', proposalBody(f, { expected_transaction_version: 3 }), staff, 'global-other-key')).status, 409);
});

test('concurrent competing reviews and balance allocations never approve twice or overallocate', async () => {
  const f = await fixture(), p = await propose(f), responses = await Promise.all([api(`proposals/${p.resource_id}/reviews`, 'POST', reviewBody(f), admin), api(`proposals/${p.resource_id}/reviews`, 'POST', reviewBody(f), owner)]);
  assert.deepEqual(responses.map(result => result.status).sort(), [200, 409]);
  const other = await fixture(), p1 = await propose(other, staff, { amount_rwf: 700 }), p2 = await propose(other, owner, { amount_rwf: 700 });
  const allocations = await Promise.all([api(`proposals/${p1.resource_id}/reviews`, 'POST', reviewBody(other), admin), api(`proposals/${p2.resource_id}/reviews`, 'POST', reviewBody(other), admin)]);
  assert.deepEqual(allocations.map(result => result.status).sort(), [200, 409]);
  assert.equal((await first('SELECT sum(amount_rwf) AS total FROM collect_payment_allocations WHERE transaction_id=?', other.tx)).total, 700);
  assert.equal((await first('SELECT count(*) AS total FROM collect_mutation_guards')).total, 0);
});

test('audit failure rolls back proposal/review/allocation/version/receipt together', async () => {
  const f = await fixture(), key = uuid();
  await run("CREATE TRIGGER qa_reconciliation_audit_abort BEFORE INSERT ON collect_operations_audit WHEN NEW.action LIKE 'reconciliations.%' BEGIN SELECT RAISE(ABORT,'QA audit insertion failed'); END");
  try {
    assert.equal((await api(`${f.tx}/proposals`, 'POST', proposalBody(f), staff, key)).status, 409);
    assert.equal((await first('SELECT count(*) AS total FROM collect_reconciliation_proposals WHERE transaction_id=?', f.tx)).total, 0);
    assert.deepEqual(await ok(`requests/${key}`), { status: 'not_found' });
  } finally { await run('DROP TRIGGER qa_reconciliation_audit_abort'); }
  const p = await propose(f), reviewKey = uuid();
  await run("CREATE TRIGGER qa_reconciliation_audit_abort BEFORE INSERT ON collect_operations_audit WHEN NEW.action='reconciliations.review' BEGIN SELECT RAISE(ABORT,'QA audit insertion failed'); END");
  try {
    assert.equal((await api(`proposals/${p.resource_id}/reviews`, 'POST', reviewBody(f), admin, reviewKey)).status, 409);
    assert.equal((await first('SELECT count(*) AS total FROM collect_payment_allocations WHERE transaction_id=?', f.tx)).total, 0);
    assert.equal((await first('SELECT count(*) AS total FROM collect_reconciliation_reviews WHERE proposal_id=?', p.resource_id)).total, 0);
    assert.equal((await first('SELECT version FROM collect_transactions WHERE id=?', f.tx)).version, 2);
    assert.deepEqual(await ok(`requests/${reviewKey}`, 'GET', null, admin), { status: 'not_found' });
  } finally { await run('DROP TRIGGER qa_reconciliation_audit_abort'); }
  await approve(f, p, admin, {}, reviewKey);
});

test('lost database acknowledgments recover through authoritative receipts and same-key replay without a second allocation', async () => {
  for (const stage of ['propose', 'approve']) {
    const f = await fixture(), p = stage === 'approve' ? await propose(f) : null, user = stage === 'approve' ? admin : staff, key = uuid();
    const path = stage === 'approve' ? `proposals/${p.resource_id}/reviews` : `${f.tx}/proposals`, data = stage === 'approve' ? reviewBody(f) : proposalBody(f);
    let lost = false;
    // Identify the final mutation batch by its plan length, distinct from the
    // two-statement read snapshots. Fault is injected after the actual commit.
    const wrapped = { prepare: query => db.prepare(query), batch: async statements => { const result = await db.batch(statements);
      if (!lost && statements.length > 8) { lost = true; throw new Error('QA lost D1 acknowledgement after commit'); } return result; } };
    await assert.rejects(handleReconciliation(directRequest(path, data, user, key), { ADMIN_DB: wrapped }, user), error => error instanceof ReconciliationError && error.status === 503);
    const recovered = await ok(`requests/${key}`, 'GET', null, user); assert.equal(recovered.status, 'succeeded');
    assert.deepEqual(await ok(path, 'POST', data, user, key), recovered.receipt);
    assert.equal((await first('SELECT count(*) AS total FROM collect_operations_audit WHERE operation_request_id=?', recovered.request_id)).total, 1);
    assert.equal((await first('SELECT count(*) AS total FROM collect_payment_allocations WHERE transaction_id=?', f.tx)).total, stage === 'approve' ? 1 : 0);
  }
});

test('fresh authorization and source assertions at commit reject revocation, role changes and identity races', async () => {
  for (const mode of ['revoke', 'role', 'identity']) {
    const f = await fixture(), p = await propose(f), user = await actor(), key = uuid(); let changed = false;
    const wrapped = { prepare: query => db.prepare(query), batch: async statements => {
      if (!changed && statements.length > 8) { changed = true;
        if (mode === 'revoke') await run('DELETE FROM admin_sessions WHERE token_hash=?', user.token_hash);
        else if (mode === 'role') await run("UPDATE admin_users SET role='staff' WHERE id=?", user.id);
        else await run("UPDATE collect_profiles SET momo_pay_code='000099' WHERE user_id=?", f.member); }
      return db.batch(statements);
    } };
    await assert.rejects(handleReconciliation(directRequest(`proposals/${p.resource_id}/reviews`, reviewBody(f), user, key), { ADMIN_DB: wrapped }, user), error => error.status === (mode === 'identity' ? 409 : 401));
    assert.equal((await first('SELECT count(*) AS total FROM collect_payment_allocations WHERE transaction_id=?', f.tx)).total, 0);
    assert.equal((await first('SELECT count(*) AS total FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', user.id, key)).total, 0);
  }
  const user = await actor('staff'); await run('UPDATE admin_sessions SET expires_at=unixepoch()-1 WHERE token_hash=?', user.token_hash);
  assert.equal((await api('', 'GET', null, user)).status, 401);
});

test('detail exposes explicitly pageable full related history rather than silent 200-row truncation', async () => {
  const f = await fixture({ confirmed: false });
  const batches = [];
  for (let index = 0; index < 205; index++) { const requestId = uuid(); batches.push(q("INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,'qa.fixture',?,?,?)", requestId, owner.id, uuid(), await digest(uuid()), timestamp),
    q("INSERT INTO collect_transaction_evidence(id,transaction_id,kind,reference,artifact_sha256,recorded_by_admin_id,operation_request_id,recorded_at) VALUES(?,?,'operator_observation',?,?,?,?,?)", uuid(), f.tx, `Local evidence item ${index}`, await digest(uuid()), owner.id, requestId, timestamp)); }
  for (let index = 0; index < batches.length; index += 80) await db.batch(batches.slice(index, index + 80));
  const initial = await ok(f.tx); assert.equal(initial.related.evidence.total, 205); assert.equal(initial.related.evidence.rows.length, 25); assert.equal(initial.related.evidence.next_offset, 25);
  const ids = new Set(); let offset = 0;
  do { const detail = await ok(`${f.tx}?related=evidence&limit=100&offset=${offset}`); assert.deepEqual(Object.keys(detail.related), ['evidence']);
    for (const row of detail.related.evidence.rows) { assert.ok(!ids.has(row.id)); ids.add(row.id); } offset = detail.related.evidence.next_offset;
  } while (offset !== null);
  assert.equal(ids.size, 205); assert.equal((await api(`${f.tx}?related=unsupported`)).status, 400);
});
