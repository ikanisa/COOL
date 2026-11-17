// Isolated native PG17 tests: fresh cluster, private Unix socket, synthetic data.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import pg from '../../node_modules/pg/lib/index.js';
import {QuarantineError,planDigest,sourceSnapshotHmac,sealBatch,stageEncryptedBatch,reconcileEncryptedBatch,isSyntheticQuarantineSocket} from './quarantine.mjs';
import {startOwnedPg17} from '../test-support/owned-pg17.mjs';

const {Client}=pg;
const sha=x=>createHash('sha256').update(x).digest('hex');
const sql=readFileSync(new URL('./candidate-schema.sql',import.meta.url),'utf8');
const op='00000000-0000-4000-8000-000000000001',fenceSource='a'.repeat(64),baseline='b'.repeat(64);

test('encrypted quarantine on disposable PostgreSQL 17', {timeout:90000}, async t=>{
 const cluster=await startOwnedPg17({prefix:'collect-quarantine-',initialUser:'fixture_bootstrap',clusterName:'collect_quarantine_synthetic_only'});
 const {socket:sock,port,log}=cluster,clients=[];let admin,serial=0;
 const connect=async(db,user='postgres')=>{const c=new Client({host:sock,port,database:db,user,connectionTimeoutMillis:3000});c.on('error',()=>{});clients.push(c);await c.connect();return c;};
 try{
  assert.equal(isSyntheticQuarantineSocket(sock),true);
  assert.equal(isSyntheticQuarantineSocket('/private/tmp/collect-quarantine-Ab12/s','darwin'),true);
  assert.equal(isSyntheticQuarantineSocket('/tmp/collect-quarantine-Ab12/s','linux'),true);
  assert.equal(isSyntheticQuarantineSocket('/tmp/collect-quarantine-Ab12/s','darwin'),false);
  assert.equal(isSyntheticQuarantineSocket('/private/tmp/collect-quarantine-Ab12/s','linux'),false);
  assert.equal(isSyntheticQuarantineSocket('/tmp/collect-quarantine-Ab12/../s','linux'),false);
  assert.equal(isSyntheticQuarantineSocket('/tmp/collect-pg-transfer-Ab12/s','linux'),false);
  assert.equal(isSyntheticQuarantineSocket('/tmp/collect-quarantine-Ab12/s','win32'),false);
  assert.equal(isSyntheticQuarantineSocket('/tmp/collect-quarantine-Ab_12/s','linux'),false);
  admin=await connect('postgres','fixture_bootstrap');
  assert.deepEqual((await admin.query("SELECT inet_server_addr() IS NULL AS local,current_setting('server_version_num')::int/10000 AS version")).rows[0],{local:true,version:17});
  await admin.query('CREATE ROLE postgres LOGIN NOSUPERUSER NOINHERIT NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_runtime;CREATE ROLE audit_probe');
  await admin.query('GRANT SET ON PARAMETER log_parameter_max_length TO postgres');
  assert.deepEqual((await admin.query("SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname='postgres'")).rows[0],{rolsuper:false,rolbypassrls:false});
  async function fixture({mode='fenced',admission,expectInstallRefusal=false,databasePrefix='collect_fixture_'}={}){
   const database=databasePrefix+(++serial);await admin.query('CREATE DATABASE '+database+' OWNER postgres');const setup=await connect(database);
   await setup.query(`CREATE SCHEMA private;
    CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,project_ref text,baseline_manifest_sha256 text,source_sha256 text,epoch bigint,mode text,operation_id uuid);
    CREATE TABLE private.collect_fence_admissions(state text,uncertain_dispatches integer);
    CREATE TABLE private.collect_deployment_identity(singleton boolean PRIMARY KEY,profile_raw text,profile_sha256 text);
    ALTER DEFAULT PRIVILEGES IN SCHEMA private GRANT SELECT ON TABLES TO audit_probe;
    ALTER DEFAULT PRIVILEGES IN SCHEMA private GRANT EXECUTE ON FUNCTIONS TO audit_probe`);
   const raw='synthetic-profile';await setup.query('INSERT INTO private.collect_fence_control VALUES(true,$1,$2,$3,1,$4,$5)',['rrlduytparvsjfmegalh',baseline,fenceSource,mode,op]);
   await setup.query('INSERT INTO private.collect_deployment_identity VALUES(true,$1,$2)',[raw,sha(raw)]);
   if(admission)await setup.query('INSERT INTO private.collect_fence_admissions VALUES($1,$2)',admission);
   if(expectInstallRefusal){
    await assert.rejects(setup.query(sql),e=>e.code==='55000');await setup.query('ROLLBACK');
    assert.equal((await setup.query("SELECT to_regclass('private.collect_pg_transfer_quarantine') AS name")).rows[0].name,null);
    return {setup};
   }
   await setup.query(sql);
   const key=randomBytes(32),plaintext=Buffer.from('synthetic-private-row-and-mapping');
   const plan={format:'collect.pg-quarantine-plan.v1',project_ref:'rrlduytparvsjfmegalh',operation_id:randomUUID(),source_batch_id:randomUUID(),
    source_identity_sha256:'c'.repeat(64),source_set_sha256:'d'.repeat(64),source_snapshot_hmac:sourceSnapshotHmac(key,plaintext),
    target:{kind:'synthetic',host:sock,port,database,baseline_manifest_sha256:baseline,source_sha256:fenceSource,epoch:'1',fence_operation_id:op,profile_sha256:sha(raw)},
    relations:[{source_schema:'app',source_table:'users',target_schema:'app',target_table:'users',columns:[{source:'id',target:'id',type:'text'}],key:[{source:'id',target:'id'}],mapping_sha256:'e'.repeat(64)}]};
   const pin=planDigest(plan),envelope=sealBatch(plan,pin,plaintext,key);
   return {database,setup,key,plaintext,plan,pin,envelope,client:()=>connect(database),args:()=>({plan,expectedPlanSha256:pin,envelope,key})};
  }

  await t.test('candidate install refuses an open fence or uncertain admission',async()=>{
   await fixture({mode:'open',expectInstallRefusal:true});
   await fixture({admission:['settled',1],expectInstallRefusal:true});
   await fixture({admission:['settled',null],expectInstallRefusal:true});
  });

  await t.test('candidate installer refuses a nonfixture database even with a fenced controller',async()=>{
   await fixture({databasePrefix:'collect_nonfixture_',expectInstallRefusal:true});
  });

  await t.test('stage, exact replay and readback keep plaintext out of the result and journal',async()=>{
   const f=await fixture(),r=await stageEncryptedBatch(await f.client(),f.args());
   assert.equal(r.status,'staged');assert.equal(r.business_rows_imported,false);
   const replay=await stageEncryptedBatch(await f.client(),f.args());assert.equal(replay.status,'exact_replay');
   assert.equal((await reconcileEncryptedBatch(await f.client(),f.args())).status,'staged_receipt_verified');
   const db=(await f.setup.query('SELECT octet_length(envelope)::int AS bytes,position($1::bytea IN envelope)::int AS position FROM private.collect_pg_transfer_quarantine',[f.plaintext])).rows[0];
   assert.equal(db.bytes,f.envelope.length);assert.equal(db.position,0);
   assert.doesNotMatch(JSON.stringify({r,replay}),/synthetic-private-row|mapping/);
  });

  await t.test('authenticated owned bytes survive caller mutation between authentication and client checks',async()=>{
   const f=await fixture(),c=await f.client(),envelopeBefore=Buffer.from(f.envelope),keyBefore=Buffer.from(f.key);
   let subarrayCalled=false,mutations=0;
   Object.defineProperty(f.envelope,'subarray',{value:()=>{subarrayCalled=true;throw Error('caller subarray must not run');}});
   const params=c.connectionParameters,host=params.host;
   Object.defineProperty(params,'host',{configurable:true,get(){mutations++;f.envelope[f.envelope.length-1]^=1;f.key[0]^=1;return host;}});
   assert.equal((await stageEncryptedBatch(c,f.args())).status,'staged');
   assert.equal(mutations,1);assert.equal(subarrayCalled,false);
   const digest=(await f.setup.query("SELECT encode(sha256(envelope),'hex') AS digest FROM private.collect_pg_transfer_quarantine")).rows[0].digest;
   assert.equal(digest,sha(envelopeBefore));
   assert.equal((await reconcileEncryptedBatch(await f.client(),{...f.args(),envelope:envelopeBefore,key:keyBefore})).status,'staged_receipt_verified');
   keyBefore.fill(0);
  });

  await t.test('sealing snapshots plaintext and key before evaluating mutable plan properties',async()=>{
   const f=await fixture(),keyBefore=Buffer.from(f.key),plainBefore=Buffer.from(f.plaintext),plan=structuredClone(f.plan);let mutated=false;
   Object.defineProperty(plan.target,'host',{enumerable:true,get(){if(!mutated){mutated=true;f.key[0]^=1;f.plaintext[0]^=1;}return sock;}});
   const sealed=sealBatch(plan,f.pin,f.plaintext,f.key);assert.equal(mutated,true);
   assert.equal(sourceSnapshotHmac(keyBefore,plainBefore),f.plan.source_snapshot_hmac);
   assert.equal((await stageEncryptedBatch(await f.client(),{...f.args(),envelope:sealed,key:keyBefore})).status,'staged');
   keyBefore.fill(0);plainBefore.fill(0);
  });

  await t.test('shared, resizable and accessor-backed inputs are refused before database work',async()=>{
   const f=await fixture(),sharedEnvelope=Buffer.from(new SharedArrayBuffer(f.envelope.length)),sharedKey=Buffer.from(new SharedArrayBuffer(32));
   f.envelope.copy(sharedEnvelope);f.key.copy(sharedKey);
   await assert.rejects(stageEncryptedBatch(null,{...f.args(),envelope:sharedEnvelope}),{code:'invalid_envelope'});
   await assert.rejects(stageEncryptedBatch(null,{...f.args(),key:sharedKey}),{code:'invalid_envelope'});
   assert.throws(()=>sourceSnapshotHmac(sharedKey,f.plaintext),{code:'invalid_envelope'});
   assert.throws(()=>sealBatch(f.plan,f.pin,f.plaintext,sharedKey),{code:'invalid_envelope'});
   const resizable=new ArrayBuffer(f.envelope.length,{maxByteLength:f.envelope.length+16}),resizableEnvelope=Buffer.from(resizable);
   f.envelope.copy(resizableEnvelope);await assert.rejects(stageEncryptedBatch(null,{...f.args(),envelope:resizableEnvelope}),{code:'invalid_envelope'});
   let accessed=false;const input={...f.args()};Object.defineProperty(input,'key',{enumerable:true,get(){accessed=true;return f.key;}});
   await assert.rejects(stageEncryptedBatch(null,input),{code:'invalid_envelope'});assert.equal(accessed,false);
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
  });

  await t.test('throwing plan properties do not leak their exception text',async()=>{
   const f=await fixture(),plan=structuredClone(f.plan);
   Object.defineProperty(plan.target,'host',{enumerable:true,get(){throw Error('synthetic-sensitive-plan-error');}});
   assert.throws(()=>planDigest(plan),e=>e.code==='invalid_plan'&&!String(e).includes('synthetic-sensitive'));
   assert.throws(()=>sealBatch(plan,f.pin,f.plaintext,f.key),e=>e.code==='invalid_plan'&&!String(e).includes('synthetic-sensitive'));
   await assert.rejects(stageEncryptedBatch(null,{...f.args(),plan}),e=>e.code==='invalid_plan'&&!String(e).includes('synthetic-sensitive'));
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
  });

  await t.test('caller-created QuarantineError in plan getters is not trusted by public APIs',async()=>{
   const f=await fixture(),plan=structuredClone(f.plan),secret='synthetic-hostile-plan-error';
   Object.defineProperty(plan.target,'host',{enumerable:true,configurable:true,get(){throw new QuarantineError(secret);}});
   const safe=expected=>e=>e.code===expected&&![String(e),e.message,e.stack,JSON.stringify(e)].some(x=>String(x).includes(secret));
   assert.throws(()=>planDigest(plan),safe('invalid_plan'));
   assert.throws(()=>sealBatch(plan,f.pin,f.plaintext,f.key),safe('invalid_plan'));
   await assert.rejects(stageEncryptedBatch(null,{...f.args(),plan}),safe('invalid_plan'));
   let generated;try{planDigest({...f.plan,source_set_sha256:'x'.repeat(70000)});}catch(e){generated=e;}
   assert.equal(Object.isFrozen(generated),true);assert.throws(()=>{generated.code=secret;},TypeError);
   Object.defineProperty(plan.target,'host',{enumerable:true,configurable:true,get(){throw generated;}});
   assert.throws(()=>planDigest(plan),{code:'invalid_plan'});
  });

  await t.test('caller-created QuarantineError from a client is never rethrown or logged',async()=>{
   const f=await fixture(),c=await f.client(),original=c.query.bind(c),secret='synthetic-hostile-client-error';
   c.query=async q=>{if(q?.text?.startsWith('INSERT INTO private.collect_pg_transfer_quarantine'))throw new QuarantineError(secret);return original(q);};
   await assert.rejects(stageEncryptedBatch(c,f.args()),e=>e.code==='database_error'&&
    ![String(e),e.message,e.stack,JSON.stringify(e)].some(x=>String(x).includes(secret)));
   const d=await f.client(),prior=d.query.bind(d);
   d.query=async q=>{if(q?.text?.startsWith('INSERT INTO private.collect_pg_transfer_quarantine')){
    const hostile=Error('synthetic');Object.defineProperty(hostile,'code',{get(){throw new QuarantineError(secret);}});throw hostile;
   }return prior(q);};
   await assert.rejects(stageEncryptedBatch(d,f.args()),e=>e.code==='database_error'&&!String(e).includes(secret));
   let captured;try{planDigest({...f.plan,source_set_sha256:'x'.repeat(70000)});}catch(e){captured=e;}
   const r=await f.client(),queryBefore=r.query.bind(r);
   r.query=async q=>{if(q?.text?.startsWith('INSERT INTO private.collect_pg_transfer_quarantine'))throw captured;return queryBefore(q);};
   await assert.rejects(stageEncryptedBatch(r,f.args()),{code:'database_error'});
   const badClient=await f.client(),params=badClient.connectionParameters,host=params.host;
   Object.defineProperty(params,'host',{configurable:true,get(){throw new QuarantineError(secret);}});
   try{await assert.rejects(stageEncryptedBatch(badClient,f.args()),e=>e.code==='invalid_client'&&!String(e).includes(secret));}
   finally{Object.defineProperty(params,'host',{configurable:true,writable:true,value:host});await badClient.end();}
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
  });

  await t.test('client proxy is rejected before a prototype trap can rethrow a captured internal error',async()=>{
   const f=await fixture(),client=await f.client();let captured,trapped=0;
   try{planDigest({...f.plan,source_set_sha256:'x'.repeat(70000)});}catch(e){captured=e;}
   const proxy=new Proxy(client,{getPrototypeOf(){trapped++;throw captured;}});
   try{
    await assert.rejects(stageEncryptedBatch(proxy,f.args()),{code:'invalid_client'});
    assert.equal(trapped,0);
    assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
   }finally{await client.end();}
  });

  await t.test('uncontrolled bind logging is refused before ciphertext is sent',async()=>{
   const f=await fixture(),marker='SYNTHETIC_BIND_LOG_MARKER_7a90';
   await admin.query("ALTER ROLE postgres SET log_statement='all';ALTER ROLE postgres SET log_parameter_max_length=-1;REVOKE SET ON PARAMETER log_parameter_max_length FROM postgres");
   try{
    const probe=await f.client();await probe.query('SELECT $1::text AS synthetic_marker',[marker]);await probe.end();
    assert.equal(readFileSync(log,'utf8').includes(marker),true);
    await assert.rejects(stageEncryptedBatch(await f.client(),f.args()),{code:'parameter_logging_uncontrolled'});
    assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
    assert.equal(readFileSync(log,'utf8').includes(f.envelope.toString('hex')),false);
   }finally{
    await admin.query('ALTER ROLE postgres RESET log_statement;ALTER ROLE postgres RESET log_parameter_max_length;GRANT SET ON PARAMETER log_parameter_max_length TO postgres');
   }
  });

  await t.test('both bind-parameter logging limits are pinned before ciphertext under statement logging',async()=>{
   const f=await fixture();await admin.query("ALTER ROLE postgres SET log_statement='all';ALTER ROLE postgres SET log_parameter_max_length=-1");
   try{
    const c=await f.client();await c.query("SET log_parameter_max_length_on_error=-1");const original=c.query.bind(c);let observed=false;
    c.query=async q=>{if(q?.text?.startsWith('INSERT INTO private.collect_pg_transfer_quarantine')){
      const r=await original("SELECT current_setting('log_parameter_max_length') AS normal,current_setting('log_parameter_max_length_on_error') AS on_error");
      assert.deepEqual(r.rows[0],{normal:'0',on_error:'0'});observed=true;
     }return original(q);};
    assert.equal((await stageEncryptedBatch(c,f.args())).status,'staged');assert.equal(observed,true);
    assert.equal(readFileSync(log,'utf8').includes(f.envelope.toString('hex')),false);
   }finally{await admin.query('ALTER ROLE postgres RESET log_statement;ALTER ROLE postgres RESET log_parameter_max_length');}
  });

  await t.test('failing-row error details remain an independent ciphertext log-custody concern',async()=>{
   const f=await fixture();await admin.query("ALTER ROLE postgres SET log_statement='all';ALTER ROLE postgres SET log_parameter_max_length=-1");
   try{
    const c=await f.client(),original=c.query.bind(c);
    c.query=async q=>{
     if(q?.text?.startsWith('INSERT INTO private.collect_pg_transfer_quarantine')){
      const values=[...q.values];values[4]='0'.repeat(64);return original({...q,values});
     }
     return original(q);
    };
    await assert.rejects(stageEncryptedBatch(c,f.args()),{code:'database_error'});
    // The server can include part of a failed row in ERROR DETAIL even when
    // bind-parameter logging is disabled; never print that synthetic content.
    assert.equal(readFileSync(log,'utf8').includes(f.envelope.subarray(0,8).toString('hex')),true);
    assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
   }finally{await admin.query('ALTER ROLE postgres RESET log_statement;ALTER ROLE postgres RESET log_parameter_max_length');}
  });

  await t.test('staging overrides a session with asynchronous commit',async()=>{
   const f=await fixture(),c=await f.client();await c.query("SET synchronous_commit='off'");
   const original=c.query.bind(c);let observed=false;
   c.query=async q=>{const result=await original(q);if(q?.text?.includes("current_setting('synchronous_commit')")){
    assert.equal(result.rows[0].synchronous_commit,'on');assert.equal(result.rows[0].fsync,'on');assert.equal(result.rows[0].full_page_writes,'on');observed=true;
   }return result;};
   assert.equal((await stageEncryptedBatch(c,f.args())).status,'staged');assert.equal(observed,true);
  });

  await t.test('same operation with different contents and same source batch with new operation refuse',async()=>{
   const f=await fixture();await stageEncryptedBatch(await f.client(),f.args());
   const other=Buffer.from('different-private-payload'),plan={...f.plan,source_snapshot_hmac:sourceSnapshotHmac(f.key,other)},pin=planDigest(plan),envelope=sealBatch(plan,pin,other,f.key);
   await assert.rejects(stageEncryptedBatch(await f.client(),{plan,expectedPlanSha256:pin,envelope,key:f.key}),{code:'batch_collision'});
   const collision={...f.plan,operation_id:randomUUID()},p=planDigest(collision),e=sealBatch(collision,p,f.plaintext,f.key);
   await assert.rejects(stageEncryptedBatch(await f.client(),{plan:collision,expectedPlanSha256:p,envelope:e,key:f.key}),{code:'batch_collision'});
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,1);
  });

  await t.test('tampered envelope, wrong key and changed mapping plan refuse before write',async()=>{
   const f=await fixture(),damaged=Buffer.from(f.envelope);damaged[damaged.length-1]^=1;
   let c=await f.client();try{await assert.rejects(stageEncryptedBatch(c,{...f.args(),envelope:damaged}),{code:'envelope_authentication_failed'});}finally{await c.end();}
   c=await f.client();try{await assert.rejects(stageEncryptedBatch(c,{...f.args(),key:randomBytes(32)}),{code:'envelope_authentication_failed'});}finally{await c.end();}
   c=await f.client();try{await assert.rejects(stageEncryptedBatch(c,{...f.args(),plan:{...f.plan,source_set_sha256:'f'.repeat(64)}}),{code:'invalid_plan'});}finally{await c.end();}
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
  });

  await t.test('oversized and deeply nested plans are rejected before serialization or database access',async()=>{
   const f=await fixture();
   assert.throws(()=>planDigest({...f.plan,source_set_sha256:'x'.repeat(70000)}),{code:'invalid_plan'});
   let nested='x';for(let i=0;i<20;i++)nested=[nested];
   assert.throws(()=>planDigest({...f.plan,relations:nested}),{code:'invalid_plan'});
   assert.throws(()=>planDigest({...f.plan,relations:Array(129).fill(f.plan.relations[0])}),{code:'invalid_plan'});
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
  });

  await t.test('pre-commit interruption rolls back quarantine and receipt',async()=>{
   const f=await fixture(),c=await f.client(),original=c.query.bind(c);let interrupted=false;
   c.query=async q=>{const r=await original(q);if(q?.text?.startsWith('INSERT INTO private.collect_pg_transfer_quarantine')){interrupted=true;throw Error('synthetic interruption');}return r;};
   await assert.rejects(stageEncryptedBatch(c,f.args()),{code:'database_error'});assert.equal(interrupted,true);
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
  });

  await t.test('driver errors containing sensitive text are never returned',async()=>{
   const f=await fixture(),c=await f.client(),original=c.query.bind(c);
   c.query=async q=>{if(q?.text?.startsWith('INSERT INTO private.collect_pg_transfer_quarantine'))throw Error('synthetic-secret-in-driver-error');return original(q);};
   await assert.rejects(stageEncryptedBatch(c,f.args()),e=>e.code==='database_error'&&!JSON.stringify(e).includes('synthetic-secret'));
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
  });

  await t.test('a claimed insert without the exact stored postimage cannot commit a receipt',async()=>{
   const f=await fixture(),c=await f.client(),original=c.query.bind(c);
   c.query=async q=>q?.text?.startsWith('INSERT INTO private.collect_pg_transfer_quarantine')?{rows:[{inserted:1}]}:original(q);
   await assert.rejects(stageEncryptedBatch(c,f.args()),{code:'postimage_mismatch'});
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
  });

  await t.test('lost commit acknowledgement requires separate verified readback',async()=>{
   const f=await fixture(),c=await f.client(),original=c.query.bind(c);
   c.query=async q=>{const r=await original(q);if(q?.text==='COMMIT')throw Error('synthetic lost ack');return r;};
   await assert.rejects(stageEncryptedBatch(c,f.args()),{code:'commit_unconfirmed'});
   assert.equal((await reconcileEncryptedBatch(await f.client(),f.args())).status,'staged_receipt_verified');
   assert.equal((await stageEncryptedBatch(await f.client(),f.args())).status,'exact_replay');
  });

  await t.test('commit not sent yields absent readback without automatic retry',async()=>{
   const f=await fixture(),c=await f.client(),original=c.query.bind(c);
   c.query=async q=>{if(q?.text==='COMMIT')throw Error('synthetic lost channel');return original(q);};
   await assert.rejects(stageEncryptedBatch(c,f.args()),{code:'commit_unconfirmed'});
   assert.equal((await reconcileEncryptedBatch(await f.client(),f.args())).status,'receipt_absent_at_readback');
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
  });

  await t.test('two concurrent same-operation calls serialize to stage and replay',async()=>{
   const f=await fixture(),a=await f.client(),b=await f.client(),original=a.query.bind(a);
   let release,started;const gate=new Promise(r=>release=r),entered=new Promise(r=>started=r);
   a.query=async q=>{const r=await original(q);if(q?.text?.startsWith('INSERT INTO private.collect_pg_transfer_quarantine')){started();await gate;}return r;};
   const first=stageEncryptedBatch(a,f.args());await entered;let finished=false;
   const second=stageEncryptedBatch(b,f.args()).finally(()=>{finished=true;});
   await new Promise(r=>setTimeout(r,100));assert.equal(finished,false);release();
   assert.equal((await first).status,'staged');assert.equal((await second).status,'exact_replay');
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,1);
  });

  await t.test('concurrent claims for one source batch never overwrite or duplicate it',async()=>{
   const f=await fixture(),a=await f.client(),b=await f.client(),original=a.query.bind(a);
   let release,started;const gate=new Promise(r=>release=r),entered=new Promise(r=>started=r);
   a.query=async q=>{const r=await original(q);if(q?.text?.startsWith('INSERT INTO private.collect_pg_transfer_quarantine')){started();await gate;}return r;};
   const first=stageEncryptedBatch(a,f.args());await entered;
   const other={...f.plan,operation_id:randomUUID()},pin=planDigest(other),envelope=sealBatch(other,pin,f.plaintext,f.key);
   const second=stageEncryptedBatch(b,{plan:other,expectedPlanSha256:pin,envelope,key:f.key})
    .then(()=>({accepted:true}),error=>({accepted:false,code:error.code}));release();
   assert.equal((await first).status,'staged');assert.deepEqual(await second,{accepted:false,code:'batch_collision'});
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,1);
  });

  await t.test('a real PostgreSQL lock timeout remains a sanitized timeout',async()=>{
   const f=await fixture(),holder=await f.client();await holder.query('BEGIN');await holder.query('SELECT pg_advisory_xact_lock(7346371,1)');
   try{await assert.rejects(stageEncryptedBatch(await f.client(),f.args()),{code:'database_timeout'});}
   finally{await holder.query('ROLLBACK');}
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
  });

  await t.test('fence, deployment and quarantine catalogue drift fail closed',async()=>{
   const f=await fixture();await f.setup.query("UPDATE private.collect_fence_control SET mode='open'");
   await assert.rejects(stageEncryptedBatch(await f.client(),f.args()),{code:'identity_mismatch'});
   await f.setup.query("UPDATE private.collect_fence_control SET mode='fenced';INSERT INTO private.collect_fence_admissions VALUES('settled',1)");
   await assert.rejects(stageEncryptedBatch(await f.client(),f.args()),{code:'fence_not_quiescent'});await f.setup.query('DELETE FROM private.collect_fence_admissions');
   await f.setup.query("UPDATE private.collect_deployment_identity SET profile_sha256=repeat('f',64)");
   await assert.rejects(stageEncryptedBatch(await f.client(),f.args()),{code:'identity_mismatch'});
   await f.setup.query('UPDATE private.collect_deployment_identity SET profile_sha256=$1',[f.plan.target.profile_sha256]);
   await f.setup.query('ALTER TABLE private.collect_pg_transfer_quarantine DISABLE TRIGGER collect_pg_quarantine_immutable');
   await assert.rejects(stageEncryptedBatch(await f.client(),f.args()),{code:'quarantine_catalogue_mismatch'});
   assert.equal((await f.setup.query('SELECT count(*)::int AS n FROM private.collect_pg_transfer_quarantine')).rows[0].n,0);
  });

  await t.test('an unlogged journal or a rewrite rule cannot masquerade as a durable receipt',async()=>{
   const unlogged=await fixture();await unlogged.setup.query('ALTER TABLE private.collect_pg_transfer_quarantine SET UNLOGGED');
   await assert.rejects(stageEncryptedBatch(await unlogged.client(),unlogged.args()),{code:'quarantine_catalogue_mismatch'});
   const rewritten=await fixture();await rewritten.setup.query('CREATE RULE synthetic_discard AS ON INSERT TO private.collect_pg_transfer_quarantine DO INSTEAD NOTHING');
   await assert.rejects(stageEncryptedBatch(await rewritten.client(),rewritten.args()),{code:'quarantine_catalogue_mismatch'});
  });
 }finally{
  for(const c of clients.reverse()){try{await c.end();}catch{}}
  if(!(await cluster.close()).removed)throw Error('fixture_cleanup_unconfirmed');
 }
});
