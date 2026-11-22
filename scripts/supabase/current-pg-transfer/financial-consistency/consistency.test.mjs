import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import pg from '../../node_modules/pg/lib/index.js';
import {startOwnedPg17,resolvePg17Bin} from '../test-support/owned-pg17.mjs';

const {Client}=pg;
const sql=await readFile(new URL('./consistency.sql',import.meta.url),'utf8');
const boundary=sql.indexOf('BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;');
assert.ok(boundary>0);const preflight=sql.slice(0,boundary),transaction=sql.slice(boundary);
const fixtureSql=await readFile(new URL('./fixture.sql',import.meta.url),'utf8');

async function within(promise,ms){
 let timer;try{return await Promise.race([promise.then(()=>true),new Promise(resolve=>{timer=setTimeout(()=>resolve(false),ms);})]);}
 finally{clearTimeout(timer);}
}
async function closeClient(client){
 const stream=client?.connection?.stream;let listener;
 try{
  if(!stream){await within(Promise.resolve().then(()=>client.end()).catch(()=>{}),2000);return;}
  let done;const closed=new Promise(resolve=>{done=resolve;});listener=()=>done();stream.once('close',listener);if(stream.closed)done();
  const end=Promise.resolve().then(()=>client.end()).catch(()=>{});
  if(!await within(Promise.all([end,closed]),2000)){
   stream.destroy();if(stream.closed)done();
   if(!await within(Promise.all([end,closed]),2000))throw Error('owned client closure unconfirmed');
  }
 }finally{if(listener&&stream)stream.removeListener('close',listener);}
}

test('financial consistency is aggregate-only and read-only on owned PostgreSQL 17',{timeout:120000},async t=>{
 const fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap'});
 const db=new Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'fixture_bootstrap',connectionTimeoutMillis:3000});
 db.on('error',()=>{});
 const run=async()=>{
  await db.query(preflight);const result=await db.query(transaction),selected=(Array.isArray(result)?result:[result]).filter(x=>x.command==='SELECT');
  assert.equal(selected.length,1);assert.equal(selected[0].rows.length,1);
  const value=selected[0].rows[0].consistency;
  assert.doesNotMatch(JSON.stringify(value),/private-(?:payment|evidence|ledger|member|group|sms|transaction|owner)|a{64}|b{64}|c{64}/);
  assert.equal(value.write_authorized,false);assert.equal(value.complete_history_verified,false);return value;
 };
 try{
  await db.connect();
  assert.deepEqual((await db.query("SELECT inet_server_addr() IS NULL AS socket,current_setting('server_version_num')::int/10000 AS major")).rows[0],{socket:true,major:17});
  await db.query(fixtureSql);
  await t.test('consistent observed chain and native paths produce only aggregate counts',async()=>{
   const v=await run();assert.equal(v.format,'collect.financial-consistency.v1');
   assert.equal(v.timestamps.ledger_entries,3);assert.equal(v.timestamps.snapshot_text_differs_from_ledger,0);
   assert.equal(v.balances.observed_positive_only_candidate_groups,1);assert.equal(v.balances.group_balance_model_contradicted_groups,0);
   assert.equal(v.balances.member_balance_model_contradicted_groups,0);assert.equal(v.balances.chronological_model_contradicted_groups,0);
   assert.equal(v.native_sms.native_candidate_payments,3);assert.equal(v.native_sms.digest_comparable,3);
   assert.equal(v.native_sms.digest_mismatch,0);assert.equal(v.native_sms.reference_mismatch,0);
   assert.equal(v.native_sms.linked_fields_mismatch,0);assert.equal(v.native_sms.digest_unknown,0);
   assert.equal(v.native_sms.accepted_linkage_comparable,3);assert.equal(v.native_sms.accepted_linkage_mismatch,0);assert.equal(v.native_sms.accepted_linkage_unknown,0);
  });
  await t.test('psql executes precheck and transaction on one physical session',async()=>{
   const result=spawnSync(join(resolvePg17Bin(),'psql'),['-X','-h',fixture.socket,'-p',String(fixture.port),'-U','fixture_bootstrap','-d','postgres','-qAt','-v','ON_ERROR_STOP=1','-f',fileURLToPath(new URL('./consistency.sql',import.meta.url))],
    {encoding:'utf8',timeout:10000,env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
   assert.equal(result.status,0,'psql diagnostic must succeed on its owned socket');const observation=JSON.parse(result.stdout);
   assert.equal(observation.format,'collect.financial-consistency.v1');assert.equal(observation.timestamps.ledger_entries,3);assert.equal(observation.write_authorized,false);
  });
  await t.test('equal instants are counted and balance order can still describe one possible sequence',async()=>{
   await db.query("UPDATE app.ledger_entries SET posted_at='2026-01-01T00:00:00.000Z' WHERE id='private-ledger-b'; UPDATE app.contribution_posting_snapshots SET posted_at='2026-01-01T00:00:00.000Z' WHERE ledger_entry_id='private-ledger-b'");
   try{const v=await run();assert.equal(v.balances.eligible_groups_with_tied_instants,1);
    assert.equal(v.balances.eligible_ledger_entries_at_tied_instants,2);assert.equal(v.balances.group_balance_model_contradicted_groups,0);}
   finally{await db.query("UPDATE app.ledger_entries SET posted_at='2026-01-01T00:00:01.000Z' WHERE id='private-ledger-b'; UPDATE app.contribution_posting_snapshots SET posted_at='2026-01-01T00:00:01.000Z' WHERE ledger_entry_id='private-ledger-b'");}
  });
  await t.test('group and member balance contradictions remain distinct',async()=>{
   await db.query("UPDATE app.contribution_posting_snapshots SET group_balance_after_minor=31 WHERE ledger_entry_id='private-ledger-b'");
   try{const v=await run();assert.equal(v.balances.group_balance_model_contradicted_groups,1);assert.equal(v.balances.member_balance_unknown_groups,1);
    assert.equal(v.balances.chronological_model_unknown_groups,1);}
   finally{await db.query("UPDATE app.contribution_posting_snapshots SET group_balance_after_minor=30 WHERE ledger_entry_id='private-ledger-b'");}
   await db.query("UPDATE app.contribution_posting_snapshots SET member_balance_after_minor=9 WHERE ledger_entry_id='private-ledger-a'");
   try{const v=await run();assert.equal(v.balances.group_balance_model_contradicted_groups,0);assert.equal(v.balances.member_balance_model_contradicted_groups,1);}
   finally{await db.query("UPDATE app.contribution_posting_snapshots SET member_balance_after_minor=10 WHERE ledger_entry_id='private-ledger-a'");}
  });
  await t.test('duplicate group balances cannot prove a positive-only serial order',async()=>{
   await db.query("UPDATE app.contribution_posting_snapshots SET group_balance_after_minor=10 WHERE ledger_entry_id='private-ledger-b'");
   try{const v=await run();assert.equal(v.balances.group_balance_model_contradicted_groups,1);assert.equal(v.balances.member_balance_unknown_groups,1);}
   finally{await db.query("UPDATE app.contribution_posting_snapshots SET group_balance_after_minor=30 WHERE ledger_entry_id='private-ledger-b'");}
  });
  await t.test('time order contradictions do not imply an impossible financial sum',async()=>{
   await db.query("UPDATE app.ledger_entries SET posted_at='2026-01-01T00:00:03.000Z' WHERE id='private-ledger-a'; UPDATE app.contribution_posting_snapshots SET posted_at='2026-01-01T00:00:03.000Z' WHERE ledger_entry_id='private-ledger-a'");
   try{const v=await run();assert.equal(v.balances.group_balance_model_contradicted_groups,0);assert.equal(v.balances.chronological_model_contradicted_groups,1);}
   finally{await db.query("UPDATE app.ledger_entries SET posted_at='2026-01-01T00:00:00.000Z' WHERE id='private-ledger-a'; UPDATE app.contribution_posting_snapshots SET posted_at='2026-01-01T00:00:00.000Z' WHERE ledger_entry_id='private-ledger-a'");}
  });
  await t.test('missing, invalid, or unequal snapshot timestamps are not called balance mismatches',async()=>{
   await db.query("UPDATE app.contribution_posting_snapshots SET posted_at=NULL WHERE ledger_entry_id='private-ledger-a'");
   try{const v=await run();assert.equal(v.timestamps.snapshot_time_unknown_or_noncanonical,1);assert.equal(v.timestamps.snapshot_text_differs_from_ledger,0);
    assert.equal(v.balances.ineligible_or_unknown_groups,1);assert.equal(v.balances.group_balance_model_contradicted_groups,0);}
   finally{await db.query("UPDATE app.contribution_posting_snapshots SET posted_at='2026-01-01T00:00:00.000Z' WHERE ledger_entry_id='private-ledger-a'");}
   await db.query("UPDATE app.ledger_entries SET posted_at='bad-date' WHERE id='private-ledger-a'");
   try{const v=await run();assert.equal(v.timestamps.ledger_time_unknown_or_noncanonical,1);assert.equal(v.balances.ineligible_or_unknown_groups,1);}
   finally{await db.query("UPDATE app.ledger_entries SET posted_at='2026-01-01T00:00:00.000Z' WHERE id='private-ledger-a'");}
   await db.query("UPDATE app.contribution_posting_snapshots SET posted_at='2026-01-01T00:00:01.000Z' WHERE ledger_entry_id='private-ledger-a'");
   try{const v=await run();assert.equal(v.timestamps.snapshot_text_differs_from_ledger,1);assert.equal(v.balances.ineligible_or_unknown_groups,1);}
   finally{await db.query("UPDATE app.contribution_posting_snapshots SET posted_at='2026-01-01T00:00:00.000Z' WHERE ledger_entry_id='private-ledger-a'");}
  });
  await t.test('reversal and missing snapshot are ineligible, not fabricated mismatches',async()=>{
   await db.query("UPDATE app.ledger_entries SET kind='reversal' WHERE id='private-ledger-a'");
   try{const v=await run();assert.equal(v.balances.ineligible_or_unknown_groups,1);assert.equal(v.balances.member_balance_unknown_groups,1);}
   finally{await db.query("UPDATE app.ledger_entries SET kind='contribution' WHERE id='private-ledger-a'");}
   await db.query("DELETE FROM app.contribution_posting_snapshots WHERE ledger_entry_id='private-ledger-a'");
   try{const v=await run();assert.equal(v.timestamps.snapshot_time_unknown_or_noncanonical,1);assert.equal(v.balances.ineligible_or_unknown_groups,1);}
   finally{await db.query("INSERT INTO app.contribution_posting_snapshots VALUES('private-ledger-a','private-payment-a',10,10,'2026-01-01T00:00:00.000Z')");}
  });
  await t.test('known SMS mismatches and missing values have separate counts',async()=>{
   await db.query("UPDATE app.payment_evidence SET object_sha256=repeat('f',64),object_key='bad',external_reference='sms:wrong' WHERE id='private-evidence-a'");
   try{const v=await run();assert.equal(v.native_sms.digest_mismatch,1);assert.equal(v.native_sms.reference_mismatch,1);assert.equal(v.native_sms.evidence_key_mismatch,1);assert.equal(v.native_sms.digest_unknown,0);}
   finally{await db.query("UPDATE app.payment_evidence SET object_sha256=repeat('a',64),object_key='evidence/private-evidence-a',external_reference='sms:'||repeat('a',64)||':private-sms-a' WHERE id='private-evidence-a'");}
   await db.query("UPDATE app.sms_receipts SET body_sha256=NULL WHERE id='private-sms-a'");
   try{const v=await run();assert.equal(v.native_sms.digest_unknown,1);assert.equal(v.native_sms.digest_mismatch,0);assert.equal(v.native_sms.reference_unknown,1);}
   finally{await db.query("UPDATE app.sms_receipts SET body_sha256=repeat('a',64) WHERE id='private-sms-a'");}
  });
  await t.test('ambiguous or incomplete native source paths remain unknown',async()=>{
   await db.query("INSERT INTO app.momo_transaction_sources VALUES('private-transaction-a','private-sms-b','00000000-0000-0000-0000-000000000002','accepted')");
   try{const v=await run();assert.equal(v.native_sms.candidate_path_unknown_or_ambiguous,1);assert.equal(v.native_sms.digest_unknown,1);assert.equal(v.native_sms.digest_mismatch,0);}
   finally{await db.query("DELETE FROM app.momo_transaction_sources WHERE transaction_id='private-transaction-a' AND raw_sms_id='private-sms-b'");}
   await db.query("DELETE FROM private.burimunsi_auto_sms_jobs WHERE source_id='private-sms-a'");
   try{const v=await run();assert.equal(v.native_sms.candidate_path_unknown_or_ambiguous,1);assert.equal(v.native_sms.reference_unknown,1);}
   finally{await db.query("INSERT INTO private.burimunsi_auto_sms_jobs VALUES('private-sms-a','private-transaction-a','private-group','completed','successful','00000000-0000-0000-0000-000000000001','private-account','accepted')");}
  });
  await t.test('accepted source/job relation and parse-attempt links distinguish conflicts from unknown',async()=>{
   await db.query("UPDATE app.momo_transaction_sources SET relation='conflict' WHERE raw_sms_id='private-sms-a'; UPDATE private.burimunsi_auto_sms_jobs SET relation='conflict' WHERE source_id='private-sms-a'");
   try{const v=await run();assert.equal(v.native_sms.accepted_linkage_mismatch,1);assert.equal(v.native_sms.accepted_linkage_unknown,0);}
   finally{await db.query("UPDATE app.momo_transaction_sources SET relation='accepted' WHERE raw_sms_id='private-sms-a'; UPDATE private.burimunsi_auto_sms_jobs SET relation='accepted' WHERE source_id='private-sms-a'");}
   await db.query("UPDATE private.burimunsi_auto_sms_jobs SET attempt_id='00000000-0000-0000-0000-000000000002' WHERE source_id='private-sms-a'");
   try{const v=await run();assert.equal(v.native_sms.accepted_linkage_mismatch,1);assert.equal(v.native_sms.accepted_linkage_unknown,0);}
   finally{await db.query("UPDATE private.burimunsi_auto_sms_jobs SET attempt_id='00000000-0000-0000-0000-000000000001' WHERE source_id='private-sms-a'");}
   await db.query("UPDATE app.momo_transactions SET parse_attempt_id=NULL WHERE id='private-transaction-a'");
   try{const v=await run();assert.equal(v.native_sms.accepted_linkage_unknown,1);assert.equal(v.native_sms.accepted_linkage_mismatch,0);}
   finally{await db.query("UPDATE app.momo_transactions SET parse_attempt_id='00000000-0000-0000-0000-000000000001' WHERE id='private-transaction-a'");}
   await db.query("UPDATE app.momo_parse_attempts SET source_body_sha256=repeat('f',64) WHERE raw_sms_id='private-sms-a'");
   try{const v=await run();assert.equal(v.native_sms.accepted_linkage_mismatch,1);}
   finally{await db.query("UPDATE app.momo_parse_attempts SET source_body_sha256=repeat('a',64) WHERE raw_sms_id='private-sms-a'");}
  });
  await t.test('unknown native identity is not declared a mismatch',async()=>{
   await db.query("UPDATE app.payment_evidence SET external_reference='operator-reference' WHERE id='private-evidence-a'; DELETE FROM private.burimunsi_auto_sms_jobs WHERE source_id='private-sms-a'");
   try{const v=await run();assert.equal(v.native_sms.native_candidate_payments,2);assert.equal(v.native_sms.payments_without_native_marker,1);}
   finally{await db.query("UPDATE app.payment_evidence SET external_reference='sms:'||repeat('a',64)||':private-sms-a' WHERE id='private-evidence-a'; INSERT INTO private.burimunsi_auto_sms_jobs VALUES('private-sms-a','private-transaction-a','private-group','completed','successful','00000000-0000-0000-0000-000000000001','private-account','accepted')");}
  });
  await t.test('duplicate payment identifiers are refused instead of collapsing rows',async()=>{
   await db.query("INSERT INTO app.payments SELECT * FROM app.payments WHERE id='private-payment-a'");
   try{await assert.rejects(run(),e=>e.code==='55000'&&e.message==='financial_consistency_payment_identity_refused');}
   finally{await db.query("ROLLBACK; DELETE FROM app.payments WHERE ctid IN (SELECT ctid FROM app.payments WHERE id='private-payment-a' LIMIT 1)");}
  });
  await t.test('a different database is refused before table access',async()=>{
   await db.query('CREATE DATABASE financial_consistency_other');
   const other=new Client({host:fixture.socket,port:fixture.port,database:'financial_consistency_other',user:'fixture_bootstrap',connectionTimeoutMillis:3000});
   other.on('error',()=>{});
   try{await other.connect();await assert.rejects(other.query(preflight),e=>e.code==='55000'&&e.message==='financial_consistency_transaction_refused');
    await other.query('ROLLBACK');}
   finally{await closeClient(other);await db.query('DROP DATABASE financial_consistency_other');}
  });
  await t.test('precheck and locked transaction must use the same database session',async()=>{
   const fresh=()=>new Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'fixture_bootstrap',connectionTimeoutMillis:3000});
   const one=fresh(),two=fresh();one.on('error',()=>{});two.on('error',()=>{});
   try{await one.connect();await two.connect();await one.query(preflight);
    await assert.rejects(two.query(transaction),e=>e.code==='55000'&&e.message==='financial_consistency_transaction_refused');await two.query('ROLLBACK');}
   finally{await closeClient(one);await closeClient(two);}
  });
  await t.test('concurrent committed inheritance and RLS are visible after the relation lock',async()=>{
   await db.query('CREATE ROLE financial_consistency_race_reader LOGIN; GRANT USAGE ON SCHEMA app,private TO financial_consistency_race_reader; GRANT SELECT ON ALL TABLES IN SCHEMA app,private TO financial_consistency_race_reader');
   for(const scenario of ['inheritance','row_security']){
    const reader=new Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'financial_consistency_race_reader',connectionTimeoutMillis:3000});reader.on('error',()=>{});let pending;
    try{await reader.connect();const pid=(await reader.query('SELECT pg_backend_pid() pid')).rows[0].pid;
     await db.query('BEGIN; LOCK TABLE app.sms_receipts IN ACCESS EXCLUSIVE MODE');
     await db.query(scenario==='inheritance'?'CREATE TABLE app.sms_receipts_race_child() INHERITS(app.sms_receipts)':'ALTER TABLE app.sms_receipts ENABLE ROW LEVEL SECURITY');
     await reader.query(preflight);let settled=false;
     pending=reader.query(transaction).then(()=>({accepted:true}),error=>({error})).then(x=>(settled=true,x));
     let waiting=false;for(let i=0;i<120;i++){
      const q=await db.query("SELECT wait_event_type='Lock' AS waiting FROM pg_stat_activity WHERE pid=$1",[pid]);
      if(q.rows[0]?.waiting){waiting=true;break}if(settled)break;await new Promise(resolve=>setTimeout(resolve,25));
     }
     assert.equal(waiting,true,'diagnostic must wait for the concurrent DDL lock');await db.query('COMMIT');
     const result=await pending;assert.equal(result.accepted,undefined);assert.equal(result.error?.code,'42501');assert.equal(result.error?.message,'financial_consistency_visibility_refused');
    }finally{
     await db.query('ROLLBACK').catch(()=>{});if(pending)await pending;await reader.query('ROLLBACK').catch(()=>{});await closeClient(reader);
     if(scenario==='inheritance')await db.query('DROP TABLE IF EXISTS app.sms_receipts_race_child');else await db.query('ALTER TABLE app.sms_receipts DISABLE ROW LEVEL SECURITY');
    }
   }
  });
  await t.test('RLS-filtered readers and roles lacking SELECT are refused',async()=>{
   await db.query('CREATE ROLE financial_consistency_reader; GRANT USAGE ON SCHEMA app,private TO financial_consistency_reader; GRANT SELECT ON ALL TABLES IN SCHEMA app,private TO financial_consistency_reader; ALTER TABLE app.payments ENABLE ROW LEVEL SECURITY; SET ROLE financial_consistency_reader');
   try{await assert.rejects(run(),e=>e.code==='42501');}
   finally{await db.query('ROLLBACK; RESET ROLE; ALTER TABLE app.payments DISABLE ROW LEVEL SECURITY');}
   await db.query('REVOKE SELECT ON app.sms_receipts FROM financial_consistency_reader; SET ROLE financial_consistency_reader');
   try{await assert.rejects(run(),e=>e.code==='42501');}
   finally{await db.query('ROLLBACK; RESET ROLE');}
  });
  await t.test('inherited tables and missing columns are refused',async()=>{
   await db.query('CREATE TABLE app.payments_child() INHERITS(app.payments)');
   try{await assert.rejects(run(),e=>e.code==='42501'&&e.message==='financial_consistency_visibility_refused');}
   finally{await db.query('ROLLBACK; DROP TABLE app.payments_child');}
   await db.query('ALTER TABLE app.sms_receipts DROP COLUMN body_sha256');
   try{await assert.rejects(run(),e=>e.code==='55000'&&e.message==='financial_consistency_columns_refused');}
   finally{await db.query('ROLLBACK');}
  });
 }finally{try{await closeClient(db);}finally{const closed=await fixture.close();assert.equal(closed.removed,true,'owned PostgreSQL cleanup must be confirmed');}}
});
