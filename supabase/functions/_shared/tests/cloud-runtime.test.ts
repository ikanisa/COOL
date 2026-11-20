import {assertEquals,assertRejects} from 'jsr:@std/assert@1.0.14';
import {logicalRequest,createHandler} from '../serve.js';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN} from '../deployment-profile.js';
import {SupabaseNativeTransport} from '../storage/supabase-transport.js';
const profile={format:'collect.deployment.v1',id:'collect-managed-test',mode:'managed',environment:'qualification',supabase_origin:MANAGED_SUPABASE_ORIGIN,member_api_origin:'https://api.collect.example',admin_origin:'https://admin.collect.example',public_origin:'https://collect.example',google_callback_origin:'https://api.collect.example'};
async function environment(){const raw=canonicalProfile(profile),hash=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw));return {COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:Array.from(new Uint8Array(hash),b=>b.toString(16).padStart(2,'0')).join(''),APP_ENVIRONMENT:'qualification'};}
Deno.test('Edge restores HTTPS only for the configured Cloud project hostname',async()=>{
 const env=await environment(),host=new URL(profile.supabase_origin).hostname;
 const result=logicalRequest(new Request('http://'+host+'/functions/v1/admin-api/api/admin/auth/session',{headers:{'X-Forwarded-Host':'evil.example','X-Forwarded-Proto':'http'}}),'admin-api',env);
 assertEquals(result.url,profile.supabase_origin+'/api/admin/auth/session');
 for(const origin of ['http://api-gw:8000','http://functions:9000','http://127.0.0.1:9000','http://other.example']){
  const other=logicalRequest(new Request(origin+'/functions/v1/admin-api/api/admin/auth/session'),'admin-api',env);
  assertEquals(new URL(other.url).origin,origin);
 }
});
Deno.test('Cloud profile public function path normalizes to the scoped route',async()=>{
 const env=await environment(),path='/v1/momo/gateway/profile';
 const result=logicalRequest(new Request(profile.supabase_origin+'/functions/v1/collect-api'+path),'collect-api',env);
 assertEquals(result.url,profile.supabase_origin+path);
});
Deno.test('profile hashes and exact CORS bind preflight before database work',async()=>{
 const env=await environment(),handler=createHandler('admin-api',()=>env);
 const request=new Request(profile.supabase_origin+'/functions/v1/admin-api/api/admin/auth/session',{method:'OPTIONS',headers:{Origin:profile.admin_origin}});
 const allowed=await handler(request);assertEquals(allowed.status,204);assertEquals(allowed.headers.get('Access-Control-Allow-Origin'),profile.admin_origin);
 const invalid=createHandler('admin-api',()=>({...env,COLLECT_DEPLOYMENT_PROFILE_SHA256:'0'.repeat(64)}),{reportHealth:()=>false});
 assertEquals((await invalid(request)).status,503);
});
Deno.test('Storage rejects private HTTP gateways',async()=>{
 for(const url of ['http://api-gw:8000','http://kong:8000','http://169.254.169.254'])
  await assertRejects(async()=>{new SupabaseNativeTransport({url,secretKey:'sb_secret_synthetic'});});
 assertEquals(new SupabaseNativeTransport({url:profile.supabase_origin,secretKey:'sb_secret_synthetic'}).url,profile.supabase_origin);
});
