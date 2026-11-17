// Isolated ports; no real account, SQL server, scheduler, key or provider.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {disableNative,rebindProvider,bindExistingKey,updateBudget,functions as qualifiedFunctions} from './native-source-rebind-operator.mjs';
const hash=x=>createHash('sha256').update(x).digest('hex');
const OLD='1'.repeat(64),NEW='2'.repeat(64),OLD_APPROVAL='3'.repeat(64),NEW_APPROVAL='4'.repeat(64),QUAL='5'.repeat(64);
const MODEL='synthetic-model',PROJECT='rrlduytparvsjfmegalh',KEY='6'.repeat(64),APIKEY='7'.repeat(64),USED='137';
const slugs=['collect-api','admin-api','collect-jobs'];
const functions=(bundle,version)=>slugs.map((slug,i)=>({slug,id:`00000000-0000-4000-8000-00000000000${i+1}`,
 status:'ACTIVE',version,verify_jwt:false,ezbr_sha256:bundle.repeat(64)}));
function fixture(){
 const files=new Map(),oldFunctions=functions('a',3),newFunctions=functions('b',4);
 const prior={format:'collect.native-sms.owner-approval.v1',project:PROJECT,sourceSha256:OLD,model:MODEL,
  providerUsedPreserved:'128',applicationLimit:400,applicationDeadline:null};
 const previous={sourceSha256:OLD,keySha256:KEY,vaultId:'00000000-0000-4000-8000-000000000004',operation:'synthetic-key-operation',functions:oldFunctions};
 const oldBudget={native_provider_source_sha256:OLD,native_provider_model_id:MODEL,native_provider_approval_sha256:OLD_APPROVAL,
  native_provider_used:USED,native_provider_limit:'400',native_provider_expires_at:null};
 const state={control:{mode:'open',epoch:28,source_sha256:OLD},enabled:false,active:false,pending:0,activeAdmissions:0,imported:37,
  schedule:'* * * * *',command:'SELECT collect_ops.tick_jobs();',operator:true,
  scheduler:{checked:true,coverageVerified:true,blocking:false},budget:{...oldBudget},keyCount:1,
  key:{id:previous.vaultId,digest:KEY,description:'collect.jobs.key.v1:'+previous.operation},keyEvidence:previous,functions:structuredClone(oldFunctions),
  secrets:{BUILD_SOURCE_ID:hash(OLD),BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:hash('true'),MOMO_AI_ENABLED:hash('true'),
   MOMO_AI_MODEL:hash(MODEL),COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256:hash(OLD_APPROVAL),
   COLLECT_JOB_AUTH_MODE:hash('supabase_dispatch_hmac_v1'),COLLECT_JOB_SIGNING_KEY:KEY,OPENAI_API_KEY:APIKEY}};
 const counters={api:0,updates:0,binds:0};
 const put=(name,value,digest='f'.repeat(64))=>files.set(name,{value:structuredClone(value),digest});
 put('previous.json',prior,OLD_APPROVAL);
 put('qualification.json',{project:PROJECT,sourceSha256:NEW,checked:{status:'passed',sourceSha256:NEW}},QUAL);
 put('approval.json',{format:'collect.native-sms.owner-approval.v1',project:PROJECT,sourceSha256:NEW,previousSourceSha256:OLD,
  model:MODEL,providerUsedPreserved:USED,applicationLimit:400,applicationDeadline:null,qualificationSha256:QUAL,scope:'New eligible observations'},NEW_APPROVAL);
 put('revision-intent.json',{before:{mode:'open',source_sha256:OLD,epoch:28},snapshot:{sourceSha256:NEW},
  checked:{status:'passed',sourceSha256:NEW},testEvidence:{passed:true,sourceSha256:NEW,evidenceSha256:QUAL}});
 put('revision-complete.json',{sourceSha256:NEW,epoch:30,functions:newFunctions});
 const io={read:(name,optional=false)=>{if(files.has(name))return structuredClone(files.get(name));if(optional)return null;throw Error('missing fixture evidence');},
  save:(name,value)=>{if(files.has(name))throw Error('duplicate fixture evidence');put(name,value);},
  state:async()=>structuredClone(state),snapshot:()=>({sourceSha:NEW}),check:()=>({status:'passed'}),
  api:async(path,options)=>{assert.equal(path,'secrets');counters.api++;for(const {name,value} of JSON.parse(options.body))state.secrets[name]=hash(value);return {status:201};},
  updateBudget:async(intent,approval)=>{counters.updates++;assert.equal(intent.budget.used,USED);
   state.budget.native_provider_source_sha256=NEW;state.budget.native_provider_approval_sha256=approval;},
  verifyDeployment:()=>{},guardStatus:async()=>{},bindKey:async()=>{counters.binds++;put('managed-jobs-key-source-'+NEW+'.json',
   {...previous,sourceSha256:NEW,keyChanged:false,functions:newFunctions});}};
 const disable=()=>disableNative({label:'fixture-revision',nextSource:NEW,previousApprovalName:'previous.json'},io);
 const rebind=()=>rebindProvider({label:'fixture-revision',approvalName:'approval.json',qualificationName:'qualification.json',
  revisionIntentName:'revision-intent.json',revisionCompleteName:'revision-complete.json'},io);
 const bind=()=>bindExistingKey({label:'fixture-revision',revisionIntentName:'revision-intent.json',revisionCompleteName:'revision-complete.json'},io);
 const revise=()=>{state.control={mode:'open',epoch:30,source_sha256:NEW};state.functions=newFunctions;state.secrets.BUILD_SOURCE_ID=hash(NEW);};
 return {state,io,files,counters,disable,rebind,bind,revise,put};
}

test('staged source revision preserves lifetime provider policy and binds the existing key',async()=>{
 const f=fixture();await f.disable();assert.equal(f.state.secrets.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED,hash('false'));
 assert.equal(f.counters.api,1);await f.disable();assert.equal(f.counters.api,1);
 f.revise();const result=await f.rebind();assert.equal(result.status,'provider_rebound_scheduler_inactive');
 assert.equal(f.state.budget.native_provider_source_sha256,NEW);assert.equal(f.state.budget.native_provider_approval_sha256,NEW_APPROVAL);
 assert.equal(f.state.budget.native_provider_used,USED);assert.equal(f.state.budget.native_provider_limit,'400');
 assert.equal(f.state.budget.native_provider_expires_at,null);assert.equal(f.state.budget.native_provider_model_id,MODEL);
 assert.equal(f.state.secrets.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256,hash(NEW_APPROVAL));
 await f.rebind();assert.equal(f.counters.updates,1);assert.equal(f.counters.api,2);
 await f.bind();await f.bind();assert.equal(f.counters.binds,1);assert.equal(f.state.enabled,false);assert.equal(f.state.active,false);
});

for(const [name,change] of [
 ['active scheduler',s=>s.active=true],['enabled scheduler',s=>s.enabled=true],['pending dispatch',s=>s.pending=1],
 ['active work',s=>s.activeAdmissions=1],['uncovered scheduler',s=>s.scheduler.coverageVerified=false],
 ['changed model',s=>s.budget.native_provider_model_id='changed'],['changed approval',s=>s.budget.native_provider_approval_sha256='9'.repeat(64)],
 ['changed limit',s=>s.budget.native_provider_limit='399'],['changed key',s=>s.key.digest='9'.repeat(64)],
 ['changed original bundle',s=>s.functions[0].ezbr_sha256='9'.repeat(64)],
])test('disable refuses '+name+' before touching a provider',async()=>{
 const f=fixture();change(f.state);await assert.rejects(f.disable());assert.equal(f.counters.api,0);assert.equal(f.files.has('native-source-rebind-fixture-revision-disable-intent.json'),false);
});

test('unacknowledged native disable is not sent a second time',async()=>{
 const f=fixture();const api=f.io.api;f.io.api=async(...args)=>{await api(...args);throw Error('lost reply');};
 await assert.rejects(f.disable(),/lost reply/);await assert.rejects(f.disable(),/rebind_disable_outcome_unknown/);
 assert.equal(f.counters.api,1);
});
test('pre-send drift leaves an unsent intent that can be safely resumed',async()=>{
 const f=fixture(),state=f.io.state;let calls=0;
 f.io.state=async(...args)=>{const result=await state(...args);if(++calls===2)result.active=true;return result;};
 await assert.rejects(f.disable(),/rebind_scheduler_not_drained/);
 assert.equal(f.counters.api,0);assert.equal(f.files.has('native-source-rebind-fixture-revision-disable-intent.json'),true);
 assert.equal(f.files.has('native-source-rebind-fixture-revision-disable-attempt.json'),false);
 await f.disable();assert.equal(f.counters.api,1);
});
test('an equal key recreated with a different Vault ID or operation cannot replace captured custody',async()=>{
 const change=s=>{s.key.id='00000000-0000-4000-8000-000000000099';s.key.description='collect.jobs.key.v1:replacement';
  s.keyEvidence.vaultId=s.key.id;s.keyEvidence.operation='replacement';};
 for(const phase of ['before-send','after-send','resume-complete']){
  const f=fixture();
  if(phase==='before-send'){
   const state=f.io.state;let calls=0;f.io.state=async(...args)=>{if(++calls===2)change(f.state);return state(...args);};
   await assert.rejects(f.disable(),/rebind_key_changed/);assert.equal(f.counters.api,0);
  }else if(phase==='after-send'){
   const api=f.io.api;f.io.api=async(...args)=>{const response=await api(...args);change(f.state);return response;};
   await assert.rejects(f.disable(),/rebind_key_changed/);assert.equal(f.counters.api,1);
   await assert.rejects(f.disable(),/rebind_key_changed/);assert.equal(f.counters.api,1);
  }else{
   await f.disable();change(f.state);await assert.rejects(f.disable(),/rebind_key_changed/);
  }
  assert.equal(f.files.has('native-source-rebind-fixture-revision-disable-complete.json'),phase==='resume-complete');
 }
});
test('acknowledged disable can finish readback only, without resending',async()=>{
 const f=fixture();const api=f.io.api;f.io.api=async(...args)=>{const r=await api(...args);f.state.pending=1;return r;};
 await assert.rejects(f.disable());assert.equal(f.counters.api,1);f.state.pending=0;
 await f.disable();assert.equal(f.counters.api,1);
});
test('counter drift after revision prevents provider rebinding',async()=>{
 const f=fixture();await f.disable();f.revise();f.state.budget.native_provider_used='138';
 await assert.rejects(f.rebind(),/rebind_provider_preimage_changed/);assert.equal(f.counters.updates,0);
});
test('unknown database commit is not automatically repeated',async()=>{
 const f=fixture();await f.disable();f.revise();const update=f.io.updateBudget;
 f.io.updateBudget=async(...args)=>{await update(...args);throw Error('commit reply lost');};
 await assert.rejects(f.rebind(),/commit reply lost/);await assert.rejects(f.rebind(),/rebind_provider_outcome_unknown/);
 assert.equal(f.counters.updates,1);assert.equal(f.counters.api,1);
});
test('unknown approval secret outcome is not automatically repeated',async()=>{
 const f=fixture();await f.disable();f.revise();const api=f.io.api;
 f.io.api=async(...args)=>{await api(...args);throw Error('approval reply lost');};
 await assert.rejects(f.rebind(),/approval reply lost/);await assert.rejects(f.rebind(),/rebind_approval_outcome_unknown/);
 assert.equal(f.counters.updates,1);assert.equal(f.counters.api,2);
});
test('source qualification, function and approval drift all prevent rebinding',async()=>{
 for(const kind of ['qualification','qualification-digest','approval','functions']){
  const f=fixture();await f.disable();f.revise();
  if(kind==='qualification')f.files.get('qualification.json').value.checked.sourceSha256=OLD;
  if(kind==='qualification-digest')f.files.get('revision-intent.json').value.testEvidence.evidenceSha256='8'.repeat(64);
  if(kind==='approval')f.files.get('approval.json').value.providerUsedPreserved='0';
  if(kind==='functions')f.state.functions[0].ezbr_sha256='9'.repeat(64);
  await assert.rejects(f.rebind());assert.equal(f.counters.updates,0);
 }
});
test('provider function inventory must contain exactly the expected three functions',()=>{
 const current=functions('b',4);assert.equal(qualifiedFunctions(current).length,3);
 assert.throws(()=>qualifiedFunctions([...current,{...current[0],slug:'unexpected'}]),/rebind_functions_changed/);
 assert.throws(()=>qualifiedFunctions([current[0],current[0],current[2]]),/rebind_functions_changed/);
});
test('key binding rechecks the complete provider budget and approval before and after binding',async()=>{
 for(const kind of ['before-counter','before-model','before-approval','after-counter','after-approval','after-function']){
  const f=fixture();await f.disable();f.revise();await f.rebind();
  if(kind==='before-counter')f.state.budget.native_provider_used='138';
  if(kind==='before-model')f.state.budget.native_provider_model_id='changed';
  if(kind==='before-approval')f.state.secrets.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256='9'.repeat(64);
  if(kind.startsWith('after-')){
   const bind=f.io.bindKey;f.io.bindKey=async(...args)=>{await bind(...args);
    if(kind==='after-counter')f.state.budget.native_provider_used='138';
    if(kind==='after-approval')f.state.secrets.COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256='9'.repeat(64);
    if(kind==='after-function')f.state.functions[0].ezbr_sha256='9'.repeat(64);
   };
  }
  await assert.rejects(f.bind());
  if(kind.startsWith('before-'))assert.equal(f.counters.binds,0);
  assert.equal(f.files.has('native-source-rebind-fixture-revision-key-complete.json'),false);
 }
});

test('CAS locks fence, scheduler and configuration in order without locking cron.job',async()=>{
 const queries=[],intent={epoch:28,oldSource:OLD,newSource:NEW,budget:{source:OLD,model:MODEL,approval:OLD_APPROVAL,
  used:USED,limit:'400',expires:null}};
 const base={singleton:true,enabled:false,cron_job_id:'42',native_provider_source_sha256:OLD,native_provider_model_id:MODEL,
  native_provider_approval_sha256:OLD_APPROVAL,native_provider_used:USED,native_provider_limit:'400',native_provider_expires_at:null,
  pending:0,active_admissions:0,scheduler:{checked:true,coverageVerified:true,blocking:false}};
 const db={query:async(sql)=>{queries.push(sql);
  if(sql.startsWith('SELECT mode,epoch'))return {rows:[{mode:'open',epoch:30,source_sha256:NEW}]};
  if(sql.includes('FROM collect_ops.jobs_config c WHERE'))return {rows:[base]};
  if(sql.startsWith('SELECT active,schedule,command FROM cron.job'))return {rows:[{active:false,schedule:'* * * * *',command:'SELECT collect_ops.tick_jobs();'}]};
  if(sql.startsWith('UPDATE collect_ops.jobs_config'))return {rows:[{...base,native_provider_source_sha256:NEW,native_provider_approval_sha256:NEW_APPROVAL}]};
  return {rows:[]};}};
 await updateBudget(db,intent,NEW_APPROVAL);
 const locks=queries.find(q=>q.includes('hashtextextended'));
 assert(locks.indexOf('collect_fence_assert_write')<locks.indexOf('collect.scheduler.'));
 assert(locks.indexOf('collect.scheduler.')<locks.indexOf('734636924058501'));
 assert(queries.findIndex(q=>q.includes('FOR UPDATE OF c'))<queries.findIndex(q=>q.includes('FROM cron.job')));
 assert(!queries.find(q=>q.includes('FROM cron.job')).includes('FOR UPDATE'));
 assert.equal(queries.at(-1),'COMMIT');
});
