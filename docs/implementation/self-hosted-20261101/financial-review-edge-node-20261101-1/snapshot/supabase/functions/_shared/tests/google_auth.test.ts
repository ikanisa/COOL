import {initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest} from './helpers/fenced-unit.js';
import {assert,assertEquals,assertRejects} from 'jsr:@std/assert@1.0.14';
import {handleGoogleAuth,startGoogleFlow,exchangeGoogleFlow,GOOGLE_PROJECT_ORIGIN,GOOGLE_APPLICATION_CALLBACK} from './helpers/module-domain-google_auth.js';
import {handleAdminAccounts} from './helpers/module-domain-admin_accounts.js';
import {PostgresDatabase,connection} from './helpers/fenced-postgres.js';
import {logicalRequest} from './helpers/real-handler.js';

const front='https://platform-admin.collect.ikanisa.com',member='https://collect.ikanisa.com';
const qa='https://admin-supabase-qa.collect.ikanisa.com',qaCallback=qa+'/functions/v1/collect-api/v1/auth/google/callback';
const qaConfig={COLLECT_GOOGLE_CALLBACK_URL:qaCallback,SUPABASE_GOOGLE_CALLBACK_URL:qaCallback,ADMIN_ORIGIN:qa,ADMIN_ORIGINS:front+','+qa};
const base={GOOGLE_AUTH_ENABLED:'true',SUPABASE_URL:GOOGLE_PROJECT_ORIGIN,COLLECT_GOOGLE_CALLBACK_URL:GOOGLE_APPLICATION_CALLBACK,
 SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_google_fixture',ADMIN_ORIGIN:front,GOOGLE_WEB_ORIGINS:member,
 SESSION_KEY_ID:'synthetic-google-v1',SESSION_ENCRYPTION_KEY:btoa('s'.repeat(32)),AUTH_MEMBER_REGISTRATION_ENABLED:'false'};
const nonce=()=>btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
const challenge=async(value:string)=>btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value))))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
const post=(path:string,body:unknown,origin:string|null=front)=>new Request(GOOGLE_PROJECT_ORIGIN+path,{method:'POST',headers:{'Content-Type':'application/json',...(origin?{Origin:origin}:{}),'X-Collect-Requested-With':'collect-admin'},body:JSON.stringify(body)});

fencedTest('Google is disabled or fixed-target misconfigured before database access',async()=>{
 const noDb={prepare(){throw new Error('Must not access database');},batch(){throw new Error('Must not access database');}};
 for(const config of [{GOOGLE_AUTH_ENABLED:'false'},{SUPABASE_URL:'https://other.supabase.co'},{COLLECT_GOOGLE_CALLBACK_URL:'https://evil.invalid/callback'},{SUPABASE_GOOGLE_CALLBACK_URL:'https://evil.invalid/conflict'}]){
  await assertRejects(()=>startGoogleFlow(post('/v1/auth/google/start',{}),{...base,...config,DB:noDb}));
 }
});
fencedTest('Google start rejects foreign or missing Admin browser origin and wrong surface',async()=>{
 const noDb={prepare(){throw new Error('Must not access database');},batch(){throw new Error('Must not access database');}};
 for(const [surface,origin,body]of [['admin',null,{return_origin:null}],['admin','https://evil.invalid',{return_origin:'https://evil.invalid'}],['admin',front,{return_origin:front,surface:'member'}],['member',member,{return_origin:null}]] as const){
  await assertRejects(()=>startGoogleFlow(post('/v1/auth/google/start',{code_challenge:'a'.repeat(43),client_state:'b'.repeat(43),...body},origin),{...base,DB:noDb},{surface}));
 }
});
fencedTest('Google callback refuses duplicate state/code controls before provider or database access',async()=>{
 const noDb={prepare(){throw new Error('Must not access database');}};
 for(const query of ['state=a','state='+ 'a'.repeat(43)+'&state='+ 'b'.repeat(43),
  'state='+ 'a'.repeat(43)+'&code=x&code=y','state='+ 'a'.repeat(43)+'&code=x&error=access_denied']){
  await assertRejects(()=>handleGoogleAuth(new Request(GOOGLE_PROJECT_ORIGIN+'/v1/auth/google/callback?'+query),{...base,DB:noDb}));
 }
});

// These cases require rejection by the real configuration/origin boundary,
// rather than treating a sentinel DB exception as an acceptable refusal.
fencedTest('Google callback selection rejects hostile aliases and missing callback settings before DB',async()=>{
 let dbCalls=0;const noDb={prepare(){dbCalls++;throw Error('Unexpected fixture database access');},batch(){dbCalls++;throw Error('Unexpected fixture database access');}};
 const callbacks=[
  qaCallback+'/',qaCallback+'/extra',qaCallback+'?state=untrusted',qaCallback+'#fragment',
  qaCallback.replace('https:','http:'),qaCallback.replace('https://','https://user:password@'),
  qaCallback.replace('collect.ikanisa.com','collect.ikanisa.com.evil.invalid'),
  qaCallback.replace('/auth/google/callback','/auth/google/%63allback'),
  qaCallback.replace('/auth/google/callback','/auth/google/../google/callback'),
  qaCallback.replace('https://','https://*.'),
  qaCallback.replace('https://','HTTPS://'),qaCallback.replace('.com/','.com:443/'),
  GOOGLE_PROJECT_ORIGIN+'/auth/v1/callback'
 ];
 for(const callback of callbacks){
  const error=await assertRejects(()=>startGoogleFlow(post('/v1/auth/google/start',{code_challenge:'a'.repeat(43),client_state:'b'.repeat(43),return_origin:qa},qa),{...base,...qaConfig,COLLECT_GOOGLE_CALLBACK_URL:callback,SUPABASE_GOOGLE_CALLBACK_URL:callback,DB:noDb},{surface:'admin'}));
  assertEquals((error as any).code,'google_auth_unavailable');assertEquals((error as any).status,503);
 }
 for(const config of[
  {COLLECT_GOOGLE_CALLBACK_URL:undefined,SUPABASE_GOOGLE_CALLBACK_URL:undefined},
  {SUPABASE_GOOGLE_CALLBACK_URL:''},{SUPABASE_GOOGLE_CALLBACK_URL:qaCallback},
  {COLLECT_GOOGLE_CALLBACK_URL:qaCallback,SUPABASE_GOOGLE_CALLBACK_URL:GOOGLE_APPLICATION_CALLBACK},
 ]){
  const error=await assertRejects(()=>startGoogleFlow(post('/v1/auth/google/start',{code_challenge:'a'.repeat(43),client_state:'b'.repeat(43),return_origin:front}),{...base,...config,DB:noDb},{surface:'admin'}));
  assertEquals((error as any).code,'google_auth_unavailable');assertEquals((error as any).status,503);
 }
 assertEquals(dbCalls,0);
});
fencedTest('Google exact legacy-only callbacks pass configuration to genuine start DB boundary',async()=>{
 for(const[callback,origin]of[[GOOGLE_APPLICATION_CALLBACK,front],[qaCallback,qa]] as const){
  let dbCalls=0;const sentinel=Error('Expected start database boundary');
  const noCommitDb={prepare(){return {bind(){return {};}};},batch(){dbCalls++;throw sentinel;}};
  const error=await assertRejects(()=>startGoogleFlow(post('/v1/auth/google/start',{code_challenge:'a'.repeat(43),client_state:'b'.repeat(43),return_origin:origin},origin),{...base,COLLECT_GOOGLE_CALLBACK_URL:undefined,SUPABASE_GOOGLE_CALLBACK_URL:callback,ADMIN_ORIGINS:front+','+qa,DB:noCommitDb},{surface:'admin'}));
  assertEquals(error,sentinel);assertEquals(dbCalls,1);
 }
});
fencedTest('Google Admin selected callback binds allowed caller origin before start/exchange DB',async()=>{
 let dbCalls=0;const noDb={prepare(){dbCalls++;throw Error('Unexpected fixture database access');},batch(){dbCalls++;throw Error('Unexpected fixture database access');}};
 for(const[selected,origin]of[[GOOGLE_APPLICATION_CALLBACK,qa],[qaCallback,front]] as const){
  const config={...base,ADMIN_ORIGINS:front+','+qa,COLLECT_GOOGLE_CALLBACK_URL:selected,DB:noDb};
  const error=await assertRejects(()=>startGoogleFlow(post('/v1/auth/google/start',{code_challenge:'a'.repeat(43),client_state:'b'.repeat(43),return_origin:origin},origin),config,{surface:'admin'}));
  assertEquals((error as any).code,'origin_denied');assertEquals((error as any).status,403);
  const exchangeError=await assertRejects(()=>exchangeGoogleFlow(post('/api/admin/auth/google/exchange',{code:'a'.repeat(43),code_verifier:'b'.repeat(43),client_state:'c'.repeat(43)},origin),config,{surface:'admin'}));
  assertEquals((exchangeError as any).code,'origin_denied');assertEquals((exchangeError as any).status,403);
 }
 for(const headers of[{Origin:qa},{Origin:qa,'X-Collect-Requested-With':'other'},{Origin:qa,'X-Collect-Requested-With':'collect-admin','Sec-Fetch-Site':'cross-site'}] as Record<string,string>[]){
  const request=new Request(GOOGLE_PROJECT_ORIGIN+'/v1/auth/google/start',{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify({code_challenge:'a'.repeat(43),client_state:'b'.repeat(43),return_origin:qa})});
  const error=await assertRejects(()=>startGoogleFlow(request,{...base,...qaConfig,DB:noDb},{surface:'admin'}));assertEquals((error as any).code,'origin_denied');
 }
 const notAllowed=await assertRejects(()=>startGoogleFlow(post('/v1/auth/google/start',{code_challenge:'a'.repeat(43),client_state:'b'.repeat(43),return_origin:qa},qa),{...base,COLLECT_GOOGLE_CALLBACK_URL:qaCallback,DB:noDb},{surface:'admin'}));assertEquals((notAllowed as any).code,'origin_denied');
 assertEquals(dbCalls,0);
});

const callbackRequest=(value:URL)=>{const url=new URL(value);return logicalRequest(new Request(GOOGLE_PROJECT_ORIGIN+url.pathname+url.search),'collect-api');};
const database=Deno.env.get('COLLECT_GOOGLE_TEST_DATABASE_URL');
fencedTest({name:'actual Google member/Admin PKCE and staff-only BFF on isolated PostgreSQL',ignore:!database,sanitizeResources:false,sanitizeOps:false,fn:async()=>{
 const url=new URL(database!);assert(['127.0.0.1','localhost'].includes(url.hostname)&&(url.port==='55439'||(Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'&&['55441','55443'].includes(url.port)))&&url.pathname==='/collect_google_test','Use only the separate synthetic Google fixture database');
 const sql=connection(database!);await initializeSqlFixture(sql);const originalFetch=globalThis.fetch;
 const managed=new Map<string,any>(),codes=new Map<string,any>(),calls:{path:string,body:any}[]=[],revoked=new Set<string>();
 const env=(db:PostgresDatabase=new PostgresDatabase(sql))=>({...base,DB:db});
 class LostReplyDatabase extends PostgresDatabase {
  pattern:string;fired=false;
  constructor(pattern:string){super(sql);this.pattern=pattern;}
  override async execute(statement:any){const result=await super.execute(statement);if(!this.fired&&statement.sql.includes(this.pattern)){this.fired=true;throw new Error('Synthetic committed SQL reply lost');}return result;}
 }
 class LostBffReplyDatabase extends PostgresDatabase {
  fired=false;
  constructor(){super(sql);}
  override async batch(statements:any[]){const result=await super.batch(statements);if(!this.fired&&statements.some(s=>s.sql.includes('INSERT INTO private.bff_sessions'))){this.fired=true;throw new Error('Synthetic committed BFF reply lost');}return result;}
 }
 const principal=async(email:string,staff=false,status='invited')=>{
  const auth=crypto.randomUUID(),sid=crypto.randomUUID(),pid=crypto.randomUUID(),aid=crypto.randomUUID(),at=Math.floor(Date.now()/1000);
  await sql`insert into auth.users(id,email,email_confirmed_at)values(${auth},${email},now())`;
  await sql`insert into auth.sessions(id,user_id,aal,not_after)values(${sid},${auth},'aal1',to_timestamp(${at+600}))`;
  const next=await sql`select lpad((coalesce(max(public_id::int)filter(where public_id<>'999999'),100000)+1)::text,6,'0') as value from app.users`;
  await sql`insert into app.users(id,email,public_id,full_name,member_type,created_at,updated_at)values(${pid},${email},${next[0].value},'Synthetic Google fixture',${staff?'operator':'app'},${new Date().toISOString()},${new Date().toISOString()})`;
  await sql`insert into private.auth_principal_links(auth_user_id,user_id,proof_reference)values(${auth},${pid},'synthetic-google-test')`;
  if(staff){await sql`insert into app.admin_users(id,email,role,status,display_name,created_at,updated_at)values(${aid},${email},'staff',${status},'Synthetic Google Staff',${at},${at})`;
   await sql`insert into app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)values(${aid},${pid},'synthetic-google-approval',${new Date().toISOString()})`;}
  const claims={sub:auth,session_id:sid,role:'authenticated',aal:'aal1',aud:'authenticated',iat:at,exp:at+3600,iss:GOOGLE_PROJECT_ORIGIN+'/auth/v1',amr:[{method:'oauth',timestamp:at}]};
  const token=btoa('{}')+'.'+btoa(JSON.stringify(claims))+'.synthetic-not-a-hosted-signature';
  const user={id:auth,email,email_confirmed_at:new Date().toISOString(),identities:[{provider:'google'}],app_metadata:{provider:'google'},user_metadata:{}};
  const fixture={auth,sid,pid,aid,claims,user,token,session:{access_token:token,refresh_token:'synthetic-refresh-'+sid,expires_in:3600,token_type:'bearer',provider_token:'must-never-leave-server'}};
  managed.set(token,fixture);return fixture;
 };
 globalThis.fetch=async(input:Request|string|URL,init?:RequestInit)=>{
  const request=input instanceof Request?input:new Request(input,init),u=new URL(request.url),body=request.method==='GET'?null:await request.json().catch(()=>null);
  assertEquals(u.origin,GOOGLE_PROJECT_ORIGIN);calls.push({path:u.pathname+u.search,body});
  if(u.pathname==='/auth/v1/token'&&u.searchParams.get('grant_type')==='pkce'){
   const fixture=codes.get(body.auth_code);if(!fixture||fixture.used||await challenge(body.code_verifier)!==fixture.challenge)return Response.json({error_code:'bad_code'},{status:400});
   fixture.used=true;if(fixture.lose)throw new Error('Synthetic provider commit reply lost');return Response.json(fixture.identity.session);
  }
  const token=request.headers.get('Authorization')?.slice(7)??'',fixture=managed.get(token);
  if(u.pathname==='/auth/v1/user'&&fixture&&!revoked.has(token))return Response.json(fixture.user);
  if(u.pathname==='/auth/v1/logout'&&u.searchParams.get('scope')==='local'&&fixture){revoked.add(token);return Response.json({});}
  return Response.json({error_code:'invalid_session'},{status:401});
 };
 const begin=async(surface:'member'|'admin',identity:any,{native=false,db,config={}}:any={})=>{
  const verifier=nonce(),state=nonce(),selected=config.COLLECT_GOOGLE_CALLBACK_URL??config.SUPABASE_GOOGLE_CALLBACK_URL??GOOGLE_APPLICATION_CALLBACK,returnOrigin=native?null:surface==='admin'?new URL(selected).origin:member;
  const body={code_challenge:await challenge(verifier),client_state:state,return_origin:returnOrigin};
  const request=post(surface==='admin'?'/api/admin/auth/google/start':'/v1/auth/google/start',body,returnOrigin);
  const response=surface==='admin'?await handleAdminAccounts(request,{...env(db),...config},{}):await handleGoogleAuth(request,{...env(db),...config});assert(response);
  const data=await response.json(),authorize=new URL(data.authorization_url);assertEquals(authorize.origin,GOOGLE_PROJECT_ORIGIN);assertEquals(authorize.pathname,'/auth/v1/authorize');assertEquals(authorize.searchParams.get('provider'),'google');
  const callback=new URL(authorize.searchParams.get('redirect_to')!);assertEquals(callback.origin+callback.pathname,selected);assertEquals(authorize.searchParams.get('code_challenge_method'),'s256');
  const code=crypto.randomUUID();codes.set(code,{identity,challenge:authorize.searchParams.get('code_challenge'),used:false});callback.searchParams.set('code',code);
  return {verifier,state,returnOrigin,callback,code,config};
 };
 const finish=async(flow:any,db?:PostgresDatabase)=>{
  const response=await handleGoogleAuth(callbackRequest(flow.callback),{...env(db),...flow.config});
  assertEquals(response.headers.get('Cache-Control'),'no-store');
  if(flow.returnOrigin===null){assertEquals(response.status,302);const location=new URL(response.headers.get('Location')!);assertEquals(location.protocol,'collect:');assertEquals(location.host,'auth');assertEquals(location.pathname,'/google');return Object.fromEntries(location.searchParams);}
  assertEquals(response.headers.get('X-Collect-Document'),'collect.google.callback.v1');
  const html=await response.text();assert(html.includes(JSON.stringify(flow.returnOrigin)));assert(!html.includes('access_token')&&!html.includes('refresh_token')&&!html.includes('must-never-leave-server'));
  return JSON.parse(html.match(/postMessage\((\{.*?\}),"https:/)![1]);
 };
 const exchange=(surface:'member'|'admin',flow:any,reply:any,db?:PostgresDatabase,overrides:any={})=>{
  const request=post(surface==='admin'?'/api/admin/auth/google/exchange':'/v1/auth/google/exchange',{code:reply.code,code_verifier:flow.verifier,client_state:flow.state,...overrides},flow.returnOrigin);
  return surface==='admin'?handleAdminAccounts(request,{...env(db),...flow.config},{}):handleGoogleAuth(request,{...env(db),...flow.config});
 };
 try {
  // Local managed Auth shape: the resolver reads the same confirmed-email
  // fact returned by this synthetic provider. Google still creates no OTP proof.
  await sql.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
  const staff=await principal('google-staff-'+crypto.randomUUID()+'@example.test',true);
  const admin=await begin('admin',staff),ready=await finish(admin,new LostReplyDatabase("SET status='ready'"));assertEquals(ready.state,admin.state);
  // Wrong surface, verifier and caller origin cannot consume the real handoff.
  await assertRejects(()=>exchangeGoogleFlow(post('/v1/auth/google/exchange',{code:ready.code,code_verifier:admin.verifier,client_state:admin.state},front),env()));
  await assertRejects(()=>exchange('admin',admin,ready,undefined,{code_verifier:nonce()}));
  await assertRejects(()=>exchangeGoogleFlow(post('/api/admin/auth/google/exchange',{code:ready.code,code_verifier:admin.verifier,client_state:admin.state},'https://evil.invalid'),env(),{surface:'admin'}));
  const admitted=await exchange('admin',admin,ready,new LostReplyDatabase("SET status='consumed'"));assert(admitted);assertEquals(admitted.status,200);
  const cookie=admitted.headers.get('Set-Cookie')!;assert(cookie.startsWith('__Host-collect_admin='));assert(cookie.includes('HttpOnly'));
  const account=await admitted.json();assertEquals(account.user.email,staff.user.email);assertEquals(account.user.role,'staff');assertEquals(account.user.assuranceLevel,1);assertEquals(account.user.mfaAt,null);assertEquals(typeof account.csrfToken,'string');
  assert(!JSON.stringify(account).includes('access_token')&&!JSON.stringify(account).includes('refresh_token'));
  const googleEmailState=await handleAdminAccounts(new Request(GOOGLE_PROJECT_ORIGIN+'/api/admin/auth/email-verification',{headers:{Origin:front,Cookie:cookie.split(';')[0]}}),env(),{});
  assert(googleEmailState);assertEquals(googleEmailState.status,200);assertEquals((await googleEmailState.json()).emailVerifiedAt,null);
  assertEquals(Number((await sql`select count(*) as n from private.admin_sensitive_email_proofs where original_session_id=${staff.sid}`)[0].n),0,'Google confirmation is ordinary sign-in, not a sensitive email OTP proof');
  const actual=await sql`select status from app.admin_users where id=${staff.aid}`;assertEquals(actual[0].status,'active');
  const expiry=await sql`select expires_at from app.admin_sessions where auth_session_id=${staff.sid}`;assertEquals(Number(expiry[0].expires_at)<=staff.claims.iat+600,true);
  const purged=await sql`select provider_verifier,status from app.auth_google_flows where client_state=${admin.state}`;assertEquals(purged[0].provider_verifier,'{}');assertEquals(purged[0].status,'consumed');
  await assertRejects(()=>exchange('admin',admin,ready));await assertRejects(()=>handleGoogleAuth(callbackRequest(admin.callback),env()));
  const session=await handleAdminAccounts(new Request(GOOGLE_PROJECT_ORIGIN+'/api/admin/auth/session',{headers:{Origin:front,Cookie:cookie.split(';')[0]}}),env(),{});assert(session);assertEquals((await session.json()).user.email,staff.user.email);
  await sql`update app.admin_users set status='revoked',auth_version=auth_version+1 where id=${staff.aid}`;
  const revokedSession=await handleAdminAccounts(new Request(GOOGLE_PROJECT_ORIGIN+'/api/admin/auth/session',{headers:{Origin:front,Cookie:cookie.split(';')[0]}}),env(),{});assert(revokedSession);assertEquals((await revokedSession.json()).user,null);

  const memberIdentity=await principal('google-member-'+crypto.randomUUID()+'@example.test');
  const memberFlow=await begin('member',memberIdentity,{native:true}),memberReply=await finish(memberFlow);
  const memberResponse=await exchange('member',memberFlow,memberReply);assert(memberResponse);const memberBody=await memberResponse.json();assertEquals(memberBody.user.id,memberIdentity.pid);assertEquals(memberBody.user.app_metadata.roles,['member']);assertEquals(memberBody.provider_token,undefined);
  const attemptedAdmin=await begin('admin',memberIdentity),attemptedReply=await finish(attemptedAdmin);
  await assertRejects(()=>exchange('admin',attemptedAdmin,attemptedReply),Error,'Admin');
  const leaked=await sql`select count(*)::int as value from private.bff_sessions where auth_user_id=${memberIdentity.auth}`;assertEquals(leaked[0].value,0);
  assert(calls.some(call=>call.path==='/auth/v1/logout?scope=local'));

  const lateRevoked=await principal('google-revoked-'+crypto.randomUUID()+'@example.test',true);
  const lateFlow=await begin('admin',lateRevoked),lateReply=await finish(lateFlow);
  await sql`update app.admin_users set status='revoked',auth_version=auth_version+1 where id=${lateRevoked.aid}`;
  await assertRejects(()=>exchange('admin',lateFlow,lateReply));
  const lateNone=await sql`select count(*)::int as value from private.bff_sessions where auth_user_id=${lateRevoked.auth}`;assertEquals(lateNone[0].value,0);

  const falseProvider=await principal('google-false-provider-'+crypto.randomUUID()+'@example.test');falseProvider.user.identities=[{provider:'email'}];
  const falseFlow=await begin('member',falseProvider,{native:true}),falseReply=await finish(falseFlow);assertEquals(falseReply.error,'google_use_email_sign_in');

  const commitStaff=await principal('google-commit-'+crypto.randomUUID()+'@example.test',true);
  const commitFlow=await begin('admin',commitStaff),commitReply=await finish(commitFlow);
  const commitResponse=await exchange('admin',commitFlow,commitReply,new LostBffReplyDatabase());assert(commitResponse);assertEquals(commitResponse.status,200);
  const single=await sql`select count(*)::int as value from private.bff_sessions where auth_session_id=${commitStaff.sid}`;assertEquals(single[0].value,1);

  const concurrentStaff=await principal('google-concurrent-'+crypto.randomUUID()+'@example.test',true);
  const concurrentFlow=await begin('admin',concurrentStaff),concurrentReply=await finish(concurrentFlow);
  const raced=await Promise.allSettled([exchange('admin',concurrentFlow,concurrentReply),exchange('admin',concurrentFlow,concurrentReply)]);
  assertEquals(raced.filter(r=>r.status==='fulfilled').length,1);assertEquals(raced.filter(r=>r.status==='rejected').length,1);
  const concurrentRows=await sql`select count(*)::int as value from private.bff_sessions where auth_session_id=${concurrentStaff.sid}`;assertEquals(concurrentRows[0].value,1);

  const uncertainStaff=await principal('google-issue-unknown-'+crypto.randomUUID()+'@example.test',true);
  const issueFlow=await begin('admin',uncertainStaff),issueReply=await finish(issueFlow);let issueCalls=0;
  const issueRequest=()=>post('/api/admin/auth/google/exchange',{code:issueReply.code,code_verifier:issueFlow.verifier,client_state:issueFlow.state},front);
  await assertRejects(()=>exchangeGoogleFlow(issueRequest(),env(),{surface:'admin',admit:async()=>{issueCalls++;throw new Error('Synthetic unknown admission result');}}));
  await assertRejects(()=>exchangeGoogleFlow(issueRequest(),env(),{surface:'admin',admit:async()=>{issueCalls++;return Response.json({});}}));assertEquals(issueCalls,1);

  const unknownIdentity=await principal('google-unknown-'+crypto.randomUUID()+'@example.test',true);
  const unknown=await begin('admin',unknownIdentity);codes.get(unknown.code).lose=true;const before=calls.filter(c=>c.path==='/auth/v1/token?grant_type=pkce').length;
  const uncertain=await finish(unknown);assertEquals(uncertain.error,'google_sign_in_unconfirmed');
  await assertRejects(()=>handleGoogleAuth(callbackRequest(unknown.callback),env()));assertEquals(calls.filter(c=>c.path==='/auth/v1/token?grant_type=pkce').length,before+1);
  const none=await sql`select count(*)::int as value from private.bff_sessions where auth_user_id=${unknownIdentity.auth}`;assertEquals(none[0].value,0);

  const qaStaff=await principal('google-qa-staff-'+crypto.randomUUID()+'@example.test',true);
  const qaFlow=await begin('admin',qaStaff,{config:qaConfig}),qaReply=await finish(qaFlow);assertEquals(qaReply.state,qaFlow.state);
  const qaResponse=await exchange('admin',qaFlow,qaReply);assert(qaResponse);assertEquals(qaResponse.status,200);
  const qaCookie=qaResponse.headers.get('Set-Cookie')!;assert(qaCookie.startsWith('__Host-collect_admin=')&&qaCookie.includes('HttpOnly'));
  const qaAccount=await qaResponse.json();assertEquals(qaAccount.user.email,qaStaff.user.email);assertEquals(qaAccount.user.assuranceLevel,1);assertEquals(qaAccount.user.mfaAt,null);assertEquals(typeof qaAccount.csrfToken,'string');assert(!JSON.stringify(qaAccount).includes('access_token')&&!JSON.stringify(qaAccount).includes('refresh_token'));
  const qaSessions=await sql`select origin from app.admin_sessions where auth_session_id=${qaStaff.sid}`;assertEquals(qaSessions.length,1);assertEquals(qaSessions[0].origin,qa);
  await assertRejects(()=>exchange('admin',qaFlow,qaReply));

  const mixedIdentity=await principal('google-qa-mixed-'+crypto.randomUUID()+'@example.test',true);
  const mixed=await begin('admin',mixedIdentity,{config:qaConfig});const beforeMixed=calls.filter(c=>c.path==='/auth/v1/token?grant_type=pkce').length;
  const mixedCallback=await assertRejects(()=>handleGoogleAuth(callbackRequest(mixed.callback),{...env(),ADMIN_ORIGINS:front+','+qa}));assertEquals((mixedCallback as any).code,'origin_denied');
  assertEquals(calls.filter(c=>c.path==='/auth/v1/token?grant_type=pkce').length,beforeMixed);assertEquals(codes.get(mixed.code).used,false);
  const mixedState=await sql`select status from app.auth_google_flows where client_state=${mixed.state}`;assertEquals(mixedState[0].status,'pending');
  const correctedReply=await finish(mixed),correctedAdmission=await exchange('admin',mixed,correctedReply);assert(correctedAdmission);assertEquals(correctedAdmission.status,200);

  const cancelledIdentity=await principal('google-qa-cancel-'+crypto.randomUUID()+'@example.test',true);
  const cancelled=await begin('admin',cancelledIdentity,{config:qaConfig});cancelled.callback.searchParams.delete('code');cancelled.callback.searchParams.set('error','access_denied');
  const beforeCancel=calls.filter(c=>c.path==='/auth/v1/token?grant_type=pkce').length;
  const cancelledReply=await finish(cancelled);assertEquals(cancelledReply.error,'google_cancelled');assertEquals(cancelledReply.state,cancelled.state);
  assertEquals(calls.filter(c=>c.path==='/auth/v1/token?grant_type=pkce').length,beforeCancel);
  await assertRejects(()=>handleGoogleAuth(callbackRequest(cancelled.callback),{...env(),...qaConfig}));
  const cancelledRow=await sql`select status,provider_verifier from app.auth_google_flows where client_state=${cancelled.state}`;assertEquals(cancelledRow[0].status,'failed');assertEquals(cancelledRow[0].provider_verifier,'{}');
  const cancelledBff=await sql`select count(*)::int as value from private.bff_sessions where auth_user_id=${cancelledIdentity.auth}`;assertEquals(cancelledBff[0].value,0);

  const qaUnknownIdentity=await principal('google-qa-unknown-'+crypto.randomUUID()+'@example.test',true);
  const qaUnknown=await begin('admin',qaUnknownIdentity,{config:qaConfig});codes.get(qaUnknown.code).lose=true;
  const beforeQaUnknown=calls.filter(c=>c.path==='/auth/v1/token?grant_type=pkce').length;
  const qaUncertain=await finish(qaUnknown);assertEquals(qaUncertain.error,'google_sign_in_unconfirmed');
  await assertRejects(()=>handleGoogleAuth(callbackRequest(qaUnknown.callback),{...env(),...qaConfig}));
  assertEquals(calls.filter(c=>c.path==='/auth/v1/token?grant_type=pkce').length,beforeQaUnknown+1);
  const qaUnknownBff=await sql`select count(*)::int as value from private.bff_sessions where auth_user_id=${qaUnknownIdentity.auth}`;assertEquals(qaUnknownBff[0].value,0);

  // Legacy-only compatibility uses the real PG start/callback/BFF path for
  // both allowed callbacks, rather than claiming success from the DB sentinel.
  for(const[legacyCallback,legacyOrigin]of[[GOOGLE_APPLICATION_CALLBACK,front],[qaCallback,qa]] as const){
   const legacyStaff=await principal('google-legacy-'+crypto.randomUUID()+'@example.test',true);
   const legacyConfig={COLLECT_GOOGLE_CALLBACK_URL:undefined,SUPABASE_GOOGLE_CALLBACK_URL:legacyCallback,ADMIN_ORIGIN:legacyOrigin,ADMIN_ORIGINS:front+','+qa};
   const legacyFlow=await begin('admin',legacyStaff,{config:legacyConfig}),legacyReply=await finish(legacyFlow);
   assertEquals(legacyFlow.callback.origin+legacyFlow.callback.pathname,legacyCallback);
   const legacyResponse=await exchange('admin',legacyFlow,legacyReply);assert(legacyResponse);assertEquals(legacyResponse.status,200);
   const legacyAccount=await legacyResponse.json();assertEquals(legacyAccount.user.email,legacyStaff.user.email);assertEquals(legacyAccount.user.assuranceLevel,1);assertEquals(legacyAccount.user.mfaAt,null);
   const legacySessions=await sql`select origin from app.admin_sessions where auth_session_id=${legacyStaff.sid}`;assertEquals(legacySessions.length,1);assertEquals(legacySessions[0].origin,legacyOrigin);
   await assertRejects(()=>exchange('admin',legacyFlow,legacyReply));
  }

  // Selected application callback and member return origin are independent.
  // Both browser postMessage and native collect:// final delivery remain valid.
  const qaMember=await principal('google-qa-member-'+crypto.randomUUID()+'@example.test');
  const qaBrowser=await begin('member',qaMember,{config:qaConfig});assertEquals(qaBrowser.returnOrigin,member);
  const qaBrowserReply=await finish(qaBrowser),qaMemberResponse=await exchange('member',qaBrowser,qaBrowserReply);assert(qaMemberResponse);assertEquals((await qaMemberResponse.json()).user.id,qaMember.pid);
  const qaNative=await begin('member',qaMember,{native:true,config:qaConfig});assertEquals(qaNative.returnOrigin,null);
  const qaNativeReply=await finish(qaNative),qaNativeResponse=await exchange('member',qaNative,qaNativeReply);assert(qaNativeResponse);assertEquals((await qaNativeResponse.json()).user.id,qaMember.pid);
 }finally{globalThis.fetch=originalFetch;await finishSqlFixtureWork();await sql.end({timeout:1});}
}});
