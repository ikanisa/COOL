import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {fixture} from './support/auth_fixture.mjs';

async function open(t){const f=await fixture();t.after(()=>f.close());return f;}
const identity={phone:'+250788123456'};

test('privacy no-registration sign-in can authenticate an existing account without creating one',async t=>{
 const f=await open(t),userId=randomUUID(),date=new Date().toISOString();
 await f.db.prepare('INSERT INTO users(id,phone,public_id,created_at,updated_at) VALUES(?,?,?,?,?)')
  .bind(userId,identity.phone,'123456',date,date).run();
 const requested=await f.otp(identity,{create_account:false});assert.equal(requested.status,202,JSON.stringify(requested.body));
 const stored=await f.db.prepare('SELECT registration_allowed FROM auth_otp_challenges WHERE id=?').bind(requested.body.challenge_id).first();
 assert.equal(stored.registration_allowed,0);assert.equal(f.messages.length,1);
 const verified=await f.verify(requested,identity);assert.equal(verified.status,200,JSON.stringify(verified.body));assert.equal(verified.body.user.id,userId);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM users').first()).n,1);
});

test('an unknown account receives the same generic acknowledgement and cannot be registered by privacy verification',async t=>{
 const f=await open(t),requestId=randomUUID(),requested=await f.otp(identity,{create_account:false,request_id:requestId});
 assert.equal(requested.status,202);assert.equal(requested.body.accepted,true);assert.equal(requested.body.challenge_id,requestId);
 assert.equal(f.messages.length,0);assert.equal((await f.db.prepare('SELECT registration_allowed FROM auth_otp_challenges WHERE id=?').bind(requestId).first()).registration_allowed,0);
 const verified=await f.call('/v1/auth/verify',{...identity,challenge_id:requestId,code:'123456',captcha_token:randomUUID()});
 assert.equal(verified.status,401);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM users').first()).n,0);
 const retry=await f.otp(identity,{create_account:false,request_id:requestId});assert.deepEqual(retry.body,requested.body);assert.equal(f.messages.length,0);
});

test('a privacy replay cannot adopt a registration-enabled challenge',async t=>{
 const f=await open(t),requestId=randomUUID(),normal=await f.otp(identity,{request_id:requestId});assert.equal(normal.status,202);assert.equal(f.messages.length,1);
 const restricted=await f.otp(identity,{create_account:false,request_id:requestId});assert.equal(restricted.status,409);assert.equal(restricted.body.error.code,'request_conflict');
 assert.equal(f.messages.length,1);assert.equal((await f.db.prepare('SELECT registration_allowed FROM auth_otp_challenges WHERE id=?').bind(requestId).first()).registration_allowed,1);
});

test('concurrent ordinary and restricted requests cannot acknowledge a registration-enabled privacy attempt',async t=>{
 const f=await open(t),requestId=randomUUID();
 const [normal,restricted]=await Promise.all([f.otp(identity,{request_id:requestId}),f.otp(identity,{create_account:false,request_id:requestId})]);
 const stored=await f.db.prepare('SELECT registration_allowed FROM auth_otp_challenges WHERE id=?').bind(requestId).first();
 assert.equal(normal.status,202,JSON.stringify(normal));
 assert.equal(restricted.status,stored.registration_allowed===0?202:409,JSON.stringify({normal,restricted,stored}));
 assert.equal(f.messages.length,stored.registration_allowed===0?0:1);
 assert.equal((await f.db.prepare('SELECT count(*) AS n FROM auth_otp_challenges').first()).n,1);
});

test('registration option is an explicit boolean and never overrides disabled global registration',async t=>{
 const f=await open(t);
 for(const create_account of [null,0,1,'false',{},[]])assert.equal((await f.otp(identity,{create_account})).status,400);
 assert.equal(f.messages.length,0);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM auth_otp_challenges').first()).n,0);
 const disabled=await fixture({AUTH_MEMBER_REGISTRATION_ENABLED:'false'});t.after(()=>disabled.close());
 const r=await disabled.otp(identity,{create_account:true});assert.equal(r.status,202);assert.equal(disabled.messages.length,0);
 assert.equal((await disabled.db.prepare('SELECT registration_allowed FROM auth_otp_challenges WHERE id=?').bind(r.body.challenge_id).first()).registration_allowed,0);
});
