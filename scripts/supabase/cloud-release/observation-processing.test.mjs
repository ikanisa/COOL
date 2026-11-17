// Actual forward migration against an isolated, synthetic PostgreSQL 17 cluster.
// No cloud credentials, original SMS, or real operator data are used.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {randomUUID,createHash} from 'node:crypto';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {verifyBinaryPins,verifyEnvironment,BIN} from '../managed-identity-provider-compat/fixture-safety.mjs';
verifyEnvironment(process.env);await verifyBinaryPins();
const {Client}=createRequire(import.meta.url)('pg');
const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'observation_processing_fixture'});
assert.equal(f.bin,BIN);const clients=[];
async function connect(user){const c=new Client({host:f.socket,port:f.port,database:'postgres',user,connectionTimeoutMillis:5000});c.on('error',()=>{});await c.connect();clients.push(c);return c;}
const source=n=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const account='20000000-0000-4000-8000-000000000001',installation='30000000-0000-4000-8000-000000000001';
let checks=0;
try{
 const root=await connect('fixture_bootstrap');
 await root.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS;CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_runtime;CREATE ROLE collect_importer;GRANT collect_runtime TO postgres;
 CREATE SCHEMA private AUTHORIZATION postgres;GRANT USAGE ON SCHEMA private TO collect_runtime;`);
 const db=await connect('postgres');
 const fenceSource=await readFile(new URL('../../../supabase/migrations/20261022195747_collect_application_mutation_fence.sql',import.meta.url),'utf8');
 const eventSource=await readFile(new URL('../../../supabase/migrations/20261114102000_burimunsi_native_event_identity.sql',import.meta.url),'utf8');
 const fenceBody=/CREATE FUNCTION private\._collect_fence_statement\(\) RETURNS trigger\nLANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS \$fn\$([\s\S]*?)\$fn\$;/.exec(fenceSource)?.[1];
 assert.equal(createHash('sha256').update(fenceBody).digest('hex'),'0b886c44b329012c91e5eb85fce1a160a60e4172e016a284f2c280121b0a217d');
 const old=/anchor:=\$old\$([\s\S]*?)\$old\$;/.exec(eventSource)?.[1],replacement=/replacement:=\$new\$([\s\S]*?)\$new\$;/.exec(eventSource)?.[1];
 assert.ok(old&&replacement&&fenceBody.includes(old));const specialBody=fenceBody.replace(old,replacement);
 await db.query(`
 CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,mode text);INSERT INTO private.collect_fence_control VALUES(true,'fenced');
 CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$BEGIN IF current_user<>'postgres' OR current_setting('role',true)='collect_runtime' THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501';END IF;END$$;
 CREATE FUNCTION private.burimunsi_setup_fence() RETURNS void LANGUAGE plpgsql AS $$BEGIN IF current_setting('role',true) IS DISTINCT FROM 'collect_runtime' OR current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true' OR current_setting('fixture.fenced',true)='yes' THEN RAISE EXCEPTION 'fenced' USING ERRCODE='42501';END IF;END$$;
 CREATE FUNCTION private._collect_fence_operator() RETURNS boolean LANGUAGE sql AS $$SELECT false$$;
 CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS jsonb LANGUAGE plpgsql AS $$BEGIN
  IF current_setting('fixture.fenced',true)='yes' OR (current_setting('role',true)='collect_runtime' AND ($1 IS NULL OR $2<>1 OR $3<>repeat('a',64))) THEN RAISE EXCEPTION 'fenced' USING ERRCODE='42501';END IF;
  RETURN '{}'::jsonb;END$$;
 CREATE FUNCTION private._collect_fence_statement() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fence$${fenceBody}$fence$;
 CREATE FUNCTION private._burimunsi_native_event_jobs_statement() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $special$${specialBody}$special$;
 CREATE TABLE private.fixture_sources(source_id text PRIMARY KEY,collection_id text,account_id uuid,installation_id uuid,imported boolean DEFAULT false,imported_job boolean DEFAULT false);
 CREATE TABLE private.burimunsi_auto_sms_jobs(source_id text PRIMARY KEY,collection_id text,state text,invalid_output_count integer DEFAULT 0,last_error text,lease_token uuid,lease_until bigint,next_attempt_at bigint,updated_at bigint,relation text,posting_last_error text);
 INSERT INTO private.fixture_sources VALUES
  ('${source(1)}','group-1','${account}','${installation}',false,false),('${source(2)}','group-1','${account}','${installation}',true,false),
  ('${source(3)}','group-1','${account}','${installation}',false,false),('${source(4)}','group-1','${account}','${installation}',false,false),
  ('${source(5)}','group-2','${account}','${installation}',false,false),('${source(6)}','group-1','${account}','30000000-0000-4000-8000-000000000002',false,false),
  ('${source(7)}','group-1','${account}','${installation}',false,false),('${source(8)}','group-1','${account}','${installation}',false,true),
  ('${source(9)}','group-1','${account}','${installation}',false,false),('${source(10)}','group-1','${account}','${installation}',false,false);
 INSERT INTO private.burimunsi_auto_sms_jobs VALUES
  ('${source(1)}','group-1','retry',5,'invalid_output',NULL,NULL,9999999999999,0,NULL,NULL),
  ('${source(2)}','group-1','retry',0,'provider_unavailable',NULL,NULL,9999999999999,0,NULL,NULL),
  ('${source(3)}','group-1','processing',0,NULL,'40000000-0000-4000-8000-000000000001',9999999999999,NULL,0,NULL,NULL),
  ('${source(4)}','group-1','completed',0,NULL,NULL,NULL,NULL,0,'accepted',NULL),
  ('${source(5)}','group-2','retry',0,'provider_unavailable',NULL,NULL,9999999999999,0,NULL,NULL),
  ('${source(6)}','group-1','retry',0,'provider_unavailable',NULL,NULL,9999999999999,0,NULL,NULL),
  ('${source(7)}','group-1','completed',0,NULL,NULL,NULL,NULL,0,'conflict',NULL),
  ('${source(8)}','group-1','retry',0,'provider_unavailable',NULL,NULL,9999999999999,0,NULL,NULL),
  ('${source(9)}','group-1','security_message',0,NULL,NULL,NULL,NULL,0,NULL,NULL);
 ALTER TABLE private.burimunsi_auto_sms_jobs ENABLE ROW LEVEL SECURITY;ALTER TABLE private.burimunsi_auto_sms_jobs FORCE ROW LEVEL SECURITY;
 REVOKE ALL ON private.burimunsi_auto_sms_jobs FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
 CREATE POLICY test_job_frame ON private.burimunsi_auto_sms_jobs TO postgres USING((current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true' AND current_setting('burimunsi.native_receipt_frame',true)='1') OR current_setting('fixture.seed',true)='yes') WITH CHECK((current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true' AND current_setting('burimunsi.native_receipt_frame',true)='1') OR current_setting('fixture.seed',true)='yes');
 CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_auto_sms_jobs FOR EACH STATEMENT EXECUTE FUNCTION private._burimunsi_native_event_jobs_statement();ALTER TABLE private.burimunsi_auto_sms_jobs ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
 CREATE FUNCTION private.burimunsi_observation_actor(boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$BEGIN
  PERFORM private.burimunsi_setup_fence();IF current_setting('fixture.role',true) IS DISTINCT FROM 'admin' OR current_setting('fixture.consent',true) IS DISTINCT FROM 'yes' OR ($1 AND current_setting('fixture.reveal',true) IS DISTINCT FROM 'yes') THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501';END IF;
  RETURN jsonb_build_object('collectionId',current_setting('fixture.group'),'accountId',current_setting('fixture.account'),'installationId',current_setting('fixture.installation'));END$$;
 CREATE FUNCTION private.burimunsi_observation_history_rows(text) RETURNS TABLE(source_id text,object_key text,principal_user_id text,object_sha256 text) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$DECLARE a jsonb:=private.burimunsi_observation_actor(false);BEGIN
  RETURN QUERY SELECT f.source_id,'synthetic','principal-a',repeat('a',64) FROM private.fixture_sources f WHERE f.source_id=$1 AND f.collection_id=a->>'collectionId' AND f.account_id=(a->>'accountId')::uuid;END$$;
 CREATE FUNCTION private.burimunsi_observation_storage_matches(text,jsonb,text) RETURNS boolean LANGUAGE sql AS $$SELECT true$$;
 CREATE FUNCTION private.burimunsi_observation_own(text,boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$DECLARE a jsonb:=private.burimunsi_observation_actor($2);BEGIN
  IF EXISTS(SELECT 1 FROM private.fixture_sources WHERE source_id=$1 AND collection_id=a->>'collectionId' AND account_id=(a->>'accountId')::uuid AND installation_id=(a->>'installationId')::uuid) THEN RETURN '{}'::jsonb;END IF;RETURN NULL;END$$;
 CREATE FUNCTION private.collect_imported_native_source(text) RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$SELECT coalesce((SELECT imported FROM private.fixture_sources WHERE source_id=$1),false)$$;
 CREATE FUNCTION private.collect_imported_native_job_transaction(text) RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$SELECT coalesce((SELECT imported_job FROM private.fixture_sources WHERE source_id=$1),false)$$;
 `);
 const predecessors=JSON.parse(await readFile(new URL('./fixtures/observation-processing-retention-predecessors.json',import.meta.url),'utf8'));
 await db.query('SET check_function_bodies=off');
 for(const predecessor of predecessors)await db.query(predecessor.definition);
 await db.query('REVOKE ALL ON FUNCTION private._retention_manifest_catalog_v2() FROM PUBLIC;REVOKE ALL ON FUNCTION private.retention_capture_inventory_v2(uuid,text,bigint,text,integer) FROM PUBLIC;GRANT EXECUTE ON FUNCTION private.retention_capture_inventory_v2(uuid,text,bigint,text,integer) TO collect_runtime');
 await db.query(await readFile(new URL('../../../supabase/migrations/20261117134954_burimunsi_observation_processing_status.sql',import.meta.url),'utf8'));checks++;
 const table=(await db.query("SELECT relrowsecurity,relforcerowsecurity FROM pg_class WHERE oid='private.burimunsi_observation_retry_commands'::regclass")).rows[0];assert.deepEqual(table,{relrowsecurity:true,relforcerowsecurity:true});
 assert.equal((await db.query("SELECT tgenabled FROM pg_trigger WHERE tgrelid='private.burimunsi_observation_retry_commands'::regclass AND tgname='collect_fence_statement_v1'")).rows[0].tgenabled,'A');
 assert.equal((await db.query("SELECT c->>'scope' v FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') c WHERE c->>'relation'='private.burimunsi_observation_retry_commands'")).rows[0].v,'unmapped_private');
 assert.match((await db.query("SELECT prosrc FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure")).rows[0].prosrc,/private:burimunsi_observation_retry_commands/);checks++;
 async function asActor(c,fn,{role='admin',group='group-1',consent='yes',fenced='no'}={}){
  await c.query('BEGIN');try{await c.query('SET LOCAL ROLE collect_runtime');await c.query("SELECT set_config('collect.edge_verified','true',true),set_config('fixture.role',$1,true),set_config('fixture.group',$2,true),set_config('fixture.consent',$3,true),set_config('fixture.fenced',$4,true),set_config('fixture.account',$5,true),set_config('fixture.installation',$6,true),set_config('fixture.reveal','no',true),set_config('collect.fence_admission_id','50000000-0000-4000-8000-000000000001',true),set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',repeat('a',64),true)",[role,group,consent,fenced,account,installation]);const v=await fn(c);await c.query('COMMIT');return v;}catch(e){await c.query('ROLLBACK');throw e;}
 }
 const get=(c,ids)=>c.query('SELECT private.burimunsi_observation_processing_status($1::jsonb) result',[JSON.stringify(ids)]).then(r=>r.rows[0].result);
 const retry=(c,id,request)=>c.query('SELECT private.burimunsi_observation_processing_retry($1,$2) result',[id,request]).then(r=>r.rows[0].result);
 const a=await connect('postgres'),b=await connect('postgres');
 const page=await asActor(a,c=>get(c,[source(1),source(2),source(3),source(4),source(5),source(6),source(7),source(8),source(9),source(10)]));
 assert.deepEqual(page.statuses.map(x=>x.status),['needs_review','historical','pending','parsed','unknown','retrying','conflict','retrying','security','pending']);
 assert.deepEqual(page.statuses.map(x=>x.canRetry),[true,false,false,false,false,false,false,false,false,false]);checks++;
 for(const opt of [{role:'staff'},{consent:'no'},{fenced:'yes'}])await assert.rejects(asActor(a,c=>get(c,[source(1)]),opt));
 await assert.rejects(asActor(a,c=>retry(c,source(5),randomUUID())));await assert.rejects(asActor(a,c=>retry(c,source(1),randomUUID()),{role:'staff'}));checks++;
 for(const id of [source(2),source(3),source(4),source(6),source(8),source(9),source(10)])assert.equal((await asActor(a,c=>retry(c,id,randomUUID()))).result,'not_eligible');checks++;
 const cmd=randomUUID();const same=await Promise.all([asActor(a,c=>retry(c,source(1),cmd)),asActor(b,c=>retry(c,source(1),cmd))]);assert.deepEqual(same.map(x=>x.result),['scheduled','scheduled']);
 const raw=await db.query("SELECT set_config('fixture.seed','yes',false)");
 assert.equal((await db.query('SELECT count(*)::int n FROM private.burimunsi_observation_retry_commands WHERE request_id=$1',[cmd])).rows[0]?.n,0); // FORCE RLS hides even the table owner without its frame.
 await db.query("SELECT set_config('fixture.seed','no',false)");
 await db.query("SELECT set_config('fixture.seed','yes',false)");
 await db.query('UPDATE private.burimunsi_auto_sms_jobs SET next_attempt_at=9999999999999 WHERE source_id=$1',[source(1)]);
 const once=await asActor(a,c=>retry(c,source(1),cmd));assert.equal(once.result,'scheduled');
 assert.equal((await db.query('SELECT next_attempt_at FROM private.burimunsi_auto_sms_jobs WHERE source_id=$1',[source(1)])).rows[0].next_attempt_at,'9999999999999');
 await db.query("SELECT set_config('fixture.seed','no',false)");
 await assert.rejects(asActor(a,c=>retry(c,source(3),cmd)));checks++;
 await assert.rejects(asActor(a,c=>c.query('SELECT * FROM private.burimunsi_observation_retry_commands')));
 await assert.rejects(asActor(a,c=>c.query("UPDATE private.burimunsi_auto_sms_jobs SET state='completed'")));
 await assert.rejects(asActor(a,c=>retry(c,source(1),randomUUID()),{fenced:'yes'}));checks++;
 console.log(JSON.stringify({suite:'observation-processing',checks,actualMigration:true,forceRls:true,statementFence:true,staffAndScopeDenied:true,importAndLeaseGuard:true,idempotentRetry:true,cloudWrites:0}));
}finally{for(const c of clients)await c.end().catch(()=>{});await f.close();}
