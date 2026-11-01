import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {mkdtemp,writeFile,chmod,symlink,link,rm,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {emailDeployment,renderEmailSql,validateEmailReadiness,readEmailReadiness,runEmailOperation} from './email_jobs_operator.mjs';
const sha=value=>createHash('sha256').update(value).digest('hex');
const profile={format:'collect.deployment.v1',id:'email-test',mode:'self_hosted',environment:'qualification',supabase_origin:'https://db.example.invalid',member_api_origin:'https://api.example.invalid',admin_origin:'https://admin.example.invalid',public_origin:'https://www.example.invalid',google_callback_origin:'https://admin.example.invalid'};
const raw=JSON.stringify(Object.fromEntries(Object.keys(profile).sort().map(k=>[k,profile[k]])));
const env={COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:sha(raw)};
const readiness=()=>({format:'collect.email.readiness.v1',profile_sha256:sha(raw),endpoint:profile.supabase_origin+'/functions/v1/collect-email-jobs',
 source_sha256:'a'.repeat(64),deployment_sha256:'b'.repeat(64),runtime_evidence_sha256:'c'.repeat(64),provider_evidence_sha256:'d'.repeat(64),
 token_custody_evidence_sha256:'e'.repeat(64),copy_inventory_evidence_sha256:'f'.repeat(64),quota_evidence_sha256:'a'.repeat(64),verified_at:new Date().toISOString(),monthly_budget:100,
 email_admission:{contract:'collect.contribution-email.v1',source_sha256:'a'.repeat(64),approval_sha256:'b'.repeat(64),admitted_from:1793480000,batch_limit:1}});

test('renderer requires a canonical hashed self-hosted profile and installs no active/provider work',async()=>{
 assert.throws(()=>emailDeployment({}));
 assert.throws(()=>emailDeployment({...env,COLLECT_DEPLOYMENT_PROFILE_SHA256:'0'.repeat(64)}));
 assert.throws(()=>emailDeployment({...env,COLLECT_DEPLOYMENT_PROFILE:JSON.stringify(profile)}));
 const output=await renderEmailSql(env);assert(!/__EMAIL_|__PROFILE_|__ENDPOINT__/.test(output.sql));
 assert(output.sql.includes('active:=false'));assert(!/CREATE EXTENSION|vault\.create_secret/.test(output.sql));
 assert(output.sql.includes('private.collect_assert_deployment'));assert(output.sql.includes('private._collect_fence_scheduler_status'));
 assert.equal(output.sqlSha,sha(output.sql));assert.deepEqual(await renderEmailSql(env),output);
});
test('readiness refuses missing, widened, stale, cross-source and credential fields',()=>{
 const ready=readiness();assert.equal(validateEmailReadiness(ready,env),ready);
 for(const change of [{token:'forbidden'},{monthly_budget:0},{monthly_budget:10001},{verified_at:new Date(Date.now()-3601000).toISOString()},
  {endpoint:'https://sibling.example.invalid/functions/v1/collect-email-jobs'},
  {email_admission:{...ready.email_admission,batch_limit:2}},
  {email_admission:{...ready.email_admission,source_sha256:'f'.repeat(64)}},
  {email_admission:{...ready.email_admission,admitted_from:4102444800}},
  {email_admission:{...ready.email_admission,secret:'forbidden'}}])assert.throws(()=>validateEmailReadiness({...ready,...change},env));
});
test('readiness evidence is an owned independent private file with retained exact bytes',async()=>{
 const directory=await realpath(await mkdtemp(join(tmpdir(),'collect-email-readiness-'))),file=join(directory,'readiness.json'),bytes=JSON.stringify(readiness());
 try{
  await writeFile(file,bytes,{mode:0o600});const result=await readEmailReadiness(file,env);assert.equal(result.evidence_file_sha256,sha(bytes));
  await chmod(file,0o644);await assert.rejects(readEmailReadiness(file,env));await chmod(file,0o600);
  await symlink(file,join(directory,'symlink.json'));await assert.rejects(readEmailReadiness(join(directory,'symlink.json'),env));
  await link(file,join(directory,'hardlink.json'));await assert.rejects(readEmailReadiness(file,env));
 }finally{await rm(directory,{recursive:true,force:true});}
});
test('operator verifies exact owner and database identity before any lane operation',async()=>{
 const calls=[],sql={unsafe:async(text,values)=>{calls.push([text,values]);if(text.includes('current_user'))return [{current:'postgres',session:'postgres'}];if(text.includes('collect_assert_deployment'))return [{verified:true}];return [{value:{enabled:false}}];}};
 assert.deepEqual(await runEmailOperation('status',{sql,env}),{enabled:false});
 assert.equal(calls[1][1][0],sha(raw));assert(calls[2][0].includes('email_state'));
 let mutations=0;
 for(const wrong of ['owner','profile'])await assert.rejects(runEmailOperation('activate',{evidence:'a'.repeat(64),env,sql:{unsafe:async text=>{
  if(text.includes('current_user'))return [{current:wrong==='owner'?'collect_runtime':'postgres',session:'postgres'}];
  if(text.includes('collect_assert_deployment'))return [{verified:false}];mutations++;return [];
 }}}));
 assert.equal(mutations,0);
});
test('probe and unknown review require the retained original UUID and evidence',async()=>{
 const calls=[],id=randomUUID(),sql={unsafe:async(text,values)=>{if(text.includes('current_user'))return [{current:'postgres',session:'postgres'}];if(text.includes('collect_assert_deployment'))return [{verified:true}];calls.push([text,values]);return [{value:{dispatch_id:id,state:'awaiting'}}];}};
 await assert.rejects(runEmailOperation('probe',{sql,env}));await assert.rejects(runEmailOperation('review-unknown',{sql,env,id,evidence:'invalid'}));assert.equal(calls.length,0);
 await runEmailOperation('probe',{sql,env,id});assert.deepEqual(calls[0][1],[id]);
 await runEmailOperation('review-unknown',{sql,env,id,evidence:'d'.repeat(64)});assert.deepEqual(calls[1][1],[id,'d'.repeat(64)]);
});
