// Synthetic records on an owned, socket-only PostgreSQL 17 cluster. No live
// Supabase, source service, device or personal data is used by this test.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomBytes,randomUUID} from 'node:crypto';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';

const hash=()=>randomBytes(32).toString('hex');
const expiry=(delta=120)=>String(Math.floor(Date.now()/1000)+delta);
function binding(){return {
 format:'collect.fixture.commissioning-binding.v1',transition_id:randomUUID(),target_project:'synthetic-project-only',
 application:'rw.ikanisa.burimunsi.gateway',role:'receiver',installation_sha256:hash(),
 source_api_sha256:hash(),source_auth_sha256:hash(),source_gateway_sha256:hash(),
 target_api_sha256:hash(),target_auth_sha256:hash(),target_gateway_sha256:hash(),
 source_account_sha256:hash(),target_primary_account_sha256:hash(),account_group_mapping_sha256:hash(),
 source_fence_sha256:hash(),target_fence_sha256:hash(),reconciliation_sha256:hash(),sealed_queue_sha256:hash(),
 queue_generation:'1',queue_revision:'7',queue_watermark:'4',target_device_key_sha256:hash(),
 approved_operator_sha256:hash(),expires_epoch:expiry()
};}
const consume=(b,r,id=randomUUID())=>({transition_id:b.transition_id,receipt_id:r.receipt_id,
 installation_sha256:b.installation_sha256,target_device_key_sha256:b.target_device_key_sha256,consume_id:id});

test('commissioning receipt transaction fixture', {timeout:120000},async t=>{
 const cluster=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_commissioning_synthetic_only'});
 const clients=[];let admin,serial=0;
 const connect=async(db,user='fixture_bootstrap')=>{
  const c=new pg.Client({host:cluster.socket,port:cluster.port,database:db,user,connectionTimeoutMillis:3000});
  c.on('error',()=>{});clients.push(c);await c.connect();return c;
 };
 try{
  admin=await connect('postgres');
  assert.deepEqual((await admin.query("SELECT inet_server_addr() IS NULL AS socket_only,current_setting('server_version_num')::int/10000 AS version")).rows[0],{socket_only:true,version:17});
  await admin.query('CREATE ROLE collect_commissioning_fixture_runtime LOGIN NOSUPERUSER NOINHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS');
  const sql=await readFile(new URL('./fixture-schema.sql',import.meta.url),'utf8');
  await t.test('installer refuses a nonfixture database',async()=>{
   await assert.rejects(admin.query(sql),{code:'55000',message:'fixture_install_refused'});
   await admin.query('ROLLBACK');
   assert.equal((await admin.query("SELECT to_regnamespace('commissioning_fixture') AS schema")).rows[0].schema,null);
  });
  const database='collect_commissioning_fixture_'+(++serial);await admin.query('CREATE DATABASE '+database);
  const owner=await connect(database);await owner.query(sql);
  const client=async()=>connect(database,'collect_commissioning_fixture_runtime');
  const run=async(c,fn,value)=>(await c.query(`SELECT commissioning_fixture.${fn}($1::jsonb) AS result`,[JSON.stringify(value)])).rows[0].result;
  const issue=async(c,b)=>run(c,'issue',b), status=async(c,b)=>run(c,'status',b), use=async(c,p)=>run(c,'consume',p);
  const conflict=e=>e.code==='23505';

  await t.test('a durable exact issue, status and one-use consumption replay consistently',async()=>{
   const c=await client(),b=binding(),r=await issue(c,b);
   assert.equal(r.format,'collect.fixture.commissioning-receipt.v1');assert.deepEqual(r.binding,b);
   assert.deepEqual(await issue(c,b),r);assert.deepEqual(await status(c,b),{state:'found',receipt:r,consumption:null});
   const req=consume(b,r),ack=await use(c,req);assert.equal(ack.state,'consumed');assert.deepEqual(await use(c,req),ack);
   assert.deepEqual(await status(c,b),{state:'found',receipt:r,consumption:ack});
   await assert.rejects(use(c,{...req,consume_id:randomUUID()}),conflict);
   await assert.rejects(use(c,{...req,receipt_id:randomUUID()}),{code:'42501'});
   await c.query('BEGIN READ ONLY');assert.equal((await status(c,b)).state,'found');await c.query('COMMIT');
  });

  await t.test('every authority and custody binding is fixed on a transition',async()=>{
   const c=await client(),b=binding();await issue(c,b);
   const fields=['account_group_mapping_sha256','approved_operator_sha256','installation_sha256','reconciliation_sha256',
    'sealed_queue_sha256','source_account_sha256','source_api_sha256','source_auth_sha256','source_fence_sha256',
    'source_gateway_sha256','target_api_sha256','target_auth_sha256','target_device_key_sha256','target_fence_sha256','target_gateway_sha256','target_primary_account_sha256'];
   for(const key of fields)await assert.rejects(issue(c,{...b,[key]:hash()}),conflict,key);
   for(const key of ['queue_generation','queue_revision','queue_watermark','expires_epoch'])
    await assert.rejects(issue(c,{...b,[key]:String(BigInt(b[key])+1n)}),conflict,key);
   await assert.rejects(issue(c,{...b,application:'rw.ikanisa.burimunsi.staff',role:'staff'}),conflict);
   await assert.rejects(status(c,{...b,source_fence_sha256:hash()}),conflict);
   for(const bad of [{...b,target_project:'rrlduytparvsjfmegalh'},{...b,unexpected:'x'},
    {...b,queue_generation:'01'},{...b,queue_watermark:3},{...b,target_auth_sha256:'bad'},
    {...b,application:'rw.ikanisa.burimunsi.staff'},{...b,transition_id:'not-uuid'}])
    await assert.rejects(issue(c,bad),{code:'22023'});
  });

  await t.test('generation and target device key cannot be reused under a different transition',async()=>{
   const c=await client(),b=binding();await issue(c,b);
   await assert.rejects(issue(c,{...binding(),installation_sha256:b.installation_sha256,queue_generation:b.queue_generation}),conflict);
   await assert.rejects(issue(c,{...binding(),target_device_key_sha256:b.target_device_key_sha256}),conflict);
  });

  await t.test('simultaneous exact issues have one durable receipt',async()=>{
   const a=await client(),c=await client(),b=binding();const [r1,r2]=await Promise.all([issue(a,b),issue(c,b)]);
   assert.deepEqual(r1,r2);
   assert.equal((await owner.query('SELECT count(*)::int AS n FROM commissioning_fixture.receipts WHERE transition_id=$1',[b.transition_id])).rows[0].n,1);
  });

  await t.test('simultaneous different bindings for one transition have exactly one winner',async()=>{
   const a=await client(),c=await client(),b=binding(),changed={...b,source_fence_sha256:hash()};
   const outcomes=await Promise.allSettled([issue(a,b),issue(c,changed)]);
   assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);assert.equal(outcomes.filter(x=>x.status==='rejected'&&conflict(x.reason)).length,1);
  });

  await t.test('simultaneous identical consumption has one durable result; different retries conflict',async()=>{
   const a=await client(),c=await client(),b=binding(),r=await issue(a,b),req=consume(b,r);
   const [x,y]=await Promise.all([use(a,req),use(c,req)]);assert.deepEqual(x,y);
   assert.equal((await owner.query('SELECT count(*)::int AS n FROM commissioning_fixture.consumptions WHERE transition_id=$1',[b.transition_id])).rows[0].n,1);
   await assert.rejects(use(c,{...req,consume_id:randomUUID()}),conflict);
  });

  await t.test('simultaneous different consumption IDs have exactly one winner',async()=>{
   const a=await client(),c=await client(),b=binding(),r=await issue(a,b);
   const outcomes=await Promise.allSettled([use(a,consume(b,r)),use(c,consume(b,r))]);
   assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);assert.equal(outcomes.filter(x=>x.status==='rejected'&&conflict(x.reason)).length,1);
  });

  await t.test('a lost acknowledgement is recovered by a separate read; absent is only a snapshot',async()=>{
   const a=await client(),c=await client(),b=binding();await a.query('BEGIN');const committed=await issue(a,b);
   assert.deepEqual(await status(c,b),{state:'absent_at_snapshot'});
   await a.query('COMMIT'); // Deliberately discard the transaction acknowledgement at the caller boundary.
   assert.deepEqual(await status(c,b),{state:'found',receipt:committed,consumption:null});
   assert.deepEqual(await issue(c,b),committed);
  });

  await t.test('rollback leaves no receipt or consumption',async()=>{
   const a=await client(),c=await client(),b=binding();await a.query('BEGIN');const r=await issue(a,b);await use(a,consume(b,r));await a.query('ROLLBACK');
   assert.deepEqual(await status(c,b),{state:'absent_at_snapshot'});
  });

  await t.test('repeatable read and serializable transactions are refused',async()=>{
   const c=await client(),b=binding();
   for(const isolation of ['REPEATABLE READ','SERIALIZABLE']){
    await c.query('BEGIN ISOLATION LEVEL '+isolation);
    await assert.rejects(issue(c,b),{code:'55000',message:'fixture_runtime_refused'});await c.query('ROLLBACK');
   }
   assert.deepEqual(await status(c,b),{state:'absent_at_snapshot'});
  });

  await t.test('expiry blocks first consumption, while an already consumed retry stays idempotent',async()=>{
   const c=await client(),b=binding(),later=binding();b.expires_epoch=expiry(2);later.expires_epoch=b.expires_epoch;
   const r=await issue(c,b),prior=await issue(c,later),req=consume(later,prior),ack=await use(c,req);
   await c.query('SELECT pg_sleep(2.2)');
   await assert.rejects(use(c,consume(b,r)),{code:'55000',message:'fixture_receipt_expired'});
   assert.deepEqual(await issue(c,b),r);assert.deepEqual(await use(c,req),ack);
   await assert.rejects(issue(c,{...binding(),expires_epoch:expiry(-1)}),{code:'22023',message:'fixture_expiry_invalid'});
   await assert.rejects(issue(c,{...binding(),expires_epoch:expiry(1000)}),{code:'22023',message:'fixture_expiry_invalid'});
  });

  await t.test('default deferred checks refuse inserts that expire before commit',async()=>{
   const c=await client(),probe=await client(),b=binding();b.expires_epoch=expiry(2);
   await c.query('BEGIN');await issue(c,b);await c.query('SELECT pg_sleep(2.2)');
   await assert.rejects(c.query('COMMIT'),{code:'55000',message:'fixture_receipt_expired'});
   assert.deepEqual(await status(probe,b),{state:'absent_at_snapshot'});
   const other=binding();other.expires_epoch=expiry(2);const r=await issue(c,other);
   await c.query('BEGIN');await use(c,consume(other,r));await c.query('SELECT pg_sleep(2.2)');
   await assert.rejects(c.query('COMMIT'),{code:'55000',message:'fixture_receipt_expired'});
   assert.deepEqual(await status(probe,other),{state:'found',receipt:r,consumption:null});
  });

  await t.test('runtime cannot read or mutate tables and owner mutations are refused by triggers',async()=>{
   const c=await client(),b=binding();await issue(c,b);
   for(const sql of ['SELECT * FROM commissioning_fixture.receipts','DELETE FROM commissioning_fixture.receipts',
    'UPDATE commissioning_fixture.receipts SET binding=binding','TRUNCATE commissioning_fixture.receipts'])
    await assert.rejects(c.query(sql),{code:'42501'});
   for(const sql of ['UPDATE commissioning_fixture.receipts SET binding=binding',
    'DELETE FROM commissioning_fixture.receipts','TRUNCATE commissioning_fixture.receipts CASCADE'])
    await assert.rejects(owner.query(sql),{code:'55000',message:'fixture_receipt_immutable'});
  });
 }finally{
  await Promise.allSettled(clients.map(c=>c.end()));
  const closed=await cluster.close();assert.equal(closed.removed,true,'owned fixture cleanup must be confirmed');
 }
});
