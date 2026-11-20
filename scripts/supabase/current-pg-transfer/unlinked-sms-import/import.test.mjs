import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../test-support/owned-pg17.mjs';
import {verifyEnvironment,verifyBinaryPins,BIN} from '../../managed-identity-provider-compat/fixture-safety.mjs';
import {FINANCIAL_CATALOG_SQL} from '../financial-import/import.mjs';
import {UNLINKED_FIXTURE_TABLES,UNLINKED_RECONCILE_TABLES,UnlinkedSmsImportError,
 captureSyntheticUnlinkedPlan,importSyntheticUnlinkedQuarantine,reconcileSyntheticUnlinkedQuarantine} from './import.mjs';
const {Client}=pg;
const ids={source:'local-owner',target:'cloud-primary',collection:'collection-one',sourceAuth:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 targetAuth:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',operation:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
 account:'11111111-1111-4111-8111-111111111111',install:'22222222-2222-4222-8222-222222222222',
 grant:'33333333-3333-4333-8333-333333333333',session:'44444444-4444-4444-8444-444444444444'};
const canonical=x=>Array.isArray(x)?'['+x.map(canonical).join(',')+']':x&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+canonical(x[k])).join(',')+'}':JSON.stringify(x);
const code=x=>e=>e instanceof UnlinkedSmsImportError&&e.code===x;
const sms=i=>'10000000-0000-4000-8000-'+String(i).padStart(12,'0');
const attempt=i=>'20000000-0000-4000-8000-'+String(i).padStart(12,'0');
const requestId=i=>'55555555-5555-4555-8555-'+String(i).padStart(12,'0');
const sha=i=>i.toString(16).padStart(64,'0');

test('inert unlinked SMS quarantine on an owned PG17 cluster',{timeout:180000},async t=>{
 verifyEnvironment(process.env);await verifyBinaryPins();process.env.COLLECT_SYNTHETIC_PG_BIN=BIN;
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_unlinked_sms_fixture'}),clients=[];
 async function connect(db='collect_unlinked_sms_fixture',user='fixture_operator'){
  const c=new Client({host:f.socket,port:f.port,database:db,user,connectionTimeoutMillis:3000});c.on('error',()=>{});await c.connect();clients.push(c);return c;
 }
 try{
  const boot=await connect('postgres','fixture_bootstrap');
  await boot.query('CREATE ROLE fixture_operator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS; CREATE ROLE fixture_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS');
  await boot.query('CREATE DATABASE collect_unlinked_sms_fixture OWNER fixture_bootstrap');
  const a=await connect('collect_unlinked_sms_fixture','fixture_bootstrap');
  await a.query(await readFile(new URL('../financial-import/fixture.sql',import.meta.url),'utf8'));
  await a.query(await readFile(new URL('../native-sms-import/fixture.sql',import.meta.url),'utf8'));
  await a.query(await readFile(new URL('./fixture.sql',import.meta.url),'utf8'));
  if(process.env.COLLECT_PRINT_SYNTHETIC_CATALOG==='1'){
   process.stdout.write('unlinked catalog '+(await a.query(FINANCIAL_CATALOG_SQL,[UNLINKED_FIXTURE_TABLES])).rows[0].value+'\n');
   process.stdout.write('unlinked reconcile catalog '+(await a.query(FINANCIAL_CATALOG_SQL,[UNLINKED_RECONCILE_TABLES])).rows[0].value+'\n');return;
  }
  await a.query('INSERT INTO src.users VALUES($1,true)',[ids.source]);await a.query('INSERT INTO app.users VALUES($1,true)',[ids.target]);
  await a.query('INSERT INTO src.auth_users VALUES($1,true)',[ids.sourceAuth]);await a.query('INSERT INTO auth.users VALUES($1,true)',[ids.targetAuth]);
  await a.query('INSERT INTO src.auth_links VALUES($1,$2)',[ids.sourceAuth,ids.source]);await a.query('INSERT INTO private.auth_links VALUES($1,$2)',[ids.targetAuth,ids.target]);
  await a.query('INSERT INTO src.collections VALUES($1,$2)',[ids.collection,ids.source]);await a.query('INSERT INTO app.collections VALUES($1,$2)',[ids.collection,ids.target]);
  await a.query("INSERT INTO private.fixture_fences VALUES('source',11,'fenced'),('target',22,'fenced');INSERT INTO private.fixture_admissions VALUES('settled',0)");
  for(let i=1;i<=33;i++){
   const source=sms(i),parse=attempt(i),body=sha(i),object=sha(i+100),date='2026-01-01T00:00:00.000Z';
   // The 14 incomplete / three unknown-wallet categories are synthetic; the
   // real aggregate does not identify their overlap or individual records.
   const linked=i<=10,alloc=linked?'linked':i<=24?'not_applicable':i%2?'unallocated':'needs_review';
   const nullable=alloc==='not_applicable',event=nullable?'unknown':'incoming_receipt',ref=alloc==='unallocated'?null:nullable?null:'ref-'+i;
   const amount=nullable?null:i*1250,currency=nullable?null:'RWF',scale=nullable?null:0,wallet=i%7===0?null:9000+i;
   await a.query(`INSERT INTO src.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at)
    VALUES($1,$2,NULL,$3,$4,NULL,$5,$6,10,$7)`,[source,ids.source,'envelope-'+i,body,'sms/'+source,object,date]);
   await a.query(`INSERT INTO src.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at)
    VALUES($1,$2,1,'fixture','v1','v1','v1','v1','{}',$3,NULL,'{}','accepted',$4)`,[parse,source,body,date]);
   await a.query(`INSERT INTO src.momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,currency_scale,wallet_balance_after_minor,transaction_timezone,transaction_time_source,parse_attempt_id,mode,allocation_state,created_at,updated_at)
    VALUES($1,'account-one','mtn',$2,$3,$4,$5,$6,$7,'Africa/Kigali','missing',$8,'historical',$9,$10,$10)`,[source,ref,event,amount,currency,scale,wallet,parse,alloc,date]);
   await a.query("INSERT INTO src.momo_transaction_sources VALUES($1,$1,$2,'accepted',$3)",[source,parse,date]);
   await a.query('INSERT INTO src.origins VALUES($1,$2,$3,$4,$5)',[source,ids.collection,ids.source,body,object]);
   const facts=i===11?null:i===12?{wallet_balance_after_minor:null,amount_minor:null}:i===13?{}:i<=24&&i>10?
    {wallet_balance_after_minor:100+i,event_kind:null}:
    {event_kind:event,payment_outcome:'successful',currency,amount_minor:amount,source_mode:'catch_up',wallet_balance_after_minor:100+i};
   await a.query(`INSERT INTO src.jobs(source_id,transaction_id,collection_id,source_fingerprint,state,posting_facts,posting_output,posting_next_attempt_at,posting_failure_count,posting_last_error)
    VALUES($1,$1,$2,$3,'completed',$4::jsonb,$5::jsonb,0,0,NULL)`,[source,ids.collection,'b'.repeat(64),facts===null?null:JSON.stringify(facts),facts===null?null:'{}']);
   await a.query("INSERT INTO src.scopes VALUES($1,$1,$2,'account-one')",[source,ids.collection]);
   await a.query(`INSERT INTO src.native_lineage VALUES($1,$2,$3,$4,$5,1,$6,NULL,'jobs',$7,$8,$9,$10,'finished',NULL,NULL,NULL,$11,'accepted',$12,true,true,false,false)`,
    [source,ids.source,ids.account,ids.install,ids.grant,ids.session,requestId(i),'b'.repeat(64),'c'.repeat(64),'e'.repeat(64),parse,i===11?'unknown':'successful']);
   await a.query('INSERT INTO src.object_proofs VALUES($1,$2,$3,$4,$5,$6,$7,true)',
    ['sms/'+source,ids.source,source,'sms_receipt',object,sha(i+200),'sms:'+source+':'+object]);
   if(linked)await a.query('INSERT INTO src.momo_financial_links VALUES($1,$2,$3,$4,$5,0,$6)',[source,'payment-'+i,'member-'+i,ids.source,'synthetic',date]);
  }
  await a.query(`INSERT INTO src.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at)
   VALUES($1,$2,2,'fixture','v1','v1','v1','v1','{}',$3,'{}','{}','superseded','2026-01-01T00:00:01Z')`,[attempt(99),sms(11),sha(11)]);
  const key=randomBytes(32),request={version:'collect.synthetic-unlinked-quarantine.v1',operation_id:ids.operation,collection_id:ids.collection,
   source_owner:ids.source,target_owner:ids.target,source_auth:ids.sourceAuth,target_auth:ids.targetAuth,source_epoch:'11',target_epoch:'22'};
  const base=()=>({mode:'synthetic',requestJson:canonical(request),key,connect:()=>connect()});
  const capture=async()=>({...await captureSyntheticUnlinkedPlan(base()),mode:'synthetic',key,connect:()=>connect()});
  const clear=()=>a.query('TRUNCATE private.fixture_unlinked_items,private.fixture_unlinked_receipts,private.fixture_unlinked_claims');
  const counts=async()=> (await a.query(`SELECT (SELECT count(*) FROM private.fixture_unlinked_claims)::int claims,
   (SELECT count(*) FROM private.fixture_unlinked_receipts)::int receipts,(SELECT count(*) FROM private.fixture_unlinked_items)::int items,
   (SELECT count(*) FROM app.sms_receipts)::int target_sms,(SELECT count(*) FROM app.momo_transactions)::int target_tx,
   (SELECT count(*) FROM private.jobs)::int target_jobs,(SELECT count(*) FROM app.payments)::int payments,
   (SELECT count(*) FROM app.ledger_entries)::int ledger,(SELECT count(*) FROM app.momo_financial_links)::int financial_links`)).rows[0];
  await t.test('managed execution is refused before connecting',async()=>{
   let called=false;const options={...base(),mode:'managed',connect:()=>{called=true;}};
   await assert.rejects(captureSyntheticUnlinkedPlan(options),code('managed_execution_closed'));
   await assert.rejects(importSyntheticUnlinkedQuarantine(options),code('managed_execution_closed'));
   await assert.rejects(reconcileSyntheticUnlinkedQuarantine(options),code('managed_execution_closed'));assert.equal(called,false);
  });
  await t.test('synthetic graph contradictions and ambiguous relationships fail closed',async()=>{
   for(const [forward,back] of [
    ["UPDATE src.native_lineage SET relation='conflict' WHERE source_id=$1","UPDATE src.native_lineage SET relation='accepted' WHERE source_id=$1"],
    ["UPDATE src.native_lineage SET observation_fingerprint=repeat('d',64) WHERE source_id=$1","UPDATE src.native_lineage SET observation_fingerprint=repeat('b',64) WHERE source_id=$1"],
    ["UPDATE src.jobs SET state='retry' WHERE source_id=$1","UPDATE src.jobs SET state='completed' WHERE source_id=$1"],
    ["UPDATE src.native_lineage SET upload_unresolved=true WHERE source_id=$1","UPDATE src.native_lineage SET upload_unresolved=false WHERE source_id=$1"],
    ["UPDATE src.momo_transactions SET has_conflict=1 WHERE id=$1","UPDATE src.momo_transactions SET has_conflict=0 WHERE id=$1"]]){
    await a.query(forward,[sms(11)]);try{await assert.rejects(captureSyntheticUnlinkedPlan(base()),code('unlinked_graph_refused'));}finally{await a.query(back,[sms(11)]);}
   }
   await a.query("INSERT INTO src.momo_transaction_sources VALUES($1,$1,$2,'conflict','2026-01-01T00:00:01Z')",[sms(11),attempt(99)]);
   try{await assert.rejects(captureSyntheticUnlinkedPlan(base()),code('unlinked_graph_refused'));}
   finally{await a.query('DELETE FROM src.momo_transaction_sources WHERE raw_sms_id=$1 AND parse_attempt_id=$2',[sms(11),attempt(99)]);}
  });
  await t.test('identity, target fences, table visibility and runtime privileges are checked',async()=>{
   await a.query("UPDATE private.fixture_fences SET mode='open' WHERE side='source'");
   try{await assert.rejects(captureSyntheticUnlinkedPlan(base()),code('identity_or_fence_changed'));}finally{await a.query("UPDATE private.fixture_fences SET mode='fenced' WHERE side='source'");}
   await a.query('UPDATE auth.users SET active=false WHERE id=$1',[ids.targetAuth]);
   try{await assert.rejects(captureSyntheticUnlinkedPlan(base()),code('identity_or_fence_changed'));}finally{await a.query('UPDATE auth.users SET active=true WHERE id=$1',[ids.targetAuth]);}
   await a.query('ALTER TABLE src.momo_financial_links ENABLE ROW LEVEL SECURITY');
   try{await assert.rejects(captureSyntheticUnlinkedPlan(base()),code('fixture_catalog_refused'));}finally{await a.query('ALTER TABLE src.momo_financial_links DISABLE ROW LEVEL SECURITY');}
   await a.query('GRANT SELECT ON private.fixture_unlinked_items TO fixture_runtime');
   try{await assert.rejects(captureSyntheticUnlinkedPlan(base()),code('fixture_runtime_access_refused'));}finally{await a.query('REVOKE SELECT ON private.fixture_unlinked_items FROM fixture_runtime');}
   await a.query('ALTER TABLE src.jobs ADD COLUMN unexpected text');
   try{await assert.rejects(captureSyntheticUnlinkedPlan(base()),code('fixture_schema_changed'));}finally{await a.query('ALTER TABLE src.jobs DROP COLUMN unexpected');}
  });
  await t.test('changed JSON constraint helper and previously inserted invalid text are refused',async()=>{
   const definition=(await a.query("SELECT pg_get_functiondef('app.json_valid(text)'::regprocedure) definition")).rows[0].definition;
   for(const field of ['profile_json','output_json','validation_json']){
    try{
     await a.query('CREATE OR REPLACE FUNCTION app.json_valid(value text) RETURNS boolean LANGUAGE plpgsql IMMUTABLE STRICT AS $$BEGIN RETURN true;END$$');
     await a.query(`UPDATE src.momo_parse_attempts SET ${field}='not-valid-json' WHERE id=$1`,[attempt(11)]);
     await assert.rejects(captureSyntheticUnlinkedPlan(base()),code('fixture_helper_changed'));
     await a.query(definition);
     await assert.rejects(captureSyntheticUnlinkedPlan(base()),code('unlinked_parse_json_invalid'));
    }finally{
     await a.query(definition);
     await a.query(`UPDATE src.momo_parse_attempts SET ${field}=$2 WHERE id=$1`,[attempt(11),field==='output_json'?null:'{}']);
    }
   }
  });
  await t.test('a newly linked or changed source after planning is refused before a claim',async()=>{
   const p=await capture();await a.query("INSERT INTO src.momo_financial_links VALUES($1,'new-payment','member',$2,'synthetic',0,'2026-01-01')",[sms(11),ids.source]);
   try{await assert.rejects(importSyntheticUnlinkedQuarantine(p),code('unlinked_graph_refused'));assert.equal((await counts()).claims,0);}
   finally{await a.query('DELETE FROM src.momo_financial_links WHERE transaction_id=$1',[sms(11)]);}
   await a.query("UPDATE src.jobs SET posting_last_error='synthetic-change' WHERE source_id=$1",[sms(11)]);
   try{await assert.rejects(importSyntheticUnlinkedQuarantine(p),code('preimage_changed'));assert.equal((await counts()).claims,0);}
   finally{await a.query('UPDATE src.jobs SET posting_last_error=NULL WHERE source_id=$1',[sms(11)]);}
   await a.query("UPDATE src.jobs SET posting_facts='null'::jsonb,posting_output='null'::jsonb WHERE source_id=$1",[sms(11)]);
   try{await assert.rejects(importSyntheticUnlinkedQuarantine(p),code('preimage_changed'));assert.equal((await counts()).claims,0);}
   finally{await a.query('UPDATE src.jobs SET posting_facts=NULL,posting_output=NULL WHERE source_id=$1',[sms(11)]);}
  });
  await t.test('lost claim acknowledgement holds without a data write or automatic retry',async()=>{
   const p=await capture();p.connect=async()=>{const c=await connect(),q=c.query.bind(c);c.query=async(sql,...args)=>{
    const result=await q(sql,...args);if(sql==='COMMIT')throw Error('synthetic lost claim acknowledgement');return result;};return c;};
   assert.deepEqual(await importSyntheticUnlinkedQuarantine(p),{status:'claim_commit_unconfirmed_do_not_retry'});p.connect=()=>connect();
   assert.equal((await counts()).claims,1);assert.equal((await counts()).items,0);
   await assert.rejects(importSyntheticUnlinkedQuarantine(p),code('claim_exists_do_not_retry'));
   const other={...request,operation_id:'dddddddd-dddd-4ddd-8ddd-dddddddddddd'};
   await assert.rejects(captureSyntheticUnlinkedPlan({...base(),requestJson:canonical(other)}),code('claim_exists_do_not_retry'));
   assert.deepEqual(await reconcileSyntheticUnlinkedQuarantine(p),{status:'receipt_or_claim_not_visible_do_not_retry'});await clear();
  });
  await t.test('source drift after a claim cannot trigger an automatic second attempt',async()=>{
   const p=await capture();let n=0;p.connect=async()=>{
    if(++n===2)await a.query("UPDATE src.jobs SET posting_last_error='after-claim' WHERE source_id=$1",[sms(11)]);
    return connect();};
   try{await assert.rejects(importSyntheticUnlinkedQuarantine(p),code('preimage_changed_after_claim'));
    assert.equal((await counts()).claims,1);assert.equal((await counts()).items,0);
   }finally{await a.query('UPDATE src.jobs SET posting_last_error=NULL WHERE source_id=$1',[sms(11)]);}
   p.connect=()=>connect();await assert.rejects(importSyntheticUnlinkedQuarantine(p),code('claim_exists_do_not_retry'));await clear();
  });
  await t.test('a failure after claiming rolls back all items while the one-use claim remains',async()=>{
   const p=await capture();let n=0;p.connect=async()=>{const c=await connect(),q=c.query.bind(c),which=++n;c.query=(sql,...args)=>
    which===2&&String(sql).startsWith('INSERT INTO private.fixture_unlinked_items')?Promise.reject(Error('synthetic item failure')):q(sql,...args);return c;};
   await assert.rejects(importSyntheticUnlinkedQuarantine(p),code('fixture_transaction_failed'));p.connect=()=>connect();
   assert.equal((await counts()).claims,1);assert.equal((await counts()).receipts,0);assert.equal((await counts()).items,0);
   await assert.rejects(importSyntheticUnlinkedQuarantine(p),code('claim_exists_do_not_retry'));await clear();
  });
  await t.test('a lost data COMMIT acknowledgement is reconciled only by a read-only check',async()=>{
   const p=await capture();let n=0;p.connect=async()=>{const c=await connect(),q=c.query.bind(c),which=++n;c.query=async(sql,...args)=>{
    const result=await q(sql,...args);if(which===2&&sql==='COMMIT')throw Error('synthetic lost data acknowledgement');return result;};return c;};
   assert.deepEqual(await importSyntheticUnlinkedQuarantine(p),{status:'commit_unconfirmed_do_not_retry'});p.connect=()=>connect();
   assert.deepEqual(await reconcileSyntheticUnlinkedQuarantine(p),{status:'quarantine_receipt_and_postimage_verified',replayEnabled:false});
   await assert.rejects(importSyntheticUnlinkedQuarantine(p),code('claim_exists_do_not_retry'));await clear();
  });
  await t.test('concurrent use of one plan admits exactly one quarantine operation',async()=>{
   const p=await capture(),out=await Promise.allSettled([importSyntheticUnlinkedQuarantine(p),importSyntheticUnlinkedQuarantine(p)]);
   assert.equal(out.filter(x=>x.status==='fulfilled'&&x.value.status==='quarantined').length,1);
   assert.equal(out.filter(x=>x.status==='rejected'&&x.reason instanceof UnlinkedSmsImportError&&x.reason.code==='claim_exists_do_not_retry').length,1);
   assert.equal((await counts()).items,23);assert.equal((await counts()).payments,0);await clear();
  });
  await t.test('an ordinary source writer waits behind the quarantine transaction locks',async()=>{
   const p=await capture(),observer=await connect('collect_unlinked_sms_fixture','fixture_bootstrap');let n=0,writer;
   p.connect=async()=>{const c=await connect(),q=c.query.bind(c),which=++n;c.query=async(sql,...args)=>{
    if(which===2&&String(sql).startsWith('INSERT INTO private.fixture_unlinked_items')){
     writer=a.query("UPDATE src.sms_receipts SET status='under_review' WHERE id=$1",[sms(11)]);void writer.catch(()=>{});
     let blocked=false;const deadline=Date.now()+2000;
     while(Date.now()<deadline&&!blocked){
      const b=(await observer.query('SELECT $1::int=ANY(pg_blocking_pids($2::int)) blocked',[c.processID,a.processID])).rows[0];blocked=b.blocked;
      if(!blocked)await new Promise(resolve=>setTimeout(resolve,25));
     }
     assert.equal(blocked,true,'source writer never reached the expected PostgreSQL lock wait');
    }
    return q(sql,...args);};return c;};
   try{assert.equal((await importSyntheticUnlinkedQuarantine(p)).status,'quarantined');await writer;}
   finally{if(writer)await writer.catch(()=>{});await a.query("UPDATE src.sms_receipts SET status='received' WHERE id=$1",[sms(11)]);await clear();}
  });
  await t.test('SQL NULL and JSON null in JSONB columns remain distinguishable in the archive',async()=>{
   await a.query("UPDATE src.jobs SET posting_facts='null'::jsonb,posting_output='null'::jsonb WHERE source_id=$1",[sms(14)]);
   try{
    const p=await capture();await importSyntheticUnlinkedQuarantine(p);
    const q=await a.query(`SELECT payload->'job'->'posting_facts' facts,payload->'job_sql_nulls' sql_nulls
     FROM private.fixture_unlinked_items WHERE source_id=ANY($1::text[]) ORDER BY source_id`,[[sms(11),sms(14)]]);
    assert.equal(q.rows.length,2);assert.equal(q.rows[0].facts,null);assert.equal(q.rows[1].facts,null);
    assert.deepEqual(q.rows[0].sql_nulls,{posting_facts:true,posting_output:true});
    assert.deepEqual(q.rows[1].sql_nulls,{posting_facts:false,posting_output:false});
   }finally{await clear();await a.query("UPDATE src.jobs SET posting_facts=$2::jsonb,posting_output='{}'::jsonb WHERE source_id=$1",[sms(14),JSON.stringify({wallet_balance_after_minor:114,event_kind:null})]);}
  });
  await t.test('unverified synthetic object metadata stays unverified and is not a Storage proof',async()=>{
   await a.query('UPDATE src.object_proofs SET verified=false WHERE entity_id=$1',[sms(11)]);
   try{const p=await capture();await importSyntheticUnlinkedQuarantine(p);
    const q=await a.query("SELECT payload->'synthetic_object_metadata'->'verified' verified FROM private.fixture_unlinked_items WHERE source_id=$1",[sms(11)]);
    assert.equal(q.rows[0].verified,false);
    assert.equal((await reconcileSyntheticUnlinkedQuarantine(p)).status,'quarantine_receipt_and_postimage_verified');
   }finally{await clear();await a.query('UPDATE src.object_proofs SET verified=true WHERE entity_id=$1',[sms(11)]);}
  });
  await t.test('mixed source imports only 23 unlinked graphs and preserves nulls without activating any work',async()=>{
   const selected=(await a.query(`SELECT count(*) FILTER(WHERE posting_facts IS NULL OR jsonb_typeof(posting_facts)<>'object'
    OR NOT(posting_facts ?& ARRAY['event_kind','payment_outcome','currency','amount_minor','source_mode'])
    OR posting_facts->'event_kind'='null'::jsonb OR posting_facts->'payment_outcome'='null'::jsonb
    OR posting_facts->'currency'='null'::jsonb OR posting_facts->'amount_minor'='null'::jsonb OR posting_facts->'source_mode'='null'::jsonb)::int facts_unknown,
    count(*) FILTER(WHERE posting_facts IS NULL OR jsonb_typeof(posting_facts)<>'object' OR NOT(posting_facts ? 'wallet_balance_after_minor')
     OR posting_facts->'wallet_balance_after_minor'='null'::jsonb)::int wallet_unknown FROM src.jobs`)).rows[0];
   assert.deepEqual(selected,{facts_unknown:14,wallet_unknown:3});
   const p=await capture();assert.equal(p.writeAuthorized,false);assert.equal(JSON.parse(p.planJson).sms_count,23);
   assert.deepEqual(await importSyntheticUnlinkedQuarantine(p),{status:'quarantined',sms_count:23,replayEnabled:false});
   assert.deepEqual(await counts(),{claims:1,receipts:1,items:23,target_sms:0,target_tx:0,target_jobs:0,payments:0,ledger:0,financial_links:0});
   const q=await a.query(`SELECT source_id,payload->'job'->'posting_facts' facts,payload->'transaction'->'amount_minor' amount,
    payload->'transaction'->'wallet_balance_after_minor' wallet,jsonb_array_length(payload->'parse_attempts') attempts
    FROM private.fixture_unlinked_items WHERE source_id=ANY($1::text[]) ORDER BY source_id`,[[sms(11),sms(12),sms(13),sms(14)]]);
   assert.equal(q.rows.length,4);assert.equal(q.rows[0].facts,null);assert.equal(q.rows[0].attempts,2);
   assert.deepEqual(q.rows[1].facts,{amount_minor:null,wallet_balance_after_minor:null});assert.deepEqual(q.rows[2].facts,{});
   assert.equal(q.rows[1].amount,null);assert.equal(q.rows[3].wallet,null);
   assert.deepEqual((await a.query('SELECT auth_id::text,user_id FROM private.auth_links')).rows,[{auth_id:ids.targetAuth,user_id:ids.target}]);
   const runtime=await connect('collect_unlinked_sms_fixture','fixture_runtime');
   await assert.rejects(runtime.query('SELECT count(*) FROM private.fixture_unlinked_items'),/permission denied/);
   await assert.rejects(importSyntheticUnlinkedQuarantine(p),code('claim_exists_do_not_retry'));
   assert.deepEqual(await reconcileSyntheticUnlinkedQuarantine(p),{status:'quarantine_receipt_and_postimage_verified',replayEnabled:false});await clear();
  });
  await t.test('tampered or RLS-hidden target cannot reconcile as a valid archive',async()=>{
   const p=await capture();await importSyntheticUnlinkedQuarantine(p);
   await a.query('ALTER TABLE private.fixture_unlinked_items ENABLE ROW LEVEL SECURITY;ALTER TABLE private.fixture_unlinked_items FORCE ROW LEVEL SECURITY');
   try{await assert.rejects(reconcileSyntheticUnlinkedQuarantine(p),code('fixture_catalog_refused'));}
   finally{await a.query('ALTER TABLE private.fixture_unlinked_items NO FORCE ROW LEVEL SECURITY;ALTER TABLE private.fixture_unlinked_items DISABLE ROW LEVEL SECURITY');}
   // SMS 10 sorts before SMS 12 just like SMS 11, so key-only tampering
   // preserves the payload order and would evade an order-only digest.
   await a.query('UPDATE private.fixture_unlinked_items SET source_id=$2 WHERE source_id=$1',[sms(11),sms(10)]);
   await assert.rejects(reconcileSyntheticUnlinkedQuarantine(p),code('postimage_changed'));
   await a.query('UPDATE private.fixture_unlinked_items SET source_id=$2 WHERE source_id=$1',[sms(10),sms(11)]);
   await a.query("UPDATE private.fixture_unlinked_items SET payload=jsonb_set(payload,'{transaction,amount_minor}','999') WHERE source_id=$1",[sms(11)]);
   await assert.rejects(reconcileSyntheticUnlinkedQuarantine(p),code('postimage_changed'));await clear();
  });
 }finally{await Promise.allSettled(clients.map(c=>c.end()));const closed=await f.close();assert.equal(closed.removed,true);await verifyBinaryPins();}
});
