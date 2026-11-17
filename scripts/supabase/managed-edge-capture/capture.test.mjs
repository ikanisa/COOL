import test from 'node:test';
import assert from 'node:assert/strict';
import {createCipheriv,createDecipheriv,createHash,randomBytes,randomUUID} from 'node:crypto';
import {mkdtemp,mkdir,readFile,readdir,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {captureManaged,captureSynthetic,planDigest,cleanEnvironment} from './capture.mjs';
import {CaptureError,SLUGS,inspectSealedFunctionBodies} from './seal.mjs';

const sha=b=>createHash('sha256').update(b).digest('hex');
const denied=code=>e=>e instanceof CaptureError&&e.code===code;
function addForgedMetadata(archive,key){
 const headLen=Buffer.byteLength('COLLECTEDGE1')+1+36+64+12,header=archive.subarray(0,headLen),d=createDecipheriv('aes-256-gcm',key,header.subarray(headLen-12));
 d.setAAD(header);d.setAuthTag(archive.subarray(-16));const a=d.update(archive.subarray(headLen,-16)),b=d.final(),plain=Buffer.concat([a,b]);
 let metadata,changed;try{
  const n=plain.readUInt32BE(0),info=JSON.parse(plain.subarray(4,4+n).toString('utf8'));info.functions[0].unexpected='synthetic-source-secret';
  metadata=Buffer.from(JSON.stringify(info));const len=Buffer.alloc(4);len.writeUInt32BE(metadata.length);changed=Buffer.concat([len,metadata,plain.subarray(4+n)]);
  const iv=randomBytes(12),newHeader=Buffer.concat([header.subarray(0,headLen-12),iv]),c=createCipheriv('aes-256-gcm',key,iv);c.setAAD(newHeader);
  return Buffer.concat([newHeader,c.update(changed),c.final(),c.getAuthTag()]);
 }finally{a.fill(0);b.fill(0);plain.fill(0);metadata?.fill(0);changed?.fill(0);}
}
async function fixture(fn){const root=await mkdtemp('/private/tmp/collect-edge-capture-test-');const a=join(root,'archive'),k=join(root,'key');
 await mkdir(a,{mode:0o700});await mkdir(k,{mode:0o700});const plan={format:'collect.edge-capture.plan.v1',scope:'synthetic',operation_id:randomUUID(),archive_dir:a,key_dir:k,token_path:null};
 try{return await fn({root,a,k,plan});}finally{await rm(root,{recursive:true,force:true});}}
function mock({drift=false,badHash=false,noHash=false,wrongProject=false,removed=false,duplicateIds=false}={}){
 const bodies=SLUGS.map((slug,i)=>Buffer.from('synthetic-source-'+slug+'-'+i));let projectCalls=0,metaCalls=0;
 const metadata=slug=>{const i=SLUGS.indexOf(slug);return {slug,status:removed?'REMOVED':'ACTIVE',id:['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','cccccccc-cccc-4ccc-8ccc-cccccccccccc'][duplicateIds?0:i],
  version:drift&&metaCalls===2?2:1,updated_at:100+i,ezbr_sha256:noHash?null:badHash?'0'.repeat(64):sha(bodies[i])};};
 const transport={async project(){projectCalls++;return {id:'rrlduytparvsjfmegalh',ref:wrongProject?'different':'rrlduytparvsjfmegalh',organization_id:'ghnjnepwvwknswrwzepn',status:'ACTIVE_HEALTHY'};},
  async metadata(slug){metaCalls++;return metadata(slug);},async body(slug){return bodies[SLUGS.indexOf(slug)];}};
 return {transport,bodies,get projectCalls(){return projectCalls;}};
}

test('synthetic capture seals three opaque function bodies without writing source text',async()=>fixture(async f=>{
 const m=mock(),expected=m.bodies.map(sha),r=await captureSynthetic({plan:f.plan,expectedPlanSha256:planDigest(f.plan),transport:m.transport});
 assert.equal(r.scope,'synthetic');assert.equal(r.authenticated_readback,true);assert.equal(r.deployability_proven,false);assert.equal(r.coordinated_snapshot,false);
 assert.deepEqual(r.functions.map(x=>x.body_sha256),expected);assert.equal(m.projectCalls,1);assert(m.bodies.every(b=>b.every(x=>x===0)));
 const names=await readdir(f.a),blob=await readFile(join(f.a,f.plan.operation_id+'.edge.gcm')),key=await readFile(join(f.k,f.plan.operation_id+'.key'));
 assert.equal(key.length,32);assert(!blob.includes(Buffer.from('synthetic-source-')));assert(!blob.includes(key));
 const check={archive:blob,key,operationId:f.plan.operation_id,scope:'synthetic',planSha256:planDigest(f.plan)};
 assert.deepEqual(inspectSealedFunctionBodies(check).functions.map(x=>x.body_sha256),expected);
 assert.throws(()=>inspectSealedFunctionBodies({...check,key:randomBytes(32)}),denied('ARCHIVE_AUTHENTICATION_FAILED'));
 assert.throws(()=>inspectSealedFunctionBodies({...check,planSha256:'0'.repeat(64)}),denied('ARCHIVE_BINDING_MISMATCH'));
 const damaged=Buffer.from(blob);damaged[damaged.length-17]^=1;assert.throws(()=>inspectSealedFunctionBodies({...check,archive:damaged}),denied('ARCHIVE_AUTHENTICATION_FAILED'));damaged.fill(0);
 const forged=addForgedMetadata(blob,key);assert.throws(()=>inspectSealedFunctionBodies({...check,archive:forged}),denied('ARCHIVE_INVALID'));forged.fill(0);
 for(const name of names){const b=await readFile(join(f.a,name));assert(!b.includes(Buffer.from('synthetic-source-')));}
 key.fill(0);blob.fill(0);
 const replay=mock();await assert.rejects(captureSynthetic({plan:f.plan,expectedPlanSha256:planDigest(f.plan),transport:replay.transport}));assert.equal(replay.projectCalls,0);
}));
test('version drift, inactive functions, duplicate IDs or conflicting project identity cannot complete',async()=>{
 for(const [option,code] of [[{drift:true},'DEPLOYMENT_CHANGED'],[{wrongProject:true},'PROJECT_IDENTITY_INVALID'],[{removed:true},'METADATA_INVALID'],[{duplicateIds:true},'METADATA_INVALID']])await fixture(async f=>{
  await assert.rejects(captureSynthetic({plan:f.plan,expectedPlanSha256:planDigest(f.plan),transport:mock(option).transport}),denied(code));
  const outcome=JSON.parse(await readFile(join(f.a,'EDGE-CAPTURE-OUTCOME.json'),'utf8'));assert.equal(outcome.outcome,'UNCONFIRMED');
  assert(!(await readdir(f.a)).includes('EDGE-CAPTURE-RESULT.json'));
 });
});
test('provider upload digest remains separate from opaque response digest',async()=>{
 for(const [option,expected] of [[{badHash:true},false],[{noHash:true},null]])await fixture(async f=>{
  const r=await captureSynthetic({plan:f.plan,expectedPlanSha256:planDigest(f.plan),transport:mock(option).transport});
  assert(r.functions.every(x=>x.provider_digest_matches_body===expected));assert.equal(r.source_content_extracted,false);assert.equal(r.source_may_contain_sensitive_material,true);
 });
});
test('invalid plans and unsafe managed environment refuse before network or secret access',async()=>fixture(async f=>{
 const m=mock();await assert.rejects(captureSynthetic({plan:f.plan,expectedPlanSha256:'0'.repeat(64),transport:m.transport}),denied('PLAN_PIN_MISMATCH'));assert.equal(m.projectCalls,0);
 assert.deepEqual(await readdir(f.a),[]);assert.equal(cleanEnvironment({NODE_DEBUG:'https'},[]),false);assert.equal(cleanEnvironment({SSLKEYLOGFILE:'/tmp/x'},[]),false);
 const managed={...f.plan,scope:'managed',token_path:'/not/read/in/test'};const old=process.env.NODE_DEBUG;process.env.NODE_DEBUG='https';
 try{await assert.rejects(captureManaged({plan:managed,expectedPlanSha256:planDigest(managed)}),denied('MANAGED_CAPTURE_NOT_ENABLED'));}finally{if(old===undefined)delete process.env.NODE_DEBUG;else process.env.NODE_DEBUG=old;}
 await assert.rejects(captureManaged({plan:managed,expectedPlanSha256:planDigest(managed)}),denied('MANAGED_CAPTURE_NOT_ENABLED'));
 assert.deepEqual(await readdir(f.a),[]);
}));
