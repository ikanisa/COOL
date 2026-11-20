// Private inputs run in a separately bounded worker; password bytes never enter argv/env/logs.
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {types} from 'node:util';
export class InputError extends Error{constructor(code){super(code);this.name='InputError';this.code=code;}}
const fail=c=>{throw new InputError(c);};
function option(o,k){const d=Object.getOwnPropertyDescriptor(o,k);if(!d||!Object.hasOwn(d,'value'))fail('invalid_input');return d.value;}
async function within(p,ms){let timer;try{return await Promise.race([p,new Promise(r=>{timer=setTimeout(()=>r(null),ms);})]);}finally{clearTimeout(timer);}}
function outcome(child){return new Promise(resolve=>{let error=false;child.once('error',()=>{error=true;});child.once('close',(code,signal)=>resolve({code,signal,error}));});}
function signalRunning(child,sig){if(child.pid>0&&child.exitCode===null&&child.signalCode===null)try{child.kill(sig);}catch{}}
async function stop(child,closed){signalRunning(child,'SIGTERM');let x=await within(closed,750);if(!x){signalRunning(child,'SIGKILL');x=await within(closed,750);}return x;}
async function readInput(o,kind){
 if(!o||typeof o!=='object'||types.isProxy(o))fail('invalid_input');const mode=option(o,'mode');if(!['managed','synthetic'].includes(mode))fail('invalid_input');
 const path=option(o,'path'),signal=option(o,'signal'),testHang=option(o,'testHang');
 if(typeof path!=='string'||!path.startsWith('/')||path.length>4096||typeof testHang!=='boolean'||mode==='managed'&&testHang)fail('invalid_input');
 if(signal?.aborted)fail('aborted');
 const child=spawn(process.execPath,[fileURLToPath(new URL('./private-input-worker.mjs',import.meta.url))],{stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}}),closed=outcome(child);
 let chunks=[],count=0,tooLarge=false,aborted=false,timed=false,finished=false,timer,listenerInstalled=false;
 try{
  child.stdout.on('data',b=>{count+=b.length;if(count>4096){tooLarge=true;b.fill(0);signalRunning(child,'SIGTERM');}else chunks.push(b);});
  child.stdin.on('error',()=>{});
  const stopNow=()=>{aborted=true;signalRunning(child,'SIGTERM');};
  try{
   if(signal){signal.addEventListener('abort',stopNow,{once:true});listenerInstalled=true;}
   timer=setTimeout(()=>{timed=true;signalRunning(child,'SIGTERM');},1000);
   child.stdin.end(JSON.stringify({mode,path,testHang,kind}));
   let result=await within(closed,2000);if(!result)result=await stop(child,closed);
   if(!result){finished=true;fail('input_stop_unconfirmed');}finished=true;
   if(aborted)fail('aborted');if(timed)fail('input_timed_out');
   if(result.error||result.code!==0||result.signal||tooLarge||count<1||kind==='key'&&count!==32)fail('private_input_refused');
   const secret=Buffer.concat(chunks);return secret;
  }finally{if(timer!==undefined)clearTimeout(timer);if(listenerInstalled)signal.removeEventListener('abort',stopNow);}
 }catch(e){if(e instanceof InputError)throw e;fail('private_input_failed');}
 finally{try{if(!finished&&!await stop(child,closed))fail('input_stop_unconfirmed');}finally{for(const b of chunks)b.fill(0);chunks=[];}}
}
export async function readPrivatePassword(o){return readInput(o,'password');}
export async function readPrivateKey(o){return readInput(o,'key');}
