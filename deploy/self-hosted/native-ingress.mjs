/** Retained-local frontdoor. No service is started merely by importing this
 * module. Production listens ONLY on a new, owner-protected Unix socket for the
 * approved named cloudflared connector; it never publishes a TCP listener. */
import http from 'node:http';
import {isIP} from 'node:net';
import {lstat,realpath,chmod,unlink,open} from 'node:fs/promises';
import {constants} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {verifyDeploymentProfile} from '../../supabase/functions/_shared/deployment-profile.js';
import {createNativeIngressSigner,NATIVE_INGRESS_HEADER,NativeIngressError} from '../../supabase/functions/_shared/native-ingress.js';
import {nativeRequestBodyLimit} from '../../supabase/functions/_shared/domain/burimunsi/wire/request-boundary.mjs';
import {createAuthPhoneProxy} from './auth-phone-proxy.mjs';
import {validRawTarget} from './web-server.mjs';

const UPSTREAM='http://127.0.0.1:55101',MAX_BYTES=16*1024*1024;
const safeHeaders={'Cache-Control':'private, no-store, no-transform','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer'};
const hop=new Set(['host','connection','keep-alive','proxy-authenticate','proxy-authorization','te','trailer','transfer-encoding','upgrade','content-length','content-encoding']);
const functions=new Set(['collect-api','admin-api','collect-sms','send-sms-hook','collect-jobs','collect-email-jobs']);
export const INGRESS_ENV_FIELDS=Object.freeze(['APP_ENVIRONMENT','AUTH_PHONE_DELIVERY_MODE','AUTH_WHATSAPP_ENABLED','BURIMUNSI_NATIVE_ENABLED',
 'COLLECT_DEPLOYMENT_PROFILE','COLLECT_DEPLOYMENT_PROFILE_SHA256','COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON','COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256',
 'COLLECT_NATIVE_INGRESS_KEY_BASE64','COLLECT_NATIVE_INGRESS_KEY_ID','COLLECT_NATIVE_INGRESS_SOCKET','SUPABASE_INTERNAL_URL','SUPABASE_URL'].sort());
const NATIVE_PREFIX='/functions/v1/collect-api',NATIVE_ROOT=NATIVE_PREFIX+'/v1/burimunsi';
const nativePath=path=>path===NATIVE_ROOT||path.startsWith(NATIVE_ROOT+'/');
const nativeLimit=(method,rawTarget)=>nativeRequestBodyLimit(method,rawTarget.slice(NATIVE_PREFIX.length));
const fail=(status,code)=>Response.json({code},{status,headers:safeHeaders});
function targetAllowed(path){
 return /^\/(?:rest|storage|realtime)\/v1(?:\/|$)/.test(path)||path==='/graphql/v1'||
  path.startsWith('/functions/v1/')&&functions.has(path.split('/')[3]);
}
function cleanHeaders(source){
 const result=new Headers();
 for(const [name,value]of source)if(!hop.has(name)&&!name.startsWith('cf-')&&!name.startsWith('x-forwarded-')&&
  !name.startsWith('x-collect-native-ingress')&&!['forwarded','x-real-ip','x-collect-actor','x-collect-original-path','x-original-url','x-rewrite-url'].includes(name))result.set(name,value);
 return result;
}
export function canonicalClientAddress(value){
 if(typeof value!=='string'||value.length>64||/[\s%,\[\]]/.test(value))throw Error('native_ingress_network_denied');
 const version=isIP(value);if(!version)throw Error('native_ingress_network_denied');
 if(version===4)return value;
 const normalized=new URL('http://['+value+']/').hostname.slice(1,-1);
 // One identity for IPv4 and its IPv4-mapped IPv6 spelling.
 const mapped=/^::ffff:([a-f0-9]{1,4}):([a-f0-9]{1,4})$/.exec(normalized);
 if(mapped){const a=parseInt(mapped[1],16),b=parseInt(mapped[2],16);return [a>>8,a&255,b>>8,b&255].join('.');}
 if(normalized==='2a06:98c0:3600::103')throw Error('native_ingress_network_denied');
 return normalized;
}
async function bounded(stream,limit,signal){
 if(!stream)return new Uint8Array();const reader=stream.getReader();let bytes=new Uint8Array(),size=0,complete=false,reads=0;
 try{
  for(;;){
   if(signal.aborted)throw Error('deadline');if(++reads>32768)throw Error('stream_complexity');
   const part=await new Promise((resolve,reject)=>{
    const abort=()=>{signal.removeEventListener('abort',abort);reject(Error('deadline'));};
    signal.addEventListener('abort',abort,{once:true});
    if(signal.aborted){abort();return;}
    reader.read().then(value=>{signal.removeEventListener('abort',abort);resolve(value);},()=>{signal.removeEventListener('abort',abort);reject(Error('stream'));});
   });
   if(part.done){complete=true;break;}if(!(part.value instanceof Uint8Array)||size+part.value.length>limit)throw Error('body_limit');
   if(size+part.value.length>bytes.length){const grown=new Uint8Array(Math.min(limit,Math.max(size+part.value.length,bytes.length?bytes.length*2:1024)));grown.set(bytes.subarray(0,size));bytes=grown;}
   bytes.set(part.value,size);size+=part.value.length;
  }
  return bytes.subarray(0,size);
 }finally{if(!complete)try{void reader.cancel().catch(()=>{});}catch{}try{reader.releaseLock();}catch{}}
}
export async function createNativeIngressApplication(env,{fetchImpl=fetch,clock=()=>Date.now()}={}){
 const profile=await verifyDeploymentProfile(env);
 if(env.COLLECT_DEPLOYMENT_PROFILE===undefined||profile.mode!=='self_hosted'||env.SUPABASE_URL!==profile.supabase_origin||
  env.APP_ENVIRONMENT!==profile.environment||env.SUPABASE_INTERNAL_URL!==UPSTREAM||typeof fetchImpl!=='function')throw Error('native_ingress_unconfigured');
 const auth=createAuthPhoneProxy(env,{fetchImpl,retainedLocal:true});let signer;
 return async(request,metadata={})=>{
  try{
   const rawTarget=metadata.rawTarget,url=new URL(request.url),native=nativePath(url.pathname);
   if(url.origin!==profile.supabase_origin||request.headers.has('host')&&request.headers.get('host')!==url.host)return fail(421,'origin_unavailable');
   if(!validRawTarget(rawTarget)||/[\\\x00-\x20\x7f#]/.test(rawTarget)||url.pathname+url.search!==rawTarget)return fail(400,'invalid_request');
   if(!['GET','HEAD','POST','PUT','PATCH','DELETE','OPTIONS'].includes(request.method))return fail(405,'method_not_allowed');
   if(request.headers.has('upgrade'))return fail(426,'upgrade_unavailable');
   // The named Tunnel is the only socket client. Cloudflare adds CF-Worker
   // after Worker fetch(), so reject even an empty marker before selecting IP,
   // cleaning headers, consuming a body or issuing an attestation. No WAF slot
   // is required for this origin-side check.
   if(native&&(request.headers.has('cf-worker')||metadata.workerSubrequest))return fail(403,'native_ingress_network_denied');
   const headers=cleanHeaders(request.headers),clean=new Request(request,{headers});
   if(url.pathname.startsWith('/auth/v1/'))return auth(clean);
   if(!targetAllowed(url.pathname))return fail(404,'not_found');
   const limit=native?nativeLimit(request.method,rawTarget):MAX_BYTES,declared=request.headers.get('content-length');
   if(declared!==null&&(!/^(0|[1-9][0-9]*)$/.test(declared)||Number(declared)>limit))return fail(413,'request_too_large');
   const signal=AbortSignal.any([request.signal,AbortSignal.timeout(30000)]);
   let outgoing;
   if(native){
    if(env.BURIMUNSI_NATIVE_ENABLED!=='true')return fail(503,'native_service_unconfigured');
    let address;try{address=canonicalClientAddress(metadata.clientAddress);}catch{return fail(403,'native_ingress_network_denied');}
    signer??=createNativeIngressSigner(env,{clock});
    outgoing=await(await signer)(new Request(clean,{signal}),address);
   }else{
    const bytes=await bounded(clean.body,limit,signal);
    outgoing=new Request(clean.url,{method:clean.method,headers:clean.headers,body:['GET','HEAD'].includes(clean.method)?undefined:bytes,signal});
   }
   const target=new URL(outgoing.url);target.protocol='http:';target.hostname='127.0.0.1';target.port='55101';
   const response=await fetchImpl(new Request(target,{method:outgoing.method,headers:outgoing.headers,
    body:['GET','HEAD'].includes(outgoing.method)?undefined:outgoing.body,duplex:'half',redirect:'manual',signal}));
   const output=await bounded(response.body,MAX_BYTES,signal),responseHeaders=new Headers(response.headers);
   for(const name of [...responseHeaders.keys()])if(hop.has(name)||name.toLowerCase()===NATIVE_INGRESS_HEADER.toLowerCase())responseHeaders.delete(name);
   for(const [key,value]of Object.entries(safeHeaders))responseHeaders.set(key,value);
   return new Response(request.method==='HEAD'||[204,205,304].includes(response.status)?null:output,{status:response.status,headers:responseHeaders});
  }catch(error){return fail(error instanceof NativeIngressError?error.status:error?.status===413||error?.code==='CONTRACT_REQUEST_SIZE'||error?.message==='body_limit'?413:503,error instanceof NativeIngressError?error.code:'backend_unavailable');}
 };
}
export async function serveNativeIngress(env=process.env,options={}){
 const path=env.COLLECT_NATIVE_INGRESS_SOCKET;
 if(typeof path!=='string'||resolve(path)!==path||path.length>100)throw Error('native_ingress_socket_required');
 const parent=dirname(path),info=await lstat(parent);
 if(info.isSymbolicLink()||!info.isDirectory()||info.uid!==process.getuid()||info.mode&0o077||await realpath(parent)!==parent)throw Error('native_ingress_socket_unprotected');
 try{await lstat(path);throw Error('native_ingress_socket_exists');}catch(error){if(error.code!=='ENOENT')throw error;}
 const application=await createNativeIngressApplication(env,options),profile=await verifyDeploymentProfile(env);
 const server=http.createServer({maxHeaderSize:16384,requestTimeout:20000,headersTimeout:10000,keepAliveTimeout:5000},async(req,res)=>{
  const controller=new AbortController(),abort=()=>controller.abort(),onClose=()=>{if(!res.writableFinished)abort();};
  req.once('aborted',abort);res.once('close',onClose);
  try{
   const count=name=>req.rawHeaders.filter((value,index)=>index%2===0&&value.toLowerCase()===name).length;
   if(req.headers.host!==new URL(profile.supabase_origin).host||count('host')!==1){res.writeHead(421,safeHeaders);res.end();return;}
   if(!validRawTarget(req.url)||/[\\\x00-\x20\x7f#]/.test(req.url)){res.writeHead(400,safeHeaders);res.end();return;}
   const native=nativePath(req.url.split('?')[0]);
   if(native&&count('cf-worker')>0){res.writeHead(403,{...safeHeaders,Connection:'close'});res.end();return;}
   if(native&&count('cf-connecting-ip')!==1){res.writeHead(403,safeHeaders);res.end();return;}
   const headers=new Headers();for(let i=0;i<req.rawHeaders.length;i+=2)headers.append(req.rawHeaders[i],req.rawHeaders[i+1]);
   const signal=AbortSignal.any([controller.signal,AbortSignal.timeout(15000)]),limit=native?nativeLimit(req.method,req.url):req.url.startsWith('/auth/v1/')?16384:MAX_BYTES;
   const declared=headers.get('content-length');if(declared!==null&&(!/^(0|[1-9][0-9]*)$/.test(declared)||Number(declared)>limit)){res.writeHead(413,safeHeaders);res.end();return;}
   const bytes=await bounded(['GET','HEAD'].includes(req.method)?null:ReadableStream.from(req),limit,signal);
   const request=new Request(profile.supabase_origin+req.url,{method:req.method,headers,body:['GET','HEAD'].includes(req.method)?undefined:bytes,signal:controller.signal});
   const response=await application(request,{rawTarget:req.url,clientAddress:req.headers['cf-connecting-ip'],workerSubrequest:count('cf-worker')>0});
   const output=Object.fromEntries(response.headers);if(response.headers.getSetCookie().length)output['set-cookie']=response.headers.getSetCookie();
   res.writeHead(response.status,output);res.end(request.method==='HEAD'?undefined:Buffer.from(await response.arrayBuffer()));
  }catch(error){if(!res.headersSent)res.writeHead(error?.message==='body_limit'?413:503,safeHeaders);res.end();}
  finally{req.removeListener('aborted',abort);res.removeListener('close',onClose);}
 });
 // No unlink/replacement of a retained socket. chmod completes before return;
 // the private parent protects the brief creation interval.
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(path,resolve);});
 const socket=await lstat(path);
 server.once('close',()=>{void lstat(path).then(current=>{if(current.isSocket()&&current.ino===socket.ino&&current.dev===socket.dev)return unlink(path);}).catch(()=>{});});
 try{await chmod(path,0o600);}catch{await new Promise(resolve=>server.close(resolve));throw Error('native_ingress_socket_unprotected');}
 return server;
}
export async function loadNativeIngressEnvironment(path){
 let handle;
 try{
  if(typeof path!=='string'||resolve(path)!==path||await realpath(dirname(path))!==dirname(path))throw Error();
  const parent=await lstat(dirname(path));if(!parent.isDirectory()||parent.uid!==process.getuid()||parent.mode&0o077)throw Error();
  handle=await open(path,constants.O_RDONLY|constants.O_NOFOLLOW);const before=await handle.stat();
  if(!before.isFile()||before.nlink!==1||before.uid!==process.getuid()||before.mode&0o077||before.size>32768)throw Error();
  const buffer=Buffer.alloc(32769);let size=0;
  while(size<buffer.length){const {bytesRead}=await handle.read(buffer,size,buffer.length-size,size);if(!bytesRead)break;size+=bytesRead;}
  if(size>32768)throw Error();
  const raw=new TextDecoder('utf-8',{fatal:true}).decode(buffer.subarray(0,size)),values={};
  for(const line of raw.endsWith('\n')?raw.slice(0,-1).split('\n'):raw.split('\n')){
   const equals=line.indexOf('='),name=line.slice(0,equals);
   if(equals<1||!INGRESS_ENV_FIELDS.includes(name)||Object.hasOwn(values,name))throw Error();
   const value=JSON.parse(line.slice(equals+1));if(typeof value!=='string'||value.includes('\0'))throw Error();values[name]=value.replaceAll('$$','$');
  }
  const after=await handle.stat();if(before.ino!==after.ino||before.dev!==after.dev||before.size!==after.size||before.mtimeMs!==after.mtimeMs||
   Object.keys(values).sort().join('|')!==INGRESS_ENV_FIELDS.join('|')||!['true','false'].includes(values.BURIMUNSI_NATIVE_ENABLED))throw Error();
  return Object.freeze(values);
 }catch{throw Error('native_ingress_env_unprotected_or_invalid');}finally{await handle?.close();}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 if(process.argv.length!==3)throw Error('one_private_native_ingress_file_required');
 await serveNativeIngress(await loadNativeIngressEnvironment(process.argv[2]));
}
