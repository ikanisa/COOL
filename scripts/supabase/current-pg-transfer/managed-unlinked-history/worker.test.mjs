import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../test-support/owned-pg17.mjs';
import {verifyEnvironment,verifyBinaryPins,BIN} from '../../managed-identity-provider-compat/fixture-safety.mjs';
import {nativeObservationId} from './custody.mjs';
const sha=x=>createHash('sha256').update(x).digest('hex');
const migration=new URL('../../../../supabase/migrations/20261113130900_burimunsi_native_sms_posting.sql',import.meta.url);
const expected='6fa1438824f9d5455903353573c508d697e11aabae9ec41df2d456fb0ab43d71';
const observations=new URL('../../../../supabase/migrations/20261111121000_burimunsi_private_observations.sql',import.meta.url);
const observationsExpected='df3e00ad7a5bc1f3f1f3c602989e7aa74f8da01d86f7c4d0c27cf04058d659e5';
const migrationBytes=await readFile(migration);assert.equal(sha(migrationBytes),expected);
const observationsBytes=await readFile(observations);assert.equal(sha(observationsBytes),observationsExpected);
assert.ok(observationsBytes.toString('utf8').includes("'collect.storage.entity.v1'||E'\\n'||'burimunsi.native.observation.v1'||E'\\n'||(a->>'principalUserId')||E'\\n'||p_request::text"));
const source=migrationBytes.toString('utf8'),start=source.indexOf('CREATE FUNCTION private.burimunsi_native_sms_post_candidates('),
 end=source.indexOf('REVOKE ALL ON FUNCTION private.burimunsi_native_sms_post_candidates(',start);
assert.ok(start>0&&end>start);const selector=source.slice(start,end);

test('actual native posting selector can select completed unlinked work',{timeout:120000},async t=>{
 verifyEnvironment(process.env);await verifyBinaryPins();process.env.COLLECT_SYNTHETIC_PG_BIN=BIN;
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_unlinked_worker_fixture'}),c=new pg.Client({host:f.socket,port:f.port,database:'postgres',user:'fixture_bootstrap',connectionTimeoutMillis:3000});
 c.on('error',()=>{});await c.connect();
 try{
  await c.query(`CREATE SCHEMA app;CREATE SCHEMA private;
   CREATE FUNCTION private.burimunsi_auto_jobs_guard() RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
   CREATE TABLE private.burimunsi_auto_sms_jobs(collection_id text,source_id text,transaction_id text,state text,relation text,posting_facts jsonb,posting_next_attempt_at bigint,created_at bigint);
   CREATE TABLE app.momo_transactions(id text,event_kind text,has_conflict bigint,allocation_state text);
   CREATE TABLE app.momo_financial_links(transaction_id text);`);
  await c.query(selector);
  const candidate=async({event='unknown',state='completed',relation='accepted',facts=null,allocation='not_applicable',conflict=0,linked=false,due=0}={})=>{
   await c.query('TRUNCATE private.burimunsi_auto_sms_jobs,app.momo_transactions,app.momo_financial_links');
   await c.query('INSERT INTO app.momo_transactions VALUES($1,$2,$3,$4)',['synthetic-transaction',event,conflict,allocation]);
   await c.query('INSERT INTO private.burimunsi_auto_sms_jobs VALUES($1,$2,$3,$4,$5,$6::jsonb,$7,0)',
    ['synthetic-collection','synthetic-source','synthetic-transaction',state,relation,facts===null?null:JSON.stringify(facts),due]);
   if(linked)await c.query("INSERT INTO app.momo_financial_links VALUES('synthetic-transaction')");
   const q=await c.query('SELECT private.burimunsi_native_sms_post_candidates(1) result');return q.rows[0].result;
  };
  await t.test('completed accepted unlinked job with SQL NULL posting facts is eligible',async()=>{
   assert.deepEqual(await candidate(),[{groupId:'synthetic-collection',sourceId:'synthetic-source'}]);
   assert.equal((await candidate({event:'outgoing'})).length,1);
   assert.equal((await candidate({event:'incoming_receipt',facts:{event_kind:'incoming_receipt'},allocation:'unallocated'})).length,1);
   assert.equal((await candidate({event:'incoming_receipt',facts:{event_kind:'incoming_receipt'},allocation:'not_applicable'})).length,1);
  });
  await t.test('linked, conflicting, delayed and ineligible jobs are excluded by the actual selector',async()=>{
   for(const x of [{linked:true},{conflict:1},{conflict:null},{relation:'conflict'},{state:'retry'},
    {event:'reversal'},{due:9007199254740991},{allocation:'linked',event:'incoming_receipt',facts:{event_kind:'incoming_receipt'}},
    {event:'unknown',facts:{event_kind:'unknown'}}])assert.deepEqual(await candidate(x),[]);
   await assert.rejects(c.query('SELECT private.burimunsi_native_sms_post_candidates(2)'),e=>e.code==='22023');
  });
  await t.test('source UUID derivation matches PostgreSQL expression from the actual observation migration',async()=>{
   const owner='fixture-owner',request='11111111-1111-4111-8111-111111111111';
   const q=await c.query(`WITH x AS (SELECT encode(sha256(convert_to('collect.storage.entity.v1'||E'\\n'||'burimunsi.native.observation.v1'||E'\\n'||$1||E'\\n'||$2::uuid::text,'UTF8')),'hex') h)
    SELECT substr(h,1,8)||'-'||substr(h,9,4)||'-5'||substr(h,14,3)||'-8'||substr(h,18,3)||'-'||substr(h,21,12) id FROM x`,[owner,request]);
   assert.equal(q.rows[0].id,nativeObservationId(owner,request));assert.notEqual(q.rows[0].id,nativeObservationId('different-owner',request));
  });
 }finally{await c.end();const closed=await f.close();assert.equal(closed.removed,true);await verifyBinaryPins();
  assert.equal(sha(await readFile(migration)),expected);assert.equal(sha(await readFile(observations)),observationsExpected);}
});
