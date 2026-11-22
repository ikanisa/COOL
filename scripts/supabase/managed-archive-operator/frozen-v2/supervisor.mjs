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
async function verifyBeforeInput(expected,ctl){
 if(!/^[a-f0-9]{64}$/.test(expected??''))throw Object.assign(Error(),{safeCode:'SOURCE_MANIFEST_REFUSED'});
 const c=spawn(process.execPath,[fileURLToPath(new URL('./verify-worker.mjs',import.meta.url)),expected],{detached:true,stdio:['ignore','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
 let bytes=0,chunks=[],bad=false;const closed=new Promise(resolve=>{c.once('error',()=>{bad=true;});c.once('close',(code,sig)=>resolve({code,sig}));});
 c.stdout.on('data',b=>{bytes+=b.length;if(bytes>4096){bad=true;b.fill(0);signal(c,'SIGTERM');}else chunks.push(b);});
 let abort;const interrupted=new Promise(resolve=>{abort=()=>resolve(null);ctl.signal.addEventListener('abort',abort,{once:true});if(ctl.signal.aborted)abort();});
 try{
  let r=await within(Promise.race([closed,interrupted]),20000);const timed=!r;if(!r)r=await stop(c,closed);
  if(timed||!r||!c.pid||!await stopped(c.pid)||ctl.signal.aborted||bad||r.code!==0||r.sig)throw Error();
  const v=JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if(!exact(v,['status','manifestSha256'])||v.status!=='source_verified'||v.manifestSha256!==expected)throw Error();
 }catch{throw Object.assign(Error(),{safeCode:'SOURCE_MANIFEST_REFUSED'});}
 finally{ctl.signal.removeEventListener('abort',abort);if(c.exitCode===null&&c.signalCode===null)await stop(c,closed);for(const b of chunks)b.fill(0);chunks=[];}
}
function valid(v){
 const keys=v?.action==='capture'?['format','action','password','timeoutMs']:['format','action','password','timeoutMs','journalRoot','plan'];
 return exact(v,keys)&&v.format==='collect.managed-archive-operator.v1'&&['capture','apply','reconcile'].includes(v.action)&&
  typeof v.password==='string'&&Buffer.byteLength(v.password)>0&&Buffer.byteLength(v.password)<=1024&&!/[\u0000-\u001f\u007f]/u.test(v.password)&&
  Number.isSafeInteger(v.timeoutMs)&&v.timeoutMs>=1000&&v.timeoutMs<=120000;
}
async function supervise(v,ctl){
 if(v.action!=='capture'&&MANAGED_REVIEWED_APPLY_PLAN_SHA256===null)return refuse('MANAGED_APPLY_UNQUALIFIED');
 const c=spawn(process.execPath,[fileURLToPath(new URL('./worker.mjs',import.meta.url)),process.argv[2]],{detached:true,stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
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
  if(result.code===0&&v.action==='capture'&&exact(body,['status','sha256','preimage','productionAuthorized','implementationManifestSha256'])&&body.status==='preimage_captured'&&
   body.implementationManifestSha256===process.argv[2]&&body.productionAuthorized===false&&/^[a-f0-9]{64}$/.test(body.sha256)&&createHash('sha256').update(JSON.stringify(body.preimage)).digest('hex')===body.sha256)return body;
  if(result.code===1&&exact(body,['status','code','writeAuthorized'])&&body.status==='refused'&&body.writeAuthorized===false&&/^[A-Z_]{1,64}$/.test(body.code))return body;
  return unknown('observation_unconfirmed');
 }catch{return unknown('observation_unconfirmed');}
 finally{if(timer)clearTimeout(timer);ctl.signal.removeEventListener('abort',onAbort);if(c.exitCode===null&&c.signalCode===null)await stop(c,closed);for(const b of chunks)b.fill(0);chunks=[];}
}
const ctl=new AbortController(),onSignal=()=>{ctl.abort();process.stdin.destroy();};process.on('SIGTERM',onSignal);process.on('SIGINT',onSignal);
let result;
try{
 const out=fstatSync(1);if(process.argv.length!==3||!cleanEnvironment()||!(out.isFIFO()||out.isSocket()))throw Error();
 await verifyBeforeInput(process.argv[2],ctl);
 const request=await readPrivateInput();if(!valid(request))throw Error();result=await supervise(request,ctl);
}catch(e){result=ctl.signal.aborted?unknown('observation_interrupted'):refuse(e?.safeCode==='SOURCE_MANIFEST_REFUSED'?'SOURCE_MANIFEST_REFUSED':'PRIVATE_INPUT_REFUSED');}
const wrote=await within(new Promise(resolve=>{process.stdout.once('error',()=>resolve(false));process.stdout.write(JSON.stringify(result)+'\n',e=>resolve(!e));}),5000);
if(!wrote)process.stdout.destroy();
if(!wrote||result.status!=='preimage_captured')process.exitCode=1;
process.removeListener('SIGTERM',onSignal);process.removeListener('SIGINT',onSignal);
