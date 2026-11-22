import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './support/notification_operator_integration_fixture.mjs';
import {claims,totp} from './support/auth_fixture.mjs';

const base='/api/admin/notification-operator';
const ok=r=>{assert.equal(r.status,200,JSON.stringify(r.body));return r.body.result??r.body;};
const count=async(f,table)=>(await f.db.prepare('SELECT count(*) AS n FROM '+table).first()).n;
const consentBody=(s,optIn,revision=0,decision=0)=>({p_collection_id:s.group,p_expected_revision:revision,p_expected_decision_revision:decision,p_opt_in:optIn,p_request_id:randomUUID()});
const consent=(s,body,headers={},session=s.phone)=>s.f.call('/v1/rpc/set_assisted_sms_consent_v1',{origin:'https://collect.example',data:body,headers:{Authorization:'Bearer '+session.access_token,...headers}});
const consentState=(s,session=s.phone,group=s.group)=>s.f.call('/v1/rpc/get_assisted_sms_consent_v1',{origin:'https://collect.example',data:{p_collection_id:group},headers:{Authorization:'Bearer '+session.access_token}});
const accessBody=(enabled,read=false,manage=read,decision=0)=>({request_id:randomUUID(),expected_read:read,expected_manage:manage,expected_decision_revision:decision,enabled,...(enabled?{owner_confirmation:true}:{})});
const access=(s,body,headers={},session=s.operator)=>s.f.call(base+'/access',{cookie:session.cookie,data:body,headers:{'X-Collect-Admin':'1',...headers}});
const accessState=(s,session=s.operator)=>s.f.call(base+'/access',{method:'GET',cookie:session.cookie});
const accessOperation=(s,requestId,session=s.operator)=>s.f.call(base+'/access/operations/'+requestId,{method:'GET',cookie:session.cookie});
const receipts=async(s,operation)=>(await s.f.db.prepare('SELECT * FROM request_receipts WHERE operation=? ORDER BY request_id').bind(operation).all()).results;
async function group(f,userId){const id=randomUUID(),date=new Date().toISOString();await f.db.batch([
 f.db.prepare("INSERT INTO collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES(?,?,?,'Synthetic ordered decisions','ikimina',?,?)").bind(id,'decision-'+id,userId,date,date),
 f.db.prepare("INSERT INTO memberships(id,collection_id,user_id,role,joined_at) VALUES(?,?,?,'owner',?)").bind(randomUUID(),id,userId,date),
]);return id;}
async function member(t,{second=false}={}){
 const f=await fixture(t),phone=await f.nativeLogin(),userId=claims(phone.access_token).sub,s={f,phone,userId,group:await group(f,userId)};
 if(second){const email='decision-session@synthetic.test';await f.db.prepare('UPDATE users SET email=?,updated_at=? WHERE id=?').bind(email,new Date().toISOString(),userId).run();
  const challenge=await f.call('/v1/auth/otp',{origin:'https://collect.example',data:{email,captcha_token:randomUUID()}});assert.equal(challenge.status,202);
  const delivered=f.mail.findLast(x=>x.to===email&&x.subject==='Your Collect sign-in code');assert.ok(delivered,'Native email binding captured this recipient');
  const code=/^Your Collect sign-in code is ([0-9]{6})\. /.exec(delivered.text)?.[1];assert.ok(code,'Native email contains the exact sign-in code');
  const verified=await f.call('/v1/auth/verify',{origin:'https://collect.example',data:{email,challenge_id:challenge.body.challenge_id,code,captcha_token:randomUUID()}});assert.equal(verified.status,200);s.other=verified.body;
  assert.equal(claims(s.other.access_token).sub,userId);assert.notEqual(claims(s.other.access_token).session_id,claims(phone.access_token).session_id);
 }return s;
}
async function owner(t,{second=false}={}){
 const f=await fixture(t),account=await f.seedAccount(),operator=await f.stepUp(await f.login(account)),s={f,account,operator};
 if(second){const factor=operator.factor,login=await f.login(account),challenge=await f.call('/api/admin/auth/mfa/challenge',{cookie:login.cookie,data:{factor_id:factor.id}});assert.equal(challenge.status,200);
  const verified=await f.call('/api/admin/auth/mfa/verify',{cookie:login.cookie,data:{factor_id:factor.id,challenge_id:challenge.body.challenge_id,code:totp(factor.totp.secret,Math.floor(Date.now()/30000)+1)}});assert.equal(verified.status,200);s.other=verified;
  const first=ok(await f.call('/api/admin/auth/session',{method:'GET',cookie:operator.cookie})).user,second=ok(await f.call('/api/admin/auth/session',{method:'GET',cookie:s.other.cookie})).user;
  assert.equal(first.principalId,second.principalId);assert.notEqual(first.sessionId,second.sessionId);
 }return s;
}
async function assertNoReceipt(s,requestId){for(const table of ['request_receipts','audit_log'])assert.equal((await s.f.db.prepare('SELECT count(*) AS n FROM '+table+' WHERE request_id=?').bind(requestId).first()).n,0);}

test('each no-op member withdrawal advances only the immutable decision head and exact replay never increments it',async t=>{
 const s=await member(t),initial=ok(await consentState(s));assert.equal(initial.decision_revision,0);assert.equal(initial.revision,0);
 const firstBody=consentBody(s,false),first=ok(await consent(s,firstBody));assert.equal(first.decision_revision,1);assert.equal(first.consent_revision,0);assert.equal(first.destination_revision,null);assert.equal(first.authorization_receipt_sha256,null);
 const second=ok(await consent(s,consentBody(s,false,0,1)));assert.equal(second.decision_revision,2);assert.equal(second.consent_revision,0);assert.equal(await count(s.f,'assisted_sms_authorizations'),0);
 const repeated=ok(await consent(s,firstBody));assert.equal(repeated.replay,true);assert.equal(repeated.decision_revision,1);assert.equal(repeated.decision_sha256,first.decision_sha256);
 assert.equal(ok(await consentState(s)).decision_revision,2);assert.equal((await receipts(s,'assisted_sms.consent.set')).length,2);
 const stale=consentBody(s,false);assert.equal((await consent(s,stale)).status,409);await assertNoReceipt(s,stale.p_request_id);
});

test('later explicit initial withdrawal in another genuine live session atomically fences an older paused opt-in',async t=>{
 const s=await member(t,{second:true}),older=consentBody(s,true),later=consentBody(s,false);let observed;
 s.f.setGate(async()=>{observed=ok(await consent(s,later,{},s.other));assert.equal(observed.decision_revision,1);assert.equal(observed.consent_revision,0);assert.equal(await count(s.f,'assisted_sms_authorizations'),0);});
 const denied=await consent(s,older,{'X-Test-Pause':'before_commit'});assert.equal(denied.status,409);assert.equal(denied.body.code,'stale_state');assert.ok(observed);await assertNoReceipt(s,older.p_request_id);
 const current=ok(await consentState(s,s.other));assert.equal(current.decision_revision,1);assert.equal(current.opt_in,false);assert.equal(current.revision,0);assert.equal(await count(s.f,'assisted_sms_authorizations'),0);
 const laterExplicit=ok(await consent(s,consentBody(s,true,0,1)));assert.equal(laterExplicit.decision_revision,2);assert.equal(laterExplicit.consent_revision,1);assert.equal(ok(await consentState(s,s.other)).decision_revision,2);
});

test('opt-in committing first remains historical while a later correctly based withdrawal wins the inverse ordering',async t=>{
 const s=await member(t,{second:true}),body=consentBody(s,true),first=ok(await consent(s,body));assert.equal(first.decision_revision,1);
 const withdrawn=ok(await consent(s,consentBody(s,false,1,1),{},s.other));assert.equal(withdrawn.decision_revision,2);assert.equal(withdrawn.consent_revision,2);
 const historical=ok(await consent(s,body));assert.equal(historical.opt_in,true);assert.equal(historical.decision_revision,1);assert.equal(historical.recorded_state_only,true);assert.equal(ok(await consentState(s)).opt_in,false);assert.equal(ok(await consentState(s)).decision_revision,2);
});

test('two same-head no-op member choices cannot both commit and exact concurrent retries share one receipt',async t=>{
 const s=await member(t),first=consentBody(s,false),second=consentBody(s,false);let winner;
 s.f.setGate(async()=>{winner=ok(await consent(s,second));});assert.equal((await consent(s,first,{'X-Test-Pause':'before_commit'})).status,409);assert.equal(winner.decision_revision,1);await assertNoReceipt(s,first.p_request_id);
 const exact=consentBody(s,false,0,1);s.f.setGate(async()=>{ok(await consent(s,exact));});const repeated=ok(await consent(s,exact,{'X-Test-Pause':'before_commit'}));assert.equal(repeated.decision_revision,2);
 assert.equal((await receipts(s,'assisted_sms.consent.set')).length,2);assert.equal(await count(s.f,'assisted_sms_authorizations'),0);
});

test('member decision heads are exact subject/group/purpose scoped and a new session cannot adopt an older receipt',async t=>{
 const s=await member(t,{second:true}),body=consentBody(s,false),first=ok(await consent(s,body));assert.equal(first.decision_revision,1);
 assert.equal(ok(await consentState(s,s.other)).decision_revision,1);assert.equal((await consent(s,body,{},s.other)).status,409);
 const otherGroup=await group(s.f,s.userId);assert.equal(ok(await consentState(s,s.other,otherGroup)).decision_revision,0);
 ok(await consent(s,{...consentBody(s,false),p_collection_id:otherGroup}, {},s.other));assert.equal(ok(await consentState(s)).decision_revision,1);assert.equal(ok(await consentState(s,s.other,otherGroup)).decision_revision,1);
 const foreign=await s.f.nativeLogin('+250789123456'),foreignId=claims(foreign.access_token).sub;await s.f.db.prepare("INSERT INTO memberships(id,collection_id,user_id,role,joined_at) VALUES(?,?,?,'member',?)").bind(randomUUID(),s.group,foreignId,new Date().toISOString()).run();
 assert.equal(ok(await consentState(s,foreign)).decision_revision,0);ok(await consent(s,consentBody(s,false),{},foreign));assert.equal(ok(await consentState(s)).decision_revision,1);
});

test('member decision revision is required, canonical safe numeric and leaves no receipt for invalid or stale expectations',async t=>{
 const s=await member(t),body=consentBody(s,false);
 for(const value of [undefined,null,true,'0',-1,0.5,Number.MAX_SAFE_INTEGER,Number.MAX_SAFE_INTEGER+1]){const invalid={...body,p_request_id:randomUUID(),p_expected_decision_revision:value};assert.equal((await consent(s,invalid)).status,400);await assertNoReceipt(s,invalid.p_request_id);}
 const large={...body,p_expected_decision_revision:Number.MAX_SAFE_INTEGER-1};assert.equal((await consent(s,large)).status,409);await assertNoReceipt(s,large.p_request_id);
 assert.equal(ok(await consentState(s)).decision_revision,0);assert.equal(await count(s.f,'assisted_sms_authorizations'),0);
});

for(const phase of ['before','after'])test('member '+phase+' commit lost acknowledgement has observed head recovery without a blind replacement decision',async t=>{
 const s=await member(t),body=consentBody(s,false);s.f.setGate(async()=>{if(phase==='before')throw new Error('controlled_unavailable_before_commit');});
 const failed=await consent(s,body,{'X-Test-Pause':phase==='before'?'before_commit':'consent_lost_reply'});assert.equal(failed.status,503);
 const head=ok(await consentState(s));assert.equal(head.decision_revision,phase==='before'?0:1);assert.equal(head.opt_in,false);assert.equal(await count(s.f,'assisted_sms_authorizations'),0);
 const recovered=ok(await consent(s,body));assert.equal(recovered.decision_revision,1);assert.equal(recovered.replay,phase==='after');assert.equal((await receipts(s,'assisted_sms.consent.set')).length,1);
});

test('each no-op Owner disable advances its head and status separates original revision from current state and history',async t=>{
 const s=await owner(t),body=accessBody(false),first=ok(await access(s,body));assert.equal(first.decision_revision,1);assert.equal(first.can_operate,false);
 const second=ok(await access(s,accessBody(false,false,false,1)));assert.equal(second.decision_revision,2);assert.equal(second.can_operate,false);
 const replay=ok(await access(s,body));assert.equal(replay.replay,true);assert.equal(replay.decision_revision,1);assert.equal(replay.decision_sha256,first.decision_sha256);
 const status=ok(await accessOperation(s,body.request_id));assert.equal(status.recorded_decision.decision_revision,1);assert.equal(status.current_access.decision_revision,2);assert.equal(status.may_send,false);assert.equal(status.replay_authorized,false);
 const history=ok(await s.f.call(base+'/operations',{method:'GET',cookie:s.operator.cookie}));assert.equal(history.items.length,2);assert.ok(history.items.every(x=>x.kind==='access'&&x.may_send===false));assert.equal((await receipts(s,'assisted_sms.access.set')).length,2);
});

test('later false-to-false disable in another genuine Owner session fences an older paused enable atomically',async t=>{
 const s=await owner(t,{second:true}),older=accessBody(true),later=accessBody(false);let disabled;
 s.f.setGate(async()=>{disabled=ok(await access(s,later,{},s.other));assert.equal(disabled.decision_revision,1);assert.equal(disabled.can_operate,false);});
 const denied=await access(s,older,{'X-Test-Pause':'before_commit'});assert.equal(denied.status,409);assert.equal(denied.body.error.code,'stale_state');assert.ok(disabled);await assertNoReceipt(s,older.request_id);
 const current=ok(await accessState(s,s.other));assert.equal(current.decision_revision,1);assert.equal(current.can_operate,false);
 const explicit=ok(await access(s,accessBody(true,false,false,1)));assert.equal(explicit.decision_revision,2);assert.equal(explicit.can_operate,true);assert.equal(ok(await accessState(s,s.other)).decision_revision,2);
});

test('Owner enable first then explicit disable preserves recorded history while preventing Boolean ABA adoption',async t=>{
 const s=await owner(t,{second:true}),original=accessBody(true),enabled=ok(await access(s,original));assert.equal(enabled.decision_revision,1);
 const disabled=ok(await access(s,accessBody(false,true,true,1),{},s.other));assert.equal(disabled.decision_revision,2);assert.equal(disabled.can_operate,false);
 const stale=accessBody(true);assert.equal((await access(s,stale)).status,409);await assertNoReceipt(s,stale.request_id);
 const old=ok(await access(s,original));assert.equal(old.decision_revision,1);assert.equal(old.can_operate,true);assert.equal(old.recorded_state_only,true);assert.equal(ok(await accessState(s)).can_operate,false);assert.equal(ok(await accessState(s)).decision_revision,2);
 assert.equal((await access(s,original,{},s.other)).status,409);assert.equal((await accessOperation(s,original.request_id,s.other)).status,409);
});

test('same-head explicit Owner no-ops serialize once and exact concurrent retries do not increment twice',async t=>{
 const s=await owner(t),older=accessBody(false),later=accessBody(false);s.f.setGate(async()=>{ok(await access(s,later));});
 assert.equal((await access(s,older,{'X-Test-Pause':'before_commit'})).status,409);await assertNoReceipt(s,older.request_id);
 const exact=accessBody(false,false,false,1);s.f.setGate(async()=>{ok(await access(s,exact));});assert.equal(ok(await access(s,exact,{'X-Test-Pause':'before_commit'})).decision_revision,2);
 assert.equal((await receipts(s,'assisted_sms.access.set')).length,2);assert.equal(ok(await accessState(s)).can_operate,false);
});

test('Owner decision revision is required and safe numeric; unchanged grant booleans cannot excuse a stale head',async t=>{
 const s=await owner(t),body=accessBody(false);
 for(const value of [undefined,null,true,'0',-1,0.5,Number.MAX_SAFE_INTEGER,Number.MAX_SAFE_INTEGER+1]){const invalid={...body,request_id:randomUUID(),expected_decision_revision:value};assert.equal((await access(s,invalid)).status,400);await assertNoReceipt(s,invalid.request_id);}
 const large={...body,expected_decision_revision:Number.MAX_SAFE_INTEGER-1};assert.equal((await access(s,large)).status,409);await assertNoReceipt(s,large.request_id);
 ok(await access(s,body));const stale=accessBody(false);assert.equal((await access(s,stale)).status,409);await assertNoReceipt(s,stale.request_id);assert.equal(ok(await accessState(s)).decision_revision,1);
});

for(const phase of ['before','after'])test('Owner '+phase+' commit lost acknowledgement readback retains one monotonic decision without regranting',async t=>{
 const s=await owner(t),body=accessBody(false);s.f.setGate(async()=>{if(phase==='before')throw new Error('controlled_unavailable_before_commit');});
 const failed=await access(s,body,{'X-Test-Pause':phase==='before'?'before_commit':'access_lost_reply'});assert.equal(failed.status,503);
 const status=ok(await accessOperation(s,body.request_id));assert.equal(status.current_access.decision_revision,phase==='before'?0:1);assert.equal(status.observed,phase==='after');assert.equal(status.may_be_in_flight,phase==='before');
 const replay=ok(await access(s,body));assert.equal(replay.decision_revision,1);assert.equal(replay.replay,phase==='after');assert.equal(ok(await accessState(s)).can_operate,false);assert.equal((await receipts(s,'assisted_sms.access.set')).length,1);
});

test('actual immutable receipt update/delete constraints preserve no-op decision heads; unrelated operation receipts never advance them',async t=>{
 const s=await member(t),body=consentBody(s,false),first=ok(await consent(s,body)),before=await receipts(s,'assisted_sms.consent.set');
 await assert.rejects(s.f.db.prepare("UPDATE request_receipts SET response_json='{}' WHERE user_id=? AND request_id=?").bind(s.userId,body.p_request_id).run(),/immutable_receipt/);
 await assert.rejects(s.f.db.prepare('DELETE FROM request_receipts WHERE user_id=? AND request_id=?').bind(s.userId,body.p_request_id).run(),/retain_request_receipt/);
 const unrelated=randomUUID();await s.f.db.prepare('INSERT INTO request_receipts(user_id,request_id,operation,session_id,body_sha256,response_json,created_at) VALUES(?,?,?,?,?,?,?)').bind(s.userId,unrelated,'declared_synthetic_unrelated_receipt',claims(s.phone.access_token).session_id,'0'.repeat(64),JSON.stringify(first),new Date().toISOString()).run();
 assert.deepEqual(await receipts(s,'assisted_sms.consent.set'),before);assert.equal(ok(await consentState(s)).decision_revision,1);assert.equal(await count(s.f,'assisted_sms_authorizations'),0);
 const a=await owner(t),choice=accessBody(false);ok(await access(a,choice));const saved=await receipts(a,'assisted_sms.access.set');
 await assert.rejects(a.f.db.prepare("UPDATE request_receipts SET operation='discarded' WHERE user_id=? AND request_id=?").bind(a.account.userId,choice.request_id).run(),/immutable_receipt/);
 await assert.rejects(a.f.db.prepare('DELETE FROM request_receipts WHERE user_id=? AND request_id=?').bind(a.account.userId,choice.request_id).run(),/retain_request_receipt/);
 assert.deepEqual(await receipts(a,'assisted_sms.access.set'),saved);assert.equal(ok(await accessState(a)).decision_revision,1);
});
