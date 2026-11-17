import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {mkdtemp,mkdir,readFile,readdir,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {captureManaged,captureSynthetic,planDigest} from './core.mjs';
import {fixtureTransport} from './fixture.mjs';
import {inspectSealedFunctionBodies} from './seal.mjs';
const sha=b=>createHash('sha256').update(b).digest('hex');
const pins=async()=>sha(await readFile(new URL('./LIVE-SOURCE-PINS.json',import.meta.url)));
const code=c=>e=>e?.code===c;
async function fixture(fn,operation=randomUUID()){
 const root=await mkdtemp('/private/tmp/collect-edge-capture-test-'),archive=join(root,'archive'),keys=join(root,'key');await mkdir(archive,{mode:0o700});await mkdir(keys,{mode:0o700});
 const plan={format:'collect.edge-capture.plan.v2',scope:'synthetic',operation_id:operation,archive_dir:archive,key_dir:keys,token_path:null,source_pins_sha256:await pins(),deadline_ms:30000,fixture:'normal'};
 try{return await fn({root,archive,keys,plan});}finally{await rm(root,{recursive:true,force:true});}
}
async function run(plan,behavior='normal'){
 const f=fixtureTransport(behavior,null),expected=f.bodies.map(sha),result=await captureSynthetic({plan,expectedPlanSha256:planDigest(plan),transport:f.transport,signal:null});return {result,expected,f};
}
test('synthetic capture authenticates opaque multipart bodies and all metadata hashes',async()=>fixture(async f=>{
 const {result,expected,f:transport}=await run(f.plan);assert.equal(result.recognized_multipart_envelope,true);assert.equal(result.source_content_extracted,false);
 assert.deepEqual(result.functions.map(x=>x.body_sha256),expected);assert(result.functions.every(x=>x.verify_jwt===true&&x.metadata_sha256.length===64&&!Object.hasOwn(x,'body_content_type')));assert(transport.bodies.every(b=>b.every(x=>x===0)));
 const archive=await readFile(join(f.archive,f.plan.operation_id+'.edge.gcm')),key=await readFile(join(f.keys,f.plan.operation_id+'.key'));
 const checked=inspectSealedFunctionBodies({archive,key,operationId:f.plan.operation_id,scope:'synthetic',planSha256:planDigest(f.plan)});assert.deepEqual(checked.functions.map(x=>x.body_sha256),expected);assert(checked.functions.every(x=>x.body_content_type==='multipart/form-data; boundary=fixture-boundary'));
 for(const file of await readdir(f.archive)){const bytes=await readFile(join(f.archive,file));assert(!bytes.includes(Buffer.from('synthetic-private-source-')));assert(!bytes.includes(Buffer.from('synthetic-canary')));}
 archive.fill(0);key.fill(0);const replay=fixtureTransport('normal',null);let called=false;const original=replay.transport.project;replay.transport.project=async()=>{called=true;return original();};
 await assert.rejects(captureSynthetic({plan:f.plan,expectedPlanSha256:planDigest(f.plan),transport:replay.transport,signal:null}));assert.equal(called,false);for(const b of replay.bodies)b.fill(0);
}));
test('unselected metadata drift and arbitrary JSON error bodies cannot complete',async()=>{
 for(const [behavior,expected] of [['metadata_drift','DEPLOYMENT_CHANGED'],['other_metadata_drift','DEPLOYMENT_CHANGED'],['numeric_precision_drift','DEPLOYMENT_CHANGED'],['error_body','UNSUPPORTED_PROVIDER_BODY'],['wrong_project','PROJECT_IDENTITY_INVALID']])await fixture(async f=>{
  const x=fixtureTransport(behavior,null);await assert.rejects(captureSynthetic({plan:f.plan,expectedPlanSha256:planDigest(f.plan),transport:x.transport,signal:null}),code(expected));
  assert.equal(JSON.parse(await readFile(join(f.archive,'EDGE-CAPTURE-OUTCOME.json'),'utf8')).outcome,'UNCONFIRMED');assert(!(await readdir(f.archive)).includes('EDGE-CAPTURE-RESULT.json'));for(const b of x.bodies)b.fill(0);
 });
});
test('claims are directory-scoped, and bad pins fail before any claim or credential read',async()=>{
 const op=randomUUID();await fixture(async a=>fixture(async b=>{
  await run(a.plan);await run(b.plan);assert.notEqual(planDigest(a.plan),planDigest(b.plan));
 },op),op);
 await fixture(async f=>{const bad={...f.plan,source_pins_sha256:'0'.repeat(64)};await assert.rejects(captureSynthetic({plan:bad,expectedPlanSha256:planDigest(bad),transport:fixtureTransport('normal',null).transport,signal:null}),code('SOURCE_PINS_REFUSED'));
  assert.deepEqual(await readdir(f.archive),[]);const managed={...f.plan,scope:'managed',fixture:null,token_path:'/not/read',source_pins_sha256:'0'.repeat(64)};
  await assert.rejects(captureManaged({plan:managed,expectedPlanSha256:planDigest(managed),signal:null}),code('SOURCE_PINS_REFUSED'));assert.deepEqual(await readdir(f.archive),[]);
 });
});
