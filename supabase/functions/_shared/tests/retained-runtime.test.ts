// Actual transport constructors/normalization; synthetic HTTP + fence only.
// No Docker, database connection, provider or retained credential is used.
import {assertEquals,assertThrows} from 'jsr:@std/assert@1.0.14';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN} from '../deployment-profile.js';
import {normalizeRuntimeEnv} from '../runtime-env.js';
import {SupabaseNativeTransport} from '../storage/supabase-transport.js';
import {SupabaseObjectBucket} from '../adapters.js';
import {authRequest} from '../auth-http.js';
import {fencedTest,fixtureEnvironment} from './helpers/fenced-unit.js';

const profile={format:'collect.deployment.v1',id:'retained-fixture',mode:'self_hosted',environment:'qualification',
 supabase_origin:'https://supabase.retained.example',member_api_origin:'https://api.retained.example',
 admin_origin:'https://admin.retained.example',public_origin:'https://retained.example',google_callback_origin:'https://admin.retained.example'};
async function environment(mode='self_hosted'){
 const selected=mode==='self_hosted'?profile:{...profile,mode:'managed',supabase_origin:MANAGED_SUPABASE_ORIGIN};
 const raw=canonicalProfile(selected),digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw));
 return {COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:Array.from(new Uint8Array(digest),v=>v.toString(16).padStart(2,'0')).join(''),
  APP_ENVIRONMENT:'qualification',SUPABASE_URL:selected.supabase_origin,
  COLLECT_DATABASE_URL:mode==='self_hosted'?'postgres://collect_edge:synthetic-password@db:5432/postgres':'postgres://postgres:synthetic-password@db.rrlduytparvsjfmegalh.supabase.co:5432/postgres',
  COLLECT_DB_CA_PEM:'-----BEGIN CERTIFICATE-----\nQQ==\n-----END CERTIFICATE-----',
  SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_retained',SUPABASE_SECRET_KEY:'sb_secret_synthetic_retained',
  SUPABASE_INTERNAL_URL:'http://kong:8000'};
}
Deno.test('retained Kong is private transport while Storage namespace and Auth issuer stay public',async()=>{
 const env=normalizeRuntimeEnv(await environment());
 assertEquals(env.SUPABASE_INTERNAL_URL,'http://kong:8000');
 assertEquals(env.SUPABASE_AUTH_ISSUER,profile.supabase_origin+'/auth/v1');
 const bucket=new SupabaseObjectBucket({...env,DB:{}});
 assertEquals(bucket.namespace,{origin:profile.supabase_origin,bucket:'collect-evidence'});
 assertEquals(bucket.transport.url,'http://kong:8000');
});
Deno.test('retained exception keeps exact host/port/profile and database TLS boundaries',async()=>{
 const env=await environment();
 for(const internal of ['http://api-gw:8000','http://kong:8000',profile.supabase_origin])
  assertEquals(normalizeRuntimeEnv({...env,SUPABASE_INTERNAL_URL:internal}).SUPABASE_INTERNAL_URL,internal);
 for(const internal of ['http://kong:8001','https://kong:8000','http://kong:8000/','http://kong.evil:8000',
  'http://user@kong:8000','http://api.supabase.internal:8000','http://127.0.0.1:55101','http://169.254.169.254'])
  assertThrows(()=>normalizeRuntimeEnv({...env,SUPABASE_INTERNAL_URL:internal}));
 assertThrows(()=>normalizeRuntimeEnv({...env,COLLECT_DB_CA_PEM:undefined}));
 assertThrows(()=>normalizeRuntimeEnv({...env,COLLECT_DATABASE_URL:'postgres://collect_edge:synthetic@supabase_db_local-app:5432/postgres'}));
 const hosted=await environment('managed');
 assertThrows(()=>normalizeRuntimeEnv(hosted));
 assertThrows(()=>new SupabaseObjectBucket({...hosted,DB:{}}));
 for(const url of ['http://kong:8000','http://api-gw:8000'])assertThrows(()=>new SupabaseNativeTransport({url,secretKey:'synthetic-key'}));
 for(const url of ['http://kong:8001','http://kong.evil:8000','http://kong:8000/path','http://kong:8000/?redirect=other'])
  assertThrows(()=>new SupabaseNativeTransport({url,secretKey:'synthetic-key',allowPrivateGateway:true}));
});
fencedTest('actual Auth request uses fixed retained Kong, existing opaque API key and user bearer',async()=>{
 const env=fixtureEnvironment(normalizeRuntimeEnv(await environment())),previous=globalThis.fetch,calls:unknown[][]=[];
 globalThis.fetch=async(input,options)=>{calls.push([input,options]);return Response.json({id:'synthetic-existing-user'});};
 try{
  assertEquals(await authRequest(env,'/user',{method:'GET',token:'synthetic-existing-user-bearer'}),{id:'synthetic-existing-user'});
  assertEquals(calls.length,1);assertEquals(calls[0][0],'http://kong:8000/auth/v1/user');
  const options=calls[0][1] as RequestInit;
  assertEquals(options.redirect,'error');
  assertEquals(new Headers(options.headers).get('apikey'),env.SUPABASE_PUBLISHABLE_KEY);
  assertEquals(new Headers(options.headers).get('Authorization'),'Bearer synthetic-existing-user-bearer');
 }finally{globalThis.fetch=previous;}
});
