// Offline, bounded witness custody only: no database, provider, credential
// lookup, active-row writer or network adapter. See README before integration.
import {createCipheriv,createDecipheriv,createHash,randomBytes} from 'node:crypto';
import {mkdir,open} from 'node:fs/promises';
import {constants} from 'node:fs';
import {isAbsolute,join,resolve} from 'node:path';
import {types} from 'node:util';
import {privateDirectory,readPrivateFile} from '../../current-archive/bundle.mjs';

export const FORMAT='collect.unlinked-history-witness.v1';
const HASH=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const KEY_ID=/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const MAX_PLAN=32768,MAX_CIPHER=524288,MAX_RECORD=2_000_000;
const sha=x=>createHash('sha256').update(x).digest('hex');
const fail=code=>{const e=new Error(code);e.code=code;throw e;};
const exact=(x,keys)=>x&&typeof x==='object'&&!Array.isArray(x)&&Object.getPrototypeOf(x)===Object.prototype&&
 Object.keys(x).sort().join('\0')===[...keys].sort().join('\0');
const canonical=x=>x===null||typeof x!=='object'?JSON.stringify(x):Array.isArray(x)?'['+x.map(canonical).join(',')+']':
 '{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+canonical(x[k])).join(',')+'}';
const same=(a,b)=>canonical(a)===canonical(b);
const text=(s,n)=>typeof s==='string'&&s.length>0&&Buffer.byteLength(s)<=n&&!/[\u0000-\u001f\u007f]/.test(s)&&Buffer.from(s,'utf8').toString('utf8')===s;
const typed=Object.getPrototypeOf(Uint8Array.prototype),getBuffer=Object.getOwnPropertyDescriptor(typed,'buffer').get;
const getLength=Object.getOwnPropertyDescriptor(typed,'byteLength').get,getOffset=Object.getOwnPropertyDescriptor(typed,'byteOffset').get;
const resizable=Object.getOwnPropertyDescriptor(ArrayBuffer.prototype,'resizable')?.get;
function bytes(b,min,max){
 if(types.isProxy(b)||!Buffer.isBuffer(b)||Object.getPrototypeOf(b)!==Buffer.prototype)fail('invalid_input');
 try{const backing=getBuffer.call(b),size=getLength.call(b),offset=getOffset.call(b);
  if(types.isSharedArrayBuffer(backing)||(resizable&&resizable.call(backing))||size<min||size>max)fail('invalid_input');
  const out=Buffer.alloc(size);Uint8Array.prototype.set.call(out,new Uint8Array(backing,offset,size));return out;
 }catch{fail('invalid_input');}
}
function entity(owner,request){
 const h=sha('collect.storage.entity.v1\nburimunsi.native.observation.v1\n'+owner+'\n'+request);
 return h.slice(0,8)+'-'+h.slice(8,12)+'-5'+h.slice(13,16)+'-8'+h.slice(17,20)+'-'+h.slice(20,32);
}
export function nativeObservationId(owner,request){
 if(!text(owner,128)||!UUID.test(request??''))fail('invalid_input');return entity(owner,request);
}
function parsePlan(serialized,expected){
 if(typeof serialized!=='string'||Buffer.byteLength(serialized)>MAX_PLAN||!HASH.test(expected??'')||sha(serialized)!==expected)fail('invalid_plan');
 let p;try{p=JSON.parse(serialized);if(canonical(p)!==serialized)fail('invalid_plan');}catch{fail('invalid_plan');}
 if(!exact(p,['format','operation_id','source','target','reservation','intent','object'])||p.format!==FORMAT||!UUID.test(p.operation_id??''))fail('invalid_plan');
 const s=p.source,t=p.target,r=p.reservation,i=p.intent,o=p.object;
 if(!exact(s,['id','owner','request_id','body_sha256','object_sha256','size_bytes','fingerprint'])||
  !UUID.test(s.id??'')||!UUID.test(s.request_id??'')||!text(s.owner,128)||![s.body_sha256,s.object_sha256,s.fingerprint].every(v=>HASH.test(v??''))||
  !Number.isSafeInteger(s.size_bytes)||s.size_bytes<1||s.size_bytes>131072||entity(s.owner,s.request_id)!==s.id||
  !exact(t,['owner','key_id'])||!text(t.owner,128)||!KEY_ID.test(t.key_id??'')||
  !exact(r,['key','scope','aad','key_id','plaintext_sha256','source_fingerprint'])||
  !exact(i,['key','operation_id','fingerprint','sha256','size','scope','http_metadata','custom_metadata','state','active_attempt','upload_unresolved','delete_tombstone'])||
  !exact(o,['key','operation_id','fingerprint','sha256','size','scope','http_metadata','custom_metadata']))fail('invalid_plan');
 const scope={ownerId:s.owner,purpose:'sms_receipt',entityId:s.id};
 const aad='sms:'+s.id+':'+s.object_sha256,objectKey='sms/'+s.id,http={contentType:'application/octet-stream'};
 if(r.key!==objectKey||r.aad!==aad||!same(r.scope,scope)||!KEY_ID.test(r.key_id??'')||t.key_id!==r.key_id||
  r.plaintext_sha256!==s.object_sha256||!HASH.test(r.source_fingerprint??'')||i.key!==objectKey||i.state!=='committed'||
  i.active_attempt!==null||i.upload_unresolved!==false||i.delete_tombstone!==false||!same(i.scope,scope)||!same(i.http_metadata,http)||
  !HASH.test(i.fingerprint??'')||!HASH.test(i.sha256??'')||!Number.isSafeInteger(i.size)||i.size<1||i.size>MAX_CIPHER||
  i.operation_id!==sha('collect.storage.put.v1\n'+objectKey))fail('invalid_source_binding');
 const sourceDescriptor={scope,aad,keyId:r.key_id,plaintextSha256:s.object_sha256,requestDigest:s.fingerprint,httpMetadata:http,
  customMetadata:{sha256:s.object_sha256,key_id:r.key_id}};
 const custom={...sourceDescriptor.customMetadata,source_fingerprint:r.source_fingerprint};
 const putDescriptor={key:objectKey,size:i.size,sha256:i.sha256,scope,httpMetadata:http,customMetadata:custom};
 if(sha(canonical(sourceDescriptor))!==r.source_fingerprint||!same(i.custom_metadata,custom)||sha(canonical(putDescriptor))!==i.fingerprint||
  !same(o,{key:i.key,operation_id:i.operation_id,fingerprint:i.fingerprint,sha256:i.sha256,size:i.size,scope:i.scope,
   http_metadata:i.http_metadata,custom_metadata:i.custom_metadata}))fail('invalid_source_binding');
 return p;
}
function b64(s,n){
 if(typeof s!=='string'||s.length%4!==0||!/^[A-Za-z0-9+/]*={0,2}$/.test(s))fail('ciphertext_invalid');
 const b=Buffer.from(s,'base64');if(b.toString('base64')!==s||(n!==undefined&&b.length!==n))fail('ciphertext_invalid');return b;
}
function decrypt(body,key,p){
 let d,up,fin,result;
 try{
  const raw=new TextDecoder('utf-8',{fatal:true}).decode(body),x=JSON.parse(raw);
  if(!exact(x,['v','kid','iv','data'])||JSON.stringify(x)!==raw||x.v!==1||x.kid!==p.reservation.key_id)fail('ciphertext_invalid');
  const iv=b64(x.iv,12),data=b64(x.data);if(data.length<17)fail('ciphertext_invalid');
  d=createDecipheriv('aes-256-gcm',key,iv,{authTagLength:16});d.setAAD(Buffer.from(p.reservation.aad));d.setAuthTag(data.subarray(-16));
  up=d.update(data.subarray(0,-16));fin=d.final();result=Buffer.concat([up,fin]);return result;
 }catch(e){result?.fill(0);if(e?.code==='ciphertext_invalid')throw e;fail('ciphertext_authentication_failed');}
 finally{up?.fill(0);fin?.fill(0);}
}
function verify(p,body,sourceKey,targetKey){
 if(body.length!==p.intent.size||sha(body)!==p.intent.sha256)fail('ciphertext_changed');
 let source,target;
 try{
  source=decrypt(body,sourceKey,p);target=decrypt(body,targetKey,p);
  if(!source.equals(target)||source.length!==p.source.size_bytes||sha(source)!==p.source.object_sha256)fail('plaintext_changed');
  let data,raw;try{raw=new TextDecoder('utf-8',{fatal:true}).decode(source);data=JSON.parse(raw);}catch{fail('plaintext_invalid');}
  if(!data||typeof data!=='object'||Array.isArray(data)||JSON.stringify(data)!==raw||
   data.provenance!=='native_observation_unverified'||!((data.source_mode==='live'&&data.complete===true)||(data.source_mode==='catch_up'&&data.complete===false))||
   !text(data.raw_sender,384)||data.raw_sender.length>96||typeof data.raw_body!=='string'||!data.raw_body.length||
   Buffer.byteLength(data.raw_body)>3000||data.raw_body.includes('\0')||sha(Buffer.from(data.raw_body,'utf8'))!==p.source.body_sha256)fail('plaintext_invalid');
  return {source_and_target_key_decrypt_same_object:true,plaintext_hash_and_body_hash_match:true,
   original_owner_source_id_matches:true,target_owner_derives_same_source_id:entity(p.target.owner,p.source.request_id)===p.source.id,
   source_identity_or_mapping_verified:false,provider_or_storage_verified:false,write_authorized:false};
 }finally{source?.fill(0);target?.fill(0);}
}
function b64u(s){if(typeof s!=='string'||!/^[A-Za-z0-9_-]+$/.test(s))fail('record_invalid');const b=Buffer.from(s,'base64url');if(b.toString('base64url')!==s)fail('record_invalid');return b;}
async function syncDir(dir){const d=await open(dir,constants.O_RDONLY|constants.O_NOFOLLOW);try{await d.sync();}finally{await d.close();}}
async function writeRecord(dir,name,record,key,id){
 const raw=Buffer.from(canonical(record));
 try{
  if(raw.length<1||raw.length>MAX_RECORD)fail('record_invalid');
  const iv=randomBytes(12),c=createCipheriv('aes-256-gcm',key,iv);c.setAAD(Buffer.from(FORMAT+'\n'+id+'\n'+name));
  const ct=Buffer.concat([c.update(raw),c.final()]);const out=Buffer.from(canonical({iv:iv.toString('base64url'),tag:c.getAuthTag().toString('base64url'),data:ct.toString('base64url')}));
  await privateDirectory(dir);const f=await open(join(dir,name),constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,0o600);
  try{await f.writeFile(out);await f.sync();}finally{await f.close();}await syncDir(dir);return sha(out);
 }finally{raw.fill(0);}
}
async function readRecord(dir,name,key,id){
 let body,up,fin,raw;
 try{
  body=await readPrivateFile(join(dir,name),Math.ceil(MAX_RECORD*4/3)+1024);const text=new TextDecoder('utf-8',{fatal:true}).decode(body),e=JSON.parse(text);
  if(!exact(e,['iv','tag','data'])||canonical(e)!==text)fail('record_invalid');const iv=b64u(e.iv),tag=b64u(e.tag),encrypted=b64u(e.data);
  if(iv.length!==12||tag.length!==16||encrypted.length>MAX_RECORD)fail('record_invalid');
  const d=createDecipheriv('aes-256-gcm',key,iv);d.setAAD(Buffer.from(FORMAT+'\n'+id+'\n'+name));d.setAuthTag(tag);
  up=d.update(encrypted);fin=d.final();raw=Buffer.concat([up,fin]);const str=new TextDecoder('utf-8',{fatal:true}).decode(raw),record=JSON.parse(str);
  if(canonical(record)!==str)fail('record_invalid');return {record,encryptedHash:sha(body)};
 }catch{fail('record_invalid');}finally{body?.fill(0);up?.fill(0);fin?.fill(0);raw?.fill(0);}
}
async function directory(root,id,create){
 if(typeof root!=='string'||!isAbsolute(root)||resolve(root)!==root)fail('custody_unavailable');await privateDirectory(root);
 const dir=join(root,id);let created=false;
 try{
  if(create){try{await mkdir(dir,{mode:0o700});created=true;}
   catch(e){if(e?.code==='EEXIST')fail('operation_exists');fail('claim_creation_unconfirmed');}await syncDir(root);}
  await privateDirectory(dir);return dir;
 }catch(e){if(e?.code==='operation_exists'||e?.code==='claim_creation_unconfirmed')throw e;
  if(created)fail('claim_creation_unconfirmed');fail('custody_unavailable');}
}
const response=(status,extra={})=>({format:FORMAT,status,automatic_retry:false,external_dispatch:false,production_write_authorized:false,...extra});

// Stores one independently validated, encrypted offline witness. The caller
// provides all bytes and keys privately; this function does no credential IO.
export async function retainOfflineWitness({planJson,expectedPlanSha256,root,journalKey,ciphertext,sourceKey,targetKey}={}){
 let key,sk,tk,body,p,dir;
 try{
  p=parsePlan(planJson,expectedPlanSha256);key=bytes(journalKey,32,32);sk=bytes(sourceKey,32,32);tk=bytes(targetKey,32,32);body=bytes(ciphertext,1,MAX_CIPHER);
  if(key.equals(sk)||key.equals(tk))fail('invalid_input');
  try{dir=await directory(root,p.operation_id,true);}catch(e){if(e?.code==='operation_exists')return response('reconciliation_required');throw e;}
  await writeRecord(dir,'intent.enc',{planJson,planSha256:expectedPlanSha256},key,p.operation_id);
  const observation=verify(p,body,sk,tk);
  const artifactHash=await writeRecord(dir,'artifact.enc',{planSha256:expectedPlanSha256,ciphertext:body.toString('base64'),observation},key,p.operation_id);
  await writeRecord(dir,'receipt.enc',{planSha256:expectedPlanSha256,artifactHash},key,p.operation_id);
  const checked=await reconcileOfflineWitness({planJson,expectedPlanSha256,root,journalKey:key});
  if(checked.status!=='witness_and_receipt_authenticated')fail('readback_unconfirmed');
  return response('witness_retained',{target_owner_derives_same_source_id:observation.target_owner_derives_same_source_id});
 }catch(e){return response(dir||e?.code==='claim_creation_unconfirmed'?'custody_incomplete_do_not_retry':'refused',
  {code:dir?'custody_or_verification_unconfirmed':(e?.code??'custody_unavailable')});}
 finally{key?.fill(0);sk?.fill(0);tk?.fill(0);body?.fill(0);}
}

// Read-only reconciliation only checks an authenticated local receipt and exact
// ciphertext hash. It cannot establish configured provider keys or dispatch.
export async function reconcileOfflineWitness({planJson,expectedPlanSha256,root,journalKey}={}){
 let key;
 try{
  const p=parsePlan(planJson,expectedPlanSha256);key=bytes(journalKey,32,32);const dir=await directory(root,p.operation_id,false);
  const intent=(await readRecord(dir,'intent.enc',key,p.operation_id)).record;
  const artifact=await readRecord(dir,'artifact.enc',key,p.operation_id),receipt=(await readRecord(dir,'receipt.enc',key,p.operation_id)).record;
  if(!same(intent,{planJson,planSha256:expectedPlanSha256})||!exact(receipt,['planSha256','artifactHash'])||receipt.planSha256!==expectedPlanSha256||
   receipt.artifactHash!==artifact.encryptedHash||!exact(artifact.record,['planSha256','ciphertext','observation'])||artifact.record.planSha256!==expectedPlanSha256)
   fail('record_invalid');
  const cipher=b64(artifact.record.ciphertext);try{if(cipher.length!==p.intent.size||sha(cipher)!==p.intent.sha256)fail('record_invalid');}finally{cipher.fill(0);}
  const o=artifact.record.observation;
  if(!same(o,{source_and_target_key_decrypt_same_object:true,plaintext_hash_and_body_hash_match:true,
   original_owner_source_id_matches:true,target_owner_derives_same_source_id:entity(p.target.owner,p.source.request_id)===p.source.id,
   source_identity_or_mapping_verified:false,provider_or_storage_verified:false,write_authorized:false}))fail('record_invalid');
  return response('witness_and_receipt_authenticated',{target_owner_derives_same_source_id:o.target_owner_derives_same_source_id});
 }catch{return response('custody_unconfirmed_do_not_retry');}finally{key?.fill(0);}
}

// Live transfers and application-table imports need separate qualified source,
// identity, object, worker and writer-exclusion mechanisms; none is supplied.
export function managedTransfer(){return response('managed_transfer_unqualified');}
