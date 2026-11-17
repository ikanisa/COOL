import {readFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
import {compileManagedLifecycleCandidate} from './managed-lifecycle-candidate.mjs';
import {retainedLock,migrationBytes} from './retained-source.mjs';
import {includeManagedRetirement} from './retention-candidate.mjs';

export const SOURCE=resolve(import.meta.dirname,'../../..');
export const retirement='20261117064828_collect_managed_executor_retirement.sql';
export const binding='20261117065536_collect_cloud_runtime_binding.sql';
export const hash=x=>createHash('sha256').update(x).digest('hex');
const origin='https://rrlduytparvsjfmegalh.supabase.co';
export const profile=canonicalProfile({format:'collect.deployment.v1',id:'collect-managed-production-cloud',mode:'managed',environment:'production',supabase_origin:origin,member_api_origin:origin,admin_origin:origin,public_origin:origin,google_callback_origin:origin});
export function identity(file,sql){
 const m=/^(\d{14})_(.+)\.sql$/.exec(file);if(!m)throw Error('invalid_migration_filename');
 return {file,version:m[1],name:m[2],sql,sha256:hash(sql)};
}
export function body(sql){
 const starts=[...sql.matchAll(/^BEGIN;\s*$/gm)],ends=[...sql.matchAll(/^COMMIT;\s*$/gm)];
 if(starts.length===0&&ends.length===0)return sql;
 if(starts.length!==1||ends.length!==1||ends[0].index<starts[0].index)throw Error('migration_transaction_shape');
 // One retained migration has appended DDL after COMMIT. Include those exact
 // statements in our encompassing transaction and history, never execute them
 // as an unjournaled second operation.
 return sql.slice(0,starts[0].index)+sql.slice(starts[0].index+starts[0][0].length,ends[0].index)+sql.slice(ends[0].index+ends[0][0].length);
}
export async function chain(){
 const work=JSON.parse(await readFile(SOURCE+'/supabase/managed-migration-history/source-migrations.lock.json','utf8')).migrations;
 const retained=await retainedLock();
 if(work.length!==58||retained.length!==62||work.slice(0,52).some((x,i)=>x.name!==retained[i].name||x.sha256!==retained[i].sha256))throw Error('retained_chain_changed');
 const all=[...work,...retained.filter(x=>!work.some(y=>y.name===x.name))].sort((a,b)=>a.name.localeCompare(b.name));
 all.push({name:'20261116215300_burimunsi_operator_identity_guard.sql',sha256:hash(await readFile(SOURCE+'/supabase/migrations/20261116215300_burimunsi_operator_identity_guard.sql'))});
 const variants={
  '20261114110000_burimunsi_native_retention_positive_links.sql':['20261114110001_burimunsi_native_retention_positive_links_managed_convergence.sql','managed-branch-1100-candidate.sql','23fe7bb434fd05b71da835083351fd568a1adbf997ca00f7419fb504bf1324ce'],
  '20261113130700_storage_iceberg_retention_inspection.sql':['20261117071117_storage_iceberg_cloud_catalog.sql','../../../supabase/migrations/20261117071117_storage_iceberg_cloud_catalog.sql','3ef135d93a0272260e8b12d1a2dcb690bb7a650b178fc12f98acd38ac176290d'],
  '20261114110200_storage_iceberg_retention_census.sql':['20261117071123_storage_iceberg_cloud_census.sql','../../../supabase/migrations/20261117071123_storage_iceberg_cloud_census.sql','043c3eda476542c8f8e9f85ce985f789ef1fd4c0bc9f21fc3f87a76b3fef06e9']};
 const out=[];
 for(const item of all){
  const bytes=await migrationBytes(SOURCE,item);
  let name=item.name,sql=bytes.toString();
  if(variants[name]){const [newName,file,pin]=variants[name];sql=await readFile(SOURCE+'/scripts/supabase/retention-convergence/'+file,'utf8');if(hash(sql)!==pin)throw Error('variant_changed');name=newName;}
  out.push(identity(name,sql));
  // Bind only after the original lifecycle's final preimage exists. The
  // current managed executor was already atomically retired and drained.
  if(item.name==='20261110181002_collect_local_stopped_admission.sql')out.push(identity(binding,await readFile(SOURCE+'/supabase/migrations/'+binding,'utf8')));
 }
 const textFix='20261117060642_burimunsi_retention_text_subjects.sql';
 out.push(identity(textFix,await readFile(SOURCE+'/supabase/migrations/'+textFix,'utf8')));
 return out;
}
export async function history(c){return(await c.query("select version,name,encode(sha256(convert_to(statements[1],'UTF8')),'hex') sha256,cardinality(statements)::int entries from supabase_migrations.schema_migrations order by version")).rows;}
export async function resolveEntry(c,entry){
 if(entry.file!=='20261116163800_collect_storage_lifecycle_retention.sql')return entry;
 const h=(await c.query(`SELECT count(*)::int n,encode(sha256(convert_to(string_agg(version||':'||coalesce(name,'')||':'||encode(sha256(convert_to(statements[1],'UTF8')),'hex'),E'\\n' ORDER BY version COLLATE "C"),'UTF8')),'hex') digest FROM supabase_migrations.schema_migrations`)).rows[0];
 const source=(await c.query('select source_sha256 from private.collect_fence_control where singleton')).rows[0].source_sha256;
 const result=compileManagedLifecycleCandidate(Buffer.from(entry.sql),{profileSha:hash(profile),sourceSha:source,historySha:h.digest,historyCount:h.n,storageShapeSha:'27b92cac21dab5b92f0f389a9635adeaddbd4952868fa6d9285f18205533e333'});
 return identity('20261116163801_collect_storage_lifecycle_retention_managed_convergence.sql',includeManagedRetirement(result.sql));
}
export async function applyEntry(c,entry,{before,afterBody=async()=>{}}){
 let commit=false;
 await c.query('BEGIN ISOLATION LEVEL READ COMMITTED');
 try{
  await c.query("SET LOCAL lock_timeout='5s'; SET LOCAL statement_timeout='90s'; SELECT pg_advisory_xact_lock(7346371,11); LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE; SELECT pg_advisory_xact_lock(7346371,1); SELECT pg_advisory_xact_lock(7346371,2)");
  if(JSON.stringify(await history(c))!==JSON.stringify(before))throw Error('migration_history_changed');
  const mode=(await c.query('select mode,project_ref from private.collect_fence_control where singleton')).rows[0];
  if(mode?.project_ref!=='rrlduytparvsjfmegalh'||(entry.file===retirement?!['quiescing','fenced'].includes(mode.mode):mode.mode!=='fenced'))throw Error('migration_fence_changed');
  await c.query(body(entry.sql));await afterBody(c);
  if(entry.file===binding){const result=await c.query('select private.collect_bind_deployment($1,$2,$3) ok',[randomUUID(),profile,hash(profile)]);if(result.rows[0].ok!==true)throw Error('binding_unconfirmed');}
  await c.query('insert into supabase_migrations.schema_migrations(version,name,statements) values($1,$2,$3)',[entry.version,entry.name,[entry.sql]]);
  const expected=[...before,{version:entry.version,name:entry.name,sha256:entry.sha256,entries:1}].sort((a,b)=>a.version.localeCompare(b.version));
  if(JSON.stringify(await history(c))!==JSON.stringify(expected))throw Error('migration_history_postcondition');
  commit=true;await c.query('COMMIT');
  if(JSON.stringify(await history(c))!==JSON.stringify(expected))throw Error('migration_readback_mismatch');
  return expected;
 }catch(e){if(!commit)await c.query('ROLLBACK').catch(()=>{});else e.outcome='commit_requires_reconciliation';throw e;}
}
