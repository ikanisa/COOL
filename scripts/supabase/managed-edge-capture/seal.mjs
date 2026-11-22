// Bounded in-memory encryption of opaque provider function bodies. No network.
import {createCipheriv,createDecipheriv,createHash,randomBytes} from 'node:crypto';

export const PROJECT='rrlduytparvsjfmegalh';
export const SLUGS=Object.freeze(['collect-api','admin-api','collect-jobs']);
export const MAX_BODY=20*1024*1024;
export const MAX_ARCHIVE=SLUGS.length*MAX_BODY+65536;
const MAGIC=Buffer.from('COLLECTEDGE1'),IV=12,TAG=16,UUID=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const HASH=/^[0-9a-f]{64}$/;
const sha=b=>createHash('sha256').update(b).digest('hex');
const exact=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).sort().join('\0')===[...keys].sort().join('\0');
export class CaptureError extends Error{constructor(code){super(code);this.name='CaptureError';this.code=code;}}
const need=(x,c)=>{if(!x)throw new CaptureError(c);};
function keyCopy(key){need(Buffer.isBuffer(key)&&key.length===32,'KEY_INVALID');return Buffer.from(key);}
function entry(m,slug){
 need(m&&typeof m==='object'&&!Array.isArray(m)&&m.slug===slug&&m.status==='ACTIVE'&&UUID.test(m.id??'')&&
  Number.isSafeInteger(m.version)&&m.version>0&&Number.isSafeInteger(m.updated_at)&&m.updated_at>0&&
  (m.ezbr_sha256===null||HASH.test(m.ezbr_sha256??'')),'METADATA_INVALID');
 return {slug,id:m.id,status:m.status,version:m.version,updated_at:m.updated_at,provider_ezbr_sha256:m.ezbr_sha256};
}
export function validateMetadata(m,slug){return entry(m,slug);}
function manifest(records,operationId,scope,planSha256){
 need(UUID.test(operationId??'')&&HASH.test(planSha256??'')&&['managed','synthetic'].includes(scope)&&Array.isArray(records)&&records.length===SLUGS.length,'INPUT_INVALID');
 const entries=records.map((r,i)=>{
  const m=entry(r.metadata,SLUGS[i]),body=r.body;
  need(Buffer.isBuffer(body)&&body.length>=1&&body.length<=MAX_BODY,'BODY_INVALID');
  const bodySha=sha(body);
  // The body endpoint does not promise the same representation as the upload.
  return {...m,body_sha256:bodySha,body_bytes:body.length,
   provider_digest_matches_body:m.provider_ezbr_sha256===null?null:m.provider_ezbr_sha256===bodySha};
 });
 need(new Set(entries.map(e=>e.id)).size===SLUGS.length,'METADATA_INVALID');
 return {format:'collect.edge-bundle.v1',project_ref:PROJECT,scope,operation_id:operationId,plan_sha256:planSha256,
  representation:'opaque_provider_response',functions:entries};
}
function header(operationId,scope,planSha256,iv){return Buffer.concat([MAGIC,Buffer.from([scope==='managed'?1:0]),Buffer.from(operationId),Buffer.from(planSha256),iv]);}
export function sealFunctionBodies({records,operationId,scope,planSha256,key}={}){
 const info=manifest(records,operationId,scope,planSha256),meta=Buffer.from(JSON.stringify(info),'utf8');
 need(meta.length<=32768,'METADATA_BOUND');const k=keyCopy(key),iv=randomBytes(IV),aad=header(operationId,scope,planSha256,iv);
 let ciphertext;
 try{
  const c=createCipheriv('aes-256-gcm',k,iv);c.setAAD(aad);const len=Buffer.alloc(4);len.writeUInt32BE(meta.length);
  const chunks=[aad,c.update(len),c.update(meta)];
  for(const r of records){const n=Buffer.alloc(4);n.writeUInt32BE(r.body.length);chunks.push(c.update(n),c.update(r.body));}
  chunks.push(c.final(),c.getAuthTag());ciphertext=Buffer.concat(chunks);need(ciphertext.length<=MAX_ARCHIVE,'ARCHIVE_BOUND');
  return {archive:ciphertext,functions:info.functions};
 }finally{k.fill(0);meta.fill(0);}
}
// Returns only non-source metadata. Decrypted source bytes are never returned.
export function inspectSealedFunctionBodies({archive,key,operationId,scope,planSha256}={}){
 need(Buffer.isBuffer(archive)&&archive.length<=MAX_ARCHIVE&&archive.length>MAGIC.length+1+36+64+IV+TAG,'ARCHIVE_INVALID');
 need(UUID.test(operationId??'')&&HASH.test(planSha256??'')&&['managed','synthetic'].includes(scope),'INPUT_INVALID');
 const headLen=MAGIC.length+1+36+64+IV,aad=archive.subarray(0,headLen),expected=header(operationId,scope,planSha256,aad.subarray(headLen-IV));
 need(aad.equals(expected),'ARCHIVE_BINDING_MISMATCH');const k=keyCopy(key);let update,final,plain;
 try{
  const d=createDecipheriv('aes-256-gcm',k,aad.subarray(headLen-IV));d.setAAD(aad);d.setAuthTag(archive.subarray(archive.length-TAG));
  update=d.update(archive.subarray(headLen,archive.length-TAG));final=d.final();plain=Buffer.concat([update,final]);
  let pos=0;const number=()=>{need(pos+4<=plain.length,'ARCHIVE_INVALID');const n=plain.readUInt32BE(pos);pos+=4;return n;};
  const n=number();need(n>0&&n<=32768&&pos+n<=plain.length,'ARCHIVE_INVALID');let info;
  try{info=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(plain.subarray(pos,pos+n)));}catch{throw new CaptureError('ARCHIVE_INVALID');}pos+=n;
  need(exact(info,['format','project_ref','scope','operation_id','plan_sha256','representation','functions'])&&info.format==='collect.edge-bundle.v1'&&info.project_ref===PROJECT&&info.operation_id===operationId&&info.scope===scope&&info.plan_sha256===planSha256&&
   info.representation==='opaque_provider_response'&&Array.isArray(info.functions)&&info.functions.length===SLUGS.length,'ARCHIVE_INVALID');
  for(let i=0;i<SLUGS.length;i++){
   const m=info.functions[i],size=number();need(exact(m,['slug','id','status','version','updated_at','provider_ezbr_sha256','body_sha256','body_bytes','provider_digest_matches_body'])&&m.slug===SLUGS[i]&&m.status==='ACTIVE'&&UUID.test(m.id??'')&&Number.isSafeInteger(m.version)&&m.version>0&&
    Number.isSafeInteger(m.updated_at)&&m.updated_at>0&&HASH.test(m.body_sha256??'')&&
    (m.provider_ezbr_sha256===null||HASH.test(m.provider_ezbr_sha256??''))&&
    m.provider_digest_matches_body===(m.provider_ezbr_sha256===null?null:m.provider_ezbr_sha256===m.body_sha256)&&size===m.body_bytes&&size>=1&&size<=MAX_BODY&&pos+size<=plain.length,'ARCHIVE_INVALID');
   const b=plain.subarray(pos,pos+size);need(sha(b)===m.body_sha256,'ARCHIVE_INVALID');pos+=size;
  }
  need(new Set(info.functions.map(e=>e.id)).size===SLUGS.length&&pos===plain.length,'ARCHIVE_INVALID');return {functions:info.functions,archive_sha256:sha(archive)};
 }catch(e){if(e instanceof CaptureError)throw e;throw new CaptureError('ARCHIVE_AUTHENTICATION_FAILED');}
 finally{k.fill(0);update?.fill(0);final?.fill(0);plain?.fill(0);}
}
