import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fixture,PASSWORD,NEW_PASSWORD,setupToken} from './admin_support/fixture.mjs';
import {recoveryQuarantinePlan} from '../../../scripts/cloudflare/recovery_quarantine.mjs';
import {current15Fixture} from './support/recovery15_fixture.mjs';
import {processMomoJob,drainMomoJobs} from '../src/momo_pipeline.js';
import {momoGatewayRoute} from '../src/momo_gateway.js';
import {passwordHash} from '../src/admin_account_support/security.js';

// The ordinary fixture installs all seventeen migrations. Historical exact profiles stay
// independently covered by the recovery tool suite; current integration must
// also quarantine restored gateway credentials, pairings and processing leases.
const plan=(schemaProfile='candidate17')=>recoveryQuarantinePlan({archiveSha256:'a'.repeat(64),sourceId:'b'.repeat(64),operationId:randomUUID(),createdAt:new Date(Math.floor(Date.now()/1000)*1000).toISOString(),schemaProfile});
const batch=(f,p)=>{assert.ok(['candidate15','candidate17'].includes(p.schema_profile));return p.statements.map(({sql,params})=>f.db.prepare(sql).bind(...params));};
async function rows(f,tables){return Object.fromEntries(await Promise.all(tables.map(async name=>[name,(await f.db.prepare('SELECT * FROM '+name).all()).results.map(r=>JSON.stringify(r)).sort()])));}
async function operator(f,options){const account=await f.seedAccount(options);return {...await f.stepUp(await f.login(account)),account};}
async function recordedContribution(f,owner,reviewer,member){
 const group=await f.operation('groups',owner.cookie,{title:'Recovery contribution fixture',slug:'recovery-'+randomUUID(),collection_type:'ikimina',owner_user_id:member.id,
  receiver:{label:'Recorded receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Controlled recovery fixture'});assert.equal(group.status,200,JSON.stringify(group));
 const payment=await f.operation('transactions',owner.cookie,{group_id:group.body.resource_id,payee_id:group.body.resource_id,amount_rwf:7199254740991,
  provider_reference:'retained-'+randomUUID(),observed_at:new Date().toISOString(),evidence:'Exact retained recovery evidence; no provider settlement claim.',reason:'Controlled recovery fixture'});assert.equal(payment.status,200,JSON.stringify(payment));
 const person=await f.db.prepare('SELECT * FROM users WHERE id=?').bind(member.id).first();
 const proposal=await f.call(`/api/admin/reconciliations/${payment.body.resource_id}/proposals`,{cookie:owner.cookie,headers:{'Idempotency-Key':randomUUID()},data:{
  member_user_id:member.id,amount_rwf:7199254740991,expected_transaction_version:1,expected_member_version:person.revision,expected_membership_version:1,
  expected_payment_identity:{display_name:person.full_name,momo_provider:person.momo_provider,momo_number:person.momo_number,momo_pay_code:person.momo_pay_code},reason:'Controlled independent attribution'}});assert.equal(proposal.status,200,JSON.stringify(proposal));
 const approval=await f.call(`/api/admin/reconciliations/proposals/${proposal.body.resource_id}/reviews`,{cookie:reviewer.cookie,headers:{'Idempotency-Key':randomUUID()},data:{
  outcome:'approved',expected_proposal_version:1,expected_transaction_version:1,reason:'Controlled independent review'}});assert.equal(approval.status,200,JSON.stringify(approval));
 return {groupId:group.body.resource_id,paymentId:payment.body.resource_id};
}

test('restored cookie/bearer/refresh/MFA/OTP/reset/invite authority is quarantined while populated evidence and history remain exact',async t=>{
 const f=await fixture(t),owner=await operator(f),reviewer=await operator(f,{email:'recovery-reviewer@example.com',role:'admin'}),member=await f.seedMember(),native=await f.nativeLogin(member.phone);
 const financial=await recordedContribution(f,owner,reviewer,member);
 const memberPending=await f.call('/v1/auth/otp',{origin:'https://collect.example',data:{phone:'+250788123457',captcha_token:randomUUID()}});assert.equal(memberPending.status,202);
 const otpMessage=f.messages.find(r=>r.request_id===memberPending.body.challenge_id);assert.ok(otpMessage);
 const mfa=await f.call('/api/admin/auth/mfa/challenge',{cookie:owner.cookie,data:{factor_id:owner.factor.id}});assert.equal(mfa.status,200);
 assert.equal((await f.call('/api/admin/auth/forgot-password',{data:{email:owner.account.email}})).status,202);
 for(let attempt=0;attempt<50&&f.mail.length===0;attempt++)await new Promise(resolve=>setTimeout(resolve,20));
 const resetToken=setupToken(f.mail.at(-1));
 assert.equal((await f.call('/api/admin/team/invite',{cookie:owner.cookie,data:{email:'pending-recovery@example.com',role:'staff',displayName:'Pending recovery fixture'}})).status,201);
 const invitedEmail='pending-recovery@example.com',invited=await f.db.prepare('SELECT id,status FROM admin_users WHERE email=?').bind(invitedEmail).first();assert.equal(invited.status,'invited');
 const invitation=f.mail.findLast(message=>message.to===invitedEmail&&message.subject==='Your invitation to Collect');assert.ok(invitation,'Invitation is delivered');assert.ok(!invitation.text.includes('/admin/setup?'),'Current invitation does not issue a legacy password token');
 const invitedOtp=await f.call('/api/admin/auth/otp',{data:{email:invitedEmail}});assert.equal(invitedOtp.status,202);
 const signIn=f.mail.findLast(message=>message.to===invitedEmail&&message.subject==='Your Collect Admin sign-in code');assert.ok(signIn);const invitedCode=/\n\n([0-9]{6})\n\n/.exec(signIn.text)?.[1];assert.ok(invitedCode);
 assert.equal((await f.db.prepare('SELECT delivery_status FROM admin_email_otp_challenges WHERE id=?').bind(invitedOtp.body.challenge_id).first()).delivery_status,'accepted');
 const protectedTables=['collections','memberships','payments','payment_evidence','ledger_entries','reconciliations','request_receipts','admin_bridge_requests','admin_bridge_reconciliation_snapshots','auth_otp_verifications','auth_identity_rate_aliases','auth_rate_claims','auth_otp_throttles','auth_mfa_claims','auth_refresh_tokens','native_capabilities','native_capability_claims','roster_imports','upload_objects','notification_events'];
 const before=await rows(f,protectedTables),bucket=await f.mf.getR2Bucket('PRIVATE_MEDIA'),objects=await bucket.list(),objectBytes=await Promise.all(objects.objects.map(async r=>[r.key,await(await bucket.get(r.key)).text()]));
 const p=plan();await f.db.batch(batch(f,p));
 assert.equal((await f.call('/api/admin/auth/session',{method:'GET',cookie:owner.cookie})).body.user,null);
 assert.equal((await f.call('/api/admin/core/overview',{method:'GET',cookie:reviewer.cookie})).status,401);
 assert.equal((await f.call('/v1/auth/user',{method:'GET',origin:'https://collect.example',headers:{Authorization:`Bearer ${native.access_token}`}})).status,401);
 assert.equal((await f.call('/v1/auth/refresh',{origin:'https://collect.example',data:{refresh_token:native.refresh_token}})).status,401);
 assert.equal((await f.call('/v1/auth/verify',{origin:'https://collect.example',data:{phone:'+250788123457',challenge_id:memberPending.body.challenge_id,code:otpMessage.code,captcha_token:randomUUID()}})).status,401);
 assert.equal((await f.call('/api/admin/auth/complete-password',{data:{token:resetToken,password:NEW_PASSWORD,invite:false}})).status,400);
 assert.equal((await f.call('/api/admin/auth/verify',{data:{email:invitedEmail,challenge_id:invitedOtp.body.challenge_id,code:invitedCode}})).status,401);
 assert.equal((await f.db.prepare('SELECT status FROM admin_users WHERE id=?').bind(invited.id).first()).status,'revoked');
 assert.equal((await f.db.prepare('SELECT delivery_status FROM admin_email_otp_challenges WHERE id=?').bind(invitedOtp.body.challenge_id).first()).delivery_status,'superseded');
 assert.equal((await f.call('/api/admin/auth/login',{data:{email:owner.account.email,password:PASSWORD}})).status,401);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM users WHERE access_status='active'").first()).n,0);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM auth_sessions WHERE revoked_at IS NULL').first()).n,0);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM auth_mfa_factors WHERE status!='revoked'").first()).n,0);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM auth_mfa_challenges WHERE consumed_at IS NULL AND attempts<5").first()).n,0);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM admin_users WHERE status!='revoked' OR password_hash IS NOT NULL").first()).n,0);
 assert.deepEqual(await rows(f,protectedTables),before);
 assert.deepEqual(await Promise.all(objects.objects.map(async r=>[r.key,await(await bucket.get(r.key)).text()])),objectBytes);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM ledger_entries').first()).n,1);
 assert.equal((await f.db.prepare('SELECT amount_minor FROM ledger_entries WHERE payment_id=?').bind(financial.paymentId).first()).amount_minor,7199254740991);
 assert.equal((await f.db.prepare('PRAGMA foreign_key_check').all()).results.length,0);
 const marker=await f.db.prepare("SELECT * FROM audit_log WHERE action='recovery.access.quarantined'").first();assert.equal(JSON.parse(marker.details_json).archive_sha256,p.archive_sha256);
 assert.ok(!marker.details_json.includes(resetToken));assert.ok(!marker.details_json.includes(member.phone));
});

test('a failed recovery batch rolls back revocations, accounts and the retained operation marker',async t=>{
 const f=await fixture(t),account=await f.seedAccount(),login=await f.login(account),p=plan();
 const statements=batch(f,p);statements.splice(statements.length-1,0,f.db.prepare("INSERT INTO admin_bridge_guards(id,passed) VALUES('controlled-late-recovery-failure',0)"));
 await assert.rejects(f.db.batch(statements),/admin_bridge_state/);
 assert.ok((await f.call('/api/admin/auth/session',{method:'GET',cookie:login.cookie})).body.user);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='recovery.access.quarantined'").first()).n,0);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_bridge_guards').first()).n,0);
});

test('unknown-outcome replay is exact and does not quarantine a newly approved principal again',async t=>{
 const f=await fixture(t),account=await f.seedAccount(),login=await f.login(account),p=plan();await f.db.batch(batch(f,p));
 const after=await rows(f,['users','admin_users','auth_sessions','audit_log']);
 await f.db.batch(batch(f,p));assert.deepEqual(await rows(f,['users','admin_users','auth_sessions','audit_log']),after);
 // A separate, explicit fixture models later approval. Replaying the earlier
 // operation must be a readback, not silently extend its revocation boundary.
 const approved=await f.seedAccount({email:'newly-approved@example.com',role:'admin'}),fresh=await f.login(approved);
 await f.db.batch(batch(f,p));assert.ok((await f.call('/api/admin/auth/session',{method:'GET',cookie:fresh.cookie})).body.user);
 assert.equal((await f.call('/api/admin/auth/session',{method:'GET',cookie:login.cookie})).body.user,null);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='recovery.access.quarantined'").first()).n,1);
});

test('a conflicting operation identity fails before altering any reapproved authority',async t=>{
 const f=await fixture(t),p=plan();await f.db.batch(batch(f,p));
 const account=await f.seedAccount(),fresh=await f.login(account),changed=recoveryQuarantinePlan({archiveSha256:'c'.repeat(64),sourceId:p.source_id,operationId:p.operation_id,createdAt:p.created_at,schemaProfile:'candidate17'});
 await assert.rejects(f.db.batch(batch(f,changed)),/admin_bridge_state/);
 assert.ok((await f.call('/api/admin/auth/session',{method:'GET',cookie:fresh.cookie})).body.user);
});

test('existing suspended/deleted principals and final session/factor revocations are preserved',async t=>{
 const f=await fixture(t),owner=await operator(f),member=await f.seedMember(),session=await f.db.prepare('SELECT * FROM auth_sessions WHERE user_id=?').bind(owner.account.userId).first(),past=Math.floor(Date.now()/1000)-1;
 await f.db.prepare("UPDATE auth_sessions SET revoked_at=?,revocation_reason='pre_disaster_logout' WHERE id=?").bind(past,session.id).run();
 await f.db.prepare("UPDATE auth_mfa_factors SET status='revoked',revoked_at=? WHERE id=?").bind(past,owner.factor.id).run();
 await f.db.prepare("UPDATE users SET access_status='deleted' WHERE id=?").bind(member.id).run();
 const before=await rows(f,['auth_sessions','auth_mfa_factors']);await f.db.batch(batch(f,plan()));
 assert.deepEqual(await rows(f,['auth_sessions','auth_mfa_factors']),before);
 assert.equal((await f.db.prepare('SELECT access_status FROM users WHERE id=?').bind(member.id).first()).access_status,'deleted');
});

test('a saved single-use native capability remains retained but cannot authorize a claim after recovery quarantine',async t=>{
 const f=await fixture(t),member=await f.seedMember(),native=await f.nativeLogin(member.phone),current=Math.floor(Date.now()/1000),
  sessionId=JSON.parse(Buffer.from(native.access_token.split('.')[1],'base64url')).session_id,hash=value=>createHash('sha256').update(value).digest('hex'),receiverHash=hash(member.phone);
 assert.equal((await f.call('/v1/rpc/record_sms_access_consent',{origin:'https://collect.example',headers:{Authorization:`Bearer ${native.access_token}`},data:{enabled:true,momo_number_hash:receiverHash,build_channel:'android_native_sms',request_id:randomUUID()}})).status,200);
 const insert=(name,row)=>f.db.prepare(`INSERT INTO ${name}(${Object.keys(row).join(',')}) VALUES(${Object.keys(row).map(()=>'?').join(',')})`).bind(...Object.values(row));
 // Controlled saved-admission rows exercise the real D1 claim trigger. This
 // does not replace the separate real Google Play admission requirement.
 const reservation=randomUUID(),capability=randomUUID(),payloadSha='d'.repeat(64),record={id:reservation,user_id:member.id,session_id:sessionId,nonce:randomUUID(),action:'sms.ingest',request_hash:'a'.repeat(64),token_sha256:'b'.repeat(64),receiver_hash:receiverHash,verified_phone:member.phone,
  payload_sha256:payloadSha,payload_ciphertext:'{}',policy_sha256:'c'.repeat(64),approval_id:randomUUID(),approval_evidence_sha256:'e'.repeat(64),project_id:'controlled-recovery-fixture',created_seconds:current,expires_seconds:current+120,actor_hour_limit:10,project_day_limit:100};
 await insert('native_reservations',record).run();
 for(const phase of ['oauth','decode'])await insert('native_phases',{reservation_id:reservation,phase,started_seconds:current}).run();
 await insert('native_capabilities',{id:capability,token_sha256:'f'.repeat(64),reservation_id:reservation,user_id:member.id,session_id:sessionId,action:'sms.ingest',receiver_hash:receiverHash,verified_phone:member.phone,payload_sha256:payloadSha,created_seconds:current,expires_seconds:current+120,verdict_sha256:'a'.repeat(64)}).run();
 await insert('native_completions',{reservation_id:reservation,capability_id:capability,result_ciphertext:'{}',provider_response_sha256:'b'.repeat(64),completed_seconds:current,decode_duration_ms:1}).run();
 const claim=()=>insert('native_capability_claims',{id:randomUUID(),capability_id:capability,user_id:member.id,session_id:sessionId,action:'sms.ingest',payload_sha256:payloadSha,receiver_hash:receiverHash,claimed_seconds:Math.floor(Date.now()/1000)});
 await assert.rejects(f.db.batch([claim(),f.db.prepare("INSERT INTO admin_bridge_guards(id,passed) VALUES('controlled-native-rollback',0)")]),/admin_bridge_state/);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM native_capability_claims').first()).n,0);
 const before=await rows(f,['native_reservations','native_phases','native_capabilities','native_completions','native_consents']);await f.db.batch(batch(f,plan()));
 await assert.rejects(claim().run(),/native_capability_denied/);
 assert.deepEqual(await rows(f,['native_reservations','native_phases','native_capabilities','native_completions','native_consents']),before);
});

const momoImmutableTables=['momo_receiving_accounts','momo_parse_attempts','momo_transactions','momo_transaction_sources','momo_gateway_captures','momo_source_resolutions','momo_financial_links','contribution_posting_snapshots',
 'sms_receipts','payments','payment_evidence','ledger_entries','reconciliations','request_receipts','admin_bridge_requests','notification_events'];
async function bucketBytes(bucket){const listed=await bucket.list();assert.equal(listed.truncated,false);return Object.fromEntries(await Promise.all(listed.objects.map(async object=>[object.key,Buffer.from(await(await bucket.get(object.key)).arrayBuffer()).toString('base64')])));}
async function captureFor(c,pair=c.momo.gateway.pair){
 const capture={...c.momo.completed.capture,client_envelope_id:randomUUID(),gateway_binding_id:pair.binding.id,gateway_binding_version:pair.binding.version,
  service_centre_at:new Date().toISOString(),captured_at:new Date().toISOString()};
 const response=await momoGatewayRoute(new Request('https://api.collect.example/v1/momo/gateway/ingest',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+pair.gateway_token},body:JSON.stringify(capture)}),c.momo.env),reply=await response.json();
 assert.equal(response.status,200,JSON.stringify(reply));return {capture,rawId:reply.receipt.raw_sms_id};
}
async function assertOldGatewayDenied(c){
 const headers={Authorization:'Bearer '+c.momo.gateway.pair.gateway_token};
 for(const [path,method,data]of [['status','GET',{}],['heartbeat','POST',{pending_count:0,oldest_pending_at:null,last_sms_at:null}],['ingest','POST',c.momo.completed.capture]]){
  const result=await c.f.call('/v1/momo/gateway/'+path,{method,origin:null,headers,data});assert.equal(result.status,401,JSON.stringify({path,result}));
 }
 for(const [pairing_code,installation_id]of [[c.momo.gateway.binding.pairing_code,c.momo.gateway.installation],[c.momo.unclaimed.pairing_code,randomUUID()]]){
  const result=await c.f.call('/v1/momo/gateway/pair',{origin:null,data:{pairing_code,installation_id}});assert.equal(result.status,401,JSON.stringify(result));
 }
}

test('candidate15 quarantines old gateway tokens/codes and all processing schedules while retaining populated13-table MoMo and financial history', {timeout:180000}, async t=>{
 const c=await current15Fixture(t),f=c.f,future=await captureFor(c),expired=await captureFor(c),seconds=Math.floor(Date.now()/1000);
 await f.db.prepare("UPDATE momo_processing_jobs SET available_at=? WHERE raw_sms_id=?").bind(seconds+86400,future.rawId).run();
 await f.db.prepare("UPDATE momo_processing_jobs SET state='processing',attempt_count=1,lease_token='expired-restored-worker',lease_until=0 WHERE raw_sms_id=?").bind(expired.rawId).run();
 const protectedBefore=await rows(f,momoImmutableTables),objectsBefore=await bucketBytes(c.bucket),jobsBefore=(await f.db.prepare('SELECT * FROM momo_processing_jobs ORDER BY raw_sms_id').all()).results;
 const revokedBinding=await f.db.prepare('SELECT * FROM momo_gateway_bindings WHERE id=?').bind(c.momo.revoked.binding.binding_id).first(),revokedCredential=await f.db.prepare('SELECT * FROM momo_gateway_credentials WHERE binding_id=?').bind(c.momo.revoked.binding.binding_id).first();
 const p=plan('candidate15');await f.db.batch(batch(f,p));await assertOldGatewayDenied(c);
 const jobsAfter=(await f.db.prepare('SELECT * FROM momo_processing_jobs ORDER BY raw_sms_id').all()).results;
 for(const before of jobsBefore){const after=jobsAfter.find(row=>row.raw_sms_id===before.raw_sms_id);assert.ok(after);
  for(const field of ['raw_sms_id','binding_id','binding_version','receiving_account_id','mode','created_at','attempt_count','max_attempts','available_at'])assert.equal(after[field],before[field],field);
  if(['pending','retry','processing'].includes(before.state)){assert.equal(after.state,'needs_review');assert.equal(after.last_error,'disaster_recovery_quarantine');assert.equal(after.lease_token,null);assert.equal(after.lease_until,null);}else assert.deepEqual(after,before);
 }
 assert.deepEqual(await f.db.prepare('SELECT * FROM momo_gateway_bindings WHERE id=?').bind(revokedBinding.id).first(),revokedBinding);
 assert.deepEqual(await f.db.prepare('SELECT * FROM momo_gateway_credentials WHERE id=?').bind(revokedCredential.id).first(),revokedCredential);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM momo_processing_guards').first()).n,0);
 let calls=0;const env={...c.momo.env,MOMO_PROCESSING_PAUSED:'false',AI:{run:async()=>{calls++;throw new Error('Quarantined work must not invoke AI');}}};
 for(const rawId of [c.momo.jobs.pending,c.momo.jobs.retry,c.momo.jobs.processing,c.momo.jobs.resolved,future.rawId,expired.rawId])assert.equal((await processMomoJob(env,rawId)).state,'not_claimed');
 assert.equal((await drainMomoJobs(env,{limit:20})).processed,0);assert.equal(calls,0);
 assert.deepEqual(await rows(f,momoImmutableTables),protectedBefore);assert.deepEqual(await bucketBytes(c.bucket),objectsBefore);

 // Explicit fixture reapproval creates a new credential boundary. Restoring
 // the same principal alone must not revive any old token or pairing code.
 await f.db.prepare("UPDATE users SET access_status='active',updated_at=? WHERE id=?").bind(new Date().toISOString(),c.account.userId).run();
 await f.db.prepare("UPDATE admin_users SET status='active',password_hash=?,auth_version=auth_version+1,updated_at=unixepoch() WHERE id=?").bind(await passwordHash(NEW_PASSWORD),c.account.adminId).run();
 const login=await f.call('/api/admin/auth/login',{data:{email:c.account.email,password:NEW_PASSWORD}});assert.equal(login.status,200,JSON.stringify(login));const approved=await f.stepUp(login);
 await assertOldGatewayDenied(c);
 const binding=await f.call('/api/admin/momo/bindings',{cookie:approved.cookie,headers:{'Idempotency-Key':randomUUID()},data:{receiving_account_id:c.momo.accountId,reason:'Explicit controlled post-recovery installation approval'}});assert.equal(binding.status,200,JSON.stringify(binding));
 const pair=await f.call('/v1/momo/gateway/pair',{origin:null,data:{pairing_code:binding.body.pairing_code,installation_id:randomUUID()}});assert.equal(pair.status,200,JSON.stringify(pair));
 const fresh=await captureFor(c,pair.body),freshBefore=await rows(f,['momo_gateway_bindings','momo_gateway_pairings','momo_gateway_credentials','momo_processing_jobs']);
 await f.db.batch(batch(f,p));assert.deepEqual(await rows(f,['momo_gateway_bindings','momo_gateway_pairings','momo_gateway_credentials','momo_processing_jobs']),freshBefore);
 const status=await f.call('/v1/momo/gateway/status',{method:'GET',origin:null,headers:{Authorization:'Bearer '+pair.body.gateway_token}});assert.equal(status.status,200,JSON.stringify(status));
 assert.equal((await f.db.prepare('SELECT state FROM momo_processing_jobs WHERE raw_sms_id=?').bind(fresh.rawId).first()).state,'pending');
 await assertOldGatewayDenied(c);assert.equal((await f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='recovery.access.quarantined'").first()).n,1);
 const after=await rows(f,momoImmutableTables);for(const [table,before]of Object.entries(protectedBefore))assert.ok(before.every(row=>after[table].includes(row)),table+' retained immutable history');
 const objectsAfter=await bucketBytes(c.bucket);for(const [key,bytes]of Object.entries(objectsBefore))assert.equal(objectsAfter[key],bytes,key);
 assert.equal((await f.db.prepare('PRAGMA foreign_key_check').all()).results.length,0);
});

test('candidate15 recovery fences an already awaited AI completion without a new attempt, canonical receipt or financial effect', {timeout:180000}, async t=>{
 const c=await current15Fixture(t),f=c.f,capture=await captureFor(c),synthetic=JSON.parse(await readFile(new URL('fixtures/momo-synthetic.json',import.meta.url),'utf8'));
 const output=structuredClone(synthetic.output);output.principal_amount_raw='1,250';output.evidence.incoming_success=output.evidence.incoming_success.replace('5,000','1,250');output.evidence.principal=output.evidence.principal.replace('5,000','1,250');
 let signal,release,calls=0;const started=new Promise(resolve=>{signal=resolve;}),completion=new Promise(resolve=>{release=resolve;});
 const env={...c.momo.env,MOMO_PROCESSING_PAUSED:'false',AI:{run:async()=>{calls++;signal();await completion;return {response:output};}}};
 const processing=processMomoJob(env,capture.rawId);
 try{
  await started;assert.equal(calls,1);assert.equal((await f.db.prepare('SELECT state FROM momo_processing_jobs WHERE raw_sms_id=?').bind(capture.rawId).first()).state,'processing');
  const before=await rows(f,momoImmutableTables),objectsBefore=await bucketBytes(c.bucket);await f.db.batch(batch(f,plan('candidate15')));release();
  assert.equal((await processing).state,'superseded');assert.deepEqual(await rows(f,momoImmutableTables),before);assert.deepEqual(await bucketBytes(c.bucket),objectsBefore);
  const job=await f.db.prepare('SELECT * FROM momo_processing_jobs WHERE raw_sms_id=?').bind(capture.rawId).first();assert.equal(job.state,'needs_review');assert.equal(job.attempt_count,1);assert.equal(job.lease_token,null);assert.equal(job.lease_until,null);
  assert.equal((await drainMomoJobs(env,{limit:20})).processed,0);assert.equal(calls,1,'No AI call may start after recovery parking');await assertOldGatewayDenied(c);
 }finally{release();await processing;}
});
