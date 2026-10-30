import {assert,assertEquals,assertRejects} from 'jsr:@std/assert@1.0.14';
import {loadReviewedPlatformFixture} from '../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import {connection,PostgresDatabase,initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest,SYNTHETIC_FENCE_SOURCE} from './helpers/fenced-unit.js';
import {projectSession} from './helpers/module-domain-auth.js';
import {encrypt} from './helpers/module-domain-encryption.js';
import {fixtureAdminAccount,establishInitialAdminEmail,adminEmailFixtureDatabase} from './helpers/admin-email-fixture.js';
import {digest} from '../domain/core.js';
import {createFcmSender} from '../fcm-notifications.js';
import {drainNotificationDeliveries} from '../domain/notification_delivery.js';
import {retentionSchema,retentionSnapshot,erasableTables} from '../domain/privacy_retention_catalog.js';
import {oversightHealthSql} from '../domain/admin_oversight.js';

// Actual PostgreSQL17, production SQL, source fence, encrypted device tokens,
// managed-session projection, durable worker and FCM serializer. Only provider
// HTTP I/O and explicitly identified lost-reply boundaries are synthetic.
const database=Deno.env.get('COLLECT_NOTIFICATION_DELIVERY_TEST_DATABASE_URL');
const unix=()=>Math.floor(Date.now()/1000),project='synthetic-collect',androidPackage='app.cool.mobile';
const authOrigin='https://rrlduytparvsjfmegalh.supabase.co';
const oauthUrl='https://oauth2.googleapis.com/token',sendUrl='https://fcm.googleapis.com/v1/projects/'+project+'/messages:send';
const oauth=()=>Response.json({access_token:'synthetic-oauth-token-never-sent',token_type:'Bearer',expires_in:3600});

fencedTest({name:'Android notification delivery: actual PostgreSQL obligations and provider-contract boundary',sanitizeResources:false,sanitizeOps:false,fn:async(t)=>{
 assert(database,'COLLECT_NOTIFICATION_DELIVERY_TEST_DATABASE_URL is mandatory; this suite never silently skips');
 const target=new URL(database);
 assert(['postgres:','postgresql:'].includes(target.protocol)&&target.hostname==='127.0.0.1'&&target.username==='collect_test'&&
  target.pathname==='/collect_notification_delivery_test'&&!target.search&&!target.hash&&
  ((target.password==='collect_local_fixture_only'&&(target.port==='55439'||Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'&&target.port==='55441'))||
   Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'&&target.port==='55443'&&target.password.length>0),
  'Only the exclusive synthetic notification-delivery loopback database is allowed');
 const reviewed=await loadReviewedPlatformFixture(new URL('../../../../',import.meta.url)),sql=connection(database),originalFetch=globalThis.fetch;
 assert(reviewed.clientDiagnostics&&reviewed.notificationDelivery,'Explicit reviewed additive SQL15/16 are required');
 const setup=await sql.reserve();try{
  await setup.unsafe('DROP SCHEMA IF EXISTS app CASCADE; DROP SCHEMA IF EXISTS private CASCADE; DROP SCHEMA IF EXISTS api CASCADE; DROP SCHEMA IF EXISTS auth CASCADE; DROP SCHEMA IF EXISTS realtime CASCADE');
  await reviewed.apply(text=>setup.unsafe(text),{includeAuth:true});
  await setup.unsafe(reviewed.clientDiagnostics.sql);await setup.unsafe(reviewed.notificationDelivery.sql);
  await setup.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
 }finally{setup.release();await initializeSqlFixture(sql);}
 globalThis.fetch=()=>{throw Error('This suite must never contact any real provider');};
 const pair=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
 const exported=new Uint8Array(await crypto.subtle.exportKey('pkcs8',pair.privateKey));
 const pem='-----BEGIN PRIVATE KEY-----\n'+btoa(String.fromCharCode(...exported)).match(/.{1,64}/g)!.join('\n')+'\n-----END PRIVATE KEY-----\n';
 const admittedFrom=unix()-3600;
 const admission={contract:'collect.android-push.v1',source_sha256:SYNTHETIC_FENCE_SOURCE,approval_sha256:'b'.repeat(64),project_id:project,android_package:androidPackage,admitted_from:admittedFrom,batch_limit:1};
 const base={SUPABASE_URL:authOrigin,SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_notification_fixture',AUTH_MEMBER_REGISTRATION_ENABLED:'false',
  BUILD_SOURCE_ID:SYNTHETIC_FENCE_SOURCE,SESSION_KEY_ID:'push-test-v1',SESSION_ENCRYPTION_KEY:btoa('n'.repeat(32)),DATA_KEY_ID:'push-test-v1',DATA_ENCRYPTION_KEY:btoa('n'.repeat(32)),
  COLLECT_PUSH_ENABLED:'true',COLLECT_PUSH_ADMITTED_FROM:String(admittedFrom),COLLECT_JOBS_PUSH_APPROVAL_SHA256:admission.approval_sha256,
  FCM_PROJECT_ID:project,FCM_ANDROID_PACKAGE:androidPackage,
  FCM_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:project,private_key_id:'synthetic-push-key',client_email:'synthetic@'+project+'.iam.gserviceaccount.com',private_key:pem,token_uri:oauthUrl})};
 const db=new PostgresDatabase(sql);
 const env=()=>({...base,DB:db});let serial=0,oauthCalls=0,sendCalls=0;
 // Full retention inspection keeps its production fresh-email requirement.
 // Seed a managed local owner and establish actual SQL11 initial-email proof;
 // a job/member context must never gain this permission through test stubbing.
 const owner={uid:crypto.randomUUID(),auth:crypto.randomUUID(),sid:crypto.randomUUID(),aid:crypto.randomUUID(),public:crypto.randomUUID(),at:unix()-2};
 const ownerStamp=new Date().toISOString(),ownerOrigin='https://notification-retention.example.invalid',ownerHash=await digest('synthetic-notification-owner-cookie');
 await sql`insert into auth.users(id,email,email_confirmed_at)values(${owner.auth},'info@ikanisa.com',now())`;
 await sql`insert into auth.sessions(id,user_id,aal,not_after)values(${owner.sid},${owner.auth},'aal1',now()+interval '1 hour')`;
 await sql`insert into app.users(id,email,public_id,full_name,member_type,created_at,updated_at)values(${owner.uid},'info@ikanisa.com','890000','Synthetic retained-copy owner','operator',${ownerStamp},${ownerStamp})`;
 await sql`insert into private.auth_principal_links(auth_user_id,user_id,proof_reference)values(${owner.auth},${owner.uid},'synthetic-notification-owner')`;
 await sql`insert into app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)values(${owner.sid},${owner.uid},'admin',${owner.at},${owner.at},${owner.at+3600})`;
 await sql`insert into app.admin_users(id,email,role,status,password_hash,created_at,updated_at)values(${owner.aid},'info@ikanisa.com','owner','active','!managed-supabase!',${owner.at},${owner.at})`;
 await sql`insert into app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)values(${owner.aid},${owner.uid},'synthetic-fixture',${ownerStamp})`;
 await sql`insert into app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)select ${ownerHash},${owner.public},id,auth_version,${owner.sid},${ownerOrigin},${owner.at},${owner.at+3600} from app.admin_users where id=${owner.aid}`;
 await sql`insert into private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)values(${ownerHash},${owner.auth},${owner.sid},'{}')`;
 const ownerClaims={sub:owner.auth,session_id:owner.sid,role:'authenticated',aal:'aal1',iat:owner.at,exp:owner.at+3600,amr:[{method:'otp',timestamp:owner.at}]};
 const ownerDb=new PostgresDatabase(sql,ownerClaims),ownerAccount=await fixtureAdminAccount(sql,ownerDb,[owner.aid,ownerHash,ownerOrigin,owner.public]);
 await establishInitialAdminEmail(sql,ownerDb,ownerAccount);
 const retentionEnv={...base,DB:adminEmailFixtureDatabase(ownerDb,ownerAccount),ADMIN_ACCOUNT:ownerAccount};
 const sender=(options:{onOauth?:()=>Promise<void>,onSend?:(message:any)=>Promise<Response>}={})=>createFcmSender(base,{fetchImpl:async(url,init)=>{
  assert([oauthUrl,sendUrl].includes(String(url)),'Only the two fixed synthetic provider interfaces are permitted');
  if(url===oauthUrl){oauthCalls++;await options.onOauth?.();return oauth();}
  sendCalls++;const payload=JSON.parse(init!.body as string);assertEquals(payload.validate_only,false);
  assertEquals(payload.message.notification,{title:'Collect',body:'Open Collect to view your updates.'});
  assertEquals(Object.keys(payload.message.data).sort(),['collect_event_id','collect_push_version','deep_link','recipient_id','type']);
  return options.onSend?options.onSend(payload.message):Response.json({name:'projects/'+project+'/messages/synthetic-'+sendCalls});
 }});
 const drain=(fcm=sender(),overrides:any={})=>drainNotificationDeliveries({...env(),FCM:fcm,...overrides},{limit:1,admission});
 const row=async(event:string)=>(await sql`select * from app.notification_deliveries where event_id=${event} order by id`)[0];
 const fixture=async({devices=1,eventAge=2}:{devices?:number,eventAge?:number}={})=>{
  const auth=crypto.randomUUID(),sid=crypto.randomUUID(),uid=crypto.randomUUID(),cid=crypto.randomUUID(),eid=crypto.randomUUID(),at=unix()-5;
  const email='push-'+(++serial)+'@example.invalid',stamp=new Date().toISOString(),deviceStamp=new Date((unix()-10)*1000).toISOString();
  await sql`insert into auth.users(id,email,email_confirmed_at)values(${auth},${email},now())`;
  await sql`insert into auth.sessions(id,user_id,aal,not_after)values(${sid},${auth},'aal1',now()+interval '1 hour')`;
  await sql`insert into app.users(id,email,public_id,full_name,member_type,created_at,updated_at)values(${uid},${email},${String(800000+serial)},'Synthetic Notification Member','app',${stamp},${stamp})`;
  await sql`insert into private.auth_principal_links(auth_user_id,user_id,proof_reference)values(${auth},${uid},'synthetic-notification-fixture')`;
  const claims={sub:auth,session_id:sid,role:'authenticated',aud:'authenticated',aal:'aal1',iat:at,exp:unix()+3600,iss:authOrigin+'/auth/v1',amr:[{method:'otp',timestamp:at}]};
  await projectSession(env(),{user:{id:auth,email,email_confirmed_at:stamp,app_metadata:{provider:'email'}},claims,token:btoa('{}')+'.'+btoa(JSON.stringify(claims))+'.synthetic-not-a-hosted-signature'});
  await sql`insert into app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)values(${cid},${'push-'+cid},${uid},'Private title must never enter push','voluntary',${stamp},${stamp})`;
  await sql`insert into app.memberships(id,collection_id,user_id,role,joined_at)values(${crypto.randomUUID()},${cid},${uid},'owner',${stamp})`;
  await sql`insert into app.notification_preferences(user_id,updated_at)values(${uid},${stamp})`;
  const installed=[];for(let n=0;n<devices;n++){
   const id=crypto.randomUUID(),token='synthetic-registration-'+id,hash=await digest(token),cipher=await encrypt(env(),new TextEncoder().encode(token),'notification:'+id);
   await sql`insert into app.notification_devices(id,user_id,token_hash,owner_session_id,provider,token_ciphertext,platform,created_at,updated_at)values(${id},${uid},${hash},${sid},'fcm',${cipher},'android',${deviceStamp},${deviceStamp})`;
   installed.push({id,token,hash,cipher});
  }
  await sql`insert into app.notification_events(id,user_id,event_type,title,body,data_json,status,created_at)values(${eid},${uid},'contribution','Sensitive financial title','Private RWF 9000000 balance',${JSON.stringify({collection_id:cid,amount_minor:9000000,unreviewed:'never send this'})},'pending',${new Date((unix()-eventAge)*1000).toISOString()})`;
  return {auth,sid,uid,cid,eid,devices:installed};
 };
 const snapshot=async()=>JSON.stringify((await sql`select id,state,attempt_count,attempt_log from app.notification_deliveries order by id`));
 try{
  await t.step('SQL16 is private, fenced, exactly catalogued and installs no active obligations',async()=>{
   assertEquals(Number((await sql`select count(*) as n from app.notification_deliveries`)[0].n),0);
   assertEquals((await retentionSchema(retentionEnv)).profile,'notifications16');assertEquals(erasableTables.includes('notification_deliveries'),false);
   for(const role of ['anon','authenticated','service_role','collect_importer']){
    const permission=(await sql`select has_table_privilege(${role},'app.notification_deliveries','SELECT,INSERT,UPDATE,DELETE') as any_access`)[0];assertEquals(permission.any_access,false,role);
   }
   assertEquals((await sql`select tgenabled from pg_trigger where tgrelid='app.notification_deliveries'::regclass and tgname='collect_fence_statement_v1'`)[0].tgenabled,'A');
   await assertRejects(()=>sql.begin(async(tx:any)=>{await tx`set local role collect_runtime`;await tx`update app.notification_deliveries set updated_at=updated_at where false`;}));
  });
  await t.step('default disabled and mismatched admission cause no queue or provider effects',async()=>{
   const f=await fixture(),before=await snapshot(),calls=sendCalls;
   assertEquals(await drain(sender(),{COLLECT_PUSH_ENABLED:'false'}),{status:'disabled',paused:true,processed:0,results:[],recovered_unknown:0});
   await assertRejects(()=>drain(sender(),{COLLECT_JOBS_PUSH_APPROVAL_SHA256:'c'.repeat(64)}));
   assertEquals(await snapshot(),before);assertEquals(sendCalls,calls);
   await sql`update app.notification_events set status='read' where id=${f.eid}`;
  });
  await t.step('committed events produce unique per-device obligations and accepted records cannot resend',async()=>{
   const f=await fixture({devices:2}),before=sendCalls;
   const a=await drain(),b=await drain();assertEquals(a.results,[{state:'accepted'}]);assertEquals(b.results,[{state:'accepted'}]);assertEquals(sendCalls-before,2);
   const rows=await sql`select * from app.notification_deliveries where event_id=${f.eid}`;assertEquals(rows.length,2);
   for(const item of rows){assertEquals(item.attempt_count,1);assertEquals(item.attempt_log[0].source_sha256,SYNTHETIC_FENCE_SOURCE);assert(item.attempt_log[0].send_started_at>0);assertEquals(item.attempt_log[0].state,'accepted');assertEquals(item.lease_token,null);}
   assertEquals((await drain()).processed,0);assertEquals(sendCalls-before,2);
   await assertRejects(()=>sql`update app.notification_deliveries set state='retry' where event_id=${f.eid}`);
   await assertRejects(()=>sql`delete from app.notification_deliveries where event_id=${f.eid}`);
  });
  await t.step('historical events and pre-existing opt-outs do not create provider obligations',async()=>{
   const old=await fixture({eventAge:7200}),opted=await fixture(),before=sendCalls;
   await sql`update app.notification_preferences set push_enabled=0 where user_id=${opted.uid}`;
   assertEquals((await drain()).processed,0);assertEquals(await row(old.eid),undefined);assertEquals(await row(opted.eid),undefined);assertEquals(sendCalls,before);
   await sql`update app.notification_events set status='read' where id in(${old.eid},${opted.eid})`;
  });
  await t.step('OAuth await rechecks consent, membership, device owner, read state and managed session before send-start',async()=>{
   for(const kind of ['consent','membership','device','read','managed_session','event_digest','privacy_barrier']){
    const f=await fixture(),before=sendCalls;
    const adapter=sender({onOauth:async()=>{
     if(kind==='consent')await sql`update app.notification_preferences set payment_updates=0 where user_id=${f.uid}`;
     if(kind==='membership')await sql`update app.memberships set active=0 where user_id=${f.uid}`;
     if(kind==='device')await sql`update app.notification_devices set active=0 where id=${f.devices[0].id}`;
     if(kind==='read')await sql`update app.notification_events set status='read' where id=${f.eid}`;
     if(kind==='managed_session')await sql`update auth.sessions set not_after=now()-interval '1 second' where id=${f.sid}`;
     if(kind==='event_digest')await sql`update app.notification_events set data_json='{}' where id=${f.eid}`;
     if(kind==='privacy_barrier'){
      const request=crypto.randomUUID(),plan=crypto.randomUUID(),sha='d'.repeat(64),timestamp=new Date().toISOString();
      await sql`insert into app.deletion_requests(id,user_id,submission_id,created_at,updated_at)values(${request},${f.uid},${crypto.randomUUID()},${timestamp},${timestamp})`;
      await sql`insert into app.privacy_retention_plans(id,operation_id,request_id,subject_id,actor_id,session_id,input_sha256,policy_sha256,policy_json,policy_config_revision,source_id,schema_sha256,scope_json,scope_sha256,ledger_sha256,review_revision,created_seconds)
       values(${plan},${crypto.randomUUID()},${request},${f.uid},${owner.uid},${owner.sid},${sha},${sha},'{}',1,${SYNTHETIC_FENCE_SOURCE},${sha},'{}',${sha},${sha},1,${unix()})`;
      await sql`insert into app.privacy_retention_barriers(subject_id,plan_id,source_id,policy_sha256,activated_seconds)values(${f.uid},${plan},${SYNTHETIC_FENCE_SOURCE},${sha},${unix()})`;
     }
    }});
    assertEquals((await drain(adapter)).results,[{state:'suppressed'}],kind);assertEquals(sendCalls,before,kind);
    const retained=await row(f.eid);assertEquals(retained.last_error,'authority_changed');assertEquals(retained.attempt_log[0].send_started_at,undefined);
   }
  });
  await t.step('invalid encrypted device data is rejected before OAuth or message HTTP',async()=>{
   const f=await fixture(),beforeOauth=oauthCalls,beforeSend=sendCalls;
   await sql`update app.notification_devices set token_ciphertext='invalid-synthetic-envelope' where id=${f.devices[0].id}`;
   assertEquals((await drain()).results,[{state:'rejected'}]);assertEquals((await row(f.eid)).last_error,'invalid_push_payload');
   assertEquals(oauthCalls,beforeOauth);assertEquals(sendCalls,beforeSend);
  });
  await t.step('held claims cannot overlap and expired claims retry only when no send-start was recorded',async()=>{
   const f=await fixture(),before=sendCalls;
   const interrupted={...sender(),prepare:async()=>{throw Error('synthetic interrupted token preparation before send-start');}};
   await assertRejects(()=>drain(interrupted));const retained=await row(f.eid);assertEquals(retained.state,'claimed');
   assertEquals((await drain()).processed,0);assertEquals(sendCalls,before);
   await sql`update app.notification_deliveries set lease_until=${unix()-1} where id=${retained.id}`;
   assertEquals((await drain()).processed,0);const recovered=await row(f.eid);assertEquals(recovered.state,'retry');assertEquals(recovered.last_error,'claim_expired_before_send');
   assertEquals(recovered.attempt_log[0].send_started_at,undefined);
   await sql`update app.notification_deliveries set available_at=${unix()-1} where id=${retained.id}`;
   assertEquals((await drain()).results,[{state:'accepted'}]);const completed=await row(f.eid);assertEquals(completed.attempt_count,2);
   assertEquals(completed.attempt_log[0],recovered.attempt_log[0]);assertEquals(sendCalls-before,1);
  });
  await t.step('ambiguous provider response is terminal unknown and remains retained through event/device erasure',async()=>{
   const f=await fixture(),before=sendCalls;
   assertEquals((await drain(sender({onSend:async()=>{throw Error('synthetic send timeout after possible acceptance');}}))).results,[{state:'unknown'}]);
   assertEquals((await row(f.eid)).last_error,'delivery_unconfirmed');assertEquals((await drain()).processed,0);assertEquals(sendCalls-before,1);
   const privacy=await retentionSnapshot(retentionEnv,f.uid);assertEquals(privacy.summary.in_flight_unresolved,true);assertEquals((privacy.summary.tables as Record<string,{count:number}>).notification_deliveries.count,1);
   await sql`delete from app.notification_events where id=${f.eid}`;await sql`delete from app.notification_devices where user_id=${f.uid}`;
   assertEquals((await row(f.eid)).state,'unknown');assertEquals((await drain()).processed,0);assertEquals(sendCalls-before,1);
  });
  await t.step('confirmed throttling respects provider delay and exhausts at four attempts without an inline retry',async()=>{
   const f=await fixture(),before=sendCalls,adapter=sender({onSend:async()=>Response.json({error:{status:'RESOURCE_EXHAUSTED'}},{status:429,headers:{'Retry-After':'180'}})});
   for(let attempt=1;attempt<=4;attempt++){
    const result=await drain(adapter);assertEquals(result.results,[{state:attempt===4?'rejected':'retry'}]);const retained=await row(f.eid);
    assertEquals(retained.attempt_count,attempt);assertEquals(retained.attempt_log.length,attempt);
    if(attempt<4){assert(Number(retained.available_at)>=unix()+179);assertEquals((await drain()).processed,0);await sql`update app.notification_deliveries set available_at=${unix()-1} where id=${retained.id}`;}
   }
   assertEquals((await row(f.eid)).last_error,'retry_budget_exhausted');assertEquals(sendCalls-before,4);assertEquals((await drain()).processed,0);
  });
  await t.step('UNREGISTERED disables only the exact still-current registration; payload rejection never disables it',async()=>{
   for(const kind of ['unregistered','rotated','invalid_argument']){
    const f=await fixture();
    const result=await drain(sender({onSend:async()=>{
     if(kind==='rotated')await sql`update app.notification_devices set token_hash=${'e'.repeat(64)} where id=${f.devices[0].id}`;
     return kind==='invalid_argument'?Response.json({error:{status:'INVALID_ARGUMENT'}},{status:400}):
      Response.json({error:{status:'NOT_FOUND',details:[{'@type':'type.googleapis.com/google.firebase.fcm.v1.FcmError',errorCode:'UNREGISTERED'}]}},{status:404});
    }}));
    assertEquals(result.results,[{state:'rejected'}]);assertEquals(Number((await sql`select active from app.notification_devices where id=${f.devices[0].id}`)[0].active),kind==='unregistered'?0:1,kind);
   }
  });
  await t.step('lost send-start commit reply dispatches nothing; expired sending becomes unknown with no resend',async()=>{
   const f=await fixture(),before=sendCalls;let interrupted=false;
   const uncertain={prepare(text:string){const statement=db.prepare(text);if(!text.includes("SET state='sending'"))return statement;return {bind(...values:unknown[]){const bound=statement.bind(...values);return {async first(){const result=await bound.first();if(result){interrupted=true;throw Error('synthetic lost send-start commit reply');}return result;}};}};},batch:(statements:any[])=>db.batch(statements)};
   await assertRejects(()=>drain(sender(),{DB:uncertain}));assertEquals(interrupted,true);assertEquals(sendCalls,before);
   const retained=await row(f.eid);assertEquals(retained.state,'sending');
   await sql`update app.notification_deliveries set lease_until=${unix()-1} where id=${retained.id}`;
   const recovered=await drain();assertEquals(recovered.recovered_unknown,1);assertEquals(recovered.processed,0);assertEquals((await row(f.eid)).state,'unknown');assertEquals(sendCalls,before);
  });
  await t.step('lost final local commit reply reconciles only the same durable attempt without a second provider call',async()=>{
   const f=await fixture(),before=sendCalls;let lost=false;
   const uncertain={prepare:(text:string)=>db.prepare(text),async batch(statements:any[]){const result=await db.batch(statements);if(!lost){lost=true;throw Error('synthetic lost outcome commit reply');}return result;}};
   assertEquals((await drain(sender(),{DB:uncertain})).results,[{state:'accepted'}]);assertEquals(lost,true);assertEquals((await row(f.eid)).state,'accepted');assertEquals(sendCalls-before,1);
   assertEquals((await drain()).processed,0);assertEquals(sendCalls-before,1);
  });
  await t.step('overlapping workers claim an event/device once',async()=>{
   const f=await fixture(),before=sendCalls;
   const results=await Promise.all([drain(),drain()]);assertEquals(results.reduce((n,result)=>n+result.processed,0),1);
   assertEquals(sendCalls-before,1);assertEquals((await row(f.eid)).attempt_count,1);
  });
  await t.step('oversight uses actual queue states and reports acceptance separately from uncertainty',async()=>{
   const metrics=await db.prepare(oversightHealthSql[6]).first();
   const rows=await sql`select state,count(*)::integer as count from app.notification_deliveries group by state`;
   for(const state of ['pending','retry','claimed','sending','accepted','rejected','suppressed','unknown'])assertEquals(metrics[state],rows.find((row:any)=>row.state===state)?.count??0);
   assert(metrics.accepted>0);assert(metrics.unknown>0);assertEquals(metrics.expired_lease,0);assertEquals(metrics.due,0);assertEquals(metrics.oldest_due_at,null);
   assert(metrics.records_with_error>0);assert(Number.isSafeInteger(metrics.last_changed_at));
  });
  assert(oauthCalls>0);await reviewed.parity();
 }finally{globalThis.fetch=originalFetch;await finishSqlFixtureWork();await sql.end();}
}});
