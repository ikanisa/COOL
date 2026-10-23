import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture} from './admin_support/fixture.mjs';
import {totp} from './support/auth_fixture.mjs';

// Only initial principals/role grants are SQL fixtures. Every session and AAL2
// proof below comes from the actual password/OTP/enroll/challenge/verify APIs.
async function actualAdministrator(f){
 const account=await f.seedAccount({email:'authority-admin@collect-auth.invalid',role:'admin'});
 await f.db.prepare('UPDATE users SET email=? WHERE id=?').bind(account.email,account.userId).run();
 const challenge=await f.call('/v1/auth/otp',{origin:'https://collect.example',data:{email:account.email,surface:'admin',create_account:false,captcha_token:randomUUID()}});assert.equal(challenge.status,202);
 const message=f.mail.findLast(m=>m.to===account.email&&m.subject==='Your Collect sign-in code');assert.ok(message,'Native email binding observed the approved Admin code delivery');
 const code=/^Your Collect sign-in code is ([0-9]{6})\. /.exec(message.text)?.[1];assert.ok(code,'Native email carries the sign-in code');
 const verified=await f.call('/v1/auth/verify',{origin:'https://collect.example',data:{email:account.email,surface:'admin',captcha_token:randomUUID(),challenge_id:challenge.body.challenge_id,code}});assert.equal(verified.status,200);
 const auth={Authorization:'Bearer '+verified.body.access_token};
 const factor=await f.call('/v1/auth/mfa/enroll',{origin:'https://collect.example',headers:auth,data:{factor_type:'totp'}});assert.equal(factor.status,200);
 const step=await f.call('/v1/auth/mfa/challenge',{origin:'https://collect.example',headers:auth,data:{factor_id:factor.body.id}});assert.equal(step.status,200);
 const counter=Math.floor(Date.now()/30000);
 const upgraded=await f.call('/v1/auth/mfa/verify',{origin:'https://collect.example',headers:auth,data:{factor_id:factor.body.id,challenge_id:step.body.challenge_id,code:totp(factor.body.totp.secret)}});assert.equal(upgraded.status,200);
 const login=await f.login(account),cookieStep=await f.call('/api/admin/auth/mfa/challenge',{cookie:login.cookie,data:{factor_id:factor.body.id}});assert.equal(cookieStep.status,200);
 if(Math.floor(Date.now()/30000)<=counter)await new Promise(resolve=>setTimeout(resolve,(counter+1)*30000-Date.now()+40));
 const cookie=await f.call('/api/admin/auth/mfa/verify',{cookie:login.cookie,data:{factor_id:factor.body.id,challenge_id:cookieStep.body.challenge_id,code:totp(factor.body.totp.secret)}});assert.equal(cookie.status,200);
 const session=JSON.parse(Buffer.from(upgraded.body.access_token.split('.')[1],'base64url'));
 assert.equal(session.aal,'aal2');
 const retained=await f.db.prepare('SELECT assurance_level,mfa_factor_id FROM auth_sessions WHERE id=?').bind(session.session_id).first();assert.equal(retained.assurance_level,2);assert.equal(retained.mfa_factor_id,factor.body.id);
 return {account,cookie:cookie.cookie,token:upgraded.body.access_token,sessionId:session.session_id};
}
const rpc=(f,admin,target,status='suspended',extra={})=>f.call('/v1/rpc/admin_set_user_access',{origin:'https://collect.example',headers:{Authorization:'Bearer '+admin.token,...extra.headers},data:{p_user_id:target,p_access_status:status,p_request_id:extra.requestId??randomUUID()}});
const patch=(f,admin,target,status='suspended',extra={})=>f.call('/api/admin/operations/users/'+target,{method:'PATCH',cookie:admin.cookie,headers:{'Idempotency-Key':extra.key??randomUUID(),...extra.headers},data:{status,expected_version:extra.revision??1,reason:'Synthetic member access authority regression'}});
const status=(f,target)=>f.db.prepare('SELECT access_status,revision FROM users WHERE id=?').bind(target).first();
const receiptCount=async(f)=>Number((await f.db.prepare('SELECT count(*) AS n FROM request_receipts').first()).n);
async function createGroup(f,admin,owner){return f.operation('groups',admin.cookie,{title:'Authority boundary group',slug:'authority-'+randomUUID().slice(0,8),collection_type:'ikimina',owner_user_id:owner.id,receiver:{label:'Recorded synthetic receiver',network:'mtn_momo',momo_number_or_code:owner.phone},reason:'Synthetic current-owner authority boundary'});}

// One genuine dual-transport Admin setup avoids repeatedly waiting for the same
// TOTP counter. Each subcase creates its own ordinary target and request IDs.
test('generic member management protects operators and active owners through RPC and cookie paths, including atomic authority/target races',async t=>{
 const f=await fixture(t),admin=await actualAdministrator(f),owner=await f.seedAccount(),staffAccount=await f.seedAccount({email:'authority-staff@collect-auth.invalid',role:'staff'}),staff=await f.login(staffAccount);
 let phone=700;const member=()=>f.seedMember({phone:'+25078812'+String(++phone).padStart(4,'0'),name:'Synthetic authority target'});
 for(const transport of ['rpc','cookie']){
  const invoke=(target,value='suspended',extra={})=>transport==='rpc'?rpc(f,admin,target,value,extra):patch(f,admin,target,value,extra);
  const errorCode=response=>transport==='rpc'?response.body.code:response.body.error?.code;
  await t.test(transport+' denies protected platform Owner and every operator target',async()=>{
   for(const target of [owner.userId,staffAccount.userId])for(const value of ['active','suspended']){
    const before=await status(f,target),n=await receiptCount(f),r=await invoke(target,value);assert.equal(r.status,501);assert.equal(errorCode(r),'operation_unavailable');assert.deepEqual(await status(f,target),before);assert.equal(await receiptCount(f),n);
   }
  });
  await t.test(transport+' denies linked principal even if member-type marker drifted',async()=>{
   const target=await member(),linked=await f.seedAccount({email:'linked-'+transport+'@collect-auth.invalid',role:'staff',linked:false});
   await f.db.prepare('INSERT INTO admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES(?,?,?,?)').bind(linked.adminId,target.id,'controlled-negative-fixture',new Date().toISOString()).run();
   const r=await invoke(target.id);assert.equal(r.status,501);assert.equal((await status(f,target.id)).access_status,'active');
  });
  await t.test(transport+' allows ordinary member suspension/reactivation and one exact retry',async()=>{
   const target=await member(),native=await f.nativeLogin(target.phone),key=randomUUID(),requestId=randomUUID();
   const suspended=await invoke(target.id,'suspended',{key,requestId});assert.equal(suspended.status,200);assert.equal((await status(f,target.id)).access_status,'suspended');
   const n=await receiptCount(f);assert.equal((await invoke(target.id,'suspended',{key,requestId})).status,200);assert.equal(await receiptCount(f),n);
   const denied=await f.call('/v1/rpc/get_current_member_profile',{origin:'https://collect.example',headers:{Authorization:'Bearer '+native.access_token}});assert.equal(denied.status,401);assert.equal(denied.body.code,'access_revoked');
   const current=await status(f,target.id);assert.equal((await invoke(target.id,'active',{revision:current.revision})).status,200);assert.equal((await status(f,target.id)).access_status,'active');
  });
  await t.test(transport+' denies current active-group owner but allows active status',async()=>{
   const target=await member();assert.equal((await createGroup(f,admin,target)).status,200);
   const n=await receiptCount(f);assert.equal((await invoke(target.id)).status,409);assert.equal((await status(f,target.id)).access_status,'active');assert.equal(await receiptCount(f),n);
   assert.equal((await invoke(target.id,'active')).status,200);
  });
  await t.test(transport+' target ownership wins before commit: access write and receipt roll back',async()=>{
   const target=await member(),n=await receiptCount(f);let group;
   f.setGate(async()=>{group=await createGroup(f,admin,target);assert.equal(group.status,200);});
   try{const r=await invoke(target.id,'suspended',{headers:{'X-Test-Pause':'before_commit'}});assert.equal(r.status,409);assert.equal(errorCode(r),'stale_state');}finally{f.setGate(async()=>{});}
   assert.equal((await status(f,target.id)).access_status,'active');assert.equal(await receiptCount(f),n+1,'only the separately committed group-creation receipt remains');assert.ok(group.body.resource_id);
  });
  await t.test(transport+' access suspension wins first: subsequent actual group creation denies inactive owner',async()=>{
   const target=await member();assert.equal((await invoke(target.id)).status,200);const n=await receiptCount(f);
   assert.equal((await createGroup(f,admin,target)).status,409);assert.equal((await status(f,target.id)).access_status,'suspended');assert.equal(await receiptCount(f),n);
   assert.equal(Number((await f.db.prepare('SELECT count(*) AS n FROM memberships WHERE user_id=?').bind(target.id).first()).n),0);
  });
  await t.test(transport+' operator marker added during await is denied atomically',async()=>{
   const target=await member(),n=await receiptCount(f);f.setGate(async()=>f.db.prepare("UPDATE users SET member_type='operator' WHERE id=?").bind(target.id).run());
   try{assert.equal((await invoke(target.id,'suspended',{headers:{'X-Test-Pause':'before_commit'}})).status,409);}finally{f.setGate(async()=>{});}
   assert.equal((await status(f,target.id)).access_status,'active');assert.equal(await receiptCount(f),n);
  });
  await t.test(transport+' operator link added during await is denied atomically',async()=>{
   const target=await member(),linked=await f.seedAccount({email:'raced-'+transport+'@collect-auth.invalid',role:'staff',linked:false}),n=await receiptCount(f);
   f.setGate(async()=>f.db.prepare('INSERT INTO admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES(?,?,?,?)').bind(linked.adminId,target.id,'controlled-negative-race',new Date().toISOString()).run());
   try{assert.equal((await invoke(target.id,'suspended',{headers:{'X-Test-Pause':'before_commit'}})).status,409);}finally{f.setGate(async()=>{});}
   assert.equal((await status(f,target.id)).access_status,'active');assert.equal(await receiptCount(f),n);
  });
  await t.test(transport+' stale target revision rolls back access/session/receipt changes',async()=>{
   const target=await member(),n=await receiptCount(f);f.setGate(async()=>f.db.prepare('UPDATE users SET full_name=? WHERE id=?').bind('Changed during controlled wait',target.id).run());
   try{assert.equal((await invoke(target.id,'suspended',{headers:{'X-Test-Pause':'before_commit'}})).status,409);}finally{f.setGate(async()=>{});}
   assert.equal((await status(f,target.id)).access_status,'active');assert.equal(await receiptCount(f),n);
  });
  await t.test(transport+' removed actor grant before commit rolls back target and receipt',async()=>{
   const target=await member(),n=await receiptCount(f);f.setGate(async()=>f.db.prepare('DELETE FROM admin_grants WHERE user_id=? AND permission=?').bind(admin.account.userId,'users.manage').run());
   try{const r=await invoke(target.id,'suspended',{headers:{'X-Test-Pause':'before_commit'}});assert.equal(r.status,403);}finally{f.setGate(async()=>{});await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_by,granted_at) VALUES(?,?,?,?)').bind(admin.account.userId,'users.manage','controlled-grant-restoration',new Date().toISOString()).run();}
   assert.equal((await status(f,target.id)).access_status,'active');assert.equal(await receiptCount(f),n);
  });
  await t.test(transport+' committed change survives later grant revocation but stale success cannot replay',async()=>{
   const target=await member(),n=await receiptCount(f);f.setGate(async()=>f.db.prepare('DELETE FROM admin_grants WHERE user_id=? AND permission=?').bind(admin.account.userId,'users.manage').run());
   try{const r=await invoke(target.id,'suspended',{headers:{'X-Test-Pause':'lost_reply'}});assert.equal(r.status,403);}finally{f.setGate(async()=>{});await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_by,granted_at) VALUES(?,?,?,?)').bind(admin.account.userId,'users.manage','controlled-grant-restoration',new Date().toISOString()).run();}
   assert.equal((await status(f,target.id)).access_status,'suspended');assert.equal(await receiptCount(f),n+1);
  });
 }
 await t.test('unknown target has no successful receipt',async()=>{const n=await receiptCount(f);assert.equal((await rpc(f,admin,randomUUID())).status,404);assert.equal((await patch(f,admin,randomUUID())).status,404);assert.equal(await receiptCount(f),n);});
 await t.test('ordinary member bearer, Staff cookie and genuine AAL1 cookie cannot manage members',async()=>{
  const target=await member(),native=await f.nativeLogin(target.phone);
  assert.equal((await rpc(f,{token:native.access_token},target.id)).status,403);
  assert.equal((await patch(f,{cookie:staff.cookie},target.id)).status,403);
  const fresh=await f.login(admin.account);assert.equal((await patch(f,{cookie:fresh.cookie},target.id)).status,403);
  assert.equal((await status(f,target.id)).access_status,'active');
 });
 await t.test('revoked originating bearer session cannot change target',async()=>{
  const target=await member(),n=await receiptCount(f);f.setGate(async()=>f.db.prepare("UPDATE auth_sessions SET revoked_at=?,revocation_reason='controlled_security_race' WHERE id=?").bind(Math.floor(Date.now()/1000),admin.sessionId).run());
  try{assert.equal((await rpc(f,admin,target.id,'suspended',{headers:{'X-Test-Pause':'before_commit'}})).status,403);}finally{f.setGate(async()=>{});}
  assert.equal((await status(f,target.id)).access_status,'active');assert.equal(await receiptCount(f),n);
 });
});
