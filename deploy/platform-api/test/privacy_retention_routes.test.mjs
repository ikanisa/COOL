import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {fixture,admin,setupMfa,totp,authorization} from './support/auth_fixture.mjs';
import {fixture as cookieFixture,ORIGIN} from './admin_support/fixture.mjs';
import {retentionRpcNames} from '../src/privacy_retention_rpc.js';

const source='f'.repeat(64),inspect='admin_inspect_account_retention_scope_v1';
const input=request=>({p_request_id:request,p_expected_review_revision:0,p_expected_source_id:source});
async function bearerSetup(t){
 const f=await fixture({BUILD_SOURCE_ID:source},{entrypoint:'index.js'});t.after(()=>f.close());
 const member=await f.login(),intake=await f.call('/v1/rpc/request_account_deletion_v1',{p_request_id:randomUUID()},authorization(member));
 assert.equal(intake.status,200,JSON.stringify(intake.body));
 const a=await admin(f);await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(a.id,'privacy.review',new Date().toISOString()).run();
 const initial=await f.login(a.identity),{factor,challenge}=await setupMfa(f,initial);
 const checked=await f.call('/v1/auth/mfa/verify',{factor_id:factor.id,challenge_id:challenge.id,code:totp(factor.totp.secret)},authorization(initial));
 assert.equal(checked.status,200,JSON.stringify(checked.body));return {f,member,initial,operator:checked.body,request:intake.body.request_id};
}

test('registered retention RPCs use current admin MFA authority and never trust caller policy overrides',async t=>{
 const c=await bearerSetup(t),path='/v1/rpc/'+inspect;
 const context=await c.f.call('/v1/rpc/admin_get_account_retention_context_v1',{},authorization(c.operator));
 assert.equal(context.status,200,JSON.stringify(context.body));assert.equal(context.body.source_id,source);
 assert.equal(context.body.approval_granted,false);assert.equal(context.body.erasure_completed,false);
 assert.ok(Date.parse(context.body.valid_until)>Date.parse(context.body.checked_at));
 assert.ok(Date.parse(context.body.valid_until)-Date.parse(context.body.checked_at)<=300000);
 const good=await c.f.call(path,input(c.request),authorization(c.operator));assert.equal(good.status,200,JSON.stringify(good.body));
 assert.equal(good.body.request_id,c.request);assert.equal(good.body.subject_id,c.member.user.id);
 assert.match(good.body.snapshot_sha256,/^[a-f0-9]{64}$/);assert.equal(good.body.approval_granted,false);assert.equal(good.body.erasure_completed,false);
 assert.ok(!JSON.stringify(good.body).includes('+250788123456'));
 const continuation=await c.f.call('/v1/rpc/admin_inspect_account_quarantine_continuation_v1',input(c.request),authorization(c.operator));
 assert.equal(continuation.status,200,JSON.stringify(continuation.body));
 assert.equal(continuation.body.scope,'continued_account_quarantine_preview');
 assert.equal(continuation.body.prior_quarantine,null);assert.equal(continuation.body.approval_granted,false);
 assert.equal(continuation.body.reactivation_granted,false);assert.equal(continuation.body.active_claim_count,0);
 assert.equal(continuation.body.unresolved_effect_count,0);assert.ok(!JSON.stringify(continuation.body).includes('+250788123456'));
 const spoof=await c.f.call(path,{...input(c.request),p_subject_id:c.operator.user.id},authorization(c.operator));assert.equal(spoof.status,400);
 for(const operation of retentionRpcNames){
  for(const session of [c.member,c.initial]){
   const r=await c.f.call('/v1/rpc/'+operation,{},authorization(session));assert.equal(r.status,403,operation+': '+JSON.stringify(r.body));
  }
 }
 const denied=await c.f.call('/v1/rpc/admin_plan_account_retention_v1',{...input(c.request),p_operation_id:randomUUID(),p_policy_sha256:'a'.repeat(64)},authorization(c.operator));
 assert.equal(denied.status,409);assert.equal(denied.body.code,'privacy_retention_policy_unavailable');
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_plans').first()).n,0);
});

test('the shipping cookie workspace can review intake and inspect retention without receiving bearer secrets',async t=>{
 const f=await cookieFixture(t,{BUILD_SOURCE_ID:source}),account=await f.seedAccount(),initial=await f.login(account),owner=await f.stepUp(initial);
 const member=await f.seedMember(),session=await f.nativeLogin(member.phone);
 const intake=await f.call('/v1/rpc/request_account_deletion_v1',{origin:'https://collect.example',headers:authorization(session),data:{p_request_id:randomUUID()}});
 assert.equal(intake.status,200,JSON.stringify(intake));
 const call=(operation,data={},cookie=owner.cookie)=>f.call('/api/admin/privacy/'+operation,{cookie,data});
 const list=await call('admin_list_account_deletion_reviews_v1',{p_limit:25});assert.equal(list.status,200,JSON.stringify(list));assert.equal(list.body.items.length,1);
 const context=await call('admin_get_account_retention_context_v1');assert.equal(context.status,200,JSON.stringify(context));
 assert.equal(context.body.scope,'account_retention_inspection_context');assert.equal(context.body.source_id,source);
 const scope=await call(inspect,input(intake.body.request_id));assert.equal(scope.status,200,JSON.stringify(scope));assert.equal(scope.body.subject_id,member.id);
 assert.equal(scope.body.approval_granted,false);assert.equal(scope.body.erasure_completed,false);
 const continuation=await call('admin_inspect_account_quarantine_continuation_v1',input(intake.body.request_id));
 assert.equal(continuation.status,200,JSON.stringify(continuation));assert.equal(continuation.body.prior_quarantine,null);
 assert.equal(continuation.body.reactivation_granted,false);assert.equal(continuation.body.approval_granted,false);
 assert.equal((await call('admin_inspect_account_quarantine_continuation_v1',{...input(intake.body.request_id),p_allow_reactivation:true})).status,400);
 assert.ok(!JSON.stringify(scope.body).includes('access_token'));assert.ok(!JSON.stringify(scope.body).includes('token_hash'));
 // Step-up replaces its original cookie. A separate current AAL1 sign-in
 // distinguishes revoked-cookie denial from the live MFA requirement.
 assert.equal((await call(inspect,input(intake.body.request_id),initial.cookie)).status,401);
 const unverified=await f.login(account);
 assert.equal((await call(inspect,input(intake.body.request_id),unverified.cookie)).status,403);
 const unsafe=await call('request_account_deletion_v1',{p_request_id:randomUUID()});assert.equal(unsafe.status,404);
 const method=await f.call('/api/admin/privacy/'+inspect,{method:'GET',cookie:owner.cookie});assert.equal(method.status,405);
 const cross=await f.call('/api/admin/privacy/'+inspect,{cookie:owner.cookie,origin:'https://unexpected.example',data:input(intake.body.request_id)});assert.equal(cross.status,403);
 const staffAccount=await f.seedAccount({role:'staff',email:'staff-privacy@example.test'}),staff=await f.stepUp(await f.login(staffAccount));
 assert.equal((await call(inspect,input(intake.body.request_id),staff.cookie)).status,403);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM privacy_retention_plans').first()).n,0);
});
