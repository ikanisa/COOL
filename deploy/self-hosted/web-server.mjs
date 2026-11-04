import http from 'node:http';
import {readFile,realpath,stat} from 'node:fs/promises';
import {resolve,extname,relative,sep} from 'node:path';
import {Readable} from 'node:stream';
import {createAdminWorker} from '../platform-admin/src/index.js';
import {createCollectTransport} from '../platform-admin/src/supabase-transport.js';
import {verifyDeploymentProfile} from '../../supabase/functions/_shared/deployment-profile.js';
import {renderLocalChallengeDocument} from '../platform-supabase-free/local-challenge.mjs';
import {createAuthPhoneProxy} from './auth-phone-proxy.mjs';
const types={'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.ico':'image/x-icon','.webp':'image/webp','.woff2':'font/woff2','.ttf':'font/ttf','.otf':'font/otf','.webmanifest':'application/manifest+json'};
const safeHeaders={'X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Cache-Control':'no-store, no-transform'};
export function staticAssets(directory,{directoryIndex=false}={}){
 const base=resolve(directory);
 const invitationRoots=['c','group-link'].map(name=>resolve(base,name));
 return {async fetch(request){
  if(!['GET','HEAD'].includes(request.method))return new Response(null,{status:405,headers:safeHeaders});
  let path,url;try{url=new URL(request.url);path=decodeURIComponent(url.pathname);}catch{return new Response(null,{status:400,headers:safeHeaders});}
  const wellKnown=['/.well-known/assetlinks.json','/.well-known/apple-app-site-association'].includes(path);
  if(path.includes('\\')||path.includes('\0')||path.split('/').some(p=>p.startsWith('.')&&!(wellKnown&&p==='.well-known'))||path.endsWith('.map'))return new Response(null,{status:404,headers:safeHeaders});
  const hidden=real=>relative(base,real).split(sep).some(part=>part.startsWith('.'));
  const locate=async name=>{
   const candidate=resolve(base,'.'+name);if(candidate!==base&&!candidate.startsWith(base+sep))throw Error('invalid');
   const real=await realpath(candidate);if(!real.startsWith(base+sep))throw Error('invalid');
   const info=await stat(real);if(info.isFile()){
    if(directoryIndex&&hidden(real)&&!(wellKnown&&real===candidate))throw Error('invalid');
    return real;
   }
   // Invitation directories retain their existing fallback until that route is qualified.
   const invitation=location=>invitationRoots.some(root=>location===root||location.startsWith(root+sep));
   if(!directoryIndex||!info.isDirectory()||hidden(real)||invitation(candidate)||invitation(real))throw Error('invalid');
   const index=await realpath(resolve(real,'index.html'));
   if(!index.startsWith(base+sep)||hidden(index)||invitation(index)||!(await stat(index)).isFile())throw Error('invalid');
   return index;
  };
  const html=!!request.headers.get('Accept')?.includes('text/html');
  const segments=path.split('/');const groupCode=segments.length===3&&segments[1].toLowerCase()==='c'?segments[2].trim().toLowerCase():'';
  const slugMatch=/^[a-z0-9]+(?:-[a-z0-9]+)*/.exec(groupCode);
  const groupRoute=groupCode.length>0&&groupCode.length<=140&&slugMatch?.[0]===groupCode;
  const legacyRoute=['/c','/c/','/group-link','/group-link/'].includes(path.toLowerCase())&&[...url.searchParams.keys()].some(key=>key.toLowerCase()==='slug');
  // Group routes are reserved before file lookup, avoiding a same-name file collision.
  const shareShell=directoryIndex&&(groupRoute||(html&&legacyRoute));
  let file;try{file=await locate(shareShell?'/c/index.html':path==='/'?'/index.html':path);}catch{
   if(shareShell)return new Response(null,{status:503,headers:safeHeaders});
   if(!html)return new Response(null,{status:404,headers:safeHeaders});
   try{file=await locate('/index.html');}catch{return new Response(null,{status:503,headers:safeHeaders});}
  }
  const headers={...safeHeaders,'Content-Type':wellKnown?'application/json':types[extname(file)]??'application/octet-stream'};
  return new Response(request.method==='HEAD'?null:await readFile(file),{headers});
 }};
}
export async function createWebApplication(env){
 const profile=await verifyDeploymentProfile(env);
 if(profile.mode!=='self_hosted'||env.SUPABASE_URL!==profile.supabase_origin||env.APP_ENVIRONMENT!==profile.environment)throw new Error('A matching self-hosted web profile is required');
 if(profile.admin_origin===profile.public_origin)throw new Error('Self-hosted Admin and public origins must differ');
 const origins=[...new Set([profile.admin_origin,profile.member_api_origin,profile.public_origin])],adminAssets=staticAssets(env.COLLECT_ADMIN_ASSET_DIR??'/srv/admin'),memberAssets=staticAssets(env.COLLECT_PUBLIC_ASSET_DIR??'/srv/public'),publicAssets=staticAssets(env.COLLECT_PUBLIC_ASSET_DIR??'/srv/public',{directoryIndex:true});
 const admin=createAdminWorker(),auth=createAuthPhoneProxy(env),transports=new Map(origins.map(origin=>[origin,createCollectTransport({frontendOrigin:origin,supabaseOrigin:profile.supabase_origin,upstreamOrigin:env.SUPABASE_INTERNAL_URL??profile.supabase_origin,allowedFrontendOrigins:origins})]));
 return async request=>{
  const url=new URL(request.url);
  if(url.origin===profile.supabase_origin)return url.pathname.startsWith('/auth/v1/')?auth(request):new Response(null,{status:404,headers:safeHeaders});
  if(!origins.includes(url.origin))return new Response(null,{status:421,headers:safeHeaders});
  if(url.pathname==='/__health'&&['GET','HEAD'].includes(request.method))return Response.json({status:'ready'},{headers:safeHeaders});
  if(url.origin===profile.admin_origin)return admin.fetch(request,{...env,ADMIN_ORIGIN:profile.admin_origin,ASSETS:adminAssets,COLLECT_BACKEND:'supabase'});
  if(url.pathname==='/api'||url.pathname.startsWith('/api/admin'))return new Response(null,{status:404,headers:safeHeaders});
  const challenge=renderLocalChallengeDocument(request,{origin:url.origin,allowedOrigins:origins});if(challenge)return challenge;
  if(['/v1','/functions','/privacy/account-deletion'].some(path=>url.pathname===path||url.pathname.startsWith(path+'/')))return await transports.get(url.origin)(request)??new Response(null,{status:404,headers:safeHeaders});
  return (url.origin===profile.public_origin?publicAssets:memberAssets).fetch(request);
 };
}
export function validRawTarget(target){
 if(typeof target!=='string'||target.length>8192||!target.startsWith('/')||target.startsWith('//'))return false;
 const path=target.split('?')[0];
 return !/[\\\x00-\x20\x7f]|%(?:2e|2f|5c|00)/i.test(path)&&!path.split('/').some(part=>part==='.'||part==='..');
}
export async function serveWeb(env=process.env){
 const application=await createWebApplication(env),profile=await verifyDeploymentProfile(env),hosts=new Set([profile.admin_origin,profile.member_api_origin,profile.public_origin,profile.supabase_origin].map(v=>new URL(v).host));
 const server=http.createServer({maxHeaderSize:16384,requestTimeout:20000,headersTimeout:10000,keepAliveTimeout:5000},async(req,res)=>{
  const controller=new AbortController();let stream=null;
  const cleanup=()=>{req.removeListener('aborted',onAbort);res.removeListener('close',onClose);res.removeListener('finish',onFinish);};
  const onAbort=()=>controller.abort();
  const onClose=()=>{if(!res.writableFinished){controller.abort();stream?.destroy();}cleanup();};
  const onFinish=()=>cleanup();
  req.on('aborted',onAbort);res.once('close',onClose);res.once('finish',onFinish);
  if(res.destroyed||res.writableEnded){if(!res.writableFinished)controller.abort();cleanup();return;}
  if(req.aborted)controller.abort();
  try{
   if(typeof req.headers.host!=='string'||!hosts.has(req.headers.host)||req.rawHeaders.filter((_,i)=>i%2===0&&req.rawHeaders[i].toLowerCase()==='host').length!==1){res.writeHead(421,safeHeaders);res.end();return;}
   if(!validRawTarget(req.url)){res.writeHead(400,safeHeaders);res.end();return;}
   const limit=req.headers.host===new URL(profile.supabase_origin).host?16384:16777216;
   const declared=req.headers['content-length'];if(declared!==undefined&&(!/^\d+$/.test(declared)||Number(declared)>limit)){res.writeHead(413,safeHeaders);res.end();return;}
   const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>limit){res.writeHead(413,safeHeaders);res.end();return;}chunks.push(chunk);}
   if(res.destroyed||res.writableEnded){if(!res.writableFinished)controller.abort();cleanup();return;}
   const headers=new Headers();for(let i=0;i<req.rawHeaders.length;i+=2)headers.append(req.rawHeaders[i],req.rawHeaders[i+1]);
   const request=new Request('https://'+req.headers.host+req.url,{method:req.method,headers,body:['GET','HEAD'].includes(req.method)?undefined:Buffer.concat(chunks),signal:controller.signal});
   const response=await application(request);
   if(res.destroyed||res.writableEnded){if(!res.writableFinished)controller.abort();try{const pending=response.body?.cancel();if(pending!==undefined)void Promise.resolve(pending).catch(()=>{});}catch{}cleanup();return;}
   const output=Object.fromEntries(response.headers);if(response.headers.getSetCookie().length)output['set-cookie']=response.headers.getSetCookie();
   res.writeHead(response.status,output);if(!response.body||req.method==='HEAD'){res.end();return;}
   stream=Readable.fromWeb(response.body);stream.on('error',()=>res.destroy());stream.pipe(res);
  }catch{if(res.destroyed||res.writableEnded){if(!res.writableFinished)controller.abort();cleanup();return;}if(!res.headersSent)res.writeHead(503,safeHeaders);res.end();}
 });
 server.listen(Number(env.PORT??8080),'0.0.0.0');return server;
}
if(process.argv[1]&&resolve(process.argv[1])===new URL(import.meta.url).pathname)await serveWeb();
