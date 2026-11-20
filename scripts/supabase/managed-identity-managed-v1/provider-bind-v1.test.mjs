// Synthetic, socket-only PG17: no provider client, real accounts or production
// database. The tested SQL is capable of real execution if separately approved;
// the only runner here connects to a newly owned local fixture.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {BIN,verifyEnvironment,verifyBinaryPins} from '../managed-identity-provider-compat/fixture-safety.mjs';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
import {compileManagedBinderV1,preparePreimageV1,assessAcknowledgement,executeManaged,ORIGINAL_SHA256,PROJECT_REF,SCHEDULER_SHA256,TRUST} from './provider-bind-v1.mjs';
const {Client}=pg,hash=s=>createHash('sha256').update(s).digest('hex');
const [base,fence,archive,identity,preimageQuery,routineReadback,bindingReadback]=await Promise.all([
 readFile(new URL('../../../supabase/managed-deployment-identity/bind-managed.sql',import.meta.url),'utf8'),
 readFile(new URL('../../../supabase/migrations/20261022195747_collect_application_mutation_fence.sql',import.meta.url),'utf8'),
 readFile(new URL('../../../supabase/migrations/20261101012309_collect_admission_archive.sql',import.meta.url),'utf8'),
 readFile(new URL('../../../supabase/migrations/20261101013157_collect_deployment_identity.sql',import.meta.url),'utf8'),
 readFile(new URL('./preimage-query.sql',import.meta.url),'utf8'),
 readFile(new URL('./readback-routines.sql',import.meta.url),'utf8'),
 readFile(new URL('./readback-binding.sql',import.meta.url),'utf8')]);
assert.equal(hash(base),ORIGINAL_SHA256);
assert.equal(hash(fence),'714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497');
assert.equal(hash(archive),'82b09d4d2abd5994429a978ccf80daa796fd83e5dc5d29bc54076f2b7565ad84');
assert.equal(hash(identity),'916a7b3012135484c74f0a6b4707cdda39c637959f8564233fc8f6a8f5adbdc1');
const scheduler=fence.match(/CREATE FUNCTION private\._collect_fence_scheduler_status\(\) RETURNS jsonb[\s\S]*?END;\$fn\$;/)?.[0];
assert.ok(scheduler);
const baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const fenceOperation='55555555-5555-4555-8555-555555555555',fenceSource='b'.repeat(64);
const profile=()=>canonicalProfile({format:'collect.deployment.v1',id:'collect-managed-production',mode:'managed',environment:'production',
 supabase_origin:'https://rrlduytparvsjfmegalh.supabase.co',member_api_origin:'https://api.example.invalid',
 admin_origin:'https://admin.example.invalid',public_origin:'https://public.example.invalid',google_callback_origin:'https://admin.example.invalid'});
const binding=()=>({operationId:'66666666-6666-4666-8666-666666666666',profileRaw:profile(),
 fenceOperationId:fenceOperation,fenceEpoch:1,fenceSourceSha256:fenceSource});
const bind=(db,id,p=profile())=>db.query(
 'SELECT private.collect_bind_managed_deployment($1::uuid,$2::text,$3::text,$4::uuid,$5::bigint,$6::text) AS result',
 [id,p,hash(p),fenceOperation,1,fenceSource]);
const observe=async db=>(await db.query(preimageQuery)).rows[0].preimage_observation;
const toPreimage=o=>({format:'collect.managed-provider-identity.v1',project:PROJECT_REF,trust:TRUST,observedAt:o.observedAt,
 validUntil:o.suggestedValidUntil,serverVersion:o.serverVersion,history:o.history,roleOids:o.roleOids,schedulerSha256:o.scheduler.sha256});
const roundtrip=async db=>compileManagedBinderV1({source:base,preimage:preparePreimageV1({observation:await observe(db),project:PROJECT_REF,trust:TRUST}),binding:binding()});
const noBinder=async db=>assert.equal((await db.query("SELECT to_regprocedure('private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)') IS NULL absent")).rows[0].absent,true);

test('managed identity v1 compiler and candidate on an owned PG17 cluster', {timeout:120000},async t=>{
 verifyEnvironment(process.env);await verifyBinaryPins();process.env.COLLECT_SYNTHETIC_PG_BIN=BIN;
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_managed_candidate_synthetic_only'});
 assert.equal(f.bin,BIN);const clients=[];
 const connect=async user=>{const c=new Client({host:f.socket,port:f.port,database:'postgres',user,connectionTimeoutMillis:3000});
  c.on('error',()=>{});await c.connect();clients.push(c);return c;};
 let admin,provider,db;
 try{
  admin=await connect('fixture_bootstrap');
  await admin.query(`CREATE ROLE postgres LOGIN NOSUPERUSER INHERIT CREATEDB CREATEROLE REPLICATION BYPASSRLS;
   CREATE ROLE supabase_admin LOGIN SUPERUSER;CREATE ROLE cli_login_postgres LOGIN NOSUPERUSER NOINHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
   CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_runtime LOGIN;CREATE ROLE audit_probe LOGIN;
   GRANT pg_read_all_settings TO postgres;GRANT postgres TO supabase_admin WITH ADMIN TRUE;
   ALTER DATABASE postgres OWNER TO postgres`);
  provider=await connect('supabase_admin');
  await provider.query('GRANT postgres TO cli_login_postgres WITH ADMIN FALSE, INHERIT FALSE, SET TRUE GRANTED BY supabase_admin');
  db=await connect('postgres');
  const host=(await db.query(`SELECT current_setting('server_version_num')::int version,inet_server_addr() IS NULL AND inet_client_addr() IS NULL socket,
   current_setting('cluster_name') cluster,session_user,current_user`)).rows[0];
  assert.ok(host.version>=170000&&host.version<180000);assert.equal(host.socket,true);
  assert.equal(host.cluster,'collect_managed_candidate_synthetic_only');assert.equal(host.session_user,'postgres');assert.equal(host.current_user,'postgres');
  async function setup({predecessors=true}={}){
   await db.query('ROLLBACK');
   await db.query('DROP SCHEMA IF EXISTS private CASCADE;DROP SCHEMA IF EXISTS supabase_migrations CASCADE;DROP SCHEMA IF EXISTS app CASCADE;DROP SCHEMA IF EXISTS auth CASCADE;DROP SCHEMA IF EXISTS cron CASCADE;DROP SCHEMA IF EXISTS net CASCADE;DROP SCHEMA IF EXISTS collect_ops CASCADE');
   await db.query(`CREATE SCHEMA private;GRANT USAGE ON SCHEMA private TO collect_runtime,audit_probe;
    CREATE SCHEMA supabase_migrations;CREATE SCHEMA app;CREATE SCHEMA auth;CREATE SCHEMA cron;CREATE SCHEMA net;CREATE SCHEMA collect_ops;
    CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,name text,statements text[]);
    CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,project_ref text,baseline_manifest_sha256 text,
     source_sha256 text,epoch bigint,mode text,operation_id uuid);
    CREATE TABLE private.collect_fence_admissions(state text,uncertain_dispatches integer);
    CREATE TABLE cron.job(jobname text,active boolean);CREATE TABLE net.http_request_queue(id bigint);
    CREATE TABLE auth.users(id uuid PRIMARY KEY,email text);CREATE TABLE app.users(id text PRIMARY KEY,email text);
    CREATE TABLE private.auth_principal_links(auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id),user_id text UNIQUE REFERENCES app.users(id));
    INSERT INTO auth.users VALUES('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','synthetic@invalid.example');
    INSERT INTO app.users VALUES('existing-cloud-account','synthetic@invalid.example');
    INSERT INTO private.auth_principal_links VALUES('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','existing-cloud-account');
    INSERT INTO cron.job VALUES('collect-google-ciphertext-expiry-v1',false);
    CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
    CREATE FUNCTION collect_ops.cleanup_google_expired() RETURNS void LANGUAGE plpgsql AS $$BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 END$$;
    REVOKE ALL ON FUNCTION collect_ops.cleanup_google_expired() FROM PUBLIC`);
   await db.query(scheduler);await db.query('REVOKE ALL ON FUNCTION private._collect_fence_scheduler_status() FROM PUBLIC');
   await db.query('INSERT INTO private.collect_fence_control VALUES(true,$1,$2,$3,1,$4,$5)',
    [PROJECT_REF,baseline,fenceSource,'fenced',fenceOperation]);
   await db.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2,$3)',
    ['20261022195747','collect_application_mutation_fence',[fence]]);
   if(predecessors){
    // Synthetic records only: the archive predecessor is not executed here.
    await db.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2,$3),($4,$5,$6)',
     ['20261101012309','collect_admission_archive',[archive],'20261101013157','collect_deployment_identity',[identity]]);
    await db.query(identity);
   }
  }
  async function assertRoutineReadback(receipt){
   const rows=(await db.query(routineReadback)).rows[0].routine_observation;
   assert.equal(rows.length,2);const helper=rows.find(x=>x.signature==='private._collect_managed_identity_preimage()');
   const binder=rows.find(x=>x.signature==='private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)');
   assert.equal(helper.bodySha256,receipt.helperBodySha256);assert.equal(binder.bodySha256,receipt.binderBodySha256);
   for(const r of rows){assert.equal(r.present,true);assert.equal(r.owner,'postgres');assert.equal(r.language,'plpgsql');assert.equal(r.volatility,'v');assert.equal(r.strict,false);assert.equal(r.ownerOnlyAcl,true);}
   assert.equal(helper.securityDefiner,false);assert.equal(helper.returns,'void');assert.deepEqual(helper.settings,['search_path=pg_catalog, pg_temp']);
   assert.equal(binder.securityDefiner,true);assert.equal(binder.returns,'boolean');assert.deepEqual(binder.settings,['search_path=pg_catalog, pg_temp','lock_timeout=5s']);
  }

  await t.test('current-style missing predecessors are not accepted, even if input is forged',async()=>{
   await setup({predecessors:false});const obs=await observe(db);
   assert.ok(Object.values(obs.roleOids).every(Number.isSafeInteger),JSON.stringify(obs.roleOids));
   assert.deepEqual([obs.history.fence,obs.history.archive,obs.history.identity],[true,false,false]);
   assert.throws(()=>preparePreimageV1({observation:obs,project:PROJECT_REF,trust:TRUST}),/required_predecessor_history_absent_or_invalid/);
   assert.throws(()=>compileManagedBinderV1({source:base,preimage:toPreimage(obs)}),/required_predecessor_history_absent_or_invalid/);
   const forged=toPreimage(obs);forged.history={...forged.history,count:3,archive:true,identity:true};
   const sql=compileManagedBinderV1({source:base,preimage:forged,binding:binding()}).sql;
   // PG plans the original regclass constant before it can emit the named
   // precondition. This is still a rollback, not a successful install.
   await assert.rejects(db.query(sql),/relation "private.collect_deployment_identity" does not exist/);await db.query('ROLLBACK');await noBinder(db);
  });
  await t.test('strict offline preimages require provider trust, exact source and qualified scheduler',async()=>{
   await setup();const obs=await observe(db),p=toPreimage(obs);
   assert.equal(obs.database,'postgres');assert.equal(obs.sessionUser,'postgres');assert.equal(obs.scheduler.metadataOk,true);
   assert.equal(obs.scheduler.sha256,SCHEDULER_SHA256);assert.deepEqual(Object.values(obs.roleChecks).sort(),[1,true,true,true,true,true].sort());
   assert.deepEqual(preparePreimageV1({observation:obs,project:PROJECT_REF,trust:TRUST}),p);
   assert.throws(()=>preparePreimageV1({observation:{...obs,sessionUser:'cli_login_postgres'},project:PROJECT_REF,trust:TRUST}),/observed_preimage_not_qualified/);
   assert.throws(()=>preparePreimageV1({observation:{...obs,roleChecks:{...obs.roleChecks,ownerPaths:false}},project:PROJECT_REF,trust:TRUST}),/observed_preimage_not_qualified/);
   assert.throws(()=>compileManagedBinderV1({source:base+' ',preimage:p}),/original_binder_preimage_mismatch/);
   assert.throws(()=>compileManagedBinderV1({source:base,preimage:{...p,trust:'not-a-trust-assumption'}}),/explicit_project_and_trust_required/);
   assert.throws(()=>compileManagedBinderV1({source:base,preimage:{...p,project:'other'}}),/explicit_project_and_trust_required/);
   assert.throws(()=>compileManagedBinderV1({source:base,preimage:{...p,schedulerSha256:'f'.repeat(64)}}),/scheduler_variant_not_qualified/);
   assert.throws(()=>compileManagedBinderV1({source:base,preimage:{...p,roleOids:{...p.roleOids,cli:'1;DROP ROLE postgres'}}}),/invalid_role_preimage/);
   assert.throws(()=>compileManagedBinderV1({source:base,preimage:{...p,validUntil:'2030-01-01T00:00:00.000Z'}}),/invalid_preimage_validity_or_version/);
   assert.throws(()=>compileManagedBinderV1({source:base,preimage:p,binding:{...binding(),operationId:'1;DROP ROLE postgres'}}),/invalid_atomic_binding/);
   assert.throws(()=>compileManagedBinderV1({source:base,preimage:p,binding:{...binding(),profileRaw:'{}'}}),/invalid_managed_profile/);
   assert.throws(()=>executeManaged(),/managed_dispatch_not_implemented/);
  });
  await t.test('exact preimage installs, produces catalog readback pins and preserves the synthetic cloud principal',async()=>{
   await setup();const before=(await db.query('SELECT * FROM private.auth_principal_links')).rows;
   const candidate=await roundtrip(db);assert.equal(candidate.receipt.productionDispatch,false);assert.equal(hash(candidate.sql),candidate.receipt.sqlSha256);
   const oldGuard=` IF EXISTS(SELECT 1 FROM pg_roles r WHERE NOT r.rolsuper AND r.rolname<>'postgres'
   AND pg_has_role(r.oid,'postgres'::regrole,'MEMBER'))
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_owner_role_preimage';END IF;`;
   const [prefix,suffix]=base.split(oldGuard);assert.ok(suffix&&base.endsWith('\nCOMMIT;\n'));
   assert.ok(candidate.sql.startsWith('-- collect.managed-provider-identity.v1; generated offline; provider administration explicitly trusted\n'+prefix));
   assert.ok(candidate.sql.includes(suffix.slice(0,-'\nCOMMIT;\n'.length)));
   await db.query(candidate.sql);await assertRoutineReadback(candidate.receipt);
   const status=(await db.query('SELECT private._collect_fence_scheduler_status() s')).rows[0].s;
   assert.equal(status.checked,true);assert.equal(status.coverageVerified,true);assert.equal(status.blocking,false);
   const id=candidate.receipt.operationId;assert.equal((await bind(db,id)).rows[0].result,true);assert.equal((await bind(db,id)).rows[0].result,true);
   await assert.rejects(bind(db,randomUUID()),/deployment_identity_already_bound/);
   assert.deepEqual((await db.query('SELECT * FROM private.auth_principal_links')).rows,before);
  });
  await t.test('an existing matching deployment identity cannot bypass the inactive-controller check',async()=>{
   await setup();const candidate=await roundtrip(db),id=candidate.receipt.operationId,p=profile();
   await db.query('INSERT INTO private.collect_deployment_identity(operation_id,profile_raw,profile_sha256) VALUES($1,$2,$3)',[id,p,hash(p)]);
   await db.query("INSERT INTO private.collect_fence_admissions VALUES('active',0)");
   await assert.rejects(db.query(candidate.sql),/managed_deployment_atomic_bind_requires_empty_identity/);await db.query('ROLLBACK');await noBinder(db);
   assert.equal((await db.query('SELECT count(*)::int n FROM private.collect_deployment_identity')).rows[0].n,1);
  });
  await t.test('expired and wrong-owner/CLI/membership OIDs fail closed before install',async()=>{
   await setup();const p=toPreimage(await observe(db));
   for(const field of ['owner','provider','cli','membership']){
    const bad={...p,roleOids:{...p.roleOids,[field]:4000000000}};
    await assert.rejects(db.query(compileManagedBinderV1({source:base,preimage:bad,binding:binding()}).sql),/managed_deployment_provider_role_preimage/);await db.query('ROLLBACK');await noBinder(db);
   }
   const expired={...p,observedAt:new Date(Date.now()-120000).toISOString(),validUntil:new Date(Date.now()-60000).toISOString()};
   await assert.rejects(db.query(compileManagedBinderV1({source:base,preimage:expired,binding:binding()}).sql),/managed_deployment_scope_or_preimage_expired/);await db.query('ROLLBACK');await noBinder(db);
  });
  await t.test('preimage expiry after function creation rolls the entire install and bind back',async()=>{
   await setup();const obs=await observe(db),p=toPreimage(obs);
   p.validUntil=new Date(Date.parse(p.observedAt)+3000).toISOString();
   const candidate=compileManagedBinderV1({source:base,preimage:p,binding:binding()});
   // Test-only marker and delay are inserted after CREATE FUNCTION but before
   // the atomic bind. A second session proves that marker was reached.
   const marker=`DO $fixture_marker$ BEGIN PERFORM pg_advisory_xact_lock(712345,26);END $fixture_marker$;\nSELECT pg_sleep(3.5);\n`;
   assert.equal(candidate.sql.split('-- Install and bind are one atomic transaction;').length,2);
   const delayed=candidate.sql.replace('-- Install and bind are one atomic transaction;',marker+'-- Install and bind are one atomic transaction;');
   const pending=db.query(delayed);void pending.catch(()=>{});let reached=false;
   const deadline=Date.now()+2500;
   while(Date.now()<deadline&&!reached){
    reached=(await admin.query(`SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid=$1 AND locktype='advisory'
     AND classid=712345 AND objid=26 AND objsubid=2 AND granted) AS reached`,[db.processID])).rows[0].reached;
    if(!reached)await new Promise(resolve=>setTimeout(resolve,40));
   }
   assert.equal(reached,true,'transaction did not reach the post-install marker');
   await assert.rejects(pending,/managed_deployment_scope_or_preimage_expired/);await db.query('ROLLBACK');await noBinder(db);
   assert.equal((await db.query('SELECT count(*)::int n FROM private.collect_deployment_identity')).rows[0].n,0);
  });
  await t.test('history, role options and indirect owner paths are rechecked at binding',async()=>{
   await setup();const candidate=await roundtrip(db);await db.query(candidate.sql);
   await db.query("INSERT INTO supabase_migrations.schema_migrations VALUES('99999999999999','drift',ARRAY['synthetic'])");
   await assert.rejects(bind(db,randomUUID()),/managed_deployment_full_history_preimage/);
   await db.query("DELETE FROM supabase_migrations.schema_migrations WHERE version='99999999999999'");
   await provider.query('GRANT postgres TO cli_login_postgres WITH SET FALSE GRANTED BY supabase_admin');
   try{await assert.rejects(bind(db,randomUUID()),/managed_deployment_provider_role_preimage/);}
   finally{await provider.query('GRANT postgres TO cli_login_postgres WITH SET TRUE GRANTED BY supabase_admin');}
   await admin.query('GRANT cli_login_postgres TO audit_probe');
   try{await assert.rejects(bind(db,randomUUID()),/managed_deployment_provider_role_preimage/);}
   finally{await admin.query('REVOKE cli_login_postgres FROM audit_probe');}
   assert.equal((await db.query('SELECT count(*)::int n FROM private.collect_deployment_identity')).rows[0].n,1);
  });
  await t.test('grantor, recreated membership and role-attribute drift invalidate a formerly fresh candidate',async()=>{
   await setup();const candidate=await roundtrip(db);
   await admin.query('ALTER ROLE cli_login_postgres INHERIT');
   try{await assert.rejects(db.query(candidate.sql),/managed_deployment_provider_role_preimage/);await db.query('ROLLBACK');await noBinder(db);}
   finally{await admin.query('ALTER ROLE cli_login_postgres NOINHERIT');}
   await provider.query('REVOKE postgres FROM cli_login_postgres GRANTED BY supabase_admin');
   await admin.query('GRANT postgres TO cli_login_postgres WITH ADMIN FALSE, INHERIT FALSE, SET TRUE');
   try{await assert.rejects(db.query(candidate.sql),/managed_deployment_provider_role_preimage/);await db.query('ROLLBACK');await noBinder(db);}
   finally{await admin.query('REVOKE postgres FROM cli_login_postgres');await provider.query('GRANT postgres TO cli_login_postgres WITH ADMIN FALSE, INHERIT FALSE, SET TRUE GRANTED BY supabase_admin');}
   await assert.rejects(db.query(candidate.sql),/managed_deployment_provider_role_preimage/);await db.query('ROLLBACK');await noBinder(db);
   const refreshed=await roundtrip(db);await db.query(refreshed.sql);await assertRoutineReadback(refreshed.receipt);
  });
  await t.test('changed scheduler variant or metadata is refused even with a forged preimage',async()=>{
   await setup();const candidate=await roundtrip(db);
   await db.query("CREATE OR REPLACE FUNCTION private._collect_fence_scheduler_status() RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$");
   assert.notEqual((await observe(db)).scheduler.sha256,SCHEDULER_SHA256);
   await assert.rejects(db.query(candidate.sql),/managed_deployment_scheduler_preimage/);await db.query('ROLLBACK');await noBinder(db);
   await setup();const candidate2=await roundtrip(db);await db.query('GRANT EXECUTE ON FUNCTION private._collect_fence_scheduler_status() TO audit_probe');
   await assert.rejects(db.query(candidate2.sql),/managed_deployment_scheduler_preimage/);await db.query('ROLLBACK');await noBinder(db);
  });
  await t.test('unacknowledged bind stays unknown even if a read sees absence then later sees commit',async()=>{
   await setup();const candidate=await roundtrip(db),observer=await connect('postgres'),id=candidate.receipt.operationId;
   // Hold back only the final COMMIT to simulate a request still in flight.
   assert.ok(candidate.sql.endsWith('COMMIT;\n'));await db.query(candidate.sql.slice(0,-'COMMIT;\n'.length));
   assert.equal((await observer.query('SELECT count(*)::int n FROM private.collect_deployment_identity')).rows[0].n,0);
   assert.deepEqual((await observer.query(bindingReadback,[id,hash(profile()),profile()])).rows[0].binding_observation,{rowCount:0,matchesExpected:false});
   assert.deepEqual(assessAcknowledgement({phase:'bind',acknowledgement:'unknown',readback:'absent'}),{
    phase:'bind',acknowledgement:'unknown',readback:'absent',decision:'hold_for_external_reconciliation',automaticRetry:false,actorAbsenceProven:false,productionReleaseProven:false});
   await db.query('COMMIT');assert.equal((await observer.query('SELECT operation_id FROM private.collect_deployment_identity')).rows[0].operation_id,id);
   assert.deepEqual((await observer.query(bindingReadback,[id,hash(profile()),profile()])).rows[0].binding_observation,{rowCount:1,matchesExpected:true});
   assert.equal(assessAcknowledgement({phase:'bind',acknowledgement:'unknown',readback:'matches'}).automaticRetry,false);
   assert.equal(assessAcknowledgement({phase:'install',acknowledgement:'unknown',readback:'matches'}).productionReleaseProven,false);
   await assert.rejects(db.query(candidate.sql),/managed_deployment_install_precondition/);await db.query('ROLLBACK');
  });
  await t.test('runtime access, CLI session identity, active work and acknowledgement errors remain blocked',async()=>{
   await setup();const blocked=await roundtrip(db);
   for(const [state,uncertain] of [['active',0],['settled',1],[null,0],['settled',null]]){
    await db.query('INSERT INTO private.collect_fence_admissions VALUES($1,$2)',[state,uncertain]);
    await assert.rejects(db.query(blocked.sql),/requires_inactive_controller/);await db.query('ROLLBACK');await noBinder(db);
    assert.equal((await db.query('SELECT count(*)::int n FROM private.collect_deployment_identity')).rows[0].n,0);
    await db.query('DELETE FROM private.collect_fence_admissions');
   }
   await db.query('INSERT INTO net.http_request_queue VALUES(1)');
   await assert.rejects(db.query(blocked.sql),/requires_inactive_controller/);await db.query('ROLLBACK');await noBinder(db);
   await db.query('DELETE FROM net.http_request_queue');
   await setup();const candidate=await roundtrip(db);await db.query(candidate.sql);
   const runtime=await connect('collect_runtime'),cli=await connect('cli_login_postgres');await cli.query('SET ROLE postgres');
   await assert.rejects(bind(runtime,randomUUID()),/permission denied/);await assert.rejects(bind(cli,randomUUID()),/managed_deployment_binding_refused/);
   for(const phase of ['install','bind'])for(const acknowledgement of ['success','error','unknown'])for(const readback of ['matches','absent','different','unavailable']){
    const state=assessAcknowledgement({phase,acknowledgement,readback});assert.equal(state.decision,'hold_for_external_reconciliation');
    assert.equal(state.automaticRetry,false);assert.equal(state.actorAbsenceProven,false);assert.equal(state.productionReleaseProven,false);
   }
  });
 }finally{
  await Promise.allSettled(clients.map(c=>c.end()));const closed=await f.close();assert.equal(closed.removed,true,'owned fixture cleanup unconfirmed');await verifyBinaryPins();
 }
});
