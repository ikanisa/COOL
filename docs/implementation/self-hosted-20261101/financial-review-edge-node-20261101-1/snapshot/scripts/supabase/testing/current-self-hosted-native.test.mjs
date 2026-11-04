import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,mkdir,copyFile,writeFile,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {CURRENT_HARNESSES,validateCurrentInvocation,validateHarnessReceipt} from './current-self-hosted-native.mjs';
import {CURRENT_NATIVE_PROFILE,CURRENT_MIGRATION_NAMES,CURRENT_MIGRATION_COUNT,validateCurrentFixtureDescriptor,reviewedCurrentMigrations,installCurrentFixtureAdditions} from './self-hosted-current-schema.mjs';
const env={COLLECT_CI_SYNTHETIC:'true',COLLECT_DENO:'/owned/deno',COLLECT_SELFHOST_OUTPUT_DIR:'/owned/new-current',
 COLLECT_FENCE_ADMIN_DATABASE_URL:'postgres://collect_test:collect_local_fixture_only@127.0.0.1:55439/postgres'};
const sourceText=await readFile(new URL('./current-self-hosted-native.mjs',import.meta.url),'utf8');

test('automatic current invocation admits only the dedicated explicit synthetic cluster',()=>{
 assert.equal(validateCurrentInvocation(env,'24.19.0').local,null);
 for(const delta of [{COLLECT_CI_SYNTHETIC:'false'},{COLLECT_SELFHOST_OUTPUT_DIR:'relative'},
  {COLLECT_DENO:'/owned/../deno'},{COLLECT_FENCE_ADMIN_DATABASE_URL:'postgres://collect_test:x@db.production.example:5432/postgres'},
  {COLLECT_FENCE_ADMIN_DATABASE_URL:env.COLLECT_FENCE_ADMIN_DATABASE_URL.replace('127.0.0.1','localhost')},
  {COLLECT_FENCE_ADMIN_DATABASE_URL:env.COLLECT_FENCE_ADMIN_DATABASE_URL+'?options=unsafe'}])assert.throws(()=>validateCurrentInvocation({...env,...delta},'24.19.0'));
 assert.throws(()=>validateCurrentInvocation(env,'22.1.0'),/NODE24/);
});

test('current fixture requires original16, explicit purpose and fresh private identity',()=>{
 const database='collect_selfhost_auth_'+ 'a'.repeat(24)+'_test';
 const value={format:'collect.selfhost.fixture.v1',synthetic:true,public_acceptance:false,controller_initialized:true,migration_count:16,
  source_sha256:'b'.repeat(64),purpose:'auth',database,url:'postgres://postgres:synthetic@127.0.0.1:55439/'+database};
 assert.equal(validateCurrentFixtureDescriptor(value,{purpose:'auth'}).pathname,'/'+database);
 for(const delta of [{migration_count:24},{controller_initialized:false},{synthetic:false},{public_acceptance:true},{purpose:'backend'},
  {database:'postgres'},{url:value.url.replace('127.0.0.1','host.example')},{url:value.url.replace(':55439',':5432')}])
  assert.throws(()=>validateCurrentFixtureDescriptor({...value,...delta},{purpose:'auth'}));
});

test('current coverage keeps native control, diagnostics, Auth, retention and both delivery channels',()=>{
 assert.deepEqual(CURRENT_HARNESSES.map(row=>[row.name,row.cases]),[
  ['control',8],['runtime',16],['backend',10],['auth',10],['retention',15],['notifications',9],['gateway',34],['data_stage',5],['momo',18],['contribution_review',7]]);
 assert(sourceText.includes("name:'scheduler',status:schedulerPassed?'PASS':'FAIL',cases:24"));
 assert(sourceText.includes("name:'gateway_fence',status:gatewayFencePassed?'PASS':'FAIL',cases:14"));
 assert(sourceText.includes("results.length===13"));
});

test('current contribution review requires every named native RLS and financial check',()=>{
 const schema={profile:CURRENT_NATIVE_PROFILE,migration_count:CURRENT_MIGRATION_COUNT,migrations:CURRENT_MIGRATION_NAMES.map(name=>({name,sha256:'a'.repeat(64)})),production_acceptance:false};
 const value={format:'collect.selfhost.contribution-review.native.v1',status:'PASS',current_schema:schema,normal_owner:true,normal_runtime:true,
  checks:['normal_runtime_has_select_and_active_rls_without_bypass','real_create_and_unlinked_review_succeed',
   'normal_runtime_rls_sees_null_member_beneficiary_payment','pending_beneficiary_link_denies_review',
   'shared_worker_http_with_synthetic_preverified_claims_denies_link_and_missing_auth',
   'committed_link_between_context_and_review_select_is_denied','unrelated_link_does_not_disable_unlinked_intent_or_replace_receipt'],
  provider_calls:0,external_network_calls:0,hosted_acceptance:false,production_acceptance:false,http_router:'shared_worker',
  auth_fixture:'synthetic_preverified_claims',outer_deployed_edge_handler_exercised:false,review_to_provider_race_closed:false};
 assert.equal(validateHarnessReceipt('contribution_review',value),value);
 for(const delta of [{normal_owner:false},{normal_runtime:false},{checks:value.checks.slice(1)},{provider_calls:1},
  {external_network_calls:1},{hosted_acceptance:true},{production_acceptance:true},{review_to_provider_race_closed:true},
  {http_router:'deployed_edge'},{auth_fixture:'hosted_auth'},{outer_deployed_edge_handler_exercised:true},
  {current_schema:{...schema,migration_count:CURRENT_MIGRATION_COUNT-1}}])assert.throws(()=>validateHarnessReceipt('contribution_review',{...value,...delta}));
});

test('current MoMo receipt requires every named race and authority check with no real provider calls',()=>{
 const schema={profile:CURRENT_NATIVE_PROFILE,migration_count:CURRENT_MIGRATION_COUNT,migrations:CURRENT_MIGRATION_NAMES.map(name=>({name,sha256:'a'.repeat(64)})),production_acceptance:false};
 const value={format:'collect.selfhost.momo.native.v1',status:'PASS',normal_owner:true,normal_runtime:true,current_schema:schema,
  outbox_checks:['actual_SQL_source_and_enqueue_commit_or_roll_back_together','actual_SQL_overlapping_worker_cannot_claim_unexpired_lease',
   'expired_preflight_reclaims_once_and_fences_old_dispatch','expired_dispatched_attempt_is_parked_and_stale_result_cannot_commit',
   'parking_lock_wins_and_stale_completion_rolls_back_all_facts','lease_expiry_while_finishing_lock_held_rolls_back_and_parks',
   'lease_expiry_during_unmodified_row_lock_wait_prevents_stale_facts','lease_expiry_during_dispatch_lock_wait_never_calls_provider',
   'lost_provider_response_is_durable_unknown_and_never_automatically_retried','lost_dispatch_marker_ack_never_sends_or_reclaims_ambiguously',
   'pre_dispatch_failure_retries_safely_after_backoff','legacy_ambiguous_pending_retry_and_expired_processing_are_parked'],
  admin_checks:['missing_fresh_email_proof_and_missing_csrf_denied','authorized_resolution_and_idempotent_replay_keep_one_evidence_row',
   'unknown_outcome_and_insufficient_staff_role_denied','reparse_compare_and_set_refuses_concurrent_unknown',
   'authorized_reparse_and_replay','authorized_manual_correction_has_no_financial_effect'],
  synthetic_provider_calls:{unexpired_overlap:1,expired_overlap:1,lost_response:1,lost_marker_ack:0},synthetic_auth_get_user_calls:25,
  admin_completed_admissions:14,provider_calls:0,external_network_calls:0,hosted_acceptance:false,production_acceptance:false};
 assert.equal(validateHarnessReceipt('momo',value),value);
 for(const delta of [{normal_owner:false},{normal_runtime:false},{provider_calls:1},{external_network_calls:1},{hosted_acceptance:true},
  {production_acceptance:true},{synthetic_auth_get_user_calls:0},{admin_completed_admissions:0},{outbox_checks:value.outbox_checks.slice(1)},
  {admin_checks:value.admin_checks.slice(1)},{synthetic_provider_calls:{...value.synthetic_provider_calls,lost_marker_ack:1}},
  {current_schema:{...schema,migration_count:CURRENT_MIGRATION_COUNT-1}}])assert.throws(()=>validateHarnessReceipt('momo',{...value,...delta}));
});

test('current native staging evidence cannot claim historical positive import or omit its SQL proof',()=>{
 const schema={profile:CURRENT_NATIVE_PROFILE,migration_count:CURRENT_MIGRATION_COUNT,migrations:CURRENT_MIGRATION_NAMES.map(name=>({name,sha256:'a'.repeat(64)})),production_acceptance:false};
 const value={format:'collect.selfhost.data-stage.native.v1',status:'PASS',cases:Array(5).fill('validator-only'),provider_calls:0,
  observed:{actual_postgres:true,actual_sqlite:true},current_first_import_supported:false,historical_positive_import_acceptance:false,
  production_acceptance:false,current_schema:schema};
 assert.equal(validateHarnessReceipt('data_stage',value),value);
 for(const delta of [{current_first_import_supported:true},{historical_positive_import_acceptance:true},{cases:[]},
  {provider_calls:1},{observed:{actual_postgres:false,actual_sqlite:true}}])assert.throws(()=>validateHarnessReceipt('data_stage',{...value,...delta}));
});

test('historical or partial runtime evidence cannot pass current receipt admission',()=>{
 // These are validator inputs only; no contract object is saved as SQL evidence.
 const schema={profile:CURRENT_NATIVE_PROFILE,migration_count:CURRENT_MIGRATION_COUNT,migrations:CURRENT_MIGRATION_NAMES.map(name=>({name,sha256:'a'.repeat(64)})),production_acceptance:false};
 const value={format:'collect.selfhost.auth.native.v2',status:'pass',passed:Array(10).fill('validator-only'),
  realProviderCalls:0,syntheticProviderCalls:6,productionAcceptance:false,current_schema:schema};
 assert.equal(validateHarnessReceipt('auth',value),value);
 for(const delta of [{format:'collect.current16.native.v1'},{realProviderCalls:1},{productionAcceptance:true},
  {passed:[]},{current_schema:{...schema,migration_count:18}}])assert.throws(()=>validateHarnessReceipt('auth',{...value,...delta}));
 assert.throws(()=>validateHarnessReceipt('unknown',value));
});

test('complete reviewed current source admission rejects any altered or unlisted migration',async()=>{
 const root=resolve(import.meta.dirname,'../../..'),temporary=await mkdtemp(join(tmpdir(),'collect-current-schema-'));
 try{
  await mkdir(join(temporary,'supabase/migrations'),{recursive:true});await mkdir(join(temporary,'deploy/self-hosted'),{recursive:true});
  await copyFile(join(root,'deploy/self-hosted/migrations.lock.json'),join(temporary,'deploy/self-hosted/migrations.lock.json'));
  for(const name of CURRENT_MIGRATION_NAMES)await copyFile(join(root,'supabase/migrations',name),join(temporary,'supabase/migrations',name));
  assert.equal((await reviewedCurrentMigrations(temporary)).length,CURRENT_MIGRATION_COUNT);
  const name=CURRENT_MIGRATION_NAMES.at(-1);await writeFile(join(temporary,'supabase/migrations',name),'-- altered review input\n');
  await assert.rejects(()=>reviewedCurrentMigrations(temporary),/REVIEWED_CURRENT_MIGRATION_CHANGED/);
  await copyFile(join(root,'supabase/migrations',name),join(temporary,'supabase/migrations',name));
  await writeFile(join(temporary,'supabase/migrations/20990101000000_unreviewed.sql'),'SELECT 1;');
  await assert.rejects(()=>reviewedCurrentMigrations(temporary),/UNREVIEWED_CURRENT_MIGRATION_REFUSED/);
 }finally{await rm(temporary,{recursive:true,force:true});}
});

test('existing additions are refused before any DDL, with no schema reset branch',async()=>{
 const calls=[];const owner={unsafe:async sql=>{calls.push(sql);return calls.length===1?[{owner:'postgres',session:'postgres',database:'collect_selfhost_backend_'+ 'a'.repeat(24)+'_test',host:'127.0.0.1',port:55439,major:17,privileged:false}]:[{archive:'already_exists',guest:null,gateway:null,retention:null}];}};
 await assert.rejects(()=>installCurrentFixtureAdditions(owner),/FRESH_CURRENT_ADDITIONS_REQUIRED/);
 assert.equal(calls.length,2);assert(calls.every(sql=>sql.startsWith('SELECT')));
 assert(!sourceText.includes('DROP DATABASE')&&!sourceText.includes('DROP SCHEMA'));
});
