import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {BIN,verifyBinaryPins,verifyEnvironment} from '../managed-identity-provider-compat/fixture-safety.mjs';
const profile='a'.repeat(64),policy='b'.repeat(64),source='c'.repeat(64),admission=randomUUID();
const sql=await readFile(new URL('./synthetic-nonce-candidate.sql',import.meta.url),'utf8');
const pause=ms=>new Promise(r=>setTimeout(r,ms));

test('SMS-specific nonce SQL commits once under synthetic fenced runtime authority',{timeout:90000},async t=>{
 verifyEnvironment(process.env);await verifyBinaryPins();
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_sms_nonce_fixture'}),clients=[];
 async function connect(user){const c=new pg.Client({host:f.socket,port:f.port,database:'postgres',user});await c.connect();clients.push(c);return c;}
 try{
  assert.equal(f.bin,BIN);
  const admin=await connect('fixture_bootstrap');
  await admin.query(`CREATE ROLE postgres LOGIN NOSUPERUSER CREATEROLE;
   CREATE ROLE collect_sms_runtime NOLOGIN;CREATE ROLE fixture_gateway LOGIN NOINHERIT;CREATE ROLE fixture_outsider LOGIN NOINHERIT;
   GRANT collect_sms_runtime TO fixture_gateway WITH INHERIT FALSE,SET TRUE;ALTER DATABASE postgres OWNER TO postgres`);
  const owner=await connect('postgres'),a=await connect('fixture_gateway'),b=await connect('fixture_gateway'),outsider=await connect('fixture_outsider');
  await owner.query(`CREATE SCHEMA private;CREATE SCHEMA collect_sms;REVOKE ALL ON SCHEMA private FROM PUBLIC;
   REVOKE ALL ON SCHEMA collect_sms FROM PUBLIC;GRANT USAGE ON SCHEMA collect_sms TO collect_sms_runtime;
   CREATE TABLE private.collect_deployment_identity(profile_sha256 text NOT NULL);
   CREATE TABLE private.collect_sms_fence_admissions(admission_id uuid PRIMARY KEY,profile_sha256 text NOT NULL);
   CREATE TABLE private.fixture_valid_work(admission_id uuid PRIMARY KEY,epoch bigint,source_sha256 text,active boolean);
   CREATE FUNCTION private.collect_assert_deployment(x text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$BEGIN IF NOT EXISTS(SELECT 1 FROM private.collect_deployment_identity WHERE profile_sha256=x) THEN RAISE EXCEPTION 'identity_mismatch';END IF;RETURN true;END$$;
   CREATE FUNCTION collect_sms.work_assert_write(x uuid,e bigint,s text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$BEGIN
    IF current_setting('role',true)<>'collect_sms_runtime' OR current_setting('collect.sms_verified',true)<>'true' OR current_setting('transaction_isolation')<>'read committed' OR NOT EXISTS(SELECT 1 FROM private.fixture_valid_work WHERE admission_id=x AND epoch=e AND source_sha256=s AND active)
    THEN RAISE EXCEPTION 'fixture_fence_refused';END IF;RETURN '{"contractVersion":1}'::jsonb;END$$`);
  await owner.query('INSERT INTO private.collect_deployment_identity VALUES($1)',[profile]);
  await owner.query('INSERT INTO private.collect_sms_fence_admissions VALUES($1,$2)',[admission,profile]);
  await owner.query('INSERT INTO private.fixture_valid_work VALUES($1,1,$2,true)',[admission,source]);
  await owner.query(sql);
  const enter=async c=>{await c.query('BEGIN');await c.query('SET LOCAL ROLE collect_sms_runtime');await c.query("SELECT set_config('collect.sms_verified','true',true),set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',$2,true)",[admission,source]);};
  const claim=(c,id,p=profile,at=Date.now())=>c.query('SELECT collect_sms.consume_ingress_nonce($1,$2,$3,$4) claimed',[id,p,policy,at]);
  await t.test('wrong role, absent work, stale timestamp and wrong profile refuse',async()=>{
   await assert.rejects(outsider.query('SELECT collect_sms.consume_ingress_nonce($1,$2,$3,$4)',[randomUUID(),profile,policy,Date.now()]),e=>e.code==='42501');
   await a.query('BEGIN');await a.query('SET LOCAL ROLE collect_sms_runtime');await assert.rejects(claim(a,randomUUID()),/fixture_fence_refused/);await a.query('ROLLBACK');
   await enter(a);assert.equal((await claim(a,randomUUID(),profile,Date.now()-31000)).rows[0].claimed,false);await a.query('ROLLBACK');
   await enter(a);assert.equal((await claim(a,randomUUID(),profile,Date.now()+3000)).rows[0].claimed,false);await a.query('ROLLBACK');
   await enter(a);await assert.rejects(claim(a,randomUUID(),'d'.repeat(64)),/sms_ingress_profile_conflict/);await a.query('ROLLBACK');
  });
  await t.test('uncommitted claim rolls back and cannot manufacture durable replay state',async()=>{
   const n=randomUUID();await enter(a);assert.equal((await claim(a,n)).rows[0].claimed,true);await a.query('ROLLBACK');
   assert.equal((await owner.query('SELECT count(*)::int n FROM private.collect_sms_ingress_nonce_uses WHERE nonce=$1',[n])).rows[0].n,0);
   await enter(a);assert.equal((await claim(a,n)).rows[0].claimed,true);await a.query('COMMIT');
  });
  await t.test('two concurrent claimers serialize and only one commits true',async()=>{
   const n=randomUUID();await enter(a);await enter(b);assert.equal((await claim(a,n)).rows[0].claimed,true);
   const other=claim(b,n);void other.catch(()=>{});let blocked=false,end=Date.now()+1500;
   while(Date.now()<end&&!blocked){blocked=(await admin.query('SELECT cardinality(pg_blocking_pids($1))>0 b',[b.processID])).rows[0].b;if(!blocked)await pause(15);}
   assert.equal(blocked,true);await a.query('COMMIT');assert.equal((await other).rows[0].claimed,false);await b.query('COMMIT');
   assert.equal((await owner.query('SELECT count(*)::int n FROM private.collect_sms_ingress_nonce_uses WHERE nonce=$1',[n])).rows[0].n,1);
  });
  await t.test('gateway role cannot directly read or mutate the protected nonce table',async()=>{
   await enter(a);await assert.rejects(a.query('SELECT count(*) FROM private.collect_sms_ingress_nonce_uses'),e=>e.code==='42501');await a.query('ROLLBACK');
   await enter(a);await assert.rejects(a.query('DELETE FROM private.collect_sms_ingress_nonce_uses'),e=>e.code==='42501');await a.query('ROLLBACK');
  });
 }finally{await Promise.allSettled(clients.map(c=>c.end().catch(()=>{})));const closed=await f.close();assert.equal(closed.removed,true);await verifyBinaryPins();}
});
