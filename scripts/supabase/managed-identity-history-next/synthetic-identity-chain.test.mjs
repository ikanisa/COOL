import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {withSyntheticIdentityChain} from './synthetic-identity-chain.mjs';
import {compileManagedBinderV1,preparePreimageV1,TRUST,PROJECT_REF} from '../managed-identity-managed-v1/provider-bind-v1.mjs';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
const hash=x=>createHash('sha256').update(x).digest('hex');
const base='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3',source='a'.repeat(64);
const query=await readFile(new URL('../managed-identity-managed-v1/preimage-query.sql',import.meta.url),'utf8');
const originalBinder=await readFile(new URL('../../../supabase/managed-deployment-identity/bind-managed.sql',import.meta.url),'utf8');
const identitySql=await readFile(new URL('../../../supabase/migrations/20261101013157_collect_deployment_identity.sql',import.meta.url),'utf8');
const profile=canonicalProfile({format:'collect.deployment.v1',id:'collect-managed-production',mode:'managed',environment:'production',
 supabase_origin:'https://rrlduytparvsjfmegalh.supabase.co',member_api_origin:'https://api.example.invalid',
 admin_origin:'https://admin.example.invalid',public_origin:'https://public.example.invalid',google_callback_origin:'https://admin.example.invalid'});
async function seed(owner,{unresolved=false}={}){
 const fence=randomUUID();await owner.query(`INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id)
  VALUES(true,'rrlduytparvsjfmegalh',$1,$2,1,'fenced',$3)`,[base,source,fence]);
 if(unresolved){await owner.query(`INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state,reason,external_dispatches,uncertain_dispatches,closed_at)
  VALUES($1,1,$2,'http_collect','settled','completed_with_unknown_obligation',1,1,clock_timestamp())`,[randomUUID(),source]);}
 return fence;
}
async function candidate(owner,fence){
 const observation=(await owner.query(query)).rows[0].preimage_observation;
 assert.equal(observation.history.count,18);assert.deepEqual([observation.history.fence,observation.history.archive,observation.history.identity],[true,true,true]);
 const preimage=preparePreimageV1({observation,project:PROJECT_REF,trust:TRUST});
 return compileManagedBinderV1({source:originalBinder,preimage,binding:{operationId:randomUUID(),profileRaw:profile,fenceOperationId:fence,fenceEpoch:1,fenceSourceSha256:source}});
}

test('full synthetic ordered predecessors, atomic identity history and managed binder',{timeout:180000},async t=>{
 await t.test('identity installation rolls back both DDL and history and refuses managed self-hosted binding',async()=>{
  await withSyntheticIdentityChain(async({owner,admin,watcher,backendPid,installArchive,capture,apply})=>{
   const fence=await seed(owner,{unresolved:true});await installArchive();const p=await capture();
   await admin.query("UPDATE supabase_migrations.schema_migrations SET name='drift' WHERE version='20261101012309'");
   await assert.rejects(capture(),/IDENTITY_HISTORY_MISMATCH/);
   await admin.query("UPDATE supabase_migrations.schema_migrations SET name='collect_admission_archive' WHERE version='20261101012309'");
   await admin.query('BEGIN');
   let pending;
   try{
    await admin.query('LOCK TABLE private.collect_fence_control IN ACCESS EXCLUSIVE MODE');
    await admin.query('ALTER FUNCTION private._collect_fence_resources() SECURITY INVOKER');
    pending=apply({expectedPreimageSha256:p.sha256}).then(()=>null,error=>error);
    let blocked=false,deadline=Date.now()+3500;
    while(Date.now()<deadline&&!blocked){blocked=(await watcher.query('SELECT cardinality(pg_blocking_pids($1))>0 b',[backendPid])).rows[0].b;if(!blocked)await new Promise(resolve=>setTimeout(resolve,25));}
    assert.equal(blocked,true);await admin.query('COMMIT');
    assert.match((await pending)?.message??'',/IDENTITY_PREIMAGE_CHANGED/);
   }finally{await admin.query('ROLLBACK').catch(()=>{});if(pending)await pending;}
   await admin.query('ALTER FUNCTION private._collect_fence_resources() SECURITY DEFINER');
   assert.equal((await capture()).sha256,p.sha256);
   for(const fault of ['after-body','after-history']){
    await assert.rejects(apply({expectedPreimageSha256:p.sha256,fault}),/SYNTHETIC_IDENTITY_FAIL/);
    assert.equal((await owner.query("SELECT to_regclass('private.collect_deployment_identity') IS NULL ok")).rows[0].ok,true);
    assert.equal((await owner.query("SELECT count(*)::int n FROM supabase_migrations.schema_migrations WHERE version='20261101013157'")).rows[0].n,0);
    assert.equal((await capture()).sha256,p.sha256);
   }
   await admin.query('ALTER FUNCTION private._collect_fence_resources() SECURITY INVOKER');
   await assert.rejects(apply({expectedPreimageSha256:p.sha256}),/IDENTITY_PREIMAGE_CHANGED/);
   await admin.query('ALTER FUNCTION private._collect_fence_resources() SECURITY DEFINER');
   await apply({expectedPreimageSha256:(await capture()).sha256});
   const row=(await owner.query("SELECT statements[1] sql FROM supabase_migrations.schema_migrations WHERE version='20261101013157'")).rows[0];
   assert.equal(row.sql,identitySql);
   await assert.rejects(owner.query('SELECT private.collect_bind_deployment($1,$2,$3)',[randomUUID(),profile,hash(profile)]),/deployment_profile_invalid/);
   const compiled=await candidate(owner,fence);assert.equal(compiled.receipt.productionDispatch,false);
   await assert.rejects(owner.query(compiled.sql),/managed_deployment_binding_requires_inactive_controller/);await owner.query('ROLLBACK');
   const check=(await owner.query(`SELECT (SELECT count(*)::int FROM private.collect_deployment_identity) identity_count,
    to_regprocedure('private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)') IS NULL binder_absent,
    (SELECT count(*)::int FROM private.collect_fence_admissions WHERE uncertain_dispatches>0) unknown_count`)).rows[0];
   assert.deepEqual(check,{identity_count:0,binder_absent:true,unknown_count:1});
  });
 });
 await t.test('on clean synthetic work the reviewed managed binder installs against genuine 18-position fixture history',async()=>{
  await withSyntheticIdentityChain(async({owner,installArchive,capture,apply})=>{
   const fence=await seed(owner),before=(await owner.query("SELECT to_jsonb(l) row FROM private.auth_principal_links l WHERE user_id='synthetic-primary'")).rows[0].row;
   await installArchive();await apply({expectedPreimageSha256:(await capture()).sha256});
   const compiled=await candidate(owner,fence);await owner.query(compiled.sql);
   const r=(await owner.query(`SELECT (SELECT count(*)::int FROM supabase_migrations.schema_migrations) history_count,
    (SELECT count(*)::int FROM private.collect_deployment_identity) identity_count,
    (SELECT to_jsonb(l) FROM private.auth_principal_links l WHERE user_id='synthetic-primary') primary_link,
    private.collect_assert_deployment($1) asserted`,[compiled.receipt.profileSha256])).rows[0];
   assert.equal(r.history_count,18);assert.equal(r.identity_count,1);assert.equal(r.asserted,true);assert.deepEqual(r.primary_link,before);
   await assert.rejects(capture(),/IDENTITY_HISTORY_MISMATCH|IDENTITY_PREDECESSOR_REFUSED/);
  });
 });
});
