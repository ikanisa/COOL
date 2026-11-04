import {test} from 'node:test';
import assert from 'node:assert/strict';

// Import the real handler, not a copy of its projection or receipt validator.
// The preload denies construction of network SQL/SMTP clients in Node.
await import('./helpers/node-postgres-import.mjs');
const {financialRpc} = await import('../domain/payments.js');

const user = '10000000-0000-4000-8000-000000000001';
const otherUser = '10000000-0000-4000-8000-000000000002';
const originalSession = '20000000-0000-4000-8000-000000000001';
const currentSession = originalSession;
const priorSession = '20000000-0000-4000-8000-000000000002';
const group = '30000000-0000-4000-8000-000000000001';
const intentId = '40000000-0000-4000-8000-000000000001';
const requestId = '50000000-0000-4000-8000-000000000001';
const senderHash = 'a'.repeat(64);
const currentProfileHash = 'b'.repeat(64);
const bodyHash = 'c'.repeat(64);
const actor = {userId: user, sessionId: currentSession};

function intent(overrides = {}) {
 return {
  id: intentId, collection_id: group, member_id: user, amount_minor: 500,
  currency: 'RWF', rail: 'rwanda_momo', status: 'pending',
  receiver_momo_number: '250788123492', receiver_network: 'mtn_momo',
  receiver_label: 'Synthetic recipient', originating_session_id: originalSession,
  created_at: '2026-01-01T00:00:00.000Z', expires_at: '2099-01-01T00:00:00.000Z',
  request_id: requestId, request_sha256: bodyHash, ...overrides,
 };
}

// This is the independently specified creation response stored at creation,
// not a call to the production intentJson/boundCreationReceipt functions.
function creationResponse(row, hash = senderHash) {
 return JSON.stringify({
  id: row.id, collection_id: row.collection_id, amount_minor: row.amount_minor,
  currency: row.currency, rail: row.rail, status: 'pending',
  receiver_momo_number: row.receiver_momo_number, network: row.receiver_network,
  receiver_label: row.receiver_label, receiver_momo_number_hash: '',
  sender_phone_hash: hash, originating_session_id: row.originating_session_id,
  created_at: row.created_at, expires_at: row.expires_at,
 });
}

function creationReceipt(row, overrides = {}) {
 return {
  user_id: row.member_id, request_id: row.request_id,
  operation: 'create_contribution_intent', session_id: row.originating_session_id,
  body_sha256: row.request_sha256, response_json: creationResponse(row),
  ...overrides,
 };
}

function assertReceiptJoin(sql) {
 // A fake that always matches all keys would mask an unsafe SQL join. Check
 // the query independently, then separately model the relational join below.
 for (const expression of [
  /select\s+p\s*\.\s*\*\s*,\s*case\s+when\s+length\s*\(\s*r\s*\.\s*response_json\s*\)\s*<=\s*8192\s+then\s+r\s*\.\s*response_json\s+else\s+null\s+end\s+as\s+creation_response_json/i,
  /from\s+(?:app\.)?payment_intents\s+(?:as\s+)?p\b/i,
  /left\s+join\s+(?:app\.)?request_receipts\s+(?:as\s+)?r\s+on\s+r\s*\.\s*user_id\s*=\s*p\s*\.\s*member_id\s+and\s+r\s*\.\s*request_id\s*=\s*p\s*\.\s*request_id\s+and\s+r\s*\.\s*operation\s*=\s*'create_contribution_intent'\s+and\s+r\s*\.\s*session_id\s*=\s*p\s*\.\s*originating_session_id\s+and\s+r\s*\.\s*body_sha256\s*=\s*p\s*\.\s*request_sha256\b/i,
  /where\s+p\s*\.\s*member_id\s*=\s*\?\s+and\s*\(\s*\?\s+is\s+null\s+or\s+p\s*\.\s*id\s*=\s*\?\s*\)/i,
 ]) assert.match(sql, expression);
}

function fixture({intents = [intent()], receipts, pipeline = false, payments = []} = {}) {
 const savedIntents = structuredClone(intents);
 const savedReceipts = structuredClone(receipts ?? intents.map(row => creationReceipt(row)));
 const savedPayments = structuredClone(payments);
 const original = structuredClone({savedIntents, savedReceipts, savedPayments});
 const calls = [];
 const receiptMaterializations = [];
 let writeAttempts = 0;
 const forbiddenWrite = () => { writeAttempts++; throw Error('Synthetic fixture forbids writes'); };
 const env = {DB: {
  prepare(sql) {
   if (!/^\s*SELECT\b/i.test(sql)) return forbiddenWrite();
   return {bind(...values) {
    calls.push({sql, values});
    return {
     async all() {
      assertReceiptJoin(sql);
      assert.equal(values.length, 3);
      const [owner, firstSelection, secondSelection] = values;
      assert.equal(owner, user);
      assert.equal(firstSelection, secondSelection);
      const selected = savedIntents
       .filter(row => row.member_id === owner && (firstSelection == null || row.id === firstSelection))
       .sort((a,b) => b.created_at.localeCompare(a.created_at) || a.id.localeCompare(b.id))
       .slice(0, 50);
      return {results: selected.map(row => {
       // The fixture's receipt collection has no pre-joined columns. Match all
       // immutable creation identities independently, including the original
       // session rather than the actor's current session.
       const matches = savedReceipts.filter(receipt =>
        receipt.user_id === row.member_id && receipt.request_id === row.request_id &&
        receipt.operation === 'create_contribution_intent' &&
        receipt.session_id === row.originating_session_id &&
        receipt.body_sha256 === row.request_sha256);
       assert.ok(matches.length <= 1, 'fixture must respect receipt uniqueness');
       const response = matches[0]?.response_json ?? null;
       // PostgreSQL length(text) counts characters, independently of the
       // handler's additional UTF-8 byte bound on the received string.
       const projected = typeof response === 'string' && [...response].length <= 8192 ? response : null;
       receiptMaterializations.push({matched: matches.length === 1, included: projected !== null});
       return {...row, creation_response_json: projected};
      })};
     },
     async first() {
      if (/select\s+count\(\*\)\s+as\s+n\s+from\s+payment_intents/i.test(sql)) {
       assert.equal(values[0], user);
       return {n: savedIntents.filter(row => row.member_id === values[0] && row.status === 'pending' && row.expires_at > values[1]).length};
      }
      if (/from\s+sqlite_master/i.test(sql)) return pipeline ? {name: 'momo_financial_links'} : null;
      if (/from\s+payments\s+p\s+left\s+join\s+ledger_entries/i.test(sql)) {
       assert.deepEqual(values.slice(1), [user, user]);
       return savedPayments.find(payment => payment.intent_id === values[0])?.linked ?? null;
      }
      if (/from\s+contribution_posting_snapshots/i.test(sql)) {
       return savedPayments.find(payment => payment.linked.entry_id === values[0])?.snapshot ?? null;
      }
      if (/from\s+momo_financial_links\s+f\s+join\s+momo_transactions/i.test(sql)) {
       return savedPayments.find(payment => payment.linked.id === values[0])?.reference ?? null;
      }
      throw Error('Unexpected synthetic read, including a current-profile read');
     },
     run: forbiddenWrite,
    };
   }};
  },
  batch: forbiddenWrite,
 }};
 return {env, calls, receiptMaterializations, savedIntents, savedReceipts, savedPayments, original,
  assertNoWrites() {
   assert.equal(writeAttempts, 0);
   assert.deepEqual({savedIntents, savedReceipts, savedPayments}, original);
  },
 };
}

function forbidNetwork(t) {
 let attempts = 0;
 t.mock.method(globalThis, 'fetch', () => { attempts++; throw Error('Synthetic fixture forbids network'); });
 return () => assert.equal(attempts, 0);
}

function assertNoReceiptLeak(value, receipts) {
 const encoded = JSON.stringify(value);
 for (const privateField of ['creation_response_json', 'response_json', 'body_sha256', 'request_sha256']) {
  assert.equal(encoded.includes(`"${privateField}"`), false, `leaked ${privateField}`);
 }
 for (const receipt of receipts) {
  if (typeof receipt.response_json === 'string') {
   assert.equal(encoded.includes(JSON.stringify(receipt.response_json)), false, 'leaked raw creation receipt');
  }
 }
}

async function read(f, body = {}) {
 const result = await financialRpc('list_current_member_recent_intents', body, f.env, actor);
 assert.equal(result.handled, true);
 assertNoReceiptLeak(result.value, f.savedReceipts);
 f.assertNoWrites();
 assert.equal(f.calls.some(call => /\bfrom\s+(?:app\.)?users\b/i.test(call.sql)), false);
 return result.value;
}

for (const pipeline of [false, true]) test(`matched creation receipt restores original sender without reading profile (pipeline ${pipeline})`, async t => {
 const noNetwork = forbidNetwork(t);
 const f = fixture({pipeline});
 const result = await read(f);
 assert.equal(result.pending_count, 1);
 assert.equal(result.items.length, 1);
 assert.equal(result.items[0].status, 'pending');
 assert.equal(result.items[0].sender_phone_hash, senderHash);
 assert.notEqual(result.items[0].sender_phone_hash, currentProfileHash);
 assert.equal(result.items[0].originating_session_id, originalSession);
 if (pipeline) assert.equal(result.items[0].confirmation_status, 'awaiting_confirmation');
 else assert.equal('confirmation_status' in result.items[0], false);
 noNetwork();
});

test('missing and mismatched receipt identities cannot restore a sender', async t => {
 const noNetwork = forbidNetwork(t);
 const row = intent();
 for (const [name, receipts] of [
  ['missing', []],
  ['different owner', [creationReceipt(row, {user_id: otherUser})]],
  ['different request', [creationReceipt(row, {request_id: '50000000-0000-4000-8000-000000000002'})]],
  ['different operation', [creationReceipt(row, {operation: 'other_operation'})]],
  ['different original session', [creationReceipt(row, {session_id: priorSession})]],
  ['different body hash', [creationReceipt(row, {body_sha256: 'd'.repeat(64)})]],
 ]) {
  const f = fixture({intents: [row], receipts});
  const result = await read(f);
  assert.equal(result.items.length, 1, name);
  assert.equal(result.items[0].status, 'pending', name);
  assert.equal(result.items[0].sender_phone_hash, '', name);
 }
 noNetwork();
});

test('malformed, oversized, noncanonical and non-string-hash receipts fail closed', async t => {
 const noNetwork = forbidNetwork(t);
 const row = intent();
 const valid = creationResponse(row);
 const unicodeOversize = JSON.stringify({sender_phone_hash: senderHash, padding: 'é'.repeat(4096)});
 assert.ok(unicodeOversize.length <= 8192);
 assert.ok(new TextEncoder().encode(unicodeOversize).length > 8192);
 for (const [name, raw] of [
  ['null', null], ['broken JSON', '{'], ['JSON null', 'null'], ['array', '[]'],
  ['noncanonical whitespace', valid + ' '],
  ['oversized bytes', valid + ' '.repeat(8193)], ['multibyte oversized', unicodeOversize],
  ['missing hash', JSON.stringify({...JSON.parse(valid), sender_phone_hash: undefined})],
  ['empty hash', creationResponse(row, '')], ['uppercase hash', creationResponse(row, 'A'.repeat(64))],
  ['array hash', creationResponse(row, [senderHash])], ['object hash', creationResponse(row, {hash: senderHash})],
  ['extra receipt field', JSON.stringify({...JSON.parse(valid), extra: 'private synthetic content'})],
 ]) {
  const f = fixture({intents: [row], receipts: [creationReceipt(row, {response_json: raw})]});
  const result = await read(f);
  assert.equal(result.items[0].status, 'pending', name);
  assert.equal(result.items[0].sender_phone_hash, '', name);
  assert.equal(typeof result.items[0].sender_phone_hash, 'string', name);
  if (name === 'oversized bytes') assert.deepEqual(f.receiptMaterializations, [{matched: true, included: false}]);
  if (name === 'multibyte oversized') assert.deepEqual(f.receiptMaterializations, [{matched: true, included: true}]);
 }
 noNetwork();
});

for (const pipeline of [false, true]) test(`valid prior-session receipt stays non-actionable (pipeline ${pipeline})`, async t => {
 const noNetwork = forbidNetwork(t);
 const row = intent({originating_session_id: priorSession});
 const f = fixture({intents: [row], pipeline});
 const result = await read(f);
 assert.deepEqual(f.receiptMaterializations, [{matched: true, included: true}]);
 assert.equal(result.items.length, 1);
 assert.equal(result.items[0].status, 'pending');
 assert.equal(result.items[0].originating_session_id, priorSession);
 assert.equal(result.items[0].sender_phone_hash, '');
 if (pipeline) assert.equal(result.items[0].confirmation_status, 'awaiting_confirmation');
 noNetwork();
});

test('a receipt for changed intent fields cannot restore a sender', async t => {
 const noNetwork = forbidNetwork(t);
 const original = intent();
 const receipt = creationReceipt(original);
 for (const [name, change] of [
  ['intent id', {id: '40000000-0000-4000-8000-000000000002'}],
  ['collection', {collection_id: '30000000-0000-4000-8000-000000000002'}],
  ['amount', {amount_minor: 501}], ['currency', {currency: 'USD'}], ['rail', {rail: 'other'}],
  ['receiver', {receiver_momo_number: '250788123493'}], ['network', {receiver_network: 'airtel_money'}],
  ['receiver label', {receiver_label: 'Changed recipient'}],
  ['created time', {created_at: '2026-01-02T00:00:00.000Z'}],
  ['expiry time', {expires_at: '2099-01-02T00:00:00.000Z'}],
 ]) {
  const f = fixture({intents: [{...original, ...change}], receipts: [receipt]});
  const result = await read(f);
  assert.equal(result.items[0].sender_phone_hash, '', name);
  assert.equal(result.items[0].status, 'pending', name);
 }
 noNetwork();
});

for (const paymentStatus of ['confirmed', 'reversed']) test(`receipt binding preserves current matched intent and ${paymentStatus} confirmation`, async t => {
 const noNetwork = forbidNetwork(t);
 const row = intent({status: 'matched'});
 const payment = {
  intent_id: row.id,
  linked: {id: '60000000-0000-4000-8000-000000000001', status: paymentStatus, member_id: user,
   amount_minor: row.amount_minor, entry_id: '70000000-0000-4000-8000-000000000001', posted_at: '2026-01-02T00:00:00.000Z'},
  snapshot: {member_balance_after_minor: 1200, group_balance_after_minor: 4000},
  reference: {provider_transaction_id: 'SYNTHETIC-TX', transaction_at: '2026-01-02T00:00:00.000Z'},
 };
 const f = fixture({intents: [row], pipeline: true, payments: [payment]});
 const result = await read(f);
 assert.equal(result.pending_count, 0);
 assert.equal(result.items[0].status, 'matched');
 assert.equal(result.items[0].sender_phone_hash, senderHash);
 assert.equal(result.items[0].confirmation_status, paymentStatus === 'reversed' ? 'reversed' : 'credited');
 assert.equal(result.items[0].payment_id, payment.linked.id);
 assert.equal(result.items[0].contribution_entry_id, payment.linked.entry_id);
 assert.equal(result.items[0].balance_after_contribution_rwf, 1200);
 assert.equal(result.items[0].group_balance_after_contribution_rwf, 4000);
 noNetwork();
});

test('selection returns only the requested current member intent without changing pending count', async t => {
 const noNetwork = forbidNetwork(t);
 const first = intent();
 const second = intent({id: '40000000-0000-4000-8000-000000000002', request_id: '50000000-0000-4000-8000-000000000002',
  status: 'matched', created_at: '2026-01-02T00:00:00.000Z'});
 const foreign = intent({id: '40000000-0000-4000-8000-000000000003', request_id: '50000000-0000-4000-8000-000000000003', member_id: otherUser});
 const f = fixture({intents: [first, second, foreign]});
 const result = await read(f, {p_intent_id: second.id});
 assert.equal(result.pending_count, 1);
 assert.equal(result.items.length, 1);
 assert.equal(result.items[0].id, second.id);
 assert.equal(result.items[0].status, 'matched');
 assert.equal(result.items[0].sender_phone_hash, senderHash);
 const unavailable = await read(f, {p_intent_id: foreign.id});
 assert.deepEqual(unavailable.items, []);
 assert.equal(unavailable.pending_count, 1);
 noNetwork();
});
