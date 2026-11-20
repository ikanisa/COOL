import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {withSyntheticArchive,pinnedArchiveSource,syntheticArchiveIdentity} from './synthetic-archive.mjs';
const src=new URL('../../../supabase/migrations/20261101012309_collect_admission_archive.sql',import.meta.url);
const baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3',source='a'.repeat(64);
const wait=ms=>new Promise(resolve=>setTimeout(resolve,ms));

test('source and transaction framing require the exact reviewed archive bytes',async()=>{
 const data=await readFile(src),parsed=pinnedArchiveSource(data);
 assert.equal(syntheticArchiveIdentity.productionDispatch,false);assert.ok(parsed.body.includes('CREATE TABLE private.collect_fence_admission_archive'));
 assert.equal(parsed.text,data.toString('utf8'));assert.throws(()=>pinnedArchiveSource(Buffer.concat([data,Buffer.from(' ')])),/ARCHIVE_SOURCE_CHANGED/);
});

test('archive action is atomic and preimage-pinned on a separately owned native PG17 cluster',{timeout:180000},async t=>{
 await withSyntheticArchive(async ({owner,admin,watcher,backendPid,capture,apply})=>{
  const clean=randomUUID(),unknown=randomUUID(),stopped=randomUUID(),fenceOperation=randomUUID();
  const primaryBefore=(await owner.query(`SELECT (SELECT to_jsonb(u) FROM auth.users u WHERE email='synthetic@example.invalid') auth,
   (SELECT to_jsonb(u) FROM app.users u WHERE id='synthetic-primary') app,
   (SELECT to_jsonb(l) FROM private.auth_principal_links l WHERE user_id='synthetic-primary') link`)).rows[0];
  assert.ok(primaryBefore.auth&&primaryBefore.app&&primaryBefore.link);
  // These are synthetic states, inserted only into the newly created fixture.
  await owner.query(`INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id)
   VALUES(true,'rrlduytparvsjfmegalh',$1,$2,1,'fenced',$3)`,[baseline,source,fenceOperation]);
  await owner.query(`INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state,reason,external_dispatches,uncertain_dispatches,closed_at)
   VALUES($1,1,$3,'http_collect','settled','completed',1,0,clock_timestamp()),($2,1,$3,'http_collect','settled','completed_with_unknown_obligation',1,1,clock_timestamp())`,[clean,unknown,source]);
  await owner.query("INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state) VALUES($1,1,$2,'http_collect','active')",[stopped,source]);
  // Synthetic-only role-absence and evidence values exercise the real prior
  // lifecycle trigger. They do not prove any real executor stopped or effect.
  assert.equal((await admin.query("SELECT EXISTS(SELECT 1 FROM pg_roles WHERE oid=4000000000::oid OR rolname='collect_cf_preserve_20990101') e")).rows[0].e,false);
  await owner.query(`SELECT private.collect_fence_record_stopped_admission_v3($1,$2,'rrlduytparvsjfmegalh',$3,1,$4,'http_collect',$5,
   4000000000::oid,'collect_cf_preserve_20990101',$5,true,$6,$5)`,[randomUUID(),fenceOperation,stopped,source,'b'.repeat(64),randomUUID()]);
  await t.test('history name, order, bytes and cardinality mismatch are rejected',async()=>{
   const original=(await admin.query("SELECT statements[1] sql FROM supabase_migrations.schema_migrations WHERE version='20261029120000'")).rows[0].sql;
   await admin.query("UPDATE supabase_migrations.schema_migrations SET name='synthetic_drift' WHERE version='20261029120000'");
   await assert.rejects(capture(),/SYNTHETIC_HISTORY_MISMATCH/);
   await admin.query("UPDATE supabase_migrations.schema_migrations SET name='collect_client_diagnostics' WHERE version='20261029120000'");
   await admin.query("UPDATE supabase_migrations.schema_migrations SET version='20261029125959' WHERE version='20261029120000'");
   await assert.rejects(capture(),/SYNTHETIC_HISTORY_MISMATCH/);
   await admin.query("UPDATE supabase_migrations.schema_migrations SET version='20261029120000' WHERE version='20261029125959'");
   await admin.query("UPDATE supabase_migrations.schema_migrations SET statements=ARRAY[statements[1]||'--drift'] WHERE version='20261029120000'");
   await assert.rejects(capture(),/SYNTHETIC_HISTORY_MISMATCH/);
   await admin.query("UPDATE supabase_migrations.schema_migrations SET statements=ARRAY[$1::text] WHERE version='20261029120000'",[original]);
   await admin.query("UPDATE supabase_migrations.schema_migrations SET statements=statements||'drift'::text WHERE version='20261029120000'");
   await assert.rejects(capture(),/SYNTHETIC_HISTORY_MISMATCH/);
   await admin.query("UPDATE supabase_migrations.schema_migrations SET statements=ARRAY[statements[1]] WHERE version='20261029120000'");
   assert.equal((await capture()).admissions.count,3);
  });
  await t.test('routine security drift is detected before any DDL',async()=>{
   const before=await capture();
   await admin.query('ALTER FUNCTION private._collect_fence_resources() SECURITY INVOKER');
   await assert.rejects(apply({expectedPreimageSha256:before.sha256}),/SYNTHETIC_PREIMAGE_CHANGED/);
   await admin.query('ALTER FUNCTION private._collect_fence_resources() SECURITY DEFINER');
   assert.equal((await capture()).sha256,before.sha256);
  });
  await t.test('unreviewed event triggers refuse before DDL',async()=>{
   await admin.query("CREATE FUNCTION public.synthetic_event() RETURNS event_trigger LANGUAGE plpgsql AS $$BEGIN RETURN;END$$; CREATE EVENT TRIGGER synthetic_event ON ddl_command_end EXECUTE FUNCTION public.synthetic_event()");
   try{await assert.rejects(capture(),/SYNTHETIC_EVENT_TRIGGER_REFUSED/);}finally{await admin.query('DROP EVENT TRIGGER synthetic_event; DROP FUNCTION public.synthetic_event()');}
  });
  await t.test('a writer committing while the admission lock is awaited invalidates the old preimage',async()=>{
   const before=await capture();await admin.query('BEGIN');
   await admin.query('LOCK TABLE private.collect_fence_admissions IN SHARE ROW EXCLUSIVE MODE');
   await admin.query(`INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state,reason,external_dispatches,uncertain_dispatches,closed_at)
    VALUES($1,1,$2,'jobs','settled','completed',1,0,clock_timestamp())`,[randomUUID(),source]);
   const pending=apply({expectedPreimageSha256:before.sha256});void pending.catch(()=>{});
   let blocked=false;const deadline=Date.now()+3500;
   while(Date.now()<deadline&&!blocked){blocked=(await watcher.query('SELECT cardinality(pg_blocking_pids($1))>0 b',[backendPid])).rows[0].b;if(!blocked)await wait(25);}
   assert.equal(blocked,true,'executor never waited on owned fixture writer');
   await admin.query('COMMIT');await assert.rejects(pending,/SYNTHETIC_PREIMAGE_CHANGED/);
   assert.equal((await capture()).admissions.count,4);
  });
  await t.test('failures after body and after history roll back objects and history together',async()=>{
   const before=await capture();
   for(const fault of ['after-body','after-history']){
    await assert.rejects(apply({expectedPreimageSha256:before.sha256,fault}),fault==='after-body'?/SYNTHETIC_FAIL_AFTER_BODY/:/SYNTHETIC_FAIL_AFTER_HISTORY/);
    const state=(await owner.query(`SELECT to_regclass('private.collect_fence_admission_archive') IS NULL absent,
     (SELECT count(*)::int FROM supabase_migrations.schema_migrations WHERE version='20261101012309') recorded`)).rows[0];
    assert.deepEqual(state,{absent:true,recorded:0});assert.equal((await capture()).sha256,before.sha256);
   }
  });
  await t.test('a history-insert trigger cannot tamper with an earlier row and still commit',async()=>{
   await owner.query(`CREATE FUNCTION supabase_migrations.synthetic_tamper() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN UPDATE supabase_migrations.schema_migrations SET name='tampered' WHERE version='20261029120000';RETURN NEW;END$$;
    CREATE TRIGGER synthetic_tamper BEFORE INSERT ON supabase_migrations.schema_migrations FOR EACH ROW EXECUTE FUNCTION supabase_migrations.synthetic_tamper()`);
   try{
    const before=await capture();await assert.rejects(apply({expectedPreimageSha256:before.sha256}),/POST_HISTORY_CONTENT_FAILED/);
    const row=(await owner.query("SELECT name FROM supabase_migrations.schema_migrations WHERE version='20261029120000'")).rows[0];
    assert.equal(row.name,'collect_client_diagnostics');
    assert.equal((await owner.query("SELECT to_regclass('private.collect_fence_admission_archive') IS NULL absent")).rows[0].absent,true);
   }finally{await owner.query('DROP TRIGGER synthetic_tamper ON supabase_migrations.schema_migrations; DROP FUNCTION supabase_migrations.synthetic_tamper()');}
  });
  await t.test('a history-insert trigger cannot remove the new archive index after DDL validation',async()=>{
   await owner.query(`CREATE FUNCTION supabase_migrations.synthetic_drop_index() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN EXECUTE 'DROP INDEX private.collect_fence_archivable';RETURN NEW;END$$;
    CREATE TRIGGER synthetic_drop_index BEFORE INSERT ON supabase_migrations.schema_migrations FOR EACH ROW EXECUTE FUNCTION supabase_migrations.synthetic_drop_index()`);
   try{
    const before=await capture();await assert.rejects(apply({expectedPreimageSha256:before.sha256}),/POST_HISTORY_CATALOG_CHANGED/);
    assert.equal((await owner.query("SELECT to_regclass('private.collect_fence_admission_archive') IS NULL absent")).rows[0].absent,true);
   }finally{await owner.query('DROP TRIGGER synthetic_drop_index ON supabase_migrations.schema_migrations; DROP FUNCTION supabase_migrations.synthetic_drop_index()');}
  });
  await t.test('success records the original source and preserves unknown obligations',async()=>{
   const before=await capture(),result=await apply({expectedPreimageSha256:before.sha256});
   assert.equal(result.status,'synthetic_committed');assert.equal(result.productionDispatch,false);
   const recorded=(await owner.query("SELECT statements[1] sql FROM supabase_migrations.schema_migrations WHERE version='20261101012309'")).rows;
   assert.equal(recorded.length,1);assert.equal(recorded[0].sql,(await readFile(src)).toString('utf8'));
   const archive=(await owner.query('SELECT private.collect_fence_archive_settled_v4(100) result')).rows[0].result;
   assert.equal(archive.archived,2);assert.equal(archive.originalRowsDeleted,false);assert.equal(archive.unknownObligationSettled,false);
   const status=(await owner.query(`SELECT (SELECT count(*)::int FROM private.collect_fence_admissions) retained,
    (SELECT count(*)::int FROM private.collect_fence_working_admissions) working,
    (SELECT count(*)::int FROM private.collect_fence_admission_archive) archived,
    (SELECT state='settled' AND uncertain_dispatches=1 AND reason='completed_with_unknown_obligation' FROM private.collect_fence_admissions WHERE admission_id=$1) unknown_retained,
    (SELECT state='active' FROM private.collect_fence_admissions WHERE admission_id=$2) stopped_retained`,[unknown,stopped])).rows[0];
   assert.deepEqual(status,{retained:4,working:2,archived:2,unknown_retained:true,stopped_retained:true});
   await assert.rejects(owner.query("UPDATE private.collect_fence_admissions SET state='settled',reason='completed',closed_at=clock_timestamp() WHERE admission_id=$1",[stopped]),/collect_stopped_admission_immutable/);
   const primaryAfter=(await owner.query(`SELECT (SELECT to_jsonb(u) FROM auth.users u WHERE email='synthetic@example.invalid') auth,
    (SELECT to_jsonb(u) FROM app.users u WHERE id='synthetic-primary') app,
    (SELECT to_jsonb(l) FROM private.auth_principal_links l WHERE user_id='synthetic-primary') link`)).rows[0];
   assert.deepEqual(primaryAfter,primaryBefore);
   await assert.rejects(apply({expectedPreimageSha256:before.sha256}),/SYNTHETIC_HISTORY_MISMATCH/);
  });
 });
});
