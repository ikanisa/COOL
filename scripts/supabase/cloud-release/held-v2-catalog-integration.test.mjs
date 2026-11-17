// Actual candidate + pinned predecessor function bodies on synthetic in-memory
// tables. PGlite is a single backend: this is not a concurrency qualification.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {HELD_V2_MIGRATION_SHA,HELD_V2_READY_SHA,HELD_V2_READY_IDENTITY_SQL} from '../../../supabase/functions/_shared/domain/burimunsi/held-recovery-v2.js';
const modulePath=process.env.COLLECT_CLOUD_TEST_PGLITE_MODULE;
const dir=new URL('../../../supabase/migrations/',import.meta.url);
const read=name=>readFileSync(new URL(name,dir),'utf8');
const migration=read('20261117220639_burimunsi_held_consent_v2.sql');
const hash=s=>createHash('sha256').update(s).digest('hex');
const patches={
 burimunsi_auto_snapshot:['IF private.collect_imported_native_source(p_source) OR private.collect_imported_native_job_transaction(p_source)',
  'IF private.collect_sms_recovery_held(p_source) OR private.collect_imported_native_source(p_source) OR private.collect_imported_native_job_transaction(p_source)'],
 burimunsi_auto_candidates:['WHERE NOT private.collect_imported_native_source(o.source_id)',
  'WHERE NOT private.collect_sms_recovery_held(o.source_id) AND NOT private.collect_imported_native_source(o.source_id)'],
 burimunsi_native_work_candidates:['WHERE NOT private.collect_imported_native_source(source_id)',
  'WHERE NOT private.collect_sms_recovery_held(source_id) AND NOT private.collect_imported_native_source(source_id)'],
 burimunsi_native_sms_post_candidates:['WHERE NOT private.collect_imported_native_source(j.source_id)',
  'WHERE NOT private.collect_sms_recovery_held(j.source_id) AND NOT private.collect_imported_native_source(j.source_id)']
};
const importedPatches={
 burimunsi_auto_snapshot:[' PERFORM private.burimunsi_setup_fence();',` PERFORM private.burimunsi_setup_fence();
 IF private.collect_imported_native_source(p_source) OR private.collect_imported_native_job_transaction(p_source)
  THEN RAISE EXCEPTION 'imported_native_history_blocked' USING ERRCODE='55000';END IF;`],
 burimunsi_auto_candidates:[" WHERE (p_collection IS NULL OR o.collection_id=p_collection)",` WHERE NOT private.collect_imported_native_source(o.source_id)
  AND (p_collection IS NULL OR o.collection_id=p_collection)`],
 burimunsi_native_work_candidates:["  WHERE collection_id=current_setting('burimunsi.collection_id',true) AND",`  WHERE NOT private.collect_imported_native_source(source_id)
   AND NOT private.collect_imported_native_transaction(transaction_id)
   AND collection_id=current_setting('burimunsi.collection_id',true) AND`],
 burimunsi_native_sms_post_candidates:["  WHERE j.state='completed' AND j.relation='accepted'",`  WHERE NOT private.collect_imported_native_source(j.source_id)
   AND NOT private.collect_imported_native_transaction(j.transaction_id)
   AND j.state='completed' AND j.relation='accepted'`]
};
function definition(name,expected){
 for(const file of readdirSync(dir).filter(f=>f.endsWith('.sql'))){
  const s=read(file),re=new RegExp('CREATE (?:OR REPLACE )?FUNCTION private\\.'+name+'\\s*\\(','gi');
  for(const match of s.matchAll(re)){
   const start=match.index,mark=/\$[A-Za-z_0-9]*\$/.exec(s.slice(start));if(!mark)continue;
   const tag=mark[0],a=start+mark.index+tag.length,b=s.indexOf(tag+';',a);if(b<0)continue;
   let body=s.slice(a,b);if(importedPatches[name])body=body.replace(...importedPatches[name]);
   if(patches[name])body=body.replace(...patches[name]);
   if(hash(body)===expected)return s.slice(start,a)+body+tag+';';
  }
 }
 throw Error('pinned_source_missing: '+name);
}

test('v2 catalog accepts exact pinned synthetic state and denies trigger, ACL and consent drift',{skip:!modulePath},async()=>{
 const {PGlite}=await import(modulePath),db=new PGlite();
 try{
  await db.exec(`CREATE SCHEMA private;CREATE SCHEMA app;CREATE SCHEMA supabase_migrations;
   CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_importer;CREATE ROLE collect_runtime;CREATE ROLE held_probe;
   CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,statements text[]);
   CREATE TABLE private.collect_fence_control(singleton boolean,mode text,source_sha256 text,epoch bigint);
   CREATE TABLE private.burimunsi_observation_consents(collection_id text,account_id uuid,installation_id uuid,
    grant_id uuid,grant_version bigint,generation bigint,enabled boolean);
   CREATE TABLE private.burimunsi_scopes(collection_id text,enabled boolean,active_binding_id text);
   CREATE TABLE app.collections(id text,status text);CREATE TABLE app.admin_grants(user_id text,permission text);
   CREATE TABLE app.admin_account_role_capabilities(role text,permission text);
   CREATE TABLE app.sms_receipts(id text);CREATE TABLE app.momo_processing_jobs(id text);CREATE TABLE app.momo_parse_attempts(id text);
   CREATE TABLE app.momo_transaction_sources(raw_sms_id text,transaction_id text);
   CREATE INDEX burimunsi_momo_sources_raw_lookup ON app.momo_transaction_sources(raw_sms_id,transaction_id);
   CREATE TABLE app.momo_financial_links(id text);CREATE TABLE app.payments(id text,collection_id text);
   CREATE TABLE private.burimunsi_auto_sms_jobs(id text);CREATE TABLE private.burimunsi_native_financial_work(id text);
   CREATE TABLE private.burimunsi_transaction_scopes(id text);CREATE TABLE private.burimunsi_observation_requests(id text);
   CREATE TABLE private.storage_payload_reservations(id text);CREATE TABLE private.storage_upload_attempts(id text);
   CREATE TABLE private.storage_put_intents(id text);CREATE TABLE private.collect_sms_witnesses(id text);
   CREATE TABLE private.burimunsi_recovered_sms_holds(id text);
   CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private._collect_fence_require_runtime() RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private.burimunsi_pin_assert_actor(text,text,text,bigint,bigint) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE FUNCTION private.burimunsi_pin_context() RETURNS TABLE(collection_id text,account_id uuid,principal_user_id text,
    native_session_id uuid,installation_id uuid,grant_id uuid,grant_version bigint,role text,profile text,capabilities text[],shared_role text)
    LANGUAGE sql AS $$SELECT 'group-a','10000000-0000-4000-8000-000000000001'::uuid,'owner-a',
     '40000000-0000-4000-8000-000000000001'::uuid,'20000000-0000-4000-8000-000000000001'::uuid,
     '30000000-0000-4000-8000-000000000001'::uuid,1::bigint,'admin','internal_receiver',ARRAY['sms.read','gateway.manage'],'owner'$$;
   INSERT INTO private.collect_fence_control VALUES(true,'fenced',repeat('a',64),1);
   INSERT INTO private.burimunsi_observation_consents VALUES('group-a','10000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,1,true);
   INSERT INTO private.burimunsi_scopes VALUES('group-a',true,NULL);INSERT INTO app.collections VALUES('group-a','active');
   INSERT INTO app.admin_grants VALUES('owner-a','sms.read'),('owner-a','sms.reveal');
   INSERT INTO app.admin_account_role_capabilities VALUES('owner','sms.read'),('owner','sms.reveal');
   SET check_function_bodies=off;`);
  await db.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2::text[])',
   ['20261117220000',[read('20261117220000_burimunsi_held_resume_guard.sql')]]);
  await db.exec(migration);
  const pairs=[...migration.matchAll(/\('(private\.[^']+\([^']*\))','([a-f0-9]{64})'\)/g)].map(m=>[m[1],m[2]]);
  assert.equal(pairs.length,33);
  const runtimeLine=migration.split('\n').find(x=>x.includes("p.proacl::text IS DISTINCT FROM '{postgres=X/postgres,collect_runtime=X/postgres}'"));
  assert(runtimeLine);
  for(const [sig,digest] of pairs){
   if(sig.startsWith('private.burimunsi_sms_recovery_prepare('))continue;
   const name=sig.slice('private.'.length,sig.indexOf('('));await db.exec(definition(name,digest));
   await db.exec(`REVOKE ALL ON FUNCTION ${sig} FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;`);
   if(runtimeLine.includes("'"+sig+"'"))await db.exec(`GRANT EXECUTE ON FUNCTION ${sig} TO collect_runtime;`);
  }
  const base=read('20261111121000_burimunsi_private_observations.sql');
  const a=base.indexOf('CREATE OR REPLACE FUNCTION private.trg_storage_identity()'),b=base.indexOf('$storage_identity$;',base.indexOf('$storage_identity$',a)+18);
  assert(a>=0&&b>a);await db.exec(base.slice(a,b+'$storage_identity$;'.length));
  for(const [table,name,events,fn,kind] of [
   ['app.sms_receipts','collect_sms_held_source_guard','BEFORE INSERT OR UPDATE','collect_sms_held_source_guard',''],
   ...['private.burimunsi_auto_sms_jobs','private.burimunsi_native_financial_work'].map(t=>[t,'collect_sms_recovery_work_guard','BEFORE INSERT OR UPDATE OR DELETE','collect_sms_recovery_work_guard','']),
   ...['app.momo_processing_jobs','app.momo_parse_attempts','app.momo_transaction_sources'].map(t=>[t,'collect_sms_recovery_raw_work_guard','BEFORE INSERT OR UPDATE OR DELETE','collect_sms_recovery_raw_work_guard','']),
   ['private.burimunsi_transaction_scopes','collect_sms_recovery_scope_guard','BEFORE INSERT OR UPDATE','collect_sms_recovery_scope_guard',''],
   ['app.momo_financial_links','collect_sms_recovery_financial_guard','BEFORE INSERT OR UPDATE','collect_sms_recovery_financial_guard',''],
   ['app.payments','collect_sms_recovery_financial_guard','BEFORE UPDATE OF collection_id','collect_sms_recovery_financial_guard',''],
   ['private.storage_payload_reservations','collect_sms_held_payload_guard','BEFORE INSERT','collect_sms_held_payload_guard',''],
   ['private.storage_upload_attempts','collect_sms_held_upload_guard','BEFORE INSERT','collect_sms_held_upload_guard',''],
   ['private.storage_upload_attempts','storage_upload_identity','BEFORE UPDATE OR DELETE','trg_storage_identity',''],
   ['private.storage_put_intents','storage_put_identity','BEFORE UPDATE OR DELETE','trg_storage_identity',''],
   ['private.burimunsi_observation_requests','collect_sms_request_witness_guard','AFTER INSERT','collect_sms_request_witness_guard','CONSTRAINT'],
   ['private.storage_payload_reservations','collect_sms_payload_witness_guard','BEFORE INSERT','collect_sms_payload_witness_guard',''],
   ['private.collect_sms_witnesses','collect_sms_witness_immutable','BEFORE UPDATE','collect_sms_witness_immutable',''],
   ['private.burimunsi_recovered_sms_holds','recovered_sms_hold_immutable','BEFORE UPDATE','_collect_fence_no_erasure','STATEMENT'],
   ...['private.collect_sms_witnesses','private.burimunsi_recovered_sms_holds'].flatMap(t=>[
    [t,'collect_fence_statement_v1','BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE','_collect_fence_statement','STATEMENT'],
    [t,'collect_sms_no_erasure','BEFORE DELETE OR TRUNCATE','_collect_fence_no_erasure','STATEMENT']])])
   await db.exec(`CREATE ${kind==='CONSTRAINT'?'CONSTRAINT ':''}TRIGGER ${name} ${events} ON ${table} ${kind==='CONSTRAINT'?'DEFERRABLE INITIALLY DEFERRED ':''}FOR EACH ${kind==='STATEMENT'?'STATEMENT':'ROW'} EXECUTE FUNCTION private.${fn}(); ALTER TABLE ${table} ENABLE ALWAYS TRIGGER ${name};`);
  for(const table of ['private.collect_sms_witnesses','private.burimunsi_recovered_sms_holds'])await db.exec(`
   ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY;ALTER TABLE ${table} FORCE ROW LEVEL SECURITY;
   REVOKE ALL ON ${table} FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
   CREATE POLICY collect_sms_witness_owner_frame ON ${table} TO postgres
    USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true' AND current_setting('collect.sms_witness_frame',true)='1')
    WITH CHECK(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true' AND current_setting('collect.sms_witness_frame',true)='1');`);
  for(const [version,file] of [['20261117205959','20261117205959_burimunsi_sms_source_index.sql'],
   ['20261117210000','20261117210000_burimunsi_held_recovery.sql'],['20261117220639','20261117220639_burimunsi_held_consent_v2.sql']])
   await db.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2::text[])',[version,[read(file)]]);
  await db.exec(`UPDATE private.collect_fence_control SET mode='open';
   SELECT set_config('collect.fence_source_sha256',repeat('a',64),false),set_config('collect.fence_epoch','1',false),
    set_config('collect.fence_admission_id','40000000-0000-4000-8000-000000000001',false),set_config('burimunsi.collection_id','group-a',false);`);
  assert.equal((await db.query(HELD_V2_READY_IDENTITY_SQL,[HELD_V2_READY_SHA])).rows[0].ok,true);
  const call=()=>db.query('SELECT private.burimunsi_held_v2_ready($1,$2,$3) AS result',['a'.repeat(64),1,HELD_V2_MIGRATION_SHA]);
  assert.equal((await call()).rows[0].result.groupId,'group-a');
  for(const sig of ['private.burimunsi_auto_snapshot(text)','private.burimunsi_auto_candidates(text)',
   'private.burimunsi_native_work_candidates(uuid,integer)','private.burimunsi_native_sms_post_candidates(integer)']){
   await db.exec(`GRANT EXECUTE ON FUNCTION ${sig} TO held_probe`);
   await assert.rejects(call,/sms_held_v2_guard_changed/);
   await db.exec(`REVOKE EXECUTE ON FUNCTION ${sig} FROM held_probe`);
   await db.exec(`ALTER FUNCTION ${sig} STABLE`);
   await assert.rejects(call,/sms_held_v2_guard_changed/);
   await db.exec(`ALTER FUNCTION ${sig} VOLATILE`);
   assert.equal((await call()).rows[0].result.groupId,'group-a');
  }
  // Membership must not silently grant an unrelated role the runtime's
  // effective execution privileges, including via NOINHERIT + SET ROLE.
  await db.exec('ALTER ROLE held_probe NOINHERIT;GRANT collect_runtime TO held_probe');
  await assert.rejects(call,/sms_held_v2_guard_changed/);
  await db.exec('REVOKE collect_runtime FROM held_probe');
  assert.equal((await call()).rows[0].result.groupId,'group-a');
  await db.exec('ALTER TABLE private.storage_upload_attempts DISABLE TRIGGER collect_sms_held_upload_guard');
  await assert.rejects(call,/sms_held_v2_catalog_changed/);
  await db.exec('ALTER TABLE private.storage_upload_attempts ENABLE ALWAYS TRIGGER collect_sms_held_upload_guard');
  await db.exec('REVOKE EXECUTE ON FUNCTION private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint,text,text) FROM collect_runtime');
  await assert.rejects(call,/sms_held_v2_guard_changed/);
  await db.exec('GRANT EXECUTE ON FUNCTION private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint,text,text) TO collect_runtime');
  await db.exec('UPDATE private.burimunsi_observation_consents SET enabled=false,generation=2');
  await db.exec('UPDATE private.burimunsi_observation_consents SET enabled=true,generation=3');
  await assert.rejects(call,/sms_held_v2_consent_changed/);
 }finally{await db.close();}
});
