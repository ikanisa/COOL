import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID,createHash} from 'node:crypto';
import {mkdtemp,readFile,realpath,rm,writeFile,chmod,readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {registerHooks} from 'node:module';
import {fileURLToPath} from 'node:url';
import {FORMAT,planDigest,transferObject,reconcileObject} from './transfer.mjs';
import {syntheticAdapters} from './synthetic-http.mjs';

const h=v=>createHash('sha256').update(v).digest('hex'),hash=x=>x.repeat(64);
async function fixture(){
 const root=await mkdtemp(join(await realpath(tmpdir()),'collect-object-transfer-')),key=randomBytes(32),bytes=Buffer.from('synthetic protected ciphertext');
 const p={format:FORMAT,operation_id:randomUUID(),mode:'synthetic',
  source:{origin:'http://127.0.0.1:32101',bucket:'private-source',key:'synthetic/source-item',object_id:'source-object',version:'source-version',etag:'source-etag',bytes:bytes.length,ciphertext_sha256:h(bytes),namespace_sha256:hash('a'),binding_sha256:hash('b'),key_aad_sha256:hash('c')},
  target:{origin:'http://127.0.0.1:32102',bucket:'private-target',key:'synthetic/target-item',namespace_sha256:hash('d'),key_aad_sha256:hash('c')},
  authority:{source_identity_sha256:hash('e'),target_identity_sha256:hash('f'),source_fence_sha256:hash('1'),target_fence_sha256:hash('2'),mapping_sha256:hash('3')}};
 let original={...p.source,identity_sha256:p.authority.source_identity_sha256,fence_sha256:p.authority.source_fence_sha256},stored=null,mode='normal',reads=0,inspects=0,puts=0;
 const base=()=>({origin:p.target.origin,bucket:p.target.bucket,key:p.target.key,identity_sha256:p.authority.target_identity_sha256,fence_sha256:p.authority.target_fence_sha256,namespace_sha256:p.target.namespace_sha256,private_bucket:true});
 const source={async read({signal}){assert.equal(signal.aborted,false);reads++;return {...original,body:Buffer.from(bytes)};},async inspect(){return {...original};}};
 const target={async inspect(){inspects++;return stored?{...base(),state:'present',object_id:'target-object',version:'target-version',etag:'target-etag',body:Buffer.from(stored)}:{...base(),state:'absent',absence_verified:true};},
  async createOnly(data,{signal}){puts++;assert.equal(signal.aborted,false);if(stored)return {accepted:false};if(mode==='timeout')return new Promise(()=>{});stored=Buffer.from(data);if(mode==='lost')throw Error('synthetic private lost ACK');return {accepted:true};}};
 const args=()=>({plan:p,expectedPlanSha256:planDigest(p),journalRoot:root,journalKey:key,source,target,requestMs:1000});
 return {root,key,bytes,p,source,target,args,counts:()=>({reads,inspects,puts}),setMode:v=>{mode=v},mutateSource:(k,v)=>{original={...original,[k]:v}},seed:v=>{stored=Buffer.from(v)},getStored:()=>stored&&Buffer.from(stored),cleanup:async()=>{key.fill(0);bytes.fill(0);await chmod(join(root,p.operation_id),0o700).catch(()=>{});await rm(root,{recursive:true,force:true});}};
}
async function using(fn){const f=await fixture();try{await fn(f);}finally{await f.cleanup();}}

test('exact immutable ciphertext is copied once with encrypted durable intent and receipt',()=>using(async f=>{
 const result=await transferObject(f.args());assert.equal(result.status,'content_verified');assert.equal(result.application_metadata_committed,false);assert.equal(result.production_cutover_authorized,false);
 assert.deepEqual(f.getStored(),f.bytes);assert.equal(f.counts().puts,1);
 const dir=join(f.root,f.p.operation_id);assert.deepEqual((await readdir(dir)).sort(),['attempt.enc','intent.enc','outcome.enc']);
 for(const file of await readdir(dir)){const text=(await readFile(join(dir,file))).toString();assert.equal(text.includes(f.p.source.key),false);assert.equal(text.includes(f.p.target.key),false);assert.equal(text.includes(f.bytes.toString()),false);}
 assert.equal((await transferObject(f.args())).status,'reconcile_required');assert.equal(f.counts().puts,1);
 assert.equal((await reconcileObject(f.args())).status,'matching_content_at_readback');
 assert.equal((await reconcileObject({...f.args(),source:{inspect:f.source.inspect},target:{inspect:f.target.inspect}})).status,'matching_content_at_readback');
}));
test('changed source identity, version, ciphertext or target fence refuses before dispatch',async()=>{
 for(const [field,value] of [['version','changed'],['identity_sha256',hash('9')],['ciphertext_sha256',hash('0')]])await using(async f=>{f.mutateSource(field,value);const r=await transferObject(f.args());assert.equal(r.status,'refused_before_dispatch');assert.equal(f.counts().puts,0);});
 await using(async f=>{const original=f.target.inspect;f.target.inspect=async()=>({...await original(),fence_sha256:hash('9')});assert.equal((await transferObject(f.args())).status,'refused_before_dispatch');assert.equal(f.counts().puts,0);});
});
test('preexisting target, including matching bytes, is never overwritten or attributed',()=>using(async f=>{
 f.seed(f.bytes);const r=await transferObject(f.args());assert.equal(r.status,'preexisting_conflict');assert.equal(f.counts().puts,0);assert.deepEqual(f.getStored(),f.bytes);
 assert.equal((await reconcileObject(f.args())).status,'reconciliation_unconfirmed');
}));
test('present target requires complete matching authority metadata before conflict classification',async()=>{
 await using(async f=>{
  f.target.inspect=async()=>({state:'present'});
  const r=await transferObject(f.args());assert.equal(r.status,'refused_before_dispatch');assert.notEqual(r.status,'preexisting_conflict');assert.equal(f.counts().puts,0);
 });
 await using(async f=>{
  f.seed(Buffer.from('other synthetic content'));const inspect=f.target.inspect;
  f.target.inspect=async()=>({...await inspect(),identity_sha256:hash('9')});
  const r=await transferObject(f.args());assert.equal(r.status,'refused_before_dispatch');assert.notEqual(r.status,'preexisting_conflict');assert.equal(f.counts().puts,0);
 });
 await using(async f=>{
  f.seed(Buffer.from('other synthetic content'));const r=await transferObject(f.args());
  assert.equal(r.status,'preexisting_conflict');assert.equal(f.counts().puts,0);
 });
});
test('lost acknowledgement is quarantined; readback matching content does not attribute the write',()=>using(async f=>{
 f.setMode('lost');assert.equal((await transferObject(f.args())).status,'dispatch_unconfirmed');const readback=await reconcileObject(f.args());
 assert.equal(readback.status,'matching_content_at_readback');assert.equal(readback.creation_attribution_verified,false);assert.equal(readback.retry_authorized,false);
 assert.equal((await transferObject(f.args())).status,'reconcile_required');assert.equal(f.counts().puts,1);
}));
test('timed-out send and absent readback never authorize a retry',()=>using(async f=>{
 f.setMode('timeout');assert.equal((await transferObject({...f.args(),requestMs:20})).status,'dispatch_unconfirmed');
 const r=await reconcileObject(f.args());assert.equal(r.status,'absent_at_readback');assert.equal(r.retry_authorized,false);
 assert.equal((await transferObject(f.args())).status,'reconcile_required');assert.equal(f.counts().puts,1);
}));
test('a send completing after timeout receives intact original bytes and remains unconfirmed',()=>using(async f=>{
 let captured;const original=f.target.createOnly;
 f.target.createOnly=async(data)=>{await new Promise(resolve=>setTimeout(resolve,45));captured=Buffer.from(data);return original(data,{signal:new AbortController().signal});};
 assert.equal((await transferObject({...f.args(),requestMs:10})).status,'dispatch_unconfirmed');
 await new Promise(resolve=>setTimeout(resolve,80));assert.deepEqual(captured,f.bytes);
 assert.equal((await reconcileObject(f.args())).status,'matching_content_at_readback');
}));
test('concurrent calls using the same operation cannot dispatch twice',()=>using(async f=>{
 const [a,b]=await Promise.all([transferObject(f.args()),transferObject(f.args())]);assert.deepEqual([a.status,b.status].sort(),['content_verified','reconcile_required']);assert.equal(f.counts().puts,1);
}));
test('independent operation IDs racing for one key cannot overwrite each other',()=>using(async f=>{
 const second={...f.p,operation_id:randomUUID()},args={...f.args(),plan:second,expectedPlanSha256:planDigest(second)};
 const [a,b]=await Promise.all([transferObject(f.args()),transferObject(args)]);assert.equal([a,b].filter(v=>v.status==='content_verified').length,1);
 assert.equal([a,b].filter(v=>['preexisting_conflict','dispatch_unconfirmed'].includes(v.status)).length,1);assert.deepEqual(f.getStored(),f.bytes);
}));
test('wrong reviewed plan, key/AAD assertion, or synthetic endpoint is refused without adapter calls',()=>using(async f=>{
 for(const edit of [p=>p.source.version='changed',p=>p.target.key_aad_sha256=hash('0'),p=>p.target.origin='https://external.invalid']){
  const changed=structuredClone(f.p);edit(changed);const r=await transferObject({...f.args(),plan:changed});assert.equal(r.status,'refused');
 }
 assert.deepEqual(f.counts(),{reads:0,inspects:0,puts:0});
}));
test('managed transfer remains hard-closed before journal or provider access',()=>using(async f=>{
 const plan=structuredClone(f.p);plan.mode='managed';plan.source.origin='https://source.example';plan.target.origin='https://rrlduytparvsjfmegalh.supabase.co';
 const outcome=await transferObject({...f.args(),plan,expectedPlanSha256:planDigest(plan)});
 assert.equal(outcome.status,'refused');assert.equal(outcome.code,'managed_adapter_unqualified');assert.deepEqual(f.counts(),{reads:0,inspects:0,puts:0});assert.deepEqual(await readdir(f.root),[]);
 const poison=new Proxy({},{get(){throw Error('adapter must not be touched');}});
 assert.equal((await transferObject({...f.args(),plan,expectedPlanSha256:planDigest(plan),source:poison,target:poison})).code,'managed_adapter_unqualified');
 const readback=await reconcileObject({...f.args(),plan,expectedPlanSha256:planDigest(plan),source:poison,target:poison});
 assert.equal(readback.status,'reconciliation_unconfirmed');assert.equal(readback.code,'managed_adapter_unqualified');assert.equal(readback.retry_authorized,false);assert.deepEqual(await readdir(f.root),[]);
}));
test('oversized plans, accessors and proxied observations refuse without invoking accessors',async()=>{
 await using(async f=>{
  const plan=structuredClone(f.p);plan.source.key='a'.repeat(40000);assert.throws(()=>planDigest(plan),/invalid_plan/);
  let invoked=0;const bad=structuredClone(f.p);Object.defineProperty(bad.source,'key',{enumerable:true,get(){invoked++;return 'secret';}});
  assert.throws(()=>planDigest(bad),/invalid_plan/);assert.equal(invoked,0);assert.deepEqual(f.counts(),{reads:0,inspects:0,puts:0});
 });
 await using(async f=>{
  let invoked=0;const inspect=f.target.inspect;f.target.inspect=async()=>{const record=await inspect();Object.defineProperty(record,'state',{enumerable:true,get(){invoked++;return 'absent';}});return record;};
  assert.equal((await transferObject(f.args())).status,'refused_before_dispatch');assert.equal(invoked,0);assert.equal(f.counts().puts,0);
 });
 await using(async f=>{
  const read=f.source.read;f.source.read=async(...args)=>new Proxy(await read(...args),{});
  assert.equal((await transferObject(f.args())).status,'refused_before_dispatch');assert.equal(f.counts().puts,0);
 });
});
test('tampered or wrong-key journal cannot trigger reconciliation network access',()=>using(async f=>{
 f.setMode('lost');assert.equal((await transferObject(f.args())).status,'dispatch_unconfirmed');const before=f.counts();
 assert.equal((await reconcileObject({...f.args(),journalKey:randomBytes(32)})).status,'reconciliation_unconfirmed');assert.deepEqual(f.counts(),before);
 const path=join(f.root,f.p.operation_id,'intent.enc');const b=await readFile(path);b[b.length-3]^=1;await writeFile(path,b,{mode:0o600});
 assert.equal((await reconcileObject(f.args())).status,'reconciliation_unconfirmed');assert.deepEqual(f.counts(),before);
}));
test('decrypted journal buffers are wiped on successful and failed GCM authentication',()=>using(async f=>{
 const moduleURL=new URL('./transfer.mjs?plaintext-buffer-regression',import.meta.url).href;
 const source=`import * as c from 'node:crypto';
  export const createCipheriv=c.createCipheriv,createHash=c.createHash,randomBytes=c.randomBytes,timingSafeEqual=c.timingSafeEqual;
  export function createDecipheriv(...args){const d=c.createDecipheriv(...args),update=d.update.bind(d),final=d.final.bind(d);
   d.update=(...a)=>{const out=update(...a);globalThis.__collectObjectPlaintextBuffers.push({part:'update',buffer:out});return out;};
   d.final=(...a)=>{const out=final(...a);globalThis.__collectObjectPlaintextBuffers.push({part:'final',buffer:out});return out;};return d;}`;
 const hook=registerHooks({resolve(specifier,context,next){if(context.parentURL===moduleURL&&specifier==='node:crypto')return {url:'data:text/javascript,'+encodeURIComponent(source),shortCircuit:true};return next(specifier,context);}});
 const traces=[];globalThis.__collectObjectPlaintextBuffers=traces;
 try{
  const tested=await import(moduleURL);assert.equal((await tested.transferObject(f.args())).status,'content_verified');
  assert.equal((await tested.reconcileObject(f.args())).status,'matching_content_at_readback');
  assert.ok(traces.filter(x=>x.part==='update'&&x.buffer.length>0).length>=2);
  assert.ok(traces.some(x=>x.part==='final'));
  for(const {buffer} of traces)assert.ok(buffer.every(byte=>byte===0),'successful decryption buffer retained plaintext');
  traces.length=0;
  const path=join(f.root,f.p.operation_id,'intent.enc'),envelope=JSON.parse(await readFile(path,'utf8')),tag=Buffer.from(envelope.tag,'base64url');
  tag[0]^=1;envelope.tag=tag.toString('base64url');await writeFile(path,JSON.stringify(Object.fromEntries(Object.entries(envelope).sort(([a],[b])=>a.localeCompare(b)))),{mode:0o600});
  assert.equal((await tested.reconcileObject(f.args())).status,'reconciliation_unconfirmed');
  assert.ok(traces.some(x=>x.part==='update'&&x.buffer.length>0));
  for(const {buffer} of traces)assert.ok(buffer.every(byte=>byte===0),'failed authentication buffer retained plaintext');
 }finally{hook.deregister();delete globalThis.__collectObjectPlaintextBuffers;}
}));
test('lost journal write before a send cannot dispatch',()=>using(async f=>{
 const original=f.target.inspect;f.target.inspect=async()=>{const observed=await original();await chmod(join(f.root,f.p.operation_id),0o500);return observed;};
 const r=await transferObject(f.args());assert.equal(r.status,'journal_unconfirmed');assert.equal(f.counts().puts,0);
}));
test('post-dispatch changed bytes or lost verification cannot be called success',async()=>{
 await using(async f=>{const original=f.target.createOnly;f.target.createOnly=async(...a)=>{const r=await original(...a);f.seed(Buffer.from('changed'));return r;};
  assert.equal((await transferObject(f.args())).status,'dispatch_unconfirmed');assert.equal((await reconcileObject(f.args())).status,'reconciliation_unconfirmed');});
 await using(async f=>{const original=f.target.createOnly;f.target.createOnly=async(...a)=>{const r=await original(...a);f.mutateSource('version','changed');return r;};
  assert.equal((await transferObject(f.args())).status,'dispatch_unconfirmed');});
});
test('process death after a real loopback upload reconciles without a second write', {timeout:10000},()=>using(async f=>{
 let saved=null,puts=0,seenResolve;const seen=new Promise(resolve=>{seenResolve=resolve;});
 const server=createServer(async(req,res)=>{
  if(req.url==='/source'){res.writeHead(200);res.end(f.bytes);return;}
  if(req.url==='/source-meta'){res.writeHead(200);res.end('ok');return;}
  if(req.url==='/target'&&req.method==='GET'){res.writeHead(saved?200:404);res.end(saved??'');return;}
  if(req.url==='/target'&&req.method==='PUT'){
   puts++;assert.equal(req.headers['if-none-match'],'*');const chunks=[];for await(const c of req)chunks.push(c);
   if(saved){res.writeHead(412);res.end();return;}saved=Buffer.concat(chunks);seenResolve();return; // deliberately no acknowledgement
  }
  res.writeHead(404);res.end();
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const port=server.address().port;
 const plan=structuredClone(f.p);plan.source.origin=plan.target.origin='http://127.0.0.1:'+port;
 const args={plan,expectedPlanSha256:planDigest(plan),journalRoot:f.root,journalKey:f.key.toString('base64url'),requestMs:5000};
 const child=spawn(process.execPath,[fileURLToPath(new URL('./synthetic-runner.mjs',import.meta.url))],{stdio:['pipe','ignore','pipe']});let stderr='';child.stderr.on('data',c=>{stderr+=c;});
 try{
  const closed=new Promise(resolve=>child.once('close',(code,signal)=>resolve({code,signal})));child.stdin.end(JSON.stringify(args));
  let timer;try{await Promise.race([seen,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('synthetic_upload_not_observed: '+stderr)),4000);})]);}finally{clearTimeout(timer);}
  child.kill('SIGTERM');const exit=await closed;assert.equal(exit.signal,'SIGTERM');assert.deepEqual(saved,f.bytes);
  const adapters=syntheticAdapters(plan),readback=await reconcileObject({...args,...adapters,journalKey:f.key});
  assert.equal(readback.status,'matching_content_at_readback');assert.equal(readback.retry_authorized,false);assert.equal(readback.creation_attribution_verified,false);assert.equal(puts,1);
 }finally{if(child.exitCode===null&&child.signalCode===null)child.kill('SIGKILL');server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
}));
