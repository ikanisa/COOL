import {loadReviewedPlatformFixture} from '../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import {initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest} from './helpers/fenced-unit.js';
import assert from 'node:assert/strict';
import {connection,PostgresDatabase,compileSql} from './helpers/fenced-postgres.js';
import {digest,stableJson} from '../domain/core.js';
import {inventoryPrivateRetention,privateRetentionCatalogIdentity,privateRetentionGuards,assertPrivateRetentionPolicy,assertPrivateRetentionSource,privateRetentionAfterAccess,privateCopyRetainable,privateErasureObjects} from './helpers/module-private-retention.js';
import {retentionSchema,retentionSnapshot,retentionApprovalScope,snapshotCompareGuards} from './helpers/module-domain-privacy_retention_catalog.js';
import {loadRetentionPolicy,actorGuard} from './helpers/module-domain-privacy_retention_policy.js';
import {retentionObjectSendStart} from './helpers/module-domain-privacy_retention_tasks.js';
import {ProtectedStorageProtocol} from '../storage/protocol.js';
import {SupabaseObjectBucket} from './helpers/module-adapters.js';
import {planRetention,claimRetentionTask,executeRetentionTask} from './helpers/module-domain-privacy_retention.js';
import {fixtureAdminAccount,establishRecentAdminEmail,adminEmailFixtureDatabase,bindFixtureAdminActor} from './helpers/admin-email-fixture.js';

// The inspector intentionally returns dynamic class names. This fixture
// describes only the mutable fields exercised below; cloning retains the
// complete inspected value and all runtime source assertions still execute.
interface MutablePrivateCopyFixture {
 count:number;
 rows:Array<{lifecycle?:{sealed?:boolean;cleared?:boolean}}>;
}
interface PrivateInventoryFixture {
 classes:Record<string,MutablePrivateCopyFixture>;
}

const database=Deno.env.get('COLLECT_PRIVATE_RETENTION_TEST_DATABASE_URL');
const code=(value:string)=>(error:any)=>typeof error?.code==='string'&&error.code.includes(value);
fencedTest({name:'private retention on real isolated PostgreSQL: actual scoped mirrors, policy and commit fences',ignore:!database,sanitizeOps:false,sanitizeResources:false,fn:async t=>{
 const url=new URL(database!);assert(['localhost','127.0.0.1'].includes(url.hostname)&&url.pathname==='/collect_private_retention_test'&&(url.port==='55439'||Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'),'Only this owned synthetic loopback database may be initialized.');
 const adminUrl=new URL(url);adminUrl.pathname='/postgres';const admin=connection(adminUrl.href);
 if(!(await admin`SELECT 1 FROM pg_database WHERE datname='collect_private_retention_test'`).length)await admin.unsafe('CREATE DATABASE collect_private_retention_test');
 await admin.end();
 const sql=connection(database!);await initializeSqlFixture(sql);const setup=await sql.reserve();
 const actor='d1000000-0000-4000-8000-000000000001',subject='d1000000-0000-4000-8000-000000000002',other='d1000000-0000-4000-8000-000000000003';
 const authActor='d2000000-0000-4000-8000-000000000001',authSubject='d2000000-0000-4000-8000-000000000002',authOther='d2000000-0000-4000-8000-000000000003',session='d3000000-0000-4000-8000-000000000001',factor='d4000000-0000-4000-8000-000000000001';
 const claims={sub:authActor,session_id:session,role:'authenticated',aal:'aal2',amr:[{method:'totp',timestamp:Math.floor(Date.now()/1000)}]};
 const key='synthetic/private-retention/source',body=new TextEncoder().encode('Synthetic retained source'),sha=await digest(body),scope={ownerId:subject,entityId:'synthetic-upload',purpose:'generic_upload'};
 try{
  // This test owns only its explicitly named synthetic database; no other
  // local database, provider or hosted schema is read or changed.
  await setup.unsafe('DROP SCHEMA IF EXISTS api,app,private,auth,storage,realtime CASCADE');
  await setup.unsafe(await Deno.readTextFile(new URL('../../../tests/sql/00_local_auth_fixture.sql',import.meta.url)));
  await setup.unsafe("DO $$BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN;END IF;END$$");
  await setup.unsafe(`ALTER TABLE auth.users ADD COLUMN encrypted_password text;ALTER TABLE auth.mfa_factors ADD COLUMN secret text;
   CREATE TABLE auth.refresh_tokens(id bigint PRIMARY KEY,user_id text,session_id uuid,token text);
   CREATE TABLE auth.identities(id uuid PRIMARY KEY,user_id uuid,identity_data jsonb);
   CREATE TABLE auth.mfa_recovery_code_sets(id uuid PRIMARY KEY,user_id uuid,mfa_factor_id uuid);
   CREATE TABLE auth.mfa_recovery_codes(id uuid PRIMARY KEY,mfa_recovery_code_set_id uuid,code_hash text);
   CREATE TABLE auth.webauthn_credentials(id uuid PRIMARY KEY,user_id uuid,credential_id bytea,public_key bytea);
   CREATE TABLE auth.audit_log_entries(id uuid PRIMARY KEY,payload json);
   CREATE TABLE auth.flow_state(id uuid PRIMARY KEY,user_id uuid,linking_target_id uuid,oauth_client_state_id uuid,provider_access_token text);
   CREATE TABLE auth.mfa_challenges(id uuid PRIMARY KEY,factor_id uuid,otp_code text);
   CREATE TABLE auth.oauth_client_states(id uuid PRIMARY KEY,code_verifier text);
   CREATE TABLE auth.oauth_authorizations(id uuid PRIMARY KEY,user_id uuid,authorization_code text);
   CREATE TABLE auth.oauth_consents(id uuid PRIMARY KEY,user_id uuid,scopes text);
   CREATE TABLE auth.one_time_tokens(id uuid PRIMARY KEY,user_id uuid,token_hash text);
   CREATE TABLE auth.saml_relay_states(id uuid PRIMARY KEY,flow_state_id uuid,for_email text);
   CREATE TABLE auth.scim_users(id uuid PRIMARY KEY,user_id uuid,resource jsonb);
   CREATE TABLE auth.webauthn_challenges(id uuid PRIMARY KEY,user_id uuid,session_data jsonb);
   CREATE SCHEMA storage;CREATE TABLE storage.buckets(id text PRIMARY KEY,name text,public boolean);
   CREATE TABLE storage.objects(id uuid PRIMARY KEY,bucket_id text,name text,owner_id text,metadata jsonb,archived_at timestamptz,is_delete_marker boolean);
   CREATE TABLE storage.s3_multipart_uploads(id text PRIMARY KEY,bucket_id text,key text,owner_id text,upload_signature text);
   CREATE TABLE storage.s3_multipart_uploads_parts(id uuid PRIMARY KEY,bucket_id text,key text,owner_id text,upload_id text,etag text);`);
  const reviewedPlatform=await loadReviewedPlatformFixture(new URL('../../../../',import.meta.url));await reviewedPlatform.apply(text=>setup.unsafe(text));
 }finally{setup.release();await initializeSqlFixture(sql);}
 const stamp=new Date().toISOString();
 for(const [principal,authId,email,publicId]of[[actor,authActor,'info@ikanisa.com','910001'],[subject,authSubject,'subject@example.test','910002'],[other,authOther,'other@example.test','910003']]){
  await sql`INSERT INTO auth.users(id,email,encrypted_password)VALUES(${authId},${email},'SYNTHETIC_PASSWORD_DO_NOT_EXPOSE')`;
  await sql`INSERT INTO app.users(id,email,public_id,full_name,created_at,updated_at)VALUES(${principal},${email},${publicId},'Synthetic retention fixture',${stamp},${stamp})`;
  await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${authId},${principal},'synthetic-local-fixture')`;
 }
 await sql`INSERT INTO auth.sessions(id,user_id,aal,factor_id)VALUES(${session},${authActor},'aal2',${factor}),('d3000000-0000-4000-8000-000000000002',${authSubject},'aal1',NULL),('d3000000-0000-4000-8000-000000000003',${authOther},'aal1',NULL)`;
 await sql`INSERT INTO auth.mfa_factors(id,user_id,status,secret)VALUES(${factor},${authActor},'verified','SYNTHETIC_TOTP_SECRET'),('d4000000-0000-4000-8000-000000000002',${authSubject},'verified','SYNTHETIC_SUBJECT_TOTP_SECRET')`;
 await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method)VALUES(${session},'totp')`;
 await sql`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES(${session},${actor},'admin',app.unixepoch(),app.unixepoch(),app.unixepoch()+3600)`;
 await sql`INSERT INTO app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter)VALUES(${factor},${actor},'Synthetic','{"managed_by":"supabase"}','verified',app.unixepoch(),${session},app.unixepoch(),0)`;
 await sql.begin(async(tx:any)=>{await tx`SELECT set_config('request.jwt.claims',${JSON.stringify(claims)},true)`;const proof=await tx`SELECT private.record_mfa_projection(${factor}::uuid) AS at`;await tx`UPDATE app.auth_sessions SET assurance_level=2,mfa_factor_id=${factor},mfa_at=${proof[0].at} WHERE id=${session}`;});
 await sql`INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at)VALUES('d5000000-0000-4000-8000-000000000001','info@ikanisa.com','owner','active','!managed-supabase!','Synthetic Owner',app.unixepoch(),app.unixepoch())`;
 await sql`INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)VALUES('d5000000-0000-4000-8000-000000000001',${actor},'synthetic-fixture',${stamp})`;
 await sql`INSERT INTO auth.refresh_tokens(id,user_id,session_id,token)VALUES(1,${authSubject},'d3000000-0000-4000-8000-000000000002','SYNTHETIC_REFRESH_TOKEN'),(2,${authOther},'d3000000-0000-4000-8000-000000000003','SYNTHETIC_OTHER_TOKEN')`;
 await sql`INSERT INTO auth.identities(id,user_id,identity_data)VALUES('d6000000-0000-4000-8000-000000000002',${authSubject},'"SYNTHETIC_PROVIDER_IDENTITY"')`;
 await sql`INSERT INTO auth.mfa_recovery_code_sets(id,user_id,mfa_factor_id)VALUES('d7000000-0000-4000-8000-000000000002',${authSubject},'d4000000-0000-4000-8000-000000000002')`;
 await sql`INSERT INTO auth.mfa_recovery_codes(id,mfa_recovery_code_set_id,code_hash)VALUES('d8000000-0000-4000-8000-000000000002','d7000000-0000-4000-8000-000000000002','SYNTHETIC_RECOVERY_CODE')`;
 await sql`INSERT INTO auth.webauthn_credentials(id,user_id,credential_id,public_key)VALUES('d9000000-0000-4000-8000-000000000002',${authSubject},decode('abcd','hex'),decode('1234','hex'))`;
 await sql`INSERT INTO auth.audit_log_entries(id,payload)VALUES('d0100000-0000-4000-8000-000000000002',${sql.json({actor_id:authSubject,test:'SYNTHETIC_AUTH_AUDIT'})})`;
 await sql`INSERT INTO auth.flow_state(id,user_id,linking_target_id,oauth_client_state_id,provider_access_token)VALUES('d0200000-0000-4000-8000-000000000002',${authSubject},NULL,'d0300000-0000-4000-8000-000000000002','SYNTHETIC_GOOGLE_TOKEN')`;
 await sql`INSERT INTO auth.oauth_client_states(id,code_verifier)VALUES('d0300000-0000-4000-8000-000000000002','SYNTHETIC_PKCE_VERIFIER')`;
 await sql`INSERT INTO auth.mfa_challenges(id,factor_id,otp_code)VALUES('d0400000-0000-4000-8000-000000000002','d4000000-0000-4000-8000-000000000002','SYNTHETIC_FACTOR_CHALLENGE')`;
 await sql`INSERT INTO auth.saml_relay_states(id,flow_state_id,for_email)VALUES('d0500000-0000-4000-8000-000000000002','d0200000-0000-4000-8000-000000000002','subject@example.test')`;
 for(const name of['oauth_authorizations','oauth_consents','one_time_tokens','scim_users','webauthn_challenges'])await sql.unsafe('INSERT INTO auth.'+name+'(id,user_id)VALUES($1,$2)',[crypto.randomUUID(),authSubject]);
 await sql`INSERT INTO private.storage_namespace(singleton,origin,bucket)VALUES(true,'https://synthetic-storage.example','collect-evidence')`;
 await sql`INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)VALUES(${key},${'b'.repeat(64)},${sql.json(scope)},'synthetic-aad','test',${sha},'SYNTHETIC_SEALED_BODY')`;
 await sql`INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)VALUES('synthetic-retention-put',${key},${'c'.repeat(64)},${sha},${body.length},${sql.json(scope)},'{}',${sql.json({sha256:sha,source_fingerprint:'b'.repeat(64)})},'committed')`;
 await sql`INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)SELECT object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata FROM private.storage_put_intents WHERE object_key=${key}`;
 await sql`INSERT INTO app.upload_objects(id,user_id,object_key,sha256,size_bytes,content_type,purpose,created_at)VALUES('synthetic-upload',${subject},${key},${sha},${body.length},'text/plain','synthetic',${stamp})`;
 await sql`INSERT INTO storage.buckets(id,name,public)VALUES('collect-evidence','collect-evidence',false)`;
 await sql`INSERT INTO storage.objects(id,bucket_id,name,owner_id,metadata,archived_at,is_delete_marker)VALUES('da000000-0000-4000-8000-000000000001','collect-evidence',${key},${authSubject},'{"test":"SYNTHETIC_OBJECT_METADATA"}',NULL,false),('da000000-0000-4000-8000-000000000002','collect-evidence',${key},${authSubject},'{"test":"SYNTHETIC_ARCHIVED_METADATA"}',now(),false),('da000000-0000-4000-8000-000000000003','collect-evidence','synthetic/other-user',${authOther},'{}',NULL,false)`;
 await sql`INSERT INTO storage.s3_multipart_uploads(id,bucket_id,key,owner_id,upload_signature)VALUES('synthetic-multipart','collect-evidence',${key},${authSubject},'SYNTHETIC_MULTIPART_SIGNATURE')`;
 await sql`INSERT INTO storage.s3_multipart_uploads_parts(id,bucket_id,key,owner_id,upload_id,etag)VALUES('da000000-0000-4000-8000-000000000004','collect-evidence',${key},${authSubject},'synthetic-multipart','SYNTHETIC_PART_ETAG')`;
 await sql`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,consumed_at,delivery_status)VALUES('synthetic-retention-otp',${'d'.repeat(64)},'email','subject@example.test','member',0,app.unixepoch()-600,app.unixepoch()-300,app.unixepoch()-400,'accepted')`;
  // A real helper-created retained phone proof is also a private personal copy.
  // The inspector receives its opaque descriptor, never the phone/challenge.
  await sql`UPDATE auth.users SET phone='250788123456',phone_confirmed_at=now()-interval '1 minute' WHERE id=${authSubject}`;
  await sql`UPDATE app.users SET phone='+250788123456' WHERE id=${subject}`;
  await sql`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES('d3000000-0000-4000-8000-000000000002',${subject},'member',app.unixepoch()-10,app.unixepoch()-10,app.unixepoch()+3500)`;
  await sql`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,consumed_at,delivery_status)VALUES('df100000-0000-4000-8000-000000000002',${'f'.repeat(64)},'phone','+250788123456','member',0,app.unixepoch()-300,app.unixepoch()+300,app.unixepoch()-1,'accepted')`;
  const phoneClaims={sub:authSubject,session_id:'d3000000-0000-4000-8000-000000000002',role:'authenticated',aal:'aal1',amr:[{method:'otp',timestamp:Math.floor(Date.now()/1000)-1}]};
  await new PostgresDatabase(sql,phoneClaims).prepare('SELECT private.record_managed_phone_verification(?)').bind('df100000-0000-4000-8000-000000000002').first();
 const emailHash=await digest('synthetic-retention-owner-cookie'),emailPublic=crypto.randomUUID(),emailOrigin='https://retention-admin.example';
 await sql`INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)SELECT ${emailHash},${emailPublic},a.id,a.auth_version,s.id,${emailOrigin},s.auth_at,s.expires_at FROM app.admin_users a CROSS JOIN app.auth_sessions s WHERE a.id='d5000000-0000-4000-8000-000000000001' AND s.id=${session}`;
 await sql`INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)VALUES(${emailHash},${authActor},${session},'{}')`;
 const emailDb=new PostgresDatabase(sql,claims),emailAccount=await fixtureAdminAccount(sql,emailDb,['d5000000-0000-4000-8000-000000000001',emailHash,emailOrigin,emailPublic]);await establishRecentAdminEmail(sql,emailDb,emailAccount);
 const env:any={DB:adminEmailFixtureDatabase(emailDb,emailAccount),ADMIN_ACCOUNT:emailAccount,BUILD_SOURCE_ID:'e'.repeat(64),APP_ENVIRONMENT:'test',PRIVATE_MEDIA:{async get(k:string){assert.equal(k,key);return{size:body.length,version:'synthetic-version',etag:'synthetic-etag',arrayBuffer:async()=>body.buffer};},async head(){throw Error('No effect probe expected');}}};
 let original:any,snapshot:any;
 await t.step('Admin email provenance is retained for its exact principal and contains no raw identity in inventory',async()=>{
  const copies:any=await inventoryPrivateRetention(env,actor);
  assert.equal(copies.classes['private:admin_email_operations'].count,1);assert.equal(copies.classes['private:admin_sensitive_email_proofs'].count,1);
  assert.equal(copies.classes['private:admin_email_operations'].rows[0].lifecycle.unresolved,false);
  assert.equal(copies.classes['private:admin_sensitive_email_proofs'].rows[0].lifecycle.immutable,true);
  const encoded=JSON.stringify(copies);for(const marker of['info@ikanisa.com',emailHash,emailPublic,session,authActor])assert(!encoded.includes(marker));
 });
 await t.step('untrusted roles have neither helper execution nor direct Auth access',async()=>{
  for(const role of['anon','authenticated','service_role']){assert.equal((await sql`SELECT has_function_privilege(${role},'private.retention_managed_inventory(text)','EXECUTE') AS ok`)[0].ok,false);await assert.rejects(()=>sql.begin(async(tx:any)=>{await tx.unsafe('SET LOCAL ROLE '+role);await tx`SELECT private.retention_managed_inventory(${subject})`;}),/permission denied/);}
  await assert.rejects(()=>new PostgresDatabase(sql,{}).prepare('SELECT private.retention_managed_inventory(?)').bind(subject).first(),/session_changed/);
  assert.equal((await sql`SELECT has_table_privilege('collect_runtime','auth.users','SELECT') AS ok`)[0].ok,false);
 });
 await t.step('actual scoped Auth, MFA recovery, WebAuthn and Storage mirrors return only opaque descriptors',async()=>{
  original=await inventoryPrivateRetention(env,subject);assert(original.classes['managed:auth'].count>=17);assert.equal(original.classes['private:managed_phone_verifications'].count,1);assert.equal(original.classes['managed:storage'].count,4);assert.equal(original.classes['managed:storage'].rows[0].lifecycle.catalog_rows,4);assert.equal(original.in_flight_unresolved,false);assert.equal(original.classes['managed:realtime_messages'].status,'observed');assert.equal(original.classes['managed:realtime_messages'].count,0);assert.equal(original.classes['private:member_realtime_control'].status,'unmapped');
  const encoded=JSON.stringify(original);for(const marker of['SYNTHETIC_REFRESH_TOKEN','SYNTHETIC_SUBJECT_TOTP_SECRET','SYNTHETIC_RECOVERY_CODE','subject@example.test','+250788123456','df100000-0000-4000-8000-000000000002','SYNTHETIC_SEALED_BODY','SYNTHETIC_OBJECT_METADATA','SYNTHETIC_GOOGLE_TOKEN','SYNTHETIC_PKCE_VERIFIER','SYNTHETIC_FACTOR_CHALLENGE','SYNTHETIC_MULTIPART_SIGNATURE'])assert(!encoded.includes(marker));
  const missing:any=await inventoryPrivateRetention(env,'unmapped-synthetic-subject');assert.equal(missing.classes['managed:auth'].status,'unmapped');assert.equal(missing.classes['managed:auth'].count,0);assert.equal(missing.classes['managed:storage'].count,0);assert.equal(missing.external_copy_disposition,'blocked');assert.equal(missing.classes['managed:realtime_messages'].status,'unavailable');
 });
 await t.step('unrelated user rows do not affect the scoped observation',async()=>{
  await sql`UPDATE auth.users SET encrypted_password='CHANGED_OTHER_USER_ONLY' WHERE id=${authOther}`;assert.deepEqual(await inventoryPrivateRetention(env,subject),original);
 });
 await t.step('managed rows and archived versions are bounded without truncated success',async()=>{
  await sql`INSERT INTO auth.refresh_tokens(id,user_id,session_id,token)SELECT 100+n,${authSubject},'d3000000-0000-4000-8000-000000000002','SYNTHETIC_LIMIT' FROM generate_series(1,501)n`;
  try{await assert.rejects(()=>inventoryPrivateRetention(env,subject),/retention_managed_inventory_limit/);}finally{await sql`DELETE FROM auth.refresh_tokens WHERE id>100`;}
  await sql`INSERT INTO storage.objects(id,bucket_id,name,owner_id,metadata)SELECT md5('synthetic-limit-'||n)::uuid,'collect-evidence',${key},${authSubject},'{"bulk":"synthetic-retention-limit"}' FROM generate_series(1,501)n`;
  try{await assert.rejects(()=>inventoryPrivateRetention(env,subject),/retention_managed_inventory_limit/);}finally{await sql`DELETE FROM storage.objects WHERE metadata->>'bulk'='synthetic-retention-limit'`;}
  await sql`UPDATE storage.buckets SET public=true WHERE id='collect-evidence'`;assert.equal((await inventoryPrivateRetention(env,subject) as any).classes['managed:storage'].status,'unavailable');await sql`UPDATE storage.buckets SET public=false WHERE id='collect-evidence'`;
 });
 await t.step('new unknown managed/private copy relations fail closed',async()=>{
  await sql.unsafe('CREATE TABLE auth.unknown_personal_copy(id uuid)');try{await assert.rejects(()=>inventoryPrivateRetention(env,subject),/retention_unknown_managed_relation/);}finally{await sql.unsafe('DROP TABLE auth.unknown_personal_copy');}
  await sql.unsafe('CREATE TABLE private.unknown_personal_copy(id uuid)');try{await assert.rejects(()=>inventoryPrivateRetention(env,subject),code('privacy_retention_unknown_private_class'));}finally{await sql.unsafe('DROP TABLE private.unknown_personal_copy');}
 });
 await t.step('existing application inspection binds the new catalog, schema and copy hashes',async()=>{
  const schema=await retentionSchema(env);snapshot=await retentionSnapshot(env,subject);assert(schema.classes.includes('managed:auth'));assert(schema.classes.includes('private:storage_payload_reservations'));assert.deepEqual(snapshot.summary.private_inventory,original);assert.equal(snapshot.summary.schema_sha256,schema.sha256);
  assert.equal(schema.profile,'admin_email11');assert.equal(schema.columns.assisted_sms_claims.length,18);
  assert.deepEqual(schema.columns.assisted_sms_claims.slice(-2),['actor_email_proof_id','actor_email_verified_at']);
  for(const [className,relation]of [['private:admin_email_operations','admin_email_operations'],['private:admin_sensitive_email_proofs','admin_sensitive_email_proofs'],['private:collect_fence_source_upgrades','collect_fence_source_upgrades']]){
   assert(schema.classes.includes(className));assert(schema.privateInventory.private_schema.some((row:any)=>row.name===relation));
  }
  assert.equal(snapshot.summary.private_inventory.classes['private:collect_fence_source_upgrades'].status,'unmapped',
   'Opaque source lineage stays a blocked shared copy, never a subject-empty assertion');
 });
 await t.step('current email schema rejects unknown application tables and incomplete or reordered proof columns',async()=>{
  const before=await retentionSchema(env);
  await sql.unsafe('CREATE TABLE app.synthetic_uncovered_email_copy(id text)');
  try{await assert.rejects(()=>retentionSchema(env),code('privacy_retention_unknown_class'));}
  finally{await sql.unsafe('DROP TABLE app.synthetic_uncovered_email_copy');}
  await sql.unsafe('ALTER TABLE app.assisted_sms_claims RENAME COLUMN actor_email_proof_id TO synthetic_uncovered_email_proof');
  try{await assert.rejects(()=>retentionSchema(env),code('privacy_retention_schema_changed'));}
  finally{await sql.unsafe('ALTER TABLE app.assisted_sms_claims RENAME COLUMN synthetic_uncovered_email_proof TO actor_email_proof_id');}
  // Real local column renames change physical name order, not a mocked PRAGMA.
  await sql.unsafe('ALTER TABLE app.assisted_sms_claims RENAME COLUMN actor_email_proof_id TO synthetic_email_order_swap; ALTER TABLE app.assisted_sms_claims RENAME COLUMN actor_email_verified_at TO actor_email_proof_id; ALTER TABLE app.assisted_sms_claims RENAME COLUMN synthetic_email_order_swap TO actor_email_verified_at');
  try{await assert.rejects(()=>retentionSchema(env),code('privacy_retention_schema_changed'));}
  finally{await sql.unsafe('ALTER TABLE app.assisted_sms_claims RENAME COLUMN actor_email_verified_at TO synthetic_email_order_swap; ALTER TABLE app.assisted_sms_claims RENAME COLUMN actor_email_proof_id TO actor_email_verified_at; ALTER TABLE app.assisted_sms_claims RENAME COLUMN synthetic_email_order_swap TO actor_email_proof_id');}
  const recovered=await retentionSchema(env);assert.equal(recovered.profile,'admin_email11');assert.equal(recovered.sha256,before.sha256);
  assert.deepEqual(recovered.privateInventory,before.privateInventory);
 });
 const identity=await privateRetentionCatalogIdentity(env);
 const rules=Object.fromEntries((await retentionSchema(env)).classes.map((name:string)=>[name,{action:name==='access'?'blocked':name.startsWith('external:')||name.startsWith('private:collect_fence_')||name==='private:admin_email_operations'||name==='private:admin_sensitive_email_proofs'||name==='private:member_realtime_control'||name==='managed:realtime_messages'?'blocked':'retain',basis_reference:'synthetic-reviewed-test',deadline:new Date(Date.now()+3600000).toISOString()}]));
 const policy:any={contract_version:1,policy_id:'db000000-0000-4000-8000-000000000001',version:'synthetic-v1',environment:'test',synthetic_test_only:true,approval_evidence_sha256:'a'.repeat(64),approved_by:actor,approved_at:new Date(Date.now()-1000).toISOString(),expires_at:new Date(Date.now()+3600000).toISOString(),source_id:env.BUILD_SOURCE_ID,schema_sha256:snapshot.summary.schema_sha256,scope:{request_id:'dc000000-0000-4000-8000-000000000001',subject_id:subject,snapshot_sha256:'b'.repeat(64)},rules,writer_fence:{source_id:env.BUILD_SOURCE_ID,evidence_sha256:'c'.repeat(64),generic_upload_catalog_only:true,unknown_in_flight:false},external_inventory:{status:'unverified',evidence_sha256:'d'.repeat(64)},copy_inventory:{contract_version:1,catalog_sha256:identity.catalog_sha256,unmapped_copies:'blocked',bff_access_revocation:'block'}};
 await t.step('explicit approved policy is required; no blanket private or Auth erasure',async()=>{
  assertPrivateRetentionPolicy(policy,identity);assert.throws(()=>assertPrivateRetentionPolicy({...policy,copy_inventory:undefined},identity),code('private_policy_unapproved'));assert.throws(()=>assertPrivateRetentionPolicy({...policy,rules:{...rules,'managed:auth':{...rules['managed:auth'],action:'erase'}}},identity),code('private_disposition_unapproved'));
  for(const name of ['private:admin_email_operations','private:admin_sensitive_email_proofs'])assert.throws(()=>assertPrivateRetentionPolicy({...policy,rules:{...rules,[name]:{...rules[name],action:'retain'}}},identity),code('admin_email_unapproved'));
  assert.throws(()=>assertPrivateRetentionPolicy({...policy,rules:{...rules,'private:collect_fence_source_upgrades':{...rules['private:collect_fence_source_upgrades'],action:'retain'}}},identity),code('shared_fence_unapproved'));
  const raw=stableJson(policy),pinned=await digest(raw);await sql`INSERT INTO app.runtime_config(key,value_json,updated_at)VALUES('privacy:retention:approved:v1',${raw},${stamp})`;env.PRIVACY_RETENTION_APPROVAL_SHA256=pinned;assert.equal((await loadRetentionPolicy(env,pinned)).sha256,pinned);
  await assert.rejects(()=>loadRetentionPolicy(env,'f'.repeat(64)),code('policy_unavailable'));
 });
 const plan={id:'dd000000-0000-4000-8000-000000000001',subject_id:subject};
 await sql`INSERT INTO app.deletion_requests(id,user_id,submission_id,created_at,updated_at)VALUES('dc000000-0000-4000-8000-000000000001',${subject},'synthetic-private-retention',${stamp},${stamp})`;
 await sql`INSERT INTO app.privacy_retention_plans(id,operation_id,request_id,subject_id,actor_id,session_id,input_sha256,policy_sha256,policy_json,policy_config_revision,source_id,schema_sha256,scope_json,scope_sha256,ledger_sha256,review_revision,created_seconds)VALUES(${plan.id},'de000000-0000-4000-8000-000000000001','dc000000-0000-4000-8000-000000000001',${subject},${actor},${session},${'a'.repeat(64)},${'b'.repeat(64)},'{}',1,${env.BUILD_SOURCE_ID},${snapshot.summary.schema_sha256},'{}',${'c'.repeat(64)},${'d'.repeat(64)},0,app.unixepoch())`;
 await t.step('the effect transaction recomputes private/provider preimages',async()=>{
  const admission=await retentionSnapshot(env,subject);try{await env.DB.batch([...snapshotCompareGuards(env,plan,admission,'synthetic-full-source'),env.DB.prepare('DELETE FROM app.privacy_retention_guards WHERE plan_id=?').bind(plan.id)]);}catch(error:any){console.error('Full source guard failed:',error.collectSql);throw error;}
  const guards=privateRetentionGuards(env,plan,snapshot,'synthetic-private');try{await env.DB.batch([...guards,env.DB.prepare('DELETE FROM app.privacy_retention_guards WHERE plan_id=?').bind(plan.id)]);}catch(error:any){console.error('Opaque private guard failed:',error.collectSql);throw error;}
  await sql`UPDATE private.supabase_otp_challenges SET attempts=1 WHERE id='synthetic-retention-otp'`;
  await assert.rejects(()=>env.DB.batch(privateRetentionGuards(env,plan,snapshot,'synthetic-stale')),/check constraint/);assert.equal((await sql`SELECT count(*)::int AS n FROM app.privacy_retention_guards WHERE plan_id=${plan.id}`)[0].n,0);
  const changed=await inventoryPrivateRetention(env,subject);assert.throws(()=>assertPrivateRetentionSource(original,changed),code('private_scope_changed'));
 });
 await t.step('source/provider mirror changes cannot be mistaken for retained or erased copies',async()=>{
  assert.equal(privateCopyRetainable(original,'managed:storage'),true);assert.equal(privateCopyRetainable({classes:{'managed:storage':{status:'unavailable'}}},'managed:storage'),false);
  const changed=structuredClone(original);changed.classes['managed:auth'].rows[0].row_sha256='f'.repeat(64);assert.throws(()=>assertPrivateRetentionSource(original,changed),code('private_scope_changed'));
  const bff=structuredClone(original);bff.classes['private:bff_sessions']={status:'observed',count:1,sha256:'a'.repeat(64),rows:[{key_sha256:'b'.repeat(64),row_sha256:'c'.repeat(64)}]};await assert.rejects(()=>privateRetentionAfterAccess(bff,policy),code('bff_revocation_unapproved'));assert.equal((await privateRetentionAfterAccess(bff,{...policy,copy_inventory:{...policy.copy_inventory,bff_access_revocation:'allow'}})).classes['private:bff_sessions'].count,0);
  assert.equal((await sql`SELECT count(*)::int AS n FROM app.ledger_entries`)[0].n,0);
 });
 await t.step('an empty copy table schema change still invalidates commit admission',async()=>{
  const fresh=await retentionSnapshot(env,subject);await sql.unsafe('ALTER TABLE private.google_flow_context ADD COLUMN synthetic_extra_copy text');
  try{await assert.rejects(()=>env.DB.batch(privateRetentionGuards(env,plan,fresh,'synthetic-schema-drift')),/check constraint/);}finally{await sql.unsafe('ALTER TABLE private.google_flow_context DROP COLUMN synthetic_extra_copy');}
 });
 await t.step('only the exact owned generic candidate may progress its own journal while other copies remain fenced',async()=>{
  const fresh=await retentionSnapshot(env,subject),effect={erasureObjects:[{key,key_sha256:await digest(key)}]};
  await sql`UPDATE storage.objects SET metadata='{"synthetic":"candidate journal phase"}' WHERE id='da000000-0000-4000-8000-000000000001'`;
  await assert.rejects(()=>env.DB.batch(privateRetentionGuards(env,plan,fresh,'synthetic-unexcluded')),/check constraint/);
  await env.DB.batch([...privateRetentionGuards(env,plan,fresh,'synthetic-candidate',effect),env.DB.prepare('DELETE FROM app.privacy_retention_guards WHERE plan_id=?').bind(plan.id)]);
  assert.throws(()=>privateRetentionGuards(env,plan,fresh,'synthetic-unowned',{erasureObjects:[{key:'not-owned',key_sha256:'a'.repeat(64)}]}),code('private_effect_unapproved'));
  await assert.rejects(()=>env.DB.prepare('DELETE FROM private.storage_objects WHERE object_key=?').bind(key).run(),/storage_retention_admission_required/);
  await sql`UPDATE private.supabase_otp_challenges SET attempts=2 WHERE id='synthetic-retention-otp'`;
  await assert.rejects(()=>env.DB.batch(privateRetentionGuards(env,plan,fresh,'synthetic-unrelated',effect)),/check constraint/);
 });

 await t.step('resumed object admission retains the original expired effect and requires one current fenced send-start',async()=>{
  // This is a focused authority/journal fixture, not an approved erasure run.
  // It uses the already owned synthetic PostgreSQL database and never invokes
  // Storage HTTP or mutates financial rows. The original send-start is expired.
  const at=Math.floor(Date.now()/1000),planId=crypto.randomUUID(),taskId=crypto.randomUUID(),oldId=crypto.randomUUID(),currentId=crypto.randomUUID(),effectId=crypto.randomUUID();
  const approved={...policy,rules:{...policy.rules,access:{...policy.rules.access,action:'quarantine'},'r2:upload_objects':{...policy.rules['r2:upload_objects'],action:'erase',deadline:new Date(Date.now()-60000).toISOString()}}};
  const raw=stableJson(approved),policySha=await digest(raw);
  await sql`UPDATE app.runtime_config SET value_json=${raw} WHERE key='privacy:retention:approved:v1'`;
  const config=(await sql`SELECT revision FROM app.runtime_config WHERE key='privacy:retention:approved:v1'`)[0];
  await sql`INSERT INTO app.privacy_retention_plans(id,operation_id,request_id,subject_id,actor_id,session_id,input_sha256,policy_sha256,policy_json,policy_config_revision,source_id,schema_sha256,scope_json,scope_sha256,ledger_sha256,review_revision,created_seconds)VALUES(${planId},${crypto.randomUUID()},'dc000000-0000-4000-8000-000000000001',${subject},${actor},${session},${'a'.repeat(64)},${policySha},${raw},${config.revision},${env.BUILD_SOURCE_ID},${snapshot.summary.schema_sha256},'{}',${'c'.repeat(64)},${'d'.repeat(64)},0,${at})`;
  await sql`INSERT INTO app.privacy_retention_tasks(id,plan_id,class_name,action,expected_json,state,revision,fence,claim_id)VALUES(${taskId},${planId},'r2:upload_objects','erase','{}','claimed',2,2,${currentId})`;
  for(const[id,fence,start,end]of[[oldId,1,at-100,at-10],[currentId,2,at,at+120]])await sql`INSERT INTO app.privacy_retention_claims(id,operation_id,task_id,actor_id,session_id,input_sha256,expected_revision,fence,claimed_seconds,expires_seconds)VALUES(${id},${crypto.randomUUID()},${taskId},${actor},${session},${'a'.repeat(64)},${Number(fence)-1},${fence},${start},${end})`;
  await sql`INSERT INTO app.privacy_retention_effects(operation_id,task_id,claim_id,fence,source_sha256,object_key,object_version,started_seconds)VALUES(${effectId},${taskId},${oldId},1,${sha},${key},'synthetic-version',${at-99})`;
  await sql`INSERT INTO app.privacy_retention_barriers(subject_id,plan_id,source_id,policy_sha256,activated_seconds)VALUES(${subject},${planId},${env.BUILD_SOURCE_ID},${policySha},${at})`;
  const originalEffect=(await sql`SELECT to_jsonb(e) AS value FROM app.privacy_retention_effects e WHERE operation_id=${effectId}`)[0].value;
  const mfaAt=Number((await sql`SELECT mfa_at FROM app.auth_sessions WHERE id=${session}`)[0].mfa_at);
  const reviewer=bindFixtureAdminActor({userId:actor,sessionId:session,surface:'admin',assuranceLevel:2,permissions:new Set(['privacy.review']),authAt:mfaAt,mfaAt},emailAccount);
  const planValue={id:planId,source_id:env.BUILD_SOURCE_ID,policy_sha256:policySha},taskValue={id:taskId,class_name:'r2:upload_objects'},claimValue={id:currentId,fence:2};
  const effectValue={operation_id:effectId},objectValue={key,body_sha256:sha};
  const sourceGuard=()=>env.DB.prepare("INSERT INTO app.privacy_retention_guards(id,plan_id,class_name,passed)VALUES(?,?,'r2:upload_objects',1)").bind(crypto.randomUUID(),planId);
  const assertion=()=>env.DB.prepare('SELECT private.assert_storage_delete_authorized(?)').bind(key);
  async function admission(extra:any[]=[]){const guard=actorGuard(env,reviewer);return env.DB.batch([guard.insert,sourceGuard(),...extra,assertion(),env.DB.prepare('DELETE FROM app.privacy_retention_guards WHERE plan_id=?').bind(planId),guard.remove]);}
  await assert.rejects(()=>admission(),/storage_retention_admission_required/);
  const marker=await retentionObjectSendStart(env,planValue,taskValue,claimValue,effectValue,objectValue,'a'.repeat(64));
  await admission(marker);
  assert.equal((await sql`SELECT count(*)::int AS n FROM app.privacy_retention_outcomes WHERE task_id=${taskId}`)[0].n,1);
  const duplicate=await retentionObjectSendStart(env,planValue,taskValue,claimValue,effectValue,objectValue,'a'.repeat(64));
  await assert.rejects(()=>admission(duplicate),/check constraint/);
  assert.equal((await sql`SELECT count(*)::int AS n FROM app.privacy_retention_outcomes WHERE task_id=${taskId}`)[0].n,1);

  // Each negative scenario uses a rolled-back owner fixture mutation, then the
  // actual runtime role and current managed actor. A marker alone is no grant.
  async function probe(change:any,target=key,expected=/storage_retention_admission_required/){
   const rollback=new Error('synthetic_probe_rollback');
   try{await sql.begin(async(tx:any)=>{
    if(change)await change(tx);
    await assert.rejects(async()=>{
     await env.DB.context(tx);
     const g=actorGuard(env,reviewer);
     for(const s of[g.insert,sourceGuard()]){const q=compileSql(s.sql,s.values);await tx.unsafe(q.text,q.values);}
     await tx`SELECT private.assert_storage_delete_authorized(${target})`;
    },expected);
    throw rollback;
   });}catch(error){if(error!==rollback)throw error;}
  }
  await probe(null,'synthetic/other-user');
  await probe(async(tx:any)=>{
   // All retry lineage is otherwise coherent, but the plan subject is another
   // real fixture principal. It must not authorize this object's actual owner.
   const p=crypto.randomUUID(),task=crypto.randomUUID(),claim=crypto.randomUUID(),effect=crypto.randomUUID();
   await tx`UPDATE app.privacy_retention_tasks SET state='blocked' WHERE id=${taskId}`;
   await tx`INSERT INTO app.privacy_retention_plans(id,operation_id,request_id,subject_id,actor_id,session_id,input_sha256,policy_sha256,policy_json,policy_config_revision,source_id,schema_sha256,scope_json,scope_sha256,ledger_sha256,review_revision,created_seconds)SELECT ${p},${crypto.randomUUID()},request_id,${other},actor_id,session_id,input_sha256,policy_sha256,policy_json,policy_config_revision,source_id,schema_sha256,scope_json,scope_sha256,ledger_sha256,review_revision,${at} FROM app.privacy_retention_plans WHERE id=${planId}`;
   await tx`INSERT INTO app.privacy_retention_tasks(id,plan_id,class_name,action,expected_json,state,fence,claim_id)VALUES(${task},${p},'r2:upload_objects','erase','{}','claimed',1,${claim})`;
   await tx`INSERT INTO app.privacy_retention_claims(id,operation_id,task_id,actor_id,session_id,input_sha256,expected_revision,fence,claimed_seconds,expires_seconds)VALUES(${claim},${crypto.randomUUID()},${task},${actor},${session},${'a'.repeat(64)},0,1,${at},${at+120})`;
   await tx`INSERT INTO app.privacy_retention_effects(operation_id,task_id,claim_id,fence,source_sha256,object_key,object_version,started_seconds)VALUES(${effect},${task},${claim},1,${sha},${key},'synthetic-version',${at})`;
   await tx`INSERT INTO app.privacy_retention_barriers(subject_id,plan_id,source_id,policy_sha256,activated_seconds)VALUES(${other},${p},${env.BUILD_SOURCE_ID},${policySha},${at})`;
   await tx`INSERT INTO app.privacy_retention_guards(id,plan_id,class_name,passed)VALUES(${crypto.randomUUID()},${p},'r2:upload_objects',1)`;
   const invalid={contract_version:1,verified:false,disposition:'catalog_object_send_started',original_effect_operation_id:effect,object_key_sha256:await digest(key),source_sha256:sha,source_id:planValue.source_id,policy_sha256:policySha,erasure_completed:false,all_data_erased:false};
   await tx`INSERT INTO app.privacy_retention_outcomes(operation_id,task_id,claim_id,fence,input_sha256,outcome_json,observed_seconds)VALUES(${crypto.randomUUID()},${task},${claim},1,${'a'.repeat(64)},${stableJson(invalid)},${at})`;
  });
  await probe(async(tx:any)=>{await tx`INSERT INTO app.privacy_holds(id,user_id,category,reason_code,created_at)VALUES(${crypto.randomUUID()},${subject},'synthetic','fixture',${new Date().toISOString()})`;});
  await probe(async(tx:any)=>{await tx`DELETE FROM app.admin_grants WHERE user_id=${actor} AND permission='privacy.review'`;},key,/permission_denied/);
  await probe(async(tx:any)=>{await tx`UPDATE app.privacy_retention_tasks SET claim_id=NULL WHERE id=${taskId}`;});
  await probe(async(tx:any)=>{
   await tx`UPDATE app.privacy_retention_tasks SET claim_id=${oldId},fence=1 WHERE id=${taskId}`;
   const oldMarker={contract_version:1,verified:false,disposition:'catalog_object_send_started',original_effect_operation_id:effectId,object_key_sha256:await digest(key),source_sha256:sha,source_id:planValue.source_id,policy_sha256:policySha,erasure_completed:false,all_data_erased:false};
   await tx`INSERT INTO app.privacy_retention_outcomes(operation_id,task_id,claim_id,fence,input_sha256,outcome_json,observed_seconds)VALUES(${crypto.randomUUID()},${taskId},${oldId},1,${'a'.repeat(64)},${stableJson(oldMarker)},${at-99})`;
  });
  for(const wrong of['source','effect'])await probe(async(tx:any)=>{
   const next=crypto.randomUUID();
   await tx`INSERT INTO app.privacy_retention_claims(id,operation_id,task_id,actor_id,session_id,input_sha256,expected_revision,fence,claimed_seconds,expires_seconds)VALUES(${next},${crypto.randomUUID()},${taskId},${actor},${session},${'a'.repeat(64)},2,3,${at},${at+120})`;
   await tx`UPDATE app.privacy_retention_tasks SET claim_id=${next},fence=3 WHERE id=${taskId}`;
   const invalid={contract_version:1,verified:false,disposition:'catalog_object_send_started',original_effect_operation_id:wrong==='effect'?crypto.randomUUID():effectId,object_key_sha256:await digest(key),source_sha256:wrong==='source'?'f'.repeat(64):sha,source_id:planValue.source_id,policy_sha256:policySha,erasure_completed:false,all_data_erased:false};
   await tx`INSERT INTO app.privacy_retention_outcomes(operation_id,task_id,claim_id,fence,input_sha256,outcome_json,observed_seconds)VALUES(${crypto.randomUUID()},${taskId},${next},3,${'a'.repeat(64)},${stableJson(invalid)},${at})`;
  });
  assert.deepEqual((await sql`SELECT to_jsonb(e) AS value FROM app.privacy_retention_effects e WHERE operation_id=${effectId}`)[0].value,originalEffect);
  assert.equal((await sql`SELECT count(*)::int AS n FROM private.storage_objects WHERE object_key=${key}`)[0].n,1);
  assert.equal((await sql`SELECT count(*)::int AS n FROM app.ledger_entries`)[0].n,0);
 });


 await t.step('actual caller resumes a lost DELETE into the original PostgreSQL journal without another provider send',async()=>{
  // New synthetic subject/object, separate from the authority-only fixture's
  // immutable barrier above. Provider HTTP is never called: the local transport
  // models deletion plus a lost acknowledgement; real PG guards/journal run.
  const target=crypto.randomUUID(),managed=crypto.randomUUID(),upload=crypto.randomUUID(),request=crypto.randomUUID(),k='synthetic/full-recovery/'+upload;
  const bytes=new TextEncoder().encode('Synthetic full pending-delete recovery'),contentSha=await digest(bytes),date=new Date().toISOString(),objectScope={ownerId:target,entityId:upload,purpose:'generic_upload'};
  await sql`INSERT INTO auth.users(id,email)VALUES(${managed},'pending-recovery@example.test')`;
  await sql`INSERT INTO app.users(id,email,public_id,created_at,updated_at)VALUES(${target},'pending-recovery@example.test','910004',${date},${date})`;
  await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${managed},${target},'synthetic-local-recovery-fixture')`;
  await sql`INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)VALUES(${k},${'b'.repeat(64)},${sql.json(objectScope)},'synthetic-recovery-aad','test',${contentSha},'SYNTHETIC_RECOVERY_SEALED_BODY')`;
  await sql`INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)VALUES(${'put:'+upload},${k},${'c'.repeat(64)},${contentSha},${bytes.length},${sql.json(objectScope)},'{}','{}','committed')`;
  await sql`INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)SELECT object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata FROM private.storage_put_intents WHERE object_key=${k}`;
  await sql`INSERT INTO app.upload_objects(id,user_id,object_key,sha256,size_bytes,content_type,purpose,created_at)VALUES(${upload},${target},${k},${contentSha},${bytes.length},'text/plain','synthetic',${date})`;
  await sql`INSERT INTO storage.objects(id,bucket_id,name,owner_id,metadata)VALUES(${crypto.randomUUID()},'collect-evidence',${k},${managed},'{"test":"SYNTHETIC_PENDING_RECOVERY"}')`;
  await sql`INSERT INTO app.deletion_requests(id,user_id,submission_id,created_at,updated_at)VALUES(${request},${target},${request},${date},${date})`;
  const mfaAt=Number((await sql`SELECT mfa_at FROM app.auth_sessions WHERE id=${session}`)[0].mfa_at);
  const reviewer=bindFixtureAdminActor({userId:actor,sessionId:session,surface:'admin',assuranceLevel:2,permissions:new Set(['privacy.review']),authAt:mfaAt,mfaAt},emailAccount);
  const storageEnv:any={...env,SUPABASE_URL:'https://synthetic-storage.example',SUPABASE_SECRET_KEY:'sb_secret_synthetic_recovery_only',COLLECT_PRIVATE_BUCKET:'collect-evidence'};
  const bucket=new SupabaseObjectBucket(storageEnv);
  let present=true,failProbe=false,deletes=0;
  const transport={async probe(key:string){assert.equal(key,k);if(failProbe){failProbe=false;return{headStatus:503,getStatus:503,bucketVerified:false};}return present?{headStatus:200,getStatus:200,bytes:new Uint8Array(bytes),etag:'synthetic-recovery-v1',bucketVerified:true,absent:false}:{headStatus:404,getStatus:404,bucketVerified:true,absent:true};},async remove(key:string){assert.equal(key,k);deletes++;present=false;await sql`DELETE FROM storage.objects WHERE bucket_id='collect-evidence' AND name=${k}`;failProbe=true;throw Error('Synthetic DELETE acknowledgement lost');}};
  bucket.transport=transport as any;
  bucket.protocol=new ProtectedStorageProtocol({transport,journal:bucket.journal});
  const runEnv:any={...storageEnv,PRIVATE_MEDIA:bucket};
  const observed=await retentionSnapshot(runEnv,target),scopeSha=await retentionApprovalScope(observed);
  const rules=Object.fromEntries(observed.classes.map((name:string)=>[name,{action:name==='access'?'quarantine':name==='r2:upload_objects'?'erase':name.startsWith('external:')||name.startsWith('private:collect_fence_')||name==='private:admin_email_operations'||name==='private:admin_sensitive_email_proofs'||name==='private:member_realtime_control'||name==='managed:realtime_messages'?'blocked':'retain',basis_reference:'synthetic-recovery-test-only',deadline:new Date(Date.now()+(name==='r2:upload_objects'?-60000:3600000)).toISOString()}]));
  const approved={...policy,policy_id:crypto.randomUUID(),schema_sha256:observed.summary.schema_sha256,scope:{request_id:request,subject_id:target,snapshot_sha256:scopeSha},rules,approved_at:new Date(Date.now()-1000).toISOString(),expires_at:new Date(Date.now()+3600000).toISOString()};
  const raw=stableJson(approved);runEnv.PRIVACY_RETENTION_APPROVAL_SHA256=await digest(raw);
  await sql`UPDATE app.runtime_config SET value_json=${raw} WHERE key='privacy:retention:approved:v1'`;
  const p=await planRetention(runEnv,reviewer,{operation_id:crypto.randomUUID(),request_id:request,expected_review_revision:0,policy_sha256:runEnv.PRIVACY_RETENTION_APPROVAL_SHA256,expected_source_id:runEnv.BUILD_SOURCE_ID});
  async function claim(name:string,lease=120){const task=(await sql`SELECT * FROM app.privacy_retention_tasks WHERE plan_id=${p.plan_id} AND class_name=${name}`)[0];return claimRetentionTask(runEnv,reviewer,{operation_id:crypto.randomUUID(),plan_id:p.plan_id,task_id:task.id,expected_task_revision:Number(task.revision),lease_seconds:lease});}
  const quarantine=await claim('access');await executeRetentionTask(runEnv,reviewer,{operation_id:crypto.randomUUID(),claim_id:quarantine.claim_id,fence:quarantine.fence});
  // A real bounded lease is allowed to expire; immutable claims and the
  // process clock are never rewritten to manufacture recovery authority.
  const first=await claim('r2:upload_objects',20);
  await assert.rejects(()=>executeRetentionTask(runEnv,reviewer,{operation_id:crypto.randomUUID(),claim_id:first.claim_id,fence:first.fence}),(error:any)=>error.code==='storage_absence_unconfirmed');
  assert.equal(deletes,1);assert.equal(present,false);
  const effect=(await sql`SELECT to_jsonb(e) AS value FROM app.privacy_retention_effects e WHERE task_id=${first.task_id}`)[0].value;
  assert.equal((await sql`SELECT state FROM private.storage_delete_intents WHERE object_key=${k}`)[0].state,'pending');
  assert.equal((await sql`SELECT count(*)::int AS n FROM private.storage_objects WHERE object_key=${k}`)[0].n,1);
  await assert.rejects(()=>bucket.get(k),(error:any)=>error.code==='storage_object_not_retained');
  const pending=await bucket.observeRetention(k);assert.equal(pending.kind,'pending_erasure_absence');assert.equal(pending.object,null);
  const pendingSnapshot=await retentionSnapshot(runEnv,target),pendingObject=pendingSnapshot.summary.objects[0];assert.ok(pendingObject);assert.equal(pendingObject.present,false);assert.ok(pendingObject.pending_erasure);assert.equal(pendingObject.pending_erasure.absence_verified,true);
  // The pending witness authorizes only the known provider-mirror loss. It
  // cannot authorize removing protected metadata, source spool or another copy.
  const allowed=await privateErasureObjects(observed.summary,pendingSnapshot.summary,[effect]);
  assert.equal(allowed.length,1);assert.equal(allowed[0].pending,true);assert.equal(allowed[0].committed,false);
  assertPrivateRetentionSource(observed.summary.private_inventory,pendingSnapshot.summary.private_inventory,{approvedErasureObjects:allowed});
  for(const name of['private:storage_objects','private:object_metadata']){
   const damaged:PrivateInventoryFixture=structuredClone(pendingSnapshot.summary.private_inventory);damaged.classes[name].rows=[];damaged.classes[name].count=0;
   assert.throws(()=>assertPrivateRetentionSource(observed.summary.private_inventory,damaged,{approvedErasureObjects:allowed}),code('private_object_changed'));
  }
  const spool:PrivateInventoryFixture=structuredClone(pendingSnapshot.summary.private_inventory),spoolRow=spool.classes['private:storage_payload_reservations'].rows[0];assert.ok(spoolRow);assert.ok(spoolRow.lifecycle);spoolRow.lifecycle.sealed=false;spoolRow.lifecycle.cleared=true;
  assert.throws(()=>assertPrivateRetentionSource(observed.summary.private_inventory,spool,{approvedErasureObjects:allowed}),code('private_object_changed'));
  const wrongWitness=structuredClone(pendingSnapshot.summary),wrongPending=wrongWitness.objects[0].pending_erasure;assert.ok(wrongPending);wrongPending.operation_id+=':wrong';
  const wrongAllowed=await privateErasureObjects(observed.summary,wrongWitness,[effect]);assert.equal(wrongAllowed[0].pending,false);
  assert.throws(()=>assertPrivateRetentionSource(observed.summary.private_inventory,wrongWitness.private_inventory,{approvedErasureObjects:wrongAllowed}),code('private_object_changed'));
  const getDelete=bucket.journal.getDeleteByKey.bind(bucket.journal),actualDelete=await getDelete(k);
  assert.ok(actualDelete);assert.equal(actualDelete.operationId,'retention:'+first.task_id+':'+upload);
  assert.equal((await sql`SELECT count(*)::int AS n FROM private.storage_delete_intents WHERE object_key=${k}`)[0].n,1);
  assert.equal((await sql`SELECT count(*)::int AS n FROM app.privacy_retention_effects WHERE task_id=${first.task_id}`)[0].n,1);
  for(const delta of[{state:'committed'},{key:'synthetic/wrong-object'},{expectedSha256:'f'.repeat(64)},{scope:{...objectScope,ownerId:other}},{fingerprint:'f'.repeat(64)}]){
   bucket.journal.getDeleteByKey=async()=>({...actualDelete,...delta});
   await assert.rejects(()=>bucket.observeRetention(k),(error:any)=>error.code==='storage_pending_erasure_identity_unavailable');
  }
  bucket.journal.getDeleteByKey=async()=>null;await assert.rejects(()=>bucket.observeRetention(k),(error:any)=>error.code==='storage_pending_erasure_identity_unavailable');
  bucket.journal.getDeleteByKey=getDelete;
  failProbe=true;await assert.rejects(()=>bucket.observeRetention(k),(error:any)=>error.code==='storage_probe_inconclusive');
  await assert.rejects(()=>executeRetentionTask(runEnv,reviewer,{operation_id:crypto.randomUUID(),claim_id:first.claim_id,fence:first.fence}),(error:any)=>['privacy_retention_effect_outcome_unknown','privacy_retention_claim_stale'].includes(error.code));
  assert.equal(deletes,1);
  await new Promise(resolve=>setTimeout(resolve,Math.max(0,first.expires_seconds*1000-Date.now()+50)));
  const renewed=await claim('r2:upload_objects');
  const result=await executeRetentionTask(runEnv,reviewer,{operation_id:crypto.randomUUID(),claim_id:renewed.claim_id,fence:renewed.fence});
  assert.equal(result.verified,true);assert.equal(result.disposition,'catalog_object_absence_verified');assert.equal(result.erasure_completed,false);assert.equal(result.all_data_erased,false);
  assert.equal(deletes,1,'Pending absence reconciliation never sends another DELETE');
  const finalDeletes=await sql`SELECT operation_id,state FROM private.storage_delete_intents WHERE object_key=${k}`;assert.equal(finalDeletes.length,1);assert.equal(finalDeletes[0].operation_id,actualDelete.operationId);assert.equal(finalDeletes[0].state,'committed');
  assert.equal((await sql`SELECT count(*)::int AS n FROM app.privacy_retention_effects WHERE task_id=${first.task_id}`)[0].n,1);
  assert.equal((await sql`SELECT count(*)::int AS n FROM private.storage_objects WHERE object_key=${k}`)[0].n,0);
  assert.equal((await sql`SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key=${k}`)[0].sealed_body,null);
  assert.deepEqual((await sql`SELECT to_jsonb(e) AS value FROM app.privacy_retention_effects e WHERE task_id=${first.task_id}`)[0].value,effect);
  assert.equal(await bucket.get(k),null);
  assert.equal((await sql`SELECT count(*)::int AS n FROM app.ledger_entries`)[0].n,0);
 });

 await finishSqlFixtureWork();await sql.end();
}});


fencedTest('a current erasure marker never turns unknown DELETE or HEAD/GET into completion',async t=>{
 const body=new TextEncoder().encode('synthetic object'),expected=await digest(body),present={headStatus:200,getStatus:200,bytes:body,bucketVerified:true,absent:false};
 for(const mode of['delete_unknown','head_unavailable','contradictory_absence','bucket_unverified'])await t.step(mode,async()=>{
  let commits=0,removes=0,probes=0;
  const transport={async probe(){probes++;if(mode==='head_unavailable')return{headStatus:503,getStatus:503};if(probes===1)return present;if(mode==='contradictory_absence')return{absent:true,headStatus:404,getStatus:200,bucketVerified:true};if(mode==='bucket_unverified')return{absent:true,headStatus:404,getStatus:404,bucketVerified:false};return present;},async remove(){removes++;if(mode==='delete_unknown')throw Error('synthetic acknowledgement unknown');return{status:200};}};
  const journal={async beginDelete(intent:any){return{...intent,state:'pending'};},async recordDeleteOutcome(){},async commitDelete(){commits++;},async getDeleteStatus(){return null;}};
  const protocol=new ProtectedStorageProtocol({transport,journal});
  await assert.rejects(()=>protocol.delete('synthetic/unknown',{operationId:'retention:synthetic:unknown',scope:{ownerId:'synthetic-owner',entityId:'synthetic-object',purpose:'generic_upload'},expectedSha256:expected,authorize:async()=>true}),/delete_object_identity_changed|storage_absence_unconfirmed/);
  assert.equal(commits,0);assert.equal(removes,mode==='head_unavailable'?0:1);
 });
});


fencedTest('reconciliation-only protocol refuses present, failed or contradictory observations without DELETE',async t=>{
 const bytes=new TextEncoder().encode('synthetic recovery guard'),sha=await digest(bytes);
 for(const observation of[{headStatus:200,getStatus:200,bytes,bucketVerified:true,absent:false},{headStatus:503,getStatus:503},{absent:true,headStatus:404,getStatus:404,bucketVerified:false},{absent:true,headStatus:404,getStatus:200,bucketVerified:true}])await t.step(JSON.stringify({head:observation.headStatus,get:observation.getStatus,bucket:observation.bucketVerified}),async()=>{
  let removes=0,commits=0;
  const protocol=new ProtectedStorageProtocol({transport:{async probe(){return observation;},async remove(){removes++;return{status:200};}},journal:{async beginDelete(intent:any){return{...intent,state:'pending'};},async commitDelete(){commits++;},async recordDeleteOutcome(){}}});
  await assert.rejects(()=>protocol.delete('synthetic/reconcile-only',{operationId:'retention:synthetic:reconcile-only',scope:{ownerId:'synthetic-owner',entityId:'synthetic-object',purpose:'generic_upload'},expectedSha256:sha,authorize:async()=>true,requireAbsent:true}),(error:any)=>error.code==='storage_absence_unconfirmed');
  assert.equal(removes,0);assert.equal(commits,0);
 });
});
