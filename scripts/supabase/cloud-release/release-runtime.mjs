// Explicit owner-run fence upgrade and separate release. Importing this module
// is read-only. It never deploys code, changes secrets, replays unknown work,
// creates credentials or retries an uncertain database commit.
import {readFileSync,lstatSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {connect,management,record,ROOT,PROJECT} from './access.mjs';
import {profile} from './migrations.mjs';
import {captureRuntimeSnapshot,desiredPublicConfig} from './runtime-plan.mjs';
import {qualificationName,verifyQualification} from './release-qualification.mjs';

const sha=x=>createHash('sha256').update(x).digest('hex');
const stable=x=>Array.isArray(x)?'['+x.map(stable).join(',')+']':x&&typeof x==='object'?'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+stable(x[k])).join(',')+'}':JSON.stringify(x);
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const HASH=/^[a-f0-9]{64}$/;
const slugs=['collect-api','admin-api','collect-jobs'];
const FENCE_DEFINITION_SHA='99fd575d0ddec31880cbe351e46514a34031c863d9be0d4ac06384c414b98df8';
function privateJson(name){
 if(!/^[a-z0-9_.-]+\.json$/.test(name))throw Error('release_evidence_path_invalid');
 const path=join(ROOT,name),s=lstatSync(path);
 if(!s.isFile()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o077)!==0||s.size<1||s.size>4*1024*1024)throw Error('release_evidence_file_unavailable');
 const bytes=readFileSync(path);return {bytes,value:JSON.parse(bytes.toString('utf8'))};
}
function functionSummary(x){return {slug:x.slug,id:x.id,status:x.status,version:x.version,verify_jwt:x.verify_jwt,ezbr_sha256:x.ezbr_sha256,entrypoint_path:x.entrypoint_path};}
export function verifyDeploymentReadback({deployment,secretReceipt,functions,secrets,sourceSha}){
 if(!deployment||deployment.sourceSha256!==sourceSha||deployment.databaseHeld!==true||
  !Array.isArray(deployment.functions)||deployment.functions.length!==3||
  secretReceipt?.sourceSha256!==sourceSha||secretReceipt.defaultPinConfirmed!==true||!Array.isArray(functions)||!Array.isArray(secrets))throw Error('deployment_receipt_unverified');
 for(const slug of slugs){
  const before=deployment.functions.filter(x=>x.slug===slug),after=functions.filter(x=>x.slug===slug);
  if(before.length!==1||after.length!==1||before[0].status!=='ACTIVE'||before[0].verify_jwt!==false||
   !HASH.test(before[0].ezbr_sha256??'')||!Number.isSafeInteger(before[0].version)||before[0].version<1||
   stable(functionSummary(before[0]))!==stable(functionSummary(after[0])))throw Error('deployment_readback_changed');
 }
 const names=new Map();for(const s of secrets){if(!s||typeof s.name!=='string'||!HASH.test(s.value??'')||names.has(s.name))throw Error('secret_metadata_invalid');names.set(s.name,s.value);}
 for(const [name,value] of Object.entries(desiredPublicConfig(sourceSha)))if(names.get(name)!==sha(value))throw Error('runtime_config_changed');
 for(const name of ['DATA_ENCRYPTION_KEY','DATA_KEY_ID','DATA_DECRYPTION_KEYS_JSON','SESSION_ENCRYPTION_KEY','SESSION_KEY_ID',
  'COLLECT_JOB_TOKEN','BURIMUNSI_PIN_PEPPER_BASE64','BURIMUNSI_PIN_PEPPER_ID','BURIMUNSI_CURSOR_KEY_BASE64','BURIMUNSI_DEFAULT_STAFF_PIN'])
  if(!names.has(name))throw Error('runtime_secret_missing');
 return {project:PROJECT,sourceSha256:sourceSha,functions:slugs.map(slug=>functionSummary(functions.find(x=>x.slug===slug))),
  publicConfigConfirmed:true,defaultPinConfirmed:true};
}

async function readScopedAccounts(db,group,adminId,staffId,owner){
 await db.query('BEGIN READ ONLY');
 try{
  await db.query('SET LOCAL ROLE collect_runtime');
  await db.query("SELECT set_config('collect.edge_verified','true',true),set_config('burimunsi.collection_id',$1,true)",[group]);
  const result=await db.query(`SELECT
   EXISTS(SELECT 1 FROM private.burimunsi_accounts a JOIN private.burimunsi_operator_approvals o
    ON o.collection_id=a.collection_id AND o.principal_user_id=a.principal_user_id
    WHERE a.collection_id=$1 AND a.id=$2::uuid AND a.principal_user_id=$4 AND a.role='admin' AND a.active AND NOT a.removed
     AND a.capabilities @> ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage']::text[]
     AND o.active AND o.role='admin' AND o.approved_by=$4 AND o.phone=a.phone
     AND a.pin_hash->>'algorithm'='pbkdf2-sha256+hmac-v1') AS admin_ok,
   EXISTS(SELECT 1 FROM private.burimunsi_accounts a JOIN private.burimunsi_native_staff_delegations d
    ON d.collection_id=a.collection_id AND d.principal_user_id=a.principal_user_id
    WHERE a.collection_id=$1 AND a.id=$3::uuid AND a.role='staff' AND a.active AND NOT a.removed
     AND a.capabilities @> ARRAY['records.read','members.enroll','payments.allocate']::text[]
     AND d.active AND d.parent_account_id=$2::uuid AND a.capabilities <@ d.capability_ceiling
     AND a.pin_hash->>'algorithm'='pbkdf2-sha256+hmac-v1') AS staff_ok,
   NOT EXISTS(SELECT 1 FROM private.burimunsi_sessions s WHERE s.collection_id=$1 AND s.account_id IN($2::uuid,$3::uuid) AND NOT s.revoked) AS old_sessions_retired,
   NOT EXISTS(SELECT 1 FROM private.burimunsi_device_accounts da JOIN private.burimunsi_device_grants d ON d.id=da.grant_id
     WHERE da.collection_id=$1 AND da.account_id IN($2::uuid,$3::uuid) AND d.active) AS old_grants_retired`,[group,adminId,staffId,owner]);
  await db.query('COMMIT');const r=result.rows[0];
  if(result.rowCount!==1||!r.admin_ok||!r.staff_ok||!r.old_sessions_retired||!r.old_grants_retired)throw Error('bootstrap_postimage_unverified');
  return {accountsConfirmed:true,oldCredentialsRetired:true};
 }catch(e){await db.query('ROLLBACK').catch(()=>{});throw e;}
}

export async function inspectRelease({db,api=management,graphIntentName,graphResultName,bootstrapOperationId}){
 if(!db||typeof db.query!=='function'||!UUID.test(bootstrapOperationId??''))throw Error('release_input_invalid');
 const deployment=privateJson('runtime-deploy-complete.json'),deployIntent=privateJson('runtime-deploy-intent.json'),secretReceipt=privateJson('runtime-secrets-confirmed.json');
 const graphIntent=privateJson(graphIntentName),graphResult=privateJson(graphResultName);
 const snapshot=captureRuntimeSnapshot(),sourceSha=snapshot.sourceSha;
 if(deployIntent.value.sourceSha256!==sourceSha||deployment.value.sourceSha256!==sourceSha||
  graphIntent.value.project!==PROJECT||!UUID.test(graphIntent.value.operationId??'')||
  graphResult.value.outcome!=='committed_and_receipt_read_back'||graphResult.value.migration!==graphIntent.value.migration||
  !HASH.test(graphResult.value.migrationHash??'')||!HASH.test(graphIntent.value.snapshotHmac??'')||!HASH.test(graphIntent.value.objectProofHmac??''))
  throw Error('release_evidence_unverified');
 const qualification=privateJson(qualificationName(sourceSha));verifyQualification(qualification.value,sourceSha);
 const [functionResult,secretResult]=await Promise.all([api('functions'),api('secrets')]);
 const deployed=verifyDeploymentReadback({deployment:deployment.value,secretReceipt:secretReceipt.value,
  functions:functionResult.json(),secrets:secretResult.json(),sourceSha});
 const f=await db.query(`SELECT mode,epoch::text,operation_id::text,source_sha256,project_ref FROM private.collect_fence_control WHERE singleton`),fence=f.rows[0];
 if(f.rowCount!==1||fence.project_ref!==PROJECT||fence.mode!=='fenced'||!UUID.test(fence.operation_id??'')||!HASH.test(fence.source_sha256??'')||
  !/^[1-9][0-9]{0,15}$/.test(fence.epoch??''))throw Error('release_fence_changed');
 const g=await db.query(`SELECT source_actor_id,cloud_primary_id,snapshot_hmac,object_proof_hmac,counts
  FROM private.collect_migration_import_receipts WHERE operation_id=$1`,[graphIntent.value.operationId]);
 const receipt=g.rows[0];
 if(g.rowCount!==1||receipt.snapshot_hmac!==graphIntent.value.snapshotHmac||receipt.object_proof_hmac!==graphIntent.value.objectProofHmac||
  stable(receipt.counts)!==stable(graphResult.value.counts)||receipt.counts?.sms!==graphIntent.value.summary?.sms)throw Error('graph_receipt_changed');
 const marker=await db.query('SELECT count(*)::int n,count(DISTINCT collection_id)::int groups,min(collection_id) group_id FROM private.collect_imported_native_history WHERE operation_id=$1',[graphIntent.value.operationId]);
 if(marker.rows[0]?.n!==receipt.counts.sms||marker.rows[0]?.groups!==1)throw Error('historical_markers_changed');
 const group=marker.rows[0].group_id;
 const a=await db.query(`SELECT actor_user_id,actor_session_id,entity_id,details_json::jsonb AS detail FROM app.audit_log
  WHERE action='burimunsi.migration.initial_accounts' AND request_id=$1`,[bootstrapOperationId]);
 const audit=a.rows[0],d=audit?.detail;
 if(a.rowCount!==1||audit.actor_user_id!==receipt.cloud_primary_id||audit.actor_session_id!==null||audit.entity_id!==group||
  d?.kind!=='owner_authorized_migration'||d.old_sessions_reused!==false||!HASH.test(d.authorization_sha256??'')||
  !UUID.test(d.admin_account_id??'')||!UUID.test(d.staff_account_id??''))throw Error('bootstrap_audit_unverified');
 const accounts=await readScopedAccounts(db,group,d.admin_account_id,d.staff_account_id,receipt.cloud_primary_id);
 const checks=await db.query(`SELECT
  (SELECT count(*)=1 AND bool_and(origin=$1 AND bucket='collect-evidence') FROM private.storage_namespace) AS namespace_ok,
  (SELECT profile_sha256=$2 FROM private.collect_deployment_identity WHERE singleton) AS profile_ok,
  encode(sha256(convert_to(pg_get_functiondef('private.collect_fence_assert_write(uuid,bigint,text)'::regprocedure),'UTF8')),'hex')=$3 AS fence_guard_ok,
  NOT EXISTS(SELECT 1 FROM pg_policy WHERE polname='collect_transfer_maintenance') AS policies_restored,
  (SELECT count(*)=4 AND bool_and(tgenabled='A') FROM pg_trigger WHERE NOT tgisinternal AND tgname='collect_imported_native_history_guard') AS history_triggers_ok,
  strpos((SELECT prosrc FROM pg_proc WHERE oid='private.burimunsi_observation_history_rows(text)'::regprocedure),'collect_migration_actor_lineage')>0 AS history_reader_ok,
  strpos((SELECT prosrc FROM pg_proc WHERE oid='private.burimunsi_auto_snapshot(text)'::regprocedure),'collect_imported_native_job_transaction')>0 AS history_processing_guard_ok,
  (SELECT count(*)=1 AND max(encode(sha256(convert_to(statements[1],'UTF8')),'hex'))=$4 AND bool_and(cardinality(statements)=1)
    FROM supabase_migrations.schema_migrations WHERE version=$5) AS graph_migration_ok`,
  ['https://'+PROJECT+'.supabase.co',sha(profile),FENCE_DEFINITION_SHA,graphResult.value.migrationHash,graphResult.value.migration]);
 if(checks.rowCount!==1||Object.values(checks.rows[0]).some(v=>v!==true))throw Error('release_database_postimage_unverified');
 const publicPlan={project:PROJECT,sourceSha256:sourceSha,oldFence:{epoch:fence.epoch,operationId:fence.operation_id,sourceSha256:fence.source_sha256},
  graphOperationId:graphIntent.value.operationId,bootstrapOperationId,namespaceConfirmed:true,...accounts};
 return {fence,sourceSha,planSha:sha(deployIntent.bytes),qualificationSha:sha(qualification.bytes),deploymentSha:sha(stable(deployed)),publicPlan};
}

export async function upgradeAndRelease({db,api=management,graphIntentName,graphResultName,bootstrapOperationId,save=record}){
 const before=await inspectRelease({db,api,graphIntentName,graphResultName,bootstrapOperationId});
 const upgradeId=randomUUID(),releaseId=randomUUID();
 save('runtime-source-upgrade-intent.json',{...before.publicPlan,upgradeId,releaseId,planSha:before.planSha,
  qualificationSha:before.qualificationSha,deploymentSha:before.deploymentSha,at:new Date().toISOString()});
 let upgrade;
 try{upgrade=await db.query('SELECT private.collect_fence_upgrade_source_v3($1,$2,$3::bigint,$4,$5,$6,$7,$8) v',
  [upgradeId,before.fence.operation_id,before.fence.epoch,before.fence.source_sha256,before.sourceSha,before.planSha,before.qualificationSha,before.deploymentSha]);}
 catch(e){const error=Error('source_upgrade_outcome_requires_reconciliation');error.cause=e;throw error;}
 const mid=(await db.query('SELECT mode,epoch::text,operation_id::text,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
 if(upgrade.rowCount!==1||mid?.mode!=='fenced'||mid.operation_id!==upgradeId||mid.source_sha256!==before.sourceSha||BigInt(mid.epoch)!==BigInt(before.fence.epoch)+1n)
  throw Error('source_upgrade_readback_unconfirmed');
 save('runtime-source-upgrade-complete.json',{operationId:upgradeId,epoch:mid.epoch,sourceSha256:before.sourceSha,at:new Date().toISOString()});
 // Re-read provider metadata after upgrade. The release is a separate
 // transaction, as required by collect_fence_release_v3.
 const [f,s]=await Promise.all([api('functions'),api('secrets')]);
 const deployment=privateJson('runtime-deploy-complete.json'),secretReceipt=privateJson('runtime-secrets-confirmed.json');
 const fresh=verifyDeploymentReadback({deployment:deployment.value,secretReceipt:secretReceipt.value,functions:f.json(),secrets:s.json(),sourceSha:before.sourceSha});
 if(sha(stable(fresh))!==before.deploymentSha)throw Error('deployment_changed_after_source_upgrade');
 save('runtime-source-release-intent.json',{operationId:releaseId,epoch:mid.epoch,sourceSha256:before.sourceSha,at:new Date().toISOString()});
 let release;
 try{release=await db.query('SELECT private.collect_fence_release_v3($1,$2::bigint,$3) v',[releaseId,mid.epoch,before.sourceSha]);}
 catch(e){const error=Error('source_release_outcome_requires_reconciliation');error.cause=e;throw error;}
 const end=(await db.query('SELECT mode,epoch::text,operation_id::text,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
 if(release.rowCount!==1||end?.mode!=='open'||end.operation_id!==releaseId||end.source_sha256!==before.sourceSha||BigInt(end.epoch)!==BigInt(mid.epoch)+1n)
  throw Error('source_release_readback_unconfirmed');
 save('runtime-source-release-complete.json',{operationId:releaseId,epoch:end.epoch,sourceSha256:before.sourceSha,at:new Date().toISOString()});
 return {released:true,epoch:end.epoch,sourceSha256:before.sourceSha,externalEffectsSettled:false};
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 if(process.argv.length!==6||process.argv[2]!=='--apply-verified')throw Error('explicit_apply_and_evidence_required');
 const db=await connect();try{const result=await upgradeAndRelease({db,graphIntentName:process.argv[3],graphResultName:process.argv[4],bootstrapOperationId:process.argv[5]});console.log(JSON.stringify(result));}
 finally{await db.end().catch(()=>{});}
}
