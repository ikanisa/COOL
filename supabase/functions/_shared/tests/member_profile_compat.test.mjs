import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {groupRpc} from './helpers/module-domain-groups.js';

// These fixtures exercise the real handler and mutation receipt code without a
// database or network. They do not establish PostgreSQL locking or hosted Auth.
const USER = '11111111-1111-4111-8111-111111111111';
const SESSION = '22222222-2222-4222-8222-222222222222';
const OTHER_SESSION = '33333333-3333-4333-8333-333333333333';
const REQUEST = '44444444-4444-4444-8444-444444444444';
const actor = (phone = '+250788123456', confirmed = '2026-01-01T00:00:00Z', session = SESSION) => ({
 userId: USER, sessionId: session, surface: 'member', assuranceLevel: 1,
 user: {phone, phone_confirmed_at: confirmed},
});
const body = (overrides = {}) => ({
 p_request_id: REQUEST, p_country_code: 'RW', p_momo_provider: 'mtn_momo',
 p_momo_number: '0788123456', p_momo_pay_code: '', ...overrides,
});
const key = values => `${values[0]}:${values[1]}`;

class FakeDatabase {
 constructor() {
  this.profile = {id: USER, momo_provider: 'mtn_momo', momo_number: '0788123456', momo_pay_code: '0042'};
  this.activeSessions = new Set([SESSION, OTHER_SESSION]);
  this.activeUser = true;
  this.receipts = new Map();
  this.audits = 0;
  this.updates = 0;
  this.beforeBatch = null;
  this.loseCommitReply = false;
 }
 prepare(sql) {
  const db = this;
  return {sql, values: [], bind(...values) {this.values = values; return this;}, async first() {
   if (sql === 'SELECT * FROM request_receipts WHERE user_id=? AND request_id=?') return db.receipts.get(key(this.values)) ?? null;
   throw Error('Unexpected synthetic read: ' + sql);
  }};
 }
 async batch(statements) {
  if (this.beforeBatch) {const action = this.beforeBatch; this.beforeBatch = null; action(this);}
  const before = {profile: {...this.profile}, receipts: new Map(this.receipts), audits: this.audits, updates: this.updates};
  let insertedReceipt = false;
  try {
   for (const {sql, values} of statements) {
    if (sql.startsWith('INSERT INTO mutation_guards')) {
     if (!this.activeUser || values[1] !== USER || !this.activeSessions.has(values[2])) throw Error('session_changed');
    } else if (sql.startsWith('INSERT INTO request_receipts')) {
     const k = key(values);
     if (this.receipts.has(k)) throw Error('UNIQUE constraint');
     this.receipts.set(k, {operation: values[2], session_id: values[3], body_sha256: values[4], response_json: values[5]});
     insertedReceipt = true;
    } else if (sql.startsWith('UPDATE users SET momo_provider=')) {
     assert.match(sql, /momo_pay_code=coalesce\(\?,momo_pay_code\)/);
     assert.equal(values[4], USER);
     this.profile = {...this.profile, momo_provider: values[0], momo_number: values[1],
      momo_pay_code: values[2] ?? this.profile.momo_pay_code};
     this.updates++;
    } else if (sql.startsWith('INSERT INTO audit_log')) {
     this.audits++;
    } else if (sql.startsWith('DELETE FROM mutation_guards')) {
     // The real transaction removes its own authority guard.
    } else {
     throw Error('Unexpected synthetic statement: ' + sql);
    }
   }
  } catch (error) {
   this.profile = before.profile; this.receipts = before.receipts;
   this.audits = before.audits; this.updates = before.updates;
   throw error;
  }
  if (insertedReceipt && this.loseCommitReply) {
   this.loseCommitReply = false;
   throw Error('Synthetic commit reply lost');
  }
  return statements.map(() => ({results: [], meta: {changes: 1}}));
 }
}

const update = (db, request = body(), currentActor = actor()) =>
 groupRpc('update_current_member_profile', request, {DB: db}, currentActor);

test('confirmed owner accepts equivalent Rwanda formats and stores the local form', async () => {
 for (const number of ['0788123456', '788123456', '250788123456', '00250788123456', '+250788123456', '+250 (788) 123-456']) {
  const db = new FakeDatabase();
  assert.deepEqual(await update(db, body({p_momo_number: number})), {handled: true, value: null});
  assert.equal(db.profile.momo_number, '0788123456');
  assert.equal(db.profile.momo_pay_code, '');
  assert.equal(db.updates, 1); assert.equal(db.audits, 1); assert.equal(db.receipts.size, 1);
  assert.equal([...db.receipts.values()][0].response_json, 'null');
 }
 const airtel = new FakeDatabase();
 await update(airtel, body({p_momo_provider: 'airtel_money', p_momo_number: '0738123456'}), actor('+250738123456'));
 assert.equal(airtel.profile.momo_provider, 'airtel_money');
 assert.equal(airtel.profile.momo_number, '0738123456');
});

test('missing, unconfirmed and different ownership phones cannot mutate', async () => {
 for (const currentActor of [actor(null), actor('+250788123456', null), actor('+250788123456', ''), actor('+250788123457')]) {
  const db = new FakeDatabase();
  await assert.rejects(update(db, body(), currentActor), error => error.code === '42501' && error.status === 403);
  assert.equal(db.updates, 0); assert.equal(db.receipts.size, 0); assert.equal(db.audits, 0);
 }
});

test('invalid numbers, provider mismatches and invalid codes are refused before mutation', async () => {
 for (const request of [
  body({p_momo_number: ''}), body({p_momo_number: '+0788123456'}),
  body({p_momo_number: 'not-0788123456'}), body({p_momo_number: '0788123456\nextra'}),
  body({p_momo_provider: 'airtel_money'}), body({p_momo_provider: 'unknown'}),
  body({p_momo_pay_code: '123'}), body({p_momo_pay_code: '1234567890'}),
  body({p_momo_pay_code: '12A4'}), body({p_momo_pay_code: 1234}),
 ]) {
  const db = new FakeDatabase();
  await assert.rejects(update(db, request), error => error.code === '22023' && error.status === 400);
  assert.equal(db.updates, 0); assert.equal(db.receipts.size, 0); assert.equal(db.audits, 0);
 }
});

test('omitted code preserves its stored value and explicit empty code clears it', async () => {
 const omitted = new FakeDatabase();
 const withoutCode = body(); delete withoutCode.p_momo_pay_code;
 await update(omitted, withoutCode);
 assert.equal(omitted.profile.momo_pay_code, '0042');
 const empty = new FakeDatabase();
 await update(empty, body({p_momo_pay_code: ''}));
 assert.equal(empty.profile.momo_pay_code, '');
 const supplied = new FakeDatabase();
 await update(supplied, body({p_momo_pay_code: ' 00123 '}));
 assert.equal(supplied.profile.momo_pay_code, '00123');
 const defaults = new FakeDatabase();
 await update(defaults, {p_request_id: REQUEST});
 assert.equal(defaults.profile.momo_number, '0788123456');
 assert.equal(defaults.profile.momo_provider, 'mtn_momo');
 assert.equal(defaults.profile.momo_pay_code, '0042');
});

test('same-session replay retains null and does not repeat the write or audit', async () => {
 const db = new FakeDatabase();
 assert.deepEqual(await update(db), {handled: true, value: null});
 assert.deepEqual(await update(db), {handled: true, value: null});
 assert.equal(db.updates, 1); assert.equal(db.audits, 1); assert.equal(db.receipts.size, 1);
 await assert.rejects(update(db, body({p_momo_pay_code: '5678'})), error => error.code === 'request_conflict' && error.status === 409);
 await assert.rejects(update(db, body(), actor('+250788123456', '2026-01-01T00:00:00Z', OTHER_SESSION)), error => error.code === 'request_conflict' && error.status === 409);
 assert.equal(db.updates, 1); assert.equal(db.audits, 1);
});

test('authority failure rolls back and an internally lost commit reply retains one receipt', async () => {
 const denied = new FakeDatabase();
 denied.beforeBatch = db => db.activeSessions.delete(SESSION);
 await assert.rejects(update(denied), error => error.code === 'session_changed' && error.status === 403);
 assert.equal(denied.updates, 0); assert.equal(denied.audits, 0); assert.equal(denied.receipts.size, 0);
 const lost = new FakeDatabase(); lost.loseCommitReply = true;
 assert.deepEqual(await update(lost), {handled: true, value: null});
 assert.equal(lost.updates, 1); assert.equal(lost.audits, 1); assert.equal(lost.receipts.size, 1);
});
