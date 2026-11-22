// Synthetic loopback only. Managed production dispatch is intentionally absent.
import {createHash,randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {constants,closeSync,createWriteStream,fsyncSync,fstatSync,linkSync,lstatSync,openSync,readSync,realpathSync,unlinkSync,writeSync} from 'node:fs';
import {join} from 'node:path';
import {Transform} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {types} from 'node:util';
import {loadProviderRoot} from '../managed-cloud-migrations/provider-ca.mjs';
import {resolvePg17Bin} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {readSyntheticPrivateKey,readSyntheticPrivatePassword} from '../managed-cloud-backup-preparation/supervised-input.mjs';
import {authenticateSyntheticArchive,createSyntheticEncryptor,PROJECT_BINDING} from '../managed-cloud-backup-preparation/stream-archive.mjs';
import {inspectSyntheticWithPinnedBlocks,VerifiedReadError} from './verified-block-reader.mjs';
export class BoundBackupError extends Error{constructor(code){super(code);this.name='BoundBackupError';this.code=code;}}
const fail=c=>{throw new BoundBackupError(c);},HASH=/^[0-9a-f]{64}$/;
const sha=b=>createHash('sha256').update(b).digest('hex');
const close=fd=>{if(fd!==undefined)try{closeSync(fd);}catch{}};
function option(o,k){const d=Object.getOwnPropertyDescriptor(o,k);if(!d||!Object.hasOwn(d,'value'))fail('invalid_input');return d.value;}
function preflight(o){
 if(!o||typeof o!=='object'||types.isProxy(o))fail('invalid_input');if(option(o,'mode')!=='synthetic')fail('managed_execution_closed');
 const path=option(o,'scratchPath'),port=option(o,'fixturePort'),ca=option(o,'fixtureCa'),pin=option(o,'fixtureCaSha256'),signal=option(o,'signal'),
  timeoutMs=option(o,'timeoutMs'),passwordPath=option(o,'passwordPath'),keyPath=option(o,'keyPath');
 if(typeof path!=='string'||!path.startsWith('/')||realpathSync(path)!==path||!Number.isInteger(port)||port<1024||port>65535||
  !Buffer.isBuffer(ca)||ca.length<1||ca.length>65536||!HASH.test(pin??'')||sha(ca)!==pin||
  !Number.isInteger(timeoutMs)||timeoutMs<1000||timeoutMs>3600000||typeof passwordPath!=='string'||typeof keyPath!=='string'||passwordPath===keyPath)fail('invalid_input');
 const st=lstatSync(path);if(!st.isDirectory()||st.isSymbolicLink()||st.uid!==process.getuid()||(st.mode&0o777)!==0o700)fail('scratch_refused');
 if(signal?.aborted)fail('aborted');return {path,port,ca:Buffer.from(ca),signal,timeoutMs,passwordPath,keyPath};
}
function anonFile(dir,bytes){const name=join(dir,'input-'+randomUUID());let fd,identity,created=false;
 try{fd=openSync(name,constants.O_CREAT|constants.O_EXCL|constants.O_RDWR|(constants.O_NOFOLLOW??0),0o600);created=true;identity=fstatSync(fd);unlinkSync(name);created=false;
  let n=0;while(n<bytes.length)n+=writeSync(fd,bytes,n,bytes.length-n,n);return fd;
 }catch{close(fd);if(created)try{const s=lstatSync(name);if(s.dev===identity.dev&&s.ino===identity.ino)unlinkSync(name);}catch{}fail('private_fd_failed');}}
function passfile(port,password){if(!password.length||password.some(x=>x===0||x===10||x===13))fail('invalid_input');
 const prefix=Buffer.from(`${PROJECT_BINDING.host}:${port}:${PROJECT_BINDING.database}:${PROJECT_BINDING.role}:`),out=Buffer.alloc(prefix.length+2*password.length+1);prefix.copy(out);let i=prefix.length;
 for(const b of password){if(b===58||b===92)out[i++]=92;out[i++]=b;}out[i++]=10;return out.subarray(0,i);}
function owned(path,identity){try{const s=lstatSync(path);return s.isFile()&&!s.isSymbolicLink()&&s.dev===identity.dev&&s.ino===identity.ino;}catch{return false;}}
function encryptedSink(fd){const copy=openSync('/dev/fd/'+fd,constants.O_WRONLY);try{
 const a=fstatSync(fd),b=fstatSync(copy);if(a.dev!==b.dev||a.ino!==b.ino)fail('archive_changed');
 return createWriteStream(null,{fd:copy,autoClose:true,start:0});
 }catch(e){close(copy);throw e;}}
function hashFile(fd,size){const h=createHash('sha256'),b=Buffer.alloc(65536);let pos=0;while(pos<size){const n=readSync(fd,b,0,Math.min(b.length,size-pos),pos);if(!n)fail('archive_read_failed');h.update(b.subarray(0,n));pos+=n;}b.fill(0);return h.digest('hex');}
async function within(p,ms){let timer;try{return await Promise.race([p,new Promise(r=>{timer=setTimeout(()=>r(null),ms);})]);}finally{clearTimeout(timer);}}
function outcome(child){return new Promise(resolve=>{let error=false;child.once('error',()=>{error=true;});child.once('close',(code,signal)=>resolve({code,signal,error}));});}
function signalRunning(child,sig){if(child?.pid>0&&child.exitCode===null&&child.signalCode===null)try{child.kill(sig);}catch{}}
async function stop(child,closed){signalRunning(child,'SIGTERM');let x=await within(closed,1500);if(!x){signalRunning(child,'SIGKILL');x=await within(closed,1500);}return x;}
function pinTool(path,toolHash,exeHash){
 if(!HASH.test(toolHash??'')||!HASH.test(exeHash??'')||realpathSync(path)!==path)fail('tool_refused');
 function pin(p,expected){const s=lstatSync(p);if(!s.isFile()||s.isSymbolicLink()||(s.mode&0o022)!==0||s.size>20*1024*1024)fail('tool_refused');const fd=openSync(p,constants.O_RDONLY|(constants.O_NOFOLLOW??0));try{if(hashFile(fd,s.size)!==expected)fail('tool_refused');}finally{close(fd);}}
 pin(path,toolHash);const f=openSync(path,constants.O_RDONLY),head=Buffer.alloc(2);try{readSync(f,head,0,2,0);}finally{close(f);}
 pin(head.toString('ascii')==='#!'?join(resolvePg17Bin(),'.'+path.slice(path.lastIndexOf('/')+1)+'-wrapped'):path,exeHash);
}
async function inspect(fd,key,restore,signal,timeoutMs){
 const before=await authenticateSyntheticArchive({mode:'synthetic',fd,key,signal});
 const child=spawn(restore,['--list'],{stdio:['pipe','pipe','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}}),closed=outcome(child);
 let chunks=[],bytes=0,stderr=0,over=false,done=false,timed=false,timer,listenerInstalled=false;
 const controller=new AbortController(),abort=()=>{controller.abort();child.stdin.destroy();signalRunning(child,'SIGTERM');};
 try{
  if(signal){signal.addEventListener('abort',abort,{once:true});listenerInstalled=true;if(signal.aborted)abort();}
  timer=setTimeout(()=>{timed=true;abort();},timeoutMs);
  child.stdout.on('data',b=>{bytes+=b.length;if(bytes>512*1024){over=true;signalRunning(child,'SIGTERM');}else chunks.push(b);});
  child.stderr.on('data',b=>{stderr+=b.length;if(stderr>512*1024)signalRunning(child,'SIGTERM');});
  let proof;try{proof=await inspectSyntheticWithPinnedBlocks({mode:'synthetic',fd,key,writable:child.stdin,signal:controller.signal,afterAuthenticated:null,expectedSha256:before.ciphertextSha256});}
  catch(e){if(timed)fail('inspection_timed_out');if(signal?.aborted)fail('aborted');throw e;}
  let result=await within(closed,5000);if(!result){result=await stop(child,closed);done=true;if(!result)fail('inspection_stop_unconfirmed');fail('inspection_timed_out');}done=true;
  clearTimeout(timer);timer=undefined;
  if(result.error||result.code!==0||result.signal||stderr||over)fail('inspection_failed');
  const text=Buffer.concat(chunks);try{const found=new Set();for(const line of text.toString('utf8').split('\n')){const m=/^[0-9]+;\s+[0-9]+\s+[0-9]+\s+SCHEMA\s+-\s+(app|private|auth|storage)\s+\S/.exec(line);if(m)found.add(m[1]);}
   if(!['app','private','auth','storage'].every(x=>found.has(x)))fail('required_schemas_missing');}finally{text.fill(0);}
  if(before.ciphertextSha256!==proof.ciphertextSha256||before.archiveBytes!==proof.archiveBytes)fail('archive_changed');
  return {ciphertextSha256:proof.ciphertextSha256,archiveBytes:proof.archiveBytes,listedBytes:bytes,consumerClosedEarly:proof.consumerClosedEarly};
 }catch(e){if(child&&!done){const x=await stop(child,closed);done=true;if(!x)fail('inspection_stop_unconfirmed');}throw e;}
 finally{if(timer!==undefined)clearTimeout(timer);if(listenerInstalled)signal.removeEventListener('abort',abort);for(const b of chunks)b.fill(0);chunks=[];}
}
export function checkPinnedProviderRoot(){try{loadProviderRoot();return {status:'public_provider_ca_validated',binding:PROJECT_BINDING};}catch{fail('provider_ca_unavailable');}}
// Inert hook for synthetic child-lifecycle tests; it is not a managed executor.
export const syntheticBoundTestHelpers=Object.freeze({inspect});
// There is deliberately no production connector, secret reader, or override.
export async function dispatchManagedBackup(){fail('managed_execution_closed');}
export async function createSyntheticBoundBackup(o){
 const p=preflight(o);let password,key,pass,passfd,cafd,outfd,finalfd,child,closed,partial,identity,finalPath,done=false,unconfirmed=null;
 try{
  const bin=resolvePg17Bin(),dump=join(bin,'pg_dump'),restore=join(bin,'pg_restore');
  pinTool(dump,option(o,'dumpToolSha256'),option(o,'dumpExecutableSha256'));pinTool(restore,option(o,'restoreToolSha256'),option(o,'restoreExecutableSha256'));
  password=await readSyntheticPrivatePassword({mode:'synthetic',path:p.passwordPath,signal:p.signal,testHang:false});
  key=await readSyntheticPrivateKey({mode:'synthetic',path:p.keyPath,signal:p.signal,testHang:false});
  pass=passfile(p.port,password);passfd=anonFile(p.path,pass);cafd=anonFile(p.path,p.ca);password.fill(0);pass.fill(0);
  const id=randomUUID();partial=join(p.path,`bound-${id}.partial`);finalPath=join(p.path,`bound-${id}.pgc.gcm`);
  outfd=openSync(partial,constants.O_CREAT|constants.O_EXCL|constants.O_RDWR|(constants.O_NOFOLLOW??0),0o600);identity=fstatSync(outfd);
  const env={PATH:'/usr/bin:/bin',LC_ALL:'C',PGPASSFILE:'/dev/fd/3',PGSSLROOTCERT:'/dev/fd/4',PGHOST:PROJECT_BINDING.host,PGHOSTADDR:'127.0.0.1',PGPORT:String(p.port),PGDATABASE:PROJECT_BINDING.database,PGUSER:PROJECT_BINDING.role,PGSSLMODE:'verify-full',PGGSSENCMODE:'disable',PGSSLCERTMODE:'disable',PGCONNECT_TIMEOUT:'5',PGOPTIONS:'-c default_transaction_read_only=on -c statement_timeout=0 -c lock_timeout=5000'};
  child=spawn(dump,['--no-password','--format=custom','--lock-wait-timeout=5s'],{stdio:['ignore','pipe','pipe',passfd,cafd],env});closed=outcome(child);
  let stderr=0,aborted=false,timed=false,piped=true,timer,listenerInstalled=false;
  child.stderr.on('data',b=>{stderr+=b.length;if(stderr>512*1024)signalRunning(child,'SIGTERM');});
  const abort=()=>{aborted=true;signalRunning(child,'SIGTERM');child.stdout.destroy();};
  try{if(p.signal){p.signal.addEventListener('abort',abort,{once:true});listenerInstalled=true;}
   timer=setTimeout(()=>{timed=true;signalRunning(child,'SIGTERM');child.stdout.destroy();},p.timeoutMs);
   try{await pipeline(child.stdout,createSyntheticEncryptor({mode:'synthetic',key}),encryptedSink(outfd));}
   catch{piped=false;signalRunning(child,'SIGTERM');}
  }finally{if(timer!==undefined)clearTimeout(timer);if(listenerInstalled)p.signal.removeEventListener('abort',abort);}
  let x=await within(closed,3000);if(!x)x=await stop(child,closed);if(!x){unconfirmed='dump_stop_unconfirmed';fail(unconfirmed);}
  if(aborted)fail('aborted');if(timed)fail('dump_timed_out');if(!piped||x.error||x.code!==0||x.signal||stderr)fail('dump_failed_or_warning');
  fsyncSync(outfd);const checked=await inspect(outfd,key,restore,p.signal,p.timeoutMs);fsyncSync(outfd);
  close(outfd);outfd=undefined;if(!owned(partial,identity))fail('partial_identity_changed');
  // A linked artifact is still unconfirmed until its own descriptor is
  // authenticated and compared with the pre-promotion snapshot.
  unconfirmed='promotion_integrity_unconfirmed';linkSync(partial,finalPath);
  if(!owned(finalPath,identity))fail(unconfirmed);
  finalfd=openSync(finalPath,constants.O_RDONLY|(constants.O_NOFOLLOW??0));const finalIdentity=fstatSync(finalfd);
  if(finalIdentity.dev!==identity.dev||finalIdentity.ino!==identity.ino)fail(unconfirmed);
  const readback=await authenticateSyntheticArchive({mode:'synthetic',fd:finalfd,key,signal:p.signal});
  if(readback.ciphertextSha256!==checked.ciphertextSha256||readback.archiveBytes!==checked.archiveBytes||!owned(finalPath,identity))fail(unconfirmed);
  close(finalfd);finalfd=undefined;unconfirmed=null;done=true;
  try{unlinkSync(partial);partial=undefined;}catch{return {status:'promotion_cleanup_unconfirmed',artifactPath:finalPath};}
  let dir;try{dir=openSync(p.path,constants.O_RDONLY);fsyncSync(dir);}catch{return {status:'promotion_durability_unconfirmed',artifactPath:finalPath};}finally{close(dir);}
  return {status:'synthetic_bound_backup_inspected',artifactPath:finalPath,...checked};
 }catch(e){if(e?.code==='inspection_stop_unconfirmed'||e?.code==='input_stop_unconfirmed')unconfirmed=e.code;
  if(e instanceof BoundBackupError)throw e;fail(e?.code==='input_stop_unconfirmed'?'input_stop_unconfirmed':'synthetic_bound_backup_failed');
 }finally{
  if(child&&closed&&!done&&!await stop(child,closed))unconfirmed??='dump_stop_unconfirmed';
  close(outfd);close(finalfd);close(passfd);close(cafd);password?.fill(0);key?.fill(0);pass?.fill(0);
  if(partial&&identity&&!unconfirmed&&!done){if(!owned(partial,identity))fail('partial_identity_changed');try{unlinkSync(partial);}catch{fail('encrypted_partial_cleanup_unconfirmed');}}
  if(unconfirmed&&!done)fail(unconfirmed);
 }
}
