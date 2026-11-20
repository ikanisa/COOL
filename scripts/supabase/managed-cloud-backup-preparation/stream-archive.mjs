// Synthetic-only single AES-256-GCM archive. Managed dispatch is not implemented.
import {createCipheriv,createDecipheriv,createHash,randomBytes} from 'node:crypto';
import {constants,closeSync,fstatSync,openSync,read as readFd,createReadStream} from 'node:fs';
import {Transform,Writable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {types} from 'node:util';
export class StreamArchiveError extends Error{constructor(code){super(code);this.name='StreamArchiveError';this.code=code;}}
const fail=c=>{throw new StreamArchiveError(c);};
export const PROJECT_BINDING=Object.freeze({host:'db.rrlduytparvsjfmegalh.supabase.co',port:5432,database:'postgres',role:'postgres',ca_der_sha256:'807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa'});
const MAGIC=Buffer.from('COLLECTPGGCM2'),IVLEN=12,TAGLEN=16;
const CONTEXT=createHash('sha256').update(JSON.stringify({purpose:'synthetic-only-do-not-use-with-live-data',...PROJECT_BINDING})).digest();
export const HEADER_LENGTH=MAGIC.length+IVLEN+CONTEXT.length;
export const MAX_ARCHIVE_BYTES=100*1024*1024*1024;
function option(o,k){const d=Object.getOwnPropertyDescriptor(o,k);if(!d||!Object.hasOwn(d,'value'))fail('invalid_input');return d.value;}
function synthetic(o){if(!o||typeof o!=='object'||types.isProxy(o))fail('invalid_input');if(option(o,'mode')!=='synthetic')fail('managed_execution_closed');return o;}
function keyCopy(key){if(!Buffer.isBuffer(key)||key.length!==32)fail('invalid_input');return Buffer.from(key);}
function checkedParts(fd){
 const st=fstatSync(fd);if(!st.isFile()||(st.mode&0o777)!==0o600||st.uid!==process.getuid()||!Number.isSafeInteger(st.size)||
  st.size<=HEADER_LENGTH+TAGLEN||st.size>MAX_ARCHIVE_BYTES+HEADER_LENGTH+TAGLEN)fail('archive_refused');
 return st;
}
function duplicate(fd){const copy=openSync('/dev/fd/'+fd,constants.O_RDONLY),a=fstatSync(fd),b=fstatSync(copy);if(a.dev!==b.dev||a.ino!==b.ino){closeSync(copy);fail('archive_changed');}return copy;}
function cipherSource(fd,end){const copy=duplicate(fd);try{return createReadStream(null,{fd:copy,autoClose:true,start:HEADER_LENGTH,end});}catch(e){closeSync(copy);throw e;}}
const readAt=(fd,b,off,len,pos)=>new Promise((resolve,reject)=>readFd(fd,b,off,len,pos,(e,n)=>e?reject(e):resolve(n)));
async function exact(fd,length,pos){const b=Buffer.alloc(length);let n=0;while(n<length){const k=await readAt(fd,b,n,length-n,pos+n);if(!k)fail('archive_truncated');n+=k;}return b;}
export function createSyntheticEncryptor(o){
 synthetic(o);const key=keyCopy(option(o,'key')),iv=randomBytes(IVLEN),header=Buffer.concat([MAGIC,iv,CONTEXT]);let cipher;
 try{cipher=createCipheriv('aes-256-gcm',key,iv);cipher.setAAD(header);}finally{key.fill(0);}
 let bytes=0;
 return new Transform({construct(cb){this.push(header);cb();},
  transform(chunk,_enc,cb){try{bytes+=chunk.length;if(bytes>MAX_ARCHIVE_BYTES)fail('archive_bound_exceeded');this.push(cipher.update(chunk));cb();}catch(e){cb(e instanceof StreamArchiveError?e:new StreamArchiveError('encryption_failed'));}},
  flush(cb){try{this.push(cipher.final());this.push(cipher.getAuthTag());cb();}catch{cb(new StreamArchiveError('encryption_failed'));}}
 });
}
async function prepare(fd,key){
 const st=checkedParts(fd),header=await exact(fd,HEADER_LENGTH,0),tag=await exact(fd,TAGLEN,st.size-TAGLEN);
 if(!header.subarray(0,MAGIC.length).equals(MAGIC)||!header.subarray(MAGIC.length+IVLEN).equals(CONTEXT))fail('archive_context_refused');
 const d=createDecipheriv('aes-256-gcm',key,header.subarray(MAGIC.length,MAGIC.length+IVLEN));d.setAAD(header);d.setAuthTag(tag);
 return {st,header,tag,decipher:d};
}
export async function authenticateSyntheticArchive(o){
 synthetic(o);const fd=option(o,'fd'),signal=option(o,'signal'),key=keyCopy(option(o,'key'));let state;
 try{
  if(!Number.isInteger(fd)||fd<0)fail('invalid_input');if(signal?.aborted)fail('aborted');
  state=await prepare(fd,key);const hash=createHash('sha256');hash.update(state.header);
  const hashTap=new Transform({transform(b,_e,cb){hash.update(b);cb(null,b);}}),discard=new Writable({write(_b,_e,cb){cb();}});
  try{await pipeline(cipherSource(fd,state.st.size-TAGLEN-1),hashTap,state.decipher,discard,{signal:signal??undefined});}
  catch(e){if(signal?.aborted)fail('aborted');fail('archive_authentication_failed');}
  hash.update(state.tag);const after=checkedParts(fd);
  if(after.dev!==state.st.dev||after.ino!==state.st.ino||after.size!==state.st.size||after.mtimeMs!==state.st.mtimeMs||after.ctimeMs!==state.st.ctimeMs)fail('archive_changed');
  return {ciphertextSha256:hash.digest('hex'),archiveBytes:state.st.size-HEADER_LENGTH-TAGLEN};
 }catch(e){if(e instanceof StreamArchiveError)throw e;fail('archive_authentication_failed');}
 finally{key.fill(0);}
}
export async function pipeSyntheticArchiveTo(o){
 synthetic(o);const fd=option(o,'fd'),writable=option(o,'writable'),signal=option(o,'signal'),key=keyCopy(option(o,'key'));
 try{
  if(!Number.isInteger(fd)||fd<0||!writable||typeof writable.write!=='function')fail('invalid_input');if(signal?.aborted)fail('aborted');
  const state=await prepare(fd,key);
  try{await pipeline(cipherSource(fd,state.st.size-TAGLEN-1),state.decipher,writable,{signal:signal??undefined});}
  catch(e){if(signal?.aborted)fail('aborted');if(['EPIPE','ERR_STREAM_PREMATURE_CLOSE'].includes(e?.code))fail('consumer_closed_early');fail('archive_authentication_failed');}
  const after=checkedParts(fd);if(after.dev!==state.st.dev||after.ino!==state.st.ino||after.size!==state.st.size||after.mtimeMs!==state.st.mtimeMs||after.ctimeMs!==state.st.ctimeMs)fail('archive_changed');
 }catch(e){if(e instanceof StreamArchiveError)throw e;fail('archive_authentication_failed');}
 finally{key.fill(0);}
}
