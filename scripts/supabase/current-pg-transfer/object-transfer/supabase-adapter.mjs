// Candidate only. Managed requests remain closed pending live qualification.
import {request as httpRequest} from 'node:http';
import {request as httpsRequest} from 'node:https';
import {createHash,timingSafeEqual} from 'node:crypto';
import {isIP} from 'node:net';
import {getCACertificates} from 'node:tls';
import {types as utilTypes} from 'node:util';
import {validatedTransferPlan} from './transfer.mjs';

const MAX_BYTES=8_000_000,MAX_JSON=16384,MAX_HEADERS=16384;
const fail=code=>{const e=Error(code);e.code=code;throw e;};
const sha=b=>createHash('sha256').update(b).digest('hex');
const encode=k=>k.split('/').map(encodeURIComponent).join('/');
const isPlain=x=>x&&typeof x==='object'&&!Array.isArray(x)&&!utilTypes.isProxy(x)&&Object.getPrototypeOf(x)===Object.prototype;
function assertCleanEnvironment(){
 // This observes only the current environment, not what Node or the native
 // loader consumed before this module ran. A clean, trusted launcher remains
 // mandatory and must never supply credentials to a preloaded process.
 const forbidden=/^(?:NODE_OPTIONS|NODE_PATH|NODE_EXTRA_CA_CERTS|NODE_TLS_REJECT_UNAUTHORIZED|NODE_USE_SYSTEM_CA|NODE_USE_OPENSSL_CA|NODE_USE_ENV_PROXY|NODE_DEBUG|NODE_DEBUG_NATIVE|NODE_V8_COVERAGE|NODE_COMPILE_CACHE|SSLKEYLOGFILE|SSL_[A-Z0-9_]*|OPENSSL_[A-Z0-9_]*|LD_[A-Z0-9_]*|DYLD_[A-Z0-9_]*|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY)$/i;
 if(Object.keys(process.env).some(k=>forbidden.test(k)))fail('unclean_environment');
 if(process.execArgv.some(arg=>/^(?:-r(?:.*)?|--(?:require|import|loader|experimental-loader|openssl-config|use-openssl-ca|use-system-ca|use-env-proxy|inspect|inspect-brk|tls-keylog)(?:=|$))/.test(arg)))fail('unclean_environment');
 let extra;try{extra=getCACertificates('extra');}catch{fail('unclean_environment');}
 if(!Array.isArray(extra)||extra.length!==0)fail('unclean_environment');
}
function record(x,keys){
 if(!isPlain(x)||Reflect.ownKeys(x).length!==keys.length||Object.keys(x).sort().join('\0')!==[...keys].sort().join('\0'))fail('metadata_unconfirmed');
 const d=Object.getOwnPropertyDescriptors(x);for(const entry of Object.values(d))if(!entry.enumerable||!Object.hasOwn(entry,'value'))fail('metadata_unconfirmed');
 return Object.fromEntries(keys.map(k=>[k,d[k].value]));
}
function bytes(value,min,max){
 if(!Buffer.isBuffer(value)||utilTypes.isProxy(value)||utilTypes.isSharedArrayBuffer(value.buffer)||value.buffer.resizable===true||value.length<min||value.length>max)fail('invalid_bytes');
 return Buffer.from(value);
}
function credentials(key){
 const copy=bytes(key,8,4096);try{
  // Header values are ASCII tokens; never accept embedded whitespace or CR/LF.
  const text=copy.toString('ascii');if(!/^[A-Za-z0-9._-]+$/.test(text)||!Buffer.from(text,'ascii').equals(copy))fail('invalid_credential');
  return {apikey:text,...(text.startsWith('sb_secret_')?{}:{Authorization:'Bearer '+text})};
 }finally{copy.fill(0);}
}
function boundedCall(callback,signal,ms){
 return new Promise((resolve,reject)=>{
  const controller=new AbortController();let done=false;
  const finish=(err,value)=>{if(done)return;done=true;clearTimeout(timer);signal?.removeEventListener('abort',abort);controller.abort();if(err)reject(err);else resolve(value);};
  const abort=()=>{try{fail('request_unconfirmed');}catch(e){finish(e);}};
  const timer=setTimeout(abort,ms);if(signal?.aborted)return abort();signal?.addEventListener('abort',abort,{once:true});
  Promise.resolve().then(()=>callback(controller.signal)).then(v=>finish(null,v),()=>abort());
 });
}
// Uses built-in HTTP(S) directly: no redirects, proxy agent, custom CA or
// configurable fetch implementation. HTTPS forces certificate validation.
function request(url,{method,headers={},body,signal,ms,maximum=MAX_JSON}={}){
 return new Promise((resolve,reject)=>{
  const u=new URL(url),chunks=[];let req,res,timer,total=0,done=false,ended=false,requestFinished=false,pending,reason='request_unconfirmed';
  const cleanup=()=>{clearTimeout(timer);signal?.removeEventListener('abort',abort);};
  const finish=(err,value)=>{if(done)return;done=true;cleanup();for(const c of chunks)c.fill(0);if(err){pending?.body.fill(0);reject(Error(reason));}else resolve(value);};
  const complete=()=>{if(ended&&requestFinished)finish(false,pending);};
  const stop=()=>{try{res?.destroy();}catch{}try{req?.destroy();}catch{}};
  const abort=()=>{reason='request_unconfirmed';stop();};
  if(signal?.aborted){reject(Error('request_unconfirmed'));return;}
  const options={method,headers,agent:false,maxHeaderSize:MAX_HEADERS,...(u.protocol==='https:'?{rejectUnauthorized:true,...(isIP(u.hostname)?{}:{servername:u.hostname})}: {})};
  try{req=(u.protocol==='https:'?httpsRequest:httpRequest)(u,options,response=>{
   res=response;const status=response.statusCode??0;
   if(status>=300&&status<400){reason='redirect_refused';stop();return;}
   const encoding=response.headers['content-encoding'],declared=response.headers['content-length'];
   if((encoding&&encoding!=='identity')||(declared!==undefined&&(!/^(0|[1-9][0-9]*)$/.test(declared)||Number(declared)>maximum))){reason='response_unconfirmed';stop();return;}
   response.on('data',chunk=>{total+=chunk.length;if(total>maximum){reason='response_unconfirmed';stop();return;}chunks.push(Buffer.from(chunk));});
   response.once('error',()=>{reason='response_unconfirmed';stop();});
   response.once('end',()=>{ended=true;
    if(method!=='HEAD'&&declared!==undefined&&Number(declared)!==total){reason='response_unconfirmed';finish(true);return;}
    const out=Buffer.concat(chunks,total);pending={status,headers:response.headers,body:out};complete();
   });
   response.once('close',()=>{if(!ended&&!done){reason=reason==='redirect_refused'?reason:'response_unconfirmed';stop();}});
  });}catch{reject(Error('request_unconfirmed'));return;}
  req.once('error',()=>{});req.once('finish',()=>{requestFinished=true;complete();});
  req.once('close',()=>{if(!done){if(!ended||!requestFinished)finish(true);else complete();}});
  signal?.addEventListener('abort',abort,{once:true});timer=setTimeout(abort,ms);
  if(body!==undefined)req.end(body);else req.end();
 });
}
// JSON.parse alone silently discards duplicate keys, including escaped aliases.
// Validate ordinary JSON first, then walk every bounded object and compare each
// key's JSON-decoded form before any caller inspects visibility or identity.
function json(body){
 try{
  if(!Buffer.isBuffer(body)||body.length>MAX_JSON)fail('response_unconfirmed');
  const text=new TextDecoder('utf-8',{fatal:true}).decode(body),parsed=JSON.parse(text);let p=0,nodes=0;
  const ws=()=>{while(p<text.length&&' \t\r\n'.includes(text[p]))p++;};
  const string=()=>{
   const start=p++;while(p<text.length){const ch=text[p++];if(ch==='"')return JSON.parse(text.slice(start,p));if(ch==='\\')p++;}fail('response_unconfirmed');
  };
  const value=depth=>{
   if(depth>64||++nodes>10000)fail('response_unconfirmed');ws();const ch=text[p];
   if(ch==='"'){string();return;}
   if(ch==='{'){
    p++;ws();const seen=new Set();if(text[p]==='}'){p++;return;}
    for(;;){ws();if(text[p]!=='"')fail('response_unconfirmed');const key=string();if(seen.has(key))fail('response_unconfirmed');seen.add(key);
     ws();if(text[p++]!==':')fail('response_unconfirmed');value(depth+1);ws();const sep=text[p++];if(sep==='}')return;if(sep!==',')fail('response_unconfirmed');}
   }
   if(ch==='['){p++;ws();if(text[p]===']'){p++;return;}for(;;){value(depth+1);ws();const sep=text[p++];if(sep===']')return;if(sep!==',')fail('response_unconfirmed');}}
   const match=/^(?:true|false|null|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/.exec(text.slice(p));
   if(!match)fail('response_unconfirmed');p+=match[0].length;
  };
  value(0);ws();if(p!==text.length)fail('response_unconfirmed');return parsed;
 }catch{fail('response_unconfirmed');}
}
function missing(status,body){
 if(![400,404].includes(status))return false;
 const j=json(body);if(!isPlain(j))return false;
 if(status===400)return Object.keys(j).sort().join(',')==='code,error,message,statusCode'&&j.statusCode==='404'&&j.error==='not_found'&&j.message==='Object not found'&&j.code==='NoSuchKey';
 return (j.code==='NoSuchKey'||j.error==='NoSuchKey'||String(j.statusCode??j.status??'')==='404')&&
  (j.message===undefined||/^(?:object not found|the resource was not found|the specified key does not exist\.)$/i.test(j.message));
}
function canonicalMeta(meta){return JSON.stringify(Object.fromEntries(Object.entries(meta).sort(([a],[b])=>a<b?-1:a>b?1:0)));}
function small(v,max=512){return typeof v==='string'&&v.length>0&&Buffer.byteLength(v)<=max&&!/[\u0000-\u001f\u007f]/.test(v);}
function sourceMeta(value,p){
 const expected={...p.source,identity_sha256:p.authority.source_identity_sha256,fence_sha256:p.authority.source_fence_sha256};
 const got=record(value,Object.keys(expected));for(const k of Object.keys(expected))if(got[k]!==expected[k])fail('source_metadata_changed');return got;
}
function targetMeta(value,p){
 if(!isPlain(value))fail('metadata_unconfirmed');const state=Object.getOwnPropertyDescriptor(value,'state');
 if(!state||!Object.hasOwn(state,'value')||!['absent','present'].includes(state.value))fail('metadata_unconfirmed');
 const base={...p.target,identity_sha256:p.authority.target_identity_sha256,fence_sha256:p.authority.target_fence_sha256};delete base.key_aad_sha256;
 const keys=Object.keys(base).concat('state',...(state.value==='present'?['object_id','version','etag','bytes']:[]));
 const got=record(value,keys);for(const [k,v] of Object.entries(base))if(got[k]!==v)fail('target_metadata_changed');
 if(got.state==='present'&&(!small(got.object_id,128)||!small(got.version)||!small(got.etag)||!Number.isSafeInteger(got.bytes)||got.bytes<0||got.bytes>MAX_BYTES))fail('metadata_unconfirmed');
 return got;
}
function same(a,b){return canonicalMeta(a)===canonicalMeta(b);}
function apiPath(p,key,authenticated=false){return '/storage/v1/object/'+(authenticated?'authenticated/':'')+encode(p.bucket)+'/'+encode(key);}
function headMatches(head,meta){return head.status===200&&head.headers.etag===meta.etag&&/^(0|[1-9][0-9]*)$/.test(head.headers['content-length']??'')&&Number(head.headers['content-length'])===meta.bytes;}
async function bucket(origin,config,signal){
 const r=await config.request(origin+'/storage/v1/bucket/'+encode(config.bucket),{method:'GET',signal,maximum:MAX_JSON});
 try{const j=json(r.body);if(r.status!==200||!isPlain(j)||j.id!==config.bucket||j.name!==config.bucket||j.public!==false)fail('bucket_unconfirmed');}
 finally{r.body.fill(0);}
}
async function readExisting(origin,base,meta,config,signal){
 const path=apiPath(base,base.key,true),head=await config.request(origin+path,{method:'HEAD',signal,maximum:MAX_BYTES});
 try{if(!headMatches(head,meta))fail('object_unconfirmed');}finally{head.body.fill(0);}
 const get=await config.request(origin+path,{method:'GET',signal,maximum:MAX_BYTES});
 if(get.status!==200||get.headers.etag!==meta.etag||get.body.length!==meta.bytes){get.body.fill(0);fail('object_unconfirmed');}return get.body;
}
function factory({plan,expectedPlanSha256,role,credentialSource,metadataSource,requestMs=30000},kind){
 assertCleanEnvironment();
 const p=validatedTransferPlan(plan,expectedPlanSha256);
 if(p.mode!==kind||!['source','target'].includes(role)||typeof credentialSource!=='function'||typeof metadataSource!=='function'||!Number.isInteger(requestMs)||requestMs<1||requestMs>30000)fail('invalid_configuration');
 const base=role==='source'?p.source:p.target,origin=base.origin;let credentialFingerprint;
 function closed(){assertCleanEnvironment();if(kind==='managed')fail('managed_adapter_unqualified');}
 async function metadata(signal){const value=await boundedCall(s=>metadataSource({signal:s,role}),signal,requestMs);return role==='source'?sourceMeta(value,p):targetMeta(value,p);}
 async function network(url,options){
  assertCleanEnvironment();
  const credential=await boundedCall(s=>credentialSource({signal:s}),options.signal,requestMs);let headers,owned,fingerprint;
  try{
   owned=bytes(credential,8,4096);fingerprint=createHash('sha256').update(owned).digest();
   if(credentialFingerprint&&!timingSafeEqual(credentialFingerprint,fingerprint))fail('credential_changed');
   if(!credentialFingerprint){credentialFingerprint=fingerprint;fingerprint=null;}
   headers=credentials(owned);
  }catch{fail('credential_unavailable');}finally{owned?.fill(0);fingerprint?.fill(0);}
  try{assertCleanEnvironment();return await request(url,{...options,ms:requestMs,headers:{...headers,...options.headers,'Accept-Encoding':'identity'}});}catch{fail('request_unconfirmed');}
 }
 const config={bucket:base.bucket,request:network};
 const core={
  async inspect({signal}={}){
   closed();const first=await metadata(signal);await bucket(origin,config,signal);
   if(role==='source'){const last=await metadata(signal);if(!same(first,last))fail('source_metadata_changed');return first;}
   let body;
   if(first.state==='absent'){
    const path=apiPath(base,base.key,true),head=await network(origin+path,{method:'HEAD',signal,maximum:MAX_JSON});
    const get=await network(origin+path,{method:'GET',signal,maximum:MAX_JSON});
    try{if(head.status!==get.status||![400,404].includes(head.status)||!missing(get.status,get.body))fail('absence_unconfirmed');}finally{head.body.fill(0);get.body.fill(0);}
   }else body=await readExisting(origin,base,first,config,signal);
   try{const last=await metadata(signal);if(!same(first,last))fail('target_metadata_changed');
    const common={origin:base.origin,bucket:base.bucket,key:base.key,identity_sha256:p.authority.target_identity_sha256,
     fence_sha256:p.authority.target_fence_sha256,namespace_sha256:base.namespace_sha256,private_bucket:true};
    if(first.state==='absent')return {...common,state:'absent',absence_verified:true};
    return {...common,state:'present',object_id:first.object_id,version:first.version,etag:first.etag,body};
   }catch(e){body?.fill(0);throw e;}
  }
 };
 if(role==='source')core.read=async({signal}={})=>{
  closed();const first=await metadata(signal);await bucket(origin,config,signal);let body;
  try{body=await readExisting(origin,base,first,config,signal);
   if(body.length!==p.source.bytes||sha(body)!==p.source.ciphertext_sha256)fail('source_content_changed');
   const last=await metadata(signal);if(!same(first,last))fail('source_metadata_changed');return {...first,body};
  }catch(e){body?.fill(0);throw e;}
 };
 if(role==='target')core.createOnly=async(value,{signal}={})=>{
  closed();const owned=bytes(value,1,MAX_BYTES);
  try{
   if(owned.length!==p.source.bytes||sha(owned)!==p.source.ciphertext_sha256)fail('source_content_changed');
   const before=await metadata(signal);if(before.state!=='absent')fail('target_not_absent');await bucket(origin,config,signal);
   const r=await network(origin+apiPath(base,base.key),{method:'POST',body:owned,signal,maximum:MAX_JSON,
    headers:{'Content-Type':'application/octet-stream','Cache-Control':'no-store','x-upsert':'false'}});
   let accepted;try{accepted=r.status>=200&&r.status<300;}finally{r.body.fill(0);}
   if(!accepted)return {accepted:false};
   // A 2xx alone does not prove the complete body is retained: independently
   // inspect the target bytes and metadata before acknowledging this adapter.
   const observed=await core.inspect({signal});
   if(observed.state!=='present')return {accepted:false};
   try{return {accepted:observed.body.length===p.source.bytes&&sha(observed.body)===p.source.ciphertext_sha256};}
   finally{observed.body.fill(0);}
  }finally{owned.fill(0);}
 };
 return Object.freeze(core);
}
export const createManagedStorageAdapter=options=>factory(options,'managed');
export const createSyntheticStorageAdapter=options=>factory(options,'synthetic');
// Uses the same HTTPS request function as the candidate; restricted to a
// loopback TLS server so tests can check self-signed certificates are refused.
export async function syntheticTlsProbe(origin){
 assertCleanEnvironment();
 const u=new URL(origin);if(u.protocol!=='https:'||u.hostname!=='127.0.0.1'||!u.port||u.origin!==origin)fail('synthetic_only');
 return request(origin+'/',{method:'GET',ms:2000,maximum:1024});
}
