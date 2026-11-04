// Called only by a dedicated loopback PG17 fixture after all reviewed current
// migrations are installed. GoTrue and object bytes are synthetic; the Admin
// HTTP route, managed session projection, email proof and SQL guards are real.
import assert from 'node:assert/strict';
import worker from '../domain/index.js';
import {issueAdminSession} from '../domain/admin_accounts.js';
import {PostgresDatabase} from '../postgres.js';
import {openApplicationWork,sqlFenceBackend} from '../application-fence.js';
import {MOMO_JOB_CHECKPOINT,MOMO_SCHEMA_VERSION} from '../domain/momo_pipeline.js';
import {digest} from '../domain/core.js';
import {encrypt} from '../domain/encryption.js';

const origin='https://synthetic-admin.example.invalid',project='https://synthetic-auth.example.invalid';
const epoch=()=>Math.floor(Date.now()/1000),stamp=()=>new Date().toISOString();

export async function verifyMomoAdminOnCurrentPostgres({sql,business,control,sourceSha256,member,sid}){
 const tokens=new Map(),objects=new Map(),closures=[];let syntheticAuthCalls=0,unexpectedFetches=0;
 const originalFetch=globalThis.fetch;
 globalThis.fetch=async(input,init)=>{
  const request=input instanceof Request?input:new Request(input,init),url=new URL(request.url);
  if(url.origin!==project||url.pathname!=='/auth/v1/user'||request.method!=='GET'){
   unexpectedFetches++;throw Error('Synthetic Admin fixture forbids this network destination');
  }
  syntheticAuthCalls++;const identity=tokens.get(request.headers.get('Authorization')?.slice(7));
  return identity?Response.json(identity.user):Response.json({error_code:'invalid_token'},{status:401});
 };
 const base={SUPABASE_URL:project,SUPABASE_PUBLISHABLE_KEY:'synthetic-admin-public',ADMIN_ORIGIN:origin,ALLOWED_ORIGINS:origin,
  AUTH_MEMBER_REGISTRATION_ENABLED:'false',MOMO_PROCESSING_PAUSED:'true',BUILD_SOURCE_ID:sourceSha256,
  SESSION_KEY_ID:'synthetic-current-admin',SESSION_ENCRYPTION_KEY:btoa('s'.repeat(32)),
  DATA_KEY_ID:'synthetic-current-admin',DATA_ENCRYPTION_KEY:btoa('s'.repeat(32)),
  PRIVATE_MEDIA:{async get(key){const value=objects.get(key);return value?{size:value.length,text:async()=>value}:null;}}};
 async function work(claims,fn,{beforeBatch}={}){
  const admission=await openApplicationWork({backend:sqlFenceBackend(business,control),sourceSha256,kind:'http_admin'});
  const db=new PostgresDatabase(business,claims??{},admission);
  if(beforeBatch){const original=db.batch.bind(db);let fired=false;db.batch=async statements=>{
   if(!fired&&statements.some(item=>item.sql?.startsWith("UPDATE momo_processing_jobs SET state='pending'"))){fired=true;await beforeBatch();}
   return original(statements);
  };}
  try{return await fn({...base,DB:db,COLLECT_FENCE_WORK:admission});}
  finally{const closed=await admission.finish();assert.equal(closed.applicationWorkFinished,true);assert.equal(closed.providerSettlement,false);closures.push(closed);}
 }
 async function account(role,serial){
  const auth=crypto.randomUUID(),session=crypto.randomUUID(),principal=crypto.randomUUID(),aid=crypto.randomUUID(),at=epoch()-3;
  const email=`synthetic-${role}-${serial}@example.invalid`,created=stamp();
  await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${auth},${email},now())`;
  await sql`INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES(${session},${auth},'aal1',now()+interval '1 hour')`;
  await sql`INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at) VALUES(${principal},${email},${String(810000+serial)},'Synthetic Admin operator','operator',${created},${created})`;
  await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES(${auth},${principal},'synthetic-managed-auth-only')`;
  await sql`INSERT INTO app.admin_users(id,email,role,status,password_hash,created_at,updated_at) VALUES(${aid},${email},${role},'active','supabase-managed',${at},${at})`;
  await sql`INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES(${aid},${principal},'synthetic-review',${created})`;
  const claims={sub:auth,session_id:session,role:'authenticated',aud:'authenticated',aal:'aal1',iat:at,exp:at+3600,iss:project+'/auth/v1',amr:[{method:'otp',timestamp:at}]};
  const user={id:auth,email,email_confirmed_at:created,factors:[],app_metadata:{provider:'email'}};
  const token=btoa('{}')+'.'+btoa(JSON.stringify(claims))+'.synthetic-signature';tokens.set(token,{user,claims});
  const response=await work({},env=>issueAdminSession(new Request(origin+'/api/admin/auth/verify',{method:'POST',headers:{Origin:origin,'Content-Type':'application/json','X-Collect-Requested-With':'collect-admin'},body:'{}'}),env,{access_token:token,refresh_token:'synthetic-refresh'}));
  assert.equal(response.status,200);const cookie=response.headers.get('Set-Cookie').split(';')[0],body=await response.json();
  const row=(await sql`SELECT a.id,a.email,s.token_hash,s.public_id,s.origin,s.auth_session_id FROM app.admin_users a JOIN app.admin_sessions s ON s.user_id=a.id WHERE a.id=${aid}`)[0];
  return {auth,session,principal,aid,at,email,claims,cookie,csrf:body.csrfToken,row};
 }
 async function establishEmailProof(admin){
  const challenge=crypto.randomUUID(),hash=await digest('email:'+admin.email);
  await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at) VALUES(${admin.session},'otp',to_timestamp(${admin.at}))`;
  await sql`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)
   VALUES(${challenge},${hash},'email',${admin.email},'admin',0,${admin.at-1},${admin.at+299},1,${admin.at},'accepted')`;
  await work(admin.claims,env=>env.DB.prepare('SELECT private.admin_email_record_initial(?,?,?,?,?) AS result')
   .bind(admin.row.id,admin.row.token_hash,admin.row.origin,admin.row.public_id,challenge).first());
 }
 async function call(admin,path,body,key,{csrf=true,beforeBatch}={}){
  return work({},env=>worker.fetch(new Request(origin+'/api/admin/'+path,{method:'POST',headers:{Origin:origin,Cookie:admin.cookie,
   'Content-Type':'application/json','X-Collect-Requested-With':'collect-admin',...(csrf?{'X-Collect-CSRF':admin.csrf}:{}),'Idempotency-Key':key},body:JSON.stringify(body)}),env,{waitUntil(){}}),{beforeBatch});
 }
 async function expect(response,status){const body=await response.json();assert.equal(response.status,status,JSON.stringify(body));return body;}
 const receiver=crypto.randomUUID(),receiverHash=await digest('synthetic-current-admin-receiver');
 const profile={sender_allowlist:['MTN MoMo'],currency_aliases:['RWF'],incoming_prefixes:['You have received'],transaction_id_prefixes:['TxId:'],date_format:'DMY_HMS',utc_offset_minutes:120};
 const created=stamp();
 try{
  await sql`INSERT INTO app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,currency,timezone,profile_status,profile_version,profile_json,created_at)
   VALUES(${receiver},'mtn_momo','250788123456','Synthetic receiver',${receiverHash},'RWF','Africa/Kigali','approved','synthetic.v1',${JSON.stringify(profile)},${created})`;
  async function capture(body){
   const raw=crypto.randomUUID(),key='sms/'+raw,content=new TextEncoder().encode(JSON.stringify({raw_sender:'MTN MoMo',raw_body:body,completeness:'complete'})),
    bodyHash=await digest(body),plainHash=await digest(content),aad=`sms:${raw}:${plainHash}`,cipher=await encrypt(base,content,aad),sealedHash=await digest(cipher),
    scope={ownerId:member,entityId:raw,purpose:'sms_receipt'},metadata={sha256:plainHash,source_fingerprint:'a'.repeat(64)},operation=crypto.randomUUID();
   objects.set(key,cipher);
   await sql.begin(async tx=>{
    await tx`INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body) VALUES(${key},${'a'.repeat(64)},${scope},${aad},'synthetic-current-admin',${plainHash},${cipher})`;
    await tx`INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state) VALUES(${operation},${key},${'b'.repeat(64)},${sealedHash},${cipher.length},${scope},${{}},${metadata},'committed')`;
    await tx`INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata) VALUES(${key},${operation},${'b'.repeat(64)},${sealedHash},${cipher.length},${scope},${{}},${metadata})`;
    await tx`INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at)
     VALUES(${raw},${member},${sid},${crypto.randomUUID()},${bodyHash},${receiverHash},${key},${plainHash},${content.length},${stamp()})`;
   });
   return {raw,bodyHash};
  }
  const admin=await account('admin',1),staff=await account('staff',2),before=(await sql`SELECT (SELECT count(*)::int FROM app.payments) AS payments,(SELECT count(*)::int FROM app.ledger_entries) AS ledger`)[0];
  const historical=await capture('Synthetic historical source awaiting review');
  await sql`INSERT INTO app.momo_processing_jobs(raw_sms_id,mode,state,available_at,created_at,updated_at) VALUES(${historical.raw},'historical','source_unresolved',${epoch()},${created},${created})`;
  const resolution={reason:'Review this synthetic historical source',receiving_account_id:receiver,evidence_reference:'synthetic source review evidence'},path='momo/sources/'+historical.raw+'/resolve';
  await expect(await call(admin,path,resolution,crypto.randomUUID()),403);
  assert.equal((await sql`SELECT count(*)::int AS n FROM app.momo_source_resolutions WHERE raw_sms_id=${historical.raw}`)[0].n,0);
  await establishEmailProof(admin);
  await expect(await call(admin,path,resolution,crypto.randomUUID(),{csrf:false}),403);
  const key=crypto.randomUUID(),resolved=await expect(await call(admin,path,resolution,key),200);assert.equal(resolved.status,'pending');
  const replay=await expect(await call(admin,path,resolution,key),200);assert.deepEqual(replay,resolved);
  await expect(await call(admin,path,resolution,crypto.randomUUID()),409);
  const row=(await sql`SELECT state,last_error,receiving_account_id FROM app.momo_processing_jobs WHERE raw_sms_id=${historical.raw}`)[0];
  assert.equal(row.state,'pending');assert.equal(row.last_error,MOMO_JOB_CHECKPOINT.reparse);assert.equal(row.receiving_account_id,receiver);
  assert.equal((await sql`SELECT count(*)::int AS n FROM app.momo_source_resolutions WHERE raw_sms_id=${historical.raw}`)[0].n,1);

  const unknown=await capture('Synthetic provider response unknown');
  await sql`INSERT INTO app.momo_processing_jobs(raw_sms_id,receiving_account_id,mode,state,attempt_count,available_at,last_error,created_at,updated_at)
   VALUES(${unknown.raw},${receiver},'historical','needs_review',1,${epoch()},${MOMO_JOB_CHECKPOINT.unknown},${created},${created})`;
  const reparse={reason:'Review retained synthetic extraction'},unknownPath='momo/sources/'+unknown.raw+'/reparse';
  const denied=await expect(await call(admin,unknownPath,reparse,crypto.randomUUID()),409);assert.equal(denied.error.code,'provider_outcome_unresolved');
  await expect(await call(staff,unknownPath,reparse,crypto.randomUUID()),403);
  assert.equal((await sql`SELECT last_error FROM app.momo_processing_jobs WHERE raw_sms_id=${unknown.raw}`)[0].last_error,MOMO_JOB_CHECKPOINT.unknown);

  const safe=await capture('Synthetic reviewed safe extraction');
  await sql`INSERT INTO app.momo_processing_jobs(raw_sms_id,receiving_account_id,mode,state,attempt_count,available_at,last_error,created_at,updated_at)
   VALUES(${safe.raw},${receiver},'historical','needs_review',1,${epoch()},'provider_profile_unverified',${created},${created})`;
  const safePath='momo/sources/'+safe.raw+'/reparse';let raced=false;
  await expect(await call(admin,safePath,reparse,crypto.randomUUID(),{beforeBatch:async()=>{
   raced=true;await sql`UPDATE app.momo_processing_jobs SET last_error=${MOMO_JOB_CHECKPOINT.unknown} WHERE raw_sms_id=${safe.raw}`;
  }}),409);
  assert.equal(raced,true);assert.equal((await sql`SELECT last_error FROM app.momo_processing_jobs WHERE raw_sms_id=${safe.raw}`)[0].last_error,MOMO_JOB_CHECKPOINT.unknown);
  await sql`UPDATE app.momo_processing_jobs SET last_error='provider_profile_unverified' WHERE raw_sms_id=${safe.raw}`;
  const safeKey=crypto.randomUUID(),accepted=await expect(await call(admin,safePath,reparse,safeKey),200);assert.equal(accepted.status,'pending');
  assert.deepEqual(await expect(await call(admin,safePath,reparse,safeKey),200),accepted);
  const safeState=(await sql`SELECT state,last_error,attempt_count FROM app.momo_processing_jobs WHERE raw_sms_id=${safe.raw}`)[0];
  assert.equal(safeState.state,'pending');assert.equal(safeState.last_error,MOMO_JOB_CHECKPOINT.reparse);assert.equal(Number(safeState.attempt_count),1);

  const reference='SYNTHETIC_'+crypto.randomUUID(),body=`You have received RWF 1,000 from Synthetic Payer **007. TxId: ${reference} on 20/10/2026 11:30:00. Fee: 0. Balance: 9000.`,corrected=await capture(body);
  await sql`INSERT INTO app.momo_processing_jobs(raw_sms_id,receiving_account_id,mode,state,attempt_count,available_at,last_error,created_at,updated_at)
   VALUES(${corrected.raw},${receiver},'historical','needs_review',1,${epoch()},'provider_profile_unverified',${created},${created})`;
  const extraction={schema_version:MOMO_SCHEMA_VERSION,event_kind:'incoming_receipt',payment_outcome:'successful',transaction_id_raw:reference,original_transaction_id_raw:null,
   transaction_datetime_raw:'20/10/2026 11:30:00',principal_amount_raw:'1,000',currency_raw:'RWF',payer_name_raw:'Synthetic Payer',payer_identifier_raw:'**007',payment_reference_raw:null,
   fee_amount_raw:'0',wallet_balance_after_raw:'9000',evidence:{incoming_success:'You have received RWF 1,000',principal:'1,000',transaction_id:reference,
    transaction_datetime:'20/10/2026 11:30:00',payer:'Synthetic Payer **007',fee:'Fee: 0',wallet_balance_after:'Balance: 9000'},issues:[]};
  const correction={expected_state:'needs_review',expected_attempt_count:1,expected_body_sha256:corrected.bodyHash,extraction,evidence_reference:'synthetic source evidence',reason:'Correct the synthetic source from evidence'};
  const correctedResult=await expect(await call(admin,'momo/sources/'+corrected.raw+'/correct-extraction',correction,crypto.randomUUID()),200);
  assert.equal(correctedResult.status,'review_recorded');assert.equal(correctedResult.financial_effects,0);
  const review=(await sql`SELECT state,attempt_count FROM app.momo_processing_jobs WHERE raw_sms_id=${corrected.raw}`)[0];
  assert.equal(review.state,'completed');assert.equal(Number(review.attempt_count),2);
  assert.equal((await sql`SELECT count(*)::int AS n FROM app.momo_transaction_sources WHERE raw_sms_id=${corrected.raw}`)[0].n,1);
  const after=(await sql`SELECT (SELECT count(*)::int FROM app.payments) AS payments,(SELECT count(*)::int FROM app.ledger_entries) AS ledger`)[0];assert.deepEqual({...after},{...before});
  assert.equal(unexpectedFetches,0);
  return {checks:['missing_fresh_email_proof_and_missing_csrf_denied','authorized_resolution_and_idempotent_replay_keep_one_evidence_row',
   'unknown_outcome_and_insufficient_staff_role_denied','reparse_compare_and_set_refuses_concurrent_unknown','authorized_reparse_and_replay','authorized_manual_correction_has_no_financial_effect'],
   synthetic_auth_get_user_calls:syntheticAuthCalls,unexpected_network_calls:unexpectedFetches,auth_and_storage_fixture_only:true,actual_provider_calls:0,
   completed_admissions:closures.length,production_acceptance:false};
 }finally{globalThis.fetch=originalFetch;}
}
