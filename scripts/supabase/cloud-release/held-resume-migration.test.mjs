import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {HELD_RESUME_CATALOG_SQL} from './managed-jobs-operator.mjs';

const modulePath=process.env.COLLECT_CLOUD_TEST_PGLITE_MODULE;
const prior=readFileSync(new URL('../../../supabase/migrations/20261117210000_burimunsi_held_recovery.sql',import.meta.url),'utf8');
const base=readFileSync(new URL('../../../supabase/migrations/20261111121000_burimunsi_private_observations.sql',import.meta.url),'utf8');
const resume=readFileSync(new URL('../../../supabase/migrations/20261117220000_burimunsi_held_resume_guard.sql',import.meta.url),'utf8');
function extract(source,head,tag){const start=source.indexOf(head),open=source.indexOf(tag,start),end=source.indexOf(tag+';',open+tag.length);
 assert(start>=0&&open>=0&&end>=0);return source.slice(start,end+tag.length+1);}
test('exact resume migration installs its guard against pinned predecessor functions',{skip:!modulePath},async()=>{
 const {PGlite}=await import(modulePath),db=new PGlite();try{
  await db.exec(`CREATE SCHEMA app; CREATE SCHEMA private; CREATE SCHEMA supabase_migrations;
   CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_importer;CREATE ROLE collect_runtime;
   CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,statements text[]);
   CREATE TABLE private.collect_fence_control(singleton boolean,mode text);INSERT INTO private.collect_fence_control VALUES(true,'fenced');
   CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private.burimunsi_observation_actor(boolean) RETURNS jsonb LANGUAGE sql AS $$SELECT jsonb_build_object(
    'collectionId','group-a','accountId','10000000-0000-4000-8000-000000000001','principalUserId','owner-a',
    'installationId','20000000-0000-4000-8000-000000000001','grantId','30000000-0000-4000-8000-000000000001','grantVersion',1)$$;
   CREATE FUNCTION private.burimunsi_observation_consent_current() RETURNS jsonb LANGUAGE sql AS $$SELECT jsonb_build_object(
    'enabled',true,'generation',coalesce(nullif(current_setting('fixture.generation',true),''),'1')::bigint)$$;
   CREATE TABLE private.burimunsi_observation_requests(source_id text,collection_id text,account_id uuid,principal_user_id text,
    installation_id uuid,grant_id uuid,grant_version bigint,request_id uuid,fingerprint text,source_key text,source_key_body_sha256 text,initial_consent_generation bigint);
   CREATE TABLE private.burimunsi_recovered_sms_holds(source_id text,object_key text,collection_id text,account_id uuid,owner_id text,
    body_sha256 text,inbox_received_at timestamptz,request_digest text);
   CREATE TABLE private.collect_sms_witnesses(object_key text,owner_id text,collection_id text,body_sha256 text,inbox_received_at timestamptz,request_digest text);
   CREATE TABLE private.burimunsi_unresolved_observations(source_id text);CREATE TABLE private.burimunsi_auto_sms_jobs(source_id text);
   CREATE TABLE private.burimunsi_native_financial_work(source_id text);CREATE TABLE app.sms_receipts(id text);
   CREATE TABLE private.storage_put_intents(operation_id text PRIMARY KEY,object_key text,state text,attempts integer,active_attempt uuid,
    upload_unresolved boolean,delete_tombstone boolean,last_outcome text,updated_at timestamptz);
   CREATE TABLE private.storage_upload_attempts(id uuid PRIMARY KEY,operation_id text,outcome text,completed_at timestamptz);
   ${extract(base,'CREATE OR REPLACE FUNCTION private.trg_storage_identity()','$storage_identity$')}
   CREATE TRIGGER storage_put_identity BEFORE UPDATE OR DELETE ON private.storage_put_intents FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
   CREATE TRIGGER storage_upload_identity BEFORE UPDATE OR DELETE ON private.storage_upload_attempts FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
   ${extract(prior,'CREATE FUNCTION private.burimunsi_sms_recovery_hold(' ,'$fn$')}
   REVOKE ALL ON FUNCTION private.burimunsi_sms_recovery_hold(text,uuid,text,text,timestamptz) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
   GRANT EXECUTE ON FUNCTION private.burimunsi_sms_recovery_hold(text,uuid,text,text,timestamptz) TO collect_runtime;`);
  await db.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2::text[])',['20261117210000',[prior]]);
  await db.exec(resume);assert.equal((await db.query(HELD_RESUME_CATALOG_SQL)).rows[0].ok,true);
  const source='00000000-0000-4000-8000-000000000001',req='40000000-0000-4000-8000-000000000002',fingerprint='a'.repeat(64),body='b'.repeat(64),time='2026-11-11T12:00:00Z';
  await db.query(`INSERT INTO private.burimunsi_observation_requests VALUES($1,'group-a','10000000-0000-4000-8000-000000000001','owner-a',
   '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,$2,$3,$4,$5,1)`,[source,req,fingerprint,'c'.repeat(64),body]);
  await db.query(`INSERT INTO private.burimunsi_recovered_sms_holds VALUES($1,$2,'group-a','10000000-0000-4000-8000-000000000001','owner-a',$3,$4,$5)`,[source,'sms/'+source,body,time,fingerprint]);
  await db.query("INSERT INTO private.collect_sms_witnesses VALUES($1,'owner-a','group-a',$2,$3,$4)",['sms/'+source,body,time,fingerprint]);
  await db.exec("SELECT set_config('collect.fence_admission_id','00000000-0000-4000-8000-000000000005',false),set_config('collect.fence_epoch','1',false),set_config('collect.fence_source_sha256',repeat('f',64),false)");
  assert.equal((await db.query('SELECT private.collect_sms_held_resume_check($1,$2,$3,$4,$5) AS ok',[source,req,fingerprint,body,time])).rows[0].ok,true);
  await db.exec("SELECT set_config('fixture.generation','2',false)");
  await assert.rejects(()=>db.query('SELECT private.collect_sms_held_resume_check($1,$2,$3,$4,$5)',[source,req,fingerprint,body,time]),/sms_held_resume_consent_changed/);
  await db.query("INSERT INTO private.storage_put_intents VALUES('operation',$1,'pending',0,NULL,false,false,NULL,clock_timestamp())",['sms/'+source]);
  await db.exec("INSERT INTO private.storage_upload_attempts VALUES('00000000-0000-4000-8000-000000000010','operation','started',NULL)");
  await assert.rejects(()=>db.exec("INSERT INTO private.storage_upload_attempts VALUES('00000000-0000-4000-8000-000000000011','operation','started',NULL)"),/sms_held_upload_already_attempted/);
  await assert.rejects(()=>db.exec('DELETE FROM private.storage_upload_attempts'),/retain_storage_control_identity/);
  await db.exec("UPDATE private.storage_put_intents SET attempts=1 WHERE operation_id='operation'");
  await assert.rejects(()=>db.exec("UPDATE private.storage_put_intents SET attempts=0 WHERE operation_id='operation'"),/storage_state_regression/);
 }finally{await db.close();}
});
