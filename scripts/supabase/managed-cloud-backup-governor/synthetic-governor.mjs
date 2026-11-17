// A bounded outer supervisor for synthetic workers. Managed dispatch is closed.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {types} from 'node:util';
export class GovernorError extends Error{constructor(code){super(code);this.name='GovernorError';this.code=code;}}
const fail=c=>{throw new GovernorError(c);},UUID=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
function option(o,k){const d=Object.getOwnPropertyDescriptor(o,k);if(!d||!Object.hasOwn(d,'value'))fail('invalid_input');return d.value;}
function input(o,read){if(!o||typeof o!=='object'||types.isProxy(o))fail('invalid_input');if(option(o,'mode')!=='synthetic')fail('managed_execution_closed');
 const root=option(o,'root'),operationId=option(o,'operationId'),deadlineMs=option(o,'deadlineMs'),action=read?'read':option(o,'action');
 if(typeof root!=='string'||!root.startsWith('/')||root.length>4096||!UUID.test(operationId??'')||!Number.isInteger(deadlineMs)||deadlineMs<100||deadlineMs>60000||
  !['read','hang_before_prepare','blocked_before_prepare','hang_after_dispatch','hang_with_child','fixture_complete','fixture_missing_ack','synthetic_backup','synthetic_backup_missing_ack'].includes(action))fail('invalid_input');
 const config=['synthetic_backup','synthetic_backup_missing_ack'].includes(action)?option(o,'config'):null;if(config!==null&&(!config||typeof config!=='object'||types.isProxy(config)))fail('invalid_input');
 return {mode:'synthetic',root,operationId,deadlineMs,action,config};}
async function within(p,ms){let timer;try{return await Promise.race([p,new Promise(r=>{timer=setTimeout(()=>r(null),ms);})]);}finally{clearTimeout(timer);}}
function childOutcome(c){return new Promise(resolve=>{let error=false;c.once('error',()=>{error=true;});c.once('close',(code,signal)=>resolve({code,signal,error}));});}
function signalGroup(c,sig){if(c.pid>0&&c.exitCode===null&&c.signalCode===null)try{process.kill(-c.pid,sig);}catch{}}
function groupGone(pid){try{process.kill(-pid,0);return false;}catch(e){return e?.code==='ESRCH';}}
async function stopped(c,closed){signalGroup(c,'SIGTERM');let x=await within(closed,750);if(!x){signalGroup(c,'SIGKILL');x=await within(closed,750);}return x;}
export const syntheticGovernorTestHelpers=Object.freeze({childOutcome,stopped});
async function execute(o,read){const p=input(o,read),child=spawn(process.execPath,[fileURLToPath(new URL('./governed-worker.mjs',import.meta.url))],{detached:true,stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}}),closed=childOutcome(child);
 let chunks=[],count=0,overflow=false,timed=false,timer,finished=false;
 try{child.stdout.on('data',b=>{count+=b.length;if(count>16384){overflow=true;signalGroup(child,'SIGTERM');}else chunks.push(b);});child.stdin.on('error',()=>{});
  timer=setTimeout(()=>{timed=true;signalGroup(child,'SIGTERM');},p.deadlineMs);
  child.stdin.end(JSON.stringify(p));
  let x=await within(closed,p.deadlineMs+750);if(!x)x=await stopped(child,closed);
  if(!x){finished=true;return {status:'group_stop_unconfirmed',dispatchAllowed:false};}finished=true;
  if(timed){if(!groupGone(child.pid))return {status:'group_stop_unconfirmed',dispatchAllowed:false};return {status:'deadline_terminated_outcome_unknown',dispatchAllowed:false};}
  if(!groupGone(child.pid))return {status:'group_stop_unconfirmed',dispatchAllowed:false};
  if(x.error||x.signal||x.code!==0||overflow)return {status:'worker_outcome_unconfirmed',dispatchAllowed:false};
  if(!count)return {status:'acknowledgement_missing_do_not_retry',dispatchAllowed:false};
  let response;try{response=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{return {status:'worker_outcome_unconfirmed',dispatchAllowed:false};}
  if(!response||typeof response!=='object'||!['prepared','dispatch_intent','completed','outcome_unknown'].includes(response.status))return {status:'worker_outcome_unconfirmed',dispatchAllowed:false};
  if(response.status==='completed'&&(!/^[0-9a-f]{64}$/.test(response.artifactSha256??'')))return {status:'worker_outcome_unconfirmed',dispatchAllowed:false};
  return {status:response.status,dispatchAllowed:false,artifactSha256:response.artifactSha256??null};
 }catch(e){if(e instanceof GovernorError)throw e;return {status:'worker_outcome_unconfirmed',dispatchAllowed:false};}
 finally{if(timer!==undefined)clearTimeout(timer);if(!finished)await stopped(child,closed);for(const b of chunks)b.fill(0);chunks=[];}
}
export async function runSyntheticGovernedAttempt(o){return execute(o,false);}
export async function readSyntheticGovernedAttempt(o){return execute(o,true);}
export async function dispatchManagedBackup(){fail('managed_execution_closed');}
