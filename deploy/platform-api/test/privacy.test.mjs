import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {fixture,authorization,admin,setupMfa,totp,claims} from './support/auth_fixture.mjs';
const modules=['privacy.js','mutations.js','groups.js','payments.js','evidence.js','notifications.js','admin.js'];
const falseFlags=['policy_acceptance_granted','destructive_execution_available','erasure_completed','account_access_restricted','auth_removed','processor_operation_started'];
const rtc=/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/;
async function use(t) {const f=await fixture({}, {entrypoint:'index.js',extraModules:modules});t.after(()=>f.close());return f;}
const rpc=(f,session,operation,body={})=>f.call(`/v1/rpc/${operation}`,body,authorization(session));
async function operator(f,email='owner@example.com',{granted=true,mfa=true}={}) {
  const a=await admin(f,{email}),session=await f.login(a.identity);
  if(granted)await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(a.id,'privacy.review',new Date().toISOString()).run();
  if(!mfa)return session;
  const {factor,challenge}=await setupMfa(f,session);
  const result=await f.call('/v1/auth/mfa/verify',{factor_id:factor.id,challenge_id:challenge.id,code:totp(factor.totp.secret)},authorization(session));
  assert.equal(result.status,200,JSON.stringify(result.body));return result.body;
}
const submit=(f,session,id=randomUUID(),reason=null)=>rpc(f,session,'request_account_deletion_v1',{p_request_id:id,p_reason:reason});
function intakeContract(row,submission=false) {
  const keys=['contract_version','request_id','scope','state','reason_code','reason_supplied','accepted_at','policy_review_pending',
    'subject_scope_review_pending','erasure_completed','account_access_restricted','auth_removed','retention_approval_granted','processor_operation_started'];
  if(submission)keys.push('submission_id','replay','equivalent_active_request');
  assert.deepEqual(Object.keys(row).sort(),keys.sort(),'strict installed Dart PrivacyIntakeReceipt field set');
  assert.equal(row.contract_version,1);assert.equal(row.scope,'own_account_eligible_data');assert.equal(row.state,'pending_review');
  assert.equal(row.reason_code,'account_deletion_requested');assert.match(row.accepted_at,rtc);
  assert.equal(row.policy_review_pending,true);assert.equal(row.subject_scope_review_pending,true);
  for(const key of ['erasure_completed','account_access_restricted','auth_removed','retention_approval_granted','processor_operation_started'])assert.equal(row[key],false);
}
async function claim(f,operator,requestId,revision=0,operationId=randomUUID(),lease=60) {
  return rpc(f,operator,'admin_claim_account_deletion_review_v1',{p_request_id:requestId,p_claim_request_id:operationId,p_expected_revision:revision,p_lease_seconds:lease});
}
async function outcome(f,operator,claimResult,operationId=randomUUID()) {
  return rpc(f,operator,'admin_record_account_deletion_review_v1',{p_outcome_request_id:operationId,p_claim_id:claimResult.claim_id,p_fence:claimResult.fence,p_outcome_code:'policy_authority_unavailable'});
}

test('own intake matches installed strict receipt and neither erases, restricts nor removes Auth',async t=>{
  const f=await use(t),session=await f.login(),id=randomUUID(),result=await submit(f,session,id);
  assert.equal(result.status,200,JSON.stringify(result.body));intakeContract(result.body,true);
  assert.equal(result.body.request_id,id);assert.equal(result.body.submission_id,id);assert.equal(result.body.replay,false);assert.equal(result.body.equivalent_active_request,false);
  assert.equal((await f.db.prepare('SELECT access_status FROM users WHERE id=?').bind(session.user.id).first()).access_status,'active');
  assert.equal((await f.db.prepare('SELECT revoked_at FROM auth_sessions WHERE id=?').bind(claims(session.access_token).session_id).first()).revoked_at,null);
  assert.equal((await f.db.prepare('SELECT status FROM deletion_requests').first()).status,'received');
  await assert.rejects(f.db.prepare("UPDATE deletion_requests SET status='completed'").run(),/immutable_privacy_intake/);
  await assert.rejects(f.db.prepare('DELETE FROM deletion_requests').run(),/retain_privacy_intake/);
});

test('equivalent submissions, retries and legacy request reuse one retained intake; changed reason conflicts',async t=>{
  const f=await use(t),session=await f.login(),id=randomUUID(),one=await submit(f,session,id,' Please delete my data ');assert.equal(one.status,200);
  const retry=await submit(f,session,id,'Please delete my data');assert.equal(retry.status,200);assert.equal(retry.body.replay,true);
  const alias=randomUUID(),duplicate=await submit(f,session,alias,'Please delete my data');assert.equal(duplicate.status,200);assert.equal(duplicate.body.request_id,id);assert.equal(duplicate.body.equivalent_active_request,true);
  assert.equal((await submit(f,session,id,'Another reason')).status,409);
  const legacy=await rpc(f,session,'request_account_deletion',{request_reason:'Please delete my data'});assert.equal(legacy.status,200);assert.equal(legacy.body,id);
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM deletion_requests').first()).n,1);
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM privacy_submissions').first()).n,2);
});

test('concurrent distinct aliases converge on one subject intake and concurrent exact retry is idempotent',async t=>{
  const f=await use(t),session=await f.login(),one=randomUUID(),two=randomUUID();
  const results=await Promise.all([submit(f,session,one),submit(f,session,two)]);assert.ok(results.every(r=>r.status===200),JSON.stringify(results));
  assert.equal(results[0].body.request_id,results[1].body.request_id);
  const same=randomUUID(),duplicates=await Promise.all([submit(f,session,same),submit(f,session,same)]);assert.ok(duplicates.every(r=>r.status===200));
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM deletion_requests').first()).n,1);
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM privacy_submissions').first()).n,3);
});

test('own status permits only its subject and submission aliases; reason and contact data never enter review observations',async t=>{
  const f=await use(t),session=await f.login(),one=await submit(f,session,randomUUID(),'Sensitive private explanation'),id=one.body.request_id;
  const alias=randomUUID();await submit(f,session,alias,'Sensitive private explanation');
  const status=await rpc(f,session,'get_account_deletion_request_status_v1',{p_request_id:alias});assert.equal(status.status,200);intakeContract(status.body);
  const review=await rpc(f,session,'get_account_deletion_review_status_v1',{p_request_id:id});assert.equal(review.status,200);assert.equal(review.body.review_state,'not_started');assert.equal(review.body.revision,0);assert.match(review.body.checked_at,rtc);
  assert.equal(review.body.completion,'blocked');assert.equal(review.body.subject_scope_review_pending,true);assert.equal(review.body.legal_hold_review_pending,true);for(const key of falseFlags)assert.equal(review.body[key],false);
  assert.ok(!JSON.stringify(review.body).includes('Sensitive private explanation'));
  const other=await f.login({phone:'+250788123457'});assert.equal((await rpc(f,other,'get_account_deletion_request_status_v1',{p_request_id:id})).status,404);
  assert.equal((await submit(f,other,alias,'Sensitive private explanation')).status,409);
  assert.equal((await rpc(f,other,'get_current_account_deletion_request_status_v1')).body,null);
});

test('invalid reason lengths, control characters and foreign subject parameters are refused',async t=>{
  const f=await use(t),session=await f.login();
  for(const reason of ['x'.repeat(501),'unsafe\u0000reason',true])assert.equal((await submit(f,session,randomUUID(),reason)).status,400);
  assert.equal((await rpc(f,session,'request_account_deletion_v1',{p_request_id:randomUUID(),p_subject_id:randomUUID()})).status,400);
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM deletion_requests').first()).n,0);
});

test('submission aliases are bounded at 32 without losing the retained original receipt',async t=>{
  const f=await use(t),session=await f.login(),first=await submit(f,session);assert.equal(first.status,200);
  for(let n=1;n<32;n++)assert.equal((await submit(f,session)).status,200);
  const refused=await submit(f,session);assert.equal(refused.status,429,JSON.stringify(refused.body));
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM privacy_submissions').first()).n,32);
  const original=await submit(f,session,first.body.submission_id);assert.equal(original.status,200);assert.equal(original.body.replay,true);
});

test('privacy review requires owner-granted capability and genuine current MFA, including repeat reads',async t=>{
  const f=await use(t),member=await f.login(),request=await submit(f,member),id=request.body.request_id;
  assert.equal((await rpc(f,member,'admin_get_account_deletion_review_v1',{p_request_id:id})).status,403);
  const noMfa=await operator(f,undefined,{mfa:false});assert.equal((await claim(f,noMfa,id)).status,403);
  await f.db.prepare('UPDATE auth_otp_throttles SET last_requested_at=last_requested_at-61').run();
  const owner=await operator(f,'second@example.com'),claimed=await claim(f,owner,id);assert.equal(claimed.status,200,JSON.stringify(claimed.body));
  await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='privacy.review'").bind(owner.user.id).run();
  assert.equal((await rpc(f,owner,'admin_get_account_deletion_review_v1',{p_request_id:id})).status,403);
  assert.equal((await claim(f,owner,id,0,claimed.body.claim_request_id)).status,403);
});

test('review claim, blocked outcome, strict own readback and uncertain-operation resolution preserve false completion flags',async t=>{
  const f=await use(t),member=await f.login(),request=await submit(f,member),owner=await operator(f),id=request.body.request_id;
  const detail=await rpc(f,owner,'admin_get_account_deletion_review_v1',{p_request_id:id});assert.equal(detail.status,200);assert.equal(detail.body.item.review_state,'not_started');
  const claimed=await claim(f,owner,id);assert.equal(claimed.status,200,JSON.stringify(claimed.body));assert.equal(claimed.body.revision,1);assert.equal(claimed.body.fence,1);
  assert.equal(Date.parse(claimed.body.expires_at)-Date.parse(claimed.body.claimed_at),60000);for(const k of ['policy_acceptance_granted','destructive_execution_available','erasure_completed'])assert.equal(claimed.body[k],false);
  const resolved=await rpc(f,owner,'admin_get_account_deletion_review_operation_v1',{p_operation_kind:'claim',p_operation_id:claimed.body.claim_request_id});assert.equal(resolved.status,200);assert.equal(resolved.body.observed,true);assert.equal(resolved.body.claim_authority_current,true);
  const blocked=await outcome(f,owner,claimed.body);assert.equal(blocked.status,200,JSON.stringify(blocked.body));assert.equal(blocked.body.revision,2);assert.equal(blocked.body.completion,'blocked');for(const flag of falseFlags)assert.equal(blocked.body[flag],false);
  const own=await rpc(f,member,'get_account_deletion_review_status_v1',{p_request_id:id});assert.equal(own.body.review_state,'blocked');assert.equal(own.body.revision,2);assert.equal(own.body.outcome_code,'policy_authority_unavailable');
  const after=await rpc(f,owner,'admin_get_account_deletion_review_v1',{p_request_id:id});assert.equal(after.body.item.review_state,'blocked');assert.equal(after.body.own_claim_authority_current,false);assert.deepEqual(after.body.own_outcome_receipt,blocked.body);
  const repeated=await outcome(f,owner,claimed.body,blocked.body.outcome_request_id);assert.equal(repeated.status,200);assert.deepEqual(repeated.body,blocked.body);
  assert.equal((await claim(f,owner,id,2)).status,409);
  await assert.rejects(f.db.prepare("UPDATE privacy_review_outcomes SET outcome_code='erasure_completed'").run(),/immutable_privacy_review_outcome/);
});

test('concurrent review claims create one fenced lease; another session cannot adopt or record it',async t=>{
  const f=await use(t),member=await f.login(),request=await submit(f,member),owner=await operator(f),id=request.body.request_id;
  const results=await Promise.all([claim(f,owner,id),claim(f,owner,id)]);assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);
  const claimed=results.find(r=>r.status===200).body,other=await operator(f,'another@example.com');
  assert.equal((await outcome(f,other,claimed)).status,404);
  const detail=await rpc(f,other,'admin_get_account_deletion_review_v1',{p_request_id:id});assert.equal(detail.body.own_claim_receipt,null);assert.equal(detail.body.own_claim_authority_current,false);
  const resolve=await rpc(f,other,'admin_get_account_deletion_review_operation_v1',{p_operation_kind:'claim',p_operation_id:claimed.claim_request_id});assert.equal(resolve.body.observed,false);assert.equal(resolve.body.receipt,null);
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM privacy_review_claims').first()).n,1);
  assert.equal((await rpc(f,owner,'admin_record_account_deletion_review_v1',{p_outcome_request_id:randomUUID(),p_claim_id:claimed.claim_id,p_fence:claimed.fence,p_outcome_code:'completed'})).status,409);
});

test('claim and outcome replay are bound to exact revision, lease, actor and original session',async t=>{
  const f=await use(t),member=await f.login(),request=await submit(f,member),owner=await operator(f),id=request.body.request_id;
  const operation=randomUUID(),one=await claim(f,owner,id,0,operation),repeat=await claim(f,owner,id,0,operation);assert.equal(repeat.status,200);assert.deepEqual(repeat.body,one.body);
  assert.equal((await claim(f,owner,id,1,operation)).status,409);
  assert.equal((await claim(f,owner,id,0,operation,120)).status,409);
  await f.db.prepare('UPDATE auth_otp_throttles SET last_requested_at=last_requested_at-61').run();const newSession=await f.login({email:'owner@example.com',surface:'admin'}),mfa=await setupMfa(f,owner);
  // Newly pending factor's challenge is bound to its enrollment session; use that
  // factor once on the old owner session, then the resulting proof remains old SID.
  const verified=await f.call('/v1/auth/mfa/verify',{factor_id:mfa.factor.id,challenge_id:mfa.challenge.id,code:totp(mfa.factor.totp.secret)},authorization(owner));assert.equal(verified.status,200);
  assert.equal(claims(newSession.access_token).session_id!==claims(owner.access_token).session_id,true);
  assert.equal((await claim(f,newSession,id,0,operation)).status,403,'new OTP session alone does not authorize an old review command');
});

test('review list uses canonical IDs and stable keyset pagination, disclosing no subject identities or reasons',async t=>{
  const f=await use(t);for(let i=0;i<3;i++){const member=await f.login({phone:`+25078812345${i}`});assert.equal((await submit(f,member,randomUUID(),'Private reason')).status,200);}
  const owner=await operator(f),first=await rpc(f,owner,'admin_list_account_deletion_reviews_v1',{p_limit:2,p_before_accepted_at:null,p_before_request_id:null});
  assert.equal(first.status,200);assert.equal(first.body.items.length,2);assert.ok(first.body.next_cursor);
  const second=await rpc(f,owner,'admin_list_account_deletion_reviews_v1',{p_limit:2,p_before_accepted_at:first.body.next_cursor.accepted_at,p_before_request_id:first.body.next_cursor.request_id});
  assert.equal(second.status,200);assert.equal(second.body.items.length,1);assert.equal(second.body.next_cursor,null);
  assert.equal(new Set([...first.body.items,...second.body.items].map(v=>v.request_id)).size,3);
  assert.ok(!JSON.stringify(first.body).includes('Private reason'));assert.ok(!JSON.stringify(first.body).includes('+250'));
});
