import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,readdir,stat,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {assertUniqueJson} from './capture-json.mjs';
import {executeLive,executeSynthetic,exerciseTransportSynthetic} from './capture-runner.mjs';
import {syntheticPlan,syntheticWire,testDirectory} from './capture-fixtures.mjs';

const hash=x=>createHash('sha256').update(x).digest('hex');
const args=(base,plan,component)=>({planPath:plan.plan_path,planSha256:plan.plan_sha256,pinsSha256:plan.pinsSha256,archiveDirectory:join(base,'archive-'+component),keyDirectory:join(base,'key-'+component)});
test('hard-disabled live entry point refuses without reading a plan or dispatching',async()=>{
 process.env.COLLECT_COMPONENT_CAPTURE_ACCESS_TOKEN='synthetic-token';
 await assert.rejects(executeLive({planPath:'/not-read'}),e=>e.code==='LIVE_CAPTURE_DISABLED');
 assert.equal(Object.hasOwn(process.env,'COLLECT_COMPONENT_CAPTURE_ACCESS_TOKEN'),false);
});
test('both synthetic components encrypt, authenticate, journal and refuse replay',async t=>{
 const base=await testDirectory(t);
 for(const component of ['auth','storage']){
  const plan=await syntheticPlan(base,component),wire=await syntheticWire(plan,component),opt=args(base,plan,component);
  const out=await executeSynthetic(opt,{wire});assert.equal(out.component,component);assert.equal(out.rows,1);assert.equal(out.tables,component==='auth'?27:10);
  assert.equal(out.provider_capture_dispatched,false);assert.equal(out.execution_mode,'synthetic');assert.equal(out.synthetic_response_used,true);assert.equal(out.full_recovery_acceptance,false);assert.equal(out.native_rollback_command_complete_observed,false);
  const receipt=JSON.parse(await readFile(join(opt.archiveDirectory,'RESULT.json'),'utf8'));assert.equal(receipt.authenticated_readback,true);assert.equal(receipt.full_recovery_acceptance,false);
  assert.equal(hash(await readFile(receipt.archive_path)),out.archive_sha256);assert.equal((await stat(receipt.archive_path)).mode&0o777,0o600);assert.equal((await stat(receipt.key_path)).mode&0o777,0o600);
  const archive=await readFile(receipt.archive_path,'utf8');assert.equal(archive.includes('synthetic-0'),false);
  const outcome=JSON.parse(await readFile(join(base,'plan-'+component,'OUTCOME.json'),'utf8'));assert.equal(outcome.outcome,'COMPLETED');assert.equal(outcome.transport_query_attempted,true);assert.equal(outcome.provider_query_attempted,false);assert.equal(outcome.execution_mode,'synthetic');
  await assert.rejects(executeSynthetic({...opt,archiveDirectory:join(base,'retry-archive-'+component),keyDirectory:join(base,'retry-key-'+component)},{wire}),e=>e.code==='EEXIST');
  assert.equal((await readdir(base)).includes('retry-archive-'+component),false);
 }
});
test('tampered request, bad plan hash and colliding output paths fail before claim',async t=>{
 const base=await testDirectory(t),plan=await syntheticPlan(base,'auth'),wire=await syntheticWire(plan,'auth'),opt=args(base,plan,'auth');
 await assert.rejects(executeSynthetic({...opt,planSha256:'0'.repeat(64)},{wire}),e=>e.code==='PLAN_CHANGED');
 await assert.rejects(executeSynthetic({...opt,keyDirectory:opt.archiveDirectory},{wire}),e=>e.code==='OUTPUT_PATH_INVALID');
 const path=join(base,'plan-auth','CAPTURE-REQUEST.json'),request=await readFile(path);await writeFile(path,Buffer.concat([request,Buffer.from(' ')]));
 await assert.rejects(executeSynthetic(opt,{wire}),e=>e.code==='REQUEST_CHANGED');assert.deepEqual((await readdir(join(base,'plan-auth'))).sort(),['CAPTURE-REQUEST.json','PLAN.json']);
});
test('malformed wire is wiped and leaves unconfirmed outcome with no archive',async t=>{
 const base=await testDirectory(t),plan=await syntheticPlan(base,'storage'),opt=args(base,plan,'storage');
 await assert.rejects(executeSynthetic(opt,{wire:'synthetic-secret-invalid-response'}));
 const outcome=JSON.parse(await readFile(join(base,'plan-storage','OUTCOME.json'),'utf8'));assert.equal(outcome.outcome,'REFUSED_OR_UNCONFIRMED');assert.equal(outcome.transport_query_attempted,true);assert.equal(outcome.provider_query_attempted,false);
 const files=await readdir(opt.archiveDirectory);assert.deepEqual(files,['INTENT.json']);assert.equal((await readFile(join(opt.archiveDirectory,'INTENT.json'),'utf8')).includes('synthetic-secret-invalid-response'),false);
 assert.deepEqual(await readdir(opt.keyDirectory),[]);
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
 const duplicate=await exerciseTransportSynthetic({chunks:[project.replace('"ref":','"ref":"wrong","ref":')]});assert.equal(duplicate.code,'CAPTURE_JSON_DUPLICATE_KEY');assert.equal(duplicate.owned_chunks_wiped,true);
 const post=await exerciseTransportSynthetic({kind:'query',chunks:['alpha','beta'],status:201});assert.equal(post.status,'completed');assert.equal(post.method,'POST');assert.equal(post.response_bytes,9);assert.equal(post.owned_chunks_wiped,true);assert.equal(post.outgoing_wiped,true);
 for(const [input,code] of [[{status:302},'REDIRECT_REFUSED'],[{status:403},'HTTP_STATUS_REFUSED'],[{chunks:['x'],headers:{'content-length':'2'}},'RESPONSE_LENGTH_CHANGED'],[{kind:'query',status:201,chunks:['x'.repeat(8*1024*1024+1)]},'RESPONSE_BOUND'],[{stall:true},'TRANSPORT_TIMEOUT']]){
  const result=await exerciseTransportSynthetic(input);assert.equal(result.code,code);assert.equal(result.owned_chunks_wiped,true);assert.equal(result.provider_contacted,false);
 }
});
