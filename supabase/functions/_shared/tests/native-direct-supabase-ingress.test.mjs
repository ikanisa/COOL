import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN} from '../deployment-profile.js';
import {admitDirectSupabaseNativeIngress,DIRECT_SUPABASE_INGRESS_MODE} from '../native-direct-supabase-ingress.js';

const profile={format:'collect.deployment.v1',id:'direct-qualification',mode:'managed',environment:'qualification',
 supabase_origin:MANAGED_SUPABASE_ORIGIN,member_api_origin:'https://api.fixture.invalid',admin_origin:'https://admin.fixture.invalid',
 public_origin:'https://collect.fixture.invalid',google_callback_origin:'https://admin.fixture.invalid'};
const raw=canonicalProfile(profile),sha=value=>createHash('sha256').update(value).digest('hex');
const env=()=>({COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:sha(raw),APP_ENVIRONMENT:'qualification',
 SUPABASE_URL:profile.supabase_origin,BURIMUNSI_NATIVE_ENABLED:'true',COLLECT_NATIVE_INGRESS_MODE:DIRECT_SUPABASE_INGRESS_MODE});
function input({path='/v1/burimunsi/session/login',method='POST',headers={},body='{}',origin=profile.supabase_origin,signal}={}){
 return new Request(origin+path,{method,headers:{'content-type':'application/json',...headers},...(method==='GET'?{}:{body}),signal});
}

test('all client addresses, auth headers, cookies and old ingress claims use one stable bucket',async()=>{
 const buckets=[];
 for(const headers of [
  {},{'CF-Connecting-IP':'192.0.2.1','X-Forwarded-For':'203.0.113.4','Authorization':'Bearer fixture-a','Cookie':'fixture=a'},
  {'CF-Connecting-IP':'198.51.100.9','X-Real-IP':'203.0.113.9','CF-Worker':'foreign.example','X-Collect-Native-Ingress':'forged',
   'Authorization':'Bearer fixture-b','Cookie':'fixture=b'},
 ]){
  const admitted=await admitDirectSupabaseNativeIngress(input({headers}),env());
  buckets.push(await admitted.networkBucket(admitted.request));
  for(const name of ['CF-Connecting-IP','X-Forwarded-For','X-Real-IP','CF-Worker','X-Collect-Native-Ingress'])
   assert.equal(admitted.request.headers.has(name),false);
  if(headers.Authorization)assert.equal(admitted.request.headers.get('authorization'),headers.Authorization);
  if(headers.Cookie)assert.equal(admitted.request.headers.get('cookie'),headers.Cookie);
  assert.equal(await admitted.request.text(),'{}');
  await assert.rejects(admitted.networkBucket(new Request(admitted.request.url)),e=>e.code==='native_ingress_denied');
 }
 assert.match(buckets[0],/^[a-f0-9]{64}$/);assert.equal(new Set(buckets).size,1);
});

test('only the explicitly configured managed project and native path are admitted',async()=>{
 for(const value of [undefined,'','signed_frontdoor_v1','supabase_direct_v1 ',true])
  await assert.rejects(admitDirectSupabaseNativeIngress(input(),{...env(),COLLECT_NATIVE_INGRESS_MODE:value}));
 for(const change of [{SUPABASE_URL:'https://other.invalid'},{APP_ENVIRONMENT:'production'},
  {BURIMUNSI_NATIVE_ENABLED:'false'},{COLLECT_DEPLOYMENT_PROFILE:undefined},{COLLECT_DEPLOYMENT_PROFILE_SHA256:'0'.repeat(64)}])
  await assert.rejects(admitDirectSupabaseNativeIngress(input(),{...env(),...change}));
 const self={...profile,mode:'self_hosted',supabase_origin:'https://other.invalid'};
 const encoded=canonicalProfile(self);
 await assert.rejects(admitDirectSupabaseNativeIngress(input(),{...env(),COLLECT_DEPLOYMENT_PROFILE:encoded,
  COLLECT_DEPLOYMENT_PROFILE_SHA256:sha(encoded),SUPABASE_URL:self.supabase_origin}));
 for(const change of [{origin:'https://other.invalid'},{path:'/v1/%62urimunsi/session/login'},
  {path:'/v1/burimunsi//session/login'},{path:'/v1/not-burimunsi'},{method:'PUT'}])
  await assert.rejects(admitDirectSupabaseNativeIngress(input(change),env()));
});

test('body limits and exact bytes survive direct admission',async()=>{
 const admitted=await admitDirectSupabaseNativeIngress(input({path:'/v1/burimunsi/members/import',body:'x'.repeat(8193)}),env());
 assert.equal((await admitted.request.text()).length,8193);
 await assert.rejects(admitDirectSupabaseNativeIngress(input({body:'x'.repeat(8193)}),env()),e=>e.code==='CONTRACT_REQUEST_SIZE');
 await assert.rejects(admitDirectSupabaseNativeIngress(input({path:'/v1/burimunsi/members/import?x=1',body:'x'.repeat(8193)}),env()),e=>e.code==='CONTRACT_REQUEST_SIZE');
 await assert.rejects(admitDirectSupabaseNativeIngress(input({body:'{}',headers:{'Content-Length':'3'}}),env()),e=>e.code==='CONTRACT_CONTENT_LENGTH');
});

test('aborted requests cannot be admitted or use a previously returned bucket',async()=>{
 const a=new AbortController();a.abort();
 await assert.rejects(admitDirectSupabaseNativeIngress(input({signal:a.signal}),env()),e=>e.code==='CONTRACT_REQUEST_ABORTED');
 const b=new AbortController(),admitted=await admitDirectSupabaseNativeIngress(input({signal:b.signal}),env());b.abort();
 await assert.rejects(admitted.networkBucket(admitted.request),e=>e.code==='CONTRACT_REQUEST_ABORTED');
});
