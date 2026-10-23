import {loadReviewedPlatformFixture} from '../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import {initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest} from './helpers/fenced-unit.js';
import {assert,assertEquals,assertRejects} from 'jsr:@std/assert@1.0.14';
import {connection,PostgresDatabase} from './helpers/fenced-postgres.js';
import {handleAdminAccounts,issueAdminSession,adminAccountSession} from './helpers/module-domain-admin_accounts.js';
import {accountGuard} from '../domain/admin_accounts.js';
import {ApiError,digest} from '../domain/core.js';
import {handleAuth,verifyOtp,projectSession} from './helpers/module-domain-auth.js';

// The actual JavaScript guard accepts permission strings; its untyped null default narrows the inferred test signature.
const permissionGuard=accountGuard as unknown as (environment:Parameters<typeof accountGuard>[0],account:Parameters<typeof accountGuard>[1],permission:string)=>ReturnType<typeof accountGuard>;

const project='https://rrlduytparvsjfmegalh.supabase.co',front='https://platform-admin.collect.ikanisa.com';
const unix=()=>Math.floor(Date.now()/1000);
const database=Deno.env.get('COLLECT_MFA_TEST_DATABASE_URL');
const root=new URL('../../../../',import.meta.url);
const post=(path:string,body:unknown,cookie='',csrf='')=>new Request(front+path,{method:'POST',headers:{Origin:front,'Content-Type':'application/json','X-Collect-Requested-With':'collect-admin',...(cookie?{Cookie:cookie,'X-Collect-CSRF':csrf}:{})},body:JSON.stringify(body)});

fencedTest({name:'retired managed MFA routes, historical reads and latest OTP admission on exclusive PostgreSQL fixture',sanitizeResources:false,sanitizeOps:false,fn:async(t)=>{
 assert(database,'COLLECT_MFA_TEST_DATABASE_URL is mandatory; this contract suite never silently skips');
 const target=new URL(database);assert(['127.0.0.1','localhost'].includes(target.hostname)&&target.pathname==='/collect_mfa_test'&&(target.port==='55439'||Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'),'Use only the exclusive local collect_mfa_test');
 const sql=connection(database),originalFetch=globalThis.fetch;
 const reviewedPlatform=await loadReviewedPlatformFixture(new URL('../../../../',import.meta.url),{includeMfaRetirementMigration:true});
 const sources=[{path:new URL('../../../tests/sql/00_local_auth_fixture.sql',import.meta.url),text:reviewedPlatform.auth},...reviewedPlatform.rawMigrations.map(m=>({path:new URL('../../../migrations/'+m.name,import.meta.url),text:m.sql}))];
 const setup=await sql.reserve();
 let migrationBefore:any,migrationAfter:any;
 const migrationState=async()=>({
  capabilities:Array.from(await setup.unsafe('SELECT role,permission FROM app.admin_account_role_capabilities ORDER BY role,permission')),
  functions:Array.from(await setup.unsafe("SELECT p.oid::text AS oid,p.proname,p.proowner::text AS owner,p.prosecdef,p.proconfig,p.provolatile,p.proleakproof,p.proparallel,p.proisstrict FROM pg_proc p WHERE p.oid IN('private.assert_actor(text,text,text,bigint,bigint)'::regprocedure,'private.admin_invitation_v2_list(text,text,text,text)'::regprocedure,'private.record_mfa_projection(uuid)'::regprocedure) ORDER BY p.proname")),
  functionPrivileges:Array.from(await setup.unsafe("SELECT p.proname,a.grantor::text,a.grantee::text,coalesce(r.rolname,'PUBLIC') AS grantee_name,a.privilege_type,a.is_grantable FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a LEFT JOIN pg_roles r ON r.oid=a.grantee WHERE p.oid IN('private.assert_actor(text,text,text,bigint,bigint)'::regprocedure,'private.admin_invitation_v2_list(text,text,text,text)'::regprocedure,'private.record_mfa_projection(uuid)'::regprocedure) ORDER BY p.proname,a.grantor,a.grantee,a.privilege_type")),
  view:Array.from(await setup.unsafe("SELECT oid::text,relowner::text AS owner,relkind,reloptions,relacl::text AS acl FROM pg_class WHERE oid='app.assisted_sms_current_sessions'::regclass")),
 });
 try{
  await setup.unsafe('DROP SCHEMA IF EXISTS app CASCADE; DROP SCHEMA IF EXISTS private CASCADE; DROP SCHEMA IF EXISTS api CASCADE; DROP SCHEMA IF EXISTS auth CASCADE; DROP SCHEMA IF EXISTS realtime CASCADE');
  await reviewedPlatform.apply(async text=>{
   const retiring=text===reviewedPlatform.mfaRetirement.sql;
   if(retiring){migrationBefore=await migrationState();assertEquals((await setup.unsafe('SELECT count(*)::int AS n FROM private.collect_fence_control'))[0].n,0);}
   const result=await setup.unsafe(text);
   if(retiring){migrationAfter=await migrationState();assertEquals((await setup.unsafe('SELECT count(*)::int AS n FROM private.collect_fence_control'))[0].n,0);}
   return result;
  },{includeAuth:true});
  // Local GoTrue facts must agree with the confirmed email returned by /user.
  await setup.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
 }finally{setup.release();await initializeSqlFixture(sql);}
 const base={SUPABASE_URL:project,SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_mfa_fixture',ADMIN_ORIGIN:front,AUTH_MEMBER_REGISTRATION_ENABLED:'false',SESSION_KEY_ID:'synthetic-mfa-v1',SESSION_ENCRYPTION_KEY:btoa('m'.repeat(32))};
 const env=()=>({...base,DB:new PostgresDatabase(sql)});
 const tokens=new Map<string,any>(),calls:{path:string,method:string,body:any}[]=[];
 let race:((f:any)=>Promise<void>)|null=null,serial=0;
 const tokenFor=(f:any)=>{const value=btoa('{}')+'.'+btoa(JSON.stringify(f.claims))+'.synthetic-not-a-hosted-signature';tokens.set(value,f);f.token=value;return value;};
 const fixture=async(admin=true,age=2,role='staff')=>{
  const auth=crypto.randomUUID(),sid=crypto.randomUUID(),pid=crypto.randomUUID(),aid=crypto.randomUUID(),at=unix()-age,number=++serial,email=role==='owner'?'info@ikanisa.com':'mfa-'+number+'@example.invalid';
  await sql`insert into auth.users(id,email,email_confirmed_at)values(${auth},${email},now())`;
  await sql`insert into auth.sessions(id,user_id,aal,not_after)values(${sid},${auth},'aal1',now()+interval '1 hour')`;
  await sql`insert into auth.mfa_amr_claims(session_id,authentication_method,updated_at)values(${sid},'otp',to_timestamp(${at}))`;
  await sql`insert into app.users(id,email,public_id,full_name,member_type,created_at,updated_at)values(${pid},${email},${String(200000+serial)},'Synthetic MFA',${admin?'operator':'app'},${new Date().toISOString()},${new Date().toISOString()})`;
  await sql`insert into private.auth_principal_links(auth_user_id,user_id,proof_reference)values(${auth},${pid},'synthetic-managed-mfa')`;
  if(admin){await sql`insert into app.admin_users(id,email,role,status,password_hash,created_at,updated_at)values(${aid},${email},${role},'active','supabase-managed',${at},${at})`;
   await sql`insert into app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)values(${aid},${pid},'synthetic-mfa-approval',${new Date().toISOString()})`;}
  const f:any={auth,sid,pid,aid,email,claims:{sub:auth,session_id:sid,role:'authenticated',aud:'authenticated',aal:'aal1',iat:at,exp:unix()+3600,iss:project+'/auth/v1',amr:[{method:'otp',timestamp:at}]},user:{id:auth,email,email_confirmed_at:new Date().toISOString(),factors:[],app_metadata:{provider:'email'}}};
  tokenFor(f);f.session=()=>({access_token:f.token,refresh_token:'synthetic-refresh-'+sid,expires_in:3600,token_type:'bearer'});
  if(admin){const response=await issueAdminSession(post('/api/admin/auth/verify',{}),env(),f.session()),body=await response.json();assertEquals(response.status,200);f.cookie=response.headers.get('Set-Cookie')!.split(';')[0];f.csrf=body.csrfToken;}
  return f;
 };
 const addFactor=async(f:any,status='unverified')=>{
  const factor={id:crypto.randomUUID(),factor_type:'totp',status,friendly_name:'Collect Admin'};f.user.factors.push(factor);
  await sql`insert into auth.mfa_factors(id,user_id,status)values(${factor.id},${f.auth},${status})`;return factor;
 };
 globalThis.fetch=async(input:Request|string|URL,init?:RequestInit)=>{
  const request=input instanceof Request?input:new Request(input,init),url=new URL(request.url);assertEquals(url.origin,project,'No real provider network calls');
  const path=url.pathname.slice('/auth/v1'.length),body=await request.json().catch(()=>null),f=tokens.get(request.headers.get('Authorization')?.slice(7)??'');
  calls.push({path,method:request.method,body});
  if(path==='/user'&&f)return Response.json(f.user);
  if(path==='/verify'){
   const own=[...tokens.values()].find(value=>value.email===body.email);assert(own);if(race){const current=race;race=null;await current(own);}return Response.json(own.session());
  }
  if(path==='/logout'){assertEquals(url.searchParams.get('scope'),'local');return Response.json({});}
  throw new Error('Retired MFA must never reach managed factor transport: '+request.method+' '+path);
 };
 const call=async(f:any,path:string,body:unknown):Promise<Response>=>{
  try{const response=await handleAdminAccounts(post('/api/admin/auth/mfa/'+path,body,f.cookie,f.csrf),env());assert(response instanceof Response,'The actual Admin MFA handler must own the route');return response;}
  catch(error){if(error instanceof ApiError)return Response.json({code:error.code},{status:error.status});throw error;}
 };
 const effects=()=>calls.filter(call=>call.path.startsWith('/factors'));
 const reset=()=>{calls.length=0;};
 try{
  await t.step('real Admin user route normalizes absent provider factors without granting MFA',async()=>{
   reset();const f=await fixture();delete f.user.factors;
   const request=new Request(front+'/api/admin/auth/user',{headers:{Origin:front,'X-Collect-Requested-With':'collect-admin',Cookie:f.cookie}});
   const response=await handleAdminAccounts(request,env());assert(response instanceof Response);assertEquals(response.status,200);
   const result=await response.json();assertEquals(result.id,f.pid);assertEquals(result.auth_user_id,f.auth);assertEquals(result.factors,[]);
   assertEquals((await sql`select assurance_level,mfa_at from app.auth_sessions where id=${f.sid}`)[0],{assurance_level:1,mfa_at:null});
   assertEquals((await sql`select count(*)::int as n from app.auth_mfa_factors where user_id=${f.pid}`)[0].n,0);assertEquals(effects().length,0);
  });
  await t.step('present malformed provider factors fail unavailable without MFA or identity changes',async()=>{
   for(const malformed of [null,{},'[]',false,[null],[{}],[{id:'invalid',factor_type:'totp',status:'verified'}],[{id:crypto.randomUUID(),factor_type:'totp',status:'revoked'}],Array.from({length:129},()=>({id:crypto.randomUUID(),factor_type:'totp',status:'verified'}))]){
    reset();const f=await fixture();f.user.factors=malformed;
    const request=new Request(front+'/api/admin/auth/user',{headers:{Origin:front,'X-Collect-Requested-With':'collect-admin',Cookie:f.cookie}});
    const error=await assertRejects(()=>handleAdminAccounts(request,env()),ApiError,'Account details could not be confirmed. Try again.');
    assertEquals(error.status,503);assertEquals(error.code,'auth_user_unavailable');
    assertEquals(effects().length,0);assertEquals((await sql`select assurance_level,mfa_at from app.auth_sessions where id=${f.sid}`)[0],{assurance_level:1,mfa_at:null});
    assertEquals((await sql`select count(*)::int as n from app.auth_mfa_factors where user_id=${f.pid}`)[0].n,0);
    assertEquals((await sql`select count(*)::int as n from private.auth_principal_links where auth_user_id=${f.auth} and user_id=${f.pid}`)[0].n,1);
   }
  });
  await t.step('all retired routes reject methods and malformed bodies before session, database or provider work',async()=>{
   reset();let databaseCalls=0;
   const forbidden=()=>{databaseCalls++;throw new Error('Retired MFA must not access session/database authority');};
   const noAuthority={...base,DB:{prepare:forbidden,batch:forbidden,setClaims:forbidden}};
   for(const suffix of ['','enroll','challenge','verify','cancel-enrollment','unenroll','unknown/nested']){
    const route=suffix?'/'+suffix:'';
    for(const method of ['GET','POST','PUT','PATCH','DELETE','HEAD','OPTIONS']){
     const malformed=!['GET','HEAD'].includes(method)?{body:'{malformed'}:{};
     const member=new Request(front+'/v1/auth/mfa'+route,{method,headers:{'Content-Type':'application/json'},...malformed});
     const memberError=await assertRejects(()=>handleAuth(member,noAuthority),ApiError,'Verify your email to confirm sensitive changes.');
     assertEquals([memberError.status,memberError.code],[410,'mfa_not_available']);
     const admin=new Request(front+'/api/admin/auth/mfa'+route,{method,headers:{Origin:front,'Content-Type':'application/json','X-Collect-Requested-With':'collect-admin',Cookie:'__Host-collect_admin=invalid'},...malformed});
     const adminError=await assertRejects(()=>handleAdminAccounts(admin,noAuthority),ApiError,'Verify your email to confirm sensitive changes.');
     assertEquals([adminError.status,adminError.code],[410,'mfa_not_available']);
     assertEquals(databaseCalls,0);assertEquals(calls.length,0);
    }
   }
   const invalidOrigin=new Request(front+'/api/admin/auth/mfa/enroll',{method:'POST',headers:{Origin:'https://foreign.invalid','Content-Type':'application/json'},body:'{}'});
   const originError=await assertRejects(()=>handleAdminAccounts(invalidOrigin,noAuthority),ApiError);
   assertEquals(originError.status,403);assert(originError.code!=='mfa_not_available','Origin validation must still precede Admin retirement.');
   assertEquals(databaseCalls,0);assertEquals(calls.length,0);
   const unrelated=new Request(front+'/v1/auth/mfaX',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
   const unrelatedError=await assertRejects(()=>handleAuth(unrelated,noAuthority),ApiError);
   assertEquals(unrelatedError.status,404);assert(unrelatedError.code!=='mfa_not_available','Only the exact MFA namespace and its descendants are retired.');
   const unrelatedAdminError=await assertRejects(()=>handleAdminAccounts(post('/api/admin/auth/mfaX',{}),noAuthority),ApiError);
   assertEquals([unrelatedAdminError.status,unrelatedAdminError.code],[401,'unauthenticated']);
   assertEquals(databaseCalls,0);assertEquals(calls.length,0);
  });
  await t.step('retired authenticated MFA routes preserve factors, sessions, cookies and audit truth',async()=>{
   reset();const f=await fixture(),pending=await addFactor(f),verified=await addFactor(f,'verified');
   const snapshot=async()=>({
    nativeFactors:Array.from(await sql`select id,user_id,status from auth.mfa_factors where user_id=${f.auth} order by id`),
    nativeSession:Array.from(await sql`select id,user_id,aal,factor_id from auth.sessions where id=${f.sid}`),
    projectedSession:Array.from(await sql`select * from app.auth_sessions where id=${f.sid}`),
    projectedFactors:Array.from(await sql`select * from app.auth_mfa_factors where user_id=${f.pid} order by id`),
    cookies:Array.from(await sql`select * from app.admin_sessions where auth_session_id=${f.sid}`),
    bff:Array.from(await sql`select * from private.bff_sessions where auth_session_id=${f.sid}`),
    audit:Array.from(await sql`select * from app.admin_account_audit where subject_id=${f.aid} order by id`),
   });
   const before=await snapshot(),cookie=f.cookie,csrf=f.csrf;reset();
   for(const suffix of ['enroll','challenge','verify','cancel-enrollment','unenroll','unknown']){
    for(const factor of [pending,verified]){
     const response=await call(f,suffix,{factor_type:'totp',factor_id:factor.id,challenge_id:crypto.randomUUID(),code:'123456'});
     assertEquals(response.status,410);assertEquals((await response.json()).code,'mfa_not_available');
     assertEquals(response.headers.get('Set-Cookie'),null);assertEquals(f.cookie,cookie);assertEquals(f.csrf,csrf);
     assertEquals(calls.length,0);assertEquals(await snapshot(),before);
    }
   }
  });
  await t.step('SQL13 preserves catalog and object identities while revoking only the runtime projector grant',async()=>{
   assert(migrationBefore&&migrationAfter);assertEquals(migrationAfter.capabilities,migrationBefore.capabilities);assertEquals(migrationAfter.functions,migrationBefore.functions);assertEquals(migrationAfter.view,migrationBefore.view);
   assertEquals(migrationBefore.capabilities.filter((row:any)=>row.permission==='auth.mfa.enroll').map((row:any)=>row.role),['admin','owner','staff']);
   assertEquals(migrationBefore.functions.length,3);assertEquals(migrationBefore.view.length,1);assert(migrationBefore.view[0].reloptions.includes('security_invoker=true'));
   assert(migrationBefore.functionPrivileges.some((row:any)=>row.proname==='record_mfa_projection'&&row.grantee_name==='collect_runtime'&&row.privilege_type==='EXECUTE'));
   assertEquals(migrationAfter.functionPrivileges,migrationBefore.functionPrivileges.filter((row:any)=>!(row.proname==='record_mfa_projection'&&row.grantee_name==='collect_runtime'&&row.privilege_type==='EXECUTE')));
   const privilege=(await sql`select to_regprocedure('private.record_mfa_projection(uuid)') is not null as historical_function_present,has_function_privilege('collect_runtime','private.record_mfa_projection(uuid)','EXECUTE') as runtime_allowed`)[0];
   assertEquals(privilege,{historical_function_present:true,runtime_allowed:false});
  });
  await t.step('ordinary catalog UPDATE and DELETE remain immutable under the genuine OPEN fixture',async()=>{
   assertEquals((await sql`select private.collect_fence_owner_status() AS result`)[0].result.mode,'open');
   for(const statement of ["DELETE FROM app.admin_account_role_capabilities WHERE permission='auth.mfa.enroll'","UPDATE app.admin_account_role_capabilities SET permission=permission WHERE permission='auth.mfa.enroll'"]){
    const error=await assertRejects(()=>sql.unsafe(statement),Error,'approved_role_capabilities_immutable');assertEquals((error as any).code,'P0001');
    assertEquals(Array.from(await sql`select role,permission from app.admin_account_role_capabilities order by role,permission`),migrationBefore.capabilities);
   }
  });
  await t.step('all approved roles retain raw grants but cannot project or guard the retired permission',async()=>{
   for(const role of ['owner','admin','staff']){
    reset();const f=await fixture(true,2,role),current=env();
    const raw=Array.from(await sql`select permission from app.admin_account_role_capabilities where role=${role} order by permission`).map(row=>{assert(typeof row==='object'&&row!==null&&'permission' in row&&typeof row.permission==='string');return row.permission;});
    const granted=new Set(Array.from(await sql`select permission from app.admin_grants where user_id=${f.pid} order by permission`).map(row=>{assert(typeof row==='object'&&row!==null&&'permission' in row&&typeof row.permission==='string');return row.permission;}));
    // Owner assisted-SMS capabilities require the separately recorded access grant.
    assertEquals(raw.filter(permission=>!granted.has(permission)),role==='owner'?['assisted_sms.manage','assisted_sms.read']:[]);
    const expected=raw.filter(permission=>permission!=='auth.mfa.enroll'&&granted.has(permission));
    assert(raw.includes('auth.mfa.enroll'));assert(expected.length>0);
    assertEquals((await sql`select count(*)::int as n from app.admin_grants where user_id=${f.pid} and permission='auth.mfa.enroll'`)[0].n,1);
    const projected=await projectSession(current,{user:f.user,claims:f.claims},{surface:'admin'});assertEquals([...projected.permissions].sort(),expected);
    const request=new Request(front+'/api/admin/auth/session',{headers:{Origin:front,'X-Collect-Requested-With':'collect-admin',Cookie:f.cookie}}),account=await adminAccountSession(request,current);
    assertEquals(account.permissions,expected);
    const gate=permissionGuard(current,account,'auth.mfa.enroll');await assertRejects(()=>current.DB.batch([gate.statement,gate.remove]),Error,'admin_account_authority');
    const allowed=permissionGuard(current,account,expected[0]);await current.DB.batch([allowed.statement,allowed.remove]);
    const context=current.DB.prepare('SELECT private.set_admin_email_context(?::text,?::text,?::text,?::text) AS result').bind(account.id,account.token_hash,account.origin,account.public_id);
    await assertRejects(()=>current.DB.batch([context,current.DB.prepare('SELECT private.assert_actor(?::text) AS principal').bind('auth.mfa.enroll')]),Error,'permission_denied');
    const other=await current.DB.batch([context,current.DB.prepare('SELECT private.assert_actor(?::text) AS principal').bind(expected[0])]);assertEquals(other[1].results[0].principal,f.pid);
    const revoked=await assertRejects(()=>current.DB.prepare('SELECT private.record_mfa_projection(?::uuid) AS result').bind(f.sid).first(),Error,'permission denied for function record_mfa_projection');assertEquals((revoked as any).code,'42501');
    if(role==='owner'){
     const response=await handleAdminAccounts(new Request(front+'/api/admin/team',{headers:{Origin:front,'X-Collect-Requested-With':'collect-admin',Cookie:f.cookie}}),current);assert(response instanceof Response);assertEquals(response.status,200);
     const body=await response.json();for(const namedRole of ['owner','admin','staff'])assertEquals([...body.permissionsByRole[namedRole]].sort(),migrationBefore.capabilities.filter((row:any)=>row.role===namedRole&&row.permission!=='auth.mfa.enroll').map((row:any)=>row.permission));
    }
    assertEquals((await sql`select count(*)::int as n from app.admin_grants where user_id=${f.pid} and permission='auth.mfa.enroll'`)[0].n,1);assertEquals(effects().length,0);
   }
  });
  await t.step('newer OTP reservations block older fresh-code replay across all delivery outcomes',async()=>{
   for(const status of ['accepted','unknown','rejected','reserved']){
    reset();const f=await fixture(false),key=await digest('email:'+f.email),old=crypto.randomUUID(),latest=crypto.randomUUID(),at=unix();
    await sql`insert into private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status)values(${old},${key},'email',${f.email},'member',0,${at-120},${at+180},'accepted'),(${latest},${key},'email',${f.email},'member',0,${at-60},${at+240},${status})`;
    const before=calls.length;await assertRejects(()=>verifyOtp(env(),{challenge_id:old,code:'123456',surface:'member'}));assertEquals(calls.length,before);assertEquals((await sql`select attempts,consumed_at from private.supabase_otp_challenges where id=${old}`)[0],{attempts:0,consumed_at:null});
    if(['accepted','unknown'].includes(status)){
     // A newer ADMIN reservation is independent of this member challenge.
     await sql`insert into private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status)values(${crypto.randomUUID()},${key},'email',${f.email},'admin',0,${at},${at+300},'accepted')`;
     const result=await verifyOtp(env(),{challenge_id:latest,code:'123456',surface:'member'});assertEquals(result.user.id,f.pid);assertEquals(result.user.auth_user_id,f.auth);assert((await sql`select consumed_at from private.supabase_otp_challenges where id=${latest}`)[0].consumed_at!==null);
    }
   }
  });
  await t.step('resend racing provider verify cannot consume old admission or return a session',async()=>{
   reset();const f=await fixture(false),key=await digest('email:'+f.email),old=crypto.randomUUID(),at=unix();
   await sql`insert into private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status)values(${old},${key},'email',${f.email},'member',0,${at-120},${at+180},'accepted')`;
   race=async()=>{await sql`insert into private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status)values(${crypto.randomUUID()},${key},'email',${f.email},'member',0,${unix()},${unix()+300},'unknown')`;};
   await assertRejects(()=>verifyOtp(env(),{challenge_id:old,code:'123456',surface:'member'}));assertEquals((await sql`select consumed_at from private.supabase_otp_challenges where id=${old}`)[0].consumed_at,null);assertEquals(calls.filter(call=>call.path==='/verify').length,1);assertEquals(calls.filter(call=>call.path==='/logout').length,1);assertEquals((await sql`select count(*)::int as n from app.auth_sessions where id=${f.sid}`)[0].n,0);
  });
  await reviewedPlatform.parity();for(const source of sources)assertEquals(await Deno.readTextFile(source.path),source.text,'Schema inputs changed during qualification; rerun on frozen inputs');
 }finally{globalThis.fetch=originalFetch;await finishSqlFixtureWork();await sql.end({timeout:1});}
}});
