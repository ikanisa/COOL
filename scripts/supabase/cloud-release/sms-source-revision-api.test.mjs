import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {createSmsSourceRevisionApi} from './sms-source-revision-api.mjs';
import {decodeAncillaryRegistration} from './ancillary-inventory.mjs';
import {reviseCoreWithSms} from './sms-source-revision-driver.mjs';
const hash=x=>createHash('sha256').update(x).digest('hex');
const oldSource='a'.repeat(64),newSource='b'.repeat(64),release='c'.repeat(64),project='rrlduytparvsjfmegalh';
const id='00000000-0000-4000-8000-000000000012';
const core=['collect-api','admin-api','collect-jobs'].map((slug,i)=>({slug,id:`00000000-0000-4000-8000-00000000000${i+1}`,
 version:1,status:'ACTIVE',verify_jwt:false,ezbr_sha256:'d'.repeat(64)}));
function fixture() {
 const side={slug:'collect-sms',id:'00000000-0000-4000-8000-000000000008',version:4,status:'ACTIVE',verify_jwt:false,
  ezbr_sha256:'e'.repeat(64),sourceSha256:'f'.repeat(64)};
 const proof=value=>{const bytes=Buffer.from(JSON.stringify({format:'collect.cloud-ancillary-inventory.v1',project,
  reviewedEvidenceSha256:'1'.repeat(64),functions:[value]}));return decodeAncillaryRegistration(bytes,hash(bytes));};
 const metadata=new Map(Object.entries({BUILD_SOURCE_ID:hash(oldSource),COLLECT_SMS_CORE_SOURCE_SHA256:hash(oldSource),
  COLLECT_SMS_RELEASE_SHA256:hash(release),COLLECT_SMS_ENABLED:hash('true'),COLLECT_SMS_DISPATCH_PAUSED:hash('false'),
  UNCHANGED_PROVIDER_POLICY:hash('policy')}));
 const state={side,registration:proof(side),core:structuredClone(core),writes:[],deploys:[],bump:false,
  control:{mode:'fenced',epoch:42,source_sha256:oldSource,operation_id:id,activeAdmissions:0,
   scheduler:{checked:true,coverageVerified:true,blocking:false}}};
 const row=()=>{const {sourceSha256,...r}=state.side;return r;};
 const request=async(path,options)=>{
  if(path==='functions')return {json:()=>[...structuredClone(state.core),row()]};
  if(path==='secrets'&&!options)return {json:()=>[...metadata].map(([name,value])=>({name,value}))};
  if(path==='secrets'){
   const writes=JSON.parse(options.body);state.writes.push(writes);
   for(const item of writes)metadata.set(item.name,hash(item.value));
   if(state.bump){state.side.version++;state.core.forEach(row=>row.version++);}
   return {status:201};
  }
  if(path.startsWith('functions/deploy?slug=')){state.deploys.push(path);const row=state.core.find(x=>x.slug===path.split('=')[1]);
   row.version++;row.ezbr_sha256=newSource;return {status:201,json:()=>({version:row.version})};}
  throw Error('unexpected_test_request');
 };
 const init={request,oldSource,newSource,gatewayReleaseSha256:release,oldEpoch:42,
  readFence:async()=>structuredClone(state.control),expectedFenceId:()=>id,withFenceLock:action=>action(),readRegistration:()=>state.registration,
  unchangedSecrets:{UNCHANGED_PROVIDER_POLICY:hash('policy')}};
 const api=createSmsSourceRevisionApi(init);
 const write={method:'POST',body:JSON.stringify([{name:'BUILD_SOURCE_ID',value:newSource}])};
 return {state,metadata,api,write,init,proof};
}

test('passes full inventory and binds both sources while dispatch remains unpaused',async()=>{
 const f=fixture();assert.equal((await f.api('functions')).json().length,4);
 await f.api('secrets',f.write);
 assert.deepEqual(f.state.writes,[[{name:'BUILD_SOURCE_ID',value:newSource},{name:'COLLECT_SMS_CORE_SOURCE_SHA256',value:newSource}]]);
 assert.equal(f.metadata.get('COLLECT_SMS_DISPATCH_PAUSED'),hash('false'));
 await f.api('functions/deploy?slug=collect-api',{method:'POST'});
 assert.equal(f.state.deploys.length,1);
 await assert.rejects(f.api('secrets',f.write),/sms_revision_write_invalid/);
 await assert.rejects(f.api('functions/deploy?slug=collect-sms',{method:'POST'}),/sms_revision_request_invalid/);
});

test('does not post before the exact stopped fence, gateway registration and flags are established',async()=>{
 for(const mutate of [f=>f.state.control.mode='open',f=>f.state.control.epoch++,f=>f.state.control.operation_id=randomUUID(),
  f=>f.state.control.activeAdmissions=1,f=>f.state.control.scheduler.blocking=true,
  f=>f.state.side.version++,f=>f.metadata.set('COLLECT_SMS_DISPATCH_PAUSED',hash('true')),
  f=>f.metadata.set('UNCHANGED_PROVIDER_POLICY',hash('changed')),
  f=>f.metadata.set('COLLECT_SMS_CORE_SOURCE_SHA256',hash(newSource))]){
   const f=fixture();mutate(f);await assert.rejects(f.api('secrets',f.write));assert.equal(f.state.writes.length,0);
 }
});

test('source mismatch or an uncertain write does not permit retry or deployment',async()=>{
 for(const mode of ['partial','timeout']){
  const f=fixture(),base=f.init.request;
  f.init.request=async(path,options)=>{
   if(path==='secrets'&&options?.method==='POST'){
    if(mode==='partial'){f.state.writes.push(JSON.parse(options.body));f.metadata.set('BUILD_SOURCE_ID',hash(newSource));return {status:201};}
    f.state.writes.push(JSON.parse(options.body));throw Error('provider_outcome_unknown');
   }
   return base(path,options);
  };
  const api=createSmsSourceRevisionApi(f.init);
  await assert.rejects(api('secrets',f.write));await assert.rejects(api('secrets',f.write),/sms_revision_write_invalid/);
  await assert.rejects(api('functions/deploy?slug=collect-api',{method:'POST'}));
  assert.equal(f.state.writes.length,1);assert.equal(f.state.deploys.length,0);
 }
});

test('a global secret version bump does not prevent the operator recording the source acknowledgement',async()=>{
 const f=fixture();f.state.bump=true;
 const result=await f.api('secrets',f.write);assert.equal(result.status,201);
 assert.equal(f.state.writes.length,1);assert.equal(f.state.side.version,5);
 // Exact integrated inventory validation blocks any core deployment until the
 // version-only provider preimage is requalified with its journal.
 await assert.rejects(f.api('functions/deploy?slug=collect-api',{method:'POST'}),/ancillary_inventory_changed/);
 assert.equal((await f.api('functions')).json().length,4);
 f.state.registration=f.proof(f.state.side);
 await f.api('functions/deploy?slug=collect-api',{method:'POST'});
 assert.equal(f.state.deploys.length,1);
});

test('refuses unrelated mutations and conflicting immutable secret claims',async()=>{
 const f=fixture();
 await assert.rejects(f.api('secrets',{method:'POST',body:JSON.stringify([{name:'COLLECT_SMS_DISPATCH_PAUSED',value:'true'}])}),/sms_revision_write_invalid/);
 assert.throws(()=>createSmsSourceRevisionApi({...f.init,unchangedSecrets:{COLLECT_SMS_DISPATCH_PAUSED:hash('true')}}),/sms_revision_input_invalid/);
 assert.throws(()=>createSmsSourceRevisionApi({...f.init,unchangedSecrets:{COLLECT_SMS_CORE_SOURCE_SHA256:hash(oldSource)}}),/sms_revision_input_invalid/);
 assert.equal(f.state.writes.length,0);
});


test('integrated revision journals paired source then resumes exact version-only proof without a second write',async()=>{
 const f=fixture(),records=new Map(),locks=[];f.state.bump=true;let transaction=false,locked=false;
 f.state.control.mode='open';f.state.control.operation_id='00000000-0000-4000-8000-000000000099';
 const before={mode:'open',epoch:42,source_sha256:oldSource};
 const db={async query(sql,args){
  if(sql.startsWith('SELECT mode,epoch,operation_id,source_sha256')||sql.startsWith('SELECT c.mode,c.epoch'))return {rows:[{...f.state.control}]};
  if(sql.startsWith('BEGIN')){assert.equal(transaction,false);transaction=true;locks.push('begin');return {rows:[]};}
  if(sql.startsWith('SET LOCAL lock_timeout')){assert.equal(transaction,true);locked=true;locks.push('advisory');return {rows:[]};}
  if(sql==='COMMIT'||sql==='ROLLBACK'){assert.equal(transaction,true);transaction=false;locked=false;locks.push(sql.toLowerCase());return {rows:[]};}
  if(sql.startsWith('SELECT count(*)::int n FROM private.collect_fence_admissions'))return {rows:[{n:0}]};
  if(sql==='SELECT private._collect_fence_scheduler_status() AS status')return {rows:[{status:f.state.control.scheduler}]};
  if(sql.startsWith('SELECT private.collect_fence_begin_quiesce')){f.state.control.mode='quiescing';f.state.control.operation_id=args[0];return {rows:[{v:{mode:'quiescing'}}]};}
  if(sql.startsWith('SELECT private.collect_fence_drain_v3')){f.state.control.mode='fenced';return {rows:[{v:{mode:'fenced'}}]};}
  if(sql.startsWith('SELECT private.collect_fence_upgrade_source_v3')){Object.assign(f.state.control,{mode:'fenced',epoch:43,source_sha256:newSource,operation_id:args[0]});return {rows:[]};}
  if(sql.startsWith('SELECT private.collect_fence_release_v3')){Object.assign(f.state.control,{mode:'open',epoch:44,source_sha256:newSource,operation_id:args[0]});return {rows:[]};}
  throw Error('unexpected_database_operation');
 },async end(){}};
 const deps={captureSnapshot:()=>({sourceSha:newSource,summary:()=>({sourceSha256:newSource}),makeForm:()=>({})}),
  check:()=>({status:'passed',sourceSha256:newSource}),open:async()=>db,readHistory:async()=>[],
  readRecord:name=>records.get(name)??null,readRegistration:()=>f.state.registration,
  save:(name,value)=>{assert(!records.has(name));records.set(name,structuredClone(value));}};
 const baseRequest=f.init.request;
 deps.api=async(path,options)=>{if(options?.method==='POST')assert(transaction&&locked);return baseRequest(path,options);};
 const evidence={passed:true,sourceSha256:newSource},immutable={UNCHANGED_PROVIDER_POLICY:hash('policy')};
 const settings={oldSource,newSource,oldEpoch:42,gatewayReleaseSha256:release,unchangedSecrets:immutable};
 await assert.rejects(reviseCoreWithSms({...settings,revision:{label:'sms-source-initial',testEvidence:evidence,expectedBefore:before,
  expectedFunctions:core,expectedSecretPreimages:immutable,requireChangedBundles:true}},deps),/runtime_revision_functions_changed/);
 assert.equal(f.state.control.mode,'fenced');assert.equal(f.state.writes.length,1);assert.equal(f.state.deploys.length,0);
 assert(records.has('revision-sms-source-initial-source-secret-attempt.json'));
 assert(records.has('revision-sms-source-initial-source-secret-complete.json'));
 assert.equal(f.metadata.get('COLLECT_SMS_DISPATCH_PAUSED'),hash('false'));
 f.state.registration=f.proof(f.state.side);
 const result=await reviseCoreWithSms({...settings,revision:{label:'sms-source-resumed',resumeFencedRevision:'sms-source-initial',
  acceptAncillaryRequalification:true,testEvidence:evidence,expectedSecretPreimages:immutable,requireChangedBundles:true}},deps);
 assert.equal(result.status,'revision_deployed_live');assert.equal(f.state.writes.length,1);
 assert.equal(f.state.deploys.length,3);assert.equal(f.metadata.get('COLLECT_SMS_DISPATCH_PAUSED'),hash('false'));
 assert.equal(f.state.control.mode,'open');assert.equal(f.state.control.source_sha256,newSource);
 assert.equal(locks.filter(x=>x==='advisory').length,4);assert.equal(locks.filter(x=>x==='commit').length,4);assert.equal(transaction,false);
 assert.equal(records.get('revision-sms-source-resumed-intent.json').ancillaryRequalification.sourceSecretAcknowledgedBy,'sms-source-initial');
});
