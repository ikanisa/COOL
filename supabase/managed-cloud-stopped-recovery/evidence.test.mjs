// Isolated synthetic PG17 only. No existing database or remote endpoint is used.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,generateKeyPairSync,randomUUID,sign} from 'node:crypto';
import pg from '../../scripts/supabase/node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../../scripts/supabase/current-pg-transfer/test-support/owned-pg17.mjs';
import {canonicalEvidence,evidenceDigest,inspectManagedStopEvidence,parseCanonicalEvidence} from './evidence.mjs';

const project='rrlduytparvsjfmegalh',source='b'.repeat(64),receipt='c'.repeat(64);
const code=expected=>error=>error?.name==='EvidenceError'&&error.code===expected;
const {publicKey,privateKey}=generateKeyPairSync('ed25519');
const pem=publicKey.export({type:'spki',format:'pem'}).toString();
const signerSha=createHash('sha256').update(publicKey.export({type:'spki',format:'der'})).digest('hex');
const now='2026-11-13T20:01:31.123456Z';
const iso=value=>value; // Fixture uses fixed UTC microsecond timestamps.
const mkPolicy=snapshot=>({format:'collect.managed-stop-review-policy.v1',project_ref:project,
 admission_id:snapshot.admission.admission_id,epoch:snapshot.admission.epoch,source_sha256:snapshot.admission.source_sha256,
 snapshot_sha256:evidenceDigest(snapshot),signer_spki_sha256:signerSha,max_age_seconds:300,clock_skew_seconds:2,max_worker_seconds:150});
const mkClaims=snapshot=>({format:'collect.managed-edge-stop-attestation.v1',project_ref:project,admission_id:snapshot.admission.admission_id,
 epoch:snapshot.admission.epoch,source_sha256:snapshot.admission.source_sha256,snapshot_sha256:evidenceDigest(snapshot),
 control_operation_id:snapshot.control.operation_id,quiesce_receipt_sha256:snapshot.control.quiesce_receipt_sha256,
 invocation_id:'synthetic-execution-17',deployment_sha256:'d'.repeat(64),linkage_artifact_sha256:'e'.repeat(64),
 stopped_artifact_sha256:'f'.repeat(64),invocation_started_at:iso('2026-10-27T21:32:00.000000Z'),
 invocation_stopped_at:iso('2026-10-27T21:33:11.151000Z'),issued_at:iso('2026-11-13T20:01:30.000000Z'),
 external_effects:'unknown',executor_outcome:'stopped'});
const signature=claims=>sign(null,Buffer.from(canonicalEvidence(claims)),privateKey).toString('base64');
const input=(snapshot,claims)=>{const policy=mkPolicy(snapshot);return {snapshot,policy,expectedPolicySha256:evidenceDigest(policy),
 attestation:claims,signatureBase64:claims?signature(claims):undefined,signerPublicKeyPem:pem,now};};
const noAuthority=r=>{for(const key of ['write_authorized','fence_change_authorized','stopped_record_authorized','replay_authorized','provider_settlement_proven','original_counters_recovered'])assert.equal(r[key],false,key);
 assert.equal(r.external_effects,'unknown');assert.ok(r.still_unverified.includes('unknown_effect_obligation_retention'));};

test('managed stopped-work evidence remains non-authorizing with synthetic PG snapshots',{timeout:120000},async t=>{
 const cluster=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_managed_stop_synthetic_only'});
 const clients=[];
 const connect=async(db)=>{const c=new pg.Client({host:cluster.socket,port:cluster.port,database:db,user:'fixture_bootstrap',connectionTimeoutMillis:3000});c.on('error',()=>{});await c.connect();clients.push(c);return c;};
 try{
  const admin=await connect('postgres');
  assert.deepEqual((await admin.query("SELECT inet_server_addr() IS NULL AS socket_only,current_setting('server_version_num')::int/10000 AS version")).rows[0],{socket_only:true,version:17});
  await admin.query('CREATE DATABASE collect_managed_stop_fixture');
  const db=await connect('collect_managed_stop_fixture'),other=await connect('collect_managed_stop_fixture');
  await db.query(`CREATE SCHEMA synthetic_private;
   CREATE TABLE synthetic_private.control(mode text,epoch bigint,source_sha256 text,operation_id uuid,changed_at timestamptz,quiesce_receipt_sha256 text);
   CREATE TABLE synthetic_private.admissions(admission_id uuid,epoch bigint,source_sha256 text,kind text,state text,created_at timestamptz,external_dispatches integer,uncertain_dispatches integer);`);
  const id=randomUUID(),operation=randomUUID();
  await db.query('INSERT INTO synthetic_private.control VALUES($1,13,$2,$3,$4,$5)', ['open',source,operation,'2026-10-27T21:00:00.000000Z',null]);
  await db.query('INSERT INTO synthetic_private.admissions VALUES($1,13,$2,$3,$4,$5,0,0)',[id,source,'http_collect','active','2026-10-27T21:32:01.044520Z']);
  const capture=async(client)=>{
   const c=(await client.query(`SELECT mode,epoch::text,source_sha256,operation_id::text,
    to_char(changed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS changed_at,quiesce_receipt_sha256 FROM synthetic_private.control`)).rows[0];
   const a=(await client.query(`SELECT admission_id::text,epoch::text,source_sha256,kind,state,
    to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS created_at,
    external_dispatches::text,uncertain_dispatches::text FROM synthetic_private.admissions`)).rows[0];
   return {format:'collect.managed-fence-snapshot.v1',project_ref:project,control:c,admission:a};
  };
  const open=await capture(db);
  await t.test('a historical active row, zero counters and nearby shutdown do not prove recovery',async()=>{
   const result=inspectManagedStopEvidence(input(open));noAuthority(result);assert.equal(result.status,'blocked');
   assert.deepEqual(result.blockers,['committed_quiesce_not_verified','authenticated_admission_execution_binding_missing','authenticated_executor_stop_missing']);
  });
  await t.test('mismatched epoch, source or project never enters the review',async()=>{
   for(const altered of [{...open,project_ref:'other'}, {...open,admission:{...open.admission,epoch:'12'}},
    {...open,control:{...open.control,source_sha256:'a'.repeat(64)}}])
    assert.throws(()=>inspectManagedStopEvidence(input(altered)),e=>['invalid_snapshot','snapshot_binding_mismatch'].includes(e.code));
  });
  await db.query('UPDATE synthetic_private.control SET mode=$1,changed_at=$2,quiesce_receipt_sha256=$3',['quiescing','2026-11-13T20:00:00.000000Z',receipt]);
  const snapshot=await capture(db),claims=mkClaims(snapshot);
  await t.test('quiescing alone does not produce an authenticated link or effect disposition',async()=>{
   const result=inspectManagedStopEvidence(input(snapshot));noAuthority(result);assert.equal(result.status,'blocked');
   assert.deepEqual(result.blockers,['authenticated_admission_execution_binding_missing','authenticated_executor_stop_missing']);
  });
  await t.test('consistent separately pinned synthetic signatures still cannot authorize any action',async()=>{
   const result=inspectManagedStopEvidence(input(snapshot,claims));noAuthority(result);assert.equal(result.status,'signed_claims_consistent');
   for(const name of ['signer_authority','provider_artifact_authenticity','admission_execution_link','committed_quiesce','executor_termination','current_catalogue'])assert.ok(result.still_unverified.includes(name));
  });
  await t.test('an independently pinned policy and signer are mandatory',async()=>{
   const original=input(snapshot,claims);assert.throws(()=>inspectManagedStopEvidence({...original,expectedPolicySha256:'0'.repeat(64)}),code('policy_pin_mismatch'));
   const otherKey=generateKeyPairSync('ed25519');assert.throws(()=>inspectManagedStopEvidence({...original,signerPublicKeyPem:otherKey.publicKey.export({type:'spki',format:'pem'}).toString()}),code('invalid_signature'));
   const changed={...original.policy,signer_spki_sha256:'0'.repeat(64)};
   assert.throws(()=>inspectManagedStopEvidence({...original,policy:changed,expectedPolicySha256:evidenceDigest(changed)}),code('invalid_signature'));
  });
  await t.test('signature, snapshot, admission and original authority tampering are rejected',async()=>{
   const original=input(snapshot,claims);
   assert.throws(()=>inspectManagedStopEvidence({...original,attestation:{...claims,invocation_id:'other'}}),code('invalid_signature'));
   for(const key of ['admission_id','control_operation_id','snapshot_sha256','quiesce_receipt_sha256','source_sha256','epoch']){
    const value=key==='epoch'?'12':key==='admission_id'||key==='control_operation_id'?randomUUID():'0'.repeat(64);
    const changed={...claims,[key]:value};assert.throws(()=>inspectManagedStopEvidence({...original,attestation:changed,signatureBase64:signature(changed)}),code('attestation_binding_mismatch'),key);
   }
   const changedSnapshot={...snapshot,admission:{...snapshot.admission,external_dispatches:'1'}};
   assert.throws(()=>inspectManagedStopEvidence({...original,snapshot:changedSnapshot}),code('snapshot_pin_mismatch'));
  });
  await t.test('an unknown outcome cannot be recast as settled or a live executor as stopped',async()=>{
   for(const changed of [{...claims,external_effects:'settled'},{...claims,executor_outcome:'running'}])
    assert.throws(()=>inspectManagedStopEvidence({...input(snapshot,claims),attestation:changed,signatureBase64:signature(changed)}),code('invalid_attestation'));
  });
  await t.test('time, freshness and worker bounds use exact microseconds',async()=>{
   const changes=[{invocation_stopped_at:'2026-10-27T21:32:01.044519Z'},
    {invocation_started_at:'2026-10-27T21:32:01.044521Z'},{invocation_stopped_at:'2026-10-27T21:35:00.000000Z'},
    {issued_at:'2026-11-13T19:59:59.999999Z'},{issued_at:'2026-11-13T20:01:35.000000Z'},
    {issued_at:'2026-11-13T20:01:30.000001Z'}];
   // Last value is a different signed instant and remains in the valid interval.
   for(const change of changes.slice(0,5)){const changed={...claims,...change};
    assert.throws(()=>inspectManagedStopEvidence({...input(snapshot,claims),attestation:changed,signatureBase64:signature(changed)}),code('attestation_time_mismatch'));}
   const changed={...claims,...changes[5]};noAuthority(inspectManagedStopEvidence({...input(snapshot,claims),attestation:changed,signatureBase64:signature(changed)}));
   assert.throws(()=>inspectManagedStopEvidence({...input(snapshot,claims),now:'2026-11-13T20:07:00.000000Z'}),code('attestation_time_mismatch'));
   assert.throws(()=>inspectManagedStopEvidence({...input(snapshot,claims),now:'2026-02-30T20:01:31.123456Z'}),code('invalid_timestamp'));
   const impossible={...snapshot,control:{...snapshot.control,changed_at:'2026-10-27T21:32:01.044519Z'}};
   const impossibleClaims=mkClaims(impossible);
   assert.throws(()=>inspectManagedStopEvidence(input(impossible,impossibleClaims)),code('attestation_time_mismatch'));
  });
  await t.test('wire input rejects duplicate keys, alternate serializations and extra claims',async()=>{
   assert.deepEqual(parseCanonicalEvidence(canonicalEvidence(claims)),claims);
   assert.throws(()=>parseCanonicalEvidence('{"x":1,"x":1}'),code('noncanonical_evidence'));
   assert.throws(()=>parseCanonicalEvidence(' {"x":1}'),code('noncanonical_evidence'));
   const extra={...claims,unreviewed:'value'};assert.throws(()=>inspectManagedStopEvidence({...input(snapshot,claims),attestation:extra,signatureBase64:signature(extra)}),code('invalid_attestation'));
  });
  await t.test('deep and non-JSON object graphs fail before recursive serialization',async()=>{
   const deep='['.repeat(5000)+'0'+']'.repeat(5000);
   assert.ok(Buffer.byteLength(deep)<16384);
   assert.throws(()=>parseCanonicalEvidence(deep),code('evidence_structure_limit'));
   const tooWide=Object.fromEntries(Array.from({length:129},(_,i)=>['k'+i,i]));
   assert.throws(()=>canonicalEvidence(tooWide),code('evidence_structure_limit'));
   assert.throws(()=>canonicalEvidence(new Array(1)),code('evidence_structure_limit'));
   const cyclic={};cyclic.self=cyclic;assert.throws(()=>canonicalEvidence(cyclic),code('invalid_json_value'));
   const shared={value:true};assert.throws(()=>canonicalEvidence({first:shared,second:shared}),code('invalid_json_value'));
   let accessed=false;const getter={};Object.defineProperty(getter,'value',{enumerable:true,get(){accessed=true;return 1;}});
   assert.throws(()=>canonicalEvidence(getter),code('invalid_json_value'));assert.equal(accessed,false);
   assert.equal(canonicalEvidence(Array.from({length:128},()=>null)).length,641);
  });
  await t.test('a signed observation becomes stale if the live controller changes',async()=>{
   const pinned=input(snapshot,claims);await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
   const first=await capture(db);await other.query("UPDATE synthetic_private.control SET mode='fenced'");
   const stillFirst=await capture(db);assert.deepEqual(stillFirst,first);noAuthority(inspectManagedStopEvidence({...pinned,snapshot:stillFirst}));
   await db.query('ROLLBACK');const latest=await capture(db);assert.equal(latest.control.mode,'fenced');
   assert.throws(()=>inspectManagedStopEvidence({...pinned,snapshot:latest}),code('snapshot_pin_mismatch'));
  });
  await t.test('preparation never alters the original admission or fabricates a stopped record',async()=>{
   const row=(await db.query('SELECT state,external_dispatches,uncertain_dispatches FROM synthetic_private.admissions')).rows[0];
   assert.deepEqual(row,{state:'active',external_dispatches:0,uncertain_dispatches:0});
   assert.equal((await db.query("SELECT count(*)::int AS n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='synthetic_private' AND c.relkind='r'")).rows[0].n,2);
  });
 }finally{
  await Promise.allSettled(clients.map(c=>c.end()));
  const closed=await cluster.close();assert.equal(closed.removed,true,'owned fixture cleanup must be confirmed');
 }
});
