// Trusted-root single-attempt journal. It is not global actor exclusion.
import {constants} from 'node:fs';
import {lstat,mkdir,open,realpath} from 'node:fs/promises';
import {isAbsolute,join,normalize} from 'node:path';
import {randomUUID} from 'node:crypto';
import {archiveIdentity} from './archive-core.mjs';

const FORMAT='collect.archive-journal.v1',PROJECT='rrlduytparvsjfmegalh',HASH=/^[a-f0-9]{64}$/;
const fail=code=>{throw Object.assign(Error(code),{archiveCode:code});};
const exact=(o,k)=>!!o&&typeof o==='object'&&!Array.isArray(o)&&Object.getPrototypeOf(o)===Object.prototype&&
 Object.keys(o).sort().join('\0')===[...k].sort().join('\0');
function intent(p){
 if(!exact(p,['preimageSha256','admissions','reviewedPlanSha256','exclusionEvidenceSha256','implementationManifestSha256'])||!HASH.test(p.preimageSha256??'')||
  !HASH.test(p.reviewedPlanSha256??'')||!HASH.test(p.exclusionEvidenceSha256??'')||!HASH.test(p.implementationManifestSha256??'')||!exact(p.admissions,['count','sha'])||
  !Number.isSafeInteger(p.admissions.count)||p.admissions.count<0||p.admissions.count>10000||!HASH.test(p.admissions.sha??''))fail('JOURNAL_PLAN_REFUSED');
 return {format:FORMAT,project:PROJECT,version:archiveIdentity.version,sourceSha256:archiveIdentity.sourceSha256,
  preimageSha256:p.preimageSha256,admissionsCount:p.admissions.count,admissionsSha256:p.admissions.sha,
  exclusionEvidenceSha256:p.exclusionEvidenceSha256,implementationManifestSha256:p.implementationManifestSha256,reviewedPlanSha256:p.reviewedPlanSha256};
}
async function directory(path){
 if(typeof path!=='string'||!isAbsolute(path)||normalize(path)!==path||path==='/'||path.includes('\0'))fail('JOURNAL_UNAVAILABLE');
 try{const s=await lstat(path),p=await realpath(path);
  if(!s.isDirectory()||s.isSymbolicLink()||p!==path||s.uid!==process.getuid()||(s.mode&0o777)!==0o700)fail('JOURNAL_UNAVAILABLE');
 }catch{fail('JOURNAL_UNAVAILABLE');}return path;
}
async function syncDir(path){let h;try{h=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);await h.sync();}catch{fail('JOURNAL_UNAVAILABLE');}finally{await h?.close().catch(()=>{});}}
async function write(dir,name,value){
 const data=JSON.stringify(value);if(Buffer.byteLength(data)>8192)fail('JOURNAL_UNAVAILABLE');let h;
 try{h=await open(join(dir,name),constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,0o600);await h.writeFile(data);await h.sync();}
 catch{fail('JOURNAL_UNAVAILABLE');}finally{await h?.close().catch(()=>{});}await syncDir(dir);
}
async function read(dir,name){
 let h;try{
  h=await open(join(dir,name),constants.O_RDONLY|constants.O_NOFOLLOW);const a=await h.stat();
  if(!a.isFile()||a.uid!==process.getuid()||(a.mode&0o777)!==0o600||a.size<2||a.size>8192)fail('JOURNAL_UNAVAILABLE');
  const raw=await h.readFile('utf8'),b=await h.stat();
  if(a.dev!==b.dev||a.ino!==b.ino||a.size!==b.size||a.mtimeMs!==b.mtimeMs||a.ctimeMs!==b.ctimeMs)fail('JOURNAL_UNAVAILABLE');
  const v=JSON.parse(raw);if(JSON.stringify(v)!==raw)fail('JOURNAL_UNAVAILABLE');return v;
 }catch{fail('JOURNAL_UNAVAILABLE');}finally{await h?.close().catch(()=>{});}
}
export async function beginAttempt(root,plan){
 const value=intent(plan),dir=join(await directory(root),archiveIdentity.version);
 try{await mkdir(dir,{mode:0o700});}catch{fail('APPLY_ALREADY_ATTEMPTED');}
 await syncDir(root);await write(dir,'intent.json',value);return Object.freeze({root,dir});
}
export async function attachBackend(job,pid){
 await directory(job?.dir);if(!Number.isSafeInteger(pid)||pid<1)fail('JOURNAL_BACKEND_REFUSED');
 await write(job.dir,'backend.json',{format:FORMAT,backendPid:pid});
}
export async function finishAttempt(job,state,code=null){
 await directory(job?.dir);if(!['committed','refused','unconfirmed'].includes(state)||!(code===null||/^[A-Z_]{1,64}$/.test(code)))fail('JOURNAL_OUTCOME_REFUSED');
 await write(job.dir,'outcome.json',{format:FORMAT,state,code});
}
export async function beginReconciliation(root,plan){
 const expected=intent(plan),dir=join(await directory(root),archiveIdentity.version);await directory(dir);
 const [stored,backend]=await Promise.all([read(dir,'intent.json'),read(dir,'backend.json')]);
 if(JSON.stringify(stored)!==JSON.stringify(expected)||!exact(backend,['format','backendPid'])||backend.format!==FORMAT||
  !Number.isSafeInteger(backend.backendPid)||backend.backendPid<1)fail('JOURNAL_MISMATCH');
 const attempt=randomUUID();await write(dir,`reconcile-${attempt}.intent.json`,{format:FORMAT,attempt,priorBackendPid:backend.backendPid});
 return Object.freeze({root,dir,attempt,priorBackendPid:backend.backendPid});
}
export async function finishReconciliation(job,state){
 await directory(job?.dir);if(!/^[0-9a-f-]{36}$/.test(job?.attempt??'')||
  !['recorded_selected_postconditions_verified','not_recorded_do_not_retry','unconfirmed'].includes(state))fail('JOURNAL_OUTCOME_REFUSED');
 await write(job.dir,`reconcile-${job.attempt}.outcome.json`,{format:FORMAT,attempt:job.attempt,state});
}
