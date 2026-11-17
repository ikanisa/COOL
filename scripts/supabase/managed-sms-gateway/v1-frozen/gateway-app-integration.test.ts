// Deno synthetic integration: the actual SMS Hono app and auth middleware run
// behind an in-memory claim fixture. No provider, real DB or device is used.
import {app} from '../../../deploy/collect-sms/src/index.ts';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
import {openApplicationWork} from '../../../supabase/functions/_shared/application-fence.js';
import {createSyntheticSmsSigner,createSyntheticSmsVerifier,claimSyntheticSmsIngress} from './synthetic-ingress.mjs';
import assert from 'node:assert/strict';
function assertEquals(actual:unknown,expected:unknown):void {assert.deepEqual(actual,expected);}
const hex=(x:ArrayBuffer)=>Array.from(new Uint8Array(x),v=>v.toString(16).padStart(2,'0')).join('');
const sha=async(x:string)=>hex(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(x)));
const now=1800000000000,profile={format:'collect.deployment.v1',id:'sms-fixture',mode:'managed',environment:'qualification',supabase_origin:'https://rrlduytparvsjfmegalh.supabase.co',member_api_origin:'https://sms.example.invalid',admin_origin:'https://admin.example.invalid',public_origin:'https://public.example.invalid',google_callback_origin:'https://admin.example.invalid'};
const raw=canonicalProfile(profile),profileHash=await sha(raw),proof={evidenceSha256:'e'.repeat(64),format:'collect.sms-ingress.fixture-proof.v1',frontdoorOrigin:profile.member_api_origin,profileSha256:profileHash,reviewedAt:now-1,status:'synthetic',supabaseOrigin:profile.supabase_origin,workerGuard:'synthetic_cf_worker_reject'};
const proofRaw=JSON.stringify(Object.fromEntries(Object.keys(proof).sort().map(k=>[k,(proof as any)[k]])));
const config={COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:profileHash,SUPABASE_URL:profile.supabase_origin,APP_ENVIRONMENT:'qualification',COLLECT_SMS_ENABLED:'true',COLLECT_SMS_INGRESS_PROOF_JSON:proofRaw,COLLECT_SMS_INGRESS_PROOF_SHA256:await sha(proofRaw),COLLECT_SMS_INGRESS_KEY_ID:'fixture',COLLECT_SMS_INGRESS_KEY_BASE64:btoa('x'.repeat(32))};
const signer=await createSyntheticSmsSigner(config,{clock:()=>now}),verify=await createSyntheticSmsVerifier(config,{clock:()=>now});
async function work(){let row:any;return await (openApplicationWork as any)({sourceSha256:'a'.repeat(64),kind:'http_collect',backend:{
 register:async(id:string,s:string,k:string)=>(row={contractVersion:1,admissionId:id,sourceSha256:s,epoch:1,state:'active',mode:'open',kind:k}),
 lease:async()=>({row,assert:async()=>row,release:async()=>{}}),
 close:async(_id:string,_e:number,_s:string,state:string,reason:string,externalDispatches:number,uncertainDispatches:number)=>({...row,state,reason,externalDispatches,uncertainDispatches}),status:async()=>({...row,found:true})}});}
const deviceHash=await sha('synthetic-device-token'),appHash=await sha('synthetic-application-token');let revoked=false,queries=0;
const DB={prepare(query:string){let values:unknown[]=[];return {bind(...x:unknown[]){values=x;return this;},async first(){queries++;
 if(query.includes('FROM applications WHERE token_hash'))return values[0]===appHash?{application_id:'synthetic-app',allowed_kinds:'["receipt"]',scopes:'["messages:read"]'}:null;
 if(query.includes('FROM devices WHERE token_hash'))return values[0]===deviceHash&&!revoked?{installation_id:'synthetic-device',allowed_kinds:'["receipt"]'}:null;
 if(query.includes('FROM devices WHERE installation_id'))return {ready:0,sim_slot:0};return null;}};}};
const env={DB,ROOT_ADMIN_TOKEN:'r'.repeat(48),OTP_HMAC_KEY:'o'.repeat(48),ENVIRONMENT:'production',ALLOW_INSECURE_LOCALHOST:'false',ADMIN_ORIGIN:profile.admin_origin,DISPATCH_PAUSED:'true',FCM_ENABLED:'false'};
async function route(token:string,consume=async()=>true){const w=await work();try{
 const external=new Request(profile.member_api_origin+'/functions/v1/collect-sms/v1/device/jobs?limit=2',{headers:{authorization:'Bearer '+token}});
 const admitted=await claimSyntheticSmsIngress(await verify(await signer(external)),w,consume);
 return await app.fetch(admitted,env as any,{waitUntil(){},passThroughOnException(){}} as any);
 }finally{await w.finish();}}
Deno.test('actual SMS middleware retains device token, revocation and application-scope semantics',async()=>{
 revoked=false;const valid=await route('synthetic-device-token');assertEquals(valid.status,200);assertEquals((await valid.json()).jobs,[]);
 revoked=true;assertEquals((await route('synthetic-device-token')).status,401);revoked=false;
 assertEquals((await route('synthetic-application-token')).status,403);
 assertEquals((await route('invalid-token')).status,401);
});
Deno.test('failed replay claim cannot reach the actual SMS middleware',async()=>{
 const before=queries;let rejected=false;try{await route('synthetic-device-token',async()=>false);}catch{rejected=true;}
 assertEquals(rejected,true);assertEquals(queries,before);
});
