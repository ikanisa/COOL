// Owned socket-only PostgreSQL 17 and invented rows/roles only. Never use a
// production connection, credential, role alteration, or real identity.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
import {syntheticProviderBinder,executeManaged,ORIGINAL_SHA256} from './synthetic-provider-binder.mjs';
import {BIN,verifyEnvironment,verifyBinaryPins} from './fixture-safety.mjs';

const {Client}=pg,hash=s=>createHash('sha256').update(s).digest('hex');
const [base,fence,archive,identity]=await Promise.all([
 readFile(new URL('../../../supabase/managed-deployment-identity/bind-managed.sql',import.meta.url),'utf8'),
 readFile(new URL('../../../supabase/migrations/20261022195747_collect_application_mutation_fence.sql',import.meta.url),'utf8'),
 readFile(new URL('../../../supabase/migrations/20261101012309_collect_admission_archive.sql',import.meta.url),'utf8'),
 readFile(new URL('../../../supabase/migrations/20261101013157_collect_deployment_identity.sql',import.meta.url),'utf8')]);
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
const bind=(db,id,p=profile())=>db.query(
 'SELECT private.collect_bind_managed_deployment($1::uuid,$2::text,$3::text,$4::uuid,$5::bigint,$6::text) AS result',
 [id,p,hash(p),fenceOperation,1,fenceSource]);

test('provider-trust preimage is synthetic-only and preserves the original constraints', {timeout:120000},async t=>{
 verifyEnvironment(process.env);await verifyBinaryPins();process.env.COLLECT_SYNTHETIC_PG_BIN=BIN;
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_managed_identity_synthetic_only'});
 assert.equal(f.bin,BIN);
 const dbName='collect_managed_identity_'+randomUUID().replaceAll('-','')+'_test';
 const clients=[];
 const connect=async(user,database=dbName)=>{const c=new Client({host:f.socket,port:f.port,database,user,connectionTimeoutMillis:3000});
  c.on('error',()=>{});await c.connect();clients.push(c);return c;};
 let bootstrap,provider,db;
 try{
  bootstrap=await connect('fixture_bootstrap','postgres');
  await bootstrap.query(`CREATE ROLE postgres LOGIN NOSUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS;
   CREATE ROLE supabase_admin LOGIN SUPERUSER;
   CREATE ROLE cli_login_postgres LOGIN NOSUPERUSER NOINHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
   CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_runtime LOGIN;CREATE ROLE audit_probe LOGIN;
   GRANT pg_read_all_settings TO postgres;
   GRANT postgres TO supabase_admin WITH ADMIN TRUE`);
  provider=await connect('supabase_admin','postgres');
  await provider.query('GRANT postgres TO cli_login_postgres WITH ADMIN FALSE, INHERIT FALSE, SET TRUE GRANTED BY supabase_admin');
  await bootstrap.query(`CREATE DATABASE ${dbName} OWNER postgres`);db=await connect('postgres');
  const info=(await db.query(`SELECT current_setting('server_version_num')::int version,session_user,current_user,
   inet_server_addr() IS NULL AND inet_client_addr() IS NULL socket_only,
   r.rolsuper,r.rolbypassrls FROM pg_roles r WHERE r.rolname=current_user`)).rows[0];
  assert.ok(info.version>=170000&&info.version<180000);assert.equal(info.socket_only,true);
  assert.equal(info.session_user,'postgres');assert.equal(info.current_user,'postgres');assert.equal(info.rolsuper,false);assert.equal(info.rolbypassrls,true);
  const rows=(await bootstrap.query(`SELECT o.oid::int owner,p.oid::int provider,c.oid::int cli,m.oid::int membership
   FROM pg_roles o CROSS JOIN pg_roles p CROSS JOIN pg_roles c JOIN pg_auth_members m ON m.member=c.oid
   WHERE o.rolname='postgres' AND p.rolname='supabase_admin' AND c.rolname='cli_login_postgres'
    AND m.roleid=o.oid AND m.grantor=p.oid AND m.set_option AND NOT m.inherit_option AND NOT m.admin_option`)).rows;
  if(rows.length!==1){const detail=(await bootstrap.query(`SELECT pg_get_userbyid(roleid) granted,pg_get_userbyid(member) member,
   pg_get_userbyid(grantor) grantor,admin_option,inherit_option,set_option FROM pg_auth_members WHERE member='cli_login_postgres'::regrole`)).rows;
   assert.fail(`unexpected synthetic grant ${JSON.stringify(detail)}`);}
  const oids=rows[0];
  const args={source:base,trust:'synthetic-provider-admin-is-trusted',fixtureDatabase:dbName,oids};
  const candidate=syntheticProviderBinder(args);

  async function setup({install=true,predecessor=true,mutate}={}){
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
    ['rrlduytparvsjfmegalh',baseline,fenceSource,'fenced',fenceOperation]);
   // The two later rows are deliberately simulated, not executed migrations.
   await db.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2,$3),($4,$5,$6),($7,$8,$9)',
    ['20261022195747','collect_application_mutation_fence',[fence],'20261101012309','collect_admission_archive',[archive],
     '20261101013157','collect_deployment_identity',[identity]]);
   if(predecessor)await db.query(identity);if(mutate)await mutate();if(install)await db.query(candidate);
  }
  const accountSnapshot=async()=>(await db.query(`SELECT
   (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM auth.users u) auth,
   (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM app.users u) app,
   (SELECT jsonb_agg(to_jsonb(l) ORDER BY auth_user_id) FROM private.auth_principal_links l) links`)).rows[0];
  const noBinder=async()=>assert.equal((await db.query("SELECT to_regprocedure('private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)') IS NULL absent")).rows[0].absent,true);

  await t.test('compiler refuses unknown source, missing trust, invalid fixture and any managed dispatch',async()=>{
   assert.throws(()=>syntheticProviderBinder({...args,trust:undefined}),/synthetic_trust_assumption_required/);
   assert.throws(()=>syntheticProviderBinder({...args,source:base+' '}),/original_candidate_preimage_mismatch/);
   assert.throws(()=>syntheticProviderBinder({...args,fixtureDatabase:'postgres'}),/fixture_database_required/);
   assert.throws(()=>syntheticProviderBinder({...args,oids:{...oids,cli:'1;DROP ROLE postgres'}}),/invalid_fixture_oids/);
   assert.throws(()=>executeManaged(),/managed_execution_not_implemented_or_authorized/);
   assert.throws(()=>verifyEnvironment({PGOPTIONS:'synthetic'}),/MANAGED_OR_EXTERNAL_CONNECTION_REFUSED/);
   assert.throws(()=>verifyEnvironment({SUPABASE_ACCESS_TOKEN:'synthetic'}),/MANAGED_OR_EXTERNAL_CONNECTION_REFUSED/);
   assert.throws(()=>verifyEnvironment({COLLECT_SYNTHETIC_PG_BIN:'/tmp/unreviewed'}),/SYNTHETIC_BINARY_REQUIRED/);
   const other=await connect('postgres','postgres');
   await assert.rejects(other.query(candidate),/SYNTHETIC_ONLY_REFUSAL/);
   assert.equal((await other.query("SELECT to_regnamespace('private') IS NULL absent")).rows[0].absent,true);
  });
  await t.test('unmodified candidate rejects the actual modeled provider membership',async()=>{
   await setup({install:false});await assert.rejects(db.query(base),/managed_deployment_owner_role_preimage/);await db.query('ROLLBACK');await noBinder();
  });
  await t.test('CLI SET ROLE cannot install the original predecessor because session identity is retained',async()=>{
   await setup({install:false,predecessor:false});const cli=await connect('cli_login_postgres');await cli.query('SET ROLE postgres');
   await assert.rejects(cli.query(identity),/deployment_owner_install_required/);await cli.query('ROLLBACK');
   assert.equal((await db.query("SELECT to_regclass('private.collect_deployment_identity') IS NULL absent")).rows[0].absent,true);
  });
  await t.test('exact trusted-provider preimage binds once and preserves the existing cloud principal',async()=>{
   await setup();const before=await accountSnapshot(),id=randomUUID();
   const schedulerStatus=(await db.query('SELECT private._collect_fence_scheduler_status() status')).rows[0].status;
   assert.equal(schedulerStatus.checked,true);assert.equal(schedulerStatus.coverageVerified,true);assert.equal(schedulerStatus.blocking,false);
   assert.equal((await bind(db,id)).rows[0].result,true);assert.equal((await bind(db,id)).rows[0].result,true);
   await assert.rejects(bind(db,randomUUID()),/deployment_identity_already_bound/);
   assert.equal((await db.query('SELECT private.collect_assert_deployment($1) ok',[hash(profile())])).rows[0].ok,true);
   assert.deepEqual(await accountSnapshot(),before);
  });
  await t.test('ordinary runtime is denied; CLI SET ROLE is denied by session identity but retains owner DDL power',async()=>{
   await setup();const runtime=await connect('collect_runtime'),cli=await connect('cli_login_postgres');
   await assert.rejects(bind(runtime,randomUUID()),/permission denied/);
   await cli.query('SET ROLE postgres');
   assert.deepEqual((await cli.query('SELECT session_user,current_user')).rows[0],{session_user:'cli_login_postgres',current_user:'postgres'});
   await assert.rejects(bind(cli,randomUUID()),/managed_deployment_binding_refused/);
   // This proves why the provider/admin session is a trusted actor: it can
   // alter owner objects even though it cannot invoke this binding contract.
   await cli.query('BEGIN');await cli.query("ALTER FUNCTION private._collect_managed_identity_preimage() SET statement_timeout='1s'");
   const changed=(await cli.query("SELECT proconfig FROM pg_proc WHERE oid='private._collect_managed_identity_preimage()'::regprocedure")).rows[0].proconfig;
   assert.ok(changed.includes('statement_timeout=1s'));await cli.query('ROLLBACK');
   assert.equal((await db.query('SELECT count(*)::int n FROM private.collect_deployment_identity')).rows[0].n,0);
  });
  await t.test('membership, grantor, attributes and additional indirect runtime paths are pinned',async()=>{
   await setup({install:false});
   for(const [forward,undo] of [
    ['ALTER ROLE cli_login_postgres INHERIT','ALTER ROLE cli_login_postgres NOINHERIT'],
    ['ALTER ROLE cli_login_postgres NOLOGIN','ALTER ROLE cli_login_postgres LOGIN'],
    ['ALTER ROLE cli_login_postgres CREATEROLE','ALTER ROLE cli_login_postgres NOCREATEROLE'],
    ['GRANT cli_login_postgres TO audit_probe','REVOKE cli_login_postgres FROM audit_probe'],
    ['GRANT fixture_bootstrap TO audit_probe','REVOKE fixture_bootstrap FROM audit_probe'],
    ['GRANT postgres TO audit_probe','REVOKE postgres FROM audit_probe']]){
    await bootstrap.query(forward);
    try{await assert.rejects(db.query(candidate),/managed_deployment_provider_role_preimage/);await db.query('ROLLBACK');await noBinder();}
    finally{await bootstrap.query(undo);}
   }
   await provider.query('GRANT postgres TO cli_login_postgres WITH SET FALSE GRANTED BY supabase_admin');
   try{await assert.rejects(db.query(candidate),/managed_deployment_provider_role_preimage/);await db.query('ROLLBACK');await noBinder();}
   finally{await provider.query('GRANT postgres TO cli_login_postgres WITH SET TRUE GRANTED BY supabase_admin');}
   await db.query(candidate);
   await bootstrap.query('GRANT cli_login_postgres TO audit_probe');
   try{await assert.rejects(bind(db,randomUUID()),/managed_deployment_provider_role_preimage/);}
   finally{await bootstrap.query('REVOKE cli_login_postgres FROM audit_probe');}
   await setup({install:false});
   // Replace the same named direct membership with a distinct grantor/OID.
   await provider.query('REVOKE postgres FROM cli_login_postgres GRANTED BY supabase_admin');
   await bootstrap.query('GRANT postgres TO cli_login_postgres WITH ADMIN FALSE, INHERIT FALSE, SET TRUE');
   try{await assert.rejects(db.query(candidate),/managed_deployment_provider_role_preimage/);await db.query('ROLLBACK');await noBinder();}
   finally{await bootstrap.query('REVOKE postgres FROM cli_login_postgres');await provider.query('GRANT postgres TO cli_login_postgres WITH ADMIN FALSE, INHERIT FALSE, SET TRUE GRANTED BY supabase_admin');}
   // Restored provider grant receives a new OID and requires a fresh fixture preimage.
   await assert.rejects(db.query(candidate),/managed_deployment_provider_role_preimage/);await db.query('ROLLBACK');await noBinder();
   const membership=(await bootstrap.query(`SELECT m.oid::int membership FROM pg_auth_members m
    JOIN pg_roles o ON o.oid=m.roleid JOIN pg_roles c ON c.oid=m.member JOIN pg_roles p ON p.oid=m.grantor
    WHERE o.rolname='postgres' AND c.rolname='cli_login_postgres' AND p.rolname='supabase_admin'`)).rows[0].membership;
   oids.membership=membership;
  });
  await t.test('scheduler/body drift and unresolved or active work continue to block',async()=>{
   const refreshed=syntheticProviderBinder(args);await setup({install:false});
   await db.query("CREATE OR REPLACE FUNCTION private._collect_fence_scheduler_status() RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$");
   await assert.rejects(db.query(refreshed),/managed_deployment_scheduler_preimage/);await db.query('ROLLBACK');await noBinder();
   await setup({install:false});await db.query(refreshed);
   for(const [state,uncertain] of [['active',0],['settled',1],[null,0],['settled',null]]){
    await db.query('INSERT INTO private.collect_fence_admissions VALUES($1,$2)',[state,uncertain]);
    await assert.rejects(bind(db,randomUUID()),/requires_inactive_controller/);await db.query('DELETE FROM private.collect_fence_admissions');
   }
   await db.query("UPDATE cron.job SET active=true");await assert.rejects(bind(db,randomUUID()),/requires_inactive_controller/);
   assert.equal((await db.query('SELECT count(*)::int n FROM private.collect_deployment_identity')).rows[0].n,0);
  });
 }finally{
  await Promise.allSettled(clients.map(c=>c.end()));const closed=await f.close();assert.equal(closed.removed,true,'owned fixture cleanup unconfirmed');
  await verifyBinaryPins();
 }
});
