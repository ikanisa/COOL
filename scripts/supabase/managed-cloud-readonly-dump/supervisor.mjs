// Governed, one-dispatch read-only dump. The reviewed plan contains paths and
// pins only; password and key bytes are consumed inside the child process.
import {createHash,timingSafeEqual} from 'node:crypto';
import {spawn} from 'node:child_process';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {types} from 'node:util';
import {cleanManagedEnvironment} from './snapshot.mjs';
import {decodeDiagnostics,MAX_DIAGNOSTIC_BYTES} from './diagnostics.mjs';
export class SupervisorError extends Error{constructor(code){super(code);this.name='SupervisorError';this.code=code;}}
const fail=c=>{throw new SupervisorError(c);},HASH=/^[0-9a-f]{64}$/;
function canonical(v){if(v===null||typeof v==='string'||typeof v==='boolean')return JSON.stringify(v);if(typeof v==='number'&&Number.isSafeInteger(v))return JSON.stringify(v);
 if(types.isProxy(v))fail('invalid_plan');if(Array.isArray(v)){if(Reflect.ownKeys(v).length!==v.length+1)fail('invalid_plan');for(let i=0;i<v.length;i++){const d=Object.getOwnPropertyDescriptor(v,String(i));if(!d||!Object.hasOwn(d,'value'))fail('invalid_plan');}return '['+v.map(canonical).join(',')+']';}
 if(v&&typeof v==='object'&&Object.getPrototypeOf(v)===Object.prototype){const keys=Object.keys(v).sort();if(Reflect.ownKeys(v).length!==keys.length)fail('invalid_plan');return '{'+keys.map(k=>{const d=Object.getOwnPropertyDescriptor(v,k);if(!d||!Object.hasOwn(d,'value'))fail('invalid_plan');return JSON.stringify(k)+':'+canonical(d.value);}).join(',')+'}';}fail('invalid_plan');}
export const planDigest=plan=>createHash('sha256').update(canonical(plan),'utf8').digest('hex');
// Only a verified completed receipt is successful for shell/automation use.
export const cliExitCode=result=>result?.status==='completed_point_in_time'?0:1;
function validate(plan,pin){
 if(!plan||typeof plan!=='object'||types.isProxy(plan)||Object.getPrototypeOf(plan)!==Object.prototype||
  Object.keys(plan).sort().join(',')!=='deadlineMs,request'||!HASH.test(pin??''))fail('invalid_plan');
 const deadline=Object.getOwnPropertyDescriptor(plan,'deadlineMs'),requestDescriptor=Object.getOwnPropertyDescriptor(plan,'request');
 if(!deadline||!Object.hasOwn(deadline,'value')||!requestDescriptor||!Object.hasOwn(requestDescriptor,'value')||!Number.isSafeInteger(deadline.value)||deadline.value<1000||deadline.value>14400000)fail('invalid_plan');
 const serialized=canonical(plan),safe=JSON.parse(serialized),request=safe.request;if(!request||typeof request!=='object'||!['managed','synthetic'].includes(request.mode))fail('invalid_plan');
 if(request.mode==='managed'&&!cleanManagedEnvironment())fail('managed_environment_refused');
 const computed=createHash('sha256').update(serialized).digest('hex');if(!timingSafeEqual(Buffer.from(computed,'hex'),Buffer.from(pin,'hex')))fail('plan_pin_mismatch');return safe;
}
function outcome(c){return new Promise(resolve=>{let error=false;c.once('error',()=>{error=true;});c.once('close',(code,signal)=>resolve({code,signal,error}));});}
async function within(p,ms){let timer;try{return await Promise.race([p,new Promise(r=>{timer=setTimeout(()=>r(null),ms);})]);}finally{clearTimeout(timer);}}
function signalGroup(c,sig){if(c.pid>0&&c.exitCode===null&&c.signalCode===null)try{process.kill(-c.pid,sig);}catch{}}
function groupGone(pid){try{process.kill(-pid,0);return false;}catch(e){return e?.code==='ESRCH';}}
async function groupStopped(pid){const end=Date.now()+1500;while(Date.now()<end){if(groupGone(pid))return true;await new Promise(r=>setTimeout(r,50));}return groupGone(pid);}
async function stop(c,closed){signalGroup(c,'SIGTERM');let x=await within(closed,1500);if(!x){signalGroup(c,'SIGKILL');x=await within(closed,1500);}return x;}
export async function runReviewedDump({plan,expectedPlanSha256,signal=null}={}){
 const safe=validate(plan,expectedPlanSha256),request=safe.request,env={PATH:'/usr/bin:/bin',LC_ALL:'C'};
 if(signal!==null&&(typeof signal!=='object'||typeof signal.addEventListener!=='function'||typeof signal.removeEventListener!=='function'))fail('invalid_input');
 if(signal?.aborted)return {status:'interrupted_before_dispatch',retryAuthorized:false};
 if(request.mode==='synthetic'&&process.env.COLLECT_SYNTHETIC_PG_BIN)env.COLLECT_SYNTHETIC_PG_BIN=process.env.COLLECT_SYNTHETIC_PG_BIN;
 const child=spawn(process.execPath,[fileURLToPath(new URL('./worker.mjs',import.meta.url))],{detached:true,stdio:['pipe','pipe','ignore','pipe'],env}),closed=outcome(child);
 let chunks=[],trace=[],traceBytes=0,traceOverflow=false,n=0,overflow=false,timed=false,interrupted=false,timer,fallback,finished=false,resolveAbort;
 const annotated=value=>{if(traceOverflow||!trace.length)return value;const b=Buffer.concat(trace);try{const diagnostics=decodeDiagnostics(b);return diagnostics.length?{...value,diagnostics}:value;}finally{b.fill(0);}};
 const abortWait=new Promise(resolve=>{resolveAbort=resolve;}),onAbort=()=>{interrupted=true;signalGroup(child,'SIGTERM');resolveAbort({kind:'abort'});};
 try{child.stdout.on('data',b=>{n+=b.length;if(n>16384){overflow=true;signalGroup(child,'SIGTERM');}else chunks.push(b);});child.stdin.on('error',()=>{});
  child.stdio[3].on('error',()=>{});child.stdio[3].on('data',b=>{traceBytes+=b.length;if(traceBytes>MAX_DIAGNOSTIC_BYTES){traceOverflow=true;b.fill(0);}else trace.push(b);});
  signal?.addEventListener('abort',onAbort,{once:true});if(signal?.aborted)onAbort();
  timer=setTimeout(()=>{timed=true;signalGroup(child,'SIGTERM');},safe.deadlineMs);child.stdin.end(JSON.stringify({action:'dump',plan:safe,planSha256:expectedPlanSha256}));
  const limit=new Promise(resolve=>{fallback=setTimeout(()=>resolve({kind:'stuck'}),safe.deadlineMs+1500);});
  const event=await Promise.race([closed.then(result=>({kind:'closed',result})),abortWait,limit]);
  let result=event.kind==='closed'?event.result:await stop(child,closed);
  if(!result){finished=true;return annotated({status:'group_stop_unconfirmed',retryAuthorized:false});}finished=true;
  if(interrupted){if(!await groupStopped(child.pid))return annotated({status:'group_stop_unconfirmed',retryAuthorized:false});return annotated({status:'interrupted_outcome_unknown',retryAuthorized:false});}
  if(timed){if(!await groupStopped(child.pid))return annotated({status:'group_stop_unconfirmed',retryAuthorized:false});return annotated({status:'deadline_terminated_outcome_unknown',retryAuthorized:false});}
  if(!await groupStopped(child.pid))return annotated({status:'group_stop_unconfirmed',retryAuthorized:false});
  if(result.error||result.signal||result.code!==0||overflow)return annotated({status:'worker_outcome_unconfirmed',retryAuthorized:false});
  if(!n)return annotated({status:'acknowledgement_missing_do_not_retry',retryAuthorized:false});
  let body;try{body=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{return annotated({status:'worker_outcome_unconfirmed',retryAuthorized:false});}
  if(body?.status!=='completed_point_in_time'||!['bundleSha256','dumpSha256','inventorySha256','snapshotSha256'].every(k=>HASH.test(body[k]??''))||body.operationId!==request.operationId||body.planSha256!==expectedPlanSha256)return annotated({status:'worker_outcome_unconfirmed',retryAuthorized:false});
  return {...body,retryAuthorized:false};
 }catch(e){if(e instanceof SupervisorError)throw e;return annotated({status:'worker_outcome_unconfirmed',retryAuthorized:false});}
 finally{if(timer!==undefined)clearTimeout(timer);if(fallback!==undefined)clearTimeout(fallback);signal?.removeEventListener('abort',onAbort);if(!finished)await stop(child,closed);for(const b of chunks)b.fill(0);for(const b of trace)b.fill(0);chunks=[];trace=[];}
}
export async function readReviewedDumpStatus({mode,root,operationId,expectedPlanSha256,deadlineMs}={}){
 if(!['managed','synthetic'].includes(mode)||typeof root!=='string'||!root.startsWith('/')||root.length>4096||
  !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(operationId??'')||!HASH.test(expectedPlanSha256??'')||!Number.isSafeInteger(deadlineMs)||deadlineMs<1000||deadlineMs>60000)fail('invalid_input');
 if(mode==='managed'&&!cleanManagedEnvironment())fail('managed_environment_refused');
 const child=spawn(process.execPath,[fileURLToPath(new URL('./worker.mjs',import.meta.url))],{detached:true,stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}}),closed=outcome(child);
 let chunks=[],n=0,timed=false,timer,finished=false;
 try{child.stdout.on('data',b=>{n+=b.length;if(n<=16384)chunks.push(b);else signalGroup(child,'SIGTERM');});child.stdin.on('error',()=>{});
  timer=setTimeout(()=>{timed=true;signalGroup(child,'SIGTERM');},deadlineMs);child.stdin.end(JSON.stringify({action:'status',mode,root,operationId,expectedPlanSha256}));
  let x=await within(closed,deadlineMs+1500);if(!x)x=await stop(child,closed);if(!x){finished=true;return {status:'group_stop_unconfirmed',retryAuthorized:false};}finished=true;
  if(!await groupStopped(child.pid))return {status:'group_stop_unconfirmed',retryAuthorized:false};
  if(timed||x.error||x.signal||x.code!==0||!n||n>16384)return {status:'status_unavailable_do_not_retry',retryAuthorized:false};
  let body;try{body=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{return {status:'status_unavailable_do_not_retry',retryAuthorized:false};}
  if(!body||!['prepared','dispatch_intent','completed','outcome_unknown'].includes(body.status)||body.dispatchAllowed!==false||body.planSha256!==expectedPlanSha256||
   (body.status==='completed'?!HASH.test(body.artifactSha256??''):body.artifactSha256!==null))return {status:'status_unavailable_do_not_retry',retryAuthorized:false};
  return {status:body.status,planSha256:body.planSha256,bundleSha256:body.artifactSha256,retryAuthorized:false};
 }finally{if(timer!==undefined)clearTimeout(timer);if(!finished)await stop(child,closed);for(const b of chunks)b.fill(0);chunks=[];}
}
export async function verifyReviewedDump({mode,journalRoot,artifactRoot,keyPath,operationId,expectedPlanSha256,deadlineMs}={}){
 if(!['managed','synthetic'].includes(mode)||![journalRoot,artifactRoot,keyPath].every(x=>typeof x==='string'&&x.startsWith('/')&&x.length<=4096)||
  !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(operationId??'')||!HASH.test(expectedPlanSha256??'')||!Number.isSafeInteger(deadlineMs)||deadlineMs<1000||deadlineMs>14400000)fail('invalid_input');
 if(mode==='managed'&&!cleanManagedEnvironment())fail('managed_environment_refused');
 const child=spawn(process.execPath,[fileURLToPath(new URL('./worker.mjs',import.meta.url))],{detached:true,stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}}),closed=outcome(child);
 let chunks=[],n=0,timed=false,timer,finished=false;
 try{child.stdout.on('data',b=>{n+=b.length;if(n<=16384)chunks.push(b);else signalGroup(child,'SIGTERM');});child.stdin.on('error',()=>{});
  timer=setTimeout(()=>{timed=true;signalGroup(child,'SIGTERM');},deadlineMs);child.stdin.end(JSON.stringify({action:'verify',request:{mode,journalRoot,artifactRoot,keyPath,operationId,expectedPlanSha256}}));
  let x=await within(closed,deadlineMs+1500);if(!x)x=await stop(child,closed);if(!x){finished=true;return {status:'group_stop_unconfirmed',retryAuthorized:false};}finished=true;
  if(!await groupStopped(child.pid))return {status:'group_stop_unconfirmed',retryAuthorized:false};
  if(timed||x.error||x.signal||x.code!==0||!n||n>16384)return {status:'verification_unavailable_do_not_retry',retryAuthorized:false};
  let body;try{body=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{return {status:'verification_unavailable_do_not_retry',retryAuthorized:false};}
  if(body?.status!=='bundle_verified_point_in_time'||body.operationId!==operationId||body.planSha256!==expectedPlanSha256||body.retryAuthorized!==false||
   !['bundleSha256','dumpSha256','inventorySha256','snapshotSha256'].every(k=>HASH.test(body[k]??'')))return {status:'verification_unavailable_do_not_retry',retryAuthorized:false};
  return body;
 }finally{if(timer!==undefined)clearTimeout(timer);if(!finished)await stop(child,closed);for(const b of chunks)b.fill(0);chunks=[];}
}
async function stdin(){return new Promise((resolve,reject)=>{let chunks=[],size=0,finished=false,timer;const finish=e=>{if(finished)return;finished=true;clearTimeout(timer);process.stdin.removeListener('data',onData);process.stdin.removeListener('end',onEnd);process.stdin.removeListener('error',onError);process.stdin.removeListener('close',onClose);if(e){for(const b of chunks)b.fill(0);process.stdin.destroy();reject(e);return;}const b=Buffer.concat(chunks);for(const x of chunks)x.fill(0);try{resolve(JSON.parse(b.toString('utf8')));}catch{reject(new Error());}finally{b.fill(0);}};
 const onData=b=>{size+=b.length;if(size>65536){b.fill(0);finish(Error());}else chunks.push(b);},onEnd=()=>finish(),onError=()=>finish(Error()),onClose=()=>finish(Error());
 process.stdin.on('data',onData);process.stdin.on('end',onEnd);process.stdin.on('error',onError);process.stdin.on('close',onClose);timer=setTimeout(()=>finish(Error()),10000);});}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const ctl=new AbortController(),interrupt=()=>{ctl.abort();process.stdin.destroy();};process.on('SIGTERM',interrupt);process.on('SIGINT',interrupt);
 try{if(process.argv.length!==3||!HASH.test(process.argv[2])||!cleanManagedEnvironment())fail('managed_environment_refused');const plan=await stdin();const result=await runReviewedDump({plan,expectedPlanSha256:process.argv[2],signal:ctl.signal});process.stdout.write(JSON.stringify(result)+'\n');process.exitCode=ctl.signal.aborted?1:cliExitCode(result);}
 catch{process.stdout.write(JSON.stringify({status:'refused',retryAuthorized:false})+'\n');process.exitCode=1;}
 finally{process.removeListener('SIGTERM',interrupt);process.removeListener('SIGINT',interrupt);}
}
