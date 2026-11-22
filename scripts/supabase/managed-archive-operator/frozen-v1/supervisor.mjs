// Private pipe entrypoint. A missing response or unconfirmed stop is unknown.
import {spawn} from 'node:child_process';
import {fstatSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {readPrivateInput} from './input.mjs';
import {MANAGED_REVIEWED_APPLY_PLAN_SHA256} from './archive-core.mjs';
import {cleanEnvironment} from '../current-pg-transfer/principal-mapping-operator/protocol.mjs';
const exact=(o,k)=>o&&typeof o==='object'&&!Array.isArray(o)&&Object.getPrototypeOf(o)===Object.prototype&&Object.keys(o).sort().join(',')===[...k].sort().join(',');
const refuse=code=>({status:'refused',code,writeAuthorized:false});
const unknown=status=>({status,writeAuthorized:false});
const within=(p,ms)=>new Promise(resolve=>{const t=setTimeout(()=>resolve(null),ms);p.then(x=>{clearTimeout(t);resolve(x);},()=>{clearTimeout(t);resolve(null);});});
const signal=(c,s)=>{if(c.pid>1&&c.exitCode===null&&c.signalCode===null)try{process.kill(-c.pid,s);}catch{}};
const gone=pid=>{try{process.kill(-pid,0);return false;}catch(e){return e?.code==='ESRCH';}};
async function stopped(pid){const end=Date.now()+1500;while(Date.now()<end){if(gone(pid))return true;await new Promise(r=>setTimeout(r,30));}return gone(pid);}
async function stop(c,closed){signal(c,'SIGTERM');let x=await within(closed,1000);if(!x){signal(c,'SIGKILL');x=await within(closed,1500);}return x;}
function valid(v){
 const keys=v?.action==='capture'?['format','action','password','timeoutMs']:['format','action','password','timeoutMs','journalRoot','plan'];
 return exact(v,keys)&&v.format==='collect.managed-archive-operator.v1'&&['capture','apply','reconcile'].includes(v.action)&&
  typeof v.password==='string'&&Buffer.byteLength(v.password)>0&&Buffer.byteLength(v.password)<=1024&&!/[\u0000-\u001f\u007f]/u.test(v.password)&&
  Number.isSafeInteger(v.timeoutMs)&&v.timeoutMs>=1000&&v.timeoutMs<=120000;
}
async function supervise(v,ctl){
 if(v.action!=='capture'&&MANAGED_REVIEWED_APPLY_PLAN_SHA256===null)return refuse('MANAGED_APPLY_UNQUALIFIED');
 const c=spawn(process.execPath,[fileURLToPath(new URL('./worker.mjs',import.meta.url))],{detached:true,stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
 let failed=false;const closed=new Promise(resolve=>{c.once('error',()=>{failed=true;});c.once('close',(code,sig)=>resolve({code,sig}));});
 let chunks=[],size=0,overflow=false,aborted=false,timed=false,timer,abortResolve;
 const abortPromise=new Promise(resolve=>{abortResolve=resolve;}),onAbort=()=>{aborted=true;signal(c,'SIGTERM');abortResolve({kind:'abort'});};
 try{
  c.stdout.on('data',b=>{size+=b.length;if(size>18*1024*1024){overflow=true;b.fill(0);signal(c,'SIGTERM');}else chunks.push(b);});c.stdin.on('error',()=>{});
  ctl.signal.addEventListener('abort',onAbort,{once:true});if(ctl.signal.aborted)onAbort();
  timer=setTimeout(()=>{timed=true;signal(c,'SIGTERM');},v.timeoutMs+12000);c.stdin.end(JSON.stringify(v));
  const event=await Promise.race([closed.then(x=>({kind:'closed',value:x})),abortPromise,new Promise(resolve=>{const t=setTimeout(()=>resolve({kind:'deadline'}),v.timeoutMs+13200);closed.finally(()=>clearTimeout(t));})]);
  const result=event.kind==='closed'?event.value:await stop(c,closed);
  if(!result||!c.pid||!await stopped(c.pid))return unknown('worker_stop_unconfirmed');
  if(aborted)return unknown('observation_interrupted');if(timed||event.kind==='deadline')return unknown('observation_deadline');
  if(failed||result.sig||overflow||size<1)return unknown('observation_unconfirmed');
  let body;try{body=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{return unknown('observation_unconfirmed');}
  if(result.code===0&&v.action==='capture'&&exact(body,['status','sha256','preimage','productionAuthorized'])&&body.status==='preimage_captured'&&
   body.productionAuthorized===false&&/^[a-f0-9]{64}$/.test(body.sha256)&&createHash('sha256').update(JSON.stringify(body.preimage)).digest('hex')===body.sha256)return body;
  if(result.code===1&&exact(body,['status','code','writeAuthorized'])&&body.status==='refused'&&body.writeAuthorized===false&&/^[A-Z_]{1,64}$/.test(body.code))return body;
  return unknown('observation_unconfirmed');
 }catch{return unknown('observation_unconfirmed');}
 finally{if(timer)clearTimeout(timer);ctl.signal.removeEventListener('abort',onAbort);if(c.exitCode===null&&c.signalCode===null)await stop(c,closed);for(const b of chunks)b.fill(0);chunks=[];}
}
const ctl=new AbortController(),onSignal=()=>{ctl.abort();process.stdin.destroy();};process.on('SIGTERM',onSignal);process.on('SIGINT',onSignal);
let result;
try{
 const out=fstatSync(1);if(process.argv.length!==2||!cleanEnvironment()||!(out.isFIFO()||out.isSocket()))throw Error();
 const request=await readPrivateInput();if(!valid(request))throw Error();result=await supervise(request,ctl);
}catch{result=ctl.signal.aborted?unknown('observation_interrupted'):refuse('PRIVATE_INPUT_REFUSED');}
const wrote=await within(new Promise(resolve=>{process.stdout.once('error',()=>resolve(false));process.stdout.write(JSON.stringify(result)+'\n',e=>resolve(!e));}),5000);
if(!wrote)process.stdout.destroy();
if(!wrote||result.status!=='preimage_captured')process.exitCode=1;
process.removeListener('SIGTERM',onSignal);process.removeListener('SIGINT',onSignal);
