import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {createCloudBinderFixture,installCloudBinder,bindCloud,managedRaw,managedHash,managedProfile} from './cloud-binder-fixture.mjs';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
const hash=value=>createHash('sha256').update(value).digest('hex');
const withFixture=async run=>{const fixture=await createCloudBinderFixture();try{return await run(fixture);}finally{await fixture.db.close();}};
const identityCount=async f=>Number((await f.db.query('SELECT count(*) AS n FROM private.collect_deployment_identity')).rows[0].n);

test('empty historical identity installs the actual Cloud migration then binds the nominated managed profile once',()=>withFixture(async f=>{
 assert.equal(await identityCount(f),0);
 const fence=(await f.db.query('SELECT mode,epoch,project_ref FROM private.collect_fence_control')).rows[0];
 assert.deepEqual(fence,{mode:'fenced',epoch:1,project_ref:'rrlduytparvsjfmegalh'});
 const actions=(await f.db.query('SELECT action FROM private.collect_fence_operations')).rows.map(row=>row.action);
 assert.deepEqual(actions,['initialize','begin_quiesce','drain']);
 await installCloudBinder(f);assert.equal(await identityCount(f),0);
 assert.equal(await bindCloud(f),true);assert.equal(await bindCloud(f),true);
 const rows=(await f.db.query('SELECT operation_id,profile_raw,profile_sha256 FROM private.collect_deployment_identity')).rows;
 assert.deepEqual(rows,[{operation_id:f.operation,profile_raw:managedRaw,profile_sha256:managedHash}]);
 assert.equal((await f.db.query('SELECT private.collect_assert_deployment($1) AS ok',[managedHash])).rows[0].ok,true);
 await assert.rejects(bindCloud(f,{operation:randomUUID()}),/deployment_identity_already_bound/);
 await assert.rejects(f.db.query("UPDATE private.collect_deployment_identity SET profile_raw='changed'"),/deployment_identity_is_immutable/);
}));

test('Cloud migration refuses a nonempty predecessor identity, open fence or wrong project',async()=>{
 for(const setup of [
  f=>f.db.query('INSERT INTO private.collect_deployment_identity(operation_id,profile_raw,profile_sha256) VALUES($1,$2,$3)',[randomUUID(),managedRaw,managedHash]),
  f=>f.db.exec("UPDATE private.collect_fence_control SET mode='open'"),
  f=>f.db.exec("UPDATE private.collect_fence_control SET project_ref='another-project'"),
 ])await withFixture(async f=>{await setup(f);await assert.rejects(installCloudBinder(f),/cloud_binding_precondition/);});
});

test('Cloud migration refuses changed predecessor function bytes',()=>withFixture(async f=>{
 await f.db.exec("CREATE OR REPLACE FUNCTION private._collect_stopped_proof_total() RETURNS bigint LANGUAGE sql AS $$SELECT 0::bigint$$");
 await assert.rejects(installCloudBinder(f),/cloud_binding_function_preimage/);assert.equal(await identityCount(f),0);
}));

test('the binder refuses open or quiescing fence, blocked scheduler and mismatched project',()=>withFixture(async f=>{
 await installCloudBinder(f);
 for(const state of ['open','quiescing']){
  await f.db.query('UPDATE private.collect_fence_control SET mode=$1',[state]);
  await assert.rejects(bindCloud(f),/cloud_deployment_requires_inactive_controller/);assert.equal(await identityCount(f),0);
 }
 await f.db.exec("UPDATE private.collect_fence_control SET mode='fenced'; UPDATE synthetic_fixture.scheduler SET blocking=true");
 await assert.rejects(bindCloud(f),/cloud_deployment_requires_inactive_controller/);
 await f.db.exec("UPDATE synthetic_fixture.scheduler SET blocking=false; UPDATE private.collect_fence_control SET project_ref='another-project'");
 await assert.rejects(bindCloud(f),/cloud_deployment_requires_inactive_controller/);assert.equal(await identityCount(f),0);
}));

test('real predecessor drain keeps the synthetic fence quiescing while active work remains',()=>withFixture(async f=>{
 await installCloudBinder(f);
 const source='a'.repeat(64),operation=randomUUID(),admission=randomUUID();
 // Test-only reset of the synthetic state; no hosted controller is contacted.
 await f.db.exec("UPDATE private.collect_fence_control SET mode='open'");
 await f.db.query("INSERT INTO private.collect_fence_admissions VALUES($1,1,$2,'jobs','active')",[admission,source]);
 assert.equal((await f.db.query('SELECT private.collect_fence_begin_quiesce($1,1,$2) AS value',[operation,source])).rows[0].value.mode,'quiescing');
 assert.equal((await f.db.query('SELECT private.collect_fence_drain($1,1,$2) AS value',[operation,source])).rows[0].value.mode,'quiescing');
 await assert.rejects(bindCloud(f),/cloud_deployment_requires_inactive_controller/);
 await f.db.query("UPDATE private.collect_fence_admissions SET state='settled' WHERE admission_id=$1",[admission]);
 assert.equal((await f.db.query('SELECT private.collect_fence_drain($1,1,$2) AS value',[operation,source])).rows[0].value.mode,'fenced');
 assert.equal(await bindCloud(f),true);
}));

test('binder refuses unresolved work and does not create retirement or identity evidence',()=>withFixture(async f=>{
 await installCloudBinder(f);
 const admission=randomUUID(),source='a'.repeat(64);
 await f.db.query("INSERT INTO private.collect_fence_admissions VALUES($1,4,$2,'jobs','active')",[admission,source]);
 await assert.rejects(bindCloud(f),/cloud_deployment_requires_inactive_controller/);
 assert.equal(await identityCount(f),0);
 assert.equal(Number((await f.db.query('SELECT count(*) AS n FROM private.collect_managed_executor_retirements')).rows[0].n),0);
 assert.equal((await f.db.query('SELECT state FROM private.collect_fence_admissions WHERE admission_id=$1',[admission])).rows[0].state,'active');
}));

test('only the exact canonical production profile and digest can bind',()=>withFixture(async f=>{
 await installCloudBinder(f);
 const profiles=[{...managedProfile,mode:'self_hosted'},{...managedProfile,environment:'qualification'},
  {...managedProfile,supabase_origin:'https://another.example'},{...managedProfile,id:'another'}];
 for(const profile of profiles){const raw=canonicalProfile(profile);await assert.rejects(bindCloud(f,{raw,hash:hash(raw)}),/cloud_deployment_profile_refused/);}
 await assert.rejects(bindCloud(f,{hash:'0'.repeat(64)}),/cloud_deployment_profile_refused/);
 await assert.rejects(bindCloud(f,{raw:JSON.stringify(managedProfile),hash:hash(JSON.stringify(managedProfile))}),/cloud_deployment_profile_refused/);
 assert.equal(await identityCount(f),0);
}));

test('runtime has read-only assertion and cannot bind or mutate the deployment identity',()=>withFixture(async f=>{
 await installCloudBinder(f);await bindCloud(f);await f.db.exec('SET ROLE collect_runtime');
 try{
  assert.equal((await f.db.query('SELECT private.collect_assert_deployment($1) AS ok',[managedHash])).rows[0].ok,true);
  await assert.rejects(bindCloud(f),/permission denied/);
  await assert.rejects(f.db.query('SELECT * FROM private.collect_deployment_identity'),/permission denied/);
 }finally{await f.db.exec('RESET ROLE');}
}));
