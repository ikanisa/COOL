// Single AES-256-GCM archive with authenticated binding and bounded reads.
import {createCipheriv,createDecipheriv,createHash,randomBytes,timingSafeEqual} from 'node:crypto';
import {fstatSync,read as readFd} from 'node:fs';
import {Transform} from 'node:stream';
import {types} from 'node:util';
import {MAX_DUMP_BYTES} from './capacity.mjs';
export {MAX_DUMP_BYTES} from './capacity.mjs';
export class ArchiveError extends Error{constructor(code){super(code);this.name='ArchiveError';this.code=code;}}
const fail=c=>{throw new ArchiveError(c);};
export const PROVIDER_ROOT_SHA256='807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa';
const MAGIC=Buffer.from('COLLECTPGBKUP1'),IV=12,LEN=4,TAG=16,BLOCK=1024*1024,UUID=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/,HASH=/^[0-9a-f]{64}$/;
const KEYS=['format','scope','operation_id','plan_sha256','project_ref','host','database','role','provider_ca_sha256','snapshot_sha256','inventory_sha256','created_at'];
const expectedHost='db.rrlduytparvsjfmegalh.supabase.co';
function validateMetadata(m){
 if(!m||typeof m!=='object'||types.isProxy(m)||Object.getPrototypeOf(m)!==Object.prototype||Object.keys(m).join(',')!==KEYS.join(',')||
  m.format!=='collect.pg-backup.v2'||!['managed','synthetic'].includes(m.scope)||!UUID.test(m.operation_id??'')||!HASH.test(m.plan_sha256??'')||m.project_ref!=='rrlduytparvsjfmegalh'||
  m.host!==expectedHost||m.database!=='postgres'||m.role!=='postgres'||m.provider_ca_sha256!==PROVIDER_ROOT_SHA256||
  !HASH.test(m.snapshot_sha256??'')||!HASH.test(m.inventory_sha256??'')||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(m.created_at??''))fail('invalid_metadata');
 return m;
}
function copyKey(key){if(!Buffer.isBuffer(key)||key.length!==32)fail('invalid_input');return Buffer.from(key);}
export function createBackupEncryptor({key,metadata,onProgress=null}={}){
 validateMetadata(metadata);if(onProgress!==null&&typeof onProgress!=='function')fail('invalid_input');const encoded=Buffer.from(JSON.stringify(metadata),'utf8');if(encoded.length>4096)fail('invalid_metadata');const k=copyKey(key),iv=randomBytes(IV);
 const size=Buffer.alloc(LEN);size.writeUInt32BE(encoded.length);const header=Buffer.concat([MAGIC,iv,size,encoded]);let cipher;
 try{cipher=createCipheriv('aes-256-gcm',k,iv);cipher.setAAD(header);}finally{k.fill(0);}
 let n=0;return new Transform({construct(cb){this.push(header);cb();},transform(b,_e,cb){try{n+=b.length;if(n>MAX_DUMP_BYTES)fail('dump_bound_exceeded');if(onProgress)onProgress(n);this.push(cipher.update(b));cb();}catch(e){cb(e instanceof ArchiveError?e:new ArchiveError('encryption_failed'));}},flush(cb){try{this.push(cipher.final());this.push(cipher.getAuthTag());cb();}catch{cb(new ArchiveError('encryption_failed'));}}});
}
const readAt=(fd,b,off,len,pos)=>new Promise((resolve,reject)=>readFd(fd,b,off,len,pos,(e,n)=>e?reject(e):resolve(n)));
async function exact(fd,n,pos,signal){const b=Buffer.alloc(n);let used=0;while(used<n){if(signal?.aborted)fail('aborted');const k=await readAt(fd,b,used,n-used,pos+used);if(!k)fail('archive_truncated');used+=k;}return b;}
function getStat(fd){const s=fstatSync(fd);if(!s.isFile()||(s.mode&0o777)!==0o600||s.uid!==process.getuid()||!Number.isSafeInteger(s.size)||s.size>MAX_DUMP_BYTES+8192||s.size<MAGIC.length+IV+LEN+TAG+1)fail('archive_refused');return s;}
function blockHash(i,b){const index=Buffer.alloc(8);index.writeBigUInt64BE(BigInt(i));return createHash('sha256').update('collect-backup-block-v1\0').update(index).update(b).digest();}
function decrypt(key,header,tag){const d=createDecipheriv('aes-256-gcm',key,header.subarray(MAGIC.length,MAGIC.length+IV));d.setAAD(header);d.setAuthTag(tag);return d;}
function write(writable,b){return new Promise((resolve,reject)=>{try{writable.write(b,e=>e?reject(e):resolve());}catch(e){reject(e);}});}
export async function authenticateAndInspectArchive({fd,key,expectedMetadata,writable=null,signal=null,afterAuthenticated=null}={}){
 const k=copyKey(key);let map;
 try{
  if(!Number.isInteger(fd)||fd<0||writable!==null&&typeof writable.write!=='function'||afterAuthenticated!==null&&typeof afterAuthenticated!=='function')fail('invalid_input');
  validateMetadata(expectedMetadata);if(signal?.aborted)fail('aborted');
  const st=getStat(fd),prefix=await exact(fd,MAGIC.length+IV+LEN,0,signal);if(!prefix.subarray(0,MAGIC.length).equals(MAGIC))fail('archive_refused');
  const metaLen=prefix.readUInt32BE(MAGIC.length+IV);if(metaLen<1||metaLen>4096||st.size<MAGIC.length+IV+LEN+metaLen+TAG+1)fail('archive_refused');
  const body=await exact(fd,metaLen,prefix.length,signal),header=Buffer.concat([prefix,body]),tag=await exact(fd,TAG,st.size-TAG,signal);
  let parsed;try{parsed=JSON.parse(body.toString('utf8'));}catch{fail('archive_refused');}validateMetadata(parsed);
  if(JSON.stringify(parsed)!==JSON.stringify(expectedMetadata))fail('archive_binding_mismatch');
  const length=st.size-header.length-TAG,blocks=Math.ceil(length/BLOCK);map=Buffer.alloc(blocks*32);const hash=createHash('sha256');hash.update(header);let pos=0;
  const first=decrypt(k,header,tag);for(let i=0;i<blocks;i++){const b=await exact(fd,Math.min(BLOCK,length-pos),header.length+pos,signal);hash.update(b);const h=blockHash(i,b);h.copy(map,i*32);h.fill(0);let p;try{p=first.update(b);}finally{p?.fill(0);b.fill(0);}pos+=Math.min(BLOCK,length-pos);}
  try{const last=first.final();last.fill(0);}catch{fail('archive_authentication_failed');}hash.update(tag);const digest=hash.digest('hex');
  const firstAfter=getStat(fd);if(firstAfter.dev!==st.dev||firstAfter.ino!==st.ino||firstAfter.size!==st.size||firstAfter.mtimeMs!==st.mtimeMs||firstAfter.ctimeMs!==st.ctimeMs)fail('archive_changed');
  if(writable===null)return {ciphertextSha256:digest,dumpBytes:length,metadata:parsed};
  if(afterAuthenticated!==null){if(parsed.scope!=='synthetic')fail('invalid_input');await afterAuthenticated();}
  const header2=await exact(fd,header.length,0,signal),tag2=await exact(fd,TAG,st.size-TAG,signal);if(!timingSafeEqual(header,header2)||!timingSafeEqual(tag,tag2))fail('archive_changed_before_parser');
  const second=decrypt(k,header,tag);pos=0;let early=false,delivered=0;const onError=()=>{};writable.on('error',onError);
  try{for(let i=0;i<blocks;i++){const n=Math.min(BLOCK,length-pos),b=await exact(fd,n,header.length+pos,signal),h=blockHash(i,b);
   if(!timingSafeEqual(h,map.subarray(i*32,i*32+32))){h.fill(0);b.fill(0);fail('archive_changed_before_parser');}h.fill(0);let p;try{p=second.update(b);}finally{b.fill(0);}
   try{if(!early){try{await write(writable,p);delivered+=p.length;}catch(e){if(signal?.aborted)fail('aborted');if(['EPIPE','ERR_STREAM_DESTROYED','ERR_STREAM_PREMATURE_CLOSE'].includes(e?.code))early=true;else fail('consumer_failed');}}}finally{p.fill(0);}pos+=n;}
   try{const last=second.final();last.fill(0);}catch{fail('archive_authentication_failed');}if(!early)await new Promise((resolve,reject)=>writable.end(e=>e?reject(e):resolve()));
  }finally{writable.removeListener('error',onError);}
  const after=getStat(fd);if(after.dev!==st.dev||after.ino!==st.ino||after.size!==st.size||after.mtimeMs!==st.mtimeMs||after.ctimeMs!==st.ctimeMs)fail('archive_changed');
  return {ciphertextSha256:digest,dumpBytes:length,metadata:parsed,consumerClosedEarly:early,deliveredBytes:delivered};
 }catch(e){if(e instanceof ArchiveError)throw e;fail('archive_authentication_failed');}finally{k.fill(0);map?.fill(0);}
}
