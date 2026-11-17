import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp,readFile,readdir,rm,stat,chmod} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {runPreflight,uniqueJson} from './preflight.mjs';
import authRef from '../managed-auth-archive/REFERENCE.json' with {type:'json'};
import storageRef from '../managed-storage-archive-v2/REFERENCE.json' with {type:'json'};

const pin=async()=>createHash('sha256').update(await readFile(new URL('./SOURCE-PINS.json',import.meta.url))).digest('hex');
const project={project_ref:'rrlduytparvsjfmegalh',organization_id:'ghnjnepwvwknswrwzepn',status:'ACTIVE_HEALTHY'};
const TOKEN='synthetic-token-never-send-to-provider';
const SECRET='synthetic-row-secret-must-not-be-persisted';
const environment=()=>({COLLECT_COMPONENT_PREFLIGHT_ACCESS_TOKEN:TOKEN});
async function directory(t){const path=await mkdtemp('/private/tmp/collect-component-preflight-');await chmod(path,0o700);t.after(()=>rm(path,{recursive:true,force:true}));return path;}
function payload(component,request){
 const isAuth=component==='auth',reference=isAuth?authRef:storageRef;
 const referenceHash=isAuth?'50e1fbcc6b1c97dab6d541fb2e342bdcb64b48efa5fc66a3757713d654b233d4':'38f477adf5aa3733af295a6c00893017f23ff6d253fe494ab554501660e11fbe';
 const identity={database:'postgres',server_version_num:'170011',read_only:'on',isolation:'repeatable read',row_security:'off',
  application_name:(isAuth?'collect.authmeta.':'collect.storagemeta.')+request.request_id.replaceAll('-',''),
  server_encoding:'UTF8',client_encoding:'UTF8',timezone:'UTC',backend_pid:'1234',snapshot:'10:10:',observed_at:'2026-11-14 10:00:00+00'};
 if(isAuth)return {format:'collect.managed-auth.counts.v1',request_id:request.request_id,project_ref:project.project_ref,
  reference_sha256:referenceHash,identity,tables:reference.relations.filter(x=>x.kind==='r').map(x=>({schema:'auth',name:x.name,rows:'0'})).sort((a,b)=>a.name.localeCompare(b.name)),
  total_rows:'0',exact_auth_row_counts_measured:true,auth_cell_values_returned:false,sequence_values_returned:false,capture_dispatched:false};
 return {format:'collect.managed-storage.counts.v1',request_id:request.request_id,project_ref:project.project_ref,reference_sha256:referenceHash,identity,
  tables:reference.relations.map(x=>({schema:'storage',name:x.name,rows:'0',rows_at_least:'0',exact:true})).sort((a,b)=>a.name.localeCompare(b.name)),
  total_rows:'0',within_row_caps:true,anonymous_bucket_count:'0',aggregates_measured:true,buckets:[],storage_identifiers_returned:false,
  metadata_bodies_returned:false,version_values_returned:false,object_bodies_read:false,capture_dispatched:false};
}
function fake(component,{wrongProject=false,changePayload,wireMutation,queryError}={}){
 const calls=[],bodies=[];
 return {calls,bodies,factory:({token,environment:env})=>{
  assert.equal(token,TOKEN);assert.equal(Object.hasOwn(env,'COLLECT_COMPONENT_PREFLIGHT_ACCESS_TOKEN'),false);
  return {async readProject(){calls.push('get');return wrongProject?{...project,project_ref:'different'}:project;},
   async query(request){calls.push('count');assert.equal(request.kind,'metadata');assert.equal(request.body.read_only,true);
    assert.match(request.body.query,/^BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;\n/);assert.ok(request.body.query.endsWith('\nROLLBACK;'));
    if(queryError)throw Error(SECRET);
    let data=payload(component,request);if(changePayload)data=changePayload(data)??data;
    let wire=JSON.stringify([{kind:data.format,payload:JSON.stringify(data)}]);if(wireMutation)wire=wireMutation(wire,data);
    const body=Buffer.from(wire);bodies.push(body);return {status:201,body};}};
 }};
}

test('count preflight validates both components and persists only private aggregate receipts',async t=>{
 const base=await directory(t);
 for(const component of ['auth','storage']){
  const f=fake(component),env=environment(),out=join(base,component);
  const result=await runPreflight({component,pinsSha256:await pin(),outputDirectory:out,environment:env,transportFactory:f.factory});
  assert.deepEqual(f.calls,['get','count']);assert.equal(result.status,'observed');assert.equal(result.metadata_only,true);assert.equal(result.real_data_capture,false);
  assert.equal(Object.hasOwn(env,'COLLECT_COMPONENT_PREFLIGHT_ACCESS_TOKEN'),false);assert.ok(f.bodies[0].every(x=>x===0));
  const names=(await readdir(out)).sort();assert.deepEqual(names,['COUNTS.json','INTENT.json','RESULT.json']);
  for(const name of names){const path=join(out,name),s=await stat(path),text=await readFile(path,'utf8');assert.equal(s.mode&0o777,0o600);
   assert.doesNotMatch(text,/synthetic-token-never-send|synthetic-row-secret|raw_sms|"access_token"\s*:|"refresh_token"\s*:/);}
  const countsBytes=await readFile(join(out,'COUNTS.json')),record=JSON.parse(await readFile(join(out,'RESULT.json'),'utf8'));
  assert.equal(record.counts_file_sha256,createHash('sha256').update(countsBytes).digest('hex'));assert.equal(record.total_rows,'0');
  assert.equal(record.native_rollback_command_complete_observed,false);assert.equal(record.full_recovery_acceptance,false);
 }
});

test('wrong project is rejected before any count query',async t=>{
 const base=await directory(t),f=fake('auth',{wrongProject:true});
 await assert.rejects(runPreflight({component:'auth',pinsSha256:await pin(),outputDirectory:join(base,'attempt'),environment:environment(),transportFactory:f.factory}),e=>e.code==='PROJECT_IDENTITY_INVALID');
 assert.deepEqual(f.calls,['get']);const failed=JSON.parse(await readFile(join(base,'attempt/FAILED.json'),'utf8'));assert.equal(failed.real_data_capture,false);assert.equal(failed.automatic_retry,false);
});

test('source pin, environment, token and output paths fail closed',async t=>{
 const base=await directory(t);let calls=0;const f=()=>{calls++;throw Error('unexpected');};
 await assert.rejects(runPreflight({component:'auth',pinsSha256:'0'.repeat(64),outputDirectory:join(base,'wrong-pin'),environment:environment(),transportFactory:f}),e=>e.code==='SOURCE_PIN_CHANGED');
 await assert.rejects(runPreflight({component:'auth',pinsSha256:await pin(),outputDirectory:join(base,'proxy'),environment:{...environment(),HTTPS_PROXY:'http://invalid'},transportFactory:f}),e=>e.code==='UNSAFE_ENVIRONMENT');
 await assert.rejects(runPreflight({component:'other',pinsSha256:await pin(),outputDirectory:join(base,'wrong-component'),environment:environment(),transportFactory:f}),e=>e.code==='COMPONENT_INVALID');
 await assert.rejects(runPreflight({component:'auth',pinsSha256:await pin(),outputDirectory:resolve('scripts/supabase/managed-component-refresh/not-allowed'),environment:environment(),transportFactory:f}),e=>e.code==='OUTPUT_PATH_INVALID');
 await assert.rejects(runPreflight({component:'auth',pinsSha256:await pin(),outputDirectory:join(base,'no-token'),environment:{},transportFactory:f}),e=>e.code==='TOKEN_INVALID');
 assert.equal(calls,0);assert.deepEqual((await readdir(base)).sort(),['no-token']);
});

test('fresh output cannot be reused and no request is retried',async t=>{
 const base=await directory(t),out=join(base,'attempt'),f=fake('storage');
 await runPreflight({component:'storage',pinsSha256:await pin(),outputDirectory:out,environment:environment(),transportFactory:f.factory});
 await assert.rejects(runPreflight({component:'storage',pinsSha256:await pin(),outputDirectory:out,environment:environment(),transportFactory:f.factory}));
 assert.deepEqual(f.calls,['get','count']);assert.equal((await readdir(out)).includes('FAILED.json'),false);
});

test('malformed or duplicate outer and nested JSON never produces a count receipt',async t=>{
 const base=await directory(t);
 const mutations=[
  wire=>wire.replace('"kind":','"kind":"hidden", "kind":'),
  (_wire,data)=>JSON.stringify([{kind:data.format,payload:JSON.stringify(data).replace('"capture_dispatched":false','"capture_dispatched":true,"capture_dispatched":false')}]),
  (_wire,data)=>{data.identity.hidden=SECRET;return JSON.stringify([{kind:data.format,payload:JSON.stringify(data)}]);},
 ];
 for(const [i,wireMutation] of mutations.entries()){
  const f=fake('auth',{wireMutation}),out=join(base,'case-'+i);
  await assert.rejects(runPreflight({component:'auth',pinsSha256:await pin(),outputDirectory:out,environment:environment(),transportFactory:f.factory}));
  assert.ok(f.bodies[0].every(x=>x===0));assert.deepEqual((await readdir(out)).sort(),['FAILED.json','INTENT.json']);
  assert.doesNotMatch(await readFile(join(out,'FAILED.json'),'utf8'),/synthetic-row-secret/);
 }
});

test('unknown transport errors are sanitized and count dispatch is not retried',async t=>{
 const base=await directory(t),f=fake('auth',{queryError:true}),out=join(base,'attempt');
 await assert.rejects(runPreflight({component:'auth',pinsSha256:await pin(),outputDirectory:out,environment:environment(),transportFactory:f.factory}));
 assert.deepEqual(f.calls,['get','count']);const failed=await readFile(join(out,'FAILED.json'),'utf8');assert.doesNotMatch(failed,/synthetic-row-secret/);assert.equal(JSON.parse(failed).code,'PREFLIGHT_UNCONFIRMED');
});

test('JSON duplicate detection includes escape-equivalent keys and enforces a depth bound',()=>{
 for(const text of ['{"a":1,"a":2}','{"a":1,"\\u0061":2}','{"outer":{"x":1,"x":2}}'])assert.throws(()=>uniqueJson(text),e=>e.code==='JSON_DUPLICATE_KEY');
 assert.throws(()=>uniqueJson('['.repeat(67)+'0'+']'.repeat(67)),e=>e.code==='JSON_DEPTH_EXCEEDED');
 for(const text of ['{"a":[1,true,null,{"b":"x"}]}','[{},[],"escaped\\ntext"]'])assert.doesNotThrow(()=>uniqueJson(text));
});
