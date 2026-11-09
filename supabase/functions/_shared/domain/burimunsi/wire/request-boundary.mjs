import {ContractViolation} from './runtime.mjs';
export const MAX_NATIVE_REQUEST_BYTES=8192;
export const MAX_NATIVE_READ_MS=15000;
const fail=code=>{throw new ContractViolation(code);};
export function requireActiveNativeRequest(request){if(request.signal?.aborted)fail('CONTRACT_REQUEST_ABORTED');}
/** Cleanup cannot delay or replace a protocol outcome, even if cancel never settles. */
function cancelQuietly(body){try{void body?.cancel().catch(()=>{});}catch{}}
export function discardNativeBody(request){cancelQuietly(request.body);}
export function nativeRequestErrorStatus(error){
 return error.code==='CONTRACT_REQUEST_SIZE'?413:
  ['CONTRACT_REQUEST_ABORTED','CONTRACT_REQUEST_TIMEOUT'].includes(error.code)?408:400;
}
/** Absolute deadline, fixed memory bound, fatal decoding left to the wire parser.
 * The timeout is a trusted server option, never a client header/query value. */
export async function readNativeBody(request,{timeoutMs=MAX_NATIVE_READ_MS}={}){
 if(!Number.isSafeInteger(timeoutMs)||timeoutMs<1||timeoutMs>MAX_NATIVE_READ_MS)fail('CONTRACT_CONTEXT');
 requireActiveNativeRequest(request);
 const declared=request.headers.get('content-length');
 if(declared!==null){
  if(!/^(0|[1-9][0-9]{0,7})(?![\s\S])/.test(declared))fail('CONTRACT_CONTENT_LENGTH');
  if(Number(declared)>MAX_NATIVE_REQUEST_BYTES)fail('CONTRACT_REQUEST_SIZE');
 }
 if(!request.body)fail('CONTRACT_JSON');
 const reader=request.body.getReader();
 const bytes=new Uint8Array(MAX_NATIVE_REQUEST_BYTES);let size=0,reads=0,completed=false,stopped=null,pendingReject=null;
 const deadline=performance.now()+timeoutMs;
 const stop=code=>{if(stopped)return;stopped=new ContractViolation(code);pendingReject?.(stopped);};
 const onAbort=()=>stop('CONTRACT_REQUEST_ABORTED');
 const timer=setTimeout(()=>stop('CONTRACT_REQUEST_TIMEOUT'),timeoutMs);
 request.signal?.addEventListener('abort',onAbort,{once:true});
 if(request.signal?.aborted)onAbort();
 const check=()=>{if(performance.now()>=deadline)stop('CONTRACT_REQUEST_TIMEOUT');if(stopped)throw stopped;};
 const read=()=>new Promise((resolve,reject)=>{
  pendingReject=reject;
  reader.read().then(value=>{pendingReject=null;stopped?reject(stopped):resolve(value);},()=>{
   pendingReject=null;reject(stopped??new ContractViolation('CONTRACT_REQUEST_STREAM'));
  });
 });
 try{
  for(;;){
   check();if(++reads>16384)fail('CONTRACT_COMPLEXITY');
   const part=await read();check();
   if(part.done){completed=true;break;}
   if(!(part.value instanceof Uint8Array))fail('CONTRACT_REQUEST_STREAM');
   if(size+part.value.byteLength>bytes.byteLength)fail('CONTRACT_REQUEST_SIZE');
   bytes.set(part.value,size);size+=part.value.byteLength;
  }
  if(declared!==null&&Number(declared)!==size)fail('CONTRACT_CONTENT_LENGTH');
  return bytes.slice(0,size);
 }finally{
  clearTimeout(timer);request.signal?.removeEventListener('abort',onAbort);pendingReject=null;
  if(!completed)cancelQuietly(reader);
  try{reader.releaseLock();}catch{}
 }
}
