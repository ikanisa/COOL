// Explicit one-shot production import. Parent operator must stop/fence source
// writers first and preserve the independently encrypted full source archive.
// Private source rows and ciphertext proof names remain in process memory only.
// The exclusive intent prevents accidental retries, including unknown COMMIT.
import {createHmac,hkdfSync,randomBytes,randomUUID} from 'node:crypto';
import {lstatSync,readFileSync,openSync,writeFileSync,fsyncSync,closeSync} from 'node:fs';
import {connect,ROOT,PROJECT} from '../cloud-release/access.mjs';
import {isManagedReconciliationPeer} from '../current-pg-transfer/managed-target.mjs';
import {captureLocalSource} from './source-reader.mjs';
import {inspectSourceGraph,sourceSnapshotHmac} from './compile.mjs';
import {insertGraph,verifyGraph} from './graph-transaction.mjs';
import {executeManagedMaintenance} from './maintenance.mjs';

const PROOF=ROOT+'/verified-application-objects.json';
const PRIOR_KEY=ROOT+'/graph-import-custody-key.bin';
const PRIOR_INTENT=ROOT+'/graph-import-intent.json';
const PRIOR_RESULT=ROOT+'/graph-import-result.json';
const KEY=ROOT+'/graph-import-attempt-002-custody-key.bin';
const INTENT=ROOT+'/graph-import-attempt-002-intent.json';
const RESULT=ROOT+'/graph-import-attempt-002-result.json';
const MIGRATION='20261117071343';
function privateFile(path,max){
 const s=lstatSync(path);
 if(!s.isFile()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o077)!==0||s.size<1||s.size>max)throw Error('private_import_file_required');
 return readFileSync(path);
}
function privateRoot(){
 const s=lstatSync(ROOT);
 if(!s.isDirectory()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o077)!==0)throw Error('private_import_directory_required');
}
function persist(path,value){
 const fd=openSync(path,'wx',0o600);
 try{writeFileSync(fd,value);fsyncSync(fd);}finally{closeSync(fd);}
 const dir=openSync(ROOT,'r');try{fsyncSync(dir);}finally{closeSync(dir);}
}
const stable=x=>Array.isArray(x)?'['+x.map(stable).join(',')+']':x&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+stable(x[k])).join(',')+'}':JSON.stringify(x);
function proofMac(proof,key,operationId){
 const h=Buffer.from(hkdfSync('sha256',key,Buffer.from(operationId),Buffer.from('collect.graph.object-proof.v1'),32));
 try{return createHmac('sha256',h).update(stable(proof)).digest('hex');}finally{h.fill(0);}
}
function loadProof(){
 const proof=JSON.parse(privateFile(PROOF,4*1024*1024).toString('utf8'));
 if(!proof || Array.isArray(proof) || typeof proof!=='object')throw Error('object_proof_invalid');
 return proof;
}
function requireFencedSource(capture){
 if(capture.fenceMode!=='fenced'||capture.effectiveActiveAdmissions!==0)throw Error('source_not_fully_fenced');
 return inspectSourceGraph(capture.snapshot);
}
async function cloudOwner(db){
 const q=await db.query(`SELECT i.principal_user_id
  FROM private.collect_owner_identity i
  JOIN app.admin_users a ON a.id=i.admin_user_id AND a.role='owner' AND a.status='active' AND a.email=i.owner_email
  JOIN app.admin_principal_links l ON l.admin_user_id=a.id AND l.user_id=i.principal_user_id
  JOIN app.users u ON u.id=i.principal_user_id AND u.access_status='active'
  JOIN private.auth_principal_links p ON p.user_id=u.id
  JOIN auth.users actual ON actual.id=p.auth_user_id AND lower(actual.email)=a.email AND actual.email_confirmed_at IS NOT NULL
  WHERE i.singleton`);
 if(q.rowCount!==1)throw Error('verified_cloud_owner_required');
 return q.rows[0].principal_user_id;
}
async function safeLogging(db){
 const q=await db.query(`SELECT current_setting('log_statement') statement,
  current_setting('log_min_duration_statement') duration,
  current_setting('log_parameter_max_length_on_error') on_error`);
 const r=q.rows[0];
 if(!['none','ddl'].includes(r.statement)||r.duration!=='-1'||r.on_error!=='0')throw Error('private_parameter_logging_unqualified');
}
async function readReceipt(db,operationId,expected){
 const q=await db.query(`SELECT source_actor_id,cloud_primary_id,snapshot_hmac,object_proof_hmac,counts
  FROM private.collect_migration_import_receipts WHERE operation_id=$1`,[operationId]);
 const r=q.rows[0];
 return q.rowCount===1 && r.source_actor_id===expected.sourceActorId && r.cloud_primary_id===expected.cloudPrimaryId &&
  r.snapshot_hmac===expected.snapshotHmac && r.object_proof_hmac===expected.objectProofHmac && stable(r.counts)===stable(expected.counts);
}
async function requireFirstRollback(db,capture,proof){
 const prior=JSON.parse(privateFile(PRIOR_INTENT,65536).toString('utf8'));
 const result=JSON.parse(privateFile(PRIOR_RESULT,65536).toString('utf8'));
 const oldKey=privateFile(PRIOR_KEY,32);
 try{
  if(oldKey.length!==32||prior.version!==1||prior.project!==PROJECT||result.outcome!=='rolled_back'||
    sourceSnapshotHmac(capture.snapshot,oldKey,prior.operationId)!==prior.snapshotHmac||
    proofMac(proof,oldKey,prior.operationId)!==prior.objectProofHmac)throw Error('previous_attempt_unreconciled');
  const q=await db.query(`SELECT to_regclass('private.collect_migration_import_receipts') IS NULL AS receipt_absent,
    NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version=$1) AS history_absent`,[MIGRATION]);
  if(!q.rows[0]?.receipt_absent||!q.rows[0]?.history_absent)throw Error('previous_attempt_unreconciled');
 }finally{oldKey.fill(0);}
}
function safeCode(error){
 if(typeof error?.code==='string'&&/^[A-Z0-9]{5}$/.test(error.code))return error.code;
 if(typeof error?.message==='string'&&/^[a-z][a-z0-9_]{1,95}$/.test(error.message))return error.message;
 return 'import_failed';
}

if(process.argv.length!==3||process.argv[2]!=='--apply')throw Error('explicit_apply_required');
privateRoot();
const capture=captureLocalSource(),summary=requireFencedSource(capture),proof=loadProof();
if(Object.keys(proof).length!==summary.objects)throw Error('object_proof_count_mismatch');
const db=await connect();
let key=null,intentWritten=false,inserted,phase='preflight',outcome='not_dispatched';
try{
 if(!isManagedReconciliationPeer(db.connectionParameters,db.connection?.stream))throw Error('managed_peer_refused');
 await safeLogging(db);
 await requireFirstRollback(db,capture,proof);
 const initialOwner=await cloudOwner(db);
 const f=await db.query(`SELECT mode,epoch::text,operation_id::text,source_sha256,project_ref FROM private.collect_fence_control WHERE singleton`);
 if(f.rowCount!==1||f.rows[0].mode!=='fenced'||f.rows[0].project_ref!==PROJECT)throw Error('target_fence_unavailable');
 const fence=f.rows[0],operationId=randomUUID();
 key=randomBytes(32);
 const snapshotHmac=sourceSnapshotHmac(capture.snapshot,key,operationId),objectProofHmac=proofMac(proof,key,operationId);
 // Both files are exclusive and durable before any target mutation is sent.
 // An existing key/intent means manual outcome reconciliation is required.
 persist(KEY,key);
 persist(INTENT,JSON.stringify({version:1,project:PROJECT,operationId,snapshotHmac,objectProofHmac,
  summary,migration:MIGRATION,createdAt:new Date().toISOString()})+'\n');
 intentWritten=true;phase='transaction';
 const identity={operationId,fenceOperationId:fence.operation_id,epoch:fence.epoch,sourceSha256:fence.source_sha256};
 await executeManagedMaintenance(db,identity,async tx=>{
  await tx.query("SET LOCAL TIME ZONE 'UTC'");
  await safeLogging(tx);
  // Managed postgres may be forbidden to change this superuser setting. A
  // savepoint keeps that denial from aborting the import; safeLogging still
  // requires DML and error bind parameters not to be logged by current policy.
  await tx.query('SAVEPOINT parameter_log_restriction');
  try{await tx.query("SET LOCAL log_parameter_max_length='0'");await tx.query('RELEASE SAVEPOINT parameter_log_restriction');}
  catch{await tx.query('ROLLBACK TO SAVEPOINT parameter_log_restriction');await tx.query('RELEASE SAVEPOINT parameter_log_restriction');}
  const currentOwner=await cloudOwner(tx);
  if(currentOwner!==initialOwner)throw Error('cloud_owner_changed');
  inserted=await insertGraph(tx,{capture,key,operationId,cloudPrimaryId:currentOwner,proof,proofHmac:objectProofHmac});
  if(inserted.hmac!==snapshotHmac)throw Error('source_hmac_changed');
 },async tx=>{
  if(!await verifyGraph(tx,{capture,key,operationId,proofHmac:objectProofHmac,inserted}))return false;
  const again=captureLocalSource();requireFencedSource(again);
  if(again.sourceOwnerId!==capture.sourceOwnerId||sourceSnapshotHmac(again.snapshot,key,operationId)!==snapshotHmac ||
    proofMac(loadProof(),key,operationId)!==objectProofHmac)throw Error('cutover_inputs_changed');
  return true;
 });
 outcome='commit_acknowledged';phase='readback';
 if(!await readReceipt(db,operationId,{sourceActorId:capture.sourceOwnerId,cloudPrimaryId:initialOwner,snapshotHmac,objectProofHmac,counts:inserted.counts}))throw Error('receipt_readback_unconfirmed');
 const history=await db.query(`SELECT cardinality(statements)::int n,
  encode(sha256(convert_to(statements[1],'UTF8')),'hex') hash FROM supabase_migrations.schema_migrations WHERE version=$1`,[MIGRATION]);
 if(history.rowCount!==1||history.rows[0].n!==1)throw Error('migration_readback_unconfirmed');
 outcome='committed_and_receipt_read_back';
 persist(RESULT,JSON.stringify({outcome,counts:inserted.counts,migration:MIGRATION,migrationHash:history.rows[0].hash,
  at:new Date().toISOString()})+'\n');
 console.log(JSON.stringify({outcome,counts:inserted.counts,migration:MIGRATION}));
}catch(error){
 const status={outcome:error.outcome??outcome,phase,code:safeCode(error),at:new Date().toISOString()};
 if(intentWritten){try{persist(RESULT,JSON.stringify(status)+'\n');}catch{}}
 console.error(JSON.stringify(status));process.exitCode=1;
}finally{key?.fill(0);await db.end().catch(()=>{});}
