import {loadReviewedPlatformFixture} from '../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import postgres from 'npm:postgres@3.4.7';
import {PostgresDatabase as ActualPostgresDatabase} from '../postgres.js';
import {createHandler as actualCreateHandler} from '../serve.js';
import {openApplicationWork,sqlFenceBackend} from '../application-fence.js';
import {SYNTHETIC_FENCE_SOURCE,ownFixtureWork} from './helpers/fenced-unit.js';
import {initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest} from './helpers/fenced-unit.js';
import {assertEquals,assert} from 'jsr:@std/assert@1.0.14';
import {connection,PostgresDatabase,compileSql} from './helpers/fenced-postgres.js';
import {createHandler,createScheduledHandler} from './helpers/real-handler.js';
import {digest} from '../domain/core.js';
import {requireSession} from './helpers/module-domain-auth.js';
import {dispatchOperation} from './helpers/module-domain-operations.js';
import {encrypt} from './helpers/module-domain-encryption.js';
import {issueAdminSession} from './helpers/module-domain-admin_accounts.js';
import {SupabaseObjectBucket} from './helpers/module-adapters.js';
const database=Deno.env.get('COLLECT_TEST_DATABASE_URL');
fencedTest({name:'actual Edge handlers on PostgreSQL: managed identities, phone consent, private Storage, retired Staff MFA and atomic financial review',ignore:!database,sanitizeResources:false,sanitizeOps:false,fn:async()=>{
 const url=new URL(database!);assert(['127.0.0.1','localhost'].includes(url.hostname)&&(url.port==='55439'||Deno.env.get('COLLECT_CI_SYNTHETIC')==='true')&&['/collect_edge_test','/collect_edge_ci_test','/collect_edge_storage_test'].includes(url.pathname),'Only the dedicated synthetic loopback database is allowed.');
 const sql=connection(database!);await initializeSqlFixture(sql);
 const present=await sql`select to_regclass('app.users') as present`;
 if(!present[0].present){const setup=await sql.reserve();try{await setup.unsafe(await Deno.readTextFile(new URL('../../../tests/sql/00_local_auth_fixture.sql',import.meta.url)));const reviewedPlatform=await loadReviewedPlatformFixture(new URL('../../../../',import.meta.url),{includeMfaRetirementMigration:true});await reviewedPlatform.apply(text=>setup.unsafe(text));}finally{setup.release();await initializeSqlFixture(sql);}}
 // Extend only this loopback managed-Auth fixture, not a hosted schema.
 await sql.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
 async function nextPublicId(){const row=(await sql.unsafe("SELECT lpad(min(candidate)::text,6,'0') AS id FROM(SELECT 0 AS candidate UNION ALL SELECT public_id::integer+1 FROM app.users WHERE public_id<>'999999') c WHERE candidate<1000000 AND NOT EXISTS(SELECT 1 FROM app.users WHERE public_id=lpad(candidate::text,6,'0'))"))[0];return row.id;}
 const memberPublic=await nextPublicId();
 const authId=crypto.randomUUID(),principal=crypto.randomUUID(),sessionId=crypto.randomUUID(),group=crypto.randomUUID(),at=Math.floor(Date.now()/1000),phone='+250788'+memberPublic;
 await sql`insert into auth.users(id,email)values(${authId},'synthetic-edge-member@example.test')`;
 await sql`insert into auth.sessions(id,user_id,aal)values(${sessionId},${authId},'aal1')`;
 await sql`insert into app.users(id,phone,public_id,full_name,momo_number,country_code,created_at,updated_at)values(${principal},${phone},${memberPublic},'Synthetic Edge Member',${phone},'RW',${new Date().toISOString()},${new Date().toISOString()})`;
 await sql`insert into private.auth_principal_links(auth_user_id,user_id,proof_reference)values(${authId},${principal},'synthetic-local-auth-service')`;
 await sql`insert into app.collections(id,slug,creator_user_id,title,collection_type,receiver_momo_number,receiver_network,created_at,updated_at)values(${group},${'edge-'+group},${principal},'Synthetic Edge Group','ikimina','250788123491','mtn_momo',${new Date().toISOString()},${new Date().toISOString()})`;
 await sql`insert into app.memberships(id,collection_id,user_id,role,joined_at)values(${crypto.randomUUID()},${group},${principal},'owner',${new Date().toISOString()})`;
 const objects=new Map<string,Uint8Array>();let issuer='',uploadMode='normal',uploadCount=0,refreshCount=0,refreshMode='normal',phoneVerifyMode='normal',managedAuthRequests=0;const factorRequests:string[]=[];
 const claims={sub:authId,session_id:sessionId,role:'authenticated',aal:'aal1',aud:'authenticated',iat:at,exp:at+900,iss:'',amr:[{method:'otp',timestamp:at}]};let token='';const adminFixtures=new Map<string,any>(),adminTokens=new Map<string,any>();
 const server=Deno.serve({hostname:'127.0.0.1',port:0,onListen:()=>{}},async request=>{
  const path=new URL(request.url).pathname;if(path.startsWith('/auth/v1/'))managedAuthRequests++;
  if(path==='/auth/v1/user'&&request.headers.get('Authorization')==='Bearer '+token)return Response.json({id:authId,email:'synthetic-edge-member@example.test',email_confirmed_at:new Date().toISOString(),phone:phone.slice(1),phone_confirmed_at:new Date().toISOString(),app_metadata:{provider:'phone'},user_metadata:{}});
  if(path==='/storage/v1/bucket/collect-evidence')return Response.json({id:'collect-evidence',name:'collect-evidence',public:false});
  if(path==='/auth/v1/user'){const user=adminTokens.get((request.headers.get('Authorization')??'').slice(7));if(user)return Response.json(user);}
  if(path==='/auth/v1/token'&&new URL(request.url).searchParams.get('grant_type')==='refresh_token'){refreshCount++;const body=await request.json(),fixture=[...adminFixtures.values()].find(f=>f.session.refresh_token===body.refresh_token);if(!fixture)return Response.json({error_code:'invalid_refresh_token'},{status:401});if(refreshMode==='unknown')return Response.json({error_code:'synthetic-provider-unknown'},{status:503});fixture.claims={...fixture.claims,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+900};const access=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(fixture.claims))+'.synthetic-not-a-hosted-signature';adminTokens.set(access,fixture.user);fixture.session={...fixture.session,access_token:access,refresh_token:'synthetic-rotated-'+refreshCount};return Response.json(fixture.session);}
  if(path==='/auth/v1/otp'){
   const body=await request.json(),fixture=adminFixtures.get(body.email);
   if(fixture)fixture.emailReauthentication=body.create_user===false;
   return Response.json({message_id:'synthetic-no-delivery'});
  }
  if(path==='/auth/v1/verify'){const body=await request.json(),fixture=adminFixtures.get(body.email);
   if(fixture&&body.token==='111111'){
    // Model the provider's actual email OTP event in native managed rows. A
    // sensitive reauthentication receives a distinct AAL1 candidate SID and
    // must not replace the original BFF session, tokens, first factor or MFA.
    const stamp=Math.floor(Date.now()/1000),candidate=fixture.emailReauthentication?crypto.randomUUID():fixture.sessionId;
    if(fixture.emailReauthentication)await sql`insert into auth.sessions(id,user_id,aal,not_after)values(${candidate},${fixture.user.id},'aal1',to_timestamp(${stamp+900}))`;
    await sql`insert into auth.mfa_amr_claims(session_id,authentication_method,created_at,updated_at)values(${candidate},'otp',to_timestamp(${stamp}),to_timestamp(${stamp})) on conflict(session_id,authentication_method)do update set updated_at=excluded.updated_at`;
    const claims={...fixture.claims,session_id:candidate,aal:'aal1',iat:stamp,exp:stamp+900,amr:[{method:'otp',timestamp:stamp}]},access=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(claims))+'.synthetic-not-a-hosted-signature';
    adminTokens.set(access,fixture.user);
    const session={access_token:access,refresh_token:'synthetic-email-'+candidate,expires_in:900,token_type:'bearer',user:fixture.user};
    if(!fixture.emailReauthentication){fixture.claims=claims;fixture.session=session;}
    return Response.json(session);
   }
   if(body.phone===phone&&body.token==='111111'){const managedSession=crypto.randomUUID(),stamp=Math.floor(Date.now()/1000);await sql`insert into auth.sessions(id,user_id,aal)values(${managedSession},${authId},'aal1')`;const proofClaims={...claims,session_id:managedSession,iat:stamp,exp:stamp+900,amr:[{method:'otp',timestamp:stamp}]},access=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(proofClaims))+'.synthetic-not-a-hosted-signature',user={id:authId,phone:phoneVerifyMode==='wrongphone'?'250788999999':phone.slice(1),...(phoneVerifyMode==='unconfirmed'?{}:{phone_confirmed_at:new Date().toISOString()}),app_metadata:{provider:'phone'},user_metadata:{phone_verified:true}};adminTokens.set(access,user);return Response.json({access_token:access,refresh_token:'synthetic-member-'+managedSession,expires_in:900,token_type:'bearer',user});}
   return Response.json({error_code:'invalid_otp'},{status:400});}
  if(path==='/auth/v1/logout'&&request.method==='POST'){const access=(request.headers.get('Authorization')??'').slice(7),payload=JSON.parse(atob(access.split('.')[1]));await sql`delete from auth.mfa_amr_claims where session_id=${payload.session_id}`;await sql`delete from auth.sessions where id=${payload.session_id}`;return Response.json({});}
  if(path.startsWith('/auth/v1/factors')){factorRequests.push(request.method+' '+path);return Response.json({error_code:'retired_mfa_provider_transport_forbidden'},{status:500});}
  if(path.startsWith('/storage/v1/object/authenticated/')){const key=decodeURIComponent(path.split('/').slice(6).join('/'));const b=objects.get(key);return b?new Response(request.method==='HEAD'?null:new Blob([new Uint8Array(b)]),{headers:{'Content-Length':String(b.length)}}):Response.json({code:'NoSuchKey',message:'The specified key does not exist.'},{status:404});}
  if(path.startsWith('/storage/v1/object/collect-evidence/')&&request.method==='POST'){const key=decodeURIComponent(path.split('/').slice(5).join('/'));uploadCount++;if(objects.has(key))return Response.json({code:'KeyAlreadyExists'},{status:409});const bytes=new Uint8Array(await request.arrayBuffer());if(uploadMode==='404-before-store')return Response.json({code:'NoSuchBucket'},{status:404});objects.set(key,bytes);if(uploadMode==='500-after-store')return Response.json({code:'synthetic-lost-reply'},{status:500});return Response.json({Key:key});}
  if(path==='/storage/v1/object/collect-evidence'&&request.method==='DELETE'){const body=await request.json();for(const k of body.prefixes)objects.delete(k);return Response.json({});}
  return Response.json({error:'unauthorized'},{status:401});
 });
 const fixtureOrigin=`http://127.0.0.1:${(server.addr as Deno.NetAddr).port}`,nativeFetch=globalThis.fetch;issuer='https://synthetic-supabase.example';globalThis.fetch=(input,init)=>{const u=typeof input==='string'?input:input instanceof URL?input.href:input.url;return nativeFetch(u.startsWith(issuer+'/')?fixtureOrigin+u.slice(issuer.length):input,init);};claims.iss=issuer+'/auth/v1';token=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(claims))+'.synthetic-not-a-hosted-signature';
 const env:any={COLLECT_DATABASE_URL:database!,SUPABASE_URL:issuer,SUPABASE_PUBLISHABLE_KEY:'synthetic-public-key',SUPABASE_SERVICE_ROLE_KEY:'synthetic-server-key',ALLOWED_ORIGINS:'https://member.example',ADMIN_ORIGIN:'https://admin.example',DATA_KEY_ID:'synthetic-data-v1',DATA_ENCRYPTION_KEY:btoa(String.fromCharCode(...new Uint8Array(32).fill(7))),MOMO_PROCESSING_PAUSED:'true',AUTH_PHONE_ENABLED:'true',APP_ENVIRONMENT:'test',SESSION_KEY_ID:'synthetic-bff-v1',SESSION_ENCRYPTION_KEY:btoa(String.fromCharCode(...new Uint8Array(32).fill(8)))};
 const handler=createHandler('collect-api',()=>({...env}));
 async function call(path:string,body?:unknown,bearer=token,requestHandler=handler){const request=new Request('https://backend.example/functions/v1/collect-api'+path,{method:body===undefined?'GET':'POST',headers:{Origin:'https://member.example','Content-Type':'application/json',...(bearer?{Authorization:'Bearer '+bearer}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});const response=await requestHandler(request);if((response.status===500||(response.status===503&&(await response.clone().json()).code==='storage_metadata_commit_unknown'))&&/^\/v1\/(rpc|functions)\//.test(path)){const diagnostic={...env,DB:new PostgresDatabase(sql)};diagnostic.PRIVATE_MEDIA=new SupabaseObjectBucket(diagnostic);const actor=await requireSession(new Request(request.url,{headers:request.headers}),diagnostic);const parts=path.split('/');try{await dispatchOperation(parts[2]==='rpc'?'rpc':'function',parts[3],body,diagnostic,actor);}catch(error){console.error('Synthetic fixture SQL failure',path,(error as any).collectSql);throw error;}}return response;}
 try{
  let r=await call('/v1/auth/user');let b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.id,principal);assertEquals(b.auth_user_id,authId);
  r=await call('/v1/rpc/list_current_user_collections',{});b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b[0].id,group);
  r=await call('/v1/rpc/create_contribution_intent',{p_request_id:crypto.randomUUID(),p_collection_id:group,p_expected_amount_rwf:1700});b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.amount_minor,1700);
  // Confirmed profile data alone cannot replace an OTP proven by this managed
  // sign-in. No wallet registration is required for the member's SMS choice.
  await sql`update auth.users set phone=${phone.slice(1)},phone_confirmed_at=now() where id=${authId}`;await sql`update app.users set momo_number='' where id=${principal}`;
  r=await call('/v1/rpc/get_assisted_sms_consent_v1',{p_collection_id:group});b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.phone_verification_available,false);
  r=await call('/v1/auth/otp',{phone,surface:'member',channel:'whatsapp',should_create_user:false});b=await r.json();assertEquals(r.status,200,JSON.stringify(b));const phoneChallenge=b.challenge_id;
  for(const invalid of ['wrongphone','unconfirmed']){phoneVerifyMode=invalid;r=await call('/v1/auth/verify',{challenge_id:phoneChallenge,code:'111111',surface:'member'});b=await r.json();assertEquals(r.status,403,JSON.stringify(b));assertEquals(b.error?.code??b.code,'verified_identity_mismatch');assertEquals((await sql`select consumed_at from private.supabase_otp_challenges where id=${phoneChallenge}`)[0].consumed_at,null);assertEquals(Number((await sql`select count(*) as n from private.managed_phone_verifications where challenge_id=${phoneChallenge}`)[0].n),0);}
  phoneVerifyMode='normal';r=await call('/v1/auth/verify',{challenge_id:phoneChallenge,code:'111111',surface:'member'});b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.user.id,principal);assertEquals(b.user.auth_user_id,authId);const verifiedPhoneToken=b.access_token,verifiedPhoneSession=JSON.parse(atob(verifiedPhoneToken.split('.')[1])).session_id;
  r=await call('/v1/rpc/get_assisted_sms_consent_v1',{p_collection_id:group},verifiedPhoneToken);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.opt_in_available,true);
  const optIn={p_collection_id:group,p_expected_revision:0,p_expected_decision_revision:0,p_opt_in:true,p_request_id:crypto.randomUUID()};r=await call('/v1/rpc/set_assisted_sms_consent_v1',optIn,verifiedPhoneToken);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.phone_verification_challenge_id,phoneChallenge);assertEquals((await sql`select momo_number from app.users where id=${principal}`)[0].momo_number,'');
  r=await call('/v1/rpc/get_assisted_sms_consent_v1',{p_collection_id:group});b=await r.json();assertEquals(b.phone_verification_available,false);assertEquals(b.consent_effective,true);
  r=await call('/v1/rpc/set_assisted_sms_consent_v1',{...optIn,p_expected_revision:1,p_expected_decision_revision:1,p_request_id:crypto.randomUUID()});assertEquals(r.status,403);
  await sql`update app.memberships set active=0 where collection_id=${group} and user_id=${principal}`;r=await call('/v1/rpc/get_assisted_sms_consent_v1',{p_collection_id:group},verifiedPhoneToken);b=await r.json();assertEquals(b.opt_in_available,false);assertEquals(b.consent_effective,false);await sql`update app.memberships set active=1 where collection_id=${group} and user_id=${principal}`;
  await sql`update app.users set member_type='operator' where id=${principal}`;r=await call('/v1/rpc/get_assisted_sms_consent_v1',{p_collection_id:group},verifiedPhoneToken);b=await r.json();assertEquals(b.opt_in_available,false);assertEquals(b.consent_effective,false);await sql`update app.users set member_type='app' where id=${principal}`;
  await sql`update auth.users set phone_confirmed_at=NULL where id=${authId}`;r=await call('/v1/rpc/get_assisted_sms_consent_v1',{p_collection_id:group},verifiedPhoneToken);b=await r.json();assertEquals(b.opt_in_available,false);assertEquals(b.consent_effective,false);await sql`update auth.users set phone_confirmed_at=now() where id=${authId}`;
  // GoTrue deletes its session before local revocation: cleanup must still be
  // irreversible and succeed without restoring a managed identity/session.
  r=await call('/v1/auth/logout',{},verifiedPhoneToken);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals((await sql`select revoked_at from app.auth_sessions where id=${verifiedPhoneSession}`)[0].revoked_at!==null,true);assertEquals(Number((await sql`select count(*) as n from auth.sessions where id=${verifiedPhoneSession}`)[0].n),0);r=await call('/v1/auth/user',undefined,verifiedPhoneToken);assertEquals(r.status,401);
  r=await call('/v1/rpc/record_sms_access_consent',{enabled:true,build_channel:'android_sms_access',device_label:'synthetic',request_id:crypto.randomUUID()});b=await r.json();assertEquals(r.status,200,JSON.stringify(b));
  const envelope=crypto.randomUUID(),capture={client_envelope_id:envelope,raw_sender:'MTN MoMo',raw_body:'SYNTHETIC receipt only; no payment claim',received_at_device:new Date().toISOString(),completeness:'complete'};
  r=await call('/v1/functions/ingest-client-sms',capture);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.receipt.financial_effects,0);const firstAck=b;
  r=await call('/v1/functions/ingest-client-sms',capture);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b,firstAck);assertEquals(objects.size,1);
  const storedCapture=[...objects.entries()][0];objects.delete(storedCapture[0]);r=await call('/v1/functions/ingest-client-sms',capture);assertEquals(r.status,503);objects.set(storedCapture[0],storedCapture[1]);
  r=await call('/v1/functions/ingest-client-sms',{...capture,raw_body:'changed'});assertEquals(r.status,409);
  assertEquals(Number((await sql`select count(*) as n from app.ledger_entries where member_id=${principal}`)[0].n),0);
  r=await call('/v1/rpc/admin_current_user',{});assertEquals(r.status,200);assertEquals(await r.json(),null);r=await call('/v1/rpc/admin_overview',{});assertEquals(r.status,403);
  const nextSession=crypto.randomUUID();await sql`insert into auth.sessions(id,user_id,aal)values(${nextSession},${authId},'aal1')`;claims.session_id=nextSession;token=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(claims))+'.synthetic-not-a-hosted-signature';
  r=await call('/v1/rpc/record_sms_access_consent',{enabled:true,build_channel:'android_sms_access',device_label:'synthetic',request_id:crypto.randomUUID()});assertEquals(r.status,200);
  r=await call('/v1/functions/ingest-client-sms',capture);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b,firstAck);assertEquals(objects.size,1);
  // Provider failure after commit is reconciled using the original ciphertext.
  uploadMode='500-after-store';const lostCapture={...capture,client_envelope_id:crypto.randomUUID(),raw_body:'SYNTHETIC lost storage reply'};const beforeUploads=uploadCount;
  r=await call('/v1/functions/ingest-client-sms',lostCapture);assertEquals(r.status,503);uploadMode='normal';
  const reserved=await sql`select object_key,source_fingerprint,sealed_body from private.storage_payload_reservations where scope->>'ownerId'=${principal} and sealed_body is not null`;assert(reserved.length>=1);const retainedCipher=objects.get(reserved.at(-1).object_key);
  r=await call('/v1/functions/ingest-client-sms',lostCapture);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(uploadCount,beforeUploads+1);assertEquals(objects.get(reserved.at(-1).object_key),retainedCipher);
  assertEquals((await sql`select sealed_body from private.storage_payload_reservations where object_key=${reserved.at(-1).object_key}`)[0].sealed_body,null);
  // A 404 upload is never acknowledged or silently resent under a new identity.
  uploadMode='404-before-store';const absentCapture={...capture,client_envelope_id:crypto.randomUUID(),raw_body:'SYNTHETIC failed upload'};const before404=uploadCount;
  r=await call('/v1/functions/ingest-client-sms',absentCapture);assertEquals(r.status,503);uploadMode='normal';r=await call('/v1/functions/ingest-client-sms',absentCapture);assertEquals(r.status,409);assertEquals(uploadCount,before404+1);
  r=await call('/v1/functions/ingest-client-sms',{...absentCapture,raw_body:'SYNTHETIC conflicting pending request'});assertEquals(r.status,409);assertEquals(uploadCount,before404+1);
  assertEquals(Number((await sql`select count(*) as n from app.sms_receipts where owner_user_id=${principal} and client_envelope_id=${absentCapture.client_envelope_id}`)[0].n),0);
  // Invited Staff traverses the real OTP->BFF handler and exact managed timing.
  const staffAuth=crypto.randomUUID(),staffPrincipal=crypto.randomUUID(),staffAccount=crypto.randomUUID(),staffSession=crypto.randomUUID(),staffFactor=crypto.randomUUID(),extraEnrollment=crypto.randomUUID(),staffEmail='staff-'+staffAccount+'@example.test',staffAt=Math.floor(Date.now()/1000)-4;
  await sql`insert into auth.users(id,email,email_confirmed_at)values(${staffAuth},${staffEmail},now())`;await sql`insert into auth.sessions(id,user_id,aal,not_after)values(${staffSession},${staffAuth},'aal1',to_timestamp(${staffAt+7200}))`;
  await sql`insert into auth.mfa_factors(id,user_id,status)values(${staffFactor},${staffAuth},'unverified'),(${extraEnrollment},${staffAuth},'unverified')`;
  await sql`insert into app.users(id,email,public_id,full_name,member_type,created_at,updated_at)values(${staffPrincipal},NULL,${await nextPublicId()},'Synthetic Staff','operator',${new Date().toISOString()},${new Date().toISOString()})`;
  await sql`insert into app.admin_users(id,email,role,status,display_name,created_at,updated_at)values(${staffAccount},${staffEmail},'staff','invited','Synthetic Staff',${staffAt},${staffAt})`;await sql`insert into app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)values(${staffAccount},${staffPrincipal},'synthetic-fixture',${new Date().toISOString()})`;
  const staffClaims={sub:staffAuth,session_id:staffSession,role:'authenticated',aal:'aal1',aud:'authenticated',iat:staffAt,exp:staffAt+900,iss:issuer+'/auth/v1',amr:[{method:'otp',timestamp:staffAt}]},staffToken=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(staffClaims))+'.synthetic-not-a-hosted-signature',staffUser={id:staffAuth,email:staffEmail,email_confirmed_at:new Date().toISOString(),factors:[{id:staffFactor,factor_type:'totp',status:'unverified'},{id:extraEnrollment,factor_type:'totp',status:'unverified'}],app_metadata:{provider:'email'},user_metadata:{}},staffFixture={user:staffUser,claims:staffClaims,sessionId:staffSession,factor:staffFactor,session:{access_token:staffToken,refresh_token:'synthetic-admin-refresh',expires_in:900,token_type:'bearer',user:staffUser}};
  adminFixtures.set(staffEmail,staffFixture);adminTokens.set(staffToken,staffUser);
  // Actual legacy shape: canonical email is NULL, approved Admin email is separate.
  // A member-first sign-in must retain this principal without receiving Admin.
  const memberFirstSession=crypto.randomUUID();await sql`insert into auth.sessions(id,user_id,aal)values(${memberFirstSession},${staffAuth},'aal1')`;const memberFirstClaims={...staffClaims,session_id:memberFirstSession},memberFirstToken=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(memberFirstClaims))+'.synthetic-not-a-hosted-signature';adminTokens.set(memberFirstToken,staffUser);
  r=await call('/v1/auth/user',undefined,memberFirstToken);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.id,staffPrincipal);assertEquals(b.auth_user_id,staffAuth);assertEquals(b.app_metadata.permissions,[]);assertEquals((await sql`select email from app.users where id=${staffPrincipal}`)[0].email,null);assertEquals((await sql`select user_id from private.auth_principal_links where auth_user_id=${staffAuth}`)[0].user_id,staffPrincipal);
  let observedAdminError:any=null;const adminHandler=createHandler('admin-api',()=>({...env,INTERNAL_ERROR_OBSERVER:(e:any)=>{observedAdminError=e;}}));let adminCookie='',csrf='';
  async function adminCall(path:string,body?:unknown,headers:Record<string,string>={}){observedAdminError=null;const response=await adminHandler(new Request('https://backend.example/functions/v1/admin-api/api/admin'+path,{method:body===undefined?'GET':'POST',headers:{Origin:'https://admin.example','Content-Type':'application/json','X-Collect-Requested-With':'collect-admin',...(adminCookie?{Cookie:adminCookie}:{}),...headers},...(body===undefined?{}:{body:JSON.stringify(body)})}));if(response.status===503&&observedAdminError)throw observedAdminError;return response;}
  r=await adminCall('/auth/otp',{email:'unapproved@example.test'});b=await r.json();assertEquals(r.status,403);assertEquals(b.error.code,'admin_access_not_approved');assert(b.error.message.includes('Contact the super admin'));
  r=await adminCall('/auth/otp',{email:staffEmail});b=await r.json();assertEquals(r.status,200,JSON.stringify(b));const staffChallenge=b.challenge_id;
  r=await adminCall('/auth/verify',{challenge_id:staffChallenge,code:'111111'});b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.user.role,'staff');assertEquals(b.user.assuranceLevel,1);assertEquals(JSON.stringify(b).includes('access_token'),false);csrf=b.csrfToken;assert(/^[a-f0-9]{64}$/.test(csrf));adminCookie=r.headers.get('Set-Cookie')!.split(';')[0];assert(r.headers.get('Set-Cookie')!.includes('HttpOnly'));assert(r.headers.get('Set-Cookie')!.includes('Secure'));assert(r.headers.get('Set-Cookie')!.includes('SameSite=Strict'));
  const staffOtpAt=Number(staffFixture.claims.amr.find(event=>event.method==='otp')?.timestamp);assert(Number.isSafeInteger(staffOtpAt)&&staffOtpAt>0);
  const projectedAdmin=(await sql`select * from app.auth_sessions where id=${staffSession}`)[0],boundAdmin=(await sql`select * from app.admin_sessions where auth_session_id=${staffSession}`)[0];assertEquals(Number(projectedAdmin.auth_at),staffOtpAt);assertEquals(Number(boundAdmin.created_at),staffOtpAt);assertEquals(Number(boundAdmin.expires_at),Number(projectedAdmin.expires_at));assertEquals(boundAdmin.origin,'https://admin.example');assertEquals(projectedAdmin.revoked_at,null);
  const initialProof=(await sql`select p.admin_id,p.principal_id,p.auth_user_id,p.original_session_id,p.cookie_hash,p.public_session_id,p.auth_version,p.origin,p.verified_session_id,p.verified_at,s.auth_session_id as admin_session_id,s.public_id,s.token_hash as admin_token_hash,s.auth_version as admin_auth_version,b.auth_session_id as bff_session_id,o.mode,o.original_session_id as operation_original_session_id,o.verified_session_id as operation_verified_session_id,(select count(*) from app.admin_account_audit a where a.subject_id=${staffAccount} and a.action='supabase_signed_in') as sign_in_audits,(select count(*) from app.admin_account_audit a where a.subject_id=${staffAccount} and a.action='admin_initial_email_proof_recorded') as proof_audits from private.admin_sensitive_email_proofs p join private.admin_email_operations o on o.challenge_id=p.challenge_id join app.admin_sessions s on s.token_hash=p.cookie_hash join private.bff_sessions b on b.token_hash=s.token_hash where p.challenge_id=${staffChallenge}`)[0];assert(initialProof,'The first-factor email OTP must persist its initial proof before a cookie is returned.');assertEquals(initialProof.admin_id,staffAccount);assertEquals(initialProof.principal_id,staffPrincipal);assertEquals(initialProof.auth_user_id,staffAuth);assertEquals(initialProof.original_session_id,staffSession);assertEquals(initialProof.verified_session_id,staffSession);assertEquals(Number(initialProof.verified_at),staffOtpAt);assertEquals(initialProof.admin_session_id,staffSession);assertEquals(initialProof.bff_session_id,staffSession);assertEquals(initialProof.cookie_hash,initialProof.admin_token_hash);assertEquals(initialProof.public_session_id,initialProof.public_id);assertEquals(Number(initialProof.auth_version),Number(initialProof.admin_auth_version));assertEquals(initialProof.origin,'https://admin.example');assertEquals(initialProof.mode,'initial');assertEquals(initialProof.operation_original_session_id,staffSession);assertEquals(initialProof.operation_verified_session_id,staffSession);assertEquals(Number(initialProof.sign_in_audits),1);assertEquals(Number(initialProof.proof_audits),1);
  async function prepareExpiredInitialProof(label:string,eventAgeSeconds:number){
   const email=`initial-proof-${label}-${crypto.randomUUID()}@example.test`,auth=crypto.randomUUID(),principal=crypto.randomUUID(),account=crypto.randomUUID(),session=crypto.randomUUID(),challenge=crypto.randomUUID(),at=Math.floor(Date.now()/1000),eventAt=at-eventAgeSeconds,createdAt=eventAt-300,expiresAt=eventAt;
   await sql`insert into auth.users(id,email,email_confirmed_at)values(${auth},${email},now())`;
   await sql`insert into auth.sessions(id,user_id,aal,not_after)values(${session},${auth},'aal1',to_timestamp(${at+7200}))`;
   await sql`insert into app.users(id,email,public_id,full_name,member_type,created_at,updated_at)values(${principal},${email},${await nextPublicId()},'Synthetic Initial Proof','operator',${new Date().toISOString()},${new Date().toISOString()})`;
   await sql`insert into private.auth_principal_links(auth_user_id,user_id,proof_reference)values(${auth},${principal},'synthetic-initial-email-proof')`;
   await sql`insert into app.admin_users(id,email,role,status,display_name,created_at,updated_at)values(${account},${email},'staff','invited','Synthetic Initial Proof',${at},${at})`;
   await sql`insert into app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)values(${account},${principal},'synthetic-fixture',${new Date().toISOString()})`;
   await sql`insert into private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)values(${challenge},${await digest('email:'+email)},'email',${email},'admin',0,${createdAt},${expiresAt},1,${expiresAt},'accepted')`;
   await sql`insert into auth.mfa_amr_claims(session_id,authentication_method,created_at,updated_at)values(${session},'otp',to_timestamp(${eventAt}),to_timestamp(${eventAt}))`;
   const claims={sub:auth,session_id:session,role:'authenticated',aal:'aal1',aud:'authenticated',iat:at,exp:at+900,iss:issuer+'/auth/v1',amr:[{method:'otp',timestamp:eventAt}]},access=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(claims))+'.synthetic-not-a-hosted-signature',user={id:auth,email,email_confirmed_at:new Date().toISOString(),factors:[],app_metadata:{provider:'email'},user_metadata:{}},sessionData={access_token:access,refresh_token:'synthetic-initial-'+session,expires_in:900,token_type:'bearer',user};
   adminTokens.set(access,user);
   return{email,auth,principal,account,session,challenge,eventAt,createdAt,expiresAt,claims,user,sessionData};
  }
  // A consumed, already-expired challenge can be acknowledged only while its
  // signed OTP event is still within the five-minute initial-proof freshness window.
  const expiredButFresh=await prepareExpiredInitialProof('fresh',120);assert(expiredButFresh.expiresAt<Math.floor(Date.now()/1000));
  const freshInitialResponse=await issueAdminSession(new Request('https://backend.example/api/admin/auth/login',{headers:{Origin:'https://admin.example'}}),{...env,DB:new PostgresDatabase(sql)},expiredButFresh.sessionData,{emailChallengeId:expiredButFresh.challenge});
  assertEquals(freshInitialResponse.status,200);assert(freshInitialResponse.headers.get('Set-Cookie')?.includes('HttpOnly'));const freshInitialProof=(await sql`select p.original_session_id,p.verified_session_id,p.verified_at,s.auth_session_id as admin_session_id,b.auth_session_id as bff_session_id from private.admin_sensitive_email_proofs p join app.admin_sessions s on s.token_hash=p.cookie_hash join private.bff_sessions b on b.token_hash=s.token_hash where p.challenge_id=${expiredButFresh.challenge}`)[0];assert(freshInitialProof);assertEquals(freshInitialProof.original_session_id,expiredButFresh.session);assertEquals(freshInitialProof.verified_session_id,expiredButFresh.session);assertEquals(Number(freshInitialProof.verified_at),expiredButFresh.eventAt);assertEquals(freshInitialProof.admin_session_id,expiredButFresh.session);assertEquals(freshInitialProof.bff_session_id,expiredButFresh.session);
  // Stale signed OTP evidence must fail inside the same SQL batch that would
  // otherwise commit the BFF session, Admin cookie session, and sign-in audit.
  const staleInitial=await prepareExpiredInitialProof('stale',600),staleAuditBefore=Number((await sql`select count(*) as n from app.admin_account_audit where subject_id=${staleInitial.account} and action='supabase_signed_in'`)[0].n);let staleError:any=null,staleResponse:Response|null=null;
  try{staleResponse=await issueAdminSession(new Request('https://backend.example/api/admin/auth/login',{headers:{Origin:'https://admin.example'}}),{...env,DB:new PostgresDatabase(sql)},staleInitial.sessionData,{emailChallengeId:staleInitial.challenge});}catch(error){staleError=error;}
  assert(staleError,'Expired initial proof older than five minutes must be denied.');assertEquals(staleError.status,403);assertEquals(staleError.code,'admin_email_denied');assertEquals(staleResponse,null,'No response means no Set-Cookie header can escape the failed proof batch.');
  const staleRows=(await sql`select (select count(*) from app.admin_sessions where auth_session_id=${staleInitial.session}) as admin_sessions,(select count(*) from private.bff_sessions where auth_session_id=${staleInitial.session}) as bff_sessions,(select count(*) from app.admin_account_audit where subject_id=${staleInitial.account} and action='supabase_signed_in') as sign_in_audits,(select count(*) from private.admin_sensitive_email_proofs where challenge_id=${staleInitial.challenge}) as proofs,(select count(*) from private.admin_email_operations where challenge_id=${staleInitial.challenge}) as operations`)[0];assertEquals(Number(staleRows.admin_sessions),0);assertEquals(Number(staleRows.bff_sessions),0);assertEquals(Number(staleRows.sign_in_audits),staleAuditBefore);assertEquals(Number(staleRows.proofs),0);assertEquals(Number(staleRows.operations),0);
  r=await adminCall('/auth/session');b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.user.id,staffAccount);assertEquals(b.csrfToken,csrf);
  r=await adminCall('/auth/email-verification');b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.emailVerifiedAt,new Date(staffOtpAt*1000).toISOString());
  r=await call('/v1/rpc/admin_overview',{},memberFirstToken);assertEquals(r.status,403);assertEquals((await sql`select count(*) AS n from private.auth_principal_links where auth_user_id=${staffAuth}`)[0].n,1);
  r=await adminCall('/auth/change-password',{newPassword:'synthetic-do-not-use'});b=await r.json();assertEquals(r.status,403);assertEquals(b.error.code,'csrf_rejected');
  r=await adminCall('/auth/logout');assertEquals(r.status,405);r=await adminCall('/auth/session');b=await r.json();assertEquals(b.user.id,staffAccount);
  // Retirement is independent of factor ownership, freshness and the old capability.
  // It must not read managed /user, mutate factors, rotate cookies or upgrade AAL1.
  const beforeRetirement=Array.from(await sql`select to_jsonb(s) as app,to_jsonb(c) as cookie,to_jsonb(b) as bff from app.auth_sessions s join app.admin_sessions c on c.auth_session_id=s.id join private.bff_sessions b on b.token_hash=c.token_hash where s.id=${staffSession}`);
  const beforeFactors=Array.from(await sql`select id,user_id,status from auth.mfa_factors where user_id=${staffAuth} order by id`),oldCookie=adminCookie,oldCsrf=csrf,beforeRetiredProvider=managedAuthRequests;
  for(const path of ['enroll','challenge','verify','cancel-enrollment','unenroll','unknown/nested']){
   r=await adminCall('/auth/mfa/'+path,{factor_id:extraEnrollment,challenge_id:crypto.randomUUID(),code:'111111'},{'X-Collect-CSRF':csrf});b=await r.json();assertEquals(r.status,410,JSON.stringify(b));assertEquals(b.error.code,'mfa_not_available');assertEquals(r.headers.get('Set-Cookie'),null);
   assertEquals(adminCookie,oldCookie);assertEquals(csrf,oldCsrf);assertEquals(managedAuthRequests,beforeRetiredProvider);assertEquals(factorRequests,[]);
   assertEquals(Array.from(await sql`select to_jsonb(s) as app,to_jsonb(c) as cookie,to_jsonb(b) as bff from app.auth_sessions s join app.admin_sessions c on c.auth_session_id=s.id join private.bff_sessions b on b.token_hash=c.token_hash where s.id=${staffSession}`),beforeRetirement);
   assertEquals(Array.from(await sql`select id,user_id,status from auth.mfa_factors where user_id=${staffAuth} order by id`),beforeFactors);
  }
  assertEquals(Number((await sql`select count(*) as n from app.admin_account_role_capabilities where permission='auth.mfa.enroll'`)[0].n),3);
  assertEquals(Number((await sql`select count(*) as n from app.admin_grants where user_id=${staffPrincipal} and permission='auth.mfa.enroll'`)[0].n),1);
  assertEquals((await sql`select has_function_privilege('collect_runtime','private.record_mfa_projection(uuid)','EXECUTE') as allowed`)[0].allowed,false);
  r=await adminCall('/auth/session');b=await r.json();assertEquals(b.user.assuranceLevel,1);assertEquals(b.user.permissions.includes('auth.mfa.enroll'),false);
  // Privileged synthetic historical facts only: retirement must still report an
  // existing real managed AAL2 tuple truthfully during normal token refresh.
  // No MFA route, runtime projection function or cookie upgrade is exercised.
  const custodyEnv={...env,DATA_KEY_ID:env.SESSION_KEY_ID,DATA_ENCRYPTION_KEY:env.SESSION_ENCRYPTION_KEY},historicalAt=Math.floor(Date.now()/1000);
  await sql`update auth.mfa_factors set status='verified' where id=${staffFactor} and user_id=${staffAuth}`;
  await sql`update auth.sessions set aal='aal2',factor_id=${staffFactor} where id=${staffSession} and user_id=${staffAuth}`;
  await sql`insert into auth.mfa_amr_claims(session_id,authentication_method,updated_at)values(${staffSession},'totp',to_timestamp(${historicalAt})) on conflict(session_id,authentication_method)do update set updated_at=excluded.updated_at`;
  await sql`insert into app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter)values(${staffFactor},${staffPrincipal},'Historical synthetic factor','{"managed_by":"supabase"}','verified',${historicalAt},${staffSession},${historicalAt},0)`;
  await sql`insert into private.managed_mfa_proofs(session_id,user_id,factor_id,verified_at_epoch)values(${staffSession},${staffAuth},${staffFactor},${historicalAt})`;
  await sql`update app.auth_sessions set assurance_level=2,mfa_at=${historicalAt},mfa_factor_id=${staffFactor} where id=${staffSession} and user_id=${staffPrincipal}`;
  await sql`update app.admin_sessions set issued_assurance_level=2,issued_mfa_at=${historicalAt},issued_mfa_factor_id=${staffFactor} where auth_session_id=${staffSession}`;
  staffUser.factors[0].status='verified';staffFixture.claims={...staffFixture.claims,aal:'aal2',amr:[...staffFixture.claims.amr,{method:'totp',timestamp:historicalAt}]};
  const historicalAccess=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(staffFixture.claims))+'.synthetic-not-a-hosted-signature';staffFixture.session={...staffFixture.session,access_token:historicalAccess};adminTokens.set(historicalAccess,staffUser);
  const historicalCipher=await encrypt(custodyEnv,new TextEncoder().encode(JSON.stringify({access_token:historicalAccess,refresh_token:staffFixture.session.refresh_token})),`bff:${staffSession}:${staffAuth}`);await sql`update private.bff_sessions set token_ciphertext=${historicalCipher} where auth_session_id=${staffSession}`;
  const historicalRows=async()=>({
   capabilities:Array.from(await sql`select * from app.admin_account_role_capabilities order by role,permission`),
   grants:Array.from(await sql`select * from app.admin_grants where user_id=${staffPrincipal} order by permission`),
   nativeSession:Array.from(await sql`select * from auth.sessions where id=${staffSession}`),
   nativeFactors:Array.from(await sql`select * from auth.mfa_factors where user_id=${staffAuth} order by id`),
   nativeAmr:Array.from(await sql`select * from auth.mfa_amr_claims where session_id=${staffSession} order by authentication_method`),
   projectedFactors:Array.from(await sql`select * from app.auth_mfa_factors where user_id=${staffPrincipal} order by id`),
   proofs:Array.from(await sql`select * from private.managed_mfa_proofs where session_id=${staffSession}`),
   appSession:Array.from(await sql`select * from app.auth_sessions where id=${staffSession}`),
   cookie:Array.from(await sql`select * from app.admin_sessions where auth_session_id=${staffSession}`),
   bff:Array.from(await sql`select * from private.bff_sessions where auth_session_id=${staffSession}`),
   audit:Array.from(await sql`select * from app.admin_account_audit where subject_id=${staffAccount} order by id`),
  });
  const preservedHistory=await historicalRows(),retirement=await loadReviewedPlatformFixture(new URL('../../../../',import.meta.url),{includeMfaRetirementMigration:true});
  await sql.unsafe(retirement.mfaRetirement.sql);assertEquals(await historicalRows(),preservedHistory,'Reapplying retirement must preserve raw grants, native/projected factors, managed proof, sessions and audit history.');
  r=await adminCall('/auth/session');b=await r.json();assertEquals(b.user.assuranceLevel,2);assertEquals(b.user.permissions.includes('auth.mfa.enroll'),false);assertEquals(adminCookie,oldCookie);
  async function nearExpiry(){const fixture=adminFixtures.get(staffEmail)!;fixture.claims={...fixture.claims,exp:Math.floor(Date.now()/1000)+5};const access=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(fixture.claims))+'.synthetic-not-a-hosted-signature';fixture.session={...fixture.session,access_token:access};adminTokens.set(access,fixture.user);const cipher=await encrypt(custodyEnv,new TextEncoder().encode(JSON.stringify({access_token:access,refresh_token:fixture.session.refresh_token})),`bff:${fixture.sessionId}:${staffAuth}`);await sql`update private.bff_sessions set token_ciphertext=${cipher} where auth_session_id=${fixture.sessionId}`;}
  const mfaProof=(await sql`select mfa_at from app.auth_sessions where id=${staffSession}`)[0].mfa_at;await nearExpiry();const beforeRefresh=refreshCount;r=await adminCall('/auth/session');b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(refreshCount,beforeRefresh+1);assertEquals(b.user.assuranceLevel,2);assertEquals((await sql`select mfa_at from app.auth_sessions where id=${staffSession}`)[0].mfa_at,mfaProof);
  // A crashed refresh lease cannot be reclaimed to resend a possibly-rotated token.
  await nearExpiry();await sql`update private.bff_sessions set refresh_lease=${crypto.randomUUID()},refresh_lease_until=${Math.floor(Date.now()/1000)-1} where auth_session_id=${staffSession}`;const noRetry=refreshCount;r=await adminCall('/auth/session');b=await r.json();assertEquals(r.status,401);assertEquals(b.error.code,'session_refresh_recovery_required');assertEquals(refreshCount,noRetry);
  async function freshStaffSession(){const session=crypto.randomUUID(),stamp=Math.floor(Date.now()/1000)-2,fixture=adminFixtures.get(staffEmail)!;await sql`insert into auth.sessions(id,user_id,aal,not_after)values(${session},${staffAuth},'aal1',now()+interval '2 hours')`;fixture.sessionId=session;fixture.claims={...fixture.claims,session_id:session,aal:'aal1',iat:stamp,exp:stamp+900,amr:[{method:'otp',timestamp:stamp}]};const access=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(fixture.claims))+'.synthetic-not-a-hosted-signature';fixture.session={...fixture.session,access_token:access,refresh_token:'synthetic-new-'+session};adminTokens.set(access,fixture.user);const response=await issueAdminSession(new Request('https://backend.example/api/admin/auth/login',{headers:{Origin:'https://admin.example'}}),{...env,DB:new PostgresDatabase(sql)},fixture.session);assertEquals(response.status,200);const value=await response.json();adminCookie=response.headers.get('Set-Cookie')!.split(';')[0];csrf=value.csrfToken;}
  await freshStaffSession();await nearExpiry();refreshMode='unknown';const beforeUnknown=refreshCount;r=await adminCall('/auth/session');b=await r.json();assertEquals(r.status,401);assertEquals(b.error.code,'session_refresh_recovery_required');r=await adminCall('/auth/session');b=await r.json();assertEquals(b.user,null);assertEquals(refreshCount,beforeUnknown+1);refreshMode='normal';
  await freshStaffSession();const loggedOutStaffSession=adminFixtures.get(staffEmail)!.sessionId;r=await adminCall('/auth/logout',{},{'X-Collect-CSRF':csrf});b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.ok,true);assertEquals(Number((await sql`select count(*) as n from private.bff_sessions where auth_session_id=${loggedOutStaffSession}`)[0].n),0);assertEquals(Number((await sql`select count(*) as n from app.admin_sessions where auth_session_id=${loggedOutStaffSession}`)[0].n),0);assertEquals((await sql`select revoked_at from app.auth_sessions where id=${loggedOutStaffSession}`)[0].revoked_at!==null,true);r=await adminCall('/auth/session');b=await r.json();assertEquals(b.user,null);
  await freshStaffSession();r=await adminCall('/auth/session');b=await r.json();assertEquals(b.user.id,staffAccount);await sql`update app.admin_users set status='revoked',auth_version=auth_version+1 where id=${staffAccount}`;r=await adminCall('/auth/session');b=await r.json();assertEquals(b.user,null);

  // The actual source financial handlers must retain two-person review,
  // atomic notification/snapshot/ledger writes and idempotent reversal.
  async function financialAdmin(index:number){const auth=crypto.randomUUID(),actor=crypto.randomUUID(),account=crypto.randomUUID(),session=crypto.randomUUID(),factor=crypto.randomUUID(),email='financial-'+account+'@example.test',stamp=Math.floor(Date.now()/1000)-3;
   await sql`insert into auth.users(id,email,email_confirmed_at)values(${auth},${email},now())`;await sql`insert into auth.sessions(id,user_id,aal,not_after)values(${session},${auth},'aal1',now()+interval '2 hours')`;await sql`insert into auth.mfa_factors(id,user_id,status)values(${factor},${auth},'unverified')`;
   await sql`insert into app.users(id,email,public_id,full_name,member_type,created_at,updated_at)values(${actor},${email},${await nextPublicId()},'Synthetic Financial Reviewer','operator',${new Date().toISOString()},${new Date().toISOString()})`;await sql`insert into private.auth_principal_links(auth_user_id,user_id,proof_reference)values(${auth},${actor},'synthetic-financial-auth')`;
   await sql`insert into app.admin_users(id,email,role,status,display_name,created_at,updated_at)values(${account},${email},'admin','invited','Synthetic Financial Reviewer',${stamp},${stamp})`;await sql`insert into app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)values(${account},${actor},'synthetic-fixture',${new Date().toISOString()})`;
   const claims={sub:auth,session_id:session,role:'authenticated',aal:'aal1',aud:'authenticated',iat:stamp,exp:stamp+900,iss:issuer+'/auth/v1',amr:[{method:'password',timestamp:stamp}]},access=btoa(JSON.stringify({alg:'ES256',typ:'JWT'}))+'.'+btoa(JSON.stringify(claims))+'.synthetic-not-a-hosted-signature',user={id:auth,email,email_confirmed_at:new Date().toISOString(),factors:[{id:factor,factor_type:'totp',status:'unverified'}],app_metadata:{provider:'email'},user_metadata:{}},fixture={user,claims,sessionId:session,factor,session:{access_token:access,refresh_token:'synthetic-financial-'+session,expires_in:900,token_type:'bearer',user}};
   adminFixtures.set(email,fixture);adminTokens.set(access,user);const issued=await issueAdminSession(new Request('https://backend.example/api/admin/auth/login',{headers:{Origin:'https://admin.example'}}),{...env,DB:new PostgresDatabase(sql)},fixture.session),issuedBody=await issued.json();assertEquals(issued.status,200,JSON.stringify(issuedBody));adminCookie=issued.headers.get('Set-Cookie')!.split(';')[0];csrf=issuedBody.csrfToken;
   assertEquals(issuedBody.user.assuranceLevel,1);assertEquals(issuedBody.user.permissions.includes('auth.mfa.enroll'),false);
   const unchangedTuple=async()=>await digest(JSON.stringify(await sql`select to_jsonb(s) as app,to_jsonb(c) as cookie,to_jsonb(b) as bff from app.auth_sessions s join app.admin_sessions c on c.auth_session_id=s.id join private.bff_sessions b on b.token_hash=c.token_hash where s.id=${session}`));
   const tupleBeforeEmail=await unchangedTuple();
   const noEmail=await adminCall('/auth/email-verification');assertEquals(noEmail.status,200);assertEquals((await noEmail.json()).emailVerifiedAt,null,'Password and historical factor presence do not create email freshness');
   const sent=await adminCall('/auth/email/request',{},{'X-Collect-CSRF':csrf}),sentBody=await sent.json();assertEquals(sent.status,202,JSON.stringify(sentBody));
   const emailVerified=await adminCall('/auth/email/verify',{challenge_id:sentBody.challenge_id,code:'111111'},{'X-Collect-CSRF':csrf}),emailBody=await emailVerified.json();assertEquals(emailVerified.status,200,JSON.stringify(emailBody));assert(typeof emailBody.emailVerifiedAt==='string');assertEquals(await unchangedTuple(),tupleBeforeEmail,'Email verification preserves the original AAL1 BFF tuple');
   const proof=(await sql`select p.verified_session_id,exists(select 1 from auth.sessions s where s.id=p.verified_session_id)as managed_alive,exists(select 1 from app.auth_sessions s where s.id=p.verified_session_id::text)as app_projected from private.admin_sensitive_email_proofs p where p.challenge_id=${sentBody.challenge_id}`)[0];assert(proof);assert(proof.verified_session_id!==session);assertEquals(proof.managed_alive,false);assertEquals(proof.app_projected,false);
   return {...fixture,cookie:adminCookie,csrf};
  }
  // Positive financial work traverses the real cookie/CSRF/email BFF boundary.
  // Raw managed bearer access remains denied; no test actor/attestation is forged.
  async function financialCall(path:string,body:unknown,fixture:any,key:string,requestHandler=adminHandler){
   return requestHandler(new Request('https://backend.example/functions/v1/admin-api/api/admin'+path,{method:'POST',headers:{Origin:'https://admin.example','Content-Type':'application/json','X-Collect-Requested-With':'collect-admin',Cookie:fixture.cookie,'X-Collect-CSRF':fixture.csrf,'Idempotency-Key':key},body:JSON.stringify(body)}));
  }
  const proposer=await financialAdmin(1),reviewer=await financialAdmin(2),evidenceRequest=crypto.randomUUID(),evidenceBody={request_id:evidenceRequest,collection_id:group,amount_minor:1200,evidence:'SYNTHETIC retained payment evidence',reason:'Synthetic financial integration fixture',external_reference:'synthetic-ref-'+crypto.randomUUID(),observed_at:new Date().toISOString(),payer_display_name:'Synthetic payer'};
  r=await call('/v1/evidence',evidenceBody,proposer.session.access_token);b=await r.json();assertEquals(r.status,403);assertEquals(b.code??b.error?.code,'recent_email_sign_in_required');
  const evidenceInput={group_id:group,amount_rwf:evidenceBody.amount_minor,provider_reference:evidenceBody.external_reference,observed_at:evidenceBody.observed_at,evidence:evidenceBody.evidence,payer_name:evidenceBody.payer_display_name,reason:evidenceBody.reason};
  r=await financialCall('/operations/transactions',evidenceInput,proposer,evidenceRequest);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));const paymentId=b.resource_id;
  r=await financialCall('/operations/transactions',evidenceInput,proposer,evidenceRequest);b=await r.json();assertEquals(r.status,200);assertEquals(b.resource_id,paymentId);
  const proposalBody={p_request_id:crypto.randomUUID(),p_payment_id:paymentId,p_member_id:principal,p_reason:'Synthetic retained evidence attribution'};
  const memberSnapshot=(await sql`select u.revision as member_revision,m.revision as membership_revision,u.full_name,u.momo_provider,u.momo_number,u.momo_pay_code from app.users u join app.memberships m on m.user_id=u.id where u.id=${principal} and m.collection_id=${group} and m.active=1`)[0];assert(memberSnapshot);assertEquals(memberSnapshot.momo_number,'','The earlier SMS-consent case deliberately left this member without a recorded wallet number.');
  const proposalInput={member_user_id:principal,amount_rwf:1200,expected_transaction_version:1,expected_member_version:Number(memberSnapshot.member_revision),expected_membership_version:Number(memberSnapshot.membership_revision),expected_payment_identity:{display_name:memberSnapshot.full_name,momo_provider:memberSnapshot.momo_provider,momo_number:memberSnapshot.momo_number,momo_pay_code:memberSnapshot.momo_pay_code},reason:proposalBody.p_reason};
  // SMS consent remains independent of a wallet; financial attribution still
  // requires the exact nonempty recorded payment identity at current versions.
  r=await financialCall('/reconciliations/'+paymentId+'/proposals',proposalInput,proposer,crypto.randomUUID());b=await r.json();assertEquals(r.status,409,JSON.stringify(b));assertEquals(b.error?.code,'member_changed');assertEquals(b.error?.message,'The recorded payment identity changed.');assertEquals(Number((await sql`select count(*) as n from app.reconciliations where payment_id=${paymentId}`)[0].n),0);
  // Restore only this local fixture's known initial number, advancing its
  // profile revision rather than weakening any BFF identity/version precondition.
  const restoredMember=await sql`update app.users set momo_number=${phone},revision=revision+1,updated_at=${new Date().toISOString()} where id=${principal} and momo_number='' and revision=${Number(memberSnapshot.member_revision)} returning revision,momo_number`;assertEquals(restoredMember.length,1);assertEquals(restoredMember[0].momo_number,phone);assertEquals(Number(restoredMember[0].revision),Number(memberSnapshot.member_revision)+1);
  const readyMemberSnapshot=(await sql`select u.revision as member_revision,m.revision as membership_revision,u.full_name,u.momo_provider,u.momo_number,u.momo_pay_code from app.users u join app.memberships m on m.user_id=u.id where u.id=${principal} and m.collection_id=${group} and m.active=1`)[0];assert(readyMemberSnapshot);assertEquals(readyMemberSnapshot.momo_number,phone);
  const reviewedProposalInput={...proposalInput,expected_member_version:Number(readyMemberSnapshot.member_revision),expected_membership_version:Number(readyMemberSnapshot.membership_revision),expected_payment_identity:{display_name:readyMemberSnapshot.full_name,momo_provider:readyMemberSnapshot.momo_provider,momo_number:readyMemberSnapshot.momo_number,momo_pay_code:readyMemberSnapshot.momo_pay_code}};
  r=await financialCall('/reconciliations/'+paymentId+'/proposals',reviewedProposalInput,proposer,proposalBody.p_request_id);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));const proposalId=b.resource_id;
  const approval={p_request_id:crypto.randomUUID(),p_reconciliation_id:proposalId,p_reason:'Synthetic independent financial review'},approvalInput={outcome:'approved',expected_proposal_version:1,expected_transaction_version:1,reason:'Synthetic independent financial review'};r=await financialCall('/reconciliations/proposals/'+proposalId+'/reviews',approvalInput,proposer,approval.p_request_id);assertEquals(r.status,403);
  // The production base adapter is used by actual createHandler, while this
  // suite's subclass only attaches direct-domain fixture admissions. Intercept
  // the base query point so both original payment reads are genuinely observed.
  // One warm instance correctly serializes WORK through its max1 control pool.
  // These two actual handlers model two separate Edge instances, each with its
  // own real max1 control pool and genuine SQL9 admission/shared WORK lifetime;
  // business SQL, source, financial locks and every handler/domain remain real.
  const approvalPools=[0,1].map(()=>postgres(database!,{max:1,prepare:false,ssl:false,onnotice:()=>{}})),approvalWorks:any[]=[],approvalRequests:Promise<Response>[]=[];
  const approvalHandlers=approvalPools.map(control=>actualCreateHandler('admin-api',()=>({...env,BUILD_SOURCE_ID:SYNTHETIC_FENCE_SOURCE}),{
   async openWork(options:any){const work=ownFixtureWork(await openApplicationWork({...options,backend:sqlFenceBackend(sql,control)}));approvalWorks.push(work);return work;}
  }));
  // Both callers miss the retained receipt and read the pending proposal.
  // Delay the second payment read until the first approval has committed.
  const firstPaymentRead=Promise.withResolvers<void>(),bothPaymentReads=Promise.withResolvers<void>(),firstApprovalComplete=Promise.withResolvers<void>();
  const originalPrepare=ActualPostgresDatabase.prototype.prepare;let paymentReads=0,barrierExpired=false;
  const barrierDeadline=setTimeout(()=>{barrierExpired=true;firstPaymentRead.resolve();bothPaymentReads.resolve();firstApprovalComplete.resolve();},5000);
  ActualPostgresDatabase.prototype.prepare=function(query){
   const statement=originalPrepare.call(this,query);
   if(query==='SELECT * FROM payments WHERE id=?'){
    const bind=statement.bind.bind(statement);
    statement.bind=(...values)=>{
     const bound=bind(...values);
     if(values[0]===paymentId){const first=bound.first.bind(bound);bound.first=async(column?:unknown)=>{
      const position=++paymentReads;if(position===1){firstPaymentRead.resolve();await bothPaymentReads.promise;}
      if(position===2){bothPaymentReads.resolve();await firstApprovalComplete.promise;}
      return first(column);
     };}
     return bound;
    };
   }
   return statement;
  };
  let duplicateApprovals:Response[];
  try{
   const firstApproval=financialCall('/reconciliations/proposals/'+proposalId+'/reviews',approvalInput,reviewer,approval.p_request_id,approvalHandlers[0]);approvalRequests.push(firstApproval);
   void firstApproval.then(()=>{firstPaymentRead.resolve();firstApprovalComplete.resolve();},()=>{firstPaymentRead.resolve();bothPaymentReads.resolve();firstApprovalComplete.resolve();});
   await firstPaymentRead.promise;
   const secondApproval=financialCall('/reconciliations/proposals/'+proposalId+'/reviews',approvalInput,reviewer,approval.p_request_id,approvalHandlers[1]);approvalRequests.push(secondApproval);
   void secondApproval.then(()=>bothPaymentReads.resolve(),()=>bothPaymentReads.resolve());
   duplicateApprovals=await Promise.all([firstApproval,secondApproval]);
  }finally{
   ActualPostgresDatabase.prototype.prepare=originalPrepare;clearTimeout(barrierDeadline);firstPaymentRead.resolve();bothPaymentReads.resolve();firstApprovalComplete.resolve();
   // Await every actual request/waitUntil/raw-work lifecycle before ending only
   // these two owned pools. Early failure preserves durable active/unresolved
   // facts; no force-close journal, pool-wide reset or fabricated settlement.
   await Promise.allSettled(approvalRequests);
   try{const completed=await Promise.allSettled(approvalWorks.map(work=>work.finish()));assertEquals(completed.every(row=>row.status==='fulfilled'&&row.value.state==='settled'),true,'Both genuine approval admissions finish before their owned pools are disposed.');}
   finally{await Promise.all(approvalPools.map(control=>control.end({timeout:1})));}
  }
  assertEquals(approvalWorks.length,2,'The controlled race uses two genuine SQL-admitted Edge-instance contexts.');
  assertEquals(barrierExpired,false,'Both original approval requests must reach the controlled race.');
  assertEquals(paymentReads,2,'Exercise the post-commit stale-payment window rather than a timing-dependent replay.');
  for(const response of duplicateApprovals){const value=await response.json();assertEquals(response.status,200,JSON.stringify(value));}
  assertEquals(Number((await sql`select count(*) as n from app.ledger_entries where payment_id=${paymentId} and kind='contribution'`)[0].n),1);assertEquals(Number((await sql`select member_balance_after_minor from app.contribution_posting_snapshots where payment_id=${paymentId}`)[0].member_balance_after_minor),1200);assertEquals(Number((await sql`select count(*) as n from app.notification_events where user_id=${principal} and data_json::jsonb->>'payment_id'=${paymentId}`)[0].n),1);
  r=await call('/v1/rpc/list_current_member_group_roster',{p_collection_id:group},token);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.find((x:any)=>x.public_id===memberPublic).amount_scope,'own');assertEquals(b.find((x:any)=>x.public_id===memberPublic).contributions,[{currency:'RWF',amount_minor:1200}]);
  r=await call('/v1/rpc/list_current_member_collection_balances',{},token);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.find((x:any)=>x.collection_id===group).balances[0].current_user_balance_minor,1200);
  const reverse={p_request_id:crypto.randomUUID(),p_payment_id:paymentId,p_expected_revision:2,p_reason:'Synthetic compensating reversal'},reverseInput={expected_version:reverse.p_expected_revision,reason:reverse.p_reason};r=await financialCall('/operations/transactions/'+paymentId+'/reverse',reverseInput,reviewer,reverse.p_request_id);b=await r.json();assertEquals(r.status,200,JSON.stringify(b));r=await financialCall('/operations/transactions/'+paymentId+'/reverse',reverseInput,reviewer,reverse.p_request_id);assertEquals(r.status,200);assertEquals(Number((await sql`select sum(amount_minor) as n from app.ledger_entries where payment_id=${paymentId}`)[0].n),0);assertEquals(Number((await sql`select count(*) as n from app.ledger_entries where payment_id=${paymentId}`)[0].n),2);
  const boundedStorage=new SupabaseObjectBucket({...env,DB:new PostgresDatabase(sql)});boundedStorage.journal.inventoryLimits={entries:1,bytes:8000000};let journalBounded=false;try{await boundedStorage.journal.listAll();}catch(error){journalBounded=(error as any).code==='storage_journal_inventory_limit';}assertEquals(journalBounded,true);
  const expiredFlow=crypto.randomUUID(),expiredAt=Math.floor(Date.now()/1000)-1;await sql`insert into app.auth_google_flows(id,state_hash,nonce,provider_verifier,client_challenge,client_state,return_origin,registration_allowed,created_at,expires_at,status)values(${expiredFlow},${await digest(expiredFlow)},'synthetic-nonce','{"synthetic_encrypted":true}',${'a'.repeat(43)},${'b'.repeat(43)},null,0,${expiredAt-300},${expiredAt},'ready')`;
  const jobs=createScheduledHandler(()=>({...env,COLLECT_JOB_TOKEN:'synthetic-job-token',MOMO_PROCESSING_PAUSED:'true'}));r=await jobs(new Request('https://backend.example/functions/v1/collect-jobs',{method:'POST',headers:{Authorization:'Bearer synthetic-job-token'}}));b=await r.json();assertEquals(r.status,200,JSON.stringify(b));assertEquals(b.maintenance.status,'complete');assert(b.maintenance.purged>=1);assertEquals(b.processing.paused,true);assertEquals((await sql`select status,provider_verifier from app.auth_google_flows where id=${expiredFlow}`)[0].provider_verifier,'{}');
  await sql`delete from auth.sessions where id=${nextSession}`;
  r=await call('/v1/auth/user');assertEquals(r.status,401);
 }finally{globalThis.fetch=nativeFetch;await server.shutdown();await finishSqlFixtureWork();await sql.end({timeout:1});}
}});
