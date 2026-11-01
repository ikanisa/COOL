import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {canonicalProfile,resolveDeploymentProfile,verifyDeploymentProfile,validateDeploymentProfile} from '../../supabase/functions/_shared/deployment-profile.js';
import {normalizeRuntimeEnv,configurePublicRuntimeEnv,isGoogleProviderNavigation} from '../../supabase/functions/_shared/runtime-env.js';

const profile={format:'collect.deployment.v1',id:'collect-local',mode:'self_hosted',environment:'production',
 supabase_origin:'https://supabase.collect.example',member_api_origin:'https://api.collect.example',
 admin_origin:'https://admin.collect.example',public_origin:'https://collect.example',google_callback_origin:'https://api.collect.example'};
const bound=value=>({COLLECT_DEPLOYMENT_PROFILE:canonicalProfile(value),COLLECT_DEPLOYMENT_PROFILE_SHA256:createHash('sha256').update(canonicalProfile(value)).digest('hex')});
const runtime=()=>({...bound(profile),APP_ENVIRONMENT:'production',SUPABASE_URL:profile.supabase_origin,SUPABASE_INTERNAL_URL:'http://api-gw:8000',
 COLLECT_DATABASE_URL:'postgres://collect_edge:synthetic-only@db:5432/postgres',COLLECT_DB_CA_PEM:'-----BEGIN CERTIFICATE-----\nAA==\n-----END CERTIFICATE-----',
 SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic',SUPABASE_SECRET_KEY:'sb_secret_synthetic'});

test('all release runtimes agree on the canonical public identity',async()=>{
 const env=bound(profile);assert.deepEqual(await verifyDeploymentProfile(env),profile);
 const result=execFileSync('python3',['-c',"import json,sys;from scripts.supabase.deployment_profile import resolve_profile,canonical_profile,profile_sha256;p=resolve_profile(json.load(sys.stdin));print(canonical_profile(p));print(profile_sha256(p))"],{cwd:new URL('../..',import.meta.url),input:JSON.stringify(env),encoding:'utf8',timeout:15000}).trim().split('\n');
 assert.equal(result[0],env.COLLECT_DEPLOYMENT_PROFILE);assert.equal(result[1],env.COLLECT_DEPLOYMENT_PROFILE_SHA256);
});
test('wrong digest, duplicate fields and noncanonical JSON refuse configuration',async()=>{
 await assert.rejects(verifyDeploymentProfile({...bound(profile),COLLECT_DEPLOYMENT_PROFILE_SHA256:'0'.repeat(64)}),/SHA256 mismatch/);
 const env=bound(profile);
 for(const raw of [JSON.stringify(profile),JSON.stringify(profile,null,2),env.COLLECT_DEPLOYMENT_PROFILE.replace('{','{"id":"injected",')]){
  assert.throws(()=>resolveDeploymentProfile({...env,COLLECT_DEPLOYMENT_PROFILE:raw}),/canonical/);
 }
 for(const invalid of [{...profile,extra:'x'},{...profile,mode:'cloudflare'},{...profile,environment:'test'},
  {...profile,google_callback_origin:'https://other.example'},{...profile,supabase_origin:'http://supabase.collect.example'},
  {...profile,supabase_origin:'https://127.0.0.1'},{...profile,supabase_origin:'https://999.999.999.999'},
  {...profile,supabase_origin:'https://SUPABASE.collect.example'},{...profile,supabase_origin:'https://supabase.collect.example:443'},
  {...profile,supabase_origin:'https://name:password@supabase.collect.example'},{...profile,supabase_origin:'https://supabase.collect.example/path'},
  {...profile,mode:'managed'}])assert.throws(()=>validateDeploymentProfile(invalid));
});
test('self-hosted runtime keeps issuer public and services private with verified database TLS',()=>{
 const env=normalizeRuntimeEnv(runtime());assert.equal(env.SUPABASE_AUTH_ISSUER,profile.supabase_origin+'/auth/v1');
 assert.equal(env.SUPABASE_INTERNAL_URL,'http://api-gw:8000');assert.equal(env.ADMIN_ORIGIN,profile.admin_origin);
 assert.deepEqual(new Set(env.ALLOWED_ORIGINS.split(',')),new Set([profile.admin_origin,profile.member_api_origin,profile.public_origin]));
 for(const patch of [{SUPABASE_URL:'https://wrong.example'},{SUPABASE_AUTH_ISSUER:'http://api-gw:8000/auth/v1'},
  {SUPABASE_INTERNAL_URL:'http://other:8000'},{SUPABASE_INTERNAL_URL:'http://169.254.169.254'},
  {COLLECT_DATABASE_URL:'postgres://postgres:synthetic@db:5432/postgres'},
  {COLLECT_DATABASE_URL:'postgres://collect_edge:synthetic@external.example:5432/postgres'},
  {COLLECT_DATABASE_URL:'postgres://collect_edge:synthetic@db:5432/postgres?sslmode=disable'},
  {COLLECT_DB_CA_PEM:''},{ADMIN_ORIGINS:profile.admin_origin+',https://other.example'},
  {ALLOWED_ORIGINS:'*'},{APP_ENVIRONMENT:'qualification'},{AUTH_SMS_ENABLED:'yes'}])assert.throws(()=>normalizeRuntimeEnv({...runtime(),...patch}));
});
test('public preflight configuration and Google navigation retain the exact profile origins',()=>{
 const env=configurePublicRuntimeEnv({...bound(profile),APP_ENVIRONMENT:'production'});
 const request=new Request(profile.member_api_origin+'/v1/auth/google/callback',{headers:{Origin:profile.supabase_origin,'Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'}});
 assert.equal(isGoogleProviderNavigation(request,env),true);
 for(const [path,method,mode] of [['/v1/auth/google/exchange','GET','navigate'],['/v1/auth/google/callback','POST','navigate'],['/v1/auth/google/callback','GET','cors']]){
  assert.equal(isGoogleProviderNavigation(new Request(profile.member_api_origin+path,{method,headers:{Origin:profile.supabase_origin,'Sec-Fetch-Mode':mode,'Sec-Fetch-Dest':'document'}}),env),false);
 }
 assert.throws(()=>configurePublicRuntimeEnv({...bound(profile),APP_ENVIRONMENT:'production',ADMIN_ORIGIN:'https://other.example'}));
});
