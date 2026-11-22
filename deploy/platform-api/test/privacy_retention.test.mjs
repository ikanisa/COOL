import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {retentionFixture,authorization,sourceId,sha} from './support/retention_fixture.mjs';
const ok=r=>{assert.equal(r.status,200,JSON.stringify(r.body));return r.body;};
async function setup(t,{erase=[],mfa=true,grant=true,seed=null}={}){
 const f=await retentionFixture(t),member=await f.login(),other=await f.login({phone:'+250789123456'}),approvedOperator=await f.operator({mfa:true,grant}),operator=mfa?approvedOperator:await f.operator({mfa:false,grant,email:'unverified-reviewer@example.com'});
 if(seed)await seed(f,member,other);
 const intake=ok(await f.call('/v1/rpc/request_account_deletion_v1',{p_request_id:randomUUID(),p_reason:null},authorization(member)));
 f.scopeRequest=intake.request_id;const policy=await f.policy(approvedOperator);for(const name of erase)policy.rules[name]={action:'erase',basis_reference:'SYNTHETIC TEST APPROVAL ONLY',deadline:new Date(Date.now()-60000).toISOString()};if(erase.length)await f.policy(approvedOperator,{rules:policy.rules});
 const input={operation_id:randomUUID(),request_id:intake.request_id,expected_review_revision:0,policy_sha256:f.policySha,expected_source_id:sourceId};
 return {f,member,other,operator,input};
}
async function plan(c,headers={}){return ok(await c.f.retention(c.operator,'plan',c.input,headers));}
async function claim(c,p,name,{lease=60,operation=randomUUID()}={}){
 const status=ok(await c.f.retention(c.operator,'status',{plan_id:p.plan_id})),task=status.tasks.find(t=>t.class_name===name);assert.ok(task,name);
 return ok(await c.f.retention(c.operator,'claim',{operation_id:operation,plan_id:p.plan_id,task_id:task.task_id,expected_task_revision:task.revision,lease_seconds:lease}));
}
async function execute(c,k,headers={},operation=randomUUID()){return c.f.retention(c.operator,'execute',{operation_id:operation,claim_id:k.claim_id,fence:k.fence},headers);}
async function run(c,p,name,options={}){return ok(await execute(c,await claim(c,p,name,options),options.headers));}
async function renewPolicy(c,{continuation=true,changes={}}={}){
 const preview=ok(await c.f.retention(c.operator,'continuation',{request_id:c.input.request_id,expected_review_revision:0,expected_source_id:sourceId}));
 const old=JSON.parse((await c.f.db.prepare("SELECT value_json FROM runtime_config WHERE key='privacy:retention:approved:v1'").first()).value_json);
 const prior=preview.prior_quarantine;
 await c.f.policy(c.operator,{version:'synthetic-renewed-policy-only',rules:old.rules,
  ...(continuation?{quarantine_continuation:{action:'continue_quarantine',previous_plan_id:prior.previous_plan_id,
   previous_barrier_sha256:prior.previous_barrier_sha256,approval_evidence_sha256:sha('SYNTHETIC CONTINUED QUARANTINE APPROVAL')}}:{}),...changes});
 c.input={...c.input,operation_id:randomUUID(),policy_sha256:c.f.policySha};
 return {preview};
}
async function seedSafe(f,member,other){
 const date=new Date().toISOString();
 for(const user of [member,other])await f.db.batch([
  f.db.prepare('INSERT INTO notification_preferences(user_id,updated_at) VALUES(?,?)').bind(user.user.id,date),
  f.db.prepare("INSERT INTO notification_devices(id,user_id,token_hash,owner_session_id,provider,token_ciphertext,platform,created_at,updated_at) VALUES(?,?,?,?,'fcm','TEST_CIPHERTEXT','android',?,?)").bind(randomUUID(),user.user.id,sha(user.user.id),'synthetic-session',date,date),
  f.db.prepare("INSERT INTO notification_events(id,user_id,event_type,title,body,created_at) VALUES(?,?,'test','TEST','SYNTHETIC PRIVATE TEXT',?)").bind(randomUUID(),user.user.id,date),
  f.db.prepare("INSERT INTO support_requests(id,user_id,kind,message,created_at) VALUES(?,?,'privacy','SYNTHETIC PRIVATE TEXT',?)").bind(randomUUID(),user.user.id,date)
 ]);
}

test('inventory and status redact their result when the reviewer is revoked during source reads',async t=>{
 for(const action of ['inspect','status']){
  const c=await setup(t),p=action==='status'?await plan(c):null;
  const body=p?{plan_id:p.plan_id}:{request_id:c.input.request_id,expected_review_revision:0,expected_source_id:sourceId};
  const result=await c.f.retention(c.operator,action,body,{'x-test-revoke-after-inventory':'true'});
  assert.equal(result.status,403,JSON.stringify(result.body));
  assert.equal(result.body.code,'privacy_retention_authority_changed');
  assert.equal(result.body.table_counts,undefined);assert.equal(result.body.tasks,undefined);
 }
});

test('read-only resolution retains original plan, lease and effect identities without retrying unknown work',async t=>{
 const c=await setup(t),p=await plan(c),resolve=(kind,operation,operator=c.operator)=>c.f.retention(operator,'resolve',{operation_kind:kind,operation_id:operation});
 const absent=ok(await resolve('execute',randomUUID()));assert.equal(absent.observed,false);assert.equal(absent.receipt,null);
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_claims').first()).n,0);
 const original=ok(await resolve('plan',c.input.operation_id));assert.equal(original.observed,true);assert.equal(original.receipt.plan_id,p.plan_id);
 const lease=await claim(c,p,'access'),foundLease=ok(await resolve('claim',lease.operation_id));assert.equal(foundLease.receipt.claim_id,lease.claim_id);assert.equal(foundLease.receipt.fence,lease.fence);
 const effectId=randomUUID(),outcome=ok(await execute(c,lease,{},effectId)),foundEffect=ok(await resolve('execute',effectId));assert.deepEqual(foundEffect.receipt,outcome);
 assert.equal(foundEffect.currentness_not_asserted,true);assert.equal(foundEffect.erasure_completed,false);
 const another=await c.f.operator({email:'other-privacy-reviewer@example.com'});
 assert.equal(ok(await resolve('plan',c.input.operation_id,another)).observed,false);
 await c.f.db.prepare("DELETE FROM runtime_config WHERE key='privacy:retention:approved:v1'").run();
 assert.equal(ok(await resolve('execute',effectId)).observed,true);
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_outcomes').first()).n,1);
});
async function seedUpload(f,member,count=1){
 for(let i=0;i<count;i++){const id=randomUUID(),key='synthetic-upload/'+id,body='SYNTHETIC PRIVATE BODY '+i;await f.bucket.put(key,body);await f.db.prepare("INSERT INTO upload_objects(id,user_id,object_key,sha256,size_bytes,content_type,purpose,created_at) VALUES(?,?,?,?,?,'text/plain','test',?)").bind(id,member.user.id,key,sha(body),Buffer.byteLength(body),new Date().toISOString()).run();}
}
async function seedFinancial(f,member){
 const g=randomUUID(),e=randomUUID(),p=randomUUID(),entry=randomUUID(),date=new Date().toISOString(),key='evidence/'+e,body='SYNTHETIC RETAINED FINANCIAL EVIDENCE';await f.bucket.put(key,body);
 await f.db.batch([
  f.db.prepare("INSERT INTO collections(id,slug,creator_user_id,title,collection_type,receiver_momo_number,receiver_network,created_at,updated_at) VALUES(?,?,?,'Synthetic group','ikimina','250788123456','mtn_momo',?,?)").bind(g,randomUUID(),member.user.id,date,date),
  f.db.prepare("INSERT INTO memberships(id,collection_id,user_id,role,joined_at) VALUES(?,?,?,'owner',?)").bind(randomUUID(),g,member.user.id,date),
  f.db.prepare("INSERT INTO payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,observed_at,created_at) VALUES(?,?,?,?,?,?,'text/plain','operator_recorded',?,?)").bind(e,g,member.user.id,key,sha(body),Buffer.byteLength(body),date,date),
  f.db.prepare("INSERT INTO payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at) VALUES(?,?,?,?,1000,'reconciled',?)").bind(p,g,member.user.id,e,date),
  f.db.prepare("INSERT INTO ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES(?,?,?,?,1000,'contribution',?,?,?,?)").bind(entry,p,g,member.user.id,e,member.user.id,randomUUID(),date)
 ]);
}

test('exact approved policy and existing authenticated intake bind the complete predecessor catalog',async t=>{
 const c=await setup(t),p=await plan(c);assert.equal(p.tasks.length,c.f.retentionClasses.length);assert.deepEqual(p.tasks.map(t=>t.class_name).sort(),[...c.f.retentionClasses].sort());
 assert.equal(p.erasure_completed,false);assert.equal(p.all_data_erased,false);assert.equal(p.operational_acceptance_granted,false);
 const replay=await plan(c);assert.equal(replay.plan_id,p.plan_id);
 const conflict=await c.f.retention(c.operator,'plan',{...c.input,expected_review_revision:1});assert.equal(conflict.status,409);assert.equal(conflict.body.code,'privacy_retention_operation_conflict');
 const retained=await c.f.db.prepare('SELECT scope_json,policy_json FROM privacy_retention_plans').first();assert.ok(!retained.scope_json.includes('+250788123456'));assert.ok(!retained.scope_json.includes('SYNTHETIC PRIVATE TEXT'));
});

test('versioned identity aliases are scoped through their original challenge and retained as pseudonymous controls',async t=>{
 const c=await setup(t,{seed:async(f,member)=>{
  const original=await f.db.prepare('SELECT a.* FROM auth_identity_rate_aliases a JOIN auth_otp_challenges c ON c.id=a.request_id WHERE c.identity_value=?')
   .bind(member.user.phone).first();assert.ok(original);
  await f.db.prepare('INSERT INTO auth_identity_rate_aliases(request_id,identity_key_id,identity_hash,requested_at,hourly_window_ends_at) VALUES(?,?,?,?,?)')
   .bind(original.request_id,'synthetic-historical-key',sha('SYNTHETIC OWN ALIAS'),original.requested_at,original.hourly_window_ends_at).run();
 }});
 const inspected=ok(await c.f.retention(c.operator,'inspect',{request_id:c.input.request_id,expected_review_revision:0,expected_source_id:sourceId}));
 assert.equal(inspected.table_counts.auth_identity_rate_aliases,2);
 assert.ok(!JSON.stringify(inspected).includes(sha('SYNTHETIC OWN ALIAS')));
 const before=(await c.f.db.prepare('SELECT * FROM auth_identity_rate_aliases ORDER BY request_id,identity_key_id').all()).results;
 const p=await plan(c);await run(c,p,'access');const retained=await run(c,p,'auth_identity_rate_aliases');
 assert.equal(retained.disposition,'retained');assert.equal(retained.erasure_completed,false);
 assert.deepEqual((await c.f.db.prepare('SELECT * FROM auth_identity_rate_aliases ORDER BY request_id,identity_key_id').all()).results,before);
});

test('missing policy pin, unknown classes, source mismatch and expired approval cannot authorize a plan',async t=>{
 const c=await setup(t);
 for(const [input,headers,code]of [[c.input,{'x-test-policy-pin':''},'privacy_retention_policy_unavailable'],[{...c.input,expected_source_id:'a'.repeat(64)},{},'privacy_retention_source_changed']]){const r=await c.f.retention(c.operator,'plan',input,headers);assert.equal(r.status,409);assert.equal(r.body.code,code);}
 const policy=JSON.parse((await c.f.db.prepare("SELECT value_json FROM runtime_config WHERE key='privacy:retention:approved:v1'").first()).value_json);delete policy.rules.users;await c.f.policy(c.operator,policy);c.input.policy_sha256=c.f.policySha;
 assert.equal((await c.f.retention(c.operator,'plan',c.input)).body.code,'privacy_retention_policy_unavailable');
 await c.f.policy(c.operator,{expires_at:new Date(Date.now()-1000).toISOString()});c.input.policy_sha256=c.f.policySha;assert.equal((await c.f.retention(c.operator,'plan',c.input)).body.code,'privacy_retention_policy_unavailable');
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_plans').first()).n,0);
});

test('genuine current MFA and privacy capability are required; revocation also denies an operation replay',async t=>{
 const c=await setup(t,{mfa:false});assert.equal((await c.f.retention(c.operator,'plan',c.input)).status,403);
 const d=await setup(t);await plan(d);await d.f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='privacy.review'").bind(d.operator.user.id).run();const r=await d.f.retention(d.operator,'plan',d.input);assert.equal(r.status,403);assert.match(r.body.code,/authority_changed|mfa_required/);
});

test('source preimages and schema coverage fail closed before a plan becomes durable',async t=>{
 const c=await setup(t,{seed:seedSafe});const r=await c.f.retention(c.operator,'plan',c.input,{'x-test-source-race':'support','x-test-subject':c.member.user.id});assert.equal(r.status,409,JSON.stringify(r.body));
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_plans').first()).n,0);
 await c.f.db.prepare('CREATE TABLE uncovered_private_copy(id TEXT, user_id TEXT)').run();assert.equal((await c.f.retention(c.operator,'plan',c.input)).body.code,'privacy_retention_unknown_class');
});

test('quarantine revokes real sessions and prevents silent reactivation or new sign-in sessions',async t=>{
 const c=await setup(t),p=await plan(c),result=await run(c,p,'access');assert.equal(result.disposition,'access_quarantined');assert.equal(result.session_reapproval_required,true);
 assert.equal((await c.f.call('/v1/auth/user',{},authorization(c.member))).status,401);
 assert.equal((await c.f.db.prepare('SELECT access_status FROM users WHERE id=?').bind(c.member.user.id).first()).access_status,'suspended');
 await assert.rejects(c.f.db.prepare("UPDATE users SET access_status='active' WHERE id=?").bind(c.member.user.id).run(),/privacy_retention_access_quarantined/);
 const at=Math.floor(Date.now()/1000);await assert.rejects(c.f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'member',?,?,?)").bind(randomUUID(),c.member.user.id,at,at,at+3600).run(),/privacy_retention_access_quarantined/);
 assert.equal((await c.f.call('/v1/auth/user',{},authorization(c.other))).status,200);
});

test('renewed policy cannot silently adopt an older immutable quarantine',async t=>{
 const c=await setup(t,{seed:seedSafe}),old=await plan(c);await run(c,old,'access');
 const before=await c.f.db.prepare('SELECT * FROM privacy_retention_barriers').first();
 await renewPolicy(c,{continuation:false});const current=await plan(c),result=await run(c,current,'access');
 assert.equal(result.verified,false);assert.equal(result.reason,'prior_quarantine_requires_explicit_recovery_authority');
 assert.deepEqual(await c.f.db.prepare('SELECT * FROM privacy_retention_barriers').first(),before);
 assert.equal((await c.f.call('/v1/auth/user',{},authorization(c.member))).status,401);
 assert.equal(ok(await c.f.retention(c.operator,'status',{plan_id:old.plan_id})).policy_current,false);
});

test('explicit continued-quarantine approval retains old barrier and requires a durable current access outcome before erasure',async t=>{
 const c=await setup(t,{erase:['support_requests'],seed:seedSafe}),old=await plan(c);await run(c,old,'access');
 const barrier=await c.f.db.prepare('SELECT * FROM privacy_retention_barriers').first();
 const user=await c.f.db.prepare('SELECT * FROM users WHERE id=?').bind(c.member.user.id).first();
 const {preview}=await renewPolicy(c);assert.equal(preview.prior_quarantine.previous_plan_id,old.plan_id);
 assert.equal(preview.approval_granted,false);assert.equal(preview.reactivation_granted,false);
 assert.equal(preview.active_claim_count,0);assert.equal(preview.unresolved_effect_count,0);
 const current=await plan(c),early=await run(c,current,'support_requests');
 assert.equal(early.reason,'subject_write_barrier_required');
 const outcomeId=randomUUID(),lease=await claim(c,current,'access'),continued=ok(await execute(c,lease,{},outcomeId));
 assert.equal(continued.disposition,'access_quarantine_continued');assert.equal(continued.continuation.previous_plan_id,old.plan_id);
 assert.equal(continued.continuation.previous_barrier_sha256,preview.prior_quarantine.previous_barrier_sha256);
 assert.deepEqual(ok(await execute(c,lease,{},outcomeId)),continued,'lost response reuses immutable original outcome');
 assert.deepEqual(await c.f.db.prepare('SELECT * FROM privacy_retention_barriers').first(),barrier);
 assert.deepEqual(await c.f.db.prepare('SELECT * FROM users WHERE id=?').bind(c.member.user.id).first(),user);
 assert.equal((await run(c,current,'support_requests')).disposition,'own_rows_absence_verified');
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM support_requests WHERE user_id=?').bind(c.other.user.id).first()).n,1);
 await assert.rejects(c.f.db.prepare("UPDATE users SET access_status='active' WHERE id=?").bind(c.member.user.id).run(),/privacy_retention_access_quarantined/);
 await assert.rejects(c.f.db.prepare('DELETE FROM privacy_retention_barriers').run(),/retention_barrier_requires_separate_recovery_authority/);
});

test('continued quarantine can use the existing actual R2 adapter without rewriting the predecessor barrier',async t=>{
 const c=await setup(t,{erase:['r2:upload_objects'],seed:(f,m)=>seedUpload(f,m)}),old=await plan(c);await run(c,old,'access');
 const before=await c.f.db.prepare('SELECT * FROM privacy_retention_barriers').first();
 await renewPolicy(c);const current=await plan(c);await run(c,current,'access');
 const erased=await run(c,current,'r2:upload_objects');assert.equal(erased.disposition,'catalog_object_absence_verified');
 const key=(await c.f.db.prepare('SELECT object_key FROM upload_objects').first()).object_key;
 assert.equal(await c.f.bucket.head(key),null);assert.equal(await c.f.bucket.get(key),null);
 assert.deepEqual(await c.f.db.prepare('SELECT * FROM privacy_retention_barriers').first(),before);
});

test('malformed or mismatched continuation approval never grants adoption or reactivation',async t=>{
 const c=await setup(t),old=await plan(c);await run(c,old,'access');
 for(const value of [null,{action:'reactivate'},
  {action:'continue_quarantine',previous_plan_id:old.plan_id,previous_barrier_sha256:'a'.repeat(64),approval_evidence_sha256:'b'.repeat(64),extra:true}]){
  await renewPolicy(c,{changes:{quarantine_continuation:value}});
  const denied=await c.f.retention(c.operator,'plan',c.input);assert.equal(denied.body.code,'privacy_retention_continuation_unapproved');
 }
 const preview=ok(await c.f.retention(c.operator,'continuation',{request_id:c.input.request_id,expected_review_revision:0,expected_source_id:sourceId}));
 for(const changes of [{previous_plan_id:randomUUID()},{previous_barrier_sha256:'c'.repeat(64)}]){
  await renewPolicy(c,{changes:{quarantine_continuation:{action:'continue_quarantine',previous_plan_id:old.plan_id,
   previous_barrier_sha256:preview.prior_quarantine.previous_barrier_sha256,approval_evidence_sha256:sha('SYNTHETIC'),...changes}}});
  const result=await run(c,await plan(c),'access');assert.equal(result.verified,false);assert.equal(result.reason,'prior_quarantine_requires_explicit_recovery_authority');
 }
 assert.equal((await c.f.db.prepare('SELECT access_status FROM users WHERE id=?').bind(c.member.user.id).first()).access_status,'suspended');
});

test('another plan active lease blocks continuation until it expires without restoring old policy authority',async t=>{
 const c=await setup(t,{seed:seedSafe}),old=await plan(c);await run(c,old,'access');
 const priorLease=await claim(c,old,'support_requests',{lease:5});
 const {preview}=await renewPolicy(c);assert.equal(preview.active_claim_count,1);
 const current=await plan(c),blocked=await run(c,current,'access');assert.equal(blocked.reason,'prior_retention_work_unresolved');
 await delay(5100);
 assert.equal((await run(c,current,'access')).disposition,'access_quarantine_continued');
 assert.notEqual((await execute(c,priorLease)).status,200,'renewal cannot restore an old lease/policy');
});

test('unknown predecessor R2 send-start blocks continuation even after its old lease expires',async t=>{
 const c=await setup(t,{erase:['r2:upload_objects'],seed:(f,m)=>seedUpload(f,m)}),old=await plan(c);await run(c,old,'access');
 const priorLease=await claim(c,old,'r2:upload_objects',{lease:5});
 const failed=await execute(c,priorLease,{'x-test-r2-fail-before-delete':'true'});assert.equal(failed.status,500);
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_effects').first()).n,1);
 await delay(5100);
 const {preview}=await renewPolicy(c);assert.equal(preview.active_claim_count,0);assert.equal(preview.unresolved_effect_count,1);
 const result=await run(c,await plan(c),'access');assert.equal(result.verified,false);assert.equal(result.reason,'prior_retention_work_unresolved');
 const key=(await c.f.db.prepare('SELECT object_key FROM upload_objects').first()).object_key;assert.ok(await c.f.bucket.get(key));
});

test('concurrent plans cannot both claim ownership of one newly created quarantine barrier',async t=>{
 const c=await setup(t),first=await plan(c);c.input={...c.input,operation_id:randomUUID()};const second=await plan(c);
 const a=await claim(c,first,'access'),b=await claim(c,second,'access');
 const results=await Promise.all([execute(c,a),execute(c,b)]);
 assert.equal(results.filter(r=>r.status===200&&r.body.verified).length,1,JSON.stringify(results));
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_barriers').first()).n,1);
 assert.equal((await c.f.db.prepare("SELECT count(*) AS n FROM privacy_retention_outcomes WHERE json_extract(outcome_json,'$.verified')=1").first()).n,1);
});

test('all four actual safe-table adapters erase only own rows and preserve other users',async t=>{
 const names=['notification_devices','notification_preferences','notification_events','support_requests'],c=await setup(t,{erase:names,seed:seedSafe}),p=await plan(c);await run(c,p,'access');
 for(const name of names){const result=await run(c,p,name);assert.equal(result.verified,true,JSON.stringify(result));assert.equal(result.disposition,'own_rows_absence_verified');assert.equal(result.erasure_completed,false);assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM '+name+' WHERE user_id=?').bind(c.member.user.id).first()).n,0);assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM '+name+' WHERE user_id=?').bind(c.other.user.id).first()).n,1);}
 const stamp=new Date().toISOString();await assert.rejects(c.f.db.prepare('INSERT INTO notification_preferences(user_id,updated_at) VALUES(?,?)').bind(c.member.user.id,stamp).run(),/privacy_retention_write_barrier/);
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_guards').first()).n,0);
});

test('full-row CAS rolls back a concurrent changed source instead of erasing it',async t=>{
 const c=await setup(t,{erase:['support_requests'],seed:seedSafe}),p=await plan(c);await run(c,p,'access');const k=await claim(c,p,'support_requests');
 const r=await execute(c,k,{'x-test-source-race':'user','x-test-subject':c.member.user.id});assert.equal(r.status,409,JSON.stringify(r.body));assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM support_requests WHERE user_id=?').bind(c.member.user.id).first()).n,1);assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_outcomes WHERE task_id=?').bind(k.task_id).first()).n,0);
});

test('legal holds and unresolved operations prevent destructive admission',async t=>{
 const c=await setup(t);await c.f.db.prepare("INSERT INTO privacy_holds(id,user_id,category,reason_code,created_at) VALUES(?,?,'test','synthetic_hold',?)").bind(randomUUID(),c.member.user.id,new Date().toISOString()).run();await c.f.policy(c.operator);c.input.policy_sha256=c.f.policySha;const p=await plan(c),r=await run(c,p,'access');assert.equal(r.verified,false);assert.equal(r.reason,'legal_hold_active');assert.equal((await c.f.db.prepare('SELECT access_status FROM users WHERE id=?').bind(c.member.user.id).first()).access_status,'active');
 const d=await setup(t);
 // A separate new dispatch is a real retained source row with no fabricated
 // completion; changing consumed OTP identities/states is correctly immutable.
 const row=await d.f.db.prepare('SELECT * FROM auth_otp_challenges WHERE identity_value=?').bind('+250788123456').first();
 await d.f.db.prepare("INSERT INTO auth_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,code_hash,created_at,expires_at,status) VALUES(?,?,?,?,?,0,?,?,?,'delivery_unknown')").bind(randomUUID(),row.identity_hash,row.identity_type,row.identity_value,row.surface,'a'.repeat(64),Math.floor(Date.now()/1000),Math.floor(Date.now()/1000)+300).run();
 await d.f.policy(d.operator);d.input.policy_sha256=d.f.policySha;const q=await plan(d),blocked=await run(d,q,'access');assert.equal(blocked.reason,'in_flight_operation_unresolved');
});

test('expired claim heads are fenced and unknown writes reconcile without guessing success',async t=>{
 const c=await setup(t),p=await plan(c),first=await claim(c,p,'access',{lease:1});await delay(1200);const second=await claim(c,p,'access');assert.ok(second.fence>first.fence);assert.equal((await execute(c,first)).body.code,'privacy_retention_claim_stale');
 const operation=randomUUID(),result=ok(await execute(c,second,{},operation)),replay=ok(await execute(c,second,{},operation));assert.deepEqual(replay,result);assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_outcomes WHERE claim_id=?').bind(second.claim_id).first()).n,1);
});

test('actual R2 deletion is one object per execution, resumable and tied to verified absence',async t=>{
 const c=await setup(t,{erase:['r2:upload_objects'],seed:async(f,m)=>{await seedUpload(f,m,2);await f.db.prepare("UPDATE upload_objects SET deleted_at='2020-01-01T00:00:00.000Z'").run();}}),p=await plan(c);await run(c,p,'access');const first=await run(c,p,'r2:upload_objects');assert.equal(first.disposition,'partial');assert.equal(first.objects_verified_absent,1);assert.equal(first.objects_remaining,1);
 const second=await run(c,p,'r2:upload_objects');assert.equal(second.verified,true,JSON.stringify(second));assert.equal(second.objects_verified_absent,2);assert.equal(second.all_data_erased,false);
 const catalog=(await c.f.db.prepare('SELECT * FROM upload_objects').all()).results;for(const row of catalog){assert.equal(row.status,'deleted');assert.ok(Date.parse(row.deleted_at)>Date.parse('2020-01-01T00:00:00.000Z'));assert.equal(await c.f.bucket.head(row.object_key),null);assert.equal(await c.f.bucket.get(row.object_key),null);}
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_effects').first()).n,2);
});

test('lost R2 acknowledgement is reconciled from retained effect identity on the next lease',async t=>{
 const c=await setup(t,{erase:['r2:upload_objects'],seed:(f,m)=>seedUpload(f,m)}),p=await plan(c);await run(c,p,'access');const first=await claim(c,p,'r2:upload_objects',{lease:2}),failed=await execute(c,first,{'x-test-r2-lost-ack':'true'});assert.equal(failed.status,500);assert.match(failed.body.detail,/Controlled lost acknowledgement/);
 const object=await c.f.db.prepare('SELECT * FROM upload_objects').first();assert.equal(await c.f.bucket.head(object.object_key),null);assert.equal(object.status,'retained');assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_effects').first()).n,1);await delay(2200);
 const recovered=await run(c,p,'r2:upload_objects');assert.equal(recovered.verified,true,JSON.stringify(recovered));assert.equal(recovered.objects_verified_absent,1);assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_effects').first()).n,1);
});

test('a replacement object or hold introduced before effect admission is never deleted',async t=>{
 for(const kind of ['replace','hold']){const c=await setup(t,{erase:['r2:upload_objects'],seed:(f,m)=>seedUpload(f,m)}),p=await plan(c);await run(c,p,'access');const k=await claim(c,p,'r2:upload_objects'),r=await execute(c,k,{'x-test-r2-race':kind,'x-test-subject':c.member.user.id});assert.ok(r.status===409||r.body.verified===false,JSON.stringify(r));const object=await c.f.db.prepare('SELECT * FROM upload_objects').first();assert.ok(await c.f.bucket.head(object.object_key));assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_effects').first()).n,0);}
});

test('immutable journals, financial evidence and exact balances survive eligible erasure',async t=>{
 const c=await setup(t,{erase:['support_requests'],seed:async(f,m,o)=>{await seedSafe(f,m,o);await seedFinancial(f,m);}}),p=await plan(c),before=(await c.f.db.prepare('SELECT * FROM ledger_entries ORDER BY id').all()).results;await run(c,p,'access');await run(c,p,'support_requests');
 assert.deepEqual((await c.f.db.prepare('SELECT * FROM ledger_entries ORDER BY id').all()).results,before);assert.equal((await c.f.db.prepare('SELECT sum(amount_minor) AS n FROM ledger_entries').first()).n,1000);
 await assert.rejects(c.f.db.prepare('DELETE FROM ledger_entries').run(),/immutable_ledger/);await assert.rejects(c.f.db.prepare('DELETE FROM payment_evidence').run(),/retain_financial_evidence/);
 const reconciled=ok(await c.f.retention(c.operator,'reconcile',{plan_id:p.plan_id}));assert.equal(reconciled.financial_journal_preserved,true);assert.equal(reconciled.eligible_dispositions_verified,false);assert.equal(reconciled.all_actual_copy_outcomes_verified,false);assert.equal(reconciled.erasure_completed,false);
});

test('unimplemented copies and immutable erasure requests block whole completion truthfully',async t=>{
 const c=await setup(t,{erase:['users']}),p=await plan(c);await run(c,p,'access');const users=await run(c,p,'users');assert.equal(users.reason,'immutable_or_unimplemented_class_adapter');
 for(const name of ['external:backups','external:processors','external:exports','external:derivatives','external:unmapped_identifiers']){const r=await run(c,p,name);assert.equal(r.verified,false);assert.equal(r.reason,'external_copy_adapter_and_actual_inventory_required');}
 const r=ok(await c.f.retention(c.operator,'reconcile',{plan_id:p.plan_id}));assert.equal(r.state,'blocked');assert.equal(r.eligible_dispositions_verified,false);assert.equal(r.all_data_erased,false);assert.equal(r.operational_acceptance_granted,false);
});

test('source or policy changes invalidate status and new execution; immutable receipts remain evidence',async t=>{
 const c=await setup(t),p=await plan(c);await run(c,p,'access');await c.f.db.prepare("UPDATE runtime_config SET revision=revision+1 WHERE key='privacy:retention:approved:v1'").run();const status=ok(await c.f.retention(c.operator,'status',{plan_id:p.plan_id}));assert.equal(status.state,'blocked');assert.equal(status.policy_current,false);
 assert.equal((await c.f.retention(c.operator,'claim',{operation_id:randomUUID(),plan_id:p.plan_id,task_id:p.tasks.find(t=>t.class_name==='users').task_id,expected_task_revision:0,lease_seconds:60})).body.code,'privacy_retention_policy_changed');
 await assert.rejects(c.f.db.prepare('DELETE FROM privacy_retention_outcomes').run(),/retain_retention_outcome/);await assert.rejects(c.f.db.prepare("UPDATE privacy_retention_plans SET source_id=?").bind('b'.repeat(64)).run(),/immutable_retention_plan/);
});

test('engine-generated control copies require seven explicit retain decisions and actual scoped observations',async t=>{
 const c=await setup(t),p=await plan(c);for(const name of ['privacy_retention_plans','privacy_retention_tasks','privacy_retention_claims','privacy_retention_outcomes','privacy_retention_effects','privacy_retention_guards','privacy_retention_barriers']){const r=await run(c,p,name);assert.equal(r.verified,true,JSON.stringify(r));assert.equal(r.disposition,'control_records_retained');assert.match(r.engine_snapshot_sha256,/^[a-f0-9]{64}$/);}
 assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_guards').first()).n,0);
});

test('an earlier durable send-start cannot bypass a new hold on a renewed deletion attempt',async t=>{
 const c=await setup(t,{erase:['r2:upload_objects'],seed:(f,m)=>seedUpload(f,m)}),p=await plan(c);await run(c,p,'access');const first=await claim(c,p,'r2:upload_objects',{lease:2});const outage=await execute(c,first,{'x-test-r2-fail-before-delete':'true'});assert.equal(outage.status,500);assert.match(outage.body.detail,/Controlled outage before actual R2 delete/);
 const object=await c.f.db.prepare('SELECT * FROM upload_objects').first();assert.ok(await c.f.bucket.head(object.object_key));assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_effects').first()).n,1);await delay(2200);const renewed=await claim(c,p,'r2:upload_objects');const denied=await execute(c,renewed,{'x-test-r2-race':'hold','x-test-subject':c.member.user.id});assert.equal(denied.status,409,JSON.stringify(denied.body));assert.ok(await c.f.bucket.head(object.object_key));
});

test('unsafe database integers and new columns cannot be silently omitted from source coverage',async t=>{
 const c=await setup(t,{seed:seedSafe});await c.f.db.prepare('UPDATE notification_preferences SET revision=9007199254740993 WHERE user_id=?').bind(c.member.user.id).run();const precision=await c.f.retention(c.operator,'plan',c.input);assert.equal(precision.status,409,JSON.stringify(precision.body));assert.equal(precision.body.code,'privacy_retention_precision_unavailable');
 const d=await setup(t);await d.f.db.prepare('ALTER TABLE users ADD COLUMN uncovered_private_text TEXT').run();const schema=await d.f.retention(d.operator,'plan',d.input);assert.equal(schema.status,409);assert.equal(schema.body.code,'privacy_retention_schema_changed');
});

test('approval binds one authenticated request, subject and exact inventory instead of an arbitrary current account',async t=>{
 const c=await setup(t,{seed:seedSafe});const inspect=ok(await c.f.retention(c.operator,'inspect',{request_id:c.input.request_id,expected_review_revision:0,expected_source_id:sourceId}));assert.equal(inspect.subject_id,c.member.user.id);assert.equal(inspect.approval_granted,false);assert.match(inspect.snapshot_sha256,/^[a-f0-9]{64}$/);
 const otherIntake=ok(await c.f.call('/v1/rpc/request_account_deletion_v1',{p_request_id:randomUUID(),p_reason:null},authorization(c.other)));
 const wrong=await c.f.retention(c.operator,'plan',{...c.input,operation_id:randomUUID(),request_id:otherIntake.request_id});assert.equal(wrong.status,409);assert.equal(wrong.body.code,'privacy_retention_scope_unapproved');
 await c.f.db.prepare("UPDATE support_requests SET message='OWNER HAS NOT APPROVED THIS NEW INVENTORY' WHERE user_id=?").bind(c.member.user.id).run();const changed=await c.f.retention(c.operator,'plan',c.input);assert.equal(changed.status,409);assert.equal(changed.body.code,'privacy_retention_scope_unapproved');assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_plans').first()).n,0);
});

test('concurrent exact plan and claim retries retain one operation identity',async t=>{
 const c=await setup(t);const plans=await Promise.all([c.f.retention(c.operator,'plan',c.input),c.f.retention(c.operator,'plan',c.input)]);plans.forEach(ok);assert.equal(plans[0].body.plan_id,plans[1].body.plan_id);assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_plans').first()).n,1);
 const p=plans[0].body,task=p.tasks.find(t=>t.class_name==='access'),body={operation_id:randomUUID(),plan_id:p.plan_id,task_id:task.task_id,expected_task_revision:0,lease_seconds:60};const claims=await Promise.all([c.f.retention(c.operator,'claim',body),c.f.retention(c.operator,'claim',body)]);claims.forEach(ok);assert.deepEqual(claims[0].body,claims[1].body);assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_claims').first()).n,1);
 const operation=randomUUID(),outcomes=await Promise.all([execute(c,claims[0].body,{},operation),execute(c,claims[0].body,{},operation)]);outcomes.forEach(ok);assert.deepEqual(outcomes[0].body,outcomes[1].body);assert.equal((await c.f.db.prepare('SELECT count(*) AS n FROM privacy_retention_outcomes').first()).n,1);
});
