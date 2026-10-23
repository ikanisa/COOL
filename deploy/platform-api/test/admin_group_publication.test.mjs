import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture,hash,ORIGIN} from './admin_support/fixture.mjs';

async function operator(f,options={}){const account=await f.seedAccount(options);return {...await f.stepUp(await f.login(account)),account};}
const groupBody=member=>({title:'Public boundary group',slug:'publication-'+randomUUID(),collection_type:'ikimina',
 owner_user_id:member.id,receiver:{label:'Recorded public receiver',network:'mtn_momo',momo_number_or_code:member.phone},reason:'Review canonical group publication'});
const publishBody=version=>({expected_version:version,visibility:'public_approved',is_platform_sponsored:true,reason:'Publish the reviewed existing group'});
const patch=(f,admin,id,body,key=randomUUID(),headers={})=>f.call('/api/admin/operations/groups/'+id,{method:'PATCH',cookie:admin.cookie,data:body,headers:{'Idempotency-Key':key,...headers}});
const detail=(f,admin,type,id)=>f.call(`/api/admin/operations/${type}/${id}`,{method:'GET',cookie:admin.cookie});
const publicFeed=f=>f.call('/v1/query/public-collections',{method:'GET',origin:'https://collect.example'});
const group=(f,id)=>f.db.prepare('SELECT * FROM collections WHERE id=?').bind(id).first();
const count=(f,table)=>f.db.prepare('SELECT count(*) AS n FROM '+table).first().then(r=>r.n);

test('owner and Admin public creation retain exact receipts and audited locked merchant routes',async t=>{
 for(const role of ['owner','admin'])await t.test(role,async t=>{
  const f=await fixture(t),admin=await operator(f,{role,...(role==='admin'?{email:'publisher@example.test'}:{})}),member=await f.seedMember(),key=randomUUID(),body={...groupBody(member),visibility:'public_approved',is_platform_sponsored:true,
   receiver:{label:'Recorded merchant code',network:'airtel_money',momo_number_or_code:'123456'}};
  const created=await f.operation('groups',admin.cookie,body,key,{'X-Test-Pause':'lost_reply'});assert.equal(created.status,200,JSON.stringify(created));
  assert.deepEqual((await f.operation('groups',admin.cookie,body,key)).body,created.body);
  const row=await group(f,created.body.resource_id);assert.equal(row.visibility_status,'public_approved');assert.equal(row.is_platform_sponsored,1);assert.equal(row.receiver_momo_number,'123456');assert.equal(row.receiver_network,'airtel_money');assert.equal(row.creator_user_id,member.id);
  assert.equal(await count(f,'collections'),1);assert.equal(await count(f,'memberships'),1);assert.equal(await count(f,'admin_bridge_requests'),1);assert.equal(await count(f,'request_receipts'),1);
  assert.equal(await count(f,'ledger_entries'),0,'publication records no contribution or settlement');
  const audit=await f.db.prepare('SELECT * FROM audit_log WHERE request_id=?').bind(created.body.request_id).first();assert.equal(audit.actor_user_id,admin.account.userId);assert.equal(audit.entity_id,row.id);assert.ok(JSON.stringify(audit).includes(body.reason));
  const feed=await publicFeed(f);assert.equal(feed.status,200);assert.equal(feed.body.length,1);assert.equal(feed.body[0].id,row.id);assert.equal(feed.body[0].is_public,true);assert.equal(feed.body[0].is_platform_sponsored,true);assert.ok(!('receiver_momo_number' in feed.body[0]));
  const history=await f.call('/api/admin/operations/requests/'+key,{method:'GET',cookie:admin.cookie});assert.equal(history.body.status,'succeeded');assert.deepEqual(history.body.receipt,created.body);
  assert.equal((await f.operation('groups',admin.cookie,{...body,title:'Changed publication'},key)).status,409);
 });
});

test('publication requires actual Admin authority, current grants and real MFA without escalating Staff',async t=>{
 const f=await fixture(t),member=await f.seedMember(),staff=await operator(f,{email:'staff-publish@example.test',role:'staff'}),account=await f.seedAccount({email:'admin-password@example.test',role:'admin'}),password=await f.login(account),body={...groupBody(member),visibility:'public_approved',is_platform_sponsored:true};
 for(const permission of ['collections.manage','receivers.manage'])await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_by,granted_at) VALUES(?,?,?,?)').bind(staff.account.userId,permission,'explicit test forged grant',new Date().toISOString()).run();
 assert.equal((await f.operation('groups',staff.cookie,body)).status,403);
 assert.equal((await f.operation('groups',password.cookie,body)).status,403);
 const admin=await f.stepUp(password);await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='receivers.manage'").bind(account.userId).run();
 assert.equal((await f.operation('groups',admin.cookie,body)).status,403);
 assert.equal(await count(f,'collections'),0);assert.equal(await count(f,'admin_bridge_requests'),0);assert.equal(await count(f,'request_receipts'),0);
 assert.equal((await f.db.prepare('SELECT role FROM admin_users WHERE id=?').bind(staff.account.adminId).first()).role,'staff');
});

test('Admin publishes an existing Staff group with recorded receiver, cancels pending intents and fences native edits permanently',async t=>{
 const f=await fixture(t),staff=await operator(f,{email:'staff-private@example.test',role:'staff'}),admin=await operator(f),member=await f.seedMember(),created=await f.operation('groups',staff.cookie,groupBody(member));assert.equal(created.status,200);
 const id=created.body.resource_id,native=await f.nativeLogin(member.phone),auth={Authorization:`Bearer ${native.access_token}`};
 const requestPublic=await f.call('/v1/rpc/update_rwanda_momo_group_profile',{origin:'https://collect.example',headers:auth,data:{p_collection_id:id,p_request_id:randomUUID(),p_group_name:'Member pending group',p_group_is_public:true}});assert.equal(requestPublic.status,200,JSON.stringify(requestPublic));
 const before=await group(f,id);assert.equal(before.visibility_status,'public_pending');assert.equal(before.is_platform_sponsored,0);
 const pending=await f.call('/v1/rpc/create_contribution_intent',{origin:'https://collect.example',headers:auth,data:{p_collection_id:id,p_request_id:randomUUID(),p_expected_amount_rwf:1000}});assert.equal(pending.status,200,JSON.stringify(pending));
 const data=publishBody(before.revision),key=randomUUID();assert.equal((await patch(f,staff,id,data)).status,403);
 const published=await patch(f,admin,id,data,key);assert.equal(published.status,200,JSON.stringify(published));assert.equal(published.body.version,before.revision+1);
 assert.deepEqual((await patch(f,admin,id,data,key)).body,published.body,'exact publish retry resolves the retained receipt before stale-version validation');
 const after=await group(f,id);assert.equal(after.visibility_status,'public_approved');assert.equal(after.is_platform_sponsored,1);
 for(const field of ['creator_user_id','receiver_momo_number','receiver_network','receiver_display_label'])assert.equal(after[field],before[field]);
 assert.equal((await f.db.prepare('SELECT status FROM payment_intents WHERE id=?').bind(pending.body.id).first()).status,'cancelled');
 assert.equal((await publicFeed(f)).body[0].id,id);assert.equal(await count(f,'ledger_entries'),0);
 const blocked=await f.call('/v1/rpc/update_rwanda_momo_group_profile',{origin:'https://collect.example',headers:auth,data:{p_collection_id:id,p_request_id:randomUUID(),p_group_name:'Native demotion attempt',p_group_is_public:false}});assert.equal(blocked.status,403);assert.equal(blocked.body.code,'admin_managed_group');
 const demoted=await patch(f,admin,id,{expected_version:after.revision,visibility:'private',is_platform_sponsored:true,reason:'Withdraw public visibility without unlocking receiver'});assert.equal(demoted.status,200,JSON.stringify(demoted));
 assert.equal((await publicFeed(f)).body.length,0);assert.equal((await group(f,id)).is_platform_sponsored,1);
 assert.equal((await f.call('/v1/rpc/update_rwanda_momo_group_profile',{origin:'https://collect.example',headers:auth,data:{p_collection_id:id,p_request_id:randomUUID(),p_group_name:'Native edit after demotion',p_group_is_public:true}})).status,403);
 const locked=await detail(f,admin,'payees',id);assert.equal(locked.status,200);assert.equal(locked.body.can_manage,false);assert.deepEqual(locked.body.allowed_operations,[]);
});

test('public or sponsored receivers cannot change through group/payee mutation or advertised detail operations',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember(),created=await f.operation('groups',admin.cookie,{...groupBody(member),visibility:'public_approved',is_platform_sponsored:true}),id=created.body.resource_id,before=await group(f,id);
 const changed={label:'Substituted receiver',network:'mtn_momo',momo_number_or_code:'+250788123459'};
 const direct=await patch(f,admin,id,{expected_version:1,receiver:changed,reason:'Attempt public receiver substitution'});assert.equal(direct.status,409);assert.equal(direct.body.error.code,'receiver_locked');
 for(const method of ['POST','PATCH']){const reply=await f.call('/api/admin/operations/payees'+(method==='PATCH'?'/'+id:''),{method,cookie:admin.cookie,data:{group_id:id,expected_version:1,...changed,reason:'Attempt locked payee change'},headers:{'Idempotency-Key':randomUUID()}});assert.equal(reply.status,409,JSON.stringify(reply));assert.equal(reply.body.error.code,'receiver_locked');}
 assert.equal((await patch(f,admin,id,{expected_version:1,visibility:'private',is_platform_sponsored:false,reason:'Attempt to remove permanent sponsorship'})).status,409);
 assert.deepEqual(await group(f,id),before);assert.equal(await count(f,'admin_bridge_requests'),1);assert.equal(await count(f,'request_receipts'),1);
 const groupDetail=await detail(f,admin,'groups',id);assert.equal(groupDetail.status,200);assert.ok(!groupDetail.body.allowed_operations.includes('updatePayee'));assert.ok(groupDetail.body.allowed_operations.includes('updateGroup'));
 const payeeDetail=await detail(f,admin,'payees',id);assert.equal(payeeDetail.status,200);assert.equal(payeeDetail.body.can_manage,false);assert.deepEqual(payeeDetail.body.allowed_operations,[]);
});

test('revoking publication permission at commit rolls back public creation and its retained request',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember(),beforeAudits=await count(f,'audit_log');f.setGate(async()=>f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='receivers.manage'").bind(admin.account.userId).run());
 const result=await f.operation('groups',admin.cookie,{...groupBody(member),visibility:'public_approved',is_platform_sponsored:true},randomUUID(),{'X-Test-Pause':'before_commit'});assert.equal(result.status,403,JSON.stringify(result));
 for(const table of ['collections','memberships','admin_bridge_requests','request_receipts'])assert.equal(await count(f,table),0,table);assert.equal(await count(f,'audit_log'),beforeAudits,'no publication audit after a denied commit');
});

test('a receiver or revision change at publication commit keeps the group private without an invented receipt',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember(),created=await f.operation('groups',admin.cookie,groupBody(member)),id=created.body.resource_id;
 f.setGate(async()=>f.db.prepare('UPDATE collections SET receiver_momo_number=?,revision=revision+1 WHERE id=?').bind('250788123459',id).run());
 const result=await patch(f,admin,id,publishBody(1),randomUUID(),{'X-Test-Pause':'before_commit'});assert.equal(result.status,409,JSON.stringify(result));
 const row=await group(f,id);assert.equal(row.visibility_status,'private');assert.equal(row.is_platform_sponsored,0);assert.equal(row.receiver_momo_number,'250788123459');
 assert.equal(await count(f,'admin_bridge_requests'),1);assert.equal(await count(f,'request_receipts'),1);assert.equal((await publicFeed(f)).body.length,0);
});

test('stale MFA and malformed publication combinations cannot create public effects',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember(),body=groupBody(member);
 for(const extra of [{visibility:'public_approved',is_platform_sponsored:false},{visibility:'private',is_platform_sponsored:true},{visibility:'public_pending'},{is_platform_sponsored:'true'}])assert.equal((await f.operation('groups',admin.cookie,{...body,...extra})).status,400,JSON.stringify(extra));
 // Declare an aged proof while preserving all immutable claims and database MFA guards.
 // Fresh verification above uses the real authenticator; this setup tests its expiry state.
 const original=await f.db.prepare('SELECT s.* FROM auth_sessions s JOIN admin_sessions a ON a.auth_session_id=s.id WHERE a.user_id=?').bind(admin.account.adminId).first();
 const aged=Math.floor(Date.now()/1000)-301,operation=randomUUID(),challenge=randomUUID(),sessionId=randomUUID(),token=hash(randomUUID()),cookie='__Host-collect_admin='+token;
 const factor=await f.db.prepare('SELECT * FROM auth_mfa_factors WHERE id=?').bind(original.mfa_factor_id).first(),counter=factor.last_totp_counter+1;
 await f.db.prepare("INSERT INTO auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(?,?,'admin',?,?,?)").bind(sessionId,original.user_id,aged,aged,aged+28800).run();
 await f.db.prepare('INSERT INTO admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at) VALUES(?,?,?,1,?,?,?,?)').bind(hash(token),randomUUID(),admin.account.adminId,sessionId,ORIGIN,aged,aged+28800).run();
 await f.db.prepare('INSERT INTO auth_mfa_challenges(id,user_id,session_id,factor_id,created_at,expires_at,consumed_at,consumed_operation_id) VALUES(?,?,?,?,?,?,?,?)').bind(challenge,original.user_id,sessionId,factor.id,aged-10,aged+60,aged,operation).run();
 await f.db.prepare('INSERT INTO auth_mfa_claims(operation_id,challenge_id,factor_id,user_id,session_id,totp_counter,verified_at) VALUES(?,?,?,?,?,?,?)').bind(operation,challenge,factor.id,original.user_id,sessionId,counter,aged).run();
 await f.db.prepare('UPDATE auth_mfa_factors SET last_totp_counter=? WHERE id=?').bind(counter,factor.id).run();
 await f.db.prepare('UPDATE auth_sessions SET assurance_level=2,mfa_at=?,mfa_factor_id=? WHERE id=?').bind(aged,factor.id,sessionId).run();
 await f.db.prepare('UPDATE admin_sessions SET issued_assurance_level=2,issued_mfa_at=?,issued_mfa_factor_id=? WHERE token_hash=?').bind(aged,factor.id,hash(token)).run();
 const stale=await f.operation('groups',cookie,{...body,visibility:'public_approved',is_platform_sponsored:true});assert.ok([401,403].includes(stale.status),JSON.stringify(stale));
 assert.equal(await count(f,'collections'),0);assert.equal(await count(f,'admin_bridge_requests'),0);assert.equal(await count(f,'request_receipts'),0);
});

test('withdrawing an existing public group without a sponsorship flag permanently preserves receiver protection',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember(),created=await f.operation('groups',admin.cookie,groupBody(member)),id=created.body.resource_id;
 // This state is permitted by the canonical schema and can predate this publication path.
 await f.db.prepare("UPDATE collections SET visibility_status='public_approved',is_platform_sponsored=0,revision=revision+1 WHERE id=?").bind(id).run();
 const before=await group(f,id),demoted=await patch(f,admin,id,{expected_version:before.revision,visibility:'private',reason:'Withdraw an existing public group while preserving receiver protection'});assert.equal(demoted.status,200,JSON.stringify(demoted));
 const after=await group(f,id);assert.equal(after.visibility_status,'private');assert.equal(after.is_platform_sponsored,1);assert.equal(after.receiver_momo_number,before.receiver_momo_number);
 const payee=await f.call('/api/admin/operations/payees/'+id,{method:'PATCH',cookie:admin.cookie,data:{expected_version:after.revision,label:'Different receiver',network:'mtn_momo',momo_number_or_code:'+250788123459',reason:'Attempt receiver edit after public withdrawal'},headers:{'Idempotency-Key':randomUUID()}});assert.equal(payee.status,409);assert.equal(payee.body.error.code,'receiver_locked');
 const locked=await detail(f,admin,'payees',id);assert.equal(locked.body.can_manage,false);assert.deepEqual(locked.body.allowed_operations,[]);
 const native=await f.nativeLogin(member.phone),reply=await f.call('/v1/rpc/update_rwanda_momo_group_profile',{origin:'https://collect.example',headers:{Authorization:`Bearer ${native.access_token}`},data:{p_collection_id:id,p_request_id:randomUUID(),p_group_name:'Native change after public withdrawal',p_group_is_public:false}});assert.equal(reply.status,403);assert.equal(reply.body.code,'admin_managed_group');
});

test('publication winning a concurrent private payee edit atomically prevents receiver substitution',async t=>{
 const f=await fixture(t),admin=await operator(f),member=await f.seedMember(),created=await f.operation('groups',admin.cookie,groupBody(member)),id=created.body.resource_id,before=await group(f,id);let published;
 f.setGate(async()=>{published=await patch(f,admin,id,publishBody(before.revision));assert.equal(published.status,200,JSON.stringify(published));});
 const edit=await f.call('/api/admin/operations/payees/'+id,{method:'PATCH',cookie:admin.cookie,data:{expected_version:before.revision,label:'Concurrent substitute',network:'mtn_momo',momo_number_or_code:'+250788123459',reason:'Attempt private receiver edit concurrent with publication'},headers:{'Idempotency-Key':randomUUID(),'X-Test-Pause':'before_commit'}});assert.equal(edit.status,409,JSON.stringify(edit));
 const after=await group(f,id);assert.equal(after.visibility_status,'public_approved');assert.equal(after.is_platform_sponsored,1);assert.equal(after.receiver_momo_number,before.receiver_momo_number);assert.equal(after.receiver_display_label,before.receiver_display_label);
 assert.equal(await count(f,'admin_bridge_requests'),2);assert.equal(await count(f,'request_receipts'),2);assert.equal((await publicFeed(f)).body[0].id,id);
});
