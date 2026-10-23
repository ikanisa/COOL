import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {fixture,PASSWORD,NEW_PASSWORD} from './support/notification_operator_integration_fixture.mjs';
import {claims,signed,totp} from './support/auth_fixture.mjs';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {decrypt} from '../src/encryption.js';
import {assistedSmsDestinationContext} from '../src/notification_operator.js';
const hash=x=>createHash('sha256').update(x).digest('hex');
const ok=r=>{assert.equal(r.status,200,JSON.stringify(r));return r.body.result??r.body;};
const dataEnv={DATA_KEY_ID:'admin-test-v1',DATA_ENCRYPTION_KEY:Buffer.from(Array.from({length:32},(_,i)=>i+1)).toString('base64')};
const count=async(s,table)=>Number((await s.f.db.prepare('SELECT count(*) AS n FROM '+table).first()).n);
async function setup(t,{role='owner',assurance=2,phone=true,access=true,migrationsThrough=null}={}){
 const f=await fixture(t,{}, {migrationsThrough}),account=await f.seedAccount({role,email:role==='owner'?'info@ikanisa.com':role+'@operator.example.test'}),login=await f.login(account),operator=assurance===2?await f.stepUp(login):login;
 if(access&&role==='owner'&&assurance===2)ok(await f.call('/api/admin/notification-operator/access',{cookie:operator.cookie,headers:{'X-Collect-Admin':'1'},data:{request_id:randomUUID(),expected_read:false,expected_manage:false,expected_decision_revision:0,enabled:true,owner_confirmation:true}}));
 const session=phone?await f.nativeLogin():null,member=phone?{id:claims(session.access_token).sub,phone:'+250788123456'}:await f.seedMember();
 const group=randomUUID(),date=new Date().toISOString();
 await f.db.batch([
  f.db.prepare("INSERT INTO collections(id,slug,creator_user_id,title,description,collection_type,created_at,updated_at) VALUES(?,?,?,'Synthetic receipt integration','','ikimina',?,?)").bind(group,'synthetic-'+group,member.id,date,date),
  f.db.prepare("INSERT INTO memberships(id,collection_id,user_id,role,active,joined_at) VALUES(?,?,?,'owner',1,?)").bind(randomUUID(),group,member.id,date),
 ]);
 return {f,account,operator,session,member,group};
}
const policy=(s,body,extra={})=>s.f.call('/api/admin/notification-operator/policies/'+s.group,{cookie:s.operator.cookie,data:body,headers:{'X-Collect-Admin':'1',...extra}});
const configure=(s,enabled=true,revision=0,extra={})=>policy(s,{request_id:randomUUID(),expected_revision:revision,enabled,...(enabled?{owner_confirmation:true}:{})},extra);
const consent=(s,body={},extra={})=>s.f.call('/v1/rpc/set_assisted_sms_consent_v1',{origin:'https://collect.example',data:{p_collection_id:s.group,p_expected_revision:0,p_expected_decision_revision:body.p_expected_revision??0,p_opt_in:true,p_request_id:randomUUID(),...body},headers:{Authorization:'Bearer '+s.session.access_token,...extra}});
const getConsent=s=>s.f.call('/v1/rpc/get_assisted_sms_consent_v1',{origin:'https://collect.example',data:{p_collection_id:s.group},headers:{Authorization:'Bearer '+s.session.access_token}});
const materialize=(s,limit=5,extra={},body={})=>s.f.call('/api/admin/notification-operator/materialize',{cookie:s.operator.cookie,data:{request_id:randomUUID(),collection_id:s.group,limit,...body},headers:{'X-Collect-Admin':'1',...extra}});
const materializationStatus=(s,requestId,extra={})=>s.f.call('/api/admin/notification-operator/materialize/'+requestId,{method:'GET',cookie:s.operator.cookie,headers:extra});
const accessOperation=(s,requestId,extra={})=>s.f.call('/api/admin/notification-operator/access/operations/'+requestId,{method:'GET',cookie:s.operator.cookie,headers:extra});
const command=(s,action,body={},extra={})=>s.f.call('/api/admin/notification-operator',{cookie:s.operator.cookie,data:{action,...body},headers:{'X-Collect-Admin':'1',...extra}});
const access=(s,body,extra={})=>s.f.call('/api/admin/notification-operator/access',{cookie:s.operator.cookie,data:body,headers:{'X-Collect-Admin':'1',...extra}});
const getAccess=s=>s.f.call('/api/admin/notification-operator/access',{method:'GET',cookie:s.operator.cookie});
const accessChoice=(enabled,expected=false)=>({request_id:randomUUID(),expected_read:expected,expected_manage:expected,expected_decision_revision:Number(expected),enabled,...(enabled?{owner_confirmation:true}:{})});
const notificationRows=s=>s.f.db.prepare("SELECT * FROM admin_grants WHERE permission IN('assisted_sms.read','assisted_sms.manage') ORDER BY user_id,permission").all();
async function payment(s,{status='reconciled',compensated=false}={}){
 const db=s.f.db,date=new Date().toISOString(),p=randomUUID(),e=randomUUID(),entry=randomUUID();
 await db.batch([
  db.prepare("INSERT INTO payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,amount_minor,observed_at,created_at) VALUES(?,?,?,?,?,1,'text/plain','operator_recorded',?,1250,?,?)").bind(e,s.group,s.account.userId,'synthetic-evidence/'+e,hash('Synthetic receipt source'),randomUUID(),date,date),
  db.prepare('INSERT INTO payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at) VALUES(?,?,?,?,1250,?,?)').bind(p,s.group,s.member.id,e,status,date),
  ...(status==='reconciled'?[db.prepare("INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,1250,'contribution',?,?,?,?)").bind(entry,p,s.group,s.member.id,e,s.account.userId,randomUUID(),date)]:[]),
 ]);
 if(compensated)await db.prepare("INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at,reverses_entry_id) VALUES(?,?,?,?,-1250,'reversal',?,?,?,?,?)").bind(randomUUID(),p,s.group,s.member.id,e,s.account.userId,randomUUID(),date,entry).run();
 return {id:p,entry,evidence:e};
}
async function ready(t){const s=await setup(t);ok(await configure(s));ok(await consent(s));await payment(s);const made=ok(await materialize(s));assert.equal(made.materialized_count,1);s.job=made.materialized_jobs[0];return s;}
async function claimed(s){return ok(await command(s,'claim',{job_id:s.job.job_id,request_id:randomUUID(),worker_id:'synthetic-integration',expected_fence:0}));}
const claimFields=c=>({job_id:c.job_id,claim_token:c.claim_token,fence_version:c.fence_version});
async function confirmed(s,c){const content=ok(await command(s,'get_claimed',claimFields(c))),confirmation_id=randomUUID();
 ok(await command(s,'confirm',{...claimFields(c),request_id:randomUUID(),confirmation_id,body_sha256:content.body_sha256,destination_sha256:content.destination_sha256,destination_revision:content.destination_revision,user_confirmation:true}));return {content,confirmation_id};}

test('owner policy defaults disabled; enabling requires explicit owner decision; raw receipt binds original sign-in',async t=>{
 const s=await setup(t,{phone:false}),initial=ok(await s.f.call('/api/admin/notification-operator/policies/'+s.group,{method:'GET',cookie:s.operator.cookie}));
 assert.equal(initial.enabled,false);assert.equal(initial.configured,false);assert.equal(initial.revision,0);
 assert.equal((await policy(s,{request_id:randomUUID(),expected_revision:0,enabled:true})).status,400);
 assert.equal((await policy(s,{request_id:randomUUID(),expected_revision:0,enabled:null})).status,400);
 const disabled=ok(await policy(s,{request_id:randomUUID(),expected_revision:0}));assert.equal(disabled.enabled,false);assert.equal(disabled.revision,1);
 const enabled=ok(await configure(s,true,1));assert.equal(enabled.revision,2);assert.equal(enabled.enabled,true);assert.equal(enabled.legal_release_approved,false);assert.equal(enabled.provider_approved,false);
 const receipt=await s.f.db.prepare('SELECT session_id,response_json FROM request_receipts WHERE request_id=?').bind(enabled.request_id).first();assert.equal(receipt.session_id,enabled.originating_session_id);assert.equal(JSON.parse(receipt.response_json).recorded_owner_decision_sha256,enabled.recorded_owner_decision_sha256);
 assert.equal((await configure(s,false,1)).status,409);assert.equal((await s.f.db.prepare('SELECT revision FROM assisted_sms_policies').first()).revision,2);
});
for(const role of ['admin','staff'])test('policy and producer deny non-owner '+role+' and unauthorized notification grants are not inserted',async t=>{
 const s=await setup(t,{role,phone:false});await s.f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(s.account.userId,'assisted_sms.manage',new Date().toISOString()).run();
 assert.equal((await configure(s)).status,403);assert.equal((await materialize(s)).status,403);assert.equal(await count(s,'assisted_sms_policies'),0);assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM admin_grants WHERE user_id=? AND permission='assisted_sms.manage'").bind(s.account.userId).first()).n,0);
});
test('policy requires issued fresh AAL2 and exact cookie origin/header',async t=>{
 const s=await setup(t,{phone:false,assurance:1});assert.equal((await configure(s)).status,403);
 assert.equal((await s.f.call('/api/admin/notification-operator/policies/'+s.group,{cookie:s.operator.cookie,data:{request_id:randomUUID(),expected_revision:0},origin:'https://evil.example'})).status,403);
 assert.equal((await s.f.call('/api/admin/notification-operator/policies/'+s.group,{cookie:s.operator.cookie,data:{request_id:randomUUID(),expected_revision:0}})).status,403);assert.equal(await count(s,'assisted_sms_policies'),0);
});
test('owner policy committed lost acknowledgement resolves same receipt without a second revision',async t=>{
 const s=await setup(t,{phone:false}),body={request_id:randomUUID(),expected_revision:0,enabled:false};
 const first=ok(await policy(s,body,{'X-Test-Pause':'lost_reply'})),repeat=ok(await policy(s,body));assert.deepEqual(first,repeat);assert.equal(await count(s,'assisted_sms_policies'),1);assert.equal(first.revision,1);
});
test('winning owner revocation rolls back policy receipt and source write atomically',async t=>{
 const s=await setup(t,{phone:false}),receipts=await count(s,'request_receipts');s.f.setGate(async()=>{await s.f.db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(s.account.userId).run();});
 assert.equal((await configure(s,true,0,{'X-Test-Pause':'before_commit'})).status,403);assert.equal(await count(s,'assisted_sms_policies'),0);assert.equal(await count(s,'request_receipts'),receipts);
});
test('real member phone OTP proof produces encrypted purpose-specific consent; no client recipient or number accepted',async t=>{
 const s=await setup(t),before=ok(await getConsent(s));assert.equal(before.opt_in,false);assert.equal(before.phone_verification_available,true);assert.equal(before.current_verified_phone_binding,false);
 const result=ok(await consent(s));assert.equal(result.purpose,'contribution_receipt_sms');assert.equal(result.consent_revision,1);assert.equal(result.destination_revision,1);
 const row=await s.f.db.prepare('SELECT * FROM assisted_sms_authorizations').first();assert.equal(row.destination_sha256,hash(s.member.phone));assert.equal(new TextDecoder().decode(await decrypt(dataEnv,row.destination_ciphertext,assistedSmsDestinationContext(s.group,s.member.id,1))),s.member.phone);
 assert.ok(row.phone_verification_challenge_id);assert.equal(JSON.stringify(result).includes(s.member.phone),false);assert.equal((await s.f.db.prepare('SELECT details_json FROM audit_log WHERE action=?').bind('assisted_sms.consent.set').first()).details_json.includes(s.member.phone),false);
 for(const extra of [{p_phone:'+250788999999'},{p_user_id:randomUUID()},{p_session_id:randomUUID()},{p_authorization_receipt_sha256:hash('self assertion')}])assert.equal((await consent(s,{p_expected_revision:1,...extra})).status,400);
 assert.equal((await consent(s,{p_expected_revision:1,p_opt_in:undefined})).status,400);assert.equal((await consent(s,{p_expected_revision:1,p_opt_in:'true'})).status,400);
 const after=ok(await getConsent(s));assert.equal(after.opt_in,true);assert.equal(after.current_verified_phone_binding,true);
});
test('email-only member session cannot borrow another session phone verification',async t=>{
 const s=await setup(t),date=new Date().toISOString();await s.f.db.prepare('UPDATE users SET email=?,updated_at=? WHERE id=?').bind('synthetic-member@example.test',date,s.member.id).run();
 const challenge=await s.f.call('/v1/auth/otp',{origin:'https://collect.example',data:{email:'synthetic-member@example.test',captcha_token:randomUUID()}});assert.equal(challenge.status,202);
 const observed=s.f.mail.findLast(x=>x.to==='synthetic-member@example.test'&&x.subject==='Your Collect sign-in code');assert.ok(observed,'Native email binding captured this recipient');
 const code=/^Your Collect sign-in code is ([0-9]{6})\. /.exec(observed.text)?.[1];assert.ok(code,'Native email contains the exact sign-in code');
 const verify=await s.f.call('/v1/auth/verify',{origin:'https://collect.example',data:{email:'synthetic-member@example.test',challenge_id:challenge.body.challenge_id,code,captcha_token:randomUUID()}});assert.equal(verify.status,200,JSON.stringify(verify));s.session=verify.body;
 assert.equal(ok(await getConsent(s)).phone_verification_available,false);assert.equal((await consent(s)).status,403);assert.equal(await count(s,'assisted_sms_authorizations'),0);
});
test('admin bearer, foreign member and Direct identity cannot create app receipt consent',async t=>{
 const s=await setup(t);const original=s.session;
 const adminSession=await s.f.db.prepare('SELECT id,auth_at FROM auth_sessions WHERE user_id=?').bind(s.account.userId).first();
 s.session={access_token:signed({...claims(original.access_token),sub:s.account.userId,session_id:adminSession.id,auth_time:adminSession.auth_at})};assert.equal((await consent(s)).status,403);
 s.session=await s.f.nativeLogin('+250789123456');assert.equal((await getConsent(s)).status,403);assert.equal((await consent(s)).status,403);
 s.session=original;await s.f.db.prepare("UPDATE users SET member_type='direct' WHERE id=?").bind(s.member.id).run();assert.equal(ok(await getConsent(s)).unavailable_reason,'direct_recipient_verification_required');assert.equal((await consent(s)).status,403);assert.equal(await count(s,'assisted_sms_authorizations'),0);
});
test('member consent CAS, original-key replay, redundant choices and lost reply retain one authorization revision',async t=>{
 const s=await setup(t),body={p_request_id:randomUUID()};const first=ok(await consent(s,body,{'X-Test-Pause':'lost_reply'})),same=ok(await consent(s,body));assert.equal(first.decision_sha256,same.decision_sha256);assert.equal(first.consent_revision,1);
 assert.equal((await consent(s)).status,409);const noop=ok(await consent(s,{p_expected_revision:1}));assert.equal(noop.consent_revision,1);assert.equal(noop.authorization_receipt_sha256,first.authorization_receipt_sha256);
 assert.equal((await s.f.db.prepare('SELECT consent_revision FROM assisted_sms_authorizations').first()).consent_revision,1);
});
test('member can withdraw after leaving or group archive without sending a new OTP',async t=>{
 const s=await setup(t);ok(await consent(s));const messages=s.f.messages.length;
 await s.f.db.batch([s.f.db.prepare('UPDATE memberships SET active=0 WHERE user_id=?').bind(s.member.id),s.f.db.prepare("UPDATE collections SET status='archived' WHERE id=?").bind(s.group)]);
 const result=ok(await consent(s,{p_expected_revision:1,p_opt_in:false}));assert.equal(result.opt_in,false);assert.equal(result.consent_revision,2);assert.equal(s.f.messages.length,messages);assert.equal(ok(await getConsent(s)).opt_in,false);
 assert.equal((await consent(s,{p_expected_revision:2})).status,403);
});
test('default opt-out writes no destination and invents no consent activation',async t=>{
 const s=await setup(t),result=ok(await consent(s,{p_opt_in:false}));assert.equal(result.consent_revision,0);assert.equal(result.destination_revision,null);assert.equal(result.authorization_receipt_sha256,null);assert.equal(await count(s,'assisted_sms_authorizations'),0);
});
for(const cause of ['phone','logout','suspension','membership'])test('winning '+cause+' change before consent commit rolls back all decision effects',async t=>{
 const s=await setup(t),receipts=await count(s,'request_receipts');s.f.setGate(async()=>{
  if(cause==='phone')await s.f.db.prepare('UPDATE users SET phone=?,updated_at=? WHERE id=?').bind('+250788999999',new Date().toISOString(),s.member.id).run();
  if(cause==='logout')assert.equal((await s.f.call('/v1/auth/logout',{origin:'https://collect.example',headers:{Authorization:'Bearer '+s.session.access_token}})).status,200);
  if(cause==='suspension')await s.f.db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(s.member.id).run();
  if(cause==='membership')await s.f.db.prepare('UPDATE memberships SET active=0 WHERE user_id=?').bind(s.member.id).run();
 });
 const result=await consent(s,{}, {'X-Test-Pause':'before_commit'});assert.equal(result.status,['logout','suspension'].includes(cause)?403:409,JSON.stringify(result));assert.equal(await count(s,'assisted_sms_authorizations'),0);assert.equal(await count(s,'request_receipts'),receipts);
});
test('bounded materializer uses committed positive lineage only; no policy or no consent creates nothing',async t=>{
 const s=await setup(t);await payment(s);assert.equal(ok(await materialize(s)).materialized_count,0);ok(await configure(s));assert.equal(ok(await materialize(s)).materialized_count,0);ok(await consent(s));
 await payment(s,{status:'recorded'});await payment(s,{compensated:true});await payment(s);await payment(s);
 const first=ok(await materialize(s,1));assert.equal(first.materialized_count,1);assert.equal(first.has_more_observed,true);assert.equal(first.transport_started,false);assert.equal(first.all_source_events_complete,false);
 const next=ok(await materialize(s,1)),last=ok(await materialize(s,1)),done=ok(await materialize(s,1));assert.equal(next.materialized_count,1);assert.equal(last.materialized_count,1);assert.equal(done.materialized_count,0);assert.equal(await count(s,'assisted_sms_jobs'),3);assert.equal(await count(s,'assisted_sms_send_starts'),0);
 assert.equal((await s.f.db.prepare('SELECT count(DISTINCT entry_id) AS n FROM assisted_sms_jobs').first()).n,3);
 assert.equal((await materialize(s,11)).status,400);
 assert.equal((await materialize(s,null)).status,400);
});
test('materializer lost per-source acknowledgement retains one job; restart excludes committed source',async t=>{
 const s=await setup(t);ok(await configure(s));ok(await consent(s));const source=await payment(s),result=ok(await materialize(s,5,{'X-Test-Pause':'lost_reply'}));assert.equal(result.materialized_count,1);assert.equal(await count(s,'assisted_sms_jobs'),1);
 assert.equal(ok(await materialize(s)).materialized_count,0);const receipt=await s.f.db.prepare('SELECT operation FROM request_receipts WHERE request_id=?').bind(source.entry).first();assert.equal(receipt.operation,'assisted_sms.enqueue');
});
test('materializer winning source change is an honest blocked partial outcome and never starts transport',async t=>{
 const s=await setup(t);ok(await configure(s));ok(await consent(s));const p=await payment(s);
 s.f.setGate(async()=>{await s.f.db.prepare('UPDATE payments SET revision=revision+1 WHERE id=?').bind(p.id).run();});
 const result=ok(await materialize(s,5,{'X-Test-Pause':'before_commit'}));assert.equal(result.status,'partial_blocked');assert.equal(result.materialized_count,0);assert.equal(result.blocked.source_entry_id,p.entry);assert.equal(await count(s,'assisted_sms_jobs'),0);assert.equal(await count(s,'assisted_sms_send_starts'),0);
});
test('materializer owner revocation aborts pending entry without creating an alternate service authority',async t=>{
 const s=await setup(t);ok(await configure(s));ok(await consent(s));await payment(s);s.f.setGate(async()=>{await s.f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='assisted_sms.manage'").bind(s.account.userId).run();});
 assert.equal((await materialize(s,5,{'X-Test-Pause':'before_commit'})).status,403);assert.equal(await count(s,'assisted_sms_jobs'),0);
});
test('valid consumed phone authorization survives recipient logout without borrowing ongoing member authority',async t=>{
 const s=await ready(t);assert.equal((await s.f.call('/v1/auth/logout',{origin:'https://collect.example',headers:{Authorization:'Bearer '+s.session.access_token}})).status,200);
 const c=await claimed(s);assert.equal(ok(await command(s,'get_claimed',claimFields(c))).destination_e164,s.member.phone);
});
test('declared historical valid proof remains usable after its one-time-code deadline without retaining a live recipient session',async t=>{
 const s=await setup(t);ok(await configure(s));ok(await consent(s));const seconds=Math.floor(Date.now()/1000)-3600,proof=randomUUID(),operation=randomUUID(),sid=randomUUID();
 // Explicit generated historical proof model, inserted with valid immutable
 // timestamps. This is not a real provider verification or a clock override.
 await s.f.db.batch([
  s.f.db.prepare("INSERT INTO auth_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,code_hash,created_at,expires_at,status,consumed_at,consumed_operation_id) VALUES(?,?,'phone',?,'member',0,?,?,?,'consumed',?,?)").bind(proof,hash('Synthetic historical identity'),s.member.phone,hash('Synthetic historical non-OTP'),seconds-10,seconds+60,seconds,operation),
  s.f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',?,?,?)").bind(sid,s.member.id,seconds,seconds,seconds+120),
  s.f.db.prepare('INSERT INTO auth_otp_verifications(operation_id,challenge_id,user_id,session_id,verified_at) VALUES(?,?,?,?,?)').bind(operation,proof,s.member.id,sid,seconds),
  s.f.db.prepare('UPDATE assisted_sms_authorizations SET phone_verification_challenge_id=?,consent_revision=consent_revision+1 WHERE collection_id=?').bind(proof,s.group),
 ]);
 await payment(s);const made=ok(await materialize(s));assert.equal(made.materialized_count,1);s.job=made.materialized_jobs[0];await claimed(s);
});
for(const invalid of ['withdrawn','missing','expired_before_verification'])test('retained phone proof '+invalid+' fails closed without adding an OTP-retention FK',async t=>{
 const s=await ready(t),c=await claimed(s),proof=(await s.f.db.prepare('SELECT phone_verification_challenge_id AS id FROM assisted_sms_authorizations').first()).id;
 if(invalid==='withdrawn')await s.f.db.prepare("UPDATE auth_otp_challenges SET status='superseded',consumed_at=NULL,consumed_operation_id=NULL WHERE id=?").bind(proof).run();
 if(invalid==='missing'){
  // Existing0011 forbids relabeling raw identity history. Keep that admission
  // intact. A missing reference is a declared synthetic cleanup projection,
  // not a claimed successful production redaction/deletion operation.
  await assert.rejects(s.f.db.prepare('UPDATE auth_otp_challenges SET identity_value=? WHERE id=?').bind('redacted',proof).run(),/auth_identity_history_immutable/);
  await s.f.db.prepare('UPDATE assisted_sms_authorizations SET phone_verification_challenge_id=?,consent_revision=consent_revision+1 WHERE collection_id=?').bind(randomUUID(),s.group).run();
 }
 if(invalid==='expired_before_verification')await s.f.db.prepare('UPDATE auth_otp_challenges SET created_at=created_at-600,expires_at=created_at-300 WHERE id=?').bind(proof).run();
 assert.equal((await command(s,'get_claimed',claimFields(c))).status,409);const status=ok(await getConsent(s));assert.equal(status.current_verified_phone_binding,false);assert.equal(status.opt_in,true);assert.equal(status.consent_effective,false);assert.equal(status.authorization_status,'blocked_phone_binding');
 await payment(s);const noNewProofJob=ok(await materialize(s));assert.equal(noNewProofJob.status,'partial_blocked');assert.equal(noNewProofJob.materialized_count,0);assert.equal(await count(s,'assisted_sms_jobs'),1);
 const fks=(await s.f.db.prepare('PRAGMA foreign_key_list(assisted_sms_authorizations)').all()).results;assert.equal(fks.some(row=>row.from==='phone_verification_challenge_id'),false);
 // Existing immutable verification history has its pre-existing retention
 // semantics. This feature neither disables that protection nor adds a new
 // constraint preventing unrelated expired challenge cleanup.
 const disposable=randomUUID(),seconds=Math.floor(Date.now()/1000)-1000;
 await s.f.db.prepare("INSERT INTO auth_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,code_hash,created_at,expires_at,status) VALUES(?,?,'phone',?,'member',0,?,?,?,'superseded')").bind(disposable,hash(disposable),s.member.phone,hash('Synthetic expired non-OTP'),seconds,seconds+60).run();
 await s.f.db.prepare('DELETE FROM auth_otp_challenges WHERE id=?').bind(disposable).run();assert.equal(await s.f.db.prepare('SELECT id FROM auth_otp_challenges WHERE id=?').bind(disposable).first(),null);
});
for(const point of ['get_claimed','confirm','record_send_start'])test('phone change winning before '+point+' blocks the old destination atomically',async t=>{
 const s=await ready(t),c=await claimed(s);let confirmation;
 if(point==='record_send_start')confirmation=await confirmed(s,c);
 if(point==='get_claimed'){
  s.f.setGate(async()=>{await s.f.db.prepare('UPDATE users SET phone=?,updated_at=? WHERE id=?').bind('+250788999999',new Date().toISOString(),s.member.id).run();});
  assert.equal((await command(s,point,claimFields(c),{'X-Test-Pause':'content_final'})).status,409);
 }else{
  const content=point==='confirm'?ok(await command(s,'get_claimed',claimFields(c))):confirmation.content;
  const body=point==='confirm'?{...claimFields(c),request_id:randomUUID(),confirmation_id:randomUUID(),body_sha256:content.body_sha256,destination_sha256:content.destination_sha256,destination_revision:1,user_confirmation:true}:{...claimFields(c),request_id:randomUUID(),confirmation_id:confirmation.confirmation_id};
  s.f.setGate(async()=>{await s.f.db.prepare('UPDATE users SET phone=?,updated_at=? WHERE id=?').bind('+250788999999',new Date().toISOString(),s.member.id).run();});
  assert.equal((await command(s,point,body,{'X-Test-Pause':'before_commit'})).status,409);assert.equal(await count(s,'assisted_sms_send_starts'),0);
 }
});
for(const point of ['get_claimed','confirm','record_send_start'])test(point+' winning first retains its exact observation while later phone change blocks further old-destination authority',async t=>{
 const s=await ready(t),c=await claimed(s);let row;
 if(point==='get_claimed')assert.equal(ok(await command(s,point,claimFields(c))).destination_e164,s.member.phone);
 if(point==='confirm')row=(await confirmed(s,c)).confirmation_id;
 if(point==='record_send_start'){const k=await confirmed(s,c);row=ok(await command(s,point,{...claimFields(c),confirmation_id:k.confirmation_id,request_id:randomUUID()}));assert.equal(row.may_send,true);}
 const retained=point==='confirm'?await s.f.db.prepare('SELECT * FROM assisted_sms_confirmations WHERE id=?').bind(row).first():point==='record_send_start'?await s.f.db.prepare('SELECT * FROM assisted_sms_send_starts WHERE id=?').bind(row.attempt_id).first():null;
 await s.f.db.prepare('UPDATE users SET phone=?,updated_at=? WHERE id=?').bind('+250788999999',new Date().toISOString(),s.member.id).run();
 assert.equal((await command(s,'get_claimed',claimFields(c))).status,409);
 if(retained)assert.deepEqual(await s.f.db.prepare('SELECT * FROM '+(point==='confirm'?'assisted_sms_confirmations':'assisted_sms_send_starts')+' WHERE id=?').bind(retained.id).first(),retained);
 assert.equal(await count(s,'assisted_sms_send_starts'),point==='record_send_start'?1:0);
});

test('actual existing11 owner migration and new-link flow preserve grants until explicit self-access; team policy is only a definition',async t=>{
 const f=await fixture(t,{}, {migrationsThrough:11}),account=await f.seedAccount(),operator=await f.stepUp(await f.login(account)),s={f,account,operator};
 const before=(await f.db.prepare('SELECT * FROM admin_grants ORDER BY user_id,permission').all()).results;
 const require=createRequire(import.meta.url),{unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
 const sql=await readFile(new URL('../migrations/0012_notification_operator.sql',import.meta.url),'utf8');
 await f.db.batch(unstable_splitSqlQuery(sql).map(query=>f.db.prepare(query)));
 assert.deepEqual((await f.db.prepare('SELECT * FROM admin_grants ORDER BY user_id,permission').all()).results,before);
 const status=ok(await getAccess(s));assert.equal(status.read_granted,false);assert.equal(status.manage_granted,false);assert.equal(status.can_operate,false);
 const team=ok(await f.call('/api/admin/team',{method:'GET',cookie:operator.cookie}));
 for(const permission of ['assisted_sms.read','assisted_sms.manage']){assert.equal(team.permissionsByRole.owner.includes(permission),true);assert.equal(team.permissionsByRole.admin.includes(permission),false);assert.equal(team.permissionsByRole.staff.includes(permission),false);}
 const current=ok(await f.call('/api/admin/auth/session',{method:'GET',cookie:operator.cookie}));assert.equal(current.user.permissions.includes('assisted_sms.read'),false);
 const enabled=ok(await access(s,accessChoice(true)));assert.equal(enabled.current_principal_id,account.userId);assert.equal(enabled.read_granted,true);assert.equal(enabled.manage_granted,true);
 const after=ok(await f.call('/api/admin/auth/session',{method:'GET',cookie:operator.cookie}));assert.equal(after.user.permissions.includes('assisted_sms.read'),true);assert.equal(after.user.permissions.includes('assisted_sms.manage'),true);
 assert.deepEqual((await f.db.prepare("SELECT * FROM admin_grants WHERE permission NOT IN('assisted_sms.read','assisted_sms.manage') ORDER BY user_id,permission").all()).results,before);
 assert.equal(f.messages.length,0);assert.equal(f.mail.length,0);
});
test('explicit owner access rejects arbitrary principals/names and stale CAS; lost acknowledgement/replay never grants twice',async t=>{
 const s=await setup(t,{phone:false,access:false}),body=accessChoice(true),before=(await s.f.db.prepare('SELECT * FROM admin_grants ORDER BY user_id,permission').all()).results;
 assert.equal(ok(await getAccess(s)).can_operate,false);assert.equal((await configure(s)).status,403);
 for(const extra of [{user_id:randomUUID()},{admin_id:randomUUID()},{permissions:['users.manage']},{permission:'anything.unknown'},{role:'staff'}])assert.equal((await access(s,{...body,...extra})).status,400);
 assert.equal((await access(s,{...body,owner_confirmation:false})).status,400);assert.equal((await access(s,{...body,expected_manage:true})).status,409);
 const first=ok(await access(s,body,{'X-Test-Pause':'lost_reply'})),repeat=ok(await access(s,body));assert.equal(first.decision_sha256,repeat.decision_sha256);assert.equal(repeat.replay,true);
 assert.equal((await notificationRows(s)).results.length,2);assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM request_receipts WHERE operation='assisted_sms.access.set'").first()).n,1);
 assert.deepEqual((await s.f.db.prepare("SELECT * FROM admin_grants WHERE permission NOT IN('assisted_sms.read','assisted_sms.manage') ORDER BY user_id,permission").all()).results,before);
 assert.equal((await access(s,accessChoice(false,false))).status,409);assert.equal(ok(await access(s,accessChoice(false,true))).can_operate,false);assert.equal((await notificationRows(s)).results.length,0);
});
test('explicit revoke remains revoked across real password/account-version lifecycle and blocks current claims',async t=>{
 const s=await ready(t),c=await claimed(s),before=(await s.f.db.prepare("SELECT permission FROM admin_grants WHERE user_id=? AND permission NOT IN('assisted_sms.read','assisted_sms.manage') ORDER BY permission").bind(s.account.userId).all()).results;
 ok(await access(s,accessChoice(false,true)));assert.equal((await command(s,'get_claimed',claimFields(c))).status,403);
 const password=await s.f.call('/api/admin/auth/change-password',{cookie:s.operator.cookie,data:{currentPassword:PASSWORD,newPassword:NEW_PASSWORD}});assert.equal(password.status,200,JSON.stringify(password));
 assert.equal((await notificationRows(s)).results.length,0);assert.deepEqual((await s.f.db.prepare("SELECT permission FROM admin_grants WHERE user_id=? AND permission NOT IN('assisted_sms.read','assisted_sms.manage') ORDER BY permission").bind(s.account.userId).all()).results,before);
 assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM request_receipts WHERE operation='assisted_sms.access.set'").first()).n,2);
});
test('historical owner enable receipt never reactivates a revoked grant in a later copy or exact request replay',async t=>{
 const s=await setup(t,{phone:false,access:false}),body=accessChoice(true),enabled=ok(await access(s,body));
 ok(await access(s,accessChoice(false,true)));assert.equal((await notificationRows(s)).results.length,0);
 await s.f.db.prepare("INSERT OR IGNORE INTO admin_grants(user_id,permission,granted_by,granted_at) SELECT ?,permission,?,strftime('%Y-%m-%dT%H:%M:%fZ','now') FROM admin_account_role_capabilities WHERE role='owner'").bind(s.account.userId,'admin-account:'+s.account.adminId).run();
 assert.equal((await notificationRows(s)).results.length,0);const historical=ok(await access(s,body));assert.equal(historical.decision_sha256,enabled.decision_sha256);assert.equal(historical.recorded_state_only,true);assert.equal(historical.replay,true);
 assert.equal(ok(await getAccess(s)).can_operate,false);assert.equal((await notificationRows(s)).results.length,0);assert.equal(await count(s,'admin_bridge_guards'),0);
});
test('suspended then reactivated owner keeps unrelated normal grants but gains no notification access automatically',async t=>{
 const s=await setup(t,{phone:false,access:false}),before=(await s.f.db.prepare("SELECT permission FROM admin_grants WHERE user_id=? ORDER BY permission").bind(s.account.userId).all()).results;
 await s.f.db.prepare("UPDATE admin_users SET status='revoked' WHERE id=?").bind(s.account.adminId).run();
 await s.f.db.prepare("UPDATE admin_users SET status='active' WHERE id=?").bind(s.account.adminId).run();
 assert.equal((await notificationRows(s)).results.length,0);assert.deepEqual((await s.f.db.prepare("SELECT permission FROM admin_grants WHERE user_id=? ORDER BY permission").bind(s.account.userId).all()).results,before);
});
for(const role of ['admin','staff'])test('self-access '+role+' cannot gain notifications, and notification permission relabeling is refused',async t=>{
 const s=await setup(t,{role,phone:false,access:false});assert.equal((await getAccess(s)).status,403);assert.equal((await access(s,accessChoice(true))).status,403);
 assert.equal((await notificationRows(s)).results.length,0);
 await assert.rejects(s.f.db.prepare("UPDATE admin_grants SET permission='assisted_sms.manage' WHERE user_id=? AND permission='overview.read'").bind(s.account.userId).run(),/sms_grant_requires_explicit_decision/);
 assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM admin_grants WHERE user_id=? AND permission='overview.read'").bind(s.account.userId).first()).n,1);
});
test('owner self-access requires genuine current fresh AAL2 and original request cannot be adopted by a new same-user session',async t=>{
 const low=await setup(t,{phone:false,assurance:1,access:false});assert.equal((await getAccess(low)).status,403);assert.equal((await access(low,accessChoice(true))).status,403);
 const s=await setup(t,{phone:false,access:false}),body=accessChoice(true),original=ok(await access(s,body)),factor=s.operator.factor;
 const login=await s.f.login(s.account),challenge=await s.f.call('/api/admin/auth/mfa/challenge',{cookie:login.cookie,data:{factor_id:factor.id}});assert.equal(challenge.status,200);
 const verified=await s.f.call('/api/admin/auth/mfa/verify',{cookie:login.cookie,data:{factor_id:factor.id,challenge_id:challenge.body.challenge_id,code:totp(factor.totp.secret,Math.floor(Date.now()/30000)+1)}});assert.equal(verified.status,200,JSON.stringify(verified));
 const old=s.operator;s.operator=verified;assert.equal((await access(s,body)).status,409);assert.equal(ok(await getAccess(s)).can_operate,true);s.operator=old;assert.equal(ok(await access(s,body)).decision_sha256,original.decision_sha256);
});
async function revokeOwner(s,cause){
 if(cause==='logout')assert.equal((await s.f.call('/api/admin/auth/logout',{cookie:s.operator.cookie})).status,200);
 if(cause==='principal')await s.f.db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(s.account.userId).run();
 if(cause==='link')await s.f.db.prepare('DELETE FROM admin_principal_links WHERE admin_user_id=?').bind(s.account.adminId).run();
 if(cause==='role')await s.f.db.prepare("UPDATE admin_users SET role='staff',email='former-owner@synthetic.example.test' WHERE id=?").bind(s.account.adminId).run();
 if(cause==='permission')await s.f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='admin_users.manage'").bind(s.account.userId).run();
}
for(const cause of ['logout','principal','link','role','permission'])test('owner self-access '+cause+' both serial orderings retain committed decisions and deny losing mutations',async t=>{
 const first=await setup(t,{phone:false,access:false}),body=accessChoice(true),receipt=ok(await access(first,body));await revokeOwner(first,cause);
 const retained=await first.f.db.prepare('SELECT response_json,session_id FROM request_receipts WHERE request_id=?').bind(body.request_id).first();assert.equal(JSON.parse(retained.response_json).decision_sha256,receipt.decision_sha256);assert.equal(retained.session_id,receipt.originating_session_id);assert.notEqual((await access(first,accessChoice(false,true))).status,200);
 const second=await setup(t,{phone:false,access:false}),attempt=accessChoice(true);second.f.setGate(async()=>revokeOwner(second,cause));
 assert.equal((await access(second,attempt,{'X-Test-Pause':'before_commit'})).status,403);assert.equal((await notificationRows(second)).results.length,0);
 for(const table of ['request_receipts','audit_log'])assert.equal((await second.f.db.prepare('SELECT count(*) AS n FROM '+table+' WHERE request_id=?').bind(attempt.request_id).first()).n,0);
});

const durableMaterialization=async s=>({
 receipts:(await s.f.db.prepare("SELECT * FROM request_receipts WHERE operation LIKE 'assisted_sms.materialize.%' OR operation='assisted_sms.enqueue' ORDER BY request_id").all()).results,
 jobs:(await s.f.db.prepare('SELECT * FROM assisted_sms_jobs ORDER BY entry_id').all()).results,
 audits:(await s.f.db.prepare("SELECT * FROM audit_log WHERE action LIKE 'assisted_sms.materialize.%' OR action='assisted_sms.enqueue' ORDER BY id").all()).results,
});
async function producer(t,n=3){const s=await setup(t);ok(await configure(s));ok(await consent(s));s.sources=[];for(let i=0;i<n;i++)s.sources.push(await payment(s));s.batch=randomUUID();return s;}
const resume=(s,extra={},limit=3)=>materialize(s,limit,extra,{request_id:s.batch});
function checkNoAuthority(result){assert.equal(result.may_send,false);assert.equal(result.transport_started,false);assert.equal(result.recorded_state_only,true);assert.equal(result.all_source_events_complete,false);assert.equal(JSON.stringify(result).includes('claim_token'),false);assert.equal(JSON.stringify(result).includes('message_body'),false);assert.equal(JSON.stringify(result).includes('destination_e164'),false);}

test('batch recovery requires an original UUID and exact finite body, and an absent receipt is not a known write failure',async t=>{
 const s=await producer(t,11),missing=ok(await materializationStatus(s,s.batch));assert.equal(missing.status,'not_recorded');assert.equal(missing.observed,false);assert.equal(missing.may_be_in_flight,true);assert.equal(missing.planned_count,null);checkNoAuthority(missing);
 const before=await durableMaterialization(s);
 for(const body of [{request_id:undefined},{request_id:'not-a-uuid'},{limit:0},{limit:11},{limit:1.5},{actor_user_id:s.account.userId}])assert.equal((await materialize(s,3,{},body)).status,400);
 assert.deepEqual(await durableMaterialization(s),before);
 const made=ok(await materialize(s,10,{}, {request_id:s.batch}));assert.equal(made.planned_count,10);assert.equal(made.materialized_count,10);assert.equal(made.has_more_observed,true);checkNoAuthority(made);
 const saved=await durableMaterialization(s);assert.equal((await resume(s)).status,409);assert.deepEqual(await durableMaterialization(s),saved);
 const done=ok(await materialize(s,10,{}, {request_id:s.batch}));assert.equal(done.materialized_count,10);assert.deepEqual(await durableMaterialization(s),saved);
});
for(const phase of ['before','after'])test('batch plan '+phase+' commit lost reply has an honest readback and original finite-set resume',async t=>{
 const s=await producer(t),result=await resume(s,{'X-Test-Pause':'materialize_plan_'+phase});assert.equal(result.status,503,JSON.stringify(result));
 const status=ok(await materializationStatus(s,s.batch));assert.equal(status.status,phase==='before'?'not_recorded':'planned');assert.equal(status.observed,phase==='after');assert.equal(await count(s,'assisted_sms_jobs'),0);checkNoAuthority(status);
 if(phase==='after'){
  assert.deepEqual(status.items.map(x=>x.entry_id).sort(),s.sources.map(x=>x.entry).sort());
  const later=await payment(s);assert.equal(ok(await resume(s)).items.some(x=>x.entry_id===later.entry),false);
 }else assert.equal(ok(await resume(s)).materialized_count,3);
 const completed=ok(await materializationStatus(s,s.batch));assert.equal(completed.status,'bounded_pass');assert.equal(completed.materialized_count,3);const retained=await durableMaterialization(s);
 assert.deepEqual(ok(await resume(s)),completed);assert.deepEqual(await durableMaterialization(s),retained);
});
for(const phase of ['before','after','intent'])for(const ordinal of [1,2,3])test(`batch per-source ${phase} ${ordinal} lost reply resolves actual committed rows and never rescans or duplicates`,async t=>{
 const s=await producer(t),pause=phase==='intent'?'materialize_intent_after_'+ordinal:'materialize_enqueue_'+phase+'_'+ordinal;
 const attempted=await resume(s,{'X-Test-Pause':pause});assert.equal(attempted.status,503,JSON.stringify(attempted));
 const status=ok(await materializationStatus(s,s.batch)),committed=phase==='after'?ordinal:ordinal-1;
 assert.equal(status.planned_count,3);assert.equal(status.materialized_count,committed);assert.equal(await count(s,'assisted_sms_jobs'),committed);assert.equal(status.items.filter(x=>x.status==='unknown').length,phase==='after'?0:1);checkNoAuthority(status);
 const originalIds=status.items.map(x=>x.entry_id),later=await payment(s),done=ok(await resume(s));assert.deepEqual(done.items.map(x=>x.entry_id),originalIds);assert.equal(done.items.some(x=>x.entry_id===later.entry),false);assert.equal(done.materialized_count,3);assert.equal(await count(s,'assisted_sms_jobs'),3);
 const before=await durableMaterialization(s);assert.equal(ok(await resume(s)).status,'bounded_pass');assert.deepEqual(await durableMaterialization(s),before);assert.equal(await count(s,'assisted_sms_send_starts'),0);
});
test('batch concurrent exact retries use the one winning retained plan and one job per event',async t=>{
 const s=await producer(t),results=await Promise.all([resume(s),resume(s)]);for(const result of results){const value=ok(result);assert.equal(value.materialized_count,3);checkNoAuthority(value);}
 assert.deepEqual(results[0].body.result.items,results[1].body.result.items);assert.equal(await count(s,'assisted_sms_jobs'),3);
 assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM request_receipts WHERE operation='assisted_sms.materialize.plan'").first()).n,1);
 const state=await durableMaterialization(s);await materializationStatus(s,s.batch);assert.deepEqual(await durableMaterialization(s),state);
});
test('batch source race retains its original blocked source and does not silently select replacement rows',async t=>{
 const s=await producer(t);let changed;
 s.f.setGate(async()=>{const source=await s.f.db.prepare('SELECT response_json FROM request_receipts WHERE request_id=?').bind(s.batch).first();changed=JSON.parse(source.response_json).sources[0];await s.f.db.prepare('UPDATE payments SET revision=revision+1 WHERE id=?').bind(changed.payment_id).run();});
 const result=ok(await resume(s,{'X-Test-Pause':'materialize_enqueue_race'}));assert.equal(result.status,'partial_blocked');assert.equal(result.materialized_count,0);assert.equal(result.blocked.source_entry_id,changed.entry_id);assert.equal(result.items[0].status,'blocked');assert.equal(result.items[1].status,'planned');
 const state=await durableMaterialization(s);await payment(s);const retry=ok(await resume(s));assert.deepEqual(retry.items,result.items);assert.deepEqual(await durableMaterialization(s),state);checkNoAuthority(retry);
});
test('batch lost reply after a recorded block is recovered as blocked without a second attempt',async t=>{
 const s=await producer(t),proof=(await s.f.db.prepare('SELECT phone_verification_challenge_id AS id FROM assisted_sms_authorizations').first()).id;
 await s.f.db.prepare("UPDATE auth_otp_challenges SET status='superseded',consumed_at=NULL,consumed_operation_id=NULL WHERE id=?").bind(proof).run();
 assert.equal((await resume(s,{'X-Test-Pause':'materialize_block_after'})).status,503);const found=ok(await materializationStatus(s,s.batch));assert.equal(found.status,'partial_blocked');assert.equal(found.materialized_count,0);
 const state=await durableMaterialization(s);assert.equal(ok(await resume(s)).status,'partial_blocked');assert.deepEqual(await durableMaterialization(s),state);
});
test('batch recovery keeps the exact original optional-limit body rather than treating a changed retry as equivalent',async t=>{
 const s=await producer(t,1),input={request_id:s.batch,limit:undefined};const result=ok(await materialize(s,5,{},input));assert.equal(result.materialized_count,1);
 assert.equal((await materialize(s,5,{}, {request_id:s.batch})).status,409);assert.equal(ok(await materialize(s,5,{},input)).materialized_count,1);
});
test('batch recovery accepts uppercase UUID identities while preserving their exact original body digest',async t=>{
 const s=await producer(t,1),body={request_id:s.batch.toUpperCase(),collection_id:s.group.toUpperCase()},first=ok(await materialize(s,1,{},body));
 assert.equal(first.request_id,s.batch);assert.equal(first.collection_id,s.group);assert.equal(first.materialized_count,1);const before=await durableMaterialization(s);
 assert.equal(ok(await materializationStatus(s,s.batch.toUpperCase())).materialized_count,1);assert.deepEqual(ok(await materialize(s,1,{},body)),first);
 assert.equal((await materialize(s,1,{}, {request_id:s.batch,collection_id:s.group})).status,409);assert.deepEqual(await durableMaterialization(s),before);
});
async function nextOwnerSession(s){const factor=s.operator.factor,login=await s.f.login(s.account),challenge=await s.f.call('/api/admin/auth/mfa/challenge',{cookie:login.cookie,data:{factor_id:factor.id}});assert.equal(challenge.status,200);
 const verified=await s.f.call('/api/admin/auth/mfa/verify',{cookie:login.cookie,data:{factor_id:factor.id,challenge_id:challenge.body.challenge_id,code:totp(factor.totp.secret,Math.floor(Date.now()/30000)+1)}});assert.equal(verified.status,200,JSON.stringify(verified));return verified;}
test('batch and self-access operation recovery reject a fresh same-user session without adopting retained plans or decisions',async t=>{
 const s=await producer(t),accessId=(await s.f.db.prepare("SELECT request_id FROM request_receipts WHERE operation='assisted_sms.access.set'").first()).request_id;
 assert.equal((await resume(s,{'X-Test-Pause':'materialize_plan_after'})).status,503);const state=await durableMaterialization(s),original=s.operator;s.operator=await nextOwnerSession(s);
 assert.equal((await materializationStatus(s,s.batch)).status,409);assert.equal((await resume(s)).status,409);assert.equal((await accessOperation(s,accessId)).status,409);assert.deepEqual(await durableMaterialization(s),state);
 s.operator=original;assert.equal(ok(await resume(s)).materialized_count,3);assert.equal(ok(await accessOperation(s,accessId)).observed,true);
});
for(const cause of ['principal','link','role','notification_permission','mfa'])test('resuming a retained batch after '+cause+' loss cannot borrow historical authority; winning write is atomically denied',async t=>{
 const revoke=async s=>{if(cause==='notification_permission')await s.f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='assisted_sms.manage'").bind(s.account.userId).run();else if(cause==='mfa')await s.f.db.prepare("UPDATE auth_mfa_factors SET status='revoked',revoked_at=unixepoch() WHERE id=?").bind(s.operator.factor.id).run();else await revokeOwner(s,cause);};
 const s=await producer(t);assert.equal((await resume(s,{'X-Test-Pause':'materialize_plan_after'})).status,503);const state=await durableMaterialization(s);await revoke(s);assert.notEqual((await materializationStatus(s,s.batch)).status,200);assert.notEqual((await resume(s)).status,200);assert.deepEqual(await durableMaterialization(s),state);
 const raced=await producer(t);raced.f.setGate(async()=>revoke(raced));assert.equal((await resume(raced,{'X-Test-Pause':'materialize_enqueue_race'})).status,403);assert.equal(await count(raced,'assisted_sms_jobs'),0);assert.equal(await count(raced,'assisted_sms_send_starts'),0);
});
test('materialization status read winning revocation after asynchronous assembly releases no partial metadata',async t=>{
 const s=await producer(t);assert.equal((await resume(s,{'X-Test-Pause':'materialize_plan_after'})).status,503);const before=await durableMaterialization(s);let pauses=0;
 s.f.setGate(async()=>{pauses++;await s.f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='assisted_sms.manage'").bind(s.account.userId).run();});
 const result=await materializationStatus(s,s.batch,{'X-Test-Pause':'materialize_status_final'});assert.equal(result.status,403);assert.equal(pauses,1);assert.equal(result.body.result,undefined);assert.deepEqual(await durableMaterialization(s),before);
});
for(const enabled of [true,false])test('self-access '+(enabled?'grant':'revoke')+' committed reply loss survives periodic session refresh through read-only original-decision recovery',async t=>{
 const s=await setup(t,{phone:false,access:!enabled}),body=accessChoice(enabled,!enabled);let refreshed;
 const refreshedBefore=await s.f.call('/api/admin/auth/session',{method:'GET',cookie:s.operator.cookie});assert.equal(refreshedBefore.status,200);assert.equal(refreshedBefore.body.user.permissions.includes('assisted_sms.manage'),!enabled);
 s.f.setGate(async()=>{refreshed=await s.f.call('/api/admin/auth/session',{method:'GET',cookie:s.operator.cookie});assert.equal(refreshed.status,200);assert.equal(refreshed.body.user.permissions.includes('assisted_sms.manage'),enabled);});
 assert.equal((await access(s,body,{'X-Test-Pause':'access_lost_reply'})).status,503);assert.ok(refreshed);const before=await durableMaterialization(s),receiptCount=await count(s,'request_receipts'),auditCount=await count(s,'audit_log');
 const recovered=ok(await accessOperation(s,body.request_id));assert.equal(recovered.observed,true);assert.equal(recovered.status,'recorded');assert.equal(recovered.recorded_decision.enabled,enabled);assert.equal(recovered.recorded_decision.recorded_state_only,true);assert.equal(recovered.current_access.manage_granted,enabled);assert.equal(recovered.may_send,false);assert.equal(recovered.replay_authorized,false);
 const refreshedAfter=await s.f.call('/api/admin/auth/session',{method:'GET',cookie:s.operator.cookie});assert.equal(refreshedAfter.body.user.permissions.includes('assisted_sms.manage'),enabled);
 assert.equal(ok(await accessOperation(s,body.request_id)).recorded_decision.decision_sha256,recovered.recorded_decision.decision_sha256);assert.equal(await count(s,'request_receipts'),receiptCount);assert.equal(await count(s,'audit_log'),auditCount);assert.deepEqual(await durableMaterialization(s),before);
});
test('self-access recovery separates a historical enable decision from current revoked grants and keeps an in-flight absence unknown',async t=>{
 const s=await setup(t,{phone:false,access:false}),body=accessChoice(true);let during;
 s.f.setGate(async()=>{during=ok(await accessOperation(s,body.request_id));assert.equal(during.status,'not_recorded');assert.equal(during.may_be_in_flight,true);assert.equal(during.observed,false);assert.equal(during.current_access.can_operate,false);});
 const enabled=ok(await access(s,body,{'X-Test-Pause':'before_commit'}));assert.ok(during);ok(await access(s,accessChoice(false,true)));
 const receipt=ok(await accessOperation(s,body.request_id));assert.equal(receipt.recorded_decision.decision_sha256,enabled.decision_sha256);assert.equal(receipt.recorded_decision.enabled,true);assert.equal(receipt.current_access.can_operate,false);assert.equal(receipt.may_send,false);assert.equal((await command(s,'get_operation',{request_id:body.request_id})).status,403);
});
for(const cause of ['logout','principal','link','role','permission','mfa'])test('self-access recovery '+cause+' before entry and winning final read fences historical disclosure',async t=>{
 const revoke=async s=>cause==='mfa'?s.f.db.prepare("UPDATE auth_mfa_factors SET status='revoked',revoked_at=unixepoch() WHERE id=?").bind(s.operator.factor.id).run():revokeOwner(s,cause);
 const first=await setup(t,{phone:false,access:false}),a=accessChoice(true);ok(await access(first,a));const retained=await first.f.db.prepare('SELECT * FROM request_receipts WHERE request_id=?').bind(a.request_id).first();await revoke(first);assert.notEqual((await accessOperation(first,a.request_id)).status,200);assert.deepEqual(await first.f.db.prepare('SELECT * FROM request_receipts WHERE request_id=?').bind(a.request_id).first(),retained);
 const second=await setup(t,{phone:false,access:false}),b=accessChoice(true);ok(await access(second,b));let pauses=0;second.f.setGate(async()=>{pauses++;await revoke(second);});const result=await accessOperation(second,b.request_id,{'X-Test-Pause':'access_status_final'});assert.equal(result.status,403);assert.equal(pauses,1);assert.equal(result.body.result,undefined);
});
test('recovery routes refuse wrong operations, mutation methods, query fields and foreign origins without side effects',async t=>{
 const s=await producer(t,0);ok(await configure(s,false,1));const policyId=(await s.f.db.prepare("SELECT request_id FROM request_receipts WHERE operation='assisted_sms.policy.configure' LIMIT 1").first()).request_id;
 assert.equal((await accessOperation(s,policyId)).status,409);assert.equal((await materializationStatus(s,policyId)).status,409);const before=await durableMaterialization(s);
 for(const path of ['/api/admin/notification-operator/materialize/'+s.batch,'/api/admin/notification-operator/access/operations/'+s.batch]){
  assert.equal((await s.f.call(path,{cookie:s.operator.cookie,data:{},headers:{'X-Collect-Admin':'1'}})).status,405);
  assert.equal((await s.f.call(path+'?request_id='+s.batch,{method:'GET',cookie:s.operator.cookie})).status,400);
  assert.equal((await s.f.call(path,{method:'GET',cookie:s.operator.cookie,origin:'https://foreign.example'})).status,403);
 }
 assert.deepEqual(await durableMaterialization(s),before);assert.equal(await count(s,'assisted_sms_send_starts'),0);
});

async function historicalMomoLink(s,p){
 const at=new Date().toISOString(),account=randomUUID(),raw=randomUUID(),attempt=randomUUID(),transaction=randomUUID();
 const session=await s.f.db.prepare("SELECT id FROM auth_sessions WHERE user_id=? AND surface='admin' ORDER BY created_at DESC LIMIT 1").bind(s.account.userId).first();
 // Declared synthetic financial/source relationship; no provider accuracy or
 // historical approval is inferred from this local fixture graph.
 await s.f.db.batch([
  s.f.db.prepare("INSERT INTO momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,currency,timezone,created_at) VALUES(?,'mtn_momo','123456','Synthetic historical receiver',?,'RWF','Africa/Kigali',?)").bind(account,hash(account),at),
  s.f.db.prepare('INSERT INTO sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at) VALUES(?,?,?,?,?,?,?,?,1,?)').bind(raw,s.account.userId,session.id,randomUUID(),hash('SYNTHETIC HISTORY'),hash(account),'synthetic-history/'+raw,hash('SYNTHETIC OBJECT'),at),
  s.f.db.prepare("INSERT INTO momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at) VALUES(?,?,1,'synthetic-model','synthetic-schema','synthetic-prompt','synthetic-parser','synthetic-profile','{}',?,'{}','[]','accepted',?)").bind(attempt,raw,hash('SYNTHETIC HISTORY'),at),
  s.f.db.prepare("INSERT INTO momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,currency_scale,transaction_timezone,transaction_time_source,parse_attempt_id,mode,created_at,updated_at) VALUES(?,?,'mtn_momo',?,'incoming_receipt',1250,'RWF',0,'Africa/Kigali','synthetic',?,'historical',?,?)").bind(transaction,account,transaction,attempt,at,at),
  s.f.db.prepare('INSERT INTO momo_financial_links(transaction_id,payment_id,beneficiary_member_id,linked_by,reason,historical_existing,created_at) VALUES(?,?,?,?,?,1,?)').bind(transaction,p.id,s.member.id,s.account.userId,'Synthetic historical linkage test only',at)
 ]);
}
const enqueueRecorded=(s,p,headers={})=>s.f.call('/__synthetic_enqueue',{cookie:s.operator.cookie,data:{payment_id:p.id,request_id:randomUUID()},headers:{'X-Collect-Admin':'1',...headers}});

test('receipt SMS uses immutable after-contribution snapshots and preserves the group label after later activity',async t=>{
 const s=await setup(t);ok(await configure(s));ok(await consent(s));const p=await payment(s);
 await s.f.db.prepare('INSERT INTO contribution_posting_snapshots(ledger_entry_id,payment_id,member_balance_after_minor,group_balance_after_minor,posted_at) VALUES(?,?,1250,1250,?)').bind(p.entry,p.id,new Date().toISOString()).run();
 await payment(s);await payment(s);assert.equal((await s.f.db.prepare('SELECT sum(amount_minor) AS total FROM ledger_entries WHERE collection_id=?').bind(s.group).first()).total,3750);
 s.job=ok(await enqueueRecorded(s,p));const content=ok(await command(s,'get_claimed',claimFields(await claimed(s))));
 assert.match(content.message_body,/RWF 1250 credited to Synthetic receipt integration/);assert.match(content.message_body,/After this contribution: your balance RWF 1250; group balance RWF 1250/);assert.ok(!content.message_body.includes('3750'));
 assert.equal(await count(s,'assisted_sms_send_starts'),0);assert.equal(content.delivery_confirmed,false);
});

for(const migrationsThrough of [13,null])test('receipt without posting snapshot omits historical figures on '+(migrationsThrough??'current')+' schema',async t=>{
 const s=await setup(t,{migrationsThrough});ok(await configure(s));ok(await consent(s));const p=await payment(s);await payment(s);
 s.job=ok(await enqueueRecorded(s,p));const content=ok(await command(s,'get_claimed',claimFields(await claimed(s))));
 assert.match(content.message_body,/RWF 1250 credited to Synthetic receipt integration/);assert.ok(!content.message_body.includes('After this contribution'));assert.ok(!content.message_body.includes('balance RWF'));assert.equal(await count(s,'assisted_sms_send_starts'),0);
});

test('invalid zero posting snapshot blocks SMS rather than reconstructing a current position',async t=>{
 const s=await setup(t);ok(await configure(s));ok(await consent(s));const p=await payment(s);
 await s.f.db.prepare('INSERT INTO contribution_posting_snapshots(ledger_entry_id,payment_id,member_balance_after_minor,group_balance_after_minor,posted_at) VALUES(?,?,0,1250,?)').bind(p.entry,p.id,new Date().toISOString()).run();
 const result=await enqueueRecorded(s,p);assert.equal(result.status,503);assert.equal(result.body.error.code,'sms_snapshot_unavailable');assert.equal(await count(s,'assisted_sms_jobs'),0);
});

test('historical MoMo links suppress direct enqueue and new materialization',async t=>{
 const s=await setup(t);ok(await configure(s));ok(await consent(s));const p=await payment(s);await historicalMomoLink(s,p);
 assert.equal((await enqueueRecorded(s,p)).status,409);const made=ok(await materialize(s));assert.equal(made.planned_count,0);assert.equal(made.materialized_count,0);assert.equal(await count(s,'assisted_sms_jobs'),0);assert.equal(await count(s,'assisted_sms_send_starts'),0);
});

test('historical linkage arriving after producer read rolls back the new job and receipt',async t=>{
 const s=await setup(t);ok(await configure(s));ok(await consent(s));const p=await payment(s);let races=0;
 s.f.setGate(async()=>{races++;await historicalMomoLink(s,p);});const result=await enqueueRecorded(s,p,{'X-Test-Pause':'before_commit'});
 assert.equal(races,1);assert.equal(result.status,409);assert.equal(await count(s,'assisted_sms_jobs'),0);assert.equal((await s.f.db.prepare("SELECT count(*) AS n FROM request_receipts WHERE operation='assisted_sms.enqueue'").first()).n,0);assert.equal(await count(s,'assisted_sms_send_starts'),0);
});
