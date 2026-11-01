// Isolated, native PostgreSQL metadata and approved SQL-row qualification.
// No Auth HTTP server, object-content store, provider erasure, SMTP, SMS,
// or production acceptance.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import postgres from 'npm:postgres@3.4.7';
import {connection,fenceConnection,PostgresDatabase} from '../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork,sqlFenceBackend} from '../../../supabase/functions/_shared/application-fence.js';
import {captureRetentionInventory,readRetentionInventoryPage} from '../../../supabase/functions/_shared/domain/privacy_retention_manifest.js';
import {loadAdminEmailAccount} from '../../../supabase/functions/_shared/domain/admin_email_auth.js';
import {bindAdminEmailActor} from '../../../supabase/functions/_shared/domain/admin_email_policy.js';
import {accountDatabase} from '../../../supabase/functions/_shared/domain/admin_accounts_legacy.js';
import {planRetentionRows,claimRetentionRows,executeRetentionRows,retentionRowsStatus,retentionRowsOperation} from '../../../supabase/functions/_shared/domain/privacy_retention_rows.js';
import {installCurrentFixtureAdditions,validateCurrentFixtureDescriptor} from './self-hosted-current-schema.mjs';

const passed:string[]=[],observed:Record<string,unknown>={};let stage='invocation',failure:any=null;
const pools:any[]=[];const originalFetch=globalThis.fetch;let externalCalls=0;
async function step(name:string,run:()=>Promise<void>){stage=name;await run();passed.push(name);}
const errorContains=(pattern:RegExp)=>(error:any)=>pattern.test(String(error?.code??'')+' '+String(error?.message??''));
try{
 assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');assert.equal(Deno.args.length,0);
 const descriptorPath=Deno.env.get('COLLECT_SELFHOST_RETENTION_FIXTURE_DESCRIPTOR');
 const descriptor=descriptorPath?JSON.parse(await readFile(descriptorPath,'utf8')):null;
 if(descriptor)validateCurrentFixtureDescriptor(descriptor,{purpose:'recovery'});
 const raw=descriptor?.url??Deno.env.get('COLLECT_SELFHOST_RETENTION_DATABASE_URL');Deno.env.delete('COLLECT_SELFHOST_RETENTION_DATABASE_URL');assert(raw);
 const target=new URL(raw);assert.equal(target.hostname,'127.0.0.1');assert.equal(target.username,'postgres');
 assert.match(target.pathname,/^\/collect_selfhost_recovery_[a-f0-9]+_test$/);assert(target.port);assert(!target.search&&!target.hash);
 globalThis.fetch=()=>{externalCalls++;throw Error('External requests forbidden in metadata qualification');};
 const owner=postgres(raw,{max:1,prepare:false,ssl:false,onnotice:()=>{},connection:{statement_timeout:120000,lock_timeout:5000}});
 const business=connection(raw),control=fenceConnection(raw);pools.push(owner,business,control);
 const identity=(await owner`SELECT current_user AS owner,session_user AS session,current_database() AS database,
  current_setting('server_version_num') AS version,(SELECT rolsuper FROM pg_roles WHERE rolname=current_user) AS superuser`)[0];
 assert.equal(identity.owner,'postgres');assert.equal(identity.session,'postgres');assert.equal(identity.superuser,false);
 assert.equal(Math.floor(Number(identity.version)/10000),17);assert.equal(identity.database,target.pathname.slice(1));
 const state=(await owner`SELECT private.collect_fence_owner_status_v3() AS value`)[0].value;
 assert.equal(state.mode,'open');assert.equal(state.rawActiveAdmissions,0);const source=state.sourceSha256;
 if(descriptor)assert.equal(source,descriptor.source_sha256);
 const admin={id:randomUUID(),auth:randomUUID(),sid:randomUUID(),account:randomUUID(),public:randomUUID(),token:'a'.repeat(64),origin:'https://retention-admin.example',email:'info@ikanisa.com'};
 const subject={id:randomUUID(),auth:randomUUID(),sid:randomUUID()},other={id:randomUUID(),auth:randomUUID(),sid:randomUUID()};
 const at=Math.floor(Date.now()/1000),stamp=new Date().toISOString(),request=randomUUID();let account:any,policyPin:string|undefined;
 const claims={sub:admin.auth,session_id:admin.sid,role:'authenticated',aal:'aal1',iat:at,exp:at+3600,amr:[{method:'otp',timestamp:at}]};
 const actor:any={userId:admin.id,sessionId:admin.sid,surface:'admin',permissions:new Set(['privacy.review'])};
 const work=async(fn:(env:any)=>Promise<any>,authorized=true)=>{
  const admission=await (openApplicationWork as any)({backend:sqlFenceBackend(business,control),sourceSha256:source,kind:'http_collect'});
  const env:any={DB:new (PostgresDatabase as any)(business,claims,admission),COLLECT_FENCE_WORK:admission,BUILD_SOURCE_ID:source,APP_ENVIRONMENT:'test',PRIVACY_RETENTION_V2_APPROVAL_SHA256:policyPin};
  try{return await fn(authorized?(accountDatabase as any)(env,account,'privacy.review',{fresh:true}):env);}finally{await admission.finish();}
 };
 await step('complete reviewed current chain installs on a fresh original16 owner fixture',async()=>{
  const installed=await installCurrentFixtureAdditions(owner);
  observed.migrations=installed.migrations.slice(16);
  observed.current_schema=installed;
  await owner`SELECT private._retention_manifest_schema_v2()`;
 });
 await step('seed genuine local email authority and large isolated scoped metadata',async()=>{
  for(const [i,p]of [admin,subject,other].entries()){
   const email=i===0?admin.email:'retention-'+p.id+'@example.invalid';
   await owner`INSERT INTO auth.users(id,email,email_confirmed_at)VALUES(${p.auth},${email},now())`;
   await owner`INSERT INTO auth.sessions(id,user_id,aal,not_after)VALUES(${p.sid},${p.auth},'aal1',now()+interval '1 hour')`;
   await owner`INSERT INTO app.users(id,email,public_id,created_at,updated_at)VALUES(${p.id},${email},${String(950000+i)},${stamp},${stamp})`;
   await owner`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${p.auth},${p.id},'synthetic-manifest-qualification')`;
   await owner`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES(${p.sid},${p.id},${i===0?'admin':'member'},${at},${at},${at+3600})`;
  }
  await owner`INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at)VALUES(${admin.account},${admin.email},'owner','active','!managed-supabase!','Synthetic Owner',${at},${at})`;
  await owner`INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)VALUES(${admin.account},${admin.id},'synthetic-fixture',${stamp})`;
  await owner`INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)SELECT ${admin.token},${admin.public},id,auth_version,${admin.sid},${admin.origin},${at},${at+3600} FROM app.admin_users WHERE id=${admin.account}`;
  await owner`INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)VALUES(${admin.token},${admin.auth},${admin.sid},'{}')`;
  await owner`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)VALUES(${admin.sid},'otp',to_timestamp(${at}))`;
  const challenge=randomUUID(),emailHash=createHash('sha256').update('email:'+admin.email).digest('hex');
  await owner`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)
   VALUES(${challenge},${emailHash},'email',${admin.email},'admin',0,${at-1},${at+299},1,${at},'accepted')`;
  account=(await owner`SELECT a.*,c.token_hash,c.public_id,c.origin,c.auth_session_id,c.issued_assurance_level,c.issued_mfa_at,c.issued_mfa_factor_id,l.user_id AS principal_id,b.auth_user_id::text AS auth_user_id
   FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id JOIN app.admin_sessions c ON c.user_id=a.id JOIN private.bff_sessions b ON b.token_hash=c.token_hash WHERE a.id=${admin.account}`)[0];
  account.auth_version=Number(account.auth_version);account.issued_assurance_level=Number(account.issued_assurance_level);
  account.permissions=['privacy.review'];
  await work(async env=>{
   await env.DB.prepare('SELECT private.admin_email_record_initial(?,?,?,?,?)').bind(admin.account,admin.token,admin.origin,admin.public,challenge).first();
   await loadAdminEmailAccount(env,account);bindAdminEmailActor(actor,account);
  },false);
  await owner`CREATE TABLE auth.refresh_tokens(id bigint PRIMARY KEY,user_id text,session_id uuid,token text)`;
  await owner`INSERT INTO auth.refresh_tokens SELECT n,${subject.auth},${subject.sid},'SYNTHETIC_SECRET_'||n FROM generate_series(1,1005)n`;
  await owner`INSERT INTO auth.refresh_tokens VALUES(2001,${other.auth},${other.sid},'SYNTHETIC_OTHER_SECRET')`;
  await owner`CREATE SCHEMA storage`;
  await owner`CREATE TABLE storage.buckets(id text PRIMARY KEY,name text,public boolean)`;
  await owner`CREATE TABLE storage.objects(id uuid PRIMARY KEY,bucket_id text,name text,owner_id text,metadata jsonb)`;
  await owner`CREATE TABLE storage.s3_multipart_uploads_parts(id uuid PRIMARY KEY,bucket_id text,key text,owner_id text,upload_id text,etag text)`;
  await owner`INSERT INTO storage.buckets VALUES('collect-evidence','collect-evidence',false)`;
  await owner`INSERT INTO private.storage_namespace(singleton,origin,bucket)VALUES(true,'https://synthetic-storage.example','collect-evidence')`;
  await owner`INSERT INTO storage.objects SELECT gen_random_uuid(),'collect-evidence','synthetic/'||n,${subject.auth},jsonb_build_object('synthetic',n) FROM generate_series(1,1003)n`;
  await owner`INSERT INTO storage.objects VALUES(gen_random_uuid(),'collect-evidence','synthetic/other',${other.auth},'{}')`;
  await owner`INSERT INTO storage.s3_multipart_uploads_parts SELECT gen_random_uuid(),'collect-evidence','synthetic/1',${subject.auth},'synthetic-multipart','part-'||n FROM generate_series(1,3)n`;
  await owner`CREATE TABLE realtime.messages_manifest_fixture PARTITION OF realtime.messages DEFAULT`;
  await owner`INSERT INTO realtime.messages(id,topic,extension,payload,event,private)SELECT gen_random_uuid(),${'collect:member:'+subject.auth+':'+subject.sid},'broadcast','{"synthetic":true}','manifest',true FROM generate_series(1,1001)`;
  await owner`INSERT INTO app.notification_events(id,user_id,event_type,title,body,data_json,status,created_at)SELECT gen_random_uuid()::text,${subject.id},'synthetic','Synthetic inventory event','SYNTHETIC_PRIVATE_BODY','{}','pending',${stamp} FROM generate_series(1,2505)`;
  await owner`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status)
   VALUES(${randomUUID()},${'b'.repeat(64)},'email',${'retention-'+subject.id+'@example.invalid'},'member',0,${at},${at+300},'unknown')`;
  await owner`INSERT INTO app.deletion_requests(id,user_id,submission_id,reason,created_at,updated_at)VALUES(${request},${subject.id},${randomUUID()},'Synthetic local retention request',${stamp},${stamp})`;
  await owner`INSERT INTO app.privacy_holds(id,user_id,category,reason_code,active,created_at)VALUES(${randomUUID()},${subject.id},'financial_evidence','synthetic_review',1,${stamp})`;
 });
 let captured:any;const operation=randomUUID();
 await step('native v1 bound refuses while v2 captures complete larger metadata without effects',async()=>{
  await assert.rejects(work(async env=>(await env.DB.batch([env.DB.prepare('SELECT private.retention_managed_inventory(?)').bind(subject.id)]))),/retention_managed_inventory_limit/);
  captured=await work(env=>captureRetentionInventory(env,actor,{operation_id:operation,request_id:request,expected_review_revision:0,expected_source_id:source}));
  assert(captured.page_count>50);assert(captured.descriptor_count>5500);assert.equal(captured.active_hold_count,1);
  assert.equal(captured.class_counts['notification_events'].rows,2505);
  assert.equal(captured.class_counts['managed:auth'].rows,1007);
  assert.equal(captured.class_counts['managed:storage'].rows,1006);
  assert.equal(captured.class_counts['managed:realtime_messages'].rows,1001);
  assert(captured.class_counts['private:supabase_otp_challenges'].unresolved_count>=1);
  for(const name of ['private:guest_upgrade_challenges','private:collect_fence_admission_archive','private:collect_sms_fence_admissions'])assert.equal(captured.class_counts[name].status,'unmapped');
  for(const name of ['external:collect_sms','external:collect_ops','external:vault','external:net'])assert.equal(captured.class_counts[name].status,'unverified');
  assert.equal(captured.erasure_completed,false);assert.equal(captured.approval_granted,false);assert.equal(captured.physical_objects_verified,false);
  observed.capture={descriptor_count:captured.descriptor_count,page_count:captured.page_count,auth_rows:1007,storage_rows:1006,realtime_rows:1001,application_notification_rows:2505,active_holds:1};
 });
 const read=(page:number,verify=false,sha=captured.manifest_sha256)=>work(env=>readRetentionInventoryPage(env,actor,{manifest_id:operation,manifest_sha256:sha,page_number:page,verify_current:verify}));
 await step('resumable pages are immutable, exact, secret-free and independently currentness checked',async()=>{
  const all:any[]=[];for(let n=0;n<captured.page_count;n++){
   const page=await read(n,n===0);assert.equal(page.page_number,n);assert.equal(page.manifest_sha256,captured.manifest_sha256);
   assert.equal(page.next_page,n+1<captured.page_count?n+1:null);assert(page.descriptors.length<=100);
   if(n===0)assert.equal(page.data_current,true);else assert.equal(page.data_current,null);
   all.push(...page.descriptors);
  }
  assert.equal(all.length,captured.descriptor_count);
  const gatewayCustody=all.filter(row=>row.class_name==='private:collect_sms_fence_admissions');
  assert.equal(gatewayCustody.length,1);assert.equal(gatewayCustody[0].kind,'class');
  assert.equal(gatewayCustody[0].status,'unmapped');assert.equal(gatewayCustody[0].erasure,'blocked');
  assert.equal(gatewayCustody[0].subject_count,null);assert.equal(gatewayCustody[0].present,true);
  const encoded=JSON.stringify(all);for(const secret of ['SYNTHETIC_SECRET_','SYNTHETIC_PRIVATE_BODY','SYNTHETIC_OTHER_SECRET','retention-'+subject.id,subject.auth,admin.token])assert(!encoded.includes(secret));
  assert.deepEqual((await read(1)).descriptors,(await read(1)).descriptors);
  assert.equal((await work(env=>captureRetentionInventory(env,actor,{operation_id:operation,request_id:request,expected_review_revision:0,expected_source_id:source}))).manifest_sha256,captured.manifest_sha256);
  await assert.rejects(read(0,false,'f'.repeat(64)),errorContains(/retention_manifest_unavailable/));
  await assert.rejects(read(captured.page_count),errorContains(/retention_manifest_unavailable/));
  await assert.rejects(owner`UPDATE private.retention_inventory_pages SET descriptors='[]' WHERE manifest_id=${operation}`,/retention_manifest_immutable/);
  await assert.rejects(owner`DELETE FROM private.retention_inventory_manifests WHERE id=${operation}`,/retention_manifest_immutable/);
 });
 await step('data drift stays visible while old sealed evidence is resumable',async()=>{
  await owner`INSERT INTO app.notification_events(id,user_id,event_type,title,body,data_json,status,created_at)VALUES(${randomUUID()},${subject.id},'synthetic','Synthetic added event','SYNTHETIC_AFTER_CAPTURE','{}','pending',${stamp})`;
  const current=await read(0,true);assert.equal(current.data_current,false);assert.equal(current.controls_current,true);assert.equal(current.manifest_sha256,captured.manifest_sha256);
  assert.equal((await read(1)).class_counts.notification_events.rows,2505);
 });
 await step('capacity failure is atomic and does not save a partial manifest',async()=>{
  const bounded=randomUUID();
  await assert.rejects(work(env=>env.DB.batch([env.DB.prepare('SELECT private.retention_capture_inventory_v2(?::uuid,?,?::bigint,?,100)').bind(bounded,request,0,source)])),/retention_manifest_capacity_exceeded/);
  assert.equal(Number((await owner`SELECT count(*) AS n FROM private.retention_inventory_pages WHERE manifest_id=${bounded}`)[0].n),0);
  assert.equal(Number((await owner`SELECT count(*) AS n FROM private.retention_inventory_manifests WHERE id=${bounded}`)[0].n),0);
 });
 const publish=async(manifest:any,{continuation=null,mutate=(_:any)=>{}}:{continuation?:any,mutate?:(p:any)=>void}={})=>{
  const deadline=new Date(Date.now()-60000).toISOString(),rules:any={access:{action:'quarantine',basis_reference:'synthetic-only-approved-SQL-scope',deadline}};
  const own=new Set(['notification_devices','notification_preferences','notification_events','support_requests']);
  for(const[name,metadata]of Object.entries(manifest.class_counts)as any){
   const blocked=name.includes(':')||name.startsWith('privacy_retention_')||name==='notification_email_job_dispatches'||metadata.status!=='observed';
   rules[name]={action:blocked?'blocked':own.has(name)?'erase':'retain',basis_reference:'synthetic-only-approved-SQL-scope',deadline};
  }
  const policy:any={contract_version:2,scope:'sql_rows_only',policy_id:randomUUID(),environment:'test',synthetic_test_only:true,
   approval_evidence_sha256:'c'.repeat(64),approved_by:admin.id,approved_at:new Date(Date.now()-1000).toISOString(),expires_at:new Date(Date.now()+3600000).toISOString(),
   source_id:source,schema_sha256:manifest.schema_sha256,manifest_id:manifest.manifest_id,manifest_sha256:manifest.manifest_sha256,
   request_id:manifest.request_id,subject_id:manifest.subject_id,review_revision:0,rules,
   writer_fence:{source_id:source,evidence_sha256:'d'.repeat(64),unknown_in_flight:false},
   copy_inventory:{unmapped_copies:'blocked',physical_objects:'blocked',providers:'blocked',bff_access_revocation:'allow'},quarantine_continuation:continuation};
  mutate(policy);const raw=JSON.stringify(policy);policyPin=createHash('sha256').update(raw).digest('hex');
  await owner`INSERT INTO app.runtime_config(key,value_json,revision,updated_by,updated_at)VALUES('privacy:retention:approved:v2',${raw},1,${admin.id},${stamp})
   ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json,revision=app.runtime_config.revision+1,updated_by=excluded.updated_by,updated_at=excluded.updated_at`;
  return policy;
 };
 const plan=(manifest:any,id=randomUUID())=>work(env=>planRetentionRows(env,actor,{operation_id:id,manifest_id:manifest.manifest_id,manifest_sha256:manifest.manifest_sha256,policy_sha256:policyPin,expected_source_id:source}));
 const status=(id:string,current=false)=>work(env=>retentionRowsStatus(env,actor,{plan_id:id,verify_current:current}));
 const claim=async(id:string,name:string,lease=120)=>{const before=await status(id);return work(env=>claimRetentionRows(env,actor,{operation_id:randomUUID(),plan_id:id,class_name:name,expected_revision:before.revision,lease_seconds:lease}));};
 const execute=(c:any,id:string=randomUUID())=>work(env=>executeRetentionRows(env,actor,{operation_id:id,claim_id:c.claim_id,fence:c.fence}));
 await step('v2 policy cannot authorize held scope or managed/provider erasure',async()=>{
  // The original manifest was made before the drift scenario, so obtain a new
  // genuine held capture; never substitute a hand-built decoded packet.
  const held=await work(env=>captureRetentionInventory(env,actor,{operation_id:randomUUID(),request_id:request,expected_review_revision:0,expected_source_id:source}));
  await publish(held,{mutate:p=>{p.rules['managed:auth'].action='erase';}});
  await assert.rejects(plan(held),errorContains(/retention_row_unsupported_disposition/));
  await publish(held);await assert.rejects(plan(held),errorContains(/retention_row_hold_or_unknown_work/));
  assert.equal(Number((await owner`SELECT count(*) AS n FROM private.retention_row_plans WHERE subject_id=${subject.id}`)[0].n),0);
  assert.equal(Number((await owner`SELECT count(*) AS n FROM app.privacy_retention_barriers WHERE subject_id=${subject.id}`)[0].n),0);
  const unknownRequest=randomUUID();
  await owner`INSERT INTO app.deletion_requests(id,user_id,submission_id,reason,created_at,updated_at)VALUES(${unknownRequest},${other.id},${randomUUID()},'Synthetic unresolved-only request',${stamp},${stamp})`;
  await owner`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status)
   VALUES(${randomUUID()},${'9'.repeat(64)},'email',${'retention-'+other.id+'@example.invalid'},'member',0,${at},${at+300},'unknown')`;
  const unknown=await work(env=>captureRetentionInventory(env,actor,{operation_id:randomUUID(),request_id:unknownRequest,expected_review_revision:0,expected_source_id:source}));
  assert.equal(unknown.active_hold_count,0);assert(unknown.class_counts['private:supabase_otp_challenges'].unresolved_count>0);
  await publish(unknown);await assert.rejects(plan(unknown),errorContains(/retention_row_hold_or_unknown_work/));
  assert.equal(Number((await owner`SELECT count(*) AS n FROM private.retention_row_plans WHERE subject_id=${other.id}`)[0].n),0);
 });
 const eligible={id:randomUUID(),auth:randomUUID(),sid:randomUUID(),request:randomUUID()};let eligibleCapture:any,rowPlan:any;
 await step('large SQL-only plan uses exact explicit approval and rejects malformed policies',async()=>{
  const email='eligible-'+eligible.id+'@example.invalid';
  await owner`INSERT INTO auth.users(id,email,email_confirmed_at)VALUES(${eligible.auth},${email},now())`;
  await owner`INSERT INTO app.users(id,email,public_id,created_at,updated_at)VALUES(${eligible.id},${email},'950003',${stamp},${stamp})`;
  await owner`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)VALUES(${eligible.auth},${eligible.id},'synthetic-row-qualification')`;
  await owner`INSERT INTO auth.sessions(id,user_id,aal,not_after)VALUES(${eligible.sid},${eligible.auth},'aal1',now()+interval '1 hour')`;
  await owner`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES(${eligible.sid},${eligible.id},'member',${at},${at},${at+3600})`;
  await owner`WITH seeded AS(INSERT INTO auth.sessions(id,user_id,aal,not_after) SELECT gen_random_uuid(),${eligible.auth},'aal1',now()+interval '1 hour' FROM generate_series(1,84) RETURNING id)
   INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)SELECT id::text,${eligible.id},'member',${at},${at},${at+3600} FROM seeded`;
  await owner`INSERT INTO auth.refresh_tokens SELECT 3000+n,${eligible.auth},${eligible.sid},'SYNTHETIC_ELIGIBLE_SECRET_'||n FROM generate_series(1,1005)n`;
  await owner`INSERT INTO app.notification_events(id,user_id,event_type,title,body,data_json,status,created_at)SELECT gen_random_uuid()::text,${eligible.id},'synthetic','Eligible event','SYNTHETIC_ELIGIBLE_BODY','{}','pending',${stamp} FROM generate_series(1,2505)`;
  await owner`INSERT INTO app.notification_preferences(user_id,updated_at)VALUES(${eligible.id},${stamp}) ON CONFLICT DO NOTHING`;
  await owner`INSERT INTO app.notification_devices(id,user_id,token_hash,owner_session_id,provider,token_ciphertext,platform,created_at,updated_at)
   VALUES(${randomUUID()},${eligible.id},${'e'.repeat(64)},${eligible.sid},'expo','{}','android',${stamp},${stamp})`;
  await owner`INSERT INTO app.support_requests(id,user_id,kind,message,created_at)VALUES(${randomUUID()},${eligible.id},'synthetic','Synthetic eligible request',${stamp})`;
  await owner`INSERT INTO app.deletion_requests(id,user_id,submission_id,reason,created_at,updated_at)VALUES(${eligible.request},${eligible.id},${randomUUID()},'Synthetic eligible SQL request',${stamp},${stamp})`;
  eligibleCapture=await work(env=>captureRetentionInventory(env,actor,{operation_id:randomUUID(),request_id:eligible.request,expected_review_revision:0,expected_source_id:source}));
  assert.equal(eligibleCapture.class_counts.notification_events.rows,2505);assert.equal(eligibleCapture.class_counts['managed:auth'].rows,1091);
  await publish(eligibleCapture,{mutate:p=>{p.rules.notification_events.basis_reference=null;}});
  await assert.rejects(plan(eligibleCapture),errorContains(/retention_row_policy_rule_invalid/));
  await publish(eligibleCapture);const operation=randomUUID();rowPlan=await plan(eligibleCapture,operation);
  assert.equal(rowPlan.state,'planned');assert.equal((await plan(eligibleCapture,operation)).plan_id,rowPlan.plan_id);
  await assert.rejects(claim(rowPlan.plan_id,'notification_events'),errorContains(/retention_row_claim_changed/));
 });
 await step('deployment policy mismatch and expired claims cannot mutate or quarantine the subject',async()=>{
  const correctPin=policyPin;policyPin='8'.repeat(64);
  try{await assert.rejects(claim(rowPlan.plan_id,'access'),errorContains(/retention_row_policy_pin_changed/));}finally{policyPin=correctPin;}
  const expired=await claim(rowPlan.plan_id,'access',1);
  await new Promise(resolve=>setTimeout(resolve,2200));
  await assert.rejects(execute(expired),errorContains(/retention_row_claim_stale/));
  assert.equal((await status(rowPlan.plan_id)).state,'planned');
  assert.equal(Number((await owner`SELECT count(*) AS n FROM app.privacy_retention_barriers WHERE subject_id=${eligible.id}`)[0].n),0);
  assert.equal(Number((await owner`SELECT count(*) AS n FROM private.retention_row_effects WHERE plan_id=${rowPlan.plan_id}`)[0].n),0);
 });
 await step('quarantine revokes 85 real projected sessions in bounded resumed chunks',async()=>{
  let batches=0,total=0,last:any;
  do{const c=await claim(rowPlan.plan_id,'access');last=await execute(c);total+=last.sessions_revoked;assert(last.sessions_revoked<=40);batches++;}while(!last.verified);
  assert.equal(batches,3);assert.equal(total,85);assert.equal((await status(rowPlan.plan_id)).state,'quarantined');
  assert.equal((await owner`SELECT access_status FROM app.users WHERE id=${eligible.id}`)[0].access_status,'suspended');
  assert.equal(Number((await owner`SELECT count(*) AS n FROM auth.sessions WHERE user_id=${eligible.auth}`)[0].n),85,'Native Auth records are retained, never provider-erased');
  await assert.rejects(owner`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)VALUES(${randomUUID()},${eligible.id},'member',${at},${at},${at+3600})`,/privacy_retention_access_quarantined|managed_session_required/);
  observed.row_quarantine={sessions_revoked:85,chunks:3,native_auth_sessions_retained:85};
 });
 let oldPlan:string,firstOperation:string;
 await step('SQL chunk commits once and exact operation replay cannot erase a second chunk',async()=>{
  const c=await claim(rowPlan.plan_id,'notification_events');firstOperation=randomUUID();const result=await execute(c,firstOperation);
  assert.equal(result.rows_changed,40);assert.equal(result.rows_remaining,2465);assert.equal(result.verified,false);
  assert.deepEqual(await execute(c,firstOperation),result);
  assert.equal(Number((await owner`SELECT count(*) AS n FROM app.notification_events WHERE user_id=${eligible.id}`)[0].n),2465);
  const found=await work(env=>retentionRowsOperation(env,actor,{operation_kind:'execute',operation_id:firstOperation}));assert.equal(found.observed,true);assert.deepEqual(found.receipt,result);
  assert.equal((await status(rowPlan.plan_id,true)).source_current,true);oldPlan=rowPlan.plan_id;
 });
 await step('expired policy needs a new exact manifest and approved original-barrier continuation',async()=>{
  const oldStatus=await status(rowPlan.plan_id);assert(oldStatus.quarantine_barrier);
  await publish(eligibleCapture,{mutate:p=>{p.expires_at=new Date(Date.now()-1000).toISOString();}});
  await assert.rejects(claim(rowPlan.plan_id,'notification_events'),errorContains(/retention_row_policy_unavailable|retention_row_policy_changed/));
  const next=await work(env=>captureRetentionInventory(env,actor,{operation_id:randomUUID(),request_id:eligible.request,expected_review_revision:0,expected_source_id:source}));
  await publish(next);await assert.rejects(plan(next),errorContains(/retention_row_prior_plan_unresolved/));
  await publish(next,{continuation:{...oldStatus.quarantine_barrier,superseded_plan_id:oldStatus.plan_id,approval_evidence_sha256:'f'.repeat(64)}});
  rowPlan=await plan(next);assert.equal((await status(oldPlan)).state,'superseded');
  await assert.rejects(claim(oldPlan,'notification_events'),errorContains(/retention_row_plan_superseded/));
  const c=await claim(rowPlan.plan_id,'access'),done=await execute(c);assert.equal(done.verified,true);assert.equal(done.sessions_revoked,0);
  assert.equal((await status(rowPlan.plan_id)).quarantine_barrier.previous_plan_id,oldPlan);
 });
 await step('all 2505 own notification rows finish with retained deltas and current exact source',async()=>{
  let chunks=0,last:any;
  do{last=await execute(await claim(rowPlan.plan_id,'notification_events'));assert(last.rows_changed<=40);chunks++;}while(!last.verified);
  assert.equal(chunks,62);assert.equal(last.rows_remaining,0);
  for(const name of ['notification_devices','notification_preferences','support_requests']){const out=await execute(await claim(rowPlan.plan_id,name));assert.equal(out.verified,true);assert.equal(out.rows_changed,1);}
  const complete=await status(rowPlan.plan_id,true);assert.equal(complete.state,'completed');assert.equal(complete.eligible_sql_dispositions_verified,true);
  assert.equal(complete.all_data_erased,false);assert.equal(complete.all_actual_copy_outcomes_verified,false);assert.equal(complete.physical_objects_verified,false);
  assert.equal(Number((await owner`SELECT count(*) AS n FROM app.notification_events WHERE user_id=${subject.id}`)[0].n),2506,'Other held subject remains untouched');
  assert.equal(Number((await owner`SELECT count(*) AS n FROM private.retention_row_effects e JOIN private.retention_row_plans p ON p.id=e.plan_id WHERE p.subject_id=${eligible.id} AND e.class_name='notification_events'`)[0].n),2505);
  observed.row_disposition={notification_rows:2505,notification_chunks:63,other_own_rows:3,continued_plan:true,external_erasure:false,financial_source_unchanged:true};
 });
 await step('held review drift, unknown managed schema and missing current authority fail closed',async()=>{
  await owner`CREATE TABLE auth.synthetic_unclassified(id uuid)`;
  try{await assert.rejects(read(0),errorContains(/retention_manifest_unknown_managed_relation/));}finally{await owner`DROP TABLE auth.synthetic_unclassified`;}
  await owner`INSERT INTO app.privacy_holds(id,user_id,category,reason_code,active,created_at)VALUES(${randomUUID()},${subject.id},'financial_evidence','additional_synthetic_review',1,${stamp})`;
  await assert.rejects(read(0),errorContains(/retention_manifest_control_changed/));
  await owner`DELETE FROM auth.mfa_amr_claims WHERE session_id=${admin.sid}`;
  await owner`DELETE FROM auth.sessions WHERE id=${admin.sid}`;
  await assert.rejects(read(0),errorContains(/session_changed|email_sign_in|admin_access_changed/));
 });
 await step('private capture custody and helpers remain inaccessible to client roles',async()=>{
  for(const role of ['anon','authenticated','service_role','collect_runtime','collect_importer']){
   for(const table of ['retention_inventory_manifests','retention_inventory_pages','retention_row_plans','retention_row_claims','retention_row_effects','retention_row_operations'])assert.equal((await owner`SELECT has_table_privilege(${role},${'private.'+table},'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') AS ok`)[0].ok,false);
   assert.equal((await owner`SELECT has_function_privilege(${role},'private._retention_manifest_rows_v2(text)','EXECUTE') AS ok`)[0].ok,false);
   assert.equal((await owner`SELECT has_function_privilege(${role},'private._retention_row_erase_chunk_v2(uuid,uuid,text)','EXECUTE') AS ok`)[0].ok,false);
   if(role!=='collect_runtime')for(const signature of ['private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','private.retention_execute_rows_v2(uuid,uuid,bigint,text)'])assert.equal((await owner`SELECT has_function_privilege(${role},${signature},'EXECUTE') AS ok`)[0].ok,false);
  }
 });
 assert.equal(externalCalls,0);
}catch(error){const e:any=error;failure={stage,name:e?.name,message:e?.message,code:e?.code,where:e?.where,stack:String(e?.stack??'').split('\n').slice(0,5)};}
finally{globalThis.fetch=originalFetch;for(const pool of pools.reverse())try{await pool.end({timeout:2});}catch{}}
console.log(JSON.stringify({contract:'collect.selfhost.retention.native.v2',passed:failure===null,scenarios:passed,observed,external_calls:externalCalls,
 production_acceptance:false,qualification:'PG17 synthetic platform metadata and SQL-row disposition with genuine Collect SQL authority; no physical-provider or production erasure acceptance',...(failure?{failure}:{})},null,2));
if(failure)Deno.exit(1);
