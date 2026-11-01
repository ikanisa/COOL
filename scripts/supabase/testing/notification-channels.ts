// Runs only against the specifically provided isolated fixture. No real SMTP,
// OpenSMS, device, FCM or public network operation is permitted by this suite.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import postgres from 'npm:postgres@3.4.7';
import {connection,fenceConnection,PostgresDatabase} from '../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork,sqlFenceBackend} from '../../../supabase/functions/_shared/application-fence.js';
import {drainContributionEmails,drainContributionEmailDispatch,renderContributionEmail} from '../../../supabase/functions/_shared/domain/contribution_email_delivery.js';
import {notificationRpc} from '../../../supabase/functions/_shared/domain/notifications.js';
import {createOpenSmsReceiptTransport} from '../../../supabase/functions/_shared/opensms-receipts.js';
import {digest} from '../../../supabase/functions/_shared/domain/core.js';
import {CURRENT_NATIVE_PROFILE,installCurrentFixtureAdditions,validateCurrentFixtureDescriptor} from './self-hosted-current-schema.mjs';

assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');
const file=Deno.env.get('COLLECT_NOTIFICATION_FIXTURE_FILE');assert(file?.endsWith('/collect-notifications-fixture.private.json'));
const fixture=JSON.parse(await readFile(file!,'utf8')),url=new URL(fixture.url);
const current=Deno.env.get('COLLECT_SELFHOST_NATIVE_PROFILE')===CURRENT_NATIVE_PROFILE;
if(current)validateCurrentFixtureDescriptor(fixture,{purpose:'notifications'});
assert.equal(url.hostname,'127.0.0.1');assert.equal(url.username,'postgres');assert.match(url.pathname,/^\/collect_[a-z0-9_]+_test$/);
const owner=postgres(fixture.url,{max:1,prepare:false,ssl:false,onnotice:()=>{}}),business=connection(fixture.url),control=fenceConnection(fixture.url);
const originalFetch=globalThis.fetch;globalThis.fetch=()=>{throw Error('External requests forbidden');};
let count=0;let currentSchema:any=null;
async function step(name:string,run:()=>Promise<void>){await run();count++;console.log('PASS '+name);}
try{
 if(current)currentSchema=await installCurrentFixtureAdditions(owner);
 else{
 await owner.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
 const migration=await readFile(new URL('../../../supabase/migrations/20261101012312_collect_notification_channels.sql',import.meta.url),'utf8');
 if(!(await owner`SELECT to_regclass('app.notification_email_deliveries') AS name`)[0].name)await owner.unsafe(migration);
 else if(!(await owner`SELECT to_regclass('app.notification_email_job_dispatches') AS name`)[0].name){
  // This expressly owned fixture may already contain the earlier unpublished
  // channel candidate. Apply only the newly added exact source section.
  const added=migration.match(/-- Durable scheduler envelope\.[\s\S]*?-- End durable scheduler envelope\./)?.[0];assert(added);await owner.unsafe('BEGIN;'+added+'\nCOMMIT;');
 }
 }
 const source=(await owner`SELECT private.collect_fence_owner_status() AS value`)[0].value.sourceSha256;
 if(current)assert.equal(source,fixture.source_sha256);
 const runWork=async(claims:any,fn:(env:any)=>Promise<any>)=>{
  const work=await (openApplicationWork as any)({backend:sqlFenceBackend(business,control),sourceSha256:source,kind:'http_collect'});
  try{return await fn({DB:new (PostgresDatabase as any)(business,claims,work),COLLECT_FENCE_WORK:work,BUILD_SOURCE_ID:source});}finally{await work.finish();}
 };
 const admission={contract:'collect.contribution-email.v1',source_sha256:source,approval_sha256:'b'.repeat(64),admitted_from:Math.floor(Date.now()/1000)-3600,batch_limit:1};
 const outcome=(event:string)=>runWork({},env=>env.DB.prepare('SELECT state FROM app.notification_email_deliveries WHERE event_id=?').bind(event).first());
 const base={APP_ENVIRONMENT:'test',COLLECT_CONTRIBUTION_EMAIL_ENABLED:'true',COLLECT_JOBS_EMAIL_APPROVAL_SHA256:admission.approval_sha256,COLLECT_EMAIL_ADMITTED_FROM:String(admission.admitted_from),AUTH_EMAIL_FROM:'receipts@example.invalid'};
 const seed=async()=>{
  const uid=crypto.randomUUID(),auth=crypto.randomUUID(),sid=crypto.randomUUID(),group=crypto.randomUUID(),event=crypto.randomUUID(),stamp=new Date().toISOString(),at=Math.floor(Date.now()/1000);
  const email='receipt-'+uid+'@example.invalid';
  await owner`INSERT INTO auth.users(id,email,email_confirmed_at)VALUES(${auth},${email},now())`;
  await owner`INSERT INTO auth.sessions(id,user_id,aal,not_after)VALUES(${sid},${auth},'aal1',now()+interval '1 hour')`;
  await owner`INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at)VALUES(${uid},${email},${String(700000+Math.floor(Math.random()*200000))},'Synthetic receipt member','app',${stamp},${stamp})`;
  await owner`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${auth},${uid},'synthetic-notification-channel')`;
  await owner`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES(${sid},${uid},'member',${at},${at},${at+3600})`;
  await owner`INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)VALUES(${group},${'receipt-'+group},${uid},'Synthetic group','voluntary',${stamp},${stamp})`;
  await owner`INSERT INTO app.memberships(id,collection_id,user_id,role,joined_at)VALUES(${crypto.randomUUID()},${group},${uid},'owner',${stamp})`;
  const data={payment_id:crypto.randomUUID(),collection_id:group,amount_rwf:100,member_balance_after_contribution_rwf:100,group_balance_after_contribution_rwf:100,group_name:'Synthetic group',posted_at:stamp,balance_basis:'after_this_contribution'};
  await owner`INSERT INTO app.notification_events(id,user_id,event_type,title,body,data_json,created_at)VALUES(${event},${uid},'contribution','Contribution','Recorded',${JSON.stringify(data)},${stamp})`;
  return {uid,auth,sid,group,event,email,data,claims:{sub:auth,session_id:sid,role:'authenticated',aal:'aal1',iat:at,exp:at+3600,amr:[{method:'otp',timestamp:at}]},actor:{userId:uid,sessionId:sid}};
 };
 await step('native schema denies client access and keeps default email opt-out',async()=>{
  for(const role of ['anon','authenticated','service_role'])for(const table of ['notification_email_deliveries','assisted_sms_dispatches','notification_email_job_dispatches'])assert.equal((await owner`SELECT has_table_privilege(${role},${'app.'+table},'SELECT,INSERT,UPDATE,DELETE') AS allowed`)[0].allowed,false);
 });
 await step('v2 preferences keep five choices and revision CAS independently',async()=>{
  const f=await seed();const call=(op:string,body:any)=>runWork(f.claims,env=>notificationRpc(op,body,env,f.actor));
  const before=(await call('get_notification_preferences_v2',{p_contract_version:2})).value;assert.equal(before.revision,0);assert.equal(before.exists,false);assert.equal(before.preferences.email_enabled,false);
  const p={contribution_confirmations:true,payment_reminders:false,group_updates:false,security_notices:true,email_enabled:false};
  const saved=(await call('set_notification_preferences_v2',{p_contract_version:2,p_expected_revision:0,p_preferences:p})).value;assert.equal(saved.revision,1);assert.equal(saved.changed,true);
  assert.deepEqual((await call('get_notification_preferences_v2',{p_contract_version:2})).value.preferences,p);
  const same=(await call('set_notification_preferences_v2',{p_contract_version:2,p_expected_revision:1,p_preferences:p})).value;assert.equal(same.changed,false);assert.equal(same.revision,1);
  await assert.rejects(call('set_notification_preferences_v2',{p_contract_version:2,p_expected_revision:0,p_preferences:p}));
 });
 await step('default opt-out never submits email',async()=>{
  let calls=0;const result=await runWork({},env=>drainContributionEmails({...env,...base,AUTH_EMAIL:{send:()=>{calls++;throw Error('unexpected');}}},{admission}));assert.equal(calls,0);assert.equal(result.processed,0);
 });
 await step('concurrent email drains submit one original obligation',async()=>{
  const f=await seed();await owner`INSERT INTO app.notification_preferences(user_id,email_enabled,updated_at)VALUES(${f.uid},1,${new Date().toISOString()})`;
  let calls=0;const send=async(message:any)=>{calls++;assert.equal(message.to,f.email);assert(message.text.includes('after this contribution'));return {messageId:'synthetic-accepted'};};
  await Promise.all([1,2].map(()=>runWork({},env=>drainContributionEmails({...env,...base,AUTH_EMAIL:{send}},{admission}))));assert.equal(calls,1);
  assert.equal((await outcome(f.event)).state,'accepted');
 });
 await step('lost provider result remains unknown and is never submitted again',async()=>{
  const f=await seed();await owner`INSERT INTO app.notification_preferences(user_id,email_enabled,updated_at)VALUES(${f.uid},1,${new Date().toISOString()})`;
  let calls=0;const drain=()=>runWork({},env=>drainContributionEmails({...env,...base,AUTH_EMAIL:{send:async()=>{calls++;throw Error('synthetic lost response');}}},{admission}));
  await drain();await drain();assert.equal(calls,1);assert.equal((await outcome(f.event)).state,'unknown');
 });
 await step('an empty dispatch remains empty when later eligible events arrive',async()=>{
  const dispatchId=crypto.randomUUID();let calls=0;const send=async()=>{calls++;return {messageId:'synthetic-later-event'};};
  const dispatch=(id=dispatchId)=>runWork({},env=>drainContributionEmailDispatch({...env,...base,AUTH_EMAIL:{send}},{dispatchId:id,admission}));
  assert.equal((await dispatch()).processed,0);
  const f=await seed();await owner`INSERT INTO app.notification_preferences(user_id,email_enabled,updated_at)VALUES(${f.uid},1,${new Date().toISOString()})`;
  assert.equal((await dispatch()).processed,0);assert.equal(calls,0);
  assert.equal((await dispatch(crypto.randomUUID())).processed,1);assert.equal(calls,1);
 });
 await step('concurrent and repeated outer dispatch IDs consume only one original event',async()=>{
  for(const f of [await seed(),await seed()])await owner`INSERT INTO app.notification_preferences(user_id,email_enabled,updated_at)VALUES(${f.uid},1,${new Date().toISOString()})`;
  let calls=0;const send=async()=>{calls++;return {messageId:'synthetic-dispatch-'+calls};},dispatchId=crypto.randomUUID();
  const dispatch=(id=dispatchId)=>runWork({},env=>drainContributionEmailDispatch({...env,...base,AUTH_EMAIL:{send}},{dispatchId:id,admission}));
  await Promise.all([dispatch(),dispatch()]);const result=await dispatch();assert.equal(result.processed,1);assert.equal(calls,1);
  const bound=await runWork({},env=>env.DB.prepare('SELECT count(*)AS n FROM app.notification_email_deliveries WHERE attempt_id=?').bind(dispatchId).first());assert.equal(bound.n,1);
  await dispatch(crypto.randomUUID());assert.equal(calls,2);
  await assert.rejects(runWork({},env=>drainContributionEmailDispatch({...env,...base,COLLECT_EMAIL_ADMITTED_FROM:String(admission.admitted_from-1),AUTH_EMAIL:{send}},{dispatchId,admission:{...admission,admitted_from:admission.admitted_from-1}})));assert.equal(calls,2);
 });
 await step('lost dispatch claim acknowledgment never acquires a send obligation',async()=>{
  const dispatchId=crypto.randomUUID();let calls=0,lost=false;
  const send=async()=>{calls++;return {messageId:'must-not-send'};};
  const result=await runWork({},env=>{
   const db=env.DB;env.DB={prepare:(text:string)=>{
    const statement=db.prepare(text);if(!text.startsWith('INSERT INTO app.notification_email_job_dispatches'))return statement;
    return {bind:(...values:any[])=>({first:async()=>{const row=await statement.bind(...values).first();lost=true;throw Error('synthetic lost commit reply');}})};
   }};return drainContributionEmailDispatch({...env,...base,AUTH_EMAIL:{send}},{dispatchId,admission});
  });
  assert(lost);assert.equal(result.status,'unconfirmed');assert.equal(calls,0);
  assert.equal((await runWork({},env=>drainContributionEmailDispatch({...env,...base,AUTH_EMAIL:{send}},{dispatchId,admission}))).status,'unconfirmed');assert.equal(calls,0);
 });
 await step('OpenSMS verifier matches native UTF8 length-prefix contract and never retries POST',async()=>{
  const applicationId='a'.repeat(100),id=applicationId+':collect-receipt:'+crypto.randomUUID(),at=new Date().toISOString(),notAfter=new Date(Date.now()+60000).toISOString(),message={messageId:id,to:'+250788000001',text:'RWF 100 — recorded',notAfter};let post=0,get=0;
  const fields=[id,applicationId,'receipt',message.to,message.text,'80',notAfter,at,''];const payloadDigest=await digest('collect-sms-payload-v1\n'+fields.map(v=>`${new TextEncoder().encode(v).length}:${v}`).join(''));
  const transport=createOpenSmsReceiptTransport({origin:'https://gateway.example.invalid',applicationId,token:'synthetic'},{fetchImpl:async(_url:any,init:any)=>{
   if(init.method==='POST'){post++;assert(init.headers['Idempotency-Key'].length<=128);return Response.json({message_id:id,state:'accepted'},{status:202});}
   get++;return Response.json({message:{message_id:id,application_id:applicationId,kind:'receipt',to:message.to,text:message.text,priority:80,not_after:notAfter,available_at:at,campaign_id:null,state:'sent',content_redacted_at:null,payload_digest:payloadDigest,updated_at:at}});
  }});
  assert.equal((await transport.submit(message)).observation,'observed_sent');await transport.inspect(message);assert.equal(post,1);assert.equal(get,2);
  assert.throws(()=>renderContributionEmail({data_json:{}}));
 });
 console.log('PASS notification channel qualification: '+count+' cases; no provider calls');
 if(current)console.log(JSON.stringify({format:'collect.selfhost.notifications.native.v2',status:'PASS',cases:count,current_schema:currentSchema,
  synthetic_email_and_opensms_transports:true,external_provider_calls:0,production_acceptance:false}));
}finally{globalThis.fetch=originalFetch;await Promise.all([owner.end({timeout:2}),business.end({timeout:2}),control.end({timeout:2})]);}
