// Read-only dump worker. It must run under supervisor.mjs; no credentials in argv/env.
import {createHash,randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {constants,closeSync,createWriteStream,fsyncSync,fstatSync,linkSync,lstatSync,openSync,readSync,realpathSync,unlinkSync,writeSync} from 'node:fs';
import {join} from 'node:path';
import {pipeline} from 'node:stream/promises';
import {loadProviderRoot} from '../managed-cloud-migrations/provider-ca.mjs';
import {resolvePg17Bin} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {readPrivateKey,readPrivatePassword} from './private-input.mjs';
import {openPinnedManagedSnapshot,openSyntheticSnapshot,cleanManagedEnvironment} from './snapshot.mjs';
import {prepareAttempt,recordDispatchIntent,recordOutcome} from './journal.mjs';
import {authenticateAndInspectArchive,createBackupEncryptor,PROVIDER_ROOT_SHA256} from './archive.mjs';
import {openInventory,sealInventory} from './manifest-crypto.mjs';
import {MAX_DUMP_BYTES,requireDiskHeadroom,createProgressGuard} from './capacity.mjs';
import {createTocScanner} from './toc.mjs';
import {normalizedExitCode,normalizedSignal} from './diagnostics.mjs';
export class DumpError extends Error{constructor(code){super(code);this.name='DumpError';this.code=code;}}
const fail=c=>{throw new DumpError(c);},HASH=/^[0-9a-f]{64}$/,UUID=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const sha=b=>createHash('sha256').update(b).digest('hex'),close=fd=>{if(fd!==undefined)try{closeSync(fd);}catch{}};
function dir(path){if(typeof path!=='string'||!path.startsWith('/')||realpathSync(path)!==path)fail('private_root_refused');const s=lstatSync(path);if(!s.isDirectory()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o777)!==0o700)fail('private_root_refused');return path;}
function validate(q){
 const keys=['mode','operationId','journalRoot','artifactRoot','passwordPath','keyPath','dumpToolSha256','dumpExecutableSha256','restoreToolSha256','restoreExecutableSha256','fixture'];
 if(!q||typeof q!=='object'||Object.keys(q).sort().join('\0')!==keys.sort().join('\0')||!['managed','synthetic'].includes(q.mode)||!UUID.test(q.operationId??'')||
  ![q.dumpToolSha256,q.dumpExecutableSha256,q.restoreToolSha256,q.restoreExecutableSha256].every(x=>HASH.test(x??''))||typeof q.passwordPath!=='string'||typeof q.keyPath!=='string'||q.passwordPath===q.keyPath)fail('invalid_input');
 const a=dir(q.journalRoot),b=dir(q.artifactRoot);if(a===b||a.startsWith(b+'/')||b.startsWith(a+'/'))fail('private_root_refused');
 if(q.mode==='managed'&&(q.fixture!==null||!cleanManagedEnvironment()||process.env.COLLECT_SYNTHETIC_PG_BIN))fail('managed_environment_refused');
 if(q.mode==='synthetic'&&(!q.fixture||typeof q.fixture!=='object'||Object.keys(q.fixture).sort().join(',')!=='port,socket'))fail('invalid_input');
 return q;
}
function anon(dirPath,bytes){const path=join(dirPath,'input-'+randomUUID());let fd,identity,created=false;try{fd=openSync(path,constants.O_CREAT|constants.O_EXCL|constants.O_RDWR|(constants.O_NOFOLLOW??0),0o600);created=true;identity=fstatSync(fd);unlinkSync(path);created=false;
 let n=0;while(n<bytes.length)n+=writeSync(fd,bytes,n,bytes.length-n,n);return fd;}catch{close(fd);if(created)try{const s=lstatSync(path);if(s.dev===identity.dev&&s.ino===identity.ino)unlinkSync(path);}catch{}fail('private_fd_failed');}}
function passfile(host,port,database,user,password){const prefix=Buffer.from(`${host}:${port}:${database}:${user}:`),out=Buffer.alloc(prefix.length+2*password.length+1);prefix.copy(out);let n=prefix.length;for(const c of password){if(c===58||c===92)out[n++]=92;out[n++]=c;}out[n++]=10;return out.subarray(0,n);}
function hashFile(fd,size){const h=createHash('sha256'),b=Buffer.alloc(65536);let p=0;while(p<size){const n=readSync(fd,b,0,Math.min(b.length,size-p),p);if(!n)fail('tool_refused');h.update(b.subarray(0,n));p+=n;}b.fill(0);return h.digest('hex');}
function pin(path,expected){if(!HASH.test(expected)||realpathSync(path)!==path)fail('tool_refused');const s=lstatSync(path);if(!s.isFile()||s.isSymbolicLink()||(s.mode&0o022)!==0||s.size>20*1024*1024)fail('tool_refused');const f=openSync(path,constants.O_RDONLY|(constants.O_NOFOLLOW??0));try{if(hashFile(f,s.size)!==expected)fail('tool_refused');}finally{close(f);}}
function pinTool(bin,name,wrapperHash,executableHash){const path=join(bin,name);pin(path,wrapperHash);const f=openSync(path,constants.O_RDONLY),b=Buffer.alloc(2);try{readSync(f,b,0,2,0);}finally{close(f);}pin(b.toString('ascii')==='#!'?join(bin,'.'+name+'-wrapped'):path,executableHash);return path;}
function sink(fd){const copy=openSync('/dev/fd/'+fd,constants.O_WRONLY);try{const a=fstatSync(fd),b=fstatSync(copy);if(a.dev!==b.dev||a.ino!==b.ino)fail('artifact_changed');return createWriteStream(null,{fd:copy,autoClose:true,start:0});}catch(e){close(copy);throw e;}}
function writeAll(fd,b){let p=0;while(p<b.length)p+=writeSync(fd,b,p,b.length-p,p);}
function owned(path,identity){try{const s=lstatSync(path);return s.isFile()&&!s.isSymbolicLink()&&s.dev===identity.dev&&s.ino===identity.ino;}catch{return false;}}
function sameIdentity(fd,identity){const s=fstatSync(fd);if(s.dev!==identity.dev||s.ino!==identity.ino||!s.isFile()||(s.mode&0o777)!==0o600||s.uid!==process.getuid())fail('artifact_changed');}
async function within(p,ms){let timer;try{return await Promise.race([p,new Promise(r=>{timer=setTimeout(()=>r(null),ms);})]);}finally{clearTimeout(timer);}}
function outcome(c){return new Promise(resolve=>{let error=false;c.once('error',()=>{error=true;});c.once('close',(code,signal)=>resolve({code,signal,error}));});}
function signalRunning(c,s){if(c?.pid>0&&c.exitCode===null&&c.signalCode===null)try{c.kill(s);}catch{}}
async function stop(c,closed){signalRunning(c,'SIGTERM');let x=await within(closed,1500);if(!x){signalRunning(c,'SIGKILL');x=await within(closed,1500);}return x;}
const report=(progress,event)=>{try{progress?.(event);}catch{}};
async function inspect(fd,key,metadata,inventory,restore,progress){
 report(progress,{phase:'toc_authentication_started'});
 const first=await authenticateAndInspectArchive({fd,key,expectedMetadata:metadata});
 const child=spawn(restore,['--list'],{stdio:['pipe','pipe','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}}),closed=outcome(child),controller=new AbortController();
 report(progress,{phase:'toc_process_started'});
 let done=false,timed=false,outputRefused=false,timer,stderr=0;const scanner=createTocScanner();
 try{
  child.stdout.on('data',b=>{try{if(!outputRefused)try{scanner.push(b);}catch(e){report(progress,{phase:e?.code==='toc_bound_exceeded'?'toc_total_bound_refused':e?.code==='toc_line_bound_exceeded'?'toc_line_bound_refused':'toc_stream_refused'});outputRefused=true;controller.abort();child.stdin.destroy();signalRunning(child,'SIGTERM');}}finally{b.fill(0);}});child.stderr.on('data',b=>{stderr+=b.length;b.fill(0);if(stderr>512*1024)signalRunning(child,'SIGTERM');});
  timer=setTimeout(()=>{timed=true;report(progress,{phase:'toc_timeout'});controller.abort();child.stdin.destroy();signalRunning(child,'SIGTERM');},60000);
  let checked;try{checked=await authenticateAndInspectArchive({fd,key,expectedMetadata:metadata,writable:child.stdin,signal:controller.signal});}
  catch(e){if(timed)fail('inspection_timed_out');if(outputRefused)fail('inspection_output_refused');throw e;}
  let x=await within(closed,5000);if(!x){x=await stop(child,closed);done=true;if(!x){report(progress,{phase:'toc_stop_unconfirmed'});fail('inspection_stop_unconfirmed');}report(progress,{phase:'toc_process_closed',exitCode:normalizedExitCode(x.code),signal:normalizedSignal(x.signal),stderrBytes:stderr});fail('inspection_timed_out');}done=true;
  report(progress,{phase:'toc_process_closed',exitCode:normalizedExitCode(x.code),signal:normalizedSignal(x.signal),stderrBytes:stderr});
  if(x.error||x.signal||x.code!==0){report(progress,{phase:'toc_exit_refused'});fail('inspection_failed');}if(stderr){report(progress,{phase:'toc_stderr_refused'});fail('inspection_failed');}if(outputRefused)fail('inspection_failed');
  try{scanner.finish([...new Set(inventory.inventory.map(x=>x.schema).filter(x=>['app','private','collect_sms','auth','storage','supabase_migrations'].includes(x)))]);}catch(e){report(progress,{phase:e?.code==='required_schemas_missing'?'toc_missing_schema_refused':'toc_stream_refused'});fail('inspection_output_refused');}
  if(first.ciphertextSha256!==checked.ciphertextSha256||first.dumpBytes!==checked.dumpBytes)fail('artifact_changed');return checked;
 }catch(e){if(!done){const x=await stop(child,closed);done=true;if(!x){report(progress,{phase:'toc_stop_unconfirmed'});fail('inspection_stop_unconfirmed');}report(progress,{phase:'toc_process_closed',exitCode:normalizedExitCode(x.code),signal:normalizedSignal(x.signal),stderrBytes:stderr});}throw e;}
 finally{if(timer!==undefined)clearTimeout(timer);scanner.clear();}
}
export async function executeReadOnlyDump(request,planSha256,progress=null){
 if(progress!==null&&typeof progress!=='function')fail('invalid_input');
 const q=validate(request);if(!HASH.test(planSha256??''))fail('invalid_input');const journal={mode:q.mode,root:q.journalRoot,operationId:q.operationId,planSha256};let key,password,pass,passfd,cafd,outfd,metafd,finalfd,child,closed,snapshot,dispatch=false,completed=false,unconfirmed=false;
 try{
  report(progress,{phase:'headroom_check'});
  requireDiskHeadroom(q.artifactRoot,MAX_DUMP_BYTES);
  report(progress,{phase:'headroom_checked'});
  prepareAttempt(journal);recordDispatchIntent(journal);dispatch=true;
  report(progress,{phase:'dispatch_recorded'});
  report(progress,{phase:'tools_pin_started'});const bin=resolvePg17Bin(),dump=pinTool(bin,'pg_dump',q.dumpToolSha256,q.dumpExecutableSha256),restore=pinTool(bin,'pg_restore',q.restoreToolSha256,q.restoreExecutableSha256);
  report(progress,{phase:'tools_pinned'});
  report(progress,{phase:'credentials_read_started'});password=await readPrivatePassword({mode:q.mode,path:q.passwordPath,signal:null,testHang:false});key=await readPrivateKey({mode:q.mode,path:q.keyPath,signal:null,testHang:false});
  report(progress,{phase:'credentials_loaded'});
  const managed=q.mode==='managed',host=managed?'db.rrlduytparvsjfmegalh.supabase.co':q.fixture.socket,port=managed?5432:q.fixture.port,database=managed?'postgres':'collect_fixture_dump',user=managed?'postgres':'fixture_bootstrap';
  report(progress,{phase:'snapshot_open_started'});snapshot=managed?await openPinnedManagedSnapshot({password:password.toString('utf8')}):await openSyntheticSnapshot({mode:'synthetic',socket:host,port});
  report(progress,{phase:'snapshot_exported'});
  const inventory=snapshot.metadata,inventorySha=sha(Buffer.from(JSON.stringify(inventory)));
  const metadata={format:'collect.pg-backup.v2',scope:q.mode,operation_id:q.operationId,plan_sha256:planSha256,project_ref:'rrlduytparvsjfmegalh',host:'db.rrlduytparvsjfmegalh.supabase.co',database:'postgres',role:'postgres',provider_ca_sha256:PROVIDER_ROOT_SHA256,snapshot_sha256:inventory.snapshot_sha256,inventory_sha256:inventorySha,created_at:new Date().toISOString()};
  const base=join(q.artifactRoot,'backup-'+q.operationId),partial=base+'.partial',final=base+'.pgc.gcm',metaPartial=base+'.inventory.partial',metaFinal=base+'.inventory.gcm';
  report(progress,{phase:'artifact_creation_started'});pass=passfile(host,port,database,user,password);passfd=anon(q.artifactRoot,pass);if(managed)cafd=anon(q.artifactRoot,Buffer.from(loadProviderRoot()));password.fill(0);pass.fill(0);
  outfd=openSync(partial,constants.O_CREAT|constants.O_EXCL|constants.O_RDWR|(constants.O_NOFOLLOW??0),0o600);const outIdentity=fstatSync(outfd);
  metafd=openSync(metaPartial,constants.O_CREAT|constants.O_EXCL|constants.O_RDWR|(constants.O_NOFOLLOW??0),0o600);const metaIdentity=fstatSync(metafd),sealed=sealInventory({key,operationId:q.operationId,inventory});
  writeAll(metafd,sealed);fsyncSync(metafd);const metaSha=sha(sealed);sealed.fill(0);
  report(progress,{phase:'artifacts_opened'});
  const env={PATH:'/usr/bin:/bin',LC_ALL:'C',PGPASSFILE:'/dev/fd/3',PGHOST:host,PGPORT:String(port),PGDATABASE:database,PGUSER:user,PGSSLMODE:managed?'verify-full':'disable',PGGSSENCMODE:'disable',PGSSLCERTMODE:'disable',PGCONNECT_TIMEOUT:'10',PGOPTIONS:'-c default_transaction_read_only=on -c lock_timeout=5000'};
  if(managed)env.PGSSLROOTCERT='/dev/fd/4';
  requireDiskHeadroom(q.artifactRoot,MAX_DUMP_BYTES);const capacityGuard=createProgressGuard(q.artifactRoot);
  child=spawn(dump,['--no-password','--format=custom','--lock-wait-timeout=5s','--snapshot='+snapshot.snapshotId],{stdio:['ignore','pipe','pipe',passfd,managed?cafd:'ignore'],env});closed=outcome(child);
  report(progress,{phase:'dump_started'});
  let stderr=0,piped=true;child.stderr.on('data',b=>{stderr+=b.length;b.fill(0);if(stderr>512*1024)signalRunning(child,'SIGTERM');});
  try{await pipeline(child.stdout,createBackupEncryptor({key,metadata,onProgress:capacityGuard}),sink(outfd));}catch{piped=false;report(progress,{phase:'dump_stream_refused'});signalRunning(child,'SIGTERM');}
  let result=await within(closed,5000);if(!result)result=await stop(child,closed);if(!result){unconfirmed=true;report(progress,{phase:'dump_stop_unconfirmed'});fail('dump_stop_unconfirmed');}
  report(progress,{phase:'dump_process_closed',exitCode:normalizedExitCode(result.code),signal:normalizedSignal(result.signal),stderrBytes:stderr});
  if(result.error||result.signal||result.code!==0){report(progress,{phase:'dump_exit_refused'});fail('dump_failed_or_warning');}if(stderr){report(progress,{phase:'dump_stderr_refused'});fail('dump_failed_or_warning');}if(!piped)fail('dump_failed_or_warning');
  report(progress,{phase:'snapshot_recheck'});await snapshot.assertAlive();
  report(progress,{phase:'pre_toc_sync'});fsyncSync(outfd);const checked=await inspect(outfd,key,metadata,inventory,restore,progress);report(progress,{phase:'toc_validated'});fsyncSync(outfd);
  close(outfd);outfd=undefined;close(metafd);metafd=undefined;if(!owned(partial,outIdentity)||!owned(metaPartial,metaIdentity))fail('artifact_changed');
  report(progress,{phase:'promotion_started'});unconfirmed=true;linkSync(partial,final);linkSync(metaPartial,metaFinal);
  if(!owned(final,outIdentity)||!owned(metaFinal,metaIdentity))fail('promotion_integrity_unconfirmed');
  report(progress,{phase:'promotion_readback'});finalfd=openSync(final,constants.O_RDONLY|(constants.O_NOFOLLOW??0));sameIdentity(finalfd,outIdentity);const post=await authenticateAndInspectArchive({fd:finalfd,key,expectedMetadata:metadata});
  if(post.ciphertextSha256!==checked.ciphertextSha256||post.dumpBytes!==checked.dumpBytes||!owned(final,outIdentity))fail('promotion_integrity_unconfirmed');close(finalfd);finalfd=undefined;
  finalfd=openSync(metaFinal,constants.O_RDONLY|(constants.O_NOFOLLOW??0));sameIdentity(finalfd,metaIdentity);const st=fstatSync(finalfd);if(st.size>131072)fail('promotion_integrity_unconfirmed');const mb=Buffer.alloc(st.size);let p=0;while(p<mb.length){const n=readSync(finalfd,mb,p,mb.length-p,p);if(!n)fail('promotion_integrity_unconfirmed');p+=n;}
  try{if(sha(mb)!==metaSha||sha(Buffer.from(JSON.stringify(openInventory({key,operationId:q.operationId,bytes:mb}))))!==inventorySha||!owned(metaFinal,metaIdentity))fail('promotion_integrity_unconfirmed');}finally{mb.fill(0);}close(finalfd);finalfd=undefined;
  const bundle=sha(Buffer.from(checked.ciphertextSha256+'\0'+metaSha+'\0'+metadata.snapshot_sha256+'\0'+inventorySha));
  if(!owned(partial,outIdentity)||!owned(metaPartial,metaIdentity))fail('promotion_integrity_unconfirmed');
  unlinkSync(partial);unlinkSync(metaPartial);
  const d=openSync(q.artifactRoot,constants.O_RDONLY);try{fsyncSync(d);}finally{close(d);}
  report(progress,{phase:'journal_completion_started'});recordOutcome({...journal,outcome:'completed',artifactSha256:bundle});completed=true;unconfirmed=false;
  report(progress,{phase:'journal_completed'});
  return {status:'completed_point_in_time',bundleSha256:bundle,dumpSha256:checked.ciphertextSha256,inventorySha256:metaSha,snapshotSha256:metadata.snapshot_sha256,operationId:q.operationId,planSha256};
 }catch(e){if(dispatch&&!completed)try{recordOutcome({...journal,outcome:'outcome_unknown',artifactSha256:null});}catch{}if(e instanceof DumpError)throw e;fail('dump_outcome_unknown');}
 finally{if(child&&closed&&!completed&&!await stop(child,closed))unconfirmed=true;close(outfd);close(metafd);close(finalfd);close(passfd);close(cafd);key?.fill(0);password?.fill(0);pass?.fill(0);if(snapshot)await snapshot.close();}
}
