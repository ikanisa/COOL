import assert from 'node:assert/strict';
import {createHash,createHmac} from 'node:crypto';
import {createCollectSendSmsHandler} from '../send-sms-hook.js';
import {canonicalProfile} from '../deployment-profile.js';
import {openApplicationWork} from '../application-fence.js';
import {syntheticFenceBackend} from './helpers/fenced-unit.js';

const NOW=1793448000000,secret=Buffer.alloc(32,7);
const profile={format:'collect.deployment.v1',id:'collect-hook-test',mode:'self_hosted',environment:'qualification',
 supabase_origin:'https://supabase.collect.example',member_api_origin:'https://api.collect.example',admin_origin:'https://admin.collect.example',
 public_origin:'https://collect.example',google_callback_origin:'https://admin.collect.example'};
const encoded=canonicalProfile(profile),sha=(value:string)=>createHash('sha256').update(value).digest('hex');
const env={COLLECT_DEPLOYMENT_PROFILE:encoded,COLLECT_DEPLOYMENT_PROFILE_SHA256:sha(encoded),BUILD_SOURCE_ID:'a'.repeat(64),
 SUPABASE_URL:profile.supabase_origin,APP_ENVIRONMENT:profile.environment,AUTH_PROJECT_ID:profile.id,AUTH_SMS_ENABLED:'true',AUTH_PHONE_DELIVERY_MODE:'opensms_hook',
 AUTH_SEND_SMS_SECRET:'v1,whsec_'+secret.toString('base64'),OPENSMS_BASE_URL:profile.supabase_origin+'/functions/v1/collect-sms',
 OPENSMS_APPLICATION_ID:'collect_auth',OPENSMS_APPLICATION_TOKEN:'app_'+'s'.repeat(40),OPENSMS_DISPATCH_TTL_SECONDS:'120'};
function request({signed=true,id='event_a'}={}){
 const raw=JSON.stringify({user:{id:'11111111-1111-4111-8111-111111111111',phone:'250788000001'},sms:{phone:'250788000002',otp:'123456'}}),stamp=String(NOW/1000);
 return new Request(profile.supabase_origin+'/functions/v1/send-sms-hook',{method:'POST',headers:{'Content-Type':'application/json',
  ...(signed?{'webhook-id':id,'webhook-timestamp':stamp,'webhook-signature':'v1,'+createHmac('sha256',secret).update(id+'.'+stamp+'.'+raw).digest('base64')}:{})},body:raw});
}
async function fixture(fn:(h:any)=>Promise<void>){
 const previous=globalThis.fetch,backend=syntheticFenceBackend(),work:any[]=[],jobs=new Map(),calls:any[]=[];let lost=false;
 const admit=async()=>{const current=await (openApplicationWork as any)({backend,sourceSha256:env.BUILD_SOURCE_ID,kind:'http_collect'});work.push(current);return current;};
 globalThis.fetch=async(input:any,options:any)=>{
  const url=new URL(String(input));assert.equal(url.origin,profile.supabase_origin);assert(url.pathname.startsWith('/functions/v1/collect-sms/v1/messages'));
  assert.equal(options.redirect,'error');assert.equal(options.headers.authorization,'Bearer '+env.OPENSMS_APPLICATION_TOKEN);
  calls.push({path:url.pathname,method:options.method});
  if(options.method==='GET'){const id=decodeURIComponent(url.pathname.split('/').at(-1)!);return Response.json(jobs.has(id)?{message:jobs.get(id)}:{},{status:jobs.has(id)?200:404});}
  const body=JSON.parse(options.body),row={...body,application_id:env.OPENSMS_APPLICATION_ID,available_at:new Date(NOW).toISOString(),campaign_id:null,state:'accepted',cancel_requested:false};
  assert.equal(body.kind,'otp');assert.equal(body.to,'+250788000002');
  const fields=[row.message_id,row.application_id,row.kind,row.to,row.text,String(row.priority),row.not_after,row.available_at,''];
  row.payload_digest=sha('collect-sms-payload-v1\n'+fields.map(v=>Buffer.byteLength(v)+':'+v).join(''));row.text='[OTP content hidden]';jobs.set(row.message_id,row);
  if(lost){lost=false;throw Error('synthetic_lost_response');}
  return Response.json({message_id:row.message_id,state:'accepted'},{status:202});
 };
 try{await fn({admit,backend,work,jobs,calls,loseNext:()=>{lost=true;},handler:(changes:any={},options:any={})=>createCollectSendSmsHandler(()=>({...env,...changes}),{admit,handlerOptions:{now:()=>NOW,...options}})});}
 finally{globalThis.fetch=previous;for(const owned of work)await owned.finish();}
}

Deno.test('OTP signature, activation, profile hash and credential separation precede every admission',async()=>fixture(async h=>{
 assert.equal((await h.handler()(request({signed:false}))).status,401);assert.equal(h.work.length,0);assert.equal(h.calls.length,0);
 for(const overrides of [{AUTH_SMS_ENABLED:'false'},{AUTH_PHONE_DELIVERY_MODE:'twilio'},{AUTH_PHONE_DELIVERY_MODE:'twilio_verify'},
  {AUTH_PHONE_DELIVERY_MODE:undefined},{AUTH_WHATSAPP_ENABLED:'true'},{COLLECT_DEPLOYMENT_PROFILE_SHA256:'0'.repeat(64)},{AUTH_PROJECT_ID:'other-project'},
  {OPENSMS_RECEIPT_APPLICATION_ID:env.OPENSMS_APPLICATION_ID},{OPENSMS_RECEIPT_APPLICATION_TOKEN:env.OPENSMS_APPLICATION_TOKEN}]){
  assert.equal((await h.handler(overrides)(request())).status,503);assert.equal(h.work.length,0);assert.equal(h.calls.length,0);
 }
}));
Deno.test('Supabase Functions path survives signed enqueue and a cold retry never resends the OTP',async()=>fixture(async h=>{
 assert.equal((await h.handler()(request())).status,200);assert.equal(h.work.length,1);assert.equal(h.calls.filter((r:any)=>r.method==='POST').length,1);
 assert.equal((await h.handler()(request())).status,200);assert.equal(h.work.length,2);assert.equal(h.calls.filter((r:any)=>r.method==='POST').length,1);
 assert.equal(h.jobs.size,1);for(const row of h.jobs.values())assert.equal(row.kind,'otp');
}));
Deno.test('lost provider acknowledgement is fenced as uncertain and recovered using the original job',async()=>fixture(async h=>{
 h.loseNext();assert.equal((await h.handler()(request())).status,503);
 await h.work[0].finish();assert.equal([...h.backend.rows.values()][0].reason,'completed_with_unknown_obligation');
 assert.equal((await h.handler()(request())).status,200);assert.equal(h.calls.filter((r:any)=>r.method==='POST').length,1);assert.equal(h.jobs.size,1);
}));
Deno.test('late application admission cannot send after the shared hook deadline',async()=>fixture(async h=>{
 let release!:()=>void;const held=new Promise<void>(resolve=>{release=resolve;});let started!:()=>void;const entered=new Promise<void>(resolve=>{started=resolve;});
 const handler=createCollectSendSmsHandler(()=>env,{admit:async()=>{started();await held;return h.admit();},handlerOptions:{now:()=>NOW,timeoutMs:25}});
 const reply=handler(request());await entered;assert.equal((await reply).status,503);release();
 await new Promise(resolve=>setTimeout(resolve,10));assert.equal(h.calls.length,0);
}));
