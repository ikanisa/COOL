import http from 'node:http';
import {readFile,realpath,stat} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import {Readable} from 'node:stream';
import {createAdminWorker} from '../platform-admin/src/index.js';
import {createCollectTransport} from '../platform-admin/src/supabase-transport.js';
import {verifyDeploymentProfile} from '../../supabase/functions/_shared/deployment-profile.js';
import {renderLocalChallengeDocument} from '../platform-supabase-free/local-challenge.mjs';
import {createAuthPhoneProxy} from './auth-phone-proxy.mjs';
const types={'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.css':'text/css','.svg':'image/svg+xml','.png':'image/png','.jpg':'image/jpeg','.jpeg':'image/jpeg','.ico':'image/x-icon','.webp':'image/webp','.woff2':'font/woff2','.ttf':'font/ttf','.otf':'font/otf','.webmanifest':'application/manifest+json'};
const safeHeaders={'X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Cache-Control':'no-store, no-transform'};
export function staticAssets(directory){
 const base=resolve(directory);
 return {async fetch(request){
  if(!['GET','HEAD'].includes(request.method))return new Response(null,{status:405,headers:safeHeaders});
  let path;try{path=decodeURIComponent(new URL(request.url).pathname);}catch{return new Response(null,{status:400,headers:safeHeaders});}
  const wellKnown=['/.well-known/assetlinks.json','/.well-known/apple-app-site-association'].includes(path);
  if(path.includes('\\')||path.includes('\0')||path.split('/').some(p=>p.startsWith('.')&&!(wellKnown&&p==='.well-known'))||path.endsWith('.map'))return new Response(null,{status:404,headers:safeHeaders});
  const locate=async name=>{const candidate=resolve(base,'.'+name);if(candidate!==base&&!candidate.startsWith(base+sep))throw Error('invalid');const real=await realpath(candidate);if(!real.startsWith(base+sep)||!(await stat(real)).isFile())throw Error('invalid');return real;};
  let file;try{file=await locate(path==='/'?'/index.html':path);}catch{
   if(!request.headers.get('Accept')?.includes('text/html'))return new Response(null,{status:404,headers:safeHeaders});
   try{file=await locate('/index.html');}catch{return new Response(null,{status:503,headers:safeHeaders});}
  }
  const headers={...safeHeaders,'Content-Type':wellKnown?'application/json':types[extname(file)]??'application/octet-stream'};
  return new Response(request.method==='HEAD'?null:await readFile(file),{headers});
 }};
}
export async function createWebApplication(env){
 const profile=await verifyDeploymentProfile(env);
 if(profile.mode!=='self_hosted'||env.SUPABASE_URL!==profile.supabase_origin||env.APP_ENVIRONMENT!==profile.environment)throw new Error('A matching self-hosted web profile is required');
 const origins=[...new Set([profile.admin_origin,profile.member_api_origin,profile.public_origin])],adminAssets=staticAssets(env.COLLECT_ADMIN_ASSET_DIR??'/srv/admin'),memberAssets=staticAssets(env.COLLECT_PUBLIC_ASSET_DIR??'/srv/public');
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
  return memberAssets.fetch(request);
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
  const controller=new AbortController();req.on('aborted',()=>controller.abort());
  try{
   if(typeof req.headers.host!=='string'||!hosts.has(req.headers.host)||req.rawHeaders.filter((_,i)=>i%2===0&&req.rawHeaders[i].toLowerCase()==='host').length!==1){res.writeHead(421,safeHeaders);res.end();return;}
   if(!validRawTarget(req.url)){res.writeHead(400,safeHeaders);res.end();return;}
   const limit=req.headers.host===new URL(profile.supabase_origin).host?16384:16777216;
   const declared=req.headers['content-length'];if(declared!==undefined&&(!/^\d+$/.test(declared)||Number(declared)>limit)){res.writeHead(413,safeHeaders);res.end();return;}
   const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>limit){res.writeHead(413,safeHeaders);res.end();return;}chunks.push(chunk);}
   const headers=new Headers();for(let i=0;i<req.rawHeaders.length;i+=2)headers.append(req.rawHeaders[i],req.rawHeaders[i+1]);
   const request=new Request('https://'+req.headers.host+req.url,{method:req.method,headers,body:['GET','HEAD'].includes(req.method)?undefined:Buffer.concat(chunks),signal:controller.signal});
   const response=await application(request),output=Object.fromEntries(response.headers);if(response.headers.getSetCookie().length)output['set-cookie']=response.headers.getSetCookie();
   res.writeHead(response.status,output);if(!response.body||req.method==='HEAD'){res.end();return;}
   const stream=Readable.fromWeb(response.body);res.on('close',()=>{if(!res.writableEnded){controller.abort();stream.destroy();}});stream.on('error',()=>res.destroy());stream.pipe(res);
  }catch{if(!res.headersSent)res.writeHead(503,safeHeaders);res.end();}
 });
 server.listen(Number(env.PORT??8080),'0.0.0.0');return server;
}
if(process.argv[1]&&resolve(process.argv[1])===new URL(import.meta.url).pathname)await serveWeb();
