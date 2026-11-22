import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN,resolveDeploymentProfile,verifyDeploymentProfile,validateDeploymentProfile} from '../../supabase/functions/_shared/deployment-profile.js';
import {COLLECT_PROJECT_REF,normalizeRuntimeEnv,configurePublicRuntimeEnv,isGoogleProviderNavigation} from '../../supabase/functions/_shared/runtime-env.js';

const profile={format:'collect.deployment.v1',id:'collect-cloud',mode:'managed',environment:'production',
 supabase_origin:MANAGED_SUPABASE_ORIGIN,member_api_origin:'https://api.collect.example',
 admin_origin:'https://admin.collect.example',public_origin:'https://collect.example',google_callback_origin:'https://api.collect.example'};
const bound=value=>({COLLECT_DEPLOYMENT_PROFILE:canonicalProfile(value),COLLECT_DEPLOYMENT_PROFILE_SHA256:createHash('sha256').update(canonicalProfile(value)).digest('hex')});
const runtime=()=>({...bound(profile),APP_ENVIRONMENT:'production',SUPABASE_URL:profile.supabase_origin,
 COLLECT_DATABASE_URL:'postgres://postgres:synthetic-only@db.'+COLLECT_PROJECT_REF+'.supabase.co:5432/postgres',
 SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic',SUPABASE_SECRET_KEY:'sb_secret_synthetic'});

test('JavaScript and Python agree on the managed Cloud identity',async()=>{
 const env=bound(profile);assert.deepEqual(await verifyDeploymentProfile(env),profile);
 const result=execFileSync('python3',['-c',"import json,sys;from scripts.supabase.deployment_profile import resolve_profile,canonical_profile,profile_sha256;p=resolve_profile(json.load(sys.stdin));print(canonical_profile(p));print(profile_sha256(p))"],{cwd:new URL('../..',import.meta.url),input:JSON.stringify(env),encoding:'utf8',timeout:15000}).trim().split('\n');
 assert.equal(result[0],env.COLLECT_DEPLOYMENT_PROFILE);assert.equal(result[1],env.COLLECT_DEPLOYMENT_PROFILE_SHA256);
});
test('both validators refuse non-managed profiles and other project origins',()=>{
 for(const invalid of [{...profile,mode:'self_hosted'},{...profile,mode:'cloudflare'},
  {...profile,supabase_origin:'https://another.example'},{...profile,google_callback_origin:'https://other.example'},
  {...profile,environment:'test'},{...profile,extra:'x'}]){
  assert.throws(()=>validateDeploymentProfile(invalid));
  assert.throws(()=>execFileSync('python3',['-c',"import json,sys;from scripts.supabase.deployment_profile import validate_profile;validate_profile(json.load(sys.stdin))"],{cwd:new URL('../..',import.meta.url),input:JSON.stringify(invalid),stdio:['pipe','pipe','pipe'],timeout:15000}));
 }
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
  {...profile,supabase_origin:'https://other.supabase.co'},{...profile,mode:'self_hosted'}])assert.throws(()=>validateDeploymentProfile(invalid));
});
test('Cloud runtime binds the issuer, database and configured application origins',()=>{
 const env=normalizeRuntimeEnv(runtime());assert.equal(env.SUPABASE_AUTH_ISSUER,profile.supabase_origin+'/auth/v1');
 assert.equal(env.SUPABASE_URL,MANAGED_SUPABASE_ORIGIN);assert.equal(env.ADMIN_ORIGIN,profile.admin_origin);
 assert.deepEqual(new Set(env.ALLOWED_ORIGINS.split(',')),new Set([profile.admin_origin,profile.member_api_origin,profile.public_origin]));
 for(const patch of [{SUPABASE_URL:'https://wrong.example'},{SUPABASE_AUTH_ISSUER:'https://elsewhere.example/auth/v1'},
  {SUPABASE_INTERNAL_URL:'http://other:8000'},{SUPABASE_INTERNAL_URL:MANAGED_SUPABASE_ORIGIN},
  {COLLECT_DATABASE_URL:'postgres://postgres:synthetic@db:5432/postgres'},
  {COLLECT_DATABASE_URL:'postgres://collect_edge:synthetic@external.example:5432/postgres'},
  {COLLECT_DATABASE_URL:'postgres://collect_edge:synthetic@db:5432/postgres?sslmode=disable'},
  {ADMIN_ORIGINS:profile.admin_origin+',https://other.example'},
  {ALLOWED_ORIGINS:'*'},{APP_ENVIRONMENT:'qualification'},{AUTH_SMS_ENABLED:'yes'}])assert.throws(()=>normalizeRuntimeEnv({...runtime(),...patch}));
});
test('public preflight configuration and Google navigation retain exact Cloud profile origins',()=>{
 const env=configurePublicRuntimeEnv({...bound(profile),APP_ENVIRONMENT:'production'});
 const request=new Request(profile.member_api_origin+'/v1/auth/google/callback',{headers:{Origin:profile.supabase_origin,'Sec-Fetch-Mode':'navigate','Sec-Fetch-Dest':'document'}});
 assert.equal(isGoogleProviderNavigation(request),true);
 for(const [path,method,mode] of [['/v1/auth/google/exchange','GET','navigate'],['/v1/auth/google/callback','POST','navigate'],['/v1/auth/google/callback','GET','cors']]){
  assert.equal(isGoogleProviderNavigation(new Request(profile.member_api_origin+path,{method,headers:{Origin:profile.supabase_origin,'Sec-Fetch-Mode':mode,'Sec-Fetch-Dest':'document'}})),false);
 }
 assert.throws(()=>configurePublicRuntimeEnv({...bound(profile),APP_ENVIRONMENT:'production',ADMIN_ORIGIN:'https://other.example'}));
});
