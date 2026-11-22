import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_sms_support/fixture.mjs';

async function operator(f, options = {}) {
 const account = await f.seedAccount(options);
 return {...await f.stepUp(await f.login(account)), account};
}

async function proposedContribution(f, s, amount) {
 const recorded = await f.operation('transactions', s.owner.cookie, {
  group_id: s.groupId, payee_id: s.groupId, amount_rwf: amount,
  provider_reference: 'synthetic-f19-' + randomUUID(), observed_at: new Date().toISOString(),
  evidence: 'Synthetic retained evidence for the F19 monetary concurrency regression. No provider confirmation claim.',
  reason: 'Record distinct controlled evidence for concurrency verification',
 });
 assert.equal(recorded.status, 200, JSON.stringify(recorded));
 const paymentId = recorded.body.resource_id;
 const member = await f.db.prepare('SELECT * FROM users WHERE id=?').bind(s.member.id).first();
 const proposal = await f.call(`/api/admin/reconciliations/${paymentId}/proposals`, {
  cookie: s.staff.cookie, headers: {'Idempotency-Key': randomUUID()}, data: {
   member_user_id: s.member.id, amount_rwf: amount, expected_transaction_version: 1,
   expected_member_version: member.revision, expected_membership_version: 1,
   expected_payment_identity: {display_name: member.full_name, momo_provider: member.momo_provider,
    momo_number: member.momo_number, momo_pay_code: member.momo_pay_code},
   reason: 'Attribute this distinct controlled contribution to the retained member',
  },
 });
 assert.equal(proposal.status, 200, JSON.stringify(proposal));
 const key = randomUUID(), data = {outcome: 'approved', expected_proposal_version: 1,
  expected_transaction_version: 1, reason: 'Independent reviewer approves the retained contribution evidence'};
 const review = (pause = false) => f.call(`/api/admin/reconciliations/proposals/${proposal.body.resource_id}/reviews`, {
  cookie: s.owner.cookie, headers: {'Idempotency-Key': key, ...(pause ? {'X-Test-Pause': 'before_commit'} : {})}, data,
 });
 return {paymentId, review};
}

// Both requests reach their committing batches before either is allowed to
// proceed. Every SQL batch and balance projection still executes real workerd/D1.
function pairedCommitBarrier(f) {
 let arrivals = 0, release;
 const both = new Promise(resolve => { release = resolve; });
 f.setGate(async event => {
  assert.equal(event.phase, 'before_commit');
  arrivals += 1;
  if (arrivals === 2) release();
  await both;
 });
 return () => { assert.equal(arrivals, 2); f.setGate(async () => {}); };
}

const snapshots = async f => (await f.db.prepare(
 'SELECT ledger_entry_id,payment_id,member_balance_after_minor,group_balance_after_minor,posted_at FROM contribution_posting_snapshots ORDER BY payment_id',
).all()).results;

async function assertBalances(f, s, expected) {
 const ledger = await f.db.prepare('SELECT sum(amount_minor) AS total FROM ledger_entries WHERE collection_id=? AND member_id=?')
  .bind(s.groupId, s.member.id).first();
 assert.equal(ledger.total, expected);
 const current = await f.call('/v1/rpc/list_current_member_collection_balances', {
  origin: 'https://collect.example', headers: {Authorization: 'Bearer ' + s.native.access_token},
 });
 assert.equal(current.status, 200, JSON.stringify(current));
 const balance = current.body.find(row => row.collection_id === s.groupId).balances[0];
 assert.equal(balance.current_user_balance_minor, expected);
 assert.equal(balance.amount_raised_minor, expected);
 const overview = await f.call('/api/admin/core/overview', {method: 'GET', cookie: s.owner.cookie});
 assert.equal(overview.status, 200, JSON.stringify(overview));
 assert.equal(overview.body.amounts.total_net_contributions_rwf, String(expected));
}

test('F19 concurrent distinct contributions and full reversal retain exact ledger balances and immutable after-posting snapshots', {timeout: 180000}, async t => {
 const f = await fixture(t, {MOMO_PROCESSING_PAUSED: 'true'}, {migrationsThrough: 15});
 const owner = await operator(f), staff = await operator(f, {role: 'staff', email: 'f19-proposer@example.test'});
 const member = await f.seedMember();
 const group = await f.operation('groups', owner.cookie, {title: 'F19 concurrency savings', slug: 'f19-concurrency-savings',
  collection_type: 'ikimina', owner_user_id: member.id,
  receiver: {label: 'Controlled F19 receiver', network: 'mtn_momo', momo_number_or_code: member.phone},
  reason: 'Create the controlled monetary concurrency destination'});
 assert.equal(group.status, 200, JSON.stringify(group));
 const s = {owner, staff, member, groupId: group.body.resource_id, native: await f.nativeLogin(member.phone)};

 const opening = await proposedContribution(f, s, 10000), openingApproval = await opening.review();
 assert.equal(openingApproval.status, 200, JSON.stringify(openingApproval));
 await assertBalances(f, s, 10000);
 const openingSnapshot = await snapshots(f);
 assert.deepEqual(openingSnapshot.map(row => row.member_balance_after_minor), [10000]);

 const first = await proposedContribution(f, s, 5000), second = await proposedContribution(f, s, 5000);
 const releaseContributions = pairedCommitBarrier(f);
 const approvals = await Promise.all([first.review(true), second.review(true)]);
 releaseContributions();
 for (const result of approvals) assert.equal(result.status, 200, JSON.stringify(result));
 await assertBalances(f, s, 20000);
 const beforeReversal = await snapshots(f);
 assert.deepEqual(beforeReversal.map(row => row.member_balance_after_minor).sort((a, b) => a - b), [10000, 15000, 20000]);
 assert.deepEqual(beforeReversal.map(row => row.group_balance_after_minor).sort((a, b) => a - b), [10000, 15000, 20000]);
 assert.deepEqual(beforeReversal.find(row => row.payment_id === opening.paymentId), openingSnapshot[0]);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM ledger_entries WHERE kind='contribution'").first()).n, 3);

 // Exact retries use each original request identity and return its committed
 // result without another contribution or a changed historical balance.
 const retries = await Promise.all([first.review(), second.review()]);
 retries.forEach((result, index) => assert.deepEqual(result.body, approvals[index].body));
 assert.deepEqual(await snapshots(f), beforeReversal);
 await assertBalances(f, s, 20000);

 const fourth = await proposedContribution(f, s, 5000), reversalKey = randomUUID();
 const reversalData = {expected_version: 2, reason: 'Reverse the complete opening contribution against retained evidence'};
 const reverse = pause => f.operation(`transactions/${opening.paymentId}/reverse`, owner.cookie, reversalData,
  reversalKey, pause ? {'X-Test-Pause': 'before_commit'} : {});
 const releaseReversal = pairedCommitBarrier(f);
 const mixed = await Promise.all([fourth.review(true), reverse(true)]);
 releaseReversal();
 for (const result of mixed) assert.equal(result.status, 200, JSON.stringify(result));
 await assertBalances(f, s, 15000);
 const afterReversal = await snapshots(f), latest = afterReversal.find(row => row.payment_id === fourth.paymentId);
 assert.ok([15000, 25000].includes(latest.member_balance_after_minor), JSON.stringify(latest));
 assert.equal(latest.group_balance_after_minor, latest.member_balance_after_minor);
 assert.deepEqual(afterReversal.filter(row => row.payment_id !== fourth.paymentId), beforeReversal);
 const ledger = (await f.db.prepare('SELECT payment_id,amount_minor,kind,reverses_entry_id FROM ledger_entries').all()).results;
 assert.equal(ledger.length, 5);
 assert.equal(ledger.filter(row => row.kind === 'contribution').length, 4);
 const reversed = ledger.filter(row => row.kind === 'reversal');
 assert.equal(reversed.length, 1); assert.equal(reversed[0].amount_minor, -10000);
 assert.equal(reversed[0].payment_id, opening.paymentId); assert.ok(reversed[0].reverses_entry_id);
 assert.deepEqual((await fourth.review()).body, mixed[0].body);
 assert.deepEqual((await reverse(false)).body, mixed[1].body);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n, 5);
 assert.deepEqual(await snapshots(f), afterReversal);
 await assertBalances(f, s, 15000);
});
