import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';

const sql=await readFile(new URL('./user-id-forward-candidate.sql',import.meta.url),'utf8');
const source=await readFile(new URL('../../../supabase/migrations/20261114110000_burimunsi_native_retention_positive_links.sql',import.meta.url),'utf8');
const helper=source.match(/CREATE FUNCTION private\._burimunsi_retention_positive_links_v1\(p_subject text,p_class text\)[\s\S]*?\$fn\$;/)?.[0];
assert.ok(helper,'the previously recorded helper must be present');
const expectedAfter='f35281816661c456bc0e3e17bc0c70961bbef2160cfed729d8e0463cf79ac7a7';
const hash=s=>createHash('sha256').update(s).digest('hex');

test('forward-only retention user ID correction on owned PostgreSQL 17',{timeout:90000},async t=>{
 const fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap'});
 const bootstrap=new pg.Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'fixture_bootstrap',connectionTimeoutMillis:3000});
 let db;bootstrap.on('error',()=>{});
 try{
  await bootstrap.connect();await bootstrap.query('CREATE ROLE postgres LOGIN SUPERUSER; CREATE ROLE collect_runtime');
  db=new pg.Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'postgres',connectionTimeoutMillis:3000});db.on('error',()=>{});await db.connect();
  await db.query(`CREATE SCHEMA private;CREATE SCHEMA app;GRANT USAGE ON SCHEMA private TO collect_runtime;
   CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,mode text);
   INSERT INTO private.collect_fence_control VALUES(true,'fenced');
   CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$ BEGIN RETURN; END $$;
   CREATE FUNCTION private._collect_fence_require_runtime() RETURNS void LANGUAGE plpgsql AS $$
    BEGIN IF current_setting('role',true) IS DISTINCT FROM 'collect_runtime' OR current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true'
     THEN RAISE EXCEPTION 'collect_fence_forbidden' USING ERRCODE='42501';END IF;END $$;
   CREATE TABLE private.burimunsi_native_receipt_origins(source_id text,principal_user_id text,collection_id text);
   CREATE TABLE private.burimunsi_auto_sms_jobs(source_id text,collection_id text,transaction_id text,attempt_id text,receiving_account_id text,state text,relation text);
   CREATE TABLE app.payments(id text,member_id text,collection_id text);
   CREATE TABLE app.momo_financial_links(payment_id text,beneficiary_member_id text,transaction_id text);
   CREATE TABLE app.momo_transactions(id text,parse_attempt_id text,receiving_account_id text);
   CREATE TABLE app.momo_transaction_sources(transaction_id text,parse_attempt_id text,relation text,raw_sms_id text);
   INSERT INTO private.burimunsi_native_receipt_origins VALUES('synthetic-record','synthetic-owner','synthetic-group');`);
  await db.query(helper);
  await db.query(`REVOKE ALL ON FUNCTION private._burimunsi_retention_positive_links_v1(text,text) FROM PUBLIC;
   CREATE FUNCTION private.fixture_invoke(s text,c text) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
    AS $$ SELECT private._burimunsi_retention_positive_links_v1(s,c) $$;
   REVOKE ALL ON FUNCTION private.fixture_invoke(text,text) FROM PUBLIC;
   GRANT EXECUTE ON FUNCTION private.fixture_invoke(text,text) TO collect_runtime;`);
  const sourceHash=async()=>(await db.query("SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') AS hash FROM pg_proc WHERE oid='private._burimunsi_retention_positive_links_v1(text,text)'::regprocedure")).rows[0].hash;
  const invoke=async(subject,{role=true}={})=>{
   await db.query('BEGIN');
   try{
    if(role)await db.query('SET LOCAL ROLE collect_runtime');
    await db.query("SELECT set_config('collect.edge_verified','true',true)");
    const result=(await db.query('SELECT private.fixture_invoke($1,$2) AS value',[subject,'private:burimunsi_native_receipt_origins'])).rows[0].value;
    await db.query('ROLLBACK');return result;
   }catch(error){await db.query('ROLLBACK');throw error;}
  };
  await t.test('old UUID-only helper rejects an existing text identifier',async()=>{
   await assert.rejects(invoke('synthetic-owner'),e=>e.code==='22023'&&e.message==='burimunsi_retention_positive_invalid');
  });
  await t.test('open fence and changed function authority both fail closed',async()=>{
   await db.query("UPDATE private.collect_fence_control SET mode='open'");
   await assert.rejects(db.query(sql),e=>e.code==='55000'&&e.message==='retention_user_id_forward_precondition');await db.query('ROLLBACK');
   await db.query("UPDATE private.collect_fence_control SET mode='fenced'");
   const before=await sourceHash();await db.query('ALTER FUNCTION private._burimunsi_retention_positive_links_v1(text,text) SECURITY INVOKER');
   await assert.rejects(db.query(sql),e=>e.code==='55000'&&e.message==='retention_user_id_forward_precondition');await db.query('ROLLBACK');
   assert.equal(await sourceHash(),before);await db.query('ALTER FUNCTION private._burimunsi_retention_positive_links_v1(text,text) SECURITY DEFINER');
  });
  await t.test('forward fix retains the original access boundary and blocked disposition',async()=>{
   await db.query(sql);assert.equal(await sourceHash(),expectedAfter);
   const result=await invoke('synthetic-owner');
   assert.equal(result.complete,false);assert.equal(result.erasure,'blocked');assert.equal(result.matches.length,1);
   assert.equal(result.matches[0].relationship,'capture_principal');
   assert.equal(result.matches[0].record_key_sha256,hash('private:burimunsi_native_receipt_origins:synthetic-record'));
   assert.doesNotMatch(JSON.stringify(result),/synthetic-owner|synthetic-record/);
   await assert.rejects(invoke('bad/identifier'),e=>e.code==='22023'&&e.message==='burimunsi_retention_positive_invalid');
   await assert.rejects(invoke('synthetic-owner',{role:false}),e=>e.code==='42501'&&e.message==='collect_fence_forbidden');
  });
  await t.test('a repeated application fails without changing the recorded postimage',async()=>{
   await assert.rejects(db.query(sql),e=>e.code==='55000'&&e.message==='retention_user_id_forward_precondition');await db.query('ROLLBACK');
   assert.equal(await sourceHash(),expectedAfter);
  });
 }finally{
  await db?.end().catch(()=>{});await bootstrap.end().catch(()=>{});
  const closed=await fixture.close();assert.equal(closed.removed,true,'owned PostgreSQL cleanup must be confirmed');
 }
});
