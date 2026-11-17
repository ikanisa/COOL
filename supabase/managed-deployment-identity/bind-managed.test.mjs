import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {canonicalProfile,validateDeploymentProfile} from '../functions/_shared/deployment-profile.js';

const specifier=process.env.COLLECT_IDENTITY_TEST_PGLITE_MODULE??new URL('../../scripts/supabase/node_modules/@electric-sql/pglite/dist/index.js',import.meta.url).href;
let PGlite;try{({PGlite}=await import(specifier));}catch{}
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
 supabase_origin:'https://rrlduytparvsjfmegalh.supabase.co',member_api_origin:'https://api.collect.example',
 admin_origin:'https://admin.collect.example',public_origin:'https://collect.example',google_callback_origin:'https://api.collect.example'});
const raw=p=>canonicalProfile(p);
async function fixture(mode='fenced',beforeInstall=async()=>{},install=true){
 assert.ok(PGlite,'Install pinned PGlite or set COLLECT_IDENTITY_TEST_PGLITE_MODULE');
 const db=new PGlite();
 await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_runtime;CREATE ROLE audit_probe;
  CREATE SCHEMA private;GRANT USAGE ON SCHEMA private TO collect_runtime,audit_probe;
  CREATE SCHEMA supabase_migrations;
  CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,name text,statements text[]);
  CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,project_ref text,baseline_manifest_sha256 text,
   source_sha256 text,epoch bigint,mode text,operation_id uuid);
  CREATE TABLE private.collect_fence_admissions(state text,uncertain_dispatches integer DEFAULT 0);
  CREATE SCHEMA cron;CREATE TABLE cron.job(jobname text,active boolean);`);
 await db.exec(scheduler);await db.exec('REVOKE ALL ON FUNCTION private._collect_fence_scheduler_status() FROM PUBLIC');
 await db.query('INSERT INTO private.collect_fence_control VALUES(true,$1,$2,$3,1,$4,$5)',
  ['rrlduytparvsjfmegalh',baseline,fenceSource,mode,fenceOperation]);
 await db.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2,$3),($4,$5,$6),($7,$8,$9)',
  ['20261022195747','collect_application_mutation_fence',[fence],'20261101012309','collect_admission_archive',[archive],
   '20261101013157','collect_deployment_identity',[original]]);
 await db.exec(original);await db.exec('ALTER DEFAULT PRIVILEGES IN SCHEMA private GRANT EXECUTE ON FUNCTIONS TO audit_probe');
 await beforeInstall(db);if(install)await db.exec(candidate);return db;
}
const bind=(db,id,p,digest=hash(p),operation=fenceOperation,epoch=1,source=fenceSource)=>db.query(
 'SELECT private.collect_bind_managed_deployment($1::uuid,$2::text,$3::text,$4::uuid,$5::bigint,$6::text) AS result',
 [id,p,digest,operation,epoch,source]);

test('managed binding uses the existing immutable assertion and is idempotent only for the same operation',async()=>{
 const db=await fixture();try{
  const id=randomUUID(),p=raw(profile());assert.equal((await bind(db,id,p)).rows[0].result,true);
  assert.equal((await bind(db,id,p)).rows[0].result,true);
  assert.equal((await db.query('SELECT private.collect_assert_deployment($1) AS result',[hash(p)])).rows[0].result,true);
  await assert.rejects(bind(db,randomUUID(),p),/deployment_identity_already_bound/);
  await assert.rejects(db.query("UPDATE private.collect_deployment_identity SET profile_raw='changed'"),/deployment_identity_is_immutable/);
 }finally{await db.close();}
});
test('binding requires the exact managed production project and canonical profile',async()=>{
 const db=await fixture();try{
  const id=randomUUID(),p=profile(),invalid=[
   {...p,mode:'self_hosted'},{...p,environment:'qualification'},{...p,supabase_origin:'https://other.supabase.co'},
   {...p,google_callback_origin:'https://other.example'},{...p,admin_origin:'https://a.-bad.example'},
   {...p,admin_origin:'https://a.123'},{...p,admin_origin:'https://a.0x00'},{...p,admin_origin:'https://a.example:443'},
   {...p,admin_origin:'https://a.example/path'},{...p,admin_origin:'https://xn--a.example'}
  ];
  for(const item of invalid)await assert.rejects(bind(db,id,raw(item)));
  const good=raw(p);await assert.rejects(bind(db,id,good,'0'.repeat(64)));
  await assert.rejects(bind(db,id,JSON.stringify(p)));
  await assert.rejects(bind(db,id,good.replace('{','{"id":"duplicate",')));
  assert.equal((await db.query('SELECT count(*)::int AS n FROM private.collect_deployment_identity')).rows[0].n,0);
 }finally{await db.close();}
});
test('the fence and all prior admissions must be settled before first binding',async()=>{
 const db=await fixture('open');try{
  const id=randomUUID(),p=raw(profile());await assert.rejects(bind(db,id,p),/requires_inactive_controller/);
  await db.query("UPDATE private.collect_fence_control SET mode='fenced'");await db.query("INSERT INTO private.collect_fence_admissions(state) VALUES('unresolved')");
  await assert.rejects(bind(db,id,p),/requires_inactive_controller/);
  await db.query("UPDATE private.collect_fence_admissions SET state='settled',uncertain_dispatches=1");
  await assert.rejects(bind(db,id,p),/requires_inactive_controller/);
  await db.query('UPDATE private.collect_fence_admissions SET uncertain_dispatches=NULL');await assert.rejects(bind(db,id,p),/requires_inactive_controller/);
  await db.query('UPDATE private.collect_fence_admissions SET state=NULL,uncertain_dispatches=0');await assert.rejects(bind(db,id,p),/requires_inactive_controller/);
  await db.query("UPDATE private.collect_fence_admissions SET state='settled'");
  await db.query("INSERT INTO cron.job VALUES('collect-jobs-maintenance-v1',true)");await assert.rejects(bind(db,id,p),/requires_inactive_controller/);
  await db.query('DELETE FROM cron.job');
  for(const [op,epoch,source] of [[randomUUID(),1,fenceSource],[fenceOperation,2,fenceSource],[fenceOperation,1,'c'.repeat(64)]])
   await assert.rejects(bind(db,id,p,hash(p),op,epoch,source),/requires_inactive_controller/);
  await db.query('UPDATE private.collect_fence_control SET project_ref=NULL');await assert.rejects(bind(db,id,p),/requires_inactive_controller/);
  await db.query("UPDATE private.collect_fence_control SET project_ref='rrlduytparvsjfmegalh',mode=NULL");await assert.rejects(bind(db,id,p),/requires_inactive_controller/);
  await db.query("UPDATE private.collect_fence_control SET mode='fenced'");assert.equal((await bind(db,id,p)).rows[0].result,true);
 }finally{await db.close();}
});
test('default grants do not expose the managed binding to runtime or another role',async()=>{
 const db=await fixture();try{
  const row=(await db.query(`SELECT has_function_privilege('collect_runtime','private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)','EXECUTE') AS runtime,
   has_function_privilege('audit_probe','private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)','EXECUTE') AS other`)).rows[0];
  assert.deepEqual(row,{runtime:false,other:false});
  await db.exec('SET ROLE collect_runtime');await assert.rejects(bind(db,randomUUID(),raw(profile())),/permission denied/);await db.exec('RESET ROLE');
 }finally{await db.close();}
});
test('installation refuses drift in the immutable identity and assertion preimages',async()=>{
 const mutations=[
  "ALTER TABLE private.collect_deployment_identity DISABLE TRIGGER collect_deployment_immutable",
  "CREATE OR REPLACE FUNCTION private.collect_assert_deployment(p_sha256 text) RETURNS boolean LANGUAGE sql AS 'SELECT true'",
  'ALTER TABLE private.collect_deployment_identity DROP CONSTRAINT collect_deployment_identity_profile_raw_check',
  'GRANT SELECT ON private.collect_deployment_identity TO audit_probe',
  'GRANT EXECUTE ON FUNCTION private.collect_assert_deployment(text) TO audit_probe',
  'GRANT EXECUTE ON FUNCTION private.collect_assert_deployment(text) TO collect_runtime WITH GRANT OPTION'
 ];
 for(const mutation of mutations){
  const db=await fixture('fenced',async current=>current.exec(mutation),false);
  try{await assert.rejects(db.exec(candidate),/managed_deployment_(identity|assertion)_preimage/);}finally{await db.close();}
 }
});
test('installation refuses absent or changed predecessor history',async()=>{
 for(const mutation of [
  "DELETE FROM supabase_migrations.schema_migrations WHERE version='20261101012309'",
  "UPDATE supabase_migrations.schema_migrations SET name='wrong' WHERE version='20261101013157'",
  "UPDATE supabase_migrations.schema_migrations SET statements=ARRAY['changed'] WHERE version='20261101012309'"
 ]){
  const db=await fixture('fenced',async current=>current.exec(mutation),false);
  try{await assert.rejects(db.exec(candidate),/managed_deployment_history_preimage/);}finally{await db.close();}
 }
});
test('binding rechecks predecessor history',async()=>{
 const db=await fixture();try{
  await db.query("UPDATE supabase_migrations.schema_migrations SET statements=ARRAY['changed'] WHERE version='20261101013157'");
  await assert.rejects(bind(db,randomUUID(),raw(profile())),/managed_deployment_history_preimage/);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM private.collect_deployment_identity')).rows[0].n,0);
 }finally{await db.close();}
});
test('binding rejects scheduler function drift',async()=>{
 const db=await fixture();try{
  await db.exec("CREATE OR REPLACE FUNCTION private._collect_fence_scheduler_status() RETURNS jsonb LANGUAGE sql AS $$ SELECT '{\"blocking\":false}'::jsonb $$");
  await assert.rejects(bind(db,randomUUID(),raw(profile())),/managed_deployment_scheduler_preimage/);
 }finally{await db.close();}
});
test('binding rechecks identity and assertion drift after installation',async()=>{
 for(const mutation of [
  'ALTER TABLE private.collect_deployment_identity DISABLE TRIGGER collect_deployment_immutable',
  "CREATE OR REPLACE FUNCTION private.collect_assert_deployment(p_sha256 text) RETURNS boolean LANGUAGE sql AS 'SELECT true'",
  'GRANT CREATE ON SCHEMA private TO audit_probe; ALTER TABLE private.collect_deployment_identity OWNER TO audit_probe'
 ]){
  const db=await fixture();try{
   await db.exec(mutation);await assert.rejects(bind(db,randomUUID(),raw(profile())),/managed_deployment_(identity|assertion)_preimage/);
  }finally{await db.close();}
 }
});
test('installing the managed binder preserves the existing self-hosted binder',async()=>{
 const db=await fixture();try{
  const self={...profile(),id:'collect-local',mode:'self_hosted',supabase_origin:'https://supabase.collect.example'};
  assert.deepEqual(validateDeploymentProfile(self),self);const p=raw(self);
  assert.equal((await db.query('SELECT private.collect_bind_deployment($1::uuid,$2,$3) AS result',[randomUUID(),p,hash(p)])).rows[0].result,true);
 }finally{await db.close();}
});
