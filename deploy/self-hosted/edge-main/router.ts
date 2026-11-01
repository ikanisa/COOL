import {workerEnvironment} from './environment.mjs';
const names=new Set(['collect-api','admin-api','collect-jobs','collect-email-jobs','collect-sms','send-sms-hook']);

/** sourceRoot is injectable only by a qualification caller. The production
 * entrypoint always uses the fixed read-only container mount below. */
export function createRouter(env:Record<string,string>,{sourceRoot='/home/deno/collect'}={}){
 return async(request:Request)=>{
  const url=new URL(request.url),segments=url.pathname.split('/');
  const name=segments[1]==='functions'&&segments[2]==='v1'?segments[3]:segments[1];
  if(!names.has(name)||request.url.length>8192)return Response.json({code:'not_found'},{status:404});
  try{
   // EdgeRuntime is supplied by the pinned Supabase container, not stock Deno.
   // @ts-ignore Supabase Edge Runtime host API
   const worker=await EdgeRuntime.userWorkers.create({servicePath:sourceRoot+'/supabase/functions/'+name,memoryLimitMb:256,workerTimeoutMs:180000,requestAbsentTimeoutMs:60000,noModuleCache:false,importMapPath:sourceRoot+'/supabase/functions/deno.json',envVars:workerEnvironment(name,env)});
   return await worker.fetch(request);
  }catch{
   console.error(JSON.stringify({service:'collect_edge_router',event:'worker_unavailable',function:name}));
   return Response.json({code:'backend_unavailable'},{status:503,headers:{'Cache-Control':'no-store'}});
  }
 };
}
