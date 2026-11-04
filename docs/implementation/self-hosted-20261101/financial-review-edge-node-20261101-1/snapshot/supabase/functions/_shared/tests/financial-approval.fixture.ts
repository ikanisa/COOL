// Private financial-only extraction of accepted Auth PG4 source c10d404.
// No Deno.test/fencedTest is registered by this module. Root alone dispatches.
import {loadReviewedPlatformFixture,MIGRATION_THIRTEEN,ROOT_SQL13_SHA256} from '../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import postgres from 'npm:postgres@3.4.7';
import {PostgresDatabase as ActualPostgresDatabase} from '../postgres.js';
import {createHandler as actualCreateHandler} from '../serve.js';
import {openApplicationWork,sqlFenceBackend} from '../application-fence.js';
import {SYNTHETIC_FENCE_SOURCE,ownFixtureWork} from './helpers/fenced-unit.js';
import {initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {assertEquals,assert} from 'jsr:@std/assert@1.0.14';
import {connection,PostgresDatabase,compileSql} from './helpers/fenced-postgres.js';
import {createHandler,createScheduledHandler} from './helpers/real-handler.js';
import {digest} from '../domain/core.js';
import {requireSession} from './helpers/module-domain-auth.js';
import {dispatchOperation} from './helpers/module-domain-operations.js';
import {encrypt} from './helpers/module-domain-encryption.js';
import {issueAdminSession} from './helpers/module-domain-admin_accounts.js';
import {SupabaseObjectBucket} from './helpers/module-adapters.js';
import {processMomoJob,validateMomoExtraction,MOMO_SCHEMA_VERSION} from './helpers/module-domain-momo_pipeline.js';
export async function openFixture(){
 assertEquals(MIGRATION_THIRTEEN,'20261023102707_collect_retire_admin_mfa_enrollment.sql','Refuse stale planned SQL13 filename; require the actually supported normalized Auth source.');
 assertEquals(ROOT_SQL13_SHA256,'e11ee7110cc2eb3a8a6cf571532966711b6a9b737537b5b893c61d2b48d8e834');
 const database=Deno.env.get('COLLECT_FINANCIAL_TEST_DATABASE_URL')??Deno.env.get('COLLECT_TEST_DATABASE_URL');
 assert(database,'The financial-only fixture requires its fresh owned loopback database.');
 const url=new URL(database!);assert(['127.0.0.1','localhost'].includes(url.hostname)&&(url.port==='55439'||Deno.env.get('COLLECT_CI_SYNTHETIC')==='true')&&['/collect_be02_red_3f624f3e7a6d_test', '/collect_be02_green_3f624f3e7a6d_test'].includes(url.pathname),'Only the dedicated synthetic loopback database is allowed.');
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
  let observedAdminError:any=null;const adminHandler=createHandler('admin-api',()=>({...env,INTERNAL_ERROR_OBSERVER:(e:any)=>{observedAdminError=e;}}));let adminCookie='',csrf='';
  async function adminCall(path:string,body?:unknown,headers:Record<string,string>={}){observedAdminError=null;const response=await adminHandler(new Request('https://backend.example/functions/v1/admin-api/api/admin'+path,{method:body===undefined?'GET':'POST',headers:{Origin:'https://admin.example','Content-Type':'application/json','X-Collect-Requested-With':'collect-admin',...(adminCookie?{Cookie:adminCookie}:{}),...headers},...(body===undefined?{}:{body:JSON.stringify(body)})}));if(response.status===503&&observedAdminError)throw observedAdminError;return response;}
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
 const receiptObjects=new Map<string,string>();let aiCalls=0;
 const unix=()=>Math.floor(Date.now()/1000);
 const receiptEnv=()=>({...env,DB:new PostgresDatabase(sql),PRIVATE_MEDIA:{get:async(key:string)=>{const value=receiptObjects.get(key);return value?{size:new TextEncoder().encode(value).length,text:async()=>value}:null;}}});
 const capture=async(owner:any,body:string,receiverHash='d'.repeat(64))=>{
  const id=crypto.randomUUID(),key='sms/'+id,bodyHash=await digest(body),payload=new TextEncoder().encode(JSON.stringify({raw_sender:'MTN MoMo',raw_body:body,received_at_device:'2026-10-20T19:35:00+02:00',completeness:'complete'})),sha=await digest(payload),
   cipher=await encrypt(env,payload,`sms:${id}:${sha}`),sealedHash=await digest(cipher),scope={ownerId:owner.pid,entityId:id,purpose:'sms_receipt'},metadata={sha256:sha,source_fingerprint:'a'.repeat(64)},op=crypto.randomUUID();
  receiptObjects.set(key,cipher);
  await sql.begin(async(tx:any)=>{
   await tx`insert into private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)values(${key},${'a'.repeat(64)},${scope},${`sms:${id}:${sha}`},${env.DATA_KEY_ID},${sha},${cipher})`;
   await tx`insert into private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)values(${op},${key},${'b'.repeat(64)},${sealedHash},${cipher.length},${scope},${{}},${metadata},'committed')`;
   await tx`insert into private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)values(${key},${op},${'b'.repeat(64)},${sealedHash},${cipher.length},${scope},${{}},${metadata})`;
   await tx`insert into app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,received_at_device,created_at)values(${id},${owner.pid},${owner.sid},${crypto.randomUUID()},${bodyHash},${receiverHash},${key},${sha},${payload.length},'2026-10-20T19:35:00+02:00',${new Date().toISOString()})`;
  });
  return {id,key,bodyHash,body};
 };
 const account=async(iso=false,identifier='0788000001')=>{
  const id=crypto.randomUUID(),profile={sender_allowlist:['MTN MoMo'],currency_aliases:['RWF','FRW'],incoming_prefixes:['You have received'],transaction_id_prefixes:['TxId:'],date_format:iso?'ISO':'DMY_HMS',utc_offset_minutes:120};
  await sql`insert into app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,currency,timezone,profile_status,profile_version,profile_json,created_at)values(${id},'mtn_momo',${identifier},'Recorded Recipient',${await digest(identifier)},'RWF','Africa/Kigali','approved','synthetic-profile.v1',${JSON.stringify(profile)},${new Date().toISOString()})`;
  return (await sql`select * from app.momo_receiving_accounts where id=${id}`)[0];
 };
 const extracted=async(owner:any,a:any,{reference='REF_'+crypto.randomUUID(),payer='**007',name='Source Payer',time='20/10/2026 11:30:00',fee='0',balance='9000'}:{reference?:string,payer?:string|null,name?:string|null,time?:string|null,fee?:string|null,balance?:string|null}={})=>{
  const payerPart=[name,payer].filter(v=>v!==null).join(' '),body=`You have received RWF 1,000 ${payerPart?'from '+payerPart:''}. TxId: ${reference}${time?' on '+time:''}.${fee===null?'':' Fee: '+fee+'.'}${balance===null?'':' Balance: '+balance+'.'} DO_NOT_DISCLOSE_ORIGINAL_SMS`;
  const output={schema_version:MOMO_SCHEMA_VERSION,event_kind:'incoming_receipt',payment_outcome:'successful',transaction_id_raw:reference,original_transaction_id_raw:null,transaction_datetime_raw:time,
   principal_amount_raw:'1,000',currency_raw:'RWF',payer_name_raw:name,payer_identifier_raw:payer,payment_reference_raw:null,fee_amount_raw:fee,wallet_balance_after_raw:balance,
   evidence:{incoming_success:'You have received RWF 1,000',principal:'1,000',transaction_id:reference,transaction_datetime:time,payer:payerPart||null,fee:fee===null?null:'Fee: '+fee,wallet_balance_after:balance===null?null:'Balance: '+balance},issues:[]};
  const validation=validateMomoExtraction(output,{raw_sender:'MTN MoMo',raw_body:body,completeness:'complete'},a);assert(validation.accepted,JSON.stringify(validation));
  const raw=await capture(owner,body,a.receiver_hash),stamp=new Date().toISOString();
  await sql`insert into app.momo_processing_jobs(raw_sms_id,receiving_account_id,mode,state,available_at,created_at,updated_at)values(${raw.id},${a.id},'historical','pending',${unix()},${stamp},${stamp})`;
  const result=await processMomoJob({...receiptEnv(),AI:{run:async()=>{aiCalls++;return {response:output};}}},raw.id);assert(['accepted','duplicate','conflict'].includes(result.relation),JSON.stringify(result));
  return {...raw,output,result,tx:(await sql`select * from app.momo_transactions where id=${result.transaction_id}`)[0]};
 };
 const handlerPools:any[]=[],handlerWorks:any[]=[];
 const newHandler=()=>{
  const control=postgres(database!,{max:1,prepare:false,ssl:false,onnotice:()=>{}});handlerPools.push(control);
  return actualCreateHandler('admin-api',()=>({...env,BUILD_SOURCE_ID:SYNTHETIC_FENCE_SOURCE}),{
   async openWork(options:any){const work=ownFixtureWork(await openApplicationWork({...options,backend:sqlFenceBackend(sql,control)}));handlerWorks.push(work);return work;}
  });
 };
 const canonicalIncoming=async(args:any)=>{
  assert(args&&typeof args==='object');
  if(args.phase==='account'){assertEquals(args.provider,'mtn_momo');return account(false,args.receiver);}
  assertEquals(args.phase,'extract');assertEquals(args.amount,1000);
  const result=await extracted({pid:principal,sid:sessionId},args.account,{reference:args.reference});
  assertEquals(result.result.relation,'accepted');assert(result.tx);return result.tx;
 };
 let closed=false;
 async function close(){
  if(closed)return;closed=true;
  try{const settled=await Promise.allSettled(handlerWorks.map(work=>work.finish()));assertEquals(settled.every(row=>row.status==='fulfilled'&&row.value.state==='settled'),true,'All independent financial admissions settle before disposing only owned pools.');}
  finally{
   try{await Promise.all(handlerPools.map(control=>control.end({timeout:1})));}
   finally{globalThis.fetch=nativeFetch;try{await server.shutdown();}finally{try{await finishSqlFixtureWork();}finally{await sql.end({timeout:1});}}}
  }
 }
 try{
  // Project only the synthetic member through the actual handler; no full Auth suite.
  const opened=await call('/v1/auth/user');const user=await opened.json();assertEquals(opened.status,200,JSON.stringify(user));assertEquals(user.id,principal);
  const runExistingFinancialRegressions=async()=>{
   let r:Response,b:any;
   // Recreate only the accepted financial block's missing-wallet preimage.
   const missing=await sql`UPDATE app.users SET momo_number='',revision=revision+1,updated_at=${new Date().toISOString()} WHERE id=${principal} AND momo_number=${phone} RETURNING id`;assertEquals(missing.length,1);
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
  };
  return {sql,principal,financialAdmin,financialCall,ActualPostgresDatabase,newHandler,canonicalIncoming,runExistingFinancialRegressions,close};
 }catch(error){await close();throw error;}
}
