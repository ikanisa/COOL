// Extra source checks on the owned managed-chain fixture.
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PostgresStorageJournal} from '../../../supabase/functions/_shared/storage/postgres-journal.js';
import {loadWriterJournalCohort} from './writer-journal-plan.mjs';
import {installPostingSubjectFixture,verifyPostingSubjectRpc} from './journal-posting-subjects.mjs';
import {applyEntry,history} from './migrations.mjs';
import {
  joinCollectMutation,lockAdminSessionMutation,lockCollectMutation,
} from '../../../supabase/functions/_shared/postgres-mutation-lock.js';

const migration = name => readFile(new URL('../../../supabase/migrations/'+name,import.meta.url),'utf8');
const retryClass = 'private:burimunsi_observation_retry_commands';
const smsClass = 'private:burimunsi_payment_sms_deliveries';
const tx = client => ({unsafe:(sql,args)=>client.query(sql,args)});
const hash = text => createHash('sha256').update(text).digest('hex');

async function asRuntime(client,fn) {
  await client.query('BEGIN');
  try {
    await client.query("SET LOCAL ROLE collect_runtime; SET LOCAL collect.edge_verified='true'");
    return await fn(client);
  } finally {
    await client.query('ROLLBACK');
  }
}

async function verifyLockCompatibility(owner,admin,watcher) {
  const hashA='a'.repeat(64),hashB='b'.repeat(64);
  await owner.query('BEGIN');
  try {
    await lockAdminSessionMutation(tx(owner),hashA);
    await admin.query("BEGIN; SET LOCAL lock_timeout='200ms'");
    try {
      await joinCollectMutation(tx(admin));
      await lockAdminSessionMutation(tx(admin),hashB);
    } finally {
      await admin.query('ROLLBACK');
    }
    await watcher.query("BEGIN; SET LOCAL lock_timeout='200ms'");
    try {
      await assert.rejects(lockAdminSessionMutation(tx(watcher),hashA),{code:'55P03'});
    } finally {
      await watcher.query('ROLLBACK');
    }
    await watcher.query("BEGIN; SET LOCAL lock_timeout='200ms'");
    try {
      await assert.rejects(lockCollectMutation(tx(watcher)),{code:'55P03'});
    } finally {
      await watcher.query('ROLLBACK');
    }
  } finally {
    await owner.query('ROLLBACK');
  }
  await watcher.query('BEGIN');
  try {
    await lockCollectMutation(tx(watcher));
    await owner.query("BEGIN; SET LOCAL lock_timeout='200ms'");
    try {
      await assert.rejects(joinCollectMutation(tx(owner)),{code:'55P03'});
    } finally {
      await owner.query('ROLLBACK');
    }
  } finally {
    await watcher.query('ROLLBACK');
  }
}

async function verifyGrants(owner,admin,entry,commit) {
  await admin.query('CREATE ROLE synthetic_extra_writer; GRANT UPDATE ON private.storage_delete_intents TO synthetic_extra_writer; GRANT synthetic_extra_writer TO collect_runtime WITH INHERIT TRUE');
  try {
    await assert.rejects(commit(entry),{code:'55000',message:'collect_scoped_writer_unexpected_grants'});
    const {rows:[{allowed}]}=await owner.query("SELECT has_table_privilege('collect_runtime','private.burimunsi_accounts','UPDATE') AS allowed");
    assert.equal(allowed,true,'a drift refusal must roll back earlier table changes');
  } finally {
    await admin.query('REVOKE synthetic_extra_writer FROM collect_runtime');
  }
  await commit(entry);
  for(const statement of [
    'SELECT id FROM private.burimunsi_sessions FOR SHARE',
    'UPDATE private.burimunsi_sessions SET revoked=true WHERE false',
    'UPDATE private.burimunsi_accounts SET name=name,credential_version=credential_version+1 WHERE false',
    'UPDATE private.burimunsi_scopes SET binding_version=binding_version+1 WHERE false',
    'UPDATE private.storage_put_intents SET updated_at=clock_timestamp(),upload_unresolved=true WHERE false',
    'UPDATE private.storage_payload_reservations SET sealed_body=NULL,cleared_at=clock_timestamp() WHERE false',
    'UPDATE private.storage_upload_attempts SET completed_at=clock_timestamp() WHERE false',
    'UPDATE private.storage_delete_intents SET state=state,absence_proof=absence_proof WHERE false',
  ]) await asRuntime(owner,c=>c.query('EXPLAIN '+statement));
  for(const statement of [
    'UPDATE private.burimunsi_sessions SET expires_at=expires_at WHERE false',
    'INSERT INTO private.burimunsi_sessions (auth_method) VALUES (\'phone_pin\')',
    'UPDATE private.burimunsi_accounts SET principal_user_id=principal_user_id WHERE false',
    'UPDATE private.burimunsi_scopes SET enabled=false WHERE false',
    'UPDATE private.storage_put_intents SET scope=scope WHERE false',
    'UPDATE private.storage_payload_reservations SET aad=aad WHERE false',
    'UPDATE private.storage_upload_attempts SET operation_id=operation_id WHERE false',
    'UPDATE private.storage_delete_intents SET expected_sha256=expected_sha256 WHERE false',
  ]) await assert.rejects(asRuntime(owner,c=>c.query('EXPLAIN '+statement)),{code:'42501'});
}

async function verifyStorageInsertGrants(owner, admin, entry, commit) {
  const generated={
    storage_namespace:['created_at'],
    storage_payload_reservations:['created_at','cleared_at'],
    storage_put_intents:['state','attempts','active_attempt','upload_unresolved','delete_tombstone','last_outcome','created_at','updated_at'],
    storage_upload_attempts:['outcome','started_at','completed_at'],
    storage_objects:['committed_at'],
    storage_delete_intents:['state','last_outcome','absence_proof','created_at','committed_at'],
  };
  const catalog=async()=> (await owner.query(`SELECT c.relname,a.attname,
    has_table_privilege('collect_runtime',c.oid,'INSERT') AS table_insert,
    has_column_privilege('collect_runtime',c.oid,a.attnum,'INSERT') AS insertable,
    has_column_privilege('collect_runtime',c.oid,a.attnum,'INSERT WITH GRANT OPTION') AS grantable,
    has_column_privilege('collect_runtime',c.oid,a.attnum,'SELECT') AS readable,
    has_column_privilege('collect_runtime',c.oid,a.attnum,'UPDATE') AS updatable,
    has_table_privilege('collect_runtime',c.oid,'DELETE') AS deletable
    FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
    WHERE c.relnamespace='private'::regnamespace AND c.relname=ANY($1) AND a.attnum>0 AND NOT a.attisdropped
    ORDER BY c.relname,a.attnum`,[Object.keys(generated)])).rows;
  const before=await catalog();
  assert.equal(before.length,54);
  assert.ok(before.every(row=>row.table_insert && row.insertable && !row.grantable));
  const schemaIdentity=async()=> (await owner.query("SELECT encode(sha256(convert_to(private._retention_manifest_schema_v2()::text,'UTF8')),'hex') AS digest")).rows[0].digest;
  const journalDescriptors=async()=> asRuntime(owner,async c=>(await c.query(
    'SELECT * FROM private.fixture_journal_inventory($1) ORDER BY class_name',['synthetic-primary'])).rows);
  const oldIdentity=await schemaIdentity(), oldDescriptors=await journalDescriptors();
  await admin.query('CREATE ROLE synthetic_storage_inserter; GRANT INSERT(committed_at) ON private.storage_delete_intents TO synthetic_storage_inserter; GRANT synthetic_storage_inserter TO collect_runtime WITH INHERIT TRUE');
  try {
    await assert.rejects(commit(entry),{code:'55000',message:'storage_journal_insert_unexpected_grants'});
    assert.deepEqual(await catalog(),before);
  } finally {
    await admin.query('REVOKE synthetic_storage_inserter FROM collect_runtime');
  }
  await commit(entry);
  assert.deepEqual(await catalog(),before.map(row=>({...row,table_insert:false,insertable:!generated[row.relname].includes(row.attname)})));
  for (const [relation,columns] of Object.entries(generated)) for (const column of columns) {
    await assert.rejects(asRuntime(owner,c=>c.query(
      `EXPLAIN INSERT INTO private.${relation} (${column}) SELECT ${column} FROM private.${relation} WHERE false`)),{code:'42501'});
  }
  assert.notEqual(await schemaIdentity(),oldIdentity);
  assert.deepEqual(await journalDescriptors(),oldDescriptors);
  await assert.rejects(commit(entry),{code:'55000',message:'storage_journal_insert_preimage_changed'});
}

async function verifyStorageJournalReplay(owner, runtime) {
  const {rows:[control]}=await owner.query('SELECT epoch,source_sha256 FROM private.collect_fence_control WHERE singleton');
  await owner.query('SELECT private.collect_fence_release_v3($1,$2,$3)',[randomUUID(),control.epoch,control.source_sha256]);
  await runtime.query("SET ROLE collect_runtime; SET collect.edge_verified='true'");
  try {
    const admission=randomUUID();
    const {rows:[{receipt}]}=await runtime.query("SELECT private.collect_fence_register($1,$2,'http_collect') AS receipt",[admission,control.source_sha256]);
    await runtime.query(`SELECT set_config('collect.fence_admission_id',$1,false),set_config('collect.fence_epoch',$2,false),
      set_config('collect.fence_source_sha256',$3,false)`,[admission,String(receipt.epoch),control.source_sha256]);
    const namespace=(await runtime.query('SELECT origin,bucket FROM private.storage_namespace WHERE singleton')).rows[0]
      ?? {origin:'https://storage.fixture.invalid',bucket:'collect-evidence'};
    const journal=new PostgresStorageJournal({connect:async()=>({query:runtime.query.bind(runtime),release(){}})},{namespace});
    const key='synthetic/journal-insert',scope={ownerId:'synthetic-primary',purpose:'upload',entityId:'synthetic-entry'};
    const digest=hash('synthetic payload'),descriptor={scope,aad:'fixture',keyId:'fixture-key',plaintextSha256:digest};
    const reservation=await journal.reservePayload(key,descriptor,'synthetic-sealed-payload');
    assert.deepEqual(await journal.reservePayload(key,descriptor,'second-seal'),reservation);
    const intent={key,operationId:'synthetic-put',fingerprint:hash(key),sha256:digest,size:17,scope,httpMetadata:{},customMetadata:{}};
    assert.equal((await journal.beginPut(intent)).state,'pending');
    const attempt=await journal.startUpload(intent.operationId,2);
    assert.equal(attempt.started,true);
    await journal.recordOutcome(intent.operationId,'upload_accepted',attempt.attemptId);
    const committed=await journal.commitPut(intent,{verifiedSha256:digest,etag:'fixture-etag'});
    assert.equal(committed.metadata.sha256,digest);
    assert.equal((await journal.beginPut(intent)).state,'committed');
    assert.equal((await journal.startUpload(intent.operationId,2)).started,false);
    assert.equal((await journal.getPutStatus(intent.operationId)).intent.attempts,1);
    await assert.rejects(journal.beginDelete({key}),{code:'delete_authority_required'});
    await runtime.query(`EXPLAIN INSERT INTO private.storage_delete_intents(operation_id,object_key,fingerprint,expected_sha256,scope)
      VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING`,['synthetic-delete',key,hash('delete'),digest,scope]);
    const {rows:[{closed}]}=await runtime.query("SELECT private.collect_fence_close($1,$2,$3,'settled','completed',0,0) AS closed",
      [admission,receipt.epoch,control.source_sha256]);
    assert.equal(closed.state,'settled');
  } finally {
    await runtime.query('RESET ROLE; RESET ALL');
  }
}

export async function primeJournalSchema(owner) {
  await owner.query(await migration('20261117071343_collect_burimunsi_import_lineage_guard.sql'));
  // The scheduler's SQL is out of scope for this fixture. Its captured
  // retention function preimages carry the exact managed catalog forward.
  const preimages=JSON.parse(await readFile(new URL('./fixtures/observation-processing-retention-predecessors.json',import.meta.url),'utf8'));
  for(const {definition} of preimages) await owner.query(definition);
  for(const name of [
    '20261117134954_burimunsi_observation_processing_status.sql',
    '20261118090305_burimunsi_automatic_payment_sms.sql',
    '20261119041100_burimunsi_payment_sms_status.sql',
  ]) await owner.query(await migration(name));
}

async function seedJournals(admin) {
  await admin.query('BEGIN');
  try {
    // Bootstrap only synthetic fixtures while fenced. The replica setting
    // allows synthetic links whose application history is outside this test.
    await admin.query("SET LOCAL session_replication_role='replica'");
    for (const name of ['burimunsi_accounts','burimunsi_observation_retry_commands','burimunsi_payment_sms_deliveries']) {
      await admin.query('ALTER TABLE private.'+name+' DISABLE TRIGGER collect_fence_statement_v1');
    }
    await admin.query(`
      INSERT INTO private.burimunsi_accounts
        (id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
      VALUES ('12345678-0000-0000-0000-000000000001','synthetic-group','synthetic-primary',
        '+250780000001','Synthetic Operator','staff',ARRAY['records.read'],'{}',1,1);
      INSERT INTO private.burimunsi_observation_retry_commands
        (request_id,source_id,collection_id,account_id,result,created_at) VALUES
       ('12345678-0000-0000-0000-000000000002','own-source','synthetic-group','12345678-0000-0000-0000-000000000001','scheduled',1),
       ('12345678-0000-0000-0000-000000000003','wrong-scope','other-group','12345678-0000-0000-0000-000000000001','not_eligible',1),
       ('12345678-0000-0000-0000-000000000004','unknown-operator','synthetic-group','12345678-0000-0000-0000-000000000099','not_eligible',1);
      INSERT INTO private.burimunsi_payment_sms_deliveries
        (attempt_id,collection_id,payment_id,ledger_entry_id,event_id,recipient_user_id,destination_sha256,
         amount_rwf,member_balance_rwf,group_name,posted_at,enabled_at,application_id,message_id,idempotency_key,not_after,next_inspect_at)
      SELECT md5('synthetic-attempt-'||i)::uuid,'synthetic-group','payment-'||i,'ledger-'||i,'event-'||i,
       CASE WHEN i=103 THEN 'different-recipient' ELSE 'synthetic-primary' END,
       repeat('d',64),100,200,'Protected fixture value',now(),now(),'fixture','message-'||i,'intent-'||i,now(),now()
      FROM generate_series(1,103) AS i;
    `);
    for (const name of ['burimunsi_accounts','burimunsi_observation_retry_commands','burimunsi_payment_sms_deliveries']) {
      await admin.query('ALTER TABLE private.'+name+' ENABLE ALWAYS TRIGGER collect_fence_statement_v1');
    }
    await admin.query('COMMIT');
  } catch(error) {
    await admin.query('ROLLBACK');
    throw error;
  }
}

async function verifySubjectLinks(owner,admin,entry,commit) {
  await primeJournalSchema(owner);
  await owner.query('ALTER FUNCTION private._retention_manifest_rows_v2(text) SECURITY INVOKER');
  try {
    await assert.rejects(commit(entry),{code:'55000',message:'burimunsi_journal_links_precondition'});
  } finally {
    await owner.query('ALTER FUNCTION private._retention_manifest_rows_v2(text) SECURITY DEFINER');
  }
  await commit(entry);
  await seedJournals(admin);
  await owner.query(`
    CREATE FUNCTION private.fixture_journal_inventory(subject text)
    RETURNS TABLE (class_name text,descriptor jsonb)
    LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
      SELECT r.class_name,r.descriptor FROM private._retention_manifest_rows_v2(subject) r
      WHERE r.class_name IN ('${retryClass}','${smsClass}')
    $$;
    REVOKE ALL ON FUNCTION private.fixture_journal_inventory(text) FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION private.fixture_journal_inventory(text) TO collect_runtime;
  `);
  const inventory = async subject => asRuntime(owner,async c=>{
    const {rows}=await c.query('SELECT * FROM private.fixture_journal_inventory($1)',[subject]);
    const {rows:[{clean}]}=await c.query(`SELECT
      nullif(current_setting('burimunsi.native_receipt_frame',true),'') IS NULL AND
      nullif(current_setting('burimunsi.pin_frame',true),'') IS NULL AND
      nullif(current_setting('burimunsi.payment_sms_frame',true),'') IS NULL AS clean`);
    assert.equal(clean,true);
    assert.equal(rows.length,2);
    for (const {descriptor} of rows) {
      assert.equal(descriptor.status,'unmapped');
      assert.equal(descriptor.subject_count,null);
      assert.equal(descriptor.erasure,'blocked');
      assert.equal(descriptor.positive_subject_links.complete,false);
      assert.equal(descriptor.positive_subject_links.missing_matches_prove_absence,false);
    }
    return Object.fromEntries(rows.map(({class_name,descriptor})=>[class_name,descriptor.positive_subject_links]));
  });
  const result=await inventory('synthetic-primary');
  assert.deepEqual(result[retryClass].matches,[{
    relationship:'retry_operator',
    record_key_sha256:hash(retryClass+':12345678-0000-0000-0000-000000000002'),
  }]);
  assert.equal(result[smsClass].truncated,true);
  assert.equal(result[smsClass].matches.length,100);
  assert.ok(result[smsClass].matches.every(item=>typeof item.record_key_sha256==='string'
    && item.relationship==='receipt_recipient' && Object.keys(item).length===2));
  const different=await inventory('different-recipient');
  assert.equal(different[retryClass].matches.length,0);
  assert.equal(different[smsClass].matches.length,1);
  await assert.rejects(asRuntime(owner,c=>c.query('SELECT private._burimunsi_retention_journal_links_v1($1,$2)',['synthetic-primary',smsClass])),{code:'42501'});
  for(const relation of ['burimunsi_observation_retry_commands','burimunsi_payment_sms_deliveries']){
    await assert.rejects(asRuntime(owner,c=>c.query('SELECT * FROM private.'+relation)),{code:'42501'});
    await assert.rejects(asRuntime(owner,c=>c.query('DELETE FROM private.'+relation+' WHERE false')),{code:'42501'});
  }
}

export async function verifyWriterJournalSource({owner,admin,watcher}) {
  const {plan,entries:[grants,links,storageInserts,postingSubjects]}=await loadWriterJournalCohort();
  const before=await history(owner);
  let current=before;
  const commit=async entry=>{current=await applyEntry(owner,entry,{before:current});};
  await verifyLockCompatibility(owner,admin,watcher);
  await verifyGrants(owner,admin,grants,commit);
  await verifySubjectLinks(owner,admin,links,commit);
  await verifyStorageInsertGrants(owner,admin,storageInserts,commit);
  await installPostingSubjectFixture({owner,admin,entry:postingSubjects,commit});
  const installed=await history(watcher);
  assert.deepEqual(installed,current,'independent synthetic history readback');
  assert.equal(installed.length,before.length+4);
  assert.deepEqual(installed.slice(-4).map(row=>row.sha256),plan.migrations.map(row=>row.sha256));
  await verifyStorageJournalReplay(owner,watcher);
  const postingSubjectEvidence=await verifyPostingSubjectRpc({owner,runtime:watcher});
  return {plan,postingSubjectEvidence,fixtureHistory:{before:before.length,after:installed.length},
    checks:['scoped_writer_lock_compatibility','writer_column_acl_and_atomicity','journal_subject_inventory_and_acl','scoped_posting_subjects_capture_and_page_v2',
      'storage_insert_column_acl_and_atomicity','storage_journal_creation_and_replay','atomic_cohort_history_and_independent_readback']};
}
