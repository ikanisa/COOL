import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN} from '../deployment-profile.js';
import {assertRuntimeDeployment} from '../deployment-database.js';

const profile={format:'collect.deployment.v1',id:'collect-production',mode:'managed',environment:'production',
 supabase_origin:MANAGED_SUPABASE_ORIGIN,
 member_api_origin:'https://api.collect.example',admin_origin:'https://admin.collect.example',
 public_origin:'https://collect.example',google_callback_origin:'https://api.collect.example'};
const env=(mode=profile.mode)=>{const raw=canonicalProfile({...profile,mode});return {COLLECT_DEPLOYMENT_PROFILE:raw,
 COLLECT_DEPLOYMENT_PROFILE_SHA256:createHash('sha256').update(raw).digest('hex')};};
function fake(rows=[{allowed:true}]){
 const calls=[];return {calls,async begin(fn){calls.push('begin');return fn(async(strings,...values)=>{
  const sql=strings.join('?');calls.push({sql,values});return sql.includes('collect_assert_deployment')?rows:[];
 });}};
}
test('legacy deployments without an explicit profile do not require an identity table',async()=>{
 const sql=fake();await assertRuntimeDeployment(sql,{});assert.deepEqual(sql.calls,[]);
});
test('Cloud profiles are matched against the immutable database identity',async()=>{
 const sql=fake(),input=env();await assertRuntimeDeployment(sql,input);
 assert.equal(sql.calls[0],'begin');assert.match(sql.calls[1].sql,/SET LOCAL ROLE collect_runtime/);
 assert.match(sql.calls[2].sql,/private\.collect_assert_deployment/);
 assert.deepEqual(sql.calls[2].values,[input.COLLECT_DEPLOYMENT_PROFILE_SHA256]);
});
test('a false, absent or ambiguous database assertion fails closed',async()=>{
 for(const rows of [[{allowed:false}],[],[{allowed:true},{allowed:true}]])await assert.rejects(assertRuntimeDeployment(fake(rows),env()),/deployment_identity_mismatch/);
});
test('an invalid profile digest fails before opening a database transaction',async()=>{
 const sql=fake();await assert.rejects(assertRuntimeDeployment(sql,{...env(),COLLECT_DEPLOYMENT_PROFILE_SHA256:'0'.repeat(64)}),/SHA256 mismatch/);
 assert.deepEqual(sql.calls,[]);
});

test('non-managed profiles are rejected before database work',async()=>{
 const sql=fake();await assert.rejects(assertRuntimeDeployment(sql,env('self_hosted')),/Invalid public deployment profile/);
 assert.deepEqual(sql.calls,[]);
});
