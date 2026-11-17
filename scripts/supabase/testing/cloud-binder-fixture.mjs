// Synthetic in-memory Postgres fixture only. It cannot accept a database URL,
// open a network connection, deploy functions, or access production records.
import {createHash,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import {isAbsolute} from 'node:path';
import {canonicalProfile,validateDeploymentProfile} from '../../../supabase/functions/_shared/deployment-profile.js';

const root=new URL('../../../supabase/migrations/',import.meta.url);
const sources=Object.freeze({
 '20261101013157_collect_deployment_identity.sql':'916a7b3012135484c74f0a6b4707cdda39c637959f8564233fc8f6a8f5adbdc1',
 '20261110181002_collect_local_stopped_admission.sql':'c7ee8a86dbb6ba5706f2cf4cee9dcd6907a194f1a8cb8826edf606c3364bae64',
 '20261117065536_collect_cloud_runtime_binding.sql':'dbaf8ae6900c8da298a857d6710f71feda9f803f8afc8493d222b7366de51343',
 '20261023174000_collect_stopped_admission_lifecycle.sql':'db6f2f23ae1ae5a7de01d8145e84b0429717e73628443ff58054f29aab451e25',
 '20261022195747_collect_application_mutation_fence.sql':'714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497',
 '20261117064828_collect_managed_executor_retirement.sql':'af8317f31d9e92824114577c169bc0e99530384c3b6ee53724bf6cb1b5f22019',
});
const sha=value=>createHash('sha256').update(value).digest('hex');
export const cloudOrigin='https://rrlduytparvsjfmegalh.supabase.co';
export const managedProfile=Object.freeze({format:'collect.deployment.v1',id:'collect-managed-production-cloud',mode:'managed',environment:'production',
 supabase_origin:cloudOrigin,member_api_origin:cloudOrigin,admin_origin:cloudOrigin,public_origin:cloudOrigin,google_callback_origin:cloudOrigin});
export const managedRaw=canonicalProfile(validateDeploymentProfile(managedProfile));
export const managedHash=sha(managedRaw);
const fn=(sql,name,tag='fn')=>{
 const pattern=new RegExp(`CREATE (?:OR REPLACE )?FUNCTION private\\.${name}\\([^$]*?AS \\$${tag}\\$[\\s\\S]*?\\$${tag}\\$;`,'g');
 const matches=[...sql.matchAll(pattern)];if(matches.length!==1)throw Error('Exact historical function source required: '+name);
 return matches[0][0].replace('CREATE OR REPLACE FUNCTION','CREATE FUNCTION');
};
export async function reviewedSql(){
 const values={};
 for(const [name,digest]of Object.entries(sources)){
  const bytes=await readFile(new URL(name,root));if(sha(bytes)!==digest)throw Error('Historical migration bytes changed: '+name);
  values[name]=bytes.toString('utf8');
 }
 return values;
}
export async function createCloudBinderFixture(){
 const configured=process.env.COLLECT_CLOUD_TEST_PGLITE_MODULE;
 if(configured!==undefined&&!isAbsolute(configured))throw Error('A physical local PGlite module is required');
 const moduleUrl=configured?pathToFileURL(configured).href:new URL('../node_modules/@electric-sql/pglite/dist/index.js',import.meta.url).href;
 const {PGlite}=await import(moduleUrl),sql=await reviewedSql(),db=new PGlite();
 try{
  await db.exec(`CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_runtime;CREATE ROLE collect_importer;
   CREATE SCHEMA private;GRANT USAGE ON SCHEMA private TO collect_runtime;CREATE SCHEMA synthetic_fixture;
   CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,project_ref text,baseline_manifest_sha256 text,source_sha256 text,epoch bigint,mode text,operation_id uuid,changed_at timestamptz DEFAULT clock_timestamp());
   CREATE TABLE private.collect_fence_operations(operation_id uuid,action text,epoch bigint,source_sha256 text);
   CREATE TABLE private.collect_fence_admissions(admission_id uuid PRIMARY KEY,epoch bigint,source_sha256 text,kind text,state text);
   CREATE TABLE private.collect_fence_stopped_admissions(admission_id uuid,epoch bigint,source_sha256 text,kind text,project_ref text);
   CREATE TABLE private.collect_fence_local_stopped_admissions(admission_id uuid,epoch bigint,source_sha256 text,kind text,project_ref text);
   CREATE TABLE synthetic_fixture.scheduler(blocking boolean NOT NULL);INSERT INTO synthetic_fixture.scheduler VALUES(false);
   CREATE FUNCTION private._collect_fence_scheduler_status() RETURNS jsonb LANGUAGE sql AS $$SELECT jsonb_build_object('blocking',blocking) FROM synthetic_fixture.scheduler$$;
   CREATE FUNCTION private.collect_fence_owner_status() RETURNS jsonb LANGUAGE sql AS $$SELECT jsonb_build_object('mode',mode,'epoch',epoch,'sourceSha256',source_sha256) FROM private.collect_fence_control WHERE singleton$$;`);
  for(const name of ['_collect_fence_no_erasure','_collect_fence_operator','_collect_fence_require_operator','_collect_fence_require_rc',
   'collect_fence_initialize','collect_fence_begin_quiesce','collect_fence_drain'])
   await db.exec(fn(sql['20261022195747_collect_application_mutation_fence.sql'],name));
  await db.exec(fn(sql['20261023174000_collect_stopped_admission_lifecycle.sql'],'_collect_stopped_require_owner'));
  await db.exec(fn(sql['20261110181002_collect_local_stopped_admission.sql'],'_collect_stopped_matches'));
  await db.exec(fn(sql['20261110181002_collect_local_stopped_admission.sql'],'_collect_stopped_proof_total'));
  // The historical migration installs the original binder but no identity row.
  // The current migration replaces it only with an empty identity and a fence.
  await db.exec(sql['20261101013157_collect_deployment_identity.sql']);
  if(Number((await db.query('SELECT count(*) AS n FROM private.collect_deployment_identity')).rows[0].n)!==0)throw Error('Synthetic identity must be empty');
  // Real predecessor functions establish OPEN -> QUIESCING -> FENCED without
  // binding any historical profile. Status/scheduler tables remain test doubles.
  const source='a'.repeat(64),baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3',
   initialize=randomUUID(),quiesce=randomUUID();
  const run=async(name,args)=>(await db.query('SELECT private.'+name+'($1::uuid,$2::'+(name==='collect_fence_initialize'?'text,$3::text':'bigint,$3::text')+') AS value',args)).rows[0].value;
  if((await run('collect_fence_initialize',[initialize,source,baseline])).mode!=='open')throw Error('Synthetic initialization did not open');
  if((await run('collect_fence_begin_quiesce',[quiesce,1,source])).mode!=='quiescing')throw Error('Synthetic quiesce failed');
  if((await run('collect_fence_drain',[quiesce,1,source])).mode!=='fenced')throw Error('Synthetic fence did not drain');
  if(Number((await db.query('SELECT count(*) AS n FROM private.collect_deployment_identity')).rows[0].n)!==0)throw Error('Synthetic bootstrap bound a historical identity');
  await db.exec(sql['20261117064828_collect_managed_executor_retirement.sql']);
  return {db,cloudMigration:sql['20261117065536_collect_cloud_runtime_binding.sql'],operation:randomUUID(),sourceDigests:{...sources}};
 }catch(error){await db.close();throw error;}
}
export async function installCloudBinder(fixture){
 try{await fixture.db.exec(fixture.cloudMigration);}
 catch(error){await fixture.db.exec('ROLLBACK');throw error;}
 if(Number((await fixture.db.query('SELECT count(*) AS n FROM private.collect_deployment_identity')).rows[0].n)!==0)throw Error('Cloud migration must not bind an identity');
}
export async function bindCloud(fixture,{operation=fixture.operation,raw=managedRaw,hash=managedHash}={}){
 return (await fixture.db.query('SELECT private.collect_bind_deployment($1::uuid,$2::text,$3::text) AS value',[operation,raw,hash])).rows[0].value;
}
