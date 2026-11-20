// Private, one-use capture journal. A missing or partial record is unknown.
import {constants} from 'node:fs';
import {lstat,mkdir,open,realpath} from 'node:fs/promises';
import {isAbsolute,join,normalize} from 'node:path';
import {randomUUID} from 'node:crypto';
import {ChildProcess} from 'node:child_process';
const FORMAT='collect.archive-capture-session.v3',HEX=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const fail=code=>{throw Object.assign(Error(code),{captureCode:code});};
const exact=(o,k)=>!!o&&typeof o==='object'&&!Array.isArray(o)&&Object.getPrototypeOf(o)===Object.prototype&&Object.keys(o).sort().join(',')===[...k].sort().join(',');
async function directory(path){
 if(typeof path!=='string'||!isAbsolute(path)||normalize(path)!==path||path==='/'||path.includes('\0'))fail('JOURNAL_REFUSED');
 try{const s=await lstat(path);if(!s.isDirectory()||s.isSymbolicLink()||await realpath(path)!==path||s.uid!==process.getuid()||(s.mode&0o777)!==0o700)fail('JOURNAL_REFUSED');}
 catch{fail('JOURNAL_REFUSED');}return path;
}
async function syncDir(path){let h;try{h=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);await h.sync();}catch{fail('JOURNAL_REFUSED');}finally{await h?.close().catch(()=>{});}}
async function write(dir,name,value){let h;const data=JSON.stringify(value);if(Buffer.byteLength(data)>8192)fail('JOURNAL_REFUSED');
 try{h=await open(join(dir,name),constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,0o600);await h.writeFile(data);await h.sync();}
 catch{fail('JOURNAL_REFUSED');}finally{await h?.close().catch(()=>{});}await syncDir(dir);
}
async function read(dir,name){let h;try{
 const p=join(dir,name);h=await open(p,constants.O_RDONLY|constants.O_NOFOLLOW);const a=await h.stat({bigint:true});
 if(!a.isFile()||a.uid!==BigInt(process.getuid())||(Number(a.mode)&0o777)!==0o600||a.size<2n||a.size>8192n)fail('JOURNAL_REFUSED');
 const raw=await h.readFile('utf8'),b=await h.stat({bigint:true}),c=await lstat(p,{bigint:true});
 const same=(x,y)=>x.dev===y.dev&&x.ino===y.ino&&x.size===y.size&&x.mtimeNs===y.mtimeNs&&x.ctimeNs===y.ctimeNs;
 if(!same(a,b)||!same(a,c)||!c.isFile())fail('JOURNAL_REFUSED');const result=JSON.parse(raw);if(JSON.stringify(result)!==raw)fail('JOURNAL_REFUSED');return result;
 }catch{fail('JOURNAL_REFUSED');}finally{await h?.close().catch(()=>{});}}
async function checkJob(job){
 if(!job||typeof job.root!=='string'||job.dir!==join(job.root,'active-capture'))fail('JOURNAL_REFUSED');
 await directory(job.root);await directory(job.dir);const stored=await read(job.dir,'intent.json');
 if(JSON.stringify(stored)!==JSON.stringify(job.intent))fail('JOURNAL_REFUSED');return stored;
}
function validBackend(identity,intent){
 return exact(identity,['pid','backendStart','systemIdentifier','postmasterStart','database','sessionUser','applicationName'])&&
  Number.isSafeInteger(identity.pid)&&identity.pid>0&&/^[1-9][0-9]{9,19}$/.test(identity.systemIdentifier??'')&&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$/.test(identity.backendStart??'')&&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$/.test(identity.postmasterStart??'')&&
  typeof identity.database==='string'&&identity.sessionUser==='postgres'&&identity.applicationName===intent.applicationName;
}
export async function beginCapture(root,manifestSha256){
 if(!HEX.test(manifestSha256??''))fail('JOURNAL_REFUSED');const dir=join(await directory(root),'active-capture'),operationId=randomUUID();
 try{await mkdir(dir,{mode:0o700});}catch{fail('CAPTURE_ALREADY_ATTEMPTED');}
 await syncDir(root);const intent={format:FORMAT,operationId,manifestSha256,applicationName:'collect_cap_'+operationId.replaceAll('-','')};
 await write(dir,'intent.json',intent);return Object.freeze({root,dir,intent});
}
async function recordActor(job,pid){
 await checkJob(job);if(!Number.isSafeInteger(pid)||pid<2)fail('JOURNAL_REFUSED');
 await write(job.dir,'actor.json',{format:FORMAT,operationId:job.intent.operationId,pid});
}
export async function recordBackend(job,identity){
 await checkJob(job);const actor=await read(job.dir,'actor.json');
 if(!exact(actor,['format','operationId','pid'])||actor.format!==FORMAT||actor.operationId!==job.intent.operationId||!Number.isSafeInteger(actor.pid)||actor.pid<2||
  !validBackend(identity,job.intent))fail('BACKEND_IDENTITY_REFUSED');
 await write(job.dir,'backend.json',{format:FORMAT,operationId:job.intent.operationId,...identity});
}
// Only a supervisor that owns the spawned child may call this after observing
// its close event and confirming the owned process group has disappeared.
async function recordActorClosed(job,pid){
 await checkJob(job);const actor=await read(job.dir,'actor.json');
 if(actor.format!==FORMAT||actor.operationId!==job.intent.operationId||actor.pid!==pid)fail('ACTOR_IDENTITY_REFUSED');
 await write(job.dir,'actor-closed.json',{format:FORMAT,operationId:job.intent.operationId,pid,closeObserved:true,groupGoneObserved:true});
}
const within=(p,ms)=>new Promise(resolve=>{const t=setTimeout(()=>resolve(null),ms);p.then(x=>{clearTimeout(t);resolve(x);},()=>{clearTimeout(t);resolve(null);});});
const groupGone=pid=>{try{process.kill(-pid,0);return false;}catch(e){return e?.code==='ESRCH';}};
// Attach before the parent sends worker input. Only an actual ChildProcess
// close event and two observed missing-group checks create the closure record.
// An owner-process crash loses this observation and leaves reconciliation
// unknown. This does not cover escaped descendants or a hostile same user.
export async function bindOwnedActor(job,child){
 if(!(child instanceof ChildProcess)||!Number.isSafeInteger(child.pid)||child.pid<2||child.exitCode!==null||child.signalCode!==null)fail('ACTOR_IDENTITY_REFUSED');
 const pid=child.pid;let error=false;
 const closed=new Promise(resolve=>{child.once('error',()=>{error=true;});child.once('close',(code,signal)=>resolve({code,signal}));});
 await recordActor(job,pid);
 return async function confirmOwnedActorClosure(){
  const result=await within(closed,3000);if(!result||error||!groupGone(pid))return false;
  await new Promise(r=>setTimeout(r,100));if(!groupGone(pid))return false;
  await recordActorClosed(job,pid);return true;
 };
}
export async function readCapture(root,manifestSha256){
 const dir=join(await directory(root),'active-capture');await directory(dir);
 const intent=await read(dir,'intent.json');
 if(!exact(intent,['format','operationId','manifestSha256','applicationName'])||intent.format!==FORMAT||!UUID.test(intent.operationId??'')||
  intent.manifestSha256!==manifestSha256||intent.applicationName!=='collect_cap_'+intent.operationId.replaceAll('-',''))fail('JOURNAL_REFUSED');
 const actor=await read(dir,'actor.json'),backend=await read(dir,'backend.json'),closed=await read(dir,'actor-closed.json');
 const {format:backendFormat,operationId:backendOperationId,...identity}=backend;
 if(!exact(actor,['format','operationId','pid'])||actor.format!==FORMAT||actor.operationId!==intent.operationId||!Number.isSafeInteger(actor.pid)||actor.pid<2||
  !exact(closed,['format','operationId','pid','closeObserved','groupGoneObserved'])||closed.format!==FORMAT||closed.operationId!==intent.operationId||closed.pid!==actor.pid||
  closed.closeObserved!==true||closed.groupGoneObserved!==true||!exact(backend,['format','operationId','pid','backendStart','systemIdentifier','postmasterStart','database','sessionUser','applicationName'])||
  backendFormat!==FORMAT||backendOperationId!==intent.operationId||!validBackend(identity,intent))fail('JOURNAL_REFUSED');
 return Object.freeze({root,dir,intent,actor,backend});
}
export async function recordServerClosure(job){
 await checkJob(job);await write(job.dir,'server-closed.json',{format:FORMAT,operationId:job.intent.operationId,manifestSha256:job.intent.manifestSha256,independentObservations:2});
}
