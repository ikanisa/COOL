import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../test-support/owned-pg17.mjs';
import {BusinessImportError,importSyntheticCollection,planDigest,reconcileSyntheticCollection,snapshotHmac} from './import.mjs';

const {Client}=pg;
const ids={source:'source-user',target:'cloud-primary',collection:'collection-one',sourceAuth:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',targetAuth:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',operation:'cccccccc-cccc-4ccc-8ccc-cccccccccccc'};
const isCode=code=>e=>e instanceof BusinessImportError&&e.code===code&&!String(e).includes('fake-ciphertext');

test('synthetic collection transfer exercises PostgreSQL fences, mapping and receipts', {timeout:180000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_business_import_fixture'});
 const clients=[];let admin;
 const connect=async(db='collect_business_import_fixture',user='fixture_operator')=>{
  const c=new Client({host:f.socket,port:f.port,database:db,user,connectionTimeoutMillis:3000});await c.connect();clients.push(c);return c;
 };
 try{
  const boot=await connect('postgres','fixture_bootstrap');
  await boot.query('CREATE ROLE fixture_operator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS');
  await boot.query('CREATE DATABASE collect_business_import_fixture OWNER fixture_bootstrap');
  admin=await connect('collect_business_import_fixture','fixture_bootstrap');
  await admin.query(await readFile(new URL('./fixture.sql',import.meta.url),'utf8'));
  const a='a'.repeat(64);
  await admin.query("INSERT INTO src.users(id,public_id,created_at,updated_at) VALUES($1,'source-public','2024-01-01','2024-01-02')",[ids.source]);
  await admin.query("INSERT INTO app.users(id,public_id,created_at,updated_at) VALUES($1,'cloud-public','2024-01-03','2024-01-04')",[ids.target]);
  await admin.query('INSERT INTO src.auth_users VALUES($1,true)',[ids.sourceAuth]);
  await admin.query('INSERT INTO auth.users VALUES($1,true)',[ids.targetAuth]);
  await admin.query("INSERT INTO src.auth_principal_links VALUES($1,$2,'2024-01-01','source-fixture-proof')",[ids.sourceAuth,ids.source]);
  await admin.query("INSERT INTO private.auth_principal_links VALUES($1,$2,'2024-01-03','cloud-fixture-proof')",[ids.targetAuth,ids.target]);
  await admin.query(`INSERT INTO src.collections(id,slug,creator_user_id,title,description,collection_type,receiver_momo_number,share_code_hash,share_code_ciphertext,share_code_version,revision,data_json,created_at,updated_at)
   VALUES($1,'fixture-slug',$2,'Fixture collection','Original text','savings','+250000000000','fixture-hash','fake-ciphertext-unchanged',4,7,'{"synthetic":true}','2024-02-03','2024-04-05');`,[ids.collection,ids.source]);
  await admin.query("INSERT INTO private.fixture_fences VALUES('source',11,'fenced'),('target',22,'fenced')");
  await admin.query('INSERT INTO private.fixture_evidence VALUES($1,$2,$3,$4,true,true,true,true,true,$5,$5)',['fixture-proof',ids.collection,ids.source,ids.target,a]);
  const key=randomBytes(32);
  async function makePlan({collection=ids.collection,operation=ids.operation,evidence='fixture-proof'}={}){
   const p={version:'collect.synthetic-collection-import.v1',operation_id:operation,source_collection_id:collection,source_user_id:ids.source,source_auth_id:ids.sourceAuth,target_user_id:ids.target,target_auth_id:ids.targetAuth,source_epoch:'11',target_epoch:'22',evidence_id:evidence};
   const specs={source_collection:['src.collections','id',collection],source_user:['src.users','id',ids.source],source_auth:['src.auth_users','id',ids.sourceAuth],source_link:['src.auth_principal_links','auth_user_id',ids.sourceAuth],target_user:['app.users','id',ids.target],target_auth:['auth.users','id',ids.targetAuth],target_link:['private.auth_principal_links','auth_user_id',ids.targetAuth],evidence:['private.fixture_evidence','id',evidence]};
   for(const [name,[table,column,value]] of Object.entries(specs)){
    const r=await admin.query(`SELECT to_jsonb(t)::text AS value FROM ${table} t WHERE ${column}=$1`,[value]);
    p[name+'_hmac']=snapshotHmac(key,name,r.rows[0].value);
   }
   const projected=await admin.query("SELECT (to_jsonb(t)||jsonb_build_object('creator_user_id',$2::text))::text AS value FROM src.collections t WHERE id=$1",[collection,ids.target]);
   p.expected_post_hmac=snapshotHmac(key,'target_collection',projected.rows[0].value);
   return p;
  }
  const options=async()=>{const plan=await makePlan();return {mode:'synthetic',plan,key,approvedDigest:planDigest(plan),connect:()=>connect()};};
  async function clean(){await admin.query('TRUNCATE app.collections,private.fixture_receipts');}
  await t.test('managed mode refuses before invoking a connection',async()=>{
   let called=false;const p=await options();p.mode='managed';p.connect=()=>{called=true;};
   await assert.rejects(importSyntheticCollection(p),isCode('managed_execution_closed'));
   await assert.rejects(reconcileSyntheticCollection(p),isCode('managed_execution_closed'));assert.equal(called,false);
  });
  await t.test('accessors, proxies, nonprimitive plan values and shared-memory keys fail before connection',async()=>{
   let calls=0,connected=0;
   const before=await options();before.connect=()=>{connected++;};
   const accessor={...before.plan};Object.defineProperty(accessor,'target_user_id',{enumerable:true,get(){calls++;return ids.target;}});
   await assert.rejects(importSyntheticCollection({...before,plan:accessor}),isCode('invalid_plan'));
   await assert.rejects(reconcileSyntheticCollection({...before,plan:accessor}),isCode('invalid_plan'));
   const badOptions={...before};Object.defineProperty(badOptions,'plan',{enumerable:true,get(){calls++;return before.plan;}});
   await assert.rejects(importSyntheticCollection(badOptions),isCode('invalid_plan'));
   const proxy=new Proxy({...before.plan},{getOwnPropertyDescriptor(){calls++;throw new Error('should not be invoked');}});
   await assert.rejects(importSyntheticCollection({...before,plan:proxy}),isCode('invalid_plan'));
   const inherited=Object.assign(Object.create({target_user_id:ids.target}),before.plan);
   await assert.rejects(importSyntheticCollection({...before,plan:inherited}),isCode('invalid_plan'));
   const coercion={...before.plan,target_user_id:{toString(){calls++;return ids.target;}}};
   await assert.rejects(importSyntheticCollection({...before,plan:coercion}),isCode('invalid_plan'));
   await assert.rejects(importSyntheticCollection({...before,key:Buffer.from(new SharedArrayBuffer(32))}),isCode('invalid_plan'));
   assert.equal(calls,0);assert.equal(connected,0);
  });
  await t.test('buffer accessors are never invoked and key bytes are captured before connection',async()=>{
   const p=await options();p.key=Buffer.from(key);const mutableBytes=new Uint8Array(p.key.buffer,p.key.byteOffset,p.key.byteLength);let calls=0;
   for(const name of ['length','byteLength','byteOffset','buffer'])Object.defineProperty(p.key,name,{get(){calls++;throw new Error('should not be invoked');}});
   p.connect=async()=>{mutableBytes.fill(0);return connect();};
   assert.deepEqual(await importSyntheticCollection(p),{status:'applied'});assert.equal(calls,0);
   const q=await options();q.key=Buffer.from(key);q.connect=async()=>{q.key.fill(0);return connect();};
   assert.deepEqual(await reconcileSyntheticCollection(q),{status:'receipt_and_postimage_verified'});
   assert.equal(q.key.every(x=>x===0),true);await clean();
  });
  await t.test('fixture identity rejects a wrong database before writes',async()=>{
   const p=await options();p.connect=()=>connect('postgres');
   await assert.rejects(importSyntheticCollection(p),isCode('fixture_identity_rejected'));
  });
  await t.test('encrypted bytes and historical attribution are preserved while the cloud principal remains unchanged',async()=>{
   const p=await options();
   const linkBefore=(await admin.query('SELECT to_jsonb(t)::text AS value FROM private.auth_principal_links t')).rows[0].value;
   const userBefore=(await admin.query('SELECT to_jsonb(t)::text AS value FROM app.users t')).rows[0].value;
   assert.deepEqual(await importSyntheticCollection(p),{status:'applied'});
   assert.deepEqual(await importSyntheticCollection(p),{status:'already_applied'});
   const target=(await admin.query('SELECT creator_user_id,share_code_ciphertext,created_at,updated_at,revision::text FROM app.collections')).rows[0];
   assert.deepEqual(target,{creator_user_id:ids.target,share_code_ciphertext:'fake-ciphertext-unchanged',created_at:'2024-02-03',updated_at:'2024-04-05',revision:'7'});
   const receipt=(await admin.query('SELECT source_user_id,target_user_id,target_auth_id::text,source_collection_id FROM private.fixture_receipts')).rows[0];
   assert.deepEqual(receipt,{source_user_id:ids.source,target_user_id:ids.target,target_auth_id:ids.targetAuth,source_collection_id:ids.collection});
   assert.equal((await admin.query('SELECT to_jsonb(t)::text AS value FROM private.auth_principal_links t')).rows[0].value,linkBefore);
   assert.equal((await admin.query('SELECT to_jsonb(t)::text AS value FROM app.users t')).rows[0].value,userBefore);
   await assert.rejects(admin.query('UPDATE private.auth_principal_links SET user_id=$1',[ids.target]),e=>e.code==='42501');
   await assert.rejects(admin.query('DELETE FROM private.auth_principal_links'),e=>e.code==='42501');
   await clean();
  });
  await t.test('source, target and mapping snapshots are exact',async()=>{
   const p=await options();
   await admin.query("UPDATE src.collections SET title='drift' WHERE id=$1",[ids.collection]);
   await assert.rejects(importSyntheticCollection(p),isCode('preimage_changed'));
   await admin.query("UPDATE src.collections SET title='Fixture collection' WHERE id=$1",[ids.collection]);
   await admin.query("UPDATE app.users SET revision=revision+1 WHERE id=$1",[ids.target]);
   await assert.rejects(importSyntheticCollection(p),isCode('preimage_changed'));
   await admin.query('UPDATE app.users SET revision=revision-1 WHERE id=$1',[ids.target]);
   const wrong={...p.plan,target_user_id:'different-user'};
   await assert.rejects(importSyntheticCollection({...p,plan:wrong}),isCode('invalid_plan'));
   assert.equal((await admin.query('SELECT count(*)::int AS n FROM private.fixture_receipts')).rows[0].n,0);
  });
  await t.test('fence, admissions and immutable-link trigger cannot drift',async()=>{
   const p=await options();
   await admin.query("UPDATE private.fixture_fences SET mode='open' WHERE side='source'");
   await assert.rejects(importSyntheticCollection(p),isCode('fence_changed'));
   await admin.query("UPDATE private.fixture_fences SET mode='fenced' WHERE side='source'");
   for(const [state,uncertain] of [['unresolved',0],['settled',1],['settled',null]]){
    await admin.query('INSERT INTO private.fixture_admissions VALUES($1,$2)',[state,uncertain]);
    await assert.rejects(importSyntheticCollection(p),isCode('unsettled_work'));
    await admin.query('DELETE FROM private.fixture_admissions');
   }
   await admin.query('ALTER TABLE private.auth_principal_links DISABLE TRIGGER fixture_link_immutable');
   try{await assert.rejects(importSyntheticCollection(p),isCode('fixture_guards_changed'));}
   finally{await admin.query('ALTER TABLE private.auth_principal_links ENABLE ALWAYS TRIGGER fixture_link_immutable');}
  });
  await t.test('missing AAD compatibility, unresolved reference graph or dependent history refuses the insert',async()=>{
   for(const change of ["key_aad_verified=false","identity_aad_independent=false","complete_object_graph=false","reference_free=false","target_key_aad='"+'b'.repeat(64)+"'"]){
    await admin.query('UPDATE private.fixture_evidence SET '+change);
    await assert.rejects(importSyntheticCollection(await options()),isCode('proof_unavailable'));
    await admin.query('UPDATE private.fixture_evidence SET key_aad_verified=true,identity_aad_independent=true,complete_object_graph=true,reference_free=true,target_key_aad=source_key_aad');
   }
   await admin.query("INSERT INTO src.collection_dependencies VALUES($1,'synthetic-contribution')",[ids.collection]);
   await assert.rejects(importSyntheticCollection(await options()),isCode('dependent_history_present'));
   await admin.query('DELETE FROM src.collection_dependencies');
  });
  await t.test('id, slug and encrypted-code hash conflicts never overwrite',async()=>{
   for(const type of ['id','slug','hash']){
    await admin.query('BEGIN');
    await admin.query("SELECT set_config('collect.fixture_operation',$1,true)",[ids.operation]);
    await admin.query(`INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,share_code_hash,created_at,updated_at)
     VALUES($1,$2,$3,'existing','savings',$4,'x','x')`,[type==='id'?ids.collection:'other-id',type==='slug'?'fixture-slug':'other-slug',ids.target,type==='hash'?'fixture-hash':'other-hash']);
    await admin.query('COMMIT');
    await assert.rejects(importSyntheticCollection(await options()),isCode('target_unique_conflict'));
    assert.equal((await admin.query('SELECT count(*)::int n FROM app.collections')).rows[0].n,1);
    assert.equal((await admin.query('SELECT count(*)::int n FROM private.fixture_receipts')).rows[0].n,0);
    await clean();
   }
  });
  await t.test('a receipt collision rolls back the collection insert atomically',async()=>{
   const p=await options();
   await admin.query(`INSERT INTO private.fixture_receipts(operation_id,plan_digest,source_collection_id,source_user_id,target_user_id,target_auth_id,source_hmac,target_hmac,evidence_hmac)
    VALUES('dddddddd-dddd-4ddd-8ddd-dddddddddddd',$1,$2,$3,$4,$5,$6,$7,$8)`,
    [p.approvedDigest,ids.collection,ids.source,ids.target,ids.targetAuth,p.plan.source_collection_hmac,p.plan.expected_post_hmac,p.plan.evidence_hmac]);
   await assert.rejects(importSyntheticCollection(p),isCode('fixture_transaction_failed'));
   assert.equal((await admin.query('SELECT count(*)::int n FROM app.collections')).rows[0].n,0);
   assert.equal((await admin.query('SELECT count(*)::int n FROM private.fixture_receipts')).rows[0].n,1);
   await clean();
  });
  await t.test('locks hold fence and source authority until the target transaction commits',async()=>{
   const p=await options();let release,inserted;
   const blocked=new Promise(r=>{release=r;});const reached=new Promise(r=>{inserted=r;});
   p.connect=async()=>{
    const c=await connect(),query=c.query.bind(c);
    c.query=async(...args)=>{const result=await query(...args);if(typeof args[0]==='string'&&args[0].startsWith('INSERT INTO app.collections')){inserted();await blocked;}return result;};return c;
   };
   const apply=importSyntheticCollection(p);await reached;
   const other=await connect();await other.query("SET lock_timeout='150ms'");
   try{
    await assert.rejects(other.query("UPDATE private.fixture_fences SET epoch=epoch+1 WHERE side='target'"),e=>e.code==='55P03');
    await assert.rejects(other.query("UPDATE src.collections SET title='racing'"),e=>e.code==='55P03');
   }finally{release();}
   assert.deepEqual(await apply,{status:'applied'});await clean();
  });
  await t.test('lost COMMIT acknowledgement reconciles read-only without retrying',async()=>{
   const p=await options();
   assert.deepEqual(await reconcileSyntheticCollection(p),{status:'receipt_not_visible_do_not_retry'});
   let injected=false;
   p.connect=async()=>{
    const c=await connect(),query=c.query.bind(c);
    c.query=async(...args)=>{const result=await query(...args);if(args[0]==='COMMIT'){injected=true;throw new Error('synthetic acknowledgement loss');}return result;};return c;
   };
   assert.deepEqual(await importSyntheticCollection(p),{status:'commit_unconfirmed_do_not_retry'});assert.equal(injected,true);
   p.connect=()=>connect();
   assert.deepEqual(await reconcileSyntheticCollection(p),{status:'receipt_and_postimage_verified'});
   assert.equal((await admin.query('SELECT count(*)::int n FROM private.fixture_receipts')).rows[0].n,1);
   await admin.query('UPDATE private.fixture_receipts SET target_hmac=$1',['b'.repeat(64)]);
   await assert.rejects(reconcileSyntheticCollection(p),isCode('receipt_mismatch'));
   await admin.query('UPDATE private.fixture_receipts SET target_hmac=$1',[p.plan.expected_post_hmac]);
   await admin.query("UPDATE app.collections SET title='after-commit drift'");
   await assert.rejects(reconcileSyntheticCollection(p),isCode('target_postimage_changed'));
   await clean();
  });
  await t.test('mutating an approved plan cannot redirect import or lost-ack reconciliation',async()=>{
   const other='collection-two',otherEvidence='fixture-proof-two',otherOp='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
   await admin.query("INSERT INTO src.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES($1,'fixture-slug-two',$2,'Other fixture','savings','2024-01-01','2024-01-02')",[other,ids.source]);
   await admin.query('INSERT INTO private.fixture_evidence VALUES($1,$2,$3,$4,true,true,true,true,true,$5,$5)',[otherEvidence,other,ids.source,ids.target,'a'.repeat(64)]);
   try{
    const a=await makePlan(),b=await makePlan({collection:other,operation:otherOp,evidence:otherEvidence});
    const digestA=planDigest(a),digestB=planDigest(b);assert.notEqual(digestA,digestB);
    const attack={mode:'synthetic',plan:{...a},key:Buffer.from(key),approvedDigest:digestA,connect:null};
    attack.connect=async()=>{Object.assign(attack.plan,b);attack.approvedDigest=digestB;return connect();};
    assert.deepEqual(await importSyntheticCollection(attack),{status:'applied'});
    const receipt=(await admin.query('SELECT operation_id::text,plan_digest,source_collection_id FROM private.fixture_receipts')).rows[0];
    assert.deepEqual(receipt,{operation_id:ids.operation,plan_digest:digestA,source_collection_id:ids.collection});
    assert.equal((await admin.query('SELECT count(*)::int n FROM app.collections WHERE id=$1',[other])).rows[0].n,0);
    await clean();
    // Simulate the old bug's B receipt bearing A's approved digest after an
    // acknowledged-lost commit; an A reconciliation must not verify B.
    const lost={mode:'synthetic',plan:{...b},key:Buffer.from(key),approvedDigest:digestB,connect:async()=>{
     const c=await connect(),query=c.query.bind(c);
     c.query=async(...args)=>{const result=await query(...args);if(args[0]==='COMMIT')throw new Error('synthetic lost acknowledgement');return result;};return c;
    }};
    assert.deepEqual(await importSyntheticCollection(lost),{status:'commit_unconfirmed_do_not_retry'});
    await admin.query('UPDATE private.fixture_receipts SET plan_digest=$1 WHERE operation_id=$2',[digestA,otherOp]);
    const recon={mode:'synthetic',plan:{...a},key:Buffer.from(key),approvedDigest:digestA,connect:null};
    recon.connect=async()=>{Object.assign(recon.plan,b);return connect();};
    assert.deepEqual(await reconcileSyntheticCollection(recon),{status:'receipt_not_visible_do_not_retry'});
    assert.equal((await admin.query('SELECT count(*)::int n FROM app.collections WHERE id=$1',[ids.collection])).rows[0].n,0);
    assert.equal((await admin.query('SELECT count(*)::int n FROM app.collections WHERE id=$1',[other])).rows[0].n,1);
   }finally{
    await clean();await admin.query('DELETE FROM private.fixture_evidence WHERE id=$1',[otherEvidence]);await admin.query('DELETE FROM src.collections WHERE id=$1',[other]);
   }
  });
  await t.test('concurrent same-plan attempts yield one durable receipt',async()=>{
   const p=await options();const results=await Promise.all([importSyntheticCollection(p),importSyntheticCollection(p)]);
   assert.deepEqual(results.map(x=>x.status).sort(),['already_applied','applied']);
   assert.equal((await admin.query('SELECT count(*)::int n FROM private.fixture_receipts')).rows[0].n,1);
   await clean();
  });
  key.fill(0);
 }finally{
  for(const c of clients){try{await c.end();}catch{}}
  const result=await f.close();assert.equal(result.removed,true);
 }
});
