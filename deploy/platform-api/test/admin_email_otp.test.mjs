import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {fixture,PASSWORD,ORIGIN,hash} from './admin_support/fixture.mjs';
import {retentionSchema,retentionSnapshot} from '../src/privacy_retention_catalog.js';

const request=(f,email,extra={})=>f.call('/api/admin/auth/otp',{data:{email},...extra});
const code=message=>{const match=message.text.match(/\n\n([0-9]{6})\n\n/);assert.ok(match,'Sign-in email contains one code');return match[1];};
const verify=(f,email,challenge,otp,extra={})=>f.call('/api/admin/auth/verify',{data:{email,challenge_id:challenge.body.challenge_id,code:otp},...extra});
async function login(f,account){const challenge=await request(f,account.email);assert.equal(challenge.status,202,JSON.stringify(challenge));const result=await verify(f,account.email,challenge,code(f.mail.at(-1)));assert.equal(result.status,200,JSON.stringify(result));return result;}

test('only an approved explicitly linked Admin email receives a code; member email cannot enroll',async t=>{
 const f=await fixture(t),member=await f.seedMember();await f.db.prepare('UPDATE users SET email=? WHERE id=?').bind('member@example.com',member.id).run();
 const revoked=await f.seedAccount({email:'revoked@example.com',role:'staff',status:'revoked'});
 await f.seedAccount({email:'unlinked@example.com',role:'staff',linked:false});
 const suspended=await f.seedAccount({email:'suspended@example.com',role:'staff'});await f.db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(suspended.userId).run();
 const ungranted=await f.seedAccount({email:'ungranted@example.com',role:'staff'});await f.db.prepare('DELETE FROM admin_grants WHERE user_id=?').bind(ungranted.userId).run();
 for(const email of ['unknown@example.com','member@example.com',revoked.email,'unlinked@example.com',suspended.email,ungranted.email]){
  const result=await request(f,email);assert.equal(result.status,403,JSON.stringify(result));assert.equal(result.body.error.code,'admin_access_not_approved');assert.match(result.body.error.message,/super admin/);
 }
 assert.equal(f.mail.length,0);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_email_otp_challenges').first()).n,0);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_email_events').first()).n,0);
});

test('active approved email receives a private single-use HMAC code and AAL1 linked cookie session',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),requested=await request(f,' INFO@IKANISA.COM ');
 assert.equal(requested.status,202,JSON.stringify(requested));assert.equal(requested.body.retry_after,60);assert.equal(requested.body.expires_in,300);
 const otp=code(f.mail[0]),challenge=await f.db.prepare('SELECT * FROM admin_email_otp_challenges').first();
 assert.equal(challenge.user_id,owner.adminId);assert.equal(challenge.principal_user_id,owner.userId);assert.equal(challenge.origin,ORIGIN);
 assert.notEqual(challenge.code_hash,hash(otp));assert.ok(!JSON.stringify(requested.body).includes(otp));assert.ok(!JSON.stringify(challenge).includes(`"${otp}"`));
 const signed=await verify(f,owner.email,requested,otp);assert.equal(signed.status,200,JSON.stringify(signed));
 assert.equal(signed.body.user.principalId,owner.userId);assert.equal(signed.body.user.assuranceLevel,1);
 assert.ok(!('access_token' in signed.body));assert.ok(!('refresh_token' in signed.body));
 for(const expected of ['Secure','HttpOnly','SameSite=Strict','Path=/','Max-Age=28800'])assert.ok(signed.headers.get('set-cookie').includes(expected));
 const session=await f.call('/api/admin/auth/session',{method:'GET',cookie:signed.cookie});assert.equal(session.body.user.id,owner.adminId);
 assert.equal((await verify(f,owner.email,requested,otp)).status,401);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM auth_sessions').first()).n,1);
 assert.equal((await f.call('/api/admin/team/invite',{cookie:signed.cookie,data:{email:'staff@example.com',role:'staff'}})).status,403,'OTP does not grant real MFA');
});

test('super admin invitation emails a login link and the invited principal activates only after OTP',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),verified=await f.stepUp(await login(f,owner));
 const invited=await f.call('/api/admin/team/invite',{cookie:verified.cookie,data:{email:'staff@example.com',role:'staff',displayName:'Recorded Staff'}});
 assert.equal(invited.status,201,JSON.stringify(invited));assert.equal(invited.body.emailStatus,'accepted');
 const invitation=f.mail.at(-1);assert.equal(invitation.to,'staff@example.com');assert.ok(invitation.text.includes(`${ORIGIN}/#/admin/login`));
 assert.equal(invitation.subject,'Your invitation to Collect');assert.ok(invitation.text.startsWith('You have been invited to Collect.\n\n'));
 assert.ok(invitation.html.includes(`href="${ORIGIN}/#/admin/login"`));assert.match(invitation.html,/>Open Collect<\/a>/);
 assert.ok(!invitation.html.includes('Collect Admin'),'Invitation uses Collect branding');
 assert.ok(!/setup\?|token=|password/i.test(invitation.text));
 const pending=await f.db.prepare("SELECT * FROM admin_users WHERE email='staff@example.com'").first();assert.equal(pending.status,'invited');assert.equal(pending.password_hash,null);
 const link=await f.db.prepare('SELECT * FROM admin_principal_links WHERE admin_user_id=?').bind(pending.id).first();
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_grants WHERE user_id=?').bind(link.user_id).first()).n,0);
 const challenge=await request(f,pending.email),otp=code(f.mail.at(-1));assert.equal(challenge.status,202);
 assert.equal((await f.db.prepare('SELECT status FROM admin_users WHERE id=?').bind(pending.id).first()).status,'invited');
 const active=await verify(f,pending.email,challenge,otp);assert.equal(active.status,200,JSON.stringify(active));assert.equal(active.body.user.role,'staff');
 assert.equal(active.body.user.principalId,link.user_id);assert.equal(active.body.user.assuranceLevel,1);
 assert.ok(active.body.user.permissions.length>0);assert.ok(!active.body.user.permissions.includes('admin_users.manage'));
 const activated=await f.db.prepare('SELECT * FROM admin_users WHERE id=?').bind(pending.id).first();assert.equal(activated.password_hash,'email-otp-only');
 assert.equal(activated.auth_version,pending.auth_version+1);assert.equal(activated.status,'active');
 assert.equal((await f.call('/api/admin/auth/login',{data:{email:pending.email,password:'email-otp-only'}})).status,401,'sentinel cannot serve as a password');
 assert.equal((await f.call('/api/admin/auth/login',{data:{email:pending.email,password:PASSWORD}})).status,401);
 const realMfa=await f.stepUp(active);assert.equal(realMfa.body.user.assuranceLevel,2,'real TOTP remains available to OTP accounts');
});

test('concurrent verification admits exactly one session and invitation acceptance',async t=>{
 const f=await fixture(t),staff=await f.seedAccount({email:'new@example.com',role:'staff',status:'invited'}),requested=await request(f,staff.email),otp=code(f.mail[0]);
 const attempts=await Promise.all([verify(f,staff.email,requested,otp),verify(f,staff.email,requested,otp)]);
 assert.deepEqual(attempts.map(value=>value.status).sort(),[200,401]);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_sessions').first()).n,1);
 assert.equal((await f.db.prepare("SELECT count(*) AS n FROM admin_account_audit WHERE action='invitation_accepted'").first()).n,1);
});

test('wrong codes stop at five attempts and expired code is refused',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),requested=await request(f,owner.email),otp=code(f.mail[0]),wrong=otp==='000000'?'999999':'000000';
 for(let i=0;i<5;i++)assert.equal((await verify(f,owner.email,requested,wrong)).status,401);
 assert.equal((await verify(f,owner.email,requested,otp)).status,401);
 assert.equal((await f.db.prepare('SELECT attempts FROM admin_email_otp_challenges').first()).attempts,5);
 const other=await f.seedAccount({email:'expired@example.com',role:'staff'});
 // Wait-free clock fixture: insert a separately expired immutable challenge.
 const original=await f.db.prepare('SELECT * FROM admin_users WHERE id=?').bind(other.adminId).first();
 const id=randomUUID();await f.db.prepare(`INSERT INTO admin_email_otp_challenges(id,user_id,principal_user_id,origin,role,auth_version,challenge_version,account_status,code_hash,created_at,expires_at,delivery_status)
  VALUES(?,?,?,?,?,?,?,?,?,?,?,'accepted')`).bind(id,other.adminId,other.userId,ORIGIN,'staff',original.auth_version,original.challenge_version,'active','0'.repeat(64),Math.floor(Date.now()/1000)-400,Math.floor(Date.now()/1000)-100).run();
 assert.equal((await verify(f,other.email,{body:{challenge_id:id}},'123456')).status,401);
});

test('request cooldown is atomic and its identity timestamps cannot be changed',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),requests=await Promise.all([request(f,owner.email),request(f,owner.email)]);
 assert.deepEqual(requests.map(value=>value.status).sort(),[202,429]);assert.equal(f.mail.length,1);
 // Identity timestamps cannot be altered to bypass cooldown.
 await assert.rejects(f.db.prepare('UPDATE admin_email_otp_challenges SET created_at=created_at-61').run(),/immutable_admin_email_otp_identity/);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_email_otp_challenges').first()).n,1);
});

test('email change, role change, revocation, link change and missing grants invalidate outstanding codes',async t=>{
 const cases=[
  ['revoked',async(f,a)=>f.db.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1 WHERE id=?").bind(a.adminId).run()],
  ['email',async(f,a)=>f.db.prepare("UPDATE admin_users SET email='changed@example.com' WHERE id=?").bind(a.adminId).run()],
  ['role',async(f,a)=>f.db.prepare("UPDATE admin_users SET role='admin' WHERE id=?").bind(a.adminId).run()],
  ['principal',async(f,a)=>f.db.prepare("UPDATE users SET access_status='suspended' WHERE id=?").bind(a.userId).run()],
  ['link',async(f,a)=>f.db.prepare('DELETE FROM admin_principal_links WHERE admin_user_id=?').bind(a.adminId).run()],
  ['grants',async(f,a)=>f.db.prepare('DELETE FROM admin_grants WHERE user_id=?').bind(a.userId).run()],
 ];
 for(const [label,mutate] of cases){await t.test(label,async t=>{const f=await fixture(t),staff=await f.seedAccount({email:'staff@example.com',role:'staff'}),requested=await request(f,staff.email),otp=code(f.mail[0]);await mutate(f,staff);assert.equal((await verify(f,staff.email,requested,otp)).status,401);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_sessions').first()).n,0);});}
});

test('revocation during verification await fences the final committing batch',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),requested=await request(f,owner.email),otp=code(f.mail[0]);
 f.setGate(async()=>f.db.prepare("UPDATE admin_users SET status='revoked',auth_version=auth_version+1 WHERE id=?").bind(owner.adminId).run());
 const result=await verify(f,owner.email,requested,otp,{headers:{'X-Test-Pause':'before_commit'}});assert.equal(result.status,401,JSON.stringify(result));
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_sessions').first()).n,0);
 assert.equal((await f.db.prepare('SELECT used_at FROM admin_email_otp_challenges').first()).used_at,null,'failed admission rolls back code consumption');
});

test('OTP origin and same-origin CSRF protections hold across admitted Admin hosts',async t=>{
 const production='https://admin.collect.ikanisa.com',f=await fixture(t,{ADMIN_ORIGINS:ORIGIN+','+production}),owner=await f.seedAccount(),requested=await request(f,owner.email),otp=code(f.mail[0]);
 assert.equal((await request(f,owner.email,{origin:null})).status,403);assert.equal((await request(f,owner.email,{origin:'https://evil.example'})).status,403);
 const foreign=await f.mf.dispatchFetch(production+'/api/admin/auth/verify',{method:'POST',headers:{Origin:production,'Content-Type':'application/json'},body:JSON.stringify({email:owner.email,challenge_id:requested.body.challenge_id,code:otp})});assert.equal(foreign.status,401);
 assert.equal((await verify(f,owner.email,requested,otp)).status,200);
});

test('unconfirmed email keeps only the original challenge usable without activating an invitation',async t=>{
 const f=await fixture(t),staff=await f.seedAccount({email:'pending@example.com',role:'staff',status:'invited'});f.setEmailFailure(true);
 const requested=await request(f,staff.email);assert.equal(requested.status,503);assert.equal(requested.body.error.code,'email_delivery_unknown');assert.ok(requested.body.challenge_id);
 assert.equal((await f.db.prepare('SELECT status FROM admin_users WHERE id=?').bind(staff.adminId).first()).status,'invited');
 assert.equal((await f.db.prepare('SELECT delivery_status FROM admin_email_otp_challenges').first()).delivery_status,'unknown');
 assert.equal((await request(f,staff.email)).status,429);assert.equal(f.mail.length,1);
 assert.equal((await verify(f,staff.email,requested,code(f.mail[0]))).status,200,'an actually delivered original code can recover the unknown acknowledgement');
});

test('local email simulator and missing email binding never emit a code or sign a user in',async t=>{
 for(const overrides of [{ENVIRONMENT:'local'},{TEST_EMAIL:false}])await t.test(JSON.stringify(overrides),async t=>{
  const f=await fixture(t,overrides),owner=await f.seedAccount(),requested=await request(f,owner.email);assert.equal(requested.status,503);assert.equal(f.mail.length,0);
  assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_sessions').first()).n,0);
 });
});

test('auth17 privacy inventory isolates each explicit Admin principal and retains unconsumed OTP state',async t=>{
 const f=await fixture(t),owner=await f.seedAccount(),staff=await f.seedAccount({email:'staff@example.com',role:'staff'}),member=await f.seedMember();
 await f.db.prepare('UPDATE users SET email=? WHERE id=?').bind(staff.email,member.id).run();
 const one=await request(f,owner.email),two=await request(f,staff.email);assert.equal(one.status,202);assert.equal(two.status,202);
 const schema=await retentionSchema({DB:f.db});assert.equal(schema.profile,'auth17');
 const own=await retentionSnapshot({DB:f.db},owner.userId),other=await retentionSnapshot({DB:f.db},staff.userId),memberView=await retentionSnapshot({DB:f.db},member.id);
 assert.deepEqual(own.rows.admin_email_otp_challenges.map(row=>row.id),[one.body.challenge_id]);
 assert.deepEqual(other.rows.admin_email_otp_challenges.map(row=>row.id),[two.body.challenge_id]);
 assert.equal(own.summary.in_flight_unresolved,true);assert.equal(other.summary.in_flight_unresolved,true);
 assert.deepEqual(memberView.rows.admin_email_otp_challenges,[],'matching member email cannot capture an Admin principal inventory');
 assert.equal((await verify(f,staff.email,two,code(f.mail.at(-1)))).status,200);
 assert.equal((await retentionSnapshot({DB:f.db},staff.userId)).summary.in_flight_unresolved,false);
});
