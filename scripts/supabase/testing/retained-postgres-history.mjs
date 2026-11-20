// Hash-pinned historical SQL inputs for disposable PostgreSQL fixtures.
import {readFile,readdir,realpath} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';

const LOCK_PATH='supabase/managed-migration-history/source-migrations.lock.json';
const LOCK_SHA256='17d63e907cc992d62be67224319f5596c150bd1f51d5c05aa54dc250ef50aa64';
const MIGRATION_NAME=/^\d{14}_[a-z0-9_]+\.sql$/;
const need=(ok,code)=>{if(!ok)throw Error(code);};
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');

export async function loadRetainedMigrationPrefix(root,additionalPins={}){
 const lockPath=join(root,LOCK_PATH);
 need(await realpath(lockPath)===lockPath,'MIGRATION_LOCK_NOT_PHYSICAL');
 const bytes=await readFile(lockPath);
 need(sha(bytes)===LOCK_SHA256,'PINNED_MIGRATION_LOCK_CHANGED');
 const lock=JSON.parse(bytes);
 need(lock.format==='collect.selfhost.migrations.v1'&&lock.original_count===16&&lock.migrations.length===58,
  'EXACT_REVIEWED_58_REQUIRED');
 const expected=[...lock.migrations,...Object.entries(additionalPins).map(([name,sha256])=>({name,sha256}))];
 const versions=expected.map(({name})=>name.slice(0,14));
 need(expected.every(({name,sha256})=>MIGRATION_NAME.test(name)&&/^[a-f0-9]{64}$/.test(sha256))&&
  versions.every((version,index)=>index===0||version>versions[index-1]),'PINNED_MIGRATION_ORDER_INVALID');
 const directory=join(root,'supabase/migrations');
 const disk=(await readdir(directory)).filter(name=>/^\d{14}_.*\.sql$/.test(name)&&name.slice(0,14)<=versions.at(-1)).sort();
 need(disk.length===expected.length&&disk.every((name,index)=>name===expected[index].name),
  'EXACT_REVIEWED_MIGRATION_CHAIN_REQUIRED');
 const migrations=[];
 for(const entry of expected){
  const path=join(directory,entry.name);
  need(await realpath(path)===path,'MIGRATION_PATH_NOT_PHYSICAL');
  const bytes=await readFile(path);
  need(sha(bytes)===entry.sha256,'MIGRATION_BYTES_CHANGED');
  migrations.push({...entry,sql:bytes.toString('utf8')});
 }
 return migrations;
}

/** Existing initialized test fixtures use the real stop/drain/release protocol
 * before adding the inactive native realm. A fresh uninitialized installer can
 * apply it directly. Never relax the shipping migration's closed-fence gate.
 */
export async function applyRetainedFixtureMigration(owner,item){
 if(!['20261109234517_burimunsi_native_operator_schema.sql',
  '20261110030800_burimunsi_sms_source_scope.sql',
  '20261110032620_burimunsi_native_provisioning.sql',
  '20261110040728_burimunsi_gateway_classification.sql',
  '20261110052756_burimunsi_dynamic_scope_setup.sql',
  '20261110093218_burimunsi_managed_email_preauth.sql',
  '20261110143000_burimunsi_native_phone_pin.sql',
  '20261110181002_collect_local_stopped_admission.sql',
  '20261110181003_burimunsi_gateway_handoff.sql',
  '20261110193000_burimunsi_canonical_receipt_adoption.sql',
  '20261111043455_collect_admin_email_otp_lifetime.sql',
  '20261111120000_collect_admin_persistent_sessions.sql',
  '20261111120200_burimunsi_native_session_renewal.sql',
  '20261111120400_burimunsi_passcode_session_rotation.sql',
  '20261111120500_burimunsi_native_logout_barrier.sql',
  '20261111121000_burimunsi_private_observations.sql',
  '20261111121100_burimunsi_admin_observations.sql',
  '20261111121200_burimunsi_retention_inspection.sql','20261111121300_burimunsi_pin_clock_skew.sql',
  '20261111121400_collect_protected_owner_identity.sql',
  '20261111121500_burimunsi_pin_bound_clock.sql',
  '20261111121600_burimunsi_pin_rotation_expiry.sql',
  '20261111121700_burimunsi_staff_phone_preservation.sql',
  '20261112200100_burimunsi_native_auto_transactions.sql',
  '20261113130000_burimunsi_native_observation_dedup.sql',
  '20261113130100_burimunsi_smart_onboarding_journal.sql',
  '20261113130200_burimunsi_account_sms_history.sql',
  '20261113130300_burimunsi_native_financial_work.sql',
  '20261113130400_burimunsi_native_financial_custody.sql',
  '20261113130500_burimunsi_native_work_discovery.sql',
  '20261113130600_burimunsi_native_work_retention_inspection.sql',
  '20261113130700_storage_iceberg_retention_inspection.sql',
  '20261113130800_burimunsi_native_lease_history.sql'].includes(item.name))return owner.unsafe(item.sql);
 const rows=await owner.unsafe('SELECT mode,epoch,source_sha256 FROM private.collect_fence_control WHERE singleton');
 if(rows.length===0){
  need(!['20261110193000_burimunsi_canonical_receipt_adoption.sql','20261111043455_collect_admin_email_otp_lifetime.sql',
   '20261111121000_burimunsi_private_observations.sql','20261111121100_burimunsi_admin_observations.sql',
   '20261111121200_burimunsi_retention_inspection.sql','20261111121300_burimunsi_pin_clock_skew.sql',
   '20261111121400_collect_protected_owner_identity.sql',
  '20261111121500_burimunsi_pin_bound_clock.sql',
  '20261111121600_burimunsi_pin_rotation_expiry.sql',
  '20261111121700_burimunsi_staff_phone_preservation.sql',
  '20261112200100_burimunsi_native_auto_transactions.sql',
  '20261113130000_burimunsi_native_observation_dedup.sql',
  '20261113130100_burimunsi_smart_onboarding_journal.sql',
  '20261113130200_burimunsi_account_sms_history.sql',
  '20261113130300_burimunsi_native_financial_work.sql',
  '20261113130400_burimunsi_native_financial_custody.sql',
  '20261113130500_burimunsi_native_work_discovery.sql',
  '20261113130600_burimunsi_native_work_retention_inspection.sql',
  '20261113130700_storage_iceberg_retention_inspection.sql',
  '20261113130800_burimunsi_native_lease_history.sql'].includes(item.name),
   'INITIALIZED_FENCE_REQUIRED_FOR_REVIEWED_MIGRATION');
  return owner.unsafe(item.sql);
 }
 need(rows.length===1&&rows[0].mode==='open','FRESH_NATIVE_FIXTURE_OPEN_FENCE_REQUIRED');
 const control=rows[0],operation=randomUUID();
 await owner.unsafe('SELECT private.collect_fence_begin_quiesce($1::uuid,$2::bigint,$3::text)',[operation,control.epoch,control.source_sha256]);
 const drained=await owner.unsafe('SELECT private.collect_fence_drain($1::uuid,$2::bigint,$3::text) AS state',[operation,control.epoch,control.source_sha256]);
 need(drained.length===1&&drained[0].state?.mode==='fenced','NATIVE_FIXTURE_DRAIN_UNCONFIRMED');
 // Failure leaves the owned test fixture closed and preserves the diagnostic.
 await owner.unsafe(item.sql);
 const released=await owner.unsafe('SELECT private.collect_fence_release($1::uuid,$2::bigint,$3::text) AS state',[randomUUID(),control.epoch,control.source_sha256]);
 need(released.length===1&&released[0].state?.mode==='open'&&Number(released[0].state.epoch)===Number(control.epoch)+1,
  'NATIVE_FIXTURE_RELEASE_UNCONFIRMED');
}
