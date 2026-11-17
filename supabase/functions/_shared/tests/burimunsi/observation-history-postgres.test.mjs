// Runs only against a specifically named throwaway PostgreSQL container.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawn,spawnSync} from 'node:child_process';

const container=process.env.BURI_HISTORY_TEST_CONTAINER;
const allowed='codex-burimunsi-sms-history-fixture';
const migration=new URL('../../../../migrations/20261113130200_burimunsi_account_sms_history.sql',import.meta.url);
function sql(input,user='postgres'){
 assert.equal(container,allowed,'Only the isolated synthetic fixture may be used');
 const r=spawnSync('docker',['--context','colima-supabase-local','exec','-i',container,'psql','-U',user,'-d','postgres','-X','-v','ON_ERROR_STOP=1','-q'],
  {input,encoding:'utf8',maxBuffer:1_000_000});
 assert.equal(r.status,0,(r.stderr||'fixture failed').slice(-5000));
}

test('account SMS history preserves scope, audit, consent, grant and retained-object boundaries',{skip:!container},()=>{
 sql('CREATE ROLE collect_runtime; CREATE ROLE collect_importer; GRANT collect_runtime TO postgres; GRANT CREATE ON DATABASE postgres TO postgres;', 'supabase_admin');
 sql(`
 CREATE SCHEMA private;CREATE SCHEMA app;GRANT USAGE ON SCHEMA private TO collect_runtime;
 CREATE TABLE private.collect_fence_control(mode text);INSERT INTO private.collect_fence_control VALUES('fenced');
 CREATE TABLE private.burimunsi_device_grants(id uuid PRIMARY KEY,collection_id text,installation_id uuid,version bigint,active boolean,profile text);
 CREATE TABLE private.burimunsi_device_accounts(grant_id uuid,collection_id text,account_id uuid);
 CREATE TABLE private.burimunsi_observation_consents(collection_id text,account_id uuid,installation_id uuid,grant_id uuid,grant_version bigint,enabled boolean);
 CREATE TABLE private.burimunsi_unresolved_observations(source_id text PRIMARY KEY,collection_id text,account_id uuid,principal_user_id text,
  installation_id uuid,grant_id uuid,grant_version bigint,request_id uuid,fingerprint text,body_sha256 text,object_key text,object_sha256 text,
  size_bytes bigint,created_at bigint);
 CREATE TABLE private.fixture_storage(object_key text,scope jsonb,sha text,valid boolean);
 CREATE TABLE app.audit_log(actor_user_id text,actor_session_id text,action text,entity_type text,entity_id text,request_id text,details_json text,created_at text);
 CREATE FUNCTION app.strftime(text) RETURNS text LANGUAGE sql AS $$SELECT 'synthetic-time'::text$$;
 CREATE FUNCTION private.burimunsi_setup_fence() RETURNS void LANGUAGE sql AS 'SELECT';
 CREATE FUNCTION private.burimunsi_observation_actor(p_reveal boolean) RETURNS jsonb LANGUAGE plpgsql AS $f$
 BEGIN IF current_setting('fixture.read',true) IS DISTINCT FROM 'yes' OR
  (p_reveal AND current_setting('fixture.reveal',true) IS DISTINCT FROM 'yes') THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501';END IF;
  RETURN current_setting('fixture.actor')::jsonb;END;$f$;
 CREATE FUNCTION private.burimunsi_observation_consent_current() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('enabled',current_setting('fixture.consent',true)='yes','generation',1)$$;
 CREATE FUNCTION private.burimunsi_observation_page(text,text,integer,integer) RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$;
 CREATE FUNCTION private.burimunsi_observation_own(text,boolean) RETURNS jsonb LANGUAGE sql AS $$SELECT '{"original":true}'::jsonb$$;
 CREATE FUNCTION private.burimunsi_observation_storage_matches(p_key text,p_scope jsonb,p_sha text) RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS(SELECT 1 FROM private.fixture_storage WHERE object_key=p_key AND scope=p_scope AND sha=p_sha AND valid)$$;
 INSERT INTO private.burimunsi_device_grants VALUES
  ('00000000-0000-4000-8000-000000000011','group-1','00000000-0000-4000-8000-000000000021',1,true,'internal_receiver'),
  ('00000000-0000-4000-8000-000000000012','group-1','00000000-0000-4000-8000-000000000022',1,true,'internal_receiver'),
  ('00000000-0000-4000-8000-000000000013','group-1','00000000-0000-4000-8000-000000000023',1,true,'internal_receiver'),
  ('00000000-0000-4000-8000-000000000014','group-2','00000000-0000-4000-8000-000000000024',1,true,'internal_receiver');
 INSERT INTO private.burimunsi_device_accounts VALUES
  ('00000000-0000-4000-8000-000000000011','group-1','00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000012','group-1','00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000013','group-1','00000000-0000-4000-8000-000000000002'),
  ('00000000-0000-4000-8000-000000000014','group-2','00000000-0000-4000-8000-000000000001');
 INSERT INTO private.burimunsi_observation_consents SELECT d.collection_id,a.account_id,d.installation_id,d.id,d.version,true
  FROM private.burimunsi_device_grants d JOIN private.burimunsi_device_accounts a ON a.grant_id=d.id;
 INSERT INTO private.burimunsi_unresolved_observations SELECT
  '10000000-0000-4000-8000-'||lpad(row_number() OVER (ORDER BY d.id)::text,12,'0'),d.collection_id,a.account_id,
  CASE WHEN a.account_id='00000000-0000-4000-8000-000000000002' THEN 'principal-b' ELSE 'principal-a' END,
  d.installation_id,d.id,1,'20000000-0000-4000-8000-000000000001',repeat('f',64),repeat('b',64),
  'sms/'||row_number() OVER (ORDER BY d.id),repeat('c',64),100,row_number() OVER (ORDER BY d.id)
  FROM private.burimunsi_device_grants d JOIN private.burimunsi_device_accounts a ON a.grant_id=d.id;
 INSERT INTO private.fixture_storage SELECT object_key,jsonb_build_object('ownerId',principal_user_id,'purpose','sms_receipt','entityId',source_id),object_sha256,true
  FROM private.burimunsi_unresolved_observations;
 `);
 sql(readFileSync(migration,'utf8'));
 sql(`
 SELECT set_config('fixture.read','yes',false),set_config('fixture.reveal','yes',false),set_config('fixture.consent','yes',false);
 SELECT set_config('fixture.actor',jsonb_build_object('collectionId','group-1','accountId','00000000-0000-4000-8000-000000000001',
  'principalUserId','principal-a','installationId','00000000-0000-4000-8000-000000000022','grantId','00000000-0000-4000-8000-000000000012',
  'grantVersion',1,'sessionId','00000000-0000-4000-8000-000000000031')::text,false);
 SET ROLE collect_runtime;
 DO $t$ DECLARE page jsonb;proof jsonb;
 BEGIN
  IF has_function_privilege('collect_runtime','private.burimunsi_observation_history_rows(text)','EXECUTE') THEN RAISE EXCEPTION 'raw history helper exposed';END IF;
  page:=private.burimunsi_observation_page('','all',20,0);
  IF (page->>'totalCount')::int<>2 OR jsonb_array_length(page->'items')<>2 THEN RAISE EXCEPTION 'incorrect history scope: %',page;END IF;
  PERFORM set_config('fixture.initial_revision',page->>'revision',false);
  IF private.burimunsi_observation_own('irrelevant',true)->>'original'<>'true' THEN RAISE EXCEPTION 'original processing boundary changed';END IF;
  proof:=private.burimunsi_observation_history_own('10000000-0000-4000-8000-000000000001');
  IF proof IS NULL THEN RAISE EXCEPTION 'same-admin previous device absent';END IF;
  IF private.burimunsi_observation_history_own('10000000-0000-4000-8000-000000000003') IS NOT NULL OR
     private.burimunsi_observation_history_own('10000000-0000-4000-8000-000000000004') IS NOT NULL THEN
   RAISE EXCEPTION 'another account or collection disclosed';END IF;
  PERFORM private.burimunsi_observation_history_reveal_audit('10000000-0000-4000-8000-000000000001',
   '30000000-0000-4000-8000-000000000001','Inspect source','00000000-0000-4000-8000-000000000031',repeat('b',64),repeat('c',64),repeat('f',64),1);
  PERFORM set_config('fixture.reveal','no',true);
  BEGIN PERFORM private.burimunsi_observation_history_own('10000000-0000-4000-8000-000000000001');
   RAISE EXCEPTION 'reveal grant bypass';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  PERFORM set_config('fixture.reveal','yes',true);PERFORM set_config('fixture.consent','no',true);
  BEGIN PERFORM private.burimunsi_observation_page('','all',20,0);RAISE EXCEPTION 'current consent bypass';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  PERFORM set_config('fixture.consent','yes',true);PERFORM set_config('fixture.read','no',true);
  BEGIN PERFORM private.burimunsi_observation_page('','all',20,0);RAISE EXCEPTION 'current grant bypass';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 END;$t$;
 BEGIN TRANSACTION READ ONLY;
 DO $t$ BEGIN IF (private.burimunsi_observation_page('','all',20,0)->>'totalCount')::int<>2 THEN
  RAISE EXCEPTION 'read-only page failed';END IF;END;$t$;
 COMMIT;
 RESET ROLE;
 DO $t$ BEGIN IF (SELECT count(*) FROM app.audit_log)<>1 THEN RAISE EXCEPTION 'disclosure audit missing';END IF;END;$t$;
 UPDATE private.burimunsi_observation_consents SET enabled=false WHERE installation_id='00000000-0000-4000-8000-000000000021';
 SET ROLE collect_runtime;
 DO $t$ BEGIN
  IF (private.burimunsi_observation_page('','all',20,0)->>'totalCount')::int<>1 OR
   private.burimunsi_observation_page('','all',20,0)->>'revision'=current_setting('fixture.initial_revision') OR
   private.burimunsi_observation_history_own('10000000-0000-4000-8000-000000000001') IS NOT NULL THEN RAISE EXCEPTION 'old consent bypass';END IF;
  BEGIN PERFORM private.burimunsi_observation_history_reveal_audit('10000000-0000-4000-8000-000000000001',
   '30000000-0000-4000-8000-000000000002','Inspect source','00000000-0000-4000-8000-000000000031',repeat('b',64),repeat('c',64),repeat('f',64),1);
   RAISE EXCEPTION 'revocation between proof and audit accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 END;$t$;
 RESET ROLE;
 UPDATE private.burimunsi_observation_consents SET enabled=true WHERE installation_id='00000000-0000-4000-8000-000000000021';
 UPDATE private.burimunsi_device_grants SET active=false WHERE id='00000000-0000-4000-8000-000000000011';
 SET ROLE collect_runtime;
 DO $t$ BEGIN IF (private.burimunsi_observation_page('','all',20,0)->>'totalCount')::int<>1 THEN RAISE EXCEPTION 'old grant revocation bypass';END IF;END;$t$;
 RESET ROLE;
 UPDATE private.burimunsi_device_grants SET active=true,version=2 WHERE id='00000000-0000-4000-8000-000000000011';
 SET ROLE collect_runtime;
 DO $t$ BEGIN IF (private.burimunsi_observation_page('','all',20,0)->>'totalCount')::int<>1 THEN RAISE EXCEPTION 'old grant version bypass';END IF;END;$t$;
 RESET ROLE;
 UPDATE private.burimunsi_device_grants SET version=1 WHERE id='00000000-0000-4000-8000-000000000011';
 DELETE FROM private.burimunsi_device_accounts WHERE grant_id='00000000-0000-4000-8000-000000000011';
 SET ROLE collect_runtime;
 DO $t$ BEGIN IF (private.burimunsi_observation_page('','all',20,0)->>'totalCount')::int<>1 THEN RAISE EXCEPTION 'old account link revocation bypass';END IF;END;$t$;
 RESET ROLE;
 INSERT INTO private.burimunsi_device_accounts VALUES('00000000-0000-4000-8000-000000000011','group-1','00000000-0000-4000-8000-000000000001');
 UPDATE private.fixture_storage SET valid=false WHERE object_key='sms/1';
 SET ROLE collect_runtime;
 DO $t$ BEGIN
  BEGIN PERFORM private.burimunsi_observation_page('','all',20,0);RAISE EXCEPTION 'bad custody accepted';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 END;$t$;
 `);
});

test('historical authorization rows stay locked until a disclosure transaction ends',{skip:!container},async()=>{
 assert.equal(container,allowed,'Only the isolated synthetic fixture may be used');
 sql("UPDATE private.fixture_storage SET valid=true WHERE object_key='sms/1'");
 const args=['--context','colima-supabase-local','exec','-i',container,'psql','-U','postgres','-d','postgres','-X','-v','ON_ERROR_STOP=1','-q'];
 const p=spawn('docker',args,{stdio:['pipe','pipe','pipe']});let stderr='';p.stderr.on('data',v=>{stderr+=v;});
 const done=new Promise(resolve=>p.on('close',resolve));
 p.stdin.end(`SET application_name='burimunsi_history_lock_fixture';
  SELECT set_config('fixture.read','yes',false),set_config('fixture.reveal','yes',false),set_config('fixture.consent','yes',false);
  SELECT set_config('fixture.actor',jsonb_build_object('collectionId','group-1','accountId','00000000-0000-4000-8000-000000000001',
   'principalUserId','principal-a','installationId','00000000-0000-4000-8000-000000000022','grantId','00000000-0000-4000-8000-000000000012',
   'grantVersion',1,'sessionId','00000000-0000-4000-8000-000000000031')::text,false);
  SET ROLE collect_runtime;BEGIN;
  SELECT private.burimunsi_observation_history_own('10000000-0000-4000-8000-000000000001');
  SELECT pg_sleep(6);ROLLBACK;`);
 try{
  let locked=false;
  for(let attempt=0;attempt<40&&!locked;attempt++){
   const q=spawnSync('docker',['--context','colima-supabase-local','exec',container,'psql','-U','postgres','-d','postgres','-XAtq','-c',
    "SELECT count(*) FROM pg_stat_activity WHERE application_name='burimunsi_history_lock_fixture' AND state='active' AND query LIKE '%pg_sleep%';"],{encoding:'utf8'});
   locked=q.status===0&&q.stdout.trim()==='1';if(!locked)await new Promise(resolve=>setTimeout(resolve,100));
  }
  assert.ok(locked,`History transaction did not reach its lock checkpoint: ${stderr}`);
  for(const statement of [
   "UPDATE private.burimunsi_device_grants SET active=false WHERE id='00000000-0000-4000-8000-000000000011'",
   "UPDATE private.burimunsi_observation_consents SET enabled=false WHERE installation_id='00000000-0000-4000-8000-000000000021'",
   "UPDATE private.burimunsi_observation_consents SET enabled=false WHERE installation_id='00000000-0000-4000-8000-000000000022'",
   "DELETE FROM private.burimunsi_device_accounts WHERE grant_id='00000000-0000-4000-8000-000000000011'"
  ]){
   const blocked=spawnSync('docker',['--context','colima-supabase-local','exec',container,'psql','-U','postgres','-d','postgres','-X','-v','ON_ERROR_STOP=1','-c',
    `SET lock_timeout='500ms'; ${statement}`],{encoding:'utf8'});
   assert.notEqual(blocked.status,0,'revocation unexpectedly bypassed the disclosure lock');
   assert.match(blocked.stderr,/lock timeout/);
  }
 }finally{
  const code=await done;assert.equal(code,0,stderr);
 }
});
