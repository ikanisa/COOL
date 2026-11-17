import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {mkdtemp,realpath,chmod,rm,lstat,writeFile,readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createNativeIngressApplication,serveNativeIngress,canonicalClientAddress,loadNativeIngressEnvironment,INGRESS_ENV_FIELDS} from './native-ingress.mjs';
import {admitNativeIngress,NATIVE_INGRESS_HEADER} from '../../supabase/functions/_shared/native-ingress.js';
import {environment,now,profile,request} from '../../supabase/functions/_shared/tests/native-ingress-fixture.mjs';

function fixture(env=environment()){
 const calls=[];return {calls,env,application:createNativeIngressApplication(env,{clock:()=>now,fetchImpl:async(input,options)=>{
  calls.push({input,options,body:input instanceof Request?await input.clone().text():options?.body});
  return Response.json({ok:true},{headers:{'X-Collect-Native-Ingress':'must never return','Set-Cookie':'synthetic; Secure; HttpOnly'}});
 }})};
}
const metadata=input=>({rawTarget:new URL(input.url).pathname+new URL(input.url).search,clientAddress:'192.0.2.1'});
test('retained ingress targets only fixed loopback and produces a body/authority-bound usable Edge witness',async()=>{
 const f=fixture(),input=request({headers:{'X-Collect-Native-Ingress':'forged','CF-Connecting-IP':'forged'}}),original=await input.clone().text();
 const response=await(await f.application)(input,metadata(input));assert.equal(response.status,200);assert.equal(f.calls.length,1);
 const outgoing=f.calls[0].input;assert.equal(outgoing.url,'http://127.0.0.1:55101/functions/v1/collect-api/v1/burimunsi/session/login');
 assert.equal(outgoing.headers.has('cf-connecting-ip'),false);assert.notEqual(outgoing.headers.get(NATIVE_INGRESS_HEADER),'forged');
 assert.equal(response.headers.has(NATIVE_INGRESS_HEADER),false);assert.equal(response.headers.get('set-cookie'),'synthetic; Secure; HttpOnly');
 const logical=new Request(profile.supabase_origin+'/v1/burimunsi/session/login',{method:'POST',headers:outgoing.headers,body:original});
 const admission=await admitNativeIngress(logical,f.env,{clock:()=>now});assert.equal(await admission.request.text(),original);
 assert.match(await admission.networkBucket(admission.request),/^[a-f0-9]{64}$/);
});
test('default-off native and uncertified edge cannot forward a native request',async()=>{
 for(const change of [{BURIMUNSI_NATIVE_ENABLED:'false'},{COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON:''}]){
  const f=fixture(environment(change)),input=request();assert.equal((await(await f.application)(input,metadata(input))).status,503);assert.equal(f.calls.length,0);
 }
});
test('native worker subrequests/missing or invalid network identity fail closed despite a configured review record',async()=>{
 for(const change of [{clientAddress:undefined},{clientAddress:'unknown'},{clientAddress:'1.2.3.4, 5.6.7.8'},{workerSubrequest:true}]){
  const f=fixture(),input=request();assert.equal((await(await f.application)(input,{...metadata(input),...change})).status,403);assert.equal(f.calls.length,0);
 }
 const f=fixture(),input=request({headers:{'CF-Worker':'ikanisa.com'}});assert.equal((await(await f.application)(input,metadata(input))).status,403);assert.equal(f.calls.length,0);
});
test('origin marker rejection happens before IP selection, body consumption or forwarding',async()=>{
 for(const marker of ['', 'ikanisa.com', 'other.example']){
  const f=fixture(),input=request({headers:{'Cf-WoRkEr':marker,'X-Real-IP':'198.51.100.99','CF-Connecting-IP':'198.51.100.99'}});
  let selected=0;const meta={rawTarget:new URL(input.url).pathname,get clientAddress(){selected++;throw Error('must never select Worker IP');}};
  const response=await(await f.application)(input,meta);
  assert.equal(response.status,403);assert.equal(selected,0);assert.equal(input.bodyUsed,false);assert.equal(f.calls.length,0);
 }
 const f=fixture(),input=request();let selected=0;
 const meta={rawTarget:new URL(input.url).pathname,workerSubrequest:true,get clientAddress(){selected++;throw Error('must never select Worker IP');}};
 assert.equal((await(await f.application)(input,meta)).status,403);assert.equal(selected,0);assert.equal(input.bodyUsed,false);assert.equal(f.calls.length,0);
});
test('network normalization is deterministic without trusting forwarded chains',()=>{
 assert.equal(canonicalClientAddress('2001:0DB8:0000:0000:0000:0000:0000:0001'),'2001:db8::1');
 assert.equal(canonicalClientAddress('::ffff:192.0.2.1'),'192.0.2.1');
 for(const value of [' 192.0.2.1','192.0.2.01','[2001:db8::1]','fe80::1%lo0','2a06:98c0:3600::103'])assert.throws(()=>canonicalClientAddress(value));
});
test('fixed origin, raw target, body size and service allowlists cannot become a forward proxy',async()=>{
 for(const upstream of ['http://127.0.0.1:55102','http://localhost:55101','http://169.254.169.254','https://other.example'])await assert.rejects(createNativeIngressApplication(environment({SUPABASE_INTERNAL_URL:upstream})));
 const cases=[
  [new Request('https://evil.example/rest/v1/data'),{rawTarget:'/rest/v1/data'},421],
  [request(),{rawTarget:'/functions/v1/collect-api/v1/../burimunsi/session/login'},400],
  [request(),{rawTarget:'/functions/v1/collect-api/v1/burimunsi/session/login?changed=1'},400],
  [request({path:'/studio/'}),{rawTarget:'/studio/'},404],
  [request({path:'/functions/v1/unknown/route'}),{rawTarget:'/functions/v1/unknown/route'},404],
  [request({body:'x'.repeat(8193),headers:{'Content-Length':'8193'}}),{rawTarget:'/functions/v1/collect-api/v1/burimunsi/session/login'},413],
 ];
 for(const [input,meta,status]of cases){const f=fixture();assert.equal((await(await f.application)(input,{clientAddress:'192.0.2.1',...meta})).status,status);assert.equal(f.calls.length,0);}
});
test('ordinary fixed Supabase routes strip caller authority/attestation and retain existing no-store controls',async()=>{
 const f=fixture(),input=new Request(profile.supabase_origin+'/rest/v1/collections',{headers:{'X-Collect-Native-Ingress':'forged',
  'CF-Connecting-IP':'forged','X-Forwarded-Host':'evil.example','X-Collect-Actor':'forged',Authorization:'Bearer synthetic'}});
 const response=await(await f.application)(input,metadata(input));assert.equal(response.status,200);
 const headers=f.calls[0].input.headers;for(const name of ['X-Collect-Native-Ingress','CF-Connecting-IP','X-Forwarded-Host','X-Collect-Actor'])assert.equal(headers.has(name),false);
 assert.equal(headers.get('authorization'),'Bearer synthetic');assert.match(response.headers.get('cache-control'),/no-store/);
});
test('unknown upstream outcomes are redacted and never automatically retried',async()=>{
 let calls=0;const application=await createNativeIngressApplication(environment(),{clock:()=>now,fetchImpl:async()=>{
  calls++;throw Object.assign(Error('private provider detail'),{code:'native_ingress_private_provider_detail'});
 }}),input=request();
 const response=await application(input,metadata(input));assert.equal(response.status,503);assert.equal(calls,1);
 assert.deepEqual(await response.json(),{code:'backend_unavailable'});
});
test('real Auth proxy retains email semantics and refuses phone bypass against only the retained loopback',async()=>{
 const f=fixture(environment({BURIMUNSI_NATIVE_ENABLED:'false'}));
 const input=new Request(profile.supabase_origin+'/auth/v1/otp',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"email":"fixture@example.test"}'});
 assert.equal((await(await f.application)(input,metadata(input))).status,200);
 assert.equal(f.calls[0].input,'http://127.0.0.1:55101/auth/v1/otp');
 const phone=new Request(profile.supabase_origin+'/auth/v1/otp',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"Phone":"+250788123456"}'});
 assert.equal((await(await f.application)(phone,metadata(phone))).status,403);assert.equal(f.calls.length,1);
});
async function localSocket(t){
 const temporary=await mkdtemp(join(await realpath('/tmp'),'buri-i-')),root=await realpath(temporary);await chmod(root,0o700);
 t.after(()=>rm(root,{recursive:true,force:true}));return {root,path:join(root,'http.sock')};
}
const close=server=>new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve()));
function socketRequest(path,{target='/functions/v1/collect-api/v1/burimunsi/session/login',headers={},body='{"phone":"+250788123456","pin":"0123"}',method='POST'}={}){
 return new Promise((resolve,reject)=>{
  const req=http.request({socketPath:path,path:target,method,headers:{Host:new URL(profile.supabase_origin).host,'Content-Type':'application/json','CF-Connecting-IP':'192.0.2.1',...headers}},res=>{
   const chunks=[];res.on('data',chunk=>chunks.push(chunk));res.on('end',()=>resolve({status:res.statusCode,body:Buffer.concat(chunks).toString()}));
  });req.on('error',reject);req.end(body);
 });
}
test('real Unix listener forwards native PATCH edits with a usable unchanged-method/body Edge attestation',async t=>{
 const socket=await localSocket(t),calls=[],body='{"id":"fixture-staff","name":"Updated operator"}';
 const server=await serveNativeIngress({...environment(),COLLECT_NATIVE_INGRESS_SOCKET:socket.path},{clock:()=>now,
  fetchImpl:async input=>{calls.push({url:input.url,method:input.method,headers:input.headers,body:await input.text()});return Response.json({ok:true});}});
 try{
  const response=await socketRequest(socket.path,{method:'PATCH',target:'/functions/v1/collect-api/v1/burimunsi/staff',body,
   headers:{'X-Burimunsi-Auth':'phone_pin','X-Burimunsi-Profile':'internal_receiver'}});
  assert.equal(response.status,200);assert.equal(calls.length,1);assert.equal(calls[0].method,'PATCH');assert.equal(calls[0].body,body);
  const admitted=await admitNativeIngress(new Request(profile.supabase_origin+'/v1/burimunsi/staff',
   {method:'PATCH',headers:calls[0].headers,body:calls[0].body}),environment(),{clock:()=>now});
  assert.equal(admitted.request.method,'PATCH');assert.equal(await admitted.request.text(),body);
  assert.match(await admitted.networkBucket(admitted.request),/^[a-f0-9]{64}$/);
 }finally{await close(server);}
});
test('real temporary Unix listener is private, has no TCP port, enforces Host and forwards only through the test double',async t=>{
 const socket=await localSocket(t),calls=[];
 const server=await serveNativeIngress({...environment(),COLLECT_NATIVE_INGRESS_SOCKET:socket.path},{clock:()=>now,fetchImpl:async input=>{calls.push(input.url);return Response.json({ok:true});}});
 try{
  assert.equal(server.address(),socket.path);assert.equal((await lstat(socket.path)).mode&0o777,0o600);
  assert.equal((await socketRequest(socket.path)).status,200);assert.equal(calls.length,1);
  assert.equal((await socketRequest(socket.path,{headers:{Host:'evil.example'}})).status,421);
  assert.equal((await socketRequest(socket.path,{headers:{'CF-Connecting-IP':'one,two'}})).status,403);
  // Deliberately incomplete declared body: Worker denial must occur before
  // the listener waits for body bytes or examines the forged IP.
  assert.equal((await socketRequest(socket.path,{headers:{'CF-Worker':'','CF-Connecting-IP':'198.51.100.99',
   'X-Real-IP':'198.51.100.99','Content-Length':'8193'},body:''})).status,403);
  assert.equal((await socketRequest(socket.path,{headers:{'Content-Length':'8193'},body:'x'.repeat(8193)})).status,413);
  assert.equal(calls.length,1);
 }finally{await close(server);}
});
test('listener refuses unprotected parent or existing socket/file and never removes retained content',async t=>{
 const socket=await localSocket(t),env={...environment(),COLLECT_NATIVE_INGRESS_SOCKET:socket.path};
 await chmod(socket.root,0o755);await assert.rejects(serveNativeIngress(env),/unprotected/);await chmod(socket.root,0o700);
 await writeFile(socket.path,'retain this existing source');await assert.rejects(serveNativeIngress(env),/exists/);
 assert.equal(await readFile(socket.path,'utf8'),'retain this existing source');
 for(const value of ['relative.sock','/tmp/'+'x'.repeat(101)])await assert.rejects(serveNativeIngress({...env,COLLECT_NATIVE_INGRESS_SOCKET:value}),/socket_required/);
});
test('owned600 frontdoor file loads a strict minimal projection without DATA/BFF/PIN/Auth keys',async t=>{
 const socket=await localSocket(t),path=join(socket.root,'ingress.env'),full={...environment(),COLLECT_NATIVE_INGRESS_SOCKET:socket.path};
 const values=Object.fromEntries(INGRESS_ENV_FIELDS.map(name=>[name,full[name]]));
 const raw=Object.entries(values).map(([name,value])=>name+'='+JSON.stringify(value.replaceAll('$','$$'))+'\n').join('');
 await writeFile(path,raw,{mode:0o600});const loaded=await loadNativeIngressEnvironment(path);
 assert.deepEqual(loaded,values);for(const name of ['DATA_ENCRYPTION_KEY','SESSION_ENCRYPTION_KEY','BURIMUNSI_PIN_PEPPER_BASE64','JWT_KEYS','SUPABASE_SECRET_KEY'])assert.equal(loaded[name],undefined);
 const calls=[],application=await createNativeIngressApplication(loaded,{clock:()=>now,fetchImpl:async input=>{calls.push(input);return Response.json({ok:true});}}),input=request();
 assert.equal((await application(input,metadata(input))).status,200);assert.equal(calls.length,1);
});
test('frontdoor loader refuses broad or malformed credential files and permissive permissions with opaque errors',async t=>{
 const socket=await localSocket(t),path=join(socket.root,'ingress.env'),full={...environment(),COLLECT_NATIVE_INGRESS_SOCKET:socket.path};
 const raw=INGRESS_ENV_FIELDS.map(name=>name+'='+JSON.stringify(full[name])+'\n').join('');
 for(const content of [raw+'DATA_ENCRYPTION_KEY="must-not-be-inherited"\n',raw+'COLLECT_NATIVE_INGRESS_KEY_ID="duplicate"\n','SECRET=unparsed-private-value']){
  await writeFile(path,content,{mode:0o600});await assert.rejects(loadNativeIngressEnvironment(path),error=>error.message==='native_ingress_env_unprotected_or_invalid');
 }
 await writeFile(path,raw);await chmod(path,0o644);await assert.rejects(loadNativeIngressEnvironment(path),/unprotected_or_invalid/);
});
