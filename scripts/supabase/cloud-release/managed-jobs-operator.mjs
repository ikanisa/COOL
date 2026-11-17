// Explicit, evidenced cloud actions. No action is taken merely by importing.
// A native probe can process one new SMS and one ledger candidate; imported
// history remains denied by the independently verified database guard.
import {randomUUID} from 'node:crypto';
import {lstatSync,readFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {connect,management,record,ROOT,PROJECT,sha} from './access.mjs';
import {validateReadiness} from '../jobs_config.mjs';
import {renderManagedScheduler} from './managed-jobs-scheduler.mjs';
import {sameDeployedFunctions,keyEvidenceForSource} from './managed-jobs-key-operator.mjs';
import {renderNativeProviderBudget} from './native-provider-budget-render.mjs';
import {renderNativeProviderPolicy} from './native-provider-policy-render.mjs';
import {HELD_V2_MIGRATION_SHA,HELD_V2_READY_SHA,HELD_V2_READY_IDENTITY_SQL,HELD_V2_UNEXPECTED_ROLE_SQL} from '../../../supabase/functions/_shared/domain/burimunsi/held-recovery-v2.js';

const HASH=/^[a-f0-9]{64}$/,MODEL=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/;
const GUARDS={
 'private.collect_imported_native_source(text)':'3de5a1c984b9cf3d3e00f0ae8930a85b89cdc9f74f6e70c4744df96717ba2cde',
 'private.collect_imported_native_transaction(text)':'78d4c3a94b6bb10afe1fd7156e3ee6c0499eda4ba6787395ebcc2aea41d8ad0a',
 'private.collect_imported_native_job_transaction(text)':'8d2e921adc9cd1dd424dd80d4f54fe69f8de9ad3b9d10cd7fd14b06823f80878',
 'private.burimunsi_auto_snapshot(text)':'29bcd9f8440ab6d99571871ca7dc0203ec516d6f4d673a91bfc20eb5cef227f6',
 'private.burimunsi_auto_candidates(text)':'de95126024a114bc696bb570b866aece8d2334bd4db5f742428270c71c682e28',
 'private.burimunsi_native_work_candidates(uuid,integer)':'7f6186d02734c5e40ef0e66051d271d1d67e183b2c78ebbe86e7233b78fc729e',
 'private.burimunsi_native_sms_post_candidates(integer)':'9e1a2a348a06f270afb65055c58edc7e88181385adac3dd24991384b86fe0adc',
 'private.collect_imported_native_history_write_guard()':'899374fa5c194daa82a75e16159dbc36811591af55f533c83cafae9fce95e840',
 'private.collect_imported_native_history_link_guard()':'7091ccc5139d763829e9443ad94b8c5ac936fb1677281bb6017f865e92bee24a',
 'private.collect_imported_native_history_ledger_guard()':'828e7dbff6706d23b068836e7d3926810d28aad753a89b3db7acd19acea9e548'};
// This optional migration is accepted only by exact recorded and local bytes.
// A changed draft must deliberately update this pin and its SQL qualification.
const HELD_RECOVERY_SQL_SHA='1decb00238e969e2ad58b7283741bae10a968e7affbddbaf21dc196667a29651';
const HELD_SOURCE_INDEX_SQL_SHA='7a03e8d4e35b7be99c9bf072b4f835654809e582aa8e3247f45582dd686f225c';
const HELD_RESUME_SQL_SHA='870284f6146cf4c1a5ee428e5883c378cd30036333a5da5f062e97d00deefd46';
export const HELD_RESUME_GUARDS={
 'private.collect_sms_held_authorize(text,jsonb)':'c5a843a9d22d62ab475608aefeb44ac4c9fde490207dffd2fb5dddb2c3b93ec7',
 'private.collect_sms_held_payload_guard()':'7f2acd3cdba5b0b2236cc6c4d8e321477b85e652908adb49c86bb830f4fd54ef',
 'private.collect_sms_held_upload_guard()':'297ce148372422ddeb58b29735ec449e63dd61340c8c525a497f2fcc7e646fe1',
 'private.collect_sms_held_resume_check(text,uuid,text,text,timestamptz)':'fa97f3f72d863a8fd715cd63889ca65accfc4563e062f3b5e4798ed0a00a6a7a'};
const HELD_RECOVERY_GUARDS={
 'private.burimunsi_auto_snapshot(text)':'526606c23ad6d8a3b511136a8eff9e2ddf5f7a775f068b5ce8615c02a7a90dd6',
 'private.burimunsi_auto_candidates(text)':'156a2179d3e2065e9116985f3d1a88b034a8cf8c26a988fd48f9ccccc665192f',
 'private.burimunsi_native_work_candidates(uuid,integer)':'d218510947003efd8721305b84afb16b60b69a93308bbef4c85b69095a1514ea',
 'private.burimunsi_native_sms_post_candidates(integer)':'0b0778810e6e86f83dc7cbc950b2aa9b258a7e6ee2d1a3c85c48e8ce41e4521e',
 'private.collect_sms_held_source_guard()':'a3029d9460cc7f515aed5096cde699ee120e95537a3e5261893a5e09b52f9cc0',
 'private.collect_sms_recovery_held(text)':'353a9c76dfe04e60f62ddd005dddcba1f4da423fa48113284f733d134e0ac3ca',
 'private.collect_sms_recovery_work_guard()':'d34eb5497661179bd817c73fb981b2fec215d2ccf773b03cbfba520f5d183b87',
 'private.collect_sms_recovery_raw_work_guard()':'339cb3e77b644ddb359e74b6847a1698bbee4c3023caaf3a7118c2a8b8d13b6d',
 'private.collect_sms_recovery_transaction_matches(text,text)':'d0eb949bf0e1547abd080e13262df14004e4225a2e50958d014d4f91703650ad',
 'private.collect_sms_recovery_scope_guard()':'981338e7866ed560955ad98627f0f2eddb84f0e9e142b57521429740009a4a18',
 'private.collect_sms_recovery_financial_guard()':'0bbe97cd0928561597413749053a9e7ef2a5b1c8569e985be0337f38d5347e71',
 'private.collect_sms_witness_immutable()':'8002c6a0cb39fc691c5027ece5e1af15458334805ab25ecef9cc67f9ca43cc2c',
 'private.collect_sms_request_witness_guard()':'ccf51907a4e2ff6107c925b6cf9a34c2fba58786c48907c5033362cba4d388cc',
 'private.collect_sms_payload_witness_guard()':'4d6bac36fc6b05c7f947459cb47d58287a4191080ad07fc091c9663c4b287155',
 'private.collect_sms_witness_reserve(text,text,text,text,text,text,timestamptz,text)':'08604196e97299947b1dac9237297d00566959cfce18963c4c4e785ed3a813e1',
 'private.burimunsi_sms_recovery_hold(text,uuid,text,text,timestamptz)':'9d4ab9d548e4d544a918f81f4b0072389de1abee6c070492d4d3609137c6bd8a',
 'private.burimunsi_sms_recovery_ack_snapshot(text,uuid,text,text,text,text,timestamptz)':'573323471c79766de7dbe908aec97bb29eede153cdd066e89308ee75ee8f86c5',
 'private.burimunsi_observation_actor(boolean)':'e6f1bf1db6c84209a8bf00465201e1db997dc8c03a972399af7e6fcb48f4f9e1',
 'private.burimunsi_observation_consent_current()':'4c7f0cea13f47ef0a040c36e3059ded889f42932f0696a554513bf470fa060f9',
 'private.burimunsi_observation_own(text,boolean)':'f306b9c50fafa238f64816bf7a242a21d9f828ad9df5a8c565ada001b15aa7d1',
 'private.burimunsi_observation_lookup(uuid,text)':'bda49fee71b6944325a1fa9d7d884016a00691f4a9a4a0b0f7212a4fb50c71ae',
 'private.burimunsi_observation_reconcile_status()':'dbc081cd16057fb2bf07da3514aab3b3afe4e7d35427651bd8187da0e809c30e',
 'private.burimunsi_observation_reconcile_verified_status()':'9a8ed9eed540ff7eac74a85ae3765fb10e8eb1b81d3017046eccc62f0d46f4b0'};
export function schedulerGuardDigests(recordedDigest,localDigest){
 if(recordedDigest===null)return {...GUARDS};
 if(recordedDigest!==HELD_RECOVERY_SQL_SHA||localDigest!==HELD_RECOVERY_SQL_SHA)throw Error('scheduler_migration_changed');
 return {...GUARDS,...HELD_RECOVERY_GUARDS};
}
// Read-only catalog checks for every candidate-specific trigger, including its
// timing/events and deferred status, plus the effective table privileges and
// exact RLS policy. A missing relation, role, policy or trigger fails closed.
export const HELD_RECOVERY_CATALOG_SQL=`WITH expected(relation_name,trigger_name,function_name,trigger_type,deferred) AS (VALUES
 ('app.sms_receipts','collect_sms_held_source_guard','private.collect_sms_held_source_guard()',23,false),
 ('private.burimunsi_auto_sms_jobs','collect_sms_recovery_work_guard','private.collect_sms_recovery_work_guard()',31,false),
 ('private.burimunsi_native_financial_work','collect_sms_recovery_work_guard','private.collect_sms_recovery_work_guard()',31,false),
 ('app.momo_processing_jobs','collect_sms_recovery_raw_work_guard','private.collect_sms_recovery_raw_work_guard()',31,false),
 ('app.momo_parse_attempts','collect_sms_recovery_raw_work_guard','private.collect_sms_recovery_raw_work_guard()',31,false),
 ('app.momo_transaction_sources','collect_sms_recovery_raw_work_guard','private.collect_sms_recovery_raw_work_guard()',31,false),
 ('private.burimunsi_transaction_scopes','collect_sms_recovery_scope_guard','private.collect_sms_recovery_scope_guard()',23,false),
 ('app.momo_financial_links','collect_sms_recovery_financial_guard','private.collect_sms_recovery_financial_guard()',23,false),
 ('app.payments','collect_sms_recovery_financial_guard','private.collect_sms_recovery_financial_guard()',19,false),
 ('private.burimunsi_observation_requests','collect_sms_request_witness_guard','private.collect_sms_request_witness_guard()',5,true),
 ('private.storage_payload_reservations','collect_sms_payload_witness_guard','private.collect_sms_payload_witness_guard()',7,false),
 ('private.collect_sms_witnesses','collect_sms_witness_immutable','private.collect_sms_witness_immutable()',19,false),
 ('private.burimunsi_recovered_sms_holds','recovered_sms_hold_immutable','private._collect_fence_no_erasure()',18,false),
 ('private.collect_sms_witnesses','collect_fence_statement_v1','private._collect_fence_statement()',62,false),
 ('private.burimunsi_recovered_sms_holds','collect_fence_statement_v1','private._collect_fence_statement()',62,false),
 ('private.collect_sms_witnesses','collect_sms_no_erasure','private._collect_fence_no_erasure()',42,false),
 ('private.burimunsi_recovered_sms_holds','collect_sms_no_erasure','private._collect_fence_no_erasure()',42,false)
), checked_triggers AS (
 SELECT e.*,coalesce(t.tgfoid=to_regprocedure(e.function_name) AND t.tgenabled='A' AND NOT t.tgisinternal
  AND t.tgtype::int=e.trigger_type AND t.tgdeferrable=e.deferred AND t.tginitdeferred=e.deferred
  AND (t.tgconstraint<>0)=e.deferred AND t.tgqual IS NULL AND t.tgnargs=0
  AND CASE WHEN e.relation_name='app.payments' THEN t.tgattr::text=(SELECT a.attnum::text FROM pg_attribute a
   WHERE a.attrelid=t.tgrelid AND a.attname='collection_id' AND NOT a.attisdropped) ELSE t.tgattr::text='' END,false) ok
 FROM expected e LEFT JOIN pg_trigger t ON t.tgrelid=to_regclass(e.relation_name) AND t.tgname=e.trigger_name
), checked_tables AS (
 SELECT n.relation_name,coalesce(c.relkind='r' AND c.relowner='postgres'::regrole AND c.relrowsecurity AND c.relforcerowsecurity
  AND NOT EXISTS(SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role','collect_importer','collect_runtime']) role_name
   CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) privilege_name
   WHERE has_table_privilege(role_name,c.oid,privilege_name))
  AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) acl WHERE acl.grantee=0)
  AND (SELECT count(*)=1 AND bool_and(p.polname='collect_sms_witness_owner_frame' AND p.polcmd='*'
    AND p.polpermissive AND p.polroles=ARRAY['postgres'::regrole::oid]
    AND pg_get_expr(p.polqual,p.polrelid)=$1 AND pg_get_expr(p.polwithcheck,p.polrelid)=$1)
   FROM pg_policy p WHERE p.polrelid=c.oid),false) ok
 FROM (VALUES('private.collect_sms_witnesses'),('private.burimunsi_recovered_sms_holds')) n(relation_name)
 LEFT JOIN pg_class c ON c.oid=to_regclass(n.relation_name)
) SELECT (SELECT count(*)=17 AND bool_and(ok) FROM checked_triggers) triggers_ok,
 (SELECT count(*)=2 AND bool_and(ok) FROM checked_tables) tables_ok`;
export const HELD_RECOVERY_POLICY="((current_setting('role'::text, true) = 'collect_runtime'::text) AND (current_setting('collect.edge_verified'::text, true) = 'true'::text) AND (current_setting('collect.sms_witness_frame'::text, true) = '1'::text))";
export function verifyHeldRecoveryCatalog(row){
 if(row?.triggers_ok!==true||row?.tables_ok!==true)throw Error('scheduler_or_history_guard_changed');
}
export const HELD_SOURCE_INDEX_CATALOG_SQL=`SELECT count(*)=1 AND bool_and(c.relowner='postgres'::regrole
 AND i.indrelid=to_regclass('app.momo_transaction_sources') AND c.relkind='i' AND am.amname='btree'
 AND i.indisvalid AND i.indisready AND i.indislive AND NOT i.indisunique AND NOT i.indisexclusion
 AND i.indpred IS NULL AND i.indexprs IS NULL AND i.indnkeyatts=2 AND i.indnatts=2
 AND (SELECT array_agg(a.attname::text ORDER BY k.position) FROM unnest(i.indkey) WITH ORDINALITY k(attnum,position)
  JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k.attnum AND NOT a.attisdropped)=ARRAY['raw_sms_id','transaction_id']) ok
 FROM pg_class c JOIN pg_index i ON i.indexrelid=c.oid JOIN pg_am am ON am.oid=c.relam
 WHERE c.oid=to_regclass('app.burimunsi_momo_sources_raw_lookup')`;
export const HELD_RESUME_CATALOG_SQL=`WITH expected(relation_name,trigger_name,function_name,trigger_type) AS (VALUES
 ('private.storage_payload_reservations','collect_sms_held_payload_guard','private.collect_sms_held_payload_guard()',7),
 ('private.storage_upload_attempts','collect_sms_held_upload_guard','private.collect_sms_held_upload_guard()',7),
 ('private.storage_upload_attempts','storage_upload_identity','private.trg_storage_identity()',27),
 ('private.storage_put_intents','storage_put_identity','private.trg_storage_identity()',27)
) SELECT count(*)=4 AND bool_and(coalesce(t.tgfoid=to_regprocedure(e.function_name) AND t.tgenabled='A' AND NOT t.tgisinternal
 AND t.tgtype::int=e.trigger_type AND NOT t.tgdeferrable AND NOT t.tginitdeferred AND t.tgconstraint=0
 AND t.tgqual IS NULL AND t.tgnargs=0 AND t.tgattr::text='',false)) AS ok
 FROM expected e LEFT JOIN pg_trigger t ON t.tgrelid=to_regclass(e.relation_name) AND t.tgname=e.trigger_name`;
function privateBytes(name){if(!/^[a-z0-9_.-]+\.json$/.test(name))throw Error('invalid_evidence_name');const p=join(ROOT,name),s=lstatSync(p);
 if(!s.isFile()||s.isSymbolicLink()||s.nlink!==1||s.uid!==process.getuid()||(s.mode&0o077)!==0||s.size<2||s.size>1024*1024)throw Error('private_evidence_required');return readFileSync(p);}
const privateJson=name=>JSON.parse(privateBytes(name).toString('utf8'));
export function parseManagedReadiness(bytes,now=Date.now()){
 const r=JSON.parse(bytes.toString('utf8')),native=Object.hasOwn(r,'native_sms_admission'),base={...r};
 for(const k of ['native_sms_admission','native_provider_evidence_sha256','native_guard_evidence_sha256','remaining_native_provider_requests'])delete base[k];
 if(base.format!=='collect.jobs.readiness.v1')throw Error('maintenance_readiness_required');validateReadiness(base,now);
 if(base.remaining_invocations<50000)throw Error('native_readiness_invalid');
 const optional=['native_sms_admission','native_provider_evidence_sha256','native_guard_evidence_sha256','remaining_native_provider_requests'];
 if(native){const a=r.native_sms_admission,keys=['contract','source_sha256','approval_sha256','model_id','batch_limit'];
  if(optional.some(k=>!Object.hasOwn(r,k))||!a||typeof a!=='object'||Array.isArray(a)||Object.keys(a).length!==keys.length||Object.keys(a).some(k=>!keys.includes(k))||
   a.contract!=='collect.native-sms-automation.v1'||!HASH.test(a.source_sha256??'')||!HASH.test(a.approval_sha256??'')||!MODEL.test(a.model_id??'')||a.batch_limit!==1||
   !HASH.test(r.native_provider_evidence_sha256??'')||!HASH.test(r.native_guard_evidence_sha256??'')||
   !(r.remaining_native_provider_requests===null||Number.isSafeInteger(r.remaining_native_provider_requests)&&r.remaining_native_provider_requests>=2))throw Error('native_readiness_invalid');
 }else if(optional.some(k=>Object.hasOwn(r,k)))throw Error('native_readiness_invalid');
 return {readiness:{...r,evidence_file_sha256:sha(bytes)},native};
}
export function expectedSchedulerBodies(sql){
 const matches=[...sql.matchAll(/CREATE FUNCTION collect_ops\.([a-z_]+)\([^]*?\) RETURNS [^]*? AS \$\$([^]*?)\$\$;/g)];
 const expected=new Map(matches.map(m=>[m[1],sha(m[2])]));
 if(expected.size!==9||matches.length!==9)throw Error('scheduler_source_shape_changed');
 const claim=/CREATE FUNCTION private\.collect_managed_job_claim\([^]*?AS \$claim\$([^]*?)\$claim\$;/.exec(sql);
 const complete=/CREATE FUNCTION private\.collect_managed_job_complete\([^]*?AS \$complete\$([^]*?)\$complete\$;/.exec(sql);
 if(!claim||!complete)throw Error('scheduler_source_shape_changed');
 return {ops:Object.fromEntries(expected),private:{collect_managed_job_claim:sha(claim[1]),collect_managed_job_complete:sha(complete[1])}};
}
async function inspect(db){
 const [scheduler,graph]=await Promise.all([renderManagedScheduler(),Promise.resolve(privateJson('graph-import-attempt-002-result.json'))]);
 if(sha(readFileSync(new URL('../../../supabase/migrations/20261117073850_collect_managed_jobs_hmac.sql',import.meta.url)))!==scheduler.sqlSha)throw Error('scheduler_migration_changed');
 const f=(await db.query('SELECT mode,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
 const key=keyEvidenceForSource(f?.source_sha256);
 if(f?.mode!=='open'||f.source_sha256!==key.sourceSha256||key.project!==PROJECT||!HASH.test(key.keySha256??'')||!Array.isArray(key.functions))throw Error('runtime_or_key_changed');
 const [functionResult,secretResult]=await Promise.all([management('functions'),management('secrets')]);
 const funcs=functionResult.json();if(!sameDeployedFunctions(key.functions,funcs))throw Error('deployed_function_changed');
 const secrets=new Map(secretResult.json().map(x=>[x.name,x.value]));
 if(secrets.get('BUILD_SOURCE_ID')!==sha(f.source_sha256)||secrets.get('COLLECT_JOB_AUTH_MODE')!==sha('supabase_dispatch_hmac_v1')||secrets.get('COLLECT_JOB_SIGNING_KEY')!==key.keySha256||
  secrets.get('MOMO_PROCESSING_PAUSED')!==sha('true'))throw Error('runtime_or_key_changed');
 const scheduleFile='20261117135049_collect_sms_schedule_one_minute.sql',scheduleSha='df5ff3ec33e8e8d02c182072abd99e0c24705fb74f1f85514b46f9da9149300c';
 const scheduleHistory=(await db.query("SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') digest FROM supabase_migrations.schema_migrations WHERE version=$1",[scheduleFile.slice(0,14)])).rows[0];
 if(scheduleHistory&&(scheduleHistory.digest!==scheduleSha||sha(readFileSync(new URL('../../../supabase/migrations/'+scheduleFile,import.meta.url)))!==scheduleSha))throw Error('scheduler_migration_changed');
 const row=(await db.query(`SELECT c.enabled,c.config_sha256,c.template_sha256,c.readiness,c.last_probe_id,
  c.native_provider_source_sha256,c.native_provider_model_id,c.native_provider_approval_sha256,c.native_provider_expires_at,c.native_provider_limit,c.native_provider_used,
  j.jobname,j.schedule,j.command,j.database,j.username,j.active,
  (SELECT count(*)::int FROM vault.decrypted_secrets WHERE name='collect_job_signing_key_v1') AS keys,
  (SELECT encode(sha256(convert_to(decrypted_secret,'UTF8')),'hex') FROM vault.decrypted_secrets WHERE id=$1::uuid AND name='collect_job_signing_key_v1') AS key_sha,
  (SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') FROM supabase_migrations.schema_migrations WHERE version='20261117073850') AS migration_sha,
  (SELECT count(*)::int FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed')) AS pending,
  (SELECT count(*)::int FROM private.collect_imported_native_history) AS historical,
  (SELECT count(*)=4 AND bool_and(tgenabled='A') FROM pg_trigger WHERE NOT tgisinternal AND tgname='collect_imported_native_history_guard' AND tgrelid IN('private.burimunsi_auto_sms_jobs'::regclass,'private.burimunsi_native_financial_work'::regclass,'app.momo_financial_links'::regclass,'app.ledger_entries'::regclass)) AS triggers_ok,
  private._collect_fence_scheduler_status()->'coverageVerified' AS scheduler_coverage
  FROM collect_ops.jobs_config c JOIN cron.job j ON j.jobid=c.cron_job_id WHERE c.singleton`,[key.vaultId])).rows[0];
 if(!row||row.config_sha256!==scheduler.configSha||row.template_sha256!==scheduler.templateSha||row.migration_sha!==scheduler.sqlSha||row.keys!==1||row.key_sha!==key.keySha256||
  row.jobname!=='collect-jobs-maintenance-v1'||row.schedule!==(scheduleHistory?'* * * * *':'*/5 * * * *')||row.command!=='SELECT collect_ops.tick_jobs();'||row.database!=='postgres'||row.username!=='postgres'||
  row.historical!==graph.counts?.sms||row.historical!==37||row.triggers_ok!==true||row.scheduler_coverage!==true)throw Error('scheduler_or_history_guard_changed');
 const heldFile='20261117210000_burimunsi_held_recovery.sql';
 const heldHistory=(await db.query("SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') digest FROM supabase_migrations.schema_migrations WHERE version=$1",[heldFile.slice(0,14)])).rows[0];
 const resumeFile='20261117220000_burimunsi_held_resume_guard.sql';
 const resumeHistory=(await db.query("SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') digest FROM supabase_migrations.schema_migrations WHERE version=$1",[resumeFile.slice(0,14)])).rows[0];
 const v2File='20261117220639_burimunsi_held_consent_v2.sql';
 const v2History=(await db.query("SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') digest FROM supabase_migrations.schema_migrations WHERE version=$1",[v2File.slice(0,14)])).rows[0];
 const indexFile='20261117205959_burimunsi_sms_source_index.sql';
 const indexHistory=(await db.query("SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') digest FROM supabase_migrations.schema_migrations WHERE version=$1",[indexFile.slice(0,14)])).rows[0];
 if(heldHistory&&!indexHistory)throw Error('scheduler_or_history_guard_changed');
 if(heldHistory&&!resumeHistory||resumeHistory&&!heldHistory)throw Error('scheduler_or_history_guard_changed');
 if(v2History){
  if(!heldHistory||!resumeHistory||!indexHistory||v2History.digest!==HELD_V2_MIGRATION_SHA||
   sha(readFileSync(new URL('../../../supabase/migrations/'+v2File,import.meta.url)))!==HELD_V2_MIGRATION_SHA||
   (await db.query(HELD_V2_READY_IDENTITY_SQL,[HELD_V2_READY_SHA])).rows[0]?.ok!==true)throw Error('scheduler_or_history_guard_changed');
  const wrapper=(await db.query(`SELECT coalesce(p.proowner='postgres'::regrole AND p.prosecdef AND p.provolatile='v'
   AND l.lanname='plpgsql' AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
   AND p.proacl::text='{postgres=X/postgres,collect_runtime=X/postgres}'
   AND NOT ${HELD_V2_UNEXPECTED_ROLE_SQL}
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='96216aa4f5d3107aa08678ead3bf49b1cdc9e60dda2321475176b85f06fe3ce0',false) AS ok
   FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure('private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint,text,text)')`)).rows[0];
  if(wrapper?.ok!==true)throw Error('scheduler_or_history_guard_changed');
 }
 if(indexHistory){
  if(indexHistory.digest!==HELD_SOURCE_INDEX_SQL_SHA||sha(readFileSync(new URL('../../../supabase/migrations/'+indexFile,import.meta.url)))!==HELD_SOURCE_INDEX_SQL_SHA||
   (await db.query(HELD_SOURCE_INDEX_CATALOG_SQL)).rows[0]?.ok!==true)throw Error('scheduler_or_history_guard_changed');
 }
 if(resumeHistory&&(resumeHistory.digest!==HELD_RESUME_SQL_SHA||sha(readFileSync(new URL('../../../supabase/migrations/'+resumeFile,import.meta.url)))!==HELD_RESUME_SQL_SHA))throw Error('scheduler_migration_changed');
 const expectedGuards={...schedulerGuardDigests(heldHistory?.digest??null,heldHistory?sha(readFileSync(new URL('../../../supabase/migrations/'+heldFile,import.meta.url))):null),
  ...(resumeHistory?HELD_RESUME_GUARDS:{})};
 const guard=(await db.query(`SELECT x.signature,p.proowner::regrole::text owner,p.prosecdef,p.proacl::text acl,p.proconfig,p.provolatile,l.lanname,
  encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') digest
  FROM unnest($1::text[]) x(signature) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(x.signature)
  LEFT JOIN pg_language l ON l.oid=p.prolang`,[Object.keys(expectedGuards)])).rows;
 if(guard.length!==Object.keys(expectedGuards).length||guard.some(x=>x.owner!=='postgres'||x.prosecdef!==true||x.digest!==expectedGuards[x.signature]))throw Error('scheduler_or_history_guard_changed');
 if(resumeHistory&&guard.some(x=>Object.hasOwn(HELD_RESUME_GUARDS,x.signature)&&
  (x.provolatile!=='v'||x.lanname!=='plpgsql'||JSON.stringify(x.proconfig)!==JSON.stringify(['search_path=pg_catalog, pg_temp']))))throw Error('scheduler_or_history_guard_changed');
 if(heldHistory){
  const heldPrivate=['private.collect_sms_held_source_guard()','private.collect_sms_recovery_held(text)',
   'private.collect_sms_recovery_work_guard()','private.collect_sms_recovery_raw_work_guard()',
   'private.collect_sms_recovery_transaction_matches(text,text)','private.collect_sms_recovery_scope_guard()',
   'private.collect_sms_recovery_financial_guard()',
   'private.collect_sms_witness_immutable()','private.collect_sms_request_witness_guard()','private.collect_sms_payload_witness_guard()',
   'private.collect_sms_held_upload_guard()','private.collect_sms_held_payload_guard()',
   'private.burimunsi_observation_actor(boolean)'];
  const heldRuntime=['private.collect_sms_witness_reserve(text,text,text,text,text,text,timestamptz,text)',
   'private.burimunsi_sms_recovery_hold(text,uuid,text,text,timestamptz)',
   'private.burimunsi_sms_recovery_ack_snapshot(text,uuid,text,text,text,text,timestamptz)',
   'private.burimunsi_observation_consent_current()','private.burimunsi_observation_own(text,boolean)',
   'private.burimunsi_observation_lookup(uuid,text)',
   'private.burimunsi_observation_reconcile_status()','private.burimunsi_observation_reconcile_verified_status()',
   'private.collect_sms_held_resume_check(text,uuid,text,text,timestamptz)','private.collect_sms_held_authorize(text,jsonb)'];
  if(guard.some(x=>heldPrivate.includes(x.signature)&&x.acl!=='{postgres=X/postgres}'||
   heldRuntime.includes(x.signature)&&x.acl!=='{postgres=X/postgres,collect_runtime=X/postgres}'))throw Error('scheduler_or_history_guard_changed');
  verifyHeldRecoveryCatalog((await db.query(HELD_RECOVERY_CATALOG_SQL,[HELD_RECOVERY_POLICY])).rows[0]);
  const identity=(await db.query(`SELECT p.proowner::regrole::text owner,p.prosecdef,p.proconfig,p.provolatile,l.lanname,
   encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') digest FROM pg_proc p
   JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure('private.trg_storage_identity()')`)).rows[0];
  if((await db.query(HELD_RESUME_CATALOG_SQL)).rows[0]?.ok!==true||identity?.owner!=='postgres'||identity.prosecdef!==false||
   identity.provolatile!=='v'||identity.lanname!=='plpgsql'||JSON.stringify(identity.proconfig)!==JSON.stringify(['search_path=pg_catalog'])||
   identity.digest!=='2d1816d30d91303bb7f4e4df4a3cae5c3913f0d2a147da8bb057628d2e4ccddf')throw Error('scheduler_or_history_guard_changed');
 }
 const expected=expectedSchedulerBodies(scheduler.sql);
 if(scheduleHistory){
  expected.ops.dispatch_jobs='00e49b5d9603cd8564555252cc62b23d667fd9f611c558c46459e4b7580d9f72';
  expected.ops.activate_jobs='18fb407a536fa422aa539a15b161c75af638a295159f020eebc5af1692c188d3';
 }
 // The parser migration is optional until the source-bound cutover is recorded.
 const reviewMigration='20261117090952_burimunsi_native_parse_review.sql';
 const review=(await db.query("SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') digest FROM supabase_migrations.schema_migrations WHERE version=$1",[reviewMigration.slice(0,14)])).rows[0];
 if(review){
  const reviewedSha='6c9d990e607b0ca5470992c39a4b82101f1fe86407a0f64a7e18c400ac653d24';
  if(review.digest!==reviewedSha||sha(readFileSync(new URL('../../../supabase/migrations/'+reviewMigration,import.meta.url)))!==reviewedSha)throw Error('scheduler_migration_changed');
  const reviewedFunctions={
   'private.burimunsi_auto_retry(text,uuid,text,text,text)':'e459ea6c476b0e294692f0cdfff6df84aa547061ffe0ee94e99422eda9c88b23',
   'private.burimunsi_auto_finish(text,uuid,text,text,uuid,text,jsonb,jsonb)':'696e8861aabee891836369f3c5243efd5403791503a0be9f7e29831d967a22c7',
   'private.burimunsi_native_sms_post_facts(text,text,jsonb,jsonb)':'943d9979691711175a2e6bc1ebfa3b0dc96a093e9f280fc55904a67641850a22'};
  const reviewed=(await db.query(`SELECT x.signature,p.proowner::regrole::text owner,p.prosecdef,
   encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') digest,p.proacl::text acl
   FROM unnest($1::text[]) x(signature) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(x.signature)`,[Object.keys(reviewedFunctions)])).rows;
  if(reviewed.length!==3||reviewed.some(x=>x.owner!=='postgres'||x.prosecdef!==true||x.acl!=='{postgres=X/postgres,collect_runtime=X/postgres}'||x.digest!==reviewedFunctions[x.signature]))throw Error('scheduler_source_shape_changed');
 }
 const budget=await renderNativeProviderBudget();
 const budgetFile='20261117081411_collect_native_provider_budget.sql';
 if(sha(readFileSync(new URL('../../../supabase/migrations/'+budgetFile,import.meta.url)))!==budget.sqlSha256)throw Error('scheduler_migration_changed');
 const budgetHistory=(await db.query("SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') digest FROM supabase_migrations.schema_migrations WHERE version=$1",[budgetFile.slice(0,14)])).rows[0];
 let readiness=/CREATE OR REPLACE FUNCTION collect_ops\.record_jobs_readiness\([^]*? AS \$\$([^]*?)\$\$;/.exec(budget.sql);
 let setup=/CREATE FUNCTION collect_ops\.configure_native_provider_budget\([^]*? AS \$budget_setup\$([^]*?)\$budget_setup\$;/.exec(budget.sql);
 let reserve=/CREATE FUNCTION private\.collect_native_provider_reserve\([^]*? AS \$budget_reserve\$([^]*?)\$budget_reserve\$;/.exec(budget.sql);
 if(budgetHistory?.digest!==budget.sqlSha256||!readiness||!setup||!reserve)throw Error('scheduler_source_shape_changed');
 const policy=await renderNativeProviderPolicy(),policyFile='20261117134926_collect_native_provider_policy.sql';
 const policyHistory=(await db.query("SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') digest FROM supabase_migrations.schema_migrations WHERE version=$1",[policyFile.slice(0,14)])).rows[0];
 if(policyHistory){
  if(policyHistory.digest!==policy.sqlSha256||sha(readFileSync(new URL('../../../supabase/migrations/'+policyFile,import.meta.url)))!==policy.sqlSha256)throw Error('scheduler_migration_changed');
  readiness=/ AS \$\$([^]*?)\$\$;/.exec(policy.readiness);
  setup=/ AS \$budget_setup\$([^]*?)\$budget_setup\$;/.exec(policy.setup);
  reserve=/ AS \$budget_reserve\$([^]*?)\$budget_reserve\$;/.exec(policy.reserve);
  if(!readiness||!setup||!reserve)throw Error('scheduler_source_shape_changed');
 }
 const schedulerBody=/AS \$fn\$([^]*?)\$fn\$;/.exec(budget.schedulerStatus);
 const schedulerStatus=(await db.query("SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') digest FROM pg_proc WHERE oid='private._collect_fence_scheduler_status()'::regprocedure")).rows[0];
 if(!schedulerBody||schedulerStatus?.digest!==sha(schedulerBody[1]))throw Error('scheduler_source_shape_changed');
 expected.ops.record_jobs_readiness=sha(readiness[1]);
 const budgetFns=(await db.query(`SELECT p.proname,p.proowner::regrole::text owner,p.prosecdef,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') digest,
  has_function_privilege('collect_runtime',p.oid,'EXECUTE') runtime_execute,has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,has_function_privilege('service_role',p.oid,'EXECUTE') service_execute
  FROM pg_proc p WHERE p.oid IN('collect_ops.configure_native_provider_budget(text,text,text,timestamptz)'::regprocedure,'private.collect_native_provider_reserve(uuid,text,text,text)'::regprocedure)`)).rows;
 if(budgetFns.length!==2||budgetFns.some(x=>x.owner!=='postgres'||x.anon_execute||x.authenticated_execute||x.service_execute||
  (x.proname==='collect_native_provider_reserve'?(x.digest!==sha(reserve[1])||!x.prosecdef||!x.runtime_execute):(x.digest!==sha(setup[1])||x.prosecdef||x.runtime_execute))))throw Error('scheduler_source_shape_changed');
 const ops=(await db.query(`SELECT p.proname,p.proowner::regrole::text owner,p.prosecdef,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') digest
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='collect_ops' AND p.proname=ANY($1::text[])`,[Object.keys(expected.ops)])).rows;
 if(ops.length!==9||ops.some(x=>x.owner!=='postgres'||x.prosecdef!==false||x.digest!==expected.ops[x.proname]))throw Error('scheduler_source_shape_changed');
 const claims=(await db.query(`SELECT p.proname,p.proowner::regrole::text owner,p.prosecdef,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') digest,
  has_function_privilege('collect_runtime',p.oid,'EXECUTE') runtime_execute,has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,has_function_privilege('service_role',p.oid,'EXECUTE') service_execute
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname=ANY($1::text[])`,[Object.keys(expected.private)])).rows;
 const ticket=(await db.query(`SELECT c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner) owner,
  has_table_privilege('collect_runtime',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') runtime_access,
  (SELECT count(*)=1 AND bool_and(tgenabled='A') FROM pg_trigger WHERE tgrelid=c.oid AND tgname='collect_fence_statement_v1' AND NOT tgisinternal) guarded
  FROM pg_class c WHERE c.oid='private.collect_managed_job_tickets'::regclass`)).rows[0];
 if(claims.length!==2||claims.some(x=>x.owner!=='postgres'||x.prosecdef!==true||x.digest!==expected.private[x.proname]||!x.runtime_execute||x.anon_execute||x.authenticated_execute||x.service_execute)||
  !ticket||ticket.owner!=='postgres'||!ticket.relrowsecurity||!ticket.relforcerowsecurity||ticket.runtime_access||!ticket.guarded)throw Error('scheduler_source_shape_changed');
 return {row,secrets,source:f.source_sha256};
}
export function verifyNativeBudget(pre,r,now=Date.now()){
 const a=r.native_sms_admission,c=pre.row;
 const safeInt=v=>typeof v==='number'?Number.isSafeInteger(v)?v:null:typeof v==='string'&&/^(0|[1-9][0-9]{0,15})$/.test(v)&&Number.isSafeInteger(Number(v))?Number(v):null;
 const used=safeInt(c.native_provider_used),limit=c.native_provider_limit===null?null:safeInt(c.native_provider_limit);
 const expiry=c.native_provider_expires_at===null?null:Date.parse(c.native_provider_expires_at);
 if(c.native_provider_source_sha256!==pre.source||c.native_provider_model_id!==a.model_id||c.native_provider_approval_sha256!==a.approval_sha256||
  used===null||used<0||(c.native_provider_limit!==null&&(limit===null||limit<0))||
  (expiry!==null&&(!Number.isFinite(expiry)||expiry<=now))||
  (limit===null?r.remaining_native_provider_requests!==null:
   !Number.isSafeInteger(r.remaining_native_provider_requests)||r.remaining_native_provider_requests<2||r.remaining_native_provider_requests>limit-used))throw Error('native_readiness_invalid');
}
function verifyMode(pre,r,native){
 if(r.project_ref!==PROJECT||r.endpoint!==`https://${PROJECT}.supabase.co/functions/v1/collect-jobs`)throw Error('readiness_project_changed');
 if(native){verifyNativeBudget(pre,r);const a=r.native_sms_admission;if(a.source_sha256!==pre.source||pre.secrets.get('BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED')!==sha('true')||
  pre.secrets.get('MOMO_AI_ENABLED')!==sha('true')||pre.secrets.get('MOMO_AI_MODEL')!==sha(a.model_id)||
  pre.secrets.get('COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256')!==sha(a.approval_sha256)||!pre.secrets.has('OPENAI_API_KEY'))throw Error('native_config_not_qualified');
 }else if(pre.secrets.get('BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED')!==sha('false'))throw Error('maintenance_requires_native_disabled');
}
async function main(){
 const [action,evidenceName]=process.argv.slice(2);if(!['--status','--pause','--configure-native','--recover-native-config','--probe','--reconcile','--activate'].includes(action))throw Error('explicit_action_required');
 if(['--configure-native','--recover-native-config','--probe','--activate'].includes(action)!==Boolean(evidenceName)||process.argv.length!==(evidenceName?4:3))throw Error('evidence_argument_required');
 const input=evidenceName?parseManagedReadiness(privateBytes(evidenceName)):null,db=await connect();
 try{
  let pre=await inspect(db);
  if(action==='--status'){console.log(JSON.stringify({project:PROJECT,sourceSha256:pre.source,enabled:pre.row.enabled,cronActive:pre.row.active,pending:pre.row.pending,historicalProtected:pre.row.historical}));return;}
  if(action==='--pause'){const s=(await db.query('SELECT collect_ops.pause_jobs() AS state')).rows[0].state;console.log(JSON.stringify({enabled:s.enabled,cronActive:s.cron_active}));return;}
  if(action==='--reconcile'){const r=(await db.query('SELECT collect_ops.reconcile_jobs() AS result')).rows[0].result;const s=(await db.query('SELECT collect_ops.jobs_state() AS state')).rows[0].state;console.log(JSON.stringify({reconciliation:r,enabled:s.enabled,cronActive:s.cron_active,awaiting:s.awaiting,unconfirmed:s.unconfirmed}));return;}
  if(action==='--configure-native'||action==='--recover-native-config'){
   if(!input.native||input.readiness.native_sms_admission.source_sha256!==pre.source||!pre.secrets.has('OPENAI_API_KEY'))throw Error('native_readiness_invalid');
   verifyNativeBudget(pre,input.readiness);
   const configName='managed-jobs-native-config-'+pre.source.slice(0,16)+'-intent.json',a=input.readiness.native_sms_admission;
   if(action==='--configure-native'){
    if(existsSync(join(ROOT,configName))||pre.secrets.get('BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED')!==sha('false'))throw Error('native_config_requires_reconciliation');
    if(!pre.row.last_probe_id||!pre.row.enabled||!pre.row.active||pre.row.pending!==0)throw Error('confirmed_maintenance_activation_required');
    record(configName,{project:PROJECT,sourceSha256:pre.source,evidenceSha256:input.readiness.evidence_file_sha256,at:new Date().toISOString()});
    await db.query('SELECT collect_ops.pause_jobs()');await db.query('SELECT collect_ops.reconcile_jobs()');
    pre=await inspect(db);if(pre.row.enabled||pre.row.active||pre.row.pending!==0)throw Error('scheduler_not_drained');
   }else{const previous=privateJson(configName);if(previous.project!==PROJECT||previous.sourceSha256!==pre.source||previous.evidenceSha256!==input.readiness.evidence_file_sha256||pre.row.enabled||pre.row.active||pre.row.pending!==0)throw Error('native_config_requires_reconciliation');}
   const changes=[{name:'MOMO_AI_ENABLED',value:'true'},{name:'MOMO_AI_MODEL',value:a.model_id},
    {name:'COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256',value:a.approval_sha256},{name:'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED',value:'true'}];
   if(changes.some(x=>pre.secrets.has(x.name)&&![sha(x.value),...(['BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED','MOMO_AI_ENABLED'].includes(x.name)?[sha('false')]:[])].includes(pre.secrets.get(x.name))))throw Error('native_config_preimage_changed');
   try{await management('secrets',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(changes)});}catch{}
   pre=await inspect(db);verifyMode(pre,input.readiness,true);
   record('managed-jobs-native-config-'+pre.source.slice(0,16)+'-complete.json',{project:PROJECT,sourceSha256:pre.source,evidenceSha256:input.readiness.evidence_file_sha256,cronActive:false,at:new Date().toISOString()});
   console.log(JSON.stringify({status:'native_config_verified',cronActive:false}));return;
  }
  verifyMode(pre,input?.readiness,input?.native);
  const kind=input.native?'native':'maintenance',stem='managed-jobs-'+kind+'-probe-'+pre.source.slice(0,16);
  if(action==='--probe'){
   if(pre.row.enabled||pre.row.active||pre.row.pending!==0||existsSync(join(ROOT,stem+'-intent.json')))throw Error('disabled_fresh_probe_required');
   const id=randomUUID();record(stem+'-intent.json',{project:PROJECT,sourceSha256:pre.source,dispatchId:id,evidenceSha256:input.readiness.evidence_file_sha256,at:new Date().toISOString()});
   await db.query('SELECT collect_ops.record_jobs_readiness($1::jsonb)',[input.readiness]);
   const dispatch=(await db.query("SELECT collect_ops.dispatch_jobs('probe',$1::uuid) AS result",[id])).rows[0].result;
   record(stem+'-dispatched.json',{project:PROJECT,dispatchId:id,state:dispatch.state,at:new Date().toISOString()});
   if(dispatch.state!=='awaiting')throw Error('probe_not_dispatched');
   console.log(JSON.stringify({status:'probe_dispatched',kind,dispatchId:id}));return;
  }
  if(action==='--activate'){
   const intent=privateJson(stem+'-intent.json');if(intent.sourceSha256!==pre.source||intent.evidenceSha256!==input.readiness.evidence_file_sha256||pre.row.pending!==0)throw Error('confirmed_probe_required');
   const d=(await db.query('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1::uuid',[intent.dispatchId])).rows[0];if(d?.state!=='confirmed')throw Error('confirmed_probe_required');
   const state=(await db.query('SELECT collect_ops.activate_jobs($1) AS state',[input.readiness.evidence_file_sha256])).rows[0].state;
   if(!state.enabled||!state.cron_active)throw Error('activation_unconfirmed');
   record('managed-jobs-'+kind+'-'+pre.source.slice(0,16)+'-activated.json',{project:PROJECT,sourceSha256:pre.source,dispatchId:intent.dispatchId,evidenceSha256:intent.evidenceSha256,at:new Date().toISOString()});
   console.log(JSON.stringify({status:'scheduler_active',kind,sourceSha256:pre.source}));
  }
 }finally{await db.end();}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main().catch(e=>{
 const safe=new Set(['explicit_action_required','evidence_argument_required','invalid_evidence_name','private_evidence_required','maintenance_readiness_required','native_readiness_invalid','scheduler_migration_changed','runtime_or_key_changed','deployed_function_changed','scheduler_or_history_guard_changed','scheduler_source_shape_changed','readiness_project_changed','native_config_not_qualified','maintenance_requires_native_disabled','native_config_requires_reconciliation','confirmed_maintenance_activation_required','scheduler_not_drained','native_config_preimage_changed','disabled_fresh_probe_required','probe_not_dispatched','confirmed_probe_required','activation_unconfirmed']);
 console.error(JSON.stringify({outcome:'unconfirmed',reason:safe.has(e.message)?e.message:'provider_or_database_unavailable',detail:'Use status and reconcile the original recorded dispatch before retrying.'}));process.exitCode=1;});
