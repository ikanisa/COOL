// Synthetic-only chain observation. The owned fixture contains no real data and
// is stopped and removed by withOwnedArchiveFixture; this is not a deployer.
import {readFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import {withOwnedArchiveFixture} from '../managed-migration-next/synthetic-fixture.mjs';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
import {compileManagedLifecycleCandidate} from './managed-lifecycle-candidate.mjs';
import {retainedLock,migrationBytes,historyFixture} from './retained-source.mjs';
import {includeManagedRetirement} from './retention-candidate.mjs';

const root=resolve(import.meta.dirname,'../../..');
const sha=x=>createHash('sha256').update(x).digest('hex');
const fail=code=>{throw Error(code);};
const flags=process.argv.slice(2),managedLifecycle=flags.includes('--managed-lifecycle'),textSubjects=flags.includes('--text-subjects');
if(flags.some(x=>!['--managed-lifecycle','--text-subjects'].includes(x))||new Set(flags).size!==flags.length||(textSubjects&&!managedLifecycle))fail('invalid_mode');
const work=JSON.parse(await readFile(root+'/supabase/managed-migration-history/source-migrations.lock.json','utf8')).migrations;
const deployed=await retainedLock();
if(work.length!==58||deployed.length!==62||work.slice(0,52).some((x,i)=>x.name!==deployed[i].name||x.sha256!==deployed[i].sha256))fail('source_chain_changed');
const union=[...work,...deployed.filter(x=>!work.some(y=>y.name===x.name))].sort((a,b)=>a.name.localeCompare(b.name));
union.push({name:'20261116215300_burimunsi_operator_identity_guard.sql',sha256:sha(await readFile(root+'/supabase/migrations/20261116215300_burimunsi_operator_identity_guard.sql'))});
// Reuse the existing branch candidates and check that each original really
// refuses this synthetic predecessor. Never mark original bytes as applied.
const variants={
 '20261114110000_burimunsi_native_retention_positive_links.sql':['managed-branch-1100-candidate.sql','23fe7bb434fd05b71da835083351fd568a1adbf997ca00f7419fb504bf1324ce'],
 '20261113130700_storage_iceberg_retention_inspection.sql':['../../../supabase/migrations/20261117071117_storage_iceberg_cloud_catalog.sql','3ef135d93a0272260e8b12d1a2dcb690bb7a650b178fc12f98acd38ac176290d'],
 '20261114110200_storage_iceberg_retention_census.sql':['../../../supabase/migrations/20261117071123_storage_iceberg_cloud_census.sql','043c3eda476542c8f8e9f85ce985f789ef1fd4c0bc9f21fc3f87a76b3fef06e9']};
let replayFailed=false;
await withOwnedArchiveFixture(async({owner,admin,database})=>{
 const baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3',source='a'.repeat(64);
 await owner.query("ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz; ALTER TABLE auth.users ADD COLUMN is_anonymous boolean NOT NULL DEFAULT false");
 let storage=await readFile(root+'/scripts/supabase/testing/synthetic-iceberg-storage.sql','utf8');
 const old1="host(inet_server_addr()) IS DISTINCT FROM '127.0.0.1'",new1='inet_server_addr() IS NOT NULL';
 const old2="'^collect_selfhost_(backend|auth|notifications|recovery|gateway|integration)_[a-f0-9]{24}_test$'",new2="'^collect_archive_[a-f0-9]{24}_test$'";
 if(!storage.includes(old1)||!storage.includes(old2))fail('synthetic_storage_fixture_changed');storage=storage.replace(old1,()=>new1).replace(old2,()=>new2);
 await admin.query(storage);
 // Match the observed managed provider catalog, which lacks the optional
 // Iceberg child catalogs. This affects only the owned empty fixture.
 await admin.query('DROP TABLE storage.iceberg_tables; DROP TABLE storage.iceberg_namespaces');
 if(managedLifecycle){
  let ddl=await historyFixture('lifecycle-source-schema.sql','967c39a9ef16ca3836d97020b4e465df93583b6fa491877dcceafb42c6cbc1ce');
  ddl=ddl.replace(/^\\(?:un)?restrict [^\n]+\n/gm,'');
  for(const table of ['bucket_lifecycle_states','lifecycle_abandoned_artifacts']){
   const old=`GRANT ALL ON TABLE storage.${table} TO postgres;`,replacement=`GRANT SELECT ON TABLE storage.${table} TO postgres;`;
   if(ddl.split(old).length!==2)fail('synthetic_lifecycle_ddl_changed');ddl=ddl.replace(old,replacement);
  }
  await admin.query('CREATE TABLE storage.buckets(id text PRIMARY KEY); ALTER TABLE storage.buckets OWNER TO supabase_storage_admin;');
  await admin.query(ddl);await admin.query('RESET row_security; RESET search_path');
  await admin.query('CREATE TABLE storage.migrations(id integer PRIMARY KEY,name text,hash text); ALTER TABLE storage.migrations OWNER TO supabase_storage_admin; GRANT SELECT ON storage.migrations TO postgres;');
  const vendor=JSON.parse(await historyFixture('storage-vendor-history.json','89b56bc1574e348281e413e21226f12b5ab75e70c3c587b0af20bd7c601671c9'));
  if(vendor.length!==81)fail('synthetic_vendor_history_changed');
  await admin.query('INSERT INTO storage.migrations(id,name,hash) SELECT x.id,x.name,x.hash FROM jsonb_to_recordset($1::jsonb) x(id integer,name text,hash text)',[JSON.stringify(vendor)]);
 }
 await owner.query("INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id) VALUES(true,'rrlduytparvsjfmegalh',$1,$2,1,'fenced',$3)",[baseline,source,randomUUID()]);
 const profile=canonicalProfile({format:'collect.deployment.v1',id:'collect-managed-production-cloud',mode:'managed',environment:'production',
  supabase_origin:'https://rrlduytparvsjfmegalh.supabase.co',member_api_origin:'https://rrlduytparvsjfmegalh.supabase.co',
  admin_origin:'https://rrlduytparvsjfmegalh.supabase.co',public_origin:'https://rrlduytparvsjfmegalh.supabase.co',google_callback_origin:'https://rrlduytparvsjfmegalh.supabase.co'});
 await owner.query(await readFile(root+'/supabase/migrations/20261117064828_collect_managed_executor_retirement.sql','utf8'));
 const retirement=await readFile(root+'/supabase/migrations/20261117064828_collect_managed_executor_retirement.sql','utf8');
 await owner.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',['20261117064828','collect_managed_executor_retirement',[retirement]]);
 const done=[],skipped=[],negativeChecks=[];
 for(const item of union.slice(16)){
  // The later local-installation lifecycle file has a host/profile/receipt
  // preimage that does not describe managed Supabase. Keep it explicitly out
  // while testing independent later migrations; never record it as applied.
  if(item.name==='20261116163800_collect_storage_lifecycle_retention.sql'&&!managedLifecycle){skipped.push(item.name);continue;}
  const bytes=await migrationBytes(root,item);
  let sql=bytes.toString('utf8');
  if(variants[item.name]){
   let refused=false;try{await owner.query(sql);}catch(e){refused=e.code==='55000'&&['burimunsi_retention_positive_predecessor_changed','storage_iceberg_retention_predecessor_changed','storage_iceberg_retention_schema_changed'].includes(e.message);}finally{await owner.query('ROLLBACK').catch(()=>{});}
   if(!refused)fail('original_divergence_not_observed');const [file,pin]=variants[item.name],variant=await readFile(root+'/scripts/supabase/retention-convergence/'+file);if(sha(variant)!==pin)fail('branch_candidate_changed');sql=variant.toString('utf8');
  }
  if(item.name==='20261116163800_collect_storage_lifecycle_retention.sql'){
   let refused=false;try{await owner.query(sql);}catch(e){refused=e.code==='55000'&&e.message==='deployment_identity_mismatch';}finally{await owner.query('ROLLBACK').catch(()=>{});}
   if(!refused)fail('local_lifecycle_migration_not_refused');
   const h=(await owner.query(`SELECT count(*)::int AS count,encode(sha256(convert_to(string_agg(version || ':' || coalesce(name,'') || ':' || encode(sha256(convert_to(statements[1],'UTF8')),'hex'), E'\\n' ORDER BY version COLLATE "C"),'UTF8')),'hex') AS digest FROM supabase_migrations.schema_migrations`)).rows[0];
   const input={profileSha:sha(profile),sourceSha:source,historySha:h.digest,historyCount:h.count,storageShapeSha:'27b92cac21dab5b92f0f389a9635adeaddbd4952868fa6d9285f18205533e333'};
   sql=includeManagedRetirement(compileManagedLifecycleCandidate(bytes,input).sql);
   const refuses=async(candidate,reason)=>{let observed=false;try{await owner.query(candidate);}catch(e){observed=e.code==='55000'&&e.message===reason;}finally{await owner.query('ROLLBACK').catch(()=>{});}if(!observed)fail('negative_control_unconfirmed');negativeChecks.push(reason);};
   await refuses(compileManagedLifecycleCandidate(bytes,{...input,profileSha:'1'.repeat(64)}).sql,'deployment_identity_mismatch');
   await refuses(compileManagedLifecycleCandidate(bytes,{...input,sourceSha:'2'.repeat(64)}).sql,'storage_lifecycle_retention_precondition');
   await refuses(compileManagedLifecycleCandidate(bytes,{...input,historySha:'3'.repeat(64)}).sql,'storage_lifecycle_retention_app_history_changed');
   await admin.query('DROP INDEX storage.bucket_lifecycle_states_due_idx');
   try{await refuses(sql,'storage_lifecycle_retention_schema_changed');}
   finally{await admin.query('SET ROLE supabase_storage_admin; CREATE INDEX bucket_lifecycle_states_due_idx ON storage.bucket_lifecycle_states USING btree (next_run_at, bucket_id) WHERE (next_run_at IS NOT NULL); RESET ROLE');}
  }
  try{await owner.query(sql);done.push(item.name);
   if(managedLifecycle){
    
    const match=/^(\d{14})_(.*)\.sql$/.exec(item.name);if(!match)fail('migration_name_invalid');
    const version=variants[item.name]?({'20261114110000':'20261114110001','20261114110200':'20261117071123','20261113130700':'20261117071117'}[match[1]]):item.name==='20261116163800_collect_storage_lifecycle_retention.sql'?'20261116163801':match[1];
    const name=variants[item.name]?match[2]+'_managed_convergence':item.name==='20261116163800_collect_storage_lifecycle_retention.sql'?match[2]+'_managed_convergence':match[2];
    await owner.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',[version,name,[sql]]);
    if(item.name==='20261110181002_collect_local_stopped_admission.sql'){
     const binding=await readFile(root+'/supabase/migrations/20261117065536_collect_cloud_runtime_binding.sql','utf8');
     await owner.query(binding);
     await owner.query('SELECT private.collect_bind_deployment($1,$2,$3)',[randomUUID(),profile,sha(profile)]);
     await owner.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',['20261117065536','collect_cloud_runtime_binding',[binding]]);
    }

   }
  }
  catch(e){await owner.query('ROLLBACK').catch(()=>{});
   const signatures=['private._retention_manifest_catalog_v2()','private._retention_manifest_rows_v2(text)','private._retention_manifest_schema_v2()',
    'private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','private._retention_row_policy_v2(uuid,text,text,text)'];
   const hashes=(await owner.query("SELECT s.sig,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') AS sha256 FROM unnest($1::text[]) s(sig) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(s.sig) ORDER BY s.sig",[signatures])).rows;
   console.log(JSON.stringify({status:'synthetic_chain_stopped',applied:done.length,failed:item.name,sqlstate:e.code??null,reason:String(e.message??'').slice(0,180),retentionFunctionHashes:hashes,productionDispatch:false}));replayFailed=true;return;}
 }
 if(textSubjects){
  const fix=await readFile(root+'/supabase/migrations/20261117060642_burimunsi_retention_text_subjects.sql','utf8');
  const checks=[['private._burimunsi_retention_positive_links_v1(text,text)','3124613986def2fde264d20fc75c3b5974ad9e093dc6b623175c5b03cbbab583','f35281816661c456bc0e3e17bc0c70961bbef2160cfed729d8e0463cf79ac7a7'],
   ['private._burimunsi_retention_evidence_v2(text,text)','0c256f792a377bb868faefee3d81d5dee310db86380f20a4c56444bd2a7cb852','2a37dc0e053bb3146e46d8a6f7ce76afc02c16fe6574f3a2a2781064d16c617a']];
  const hashOf=async signature=>(await owner.query("SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') AS h FROM pg_proc WHERE oid=to_regprocedure($1)",[signature])).rows[0]?.h;
  for(const [sig,prior] of checks)if(await hashOf(sig)!==prior)fail('text_subject_preimage_changed');
  await owner.query('ALTER FUNCTION private._burimunsi_retention_evidence_v2(text,text) SECURITY INVOKER');
  try{let refused=false;try{await owner.query(fix);}catch(e){refused=e.code==='55000'&&e.message==='retention_text_subject_precondition';}finally{await owner.query('ROLLBACK').catch(()=>{});}if(!refused)fail('text_subject_drift_not_refused');
   if(await hashOf(checks[0][0])!==checks[0][1])fail('text_subject_atomicity_failed');}
  finally{await owner.query('ALTER FUNCTION private._burimunsi_retention_evidence_v2(text,text) SECURITY DEFINER');}
  await owner.query(fix);for(const [sig,,next] of checks)if(await hashOf(sig)!==next)fail('text_subject_postimage_changed');
  let replayRefused=false;try{await owner.query(fix);}catch(e){replayRefused=e.code==='55000'&&e.message==='retention_text_subject_precondition';}finally{await owner.query('ROLLBACK').catch(()=>{});}if(!replayRefused)fail('text_subject_replay_not_refused');
  await owner.query(`CREATE FUNCTION private.synthetic_retention_positive(s text,c text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$SELECT private._burimunsi_retention_positive_links_v1(s,c)$$;
   CREATE FUNCTION private.synthetic_retention_evidence(s text,c text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$SELECT private._burimunsi_retention_evidence_v2(s,c)$$;
   REVOKE ALL ON FUNCTION private.synthetic_retention_positive(text,text),private.synthetic_retention_evidence(text,text) FROM PUBLIC;
   GRANT EXECUTE ON FUNCTION private.synthetic_retention_positive(text,text),private.synthetic_retention_evidence(text,text) TO collect_runtime;`);
  for(const name of ['synthetic_retention_positive','synthetic_retention_evidence']){
   await owner.query('BEGIN');try{await owner.query('SET LOCAL ROLE collect_runtime');await owner.query("SELECT set_config('collect.edge_verified','true',true)");
    const response=(await owner.query('SELECT private.'+name+'($1,$2) value',['synthetic-owner','private:burimunsi_native_receipt_origins'])).rows[0].value;
    if(response.complete!==false||response.erasure!=='blocked'||!Array.isArray(response.matches))fail('text_subject_disposition_changed');
    let rejected=false;try{await owner.query('SELECT private.'+name+'($1,$2)',['invalid/identifier','private:burimunsi_native_receipt_origins']);}catch(e){rejected=e.code==='22023';}if(!rejected)fail('text_subject_invalid_accepted');
   }finally{await owner.query('ROLLBACK');}
  }
  negativeChecks.push('text_subject_atomicity','text_subject_replay','text_subject_invalid');
 }
 const hashes=(await owner.query("SELECT s.sig,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') AS sha256 FROM unnest($1::text[]) s(sig) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(s.sig) ORDER BY s.sig",[[
  'private._burimunsi_retention_positive_links_v1(text,text)','private._burimunsi_retention_evidence_v2(text,text)',
  'private._retention_manifest_catalog_v2()','private._retention_manifest_rows_v2(text)','private._retention_manifest_schema_v2()',
  'private._retention_manifest_managed_rows_v2(text,integer)','private._retention_row_policy_v2(uuid,text,text,text)',
  'private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','private.retention_inventory_page_v2(uuid,text,integer,boolean)']])).rows;
 const observations=(await owner.query(`SELECT
  to_regclass('private.burimunsi_accounts') IS NOT NULL AS accounts,
  to_regprocedure('private._burimunsi_retention_evidence_v2(text,text)') IS NOT NULL AS retention_evidence,
  to_regprocedure('private.burimunsi_operator_approve_v2(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint,text)') IS NOT NULL AS guarded_operator,
  (SELECT count(*) FROM app.runtime_config WHERE key='security:admin_mfa_required:v1')=0 AS mfa_not_enabled`)).rows[0];
 if(managedLifecycle){
  const actual=(await owner.query("SELECT private._retention_manifest_catalog_v2() AS catalog")).rows[0].catalog;
  for(const name of ['managed:storage_iceberg','managed:storage_iceberg_namespaces','managed:storage_iceberg_tables','managed:storage_bucket_lifecycle_states','managed:storage_lifecycle_abandoned_artifacts'])
   if(actual.copy_classes.filter(value=>value===name).length!==1)fail('lifecycle_catalog_incomplete');
  for(const name of ['private:burimunsi_native_financial_work','private:burimunsi_native_grant_commands','private:burimunsi_native_work_grants','private:burimunsi_native_lease_history'])
   if(actual.private_classes.filter(value=>value.name===name&&value.blocked===true).length!==1)fail('native_retention_catalog_incomplete');
  await owner.query('SELECT private._retention_manifest_schema_v2()');
  await admin.query('DROP INDEX storage.bucket_lifecycle_states_due_idx');
  try{let denied=false;try{await owner.query('SELECT private._retention_manifest_schema_v2()');}catch(e){denied=e.code==='42501'&&e.message==='retention_manifest_storage_lifecycle_shape_changed';}if(!denied)fail('lifecycle_drift_not_detected');}
  finally{await admin.query('SET ROLE supabase_storage_admin; CREATE INDEX bucket_lifecycle_states_due_idx ON storage.bucket_lifecycle_states USING btree (next_run_at, bucket_id) WHERE (next_run_at IS NOT NULL); RESET ROLE');}
  await owner.query('SELECT private._retention_manifest_schema_v2()');negativeChecks.push('post_install_storage_drift');
 }
 console.log(JSON.stringify({status:managedLifecycle?'synthetic_managed_chain_complete':'synthetic_partial_chain_complete',applied:done.length,forwardMigrations:textSubjects?1:0,total:union.length,skipped,observations,negativeChecks,retentionFunctionHashes:hashes,productionDispatch:false}));
});
if(replayFailed)process.exitCode=1;
