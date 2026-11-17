// Bounded protected-object transfer coordinator. This is not a production
// storage adapter or a business-row importer; see README before integration.
import {createCipheriv,createDecipheriv,createHash,randomBytes,timingSafeEqual} from 'node:crypto';
import {constants} from 'node:fs';
import {mkdir,open} from 'node:fs/promises';
import {join,resolve,isAbsolute} from 'node:path';
import {types as utilTypes} from 'node:util';
import {privateDirectory,readPrivateFile} from '../../current-archive/bundle.mjs';
import {validKey} from '../../../../supabase/functions/_shared/storage/protocol.js';

export const FORMAT='collect.protected-object-transfer.v1';
export const PROJECT='rrlduytparvsjfmegalh';
const HASH=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const MAX_OBJECT=8_000_000,MAX_PLAN=32768,MAX_RECORD=65536;
const failure=code=>{const e=Error(code);e.code=code;throw e;};
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const exact=(value,keys)=>value&&typeof value==='object'&&!Array.isArray(value)&&Object.getPrototypeOf(value)===Object.prototype&&Object.keys(value).sort().join('\0')===[...keys].sort().join('\0');
const same=(a,b)=>canonical(a)===canonical(b);
const result=(status,operation_id,extra={})=>({format:FORMAT,status,operation_id,automatic_retry:false,application_metadata_committed:false,production_cutover_authorized:false,...extra});
function ownedBytes(value,min,max){
 if(!Buffer.isBuffer(value)||utilTypes.isProxy(value))failure('invalid_bytes');
 try{const backing=value.buffer;if(utilTypes.isSharedArrayBuffer(backing)||backing.resizable===true||value.byteLength<min||value.byteLength>max)failure('invalid_bytes');return Buffer.from(value);}
 catch{failure('invalid_bytes');}
}
// Copy plain data properties only; reject proxies, accessors and exotic values.
function copyData(value,depth=0,state={nodes:0,bytes:0}){
 if(depth>12||++state.nodes>10000)failure('invalid_plan');
 if(typeof value==='string'){state.bytes+=Buffer.byteLength(value);if(state.bytes>MAX_PLAN)failure('invalid_plan');return value;}
 if(value===null||typeof value==='boolean'||Number.isSafeInteger(value))return value;
 if(!value||typeof value!=='object'||utilTypes.isProxy(value))failure('invalid_plan');
 const proto=Object.getPrototypeOf(value);if(proto!==Object.prototype&&proto!==Array.prototype)failure('invalid_plan');
 const ownKeys=Reflect.ownKeys(value);if(ownKeys.length>128||ownKeys.some(k=>typeof k!=='string'))failure('invalid_plan');
 const desc=Object.getOwnPropertyDescriptors(value),out=Array.isArray(value)?[]:{};
 for(const [key,entry] of Object.entries(desc)){
  if(Array.isArray(value)&&key==='length')continue;
  if(!Object.hasOwn(entry,'value')||!entry.enumerable||key==='__proto__'||key==='constructor'||key==='prototype')failure('invalid_plan');
  state.bytes+=Buffer.byteLength(key);if(state.bytes>MAX_PLAN)failure('invalid_plan');
  out[key]=copyData(entry.value,depth+1,state);
 }
 if(Array.isArray(value)&&Object.keys(out).length!==value.length)failure('invalid_plan');
 return out;
}
function canonical(value){
 if(value===null||typeof value!=='object')return JSON.stringify(value);
 if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
 return '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}';
}
const small=(s,n=1024)=>typeof s==='string'&&s.length>0&&Buffer.byteLength(s)<=n&&!/[\u0000-\u001f\u007f]/.test(s);
function origin(text,kind){
 if(!small(text,512))failure('invalid_plan');let u;try{u=new URL(text);}catch{failure('invalid_plan');}
 if(u.origin!==text||u.username||u.password||u.pathname!=='/'||u.search||u.hash)failure('invalid_plan');
 if(kind==='managed'&&text!==`https://${PROJECT}.supabase.co`)failure('invalid_plan');
 if(kind==='synthetic'&&(u.protocol!=='http:'||u.hostname!=='127.0.0.1'||!u.port))failure('invalid_plan');
}
export function planDigest(input){const plan=copyData(input),s=canonical(plan);if(Buffer.byteLength(s)>MAX_PLAN)failure('invalid_plan');return sha(Buffer.from(s));}
function validatePlan(input,expected){
 const p=copyData(input);
 if(!exact(p,['format','operation_id','mode','source','target','authority'])||p.format!==FORMAT||!UUID.test(p.operation_id??'')||!['managed','synthetic'].includes(p.mode)||!HASH.test(expected??'')||planDigest(p)!==expected)failure('invalid_plan');
 const s=p.source,t=p.target,a=p.authority;
 if(!exact(s,['origin','bucket','key','object_id','version','etag','bytes','ciphertext_sha256','namespace_sha256','binding_sha256','key_aad_sha256'])||
  !exact(t,['origin','bucket','key','namespace_sha256','key_aad_sha256'])||
  !exact(a,['source_identity_sha256','target_identity_sha256','source_fence_sha256','target_fence_sha256','mapping_sha256']))failure('invalid_plan');
 origin(s.origin,p.mode==='synthetic'?'synthetic':'source');origin(t.origin,p.mode);
 if(p.mode==='managed'&&new URL(s.origin).protocol!=='https:')failure('invalid_plan');
 for(const x of [s,t]){if(!small(x.bucket,128)||!small(x.key)||!/^[-a-zA-Z0-9_]+$/.test(x.bucket))failure('invalid_plan');try{validKey(x.key);}catch{failure('invalid_plan');}}
 if(!small(s.object_id,128)||!small(s.version,512)||!small(s.etag,512)||!Number.isSafeInteger(s.bytes)||s.bytes<1||s.bytes>MAX_OBJECT||
  ![s.ciphertext_sha256,s.namespace_sha256,s.binding_sha256,s.key_aad_sha256,t.namespace_sha256,t.key_aad_sha256,...Object.values(a)].every(x=>HASH.test(x??''))||
  s.key_aad_sha256!==t.key_aad_sha256||(s.origin===t.origin&&s.bucket===t.bucket&&s.key===t.key))failure('invalid_plan');
 return p;
}
// Return a defensive plain-data copy only after the full plan is validated.
export function validatedTransferPlan(input,expected){return validatePlan(input,expected);}
async function syncDirectory(path){const d=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);try{await d.sync();}finally{await d.close();}}
async function writeRecord(dir,name,record,key,operationId){
 const raw=Buffer.from(canonical(record)),iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv,{authTagLength:16});
 if(raw.length<1||raw.length>MAX_PLAN)failure('journal_unavailable');
 try{
  cipher.setAAD(Buffer.from(FORMAT+'\n'+operationId+'\n'+name));
  const ciphertext=Buffer.concat([cipher.update(raw),cipher.final()]);
  const body=Buffer.from(canonical({iv:iv.toString('base64url'),tag:cipher.getAuthTag().toString('base64url'),ciphertext:ciphertext.toString('base64url')}));
  const f=await open(join(dir,name),constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,0o600);
  try{await f.writeFile(body);await f.sync();}finally{await f.close();}
  await syncDirectory(dir);
 }finally{raw.fill(0);}
}
async function readRecord(dir,name,key,operationId){
 const body=await readPrivateFile(join(dir,name),MAX_RECORD);let raw,updated,final;
 try{
  const text=new TextDecoder('utf-8',{fatal:true}).decode(body),e=JSON.parse(text);
  if(!exact(e,['iv','tag','ciphertext'])||canonical(e)!==text)failure('journal_invalid');
  const parse=(v,size)=>{if(typeof v!=='string'||!/^[A-Za-z0-9_-]+$/.test(v))failure('journal_invalid');const b=Buffer.from(v,'base64url');if(b.toString('base64url')!==v||(size!==undefined&&b.length!==size))failure('journal_invalid');return b;};
  const iv=parse(e.iv,12),tag=parse(e.tag,16),encrypted=parse(e.ciphertext);if(encrypted.length>MAX_PLAN)failure('journal_invalid');
  const decipher=createDecipheriv('aes-256-gcm',key,iv,{authTagLength:16});decipher.setAAD(Buffer.from(FORMAT+'\n'+operationId+'\n'+name));decipher.setAuthTag(tag);
  updated=decipher.update(encrypted);final=decipher.final();raw=Buffer.concat([updated,final]);const decoded=new TextDecoder('utf-8',{fatal:true}).decode(raw),r=JSON.parse(decoded);
  if(canonical(r)!==decoded)failure('journal_invalid');return r;
 }catch{failure('journal_invalid');}finally{body.fill(0);updated?.fill(0);final?.fill(0);raw?.fill(0);}
}
async function operationDirectory(root,id,{create=false}={}){
 if(typeof root!=='string'||!isAbsolute(root)||resolve(root)!==root)failure('journal_unavailable');
 await privateDirectory(root);const dir=join(root,id);
 if(create){try{await mkdir(dir,{mode:0o700});await syncDirectory(root);}catch(e){if(e?.code==='EEXIST')failure('operation_already_exists');failure('journal_unavailable');}}
 await privateDirectory(dir);return dir;
}
function dataRecord(value,keys){
 if(!value||utilTypes.isProxy(value)||!exact(value,keys)||Reflect.ownKeys(value).length!==keys.length)failure('adapter_unconfirmed');
 const d=Object.getOwnPropertyDescriptors(value);
 for(const entry of Object.values(d))if(!entry.enumerable||!Object.hasOwn(entry,'value'))failure('adapter_unconfirmed');
}
function targetState(value){
 if(!value||typeof value!=='object'||utilTypes.isProxy(value))failure('target_unconfirmed');
 const state=Object.getOwnPropertyDescriptor(value,'state');
 if(!state||!Object.hasOwn(state,'value'))failure('target_unconfirmed');return state.value;
}
function sourceCheck(observed,p,includeBytes){
 const s=p.source,a=p.authority;
 dataRecord(observed,includeBytes?['origin','bucket','key','object_id','version','etag','bytes','ciphertext_sha256','namespace_sha256','binding_sha256','key_aad_sha256','identity_sha256','fence_sha256','body']:['origin','bucket','key','object_id','version','etag','bytes','ciphertext_sha256','namespace_sha256','binding_sha256','key_aad_sha256','identity_sha256','fence_sha256']);
 const {body,...metadata}=observed;
 const expected={...s,identity_sha256:a.source_identity_sha256,fence_sha256:a.source_fence_sha256};
 if(Object.keys(expected).some(key=>metadata[key]!==expected[key]))failure('source_changed');
 if(!includeBytes)return null;
 const data=ownedBytes(body,1,MAX_OBJECT);if(data.length!==s.bytes||sha(data)!==s.ciphertext_sha256){data.fill(0);failure('source_content_changed');}return data;
}
function targetCheck(observed,p,required,{matchExpected=true}={}){
 const a=p.authority,t=p.target;
 dataRecord(observed,required==='absent'?['origin','bucket','key','identity_sha256','fence_sha256','namespace_sha256','private_bucket','state','absence_verified']:['origin','bucket','key','identity_sha256','fence_sha256','namespace_sha256','private_bucket','state','object_id','version','etag','body']);
 if(!observed||observed.origin!==t.origin||observed.bucket!==t.bucket||observed.key!==t.key||observed.identity_sha256!==a.target_identity_sha256||observed.fence_sha256!==a.target_fence_sha256||observed.namespace_sha256!==t.namespace_sha256||observed.private_bucket!==true||observed.state!==required)failure('target_unconfirmed');
 if(required==='absent'){
  if(observed.absence_verified!==true)failure('target_unconfirmed');
  return null;
 }
 if(!small(observed.object_id,128)||!small(observed.version,512)||!small(observed.etag,512))failure('target_unconfirmed');
 const data=ownedBytes(observed.body,0,MAX_OBJECT);try{if(matchExpected&&(data.length!==p.source.bytes||sha(data)!==p.source.ciphertext_sha256))failure('target_content_conflict');}finally{data.fill(0);}return {object_id:observed.object_id,version:observed.version,etag:observed.etag};
}
function interfaces(source,target,{write}={}){
 if(!source||!target||typeof source.inspect!=='function'||typeof target.inspect!=='function'||
  (write&&(typeof source.read!=='function'||typeof target.createOnly!=='function')))failure('adapters_required');
}
function code(error){return ['source_unconfirmed','source_changed','source_content_changed','target_unconfirmed','target_content_conflict','invalid_bytes'].includes(error?.code)?error.code:'adapter_unconfirmed';}
async function boundedCall(callback,ms){
 const controller=new AbortController();let timer;
 const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();try{failure('adapter_timeout');}catch(e){reject(e);}},ms);});
 try{return await Promise.race([Promise.resolve().then(()=>callback(controller.signal)),deadline]);}
 finally{clearTimeout(timer);controller.abort();}
}

// A durable intent and pre-dispatch marker precede the only createOnly call.
// Existing operation directories are never retried by this method.
export async function transferObject({plan,expectedPlanSha256,journalRoot,journalKey,source,target,requestMs=30000}={}){
 let key,data,dir,dispatched=false,p;
 try{
  key=ownedBytes(journalKey,32,32);p=validatePlan(plan,expectedPlanSha256);
  if(!Number.isInteger(requestMs)||requestMs<1||requestMs>30000)failure('invalid_plan');
  // There is no qualified managed Storage adapter, fence attestation, or
  // application-metadata transaction in this candidate. Do not let arbitrary
  // callbacks turn a synthetic proof into a live production write.
  if(p.mode!=='synthetic')return result('refused',p.operation_id,{code:'managed_adapter_unqualified'});
  interfaces(source,target,{write:true});
  try{dir=await operationDirectory(journalRoot,p.operation_id,{create:true});}catch(e){if(e?.code==='operation_already_exists')return result('reconcile_required',p.operation_id);throw e;}
  await writeRecord(dir,'intent.enc',{plan:p,plan_sha256:expectedPlanSha256},key,p.operation_id);
  data=sourceCheck(await boundedCall(signal=>source.read({signal}),requestMs),p,true);sourceCheck(await boundedCall(signal=>source.inspect({signal}),requestMs),p,false);
  const initial=await boundedCall(signal=>target.inspect({signal}),requestMs);
  if(targetState(initial)==='present'){
   targetCheck(initial,p,'present',{matchExpected:false});
   await writeRecord(dir,'outcome.enc',{status:'preexisting_conflict'},key,p.operation_id);return result('preexisting_conflict',p.operation_id);
  }
  targetCheck(initial,p,'absent');
  await writeRecord(dir,'attempt.enc',{status:'dispatch_intended'},key,p.operation_id);
  dispatched=true;
  // An uncooperative transport may complete after our deadline. Give it its
  // own bytes and keep those bytes intact until its promise settles; wiping
  // the caller's buffer on timeout must not corrupt a later provider request.
  const sendBytes=Buffer.from(data);
  let response;try{response=await boundedCall(signal=>{
   const pending=Promise.resolve().then(()=>target.createOnly(sendBytes,{signal}));
   pending.then(()=>sendBytes.fill(0),()=>sendBytes.fill(0));return pending;
  },requestMs);}catch{response=null;}
  try{dataRecord(response,['accepted']);}catch{response=null;}
  if(!response||response.accepted!==true){await writeRecord(dir,'outcome.enc',{status:'dispatch_unconfirmed'},key,p.operation_id);return result('dispatch_unconfirmed',p.operation_id);}
  sourceCheck(await boundedCall(signal=>source.inspect({signal}),requestMs),p,false);const identity=targetCheck(await boundedCall(signal=>target.inspect({signal}),requestMs),p,'present');
  await writeRecord(dir,'outcome.enc',{status:'content_verified',target:identity},key,p.operation_id);
  return result('content_verified',p.operation_id,{source_snapshot_atomic:false,provider_atomicity_independently_verified:false});
 }catch(e){
  const op=p?.operation_id??null;
  if(dispatched){try{if(dir&&key)await writeRecord(dir,'outcome.enc',{status:'dispatch_unconfirmed'},key,op);}catch{}return result('dispatch_unconfirmed',op);}
  if(dir&&key)try{await writeRecord(dir,'outcome.enc',{status:'refused_before_dispatch',code:code(e)},key,op);}catch{return result('journal_unconfirmed',op);}
  return result(dir?'refused_before_dispatch':'refused',op,{code:dir?code(e):(e?.code==='invalid_plan'?'invalid_plan':'journal_unavailable')});
 }finally{key?.fill(0);data?.fill(0);}
}

// Read-only: a matching object does not prove this request created it, and an
// absent snapshot does not prove an earlier request cannot still commit.
export async function reconcileObject({plan,expectedPlanSha256,journalRoot,journalKey,source,target,requestMs=30000}={}){
 let key,p;
 try{
  key=ownedBytes(journalKey,32,32);p=validatePlan(plan,expectedPlanSha256);
  if(!Number.isInteger(requestMs)||requestMs<1||requestMs>30000)failure('invalid_plan');
  if(p.mode!=='synthetic')return result('reconciliation_unconfirmed',p.operation_id,{code:'managed_adapter_unqualified',retry_authorized:false});
  interfaces(source,target);
  const dir=await operationDirectory(journalRoot,p.operation_id),intent=await readRecord(dir,'intent.enc',key,p.operation_id),attempt=await readRecord(dir,'attempt.enc',key,p.operation_id);
  if(!exact(intent,['plan','plan_sha256'])||!same(intent.plan,p)||!timingSafeEqual(Buffer.from(intent.plan_sha256??'','utf8'),Buffer.from(expectedPlanSha256,'utf8'))||!same(attempt,{status:'dispatch_intended'}))failure('journal_invalid');
  sourceCheck(await boundedCall(signal=>source.inspect({signal}),requestMs),p,false);const state=await boundedCall(signal=>target.inspect({signal}),requestMs);
  if(targetState(state)==='absent'){targetCheck(state,p,'absent');return result('absent_at_readback',p.operation_id,{retry_authorized:false});}
  targetCheck(state,p,'present');return result('matching_content_at_readback',p.operation_id,{creation_attribution_verified:false,retry_authorized:false});
 }catch(e){return result('reconciliation_unconfirmed',p?.operation_id??null,{code:code(e),retry_authorized:false});}finally{key?.fill(0);}
}
