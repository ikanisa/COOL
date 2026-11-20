import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../test-support/owned-pg17.mjs';
import {FINANCIAL_CATALOG_SQL,captureSyntheticFinancialPlan,importSyntheticFinancialGraph} from '../financial-import/import.mjs';
import {NATIVE_FIXTURE_TABLES,NATIVE_RECONCILE_TABLES,NativeSmsImportError,captureSyntheticNativeSmsPlan,importSyntheticNativeSmsGraph,reconcileSyntheticNativeSmsGraph} from './import.mjs';
const {Client}=pg;
const ids={source:'local-owner',target:'cloud-primary',member:'beneficiary',collection:'collection-one',sourceAuth:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',targetAuth:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',operation:'cccccccc-cccc-4ccc-8ccc-cccccccccccc',account:'11111111-1111-4111-8111-111111111111',install:'22222222-2222-4222-8222-222222222222',grant:'33333333-3333-4333-8333-333333333333',session:'44444444-4444-4444-8444-444444444444'};
const canonical=x=>Array.isArray(x)?'['+x.map(canonical).join(',')+']':x&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+canonical(x[k])).join(',')+'}':JSON.stringify(x);
const code=x=>e=>e instanceof NativeSmsImportError&&e.code===x;

test('synthetic accepted native SMS history and posted financial graph',{timeout:180000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_financial_import_fixture'});
 const clients=[];
 async function connect(db='collect_financial_import_fixture',user='fixture_operator'){
  const c=new Client({host:f.socket,port:f.port,database:db,user,connectionTimeoutMillis:3000});await c.connect();clients.push(c);return c;
 }
 try{
  const boot=await connect('postgres','fixture_bootstrap');
  await boot.query('CREATE ROLE fixture_operator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS');
  await boot.query('CREATE DATABASE collect_financial_import_fixture OWNER fixture_bootstrap');
  const a=await connect('collect_financial_import_fixture','fixture_bootstrap');
  await a.query(await readFile(new URL('../financial-import/fixture.sql',import.meta.url),'utf8'));
  await a.query(await readFile(new URL('./fixture.sql',import.meta.url),'utf8'));
  if(process.env.COLLECT_PRINT_SYNTHETIC_CATALOG==='1'){
   process.stdout.write('native catalog '+(await a.query(FINANCIAL_CATALOG_SQL,[NATIVE_FIXTURE_TABLES])).rows[0].value+'\n');
   process.stdout.write('reconcile catalog '+(await a.query(FINANCIAL_CATALOG_SQL,[NATIVE_RECONCILE_TABLES])).rows[0].value+'\n');
  }
  await a.query('INSERT INTO src.users VALUES($1,true),($2,true)',[ids.source,ids.member]);await a.query('INSERT INTO app.users VALUES($1,true),($2,true)',[ids.target,ids.member]);
  await a.query('INSERT INTO src.auth_users VALUES($1,true)',[ids.sourceAuth]);await a.query('INSERT INTO auth.users VALUES($1,true)',[ids.targetAuth]);
  await a.query('INSERT INTO src.auth_links VALUES($1,$2)',[ids.sourceAuth,ids.source]);await a.query('INSERT INTO private.auth_links VALUES($1,$2)',[ids.targetAuth,ids.target]);
  await a.query('INSERT INTO src.collections VALUES($1,$2)',[ids.collection,ids.source]);await a.query('INSERT INTO app.collections VALUES($1,$2)',[ids.collection,ids.target]);
  await a.query("INSERT INTO src.memberships VALUES('membership-one',$1,$2)",[ids.collection,ids.member]);await a.query("INSERT INTO app.memberships VALUES('membership-one',$1,$2)",[ids.collection,ids.member]);
  await a.query("INSERT INTO private.fixture_history_attestation VALUES($1,true,true,true,$2)",[ids.collection,'f'.repeat(64)]);
  await a.query("INSERT INTO private.fixture_fences VALUES('source',11,'fenced'),('target',22,'fenced');INSERT INTO private.fixture_admissions VALUES('settled',0)");
  for(let i=1;i<=2;i++){
   const sms='10000000-0000-4000-8000-00000000000'+i,attempt='20000000-0000-4000-8000-00000000000'+i,txn=sms,evidence='evidence-'+i,payment='payment-'+i,ledger='ledger-'+i;
   const body=String(i).repeat(64),smsSha=String(i+2).repeat(64),cipher='a'.repeat(64),date=`2026-01-01T00:00:0${i}.000Z`,request=`55555555-5555-4555-8555-55555555555${i}`;
   await a.query(`INSERT INTO src.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at)
    VALUES($1,$2,NULL,$3,$4,NULL,$5,$6,10,$7)`,[sms,ids.source,'envelope-'+i,body,'sms/'+sms,smsSha,date]);
   await a.query(`INSERT INTO src.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at)
    VALUES($1,$2,1,'fixture','v1','v1','v1','v1','{}',$3,'{}','{}','accepted',$4)`,[attempt,sms,body,date]);
   await a.query(`INSERT INTO src.momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,currency_scale,transaction_timezone,transaction_time_source,parse_attempt_id,mode,allocation_state,created_at,updated_at)
    VALUES($1,'account-one','mtn',NULL,'incoming_receipt',$2,'RWF',0,'Africa/Kigali','missing',$3,'historical','linked',$4,$4)`,[txn,i*1250,attempt,date]);
   await a.query("INSERT INTO src.momo_transaction_sources VALUES($1,$2,$3,'accepted',$4)",[txn,sms,attempt,date]);
   await a.query('INSERT INTO src.origins VALUES($1,$2,$3,$4,$5)',[sms,ids.collection,ids.source,body,smsSha]);
   const facts={event_kind:'incoming_receipt',payment_outcome:'successful',currency:'RWF',amount_minor:i*1250,source_mode:'catch_up',wallet_balance_after_minor:9000,counterparty_name:null,counterparty_identifier:null,transaction_at:null,transaction_datetime_raw:null,provider_transaction_id:null,original_transaction_id:null,fee_minor:null,transaction_time_source:null,transaction_timezone:null};
   await a.query("INSERT INTO src.jobs VALUES($1,$2,$3,$4,'completed',$5::jsonb)",[sms,txn,ids.collection,'b'.repeat(64),JSON.stringify(facts)]);
   await a.query("INSERT INTO src.scopes VALUES($1,$2,$3,'account-one')",[sms,txn,ids.collection]);
   await a.query(`INSERT INTO src.native_lineage VALUES($1,$2,$3,$4,$5,1,$6,NULL,'jobs',$7,$8,$9,$10,'finished',NULL,NULL,NULL,$11,'accepted','successful',true,true,false,false)`,[sms,ids.source,ids.account,ids.install,ids.grant,ids.session,request,'b'.repeat(64),'c'.repeat(64),'e'.repeat(64),attempt]);
   await a.query(`INSERT INTO private.fixture_native_dependencies VALUES($1,$2,$3,$4,$5,$6,$7,1,$8,NULL,$9,true,true,true,true,true,$10)`,[sms,ids.collection,ids.source,ids.target,ids.account,ids.install,ids.grant,ids.session,request,'d'.repeat(64)]);
   await a.query(`INSERT INTO src.payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,amount_minor,observed_at,created_at)
    VALUES($1,$2,$3,$4,$5,10,'application/octet-stream','operator_recorded',$6,$7,$8,$8)`,[evidence,ids.collection,ids.source,'evidence/'+evidence,body,'sms:'+body+':'+sms,i*1250,date]);
   await a.query("INSERT INTO src.payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at) VALUES($1,$2,$3,$4,$5,'reconciled',$6)",[payment,ids.collection,ids.member,evidence,i*1250,date]);
   await a.query("INSERT INTO src.momo_financial_links VALUES($1,$2,$3,$4,'synthetic',0,$5)",[txn,payment,ids.member,ids.source,date]);
   await a.query("INSERT INTO src.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES($1,$2,$3,$4,$5,'contribution',$6,$7,$8,$9)",[ledger,payment,ids.collection,ids.member,i*1250,evidence,ids.source,'request-'+i,date]);
   await a.query('INSERT INTO src.contribution_posting_snapshots VALUES($1,$2,$3,$3,$4)',[ledger,payment,1250*i*(i+1)/2,date]);
   for(const [key,entity,purpose,plain] of [['sms/'+sms,sms,'sms_receipt',smsSha],['evidence/'+evidence,evidence,'payment_evidence',body]]){
    const aad=(purpose==='sms_receipt'?'sms:':'evidence:')+entity+':'+plain;
    await a.query('INSERT INTO src.object_proofs VALUES($1,$2,$3,$4,$5,$6,$7,true)',[key,ids.source,entity,purpose,plain,cipher,aad]);await a.query('INSERT INTO private.object_proofs VALUES($1,$2,$3,$4,$5,$6,$7,true)',[key,ids.target,entity,purpose,plain,cipher,aad]);
   }
  }
  const key=randomBytes(32),request={version:'collect.synthetic-native-sms-import.v1',operation_id:ids.operation,collection_id:ids.collection,source_owner:ids.source,target_owner:ids.target,source_auth:ids.sourceAuth,target_auth:ids.targetAuth,source_epoch:'11',target_epoch:'22'};
  const base=()=>({mode:'synthetic',requestJson:canonical(request),key,connect:()=>connect()});
  const capture=async()=>({...await captureSyntheticNativeSmsPlan(base()),mode:'synthetic',key,connect:()=>connect()});
  const clear=()=>a.query('TRUNCATE app.contribution_posting_snapshots,app.ledger_entries,app.momo_financial_links,app.payments,app.payment_evidence,private.fixture_financial_receipts,app.momo_transaction_sources,app.momo_transactions,app.momo_parse_attempts,app.sms_receipts,private.origins,private.jobs,private.scopes,private.native_lineage,private.fixture_native_receipts');
  await t.test('managed calls refuse before a connection',async()=>{let called=false;const options={...base(),mode:'managed',connect:()=>{called=true;}};
   await assert.rejects(captureSyntheticNativeSmsPlan(options),code('managed_execution_closed'));await assert.rejects(importSyntheticNativeSmsGraph(options),code('managed_execution_closed'));await assert.rejects(reconcileSyntheticNativeSmsGraph(options),code('managed_execution_closed'));assert.equal(called,false);});
  await t.test('accepted source, attempt and job relation must agree',async()=>{
   for(const [mutation,restore] of [
    ["UPDATE src.momo_transaction_sources SET relation='conflict' WHERE raw_sms_id='10000000-0000-4000-8000-000000000001'","UPDATE src.momo_transaction_sources SET relation='accepted' WHERE raw_sms_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.native_lineage SET relation='duplicate' WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.native_lineage SET relation='accepted' WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.native_lineage SET attempt_id='20000000-0000-4000-8000-000000000002' WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.native_lineage SET attempt_id='20000000-0000-4000-8000-000000000001' WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.native_lineage SET observation_fingerprint=repeat('c',64) WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.native_lineage SET observation_fingerprint=repeat('b',64) WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.native_lineage SET facts_sha256='bad' WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.native_lineage SET facts_sha256=repeat('e',64) WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.momo_transactions SET parse_attempt_id='20000000-0000-4000-8000-000000000002' WHERE id='10000000-0000-4000-8000-000000000001'","UPDATE src.momo_transactions SET parse_attempt_id='20000000-0000-4000-8000-000000000001' WHERE id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.jobs SET posting_facts=jsonb_set(posting_facts,'{amount_minor}','1') WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.jobs SET posting_facts=jsonb_set(posting_facts,'{amount_minor}','1250') WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.jobs SET posting_facts=jsonb_set(posting_facts,'{wallet_balance_after_minor}','-1') WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.jobs SET posting_facts=jsonb_set(posting_facts,'{wallet_balance_after_minor}','9000') WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.jobs SET posting_facts=posting_facts-'wallet_balance_after_minor' WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.jobs SET posting_facts=jsonb_set(posting_facts,'{wallet_balance_after_minor}','9000') WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.jobs SET posting_facts=jsonb_set(posting_facts,'{payment_outcome}','\"failed\"') WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.jobs SET posting_facts=jsonb_set(posting_facts,'{payment_outcome}','\"successful\"') WHERE source_id='10000000-0000-4000-8000-000000000001'"]]){
     try{await a.query(mutation);await assert.rejects(captureSyntheticNativeSmsPlan(base()),code('native_graph_refused'));}finally{await a.query(restore);}}
   const old='10000000-0000-4000-8000-000000000001',other='30000000-0000-4000-8000-000000000001';
   async function rename(from,to){await a.query('UPDATE src.momo_transactions SET id=$2 WHERE id=$1',[from,to]);
    await a.query('UPDATE src.momo_transaction_sources SET transaction_id=$2 WHERE transaction_id=$1',[from,to]);
    await a.query('UPDATE src.jobs SET transaction_id=$2 WHERE transaction_id=$1',[from,to]);await a.query('UPDATE src.scopes SET transaction_id=$2 WHERE transaction_id=$1',[from,to]);}
   try{await rename(old,other);await assert.rejects(captureSyntheticNativeSmsPlan(base()),code('native_graph_refused'));}finally{await rename(other,old);}
  });
  await t.test('conflicted or nonlinked transactions are refused before either graph is written',async()=>{
   for(const [field,bad,good] of [['has_conflict',1,0],['allocation_state','needs_review','linked']]){
    await a.query(`UPDATE src.momo_transactions SET ${field}=$1 WHERE id=$2`,[bad,'10000000-0000-4000-8000-000000000001']);
    try{await assert.rejects(captureSyntheticNativeSmsPlan(base()),code('native_graph_refused'));
     const q=await a.query('SELECT (SELECT count(*) FROM app.sms_receipts)::int sms,(SELECT count(*) FROM app.payments)::int payments');assert.deepEqual(q.rows[0],{sms:0,payments:0});
    }finally{await a.query(`UPDATE src.momo_transactions SET ${field}=$1 WHERE id=$2`,[good,'10000000-0000-4000-8000-000000000001']);}
   }
  });
  await t.test('unsettled effects, live credentials, missing proofs and bad owner fail closed',async()=>{
   for(const [mutation,restore] of [
    ["UPDATE src.native_lineage SET upload_unresolved=true WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.native_lineage SET upload_unresolved=false WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.native_lineage SET phase='dispatched' WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.native_lineage SET phase='finished' WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.native_lineage SET lease_token='55555555-5555-4555-8555-555555555551' WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.native_lineage SET lease_token=NULL WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.native_lineage SET payment_outcome='unknown' WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.native_lineage SET payment_outcome='successful' WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.native_lineage SET storage_intent_settled=false WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.native_lineage SET storage_intent_settled=true WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.native_lineage SET delete_tombstone=true WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE src.native_lineage SET delete_tombstone=false WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE private.fixture_native_dependencies SET sessions_revoked=false WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE private.fixture_native_dependencies SET sessions_revoked=true WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE private.fixture_native_dependencies SET account_inert=false WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE private.fixture_native_dependencies SET account_inert=true WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE private.fixture_native_dependencies SET grant_id='55555555-5555-4555-8555-555555555551' WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE private.fixture_native_dependencies SET grant_id='33333333-3333-4333-8333-333333333333' WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE private.fixture_native_dependencies SET runtime_replay_disabled=false WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE private.fixture_native_dependencies SET runtime_replay_disabled=true WHERE source_id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE private.object_proofs SET verified=false WHERE object_key='sms/10000000-0000-4000-8000-000000000001'","UPDATE private.object_proofs SET verified=true WHERE object_key='sms/10000000-0000-4000-8000-000000000001'"],
    ["UPDATE private.object_proofs SET aad='wrong' WHERE object_key='sms/10000000-0000-4000-8000-000000000001'","UPDATE private.object_proofs SET aad='sms:10000000-0000-4000-8000-000000000001:'||repeat('3',64) WHERE object_key='sms/10000000-0000-4000-8000-000000000001'"],
    ["UPDATE src.sms_receipts SET originating_session_id='unsafe' WHERE id='10000000-0000-4000-8000-000000000001'","UPDATE src.sms_receipts SET originating_session_id=NULL WHERE id='10000000-0000-4000-8000-000000000001'"],
    ["UPDATE private.fixture_native_dependencies SET target_owner='someone-else' WHERE source_id='10000000-0000-4000-8000-000000000001'","UPDATE private.fixture_native_dependencies SET target_owner='cloud-primary' WHERE source_id='10000000-0000-4000-8000-000000000001'"]]){
     try{await a.query(mutation);await assert.rejects(captureSyntheticNativeSmsPlan(base()),code('native_graph_refused'));}finally{await a.query(restore);}}
   await a.query("UPDATE private.fixture_fences SET mode='open' WHERE side='source'");try{await assert.rejects(captureSyntheticNativeSmsPlan(base()),code('identity_or_fence_changed'));}finally{await a.query("UPDATE private.fixture_fences SET mode='fenced' WHERE side='source'");}
  });
  await t.test('changed source after capture is rejected',async()=>{const p=await capture();await a.query("UPDATE src.sms_receipts SET created_at='changed' WHERE id='10000000-0000-4000-8000-000000000001'");try{await assert.rejects(importSyntheticNativeSmsGraph(p),code('preimage_changed'));}finally{await a.query("UPDATE src.sms_receipts SET created_at='2026-01-01T00:00:01.000Z' WHERE id='10000000-0000-4000-8000-000000000001'");}});
  await t.test('target identity and target conflicts are checked again before insertion',async()=>{const p=await capture();
   await a.query('UPDATE auth.users SET active=false WHERE id=$1',[ids.targetAuth]);try{await assert.rejects(importSyntheticNativeSmsGraph(p),code('identity_or_fence_changed'));}finally{await a.query('UPDATE auth.users SET active=true WHERE id=$1',[ids.targetAuth]);}
   await a.query("INSERT INTO private.jobs VALUES('other','other','collection-one',repeat('b',64),'completed','{}')");
   try{await assert.rejects(importSyntheticNativeSmsGraph(p),code('target_native_conflict'));}finally{await a.query("DELETE FROM private.jobs WHERE source_id='other'");}
  });
  await t.test('source and target catalog drift cannot be hidden',async()=>{
   await a.query('ALTER TABLE src.momo_transactions ENABLE ROW LEVEL SECURITY');try{await assert.rejects(captureSyntheticNativeSmsPlan(base()),code('fixture_catalog_refused'));}finally{await a.query('ALTER TABLE src.momo_transactions DISABLE ROW LEVEL SECURITY');}
   await a.query('ALTER TABLE app.sms_receipts ADD COLUMN unexpected text');try{await assert.rejects(captureSyntheticNativeSmsPlan(base()),code('fixture_schema_changed'));}finally{await a.query('ALTER TABLE app.sms_receipts DROP COLUMN unexpected');}
  });
  await t.test('a concurrent source writer waits until the atomic import finishes',async()=>{const p=await capture();let pending,finished=false;
   p.connect=async()=>{const c=await connect(),query=c.query.bind(c);c.query=async(sql,...args)=>{
    if(String(sql).startsWith('INSERT INTO app.sms_receipts')){pending=a.query("UPDATE src.sms_receipts SET status='under_review' WHERE id='10000000-0000-4000-8000-000000000001'").then(()=>{finished=true;});
     await new Promise(resolve=>setTimeout(resolve,100));assert.equal(finished,false);}
    return query(sql,...args);};return c;};
   assert.deepEqual(await importSyntheticNativeSmsGraph(p),{status:'applied',sms_count:2});await pending;assert.equal(finished,true);
   await a.query("UPDATE src.sms_receipts SET status='received' WHERE id='10000000-0000-4000-8000-000000000001'");await clear();
  });
  await t.test('mid-import failure rolls back every graph row',async()=>{const p=await capture();p.connect=async()=>{const c=await connect(),query=c.query.bind(c);c.query=(sql,...args)=>String(sql).startsWith('INSERT INTO app.momo_transactions')?Promise.reject(Error('test failure')):query(sql,...args);return c;};
   await assert.rejects(importSyntheticNativeSmsGraph(p),code('fixture_transaction_failed'));assert.equal((await a.query('SELECT count(*)::int n FROM app.sms_receipts')).rows[0].n,0);});
  await t.test('uncertain commit has read-only reconciliation and no retry instruction',async()=>{const p=await capture();p.connect=async()=>{const c=await connect(),query=c.query.bind(c);c.query=async(sql,...args)=>{const result=await query(sql,...args);if(sql==='COMMIT')throw Error('lost acknowledgement');return result;};return c;};
   assert.deepEqual(await importSyntheticNativeSmsGraph(p),{status:'commit_unconfirmed_do_not_retry'});p.connect=()=>connect();assert.deepEqual(await reconcileSyntheticNativeSmsGraph(p),{status:'receipt_and_postimage_verified'});await clear();});
  await t.test('transfer preserves IDs and historical provenance while the cloud account stays primary',async()=>{const p=await capture();assert.equal(p.writeAuthorized,false);assert.deepEqual(await reconcileSyntheticNativeSmsGraph(p),{status:'receipt_not_visible_do_not_retry'});
   assert.deepEqual(await importSyntheticNativeSmsGraph(p),{status:'applied',sms_count:2});assert.deepEqual(await importSyntheticNativeSmsGraph(p),{status:'already_applied'});assert.deepEqual(await reconcileSyntheticNativeSmsGraph(p),{status:'receipt_and_postimage_verified'});
   const q=await a.query('SELECT id,owner_user_id,originating_session_id FROM app.sms_receipts ORDER BY id');assert.deepEqual(q.rows.map(x=>[x.id,x.owner_user_id,x.originating_session_id]),[['10000000-0000-4000-8000-000000000001',ids.target,null],['10000000-0000-4000-8000-000000000002',ids.target,null]]);
   const h=await a.query('SELECT source_id,principal_user_id,account_id::text,capture_session_id::text FROM private.native_lineage ORDER BY source_id');assert(h.rows.every(x=>x.principal_user_id===ids.target&&x.account_id===ids.account&&x.capture_session_id===ids.session));
   assert.deepEqual((await a.query('SELECT auth_id::text,user_id FROM private.auth_links')).rows,[{auth_id:ids.targetAuth,user_id:ids.target}]);
   const fp={...request,version:'collect.synthetic-financial-import.v1',operation_id:'dddddddd-dddd-4ddd-8ddd-dddddddddddd'};
   const financial=await captureSyntheticFinancialPlan({mode:'synthetic',requestJson:canonical(fp),key,connect:()=>connect()});
   assert.deepEqual(await importSyntheticFinancialGraph({...financial,mode:'synthetic',key,connect:()=>connect()}),{status:'applied',payment_count:2});
   assert.equal((await a.query('SELECT count(*)::int n FROM app.ledger_entries')).rows[0].n,2);await clear();});
  await t.test('reconciliation refuses RLS-hidden or altered target state',async()=>{const p=await capture();await importSyntheticNativeSmsGraph(p);
   await a.query("INSERT INTO app.momo_transactions SELECT (jsonb_populate_record(NULL::app.momo_transactions,to_jsonb(t)||jsonb_build_object('id','hidden-extra'))).* FROM app.momo_transactions t WHERE id='10000000-0000-4000-8000-000000000001'");
   await a.query('ALTER TABLE app.momo_transactions ENABLE ROW LEVEL SECURITY; ALTER TABLE app.momo_transactions FORCE ROW LEVEL SECURITY');
   try{await assert.rejects(reconcileSyntheticNativeSmsGraph(p),code('fixture_catalog_refused'));}finally{await a.query('ALTER TABLE app.momo_transactions NO FORCE ROW LEVEL SECURITY; ALTER TABLE app.momo_transactions DISABLE ROW LEVEL SECURITY');}
   await a.query("DELETE FROM app.momo_transactions WHERE id='hidden-extra'");
   await a.query("UPDATE app.sms_receipts SET status='rejected' WHERE id='10000000-0000-4000-8000-000000000001'");await assert.rejects(reconcileSyntheticNativeSmsGraph(p),code('postimage_changed'));await clear();});
 }finally{await Promise.allSettled(clients.map(c=>c.end()));const result=await f.close();assert.equal(result.removed,true);}
});
