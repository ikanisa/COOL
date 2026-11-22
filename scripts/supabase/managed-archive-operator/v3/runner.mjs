// Owned-fixture runner. It never dispatches a managed operation.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {verifyV3} from './source.mjs';
import {beginCapture,bindOwnedActor} from './journal.mjs';
import {reconcileCaptureClosure} from './identity.mjs';
const fail=code=>{throw Object.assign(Error(code),{captureCode:code});};
const within=(p,ms)=>new Promise(resolve=>{const t=setTimeout(()=>resolve(null),ms);p.then(x=>{clearTimeout(t);resolve(x);},()=>{clearTimeout(t);resolve(null);});});
export async function managedCaptureV3(_options){fail('MANAGED_CAPTURE_UNQUALIFIED');}
export async function reconcileSyntheticCapture(options){
 await verifyV3(options?.manifestSha256);return reconcileCaptureClosure({...options,mode:'synthetic'});
}
export async function startSyntheticCapture({root,manifestSha256,fixture,holdMs=0}={}){
 await verifyV3(manifestSha256);const job=await beginCapture(root,manifestSha256);
 const child=spawn(process.execPath,[fileURLToPath(new URL('./worker.mjs',import.meta.url)),manifestSha256,'synthetic'],
  {detached:true,stdio:['pipe','pipe','ignore','ipc'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
 let body='',overflow=false;child.stdout.on('data',b=>{if(Buffer.byteLength(body)+b.length>18*1024*1024){overflow=true;child.kill('SIGTERM');}else body+=b.toString('utf8');});
 child.stdin.on('error',()=>{});const closed=new Promise(resolve=>child.once('close',(code,signal)=>resolve({code,signal})));
 let confirm;try{confirm=await bindOwnedActor(job,child);}catch{try{process.kill(-child.pid,'SIGTERM');}catch{}return {job,child,done:Promise.resolve({status:'unknown_do_not_retry'})};}
 child.stdin.end(JSON.stringify({mode:'synthetic',job,fixture,holdMs}));
 const done=(async()=>{let exit=await within(closed,12000);if(!exit){try{process.kill(-child.pid,'SIGTERM');}catch{}exit=await within(closed,2500);}
  if(!exit)return {status:'unknown_do_not_retry'};const actorClosed=await confirm();if(!actorClosed||overflow)return {status:'unknown_do_not_retry'};
  let r;try{r=JSON.parse(body);}catch{r=null;}return {status:'actor_closed_server_reconciliation_required',workerStatus:r?.status??null,exitCode:exit.code};})();
 return {job,child,done};
}
