// Single trusted-root journal; never claims project-wide actor exclusion.
import {createHash} from 'node:crypto';
import {constants,closeSync,fsyncSync,fstatSync,lstatSync,openSync,readSync,realpathSync,writeSync} from 'node:fs';
import {join} from 'node:path';
import {types} from 'node:util';
export class JournalError extends Error{constructor(code){super(code);this.name='JournalError';this.code=code;}}
const fail=c=>{throw new JournalError(c);},UUID=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/,HASH=/^[0-9a-f]{64}$/;
const ZERO='0'.repeat(64),sha=s=>createHash('sha256').update(s).digest('hex');
function option(o,k){const d=Object.getOwnPropertyDescriptor(o,k);if(!d||!Object.hasOwn(d,'value'))fail('invalid_input');return d.value;}
function input(o){if(!o||typeof o!=='object'||types.isProxy(o))fail('invalid_input');const scope=option(o,'mode');if(!['managed','synthetic'].includes(scope))fail('invalid_input');
 const root=option(o,'root'),id=option(o,'operationId'),plan=option(o,'planSha256');if(typeof root!=='string'||!root.startsWith('/')||realpathSync(root)!==root||!UUID.test(id??'')||!HASH.test(plan??''))fail('invalid_input');
 const s=lstatSync(root);if(!s.isDirectory()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o777)!==0o700)fail('trusted_root_refused');return {root,id,scope,plan};}
function paths(p){return {active:join(p.root,'active-attempt'),journal:join(p.root,`attempt-${p.id}.journal`),permit:join(p.root,`dispatch-${p.id}.permit`),outcome:join(p.root,`outcome-${p.id}.marker`)};}
function syncDir(root){const fd=openSync(root,constants.O_RDONLY);try{fsyncSync(fd);}finally{closeSync(fd);}}
function writeAll(fd,buffer){let pos=0;while(pos<buffer.length)pos+=writeSync(fd,buffer,pos,buffer.length-pos,null);}
function create(path,data){let fd,owned=false;try{fd=openSync(path,constants.O_CREAT|constants.O_EXCL|constants.O_WRONLY|(constants.O_NOFOLLOW??0),0o600);owned=true;writeAll(fd,Buffer.from(data));fsyncSync(fd);}
 catch(e){if(!owned&&e?.code==='EEXIST')fail('existing_record_refused');fail('journal_write_unconfirmed');}finally{if(fd!==undefined)closeSync(fd);}}
function read(path){let fd;try{fd=openSync(path,constants.O_RDONLY|(constants.O_NOFOLLOW??0));const st=fstatSync(fd);
 if(!st.isFile()||st.uid!==process.getuid()||(st.mode&0o777)!==0o600||st.nlink!==1||st.size<1||st.size>16384)fail('journal_refused');
 const b=Buffer.alloc(st.size);let n=0;while(n<b.length){const k=readSync(fd,b,n,b.length-n,n);if(!k)fail('journal_refused');n+=k;}return {text:b.toString('utf8'),identity:st};
 }catch(e){if(e instanceof JournalError)throw e;if(e?.code==='ENOENT')return null;fail('journal_refused');}finally{if(fd!==undefined)closeSync(fd);}}
function entry(p,state,previous,artifact){const fields={version:'collect.pg-backup-journal.v2',scope:p.scope,project_ref:'rrlduytparvsjfmegalh',operation_id:p.id,plan_sha256:p.plan,state,previous,artifact};const body=JSON.stringify(fields);return JSON.stringify({...fields,hash:sha(body)})+'\n';}
function parse(text,p){if(!text.endsWith('\n'))fail('journal_refused');const lines=text.trimEnd().split('\n');if(lines.length<1||lines.length>3)fail('journal_refused');let prev=ZERO,states=[],lastArtifact=null;
 for(const line of lines){let v;try{v=JSON.parse(line);}catch{fail('journal_refused');}const {version,scope,project_ref,operation_id,plan_sha256,state,previous,artifact,hash}=v;
  if(Object.keys(v).join(',')!=='version,scope,project_ref,operation_id,plan_sha256,state,previous,artifact,hash'||version!=='collect.pg-backup-journal.v2'||scope!==p.scope||project_ref!=='rrlduytparvsjfmegalh'||operation_id!==p.id||plan_sha256!==p.plan||previous!==prev||
   !['prepared','dispatch_intent','completed','outcome_unknown'].includes(state)||
   (state==='completed'?!HASH.test(artifact??''):artifact!==null)||hash!==sha(JSON.stringify({version,scope,project_ref,operation_id,plan_sha256,state,previous,artifact})))fail('journal_refused');
  prev=hash;states.push(state);lastArtifact=artifact;
 }
 const legal=[['prepared'],['prepared','dispatch_intent'],['prepared','dispatch_intent','completed'],['prepared','dispatch_intent','outcome_unknown']];
 if(!legal.some(x=>x.join(',')===states.join(',')))fail('journal_refused');return {states,last:states.at(-1),hash:prev,artifact:lastArtifact};}
function requireActive(p){const r=read(paths(p).active);if(!r||r.text!==JSON.stringify({version:'collect.pg-active.v2',scope:p.scope,project_ref:'rrlduytparvsjfmegalh',operation_id:p.id,plan_sha256:p.plan})+'\n')fail('active_attempt_mismatch');return r;}
function load(p){const r=read(paths(p).journal);if(!r)fail('journal_missing');return {...parse(r.text,p),identity:r.identity};}
function append(p,line,identity){let fd;try{fd=openSync(paths(p).journal,constants.O_WRONLY|constants.O_APPEND|(constants.O_NOFOLLOW??0));const s=fstatSync(fd);
 if(s.dev!==identity.dev||s.ino!==identity.ino||s.uid!==process.getuid()||(s.mode&0o777)!==0o600||s.nlink!==1)fail('journal_refused');writeAll(fd,Buffer.from(line));fsyncSync(fd);
 }catch(e){if(e instanceof JournalError)throw e;fail('journal_write_unconfirmed');}finally{if(fd!==undefined)closeSync(fd);}}
export function prepareAttempt(o){const p=input(o),q=paths(p);if(read(q.journal)||read(q.permit)||read(q.outcome))fail('existing_record_refused');
 create(q.active,JSON.stringify({version:'collect.pg-active.v2',scope:p.scope,project_ref:'rrlduytparvsjfmegalh',operation_id:p.id,plan_sha256:p.plan})+'\n');syncDir(p.root);
 create(q.journal,entry(p,'prepared',ZERO,null));syncDir(p.root);return {status:'prepared'};}
export function recordDispatchIntent(o){const p=input(o),q=paths(p);requireActive(p);const j=load(p);if(j.last!=='prepared')fail('dispatch_refused');
 create(q.permit,JSON.stringify({version:'collect.pg-dispatch.v2',scope:p.scope,operation_id:p.id,plan_sha256:p.plan})+'\n');syncDir(p.root);append(p,entry(p,'dispatch_intent',j.hash,null),j.identity);return {status:'dispatch_intent_recorded'};}
export function recordOutcome(o){const p=input(o),q=paths(p),result=option(o,'outcome'),artifact=option(o,'artifactSha256');
 if(!['completed','outcome_unknown'].includes(result)||result==='completed'&&!HASH.test(artifact??'')||result==='outcome_unknown'&&artifact!==null)fail('invalid_input');
 requireActive(p);const j=load(p);if(j.last!=='dispatch_intent')fail('outcome_refused');
 create(q.outcome,JSON.stringify({version:'collect.pg-outcome.v2',scope:p.scope,operation_id:p.id,plan_sha256:p.plan,outcome:result})+'\n');syncDir(p.root);
 append(p,entry(p,result,j.hash,artifact),j.identity);
 // Even completed attempts retain the active gate. Clearing it is
 // intentionally not implemented; no new attempt is implied by a receipt.
 return {status:result};
}
export function readAttempt(o){const p=input(o);requireActive(p);const j=load(p);return {status:j.last,dispatchAllowed:false,artifactSha256:j.artifact,planSha256:p.plan};}
