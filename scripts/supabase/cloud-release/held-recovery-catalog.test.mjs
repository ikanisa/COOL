import test from 'node:test';
import assert from 'node:assert/strict';
import {HELD_RECOVERY_CATALOG_SQL,HELD_RECOVERY_POLICY,HELD_SOURCE_INDEX_CATALOG_SQL,HELD_RESUME_CATALOG_SQL,verifyHeldRecoveryCatalog} from './managed-jobs-operator.mjs';

// A private in-memory PostgreSQL fixture; it opens no network listener and
// does not inspect or modify a Supabase project. The query is the exact one
// used by the scheduler operator, not a JS facsimile of catalog behavior.
const modulePath=process.env.COLLECT_CLOUD_TEST_PGLITE_MODULE;
test('held recovery catalog detects trigger, RLS, policy and privilege drift',{skip:!modulePath},async()=>{
 const {PGlite}=await import(modulePath);const db=new PGlite();
 try{
  await db.exec(`CREATE SCHEMA private; CREATE SCHEMA app;
   CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE ROLE collect_importer; CREATE ROLE collect_runtime;
   CREATE TABLE app.sms_receipts(id text); CREATE TABLE app.momo_processing_jobs(id text);
   CREATE TABLE app.momo_parse_attempts(id text); CREATE TABLE app.momo_transaction_sources(raw_sms_id text,transaction_id text);
   CREATE INDEX burimunsi_momo_sources_raw_lookup ON app.momo_transaction_sources(raw_sms_id,transaction_id);
   CREATE TABLE app.momo_financial_links(id text); CREATE TABLE app.payments(id text,collection_id text);
   CREATE TABLE private.burimunsi_auto_sms_jobs(id text); CREATE TABLE private.burimunsi_native_financial_work(id text);
   CREATE TABLE private.burimunsi_transaction_scopes(id text);
   CREATE TABLE private.burimunsi_observation_requests(id text); CREATE TABLE private.storage_payload_reservations(id text);
   CREATE TABLE private.storage_upload_attempts(id text); CREATE TABLE private.storage_put_intents(id text);
   CREATE TABLE private.collect_sms_witnesses(id text); CREATE TABLE private.burimunsi_recovered_sms_holds(id text);
   CREATE FUNCTION private.noop_trigger() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RETURN NEW; END$$;`);
  for(const name of ['collect_sms_held_source_guard','collect_sms_recovery_work_guard','collect_sms_recovery_raw_work_guard',
   'collect_sms_request_witness_guard','collect_sms_payload_witness_guard','collect_sms_witness_immutable',
   'collect_sms_recovery_scope_guard','collect_sms_recovery_financial_guard','collect_sms_held_upload_guard','trg_storage_identity',
   '_collect_fence_no_erasure','_collect_fence_statement'])
   await db.exec(`CREATE FUNCTION private.${name}() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RETURN NEW; END$$;`);
  for(const [table,name,events,fn,extra] of [
   ['app.sms_receipts','collect_sms_held_source_guard','BEFORE INSERT OR UPDATE','collect_sms_held_source_guard',''],
   ...['private.burimunsi_auto_sms_jobs','private.burimunsi_native_financial_work'].map(t=>[t,'collect_sms_recovery_work_guard','BEFORE INSERT OR UPDATE OR DELETE','collect_sms_recovery_work_guard','']),
   ...['app.momo_processing_jobs','app.momo_parse_attempts','app.momo_transaction_sources'].map(t=>[t,'collect_sms_recovery_raw_work_guard','BEFORE INSERT OR UPDATE OR DELETE','collect_sms_recovery_raw_work_guard','']),
   ['private.burimunsi_transaction_scopes','collect_sms_recovery_scope_guard','BEFORE INSERT OR UPDATE','collect_sms_recovery_scope_guard',''],
   ['app.momo_financial_links','collect_sms_recovery_financial_guard','BEFORE INSERT OR UPDATE','collect_sms_recovery_financial_guard',''],
   ['app.payments','collect_sms_recovery_financial_guard','BEFORE UPDATE OF collection_id','collect_sms_recovery_financial_guard',''],
   ['private.storage_upload_attempts','collect_sms_held_upload_guard','BEFORE INSERT','collect_sms_held_upload_guard',''],
   ['private.storage_upload_attempts','storage_upload_identity','BEFORE UPDATE OR DELETE','trg_storage_identity',''],
   ['private.storage_put_intents','storage_put_identity','BEFORE UPDATE OR DELETE','trg_storage_identity',''],
   ['private.burimunsi_observation_requests','collect_sms_request_witness_guard','AFTER INSERT','collect_sms_request_witness_guard','CONSTRAINT'],
   ['private.storage_payload_reservations','collect_sms_payload_witness_guard','BEFORE INSERT','collect_sms_payload_witness_guard',''],
   ['private.collect_sms_witnesses','collect_sms_witness_immutable','BEFORE UPDATE','collect_sms_witness_immutable',''],
   ['private.burimunsi_recovered_sms_holds','recovered_sms_hold_immutable','BEFORE UPDATE','_collect_fence_no_erasure','STATEMENT'],
   ...['private.collect_sms_witnesses','private.burimunsi_recovered_sms_holds'].flatMap(t=>[
    [t,'collect_fence_statement_v1','BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE','_collect_fence_statement','STATEMENT'],
    [t,'collect_sms_no_erasure','BEFORE DELETE OR TRUNCATE','_collect_fence_no_erasure','STATEMENT']])]){
   await db.exec(`CREATE ${extra==='CONSTRAINT'?'CONSTRAINT ':''}TRIGGER ${name} ${events} ON ${table} ${extra==='CONSTRAINT'?'DEFERRABLE INITIALLY DEFERRED ':''}FOR EACH ${extra==='STATEMENT'?'STATEMENT':'ROW'} EXECUTE FUNCTION private.${fn}(); ALTER TABLE ${table} ENABLE ALWAYS TRIGGER ${name};`);
  }
  for(const table of ['private.collect_sms_witnesses','private.burimunsi_recovered_sms_holds'])await db.exec(`
   ALTER TABLE ${table} ENABLE ROW LEVEL SECURITY; ALTER TABLE ${table} FORCE ROW LEVEL SECURITY;
   REVOKE ALL ON ${table} FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
   CREATE POLICY collect_sms_witness_owner_frame ON ${table} TO postgres
   USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true' AND current_setting('collect.sms_witness_frame',true)='1')
   WITH CHECK(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true' AND current_setting('collect.sms_witness_frame',true)='1');`);
  const check=async()=>verifyHeldRecoveryCatalog((await db.query(HELD_RECOVERY_CATALOG_SQL,[HELD_RECOVERY_POLICY])).rows[0]);
  assert.equal((await db.query(HELD_SOURCE_INDEX_CATALOG_SQL)).rows[0].ok,true);
  await db.exec('DROP INDEX app.burimunsi_momo_sources_raw_lookup');
  assert.equal((await db.query(HELD_SOURCE_INDEX_CATALOG_SQL)).rows[0].ok,false);
  assert.equal((await db.query(HELD_RESUME_CATALOG_SQL)).rows[0].ok,true);
  await db.exec('ALTER TABLE private.storage_upload_attempts DISABLE TRIGGER collect_sms_held_upload_guard');
  assert.equal((await db.query(HELD_RESUME_CATALOG_SQL)).rows[0].ok,false);
  await db.exec('ALTER TABLE private.storage_upload_attempts ENABLE ALWAYS TRIGGER collect_sms_held_upload_guard');
  assert.equal((await db.query(HELD_RESUME_CATALOG_SQL)).rows[0].ok,true);
  await db.exec('CREATE INDEX burimunsi_momo_sources_raw_lookup ON app.momo_transaction_sources(transaction_id,raw_sms_id)');
  assert.equal((await db.query(HELD_SOURCE_INDEX_CATALOG_SQL)).rows[0].ok,false);
  await check();
  await db.exec('ALTER TABLE private.burimunsi_observation_requests DISABLE TRIGGER collect_sms_request_witness_guard');
  await assert.rejects(check,/scheduler_or_history_guard_changed/);
  await db.exec('ALTER TABLE private.burimunsi_observation_requests ENABLE ALWAYS TRIGGER collect_sms_request_witness_guard');await check();
  await db.exec('ALTER TABLE private.collect_sms_witnesses NO FORCE ROW LEVEL SECURITY');
  await assert.rejects(check,/scheduler_or_history_guard_changed/);
  await db.exec('ALTER TABLE private.collect_sms_witnesses FORCE ROW LEVEL SECURITY');await check();
  await db.exec('GRANT SELECT ON private.collect_sms_witnesses TO anon');
  await assert.rejects(check,/scheduler_or_history_guard_changed/);
  await db.exec('REVOKE SELECT ON private.collect_sms_witnesses FROM anon');await check();
  await db.exec('CREATE POLICY unintended ON private.collect_sms_witnesses TO postgres USING (true)');
  await assert.rejects(check,/scheduler_or_history_guard_changed/);
  await db.exec('DROP POLICY unintended ON private.collect_sms_witnesses');await check();
 }finally{await db.close();}
});
