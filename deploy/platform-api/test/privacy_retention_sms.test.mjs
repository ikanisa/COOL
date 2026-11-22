import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdir,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {stableJson} from '../src/core.js';
import {current12Fixture,controls} from './support/recovery12_fixture.mjs';
import {retentionSchema,snapshotCompareGuards} from '../src/privacy_retention_catalog.js';
import {assistedSmsRecoveryTables} from '../../../scripts/cloudflare/recovery_quarantine.mjs';
import {retentionFixture,authorization,sourceId,sha} from './support/retention_fixture.mjs';

test('current12 real authenticated SMS and retention source populates all fourteen control/history tables and91 reviewed classes',async t=>{
 const c=await current12Fixture(t),schema=await retentionSchema({DB:c.f.db});
 assert.equal(schema.tables.length,81);assert.equal(c.counts.privacy_retention_tasks,91);
 for(const name of [...controls,...assistedSmsRecoveryTables])assert.ok(c.counts[name]>0,name);
 assert.equal(c.consent.decision_revision,2);assert.equal(c.access.decision_revision,1);
 const snapshot=await c.snapshot(c.recipient);assert.equal(snapshot.summary.in_flight_unresolved,true);
 for(const name of assistedSmsRecoveryTables)assert.ok(snapshot.rows[name].length>0,name);
 await t.test('recipient withdrawal of membership/creation identity cannot hide encrypted SMS, collection, operator receipts or audit copies',async()=>{
  const other=await c.f.seedMember({phone:'+250787123456'});await c.f.db.batch([c.f.db.prepare('DELETE FROM memberships WHERE collection_id=? AND user_id=?').bind(c.smsGroup,c.recipient),c.f.db.prepare('UPDATE collections SET creator_user_id=? WHERE id=?').bind(other.id,c.smsGroup)]);
  const observed=await c.snapshot(c.recipient);for(const name of assistedSmsRecoveryTables)assert.ok(observed.rows[name].length>0,name);assert.ok(observed.rows.collections.some(r=>r.id===c.smsGroup));assert.equal(observed.summary.in_flight_unresolved,true);
  const related=(await c.f.db.prepare("SELECT request_id FROM request_receipts WHERE operation IN('assisted_sms.enqueue','assisted_sms.claim','assisted_sms.confirm','assisted_sms.send_start','assisted_sms.outcome','assisted_sms.materialize.plan','assisted_sms.materialize.intent','assisted_sms.policy.configure')").all()).results;assert.ok(related.length>=10);
  for(const row of related){assert.ok(observed.rows.request_receipts.some(r=>r.request_id===row.request_id),row.request_id);assert.ok(observed.rows.audit_log.some(r=>r.request_id===row.request_id),row.request_id);}
 });
 await t.test('a newly added ordinary table matching an old LIKE wildcard cannot evade the in-batch schema fence',async()=>{
  const snapshot=await c.snapshot(c.recipient),env={DB:c.f.db},plan={id:c.planned.plan_id,subject_id:c.recipient},marker='synthetic_schema_probe';
  const originalCatalog=snapshot.schemaCatalog,proof={synthetic_only:true,provider_actions:false,raw_catalog:originalCatalog,raw_catalog_sha256:sha(stableJson(originalCatalog)),application_schema_sha256:snapshot.summary.schema_sha256,guard_catalog_is_complete_raw_observation:true,predicate:        "sql IS NOT NULL AND name NOT GLOB 'sqlite_*'",observations:[]};
  const save=async()=>{const folder=process.env.COLLECT_RETENTION_SCHEMA_EVIDENCE_DIR;if(folder){await mkdir(folder,{recursive:true,mode:0o700});await writeFile(join(folder,'schema-guard-provenance.json'),JSON.stringify(proof,null,2)+'\n',{mode:0o600});}};
  const guarded=()=>c.f.db.batch([...snapshotCompareGuards(env,plan,snapshot,marker),c.f.db.prepare('DELETE FROM privacy_retention_guards WHERE plan_id=? AND class_name=?').bind(plan.id,marker)]);
  await save();await guarded();proof.unchanged_raw_catalog_guard_succeeded=true;await save();
  for(const table of ['acf_unreviewed_copy','sqliteevil_copy']){
   await c.f.db.batch([c.f.db.prepare('CREATE TABLE '+table+'(id TEXT,authority TEXT)'),c.f.db.prepare('INSERT INTO '+table+" VALUES('SYNTHETIC','UNREVIEWED AUTHORITY')")]);
   const observed=(await c.f.db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' ORDER BY type,name").all()).results;
   const record={name:table,created_on_actual_D1:true,raw_catalog:observed,raw_catalog_sha256:sha(stableJson(observed))};proof.observations.push(record);await save();
   try{await assert.rejects(guarded(),/CHECK constraint failed/);record.in_batch_guard_rejected=true;await save();}
   finally{await c.f.db.prepare('DROP TABLE '+table).run();}
  }
  await assert.rejects(c.f.db.prepare('CREATE TABLE sqlite_unreviewed_copy(id TEXT)').run(),/reserved for internal use/);proof.literal_sqlite_reserved_prefix_creation_refused=true;
  const final=(await c.f.db.prepare("SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE sql IS NOT NULL AND name NOT GLOB 'sqlite_*' ORDER BY type,name").all()).results;assert.deepEqual(final,originalCatalog);proof.final_catalog_sha256=sha(stableJson(final));proof.exact_original_schema_restored_after_owned_test_objects=true;await save();
 });
 await t.test('an ordinary fake d1_migrations authority table is refused despite its familiar name',async()=>{
  await c.f.db.prepare('CREATE TABLE d1_migrations(id TEXT,authority TEXT)').run();
  await assert.rejects(retentionSchema({DB:c.f.db}),e=>e.code==='privacy_retention_unknown_class');await c.f.db.prepare('DROP TABLE d1_migrations').run();
 });
 await t.test('a changed SMS column cannot silently acquire a current91-class approval',async()=>{
  await c.f.db.prepare('ALTER TABLE assisted_sms_outcomes ADD COLUMN unreviewed_authority TEXT').run();await assert.rejects(retentionSchema({DB:c.f.db}),e=>e.code==='privacy_retention_schema_changed');
 });
});

test('synthetic approved erase of a populated new SMS class remains blocked; review cannot become erasure completion',async t=>{
 const f=await retentionFixture(t),member=await f.login(),operator=await f.operator(),date=new Date().toISOString(),group=randomUUID();
 // Declared synthetic disabled row; this is not an Owner policy activation.
 await f.db.batch([f.db.prepare("INSERT INTO collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES(?,?,?,'Synthetic retained SMS metadata','ikimina',?,?)").bind(group,'retained-'+group,member.user.id,date,date),f.db.prepare("INSERT INTO memberships(id,collection_id,user_id,role,joined_at) VALUES(?,?,?,'owner',?)").bind(randomUUID(),group,member.user.id,date),f.db.prepare("INSERT INTO assisted_sms_policies(collection_id,enabled,revision,template_key,approval_reference_sha256,updated_at) VALUES(?,0,1,'collect.recorded_contribution.v1',?,?)").bind(group,sha('DECLARED SYNTHETIC DISABLED POLICY'),date)]);
 const intake=await f.call('/v1/rpc/request_account_deletion_v1',{p_request_id:randomUUID(),p_reason:null},authorization(member));assert.equal(intake.status,200);f.scopeRequest=intake.body.request_id;const p=await f.policy(operator);p.rules.assisted_sms_policies={action:'erase',basis_reference:'SYNTHETIC TEST ONLY',deadline:new Date(Date.now()-60000).toISOString()};await f.policy(operator,{rules:p.rules});
 const planned=await f.retention(operator,'plan',{operation_id:randomUUID(),request_id:f.scopeRequest,expected_review_revision:0,expected_source_id:sourceId,policy_sha256:f.policySha});assert.equal(planned.status,200);assert.equal(planned.body.tasks.length,f.retentionClasses.length);
 const execute=async name=>{const task=planned.body.tasks.find(x=>x.class_name===name),claim=await f.retention(operator,'claim',{operation_id:randomUUID(),plan_id:planned.body.plan_id,task_id:task.task_id,expected_task_revision:0,lease_seconds:120});assert.equal(claim.status,200);const result=await f.retention(operator,'execute',{operation_id:randomUUID(),claim_id:claim.body.claim_id,fence:claim.body.fence});assert.equal(result.status,200);return result.body;};
 assert.equal((await execute('access')).disposition,'access_quarantined');const blocked=await execute('assisted_sms_policies');assert.equal(blocked.reason,'immutable_or_unimplemented_class_adapter');assert.equal(blocked.verified,false);assert.equal(blocked.all_data_erased,false);assert.equal(blocked.erasure_completed,false);assert.equal((await f.db.prepare('SELECT count(*) AS n FROM assisted_sms_policies').first()).n,1);
});
