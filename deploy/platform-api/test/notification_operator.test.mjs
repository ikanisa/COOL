import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash,randomBytes} from 'node:crypto';
import {totp,signed} from './support/auth_fixture.mjs';
import {fixture} from './support/notification_operator_fixture.mjs';
import {encrypt} from '../src/encryption.js';
import {assistedSmsDestinationContext} from '../src/notification_operator.js';
const hash=v=>createHash('sha256').update(v).digest('hex');
const dataEnv={DATA_KEY_ID:'admin-test-v1',DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64')};
const command=(s,action,body={},headers={},cookie=s.operator.cookie)=>s.f.call('/api/admin/notification-operator',{cookie,data:{action,...body},headers:{'X-Collect-Admin':'1',...headers}});
const good=r=>{assert.equal(r.status,200,JSON.stringify(r));assert.equal(r.body.ok,true);return r.body.result;};
async function setup(t,{role='owner',assurance=2,source=true,queue=true}={}){
 const f=await fixture(t),account=await f.seedAccount({role,email:role==='owner'?'info@ikanisa.com':role+'@operator.example.test'}),login=await f.login(account),operator=assurance===2?await f.stepUp(login):login;
 if(role==='owner'&&assurance===2)good(await f.call('/api/admin/notification-operator/access',{cookie:operator.cookie,headers:{'X-Collect-Admin':'1'},data:{request_id:randomUUID(),expected_read:false,expected_manage:false,expected_decision_revision:0,enabled:true,owner_confirmation:true}}));
 const s={f,account,operator};t.after(()=>{assert.equal(f.messages.length,0,'No SMS/OTP provider sends');assert.equal(f.mail.length,0,'No email sends');});
 const session=await f.call('/api/admin/auth/session',{method:'GET',cookie:operator.cookie});assert.equal(session.status,200);s.session=session.body.user;
 s.authSession=(await f.db.prepare('SELECT auth_session_id FROM admin_sessions WHERE public_id=?').bind(s.session.sessionId).first()).auth_session_id;
 if(!source)return s;
 const member=await f.seedMember(),date=new Date().toISOString(),group=randomUUID(),payment=randomUUID(),evidence=randomUUID(),entry=randomUUID(),proof=randomUUID(),proofOperation=randomUUID(),memberSession=randomUUID(),seconds=Math.floor(Date.now()/1000);
 // Explicitly generated isolated facts, not actual provider/finance approval.
 await f.db.batch([
  f.db.prepare("INSERT INTO collections(id,slug,creator_user_id,title,description,collection_type,created_at,updated_at) VALUES(?,?,?,'Synthetic SMS group','','ikimina',?,?)").bind(group,'synthetic-'+group,member.id,date,date),
  f.db.prepare("INSERT INTO memberships(id,collection_id,user_id,role,active,joined_at) VALUES(?,?,?,'owner',1,?)").bind(randomUUID(),group,member.id,date),
  f.db.prepare("INSERT INTO payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,amount_minor,observed_at,created_at) VALUES(?,?,?,?,?,1,'text/plain','operator_recorded',?,1250,?,?)").bind(evidence,group,account.userId,'synthetic-evidence/'+evidence,hash('Explicitly synthetic unverified receipt'),randomUUID(),date,date),
  f.db.prepare("INSERT INTO payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at) VALUES(?,?,?,?,1250,'reconciled',?)").bind(payment,group,member.id,evidence,date),
  f.db.prepare("INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,1250,'contribution',?,?,?,?)").bind(entry,payment,group,member.id,evidence,account.userId,randomUUID(),date),
  // Declared generated proof rows for the engine-only cohort. Real phone
  // verification is separately exercised by the integration cohort; this
  // fixture neither delivers nor pretends to verify an actual recipient.
  f.db.prepare("INSERT INTO auth_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,code_hash,created_at,expires_at,status,consumed_at,consumed_operation_id) VALUES(?,?,'phone',?,'member',0,?,?,?,'consumed',?,?)").bind(proof,hash('Synthetic identity model'),member.phone,hash('Synthetic non-OTP model'),seconds,seconds+300,seconds,proofOperation),
  f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',?,?,?)").bind(memberSession,member.id,seconds,seconds,seconds+3600),
  f.db.prepare('INSERT INTO auth_otp_verifications(operation_id,challenge_id,user_id,session_id,verified_at) VALUES(?,?,?,?,?)').bind(proofOperation,proof,member.id,memberSession,seconds),
  f.db.prepare("INSERT INTO assisted_sms_policies(collection_id,enabled,revision,template_key,approval_reference_sha256,updated_at) VALUES(?,1,1,'collect.recorded_contribution.v1',?,?)").bind(group,hash('Synthetic test-only policy approval, not owner approval'),date),
  f.db.prepare('INSERT INTO assisted_sms_authorizations(collection_id,recipient_user_id,enabled,consent_revision,destination_revision,destination_ciphertext,destination_sha256,phone_verification_challenge_id,authorization_receipt_sha256,updated_at) VALUES(?,?,1,1,1,?,?,?,?,?)')
   .bind(group,member.id,await encrypt(dataEnv,new TextEncoder().encode(member.phone),assistedSmsDestinationContext(group,member.id,1)),hash(member.phone),proof,hash('Synthetic explicit test-only recipient authorization'),date),
 ]);
 Object.assign(s,{member,group,payment,evidence,entry});
 if(queue){const result=await f.call('/__synthetic_enqueue',{cookie:operator.cookie,data:{payment_id:payment,request_id:randomUUID()}});s.job=good(result);}
 return s;
}
async function claim(s,headers={}){return good(await command(s,'claim',{job_id:s.job.job_id,request_id:randomUUID(),worker_id:'synthetic-operator',expected_fence:0},headers));}
const ids=c=>({job_id:c.job_id,claim_token:c.claim_token,fence_version:c.fence_version});
async function confirmation(s,c,headers={}){
 const content=good(await command(s,'get_claimed',ids(c)));
 const body={...ids(c),request_id:randomUUID(),confirmation_id:randomUUID(),body_sha256:content.body_sha256,destination_sha256:content.destination_sha256,destination_revision:content.destination_revision,user_confirmation:true};
 return {result:await command(s,'confirm',body,headers),body,content};
}
const startBody=(c,k)=>({...ids(c),confirmation_id:k.confirmation_id,request_id:randomUUID()});
async function freshLogin(s){
 const login=await s.f.login(s.account),factor=s.operator.factor;
 const challenge=await s.f.call('/api/admin/auth/mfa/challenge',{cookie:login.cookie,data:{factor_id:factor.id}});assert.equal(challenge.status,200,JSON.stringify(challenge));
 // Real verifier accepts its documented adjacent TOTP counter. The current
 // counter was consumed by the previous sign-in and is never reset or reused.
 const result=await s.f.call('/api/admin/auth/mfa/verify',{cookie:login.cookie,data:{factor_id:factor.id,challenge_id:challenge.body.challenge_id,code:totp(factor.totp.secret,Math.floor(Date.now()/30000)+1)}});assert.equal(result.status,200,JSON.stringify(result));return result;
}
async function shortAuthority(s){
 // A declared valid short-lived SYNTHETIC credential cohort. Lifetime is
 // fixed before insertion; no immutable row, trigger, clock or auth code is
 // changed. Standard production issuance remains eight hours and is not
 // relabeled by this narrow expiry test.
 const original=await s.f.db.prepare('SELECT * FROM auth_sessions WHERE id=?').bind(s.authSession).first(),sid=randomUUID(),publicId=randomUUID(),token=randomBytes(32).toString('hex'),expires=Math.floor(Date.now()/1000)+3,created=original.mfa_at;
 await s.f.db.batch([
  s.f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at,assurance_level,mfa_at,mfa_factor_id) VALUES(?,?,'admin',?,?,?,2,?,?)").bind(sid,s.account.userId,created,created,expires,original.mfa_at,original.mfa_factor_id),
  s.f.db.prepare('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at) VALUES(?,?,?,1,?,?,?,?)').bind(hash(token),publicId,s.account.adminId,sid,'https://admin-preview.collect.ikanisa.com',created,expires),
  s.f.db.prepare('UPDATE admin_sessions SET issued_assurance_level=2,issued_mfa_at=?,issued_mfa_factor_id=? WHERE public_id=?').bind(original.mfa_at,original.mfa_factor_id,publicId),
 ]);
 s.operator={...s.operator,cookie:'__Host-collect_admin='+token};s.authSession=sid;s.session=goodSession(await s.f.call('/api/admin/auth/session',{method:'GET',cookie:s.operator.cookie}));s.syntheticExpires=expires;
}
function goodSession(reply){assert.equal(reply.status,200,JSON.stringify(reply));assert.ok(reply.body.user);return reply.body.user;}
const count=async(s,table)=>Number((await s.f.db.prepare(`SELECT count(*) AS n FROM ${table}`).first()).n);
async function signedRows(s){return {claims:(await s.f.db.prepare('SELECT * FROM assisted_sms_claims ORDER BY id').all()).results,confirmations:(await s.f.db.prepare('SELECT * FROM assisted_sms_confirmations ORDER BY id').all()).results,starts:(await s.f.db.prepare('SELECT * FROM assisted_sms_send_starts ORDER BY id').all()).results};}
async function revoke(s,cause){
 const db=s.f.db;
 if(cause==='logout')await s.f.call('/api/admin/auth/logout',{cookie:s.operator.cookie});
 else if(cause==='expiry'){
  assert.ok(s.syntheticExpires);const delay=Math.max(0,s.syntheticExpires*1000-Date.now()+50);if(delay)await new Promise(r=>setTimeout(r,delay));
 }else if(cause==='identity')await db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(s.account.userId).run();
 else if(cause==='approval')await db.prepare('DELETE FROM admin_principal_links WHERE admin_user_id=?').bind(s.account.adminId).run();
 else if(cause==='role')await db.prepare("UPDATE admin_users SET role='staff',email='former-owner@synthetic.example.test' WHERE id=?").bind(s.account.adminId).run();
 else if(cause==='permission')await db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='assisted_sms.manage'").bind(s.account.userId).run();
 else if(cause==='assurance')await db.prepare('UPDATE auth_sessions SET assurance_level=1,mfa_at=NULL,mfa_factor_id=NULL WHERE id=?').bind(s.authSession).run();
 else throw new Error('Unknown test revocation');
}

test('real cookie/MFA claim, exact content, confirmation and first send boundary preserve immutable original sessions',async t=>{
 const s=await setup(t),c=await claim(s),k=await confirmation(s,c),confirmed=good(k.result),body=startBody(c,confirmed),started=good(await command(s,'record_send_start',body));
 assert.equal(started.may_send,true);assert.equal(started.delivery_confirmed,false);assert.equal(started.provider_confirmation,false);assert.equal(started.settlement_status,'not_asserted');
 assert.equal(k.content.destination_e164,s.member.phone);assert.match(k.content.message_body,/Provider confirmation not asserted/);assert.ok(!k.content.message_body.includes('settled'));
 for(const table of ['assisted_sms_claims','assisted_sms_confirmations','assisted_sms_send_starts']){
  const row=await s.f.db.prepare(`SELECT * FROM ${table}`).first();assert.equal(row.originating_session_id,s.authSession);assert.equal(row.public_session_id,s.session.sessionId);assert.equal(row.actor_admin_id,s.account.adminId);
  await assert.rejects(s.f.db.prepare(`DELETE FROM ${table}`).run(),/retain_immutable_sms_evidence/);
  await assert.rejects(s.f.db.prepare(`UPDATE ${table} SET originating_session_id=?`).bind(randomUUID()).run(),/retain_immutable_sms_evidence/);
 }
 const audits=(await s.f.db.prepare("SELECT * FROM audit_log WHERE action LIKE 'assisted_sms.%'").all()).results;assert.ok(audits.length>=4);assert.ok(audits.every(r=>r.actor_session_id===s.authSession));
 const receipts=(await s.f.db.prepare("SELECT * FROM request_receipts WHERE operation LIKE 'assisted_sms.%'").all()).results;
 assert.ok(!JSON.stringify([...audits,...receipts]).includes(s.member.phone));assert.ok(!JSON.stringify([...audits,...receipts]).includes(k.content.message_body));
 assert.ok(!JSON.stringify(receipts).includes('may_send'));
});

test('same request replays a recorded start without another permit, and another request cannot consume its confirmation',async t=>{
 const s=await setup(t),c=await claim(s),k=good((await confirmation(s,c)).result),body=startBody(c,k);
 const first=good(await command(s,'record_send_start',body)),again=good(await command(s,'record_send_start',body));
 assert.equal(first.may_send,true);assert.equal(again.may_send,false);assert.equal(again.attempt_id,first.attempt_id);assert.equal(again.replay,true);
 assert.equal((await command(s,'record_send_start',{...body,request_id:randomUUID()})).status,409);assert.equal(await count(s,'assisted_sms_send_starts'),1);
 const state=good(await command(s,'get_operation',{request_id:body.request_id}));assert.equal(state.observed,true);assert.equal(state.may_send,false);assert.equal(state.receipt.attempt_id,first.attempt_id);
});

test('actual committed D1 reply loss reconciles the original attempt and never issues a replacement permit',async t=>{
 const s=await setup(t),c=await claim(s),k=good((await confirmation(s,c)).result),body=startBody(c,k);let pauses=0;s.f.setGate(()=>{pauses++;});
 const result=good(await command(s,'record_send_start',body,{'X-Test-Pause':'lost_reply'}));assert.equal(pauses,1);assert.equal(result.may_send,false);assert.match(result.acknowledgement,/unknown_reply/);
 assert.equal(await count(s,'assisted_sms_send_starts'),1);assert.equal((await s.f.db.prepare('SELECT state FROM assisted_sms_jobs').first()).state,'send_started');
 assert.equal(good(await command(s,'record_send_start',body)).may_send,false);assert.equal(await count(s,'assisted_sms_send_starts'),1);
});

test('same-user fresh MFA session cannot adopt earlier claims, confirmations or original operation receipts',async t=>{
 const s=await setup(t),c=await claim(s),k=good((await confirmation(s,c)).result),body=startBody(c,k),next=await freshLogin(s);
 assert.equal((await command(s,'get_claimed',ids(c),{},next.cookie)).status,409);
 assert.equal((await command(s,'record_send_start',body,{},next.cookie)).status,409);
 const originalClaim=await s.f.db.prepare('SELECT request_id FROM assisted_sms_claims').first();assert.equal((await command(s,'get_operation',{request_id:originalClaim.request_id},{},next.cookie)).status,409);
 assert.equal(await count(s,'assisted_sms_send_starts'),0);
 await s.f.call('/api/admin/auth/logout',{cookie:s.operator.cookie});
 assert.equal((await command(s,'get_claimed',ids(c),{},next.cookie)).status,409);
 assert.equal((await command(s,'record_send_start',body,{},next.cookie)).status,409);
 assert.equal(goodSession(await s.f.call('/api/admin/auth/session',{method:'GET',cookie:next.cookie})).principalId,s.account.userId);
});

for(const cause of ['logout','expiry','identity','approval','role','permission','assurance'])for(const phase of ['confirm','record_send_start'])test(`${cause}: both serial orderings at ${phase} preserve original authority and immutable completed evidence`,async t=>{
 const first=await setup(t);if(cause==='expiry')await shortAuthority(first);const c=await claim(first),k=await confirmation(first,c);good(k.result);
 let completed,body;
 if(phase==='confirm'){completed=good(k.result);body=k.body;}
 else {body=startBody(c,k.result.body.result);completed=good(await command(first,phase,body));assert.equal(completed.may_send,true);}
 const before=await signedRows(first);await revoke(first,cause);
 const afterReply=await command(first,phase,body);assert.ok([401,403].includes(afterReply.status),JSON.stringify(afterReply));assert.deepEqual(await signedRows(first),before);
 const second=await setup(t);if(cause==='expiry')await shortAuthority(second);const c2=await claim(second);let input;
 if(phase==='confirm'){
  const content=good(await command(second,'get_claimed',ids(c2)));input={...ids(c2),request_id:randomUUID(),confirmation_id:randomUUID(),body_sha256:content.body_sha256,destination_sha256:content.destination_sha256,destination_revision:content.destination_revision,user_confirmation:true};
 }else input=startBody(c2,good((await confirmation(second,c2)).result));
 const frozen=await signedRows(second);let paused=0;second.f.setGate(async({phase:at})=>{assert.equal(at,'before_commit');paused++;await revoke(second,cause);});
 const denied=await command(second,phase,input,{'X-Test-Pause':'before_commit'});assert.equal(paused,1);assert.ok([401,403].includes(denied.status),JSON.stringify(denied));assert.deepEqual(await signedRows(second),frozen);
 assert.equal((await second.f.db.prepare('SELECT count(*) AS n FROM request_receipts WHERE request_id=?').bind(input.request_id).first()).n,0);
 assert.equal((await second.f.db.prepare('SELECT count(*) AS n FROM audit_log WHERE request_id=?').bind(input.request_id).first()).n,0);
});

test('winning revocation during awaited content work prevents plaintext release at the final guarded read',async t=>{
 const s=await setup(t),c=await claim(s);let paused=0;s.f.setGate(async()=>{paused++;await revoke(s,'permission');});
 const result=await command(s,'get_claimed',ids(c),{'X-Test-Pause':'content_final'});assert.equal(paused,1);assert.equal(result.status,403);assert.ok(!JSON.stringify(result.body).includes(s.member.phone));assert.ok(!JSON.stringify(result.body).includes('Collect record: RWF'));
 assert.equal(await count(s,'assisted_sms_confirmations'),0);assert.equal(await count(s,'assisted_sms_send_starts'),0);
});

test('missing consent/policy never queues a message and none of the candidate permissions reaches non-owner roles',async t=>{
 const s=await setup(t,{queue:false});await s.f.db.prepare('UPDATE assisted_sms_authorizations SET enabled=0,consent_revision=consent_revision+1').run();
 const denied=await s.f.call('/__synthetic_enqueue',{cookie:s.operator.cookie,data:{payment_id:s.payment,request_id:randomUUID()}});assert.equal(denied.status,409);assert.equal(await count(s,'assisted_sms_jobs'),0);
 const roles=(await s.f.db.prepare("SELECT role,permission FROM admin_account_role_capabilities WHERE substr(permission,1,13)='assisted_sms.' ORDER BY permission").all()).results;assert.deepEqual(roles,[{role:'owner',permission:'assisted_sms.manage'},{role:'owner',permission:'assisted_sms.read'}]);
});

for(const change of ['consent','destination','policy','membership','source_reversal'])test(`changed ${change} between confirmation and send start denies a new permit atomically`,async t=>{
 const s=await setup(t),c=await claim(s),k=good((await confirmation(s,c)).result),body=startBody(c,k);s.f.setGate(async()=>{
  if(change==='consent')await s.f.db.prepare('UPDATE assisted_sms_authorizations SET enabled=0,consent_revision=consent_revision+1').run();
  else if(change==='destination')await s.f.db.prepare('UPDATE assisted_sms_authorizations SET destination_revision=destination_revision+1,consent_revision=consent_revision+1').run();
  else if(change==='policy')await s.f.db.prepare('UPDATE assisted_sms_policies SET revision=revision+1').run();
  else if(change==='membership')await s.f.db.prepare('UPDATE memberships SET active=0 WHERE collection_id=?').bind(s.group).run();
  else await s.f.db.prepare("INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,reverses_entry_id,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,-1250,'reversal',?,?,?,?,?)").bind(randomUUID(),s.payment,s.group,s.member.id,s.entry,s.evidence,s.account.userId,randomUUID(),new Date().toISOString()).run();
 });
 const result=await command(s,'record_send_start',body,{'X-Test-Pause':'before_commit'});assert.equal(result.status,409,JSON.stringify(result));assert.equal(await count(s,'assisted_sms_send_starts'),0);
 assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM request_receipts WHERE request_id=?').bind(body.request_id).first()).n,0);
});

test('confirmation requires exact recipient/content and explicit human confirmation; invalid actions cannot supply identity',async t=>{
 const s=await setup(t),c=await claim(s),valid=await confirmation(s,c);good(valid.result);
 for(const extra of [{user_confirmation:false},{body_sha256:'0'.repeat(64)},{destination_revision:2},{destination_sha256:'0'.repeat(64)},{operator_user_id:s.account.userId},{operator_session_id:s.authSession}]){
  const reply=await command(s,'confirm',{...valid.body,request_id:randomUUID(),confirmation_id:randomUUID(),...extra});assert.ok([400,409].includes(reply.status),JSON.stringify(reply));
 }
 assert.equal((await command(s,'record_send_start',{...ids(c),request_id:randomUUID(),confirmation_id:randomUUID(),operator_user_id:s.account.userId})).status,400);
 assert.equal((await command(s,'unknown',{})).status,400);
 assert.equal((await command(s,'list_pending',{limit:51})).status,400);
 assert.equal((await command(s,'list_pending',{after_created_at:'2026-99-99T00:00:00.000Z',after_job_id:randomUUID()})).status,400);
 assert.equal(await count(s,'assisted_sms_confirmations'),1);assert.equal(await count(s,'assisted_sms_send_starts'),0);
});

test('release invalidates an unconsumed exact confirmation; a later claim has a higher fence and cannot reuse it',async t=>{
 const s=await setup(t),c=await claim(s),k=good((await confirmation(s,c)).result);
 const released=good(await command(s,'release_claim',{...ids(c),request_id:randomUUID()}));assert.equal(released.state,'queued');assert.equal(released.fence_version,2);
 const next=good(await command(s,'claim',{job_id:s.job.job_id,request_id:randomUUID(),worker_id:'next-synthetic-worker',expected_fence:2}));assert.equal(next.fence_version,3);
 assert.equal((await command(s,'record_send_start',startBody(c,k))).status,409);assert.equal(await count(s,'assisted_sms_send_starts'),0);
 assert.equal(await count(s,'assisted_sms_confirmations'),1);
});

test('a current new session may record an observation without adopting the old send permit or claiming delivery',async t=>{
 const s=await setup(t),c=await claim(s),k=good((await confirmation(s,c)).result),started=good(await command(s,'record_send_start',startBody(c,k)));
 await revoke(s,'logout');const current=await freshLogin(s),request={attempt_id:started.attempt_id,request_id:randomUUID(),observation:'observed_sent',evidence_reference_sha256:hash('Synthetic human observation only; no SMS transport acknowledgement')};
 const pending=good(await command(s,'list_pending',{}, {},current.cookie));assert.equal(pending.items[0].attempt_id,started.attempt_id);assert.equal(pending.items[0].state,'send_started');
 const outcome=good(await command(s,'record_outcome',request,{},current.cookie));assert.equal(outcome.may_send,false);assert.equal(outcome.delivery_confirmed,false);assert.equal(outcome.observation,'observed_sent');
 const stored=await s.f.db.prepare('SELECT * FROM assisted_sms_outcomes').first();assert.notEqual(stored.observer_session_id,s.authSession);assert.equal((await s.f.db.prepare('SELECT originating_session_id FROM assisted_sms_send_starts').first()).originating_session_id,s.authSession);
 assert.deepEqual(good(await command(s,'record_outcome',request,{},current.cookie)),outcome);
 assert.equal((await command(s,'record_outcome',{...request,request_id:randomUUID(),observation:'uncertain'},{},current.cookie)).status,409);
 assert.equal(await count(s,'assisted_sms_send_starts'),1);assert.equal(await count(s,'assisted_sms_outcomes'),1);
});

test('a pre-dispatch unknown result has no durable start; explicit status read precedes the original-key resume',async t=>{
 const s=await setup(t),c=await claim(s),k=good((await confirmation(s,c)).result),body=startBody(c,k);let pauses=0;
 s.f.setGate(()=>{pauses++;throw new Error('synthetic_no_dispatch_gate');});
 const failed=await command(s,'record_send_start',body,{'X-Test-Pause':'before_commit'});assert.equal(failed.status,503);assert.equal(failed.body.error.code,'sms_operation_unknown');assert.equal(pauses,1);assert.equal(await count(s,'assisted_sms_send_starts'),0);
 const status=good(await command(s,'get_operation',{request_id:body.request_id}));assert.equal(status.observed,false);assert.equal(status.may_send,false);
 s.f.setGate(()=>{});const resumed=good(await command(s,'record_send_start',body));assert.equal(resumed.may_send,true);assert.equal(await count(s,'assisted_sms_send_starts'),1);
});

test('claim admission rechecks current permission in its atomic batch and creates no receipt or audit on denial',async t=>{
 const s=await setup(t),requestId=randomUUID();s.f.setGate(()=>revoke(s,'permission'));
 const result=await command(s,'claim',{job_id:s.job.job_id,request_id:requestId,worker_id:'synthetic-denied-worker',expected_fence:0},{'X-Test-Pause':'before_commit'});
 assert.equal(result.status,403);assert.equal(await count(s,'assisted_sms_claims'),0);assert.equal((await s.f.db.prepare('SELECT state FROM assisted_sms_jobs').first()).state,'queued');
 for(const table of ['request_receipts','audit_log'])assert.equal((await s.f.db.prepare(`SELECT count(*) AS n FROM ${table} WHERE request_id=?`).bind(requestId).first()).n,0);
});

test('withdrawal and fresh consent revisions cannot revive an earlier encrypted job or confirmation',async t=>{
 const s=await setup(t),c=await claim(s),k=good((await confirmation(s,c)).result);
 await assert.rejects(s.f.db.prepare('UPDATE assisted_sms_authorizations SET enabled=0').run(),/sms_authorization_revision_required/);
 await s.f.db.prepare('UPDATE assisted_sms_authorizations SET enabled=0,consent_revision=2').run();
 await s.f.db.prepare('UPDATE assisted_sms_authorizations SET enabled=1,consent_revision=3').run();
 assert.equal((await command(s,'record_send_start',startBody(c,k))).status,409);assert.equal((await command(s,'get_claimed',ids(c))).status,409);
 await assert.rejects(s.f.db.prepare('UPDATE assisted_sms_jobs SET consent_revision=3').run(),/immutable_sms_envelope/);assert.equal(await count(s,'assisted_sms_send_starts'),0);
 const job=await s.f.db.prepare('SELECT policy_approval_sha256,authorization_receipt_sha256 FROM assisted_sms_jobs').first();assert.equal(job.policy_approval_sha256,hash('Synthetic test-only policy approval, not owner approval'));assert.equal(job.authorization_receipt_sha256,hash('Synthetic explicit test-only recipient authorization'));
});

test('a valid canonical Admin bearer is not a cookie operator authority, and origin/method/header smuggling is refused',async t=>{
 const s=await setup(t),row=await s.f.db.prepare('SELECT * FROM auth_sessions WHERE id=?').bind(s.authSession).first(),now=Math.floor(Date.now()/1000);
 const bearer=signed({iss:'collect-test',aud:'collect',sub:s.account.userId,session_id:s.authSession,iat:now,exp:now+300,auth_time:row.auth_at,role:'authenticated',aal:'aal2',mfa_at:row.mfa_at,mfa_factor_id:row.mfa_factor_id});
 const valid=await s.f.call('/v1/auth/user',{method:'GET',origin:'https://collect.example',headers:{Authorization:'Bearer '+bearer}});assert.equal(valid.status,200,JSON.stringify(valid));
 const noCookie=await s.f.call('/api/admin/notification-operator',{data:{action:'list_pending'},headers:{Authorization:'Bearer '+bearer,'X-Collect-Admin':'1'}});assert.equal(noCookie.status,401);
 assert.equal((await s.f.call('/api/admin/notification-operator',{cookie:s.operator.cookie,data:{action:'list_pending'}})).status,403);
 assert.equal((await s.f.call('/api/admin/notification-operator',{method:'GET',cookie:s.operator.cookie})).status,405);
 assert.equal((await s.f.call('/api/admin/notification-operator',{cookie:s.operator.cookie,origin:'https://outside.example',data:{action:'list_pending'},headers:{'X-Collect-Admin':'1'}})).status,403);
 assert.equal(await count(s,'assisted_sms_claims'),0);
});


test('concurrent exact start requests issue at most one first-response permit and retain exactly one attempt',async t=>{
 const s=await setup(t),c=await claim(s),k=good((await confirmation(s,c)).result),body=startBody(c,k);
 const responses=await Promise.all([command(s,'record_send_start',body),command(s,'record_send_start',body)]);const values=responses.map(good);
 assert.equal(values.filter(v=>v.may_send===true).length,1);assert.equal(values.filter(v=>v.may_send===false).length,1);assert.equal(values[0].attempt_id,values[1].attempt_id);assert.equal(await count(s,'assisted_sms_send_starts'),1);
 assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM audit_log WHERE action='assisted_sms.send_start'").first()).n,1);
});


test('interleaved original-key start observes the winning commit before stale-claim failure and never reissues its permit',async t=>{
 const s=await setup(t),c=await claim(s),k=good((await confirmation(s,c)).result),body=startBody(c,k);let winning,pauses=0;
 s.f.setGate(async()=>{pauses++;winning=good(await command(s,'record_send_start',body));assert.equal(winning.may_send,true);});
 const replay=good(await command(s,'record_send_start',body,{'X-Test-Pause':'start_claim_read'}));assert.equal(pauses,1);assert.equal(replay.may_send,false);assert.equal(replay.attempt_id,winning.attempt_id);assert.equal(await count(s,'assisted_sms_send_starts'),1);
});
