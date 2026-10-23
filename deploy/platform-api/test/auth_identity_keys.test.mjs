import assert from 'node:assert/strict';
import {test} from 'node:test';
import {createHmac,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {identityKeyRing,identityHashes,LEGACY_IDENTITY_KEY_ID} from '../src/identity_keys.js';
import {fixture} from './support/auth_fixture.mjs';
const require=createRequire(import.meta.url);
const {unstable_splitSqlQuery}=require(process.env.COLLECT_WRANGLER_MODULE??'wrangler');
const oldSecret='controlled-legacy-identity-and-code-secret-not-a-live-key-123456';
const keyA=Buffer.alloc(32,41).toString('base64'),keyB=Buffer.alloc(32,42).toString('base64');
const keyC=Buffer.alloc(32,43).toString('base64');
const epochs={
 legacy:{AUTH_IDENTITY_KEY_ID:'',AUTH_IDENTITY_HASH_KEY:'',AUTH_IDENTITY_PREVIOUS_KEYS_JSON:''},
 one:{AUTH_IDENTITY_KEY_ID:'identity-key-a',AUTH_IDENTITY_HASH_KEY:keyA,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:''},
 two:{AUTH_IDENTITY_KEY_ID:'identity-key-b',AUTH_IDENTITY_HASH_KEY:keyB,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:JSON.stringify({'identity-key-a':keyA})},
 missing:{AUTH_IDENTITY_KEY_ID:'identity-key-b',AUTH_IDENTITY_HASH_KEY:keyB,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:''},
 rollback:{AUTH_IDENTITY_KEY_ID:'',AUTH_IDENTITY_HASH_KEY:'',AUTH_IDENTITY_PREVIOUS_KEYS_JSON:JSON.stringify({'identity-key-a':keyA,'identity-key-b':keyB})},
};
const phone='+250788123456';
const hmac=(key,text)=>createHmac('sha256',key).update(text).digest('hex');
const request=(f,epoch='legacy',extra={})=>f.call('/v1/auth/otp',
 {phone,captcha_token:randomUUID(),...extra},{'X-Test-Identity-Epoch':epoch});
const verify=(f,r,epoch,extra={})=>f.call('/v1/auth/verify',
 {phone,challenge_id:r.body.challenge_id,code:f.messages.find(m=>m.request_id===r.body.challenge_id)?.code,
  captcha_token:randomUUID(),...extra},{'X-Test-Identity-Epoch':epoch});
async function open(t,overrides={},options={}) {
 const f=await fixture({AUTH_TOKEN_HASH_SECRET:oldSecret,...overrides},{identityEpochs:epochs,...options});
 t.after(()=>f.close());return f;
}
const count=async(f,table)=>(await f.db.prepare('SELECT count(*) AS n FROM '+table).first()).n;
const releaseCooldown=f=>f.db.prepare('UPDATE auth_otp_throttles SET last_requested_at=last_requested_at-61').run();

test('identity key domains preserve exact predecessor hashes and separate configured key IDs',async()=>{
 const legacy=await identityHashes(identityKeyRing({},oldSecret),{type:'phone',value:phone});
 assert.deepEqual(legacy,[{key_id:LEGACY_IDENTITY_KEY_ID,identity_hash:hmac(oldSecret,`collect-identity-v1:phone:${phone}`)}]);
 const ring=identityKeyRing(epochs.two,oldSecret),hashes=await identityHashes(ring,{type:'phone',value:phone});
 assert.equal(ring.currentId,'identity-key-b');assert.equal(hashes.length,3);
 assert.equal(hashes.find(x=>x.key_id==='identity-key-a').identity_hash,
  hmac(Buffer.from(keyA,'base64'),`collect-identity-v2:identity-key-a:phone:${phone}`));
 assert.equal(hashes.find(x=>x.key_id==='identity-key-b').identity_hash,
  hmac(Buffer.from(keyB,'base64'),`collect-identity-v2:identity-key-b:phone:${phone}`));
 const email=await identityHashes(ring,{type:'email',value:'person@example.com'});
 assert.ok(email.every(x=>!hashes.some(h=>h.identity_hash===x.identity_hash)));
});

test('malformed, duplicate, escaped, aliased or unbounded identity key configuration fails closed',()=>{
 const bad=[{AUTH_IDENTITY_KEY_ID:'new'}, {AUTH_IDENTITY_HASH_KEY:keyA},
  {AUTH_IDENTITY_KEY_ID:LEGACY_IDENTITY_KEY_ID,AUTH_IDENTITY_HASH_KEY:keyA},
  {AUTH_IDENTITY_KEY_ID:'bad id',AUTH_IDENTITY_HASH_KEY:keyA},
  {...epochs.one,AUTH_IDENTITY_HASH_KEY:'not-base64'},
  {...epochs.one,AUTH_JWT_SECRET:String.fromCharCode(...Buffer.alloc(32,41))},
  {...epochs.one,DATA_ENCRYPTION_KEY:keyA},
  {...epochs.one,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:`{"prior":"${keyB}","prior":"${keyC}"}`},
  {...epochs.one,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:`{"p\\u0072ior":"${keyB}"}`},
  {...epochs.one,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:JSON.stringify({'identity-key-a':keyB})},
  {...epochs.one,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:JSON.stringify({prior:keyA})},
  {...epochs.one,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:JSON.stringify({a:keyB,b:keyB})},
  {...epochs.one,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:`{"prior":"${keyB}",}`},
  {...epochs.one,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:'[]'},
  {...epochs.one,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:' '.repeat(4097)},
  {...epochs.one,AUTH_IDENTITY_PREVIOUS_KEYS_JSON:JSON.stringify(Object.fromEntries(Array.from({length:9},(_,i)=>['key-'+i,Buffer.alloc(32,i+1).toString('base64')])))}];
 for(const value of bad)assert.throws(()=>identityKeyRing(value,oldSecret),error=>error.code==='auth_identity_configuration_invalid');
 const canonical=keyB.slice(0,-2)+'p=';assert.throws(()=>identityKeyRing({...epochs.one,AUTH_IDENTITY_HASH_KEY:canonical},oldSecret));
});

test('actual new challenges retain current key labels and all lookup aliases without leaking keys',async t=>{
 const f=await open(t),r=await request(f,'one');assert.equal(r.status,202,JSON.stringify(r.body));
 const c=await f.db.prepare('SELECT * FROM auth_otp_challenges').first();
 assert.equal(c.identity_key_id,'identity-key-a');assert.equal(c.identity_hash,hmac(Buffer.from(keyA,'base64'),`collect-identity-v2:identity-key-a:phone:${phone}`));
 const aliases=(await f.db.prepare('SELECT * FROM auth_identity_rate_aliases ORDER BY identity_key_id').all()).results;
 assert.deepEqual(aliases.map(x=>x.identity_key_id),['identity-key-a',LEGACY_IDENTITY_KEY_ID]);
 const retained=JSON.stringify({c,aliases,audit:(await f.db.prepare('SELECT * FROM audit_log').all()).results,response:r.body});
 for(const value of [keyA,keyB,oldSecret])assert.ok(!retained.includes(value));
 assert.equal((await verify(f,r,'one')).status,200);
});

test('an original legacy request resolves and verifies under a new identity key without re-sending',async t=>{
 const f=await open(t),id=randomUUID(),r=await request(f,'legacy',{request_id:id});assert.equal(r.status,202);
 const before=await f.db.prepare('SELECT * FROM auth_otp_challenges').first();
 assert.deepEqual((await request(f,'one',{request_id:id})).body,r.body);
 assert.equal(f.messages.length,1);assert.equal(await count(f,'auth_rate_claims'),1);
 assert.deepEqual(await f.db.prepare('SELECT * FROM auth_otp_challenges').first(),before);
 assert.equal((await verify(f,r,'one')).status,200);assert.equal((await verify(f,r,'one')).status,401);
});

test('historical keyed requests resolve across rotation and wrong identities cannot adopt them',async t=>{
 const f=await open(t),r=await request(f,'one');assert.equal(r.status,202);
 assert.deepEqual((await request(f,'two',{request_id:r.body.challenge_id})).body,r.body);
 assert.equal((await request(f,'two',{request_id:r.body.challenge_id,phone:'+250788123457'})).status,409);
 assert.equal((await verify(f,r,'two',{phone:'+250788123457'})).status,401);
 assert.equal((await verify(f,r,'two')).status,200);assert.equal(f.messages.length,1);
});

test('rotation preserves cooldown and one identity budget under concurrent current and historical writers',async t=>{
 const f=await open(t,{AUTH_OTP_IDENTITY_PER_HOUR:'2'}),one=await request(f,'one');assert.equal(one.status,202);
 assert.equal((await request(f,'two')).status,429);assert.equal(f.messages.length,1);
 await releaseCooldown(f);
 const replies=await Promise.all(['one','two','rollback','two','one'].map(epoch=>request(f,epoch)));
 assert.equal(replies.filter(r=>r.status===202).length,1,JSON.stringify(replies));
 assert.ok(replies.every(r=>r.status===202||r.status===429));
 assert.equal(await count(f,'auth_rate_claims'),2);assert.equal(f.messages.length,2);
 const after=(await f.db.prepare("SELECT sum(used) n FROM auth_rate_buckets WHERE bucket_key LIKE 'global:%'").first()).n;
 assert.equal(after,2,'refused aliases cannot spend global budget');
 await releaseCooldown(f);assert.equal((await request(f,'two')).status,429);
});

test('missing live historical keys deny new sends and verification without consuming attempts',async t=>{
 const f=await open(t),r=await request(f,'one');assert.equal(r.status,202);await releaseCooldown(f);
 const denied=await request(f,'missing');assert.equal(denied.status,503);assert.equal(denied.body.error.code,'auth_identity_key_unavailable');
 const verifyDenied=await verify(f,r,'missing');assert.equal(verifyDenied.status,503);
 assert.equal((await f.db.prepare('SELECT attempts FROM auth_otp_challenges').first()).attempts,0);
 assert.equal(f.messages.length,1);assert.equal(await count(f,'auth_rate_claims'),1);
 assert.equal((await verify(f,r,'two')).status,200);
});

test('old-format SQL admission still shares rotated cooldown, budget and cross-key challenge supersession',async t=>{
 const f=await open(t),r=await request(f,'one');assert.equal(r.status,202);
 const legacyHash=hmac(oldSecret,`collect-identity-v1:phone:${phone}`);
 const legacyWrite=async()=>{
  const id=randomUUID(),timestamp=Math.floor(Date.now()/1000),hour=Math.floor(timestamp/3600),day=Math.floor(timestamp/86400),code='123456';
  await f.db.batch([
   f.db.prepare(`INSERT INTO auth_rate_claims(request_id,identity_hash,identity_bucket,ip_bucket,global_bucket,
    requested_at,hourly_window_ends_at,daily_window_ends_at,identity_limit,ip_limit,global_limit,cooldown_seconds)
    VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`).bind(id,legacyHash,`identity:${legacyHash}:${hour}`,'controlled-old-source:'+hour,
     'global:'+day,timestamp,(hour+1)*3600,(day+1)*86400,5,30,1000,60),
   f.db.prepare(`INSERT INTO auth_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,
    code_hash,created_at,expires_at,status) VALUES(?,?,'phone',?,'member',1,?,?,?,'accepted')`)
    .bind(id,legacyHash,phone,hmac(oldSecret,`collect-otp-v1:${id}:${legacyHash}:member:${code}`),timestamp,timestamp+300)]);
  return {id,code};
 };
 await assert.rejects(legacyWrite,/auth_rate_limited/);assert.equal(await count(f,'auth_rate_claims'),1);
 await releaseCooldown(f);const old=await legacyWrite();
 assert.equal((await f.db.prepare('SELECT status FROM auth_otp_challenges WHERE id=?').bind(r.body.challenge_id).first()).status,'superseded');
 assert.equal((await verify(f,r,'one')).status,401);
 const accepted=await f.call('/v1/auth/verify',{phone,challenge_id:old.id,code:old.code,captcha_token:randomUUID()},{'X-Test-Identity-Epoch':'one'});
 assert.equal(accepted.status,200,JSON.stringify(accepted.body));
});

test('privacy no-registration authority survives identity rotation and cannot be upgraded by request replay',async t=>{
 const f=await open(t),r=await request(f,'one',{create_account:false});assert.equal(r.status,202);assert.equal(f.messages.length,0);
 assert.deepEqual((await request(f,'two',{request_id:r.body.challenge_id,create_account:false})).body,r.body);
 assert.equal((await request(f,'two',{request_id:r.body.challenge_id})).status,202);
 assert.equal((await f.db.prepare('SELECT registration_allowed FROM auth_otp_challenges').first()).registration_allowed,0);
 assert.equal((await verify(f,r,'two',{code:'123456'})).status,401);assert.equal(await count(f,'users'),0);
});

test('new alias and identity labels are retained immutable and malformed alias admissions roll back',async t=>{
 const f=await open(t),r=await request(f,'one');assert.equal(r.status,202);await releaseCooldown(f);
 await assert.rejects(f.db.prepare("UPDATE auth_otp_challenges SET identity_key_id='relabeled'").run(),/auth_identity_history_immutable/);
 await assert.rejects(f.db.prepare("UPDATE auth_rate_claims SET identity_key_id='relabeled'").run(),/auth_identity_history_immutable/);
 await assert.rejects(f.db.prepare('DELETE FROM auth_identity_rate_aliases').run(),/auth_identity_alias_immutable/);
 const claim=await f.db.prepare('SELECT * FROM auth_rate_claims').first(),aliases=JSON.parse(claim.identity_aliases_json);
 for(const malformed of [[...aliases,aliases[0]],[],[{key_id:'other',identity_hash:'a'.repeat(64)}],
  [{key_id:claim.identity_key_id,identity_hash:'z'.repeat(64)}],[{...aliases[0],extra:true}]]) {
  await assert.rejects(f.db.prepare(`INSERT INTO auth_rate_claims(request_id,identity_hash,identity_bucket,ip_bucket,global_bucket,
   requested_at,hourly_window_ends_at,daily_window_ends_at,identity_limit,ip_limit,global_limit,cooldown_seconds,identity_key_id,identity_aliases_json)
   VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).bind(randomUUID(),claim.identity_hash,claim.identity_bucket,claim.ip_bucket,claim.global_bucket,
    claim.requested_at,claim.hourly_window_ends_at,claim.daily_window_ends_at,claim.identity_limit,claim.ip_limit,claim.global_limit,
    claim.cooldown_seconds,claim.identity_key_id,JSON.stringify(malformed)).run());
 }
 assert.equal(await count(f,'auth_rate_claims'),1);assert.equal(await count(f,'auth_identity_rate_aliases'),2);
});

test('additive migration preserves populated predecessor rows and backfills their actual legacy alias',async t=>{
 const f=await open(t,{}, {migrationsThrough:10});
 const id=randomUUID(),hash='a'.repeat(64),timestamp=Math.floor(Date.now()/1000),hour=Math.floor(timestamp/3600),day=Math.floor(timestamp/86400);
 await f.db.prepare(`INSERT INTO auth_rate_claims(request_id,identity_hash,identity_bucket,ip_bucket,global_bucket,
  requested_at,hourly_window_ends_at,daily_window_ends_at,identity_limit,ip_limit,global_limit,cooldown_seconds)
  VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`).bind(id,hash,'old-identity','old-source','old-global',timestamp,(hour+1)*3600,(day+1)*86400,5,30,1000,60).run();
 await f.db.prepare(`INSERT INTO auth_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,
  code_hash,created_at,expires_at,status) VALUES(?,?,'phone',?,'member',0,?,?,?,'superseded')`)
  .bind(id,hash,phone,'b'.repeat(64),timestamp,timestamp+300).run();
 const oldClaim=await f.db.prepare('SELECT * FROM auth_rate_claims').first(),oldChallenge=await f.db.prepare('SELECT * FROM auth_otp_challenges').first();
 const sql=await readFile(new URL('../migrations/0011_auth_identity_keys.sql',import.meta.url),'utf8');
 for(const statement of unstable_splitSqlQuery(sql))await f.db.prepare(statement).run();
 const migratedClaim=await f.db.prepare('SELECT * FROM auth_rate_claims').first(),migratedChallenge=await f.db.prepare('SELECT * FROM auth_otp_challenges').first();
 assert.deepEqual(Object.fromEntries(Object.entries(migratedClaim).filter(([k])=>Object.hasOwn(oldClaim,k))),oldClaim);
 assert.deepEqual(Object.fromEntries(Object.entries(migratedChallenge).filter(([k])=>Object.hasOwn(oldChallenge,k))),oldChallenge);
 assert.equal(migratedClaim.identity_key_id,LEGACY_IDENTITY_KEY_ID);assert.equal(migratedChallenge.identity_key_id,LEGACY_IDENTITY_KEY_ID);
 const alias=await f.db.prepare('SELECT * FROM auth_identity_rate_aliases').first();
 assert.deepEqual(alias,{request_id:id,identity_key_id:LEGACY_IDENTITY_KEY_ID,identity_hash:hash,requested_at:timestamp,hourly_window_ends_at:(hour+1)*3600});
 assert.equal((await f.db.prepare('PRAGMA foreign_key_check').all()).results.length,0);
});
