import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID,createHash} from 'node:crypto';
import {readFile,mkdir,realpath} from 'node:fs/promises';
import {join} from 'node:path';
import pg from '../node_modules/pg/lib/index.js';
import {withOwnedArchiveFixture} from '../managed-migration-next/synthetic-fixture.mjs';
import {archiveIdentity,MANAGED_REVIEWED_APPLY_PLAN_SHA256,captureArchivePreimage,applyArchiveInTransaction,reconcileArchive} from './archive-core.mjs';
import {applyManagedArchive,archivePlanDigest,syntheticJournaledApply,syntheticJournaledReconcile} from './operator.mjs';

const initial='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3',source='a'.repeat(64);
const hasCode=code=>e=>e?.archiveCode===code;

test('managed archive apply stays closed before credentials or a connection are used',async()=>{
 assert.equal(MANAGED_REVIEWED_APPLY_PLAN_SHA256,null);
 await assert.rejects(applyArchiveInTransaction({mode:'managed'},{expectedPreimageSha256:'a'.repeat(64),reviewedPlanSha256:'b'.repeat(64)}),hasCode('MANAGED_APPLY_UNQUALIFIED'));
 let read=false;await assert.rejects(applyManagedArchive({plan:{reviewedPlanSha256:'b'.repeat(64)},get secret(){read=true;return 'synthetic';}}),hasCode('MANAGED_APPLY_UNQUALIFIED'));
 assert.equal(read,false);
});

test('read-only preimage and atomic archive use exact source on an owned PG17 database',{timeout:180000},async t=>{
 await withOwnedArchiveFixture(async fixture=>{
  const {owner,admin,watcher,database,backendPid,executed}=fixture;
  const ctx={mode:'synthetic',client:owner,database,backendPid,executed,timeoutMs:60000};
  const journalRoot=join(fixture.fixtureRoot,'archive-journal');await mkdir(journalRoot,{mode:0o700});assert.equal(await realpath(journalRoot),journalRoot);
  const clean=randomUUID(),unknown=randomUUID(),operation=randomUUID();
  const accountSql=`SELECT (SELECT to_jsonb(u) FROM auth.users u WHERE email='synthetic@example.invalid') auth,
   (SELECT to_jsonb(u) FROM app.users u WHERE id='synthetic-primary') app,
   (SELECT to_jsonb(l) FROM private.auth_principal_links l WHERE user_id='synthetic-primary') link`;
  const primaryBefore=(await owner.query(accountSql)).rows[0];assert.ok(primaryBefore.auth&&primaryBefore.app&&primaryBefore.link);
  await owner.query(`INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id)
   VALUES(true,'rrlduytparvsjfmegalh',$1,$2,1,'fenced',$3)`,[initial,source,operation]);
  await owner.query(`INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state,reason,external_dispatches,uncertain_dispatches,closed_at)
   VALUES($1,1,$3,'http_collect','settled','completed',1,0,clock_timestamp()),
    ($2,1,$3,'http_collect','settled','completed_with_unknown_obligation',1,1,clock_timestamp())`,[clean,unknown,source]);
  let captured,plan;
  await t.test('capture is read-only and returns a bounded history/fence/catalogue preimage',async()=>{
   captured=await captureArchivePreimage(ctx);
   assert.equal(captured.status,'preimage_captured');assert.equal(captured.productionAuthorized,false);
   assert.equal(typeof captured.preimage.catalog_json,'string');assert.equal(typeof captured.preimage.fence_json,'string');
   assert.equal(captured.preimage.history.length,16);assert.equal(captured.preimage.admissions.count,2);
   assert.equal((await owner.query("SELECT count(*)::int n FROM supabase_migrations.schema_migrations WHERE version=$1",[archiveIdentity.version])).rows[0].n,0);
   await assert.rejects(applyArchiveInTransaction(ctx,{expectedPreimageSha256:captured.sha256,
    expectedAdmissions:{...captured.preimage.admissions,sha:'e'.repeat(64)}}),hasCode('PREIMAGE_ADMISSIONS_CHANGED'));
  });
  await t.test('history or admission changes invalidate the previous preimage',async()=>{
   await admin.query("UPDATE supabase_migrations.schema_migrations SET name='changed' WHERE version='20261029120000'");
   await assert.rejects(captureArchivePreimage(ctx),/SYNTHETIC_HISTORY_MISMATCH/);
   await admin.query("UPDATE supabase_migrations.schema_migrations SET name='collect_client_diagnostics' WHERE version='20261029120000'");
   await owner.query(`INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state,reason,external_dispatches,uncertain_dispatches,closed_at)
    VALUES($1,1,$2,'jobs','settled','completed',0,0,clock_timestamp())`,[randomUUID(),source]);
   await assert.rejects(applyArchiveInTransaction(ctx,{expectedPreimageSha256:captured.sha256,expectedAdmissions:captured.preimage.admissions}),hasCode('PREIMAGE_CHANGED'));
   assert.equal((await owner.query("SELECT to_regclass('private.collect_fence_admission_archive') IS NULL absent")).rows[0].absent,true);
   captured=await captureArchivePreimage(ctx);assert.equal(captured.preimage.admissions.count,3);
  });
  await t.test('forced row-security filtering cannot hide an admission from capture',async()=>{
   await admin.query('ALTER TABLE private.collect_fence_admissions ENABLE ROW LEVEL SECURITY; ALTER TABLE private.collect_fence_admissions FORCE ROW LEVEL SECURITY');
   try{await assert.rejects(captureArchivePreimage(ctx),hasCode('VISIBILITY_REFUSED'));}
   finally{await admin.query('ALTER TABLE private.collect_fence_admissions NO FORCE ROW LEVEL SECURITY');}
   assert.equal((await captureArchivePreimage(ctx)).sha256,captured.sha256);
  });
  await t.test('failure after migration SQL or history insertion rolls both back',async()=>{
   for(const fault of ['after-body','after-history']){
    await assert.rejects(applyArchiveInTransaction(ctx,{expectedPreimageSha256:captured.sha256,expectedAdmissions:captured.preimage.admissions,fault}),hasCode(fault==='after-body'?'SYNTHETIC_AFTER_BODY':'SYNTHETIC_AFTER_HISTORY'));
    assert.equal((await owner.query("SELECT to_regclass('private.collect_fence_admission_archive') IS NULL absent")).rows[0].absent,true);
    assert.equal((await captureArchivePreimage(ctx)).sha256,captured.sha256);
   }
  });
  await t.test('a writer that commits while locks are awaited invalidates the saved preimage',async()=>{
   await admin.query('BEGIN');await admin.query('LOCK TABLE private.collect_fence_admissions IN SHARE ROW EXCLUSIVE MODE');
   await admin.query(`INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state,reason,external_dispatches,uncertain_dispatches,closed_at)
    VALUES($1,1,$2,'jobs','settled','completed',0,0,clock_timestamp())`,[randomUUID(),source]);
   const pending=applyArchiveInTransaction(ctx,{expectedPreimageSha256:captured.sha256,expectedAdmissions:captured.preimage.admissions});void pending.catch(()=>{});
   let blocked=false;const end=Date.now()+3000;
   while(!blocked&&Date.now()<end){blocked=(await watcher.query('SELECT cardinality(pg_blocking_pids($1))>0 AS blocked',[backendPid])).rows[0].blocked;if(!blocked)await new Promise(r=>setTimeout(r,25));}
   assert.equal(blocked,true);await admin.query('COMMIT');await assert.rejects(pending,hasCode('PREIMAGE_CHANGED'));
   captured=await captureArchivePreimage(ctx);
  });
  await t.test('read-only capture waits for a prior writer and includes its committed row',async()=>{
   const before=captured;await admin.query('BEGIN');await admin.query('LOCK TABLE private.collect_fence_admissions IN SHARE ROW EXCLUSIVE MODE');
   await admin.query(`INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state,reason,external_dispatches,uncertain_dispatches,closed_at)
    VALUES($1,1,$2,'jobs','settled','completed',0,0,clock_timestamp())`,[randomUUID(),source]);
   const pending=captureArchivePreimage(ctx);void pending.catch(()=>{});let blocked=false;const end=Date.now()+3000;
   while(!blocked&&Date.now()<end){blocked=(await watcher.query('SELECT cardinality(pg_blocking_pids($1))>0 AS blocked',[backendPid])).rows[0].blocked;if(!blocked)await new Promise(r=>setTimeout(r,25));}
   assert.equal(blocked,true);await admin.query('COMMIT');captured=await pending;
   assert.equal(captured.preimage.admissions.count,before.preimage.admissions.count+1);assert.notEqual(captured.sha256,before.sha256);
  });
  await t.test('a real PostgreSQL ROLLBACK tag in response to COMMIT is unknown, never committed',async()=>{
   const original=owner.query.bind(owner);let tag;
   owner.query=async(...args)=>{
    if(args[0]==='COMMIT'){
     try{await original('SELECT 1/0');}catch{}
     const result=await original(...args);tag=result.command;return result;
    }
    return original(...args);
   };
   try{await assert.rejects(applyArchiveInTransaction(ctx,{expectedPreimageSha256:captured.sha256,expectedAdmissions:captured.preimage.admissions}),hasCode('COMMIT_UNKNOWN'));}
   finally{owner.query=original;}
   assert.equal(tag,'ROLLBACK');
   assert.equal((await owner.query("SELECT to_regclass('private.collect_fence_admission_archive') IS NULL absent")).rows[0].absent,true);
   assert.equal((await owner.query('SELECT count(*)::int n FROM supabase_migrations.schema_migrations WHERE version=$1',[archiveIdentity.version])).rows[0].n,0);
   assert.equal((await captureArchivePreimage(ctx)).sha256,captured.sha256);
  });
  await t.test('lost commit acknowledgement remains unknown while exact SQL and uncertain admissions persist',async()=>{
   const manifest=await readFile(new URL('./SOURCE-PINS.json',import.meta.url));
   const base={preimageSha256:captured.sha256,admissions:captured.preimage.admissions,exclusionEvidenceSha256:'d'.repeat(64),
    implementationManifestSha256:createHash('sha256').update(manifest).digest('hex')};
   plan={...base,reviewedPlanSha256:archivePlanDigest(base)};
   const altered={...base,implementationManifestSha256:'f'.repeat(64)};
   await assert.rejects(syntheticJournaledApply(ctx,journalRoot,{...altered,reviewedPlanSha256:archivePlanDigest(altered)}),hasCode('SOURCE_MANIFEST_REFUSED'));
   const original=owner.query.bind(owner);let lost=false;
   owner.query=async(...args)=>{const result=await original(...args);if(args[0]==='COMMIT'&&!lost){lost=true;throw Error('synthetic lost acknowledgement');}return result;};
   try{assert.deepEqual(await syntheticJournaledApply(ctx,journalRoot,plan),{status:'outcome_unconfirmed_do_not_retry',code:'COMMIT_UNKNOWN',writeAuthorized:false});}finally{owner.query=original;}
   await assert.rejects(syntheticJournaledApply(ctx,journalRoot,plan),hasCode('APPLY_ALREADY_ATTEMPTED'));
   const outcome=JSON.parse(await readFile(join(journalRoot,archiveIdentity.version,'outcome.json'),'utf8'));assert.equal(outcome.state,'unconfirmed');
   const row=(await owner.query('SELECT name,statements FROM supabase_migrations.schema_migrations WHERE version=$1',[archiveIdentity.version])).rows[0];
   assert.equal(row.name,archiveIdentity.name);assert.equal(row.statements.length,1);
   assert.equal(row.statements[0],await readFile(new URL('../../../supabase/migrations/20261101012309_collect_admission_archive.sql',import.meta.url),'utf8'));
   const state=(await owner.query(`SELECT state,reason,uncertain_dispatches::int n FROM private.collect_fence_admissions WHERE admission_id=$1`,[unknown])).rows[0];
   assert.deepEqual(state,{state:'settled',reason:'completed_with_unknown_obligation',n:1});
   assert.deepEqual((await owner.query(accountSql)).rows[0],primaryBefore);
  });
  await t.test('reconciliation refuses a live prior backend and later checks exact history and selected postconditions',async()=>{
   const cp=owner.connectionParameters,replacement=new pg.Client({host:cp.host,port:cp.port,database,user:'postgres',connectionTimeoutMillis:3000});
   replacement.on('error',()=>{});await replacement.connect();
   const rc={mode:'synthetic',client:replacement,database,backendPid:replacement.processID,executed,timeoutMs:60000};
   try{
    await assert.rejects(reconcileArchive(rc,{priorBackendPid:backendPid,expectedAdmissions:captured.preimage.admissions}),hasCode('PRIOR_BACKEND_STILL_PRESENT'));
    assert.deepEqual(await syntheticJournaledReconcile(rc,journalRoot,plan),{status:'unconfirmed',writeAuthorized:false});
    await owner.end();
    const result=await syntheticJournaledReconcile(rc,journalRoot,plan);
    assert.deepEqual(result,{status:'recorded_selected_postconditions_verified',writeAuthorized:false});
   }finally{await replacement.end();}
  });
 });
});

test('preimage preserves distinct PostgreSQL numerics beyond JavaScript safe integers',{timeout:180000},async()=>{
 await withOwnedArchiveFixture(async f=>{
  const {owner,admin,database,backendPid,executed}=f,ctx={mode:'synthetic',client:owner,database,backendPid,executed,timeoutMs:60000};
  await owner.query(`INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id)
   VALUES(true,'rrlduytparvsjfmegalh',$1,$2,1,'fenced',$3)`,[initial,source,randomUUID()]);
  await admin.query('ALTER TABLE private.collect_fence_control ADD COLUMN fixture_large_numeric numeric NOT NULL DEFAULT 9007199254740992');
  const a=await captureArchivePreimage(ctx);assert.match(a.preimage.fence_json,/9007199254740992/);
  await admin.query('ALTER TABLE private.collect_fence_control DISABLE TRIGGER collect_fence_transition');
  try{await admin.query('UPDATE private.collect_fence_control SET fixture_large_numeric=9007199254740993 WHERE singleton');}
  finally{await admin.query('ALTER TABLE private.collect_fence_control ENABLE TRIGGER collect_fence_transition');}
  const b=await captureArchivePreimage(ctx);assert.match(b.preimage.fence_json,/9007199254740993/);assert.notEqual(a.sha256,b.sha256);
 });
});
