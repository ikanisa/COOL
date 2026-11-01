import assert from 'node:assert/strict';
import {createSmsGatewayHandler} from '../src/edge.ts';
const profile={format:'collect.deployment.v1',id:'synthetic-gateway',mode:'self_hosted',environment:'qualification',supabase_origin:'https://db.example.invalid',member_api_origin:'https://api.example.invalid',admin_origin:'https://admin.example.invalid',public_origin:'https://www.example.invalid',google_callback_origin:'https://admin.example.invalid'};
const canonical=JSON.stringify(Object.fromEntries(Object.keys(profile).sort().map(k=>[k,(profile as any)[k]])));
const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(canonical))),b=>b.toString(16).padStart(2,'0')).join('');
const settings={COLLECT_SMS_ENABLED:'true',COLLECT_SMS_APPROVAL_SHA256:'a'.repeat(64),BUILD_SOURCE_ID:'b'.repeat(64),COLLECT_DEPLOYMENT_PROFILE:canonical,COLLECT_DEPLOYMENT_PROFILE_SHA256:hash,ROOT_ADMIN_TOKEN:'r'.repeat(48),OTP_HMAC_KEY:'o'.repeat(48)};
// Ingress-only doubles. The separate native gateway fence qualification uses
// actual restricted logins, registration, leases, identity and database writes.
function admissionDouble(reject=false){let active:any;return {
 register:async(id:string,source:string,kind:string)=>{if(reject)throw Error('deployment_identity_mismatch');return active={contractVersion:1,admissionId:id,epoch:1,sourceSha256:source,kind,state:'active',mode:'open'};},
 lease:async()=>({row:active,assert:async()=>active,release:async()=>{}}),
 close:async(_id:string,_epoch:number,_source:string,state:string,reason:string,externalDispatches:number,uncertainDispatches:number)=>({...active,state,reason,externalDispatches,uncertainDispatches}),
 status:async()=>({...active,found:true})};}
const databaseDouble={withApplicationWork(){return this;},prepare:()=>({first:async()=>({ok:1})})};
const handler=()=>createSmsGatewayHandler(settings,{database:databaseDouble,fenceBackend:admissionDouble()} as any);
Deno.test('gateway accepts exact long and Envoy-stripped prefixes over trusted internal HTTP',async()=>{
 const fetch=handler();
 for(const origin of ['https://db.example.invalid','http://db.example.invalid','http://api-gw:8000','http://functions:9000','http://127.0.0.1:9000'])for(const prefix of ['/functions/v1/collect-sms','/collect-sms']){
  const response=await fetch(new Request(origin+prefix+'/health?probe=one'));assert.equal(response.status,200,origin+prefix);assert.equal((await response.json()).service,'collect-sms');
 }
});
Deno.test('gateway rejects arbitrary HTTP and does not trust forwarded authority',async()=>{
 const response=await handler()(new Request('http://evil.example.invalid/collect-sms/health',{headers:{'x-forwarded-proto':'https','x-forwarded-host':'db.example.invalid'}}));assert.equal(response.status,403);
});
Deno.test('gateway reconstruction retains browser origin and token admission',async()=>{
 const fetch=handler();
 assert.equal((await fetch(new Request('http://functions:9000/collect-sms/health',{headers:{Origin:'https://evil.example.invalid'}}))).status,403);
 assert.equal((await fetch(new Request('http://functions:9000/collect-sms/v1/messages',{method:'POST',body:'{}',headers:{'Content-Type':'application/json'}}))).status,401);
 assert.equal((await fetch(new Request('http://functions:9000/collect-sms/internal/maintenance',{method:'POST'}))).status,404);
});
Deno.test('gateway remains unavailable without explicit deployment enablement',async()=>{
 assert.equal((await createSmsGatewayHandler({...settings,COLLECT_SMS_ENABLED:'false'})(new Request('https://db.example.invalid/collect-sms/health'))).status,503);
});
Deno.test('gateway refuses a database with mismatched installation identity',async()=>{
 const fetch=createSmsGatewayHandler(settings,{database:databaseDouble,fenceBackend:admissionDouble(true)} as any);
 assert.equal((await fetch(new Request('https://db.example.invalid/collect-sms/health'))).status,503);
});
