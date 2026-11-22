// Clean, bounded launcher. No token or function body is put in argv or env.
import {spawn} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {canonicalPlan,planDigest,cleanEnvironment} from './core.mjs';
const HASH=/^[0-9a-f]{64}$/;
function outcome(c){return new Promise(resolve=>{let error=false;c.once('error',()=>{error=true;});c.once('close',(code,signal)=>resolve({code,signal,error}));});}
async function within(p,ms){let timer;try{return await Promise.race([p,new Promise(r=>{timer=setTimeout(()=>r(null),ms);})]);}finally{clearTimeout(timer);}}
function send(c,s){if(c.pid>0&&c.exitCode===null&&c.signalCode===null)try{c.kill(s);}catch{}}
async function stop(c,closed){send(c,'SIGTERM');let r=await within(closed,1500);if(!r){send(c,'SIGKILL');r=await within(closed,1500);}return r;}
export async function runSupervised({plan,expectedPlanSha256,expectedPinsSha256,signal=null}={}){
 if(!cleanEnvironment()||!HASH.test(expectedPlanSha256??'')||!HASH.test(expectedPinsSha256??'')||
  signal!==null&&!(signal instanceof AbortSignal))throw Error('invalid_input');
 const safe=JSON.parse(canonicalPlan(plan));if(planDigest(safe)!==expectedPlanSha256||safe.source_pins_sha256!==expectedPinsSha256)throw Error('pin_mismatch');
 if(signal?.aborted)return {status:'interrupted_before_dispatch',retryAuthorized:false};
 const child=spawn(process.execPath,[fileURLToPath(new URL('./worker.mjs',import.meta.url))],{stdio:['pipe','pipe','ignore','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}}),closed=outcome(child);
 let chunks=[],size=0,timer,finished=false,resolveInterruption,reason=null;
 const interrupted=new Promise(r=>{resolveInterruption=r;}),interrupt=()=>{if(reason)return;reason='interrupted';send(child,'SIGTERM');resolveInterruption();};
 try{
  child.stdin.on('error',()=>{});child.stdio[3].on('error',()=>{});
  child.stdout.on('data',b=>{size+=b.length;if(size>16384){b.fill(0);if(!reason){reason='output_overflow';send(child,'SIGTERM');resolveInterruption();}}else chunks.push(b);});
  signal?.addEventListener('abort',interrupt,{once:true});if(signal?.aborted)interrupt();
  timer=setTimeout(()=>{if(!reason){reason='deadline';send(child,'SIGTERM');resolveInterruption();}},safe.deadline_ms);
  child.stdin.end(JSON.stringify({plan:safe,expectedPlanSha256}));
  const event=await Promise.race([closed.then(r=>({kind:'closed',r})),interrupted.then(()=>({kind:'interrupted'}))]);
  const result=event.kind==='closed'?event.r:await stop(child,closed);if(!result){finished=true;return {status:'worker_stop_unconfirmed',retryAuthorized:false};}finished=true;
  if(reason)return {status:reason==='deadline'?'deadline_terminated_outcome_unknown':'interrupted_or_unconfirmed',retryAuthorized:false};
  if(result.error||result.signal||result.code!==0||!size||size>16384)return {status:'worker_outcome_unconfirmed',retryAuthorized:false};
  let body;try{body=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{return {status:'worker_outcome_unconfirmed',retryAuthorized:false};}
  if(body?.status!=='completed_point_in_time'||body.operation_id!==safe.operation_id||body.plan_sha256!==expectedPlanSha256||
   body.scope!==safe.scope||body.project_ref!=='rrlduytparvsjfmegalh'||!HASH.test(body.archive_sha256??'')||body.authenticated_readback!==true||body.retryAuthorized!==false)
   return {status:'worker_outcome_unconfirmed',retryAuthorized:false};
  return body;
 }finally{clearTimeout(timer);signal?.removeEventListener('abort',interrupt);if(!finished)await stop(child,closed);child.stdio[3].destroy();for(const b of chunks)b.fill(0);}
}
async function stdin(){return new Promise((resolve,reject)=>{let chunks=[],size=0,timer,done=false;const finish=e=>{if(done)return;done=true;clearTimeout(timer);process.stdin.removeListener('data',data);process.stdin.removeListener('end',end);process.stdin.removeListener('error',error);process.stdin.removeListener('close',error);
 if(e){for(const b of chunks)b.fill(0);process.stdin.destroy();reject(Error());return;}const b=Buffer.concat(chunks);for(const x of chunks)x.fill(0);try{resolve(JSON.parse(b.toString('utf8')));}catch{reject(Error());}finally{b.fill(0);}};
 const data=b=>{size+=b.length;if(size>65536){b.fill(0);finish(true);}else chunks.push(b);},end=()=>finish(false),error=()=>finish(true);
 process.stdin.on('data',data);process.stdin.on('end',end);process.stdin.on('error',error);process.stdin.on('close',error);timer=setTimeout(()=>finish(true),10000);});}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const ctl=new AbortController(),interrupt=()=>{ctl.abort();process.stdin.destroy();};process.on('SIGTERM',interrupt);process.on('SIGINT',interrupt);
 try{if(process.argv.length!==4||!cleanEnvironment())throw Error();const plan=await stdin();const r=await runSupervised({plan,expectedPlanSha256:process.argv[2],expectedPinsSha256:process.argv[3],signal:ctl.signal});
  process.stdout.write(JSON.stringify(r)+'\n');process.exitCode=r.status==='completed_point_in_time'&&!ctl.signal.aborted?0:1;
 }catch{process.stdout.write(JSON.stringify({status:'refused_or_unconfirmed',retryAuthorized:false})+'\n');process.exitCode=1;}
 finally{process.removeListener('SIGTERM',interrupt);process.removeListener('SIGINT',interrupt);}
}
