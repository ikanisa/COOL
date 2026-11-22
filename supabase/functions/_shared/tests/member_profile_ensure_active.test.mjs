import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {groupRpc} from './helpers/module-domain-groups.js';

// Direct handler characterization with a fake actor and in-memory query results.
// It does not exercise requireSession/projectSession, actual SQL transactions,
// session replacement, or revocation after the SELECT snapshot.
const PRINCIPAL = '11111111-1111-4111-8111-111111111111';
const SESSION = '22222222-2222-4222-8222-222222222222';
const PHONE = '+250788000001';
const actor = {userId: PRINCIPAL, sessionId: SESSION, surface: 'member', user: {phone: PHONE}};
const active = () => ({id: PRINCIPAL, public_id: '000123', phone: PHONE,
 country_code: 'RW', currency_code: 'RWF', momo_provider: 'mtn_momo',
 momo_number: '0788000001', momo_pay_code: '', access_status: 'active'});
class FakeDatabase {
 constructor(row) {this.row = row; this.reads = []; this.writes = 0; this.beforeRead = null;}
 prepare(sql) {
  const db = this;
  assert.ok(sql.startsWith('SELECT '), 'Profile handler must not write in this fixture');
  return {bind(...values) {return {async first() {
   assert.deepEqual(values, [PRINCIPAL]);
   db.reads.push(sql);
   if (db.beforeRead) db.beforeRead(db);
   const row = db.row;
   const selected = row && (!sql.includes("access_status='active'") || row.access_status === 'active')
    ? structuredClone(row) : null;
   if (!selected) return null;
   if (sql.startsWith('SELECT id,public_id,phone AS whatsapp_phone')) return {
    id: selected.id, public_id: selected.public_id, whatsapp_phone: selected.phone,
    country_code: selected.country_code, currency_code: selected.currency_code,
    momo_provider: selected.momo_provider, momo_number: selected.momo_number,
    momo_pay_code: selected.momo_pay_code,
   };
   assert.ok(sql.startsWith('SELECT * FROM users WHERE id=?'));
   return selected;
  }}}};
 }
 async batch() {this.writes++; throw Error('Unexpected synthetic batch');}
}
const ensure = (db, phone = PHONE) => groupRpc('ensure_current_member_profile',
 {p_whatsapp_phone: phone, p_country_code: 'RW'}, {DB: db}, actor);
const get = db => groupRpc('get_current_member_profile', {}, {DB: db}, actor);
const denied = error => error?.status === 403 && error?.code === '42501';

test('active profile can be reread without handler writes', async () => {
 const db = new FakeDatabase(active());
 const first = await ensure(db), second = await ensure(db);
 assert.deepEqual(second, first); assert.equal(first.handled, true);
 assert.equal(first.value.id, PRINCIPAL); assert.equal(first.value.whatsapp_phone, PHONE);
 assert.equal(first.value.momo_number, '0788000001');
 assert.equal(db.reads.length, 2); assert.equal(db.writes, 0);
});
test('profile ensure refuses a mismatching phone', async () => {
 const db = new FakeDatabase(active());
 await assert.rejects(ensure(db, '+250788000002'), denied); assert.equal(db.writes, 0);
});
test('profile ensure refuses suspension or deletion before its read', async () => {
 for (const status of ['suspended', 'deleted']) {
  const db = new FakeDatabase(active()); db.beforeRead = current => {current.row.access_status = status;};
  await assert.rejects(ensure(db), denied); assert.equal(db.writes, 0);
 }
});
test('profile ensure refuses a missing row with the same generic 403', async () => {
 const db = new FakeDatabase(null);
 await assert.rejects(ensure(db), denied); assert.equal(db.writes, 0);
});
test('current profile read keeps its existing active-only behavior', async () => {
 for (const status of ['active', 'suspended', 'deleted']) {
  const row = active(); row.access_status = status; const db = new FakeDatabase(row);
  const result = await get(db);
  assert.equal(result.value?.id ?? null, status === 'active' ? PRINCIPAL : null);
  assert.equal(db.writes, 0);
 }
});
