import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {copyFile,mkdir,readFile,readdir,stat,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {assertUniqueJson} from './capture-json.mjs';
import {executeLive,executeSynthetic,exerciseTransportSynthetic,checkDispatchGate,checkReceiptAuthority,verifyLiveSources} from './capture-live.mjs';
import {makePlanSynthetic as makePlan} from './capture-plan.mjs';
import {syntheticPlan,syntheticWire,testDirectory} from './capture-fixtures.mjs';

const hash=x=>createHash('sha256').update(x).digest('hex');
const livePin=async()=>hash(await readFile(new URL('./LIVE-SOURCE-PINS.json',import.meta.url)));
const args=async(base,plan,component)=>({planPath:plan.plan_path,planSha256:plan.plan_sha256,pinsSha256:plan.pinsSha256,livePinsSha256:await livePin(),archiveDirectory:join(base,'archive-'+component),keyDirectory:join(base,'key-'+component)});
test('the live entry point refuses a closed technical gate before reading a plan or dispatching',async()=>{
 process.env.COLLECT_COMPONENT_CAPTURE_ACCESS_TOKEN='synthetic-token';
 await assert.rejects(executeLive({planPath:'/not-read'}),e=>e.code==='DISPATCH_GATE_CLOSED');
 assert.equal(Object.hasOwn(process.env,'COLLECT_COMPONENT_CAPTURE_ACCESS_TOKEN'),false);
 assert.throws(()=>checkDispatchGate('readonly'),e=>e.code==='DISPATCH_GATE_CLOSED');assert.doesNotThrow(()=>checkDispatchGate('READ_ONLY_CAPTURE'));
 await assert.rejects(verifyLiveSources('0'.repeat(64)),e=>e.code==='LIVE_SOURCE_CHANGED');
 const path='/Users/jeanbosco/Library/Application Support/Collect-Cloud-Recovery/production-metadata-20261113-122116/auth-count-refresh-20261114-001/RESULT.json';
 const digest='debcb294a3d6ac34fd674150e5cb8611431852d94073aac14c5db9cffd4ee93e';
 assert.doesNotThrow(()=>checkReceiptAuthority('auth',path,digest));assert.throws(()=>checkReceiptAuthority('auth',path+'.copy',digest),e=>e.code==='COUNT_AUTHORITY_INVALID');
});
test('even an open gate refuses a nonproduction count before any real socket or claim',async t=>{
 const base=await testDirectory(t),plan=await syntheticPlan(base,'auth'),opt=await args(base,plan,'auth');
 const child=spawnSync('/Volumes/PRO-G40/Development/Node/bin/node',[new URL('./capture-live-open-gate-fixture.mjs',import.meta.url).pathname,
  opt.planPath,opt.planSha256,opt.pinsSha256,opt.livePinsSha256,opt.archiveDirectory,opt.keyDirectory],
  {env:{PATH:'/usr/bin:/bin',COLLECT_COMPONENT_CAPTURE_ACCESS_TOKEN:'synthetic-test-token-never-used'},encoding:'utf8'});
 assert.equal(child.status,0,child.stderr);assert.match(child.stdout,/"network_calls":0/);
 assert.deepEqual((await readdir(join(base,'plan-auth'))).sort(),['CAPTURE-REQUEST.json','PLAN.json']);
 assert.equal((await readdir(join(base,'counts-auth'))).includes('CAPTURE-ONCE.json'),false);
});
test('both synthetic components encrypt, authenticate, journal and refuse replay',async t=>{
 const base=await testDirectory(t);
 for(const component of ['auth','storage']){
  const plan=await syntheticPlan(base,component),wire=await syntheticWire(plan,component),opt=await args(base,plan,component);
  const out=await executeSynthetic(opt,{wire});assert.equal(out.component,component);assert.equal(out.rows,1);assert.equal(out.tables,component==='auth'?27:10);
  assert.equal(out.provider_capture_dispatched,false);assert.equal(out.execution_mode,'synthetic');assert.equal(out.synthetic_response_used,true);assert.equal(out.full_recovery_acceptance,false);assert.equal(out.native_rollback_command_complete_observed,false);
  const receipt=JSON.parse(await readFile(join(opt.archiveDirectory,'RESULT.json'),'utf8'));assert.equal(receipt.authenticated_readback,true);assert.equal(receipt.full_recovery_acceptance,false);
  const synthetic=JSON.parse(await readFile(join(opt.archiveDirectory,'SYNTHETIC-ONLY.json'),'utf8'));assert.equal(synthetic.fixture,true);assert.equal(synthetic.provider_contacted,false);
  const anchor=JSON.parse(await readFile(join(base,'counts-'+component,'CAPTURE-ONCE.json'),'utf8'));assert.equal(anchor.execution_mode,'synthetic');assert.equal(anchor.plan_sha256,plan.plan_sha256);
  assert.equal(hash(await readFile(receipt.archive_path)),out.archive_sha256);assert.equal((await stat(receipt.archive_path)).mode&0o777,0o600);assert.equal((await stat(receipt.key_path)).mode&0o777,0o600);
  const archive=await readFile(receipt.archive_path,'utf8');assert.equal(archive.includes('synthetic-0'),false);
  const outcome=JSON.parse(await readFile(join(base,'plan-'+component,'OUTCOME.json'),'utf8'));assert.equal(outcome.outcome,'COMPLETED');assert.equal(outcome.transport_query_attempted,true);assert.equal(outcome.provider_query_attempted,false);assert.equal(outcome.execution_mode,'synthetic');
  await assert.rejects(executeSynthetic({...opt,archiveDirectory:join(base,'retry-archive-'+component),keyDirectory:join(base,'retry-key-'+component)},{wire}),e=>e.code==='EEXIST');
  assert.equal((await readdir(base)).includes('retry-archive-'+component),false);
 }
});
test('tampered request, bad plan hash and colliding output paths fail before claim',async t=>{
 const base=await testDirectory(t),plan=await syntheticPlan(base,'auth'),wire=await syntheticWire(plan,'auth'),opt=await args(base,plan,'auth');
 await assert.rejects(executeSynthetic({...opt,planSha256:'0'.repeat(64)},{wire}),e=>e.code==='PLAN_CHANGED');
 await assert.rejects(executeSynthetic({...opt,keyDirectory:opt.archiveDirectory},{wire}),e=>e.code==='OUTPUT_PATH_INVALID');
 const path=join(base,'plan-auth','CAPTURE-REQUEST.json'),request=await readFile(path);await writeFile(path,Buffer.concat([request,Buffer.from(' ')]));
 await assert.rejects(executeSynthetic(opt,{wire}),e=>e.code==='REQUEST_CHANGED');assert.deepEqual((await readdir(join(base,'plan-auth'))).sort(),['CAPTURE-REQUEST.json','PLAN.json']);
});
test('malformed wire is wiped and leaves unconfirmed outcome with no archive',async t=>{
 const base=await testDirectory(t),plan=await syntheticPlan(base,'storage'),opt=await args(base,plan,'storage');
 await assert.rejects(executeSynthetic(opt,{wire:'synthetic-secret-invalid-response'}));
 const outcome=JSON.parse(await readFile(join(base,'plan-storage','OUTCOME.json'),'utf8'));assert.equal(outcome.outcome,'REFUSED_OR_UNCONFIRMED');assert.equal(outcome.transport_query_attempted,true);assert.equal(outcome.provider_query_attempted,false);
 const files=await readdir(opt.archiveDirectory);assert.deepEqual(files.sort(),['INTENT.json','SYNTHETIC-ONLY.json']);assert.equal((await readFile(join(opt.archiveDirectory,'INTENT.json'),'utf8')).includes('synthetic-secret-invalid-response'),false);
 assert.deepEqual(await readdir(opt.keyDirectory),[]);
});
test('duplicate keys inside the nested capture payload fail before archive assembly',async t=>{
 const base=await testDirectory(t),plan=await syntheticPlan(base,'auth'),opt=await args(base,plan,'auth');
 const outer=JSON.parse(await syntheticWire(plan,'auth'));outer[0].payload=outer[0].payload.replace('"request_id":','"request_id":"spoof","request_id":');
 assert.throws(()=>assertUniqueJson(outer[0].payload),e=>e.code==='CAPTURE_JSON_DUPLICATE_KEY');
 // The underlying archive library intentionally maps foreign parser errors
 // to a generic capture error so no response value can leak into diagnostics.
 await assert.rejects(executeSynthetic(opt,{wire:JSON.stringify(outer)}),e=>e.code==='AUTH_CAPTURE_UNCONFIRMED');
 assert.deepEqual((await readdir(opt.archiveDirectory)).sort(),['INTENT.json','SYNTHETIC-ONLY.json']);
 const outcome=JSON.parse(await readFile(join(base,'plan-auth','OUTCOME.json'),'utf8'));assert.equal(outcome.outcome,'REFUSED_OR_UNCONFIRMED');assert.equal(outcome.provider_query_attempted,false);
});
test('one-use claim remains anchored to a count receipt even when a new plan is generated',async t=>{
 const base=await testDirectory(t),first=await syntheticPlan(base,'auth'),firstArgs=await args(base,first,'auth');
 const next=await makePlan({component:'auth',pinsSha256:first.pinsSha256,resultPath:first.pre.result_path,resultSha256:first.pre.result_sha256,outputDirectory:join(base,'plan-auth-copy'),environment:{}});
 const firstWire=await syntheticWire(first,'auth');await executeSynthetic(firstArgs,{wire:firstWire});
 const secondArgs={...await args(base,{...next,pinsSha256:first.pinsSha256},'auth'),archiveDirectory:join(base,'another-archive'),keyDirectory:join(base,'another-key')};
 await assert.rejects(executeSynthetic(secondArgs,{wire:await syntheticWire(next,'auth')}),e=>e.code==='EEXIST');
 assert.deepEqual((await readdir(join(base,'plan-auth-copy'))).sort(),['CAPTURE-REQUEST.json','PLAN.json']);
 assert.equal((await readdir(base)).includes('another-archive'),false);
});
test('synthetic execution cannot claim a receipt outside its own temporary root',async t=>{
 const first=await testDirectory(t),second=await testDirectory(t),plan=await syntheticPlan(first,'auth'),wire=await syntheticWire(plan,'auth');
 const moved=join(second,'plan-auth');await mkdir(moved,{mode:0o700});
 await copyFile(plan.plan_path,join(moved,'PLAN.json'));await copyFile(join(first,'plan-auth','CAPTURE-REQUEST.json'),join(moved,'CAPTURE-REQUEST.json'));
 const opt={...await args(second,plan,'auth'),planPath:join(moved,'PLAN.json')};
 await assert.rejects(executeSynthetic(opt,{wire}),e=>e.code==='SYNTHETIC_PATH_REQUIRED');
 assert.equal((await readdir(join(first,'counts-auth'))).includes('CAPTURE-ONCE.json'),false);
});
test('duplicate JSON keys, escaped duplicate keys and excessive nesting are refused',()=>{
 for(const s of ['{"a":1,"a":2}','{"a":1,"\\u0061":2}','{"outer":{"x":1,"x":2}}'])assert.throws(()=>assertUniqueJson(s),e=>e.code==='CAPTURE_JSON_DUPLICATE_KEY');
 assert.throws(()=>assertUniqueJson('['.repeat(67)+'0'+']'.repeat(67)),e=>e.code==='CAPTURE_JSON_DEPTH');assert.doesNotThrow(()=>assertUniqueJson('{"valid":[null,true,1]}'));
});
test('synthetic HTTPS path enforces identity, bounds, no redirect and clears owned buffers',async()=>{
 const project=JSON.stringify({ref:'rrlduytparvsjfmegalh',organization_id:'ghnjnepwvwknswrwzepn',status:'ACTIVE_HEALTHY'});
 const ok=await exerciseTransportSynthetic({chunks:[project.slice(0,20),project.slice(20)],headers:{'content-length':String(Buffer.byteLength(project))}});
 assert.equal(ok.status,'completed');assert.equal(ok.project_valid,true);assert.equal(ok.endpoint,'https://api.supabase.com/v1/projects/rrlduytparvsjfmegalh');assert.equal(ok.method,'GET');assert.equal(ok.tls_verified,true);assert.equal(ok.agent_disabled,true);assert.equal(ok.owned_chunks_wiped,true);
 const badProject=await exerciseTransportSynthetic({chunks:[project.replace('ACTIVE_HEALTHY','INACTIVE')]});assert.equal(badProject.code,'PROJECT_IDENTITY_INVALID');assert.equal(badProject.owned_chunks_wiped,true);
 for(const value of [{ref:'rrlduytparvsjfmegalh',id:'other-project'},{ref:'other-project',id:'rrlduytparvsjfmegalh'}]){
  const bad=JSON.stringify({...value,organization_id:'ghnjnepwvwknswrwzepn',status:'ACTIVE_HEALTHY'});
  const result=await exerciseTransportSynthetic({chunks:[bad]});assert.equal(result.code,'PROJECT_IDENTITY_INVALID');assert.equal(result.owned_chunks_wiped,true);
 }
 const idOnly=JSON.stringify({id:'rrlduytparvsjfmegalh',organization_id:'ghnjnepwvwknswrwzepn',status:'ACTIVE_HEALTHY'});
 assert.equal((await exerciseTransportSynthetic({chunks:[idOnly]})).status,'completed');
 const duplicate=await exerciseTransportSynthetic({chunks:[project.replace('"ref":','"ref":"wrong","ref":')]});assert.equal(duplicate.code,'CAPTURE_JSON_DUPLICATE_KEY');assert.equal(duplicate.owned_chunks_wiped,true);
 const post=await exerciseTransportSynthetic({kind:'query',chunks:['alpha','beta'],status:201});assert.equal(post.status,'completed');assert.equal(post.method,'POST');assert.equal(post.response_bytes,9);assert.equal(post.owned_chunks_wiped,true);assert.equal(post.outgoing_wiped,true);
 for(const [input,code] of [[{status:302},'REDIRECT_REFUSED'],[{status:403},'HTTP_STATUS_REFUSED'],[{chunks:['x'],headers:{'content-length':'2'}},'RESPONSE_LENGTH_CHANGED'],[{kind:'query',status:201,chunks:['x'.repeat(8*1024*1024+1)]},'RESPONSE_BOUND'],[{stall:true},'TRANSPORT_TIMEOUT']]){
  const result=await exerciseTransportSynthetic(input);assert.equal(result.code,code);assert.equal(result.owned_chunks_wiped,true);assert.equal(result.provider_contacted,false);
 }
 for(const [input,code] of [[{status:302,emitOnDestroy:true},'REDIRECT_REFUSED'],[{headers:{'content-length':'1048577'},emitOnDestroy:true},'RESPONSE_BOUND']]){
  const result=await exerciseTransportSynthetic(input);assert.equal(result.code,code);assert.equal(result.provider_contacted,false);
 }
});
