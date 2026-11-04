import assert from 'node:assert/strict';
import {loadReviewedPlatformFixture} from '../../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import {connection,PostgresDatabase,initializeSqlFixture,finishSqlFixtureWork} from './fenced-postgres.js';
import {digest} from '../../domain/core.js';
import {fixtureAdminAccount,establishRecentAdminEmail,adminEmailFixtureDatabase} from './admin-email-fixture.js';

// An exclusive loopback fixture, never a managed project or provider. Fast and
// STALE_300S_ONLY cohorts use separate finite leases and must not run together
// against this same database. No clock/proof/guard function is stubbed.
export async function openAdminPasswordFixture(database){
 assert(database,'An explicit password-policy cohort database URL is mandatory; no silent skip');
 const target=new URL(database);
 assert(['postgres:','postgresql:'].includes(target.protocol)&&target.hostname==='127.0.0.1'&&
  target.pathname==='/collect_admin_email_test'&&target.username==='collect_test'&&target.password.length>0&&
  (target.port==='55439'||Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'&&['55441','55443'].includes(target.port))&&
  !target.search&&!target.hash,'Only the exclusive synthetic Admin email database is allowed');
 const fixture=await loadReviewedPlatformFixture(new URL('../../../../../',import.meta.url));
 assert.equal(fixture.rawMigrations.length,11,'This cohort requires the reviewed complete eleven-migration chain');
 assert.equal(fixture.names.length,11);
 const adminTarget=new URL(target);adminTarget.pathname='/postgres';const admin=connection(adminTarget.href);
 try{if(!(await admin`SELECT 1 FROM pg_database WHERE datname='collect_admin_email_test'`).length)
  await admin.unsafe('CREATE DATABASE collect_admin_email_test');}finally{await admin.end();}
 const sql=connection(database),setup=await sql.reserve();let installed=false;
 try{
  await setup.unsafe('DROP SCHEMA IF EXISTS api,private,app,auth,realtime CASCADE');
  await fixture.apply(text=>setup.unsafe(text),{includeAuth:true});
  const before=(await setup.unsafe(`SELECT (SELECT count(*) FROM private.collect_fence_control)::int AS control,
   (SELECT count(*) FROM private.collect_fence_admissions)::int AS admissions,
   (SELECT count(*) FROM private.collect_fence_operations)::int AS operations,
   to_regprocedure('private.assert_admin_password_change_context()') IS NOT NULL AS password_guard`))[0];
  assert.deepEqual({...before},{control:0,admissions:0,operations:0,password_guard:true},
   'Full11 fresh installation must leave the emergency controller genuinely uninitialized');
  // Managed service fields exist only in this explicit local Auth schema.
  await setup.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz, ADD COLUMN IF NOT EXISTS encrypted_password text');
  installed=true;
 }finally{setup.release();if(!installed)await sql.end();}
 try{await initializeSqlFixture(sql);}catch(error){await finishSqlFixtureWork();await sql.end();throw error;}
 let serial=0;
 async function actor({method='password',hasPassword=true,emailProof=true}={}){
  assert(['password','oauth'].includes(method));
  const auth=crypto.randomUUID(),sid=crypto.randomUUID(),principal=crypto.randomUUID(),adminId=crypto.randomUUID(),
   publicId=crypto.randomUUID(),tokenHash=await digest('synthetic-password-cookie:'+sid),origin='https://admin-password.example',
   email='password-policy-'+auth+'@example.test',stamp=new Date().toISOString(),at=Math.floor(Date.now()/1000)-30;
  await sql`INSERT INTO auth.users(id,email,email_confirmed_at,encrypted_password)
   VALUES(${auth},${email},now(),${hasPassword?'SYNTHETIC_MANAGED_HASH_NEVER_RETURNED':null})`;
  await sql`INSERT INTO auth.sessions(id,user_id,aal,not_after)VALUES(${sid},${auth},'aal1',now()+interval '1 hour')`;
  await sql`INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at)
   VALUES(${principal},${email},${String(980000+ ++serial)},'Synthetic password policy','operator',${stamp},${stamp})`;
  await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)
   VALUES(${auth},${principal},'synthetic-password-policy-local-only')`;
  await sql`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)
   VALUES(${sid},${principal},'admin',${at},${at},app.unixepoch()+3600)`;
  await sql`INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at)
   VALUES(${adminId},${email},'admin','active','!managed-supabase!','Synthetic password policy',${at},${at})`;
  await sql`INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)
   VALUES(${adminId},${principal},'synthetic-password-policy-local-only',${stamp})`;
  await sql`INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
   SELECT ${tokenHash},${publicId},${adminId},1,id,${origin},auth_at,expires_at FROM app.auth_sessions WHERE id=${sid}`;
  await sql`INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)
   VALUES(${tokenHash},${auth},${sid},'{}')`;
  await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)
   VALUES(${sid},${method},to_timestamp(${at}))`;
  const claims={sub:auth,session_id:sid,role:'authenticated',aal:'aal1',iat:at,exp:at+1800,amr:[{method,timestamp:at}]},
   rawDb=new PostgresDatabase(sql,claims),account=await fixtureAdminAccount(sql,rawDb,[adminId,tokenHash,origin,publicId]);
  let proof=null;
  if(emailProof)proof=await establishRecentAdminEmail(sql,rawDb,account);
  const db=adminEmailFixtureDatabase(rawDb,account);
  return {auth,sid,principal,adminId,publicId,tokenHash,origin,email,claims,rawDb,account,db,proof};
 }
 const status=a=>a.rawDb.prepare('SELECT private.admin_email_status(?,?,?,?) AS result')
  .bind(a.account.id,a.account.token_hash,a.account.origin,a.account.public_id).first('result');
 async function check(a,db=a.db){
  const result=await db.prepare('SELECT private.assert_admin_password_change_context() AS allowed').first();
  assert.deepEqual(result,{allowed:true});
  assert.equal(JSON.stringify(result),'{"allowed":true}','The helper returns a boolean only; no password hash or account DTO');
  return result;
 }
 return {sql,actor,check,status,wrap:(db,account)=>adminEmailFixtureDatabase(db,account),
  async close(){await finishSqlFixtureWork();await sql.end();}};
}
