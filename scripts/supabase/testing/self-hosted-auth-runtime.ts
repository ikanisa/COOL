// Disposable local PostgreSQL + synthetic GoTrue responses. No provider send,
// deployed credential, real identity, database reset, or production acceptance.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import postgres from 'npm:postgres@3.4.7';
import {connection,fenceConnection,PostgresDatabase} from '../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork,sqlFenceBackend} from '../../../supabase/functions/_shared/application-fence.js';
import {handleAuth,requireSession} from '../../../supabase/functions/_shared/domain/auth.js';
import {verifyToken} from '../../../supabase/functions/_shared/auth-http.js';
import {installCurrentFixtureAdditions,validateCurrentFixtureDescriptor} from './self-hosted-current-schema.mjs';

const passed:string[]=[];let stage='invocation',failed:any=null;const pools:any[]=[];
const originalFetch=globalThis.fetch;let providerVerifications=0,externalCalls=0;
let currentSchema:any=null;
async function step(name:string,fn:()=>Promise<void>){stage=name;await fn();passed.push(name);}
try {
 assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');assert.equal(Deno.args.length,0);
 const path=Deno.env.get('COLLECT_GUEST_FIXTURE_DESCRIPTOR');assert(path?.startsWith('/'));
 const descriptor=JSON.parse(await readFile(path!,'utf8'));
 assert.equal(descriptor.synthetic,true);assert.equal(descriptor.public_acceptance,false);assert.equal(descriptor.purpose,'auth');
 const target=validateCurrentFixtureDescriptor(descriptor,{purpose:'auth'});
 assert.equal(target.username,'postgres');assert.match(target.pathname,/^\/collect_selfhost_auth_[a-f0-9]+_test$/);
 assert(!target.search&&!target.hash);
 const owner=postgres(descriptor.url,{max:1,prepare:false,ssl:false,onnotice:()=>{}});
 const business=connection(descriptor.url),control=fenceConnection(descriptor.url);pools.push(owner,business,control);
 const identity=(await owner`SELECT current_user,current_database(),(SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AS superuser`)[0];
 assert.equal(identity.current_user,'postgres');assert.equal(identity.superuser,false);assert.equal(identity.current_database,target.pathname.slice(1));
 const state=(await owner`SELECT private.collect_fence_owner_status_v3() AS value`)[0].value;
 assert.equal(state.mode,'open');assert.equal(state.sourceSha256,descriptor.source_sha256);
 const run=async(claims:any,fn:(env:any)=>Promise<any>)=>{
  const work=await (openApplicationWork as any)({backend:sqlFenceBackend(business,control),sourceSha256:descriptor.source_sha256,kind:'http_collect'});
  const env:any={DB:new (PostgresDatabase as any)(business,claims,work),COLLECT_FENCE_WORK:work,BUILD_SOURCE_ID:descriptor.source_sha256,
   SUPABASE_URL:'https://supabase.collect.example',SUPABASE_INTERNAL_URL:'http://api-gw:8000',SUPABASE_AUTH_ISSUER:'https://supabase.collect.example/auth/v1',
   SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_key_only',AUTH_ANONYMOUS_ENABLED:'true',AUTH_MEMBER_REGISTRATION_ENABLED:'true',AUTH_SMS_ENABLED:'true',AUTH_WHATSAPP_ENABLED:'false'};
  try{return await fn(env);}finally{await work.finish();}
 };
 await step('complete reviewed current chain applies to a fresh restricted-owner fixture',async()=>{
  currentSchema=await installCurrentFixtureAdditions(owner);
  assert.equal((await owner`SELECT relrowsecurity FROM pg_class WHERE oid='private.guest_upgrade_challenges'::regclass`)[0].relrowsecurity,true);
 });
 const users=new Map<string,any>(),tokens=new Map<string,any>(),refreshes=new Map<string,{subject:string,sid:string}>(),pending=new Map<string,any>();
 const token=(user:any,sid:string,anonymous=user.is_anonymous,expiry?:number)=>{
  const claims={sub:user.id,session_id:sid,role:'authenticated',aud:'authenticated',iss:'https://supabase.collect.example/auth/v1',
   is_anonymous:anonymous,exp:expiry??Math.floor(Date.now()/1000)+3600,iat:Math.floor(Date.now()/1000),amr:[{method:'otp',timestamp:Math.floor(Date.now()/1000)}]};
  const jwt=[{alg:'ES256'},claims].map(v=>Buffer.from(JSON.stringify(v)).toString('base64url')).join('.')+'.synthetic';
  tokens.set(jwt,claims);const refresh='synthetic-'+randomUUID();refreshes.set(refresh,{subject:user.id,sid});
  return {access_token:jwt,refresh_token:refresh,token_type:'bearer',user:{...user},expires_in:3600};
 };
 const create=async()=>{const id=randomUUID(),sid=randomUUID(),user={id,is_anonymous:true,email:null,phone:null};
  await owner`INSERT INTO auth.users(id,is_anonymous) VALUES(${id},true)`;await owner`INSERT INTO auth.sessions(id,user_id) VALUES(${sid},${id})`;
  users.set(id,user);return token(user,sid);};
 let nextVerification:'accept'|'reject'|'lost'|'lost-before'|'wrong-user'='accept',autoconfirmNext=false;
 globalThis.fetch=async(input:any,init:any={})=>{
  externalCalls++;const url=new URL(typeof input==='string'?input:input.url);
  assert.equal(url.origin,'http://api-gw:8000');assert(url.pathname.startsWith('/auth/v1/'));
  const method=init.method??'GET',body=init.body?JSON.parse(init.body):{},bearer=new Headers(init.headers).get('Authorization')?.replace(/^Bearer /,''),claims=tokens.get(bearer??'');
  const json=(body:any,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
  if(url.pathname==='/auth/v1/signup')return json(await create());
  if(url.pathname==='/auth/v1/user'&&method==='GET')return claims?json(users.get(claims.sub)):json({error_code:'invalid_session'},401);
  if(url.pathname==='/auth/v1/user'&&method==='PUT'){
   assert(claims);assert(users.get(claims.sub).is_anonymous);pending.set(claims.sub,body);
   if(autoconfirmNext){
    autoconfirmNext=false;const user=users.get(claims.sub);user.is_anonymous=false;user.email=body.email;user.email_confirmed_at=new Date().toISOString();
    await owner`UPDATE auth.users SET email=${body.email},email_confirmed_at=now(),is_anonymous=false WHERE id=${user.id}`;
   }
   return json(users.get(claims.sub));
  }
  if(url.pathname==='/auth/v1/verify'){
   providerVerifications++;assert(claims);const target=pending.get(claims.sub);assert(target);
   assert.equal(body.type,target.email?'email_change':'phone_change');assert.equal(body[target.email?'email':'phone'],target.email??target.phone);
   if(nextVerification==='reject'){nextVerification='accept';return json({error_code:'otp_expired'},403);}
   if(nextVerification==='lost-before'){nextVerification='accept';throw Error('synthetic_lost_before_provider_commit');}
   const user=users.get(claims.sub);user.is_anonymous=false;
   if(target.email){user.email=target.email;user.email_confirmed_at=new Date().toISOString();
    await owner`UPDATE auth.users SET email=${target.email},email_confirmed_at=now(),is_anonymous=false WHERE id=${user.id}`;}
   else{user.phone=target.phone.replace(/^\+/,'');user.phone_confirmed_at=new Date().toISOString();
    await owner`UPDATE auth.users SET phone=${user.phone},phone_confirmed_at=now(),is_anonymous=false WHERE id=${user.id}`;}
   const sid=randomUUID();await owner`INSERT INTO auth.sessions(id,user_id) VALUES(${sid},${user.id})`;
   const result=token(user,sid),mode=nextVerification;nextVerification='accept';
   if(mode==='lost')throw Error('synthetic_lost_provider_reply');
   if(mode==='wrong-user')return json(await create());
   return json(result);
  }
  if(url.pathname==='/auth/v1/token'){
   const retained=refreshes.get(body.refresh_token);assert(retained);const user=users.get(retained!.subject);
   return json(token(user,retained!.sid));
  }
  if(url.pathname==='/auth/v1/logout')return new Response(null,{status:204});
  throw Error('unreviewed_provider_request');
 };
 const call=async(route:string,body:any={},bearer?:string)=>run({},async env=>{
  const response=await handleAuth(new Request('https://api.collect.example/v1/auth/'+route,{method:'POST',headers:{'Content-Type':'application/json',...(bearer?{Authorization:'Bearer '+bearer}:{})},body:JSON.stringify(body)}),env);
  assert(response);return response!.json();
 });
 const signup=()=>call('anonymous',{surface:'member',captcha_token:'synthetic'});
 const begin=(session:any,identity:any)=>call('upgrade/otp',{surface:'member',...identity,captcha_token:'synthetic'},session.access_token);
 const verify=(session:any,challenge:any)=>call('upgrade/verify',{surface:'member',challenge_id:challenge.challenge_id,code:'123456',captcha_token:'synthetic'},session.access_token);
 const mapped=async(subject:string)=>(await owner`SELECT count(*)::int AS n FROM private.auth_principal_links WHERE auth_user_id=${subject}`)[0].n;
 await step('trusted guest identity has no principal and is denied business and Admin authority',async()=>{
  const guest=await signup();assert.equal(guest.user.id,guest.user.auth_user_id);assert.equal(guest.user.is_anonymous,true);assert.equal(await mapped(guest.user.id),0);
  await run({},async env=>{await assert.rejects(()=>requireSession(new Request('https://api.collect.example/v1/rpc/create_collection',{headers:{Authorization:'Bearer '+guest.access_token}}),env),(error:any)=>error.code==='verified_identity_required');
   const verified=await verifyToken(env,guest.access_token,{allowAnonymous:true});env.DB.setClaims(verified.claims);
   assert.equal((await env.DB.prepare('SELECT private.is_managed_session(?::uuid,?::uuid) AS allowed').bind(guest.user.id,verified.claims.session_id).first()).allowed,false);});
  await run({},async env=>{env.AUTH_ANONYMOUS_ENABLED='false';await assert.rejects(()=>handleAuth(new Request('https://api.collect.example/v1/auth/anonymous',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({surface:'member',captcha_token:'synthetic'})}),env),(error:any)=>error.code==='anonymous_unavailable');});
 });
 await step('email upgrade verifies same Auth UUID before one durable business mapping',async()=>{
  const guest=await signup(),challenge=await begin(guest,{email:'guest-'+randomUUID()+'@example.test'});
  assert.equal(await mapped(guest.user.id),0);const session=await verify(guest,challenge);
  assert.equal(session.user.auth_user_id,guest.user.id);assert.notEqual(session.user.id,guest.user.id);assert.equal(session.user.is_anonymous,false);assert.equal(await mapped(guest.user.id),1);
  const state=(await owner`SELECT verification_state FROM private.guest_upgrade_challenges WHERE id=${challenge.challenge_id}`)[0];assert.equal(state.verification_state,'verified');
  await assert.rejects(()=>verify(guest,challenge));assert.equal(await mapped(guest.user.id),1);
 });
 await step('SMS and WhatsApp have separate availability and same-identity verification',async()=>{
  const guest=await signup();await assert.rejects(()=>begin(guest,{phone:'+250788123459',channel:'whatsapp'}),(error:any)=>error.code==='whatsapp_unavailable');
  const phone='+25078'+String(Math.floor(Math.random()*10000000)).padStart(7,'0'),challenge=await begin(guest,{phone,channel:'sms'});
  assert.equal(challenge.channel,'sms');const session=await verify(guest,challenge);assert.equal(session.user.auth_user_id,guest.user.id);
 });
 await step('collision is rejected without provider mutation or automatic account merge',async()=>{
  const managed=randomUUID(),email='existing-'+randomUUID()+'@example.test';await owner`INSERT INTO auth.users(id,email,is_anonymous,email_confirmed_at) VALUES(${managed},${email},false,now())`;
  const guest=await signup(),before=externalCalls;
  await assert.rejects(()=>begin(guest,{email}),(error:any)=>error.code==='identity_already_exists');
  assert.equal(externalCalls,before+1);assert.equal(await mapped(guest.user.id),0);
 });
 await step('provider rejection is explicitly retryable but verification uncertainty cannot replay',async()=>{
  const guest=await signup(),challenge=await begin(guest,{email:'lost-'+randomUUID()+'@example.test'});
  nextVerification='reject';await assert.rejects(()=>verify(guest,challenge),(error:any)=>error.code==='guest_otp_rejected');
  nextVerification='lost';await assert.rejects(()=>verify(guest,challenge),(error:any)=>error.code==='guest_upgrade_unknown');
  assert.equal(await mapped(guest.user.id),0);const before=providerVerifications;
  await assert.rejects(()=>verify(guest,challenge));assert.equal(providerVerifications,before);
  const sid=tokens.get(guest.access_token).session_id,expired=token(users.get(guest.user.id),sid,true,1);
  const converted=token(users.get(guest.user.id),sid,false);
  await run({},async env=>{
   env.AUTH_ANONYMOUS_ENABLED='false';
   await assert.rejects(()=>requireSession(new Request('https://api.collect.example/v1/rpc/create_collection',{headers:{Authorization:'Bearer '+converted.access_token}}),env),(error:any)=>error.code==='access_revoked');
  });
  const result=await call('upgrade/reconcile',{challenge_id:challenge.challenge_id,refresh_token:guest.refresh_token},expired.access_token);
  assert.equal(result.user.auth_user_id,guest.user.id);assert.equal(await mapped(guest.user.id),1);assert.equal(providerVerifications,before);
 });
 await step('unconverted unknown recovery retains a refreshed credential with no principal or code replay',async()=>{
  const guest=await signup(),challenge=await begin(guest,{email:'pending-'+randomUUID()+'@example.test'});
  nextVerification='lost-before';await assert.rejects(()=>verify(guest,challenge),(error:any)=>error.code==='guest_upgrade_unknown');
  const before=providerVerifications,result=await call('upgrade/reconcile',{challenge_id:challenge.challenge_id,refresh_token:guest.refresh_token});
  assert.equal(result.upgrade_status,'unconfirmed');assert.equal(result.auth_user_id,guest.user.id);assert.equal(result.initiating_session_id,tokens.get(guest.access_token).session_id);
  assert.notEqual(result.recovery_refresh_token,guest.refresh_token);assert.equal(await mapped(guest.user.id),0);
  await assert.rejects(()=>verify(guest,challenge));assert.equal(providerVerifications,before);
  const foreign=await signup();await assert.rejects(()=>call('upgrade/reconcile',{challenge_id:challenge.challenge_id,refresh_token:foreign.refresh_token},guest.access_token),(error:any)=>error.code==='guest_challenge_required');
  const anotherSid=randomUUID();await owner`INSERT INTO auth.sessions(id,user_id) VALUES(${anotherSid},${guest.user.id})`;
  const sameUserOtherSession=token(users.get(guest.user.id),anotherSid);
  await assert.rejects(()=>call('upgrade/reconcile',{challenge_id:challenge.challenge_id,refresh_token:sameUserOtherSession.refresh_token},guest.access_token),(error:any)=>error.code==='guest_challenge_required');
 });
 await step('concurrent verification admits only one provider operation and one principal',async()=>{
  const guest=await signup(),challenge=await begin(guest,{email:'concurrent-'+randomUUID()+'@example.test'}),before=providerVerifications;
  const outcomes=await Promise.allSettled([verify(guest,challenge),verify(guest,challenge)]);
  assert.equal(outcomes.filter(result=>result.status==='fulfilled').length,1);assert.equal(providerVerifications,before+1);assert.equal(await mapped(guest.user.id),1);
 });
 await step('provider autoconfirm and forged anonymous parity cannot grant application authority',async()=>{
  const guest=await signup();autoconfirmNext=true;const challenge=await begin(guest,{email:'autoconfirm-'+randomUUID()+'@example.test'});
  assert.equal(challenge.delivery_status,'unknown');const sid=tokens.get(guest.access_token).session_id,fresh=token(users.get(guest.user.id),sid,false);
  await run({},async env=>{env.AUTH_ANONYMOUS_ENABLED='false';await assert.rejects(()=>requireSession(new Request('https://api.collect.example/v1/rpc/create_collection',{headers:{Authorization:'Bearer '+fresh.access_token}}),env),(error:any)=>error.code==='access_revoked');});
  assert.equal(await mapped(guest.user.id),0);
  const another=await signup(),forged=token(users.get(another.user.id),tokens.get(another.access_token).session_id,false);
  await run({},async env=>{await assert.rejects(()=>verifyToken(env,forged.access_token,{allowAnonymous:true}),(error:any)=>error.code==='invalid_session');});
 });
 await step('foreign guest session and native client roles cannot read or mutate the journal',async()=>{
  const a=await signup(),b=await signup(),challenge=await begin(a,{email:'bound-'+randomUUID()+'@example.test'}),before=providerVerifications;
  await assert.rejects(()=>verify(b,challenge),(error:any)=>error.code==='guest_challenge_required');assert.equal(providerVerifications,before);
  for(const role of ['anon','authenticated','service_role','collect_runtime','collect_importer'])assert.equal((await owner`SELECT has_table_privilege(${role},'private.guest_upgrade_challenges','SELECT,INSERT,UPDATE,DELETE,TRUNCATE') AS value`)[0].value,false);
  for(const role of ['anon','authenticated','service_role','collect_importer'])assert.equal((await owner`SELECT has_function_privilege(${role},'private.guest_upgrade_finish(uuid,uuid)','EXECUTE') AS value`)[0].value,false);
 });
}catch(error){failed=error;}
finally{globalThis.fetch=originalFetch;for(const pool of pools.reverse())try{await pool.end();}catch{}}
console.log(JSON.stringify({format:'collect.selfhost.auth.native.v2',status:failed?'fail':'pass',stage,passed,current_schema:currentSchema,providerVerifications,syntheticProviderCalls:externalCalls,realProviderCalls:0,productionAcceptance:false,...(failed?{failure:failed.code??failed.name,message:String(failed.message).slice(0,240)}:{})},null,2));
if(failed)Deno.exit(1);
