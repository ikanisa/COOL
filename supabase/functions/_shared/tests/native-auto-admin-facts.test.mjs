import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {withReceiptFacts} from '../domain/receipt_facts.js';
import {MANAGED_MOMO_SOURCE_SQL,momoTransactionSql,momoTransactionPredicates,momoTransactionPageRow} from '../domain/admin_momo.js';

const tx='11111111-1111-4111-8111-111111111111';
const account='22222222-2222-4222-8222-222222222222';
const source='33333333-3333-4333-8333-333333333333';
const attempt='44444444-4444-4444-8444-444444444444';
const group='55555555-5555-4555-8555-555555555555';
const digest='a'.repeat(64);
function row(){return {id:tx,receiving_account_id:account,parse_attempt_id:attempt,native_group_id:group,
 rf_attempt_id:attempt,rf_capture_id:source,rf_attempt_source:source,rf_link_source:source,
 rf_link_attempt:attempt,rf_link_transaction:tx,rf_relation:'accepted',rf_attempt_outcome:'accepted',
 rf_capture_digest:digest,rf_attempt_digest:digest,rf_parser_version:'native-auto.v1',rf_profile_version:'runtime.v1',
 rf_parsed_at:'2026-11-12T08:00:00.000Z',provider:'mtn_momo',event_kind:'outgoing',
 provider_transaction_id:null,amount_minor:null,currency:null,currency_scale:null,
 payer_name:null,payer_identifier:null,payer_last3:null,fee_minor:null,wallet_balance_after_minor:null,
 transaction_datetime_raw:null,transaction_at:null,transaction_timezone:'Africa/Kigali',
 transaction_time_source:'missing_provider_time',recipient_name:'Synthetic account',public_code:'12345'};}

test('automatic native transaction keeps direction and absent facts without claiming provider confirmation',()=>{
 const result=withReceiptFacts(row());
 assert.equal(result.event_kind,'outgoing');
 assert.equal(result.receipt_facts.kind,'automatic_momo_extraction');
 assert.equal(result.receipt_facts.amount_minor,null);
 assert.equal(result.receipt_facts.provider_transaction_id,null);
 assert.deepEqual(result.receiving_context,{account_id:null,identifier_raw:null,identifier_kind:null,recipient_name:null,basis:'unestablished'});
 assert.equal(result.receiving_account_id,null);
 assert.equal(result.public_code,null);
 assert.equal(result.recipient_name,null);
 assert.equal(result.native_group_id,group);
 assert.equal(result.provider_confirmation,false);
 const rawOnly=withReceiptFacts({...row(),transaction_datetime_raw:'format not normalized'});
 assert.equal(rawOnly.receipt_facts.transaction_at,null);
 assert.equal(rawOnly.receipt_facts.transaction_datetime_raw,'format not normalized');
});
test('legacy assignment source gate distinguishes native observations from managed accepted receipts',()=>{
 const db=new DatabaseSync(':memory:');
 try{
  db.exec(`CREATE TABLE momo_transactions(id TEXT PRIMARY KEY,parse_attempt_id TEXT NOT NULL);
   CREATE TABLE sms_receipts(id TEXT PRIMARY KEY,originating_session_id TEXT,receiver_hash TEXT,body_sha256 TEXT);
   CREATE TABLE momo_transaction_sources(transaction_id TEXT,raw_sms_id TEXT,parse_attempt_id TEXT,relation TEXT);
   CREATE TABLE momo_parse_attempts(id TEXT PRIMARY KEY,raw_sms_id TEXT,outcome TEXT,source_body_sha256 TEXT);
   INSERT INTO momo_transactions VALUES ('managed','attempt-managed'),('native','attempt-native'),('mismatched','first-attempt');
   INSERT INTO sms_receipts VALUES ('managed-raw','managed-session','managed-receiver-hash','source-hash'),('native-raw',NULL,NULL,'native-hash');
   INSERT INTO momo_parse_attempts VALUES ('attempt-managed','managed-raw','accepted','source-hash'),('attempt-native','native-raw','accepted','native-hash');
   INSERT INTO momo_transaction_sources VALUES
    ('managed','managed-raw','attempt-managed','accepted'),('native','native-raw','attempt-native','accepted'),
    ('mismatched','managed-raw','second-attempt','accepted');`);
  const eligible=db.prepare(`SELECT t.id FROM momo_transactions t WHERE t.id=? AND ${MANAGED_MOMO_SOURCE_SQL}`);
  assert.equal(eligible.get('managed')?.id,'managed');
  assert.equal(eligible.get('native'),undefined);
  assert.equal(eligible.get('mismatched'),undefined);
  db.prepare("UPDATE momo_parse_attempts SET raw_sms_id='native-raw' WHERE id='attempt-managed'").run();
  assert.equal(eligible.get('managed'),undefined);
  db.prepare("UPDATE momo_parse_attempts SET raw_sms_id='managed-raw',outcome='duplicate' WHERE id='attempt-managed'").run();
  assert.equal(eligible.get('managed'),undefined);
  db.prepare("UPDATE momo_parse_attempts SET outcome='accepted',source_body_sha256='other-hash' WHERE id='attempt-managed'").run();
  assert.equal(eligible.get('managed'),undefined);
  db.prepare("UPDATE momo_parse_attempts SET source_body_sha256='source-hash' WHERE id='attempt-managed'").run();
  assert.equal(eligible.get('managed')?.id,'managed');
  db.prepare("UPDATE momo_transaction_sources SET relation='duplicate' WHERE transaction_id='managed'").run();
  assert.equal(eligible.get('managed'),undefined);
 }finally{db.close();}
});
test('automatic native facts require an intact accepted first-source chain',()=>{
 for(const change of [{rf_link_source:tx},{rf_attempt_digest:'b'.repeat(64)},{rf_relation:'duplicate'},
  {event_kind:'invented'},{amount_minor:-1}]){
  assert.throws(()=>withReceiptFacts({...row(),...change}));
 }
});
test('native Admin projection excludes hidden scopes and leaves the legacy query independent of the migration',()=>{
 const old=momoTransactionSql({});
 const next=momoTransactionSql({BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true'});
 assert.doesNotMatch(old,/burimunsi_admin_transaction_visibility/);
 assert.match(next,/burimunsi_admin_transaction_visibility\(t\.id\)/);
 assert.match(next,/scope->>'kind' IN \('managed','visible'\)/);
 assert.match(next,/scope->>'groupId'/);
});

test('opt-in capture scope filters both lanes and preserves full filtered totals',()=>{
 const other='66666666-6666-4666-8666-666666666666',db=new DatabaseSync(':memory:');
 try{
  db.exec(`CREATE TABLE records(id TEXT,receiving_account_id TEXT,native_group_id TEXT,group_id TEXT,
    provider_transaction_id TEXT,payer_name TEXT,status TEXT,has_conflict INTEGER,transaction_at TEXT,
    event_kind TEXT,amount_minor INTEGER,credited_amount_minor INTEGER);
   INSERT INTO records VALUES
    ('managed','${account}',NULL,'${group}','m1','One','credited',0,'2026-11-12T08:00:00.000Z','incoming_receipt',100,100),
    ('native','${account}','${group}','${group}',NULL,'Two','recorded',0,'2026-11-12T08:00:00.000Z','incoming_receipt',200,0),
    ('other','${other}','${group}','${group}',NULL,'Three','recorded',0,'2026-11-12T08:00:00.000Z','incoming_receipt',300,0);`);
  const select=params=>{const url=new URL('https://admin.example/transactions?'+params),p=momoTransactionPredicates(url,{search:'',status:''});
   return {totals:db.prepare(`SELECT count(*) AS n,sum(amount_minor) AS received,sum(credited_amount_minor) AS credited FROM records${p.where}`).get(...p.args),
    page:db.prepare(`SELECT id FROM records${p.where} ORDER BY id LIMIT 1`).all(...p.args)};};
  const current=select('account_scope_id='+account+'&group_id='+group);
  assert.deepEqual({...current.totals},{n:2,received:300,credited:100});
  assert.equal(current.page.length,1); // Totals cover all matching rows, not one page.
  assert.deepEqual({...select('receiving_account_id='+account).totals},{n:1,received:100,credited:100});
  assert.equal(select('account_scope_id='+other).totals.n,1);
  assert.equal(select('account_scope_id='+account+'&group_id='+other).totals.n,0);
  assert.throws(()=>select('receiving_account_id='+account+'&account_scope_id='+account),{code:'invalid_filter'});
  assert.throws(()=>select('account_scope_id=invalid'),{code:'invalid_parameter'});
 }finally{db.close();}
});

test('native account-scope response is explicit and does not claim a receiving destination',()=>{
 const scoped=momoTransactionPageRow(row(),account);
 assert.equal(scoped.capture_scope_account_id,account);
 assert.equal(scoped.receiving_account_id,null);
 assert.equal(scoped.receiving_context.basis,'unestablished');
 assert.equal(Object.hasOwn(momoTransactionPageRow(row(),null),'capture_scope_account_id'),false);
 assert.throws(()=>momoTransactionPageRow(row(),group),{code:'invalid_source_data'});
});
