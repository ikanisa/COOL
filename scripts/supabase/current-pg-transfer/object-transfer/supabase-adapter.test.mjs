import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer as httpServer} from 'node:http';
import {createServer as httpsServer} from 'node:https';
import {randomBytes,randomUUID,createHash} from 'node:crypto';
import {readFile,mkdtemp,realpath,rm,writeFile} from 'node:fs/promises';
import {execFile,spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {FORMAT,planDigest,transferObject,reconcileObject} from './transfer.mjs';
import {createManagedStorageAdapter,createSyntheticStorageAdapter,syntheticTlsProbe} from './supabase-adapter.mjs';

const h=x=>createHash('sha256').update(x).digest('hex'),repeat=x=>x.repeat(64);
async function fixture({payloadBytes=0}={}){
 const plaintext=payloadBytes?Buffer.alloc(payloadBytes,65):Buffer.from('synthetic-protected-object-ciphertext'),credential=Buffer.from('synthetic-private-fixture-token');
 let calls=[],stored=null,mode='normal',sourceRevision='source-v1',counter=0,trapCalls=0,uploadResolve,service,root,journalKey;
 const uploadFinished=new Promise(resolve=>{uploadResolve=resolve;});
 const trap=httpServer((req,res)=>{trapCalls++;res.writeHead(200);res.end();});
 try{
 await new Promise(resolve=>trap.listen(0,'127.0.0.1',resolve));
 service=httpServer(async(req,res)=>{
  calls.push({method:req.method,url:req.url,apikey:req.headers.apikey,authorization:req.headers.authorization,upsert:req.headers['x-upsert']});
  if(mode==='timeout'&&req.url.includes('/object/'))return;
  if(mode==='redirect'&&req.url.includes('/object/')){res.writeHead(302,{Location:'http://127.0.0.1:'+trap.address().port+'/redirected'});res.end();return;}
  const source=req.url.includes('/private-source/'),target=req.url.includes('/private-target/');
  if(req.url.startsWith('/storage/v1/bucket/')){
   const b=req.url.split('/').at(-1),base='"id":'+JSON.stringify(b)+',"name":'+JSON.stringify(b);let body;
   if(mode==='duplicate-public')body='{'+base+',"public":true,"public":false}';
   else if(mode==='duplicate-escaped-public')body='{'+base+',"public":true,"publ\\u0069c":false}';
   else if(mode==='duplicate-escaped-id')body='{"id":"wrong","i\\u0064":'+JSON.stringify(b)+',"name":'+JSON.stringify(b)+',"public":false}';
   else if(mode==='duplicate-nested')body='{'+base+',"public":false,"extra":[{"x":1,"\\u0078":2}]}';
   else if(mode==='valid-extra-numbers')body='{'+base+',"public":false,"extra":{"fraction":1.5,"exp":1e2}}';
   else body=JSON.stringify({id:b,name:b,public:mode==='public-bucket'});
   res.writeHead(200,{'content-type':'application/json'});res.end(body);return;
  }
  if(source&&req.url.includes('/authenticated/')){
   if(mode==='oversize'){res.writeHead(200,{'content-length':'8000001',etag:'source-etag'});res.end();return;}
   res.writeHead(200,{'content-length':String(plaintext.length),etag:mode==='etag-drift'?'other-etag':'source-etag'});
   res.end(req.method==='HEAD'?undefined:mode==='body-drift'?Buffer.alloc(plaintext.length,65):plaintext);return;
  }
  if(target&&req.url.includes('/authenticated/')){
   if(!stored){const body=mode==='duplicate-missing'?'{"code":"Other","co\\u0064e":"NoSuchKey","statusCode":"404","error":"not_found","message":"Object not found"}':JSON.stringify({code:'NoSuchKey',statusCode:'404',error:'not_found',message:'Object not found'});res.writeHead(mode==='head-status-mismatch'&&req.method==='HEAD'?400:404,{'content-type':'application/json','content-length':String(Buffer.byteLength(body))});res.end(req.method==='HEAD'?undefined:body);return;}
   res.writeHead(200,{'content-length':String(stored.length),etag:'target-etag'});res.end(req.method==='HEAD'?undefined:stored);return;
  }
  if(target&&req.method==='POST'){
   if(mode==='early-ack'){req.pause();res.writeHead(201,{'content-type':'application/json'});res.end('{}');await new Promise(resolve=>setTimeout(resolve,80));req.resume();}
   const chunks=[];for await(const c of req)chunks.push(c);if(req.headers['x-upsert']!=='false'){res.writeHead(400);res.end();return;}
   if(stored){res.writeHead(mode==='existing-400'?400:409);res.end('{}');return;}stored=Buffer.concat(chunks);uploadResolve();
   if(mode==='early-ack')return;
   if(mode==='lost-ack'){req.socket.destroy();return;}if(mode==='post-timeout')return;
   if(mode==='post-redirect'){res.writeHead(307,{Location:'http://127.0.0.1:'+trap.address().port+'/redirected'});res.end();return;}
   res.writeHead(201,{'content-type':'application/json'});res.end('{}');return;
  }
  res.writeHead(404);res.end();
 });
 await new Promise(resolve=>service.listen(0,'127.0.0.1',resolve));const origin='http://127.0.0.1:'+service.address().port;
 const plan={format:FORMAT,operation_id:randomUUID(),mode:'synthetic',
  source:{origin,bucket:'private-source',key:'synthetic/from key',object_id:'source-object',version:'source-v1',etag:'source-etag',bytes:plaintext.length,ciphertext_sha256:h(plaintext),namespace_sha256:repeat('a'),binding_sha256:repeat('b'),key_aad_sha256:repeat('c')},
  target:{origin,bucket:'private-target',key:'synthetic/to key',namespace_sha256:repeat('d'),key_aad_sha256:repeat('c')},
  authority:{source_identity_sha256:repeat('e'),target_identity_sha256:repeat('f'),source_fence_sha256:repeat('1'),target_fence_sha256:repeat('2'),mapping_sha256:repeat('3')}};
 const sourceMeta=()=>({...plan.source,version:sourceRevision,identity_sha256:plan.authority.source_identity_sha256,fence_sha256:plan.authority.source_fence_sha256});
 const targetMeta=()=>({origin,bucket:plan.target.bucket,key:plan.target.key,namespace_sha256:plan.target.namespace_sha256,identity_sha256:plan.authority.target_identity_sha256,fence_sha256:plan.authority.target_fence_sha256,...(stored?{state:'present',object_id:'target-object',version:'target-v1',etag:'target-etag',bytes:stored.length}:{state:'absent'})});
 const shared={plan,expectedPlanSha256:planDigest(plan),credentialSource:async()=>{counter++;return credential;},requestMs:400};
 const source=createSyntheticStorageAdapter({...shared,role:'source',metadataSource:async()=>sourceMeta()});
 const target=createSyntheticStorageAdapter({...shared,role:'target',metadataSource:async()=>targetMeta()});
 root=await mkdtemp(join(await realpath(tmpdir()),'collect-storage-adapter-'));journalKey=randomBytes(32);
 const args=()=>({plan,expectedPlanSha256:planDigest(plan),journalRoot:root,journalKey,source,target,requestMs:1000});
 return {plan,plaintext,credential,source,target,sourceMeta,targetMeta,args,root,journalKey,uploadFinished,calls:()=>calls,credentials:()=>counter,trapCalls:()=>trapCalls,
  setMode:x=>{mode=x;},setRevision:x=>{sourceRevision=x;},seed:x=>{stored=Buffer.from(x);},stored:()=>stored&&Buffer.from(stored),
  close:async()=>{service.closeAllConnections();trap.closeAllConnections();await Promise.all([new Promise(r=>service.close(r)),new Promise(r=>trap.close(r))]);plaintext.fill(0);credential.fill(0);journalKey.fill(0);await rm(root,{recursive:true,force:true});}};
 }catch(error){
  service?.closeAllConnections();trap.closeAllConnections();
  await Promise.all([...(service?.listening?[new Promise(r=>service.close(r))]:[]),...(trap.listening?[new Promise(r=>trap.close(r))]:[])]);
  plaintext.fill(0);credential.fill(0);journalKey?.fill(0);if(root)await rm(root,{recursive:true,force:true});throw error;
 }
}
async function using(fn,options){const f=await fixture(options);try{await fn(f);}finally{await f.close();}}
async function fakeCertificate(root){
 const run=promisify(execFile),keyPath=join(root,'key.pem'),certPath=join(root,'cert.pem');
 await run('openssl',['ecparam','-name','prime256v1','-genkey','-noout','-out',keyPath],{timeout:10000,maxBuffer:16384});
 await run('openssl',['req','-new','-x509','-key',keyPath,'-out',certPath,'-days','1','-subj','/CN=collect-synthetic-loopback.invalid'],{timeout:10000,maxBuffer:16384});
 return {keyPath,certPath};
}
async function startupProbe(plan,extraEnv,extraArgs=[]){
 const moduleURL=new URL('./supabase-adapter.mjs',import.meta.url).href;
 const code=`import {createSyntheticStorageAdapter} from ${JSON.stringify(moduleURL)};import {getCACertificates} from 'node:tls';
 let text='';for await(const chunk of process.stdin)text+=chunk;const input=JSON.parse(text);let credentials=0,metadata=0,status='unexpected_success';
 try{const a=createSyntheticStorageAdapter({plan:input.plan,expectedPlanSha256:input.pin,role:'source',credentialSource:async()=>{credentials++;return Buffer.from('fixture-token');},metadataSource:async()=>{metadata++;return {};}});await a.inspect();}
 catch(e){status=e.code??'unexpected_error';}process.stdout.write(JSON.stringify({status,credentials,metadata,preloaded:globalThis.__collectFakePreload===true,extraCA:getCACertificates('extra').length}));`;
 const child=spawn(process.execPath,[...extraArgs,'--input-type=module','-e',code],{env:{PATH:process.env.PATH??'/usr/bin:/bin',...extraEnv},stdio:['pipe','pipe','pipe']});
 let output='',error='';child.stdout.on('data',x=>{output+=x;});child.stderr.on('data',x=>{error+=x;});
 const closed=new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(status,signal)=>resolve({status,signal}));});
 const timer=setTimeout(()=>child.kill('SIGKILL'),5000);
 try{child.stdin.end(JSON.stringify({plan,pin:planDigest(plan)}));const result=await closed;assert.equal(result.status,0,error);assert.equal(result.signal,null);return JSON.parse(output);}
 finally{clearTimeout(timer);}
}
test('actual adapter reads, creates once and verifies synthetic protected bytes',()=>using(async f=>{
 const r=await transferObject(f.args());assert.equal(r.status,'content_verified');assert.deepEqual(f.stored(),f.plaintext);
 const post=f.calls().filter(x=>x.method==='POST');assert.equal(post.length,1);assert.equal(post[0].upsert,'false');
 assert.ok(f.calls().every(x=>x.apikey==='synthetic-private-fixture-token'&&x.authorization==='Bearer synthetic-private-fixture-token'));
 assert.ok(f.calls().some(x=>x.url.includes('from%20key')));assert.ok(f.calls().some(x=>x.url.includes('to%20key')));
 assert.equal((await reconcileObject({...f.args(),source:{inspect:f.source.inspect},target:{inspect:f.target.inspect}})).status,'matching_content_at_readback');
}));
test('preexisting object is fully inspected and never uploaded over',()=>using(async f=>{
 f.seed(Buffer.from('different protected bytes'));const out=await transferObject(f.args());
 assert.equal(out.status,'preexisting_conflict');assert.equal(f.calls().filter(x=>x.method==='POST').length,0);assert.deepEqual(f.stored(),Buffer.from('different protected bytes'));
}));
test('source version and ETag drift refuse before upload',async()=>{
 await using(async f=>{f.setRevision('other-v2');assert.equal((await transferObject(f.args())).status,'refused_before_dispatch');assert.equal(f.calls().filter(x=>x.method==='POST').length,0);});
 await using(async f=>{f.setMode('etag-drift');assert.equal((await transferObject(f.args())).status,'refused_before_dispatch');assert.equal(f.calls().filter(x=>x.method==='POST').length,0);});
 await using(async f=>{f.setMode('body-drift');assert.equal((await transferObject(f.args())).status,'refused_before_dispatch');assert.equal(f.calls().filter(x=>x.method==='POST').length,0);});
 await using(async f=>{let calls=0;const source=createSyntheticStorageAdapter({plan:f.plan,expectedPlanSha256:planDigest(f.plan),role:'source',requestMs:400,
  credentialSource:async()=>f.credential,metadataSource:async()=>({...f.sourceMeta(),version:++calls===1?'source-v1':'changed-during-read'})});
  assert.equal((await transferObject({...f.args(),source})).status,'refused_before_dispatch');assert.equal(f.calls().filter(x=>x.method==='POST').length,0);});
});
test('create-only 400/409 conflicts and concurrent creates never overwrite the fixture',async()=>{
 for(const mode of ['existing-400','normal'])await using(async f=>{
  const absent=f.targetMeta();f.seed(Buffer.from('already-existing'));f.setMode(mode);
  const target=createSyntheticStorageAdapter({plan:f.plan,expectedPlanSha256:planDigest(f.plan),role:'target',requestMs:400,
   credentialSource:async()=>f.credential,metadataSource:async()=>absent});
  assert.equal((await target.createOnly(f.plaintext)).accepted,false);assert.deepEqual(f.stored(),Buffer.from('already-existing'));
  assert.equal(f.calls().filter(x=>x.method==='POST').length,1);
 });
 await using(async f=>{
  const absent=f.targetMeta();let reads=0;const target=createSyntheticStorageAdapter({plan:f.plan,expectedPlanSha256:planDigest(f.plan),role:'target',requestMs:400,
   credentialSource:async()=>f.credential,metadataSource:async()=>++reads<=2?absent:f.targetMeta()});
  const outcomes=await Promise.all([target.createOnly(f.plaintext),target.createOnly(f.plaintext)]);
  assert.deepEqual(outcomes.map(x=>x.accepted).sort(),[false,true]);assert.deepEqual(f.stored(),f.plaintext);
  assert.ok(f.calls().filter(x=>x.method==='POST').every(x=>x.upsert==='false'));
 });
});
test('redirects are not followed or sent credentials, and oversized responses refuse',async()=>{
 await using(async f=>{f.setMode('redirect');assert.equal((await transferObject(f.args())).status,'refused_before_dispatch');assert.equal(f.trapCalls(),0);assert.equal(f.calls().filter(x=>x.method==='POST').length,0);});
 await using(async f=>{f.setMode('oversize');assert.equal((await transferObject(f.args())).status,'refused_before_dispatch');assert.equal(f.calls().filter(x=>x.method==='POST').length,0);});
});
test('public bucket, malformed metadata and untrusted absence do not dispatch',async()=>{
 await using(async f=>{f.setMode('public-bucket');assert.equal((await transferObject(f.args())).status,'refused_before_dispatch');assert.equal(f.calls().filter(x=>x.method==='POST').length,0);});
 await using(async f=>{const target=createSyntheticStorageAdapter({plan:f.plan,expectedPlanSha256:planDigest(f.plan),role:'target',requestMs:400,
  credentialSource:async()=>f.credential,metadataSource:async()=>({...f.targetMeta(),fence_sha256:repeat('9')})});
  assert.equal((await transferObject({...f.args(),target})).status,'refused_before_dispatch');assert.equal(f.calls().filter(x=>x.method==='POST').length,0);});
 await using(async f=>{f.setMode('head-status-mismatch');assert.equal((await transferObject(f.args())).status,'refused_before_dispatch');assert.equal(f.calls().filter(x=>x.method==='POST').length,0);});
});
test('bucket visibility and identity reject literal, escaped and nested duplicate JSON keys',async()=>{
 for(const mode of ['duplicate-public','duplicate-escaped-public','duplicate-escaped-id','duplicate-nested'])await using(async f=>{
  f.setMode(mode);const out=await transferObject(f.args());assert.equal(out.status,'refused_before_dispatch',mode);
  assert.equal(f.calls().filter(x=>x.url.includes('/storage/v1/object/')).length,0,mode);
 });
 await using(async f=>{f.setMode('valid-extra-numbers');assert.equal((await transferObject(f.args())).status,'content_verified');});
});
test('duplicate error JSON keys cannot establish target absence',()=>using(async f=>{
 f.setMode('duplicate-missing');assert.equal((await transferObject(f.args())).status,'refused_before_dispatch');
 assert.equal(f.calls().filter(x=>x.method==='POST').length,0);
}));
test('upload acknowledgement loss is unconfirmed and readback cannot trigger a retry',()=>using(async f=>{
 f.setMode('lost-ack');const first=await transferObject(f.args());assert.equal(first.status,'dispatch_unconfirmed');assert.deepEqual(f.stored(),f.plaintext);
 const readback=await reconcileObject(f.args());assert.equal(readback.status,'matching_content_at_readback');assert.equal(readback.retry_authorized,false);
 assert.equal((await transferObject(f.args())).status,'reconcile_required');assert.equal(f.calls().filter(x=>x.method==='POST').length,1);
}));
test('an upload redirect after the server receives bytes is unconfirmed and not followed',()=>using(async f=>{
 f.setMode('post-redirect');assert.equal((await transferObject(f.args())).status,'dispatch_unconfirmed');assert.deepEqual(f.stored(),f.plaintext);
 assert.equal(f.trapCalls(),0);assert.equal(f.calls().filter(x=>x.method==='POST').length,1);
}));
test('request timeout is bounded and performs no retry',()=>using(async f=>{
 f.setMode('timeout');const start=Date.now();const out=await transferObject(f.args());assert.equal(out.status,'refused_before_dispatch');assert.ok(Date.now()-start<2500);
 assert.equal(f.calls().filter(x=>x.method==='POST').length,0);
}));
test('a timed-out accepted upload remains unconfirmed even if later readback matches',()=>using(async f=>{
 f.setMode('post-timeout');const out=await transferObject(f.args());assert.equal(out.status,'dispatch_unconfirmed');assert.deepEqual(f.stored(),f.plaintext);
 f.setMode('normal');const readback=await reconcileObject(f.args());assert.equal(readback.status,'matching_content_at_readback');assert.equal(readback.retry_authorized,false);
 assert.equal((await transferObject(f.args())).status,'reconcile_required');assert.equal(f.calls().filter(x=>x.method==='POST').length,1);
}));
test('a changed credential is refused before a later request',()=>using(async f=>{
 let calls=0;const source=createSyntheticStorageAdapter({plan:f.plan,expectedPlanSha256:planDigest(f.plan),role:'source',requestMs:400,
  credentialSource:async()=>++calls===1?f.credential:Buffer.from('different-synthetic-token'),metadataSource:async()=>f.sourceMeta()});
 assert.equal((await transferObject({...f.args(),source})).status,'refused_before_dispatch');assert.equal(f.calls().filter(x=>x.method==='POST').length,0);assert.equal(calls,2);
}));
test('an early provider response cannot corrupt a request body still being transmitted', {timeout:10000},()=>using(async f=>{
 f.setMode('early-ack');let acknowledged=false;
 try{acknowledged=(await f.target.createOnly(f.plaintext)).accepted;}catch{}
 if(acknowledged)assert.deepEqual(f.stored(),f.plaintext);
 else assert.equal(f.calls().filter(x=>x.method==='POST').length,1);
},{payloadBytes:6_000_000}));
test('managed endpoint is pinned and all managed methods are closed before callbacks or network',()=>using(async f=>{
 const p=structuredClone(f.plan);p.mode='managed';p.source.origin='https://source.example';p.target.origin='https://rrlduytparvsjfmegalh.supabase.co';let credentials=0,metadata=0;
 const opts={plan:p,expectedPlanSha256:planDigest(p),role:'target',credentialSource:async()=>{credentials++;return f.credential;},metadataSource:async()=>{metadata++;return {};}};
 const adapter=createManagedStorageAdapter(opts);await assert.rejects(adapter.inspect(),/managed_adapter_unqualified/);await assert.rejects(adapter.createOnly(f.plaintext),/managed_adapter_unqualified/);
 assert.equal(credentials,0);assert.equal(metadata,0);assert.equal(f.calls().length,0);
 p.target.origin='https://other.supabase.co';assert.throws(()=>createManagedStorageAdapter({...opts,plan:p,expectedPlanSha256:planDigest(p)}));
}));
test('injected trust and preload environment refuses before credentials, metadata or network',()=>using(async f=>{
 for(const name of ['NODE_EXTRA_CA_CERTS','NODE_OPTIONS','NODE_TLS_REJECT_UNAUTHORIZED','NODE_USE_ENV_PROXY','SSL_CERT_FILE','OPENSSL_CONF','LD_PRELOAD','DYLD_INSERT_LIBRARIES']){
  const prior=process.env[name];process.env[name]='synthetic-value';
  try{
   await assert.rejects(f.source.inspect(),{code:'unclean_environment'});await assert.rejects(f.target.createOnly(f.plaintext),{code:'unclean_environment'});
   assert.throws(()=>createSyntheticStorageAdapter({plan:f.plan,expectedPlanSha256:planDigest(f.plan),role:'source',credentialSource:async()=>f.credential,metadataSource:async()=>f.sourceMeta()}),{code:'unclean_environment'});
   assert.equal(f.credentials(),0,name);assert.equal(f.calls().length,0,name);
  }finally{if(prior===undefined)delete process.env[name];else process.env[name]=prior;}
 }
}));
test('CA and preload variables present at Node startup fail closed before callbacks',()=>using(async f=>{
 const {certPath}=await fakeCertificate(f.root),preload=join(f.root,'synthetic-preload.cjs'),erasePreload=join(f.root,'synthetic-erasing-preload.cjs');
 await writeFile(preload,'globalThis.__collectFakePreload=true;\n',{mode:0o600});
 await writeFile(erasePreload,'globalThis.__collectFakePreload=true;delete process.env.NODE_OPTIONS;delete process.env.NODE_EXTRA_CA_CERTS;\n',{mode:0o600});
 const ca=await startupProbe(f.plan,{NODE_EXTRA_CA_CERTS:certPath});
 assert.equal(ca.status,'unclean_environment');assert.equal(ca.credentials,0);assert.equal(ca.metadata,0);assert.ok(ca.extraCA>0);
 const preloaded=await startupProbe(f.plan,{NODE_OPTIONS:'--require='+preload});
 assert.equal(preloaded.status,'unclean_environment');assert.equal(preloaded.credentials,0);assert.equal(preloaded.metadata,0);assert.equal(preloaded.preloaded,true);
 const commandLine=await startupProbe(f.plan,{},['--require='+preload]);
 assert.equal(commandLine.status,'unclean_environment');assert.equal(commandLine.credentials,0);assert.equal(commandLine.metadata,0);assert.equal(commandLine.preloaded,true);
 const erased=await startupProbe(f.plan,{NODE_EXTRA_CA_CERTS:certPath,NODE_OPTIONS:'--require='+erasePreload});
 assert.equal(erased.status,'unclean_environment');assert.equal(erased.credentials,0);assert.equal(erased.metadata,0);assert.equal(erased.preloaded,true);assert.ok(erased.extraCA>0);
 assert.equal(f.calls().length,0);
}));
test('trust environment introduced during metadata or credential callbacks prevents network dispatch',()=>using(async f=>{
 const name='NODE_EXTRA_CA_CERTS',prior=process.env[name];
 try{
  let credentials=0;const source=createSyntheticStorageAdapter({plan:f.plan,expectedPlanSha256:planDigest(f.plan),role:'source',requestMs:400,
   metadataSource:async()=>{process.env[name]='synthetic-ca';return f.sourceMeta();},credentialSource:async()=>{credentials++;return f.credential;}});
  await assert.rejects(source.read(),{code:'unclean_environment'});assert.equal(credentials,0);assert.equal(f.calls().length,0);
  delete process.env[name];
  const second=createSyntheticStorageAdapter({plan:f.plan,expectedPlanSha256:planDigest(f.plan),role:'source',requestMs:400,
   metadataSource:async()=>f.sourceMeta(),credentialSource:async()=>{process.env[name]='synthetic-ca';return f.credential;}});
  await assert.rejects(second.read(),{code:'request_unconfirmed'});assert.equal(f.calls().length,0);
 }finally{if(prior===undefined)delete process.env[name];else process.env[name]=prior;}
}));
test('HTTPS client rejects a self-signed loopback server',async()=>{
 const root=await mkdtemp(join(await realpath(tmpdir()),'collect-fake-tls-'));
 let key,cert,server;
 try{
  const {keyPath,certPath}=await fakeCertificate(root);
  key=await readFile(keyPath);cert=await readFile(certPath);let calls=0;
  server=httpsServer({key,cert},(req,res)=>{calls++;res.writeHead(200);res.end('fake');});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  await assert.rejects(syntheticTlsProbe('https://127.0.0.1:'+server.address().port));assert.equal(calls,0);
 }finally{if(server){server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}key?.fill(0);cert?.fill(0);await rm(root,{recursive:true,force:true});}
});
