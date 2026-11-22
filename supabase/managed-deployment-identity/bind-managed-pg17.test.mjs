// Synthetic data on an owned, private-socket PG17 cluster only. This fixture
// deliberately records migration history without executing archive migration
// 309; it tests this candidate's checks, not the whole migration chain.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../../scripts/supabase/node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../../scripts/supabase/current-pg-transfer/test-support/owned-pg17.mjs';
import {canonicalProfile} from '../functions/_shared/deployment-profile.js';

const {Client}=pg;
const original=await readFile(new URL('../migrations/20261101013157_collect_deployment_identity.sql',import.meta.url),'utf8');
const archive=await readFile(new URL('../migrations/20261101012309_collect_admission_archive.sql',import.meta.url),'utf8');
const fence=await readFile(new URL('../migrations/20261022195747_collect_application_mutation_fence.sql',import.meta.url),'utf8');
const scheduler=fence.match(/CREATE FUNCTION private\._collect_fence_scheduler_status\(\) RETURNS jsonb[\s\S]*?END;\$fn\$;/)?.[0];
assert.ok(scheduler,'scheduler predecessor function must be present');
const candidate=await readFile(new URL('./bind-managed.sql',import.meta.url),'utf8');
const hash=s=>createHash('sha256').update(s).digest('hex');
const fenceOperation='55555555-5555-4555-8555-555555555555',fenceSource='b'.repeat(64);
const baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const profile=()=>({format:'collect.deployment.v1',id:'collect-managed-production',mode:'managed',environment:'production',
 supabase_origin:'https://rrlduytparvsjfmegalh.supabase.co',member_api_origin:'https://api.example.invalid',
 admin_origin:'https://admin.example.invalid',public_origin:'https://public.example.invalid',google_callback_origin:'https://admin.example.invalid'});
const raw=p=>canonicalProfile(p);
const bind=(db,id,p,digest=hash(p),operation=fenceOperation,epoch=1,source=fenceSource)=>db.query(
 'SELECT private.collect_bind_managed_deployment($1::uuid,$2::text,$3::text,$4::uuid,$5::bigint,$6::text) AS result',
 [id,p,digest,operation,epoch,source]);

test('managed candidate on native PostgreSQL 17 without a postgres superuser', {timeout:120000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_managed_identity_fixture'}),clients=[];
 const connect=async(user='postgres')=>{const c=new Client({host:f.socket,port:f.port,database:'collect_identity_fixture',user,connectionTimeoutMillis:3000});
  c.on('error',()=>{});await c.connect();clients.push(c);return c;};
 let bootstrap,db;
 try{
  bootstrap=new Client({host:f.socket,port:f.port,database:'postgres',user:'fixture_bootstrap',connectionTimeoutMillis:3000});
  bootstrap.on('error',()=>{});await bootstrap.connect();clients.push(bootstrap);
  await bootstrap.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS;
   CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE ROLE collect_runtime LOGIN; CREATE ROLE audit_probe LOGIN;`);
  await bootstrap.query('CREATE DATABASE collect_identity_fixture OWNER postgres');db=await connect();
  const info=(await db.query("SELECT current_setting('server_version_num')::int AS version, r.rolsuper,r.rolbypassrls FROM pg_roles r WHERE r.rolname=current_user")).rows[0];
  assert.ok(info.version>=170000&&info.version<180000);assert.equal(info.rolsuper,false);assert.equal(info.rolbypassrls,true);

  async function setup({install=true,mutate}={}){
   await db.query('ROLLBACK');
   await db.query('DROP SCHEMA IF EXISTS private CASCADE; DROP SCHEMA IF EXISTS supabase_migrations CASCADE; DROP SCHEMA IF EXISTS app CASCADE; DROP SCHEMA IF EXISTS auth CASCADE; DROP SCHEMA IF EXISTS cron CASCADE');
   await db.query(`CREATE SCHEMA private; GRANT USAGE ON SCHEMA private TO collect_runtime,audit_probe;
    CREATE SCHEMA supabase_migrations;CREATE SCHEMA app;CREATE SCHEMA auth;
    CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,name text,statements text[]);
    CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,project_ref text,baseline_manifest_sha256 text,
     source_sha256 text,epoch bigint,mode text,operation_id uuid);
    CREATE TABLE private.collect_fence_admissions(state text,uncertain_dispatches integer);
    CREATE SCHEMA cron;CREATE TABLE cron.job(jobname text,active boolean);
    CREATE TABLE auth.users(id uuid PRIMARY KEY,email text);
    CREATE TABLE app.users(id text PRIMARY KEY,email text);
    CREATE TABLE private.auth_principal_links(auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id),user_id text UNIQUE REFERENCES app.users(id));
    INSERT INTO auth.users VALUES('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','synthetic@invalid.example');
    INSERT INTO app.users VALUES('existing-cloud-account','synthetic@invalid.example');
    INSERT INTO private.auth_principal_links VALUES('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','existing-cloud-account');`);
   await db.query(scheduler);await db.query('REVOKE ALL ON FUNCTION private._collect_fence_scheduler_status() FROM PUBLIC');
   await db.query('INSERT INTO private.collect_fence_control VALUES(true,$1,$2,$3,1,$4,$5)',
    ['rrlduytparvsjfmegalh',baseline,fenceSource,'fenced',fenceOperation]);
   await db.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2,$3),($4,$5,$6),($7,$8,$9)',
    ['20261022195747','collect_application_mutation_fence',[fence],'20261101012309','collect_admission_archive',[archive],
     '20261101013157','collect_deployment_identity',[original]]);
   await db.query(original);await db.query('ALTER DEFAULT PRIVILEGES IN SCHEMA private GRANT EXECUTE ON FUNCTIONS TO audit_probe');
   if(mutate)await mutate();if(install)await db.query(candidate);
  }
  const accountSnapshot=async()=> (await db.query(`SELECT
   (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM auth.users u) AS auth,
   (SELECT jsonb_agg(to_jsonb(u) ORDER BY id) FROM app.users u) AS app,
   (SELECT jsonb_agg(to_jsonb(l) ORDER BY auth_user_id) FROM private.auth_principal_links l) AS links`)).rows[0];

  await t.test('binding preserves the cloud principal, checks callback origin and never rewrites identity',async()=>{
   await setup();const before=await accountSnapshot(),id=randomUUID(),p=raw(profile());
   const wrong=raw({...profile(),google_callback_origin:'https://other.example.invalid'});
   await assert.rejects(bind(db,id,wrong),/managed_deployment_profile_not_canonical/);
   const self=raw({...profile(),id:'collect-local',mode:'self_hosted',supabase_origin:'https://local.example.invalid'});
   await assert.rejects(bind(db,id,self),/managed_deployment_profile_invalid/);
   assert.equal((await bind(db,id,p)).rows[0].result,true);assert.equal((await bind(db,id,p)).rows[0].result,true);
   assert.equal((await db.query('SELECT private.collect_assert_deployment($1) AS ok',[hash(p)])).rows[0].ok,true);
   await assert.rejects(db.query("SELECT private.collect_assert_deployment($1)",['0'.repeat(64)]),/deployment_identity_mismatch/);
   await assert.rejects(bind(db,randomUUID(),p),/deployment_identity_already_bound/);
   await assert.rejects(db.query("UPDATE private.collect_deployment_identity SET profile_raw='rewrite'"),/deployment_identity_is_immutable/);
   await assert.rejects(db.query('SELECT private.collect_bind_deployment($1,$2,$3)',[randomUUID(),self,hash(self)]),/deployment_identity_already_bound/);
   assert.deepEqual(await accountSnapshot(),before);
  });
  await t.test('self-hosted binding remains distinct and cannot be converted into managed identity',async()=>{
   await setup();const before=await accountSnapshot();
   const self=raw({...profile(),id:'collect-local',mode:'self_hosted',supabase_origin:'https://local.example.invalid'}),p=raw(profile());
   assert.equal((await db.query('SELECT private.collect_bind_deployment($1,$2,$3) AS ok',[randomUUID(),self,hash(self)])).rows[0].ok,true);
   const prior=(await db.query('SELECT operation_id,profile_raw,profile_sha256 FROM private.collect_deployment_identity')).rows;
   await assert.rejects(bind(db,randomUUID(),p),/deployment_identity_already_bound/);
   assert.deepEqual((await db.query('SELECT operation_id,profile_raw,profile_sha256 FROM private.collect_deployment_identity')).rows,prior);
   assert.deepEqual(await accountSnapshot(),before);
  });
  await t.test('function grants and isolation stay closed for non-owners and unusual sessions',async()=>{
   await setup();const runtime=await connect('collect_runtime'),p=raw(profile());
   const access=(await db.query(`SELECT has_function_privilege('collect_runtime','private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)','EXECUTE') AS runtime,
    has_function_privilege('audit_probe','private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)','EXECUTE') AS other`)).rows[0];
   assert.deepEqual(access,{runtime:false,other:false});await assert.rejects(bind(runtime,randomUUID(),p),/permission denied/);
   await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ');
   await assert.rejects(bind(db,randomUUID(),p),/managed_deployment_binding_refused/);await db.query('ROLLBACK');
   assert.equal((await db.query('SELECT count(*)::int AS n FROM private.collect_deployment_identity')).rows[0].n,0);
  });
  await t.test('owner membership and effective privilege drift stop installation or binding',async()=>{
   await setup({install:false});
   await bootstrap.query('ALTER ROLE audit_probe NOINHERIT; GRANT postgres TO audit_probe');
   try{
    await assert.rejects(db.query(candidate),/managed_deployment_owner_role_preimage/);await db.query('ROLLBACK');
    assert.equal((await db.query("SELECT to_regprocedure('private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)') IS NULL AS absent")).rows[0].absent,true);
   }finally{await bootstrap.query('REVOKE postgres FROM audit_probe; ALTER ROLE audit_probe INHERIT');}
   await setup();
   await db.query('GRANT EXECUTE ON FUNCTION private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text) TO audit_probe');
   await assert.rejects(bind(db,randomUUID(),raw(profile())),/managed_deployment_effective_privilege_preimage/);
   await db.query('REVOKE EXECUTE ON FUNCTION private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text) FROM audit_probe');
   await bootstrap.query('ALTER ROLE audit_probe NOINHERIT; GRANT postgres TO audit_probe');
   try{await assert.rejects(bind(db,randomUUID(),raw(profile())),/managed_deployment_owner_role_preimage/);}
   finally{await bootstrap.query('REVOKE postgres FROM audit_probe; ALTER ROLE audit_probe INHERIT');}
   assert.equal((await db.query('SELECT count(*)::int AS n FROM private.collect_deployment_identity')).rows[0].n,0);
  });
  await t.test('predecessor history and immutable identity drift are rejected atomically',async()=>{
   for(const sql of ["DELETE FROM supabase_migrations.schema_migrations WHERE version='20261101012309'",
    "UPDATE supabase_migrations.schema_migrations SET statements=ARRAY['changed'] WHERE version='20261101013157'",
    'ALTER TABLE private.collect_deployment_identity DISABLE TRIGGER collect_deployment_immutable',
    "CREATE OR REPLACE FUNCTION private._collect_fence_scheduler_status() RETURNS jsonb LANGUAGE sql AS $$SELECT '{}'::jsonb$$"]){
    await setup({install:false,mutate:()=>db.query(sql)});
    await assert.rejects(db.query(candidate),/managed_deployment_(history|identity|scheduler)_preimage/);await db.query('ROLLBACK');
    assert.equal((await db.query("SELECT to_regprocedure('private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)') IS NULL AS absent")).rows[0].absent,true);
   }
   await setup();await db.query("UPDATE supabase_migrations.schema_migrations SET statements=ARRAY['changed'] WHERE version='20261101012309'");
   await assert.rejects(bind(db,randomUUID(),raw(profile())),/managed_deployment_history_preimage/);
   assert.equal((await db.query('SELECT count(*)::int AS n FROM private.collect_deployment_identity')).rows[0].n,0);
  });
  await t.test('wrong fence tokens, null/uncertain work, and unverified scheduler fail closed',async()=>{
   await setup();const p=raw(profile()),id=randomUUID(),attempt=()=>bind(db,id,p);
   for(const [op,epoch,source] of [[randomUUID(),1,fenceSource],[fenceOperation,2,fenceSource],[fenceOperation,1,'c'.repeat(64)]])
    await assert.rejects(bind(db,id,p,hash(p),op,epoch,source),/requires_inactive_controller/);
   for(const col of ['project_ref','baseline_manifest_sha256','source_sha256','epoch','mode','operation_id']){
    await db.query('BEGIN');await db.query(`UPDATE private.collect_fence_control SET ${col}=NULL`);
    await assert.rejects(attempt(),/requires_inactive_controller/);await db.query('ROLLBACK');
   }
   for(const [state,uncertain] of [['active',0],['settled',1],[null,0],['settled',null]]){
    await db.query('INSERT INTO private.collect_fence_admissions VALUES($1,$2)',[state,uncertain]);
    await assert.rejects(attempt(),/requires_inactive_controller/);await db.query('DELETE FROM private.collect_fence_admissions');
   }
   await db.query("INSERT INTO cron.job VALUES('collect-jobs-maintenance-v1',true)");await assert.rejects(attempt(),/requires_inactive_controller/);
   await db.query('DELETE FROM cron.job');
   assert.equal((await attempt()).rows[0].result,true);
  });
  await t.test('a conflicting work lease prevents binding until it is released',async()=>{
   await setup();const holder=await connect(),p=raw(profile());let pending;
   await holder.query('BEGIN');await holder.query('SELECT pg_advisory_xact_lock_shared(7346371,1)');
   try{
    pending=bind(db,randomUUID(),p);
    const outcome=await Promise.race([pending.then(()=>'completed',()=>'failed'),new Promise(resolve=>setTimeout(()=>resolve('waiting'),150))]);
    assert.equal(outcome,'waiting');await holder.query('COMMIT');assert.equal((await pending).rows[0].result,true);
   }finally{await holder.query('ROLLBACK').catch(()=>{});if(pending)await pending.catch(()=>{});}
  });
 }finally{
  await Promise.allSettled(clients.map(c=>c.end()));const closed=await f.close();assert.equal(closed.removed,true,'owned synthetic cluster cleanup unconfirmed');
 }
});
