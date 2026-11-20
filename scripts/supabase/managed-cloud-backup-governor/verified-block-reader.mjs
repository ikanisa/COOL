// Synthetic-only content pinning for a standard single-GCM archive.
import {createDecipheriv,createHash,timingSafeEqual} from 'node:crypto';
import {fstatSync,read as readFd} from 'node:fs';
import {types} from 'node:util';
import {HEADER_LENGTH,MAX_ARCHIVE_BYTES,PROJECT_BINDING} from '../managed-cloud-backup-preparation/stream-archive.mjs';
export class VerifiedReadError extends Error{constructor(code){super(code);this.name='VerifiedReadError';this.code=code;}}
const fail=c=>{throw new VerifiedReadError(c);},BLOCK=1024*1024,TAGLEN=16,IVLEN=12,MAGIC=Buffer.from('COLLECTPGGCM2');
const CONTEXT=createHash('sha256').update(JSON.stringify({purpose:'synthetic-only-do-not-use-with-live-data',...PROJECT_BINDING})).digest();
function option(o,k){const d=Object.getOwnPropertyDescriptor(o,k);if(!d||!Object.hasOwn(d,'value'))fail('invalid_input');return d.value;}
function validate(o){if(!o||typeof o!=='object'||types.isProxy(o))fail('invalid_input');if(option(o,'mode')!=='synthetic')fail('managed_execution_closed');}
const readAt=(fd,b,off,len,pos)=>new Promise((resolve,reject)=>readFd(fd,b,off,len,pos,(e,n)=>e?reject(e):resolve(n)));
async function exact(fd,length,pos,signal){const b=Buffer.alloc(length);let n=0;while(n<length){if(signal?.aborted)fail('aborted');const k=await readAt(fd,b,n,length-n,pos+n);if(!k)fail('archive_truncated');n+=k;}return b;}
function stat(fd){const s=fstatSync(fd);if(!s.isFile()||(s.mode&0o777)!==0o600||s.uid!==process.getuid()||!Number.isSafeInteger(s.size)||s.size<=HEADER_LENGTH+TAGLEN||s.size>MAX_ARCHIVE_BYTES+HEADER_LENGTH+TAGLEN)fail('archive_refused');return s;}
function cipher(key,header,tag){const c=createDecipheriv('aes-256-gcm',key,header.subarray(MAGIC.length,MAGIC.length+IVLEN));c.setAAD(header);c.setAuthTag(tag);return c;}
function chunkDigest(i,data){const index=Buffer.alloc(8);index.writeBigUInt64BE(BigInt(i));return createHash('sha256').update('collect-verified-block-v1\0').update(index).update(data).digest();}
function send(writable,bytes){return new Promise((resolve,reject)=>{try{writable.write(bytes,e=>e?reject(e):resolve());}catch(e){reject(e);}});}
export async function inspectSyntheticWithPinnedBlocks(o){
 validate(o);const fd=option(o,'fd'),writable=option(o,'writable'),signal=option(o,'signal'),hook=option(o,'afterAuthenticated'),input=option(o,'key');
 const expectedDescriptor=Object.getOwnPropertyDescriptor(o,'expectedSha256');if(expectedDescriptor&&!Object.hasOwn(expectedDescriptor,'value'))fail('invalid_input');
 const expected=expectedDescriptor?.value;if(expected!==undefined&&!/^[0-9a-f]{64}$/.test(expected??''))fail('invalid_input');
 if(!Number.isInteger(fd)||fd<0||!Buffer.isBuffer(input)||input.length!==32||!writable||typeof writable.write!=='function'||hook!==null&&typeof hook!=='function')fail('invalid_input');
 if(signal?.aborted)fail('aborted');const key=Buffer.from(input);let map;
 try{
  const initial=stat(fd),header=await exact(fd,HEADER_LENGTH,0,signal),tag=await exact(fd,TAGLEN,initial.size-TAGLEN,signal);
  if(!header.subarray(0,MAGIC.length).equals(MAGIC)||!header.subarray(MAGIC.length+IVLEN).equals(CONTEXT))fail('archive_context_refused');
  const bytes=initial.size-HEADER_LENGTH-TAGLEN,blocks=Math.ceil(bytes/BLOCK);map=Buffer.alloc(blocks*32);
  const d=cipher(key,header,tag),archiveHash=createHash('sha256');archiveHash.update(header);let offset=0;
  for(let i=0;i<blocks;i++){const n=Math.min(BLOCK,bytes-offset),part=await exact(fd,n,HEADER_LENGTH+offset,signal);archiveHash.update(part);
   const digest=chunkDigest(i,part);digest.copy(map,i*32);digest.fill(0);let plain;try{plain=d.update(part);}finally{plain?.fill(0);part.fill(0);}offset+=n;}
  try{const last=d.final();last.fill(0);}catch{fail('archive_authentication_failed');}
  archiveHash.update(tag);const ciphertextSha256=archiveHash.digest('hex');if(expected!==undefined&&ciphertextSha256!==expected)fail('archive_changed_before_parser');
  if(hook)await hook();if(signal?.aborted)fail('aborted');
  const againHeader=await exact(fd,HEADER_LENGTH,0,signal),againTag=await exact(fd,TAGLEN,initial.size-TAGLEN,signal);
  if(!timingSafeEqual(header,againHeader)||!timingSafeEqual(tag,againTag))fail('archive_changed_before_parser');
  const d2=cipher(key,header,tag);let delivered=0,early=false;offset=0;
  const onError=()=>{};writable.on('error',onError);
  try{for(let i=0;i<blocks;i++){
   const n=Math.min(BLOCK,bytes-offset),part=await exact(fd,n,HEADER_LENGTH+offset,signal),digest=chunkDigest(i,part);
   if(!timingSafeEqual(digest,map.subarray(i*32,i*32+32))){digest.fill(0);part.fill(0);fail('archive_changed_before_parser');}
   digest.fill(0);let plain;try{plain=d2.update(part);}finally{part.fill(0);}
   try{if(!early){try{await send(writable,plain);delivered+=plain.length;}catch(e){if(signal?.aborted)fail('aborted');if(['EPIPE','ERR_STREAM_PREMATURE_CLOSE','ERR_STREAM_DESTROYED'].includes(e?.code))early=true;else fail('consumer_failed');}}}
   finally{plain.fill(0);}offset+=n;
  }
  try{const last=d2.final();last.fill(0);}catch{fail('archive_authentication_failed');}
  if(!early)await new Promise((resolve,reject)=>{try{writable.end(e=>e?reject(e):resolve());}catch(e){reject(e);}});
  }finally{writable.removeListener('error',onError);}
  const after=stat(fd);if(after.dev!==initial.dev||after.ino!==initial.ino||after.size!==initial.size||after.mtimeMs!==initial.mtimeMs||after.ctimeMs!==initial.ctimeMs)fail('archive_changed');
  return {status:'synthetic_blocks_verified',ciphertextSha256,archiveBytes:bytes,blocks,deliveredBytes:delivered,consumerClosedEarly:early};
 }catch(e){if(e instanceof VerifiedReadError)throw e;fail('verified_read_failed');}
 finally{key.fill(0);map?.fill(0);}
}
