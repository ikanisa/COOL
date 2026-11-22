// Offline disaster-recovery preparation. This module has no network or deploy
// capability. Execute its statements together in one transaction/D1 batch.
const FORMAT='collect.platform.recovery-quarantine.v1';
const RETENTION_FORMAT='collect.platform.recovery-quarantine.v2';
const IDENTITY_FORMAT='collect.platform.recovery-quarantine.v3';
const ASSISTED_SMS_FORMAT='collect.platform.recovery-quarantine.v4';
const MOMO_FORMAT='collect.platform.recovery-quarantine.v5';
const AUTH_FORMAT='collect.platform.recovery-quarantine.v6';
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const SHA=/^[a-f0-9]{64}$/;
const required=(ok,message)=>{if(!ok)throw new Error(message);};

// A new credential schema needs explicit recovery-policy review. Do not
// silently claim that a later migration's credentials have been quarantined.
export const quarantineMigrationDigests=Object.freeze({
 'migrations/0001_core.sql':'299b0358d2545a6bbc3f6dc004eadb19168ba9d72131368d0e814165ab6b6455',
 'migrations/0002_auth.sql':'2106f1db68d8bd21a540c747079da4df032842ae42f38979be7f687e8af0b2a7',
 'migrations/0003_mutation_guards.sql':'c1a4aa837663235af26b41977a531db33e9c61b18006ca167cb7eca486562744',
 'migrations/0004_privacy.sql':'e7ba2d670e3620e7c4042f6291fa62c83407df7270987d8df5ac6431e8766ef3',
 'migrations/0005_ingestion.sql':'b8974163e228cbc776ae88378c7fb3aece26b560841e2f7f76b7a53f254c75f7',
 'migrations/0006_admin_accounts.sql':'ed56c5d5da367cccbc877848ffa0cbdb418a5cb6ef58a443318d2b6b7d794ba0',
 'migrations/0007_admin_bridge.sql':'9668f1394a24dc18c75eed61d98f24c598dc8b763103c3144fef25988e0ef3b2',
 'migrations/0008_receipt_capture.sql':'247771ccb826bb48e894dc1de703ce1cb0706c18ece1620557447faa673449fd',
 'migrations/0009_operator_notes.sql':'e7ee374a172bb818c0a382e1e94fdc467f776f05bc31789d1215484d4fbce970',
});
// Each historical archive interpretation stays exact. A named profile is an
// explicitly reviewed schema, not a statement of deployment or recovery acceptance.
export const quarantineSchemaProfiles=Object.freeze({
 published9:Object.freeze({format:FORMAT,digests:quarantineMigrationDigests}),
 candidate10:Object.freeze({format:RETENTION_FORMAT,digests:Object.freeze({...quarantineMigrationDigests,
  'migrations/0010_privacy_retention.sql':'94d7ec5146a4ef3e4721cb185a4700edea76c3e72e1cf992dd9fcb2d2e1571d2',
 })}),
 candidate11:Object.freeze({format:IDENTITY_FORMAT,identityValidatorSha256:'c0c9fbfb48b44c72c7192acd3853644349a000ba3e7fbf62fdc11037d5f6d4f7',digests:Object.freeze({...quarantineMigrationDigests,
  'migrations/0010_privacy_retention.sql':'94d7ec5146a4ef3e4721cb185a4700edea76c3e72e1cf992dd9fcb2d2e1571d2',
  'migrations/0011_auth_identity_keys.sql':'7e315ad76f45a6e5735d5ee42e7ae94f931e413de37b329a009f31ce9027e8f0',
 })}),
 candidate12:Object.freeze({format:ASSISTED_SMS_FORMAT,identityValidatorSha256:'c0c9fbfb48b44c72c7192acd3853644349a000ba3e7fbf62fdc11037d5f6d4f7',digests:Object.freeze({...quarantineMigrationDigests,
  'migrations/0010_privacy_retention.sql':'94d7ec5146a4ef3e4721cb185a4700edea76c3e72e1cf992dd9fcb2d2e1571d2',
  'migrations/0011_auth_identity_keys.sql':'7e315ad76f45a6e5735d5ee42e7ae94f931e413de37b329a009f31ce9027e8f0',
  'migrations/0012_notification_operator.sql':'f6bfc6603505b8a29338d845707b3347c8c767d230f41f8347a1979d4c70bac7',
 })}),
 candidate13:Object.freeze({format:ASSISTED_SMS_FORMAT,identityValidatorSha256:'c0c9fbfb48b44c72c7192acd3853644349a000ba3e7fbf62fdc11037d5f6d4f7',digests:Object.freeze({...quarantineMigrationDigests,
  'migrations/0010_privacy_retention.sql':'94d7ec5146a4ef3e4721cb185a4700edea76c3e72e1cf992dd9fcb2d2e1571d2',
  'migrations/0011_auth_identity_keys.sql':'7e315ad76f45a6e5735d5ee42e7ae94f931e413de37b329a009f31ce9027e8f0',
  'migrations/0012_notification_operator.sql':'f6bfc6603505b8a29338d845707b3347c8c767d230f41f8347a1979d4c70bac7',
  'migrations/0013_sms_receipt_metadata_read.sql':'724f94ab29413b6e1e69c25678078f1e3161d8b0b7bcfe3cd20b1fd25cbc146b',
 })}),
 candidate15:Object.freeze({format:MOMO_FORMAT,identityValidatorSha256:'c0c9fbfb48b44c72c7192acd3853644349a000ba3e7fbf62fdc11037d5f6d4f7',digests:Object.freeze({...quarantineMigrationDigests,
  'migrations/0010_privacy_retention.sql':'94d7ec5146a4ef3e4721cb185a4700edea76c3e72e1cf992dd9fcb2d2e1571d2',
  'migrations/0011_auth_identity_keys.sql':'7e315ad76f45a6e5735d5ee42e7ae94f931e413de37b329a009f31ce9027e8f0',
  'migrations/0012_notification_operator.sql':'f6bfc6603505b8a29338d845707b3347c8c767d230f41f8347a1979d4c70bac7',
  'migrations/0013_sms_receipt_metadata_read.sql':'724f94ab29413b6e1e69c25678078f1e3161d8b0b7bcfe3cd20b1fd25cbc146b',
  'migrations/0014_momo_pipeline.sql':'b31e0590ad4d0b5b2e6acf3c6c069b84ec1cbe8d003eb69f7c5d5f306a3a63d6',
  'migrations/0015_momo_gateway_allocation.sql':'c84e3ea9330c0506781072173af7f5b9a7324017943ca58a967e399df515c422',
 })}),
 candidate17:Object.freeze({format:AUTH_FORMAT,identityValidatorSha256:'c0c9fbfb48b44c72c7192acd3853644349a000ba3e7fbf62fdc11037d5f6d4f7',digests:Object.freeze({...quarantineMigrationDigests,
  'migrations/0010_privacy_retention.sql':'94d7ec5146a4ef3e4721cb185a4700edea76c3e72e1cf992dd9fcb2d2e1571d2',
  'migrations/0011_auth_identity_keys.sql':'7e315ad76f45a6e5735d5ee42e7ae94f931e413de37b329a009f31ce9027e8f0',
  'migrations/0012_notification_operator.sql':'f6bfc6603505b8a29338d845707b3347c8c767d230f41f8347a1979d4c70bac7',
  'migrations/0013_sms_receipt_metadata_read.sql':'724f94ab29413b6e1e69c25678078f1e3161d8b0b7bcfe3cd20b1fd25cbc146b',
  'migrations/0014_momo_pipeline.sql':'b31e0590ad4d0b5b2e6acf3c6c069b84ec1cbe8d003eb69f7c5d5f306a3a63d6',
  'migrations/0015_momo_gateway_allocation.sql':'c84e3ea9330c0506781072173af7f5b9a7324017943ca58a967e399df515c422',
  'migrations/0016_google_auth.sql':'4b225302c08f6b1839dd14256552f0de122a8edb58d22ff05a3e50c44542ca61',
  'migrations/0017_admin_email_otp.sql':'9485792aeff5157859335c629f8a2e96f8da6bb957e1a85922c99c78168f2743',
 })}),
});
const retentionTables=Object.freeze(['privacy_retention_plans','privacy_retention_tasks','privacy_retention_claims','privacy_retention_outcomes','privacy_retention_effects','privacy_retention_guards','privacy_retention_barriers']);
export const assistedSmsRecoveryTables=Object.freeze(['assisted_sms_policies','assisted_sms_authorizations','assisted_sms_jobs','assisted_sms_claims','assisted_sms_confirmations','assisted_sms_send_starts','assisted_sms_outcomes']);

// Exact application table set introduced by14/15, including the financial
// snapshot table. Older plans must reject these even when no rows exist.
export const momoRecoveryTables=Object.freeze(['momo_receiving_accounts','momo_gateway_bindings','momo_processing_jobs','momo_parse_attempts','momo_transactions','momo_transaction_sources','momo_processing_guards','momo_gateway_pairings','momo_gateway_credentials','momo_gateway_captures','momo_source_resolutions','momo_financial_links','contribution_posting_snapshots']);

export const authRecoveryTables=Object.freeze(['auth_google_flows','auth_google_identities','admin_email_otp_challenges']);

export function recoveryQuarantinePlan({archiveSha256,sourceId,operationId,createdAt,schemaProfile='published9'}){
 required(Object.hasOwn(quarantineSchemaProfiles,schemaProfile),'Unknown recovery schema profile');
 const profile=quarantineSchemaProfiles[schemaProfile],retention=schemaProfile!=='published9',identity=['candidate11','candidate12','candidate13','candidate15','candidate17'].includes(schemaProfile),assisted=['candidate12','candidate13','candidate15','candidate17'].includes(schemaProfile),momo=['candidate15','candidate17'].includes(schemaProfile),auth=schemaProfile==='candidate17';
 required(SHA.test(archiveSha256??'')&&SHA.test(sourceId??'')&&UUID.test(operationId??''),'Explicit recovery archive, source and operation identities are required');
 const seconds=Date.parse(createdAt)/1000;
 required(typeof createdAt==='string'&&Number.isSafeInteger(seconds)&&seconds>0&&new Date(seconds*1000).toISOString()===createdAt,'Use an explicit canonical UTC recovery timestamp with whole seconds');
 const details=JSON.stringify({format:profile.format,archive_sha256:archiveSha256,source_id:sourceId,operation_id:operationId,
  policy:'quarantine_all_restored_access',credential_reapproval_required:true,created_at:createdAt,
  ...(retention?{schema_profile:schemaProfile,transient_retention_guards:'drain_without_releasing_subject_barriers'}:{}),
  ...(identity?{identity_alias_history:'retain_all_key_ids_hashes_and_request_links'}:{}),
  ...(assisted?{assisted_sms_history:'retain_all_seven_tables_and_original_session_lineage',decision_fencing:'retain_all_decision_receipts_including_noops_without_reset',send_authority:'not_restored'}:{}),
  ...(auth?{google_identity_history:'retain_stable_subject_links_and_consumed_flow_history',google_handoff_authority:'fail_all_pending_exchanging_ready_flows',admin_email_otp_authority:'supersede_unconsumed_pending_accepted_unknown_codes'}:{}),
  ...(momo?{momo_history:'retain_accounts_profiles_sources_attempts_canonical_financial_links_and_snapshots',momo_gateway_authority:'revoke_bindings_credentials_and_pairing_codes',momo_processing:'pending_retry_processing_require_recovery_review_without_resetting_budgets'}:{})});
 const marker="action='recovery.access.quarantined' AND entity_type='platform_recovery' AND entity_id=? AND request_id=?";
 const absent=`NOT EXISTS(SELECT 1 FROM audit_log WHERE ${marker})`,same=[operationId,operationId];
 const statements=[
  // The retained audit marker makes an unknown-outcome replay a readback. A
  // conflicting reuse fails before any mutation, including on an empty DB.
  {sql:`INSERT INTO admin_bridge_guards(id,passed) VALUES(?,(CASE WHEN
   NOT EXISTS(SELECT 1 FROM audit_log WHERE request_id=?) OR
   (SELECT count(*) FROM audit_log WHERE request_id=?)=1 AND
   EXISTS(SELECT 1 FROM audit_log WHERE ${marker} AND actor_user_id IS NULL AND actor_session_id IS NULL AND details_json=? AND created_at=?)
   THEN 1 ELSE 0 END))`,params:['recovery-quarantine:'+operationId,operationId,operationId,...same,details,createdAt]},
  {sql:`UPDATE auth_sessions SET revoked_at=?,revocation_reason='disaster_recovery_quarantine' WHERE revoked_at IS NULL AND ${absent}`,params:[seconds,...same]},
  // Suspend even accounts whose post-snapshot revocation history is unknown.
  // Do not reactivate already suspended/deleted principals or remove history.
  {sql:`UPDATE users SET access_status='suspended',updated_at=? WHERE access_status='active' AND ${absent}`,params:[createdAt,...same]},
  // Existing role-change triggers remove cookie sessions and account-owned
  // grants. A restored password or invitation must not become a recovery path.
  {sql:`UPDATE admin_users SET status='revoked',password_hash=NULL,auth_version=auth_version+1,challenge_version=challenge_version+1,updated_at=? WHERE status!='revoked' AND ${absent}`,params:[seconds,...same]},
  {sql:`UPDATE auth_otp_challenges SET status='superseded' WHERE status IN('dispatching','accepted','delivery_unknown') AND ${absent}`,params:same},
  {sql:`UPDATE auth_mfa_factors SET status='revoked',revoked_at=? WHERE status IN('pending','verified') AND ${absent}`,params:[seconds,...same]},
  {sql:`UPDATE auth_mfa_challenges SET attempts=5 WHERE consumed_at IS NULL AND attempts<5 AND ${absent}`,params:same},
  {sql:`UPDATE admin_challenges SET used_at=? WHERE used_at IS NULL AND ${absent}`,params:[seconds,...same]},
  {sql:`INSERT INTO audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
   SELECT NULL,NULL,'recovery.access.quarantined','platform_recovery',?,?,?,? WHERE ${absent}`,params:[...same,details,createdAt,...same]},
  {sql:'DELETE FROM admin_bridge_guards WHERE id=?',params:['recovery-quarantine:'+operationId]},
 ];
 // A restored transient guard must not admit routine writes around a retained
 // subject barrier. It carries no immutable decision/effect history. All six
 // retained control classes, including the barrier, remain untouched.
 if(momo)statements.splice(1,0,
  {sql:`UPDATE momo_gateway_bindings SET status='revoked',revoked_at=? WHERE status='active' AND ${absent}`,params:[createdAt,...same]},
  {sql:`UPDATE momo_gateway_credentials SET revoked_at=? WHERE revoked_at IS NULL AND ${absent}`,params:[createdAt,...same]},
  {sql:`UPDATE momo_gateway_pairings SET expires_at=0 WHERE expires_at>0 AND ${absent}`,params:same},
  {sql:`UPDATE momo_processing_jobs SET state='needs_review',lease_token=NULL,lease_until=NULL,last_error='disaster_recovery_quarantine',updated_at=? WHERE state IN('pending','retry','processing') AND ${absent}`,params:[createdAt,...same]},
  {sql:`DELETE FROM momo_processing_guards WHERE ${absent}`,params:same},
 );
 if(auth)statements.splice(1,0,
  {sql:`UPDATE auth_google_flows SET status='failed' WHERE status IN('pending','exchanging','ready') AND ${absent}`,params:same},
  {sql:`UPDATE admin_email_otp_challenges SET delivery_status='superseded' WHERE used_at IS NULL AND delivery_status IN('pending','accepted','unknown') AND ${absent}`,params:same},
 );
 if(retention)statements.splice(1,0,{sql:`DELETE FROM privacy_retention_guards WHERE ${absent}`,params:same});
 return {format:profile.format,archive_sha256:archiveSha256,source_id:sourceId,operation_id:operationId,created_at:createdAt,
  ...(retention?{schema_profile:schemaProfile}:{}),
  execution:'one_transaction_or_one_D1_batch_on_an_isolated_restored_database',statements};
}

export function validateRecoveryQuarantinePlan(plan,controlTableNames){
 const expected=recoveryQuarantinePlan({archiveSha256:plan?.archive_sha256,sourceId:plan?.source_id,operationId:plan?.operation_id,createdAt:plan?.created_at,schemaProfile:plan?.schema_profile??'published9'});
 required(JSON.stringify(plan)===JSON.stringify(expected),'Recovery plan differs from the supported quarantine policy');
 const controls=[...controlTableNames].sort();
 const expectedTables=plan.schema_profile?[...retentionTables,...(['candidate11','candidate12','candidate13','candidate15','candidate17'].includes(plan.schema_profile)?['auth_identity_rate_aliases']:[]),...(['candidate12','candidate13','candidate15','candidate17'].includes(plan.schema_profile)?assistedSmsRecoveryTables:[]),...(['candidate15','candidate17'].includes(plan.schema_profile)?momoRecoveryTables:[]),...(plan.schema_profile==='candidate17'?authRecoveryTables:[])].sort():[];
 required(JSON.stringify(controls)===JSON.stringify(expectedTables),'Recovery plan profile differs from the restored control schema');
 return expected;
}
export function applyRecoveryQuarantine(db,plan){
 const controls=db.prepare("SELECT name FROM sqlite_schema WHERE type='table' AND (name GLOB 'privacy_retention_*' OR name='auth_identity_rate_aliases' OR name GLOB 'assisted_sms_*' OR name GLOB 'momo_*' OR name='contribution_posting_snapshots' OR name IN('auth_google_flows','auth_google_identities','admin_email_otp_challenges')) ORDER BY name").all().map(r=>r.name);
 validateRecoveryQuarantinePlan(plan,controls);
 db.exec('BEGIN');
 try{for(const {sql,params} of plan.statements)db.prepare(sql).run(...params);db.exec('COMMIT');}
 catch(error){db.exec('ROLLBACK');throw error;}
 required(db.prepare('PRAGMA integrity_check').get().integrity_check==='ok'&&db.prepare('PRAGMA foreign_key_check').all().length===0,'Quarantined recovery is inconsistent');
}

export const quarantineMutableTables=Object.freeze(new Set([
 'auth_sessions','users','admin_users','admin_sessions','admin_grants','admin_role_assignments',
 'auth_otp_challenges','auth_mfa_factors','auth_mfa_challenges','admin_challenges','audit_log','sqlite_sequence',
 'auth_google_flows','admin_email_otp_challenges',
 'privacy_retention_guards','momo_gateway_bindings','momo_gateway_credentials','momo_gateway_pairings','momo_processing_jobs','momo_processing_guards',
]));
