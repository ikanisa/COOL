// One read-only, source-pinned Collect API probe. No credentials, redirects,
// retry, provider payload or arbitrary destination are supported by the CLI.
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';

const TARGET='https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-api/health';
const SHA=/^[a-f0-9]{64}$/;
const FIELDS=['checked_at','database','release','service'];
class ProbeFault extends Error{constructor(code){super(code);this.code=code;}}

export async function probePlatformHealth({expectedSourceId,fetchImpl=fetch,now=()=>Date.now(),timeoutMs=5000}){
 if(typeof expectedSourceId!=='string'||!SHA.test(expectedSourceId))throw new Error('A reviewed source SHA-256 is required.');
 if(!Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>5000)throw new Error('Probe deadline must be between1 and5000 milliseconds.');
 const started=performance.now(),controller=new AbortController();let timer,status=null,observedSource=null;
 const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>{controller.abort();reject(new ProbeFault('timeout'));},timeoutMs);});
 try{
  const read=async()=>{
   const response=await fetchImpl(TARGET,{method:'GET',redirect:'manual',signal:controller.signal,
    headers:{Accept:'application/json','Cache-Control':'no-cache'}});
   status=Number.isInteger(response.status)&&response.status>=100&&response.status<=599?response.status:null;
   if(status!==200)throw new ProbeFault('unavailable');
   if(!/^application\/json(?:\s*;|$)/i.test(response.headers.get('Content-Type')??''))throw new ProbeFault('invalid_response');
   const length=response.headers.get('Content-Length');
   if(length&&(!/^\d+$/.test(length)||Number(length)>2048))throw new ProbeFault('invalid_response');
   if(!response.body?.getReader)throw new ProbeFault('invalid_response');
   const reader=response.body.getReader(),chunks=[];let count=0;
   try{
    while(true){const {value,done}=await reader.read();if(done)break;count+=value.byteLength;
     if(count>2048){await reader.cancel();throw new ProbeFault('invalid_response');}chunks.push(value);}
   }finally{reader.releaseLock();}
   const bytes=new Uint8Array(count);let offset=0;
   for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
   let value;try{
    const text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
    const keys=[...text.matchAll(/"((?:\\.|[^"\\])*)"\s*:/g)].map(match=>match[1]);
    if(keys.length!==4||new Set(keys).size!==4||keys.some(key=>!FIELDS.includes(key)))throw new Error();
    value=JSON.parse(text);
   }catch{throw new ProbeFault('invalid_response');}
   if(!value||typeof value!=='object'||Array.isArray(value)||JSON.stringify(Object.keys(value).sort())!==JSON.stringify(FIELDS)
    ||value.service!=='collect-platform-api'||value.database!=='available'||typeof value.release!=='string'||!SHA.test(value.release)
    ||typeof value.checked_at!=='string')throw new ProbeFault('invalid_response');
   const checked=Date.parse(value.checked_at),current=now();
   if(!Number.isFinite(checked)||!Number.isFinite(current)||new Date(checked).toISOString()!==value.checked_at
    ||current-checked>60000||checked-current>5000)throw new ProbeFault('invalid_response');
   observedSource=value.release;
   if(value.release!==expectedSourceId)throw new ProbeFault('source_mismatch');
   return 'available';
  };
  const outcome=await Promise.race([read(),deadline]);return result(outcome);
 }catch(error){return result(error instanceof ProbeFault?error.code:controller.signal.aborted?'timeout':'network_failure');}
 finally{clearTimeout(timer);controller.abort();}
 function result(outcome){return {collect_health_probe:1,service:'collect_platform_api',outcome,
  expected_source_id:expectedSourceId,observed_source_id:observedSource,http_status:status,
  elapsed_ms:Math.min(5000,Math.max(0,Math.round(performance.now()-started))),
  source_bound_health_available:outcome==='available',SLO_or_alert_delivery_accepted:false};}
}

export async function main(args){
 if(args.length!==2||args[0]!=='--expected-source'||!SHA.test(args[1]))throw new Error('Use --expected-source with the reviewed64-character source SHA-256.');
 const result=await probePlatformHealth({expectedSourceId:args[1]});
 console.log(JSON.stringify(result));return result.source_bound_health_available?0:1;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 main(process.argv.slice(2)).then(code=>{process.exitCode=code;}).catch(()=>{console.error('Invalid Collect health probe arguments.');process.exitCode=2;});
}
