// Derived synthetic-only ordering probe with exactly two unfinished migrations
// intentionally deferred. It never connects to a managed or active database.
import {copyFile,mkdir,readFile,readdir,realpath} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {randomBytes,randomUUID,createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {startOwnedPg17} from '../../current-pg-transfer/test-support/owned-pg17.mjs';
import {EXACT_CURRENT16,loadReviewedPlatformFixture,renderSyntheticSql} from '../../testing/curated-platform-fixture.mjs';
import {CURRENT_MIGRATION_NAMES,applyCurrentFixtureMigration} from '../../testing/self-hosted-current-schema.mjs';
import {canonicalProfile,validateDeploymentProfile} from '../../../../supabase/functions/_shared/deployment-profile.js';

const ROOT=resolve(import.meta.dirname,'../../../..'),{Client}=createRequire(import.meta.url)('pg');
const hash=value=>createHash('sha256').update(value).digest('hex');
const requireThat=(ok,code)=>{if(!ok)throw Error(code);};
const LOCK_HASH='17d63e907cc992d62be67224319f5596c150bd1f51d5c05aa54dc250ef50aa64';
const ICEBERG_FIXTURE_HASH='26a5cac1cae954922f54c58bcad511a3e88ac49f8a3fa9ecf4f661587114a4da';
const BASELINE='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const SYNTHETIC_SOURCE='a'.repeat(64);
const EXTRA=Object.freeze({
 '20261113130900_burimunsi_native_sms_posting.sql':'6fa1438824f9d5455903353573c508d697e11aabae9ec41df2d456fb0ab43d71',
 '20261114101000_burimunsi_native_sms_post_retry.sql':'836e5e925a03c5bbb0bb858a31e689912ecf0386f350b0fbe8d4c0209f6d329a',
 '20261114102000_burimunsi_native_event_identity.sql':'d05349ffd4a3cc93d8e641869dd2feecb4890de80d4944f95addd3d3fed535d0',
 '20261114110000_burimunsi_native_retention_positive_links.sql':'91dcc2eba2f302b85a18517a16ba2aed8aac863c3575eef2358eb29d826218e1',
 '20261114110100_collect_admin_mfa_authority.sql':'460721da7d7ea30c9255c684da477d05adea9f469b2d988a476338608c2d963d',
 '20261114110200_storage_iceberg_retention_census.sql':'643064893448da9b70e52be4d87fedc7125757f3c050c27fbc5b683689beb8b8',
 '20261114110300_collect_admin_mfa_intent_recovery.sql':'ba10d574db42eae6c981c4fb037a6d93929f6f27f4dd0b574fb5af008f33259a',
});
const VARIANTS=Object.freeze({
 '20261114110000_burimunsi_native_retention_positive_links.sql':{name:'managed-branch-1100-candidate.sql',sha256:'23fe7bb434fd05b71da835083351fd568a1adbf997ca00f7419fb504bf1324ce'},
 '20261114110200_storage_iceberg_retention_census.sql':{name:'managed-branch-1102-candidate.sql',sha256:'0d8789061572c0136064a2470b0315c20e5cec50c02fb1f981cc6f3f7e4dba44'},
});
const FORWARD={name:'user-id-forward-candidate.sql',sha256:'e5a640368a1fa3f7a14a65ebce183ca7b747c3ec1ca8c12a390ea0978b1f8e95'};
const REVIEWED_58_END='20261113130800_burimunsi_native_lease_history.sql';
const DEFERRED=new Set(['20261114110100_collect_admin_mfa_authority.sql','20261114110300_collect_admin_mfa_intent_recovery.sql']);
const SUPPORT=Object.freeze([
 'supabase/tests/sql/00_local_auth_fixture.sql',
 'scripts/supabase/testing/curated-platform-fixture.mjs',
 'scripts/supabase/testing/reviewed-self-hosted-migrations.mjs',
 'scripts/supabase/testing/self-hosted-current-schema.mjs',
 'scripts/supabase/testing/member-realtime-interface.sql',
 'scripts/supabase/testing/member-realtime-metadata.sql',
 'scripts/supabase/testing/member-realtime-fixture-plan.json',
 'scripts/supabase/testing/synthetic-iceberg-storage.sql',
 'scripts/supabase/current-pg-transfer/test-support/owned-pg17.mjs',
 'supabase/functions/_shared/deployment-profile.js',
 'deploy/self-hosted/profile.example.json',
]);
const EXPECTED_SUPPORT=Object.freeze({
 'supabase/tests/sql/00_local_auth_fixture.sql':'b935e17f44219f018cf1a864505d1895d71903885ca6c61c039d7ab6596117ea',
 'scripts/supabase/testing/curated-platform-fixture.mjs':'9ff19f93833b5ebc3021a56da344a50d216fbeb5f1929ce6d7c40da92b849673',
 'scripts/supabase/testing/reviewed-self-hosted-migrations.mjs':'41aac4992e1bb43a2ebe29b30f1aa673c159f3aa6befc2bcd3d1552347759c10',
 'scripts/supabase/testing/self-hosted-current-schema.mjs':'5790030c2f079f8fbe282f838b06d5474902110e29e7a398c2aa53e05b6ccdac',
 'scripts/supabase/testing/member-realtime-interface.sql':'074e380664493eea86a56d3f3042460bbb33352bc4f46483fd19d559446b0e1b',
 'scripts/supabase/testing/member-realtime-metadata.sql':'ed97cdf0838100502344d2d54563992df6170c6a64e95843c037aaec4cd703e3',
 'scripts/supabase/testing/member-realtime-fixture-plan.json':'6156561ea1b893b56afcf54d64934ca042dbb3251426ea3d27e532272bf65d6f',
 'scripts/supabase/testing/synthetic-iceberg-storage.sql':'26a5cac1cae954922f54c58bcad511a3e88ac49f8a3fa9ecf4f661587114a4da',
 'scripts/supabase/current-pg-transfer/test-support/owned-pg17.mjs':'d16afa140b3d2e45c25781bf5f7de1e071762b8cfbef417edb89b2017cc8f9db',
 'supabase/functions/_shared/deployment-profile.js':'81aa502648712421de8a06dc6eb083c95fb46b063c57b6d1c46cf40d8426ee7d',
 'deploy/self-hosted/profile.example.json':'adfa7f604b45ed6da91df2dd2f70a60ef5c7b986c89e4487976b5d533802f739',
});
async function supportPins(){const result={};for(const name of SUPPORT)result[name]=hash(await readFile(join(ROOT,name)));
 requireThat(JSON.stringify(result)===JSON.stringify(EXPECTED_SUPPORT),'PINNED_FIXTURE_SUPPORT_CHANGED');return result;}

async function inputs(){
 requireThat(await realpath(ROOT)===ROOT,'PHYSICAL_SOURCE_REQUIRED');
 const lockBytes=await readFile(join(ROOT,'supabase/managed-migration-history/source-migrations.lock.json'));
 requireThat(hash(lockBytes)===LOCK_HASH,'PINNED_MIGRATION_LOCK_CHANGED');
 const lock=JSON.parse(lockBytes.toString('utf8'));
 requireThat(lock.format==='collect.selfhost.migrations.v1'&&lock.original_count===16&&lock.migrations.length===58&&
  JSON.stringify(lock.migrations.map(x=>x.name))===JSON.stringify(CURRENT_MIGRATION_NAMES),
  'EXACT_REVIEWED_58_REQUIRED');
 const expected=[...lock.migrations,...Object.entries(EXTRA).map(([name,sha256])=>({name,sha256}))].sort((a,b)=>a.name.localeCompare(b.name));
 const disk=(await readdir(join(ROOT,'supabase/migrations'))).filter(x=>/^\d{14}_.*\.sql$/.test(x)).sort();
 requireThat(expected.length===65&&JSON.stringify(disk)===JSON.stringify(expected.map(x=>x.name)),
  'EXACT_65_FILE_INVENTORY_REQUIRED');
 const migrations=[];
 for(const entry of expected){
  const path=join(ROOT,'supabase/migrations',entry.name);requireThat(await realpath(path)===path,'MIGRATION_PATH_NOT_PHYSICAL');
  const bytes=await readFile(path);requireThat(hash(bytes)===entry.sha256,'MIGRATION_BYTES_CHANGED');
  migrations.push({...entry,sql:bytes.toString('utf8')});
 }
 const candidates={};
 for(const item of [...Object.values(VARIANTS),FORWARD]){
  const path=join(ROOT,'scripts/supabase/retention-convergence',item.name),bytes=await readFile(path);
  requireThat(hash(bytes)===item.sha256,'CANDIDATE_BYTES_CHANGED');candidates[item.name]=bytes.toString('utf8');
 }
 const storage=await readFile(join(ROOT,'scripts/supabase/testing/synthetic-iceberg-storage.sql'));
 requireThat(hash(storage)===ICEBERG_FIXTURE_HASH,'STORAGE_FIXTURE_CHANGED');
 return {migrations,candidates,storage:storage.toString('utf8')};
}

// Exposes only pinned file identities, never SQL or database access. This is
// planning evidence; the seven additions are not thereby approved.
export async function pinnedBranchInputs(){
 const value=await inputs();
 return {migrations:value.migrations.map(({name,sha256})=>({name,sha256})),
  variants:Object.fromEntries(Object.entries(VARIANTS).map(([source,item])=>[source,{...item}])),forward:{...FORWARD}};
}

// The upstream synthetic Iceberg fixture normally uses loopback TCP. This
// runner narrows its fixture-identity guard to its own private Unix socket;
// every Storage schema/type/table/constraint statement remains byte-identical.
function socketStorageFixture(original){
 const from="current_user<>'collect_test' OR session_user<>'collect_test'\n  OR host(inet_server_addr()) IS DISTINCT FROM '127.0.0.1'";
 const to="current_user<>'collect_test' OR session_user<>'collect_test'\n  OR inet_server_addr() IS NOT NULL OR current_setting('cluster_name')<>'collect_deferred_mfa_fixture'";
 requireThat(original.split(from).length===2,'STORAGE_FIXTURE_GUARD_CHANGED');
 const replacement=original.replace(from,to);
 requireThat(replacement.replace(to,from)===original,'STORAGE_FIXTURE_BODY_CHANGED');return replacement;
}

export async function runSyntheticDeferredMfaChain(){
 let fixture,bootstrap,custodian,setup,owner,cleanup,support,stage='input-validation',failure;const events=[];
 try{
  const initial=await inputs();support=await supportPins();
  fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_deferred_mfa_fixture'});
  const connect=async(user,database)=>{const c=new Client({host:fixture.socket,port:fixture.port,user,database,connectionTimeoutMillis:5000,statement_timeout:60000});await c.connect();return c;};
  bootstrap=await connect('fixture_bootstrap','postgres');
  const identity=(await bootstrap.query("SELECT current_user,session_user,inet_server_addr() IS NULL socket,current_setting('cluster_name') name,current_setting('server_version_num')::int/10000 major")).rows[0];
  requireThat(identity.current_user==='fixture_bootstrap'&&identity.session_user==='fixture_bootstrap'&&identity.socket&&identity.name==='collect_deferred_mfa_fixture'&&identity.major===17,'OWNED_SOCKET_FIXTURE_REQUIRED');
  // Keep the initdb owner's identity and role ordering expected by the
  // independently reviewed realtime fixture, without adding a second
  // persistent superuser to the disposable cluster.
  await bootstrap.query('CREATE ROLE fixture_custodian LOGIN SUPERUSER');
  custodian=await connect('fixture_custodian','postgres');await bootstrap.end();bootstrap=null;
  await custodian.query('ALTER ROLE fixture_bootstrap RENAME TO collect_test');await custodian.end();custodian=null;
  bootstrap=await connect('collect_test','postgres');await bootstrap.query('DROP ROLE fixture_custodian');
  const database='collect_selfhost_integration_'+randomBytes(12).toString('hex')+'_test';
  await bootstrap.query('CREATE DATABASE "'+database+'" OWNER collect_test TEMPLATE template0 ENCODING \'UTF8\'');
  setup=await connect('collect_test',database);
  const prefix=join(fixture.root,'original16');await mkdir(join(prefix,'supabase/migrations'),{recursive:true});await mkdir(join(prefix,'supabase/tests/sql'),{recursive:true});
  for(const name of EXACT_CURRENT16)await copyFile(join(ROOT,'supabase/migrations',name),join(prefix,'supabase/migrations',name));
  await copyFile(join(ROOT,'supabase/tests/sql/00_local_auth_fixture.sql'),join(prefix,'supabase/tests/sql/00_local_auth_fixture.sql'));
  const base=await loadReviewedPlatformFixture(prefix,{includeStoppedAdmissionLifecycleMigration:true});
  stage='synthetic-original16';await setup.query(base.auth);
  for(const item of base.rawMigrations.slice(0,9))await setup.query(item.sql);
  const realtime=await readFile(join(ROOT,'scripts/supabase/testing/member-realtime-interface.sql'));
  requireThat(hash(realtime)===base.binding.interface_sha256,'REALTIME_INTERFACE_CHANGED');await setup.query(realtime.toString('utf8'));
  let hostedRefused=false;try{await setup.query(base.rawMigrations[9].sql);}catch(e){hostedRefused=e.code==='55000'&&e.message==='member_realtime_metadata_not_reviewed';}finally{await setup.query('ROLLBACK');}
  requireThat(hostedRefused,'HOSTED_REALTIME_MUST_REFUSE_SYNTHETIC_METADATA');
  await setup.query(renderSyntheticSql(base.rawMigrations[9].sql,base.binding));
  for(const item of base.rawMigrations.slice(10,13))await setup.query(item.sql);
  // Transfer ownership only inside the newly created socket-only fixture.
  await setup.query(`DO $owner$ DECLARE r record;BEGIN
   IF current_user<>'collect_test' OR session_user<>'collect_test' OR current_database()<>'${database}' OR inet_server_addr() IS NOT NULL OR current_setting('cluster_name')<>'collect_deferred_mfa_fixture' THEN RAISE EXCEPTION 'OWNED_NEW_FIXTURE_REQUIRED';END IF;
   FOR r IN SELECT nspname FROM pg_namespace WHERE nspowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND nspname NOT LIKE 'pg_%' AND nspname<>'information_schema' LOOP EXECUTE format('ALTER SCHEMA %I OWNER TO postgres',r.nspname);END LOOP;
   FOR r IN SELECT c.oid::regclass object,c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND c.relkind IN('r','p','v','m','f') LOOP EXECUTE format('ALTER %s %s OWNER TO postgres',CASE r.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END,r.object);END LOOP;
   FOR r IN SELECT c.oid::regclass object FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND c.relkind='S' LOOP EXECUTE format('ALTER SEQUENCE %s OWNER TO postgres',r.object);END LOOP;
   FOR r IN SELECT p.oid::regprocedure object FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND p.prokind='f' LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',r.object);END LOOP;
  END;$owner$;`);
  await bootstrap.query('ALTER DATABASE "'+database+'" OWNER TO postgres');
  await bootstrap.query('ALTER ROLE postgres LOGIN NOSUPERUSER NOINHERIT CREATEROLE NOCREATEDB NOBYPASSRLS NOREPLICATION');
  owner=await connect('postgres',database);
  await owner.query(base.stoppedAdmissionLifecycle.sql);await owner.query(base.clientDiagnostics.sql);await owner.query(base.notificationDelivery.sql);
  await setup.query(socketStorageFixture(initial.storage));
  await owner.query('ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz; ALTER TABLE auth.users ADD COLUMN is_anonymous boolean NOT NULL DEFAULT false');
  const original16=[...base.rawMigrations,base.clientDiagnostics,base.notificationDelivery];
  requireThat(original16.length===16,'SYNTHETIC_ORIGINAL16_INCOMPLETE');
  for(const item of original16)events.push({stage:item.name,status:'pass',source_sha256:item.sha256,
   executed_sha256:item.name===base.rawMigrations[9].name?base.binding.synthetic_sql_sha256:item.sha256,
   synthetic_realtime_binding:item.name===base.rawMigrations[9].name,history_recorded:false});
  requireThat((await owner.query("SELECT to_regclass('supabase_migrations.schema_migrations') IS NULL absent")).rows[0].absent,'SYNTHETIC_HISTORY_MUST_BE_ABSENT');
  const profile=validateDeploymentProfile({...JSON.parse(await readFile(join(ROOT,'deploy/self-hosted/profile.example.json'),'utf8')),environment:'qualification',id:'collect-deferred-mfa-fixture'});
  const raw=canonicalProfile(profile),profileSha=hash(raw),operation=randomUUID();let initialized=false;
  const client={unsafe:async(text,params)=>(await owner.query(text,params)).rows};
  for(const item of initial.migrations.slice(16)){
   if(item.name>REVIEWED_58_END)break;
   stage=item.name;
   if(item.name==='20261110193000_burimunsi_canonical_receipt_adoption.sql'){
    await owner.query('BEGIN');await owner.query('SELECT private.collect_bind_deployment($1,$2,$3)',[operation,raw,profileSha]);
    await owner.query('SELECT private.collect_fence_initialize($1,$2,$3)',[operation,SYNTHETIC_SOURCE,BASELINE]);await owner.query('COMMIT');initialized=true;
   }
   await applyCurrentFixtureMigration(client,item);
   events.push({stage:item.name,status:'pass',source_sha256:item.sha256,executed_sha256:item.sha256,history_recorded:false});
  }
  requireThat(initialized,'SYNTHETIC_FENCE_NOT_INITIALIZED');
  const control=(await owner.query('SELECT mode,epoch,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows;
  requireThat(control.length===1&&control[0].mode==='open'&&control[0].source_sha256===SYNTHETIC_SOURCE,'SYNTHETIC_OPEN_FENCE_REQUIRED');
  const fence=randomUUID();await owner.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3)',[fence,control[0].epoch,SYNTHETIC_SOURCE]);
  const drained=(await owner.query('SELECT private.collect_fence_drain($1,$2,$3) result',[fence,control[0].epoch,SYNTHETIC_SOURCE])).rows[0].result;
  requireThat(drained.mode==='fenced','SYNTHETIC_DRAIN_UNCONFIRMED');
  for(const item of initial.migrations.filter(x=>x.name>REVIEWED_58_END)){
   stage=item.name;
   if(DEFERRED.has(item.name)){events.push({stage:item.name,status:'deferred',source_sha256:item.sha256,history_recorded:false});continue;}
   const variant=VARIANTS[item.name],sql=variant?initial.candidates[variant.name]:item.sql;
   if(variant){
    const preimageSql="SELECT string_agg(oid::regprocedure::text||':'||encode(sha256(convert_to(prosrc,'UTF8')),'hex'),',' ORDER BY oid::regprocedure::text) hashes FROM pg_proc WHERE oid IN('private._retention_manifest_catalog_v2()'::regprocedure,'private._retention_manifest_schema_v2()'::regprocedure,'private._retention_manifest_rows_v2(text)'::regprocedure,'private._retention_row_policy_v2(uuid,text,text,text)'::regprocedure,'private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure)";
    const before=(await owner.query(preimageSql)).rows[0].hashes;
    let refused=false;try{await owner.query(item.sql);}catch(e){refused=e.code==='55000'&&['burimunsi_retention_positive_predecessor_changed','storage_iceberg_retention_predecessor_changed'].includes(e.message);}finally{await owner.query('ROLLBACK');}
    const after=(await owner.query(preimageSql)).rows[0].hashes;
    requireThat(refused&&before===after,'ORIGINAL_DIVERGENT_MIGRATION_MUST_ROLL_BACK');
    events.push({stage:item.name+':original-refusal',status:'pass',source_sha256:item.sha256,history_recorded:false});
   }
   await owner.query(sql);
   events.push({stage:item.name,status:'pass',source_sha256:item.sha256,executed_sha256:variant?.sha256??item.sha256,
    candidate_substitution:variant?.name??null,history_recorded:false});
  }
  stage=FORWARD.name;await owner.query(initial.candidates[FORWARD.name]);
  events.push({stage:FORWARD.name,status:'pass',executed_sha256:FORWARD.sha256,history_recorded:false});
  const c=(await owner.query(`SELECT
   (SELECT count(*) FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') x
    WHERE x->>'name'=ANY(ARRAY['private:burimunsi_native_financial_work','private:burimunsi_native_grant_commands','private:burimunsi_native_work_grants','private:burimunsi_native_lease_history']) AND x->'blocked'='true'::jsonb)::int native_classes,
   (SELECT count(*) FROM jsonb_array_elements_text(private._retention_manifest_catalog_v2()->'copy_classes') x
    WHERE x=ANY(ARRAY['managed:storage_iceberg','managed:storage_iceberg_namespaces','managed:storage_iceberg_tables']))::int iceberg_classes,
   (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private' AND p.proname LIKE 'collect_admin_mfa_%')::int wip_functions,
   (SELECT count(*) FROM pg_attribute WHERE attrelid='private.bff_sessions'::regclass AND NOT attisdropped
    AND (attname LIKE 'mfa_pending_%' OR attname LIKE 'mfa_intent_%'))::int wip_columns,
   (SELECT count(*) FROM app.runtime_config WHERE key='security:admin_mfa_required:v1')::int wip_policy_rows,
   (SELECT count(*) FROM pg_trigger WHERE tgrelid='app.runtime_config'::regclass AND NOT tgisinternal
    AND tgname='collect_admin_mfa_policy_guard_v1')::int wip_triggers,
   to_regclass('private.bff_mfa_pending_candidate') IS NULL wip_index_absent,
   (SELECT attnotnull FROM pg_attribute WHERE attrelid='app.auth_mfa_factors'::regclass AND attname='enrollment_session_id' AND NOT attisdropped) legacy_enrollment_required,
   EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='app.auth_mfa_factors'::regclass AND conname='auth_mfa_factors_check'
    AND encode(sha256(convert_to(pg_get_constraintdef(oid),'UTF8')),'hex')='af9ee0c09d98c542a3761d997ca30368e1f4dd56d747e58419cbd2274c19f15f') legacy_factor_constraint,
   EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('private.assert_admin_email_context(bigint)')
    AND encode(sha256(convert_to(prosrc,'UTF8')),'hex')='5bcde2de29499118c3384a6a124df2772b6cc093ae8f7bdd5bd967d5cfaa1188') legacy_admin_authority,
   NOT has_function_privilege('collect_runtime','private.record_mfa_projection(uuid)','EXECUTE') projector_ungranted,
   (SELECT count(*) FROM unnest(ARRAY['private.burimunsi_native_sms_post_candidates(integer)',
    'private.burimunsi_native_sms_post_snapshot(text)','private.burimunsi_native_sms_post_defer(text,integer)',
    'private.burimunsi_native_sms_post_retry(text,text)','private.burimunsi_native_sms_post_facts(text,text,jsonb,jsonb)',
    'private.burimunsi_native_custody_snapshot(uuid,uuid,bigint)']) signature
    WHERE to_regprocedure(signature) IS NOT NULL AND has_function_privilege('collect_runtime',to_regprocedure(signature),'EXECUTE'))::int financial_runtime_functions,
   to_regprocedure('private.burimunsi_native_work_assert(uuid,uuid,bigint)') IS NOT NULL work_assert_present,
   to_regclass('private.burimunsi_native_one_event') IS NOT NULL event_identity_index_present,
   EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_auto_sms_jobs'::regclass AND NOT tgisinternal
    AND tgname='burimunsi_auto_event_immutable' AND tgenabled='A') event_identity_guard_enabled,
   (SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) privileged`)).rows[0];
  requireThat(c.native_classes===4&&c.iceberg_classes===3&&c.wip_functions===0&&c.wip_columns===0&&
   c.wip_policy_rows===0&&c.wip_triggers===0&&c.wip_index_absent&&c.legacy_enrollment_required&&
   c.legacy_factor_constraint&&c.legacy_admin_authority&&c.projector_ungranted&&c.financial_runtime_functions===6&&
   c.work_assert_present&&c.event_identity_index_present&&c.event_identity_guard_enabled&&!c.privileged,'SYNTHETIC_CHAIN_POSTCONDITIONS_FAILED');
  events.push({stage:'candidate-postconditions',status:'pass',...c});
  const release=(await owner.query('SELECT private.collect_fence_release($1,$2,$3) result',[randomUUID(),control[0].epoch,SYNTHETIC_SOURCE])).rows[0].result;
  requireThat(release.mode==='open'&&Number(release.epoch)===Number(control[0].epoch)+1,'SYNTHETIC_RELEASE_UNCONFIRMED');
  requireThat((await owner.query("SELECT to_regclass('supabase_migrations.schema_migrations') IS NULL absent")).rows[0].absent,'SYNTHETIC_HISTORY_MUST_REMAIN_ABSENT');
  await base.parity();
  const final=await inputs();
  requireThat(JSON.stringify(final.migrations.map(({name,sha256})=>({name,sha256})))===JSON.stringify(initial.migrations.map(({name,sha256})=>({name,sha256}))), 'MIGRATIONS_CHANGED_DURING_RUN');
  requireThat(JSON.stringify(await supportPins())===JSON.stringify(support),'FIXTURE_INPUTS_CHANGED_DURING_RUN');
  stage='complete';
 }catch(error){failure={stage,code:error?.code??error?.name??'ERROR',message:String(error?.message??'').slice(0,240)};}
 finally{
  for(const c of [owner,setup,custodian,bootstrap])if(c)try{await c.end();}catch{failure??={stage:'cleanup',code:'CLIENT_CLOSE_UNCONFIRMED'};}
  if(fixture)try{cleanup=await fixture.close();}catch{failure??={stage:'cleanup',code:'FIXTURE_CLOSE_UNCONFIRMED'};}
 }
 return {status:!failure&&cleanup?.removed?'pass':'failed',events,error:failure??null,fixture_removed:cleanup?.removed??false,
  support_sha256:support??null,synthetic_only:true,hosted_acceptance:false,history_written:false,production_ready:false,
  deferred_versions:['20261114110100','20261114110300'],
  limitations:['Synthetic Auth, realtime and Storage interfaces differ from managed services','Five additions and both candidate substitutions are not independently approved for production','Migration history and managed operator integration are not exercised','No source or target customer data or provider effects are tested']};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const result=await runSyntheticDeferredMfaChain();process.stdout.write(JSON.stringify(result,null,2)+'\n');if(result.status!=='pass')process.exitCode=1;
}
