// Actual forward-migration bytes, actual predecessor function bodies, and an
// owned socket-only PostgreSQL 17. Data, authorization and provider transport
// are explicit synthetic doubles; no Cloud or external provider calls.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID,createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {verifyBinaryPins,verifyEnvironment,BIN} from '../managed-identity-provider-compat/fixture-safety.mjs';

verifyEnvironment(process.env);await verifyBinaryPins();
const {Client}=createRequire(import.meta.url)('pg');
const prior=await readFile(new URL('./native-parser-review-preimage.sql',import.meta.url),'utf8');
const migration=await readFile(new URL('../../../supabase/migrations/20261117090952_burimunsi_native_parse_review.sql',import.meta.url),'utf8');
const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_native_parse_review_fixture'});
assert.equal(f.bin,BIN);const clients=[];
async function connect(user){const c=new Client({host:f.socket,port:f.port,database:'postgres',user,connectionTimeoutMillis:5000});c.on('error',()=>{});await c.connect();clients.push(c);return c;}
let checks=0;
try{
 const root=await connect('fixture_bootstrap');
 await root.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS;CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_runtime;CREATE ROLE collect_importer;GRANT collect_runtime,anon TO postgres;
 CREATE SCHEMA private AUTHORIZATION postgres;CREATE SCHEMA app AUTHORIZATION postgres;CREATE SCHEMA collect_ops AUTHORIZATION postgres;CREATE SCHEMA net AUTHORIZATION postgres;
 GRANT USAGE ON SCHEMA private TO collect_runtime,anon;GRANT USAGE ON SCHEMA collect_ops TO postgres;`);
 const db=await connect('postgres');
 await db.query(`CREATE TABLE private.collect_fence_control(singleton boolean,mode text);
 INSERT INTO private.collect_fence_control VALUES(true,'fenced');
 CREATE TABLE private.burimunsi_auto_sms_jobs(source_id text PRIMARY KEY,collection_id text,source_fingerprint text,profile_sha256 text,
  state text,phase text,lease_token uuid,lease_until bigint,attempt_count integer,retry_lease uuid,last_error text,next_attempt_at bigint,updated_at bigint,
  posting_facts jsonb,posting_output jsonb,receiving_account_id text DEFAULT 'synthetic-wallet',event_identity_sha256 text DEFAULT repeat('e',64),
  event_inbox_sha256 text,event_has_service_time boolean DEFAULT false,created_at bigint DEFAULT 0,transaction_id text,relation text,attempt_id uuid,facts_sha256 text,payment_outcome text);
 CREATE TABLE private.burimunsi_transaction_scopes(transaction_id text,collection_id text,receiving_account_id text,source_binding_id text,
  source_binding_version integer,policy_version text,created_at bigint,native_source_id text);
 CREATE TABLE private.burimunsi_scopes(collection_id text,receiving_account_id text);
 CREATE TABLE private.burimunsi_native_receipt_origins(source_id text,collection_id text,fingerprint text,body_sha256 text);
 CREATE TABLE app.momo_receiving_accounts(id text,provider text,timezone text,status text);
 INSERT INTO app.momo_receiving_accounts VALUES('synthetic-wallet','synthetic-provider','Africa/Kigali','active');
 INSERT INTO private.burimunsi_scopes VALUES('synthetic-group','synthetic-wallet');
 CREATE TABLE app.momo_transactions(id text,receiving_account_id text,provider text,provider_transaction_id text,event_kind text,original_transaction_id text,
  amount_minor bigint,currency text,currency_scale integer,payer_name text,payer_identifier text,payer_last3 text,transaction_at text,
  transaction_datetime_raw text,transaction_timezone text,transaction_time_source text,fee_minor bigint,wallet_balance_after_minor bigint,
  parse_attempt_id text,mode text,allocation_state text,created_at text,updated_at text);
 CREATE TABLE app.momo_parse_attempts(id text,raw_sms_id text,attempt_number integer,model_id text,schema_version text,prompt_version text,
  parser_version text,profile_version text,profile_json text,source_body_sha256 text,output_json text,validation_json text,outcome text,created_at text);
 CREATE TABLE app.momo_transaction_sources(transaction_id text,raw_sms_id text,parse_attempt_id text,relation text,created_at text);
 CREATE FUNCTION app.strftime(text) RETURNS text LANGUAGE sql AS $$ SELECT '2026-11-17T00:00:00.000Z'::text $$;
 CREATE TABLE private.imported_history(source_id text PRIMARY KEY);
 CREATE FUNCTION private.fixture_import_guard() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF EXISTS(SELECT 1 FROM private.imported_history WHERE source_id=OLD.source_id) THEN RAISE EXCEPTION 'imported_history_denied';END IF;RETURN NEW;END$$;
 CREATE TRIGGER imported_history_guard BEFORE UPDATE ON private.burimunsi_auto_sms_jobs FOR EACH ROW EXECUTE FUNCTION private.fixture_import_guard();
 CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF current_setting('role',true)='collect_runtime' THEN RAISE EXCEPTION 'denied';END IF;END $$;
 CREATE FUNCTION private.burimunsi_setup_fence() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF current_setting('test.kind',true) IS DISTINCT FROM 'jobs' THEN RAISE EXCEPTION 'denied';END IF;END $$;
 CREATE FUNCTION private.burimunsi_auto_jobs_guard() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF current_setting('test.kind',true) IS DISTINCT FROM 'jobs' THEN RAISE EXCEPTION 'denied';END IF;END $$;
 CREATE FUNCTION private.burimunsi_auto_snapshot(p_source text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT jsonb_build_object('actor',jsonb_build_object('collectionId',collection_id),
  'proof',jsonb_build_object('fingerprint',source_fingerprint,'bodySha256',repeat('d',64)),
  'profile',jsonb_build_object('profileSha256',profile_sha256,'profile',jsonb_build_object('provider','synthetic-provider','timezone','Africa/Kigali','profile_version','fixture','profile_json','{}')))
 FROM private.burimunsi_auto_sms_jobs WHERE source_id=p_source $$;
 CREATE TABLE private.fixture_snapshots(source_id text PRIMARY KEY,value jsonb);
 CREATE FUNCTION private.burimunsi_native_sms_post_snapshot(p_source text) RETURNS jsonb LANGUAGE sql AS $$ SELECT value FROM private.fixture_snapshots WHERE source_id=p_source $$;
 CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
 CREATE FUNCTION private.collect_fence_owner_status() RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('sourceSha256',repeat('a',64)) $$;
 CREATE TABLE private.collect_managed_job_tickets(dispatch_id uuid,source_sha256 text,completed_at timestamptz,response_sha256 text);
 CREATE TABLE collect_ops.jobs_config(singleton boolean PRIMARY KEY,enabled boolean);INSERT INTO collect_ops.jobs_config VALUES(true,true);
 CREATE TABLE collect_ops.jobs_dispatches(id uuid PRIMARY KEY,state text,reason text,created_at timestamptz,native_epoch text,net_request_id bigint,
  runtime_contract jsonb,notification_contract jsonb,native_contract jsonb,http_status integer,maintenance_purged integer,response_sha256 text,observed_at timestamptz);
 CREATE TABLE net._http_response(id bigint,status_code integer,timed_out boolean,error_msg text,content text,created timestamptz);
 CREATE FUNCTION collect_ops.native_jobs_epoch() RETURNS text LANGUAGE sql AS $$ SELECT 'fixture-epoch'::text $$;
 CREATE FUNCTION collect_ops.pause_jobs() RETURNS void LANGUAGE sql AS $$ UPDATE collect_ops.jobs_config SET enabled=false $$;`);
 await db.query(prior);
 for(const sig of ['private.burimunsi_auto_retry(text,uuid,text,text,text)','private.burimunsi_auto_finish(text,uuid,text,text,uuid,text,jsonb,jsonb)',
  'private.burimunsi_native_sms_post_facts(text,text,jsonb,jsonb)']){
  await db.query(`REVOKE ALL ON FUNCTION ${sig} FROM PUBLIC;GRANT EXECUTE ON FUNCTION ${sig} TO collect_runtime`);
 }
 await db.query('REVOKE ALL ON FUNCTION collect_ops.reconcile_jobs() FROM PUBLIC');
 // A changed predecessor or an open fence must abort without adding a column.
 await db.query("UPDATE private.collect_fence_control SET mode='open'");
 await assert.rejects(db.query(migration),/native_parse_review_precondition/);await db.query('ROLLBACK');
 await db.query("UPDATE private.collect_fence_control SET mode='fenced'");
 const oldDigest='a4d11f82ce94ec665aa29df8b3157b3646fca571552d2c892247c5be08400a14';
 assert.equal(migration.split(oldDigest).length,2);
 await assert.rejects(db.query(migration.replace(oldDigest,'0'.repeat(64))),/native_parse_review_preimage_changed/);await db.query('ROLLBACK');
 assert.equal((await db.query("SELECT count(*)::int n FROM pg_attribute WHERE attrelid='private.burimunsi_auto_sms_jobs'::regclass AND attname='invalid_output_count' AND NOT attisdropped")).rows[0].n,0);checks++;
 // Unchanged production bytes perform all preimage, privilege and fenced checks.
 await db.query(migration);checks++;
 const columns=(await db.query("SELECT attname FROM pg_attribute WHERE attrelid='private.burimunsi_auto_sms_jobs'::regclass AND attname='invalid_output_count' AND NOT attisdropped")).rows;
 assert.equal(columns.length,1);checks++;
 assert.equal((await db.query("SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') digest FROM pg_proc WHERE oid='private.fixture_import_guard()'::regprocedure")).rows[0].digest,
  createHash('sha256').update("BEGIN IF EXISTS(SELECT 1 FROM private.imported_history WHERE source_id=OLD.source_id) THEN RAISE EXCEPTION 'imported_history_denied';END IF;RETURN NEW;END").digest('hex'));checks++;
 const fingerprint='b'.repeat(64),profile='c'.repeat(64),source='synthetic-new',group='synthetic-group';
 const seed=async id=>db.query(`INSERT INTO private.burimunsi_auto_sms_jobs(source_id,collection_id,source_fingerprint,profile_sha256,state,phase,lease_token,lease_until,attempt_count)
  VALUES($1,$2,$3,$4,'processing','dispatched',$5,floor(extract(epoch FROM clock_timestamp())*1000)::bigint+120000,1)`,[id,group,fingerprint,profile,randomUUID()]);
 await seed(source);
 const acting=await connect('postgres');
 async function retry(id,lease,reason,fp=fingerprint,pf=profile){await acting.query('BEGIN');try{
  await acting.query('SET LOCAL ROLE collect_runtime');await acting.query("SELECT set_config('test.kind','jobs',true)");
  const out=(await acting.query('SELECT private.burimunsi_auto_retry($1,$2,$3,$4,$5) result',[id,lease,fp,pf,reason])).rows[0].result;
  await acting.query('COMMIT');return out;
 }catch(e){await acting.query('ROLLBACK');throw e;}}
 const job=async (id=source)=>(await db.query('SELECT state,phase,lease_token,lease_until,attempt_count,invalid_output_count,retry_lease,last_error,next_attempt_at FROM private.burimunsi_auto_sms_jobs WHERE source_id=$1',[id])).rows[0];
 for(let i=1;i<=7;i++){
  const lease=randomUUID();await db.query("UPDATE private.burimunsi_auto_sms_jobs SET state='processing',phase='dispatched',lease_token=$2,lease_until=floor(extract(epoch FROM clock_timestamp())*1000)::bigint+120000,attempt_count=$3 WHERE source_id=$1",[source,lease,i]);
  const before=Date.now(),result=await retry(source,lease,'invalid_output'),after=Date.now(),row=await job();
  assert.equal(result.state,'retry');assert.equal(row.invalid_output_count,Math.min(i,5));assert.equal(row.retry_lease,lease);
  assert.equal(row.lease_token,null);assert.equal(row.lease_until,null);assert.equal(row.last_error,'invalid_output');
  assert.equal(row.phase,'preflight');assert.notEqual(row.next_attempt_at,null);
  const delay=Number(row.next_attempt_at)-before;
  if(i>=5)assert.ok(delay>=86399000&&delay<=86400000+(after-before)+1000);
  else assert.ok(delay>=0&&delay<=3600000+(after-before)+1000);
  assert.deepEqual(await retry(source,lease,'invalid_output'),result);assert.equal((await job()).invalid_output_count,Math.min(i,5));checks++;
 }
 await assert.rejects(retry(source,randomUUID(),'invalid_output'));checks++;
 const saturatedLease=randomUUID();await db.query("UPDATE private.burimunsi_auto_sms_jobs SET state='processing',phase='dispatched',lease_token=$2,lease_until=floor(extract(epoch FROM clock_timestamp())*1000)::bigint+120000,attempt_count=8 WHERE source_id=$1",[source,saturatedLease]);
 const beforeOutage=Date.now(),saturatedOutage=await retry(source,saturatedLease,'provider_unavailable');
 assert.equal(saturatedOutage.state,'retry');assert.equal((await job()).invalid_output_count,5);
 assert.ok(saturatedOutage.nextAttemptAt-beforeOutage<=3601000);checks++;
 await seed('outage');
 for(let i=1;i<=7;i++){
  const lease=randomUUID();await db.query("UPDATE private.burimunsi_auto_sms_jobs SET state='processing',phase='dispatched',lease_token=$2,lease_until=floor(extract(epoch FROM clock_timestamp())*1000)::bigint+120000,attempt_count=$3 WHERE source_id=$1",['outage',lease,i]);
  assert.equal((await retry('outage',lease,'provider_unavailable')).state,'retry');assert.equal((await job('outage')).invalid_output_count,0);
 }checks++;
 await seed('mixed');
 for(const [i,reason] of ['invalid_output','provider_unavailable','invalid_output','provider_unavailable'].entries()){
  const lease=randomUUID();await db.query("UPDATE private.burimunsi_auto_sms_jobs SET state='processing',phase='dispatched',lease_token=$2,lease_until=floor(extract(epoch FROM clock_timestamp())*1000)::bigint+120000,attempt_count=$3 WHERE source_id=$1",['mixed',lease,i+1]);
  await retry('mixed',lease,reason);
 }
 assert.equal((await job('mixed')).invalid_output_count,2);checks++;
 const current=await job('outage');await assert.rejects(retry('outage',current.retry_lease,'invalid_output','d'.repeat(64)));checks++;
 await seed('imported');await db.query("INSERT INTO private.imported_history VALUES('imported')");
 const imported=await job('imported');await assert.rejects(retry('imported',imported.lease_token,'invalid_output'),/imported_history_denied/);
 assert.equal((await job('imported')).invalid_output_count,0);checks++;
 await acting.query('SET ROLE anon');await assert.rejects(acting.query('SELECT private.burimunsi_auto_retry($1,$2,$3,$4,$5)',['outage',randomUUID(),fingerprint,profile,'invalid_output']));await acting.query('RESET ROLE');checks++;
 const payload={event_kind:'incoming_receipt',payment_outcome:'successful',currency:'RWF',amount_minor:1250,source_mode:'live',wallet_balance_after_minor:null,
  counterparty_name:'Synthetic Person',counterparty_identifier:null,transaction_at:null,transaction_datetime_raw:null,provider_transaction_id:'TX-123',
  original_transaction_id:null,fee_minor:null,transaction_time_source:null,transaction_timezone:null};
 async function facts(id,canonicalId,input,actorGroup=group){
  await seed(id);await db.query('INSERT INTO private.fixture_snapshots(source_id,value) VALUES($1,$2)',[id,{source_fingerprint:fingerprint,event_kind:'incoming_receipt',amount_minor:1250,currency:'RWF',mode:'live',provider_transaction_id:canonicalId}]);
  await acting.query('BEGIN');try{await acting.query('SET LOCAL ROLE collect_runtime');await acting.query("SELECT set_config('test.kind','jobs',true),set_config('burimunsi.collection_id',$1,true)",[actorGroup]);
   const value=(await acting.query('SELECT private.burimunsi_native_sms_post_facts($1,$2,$3::jsonb,$4::jsonb) result',[id,fingerprint,JSON.stringify({synthetic:true}),JSON.stringify(input)])).rows[0].result;
   await acting.query('COMMIT');return value;
  }catch(e){await acting.query('ROLLBACK');throw e;}
 }
 assert.equal(await facts('matched-no-balance','TX-123',payload),true);checks++;
 await assert.rejects(facts('mismatch-no-balance','TX-999',payload));checks++;
 await assert.rejects(facts('missing-id-no-balance',null,{...payload,provider_transaction_id:null}));checks++;
 assert.equal(await facts('legacy-balance-no-id',null,{...payload,provider_transaction_id:null,wallet_balance_after_minor:9000}),true);checks++;
 await assert.rejects(facts('cross-collection','TX-123',payload,'different-group'));checks++;
 // Exercise the complete migrated auto_finish body, not only a copied CASE.
 // All tables are synthetic; the fixture intentionally doubles fence/profile
 // authority while using the real function, transaction creation and source
 // linking logic. No financial ledger transaction is created here.
 const extracted={event_kind:'incoming_receipt',payment_outcome:'successful',source_mode:'live',provider_transaction_id:'TX-504',
  original_transaction_id:null,amount_minor:1250,currency:'RWF',counterparty_name:'Synthetic Person',counterparty_identifier:null,
  transaction_at:null,transaction_datetime_raw:null,fee_minor:null,wallet_balance_after_minor:null};
 async function finish(id,input,attempt=randomUUID()){
  await seed(id);await db.query('UPDATE private.burimunsi_auto_sms_jobs SET event_identity_sha256=$2 WHERE source_id=$1',[id,createHash('sha256').update(id).digest('hex')]);
  const lease=(await job(id)).lease_token;
  await acting.query('BEGIN');try{await acting.query('SET LOCAL ROLE collect_runtime');await acting.query("SELECT set_config('test.kind','jobs',true)");
   const result=(await acting.query('SELECT private.burimunsi_auto_finish($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb) result',
    [id,lease,fingerprint,profile,attempt,'synthetic-model',JSON.stringify({synthetic:true}),JSON.stringify(input)])).rows[0].result;
   await acting.query('COMMIT');return {result,attempt,lease};
  }catch(e){await acting.query('ROLLBACK');throw e;}
 }
 const identified=await finish('finish-identified',extracted);
 assert.equal(identified.result.relation,'accepted');assert.equal((await db.query("SELECT allocation_state FROM app.momo_transactions WHERE id='finish-identified'")).rows[0].allocation_state,'unallocated');checks++;
 const missing=await finish('finish-no-id',{...extracted,provider_transaction_id:null});
 assert.equal(missing.result.relation,'accepted');assert.equal((await db.query("SELECT allocation_state FROM app.momo_transactions WHERE id='finish-no-id'")).rows[0].allocation_state,'not_applicable');checks++;
 const legacy=await finish('finish-with-balance',{...extracted,provider_transaction_id:null,wallet_balance_after_minor:9000});
 assert.equal(legacy.result.relation,'accepted');assert.equal((await db.query("SELECT allocation_state FROM app.momo_transactions WHERE id='finish-with-balance'")).rows[0].allocation_state,'unallocated');checks++;
 const duplicate=await finish('finish-duplicate',extracted);
 assert.equal(duplicate.result.relation,'duplicate');assert.equal(duplicate.result.transactionId,'finish-identified');
 assert.equal((await db.query("SELECT count(*)::int n FROM app.momo_transactions WHERE provider_transaction_id='TX-504'")).rows[0].n,1);checks++;
 const conflict=await finish('finish-conflict',{...extracted,amount_minor:1500});
 assert.equal(conflict.result.relation,'conflict');assert.equal(conflict.result.transactionId,'finish-identified');
 assert.equal((await db.query("SELECT count(*)::int n FROM app.momo_transactions WHERE provider_transaction_id='TX-504'")).rows[0].n,1);checks++;
 await db.query("UPDATE private.burimunsi_transaction_scopes SET collection_id='different-group' WHERE transaction_id='finish-identified'");
 await assert.rejects(finish('finish-cross-group',extracted),/burimunsi_auto_scope_conflict/);
 await db.query("UPDATE private.burimunsi_transaction_scopes SET collection_id='synthetic-group' WHERE transaction_id='finish-identified'");
 assert.equal((await db.query("SELECT count(*)::int n FROM app.momo_transactions WHERE provider_transaction_id='TX-504'")).rows[0].n,1);checks++;
 const native={contract:'synthetic'},id=randomUUID(),response=JSON.stringify({dispatch_id:id,native_sms_admission:native,
  maintenance:{status:'complete',examined_limit:100,purged:0,provider_calls:0},processing:{paused:true,processed:0,results:[]},
  native_auto_processing:{status:'complete',processed:1,results:[{state:'retry'}]},native_sms_ledger:{status:'complete',processed:0,results:[]}});
 await db.query("INSERT INTO collect_ops.jobs_dispatches(id,state,created_at,native_epoch,net_request_id,native_contract) VALUES($1,'awaiting',clock_timestamp(),'fixture-epoch',1,$2)",[id,native]);
 await db.query("INSERT INTO private.collect_managed_job_tickets VALUES($1,$2,clock_timestamp(),$3)",[id,'a'.repeat(64),createHash('sha256').update(response).digest('hex')]);
 await db.query("INSERT INTO net._http_response VALUES(1,200,false,NULL,$1,clock_timestamp())",[response]);
 const reconciled=(await db.query('SELECT collect_ops.reconcile_jobs() result')).rows[0].result;
 assert.deepEqual(reconciled,{observed:1,unconfirmed:0});assert.equal((await db.query('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[id])).rows[0].state,'confirmed');
 assert.equal((await db.query('SELECT enabled FROM collect_ops.jobs_config')).rows[0].enabled,true);checks++;
 console.log(JSON.stringify({suite:'native-parser-review',checks,actualMigration:true,predecessorBodiesPinned:true,providerCalls:0,cloudWrites:0}));
}finally{for(const c of clients)await c.end().catch(()=>{});await f.close();}
