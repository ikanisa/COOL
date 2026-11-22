// Owned socket-only PostgreSQL 17: actual pinned history/actor/audit/projection
// functions, synthetic identities and Storage metadata, no real messages.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {verifyBinaryPins,verifyEnvironment,BIN} from '../managed-identity-provider-compat/fixture-safety.mjs';
const {Client}=createRequire(import.meta.url)('pg');
const read=path=>readFile(new URL(`../../../${path}`,import.meta.url),'utf8');
const extract=(source,name)=>{
 let start=source.indexOf(`CREATE FUNCTION private.${name}(`);if(start<0)start=source.indexOf(`CREATE OR REPLACE FUNCTION private.${name}(`);
 const end=source.indexOf('$fn$;',source.indexOf('$fn$',start)+4);assert(start>=0&&end>=0);return source.slice(start,end+5);
};
const ids={account:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',other:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
 currentInstallation:'10000000-0000-4000-8000-000000000001',oldInstallation:'10000000-0000-4000-8000-000000000002',
 currentGrant:'20000000-0000-4000-8000-000000000001',oldGrant:'20000000-0000-4000-8000-000000000002',
 session:'30000000-0000-4000-8000-000000000001',request:'40000000-0000-4000-8000-000000000001'};
let fixture;const clients=[];let checks=0;
try{
 verifyEnvironment(process.env);await verifyBinaryPins();
 fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_history_read_fixture'});
 assert.equal(fixture.bin,BIN);
 async function connect(user){const c=new Client({host:fixture.socket,port:fixture.port,user,database:'postgres',connectionTimeoutMillis:5000});c.on('error',()=>{});await c.connect();clients.push(c);return c;}
 const root=await connect('fixture_bootstrap');
 await root.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS;CREATE ROLE anon;CREATE ROLE authenticated;
  CREATE ROLE service_role;CREATE ROLE collect_importer;CREATE ROLE collect_runtime;GRANT collect_runtime TO postgres;
  CREATE SCHEMA private AUTHORIZATION postgres;CREATE SCHEMA app AUTHORIZATION postgres;GRANT USAGE ON SCHEMA private,app TO collect_runtime;`);
 const owner=await connect('postgres'),other=await connect('fixture_bootstrap');
 const identity=(await owner.query("SELECT session_user u,current_user c,inet_server_addr() IS NULL sock,current_setting('cluster_name') n")).rows[0];
 assert.deepEqual(identity,{u:'postgres',c:'postgres',sock:true,n:'collect_history_read_fixture'});
 await owner.query(`CREATE TABLE private.collect_fence_control(singleton boolean,mode text);INSERT INTO private.collect_fence_control VALUES(true,'fenced');
  CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE sql AS $$ SELECT $$;
  CREATE FUNCTION private._collect_fence_require_runtime() RETURNS void LANGUAGE plpgsql AS $$ BEGIN
   IF current_setting('role',true)<>'collect_runtime' OR current_setting('collect.edge_verified',true)<>'true' THEN RAISE EXCEPTION 'denied' USING ERRCODE='42501';END IF;END $$;
  CREATE FUNCTION private.burimunsi_setup_fence() RETURNS void LANGUAGE sql AS $$ SELECT $$;
  CREATE TABLE private.test_context(key text,collection_id text,account_id uuid,principal_user_id text,role text,profile text,
   capabilities text[],shared_role text,native_session_id uuid,installation_id uuid,grant_id uuid,grant_version bigint);
  CREATE FUNCTION private.burimunsi_pin_context() RETURNS SETOF private.test_context LANGUAGE sql SECURITY DEFINER AS $$
   SELECT * FROM private.test_context WHERE key=current_setting('test.actor',true) $$;
  CREATE FUNCTION private.burimunsi_pin_assert_actor(text,text,text,integer,text) RETURNS void LANGUAGE sql AS $$ SELECT $$;
  CREATE TABLE private.burimunsi_scopes(collection_id text,enabled boolean,active_binding_id text);
  CREATE TABLE app.collections(id text,status text);
  CREATE TABLE app.admin_grants(user_id text,permission text);
  CREATE TABLE app.admin_account_role_capabilities(role text,permission text);
  CREATE TABLE private.burimunsi_observation_consents(collection_id text,account_id uuid,installation_id uuid,grant_id uuid,grant_version bigint,generation bigint,enabled boolean);
  CREATE TABLE private.burimunsi_device_grants(id uuid,collection_id text,installation_id uuid,version bigint,active boolean,profile text);
  CREATE TABLE private.burimunsi_device_accounts(grant_id uuid,collection_id text,account_id uuid);
  CREATE TABLE private.burimunsi_unresolved_observations(source_id text,collection_id text,account_id uuid,principal_user_id text,installation_id uuid,
   grant_id uuid,grant_version bigint,request_id uuid,fingerprint text,body_sha256 text,object_key text,object_sha256 text,size_bytes bigint,created_at bigint);
  CREATE TABLE private.burimunsi_native_receipt_origins(source_id text,collection_id text,account_id uuid,principal_user_id text,installation_id uuid,
   grant_id uuid,grant_version bigint,request_id uuid,fingerprint text,body_sha256 text,object_sha256 text);
  CREATE TABLE private.collect_imported_native_history(source_id text,collection_id text,request_id uuid,source_fingerprint text,body_sha256 text,object_sha256 text);
  CREATE TABLE private.collect_migration_actor_lineage(source_actor_id text,cloud_primary_id text);
  CREATE TABLE private.burimunsi_auto_sms_jobs(source_id text,collection_id text,state text,payment_outcome text,posting_facts jsonb);
  CREATE TABLE private.test_storage(key text,scope jsonb,object_sha256 text);
  CREATE FUNCTION private.burimunsi_observation_storage_matches(text,jsonb,text) RETURNS boolean LANGUAGE sql AS $$
   SELECT EXISTS(SELECT 1 FROM private.test_storage WHERE key=$1 AND scope=$2 AND object_sha256=$3) $$;
  CREATE FUNCTION private.collect_imported_native_source(text) RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$
   SELECT EXISTS(SELECT 1 FROM private.collect_imported_native_history WHERE source_id=$1) $$;
  CREATE FUNCTION private.burimunsi_observation_own(text,boolean) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$ SELECT NULL::jsonb $$;
  CREATE TABLE app.audit_log(actor_user_id text,actor_session_id text,action text,entity_type text,entity_id text,request_id text,details_json text,created_at text);
  CREATE FUNCTION private.test_audit() RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$
   SELECT jsonb_build_object('n',count(*),'actor',min(actor_user_id),'session',min(actor_session_id),'entity',min(entity_id)) FROM app.audit_log $$;
  GRANT EXECUTE ON FUNCTION private.test_audit() TO collect_runtime;
  CREATE FUNCTION app.strftime(text) RETURNS text LANGUAGE sql AS $$ SELECT '2026-01-01T00:00:00.000Z'::text $$;
  ALTER TABLE private.collect_imported_native_history ENABLE ROW LEVEL SECURITY;ALTER TABLE private.collect_imported_native_history FORCE ROW LEVEL SECURITY;
  CREATE POLICY owner_history ON private.collect_imported_native_history TO postgres USING(true) WITH CHECK(true);
  ALTER TABLE private.collect_migration_actor_lineage ENABLE ROW LEVEL SECURITY;ALTER TABLE private.collect_migration_actor_lineage FORCE ROW LEVEL SECURITY;
  CREATE POLICY owner_lineage ON private.collect_migration_actor_lineage TO postgres USING(true) WITH CHECK(true);
  ALTER TABLE private.burimunsi_native_receipt_origins ENABLE ROW LEVEL SECURITY;ALTER TABLE private.burimunsi_native_receipt_origins FORCE ROW LEVEL SECURITY;
  CREATE POLICY origin_frame ON private.burimunsi_native_receipt_origins TO postgres USING(
   current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true' AND current_setting('burimunsi.native_receipt_frame',true)='1');
  ALTER TABLE private.burimunsi_unresolved_observations ENABLE ROW LEVEL SECURITY;ALTER TABLE private.burimunsi_unresolved_observations FORCE ROW LEVEL SECURITY;
  CREATE POLICY observation_frame ON private.burimunsi_unresolved_observations TO postgres USING(
   current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true' AND current_setting('burimunsi.observation_frame',true)='1');
  ALTER TABLE private.burimunsi_auto_sms_jobs ENABLE ROW LEVEL SECURITY;ALTER TABLE private.burimunsi_auto_sms_jobs FORCE ROW LEVEL SECURITY;
  CREATE POLICY job_frame ON private.burimunsi_auto_sms_jobs TO postgres USING(
   current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true' AND current_setting('burimunsi.native_receipt_frame',true)='1');
  REVOKE ALL ON private.collect_migration_actor_lineage,private.collect_imported_native_history FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
 `);
 const observations=await read('supabase/migrations/20261111121000_burimunsi_private_observations.sql');
 const history=await read('supabase/migrations/20261113130200_burimunsi_account_sms_history.sql');
 const auto=await read('supabase/migrations/20261112200100_burimunsi_native_auto_transactions.sql');
 for(const [source,name] of [[observations,'burimunsi_observation_actor'],[observations,'burimunsi_observation_consent_current'],
  [history,'burimunsi_observation_history_rows'],[history,'burimunsi_observation_page'],[history,'burimunsi_observation_history_own'],
  [history,'burimunsi_observation_history_reveal_audit']])await owner.query(extract(source,name));
 let projection=extract(auto,'burimunsi_auto_projection').replace(
  "RETURN jsonb_build_object('sourceId',j.source_id,'outcome',j.payment_outcome,'canReveal',can_reveal);",
  "RETURN jsonb_build_object('sourceId',j.source_id,'outcome',coalesce(j.posting_facts->>'payment_outcome',j.payment_outcome),'canReveal',can_reveal,'facts',j.posting_facts);");
 await owner.query(projection);
 await owner.query(`REVOKE ALL ON FUNCTION private.burimunsi_observation_history_rows(text),private.burimunsi_observation_page(text,text,integer,integer),
  private.burimunsi_observation_history_own(text),private.burimunsi_observation_history_reveal_audit(text,uuid,text,uuid,text,text,text,bigint),
  private.burimunsi_auto_projection(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
  GRANT EXECUTE ON FUNCTION private.burimunsi_observation_page(text,text,integer,integer),private.burimunsi_observation_history_own(text),
   private.burimunsi_observation_history_reveal_audit(text,uuid,text,uuid,text,text,text,bigint),private.burimunsi_auto_projection(text) TO collect_runtime;`);
 const seed=`INSERT INTO private.burimunsi_scopes VALUES('group-a',true,NULL),('group-b',true,NULL);
  INSERT INTO app.collections VALUES('group-a','active'),('group-b','active');
  INSERT INTO app.admin_grants VALUES('cloud-owner','sms.read'),('cloud-owner','sms.reveal'),('other-owner','sms.read'),('other-owner','sms.reveal');
  INSERT INTO app.admin_account_role_capabilities VALUES('owner','sms.read'),('owner','sms.reveal');
  INSERT INTO private.test_context VALUES
   ('admin','group-a',$1,'cloud-owner','admin','internal_receiver',ARRAY['sms.read','gateway.manage','records.read'],'owner',$2,$3,$4,1),
   ('staff','group-a',$1,'cloud-owner','staff','internal_receiver',ARRAY['records.read'],'owner',$2,$3,$4,1),
   ('wrong-principal','group-a',$1,'other-owner','admin','internal_receiver',ARRAY['sms.read','gateway.manage','records.read'],'owner',$2,$3,$4,1),
   ('wrong-account','group-a',$5,'cloud-owner','admin','internal_receiver',ARRAY['sms.read','gateway.manage','records.read'],'owner',$2,$3,$4,1),
   ('wrong-profile','group-a',$1,'cloud-owner','admin','staff',ARRAY['sms.read','gateway.manage','records.read'],'owner',$2,$3,$4,1);
  INSERT INTO private.burimunsi_observation_consents VALUES('group-a',$1,$3,$4,1,2,true),('group-a',$5,$3,$4,1,2,true),
   ('group-a',$1,$6,$7,1,1,false);
  INSERT INTO private.burimunsi_device_grants VALUES($4,'group-a',$3,1,true,'internal_receiver'),($7,'group-a',$6,1,false,'internal_receiver');
  INSERT INTO private.burimunsi_device_accounts VALUES($4,'group-a',$1),($7,'group-a',$1);
  INSERT INTO private.burimunsi_unresolved_observations VALUES
   ('old-source','group-a',$1,'old-principal',$6,$7,1,$8,'fp','body','sms/old-source','object',8,10),
   ('bad-marker','group-a',$1,'old-principal',$6,$7,1,$8,'fp','body','sms/bad-marker','object',8,11),
   ('unmarked','group-a',$1,'old-principal',$6,$7,1,$8,'fp','body','sms/unmarked','object',8,12),
   ('live-source','group-a',$1,'cloud-owner',$3,$4,1,$8,'live-fp','live-body','sms/live-source','live-object',8,13),
   ('other-group','group-b',$1,'old-principal',$6,$7,1,$8,'fp','body','sms/other-group','object',8,14);
  INSERT INTO private.burimunsi_native_receipt_origins SELECT source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,request_id,fingerprint,body_sha256,object_sha256
   FROM private.burimunsi_unresolved_observations;
  INSERT INTO private.collect_imported_native_history VALUES('old-source','group-a',$8,'fp','body','object'),('bad-marker','group-a',$8,'fp','WRONG','object'),('other-group','group-b',$8,'fp','body','object');
  INSERT INTO private.collect_migration_actor_lineage VALUES('old-principal','cloud-owner');
  INSERT INTO private.burimunsi_auto_sms_jobs VALUES('old-source','group-a','completed','successful',NULL);
  INSERT INTO private.test_storage VALUES('sms/old-source',jsonb_build_object('ownerId','old-principal','purpose','sms_receipt','entityId','old-source'),'object'),
   ('sms/live-source',jsonb_build_object('ownerId','cloud-owner','purpose','sms_receipt','entityId','live-source'),'live-object');`;
 const values=[ids.account,ids.session,ids.currentInstallation,ids.currentGrant,ids.other,ids.oldInstallation,ids.oldGrant,ids.request];
 assert(values.every(x=>/^[0-9a-f-]{36}$/.test(x)));
 await root.query(seed.replace(/\$(\d+)/g,(_m,n)=>`'${values[Number(n)-1]}'::uuid`));
 const patch=await read('scripts/supabase/cloud-release/imported-history-read.sql');
 await owner.query('BEGIN');await owner.query(patch);await owner.query('COMMIT');
 await owner.query('BEGIN');await owner.query('SET LOCAL ROLE collect_runtime');
 await owner.query("SELECT set_config('collect.edge_verified','true',true),set_config('test.actor','admin',true),set_config('burimunsi.native_receipt_frame','previous',true)");
 const page=()=>owner.query("SELECT private.burimunsi_observation_page('','all',100,0) v");
 let v=(await page()).rows[0].v;assert.equal(v.totalCount,2);assert.deepEqual(v.items.map(x=>x.id).sort(),['live-source','old-source']);checks++;
 assert.equal((await owner.query("SELECT current_setting('burimunsi.native_receipt_frame') v")).rows[0].v,'previous');checks++;
 const proof=(await owner.query("SELECT private.burimunsi_observation_history_own('old-source') v")).rows[0].v;
 assert.equal(proof.principalUserId,'old-principal');assert.equal(proof.object_key,'sms/old-source');checks+=2;
 assert.equal((await owner.query("SELECT private.burimunsi_auto_projection('old-source') v")).rows[0].v.canReveal,true);checks++;
 const audit=(await owner.query('SELECT private.burimunsi_observation_history_reveal_audit($1,$2,$3,$4,$5,$6,$7,$8) v',
  ['old-source',ids.request,'review history',ids.session,'body','object','fp',2])).rows[0].v;
 assert.equal(audit.principalUserId,'old-principal');assert.deepEqual((await owner.query('SELECT private.test_audit() v')).rows[0].v,
  {n:1,actor:'cloud-owner',session:ids.session,entity:'old-source'});checks+=2;
 await owner.query('SAVEPOINT test');
 const denied=async(sql,args=[],code='42501')=>{await assert.rejects(()=>owner.query(sql,args),e=>e.code===code);checks++;await owner.query('ROLLBACK TO SAVEPOINT test');};
 await denied('SELECT * FROM private.collect_migration_actor_lineage');
 await denied('SELECT private.burimunsi_observation_history_reveal_audit($1,$2,$3,$4,$5,$6,$7,$8)',
  ['old-source',ids.request,'review history',ids.session,'WRONG','object','fp',2],'40001');
 for(const actor of ['wrong-principal','wrong-account']){
  await owner.query("SELECT set_config('test.actor',$1,true)",[actor]);assert.equal((await page()).rows[0].v.totalCount,0);checks++;
 }
 await owner.query("SELECT set_config('test.actor','staff',true)");assert.equal((await owner.query("SELECT private.burimunsi_auto_projection('old-source') v")).rows[0].v.canReveal,false);checks++;
 await denied("SELECT private.burimunsi_observation_history_own('old-source')");
 await owner.query("SELECT set_config('test.actor','wrong-profile',true)");await denied("SELECT private.burimunsi_observation_history_own('old-source')");
 await owner.query('ROLLBACK');
 // The reader locks the current consent during disclosure; a concurrent
 // revocation cannot commit until that disclosure transaction finishes.
 await owner.query('BEGIN');await owner.query('SET LOCAL ROLE collect_runtime');
 await owner.query("SELECT set_config('collect.edge_verified','true',true),set_config('test.actor','admin',true)");
 await owner.query("SELECT private.burimunsi_observation_history_own('old-source')");
 await other.query('BEGIN');await other.query("SET LOCAL lock_timeout='250ms'");
 await assert.rejects(()=>other.query('UPDATE private.burimunsi_observation_consents SET enabled=false WHERE collection_id=$1 AND account_id=$2 AND installation_id=$3',
  ['group-a',ids.account,ids.currentInstallation]),e=>e.code==='55P03');checks++;
 await other.query('ROLLBACK');await owner.query('COMMIT');
 await other.query('UPDATE private.burimunsi_observation_consents SET enabled=false WHERE collection_id=$1 AND account_id=$2 AND installation_id=$3',
  ['group-a',ids.account,ids.currentInstallation]);
 await owner.query('BEGIN');await owner.query('SET LOCAL ROLE collect_runtime');
 await owner.query("SELECT set_config('collect.edge_verified','true',true),set_config('test.actor','admin',true)");
 await assert.rejects(()=>owner.query("SELECT private.burimunsi_observation_history_own('old-source')"),e=>e.code==='42501');checks++;
 await owner.query('ROLLBACK');
 console.log(JSON.stringify({status:'PASS',checks,fixture:'owned-socket-only-pg17',actualPinnedFunctions:true,productionDispatched:false}));
}finally{
 await Promise.allSettled(clients.map(c=>c.end()));if(fixture){const result=await fixture.close();assert.equal(result.removed,true);}await verifyBinaryPins();
}
