// Invoked only by chain.test.mjs inside its owned socket-only PostgreSQL 17.
// The real synthetic migration ledger is preserved. Its alternative 89-row
// registry is test input copied from the verified recorded SQL sources.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {mkdtemp,readdir,readFile,realpath,rename,rm,writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import {setTimeout as delay} from 'node:timers/promises';
import {join} from 'node:path';
import {runCloudRelease} from './apply.mjs';
import {history} from './migrations.mjs';
import {readRecordedHistory,readRecordedSql} from './recorded-history.mjs';
import {loadWriterJournalCohort} from './writer-journal-plan.mjs';
import {primeJournalSchema} from './writer-journal-source.mjs';

const {Client}=createRequire(import.meta.url)('pg');

export async function verifyWriterJournalRelease({owner,admin,database}) {
  const settings=(await owner.query(`SELECT inet_server_addr() IS NULL AS socket,current_database() AS db,
    current_setting('cluster_name') AS cluster,session_user AS owner`)).rows[0];
  assert.ok(settings.socket && settings.db===database && /^collect_archive_[0-9a-f]{24}_test$/.test(database)
    && settings.cluster==='collect_archive_next_fixture' && settings.owner==='postgres');
  await primeJournalSchema(owner);
  await admin.query('BEGIN');
  try {
    await admin.query('ALTER TABLE private.storage_namespace DISABLE TRIGGER collect_fence_statement_v1');
    await admin.query("INSERT INTO private.storage_namespace(singleton,origin,bucket) VALUES(true,'https://storage.fixture.invalid','synthetic-private') ON CONFLICT DO NOTHING");
    await admin.query('INSERT INTO storage.buckets(id,public) SELECT bucket,false FROM private.storage_namespace WHERE singleton');
    await admin.query('ALTER TABLE private.storage_namespace ENABLE ALWAYS TRIGGER collect_fence_statement_v1');
    await admin.query('COMMIT');
  } catch (error) {await admin.query('ROLLBACK');throw error;}
  const actualSetupCount=(await history(owner)).length;
  const {record}=await readRecordedHistory('cloud-history-20261120-epoch44.json');
  const paymentReferences=['20261119114700','20261120104500'];
  for (const version of paymentReferences) {
    const entry=record.history.find(row=>row.version===version);
    await owner.query(await readRecordedSql(entry));
  }
  await owner.query('ALTER TABLE supabase_migrations.schema_migrations RENAME TO fixture_executed_chain');
  await owner.query('CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,name text,statements text[])');
  for (const row of record.history) {
    await owner.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',
      [row.version,row.name,[await readRecordedSql(row)]]);
  }
  const source=await loadWriterJournalCohort();
  const dir=await realpath(await mkdtemp(join(tmpdir(),'collect-synthetic-journal-window-')));
  const credential=join(dir,'synthetic-credential');
  await writeFile(credential,'synthetic only\n',{mode:0o600});
  const env=owner.connectionParameters;
  const run=async(args,intercept=null)=>{
    let opened=0;
    const openConnection=async password=>{
      assert.equal(password,'synthetic only');
      const db=new Client({host:env.host,port:env.port,database,user:'postgres',connectionTimeoutMillis:5000});
      db.on('error',()=>{});await db.connect();
      const which=opened++;
      if (!intercept || which!==0) return db;
      const query=db.query.bind(db);
      return {query:(sql,values)=>intercept(sql,values,query),end:()=>db.end()};
    };
    return runCloudRelease(['--writer-journal',...args,'--credential-file',credential],{openConnection});
  };
  const inspect=()=>run(['inspect']);
  const states=[];
  try {
    const first=await inspect();
    const catalogFn=(await owner.query(`SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') AS body_sha256,
      provolatile FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure`)).rows[0];
    assert.equal(first.state.migration_count,89);
    assert.equal(first.state.ordered_sha256,source.plan.predecessor.ordered_sha256);
    const grants=source.entries[0].version, initial=['apply',grants,first.capture_sha256,dir];
    await assert.rejects(run(['apply',source.entries[1].version,first.capture_sha256,dir]),/writer_journal_not_next/);
    await assert.rejects(run(['apply',grants,'0'.repeat(64),dir]),/writer_journal_preimage_changed/);
    await owner.query("UPDATE supabase_migrations.schema_migrations SET statements=ARRAY['SELECT 1'] WHERE version=$1",[record.history[0].version]);
    await assert.rejects(inspect(),/history differs/);
    await owner.query('UPDATE supabase_migrations.schema_migrations SET statements=$1 WHERE version=$2',
      [[await readRecordedSql(record.history[0])],record.history[0].version]);

    await owner.query('GRANT UPDATE ON private.burimunsi_accounts TO collect_runtime WITH GRANT OPTION');
    await assert.rejects(run(initial),/writer_journal_grant_changed/);
    await owner.query('REVOKE GRANT OPTION FOR UPDATE ON private.burimunsi_accounts FROM collect_runtime');
    await owner.query('ALTER FUNCTION private._retention_manifest_rows_v2(text) SECURITY INVOKER');
    await assert.rejects(inspect(),/writer_journal_function_access_changed/);
    await owner.query('ALTER FUNCTION private._retention_manifest_rows_v2(text) SECURITY DEFINER');
    await admin.query('UPDATE storage.buckets SET public=true');
    await assert.rejects(inspect(),/writer_journal_bucket_read_required/);
    await admin.query('UPDATE storage.buckets SET public=false');
    await owner.query('ALTER TABLE private.burimunsi_scopes ADD COLUMN synthetic_unreviewed_column text');
    await assert.rejects(inspect(),/writer_journal_role_fingerprint_changed/);
    await owner.query('ALTER TABLE private.burimunsi_scopes DROP COLUMN synthetic_unreviewed_column');
    const cron=(await owner.query("SELECT to_regnamespace('cron') IS NOT NULL AS present")).rows[0];
    assert.equal(cron.present,false,'review the scheduler fixture before changing the synthetic scope');
    await admin.query('CREATE SCHEMA cron; CREATE TABLE cron.job(jobname text,active boolean); GRANT USAGE ON SCHEMA cron TO postgres; GRANT SELECT ON cron.job TO postgres');
    await admin.query("INSERT INTO cron.job VALUES ('collect-jobs-maintenance-v1',true)");
    const running=await inspect();
    assert.equal(running.state.scheduler.blocking,true);
    await assert.rejects(run(['apply',grants,running.capture_sha256,dir]),/scheduler_not_drained/);
    await admin.query('DROP SCHEMA cron CASCADE');

    const f=first.state.fence;
    await owner.query('SELECT private.collect_fence_release_v3($1,$2,$3)',[randomUUID(),f.epoch,f.source_sha256]);
    const opened=await inspect();
    assert.equal(opened.state.fence.mode,'open');
    await assert.rejects(run(['apply',grants,opened.capture_sha256,dir]),/requires_fenced_window/);
    const hold=randomUUID(),epoch=opened.state.fence.epoch;
    await owner.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3)',[hold,epoch,f.source_sha256]);
    await owner.query('SELECT private.collect_fence_drain_managed_v1($1,$2,$3)',[hold,epoch,f.source_sha256]);
    await assert.rejects(run(initial),/writer_journal_preimage_changed/);

    for (const [index,entry] of source.entries.entries()) {
      const before=await inspect(),args=[entry.version,before.capture_sha256,dir];
      assert.equal(before.state.next.sha256,entry.sha256);
      let result;
      if (index===0) {
        // A durable intent exists, then the client fails before submitting the SQL body.
        await assert.rejects(run(['apply',...args],(sql,values,query)=>{
          if(sql.includes('DO $grants$')) throw Error('synthetic_connection_lost_before_body');
          return query(sql,values);
        }),/writer_journal_reconcile_required/);
        assert.equal((await run(['reconcile',...args])).status,'not_recorded');
        await assert.rejects(run(['apply',...args]),{code:'EEXIST'});
        result=await run(['retry',...args]);
      } else if (index===1) {
        const previous=(await readdir(dir)).find(name=>name.startsWith(grants+'-outcome-'));
        assert.ok(previous);
        await rename(join(dir,previous),join(dir,'held.fixture'));
        try {await assert.rejects(run(['apply',...args]),/previous_independent_readback_required/);}
        finally {await rename(join(dir,'held.fixture'),join(dir,previous));}
        // Reconciliation begins while the durable intent's transaction is open.
        // Observe it waiting for the writer lock, then lose only the COMMIT reply.
        const atCommit=Promise.withResolvers(),releaseCommit=Promise.withResolvers();
        const interrupted=assert.rejects(run(['apply',...args],async(sql,values,query)=>{
          if (sql!=='COMMIT') return query(sql,values);
          atCommit.resolve();await releaseCommit.promise;
          await query(sql,values);throw Error('synthetic_lost_commit_response');
        }),/writer_journal_reconcile_required/);
        await Promise.race([atCommit.promise,interrupted.then(()=>assert.fail('writer did not reach COMMIT'))]);
        const reconciliation=run(['reconcile',...args]);
        try {
          const until=Date.now()+3000;
          let waiting=false;
          while (!waiting && Date.now()<until) {
            waiting=(await admin.query(`SELECT EXISTS (SELECT FROM pg_locks WHERE locktype='advisory'
              AND classid=7346371 AND objid=11 AND NOT granted) AS waiting`)).rows[0].waiting;
            if (!waiting) await delay(10);
          }
          assert.equal(waiting,true,'reconciliation must wait until the preceding transaction ends');
        } finally { releaseCommit.resolve(); }
        await interrupted;
        assert.equal((await reconciliation).status,'recorded');
        result=await run(['retry',...args]);
        assert.equal(result.status,'recorded');
      } else if (index===2) {
        const attempts=await Promise.allSettled([run(['apply',...args]),run(['apply',...args])]);
        const applied=attempts.filter(row=>row.status==='fulfilled');
        assert.equal(applied.length,1,'concurrent attempts must apply exactly once');
        assert.match(attempts.find(row=>row.status==='rejected').reason.message,
          /migration_history_changed|writer_journal_not_next|writer_journal_witness_changed/);
        result=applied[0].value;
      } else {
        result=await run(['apply',...args]);
      }
      assert.equal(result.state.migration_count,90+index);
      assert.equal(result.state.ordered_sha256,source.plan.migrations[index].expected_history.ordered_sha256);
      assert.equal(result.sql_sha256,entry.sha256);
      assert.match(result.state.role_sha256,/^[0-9a-f]{64}$/);
      assert.match(result.state.retention_sha256,/^[0-9a-f]{64}$/);
      const intent=JSON.parse(await readFile(join(dir,entry.version+'-intent.json'),'utf8'));
      assert.equal(intent.before.next.sha256,entry.sha256);
      states.push({count:result.state.migration_count,ordered_sha256:result.state.ordered_sha256,sql_sha256:entry.sha256,
        role_sha256:result.state.role_sha256,retention_sha256:result.state.retention_sha256});
    }
    assert.notEqual(states[1].role_sha256,states[2].role_sha256);
    assert.notEqual(states[0].retention_sha256,states[1].retention_sha256);
    assert.notEqual(states[2].retention_sha256,states[3].retention_sha256);
    await owner.query('GRANT INSERT(created_at) ON private.storage_namespace TO collect_runtime');
    await assert.rejects(inspect(),/writer_journal_columns_changed/);
    await owner.query('REVOKE INSERT(created_at) ON private.storage_namespace FROM collect_runtime');
    const final=await inspect();
    assert.equal(final.state.next,null);
    assert.equal((await history(owner)).length,93);
    assert.equal((await owner.query('SELECT count(*)::int AS count FROM supabase_migrations.fixture_executed_chain')).rows[0].count,actualSetupCount);
    return {status:'synthetic_writer_journal_operator_verified',original_setup_history_rows:actualSetupCount,payment_reference_setup:paymentReferences,
      predecessor_registry_fixture_rows:89,predecessor_catalog_function:catalogFn,predecessor_role_sha256:first.state.role_sha256,
      predecessor_retention_sha256:first.state.retention_sha256,states,final_fence:final.state.fence.mode,
      checks:['role_and_catalog_drift','ordered_history_drift','refuse_open_or_busy_scheduler','changed_fence_identity',
        'uncertain_rollback_and_retry','uncertain_commit_and_duplicate_refusal','live_transaction_reconciliation_wait','concurrent_apply_once','independent_per_step_readback',
        'inventoried_private_bucket_visibility','schema_column_drift','previous_step_readback_required']};
  } finally {await rm(dir,{recursive:true,force:true});}
}
