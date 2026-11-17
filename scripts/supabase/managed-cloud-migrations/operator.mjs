// Private stdin only. No credential is accepted in arguments, environment or files.
import {OperatorError,parseCanonicalInput,runRequest,FORMAT} from './operator-core.mjs';
import {fstatSync} from 'node:fs';

async function input(){
 let source;try{source=fstatSync(0);}catch{throw new OperatorError('invalid_request');}
 if(process.stdin.isTTY||(!source.isFIFO()&&!source.isSocket()))throw new OperatorError('invalid_request');
 const chunks=[];let size=0,timer;
 try{return await new Promise((resolve,reject)=>{
  let done=false;
  function finish(err){if(done)return;done=true;clearTimeout(timer);process.stdin.removeListener('data',data);process.stdin.removeListener('end',end);
   if(err){for(const c of chunks)c.fill(0);process.stdin.destroy();reject(err);return;}
   const buffer=Buffer.concat(chunks,size);for(const c of chunks)c.fill(0);
   try{resolve(new TextDecoder('utf-8',{fatal:true}).decode(buffer));}catch{reject(new OperatorError('invalid_request'));}finally{buffer.fill(0);}}
  function data(c){size+=c.length;if(size>16384){c.fill(0);finish(new OperatorError('invalid_request'));}else chunks.push(c);}
  function end(){finish();}
  timer=setTimeout(()=>finish(new OperatorError('invalid_request')),10000);
  process.stdin.once('error',()=>finish(new OperatorError('invalid_request')));process.stdin.on('data',data);process.stdin.on('end',end);
 });}finally{clearTimeout(timer);}
}
// A successful write callback only means that the local stream accepted the
// bytes. A supervisor must still reconcile if it did not receive valid output.
process.stdout.on('error',()=>{process.exitCode=1;});
let result;
try{
 if(process.argv.length!==3)throw new OperatorError('invalid_request');
 const raw=await input(),request=parseCanonicalInput(raw);result=await runRequest(request,{journalRoot:process.argv[2]});
}catch(e){
 const allowed=new Set(['invalid_request','unclean_environment','journal_unavailable','journal_mismatch','apply_already_attempted','connection_unavailable','prior_backend_still_present']);
 const unconfirmed=e instanceof OperatorError&&e.code==='journal_outcome_unconfirmed'&&
  /^[0-9]{14}$/.test(e.version??'')&&Number.isSafeInteger(e.backendPid)&&e.backendPid>0;
 const code=e instanceof OperatorError&&allowed.has(e.code)?e.code:'operator_unconfirmed';
 result=unconfirmed?{format:FORMAT,status:'unconfirmed',code:'journal_outcome_unconfirmed',version:e.version,backendPid:e.backendPid}:
  {format:FORMAT,status:'refused',code};
}
if(['refused','unconfirmed'].includes(result.status))process.exitCode=1;
// Keep delivery outside the operation's try/catch: a failed response after a
// commit must never be transformed into a misleading `refused` response.
try{await new Promise((resolve,reject)=>process.stdout.write(JSON.stringify(result)+'\n',error=>error?reject(error):resolve()));}
catch{process.exitCode=1;}
