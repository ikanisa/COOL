// Synthetic fixture prototype only. It does not implement a managed-cloud path.
import {createCipheriv,createDecipheriv,createHash,randomBytes,randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {constants,closeSync,createWriteStream,fsyncSync,fstatSync,linkSync,lstatSync,openSync,readFileSync,readSync,realpathSync,unlinkSync,writeSync} from 'node:fs';
import {join} from 'node:path';
import {Transform} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {resolvePg17Bin} from '../current-pg-transfer/test-support/owned-pg17.mjs';

export class SyntheticBackupError extends Error{constructor(code){super(code);this.name='SyntheticBackupError';this.code=code;}}
const fail=c=>{throw new SyntheticBackupError(c);};
const MAGIC=Buffer.from('COLLECTPGGCM1'),IVLEN=12,TAGLEN=16,HEADLEN=MAGIC.length+IVLEN;
const MAX_ARCHIVE=8*1024*1024,MAX_CA=64*1024,MAX_PASSWORD=4096,MAX_LIST=512*1024;
const HOST='localhost',ADDRESS='127.0.0.1',DB='collect_backup_fixture',USER='fixture_backup';
const HASH=/^[0-9a-f]{64}$/;
const sha=b=>createHash('sha256').update(b).digest('hex');
const safeClose=fd=>{if(fd!==undefined)try{closeSync(fd);}catch{}};
async function within(p,ms){let timer;try{return await Promise.race([p,new Promise(r=>{timer=setTimeout(()=>r(null),ms);})]);}finally{clearTimeout(timer);}}
function readFd(fd,max,exact){
 if(!Number.isInteger(fd)||fd<0)fail('invalid_input');let stat;
 try{stat=fstatSync(fd);}catch{fail('input_fd_unavailable');}
 if(!stat.isFile()||!Number.isSafeInteger(stat.size)||stat.size<0||stat.size>max||exact!==undefined&&stat.size!==exact)fail('input_fd_refused');
 const out=Buffer.alloc(stat.size);let n=0;
 try{while(n<out.length){const size=readSync(fd,out,n,out.length-n,n);if(size===0)break;n+=size;}}
 catch{out.fill(0);fail('input_fd_unavailable');}
 if(n!==stat.size){out.fill(0);fail('input_fd_unavailable');}
 const result=Buffer.from(out.subarray(0,n));out.fill(0);return result;
}
function scratchPath(path){
 if(typeof path!=='string'||!path.startsWith('/')||realpathSync(path)!==path)fail('scratch_refused');
 const s=lstatSync(path);if(!s.isDirectory()||s.isSymbolicLink()||(s.mode&0o777)!==0o700||s.uid!==process.getuid?.())fail('scratch_refused');
 return path;
}
function unlinkedRegularFile(scratch,bytes){
 const path=join(scratch,'input-'+randomUUID()),flags=constants.O_CREAT|constants.O_EXCL|constants.O_RDWR|(constants.O_NOFOLLOW??0);
 let fd,created=false,identity;try{fd=openSync(path,flags,0o600);created=true;identity=fstatSync(fd);unlinkSync(path);created=false;
  let i=0;while(i<bytes.length)i+=writeSync(fd,bytes,i,bytes.length-i,i);return fd;}
 catch{safeClose(fd);if(created)try{const s=lstatSync(path);if(s.dev===identity.dev&&s.ino===identity.ino)unlinkSync(path);}catch{}fail('private_fd_failed');}
}
function ownedPath(path,identity){try{const s=lstatSync(path);return s.isFile()&&!s.isSymbolicLink()&&s.dev===identity.dev&&s.ino===identity.ino;}catch{return false;}}
function passfile(port,password){
 if(!password.length||password.some(c=>c===0||c===10||c===13))fail('invalid_password_fd');
 const prefix=Buffer.from(`${HOST}:${port}:${DB}:${USER}:`),line=Buffer.alloc(prefix.length+password.length*2+1);
 prefix.copy(line);let pos=prefix.length;
 for(const byte of password){if(byte===58||byte===92)line[pos++]=92;line[pos++]=byte;}
 line[pos++]=10;return line.subarray(0,pos);
}
function childOutcome(child){return new Promise(resolve=>{let error=false;
 // An error can precede close; it is not evidence that the child was reaped.
 child.once('error',()=>{error=true;});child.once('close',(code,signal)=>resolve({code,signal,error}));});}
function signalRunning(child,signal){
 if(child?.pid>0&&child.exitCode===null&&child.signalCode===null)try{child.kill(signal);}catch{}
}
async function stopAndWait(child,closed){
 signalRunning(child,'SIGTERM');let outcome=await within(closed,1500);
 if(!outcome){signalRunning(child,'SIGKILL');outcome=await within(closed,1500);}
 return outcome;
}
async function withWipedBuffer(buffer,operation){try{return await operation();}finally{buffer.fill(0);}}
// Exposes only inert helpers for synthetic regression tests.
export const syntheticTestHelpers=Object.freeze({childOutcome,stopAndWait,withWipedBuffer});
function pinFile(path,expectedHash){
 if(!HASH.test(expectedHash??'')||typeof path!=='string'||!path.startsWith('/')||realpathSync(path)!==path)fail('tool_refused');
 const s=lstatSync(path);if(!s.isFile()||s.isSymbolicLink()||(s.mode&0o022)!==0)fail('tool_refused');
 const fd=openSync(path,constants.O_RDONLY|(constants.O_NOFOLLOW??0));let data;
 try{const size=fstatSync(fd).size;if(size>20*1024*1024)fail('tool_refused');data=Buffer.alloc(size);let n=0;while(n<size){const k=readSync(fd,data,n,size-n,n);if(!k)fail('tool_refused');n+=k;}}
 finally{safeClose(fd);}
 if(sha(data)!==expectedHash)fail('tool_refused');
}
function pinTool(path,toolHash,executableHash){
 pinFile(path,toolHash);
 const prefix=readFileSync(path).subarray(0,2).toString('ascii');
 const executable=prefix==='#!'?join(resolvePg17Bin(),'.'+path.slice(path.lastIndexOf('/')+1)+'-wrapped'):path;
 pinFile(executable,executableHash);
}
function preflight(o){
 if(!o||typeof o!=='object'||o.mode!=='synthetic')fail('managed_execution_closed');
 if(!Number.isInteger(o.port)||o.port<1024||o.port>65535||!HASH.test(o.caSha256??'')||
  ![o.dumpToolSha256,o.restoreToolSha256,o.dumpExecutableSha256,o.restoreExecutableSha256].every(h=>HASH.test(h??''))||
  !Number.isInteger(o.passwordFd)||!Number.isInteger(o.keyFd)||!Number.isInteger(o.caFd)||new Set([o.passwordFd,o.keyFd,o.caFd]).size!==3)fail('invalid_input');
 return scratchPath(o.scratchPath);
}
function archiveParts(fd){
 const s=fstatSync(fd);if(!s.isFile()||(s.mode&0o777)!==0o600||s.uid!==process.getuid?.()||s.size<=HEADLEN+TAGLEN||s.size>MAX_ARCHIVE+HEADLEN+TAGLEN)fail('archive_refused');
 const header=Buffer.alloc(HEADLEN),tag=Buffer.alloc(TAGLEN);
 if(readSync(fd,header,0,HEADLEN,0)!==HEADLEN||readSync(fd,tag,0,TAGLEN,s.size-TAGLEN)!==TAGLEN||!header.subarray(0,MAGIC.length).equals(MAGIC))fail('archive_refused');
 return {header,tag,size:s.size,iv:header.subarray(MAGIC.length)};
}
function authenticate(fd,parts,key){
 const ciphertext=Buffer.alloc(parts.size-HEADLEN-TAGLEN);let i=0,body,last;
 try{while(i<ciphertext.length){const n=readSync(fd,ciphertext,i,ciphertext.length-i,HEADLEN+i);if(!n)fail('archive_refused');i+=n;}
  const d=createDecipheriv('aes-256-gcm',key,parts.iv);d.setAAD(parts.header);d.setAuthTag(parts.tag);
  body=d.update(ciphertext);last=d.final();return Buffer.concat([body,last]);
 }catch(e){if(e instanceof SyntheticBackupError)throw e;fail('archive_authentication_failed');}
 finally{body?.fill(0);last?.fill(0);ciphertext.fill(0);}
}
async function inspectArchive(fd,parts,key,restorePath){
 // Authenticate one bounded in-memory snapshot before exposing plaintext to a parser.
 const plaintext=authenticate(fd,parts,key);
 return withWipedBuffer(plaintext,async()=>{
  let child,closed,finished=false,stdout=[],bytes=0,stderr=0,overflow=false;
  try{
   child=spawn(restorePath,['--list'],{stdio:['pipe','pipe','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});closed=childOutcome(child);
   child.stdout.on('data',b=>{bytes+=b.length;if(bytes>MAX_LIST){overflow=true;signalRunning(child,'SIGTERM');}else stdout.push(b);});
   child.stderr.on('data',b=>{stderr+=b.length;if(stderr>MAX_LIST)signalRunning(child,'SIGTERM');});
   let piped=true;child.stdin.on('error',()=>{piped=false;});child.stdin.end(plaintext);
   let outcome=await within(closed,3000);
   if(!outcome){outcome=await stopAndWait(child,closed);finished=true;if(!outcome)fail('inspection_stop_unconfirmed');fail('inspection_timed_out');}
   finished=true;
   if(!piped||outcome.error||outcome.code!==0||outcome.signal||stderr||overflow)fail('archive_inspection_failed');
   const listing=Buffer.concat(stdout),schemaNames=['app','private','auth','storage'];
   try{const found=new Set();for(const line of listing.toString('utf8').split('\n')){
    const m=/^[0-9]+;\s+[0-9]+\s+[0-9]+\s+SCHEMA\s+-\s+(app|private|auth|storage)\s+\S/.exec(line);if(m)found.add(m[1]);}
    if(!schemaNames.every(n=>found.has(n)))fail('required_schemas_missing');}
   finally{listing.fill(0);}
   return {listedBytes:bytes,requiredSchemas:schemaNames.length};
  }catch(e){if(child&&!finished){const outcome=await stopAndWait(child,closed);finished=true;if(!outcome)fail('inspection_stop_unconfirmed');}throw e;}
  finally{for(const b of stdout)b.fill(0);stdout=[];}
 });
}
export async function inspectSyntheticEncryptedBackup(o){
 if(!o||typeof o!=='object'||o.mode!=='synthetic')fail('managed_execution_closed');
 if(!Number.isInteger(o.keyFd)||![o.restoreToolSha256,o.restoreExecutableSha256].every(h=>HASH.test(h??'')))fail('invalid_input');
 const scratch=scratchPath(o.scratchPath);
 if(typeof o.artifactPath!=='string'||!o.artifactPath.startsWith(scratch+'/')||
  !/^backup-[0-9a-f-]+\.pgc\.gcm$/.test(o.artifactPath.slice(scratch.length+1))||realpathSync(o.artifactPath)!==o.artifactPath)fail('archive_refused');
 const restore=join(resolvePg17Bin(),'pg_restore');pinTool(restore,o.restoreToolSha256,o.restoreExecutableSha256);
 let fd,key;try{fd=openSync(o.artifactPath,constants.O_RDONLY|(constants.O_NOFOLLOW??0));key=readFd(o.keyFd,32,32);
  const parts=archiveParts(fd),result=await inspectArchive(fd,parts,key,restore);
  return {status:'synthetic_backup_inspected',...result};
 }catch(e){if(e instanceof SyntheticBackupError)throw e;fail('synthetic_inspection_failed');}
 finally{safeClose(fd);key?.fill(0);}
}
export async function createSyntheticEncryptedBackup(o){
 const scratch=preflight(o);let key,password,ca,pass,passfd,cafd,outfd,child,closed,partial,partialIdentity,finalPath,done=false,unconfirmed=null;
 try{
  if(o.signal?.aborted)fail('aborted');
  const bin=resolvePg17Bin(),dump=join(bin,'pg_dump'),restore=join(bin,'pg_restore');
  pinTool(dump,o.dumpToolSha256,o.dumpExecutableSha256);pinTool(restore,o.restoreToolSha256,o.restoreExecutableSha256);
  key=readFd(o.keyFd,32,32);password=readFd(o.passwordFd,MAX_PASSWORD);ca=readFd(o.caFd,MAX_CA);
  if(!ca.length||sha(ca)!==o.caSha256)fail('ca_pin_mismatch');
  if(o.signal?.aborted)fail('aborted');
  pass=passfile(o.port,password);passfd=unlinkedRegularFile(scratch,pass);cafd=unlinkedRegularFile(scratch,ca);password.fill(0);pass.fill(0);
  const id=randomUUID();partial=join(scratch,`backup-${id}.partial`);finalPath=join(scratch,`backup-${id}.pgc.gcm`);
  outfd=openSync(partial,constants.O_CREAT|constants.O_EXCL|constants.O_RDWR|(constants.O_NOFOLLOW??0),0o600);
  partialIdentity=fstatSync(outfd);
  const iv=randomBytes(IVLEN),header=Buffer.concat([MAGIC,iv]);writeSync(outfd,header,0,header.length,0);
  const env={PATH:'/usr/bin:/bin',LC_ALL:'C',PGPASSFILE:'/dev/fd/3',PGSSLROOTCERT:'/dev/fd/4',PGHOST:HOST,PGHOSTADDR:ADDRESS,PGPORT:String(o.port),PGDATABASE:DB,PGUSER:USER,PGSSLMODE:'verify-full',PGGSSENCMODE:'disable',PGSSLCERTMODE:'disable',PGCONNECT_TIMEOUT:'5',PGOPTIONS:'-c default_transaction_read_only=on -c statement_timeout=30000 -c lock_timeout=5000'};
  child=spawn(dump,['--no-password','--format=custom','--lock-wait-timeout=5s'],{stdio:['ignore','pipe','pipe',passfd,cafd],env});closed=childOutcome(child);
  let stderr=0,tooLarge=false,aborted=false;child.stderr.on('data',b=>{stderr+=b.length;if(stderr>MAX_LIST)signalRunning(child,'SIGTERM');});
  const stop=()=>{aborted=true;signalRunning(child,'SIGTERM');child.stdout.destroy();},abortSignal=o.signal;
  let timer,listenerInstalled=false,piped=true,archiveBytes=0,cipher;
  try{
   if(abortSignal){abortSignal.addEventListener('abort',stop,{once:true});listenerInstalled=true;}
   timer=setTimeout(stop,30000);
   const limit=new Transform({transform(chunk,_enc,cb){archiveBytes+=chunk.length;if(archiveBytes>MAX_ARCHIVE){tooLarge=true;cb(Error('bounded'));}else cb(null,chunk);}});
   cipher=createCipheriv('aes-256-gcm',key,iv);cipher.setAAD(header);
   try{await pipeline(child.stdout,limit,cipher,createWriteStream(null,{fd:outfd,autoClose:false,start:HEADLEN}));}catch{piped=false;signalRunning(child,'SIGTERM');}
  }finally{
   if(timer!==undefined)clearTimeout(timer);
   if(listenerInstalled)abortSignal.removeEventListener('abort',stop);
  }
  let outcome=await within(closed,3000);if(!outcome)outcome=await stopAndWait(child,closed);
  if(!outcome){unconfirmed='dump_stop_unconfirmed';fail(unconfirmed);}
  if(aborted)fail('aborted');if(tooLarge)fail('archive_bound_exceeded');
  if(!piped||outcome.error||outcome.code!==0||outcome.signal||stderr||archiveBytes===0)fail('dump_failed_or_warning');
  const tag=cipher.getAuthTag();writeSync(outfd,tag,0,tag.length,HEADLEN+archiveBytes);fsyncSync(outfd);
  const parts=archiveParts(outfd);const inspection=await inspectArchive(outfd,parts,key,restore);
  const hash=createHash('sha256'),buffer=Buffer.alloc(65536);let pos=0;
  while(pos<parts.size){const n=readSync(outfd,buffer,0,Math.min(buffer.length,parts.size-pos),pos);if(!n)fail('archive_read_failed');hash.update(buffer.subarray(0,n));pos+=n;}
  const digest=hash.digest('hex');buffer.fill(0);fsyncSync(outfd);safeClose(outfd);outfd=undefined;
  // link() is an atomic no-overwrite promotion within the same private directory.
  if(!ownedPath(partial,partialIdentity))fail('partial_identity_changed');
  linkSync(partial,finalPath);done=true;
  if(!ownedPath(finalPath,partialIdentity))return {status:'promotion_identity_unconfirmed',artifactPath:finalPath,ciphertextSha256:digest};
  try{unlinkSync(partial);partial=undefined;}catch{return {status:'promotion_cleanup_unconfirmed',artifactPath:finalPath,ciphertextSha256:digest};}
  let dirfd;try{dirfd=openSync(scratch,constants.O_RDONLY);fsyncSync(dirfd);}catch{return {status:'promotion_durability_unconfirmed',artifactPath:finalPath,ciphertextSha256:digest};}finally{safeClose(dirfd);}
  return {status:'synthetic_backup_inspected',artifactPath:finalPath,ciphertextSha256:digest,archiveBytes,...inspection};
 }catch(e){
  if(e instanceof SyntheticBackupError&&e.code==='inspection_stop_unconfirmed')unconfirmed=e.code;
  if(e instanceof SyntheticBackupError)throw e;fail('synthetic_backup_failed');
 }finally{
  if(child&&closed&&!done){const outcome=await stopAndWait(child,closed);if(!outcome)unconfirmed??='dump_stop_unconfirmed';}
  safeClose(outfd);safeClose(passfd);safeClose(cafd);key?.fill(0);password?.fill(0);pass?.fill(0);
  if(partial&&partialIdentity&&!unconfirmed&&!done){
   if(!ownedPath(partial,partialIdentity))fail('partial_identity_changed');
   try{unlinkSync(partial);}catch{fail('encrypted_partial_cleanup_unconfirmed');}
  }
  if(partial&&partialIdentity&&unconfirmed&&!done)fail(unconfirmed);
 }
}
