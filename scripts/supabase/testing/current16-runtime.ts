// Executed only by the local current16 preparer with a private, hashed run spec.
// Native SQL/transactions/roles are real. Managed Auth rows and FCM HTTP are
// declared synthetic fixtures; no hosted service or message recipient is used.
import assert from 'node:assert/strict';
import {readFile,open} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import postgres from 'npm:postgres@3.4.7';
import {validateCurrent16RunSpec,verifyCurrent16Sources} from './current16-integration.mjs';
import {connection,fenceConnection,PostgresDatabase} from '../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork,sqlFenceBackend} from '../../../supabase/functions/_shared/application-fence.js';
import {projectSession} from '../../../supabase/functions/_shared/domain/auth.js';
import {encrypt} from '../../../supabase/functions/_shared/domain/encryption.js';
import {digest} from '../../../supabase/functions/_shared/domain/core.js';
import {clientDiagnosticsRoute,diagnosticFingerprint,clientDiagnosticGroups} from '../../../supabase/functions/_shared/domain/client_diagnostics.js';
import {createFcmSender} from '../../../supabase/functions/_shared/fcm-notifications.js';
import {drainNotificationDeliveries} from '../../../supabase/functions/_shared/domain/notification_delivery.js';
import {retentionSchema,retentionSnapshot,erasableTables} from '../../../supabase/functions/_shared/domain/privacy_retention_catalog.js';
import {accountDatabase} from '../../../supabase/functions/_shared/domain/admin_accounts.js';
import {loadAdminEmailAccount} from '../../../supabase/functions/_shared/domain/admin_email_auth.js';
import {oversightHealthSql} from '../../../supabase/functions/_shared/domain/admin_oversight.js';
import {createScheduledHandler} from '../../../supabase/functions/_shared/serve.js';

const sha=(bytes:Uint8Array|string)=>createHash('sha256').update(bytes).digest('hex');
const unix=()=>Math.floor(Date.now()/1000);
const originalFetch=globalThis.fetch;
// These JavaScript APIs use null/default parameters without TypeScript
// annotations. The aliases preserve the actual implementations, not doubles.
const admitWork=openApplicationWork as (options:any)=>Promise<any>;
const NativeDatabase=PostgresDatabase as any;
const scopedAdmin=accountDatabase as any;
let externalCalls=0,syntheticCalls=0,sendCalls=0,stage='private_spec';
const cases:Array<{name:string,status:'pass'}>=[],observations:Record<string,unknown>={};
const pools=new Set<any>(),closures:any[]=[];
let spec:any,sourceInputs:any,normalOwner=false,normalRuntime=false,failure:any=null;
async function save(name:string,value:unknown){const file=await open(join(spec.output,name),'wx',0o600);try{await file.writeFile(JSON.stringify(value,null,2)+'\n');await file.sync();}finally{await file.close();}}
async function step(name:string,run:()=>Promise<void>){stage=name;await run();cases.push({name,status:'pass'});}

try{
 assert.equal(Deno.args.length,2);const [path,expected]=Deno.args;assert.equal(resolve(path),path);assert.match(expected,/^[a-f0-9]{64}$/);
 const bytes=await readFile(path);assert.equal(sha(bytes),expected);spec=JSON.parse(bytes.toString('utf8'));
 const target=validateCurrent16RunSpec(spec,path);assert(target);
 const inputBytes=await readFile(spec.inputs);assert.equal(sha(inputBytes),spec.inputs_sha256);sourceInputs=JSON.parse(inputBytes.toString('utf8'));
 assert.equal(sourceInputs.source_sha256,spec.source_sha256);assert.equal(sourceInputs.migrations.length,16);
 await verifyCurrent16Sources(sourceInputs.files);
 globalThis.fetch=()=>{externalCalls++;return Promise.reject(Error('Current16 qualification forbids external network calls'));};
 const owner=postgres(target.href,{max:1,prepare:false,ssl:false,onnotice:()=>{},types:{bigint:{to:20,from:[20],serialize:String,parse:Number}}});
 const business=connection(target.href),control=fenceConnection(target.href);pools.add(owner);pools.add(business);pools.add(control);
 const source=spec.source_sha256;
 const base:any={APP_ENVIRONMENT:'test',SUPABASE_URL:'https://rrlduytparvsjfmegalh.supabase.co',
  SUPABASE_PUBLISHABLE_KEY:'synthetic-current16-public',SUPABASE_SECRET_KEY:'synthetic-current16-private',COLLECT_DATABASE_URL:target.href,
  BUILD_SOURCE_ID:source,MOMO_PROCESSING_PAUSED:'true',AUTH_MEMBER_REGISTRATION_ENABLED:'false',
  DATA_KEY_ID:'current16-test',DATA_ENCRYPTION_KEY:btoa('n'.repeat(32)),SESSION_KEY_ID:'current16-test',SESSION_ENCRYPTION_KEY:btoa('n'.repeat(32))};
 async function work<T>(kind:'http_collect'|'http_admin'|'jobs',claims:any,body:(env:any)=>Promise<T>):Promise<T>{
  const admitted=await admitWork({backend:sqlFenceBackend(business,control),sourceSha256:source,kind});
  const db=new NativeDatabase(business,claims,admitted);const env={...base,DB:db,COLLECT_FENCE_WORK:admitted};
  try{
   const identity=await db.prepare("SELECT current_user AS current_role,session_user AS session_role,current_setting('collect.edge_verified') AS verified").first();
   assert.equal(identity.current_role,'collect_runtime');assert.equal(identity.session_role,'postgres');assert.equal(identity.verified,'true');normalRuntime=true;
   return await body(env);
  }finally{const outcome=await admitted.finish();assert.equal(outcome.applicationWorkFinished,true);assert.equal(outcome.providerSettlement,false);closures.push(outcome);}
 }
 const read=(query:string,...args:any[])=>work('jobs',{},env=>env.DB.prepare(query).bind(...args).all());
 const first=async(query:string,...args:any[])=>(await read(query,...args) as any).results[0];
 await step('complete current16 schema with normal owner and unchanged stopped protocol',async()=>{
  const identity=(await owner`SELECT current_user AS owner,session_user AS session,current_database() AS database,host(inet_server_addr()) AS host,inet_server_port() AS port,current_setting('server_version_num') AS version,(SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AS superuser,(SELECT rolbypassrls FROM pg_roles WHERE rolname=current_user) AS bypass,pg_get_userbyid((SELECT datdba FROM pg_database WHERE datname=current_database())) AS database_owner`)[0];
  assert.equal(identity.owner,'postgres');assert.equal(identity.session,'postgres');assert.equal(identity.database,target.pathname.slice(1));assert.equal(identity.host,'127.0.0.1');assert.equal(identity.port,Number(target.port));assert.equal(identity.version,'170010');assert.equal(identity.superuser,false);assert.equal(identity.bypass,false);assert.equal(identity.database_owner,'postgres');normalOwner=true;
  const counts=(await owner`SELECT (SELECT count(*)::int FROM pg_tables WHERE schemaname='app') AS app,(SELECT count(*)::int FROM pg_tables WHERE schemaname='private') AS private,(SELECT count(*)::int FROM pg_trigger WHERE tgname='collect_fence_statement_v1' AND tgenabled='A' AND tgtype=62) AS guards`)[0];
  assert.deepEqual({...counts},{app:99,private:22,guards:115});
  const state=(await owner`SELECT private.collect_fence_owner_status_v3() AS state`)[0].state;
  assert.equal(state.contractVersion,3);assert.equal(state.mode,'open');assert.equal(state.sourceSha256,source);assert.equal(state.epoch,1);assert.equal(state.rawActiveAdmissions,0);assert.equal(state.effectiveUnresolvedAdmissions,0);
  observations.schema={identity,counts,source_migration_files_edited:false,sql10_metadata_only_substitution:true,local_sql10:sourceInputs.local_sql10};
 });
 await step('new tables retain forced RLS, narrow privileges and no unfenced writes',async()=>{
  for(const table of ['client_diagnostic_reports','notification_deliveries']){
   const flags=(await owner.unsafe('SELECT relrowsecurity,relforcerowsecurity FROM pg_class WHERE oid=$1::regclass',['app.'+table]))[0];assert.equal(flags.relrowsecurity,true);assert.equal(flags.relforcerowsecurity,true);
   for(const role of ['anon','authenticated','service_role','collect_importer']){
    const allowed=(await owner`SELECT has_table_privilege(${role},${'app.'+table},'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') AS allowed`)[0].allowed;assert.equal(allowed,false,table+'/'+role);
   }
   await assert.rejects(owner.begin(async tx=>{await tx`SET LOCAL ROLE collect_runtime`;await tx.unsafe(table==='client_diagnostic_reports'?'DELETE FROM app.client_diagnostic_reports WHERE false':'UPDATE app.notification_deliveries SET updated_at=updated_at WHERE false');}),(error:any)=>error.code==='55000'&&error.message==='collect_fence_unavailable');
  }
  assert.equal((await owner`SELECT has_table_privilege('collect_runtime','app.notification_deliveries','DELETE') AS allowed`)[0].allowed,false);
  assert.equal((await owner`SELECT has_table_privilege('collect_runtime','app.client_diagnostic_reports','UPDATE') AS allowed`)[0].allowed,false);
 });
 await step('migration installation leaves optional services inactive and queues empty',async()=>{
  assert.equal((await owner`SELECT enabled FROM private.member_realtime_control WHERE singleton`)[0].enabled,false);
  assert.equal((await owner`SELECT to_regnamespace('cron') IS NULL AS no_cron,to_regnamespace('net') IS NULL AS no_net`)[0].no_cron,true);
  assert.equal((await first('SELECT count(*)::int AS n FROM app.notification_deliveries')).n,0);
  assert.equal((await first('SELECT count(*)::int AS n FROM app.client_diagnostic_reports')).n,0);
  assert.equal(externalCalls,0);
 });
 // Managed identity is seeded locally; it is never a claimed GoTrue/OTP send.
 await owner.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
 let serial=0;
 async function member(){
  const at=unix()-2,stamp=new Date().toISOString(),auth=randomUUID(),sid=randomUUID(),uid=randomUUID(),cid=randomUUID();
  const email='current16-'+(++serial)+'@example.invalid';
  await owner`INSERT INTO auth.users(id,email,email_confirmed_at)VALUES(${auth},${email},now())`;
  await owner`INSERT INTO auth.sessions(id,user_id,aal,not_after)VALUES(${sid},${auth},'aal1',now()+interval '1 hour')`;
  await owner`INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at)VALUES(${uid},${email},${String(700000+serial)},'Synthetic current16 member','app',${stamp},${stamp})`;
  await owner`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${auth},${uid},'synthetic-current16-no-provider')`;
  const claims={sub:auth,session_id:sid,role:'authenticated',aal:'aal1',iat:at,exp:at+3600,amr:[{method:'otp',timestamp:at}]};
  const actor=await work('http_collect',claims,env=>projectSession(env,{claims,user:{id:auth,email,email_confirmed_at:stamp,app_metadata:{provider:'email'}}}));
  await owner`INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)VALUES(${cid},${'current16-'+cid},${uid},'Private current16 contribution group','voluntary',${stamp},${stamp})`;
  await owner`INSERT INTO app.memberships(id,collection_id,user_id,role,joined_at)VALUES(${randomUUID()},${cid},${uid},'owner',${stamp})`;
  await owner`INSERT INTO app.notification_preferences(user_id,updated_at)VALUES(${uid},${stamp})`;
  return {auth,sid,uid,cid,claims,actor,email};
 }
 const diagnosticMember=await member();
 const report:any={collect_diagnostic:1,code:'frameworkFailure',severity:'error',surface:'member',environment:'production',build_version:'1.2.4+23',source_revision:source,report_id:randomUUID(),occurrences:2,attempt:1,elapsed_ms:1000};report.fingerprint=await diagnosticFingerprint(report);
 const reportRequest=(value:any)=>new Request('https://synthetic.invalid/v1/diagnostics',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({contract_version:1,reports:[value]})});
 await step('authenticated diagnostics replay uses actual current16 transactions without identity leakage',async()=>{
  for(let i=0;i<2;i++)await work('http_collect',diagnosticMember.claims,async env=>assert.equal((await clientDiagnosticsRoute(reportRequest(report),env,diagnosticMember.actor))?.status,202));
  const rows=(await read('SELECT * FROM app.client_diagnostic_reports') as any).results;assert.equal(rows.length,1);const stored=JSON.stringify(rows);
  for(const value of [diagnosticMember.auth,diagnosticMember.sid,diagnosticMember.uid,diagnosticMember.email])assert.equal(stored.includes(value),false);
  await work('http_collect',diagnosticMember.claims,async env=>assert.equal(Number((await clientDiagnosticGroups(env))[0].occurrences),2));
 });
 await step('diagnostic validation and revoked managed session refuse before a new report',async()=>{
  await assert.rejects(()=>work('http_collect',diagnosticMember.claims,env=>clientDiagnosticsRoute(reportRequest({...report,raw_error:'PRIVATE_SYNTHETIC_TEXT'}),env,diagnosticMember.actor)),(error:any)=>error.code==='invalid_diagnostic');
  await owner`UPDATE app.auth_sessions SET revoked_at=${unix()},revocation_reason='synthetic-current16' WHERE id=${diagnosticMember.sid}`;
  await assert.rejects(()=>work('http_collect',diagnosticMember.claims,env=>clientDiagnosticsRoute(reportRequest(report),env,diagnosticMember.actor)),(error:any)=>error.status===403);
  assert.equal((await first('SELECT count(*)::int AS n FROM app.client_diagnostic_reports')).n,1);
 });
 const admin:any={uid:randomUUID(),auth:randomUUID(),sid:randomUUID(),aid:randomUUID(),public:randomUUID(),at:unix()-2};
 const adminStamp=new Date().toISOString(),origin='https://current16-admin.example.invalid',cookieHash=await digest('synthetic-current16-admin-cookie');
 await owner`INSERT INTO auth.users(id,email,email_confirmed_at)VALUES(${admin.auth},'info@ikanisa.com',now())`;
 await owner`INSERT INTO auth.sessions(id,user_id,aal,not_after)VALUES(${admin.sid},${admin.auth},'aal1',now()+interval '1 hour')`;
 await owner`INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at)VALUES(${admin.uid},'info@ikanisa.com','799999','Synthetic current16 reviewer','operator',${adminStamp},${adminStamp})`;
 await owner`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${admin.auth},${admin.uid},'synthetic-current16-reviewer')`;
 await owner`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES(${admin.sid},${admin.uid},'admin',${admin.at},${admin.at},${admin.at+3600})`;
 await owner`INSERT INTO app.admin_users(id,email,role,status,password_hash,created_at,updated_at)VALUES(${admin.aid},'info@ikanisa.com','owner','active','!managed-supabase!',${admin.at},${admin.at})`;
 await owner`INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)VALUES(${admin.aid},${admin.uid},'synthetic-current16',${adminStamp})`;
 await owner`INSERT INTO app.admin_grants(user_id,permission,granted_by,granted_at)VALUES(${admin.uid},'privacy.review','synthetic-current16',${adminStamp}) ON CONFLICT DO NOTHING`;
 await owner`INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)SELECT ${cookieHash},${admin.public},id,auth_version,${admin.sid},${origin},${admin.at},${admin.at+3600} FROM app.admin_users WHERE id=${admin.aid}`;
 await owner`INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)VALUES(${cookieHash},${admin.auth},${admin.sid},'{}')`;
 admin.claims={sub:admin.auth,session_id:admin.sid,role:'authenticated',aal:'aal1',iat:admin.at,exp:admin.at+3600,amr:[{method:'otp',timestamp:admin.at}]};
 const account:any=(await owner`SELECT a.*,c.token_hash,c.public_id,c.origin,c.auth_session_id,c.issued_assurance_level,c.issued_mfa_at,c.issued_mfa_factor_id,l.user_id AS principal_id,b.auth_user_id::text AS auth_user_id FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id JOIN app.admin_sessions c ON c.user_id=a.id JOIN private.bff_sessions b ON b.token_hash=c.token_hash WHERE a.id=${admin.aid}`)[0];account.permissions=['privacy.review'];
 await step('SQL12 original-email proof and SQL13 retirement remain current under SQL16',async()=>{
  const challenge=randomUUID(),hash=await digest('email:info@ikanisa.com');
  await owner`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)VALUES(${admin.sid},'otp',to_timestamp(${admin.at}))`;
  await owner`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)VALUES(${challenge},${hash},'email','info@ikanisa.com','admin',0,${admin.at-1},${admin.at+299},1,${admin.at},'accepted')`;
  await work('http_admin',admin.claims,async env=>{
   await env.DB.prepare('SELECT private.admin_email_record_initial(?,?,?,?,?) AS result').bind(account.id,account.token_hash,account.origin,account.public_id,challenge).first();
   await loadAdminEmailAccount(env,account);
   const proof=await env.DB.prepare('SELECT private.admin_email_status(?,?,?,?) AS result').bind(account.id,account.token_hash,account.origin,account.public_id).first('result');
   assert.equal(proof.email_verified_at,admin.at);assert(proof.proof_id);observations.admin_email={email_verified_at:proof.email_verified_at,proof_present:true,managed_email_fixture:true,real_email_sent:false};
  });
  // SQL13 preserves immutable historical capability/grant rows. Effective
  // enrollment is retired by executable authority, not by deleting evidence.
  assert.equal((await owner`SELECT has_function_privilege('collect_runtime','private.record_mfa_projection(uuid)','EXECUTE') AS allowed`)[0].allowed,false);
  await assert.rejects(()=>work('http_admin',admin.claims,env=>env.DB.prepare("SELECT private.assert_actor('auth.mfa.enroll')").first()),(error:any)=>error.code==='42501'&&error.message==='permission_denied');
 });
 // Deliberately use the SHIPPING accountDatabase wrapper. The test-only
 // adminEmailFixtureDatabase can mask a missing same-transaction context.
 await step('shipping Admin wrapper reads the complete app and private retention catalogs',async()=>{
  await work('http_admin',admin.claims,async env=>{
   const scoped=scopedAdmin(env,account,'privacy.review',{mfa:true,fresh:true});
   const catalog=await retentionSchema(scoped);assert.equal(catalog.profile,'notifications16');assert.equal(catalog.privateInventory.schema_profile,'stopped_admission14');
   assert.equal(catalog.tables.length,99);assert.equal(erasableTables.includes('notification_deliveries'),false);assert.equal(erasableTables.includes('client_diagnostic_reports'),false);
   observations.retention={profile:catalog.profile,private_profile:catalog.privateInventory.schema_profile,tables:catalog.tables.length,sha256:catalog.sha256,uses_shipping_account_database:true};
  });
 });
 const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
 const privateBytes=new Uint8Array(await crypto.subtle.exportKey('pkcs8',pair.privateKey)),pem='-----BEGIN PRIVATE KEY-----\n'+btoa(String.fromCharCode(...privateBytes)).match(/.{1,64}/g)!.join('\n')+'\n-----END PRIVATE KEY-----\n';
 const project='synthetic-collect',androidPackage='app.cool.mobile',admittedFrom=unix()-3600;
 const admission={contract:'collect.android-push.v1',source_sha256:source,approval_sha256:'c'.repeat(64),project_id:project,android_package:androidPackage,admitted_from:admittedFrom,batch_limit:1};
 const pushEnv={COLLECT_PUSH_ENABLED:'true',COLLECT_JOBS_PUSH_APPROVAL_SHA256:admission.approval_sha256,COLLECT_PUSH_ADMITTED_FROM:String(admittedFrom),FCM_PROJECT_ID:project,FCM_ANDROID_PACKAGE:androidPackage,
  FCM_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:project,private_key_id:'synthetic-current16-only',client_email:'current16@'+project+'.iam.gserviceaccount.com',private_key:pem,token_uri:'https://oauth2.googleapis.com/token'})};
 async function event(){
  const person=await member(),eid=randomUUID(),device=randomUUID(),token='synthetic-current16-device-'+device,stamp=new Date((unix()-2)*1000).toISOString(),deviceAt=new Date((unix()-5)*1000).toISOString();
  const ciphertext=await encrypt(base,new TextEncoder().encode(token),'notification:'+device),hash=await digest(token);
  await owner`INSERT INTO app.notification_devices(id,user_id,token_hash,owner_session_id,provider,token_ciphertext,platform,created_at,updated_at)VALUES(${device},${person.uid},${hash},${person.sid},'fcm',${ciphertext},'android',${deviceAt},${deviceAt})`;
  await owner`INSERT INTO app.notification_events(id,user_id,event_type,title,body,data_json,status,created_at)VALUES(${eid},${person.uid},'contribution','Private financial title','Private RWF 99999',${JSON.stringify({collection_id:person.cid,amount_minor:99999})},'pending',${stamp})`;
  return {...person,eid,device};
 }
 async function drain(options:{onOauth?:()=>Promise<void>,unknown?:boolean,disabled?:boolean}={}){
  return work('jobs',{},async env=>{
   Object.assign(env,pushEnv);
   env.FCM=createFcmSender(env,{track:promise=>env.COLLECT_FENCE_WORK.waitUntil(promise),onUncertain:label=>env.COLLECT_FENCE_WORK.unknown(label),fetchImpl:(url,init)=>{
    const oauth=String(url)==='https://oauth2.googleapis.com/token';assert(oauth||String(url)==='https://fcm.googleapis.com/v1/projects/'+project+'/messages:send');
    return env.COLLECT_FENCE_WORK.dispatch(oauth?'push_oauth':'push',async()=>{
     syntheticCalls++;
     if(oauth){await options.onOauth?.();return Response.json({access_token:'synthetic-current16-token',token_type:'Bearer',expires_in:3600});}
     sendCalls++;const payload=JSON.parse(String(init?.body));assert.equal(payload.validate_only,false);
     assert.deepEqual(payload.message.notification,{title:'Collect',body:'Open Collect to view your updates.'});
     assert.deepEqual(Object.keys(payload.message.data).sort(),['collect_event_id','collect_push_version','deep_link','recipient_id','type']);
     assert.equal(payload.message.data.deep_link,'/activity');assert.equal(payload.message.data.collect_push_version,'2');assert.equal(payload.message.android.notification.visibility,'PRIVATE');
     return options.unknown?Response.json({unexpected:'synthetic ambiguous response'}):Response.json({name:'projects/'+project+'/messages/current16-'+sendCalls});
    });
   }});
   if(options.disabled)env.COLLECT_PUSH_ENABLED='false';
   return drainNotificationDeliveries(env,{limit:1,admission});
  });
 }
 await step('default-disabled push leaves a committed event without provider or outbox work',async()=>{
  const before=syntheticCalls;await event();const result=await drain({disabled:true});assert.equal(result.status,'disabled');assert.equal(result.processed,0);assert.equal(syntheticCalls,before);assert.equal((await first('SELECT count(*)::int AS n FROM app.notification_deliveries')).n,0);
 });
 await step('actual outbox, serializer and adapter accept one event once under current16',async()=>{
  assert.deepEqual((await drain()).results,[{state:'accepted'}]);const before=syntheticCalls;assert.equal((await drain()).processed,0);assert.equal(syntheticCalls,before);
  const stored=await first("SELECT state,attempt_count,attempt_log FROM app.notification_deliveries WHERE state='accepted'");assert.equal(stored.attempt_count,1);assert.equal(stored.attempt_log[0].source_sha256,source);assert(stored.attempt_log[0].send_started_at>0);
  await assert.rejects(()=>read("UPDATE app.notification_deliveries SET state='retry' WHERE state='accepted'"),(error:any)=>error.code==='42501');
  await assert.rejects(()=>read("DELETE FROM app.notification_deliveries WHERE state='accepted'"),(error:any)=>error.code==='42501');
 });
 await step('current consent after OAuth prevents FCM send-start across the full migration chain',async()=>{
  const f=await event(),before=sendCalls;const result=await drain({onOauth:async()=>{await owner`UPDATE app.notification_preferences SET push_enabled=0 WHERE user_id=${f.uid}`;}});
  assert.deepEqual(result.results,[{state:'suppressed'}]);assert.equal(sendCalls,before);const stored=await first('SELECT attempt_log,last_error FROM app.notification_deliveries WHERE event_id=?',f.eid);assert.equal(stored.last_error,'authority_changed');assert.equal(stored.attempt_log[0].send_started_at,undefined);
 });
 let unknownSubject:any;
 await step('unknown FCM result is durable, not retried, and retains the application obligation',async()=>{
  unknownSubject=await event();assert.deepEqual((await drain({unknown:true})).results,[{state:'unknown'}]);const before=syntheticCalls;assert.equal((await drain()).processed,0);assert.equal(syntheticCalls,before);
  const row=await first('SELECT state,last_error,attempt_count FROM app.notification_deliveries WHERE event_id=?',unknownSubject.eid);assert.equal(row.state,'unknown');assert.equal(row.last_error,'delivery_unconfirmed');assert.equal(row.attempt_count,1);
  assert(closures.some(value=>value.uncertainDispatches===1&&value.reason==='completed_with_unknown_obligation'));
 });
 await step('shipping privacy inventory retains unknown push after original event and device erase',async()=>{
  await owner`DELETE FROM app.notification_events WHERE id=${unknownSubject.eid}`;await owner`DELETE FROM app.notification_devices WHERE id=${unknownSubject.device}`;
  await work('http_admin',admin.claims,async env=>{
   const snapshot:any=await retentionSnapshot(scopedAdmin(env,account,'privacy.review',{mfa:true,fresh:true}),unknownSubject.uid);
   assert.equal(snapshot.summary.tables.notification_deliveries.count,1);assert.equal(snapshot.summary.in_flight_unresolved,true);assert.equal(snapshot.rows.notification_deliveries[0].state,'unknown');
   observations.retention_unknown={queue_count:1,in_flight_unresolved:true,original_erasable_sources_absent:true};
  });
  const before=syntheticCalls;assert.equal((await drain()).processed,0);assert.equal(syntheticCalls,before);
 });
 await step('all seven shipping oversight projections execute against exact current16',async()=>{
  await work('jobs',{},async env=>{const health=await env.DB.batch(oversightHealthSql.map(sql=>env.DB.prepare(sql)));assert.equal(health.length,7);assert(health.every((row:any)=>row.results.length===1));const queue=health[6].results[0];assert.equal(queue.accepted,1);assert.equal(queue.suppressed,1);assert.equal(queue.unknown,1);observations.delivery_health=queue;});
 });
 await step('actual maintenance handler defaults to paused receipts and disabled push',async()=>{
  const jobs:any[]=[];const errors:any[]=[];
  const handler=createScheduledHandler(()=>({...base,COLLECT_JOB_TOKEN:'synthetic-current16-jobs'}),undefined,undefined,{
   openWork:async options=>{const value=await admitWork(options);jobs.push(value);return value;},reportHealth:value=>{errors.push(value);return true;}});
  const before=syntheticCalls;const response=await handler(new Request('https://synthetic.invalid/functions/v1/collect-jobs',{method:'POST',headers:{Authorization:'Bearer synthetic-current16-jobs','Content-Type':'application/json'},body:JSON.stringify({dispatch_id:randomUUID()})}));
  const result=await response.json();for(const item of jobs)closures.push(await item.finish());
  assert.equal(response.status,200,JSON.stringify(result));assert.equal(result.processing.paused,true);assert.equal(result.notifications.status,'disabled');assert.equal(result.maintenance.status,'complete');assert.equal(result.diagnostics.status,'complete');assert.equal(errors.length,0);assert.equal(syntheticCalls,before);assert.equal(externalCalls,0);observations.maintenance=result;
 });
 await step('shipping retention refuses revoked current Admin access after earlier successful proof',async()=>{
  await owner`UPDATE app.admin_sessions SET expires_at=${unix()-1} WHERE token_hash=${account.token_hash}`;
  await assert.rejects(()=>work('http_admin',admin.claims,env=>retentionSchema(scopedAdmin(env,account,'privacy.review',{mfa:true,fresh:true}))),(error:any)=>['admin_access_changed','recent_email_sign_in_required'].includes(error.code)||error.message==='admin_email_denied');
 });
 await step('current16 financial rows remain unchanged and v3 quiesce blocks fresh runtime admission',async()=>{
  const counts=await first('SELECT (SELECT count(*)::int FROM app.payments) AS payments,(SELECT count(*)::int FROM app.ledger_entries) AS ledger');assert.deepEqual(counts,{payments:0,ledger:0});
  const status=(await owner`SELECT private.collect_fence_owner_status_v3() AS state`)[0].state;assert.equal(status.rawActiveAdmissions,0);assert.equal(status.effectiveUnresolvedAdmissions,0);
  const operation=randomUUID();await owner`SELECT private.collect_fence_begin_quiesce(${operation},1,${source})`;
  const fenced=(await owner`SELECT private.collect_fence_drain_v3(${operation},1,${source}) AS state`)[0].state;assert.equal(fenced.mode,'fenced');assert.equal(fenced.providerSettlement,false);
  await assert.rejects(()=>admitWork({backend:sqlFenceBackend(business,control),sourceSha256:source,kind:'jobs'}),(error:any)=>error.code==='application_fenced');
  observations.final_fence={mode:fenced.mode,epoch:fenced.epoch,providerSettlement:fenced.providerSettlement,retainedUnknownObligations:fenced.retainedUnknownObligations,rawActiveAdmissions:fenced.rawActiveAdmissions};
 });
 await verifyCurrent16Sources(sourceInputs.files);assert.equal(externalCalls,0);stage='complete';
}catch(error){
 const value=error as any;
 failure={stage,type:value?.constructor?.name??'Error',code:typeof value.code==='string'&&/^[a-zA-Z0-9_]{1,80}$/.test(value.code)?value.code:null,
  message:typeof value.message==='string'&&/^[a-z][a-z0-9_]{1,100}$/.test(value.message)?value.message:'CURRENT16_NATIVE_ASSERTION_UNCONFIRMED'};
}finally{
 globalThis.fetch=originalFetch;
 for(const pool of pools)try{await pool.end({timeout:2});}catch{failure??={stage:'pool_cleanup',type:'Error',code:null,message:'CURRENT16_POOL_CLOSE_UNCONFIRMED'};}
}
if(spec){
 await save('CASES.json',cases);await save('OBSERVATIONS.json',observations);await save('WORK-CLOSURES.json',closures);
 const result={format:'collect.current16.native.v1',status:failure?'FAIL':'PASS',failure,cases:cases.length,migration_count:sourceInputs?.migrations?.length??0,
  source_sha256:spec.source_sha256,normal_owner:normalOwner,normal_runtime:normalRuntime,fixture_preserved:true,external_provider_calls:externalCalls,
  synthetic_provider_calls:syntheticCalls,hosted_acceptance:false,legacy_sql_gates_closed:false,financial_posting_acceptance:false};
 await save('NATIVE-RESULT.json',result);console.log(JSON.stringify(result));if(failure)Deno.exitCode=1;
}else{console.error(JSON.stringify({status:'FAIL',code:'CURRENT16_PRIVATE_SPEC_UNCONFIRMED'}));Deno.exitCode=1;}
