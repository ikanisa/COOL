import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fixture} from './admin_support/fixture.mjs';
import {totp} from './support/auth_fixture.mjs';

const request=(f,email)=>f.call('/api/admin/auth/otp',{data:{email}});
const messageCode=message=>{const value=message.text.match(/\n\n([0-9]{6})\n\n/)?.[1];assert.ok(value,'Isolated email fixture delivered an OTP');return value;};
const verify=(f,email,challenge,code)=>f.call('/api/admin/auth/verify',{data:{email,challenge_id:challenge.body.challenge_id,code}});
async function otpLogin(f,account){const challenge=await request(f,account.email);assert.equal(challenge.status,202);const response=await verify(f,account.email,challenge,messageCode(f.mail.at(-1)));assert.equal(response.status,200);return response;}

test('an OTP sent before an unversioned maintenance email change cannot authenticate the new recipient',async t=>{
 const f=await fixture(t),account=await f.seedAccount({email:'original-recipient@example.com',role:'staff'}),challenge=await request(f,account.email);
 assert.equal(challenge.status,202);const code=messageCode(f.mail.at(-1)),before=await f.db.prepare('SELECT auth_version,challenge_version FROM admin_users WHERE id=?').bind(account.adminId).first();
 await f.db.prepare('UPDATE admin_users SET email=? WHERE id=?').bind('new-recipient@example.com',account.adminId).run();
 const after=await f.db.prepare('SELECT auth_version,challenge_version FROM admin_users WHERE id=?').bind(account.adminId).first();assert.deepEqual(after,before,'The regression deliberately preserves both versions');
 const result=await verify(f,'new-recipient@example.com',challenge,code);assert.equal(result.status,401,'An old mailbox code must not prove ownership of a newly assigned mailbox');
 assert.equal(result.cookie,undefined);assert.equal((await verify(f,account.email,challenge,code)).status,401);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM admin_sessions').first()).n,0);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM auth_sessions').first()).n,0);
 assert.equal((await f.db.prepare('SELECT used_at FROM admin_email_otp_challenges WHERE id=?').bind(challenge.body.challenge_id).first()).used_at,null);
});

// Bind this Node contract check to the actual current Dart parser source.
// No Dart/Flutter SDK is run here. This checks the real producer's payload
// against its inspected URI constraints, rather than weakening the client.
const parserSource=await readFile(new URL('../../../lib/admin/core/cloudflare_admin_mfa.dart',import.meta.url),'utf8');
function clientUriContract(setup,user){
 const template=parserSource.match(/uri\.pathSegments\.single\s*!=\s*'([^']+)'/)?.[1];
 assert.equal(template,'Collect:${user.email}','The source-bound cross-language contract needs review if the actual parser changes');
 const parameters={secret:setup.totp.secret};
 for(const key of ['issuer','algorithm','digits','period']){
  const literal=parserSource.match(new RegExp("'"+key+"': '([^']+)'"))?.[1];assert.ok(literal,'Current parser explicitly fixes '+key);parameters[key]=literal;
 }
 const uri=new URL(setup.totp.uri);assert.equal(uri.protocol,'otpauth:');assert.equal(uri.hostname,'totp');assert.equal(uri.port,'');assert.equal(uri.username,'');assert.equal(uri.password,'');assert.equal(uri.hash,'');
 const segments=uri.pathname.split('/').filter(Boolean);assert.equal(segments.length,1);assert.equal(decodeURIComponent(segments[0]),template.replace('${user.email}',user.email));
 assert.match(setup.totp.secret,/^[A-Z2-7]{32}$/);assert.equal([...uri.searchParams].length,Object.keys(parameters).length);
 for(const [key,value]of Object.entries(parameters))assert.deepEqual(uri.searchParams.getAll(key),[value],key);
 return setup;
}

test('cookie MFA enrollment uses the authenticated Admin email under the current parser contract while its canonical principal remains separate',async t=>{
 const f=await fixture(t),account=await f.seedAccount(),login=await otpLogin(f,account);
 const principalBefore=await f.db.prepare('SELECT email,phone FROM users WHERE id=?').bind(account.userId).first();assert.deepEqual(principalBefore,{email:null,phone:null});
 const forged=await f.call('/api/admin/auth/mfa/enroll',{cookie:login.cookie,data:{factor_type:'totp',email:'forged@example.com'}});assert.equal(forged.status,400,'The request cannot choose the authenticator account label');
 const enrolled=await f.call('/api/admin/auth/mfa/enroll',{cookie:login.cookie,data:{friendly_name:'Collect Admin',factor_type:'totp'}});assert.equal(enrolled.status,200);
 clientUriContract(enrolled.body,login.body.user);
 const uri=new URL(enrolled.body.totp.uri);
 for(const mutate of [value=>{value.hostname='foreign';},value=>{value.pathname='/Collect%3Aforged%40example.com';},value=>{value.searchParams.set('issuer','Foreign');},value=>{value.searchParams.append('secret','FORGED');}]){
  const changed=new URL(uri);mutate(changed);assert.throws(()=>clientUriContract({...enrolled.body,totp:{...enrolled.body.totp,uri:changed.href}},login.body.user));
 }
 assert.deepEqual(await f.db.prepare('SELECT email,phone FROM users WHERE id=?').bind(account.userId).first(),principalBefore);
 const challenge=await f.call('/api/admin/auth/mfa/challenge',{cookie:login.cookie,data:{factor_id:enrolled.body.id}});assert.equal(challenge.status,200);
 const verified=await f.call('/api/admin/auth/mfa/verify',{cookie:login.cookie,data:{factor_id:enrolled.body.id,challenge_id:challenge.body.challenge_id,code:totp(enrolled.body.totp.secret)}});assert.equal(verified.status,200);assert.equal(verified.body.user.assuranceLevel,2);
 assert.notEqual(verified.cookie,login.cookie);assert.ok(!('access_token' in verified.body));assert.ok(!('refresh_token' in verified.body));
 assert.deepEqual(await f.db.prepare('SELECT email,phone FROM users WHERE id=?').bind(account.userId).first(),principalBefore);
});
