// Supervise one read-only observation; only aggregate response or fixed errors.
import {spawn} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {cleanEnvironment,validateEnvelope,validatePublicObservation} from './protocol.mjs';
import {readPrivateInput} from './input.mjs';
const safe=new Set(['input_refused','plan_refused','managed_preimage_unavailable','source_identity_refused','connection_refused','preflight_refused','result_refused']);
const refused=reason=>({status:'refused',reason:safe.has(reason)?reason:'input_refused',write_authorized:false});
const unknown=reason=>({status:reason,write_authorized:false});
const within=(promise,ms)=>new Promise(resolve=>{let done=false;const timer=setTimeout(()=>{if(!done){done=true;resolve(null);}},ms);promise.then(x=>{if(!done){done=true;clearTimeout(timer);resolve(x);}},()=>{if(!done){done=true;clearTimeout(timer);resolve(null);}});});
function signal(c,sig){if(c.pid>1&&c.exitCode===null&&c.signalCode===null)try{process.kill(-c.pid,sig);}catch{}}
function groupGone(pid){try{process.kill(-pid,0);return false;}catch(e){return e?.code==='ESRCH';}}
async function stopped(pid){const end=Date.now()+1500;while(Date.now()<end){if(groupGone(pid))return true;await new Promise(r=>setTimeout(r,30));}return groupGone(pid);}
async function stop(c,closed){signal(c,'SIGTERM');let r=await within(closed,1000);if(!r){signal(c,'SIGKILL');r=await within(closed,1500);}return r;}
export async function runSupervised(envelope,expectedPlanSha256,{abortSignal=null}={}){
 let p;try{if(!cleanEnvironment())return refused('input_refused');p=validateEnvelope(envelope,expectedPlanSha256).plan;}catch(e){return refused(e?.safeCode);}
 if(abortSignal!==null&&(!abortSignal||typeof abortSignal.addEventListener!=='function'||typeof abortSignal.removeEventListener!=='function'))return refused('input_refused');
 if(abortSignal?.aborted)return unknown('observation_interrupted');
 const c=spawn(process.execPath,[fileURLToPath(new URL('./worker.mjs',import.meta.url)),expectedPlanSha256],{detached:true,stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
 let failure=false;const closed=new Promise(resolve=>{c.once('error',()=>{failure=true;});c.once('close',(code,sig)=>resolve({code,sig}));});
 let chunks=[],size=0,overflow=false,timed=false,aborted=false,timer,resolveAbort;
 const abortedPromise=new Promise(resolve=>{resolveAbort=resolve;}),onAbort=()=>{aborted=true;signal(c,'SIGTERM');resolveAbort({kind:'abort'});};
 try{
  c.stdout.on('data',b=>{size+=b.length;if(size>8192){overflow=true;b.fill(0);signal(c,'SIGTERM');}else chunks.push(b);});c.stdin.on('error',()=>{});
  abortSignal?.addEventListener('abort',onAbort,{once:true});if(abortSignal?.aborted)onAbort();
  timer=setTimeout(()=>{timed=true;signal(c,'SIGTERM');},p.deadlineMs);c.stdin.end(JSON.stringify(envelope));
  const event=await Promise.race([closed.then(result=>({kind:'closed',result})),abortedPromise,new Promise(resolve=>{const t=setTimeout(()=>resolve({kind:'deadline'}),p.deadlineMs+1200);closed.finally(()=>clearTimeout(t));})]);
  let result=event.kind==='closed'?event.result:await stop(c,closed);
  if(!result||!c.pid||!await stopped(c.pid))return unknown('worker_stop_unconfirmed');
  if(aborted)return unknown('observation_interrupted');if(timed||event.kind==='deadline')return unknown('observation_deadline');
  if(failure||result.sig||overflow||size<1)return unknown('observation_unconfirmed');
  let body;try{body=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{return unknown('observation_unconfirmed');}
  if(result.code===0){try{return validatePublicObservation(body);}catch{return unknown('observation_unconfirmed');}}
  if(result.code!==1||!body||Object.keys(body).sort().join(',')!=='reason,status,write_authorized'||body.status!=='refused'||body.write_authorized!==false||!safe.has(body.reason))return unknown('observation_unconfirmed');
  return refused(body.reason);
 }catch{return unknown('observation_unconfirmed');}
 finally{if(timer)clearTimeout(timer);abortSignal?.removeEventListener('abort',onAbort);if(c.exitCode===null&&c.signalCode===null)await stop(c,closed);for(const b of chunks)b.fill(0);chunks=[];}
}
async function writeResult(result){return new Promise(resolve=>{const onError=()=>resolve(false);process.stdout.once('error',onError);process.stdout.write(JSON.stringify(result)+'\n',e=>{process.stdout.removeListener('error',onError);resolve(!e);});});}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const ctl=new AbortController(),onSignal=()=>{ctl.abort();process.stdin.destroy();};process.on('SIGTERM',onSignal);process.on('SIGINT',onSignal);
 let result;try{if(process.argv.length!==3||!cleanEnvironment())throw Error();const input=await readPrivateInput();result=await runSupervised(input,process.argv[2],{abortSignal:ctl.signal});}
 catch{result=ctl.signal.aborted?unknown('observation_interrupted'):refused('input_refused');}
 const ok=await writeResult(result);process.exitCode=ok&&result.status==='aggregate_observation'?0:1;
 process.removeListener('SIGTERM',onSignal);process.removeListener('SIGINT',onSignal);
}
