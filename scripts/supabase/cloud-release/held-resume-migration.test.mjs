import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {HELD_RESUME_CATALOG_SQL} from './managed-jobs-operator.mjs';
import {PostgresStorageJournal} from '../../../supabase/functions/_shared/storage/postgres-journal.js';
import {ProtectedStorageProtocol} from '../../../supabase/functions/_shared/storage/protocol.js';

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
   CREATE TABLE private.burimunsi_observation_consents(collection_id text,account_id uuid,installation_id uuid,grant_id uuid,
    grant_version bigint,generation bigint,enabled boolean);
   CREATE TABLE private.burimunsi_recovered_sms_holds(source_id text,object_key text,collection_id text,account_id uuid,owner_id text,
    body_sha256 text,inbox_received_at timestamptz,request_digest text);
   CREATE TABLE private.collect_sms_witnesses(object_key text,owner_id text,collection_id text,body_sha256 text,inbox_received_at timestamptz,request_digest text);
   CREATE TABLE private.burimunsi_unresolved_observations(source_id text);CREATE TABLE private.burimunsi_auto_sms_jobs(source_id text);
   CREATE TABLE private.burimunsi_native_financial_work(source_id text);CREATE TABLE app.sms_receipts(id text);
   CREATE TABLE app.privacy_retention_barriers(subject_id text);
   CREATE TABLE private.storage_namespace(singleton boolean PRIMARY KEY,origin text,bucket text);
   CREATE TABLE private.storage_payload_reservations(object_key text PRIMARY KEY,source_fingerprint text,scope jsonb,aad text,
    key_id text,plaintext_sha256 text,sealed_body text,cleared_at timestamptz);
   CREATE TABLE private.storage_put_intents(operation_id text PRIMARY KEY,object_key text UNIQUE,fingerprint text,sha256 text,size bigint,
    scope jsonb,http_metadata jsonb,custom_metadata jsonb,state text DEFAULT 'pending',attempts integer DEFAULT 0,active_attempt uuid,
    upload_unresolved boolean DEFAULT false,delete_tombstone boolean DEFAULT false,last_outcome text,
    created_at timestamptz DEFAULT clock_timestamp(),updated_at timestamptz DEFAULT clock_timestamp());
   CREATE TABLE private.storage_upload_attempts(id uuid PRIMARY KEY,operation_id text,outcome text DEFAULT 'started',
    started_at timestamptz DEFAULT clock_timestamp(),completed_at timestamptz);
   CREATE FUNCTION private.collect_sms_witness_reserve(text,text,text,text,text,text,timestamptz,text) RETURNS boolean
    LANGUAGE sql AS $$SELECT true$$;
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
  await db.exec(`INSERT INTO private.burimunsi_observation_consents VALUES('group-a','10000000-0000-4000-8000-000000000001',
   '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,1,true)`);
  await db.exec("SELECT set_config('collect.fence_admission_id','00000000-0000-4000-8000-000000000005',false),set_config('collect.fence_epoch','1',false),set_config('collect.fence_source_sha256',repeat('f',64),false)");
  assert.equal((await db.query('SELECT private.collect_sms_held_resume_check($1,$2,$3,$4,$5) AS ok',[source,req,fingerprint,body,time])).rows[0].ok,true);
  await db.exec("SELECT set_config('fixture.generation','2',false)");
  await assert.rejects(()=>db.query('SELECT private.collect_sms_held_resume_check($1,$2,$3,$4,$5)',[source,req,fingerprint,body,time]),/sms_held_resume_consent_changed/);
  await db.query("INSERT INTO private.storage_put_intents(operation_id,object_key,scope) VALUES('operation',$1,$2::jsonb)",
   ['sms/'+source,JSON.stringify({ownerId:'owner-a',purpose:'sms_receipt',entityId:source})]);
  await db.exec("INSERT INTO private.storage_upload_attempts(id,operation_id) VALUES('00000000-0000-4000-8000-000000000010','operation')");
  await assert.rejects(()=>db.exec("INSERT INTO private.storage_upload_attempts(id,operation_id) VALUES('00000000-0000-4000-8000-000000000011','operation')"),/sms_held_upload_already_attempted/);
  await assert.rejects(()=>db.exec('DELETE FROM private.storage_upload_attempts'),/retain_storage_control_identity/);
  await db.exec("UPDATE private.storage_put_intents SET attempts=1 WHERE operation_id='operation'");
  await assert.rejects(()=>db.exec("UPDATE private.storage_put_intents SET attempts=0 WHERE operation_id='operation'"),/storage_state_regression/);
  // Exercise the real journal and protected-storage protocol: even a known
  // accepted PUT followed by a 404 probe cannot produce a second PUT.
  const source2='00000000-0000-4000-8000-000000000002',key='sms/'+source2;
  await db.query(`INSERT INTO private.burimunsi_recovered_sms_holds VALUES($1,$2,'group-a','10000000-0000-4000-8000-000000000001','owner-a',$3,$4,$5)`,
   [source2,key,body,time,fingerprint]);
  await db.query(`INSERT INTO private.burimunsi_observation_requests VALUES($1,'group-a','10000000-0000-4000-8000-000000000001','owner-a',
   '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,$2,$3,$4,$5,1)`,[source2,req,fingerprint,'c'.repeat(64),body]);
  let pinBindings=0;
  const pool={async connect(){return {query:(text,values=[])=>db.query(text,values),
   async bindPhonePinContext(){pinBindings++;},release(){}};}};
  const journal=new PostgresStorageJournal(pool,{namespace:{origin:'https://synthetic.invalid',bucket:'synthetic'}});
  let uploads=0,probes=0;
  const protocol=new ProtectedStorageProtocol({journal,transport:{
   async uploadImmutable(){uploads++;return {status:200};},
   async probe(){probes++;return {absent:true,headStatus:404,getStatus:404,bucketVerified:true};}}});
  const opts={scope:{ownerId:'owner-a',purpose:'sms_receipt',entityId:source2}};
  await assert.rejects(()=>protocol.put(key,'synthetic ciphertext',opts),/storage_object_not_retained/);
  await assert.rejects(()=>protocol.put(key,'synthetic ciphertext',opts),/sms_held_upload_already_attempted/);
  assert.equal(uploads,1);assert.equal(probes,2);
  const source3='00000000-0000-4000-8000-000000000003',key3='sms/'+source3;
  await db.query(`INSERT INTO private.burimunsi_recovered_sms_holds VALUES($1,$2,'group-a','10000000-0000-4000-8000-000000000001','owner-a',$3,$4,$5)`,
   [source3,key3,body,time,fingerprint]);
  await db.query(`INSERT INTO private.burimunsi_observation_requests VALUES($1,'group-a','10000000-0000-4000-8000-000000000001','owner-a',
   '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,$2,$3,$4,$5,1)`,[source3,req,fingerprint,'c'.repeat(64),body]);
  let unknownUploads=0;
  const unknownProtocol=new ProtectedStorageProtocol({journal,transport:{
   async uploadImmutable(){unknownUploads++;throw Error('synthetic provider outcome unknown');},
   async probe(){return {absent:true,headStatus:404,getStatus:404,bucketVerified:true};}}});
  const opts3={scope:{ownerId:'owner-a',purpose:'sms_receipt',entityId:source3}};
  await assert.rejects(()=>unknownProtocol.put(key3,'synthetic ciphertext',opts3),/storage_upload_outcome_unknown/);
  await assert.rejects(()=>unknownProtocol.put(key3,'synthetic ciphertext',opts3),/storage_upload_unsettled/);
  assert.equal(unknownUploads,1);
  // Pause after the last request/consent check, then commit a revocation
  // before the first Storage start. The actual journal and trigger must deny
  // the start, leaving both the provider call count and attempt count at zero.
  const source4='00000000-0000-4000-8000-000000000004',key4='sms/'+source4;
  await db.query(`INSERT INTO private.burimunsi_recovered_sms_holds VALUES($1,$2,'group-a','10000000-0000-4000-8000-000000000001','owner-a',$3,$4,$5)`,
   [source4,key4,body,time,fingerprint]);
  await db.query(`INSERT INTO private.burimunsi_observation_requests VALUES($1,'group-a','10000000-0000-4000-8000-000000000001','owner-a',
   '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,$2,$3,$4,$5,1)`,[source4,req,fingerprint,'c'.repeat(64),body]);
  await db.query("INSERT INTO private.collect_sms_witnesses VALUES($1,'owner-a','group-a',$2,$3,$4)",[key4,body,time,fingerprint]);
  await db.exec("SELECT set_config('fixture.generation','1',false)");
  assert.equal((await db.query('SELECT private.collect_sms_held_resume_check($1,$2,$3,$4,$5) AS ok',[source4,req,fingerprint,body,time])).rows[0].ok,true);
  await db.query('SELECT private.burimunsi_observation_actor(true)');
  await db.exec('UPDATE private.burimunsi_observation_consents SET enabled=false,generation=2');
  let deniedUploads=0;const beforeBinding=pinBindings;
  const scope4={ownerId:'owner-a',purpose:'sms_receipt',entityId:source4};
  const descriptor4={scope:scope4,aad:`sms:${source4}:${body}`,keyId:'synthetic',plaintextSha256:body,
   requestDigest:fingerprint,httpMetadata:{},customMetadata:{}};
  await assert.rejects(()=>journal.reservePayload(key4,descriptor4,'synthetic encrypted SMS',
   {bodySha256:body,collectionId:'group-a',inboxReceivedAt:time}),/sms_held_upload_authority_changed/);
  assert.equal((await db.query('SELECT count(*)::int n FROM private.storage_payload_reservations WHERE object_key=$1',[key4])).rows[0].n,0);
  const deniedProtocol=new ProtectedStorageProtocol({journal,transport:{async uploadImmutable(){deniedUploads++;return {status:200};}}});
  await assert.rejects(()=>deniedProtocol.put(key4,'synthetic ciphertext',
   {scope:scope4}),/sms_held_upload_authority_changed/);
  assert.equal(deniedUploads,0);
  assert.equal(pinBindings,beforeBinding+2);
  const denied=(await db.query('SELECT operation_id,attempts,active_attempt FROM private.storage_put_intents WHERE object_key=$1',[key4])).rows[0];
  assert.equal(denied.attempts,0);assert.equal(denied.active_attempt,null);
  assert.equal((await db.query('SELECT count(*)::int n FROM private.storage_upload_attempts WHERE operation_id=$1',[denied.operation_id])).rows[0].n,0);
  // A different request reserves ciphertext while consent is active. If
  // consent is then revoked before PUT start, the retained reservation is
  // untouched and the final start still makes zero provider calls.
  const source5='00000000-0000-4000-8000-000000000005',key5='sms/'+source5;
  await db.exec("UPDATE private.burimunsi_observation_consents SET enabled=true,generation=3;SELECT set_config('fixture.generation','3',false)");
  await db.query(`INSERT INTO private.burimunsi_recovered_sms_holds VALUES($1,$2,'group-a','10000000-0000-4000-8000-000000000001','owner-a',$3,$4,$5)`,
   [source5,key5,body,time,fingerprint]);
  await db.query(`INSERT INTO private.burimunsi_observation_requests VALUES($1,'group-a','10000000-0000-4000-8000-000000000001','owner-a',
   '20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',1,$2,$3,$4,$5,3)`,[source5,req,fingerprint,'c'.repeat(64),body]);
  const scope5={ownerId:'owner-a',purpose:'sms_receipt',entityId:source5};
  const descriptor5={scope:scope5,aad:`sms:${source5}:${body}`,keyId:'synthetic',plaintextSha256:body,
   requestDigest:fingerprint,httpMetadata:{},customMetadata:{}};
  await journal.reservePayload(key5,descriptor5,'synthetic encrypted SMS before revocation',
   {bodySha256:body,collectionId:'group-a',inboxReceivedAt:time});
  await db.exec('UPDATE private.burimunsi_observation_consents SET enabled=false,generation=4');
  let lateUploads=0;
  const lateProtocol=new ProtectedStorageProtocol({journal,transport:{async uploadImmutable(){lateUploads++;return {status:200};}}});
  await assert.rejects(()=>lateProtocol.put(key5,'synthetic ciphertext',{scope:scope5}),/sms_held_upload_authority_changed/);
  assert.equal(lateUploads,0);
  assert.equal((await db.query('SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key=$1',[key5])).rows[0].sealed_body,
   'synthetic encrypted SMS before revocation');
  assert.equal((await db.query('SELECT count(*)::int n FROM private.storage_upload_attempts a JOIN private.storage_put_intents i ON i.operation_id=a.operation_id WHERE i.object_key=$1',[key5])).rows[0].n,0);
  // A start that committed before revocation is already in flight. Its
  // outcome must still be journaled after revocation, without granting any
  // new attempt or asserting that the provider call can be recalled.
  await db.exec("UPDATE private.storage_upload_attempts SET outcome='upload_accepted',completed_at=clock_timestamp() WHERE id='00000000-0000-4000-8000-000000000010'");
  await db.exec("UPDATE private.storage_put_intents SET last_outcome='upload_accepted' WHERE operation_id='operation'");
  assert.equal((await db.query("SELECT outcome FROM private.storage_upload_attempts WHERE operation_id='operation'")).rows[0].outcome,'upload_accepted');
 }finally{await db.close();}
});
