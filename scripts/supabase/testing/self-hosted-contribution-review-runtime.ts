// Synthetic native PG qualification. This creates no external transfer and
// does not prove anything about changes after the review snapshot.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import postgres from 'npm:postgres@3.4.7';
import {installCurrentFixtureAdditions,validateCurrentFixtureDescriptor} from './self-hosted-current-schema.mjs';
import {connection,fenceConnection,PostgresDatabase} from '../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork,sqlFenceBackend} from '../../../supabase/functions/_shared/application-fence.js';
import {projectSession} from '../../../supabase/functions/_shared/domain/auth.js';
import {financialRpc} from '../../../supabase/functions/_shared/domain/payments.js';
import {contributionCommandRpc} from '../../../supabase/functions/_shared/domain/contribution_commands.js';
import {digest} from '../../../supabase/functions/_shared/domain/core.js';
import worker from '../../../supabase/functions/_shared/domain/index.js';

assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');
assert.equal(Deno.args.length,0);
const descriptorPath=Deno.env.get('COLLECT_CONTRIBUTION_REVIEW_FIXTURE_DESCRIPTOR');assert(descriptorPath);
const descriptor=JSON.parse(await readFile(descriptorPath,'utf8'));
const target=validateCurrentFixtureDescriptor(descriptor,{purpose:'backend'});
const owner:any=postgres(target.href,{max:1,prepare:false,ssl:false,onnotice:()=>{},types:{bigint:{to:20,from:[20],serialize:String,parse:Number}}});
const business=connection(target.href),control=fenceConnection(target.href),originalFetch=globalThis.fetch;
let externalCalls=0,admission:any=null,receipt:any=null;
globalThis.fetch=()=>{externalCalls++;return Promise.reject(Error('Synthetic contribution review forbids external network calls'));};
try{
 const currentSchema=await installCurrentFixtureAdditions(owner);
 const [identity]=await owner`SELECT current_user AS owner,session_user AS session,current_database() AS database,host(inet_server_addr()) AS host,
  inet_server_port() AS port,current_setting('server_version_num')::int AS version,(SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) AS privileged`;
 assert.equal(identity.owner,'postgres');assert.equal(identity.session,'postgres');assert.equal(identity.database,target.pathname.slice(1));
 assert.equal(identity.host,'127.0.0.1');assert.equal(identity.port,Number(target.port));assert.equal(identity.version,170010);assert.equal(identity.privileged,false);
 const member=crypto.randomUUID(),auth=crypto.randomUUID(),sid=crypto.randomUUID(),group=crypto.randomUUID();
 const receiver=crypto.randomUUID(),created=new Date().toISOString(),at=Math.floor(Date.now()/1000)-2,project='https://synthetic-payment.example.invalid';
 await owner`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${auth},'review-synthetic@example.invalid',now())`;
 await owner`INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES(${sid},${auth},'aal1',now()+interval '1 hour')`;
 await owner`INSERT INTO app.users(id,email,public_id,full_name,member_type,momo_number,country_code,created_at,updated_at)
  VALUES(${member},'review-synthetic@example.invalid','799997','Synthetic review member','app','+250788123491','RW',${created},${created})`;
 await owner`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES(${auth},${member},'synthetic-review-no-provider')`;
 await owner`INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,receiver_momo_number,receiver_network,receiver_display_label,created_at,updated_at)
  VALUES(${group},${group},${member},'Synthetic review group','ikimina','250788123492','mtn_momo','Synthetic receiver',${created},${created})`;
 await owner`INSERT INTO app.memberships(id,collection_id,user_id,role,joined_at) VALUES(${crypto.randomUUID()},${group},${member},'owner',${created})`;
 await owner`INSERT INTO app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,currency,timezone,created_at)
  VALUES(${receiver},'mtn_momo','250788123492','Synthetic receiver',${'a'.repeat(64)},'RWF','Africa/Kigali',${created})`;
 const claims={sub:auth,session_id:sid,role:'authenticated',aud:'authenticated',aal:'aal1',iat:at,exp:at+3600,iss:project+'/auth/v1',amr:[{method:'otp',timestamp:at}]};
 const verified={claims,token:'synthetic-verified-token',user:{id:auth,email:'review-synthetic@example.invalid',email_confirmed_at:created,app_metadata:{provider:'email'}}};
 admission=await (openApplicationWork as any)({backend:sqlFenceBackend(business,control),sourceSha256:descriptor.source_sha256,kind:'http_collect'});
 const db:any=new (PostgresDatabase as any)(business,claims,admission);
 const env:any={DB:db,COLLECT_FENCE_WORK:admission,SUPABASE_URL:project,AUTH_MEMBER_REGISTRATION_ENABLED:'false'};
 const actor=await projectSession(env,verified);assert.equal(actor.userId,member);assert.equal(actor.sessionId,sid);
 const runtime=await db.prepare(`SELECT current_user AS role,session_user AS session,current_setting('collect.edge_verified') AS verified,
   (SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) AS privileged,
   row_security_active('app.payments'::regclass) AS rls,has_table_privilege(current_user,'app.payments','SELECT') AS can_select`).first();
 assert.deepEqual(runtime,{role:'collect_runtime',session:'postgres',verified:'true',privileged:false,rls:true,can_select:true});
 const checks:string[]=[];const mark=(name:string)=>checks.push(name);
 mark('normal_runtime_has_select_and_active_rls_without_bypass');
 async function makeIntent(amount:number){
  const body={collection:group,p_expected_amount_rwf:amount,p_sender_phone_hash:await digest('+250788123491'),p_request_id:crypto.randomUUID()};
  const result=await financialRpc('create_contribution_intent',body,env,actor);
  return {body,intent:result.value,review:{p_contract_version:1,p_intent_id:result.value.id,p_collection_id:group}};
 }
 async function review(query:any):Promise<any>{return (await contributionCommandRpc('review_current_member_contribution_intent_v1',query,env,actor)).value;}
 const available=await makeIntent(711),positive=await review(available.review);
 assert.equal(positive.launch_authorized,true);assert.equal(positive.external_payment,'unknown');assert.equal(positive.retry_authorized,false);
 assert.deepEqual(positive.intent,available.intent);
 mark('real_create_and_unlinked_review_succeed');
 // Every object, SMS, evidence, parser result and transaction is explicitly
 // synthetic and written through enabled current-chain constraints/triggers.
 async function storage(key:string,entity:string,purpose:string){
  const scope={ownerId:member,entityId:entity,purpose},operation=crypto.randomUUID();
  const meta={sha256:'a'.repeat(64),source_fingerprint:'d'.repeat(64)};
  await owner`INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
   VALUES(${key},${'d'.repeat(64)},${scope},'synthetic-only','fixture',${'a'.repeat(64)},'synthetic-encrypted-envelope')`;
  await owner`INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
   VALUES(${operation},${key},${'e'.repeat(64)},${'f'.repeat(64)},30,${scope},${{}},${meta},'committed')`;
  await owner`INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
   VALUES(${key},${operation},${'e'.repeat(64)},${'f'.repeat(64)},30,${scope},${{}},${meta})`;
 }
 async function seedFacts(amount:number){
  const raw=crypto.randomUUID(),attempt=crypto.randomUUID(),transaction=crypto.randomUUID(),evidence=crypto.randomUUID(),payment=crypto.randomUUID();
  const sms='sms/'+raw,key='evidence/'+evidence;
  await storage(sms,raw,'sms_receipt');await storage(key,evidence,'payment_evidence');
  await owner`INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at)
   VALUES(${raw},${member},${sid},${crypto.randomUUID()},${'b'.repeat(64)},${'a'.repeat(64)},${sms},${'a'.repeat(64)},12,${created})`;
  await owner`INSERT INTO app.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,profile_version,profile_json,source_body_sha256,validation_json,outcome,created_at)
   VALUES(${attempt},${raw},1,'synthetic','synthetic','synthetic','synthetic','synthetic','{}',${'b'.repeat(64)},'{}','accepted',${created})`;
  await owner`INSERT INTO app.momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,currency_scale,transaction_timezone,transaction_time_source,parse_attempt_id,mode,allocation_state,created_at,updated_at)
   VALUES(${transaction},${receiver},'mtn_momo',${transaction},'incoming_receipt',${amount},'RWF',0,'Africa/Kigali','synthetic',${attempt},'live','linked',${created},${created})`;
  await owner`INSERT INTO app.payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,receiver_momo_number,receiver_network,amount_minor,observed_at,created_at)
   VALUES(${evidence},${group},${member},${key},${'a'.repeat(64)},12,'text/plain','operator_recorded',${transaction},'250788123492','mtn_momo',${amount},${created},${created})`;
  return {transaction,evidence,payment,amount};
 }
 async function link(facts:any,intent:string){
  await owner.begin(async (tx:any)=>{
   await tx`INSERT INTO app.payments(id,collection_id,member_id,evidence_id,intent_id,amount_minor,status,payer_display_name,created_at)
    VALUES(${facts.payment},${group},NULL,${facts.evidence},${intent},${facts.amount},'recorded','Synthetic',${created})`;
   await tx`INSERT INTO app.momo_financial_links(transaction_id,payment_id,beneficiary_member_id,linked_by,reason,historical_existing,created_at)
    VALUES(${facts.transaction},${facts.payment},${member},${member},'Synthetic recorded assignment',0,${created})`;
  });
 }
 const linked=await makeIntent(712),facts=await seedFacts(712);await link(facts,linked.intent.id);
 // Exercise the exact read-only context used by review, not just the normal
 // write-transaction context: RLS must reveal a payment with no member_id.
 const readTx:any=await business.reserve();let readIdle=false;
 try{
  await readTx.unsafe('BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY');
  await db.readContext(readTx,{isolation:'read committed'});
  const [visible]=await readTx.unsafe(`SELECT current_user AS role,row_security_active('app.payments'::regclass) AS rls,
   p.member_id,f.beneficiary_member_id,p.status FROM payments p JOIN momo_financial_links f ON f.payment_id=p.id WHERE p.intent_id=$1`,[linked.intent.id]);
  assert.deepEqual(visible,{role:'collect_runtime',rls:true,member_id:null,beneficiary_member_id:member,status:'recorded'});
  await readTx.unsafe('COMMIT');readIdle=true;
 }finally{
  if(!readIdle)await readTx.unsafe('ROLLBACK');
  readTx.release();
 }
 mark('normal_runtime_rls_sees_null_member_beneficiary_payment');
 const recent=(await financialRpc('list_current_member_recent_intents',{p_intent_id:linked.intent.id},env,actor)).value.items[0];
 assert.equal(recent.status,'pending');assert.equal(recent.confirmation_status,'payment_received');assert.equal(recent.payment_id,facts.payment);
 await assert.rejects(()=>review(linked.review),(error:any)=>error.status===404&&error.code==='contribution_intent_unavailable');
 mark('pending_beneficiary_link_denies_review');
 // Exercise the shared worker router and session projection, using synthetic
 // preverified claims. The outer deployed Edge handler is not exercised.
 async function http(query:any,authenticated=true){
  const request=new Request('https://backend.example/v1/rpc/review_current_member_contribution_intent_v1',{
   method:'POST',headers:{'content-type':'application/json',...(authenticated?{authorization:'Bearer '+verified.token}:{})},
   body:JSON.stringify(query)});
  const requestEnv={...env,AUTH_ACTOR:undefined,AUTH_VERIFIED:authenticated?verified:undefined};
  const response=await worker.fetch(request,requestEnv,{waitUntil(){}});
  if(!authenticated){assert.equal(requestEnv.AUTH_ACTOR,undefined);assert.equal(requestEnv.AUTH_VERIFIED,undefined);}
  assert.equal(env.AUTH_ACTOR,actor);assert.equal(env.AUTH_VERIFIED,verified);
  return {status:response.status,body:await response.json()};
 }
 const httpPositive=await http(available.review),httpLinked=await http(linked.review),httpNoAuth=await http(available.review,false);
 assert.equal(httpPositive.status,200);assert.equal(httpPositive.body.launch_authorized,true);
 assert.equal(httpLinked.status,404);assert.equal(httpLinked.body.code,'contribution_intent_unavailable');
 assert.equal(httpNoAuth.status,401);
 mark('shared_worker_http_with_synthetic_preverified_claims_denies_link_and_missing_auth');
 const race=await makeIntent(713),raceFacts=await seedFacts(713);let interleaved=false;
 const original=db.readContext.bind(db),previous=Object.getOwnPropertyDescriptor(db,'readContext');
 Object.defineProperty(db,'readContext',{configurable:true,writable:true,value:async(tx:any,options:any)=>{
  await original(tx,options);if(!interleaved){interleaved=true;await link(raceFacts,race.intent.id);}
 }});
 try{await assert.rejects(()=>review(race.review),(error:any)=>error.status===404&&error.code==='contribution_intent_unavailable');}
 finally{if(previous)Object.defineProperty(db,'readContext',previous);else delete db.readContext;}
 assert.equal(interleaved,true);assert.equal((await owner`SELECT status FROM app.payment_intents WHERE id=${race.intent.id}`)[0].status,'pending');
 mark('committed_link_between_context_and_review_select_is_denied');
 assert.equal((await review(available.review)).launch_authorized,true);
 const saved=await owner`SELECT count(*)::int AS n FROM app.request_receipts WHERE user_id=${member} AND request_id=${available.body.p_request_id}`;
 assert.equal(saved[0].n,1);mark('unrelated_link_does_not_disable_unlinked_intent_or_replace_receipt');
 const closed=await admission.finish();admission=null;assert.equal(closed.applicationWorkFinished,true);assert.equal(closed.providerSettlement,false);
 assert.equal(externalCalls,0);
 receipt={format:'collect.selfhost.contribution-review.native.v1',status:'PASS',current_schema:currentSchema,checks,
  normal_owner:true,normal_runtime:true,provider_calls:0,external_network_calls:0,hosted_acceptance:false,production_acceptance:false,
  http_router:'shared_worker',auth_fixture:'synthetic_preverified_claims',outer_deployed_edge_handler_exercised:false,
  review_to_provider_race_closed:false};
}finally{
 if(admission)await admission.finish().catch(()=>{});
 globalThis.fetch=originalFetch;
 await Promise.all([business.end(),control.end(),owner.end()]);
}
console.log(JSON.stringify(receipt));
