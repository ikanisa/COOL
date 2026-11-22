import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { AVAILABLE_PERSON_PUBLIC_ID_SQL } from '../src/core.mjs';

const root=fileURLToPath(new URL('..',import.meta.url)), stamp=Math.floor(Date.now()/1000), uuid=()=>crypto.randomUUID();
let runtime,db;const q=(sql,...values)=>db.prepare(sql).bind(...values),run=(sql,...values)=>q(sql,...values).run(),first=(sql,...values)=>q(sql,...values).first();
const fixture={owner:uuid(),app:uuid(),profileless:uuid(),generic:uuid(),direct:uuid()};
async function migrate(name) {
  const sql=await readFile(new URL(`../migrations/${name}`,import.meta.url),'utf8');
  const split=spawnSync(process.execPath,['-e',"const w=require('wrangler');process.stdout.write(JSON.stringify(w.unstable_splitSqlQuery(require('node:fs').readFileSync(0,'utf8'))));"],{cwd:root,input:sql,encoding:'utf8',timeout:15000});
  assert.equal(split.status,0,split.stderr);await db.batch(JSON.parse(split.stdout).map(sql=>db.prepare(sql)));
}
before(async()=>{
  runtime=new Miniflare(convertV4MiniflareOptions({modules:true,script:'export default { fetch(){return new Response("isolated schema");}}',compatibilityDate:'2026-10-04',d1Databases:['ADMIN_DB']}));
  db=await runtime.getD1Database('ADMIN_DB');
  for(const name of ['0001_admin_accounts.sql','0002_collect_core.sql','0003_posted_verification_guard.sql','0004_operating_actions.sql','0005_member_cloudflare.sql','0006_gateway_cloudflare.sql','0007_email_only_dispatch.sql'])await migrate(name);
  await run("INSERT INTO admin_users(id,email,role,status,created_at,updated_at) VALUES(?,'info@ikanisa.com','owner','invited',?,?)",fixture.owner,stamp,stamp);
  for(const [id,email] of [[fixture.app,'historical-app@example.com'],[fixture.profileless,'historical-incomplete@example.com'],[fixture.generic,'generic-app@example.com']])await run("INSERT INTO collect_users(id,email,status,created_by_admin_id,created_at,updated_at) VALUES(?,?,'active',?,?,?)",id,email,fixture.owner,stamp,stamp);
  // Leading-zero historical identities remain allocated before operator IDs.
  await run("INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) VALUES(?,'000000','Historical App Person',?,?)",fixture.app,stamp,stamp);
  await run("INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) VALUES(?,'123999','Collect member',?,?)",fixture.generic,stamp,stamp);
  await migrate('0008_admin_people.sql');
});
after(async()=>{await runtime?.dispose();});

test('people migration preserves existing App semantics and IDs without guessing identity links',async()=>{
  for(const id of [fixture.app,fixture.profileless])assert.deepEqual(await first('SELECT member_type,operator_admin_id FROM collect_users WHERE id=?',id),{member_type:'app',operator_admin_id:null});
  assert.equal((await first('SELECT public_id FROM collect_profiles WHERE user_id=?',fixture.app)).public_id,'000000');
  assert.equal((await first('SELECT public_id FROM collect_public_identities WHERE source_id=?',fixture.app)).public_id,'000000');
  const identities=(await q('SELECT public_id FROM collect_public_identities').all()).results;
  assert.equal(identities.length,4);assert.equal(new Set(identities.map(x=>x.public_id)).size,4);
  assert.equal((await first('SELECT display_name_recorded FROM collect_profiles WHERE user_id=?',fixture.app)).display_name_recorded,1);
  assert.equal((await first('SELECT display_name_recorded FROM collect_profiles WHERE user_id=?',fixture.generic)).display_name_recorded,0);
  assert.ok(identities.every(x=>/^[0-9]{6}$/.test(x.public_id)));
  assert.equal((await q('PRAGMA foreign_key_check').all()).results.length,0);
});

test('new operator and Collect identities share one immutable collision-safe numeric namespace',async()=>{
  const operator=uuid();await run("INSERT INTO admin_users(id,email,role,status,created_at,updated_at) VALUES(?,'staff-identity@example.com','staff','invited',?,?)",operator,stamp,stamp);
  const alias=(await first('SELECT public_id FROM collect_public_identities WHERE admin_user_id=?',operator)).public_id;
  const person=uuid();
  await run("INSERT INTO collect_users(id,email,status,member_type,created_at,updated_at) VALUES(?,'new-person@example.com','active','app',?,?)",person,stamp,stamp);
  await assert.rejects(run('INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) VALUES(?,?,?,?,?)',person,alias,'Collision must fail',stamp,stamp),/UNIQUE|constraint/);
  await run(`INSERT INTO collect_profiles(user_id,public_id,display_name,created_at,updated_at) SELECT ?,(${AVAILABLE_PERSON_PUBLIC_ID_SQL}),?,?,?`,person,'New App Person',stamp,stamp);
  const publicId=(await first('SELECT public_id FROM collect_profiles WHERE user_id=?',person)).public_id;
  assert.notEqual(alias,publicId);
  await run('UPDATE collect_users SET operator_admin_id=? WHERE id=?',operator,person);
  assert.equal((await first('SELECT public_id FROM collect_public_identities WHERE source_id=?',operator)).public_id,alias);
  await assert.rejects(run('UPDATE collect_profiles SET public_id=? WHERE user_id=?','999999',person),/immutable/);
  await assert.rejects(run('DELETE FROM collect_public_identities WHERE source_id=?',operator),/reserved/);
  assert.equal((await q('PRAGMA foreign_key_check').all()).results.length,0);
});

test('Direct classification revokes App sessions and rejects new App auth without deleting payment identity',async()=>{
  await run('INSERT INTO member_sessions(id,user_id,token_hash,refresh_hash,created_at,expires_at,refresh_until,verified_at) VALUES(?,?,?,?,?,?,?,?)',uuid(),fixture.app,'a'.repeat(64),'b'.repeat(64),stamp,stamp+60,stamp+120,stamp);
  await run("UPDATE collect_profiles SET momo_provider='mtn_momo',momo_number='0788250123',momo_pay_code='000123' WHERE user_id=?",fixture.app);
  await run("UPDATE collect_users SET member_type='direct' WHERE id=?",fixture.app);
  assert.equal((await first('SELECT count(*) AS n FROM member_sessions WHERE user_id=?',fixture.app)).n,0);
  await assert.rejects(run('INSERT INTO member_sessions(id,user_id,token_hash,refresh_hash,created_at,expires_at,refresh_until,verified_at) VALUES(?,?,?,?,?,?,?,?)',uuid(),fixture.app,'c'.repeat(64),'d'.repeat(64),stamp,stamp+60,stamp+120,stamp),/Direct members/);
  assert.deepEqual(await first('SELECT momo_number,momo_pay_code FROM collect_profiles WHERE user_id=?',fixture.app),{momo_number:'0788250123',momo_pay_code:'000123'});
  await assert.rejects(run("UPDATE collect_profiles SET momo_number='mobile' WHERE user_id=?",fixture.app),/recorded Rwanda/);
  await assert.rejects(run("UPDATE collect_profiles SET momo_pay_code='00800x' WHERE user_id=?",fixture.app),/numeric recorded/);
  await assert.rejects(run("UPDATE collect_profiles SET momo_provider='airtel_money' WHERE user_id=?",fixture.app),/does not match/);
});
