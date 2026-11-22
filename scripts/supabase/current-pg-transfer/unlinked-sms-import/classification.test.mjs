import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import pg from '../../node_modules/pg/lib/index.js';
import {startOwnedPg17,resolvePg17Bin} from '../test-support/owned-pg17.mjs';
import {verifyEnvironment,verifyBinaryPins,BIN} from '../../managed-identity-provider-compat/fixture-safety.mjs';
const sql=await readFile(new URL('./classification.sql',import.meta.url),'utf8');
const boundary=sql.indexOf('BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;');
assert.ok(boundary>0);const preflight=sql.slice(0,boundary),transaction=sql.slice(boundary);
const fixture=await readFile(new URL('../financial-consistency/native-readiness-v3/fixture.sql',import.meta.url),'utf8');
const a='10000000-0000-4000-8000-000000000001',b='10000000-0000-4000-8000-000000000002';
test('unlinked classification is aggregate-only on owned PostgreSQL 17',{timeout:120000},async t=>{
 verifyEnvironment(process.env);await verifyBinaryPins();process.env.COLLECT_SYNTHETIC_PG_BIN=BIN;
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_unlinked_classification_fixture'}),clients=[];
 const connect=async(user='fixture_bootstrap')=>{const c=new pg.Client({host:f.socket,port:f.port,database:'postgres',user,connectionTimeoutMillis:3000});c.on('error',()=>{});await c.connect();clients.push(c);return c;};
 let c;
 try{
  c=await connect();await c.query(fixture);
  await c.query(`ALTER TABLE app.momo_transactions ADD COLUMN provider_transaction_id text,ADD COLUMN currency_scale bigint,ADD COLUMN wallet_balance_after_minor bigint;
   ALTER TABLE private.burimunsi_auto_sms_jobs ADD COLUMN phase text;
   UPDATE app.momo_transactions SET provider_transaction_id='synthetic-ref',currency_scale=0,wallet_balance_after_minor=42;
   UPDATE private.burimunsi_auto_sms_jobs SET phase='finished'`);
  const run=async(client=c)=>{await client.query(preflight);const result=await client.query(transaction),rows=(Array.isArray(result)?result:[result]).filter(x=>x.command==='SELECT');
   assert.equal(rows.length,1);assert.equal(rows[0].rows.length,1);const x=rows[0].rows[0].observation;
   assert.doesNotMatch(JSON.stringify(x),/10000000-0000|private-(?:account|payment)|a{64}|b{64}|c{64}|d{64}/);
   assert.equal(x.write_authorized,false);assert.equal(x.complete_graph_verified,false);assert.equal(x.source_frozen,false);return x;};
  await t.test('linked baseline and absent unlinked cohort are classified',async()=>{
   const x=await run();assert.deepEqual(x.scope,{receipts:2,linked:2,unlinked:0,link_unknown:0,multiple_paths:0});
  });
  await t.test('actual psql sends the preflight and locked read in the same local session',async()=>{
   const result=spawnSync(join(resolvePg17Bin(),'psql'),['-X','-h',f.socket,'-p',String(f.port),'-U','fixture_bootstrap','-d','postgres','-qAt','-v','ON_ERROR_STOP=1','-f',fileURLToPath(new URL('./classification.sql',import.meta.url))],
    {encoding:'utf8',timeout:10000,env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
   assert.equal(result.status,0,'owned psql must complete');const observed=JSON.parse(result.stdout);assert.equal(observed.scope.linked,2);assert.equal(observed.write_authorized,false);
  });
  await t.test('unlinked allocation, SQL null, JSON null and absent wallet keys remain distinct',async()=>{
   await c.query('DELETE FROM app.momo_financial_links WHERE transaction_id=$1',[a]);
   await c.query("UPDATE app.momo_transactions SET allocation_state='not_applicable',event_kind='unknown',provider_transaction_id=NULL,amount_minor=NULL,currency=NULL,currency_scale=NULL,wallet_balance_after_minor=NULL WHERE id=$1",[a]);
   await c.query('UPDATE private.burimunsi_auto_sms_jobs SET posting_facts=NULL WHERE source_id=$1',[a]);
   let x=await run();assert.equal(x.scope.unlinked,1);assert.equal(x.unlinked.allocation_not_applicable,1);assert.equal(x.unlinked.amount_null,1);
   assert.equal(x.unlinked.provider_reference_null,1);assert.equal(x.unlinked.transaction_wallet_null,1);assert.equal(x.unlinked.posting_facts_sql_null,1);
   assert.equal(x.unlinked.posting_facts_incomplete,1);assert.equal(x.unlinked.wallet_key_missing,0);assert.equal(x.unlinked.wallet_json_null,0);
   await c.query("UPDATE private.burimunsi_auto_sms_jobs SET posting_facts='{}' WHERE source_id=$1",[a]);x=await run();
   assert.equal(x.unlinked.posting_facts_sql_null,0);assert.equal(x.unlinked.posting_facts_object,1);assert.equal(x.unlinked.wallet_key_missing,1);
   await c.query("UPDATE private.burimunsi_auto_sms_jobs SET posting_facts='{\"wallet_balance_after_minor\":null}' WHERE source_id=$1",[a]);x=await run();
   assert.equal(x.unlinked.wallet_key_missing,0);assert.equal(x.unlinked.wallet_json_null,1);
   await c.query("UPDATE private.burimunsi_auto_sms_jobs SET posting_facts='null'::jsonb WHERE source_id=$1",[a]);x=await run();
   assert.equal(x.unlinked.posting_facts_json_null,1);assert.equal(x.unlinked.posting_facts_sql_null,0);assert.equal(x.unlinked.posting_facts_incomplete,1);
  });
  await t.test('multiple candidate paths or missing graph remain unknown, never falsely unlinked',async()=>{
   await c.query('INSERT INTO app.momo_transaction_sources SELECT * FROM app.momo_transaction_sources WHERE raw_sms_id=$1',[a]);
   try{const x=await run();assert.equal(x.scope.multiple_paths,1);assert.equal(x.scope.link_unknown,1);assert.equal(x.scope.unlinked,0);}
   finally{await c.query('DELETE FROM app.momo_transaction_sources WHERE ctid IN (SELECT ctid FROM app.momo_transaction_sources WHERE raw_sms_id=$1 LIMIT 1)',[a]);}
   await c.query('DELETE FROM app.momo_transactions WHERE id=$1',[a]);
   try{const x=await run();assert.equal(x.scope.link_unknown,1);assert.equal(x.scope.unlinked,0);}
   finally{await c.query("INSERT INTO app.momo_transactions VALUES($1,'00000000-0000-0000-0000-000000000001','private-account',0,'not_applicable','unknown',NULL,'live',NULL,NULL,NULL,NULL)",[a]);}
  });
  await t.test('inconsistent accepted relation and graph are reported as unverified',async()=>{
   await c.query("UPDATE app.momo_transaction_sources SET relation='conflict' WHERE raw_sms_id=$1",[a]);
   await c.query("UPDATE private.burimunsi_auto_sms_jobs SET source_fingerprint=repeat('f',64) WHERE source_id=$1",[a]);
   try{const x=await run();assert.equal(x.unlinked.relation_not_accepted_or_unknown,1);assert.equal(x.unlinked.fingerprint_mismatch_or_unknown,1);}
   finally{await c.query("UPDATE app.momo_transaction_sources SET relation='accepted' WHERE raw_sms_id=$1",[a]);await c.query("UPDATE private.burimunsi_auto_sms_jobs SET source_fingerprint=repeat('c',64) WHERE source_id=$1",[a]);}
  });
  await t.test('missing job is not reported as an existing job with SQL-null facts',async()=>{
   await c.query('CREATE TEMP TABLE saved_unlinked_job AS SELECT * FROM private.burimunsi_auto_sms_jobs WHERE source_id=$1',[a]);
   await c.query('DELETE FROM private.burimunsi_auto_sms_jobs WHERE source_id=$1',[a]);
   try{const x=await run();assert.equal(x.scope.unlinked,1);assert.equal(x.unlinked.job_missing,1);
    assert.equal(x.unlinked.graph_mismatch_or_unknown,1);assert.equal(x.unlinked.posting_facts_sql_null,0);
    assert.equal(x.unlinked.posting_facts_json_null,0);assert.equal(x.unlinked.posting_facts_object,0);
    assert.equal(x.unlinked.posting_facts_incomplete,0);
   }finally{await c.query('INSERT INTO private.burimunsi_auto_sms_jobs SELECT * FROM saved_unlinked_job;DROP TABLE saved_unlinked_job');}
  });
  await t.test('a nonzero or SQL-null conflict flag is separately reported',async()=>{
   for(const value of [1,null]){
    await c.query('UPDATE app.momo_transactions SET has_conflict=$2 WHERE id=$1',[a,value]);
    const x=await run();assert.equal(x.unlinked.conflict_nonzero_or_unknown,1);assert.equal(x.unlinked.graph_mismatch_or_unknown,0);
   }
   await c.query('UPDATE app.momo_transactions SET has_conflict=0 WHERE id=$1',[a]);
   assert.equal((await run()).unlinked.conflict_nonzero_or_unknown,0);
  });
  await t.test('preflight and locked transaction must share a physical session',async()=>{
   const one=await connect(),two=await connect();await one.query(preflight);
   await assert.rejects(two.query(transaction),e=>e.code==='55000'&&e.message==='unlinked_source_session_refused');await two.query('ROLLBACK');
  });
  await t.test('locked snapshot sees concurrently committed inheritance and row-security changes',async()=>{
   await c.query('CREATE ROLE unlinked_race_reader LOGIN;GRANT USAGE ON SCHEMA app,private TO unlinked_race_reader;GRANT SELECT ON ALL TABLES IN SCHEMA app,private TO unlinked_race_reader');
   for(const scenario of ['inheritance','row_security']){
    const reader=await connect('unlinked_race_reader');let pending;
    try{
     await c.query('BEGIN;LOCK TABLE app.sms_receipts IN ACCESS EXCLUSIVE MODE');
     await c.query(scenario==='inheritance'?'CREATE TABLE app.unlinked_race_child() INHERITS(app.sms_receipts)':'ALTER TABLE app.sms_receipts ENABLE ROW LEVEL SECURITY');
     await reader.query(preflight);pending=reader.query(transaction).then(()=>({accepted:true}),error=>({error}));
     let waiting=false;const deadline=Date.now()+2500;
     while(Date.now()<deadline&&!waiting){
      waiting=(await c.query('SELECT $1::int=ANY(pg_blocking_pids($2::int)) waiting',[c.processID,reader.processID])).rows[0].waiting;
      if(!waiting)await new Promise(resolve=>setTimeout(resolve,25));
     }
     assert.equal(waiting,true,'diagnostic did not wait behind the concurrent DDL lock');await c.query('COMMIT');
     const result=await pending;assert.equal(result.accepted,undefined);assert.equal(result.error?.code,'42501');assert.equal(result.error?.message,'unlinked_source_visibility_refused');
    }finally{
     await c.query('ROLLBACK').catch(()=>{});if(pending)await pending;await reader.query('ROLLBACK').catch(()=>{});
     if(scenario==='inheritance')await c.query('DROP TABLE IF EXISTS app.unlinked_race_child');else await c.query('ALTER TABLE app.sms_receipts DISABLE ROW LEVEL SECURITY');
    }
   }
  });
  await t.test('hidden data, missing SELECT, inheritance and missing columns refuse observation',async()=>{
   await c.query('CREATE ROLE unlinked_reader LOGIN;GRANT USAGE ON SCHEMA app,private TO unlinked_reader;GRANT SELECT ON ALL TABLES IN SCHEMA app,private TO unlinked_reader;ALTER TABLE app.sms_receipts ENABLE ROW LEVEL SECURITY');
   const reader=await connect('unlinked_reader');
   try{await assert.rejects(run(reader),e=>e.code==='42501'&&e.message==='unlinked_source_visibility_refused');}
   finally{await reader.query('ROLLBACK');await c.query('ALTER TABLE app.sms_receipts DISABLE ROW LEVEL SECURITY');}
   await c.query('REVOKE SELECT ON app.momo_transactions FROM unlinked_reader');
   try{await assert.rejects(run(reader),e=>e.code==='42501');}finally{await reader.query('ROLLBACK');}
   await c.query('CREATE TABLE app.unlinked_test_child() INHERITS(app.sms_receipts)');
   try{await assert.rejects(run(),e=>e.code==='42501'&&e.message==='unlinked_source_visibility_refused');}finally{await c.query('ROLLBACK;DROP TABLE app.unlinked_test_child');}
   await c.query('ALTER TABLE app.momo_transactions DROP COLUMN provider_transaction_id');
   try{await assert.rejects(run(),e=>e.code==='55000'&&e.message==='unlinked_source_columns_refused');}finally{await c.query('ROLLBACK');}
  });
 }finally{await Promise.allSettled(clients.map(c=>c.end()));const closed=await f.close();assert.equal(closed.removed,true);await verifyBinaryPins();}
});
