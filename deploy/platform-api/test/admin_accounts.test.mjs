import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture,PASSWORD,NEW_PASSWORD,ORIGIN,setupToken,hash} from './admin_support/fixture.mjs';
import {ownerBootstrapSql} from '../src/admin_account_support/bootstrap-owner.mjs';

test('explicit offline owner bootstrap is one atomic canonical account/link/grant transaction',async t=>{
 const f=await fixture(t),adminId=randomUUID(),principalId=randomUUID(),operationId=randomUUID();
 const prepared=await ownerBootstrapSql({password:PASSWORD,approvalReference:'controlled-owner-bootstrap-test',adminUserId:adminId,principalUserId:principalId,operationId});
 await f.db.prepare(prepared.sql).run();assert.equal(f.mail.length,0);
 const row=await f.db.prepare('SELECT * FROM admin_principal_links WHERE admin_user_id=?').bind(adminId).first();assert.equal(row.user_id,principalId);
 assert.equal((await f.db.prepare('SELECT role FROM admin_role_assignments WHERE user_id=?').bind(principalId).first()).role,'platform_owner');
 const login=await f.login({email:prepared.ownerEmail});assert.equal(login.body.user.principalId,principalId);
 const other=await ownerBootstrapSql({password:NEW_PASSWORD,approvalReference:'second-controlled-bootstrap-test',adminUserId:randomUUID(),principalUserId:randomUUID(),operationId:randomUUID()});
 await assert.rejects(f.db.prepare(other.sql).run(),/explicit_fresh_owner_bootstrap_required/);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_users').first()).n,1);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM users').first()).n,1);
});

test('password cookie has an explicit canonical principal and linked revocable session',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),login=await f.login(owner);
 for(const token of ['__Host-collect_admin=','Secure','HttpOnly','SameSite=Strict','Path=/','Max-Age=28800'])assert.ok(login.headers.get('set-cookie').includes(token));
 assert.equal(login.body.user.principalId,owner.userId);assert.equal(login.body.user.assuranceLevel,1);
 const readback=await f.call('/api/admin/auth/session',{method:'GET',cookie:login.cookie});assert.equal(readback.status,200);assert.equal(readback.body.expiresAt,login.body.expiresAt);assert.equal(readback.body.expiresAt,readback.body.user.expiresAt);
 assert.notEqual(login.body.user.sessionId,login.cookie.split('=')[1]);assert.ok(!JSON.stringify(login.body).includes(login.cookie.split('=')[1]));
 const row=await f.db.prepare('SELECT * FROM admin_sessions WHERE token_hash=?').bind(hash(login.cookie.split('=')[1])).first();
 const session=await f.db.prepare('SELECT * FROM auth_sessions WHERE id=?').bind(row.auth_session_id).first();assert.equal(session.user_id,owner.userId);assert.equal(session.surface,'admin');assert.equal(session.assurance_level,1);
 assert.equal((await f.call('/api/admin/core/overview',{method:'GET',cookie:login.cookie})).status,200);
 const unlinked=await f.seedAccount({email:'unlinked@example.com',role:'admin',linked:false}),date=new Date().toISOString(),member=randomUUID();
 await f.db.prepare('INSERT INTO users(id,email,public_id,created_at,updated_at) VALUES(?,?,?,?,?)').bind(member,unlinked.email,'099999',date,date).run();
 await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)').bind(member,'users.manage',date).run();
 assert.equal((await f.call('/api/admin/auth/login',{data:{email:unlinked.email,password:PASSWORD}})).status,401,'matching email is never an operator principal link');
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_sessions WHERE user_id=?').bind(unlinked.adminId).first()).n,0);
});

test('same-origin CSRF, duplicate cookies and client role claims are refused',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),login=await f.login(owner);
 assert.equal((await f.call('/api/admin/auth/login',{origin:'https://evil.example',data:{email:owner.email,password:PASSWORD}})).status,403);
 assert.equal((await f.call('/api/admin/auth/login',{origin:null,data:{email:owner.email,password:PASSWORD}})).status,403);
 assert.equal((await f.call('/api/admin/auth/login',{data:{email:owner.email,password:PASSWORD,role:'owner'}})).status,400);
 assert.equal((await f.call('/api/admin/auth/session',{method:'GET',cookie:login.cookie+'; '+login.cookie})).body.user,null);
 assert.equal((await f.call('/api/admin/auth/bootstrap')).status,404);
 assert.equal((await f.mf.dispatchFetch('https://wrong.collect.ikanisa.com/api/admin/auth/session',{method:'GET',headers:{Cookie:login.cookie}})).status,403);
});

test('explicit preview/production origin admission keeps each cookie session bound to its issuing host',async t=>{
 const production='https://admin.collect.ikanisa.com',f=await fixture(t,{ADMIN_ORIGINS:ORIGIN+','+production,ALLOWED_ORIGINS:ORIGIN+','+production+',https://collect.example'}),owner=await f.seedAccount(),preview=await f.login(owner);
 const cross=await f.mf.dispatchFetch(production+'/api/admin/auth/session',{method:'GET',headers:{Origin:production,Cookie:preview.cookie}});assert.equal(cross.status,200);assert.equal((await cross.json()).user,null);
 const login=await f.mf.dispatchFetch(production+'/api/admin/auth/login',{method:'POST',headers:{Origin:production,'Content-Type':'application/json','CF-Connecting-IP':'192.0.2.9'},body:JSON.stringify({email:owner.email,password:PASSWORD})});assert.equal(login.status,200);
 const cookie=login.headers.get('set-cookie').split(';')[0],session=await f.mf.dispatchFetch(production+'/api/admin/core/overview',{method:'GET',headers:{Origin:production,Cookie:cookie}});assert.equal(session.status,200);
 assert.equal((await f.call('/api/admin/auth/session',{method:'GET',cookie})).body.user,null);
});

test('real TOTP verification rotates the cookie and never exposes bearer/refresh credentials',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),login=await f.login(owner);
 assert.equal((await f.call('/api/admin/team/invite',{cookie:login.cookie,data:{email:'staff@example.com',role:'staff',displayName:'Recorded Staff'}})).status,403);
 const verified=await f.stepUp(login);assert.notEqual(verified.cookie,login.cookie);assert.equal(verified.body.user.assuranceLevel,2);
 assert.ok(!('access_token' in verified.body));assert.ok(!('refresh_token' in verified.body));
 assert.equal((await f.call('/api/admin/auth/session',{method:'GET',cookie:login.cookie})).body.user,null);
 const factor=await f.db.prepare('SELECT status,secret_ciphertext FROM auth_mfa_factors WHERE id=?').bind(verified.factor.id).first();assert.equal(factor.status,'verified');assert.ok(!factor.secret_ciphertext.includes(verified.factor.totp.secret));
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM auth_mfa_claims').first()).n,1);
 assert.equal((await f.call('/api/admin/auth/mfa/verify',{cookie:verified.cookie,data:{factor_id:verified.factor.id,challenge_id:randomUUID(),code:'000000'}})).status,401);
});

test('team GET preserves the current frontend contract and derives management from fresh real owner MFA',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),login=await f.login(owner);
 const before=await f.call('/api/admin/team',{method:'GET',cookie:login.cookie});assert.equal(before.status,200,JSON.stringify(before));assert.equal(before.body.currentEmail,owner.email);assert.equal(before.body.canManage,false);
 assert.deepEqual(Object.keys(before.body.permissionsByRole).sort(),['admin','owner','staff']);assert.ok(before.body.permissionsByRole.owner.includes('admin_users.manage'));assert.ok(!before.body.permissionsByRole.staff.includes('users.manage'));
 assert.equal(before.body.members[0].id,owner.adminId);assert.equal(before.body.members[0].email,owner.email);
 const verified=await f.stepUp(login),after=await f.call('/api/admin/team',{method:'GET',cookie:verified.cookie});assert.equal(after.status,200);assert.equal(after.body.canManage,true);
 await f.db.prepare("DELETE FROM admin_grants WHERE user_id=? AND permission='admin_users.manage'").bind(owner.userId).run();
 const denied=await f.call('/api/admin/team',{method:'GET',cookie:verified.cookie});assert.equal(denied.status,200);assert.equal(denied.body.canManage,false,'owner label alone cannot advertise revoked authority');
 const other=await f.seedAccount({email:'manager@example.com',role:'admin'}),manager=await f.login(other),read=await f.call('/api/admin/team',{method:'GET',cookie:manager.cookie});assert.equal(read.status,200);assert.equal(read.body.currentEmail,other.email);assert.equal(read.body.canManage,false);
});

test('logout revokes only the captured cookie session and its canonical partner',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),old=await f.login(owner),current=await f.login(owner);
 const previous=await f.db.prepare('SELECT auth_session_id FROM admin_sessions WHERE token_hash=?').bind(hash(old.cookie.split('=')[1])).first();
 assert.equal((await f.call('/api/admin/auth/logout',{cookie:old.cookie})).status,200);
 assert.ok((await f.db.prepare('SELECT revoked_at FROM auth_sessions WHERE id=?').bind(previous.auth_session_id).first()).revoked_at);
 assert.ok((await f.call('/api/admin/auth/session',{method:'GET',cookie:current.cookie})).body.user);
});

test('password change revokes all linked cookie and canonical admin sessions',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),one=await f.login(owner),two=await f.login(owner);
 const changed=await f.call('/api/admin/auth/change-password',{cookie:one.cookie,data:{currentPassword:PASSWORD,newPassword:NEW_PASSWORD}});assert.equal(changed.status,200,JSON.stringify(changed));
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_sessions WHERE user_id=?').bind(owner.adminId).first()).n,0);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM auth_sessions WHERE user_id=? AND revoked_at IS NULL').bind(owner.userId).first()).n,0);
 assert.equal((await f.call('/api/admin/auth/session',{method:'GET',cookie:two.cookie})).body.user,null);
 assert.equal((await f.call('/api/admin/auth/login',{data:{email:owner.email,password:NEW_PASSWORD}})).status,200);
});

test('reset mail acceptance binds a single-use versioned hash and concurrent completion admits once',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),login=await f.login(owner);
 const forgot=await f.call('/api/admin/auth/forgot-password',{data:{email:owner.email}});assert.equal(forgot.status,202);
 for(let attempt=0;attempt<60;attempt++){if((await f.db.prepare("SELECT count(*) AS n FROM admin_challenges WHERE delivery_status='accepted'").first()).n)break;await new Promise(r=>setTimeout(r,20));}
 assert.equal(f.mail.length,1);const token=setupToken(f.mail[0]),row=await f.db.prepare('SELECT * FROM admin_challenges').first();assert.equal(row.token_hash,hash(token));assert.ok(!JSON.stringify(row).includes(token));
 const results=await Promise.all([1,2].map(()=>f.call('/api/admin/auth/complete-password',{data:{token,password:NEW_PASSWORD,invite:false}})));
 assert.deepEqual(results.map(v=>v.status).sort(),[200,400]);assert.equal((await f.call('/api/admin/auth/session',{method:'GET',cookie:login.cookie})).body.user,null);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_account_audit WHERE action=?').bind('password_reset').first()).n,1);
});

test('owner-approved team invitation creates a separate explicit principal without email matching',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),login=await f.login(owner),verified=await f.stepUp(login),member=await f.seedMember();
 await f.db.prepare('UPDATE users SET email=? WHERE id=?').bind('staff@example.com',member.id).run();
 const result=await f.call('/api/admin/team/invite',{cookie:verified.cookie,data:{email:'staff@example.com',role:'staff',displayName:'Recorded Staff'}});assert.equal(result.status,201,JSON.stringify(result));
 const duplicate=await f.call('/api/admin/team/invite',{cookie:verified.cookie,data:{email:'staff@example.com',role:'staff',displayName:'Recorded Staff'}});assert.equal(duplicate.status,409);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM admin_account_audit WHERE action='invitation_created'").first()).n,1,'losing invitation cannot record success');
 const invited=await f.db.prepare("SELECT * FROM admin_users WHERE email='staff@example.com'").first(),link=await f.db.prepare('SELECT * FROM admin_principal_links WHERE admin_user_id=?').bind(invited.id).first();
 assert.notEqual(link.user_id,member.id);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_grants WHERE user_id=?').bind(link.user_id).first()).n,0);
 assert.match(f.mail.at(-1).text,/#\/admin\/login/);assert.ok(!/setup\?|token=/.test(f.mail.at(-1).text));
 const challenge=await f.call('/api/admin/auth/otp',{data:{email:'staff@example.com'}});assert.equal(challenge.status,202,JSON.stringify(challenge));
 const code=f.mail.at(-1).text.match(/\n\n([0-9]{6})\n\n/)[1];
 const staff=await f.call('/api/admin/auth/verify',{data:{email:'staff@example.com',challenge_id:challenge.body.challenge_id,code}});assert.equal(staff.status,200,JSON.stringify(staff));assert.equal(staff.body.user.role,'staff');assert.ok(!staff.body.user.permissions.includes('users.manage'));assert.ok(!staff.body.user.permissions.includes('payments.reconcile'));
 assert.equal((await f.call('/api/admin/team/invite',{cookie:staff.cookie,data:{email:'other@example.com',role:'staff'}})).status,403);
 assert.equal((await f.call(`/api/admin/team/${invited.id}/revoke`,{cookie:verified.cookie})).status,200);
 assert.equal((await f.call('/api/admin/auth/session',{method:'GET',cookie:staff.cookie})).body.user,null);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM auth_sessions WHERE user_id=? AND revoked_at IS NULL').bind(link.user_id).first()).n,0);
});

test('missing or local email service reports unconfirmed delivery with no credential log/activation',async t=>{
 const f=await fixture(t,{TEST_EMAIL:false}),owner=await f.seedAccount(),verified=await f.stepUp(await f.login(owner));
 const result=await f.call('/api/admin/team/invite',{cookie:verified.cookie,data:{email:'pending@example.com',role:'admin',displayName:'Pending Operator'}});assert.equal(result.status,503);assert.equal(result.body.error.code,'email_unavailable');
 const user=await f.db.prepare("SELECT * FROM admin_users WHERE email='pending@example.com'").first();assert.equal(user.status,'invited');assert.equal(user.password_hash,null);assert.equal((await f.db.prepare('SELECT status FROM admin_email_events WHERE user_id=?').bind(user.id).first()).status,'failed');
 assert.equal((await f.call('/api/admin/auth/login',{data:{email:user.email,password:PASSWORD}})).status,401);
});

test('revocation during awaited password verification prevents linked session admission atomically',async t=>{
 const f=await fixture(t),owner=await f.seedAccount();f.setGate(async()=>f.db.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1 WHERE id=?").bind(owner.adminId).run());
 const result=await f.call('/api/admin/auth/login',{data:{email:owner.email,password:PASSWORD},headers:{'X-Test-Pause':'before_commit'}});assert.equal(result.status,401,JSON.stringify(result));
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_sessions').first()).n,0);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM auth_sessions').first()).n,0);
});
