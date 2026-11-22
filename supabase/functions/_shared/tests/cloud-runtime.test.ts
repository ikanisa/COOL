// Actual Cloud transport constructors with synthetic HTTP and admission.
import {assertEquals,assertThrows} from 'jsr:@std/assert@1.0.14';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN} from '../deployment-profile.js';
import {normalizeRuntimeEnv} from '../runtime-env.js';
import {SupabaseNativeTransport} from '../storage/supabase-transport.js';
import {SupabaseObjectBucket} from '../adapters.js';
import {authRequest} from '../auth-http.js';
import {fencedTest,fixtureEnvironment} from './helpers/fenced-unit.js';

const profile={format:'collect.deployment.v1',id:'cloud-runtime-fixture',mode:'managed',environment:'qualification',
 supabase_origin:MANAGED_SUPABASE_ORIGIN,member_api_origin:'https://api.fixture.example',
 admin_origin:'https://admin.fixture.example',public_origin:'https://fixture.example',google_callback_origin:'https://admin.fixture.example'};
async function environment(){
 const raw=canonicalProfile(profile),digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw));
 return {COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:Array.from(new Uint8Array(digest),v=>v.toString(16).padStart(2,'0')).join(''),
  APP_ENVIRONMENT:'qualification',SUPABASE_URL:profile.supabase_origin,
  COLLECT_DATABASE_URL:'postgres://postgres:synthetic-password@db.rrlduytparvsjfmegalh.supabase.co:5432/postgres',
  SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_fixture',SUPABASE_SECRET_KEY:'sb_secret_synthetic_fixture'};
}
Deno.test('the Cloud project owns the Storage namespace, transport and Auth issuer',async()=>{
 const env=normalizeRuntimeEnv(await environment());
 assertEquals(env.SUPABASE_AUTH_ISSUER,profile.supabase_origin+'/auth/v1');
 const bucket=new SupabaseObjectBucket({...env,DB:{}});
 assertEquals(bucket.namespace,{origin:profile.supabase_origin,bucket:'collect-evidence'});
 assertEquals(bucket.transport.url,profile.supabase_origin);
});
Deno.test('runtime refuses a different project, private route or nonproject database',async()=>{
 const env=await environment();
 for(const internal of ['http://private-api:8000','http://127.0.0.1:55101',profile.supabase_origin])
  assertThrows(()=>normalizeRuntimeEnv({...env,SUPABASE_INTERNAL_URL:internal}));
 assertThrows(()=>normalizeRuntimeEnv({...env,SUPABASE_URL:'https://other.supabase.co'}));
 assertThrows(()=>normalizeRuntimeEnv({...env,COLLECT_DATABASE_URL:'postgres://fixture:synthetic@db:5432/postgres'}));
 for(const url of ['http://private-api:8000','http://127.0.0.1:55101'])
  assertThrows(()=>new SupabaseNativeTransport({url,secretKey:'synthetic-key'}));
});
fencedTest('Auth uses fixed Cloud HTTPS, existing opaque API key and user bearer',async()=>{
 const env=fixtureEnvironment(normalizeRuntimeEnv(await environment())),previous=globalThis.fetch,calls:unknown[][]=[];
 globalThis.fetch=async(input,options)=>{calls.push([input,options]);return Response.json({id:'synthetic-existing-user'});};
 try{
  assertEquals(await authRequest(env,'/user',{method:'GET',token:'synthetic-existing-user-bearer'}),{id:'synthetic-existing-user'});
  assertEquals(calls.length,1);assertEquals(calls[0][0],profile.supabase_origin+'/auth/v1/user');
  const options=calls[0][1] as RequestInit;
  assertEquals(options.redirect,'error');
  assertEquals(new Headers(options.headers).get('apikey'),env.SUPABASE_PUBLISHABLE_KEY);
  assertEquals(new Headers(options.headers).get('Authorization'),'Bearer synthetic-existing-user-bearer');
 }finally{globalThis.fetch=previous;}
});
