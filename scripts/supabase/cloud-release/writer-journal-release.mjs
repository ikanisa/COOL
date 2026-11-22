// SQL-only phase of an authorized managed maintenance window. The deployment
// owner supplies the digest of a reviewed, fenced capture and its evidence dir.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {open,readdir} from 'node:fs/promises';
import {isAbsolute,join} from 'node:path';
import {privateDirectory,readPrivateFile} from '../current-archive/bundle.mjs';
import {canonical,HASH,sha} from '../current-archive/codec.mjs';
import {assertCleanEnvironment} from '../managed-cloud-migrations/operator-core.mjs';
import {connectWithPassword} from './access.mjs';
import {applyEntry,history,lockMigration,profile} from './migrations.mjs';
import {historyDigest,projectRef} from './recorded-history.mjs';
import {requireRevisionSchedulerReady} from './revise-runtime.mjs';
import {readWriterJournalCatalog} from './writer-journal-catalog.mjs';
import {loadWriterJournalCohort} from './writer-journal-plan.mjs';

const format='collect.managed-writer-journal-release.v1';
const digest=value=>sha(canonical(value));

async function control(db) {
  const {rows:[fence]}=await db.query(`SELECT f.project_ref,f.mode,f.epoch::text,f.operation_id::text,f.source_sha256,
    d.profile_sha256,session_user AS session_role,current_user AS current_role,
    current_setting('server_version_num')::int/10000 AS pg_major,private._collect_fence_operator() AS authority
    FROM private.collect_fence_control f JOIN private.collect_deployment_identity d USING(singleton) WHERE f.singleton`);
  assert.ok(fence && fence.project_ref===projectRef && fence.profile_sha256===sha(profile) && fence.pg_major===17
    && fence.authority===true && fence.session_role==='postgres' && fence.current_role==='postgres'
    && /^[1-9][0-9]*$/.test(fence.epoch) && /^[a-f0-9-]{36}$/.test(fence.operation_id) && HASH.test(fence.source_sha256),
  'writer_journal_target_changed');
  const {rows:[{scheduler,outstanding}]}=await db.query(`SELECT private._collect_fence_scheduler_status() AS scheduler,
    (SELECT count(*)::int FROM private.collect_fence_admissions a WHERE a.state<>'settled'
      AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)
      AND NOT private._collect_managed_retirement_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)) AS outstanding`);
  return {fence,scheduler,outstanding};
}

async function capture(db,cohort) {
  const rows=await history(db);
  const ordered_sha256=historyDigest(rows),migration_count=rows.length;
  const receipt={format:'collect.managed-migration-history.v1',project_ref:projectRef,migration_count,ordered_sha256,history:rows};
  const {matching_migrations:completed}=cohort.compareHistory(receipt);
  const state={format,...await control(db),migration_count,ordered_sha256,
    ...await readWriterJournalCatalog(db,completed),cohort_sha256:digest(cohort.plan.migrations),
    next:cohort.plan.migrations[completed]??null};
  return {rows,completed,state};
}

async function snapshot(db,cohort) {
  await db.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
  try { return await capture(db,cohort); }
  finally { await db.query('ROLLBACK'); }
}

async function witnessed(owner,witness,cohort,{locked=false}={}) {
  const a=locked?await capture(owner,cohort):await snapshot(owner,cohort);
  const b=await snapshot(witness,cohort);
  assert.deepEqual(a,b,'writer_journal_witness_changed');
  return a;
}

function requireFenced({fence,scheduler,outstanding}) {
  assert.equal(fence.mode,'fenced','writer_journal_requires_fenced_window');
  assert.equal(outstanding,0,'writer_journal_work_outstanding');
  requireRevisionSchedulerReady(scheduler);
}

async function save(dir,name,metadata) {
  const file=await open(join(dir,name),'wx',0o600);
  try {await file.writeFile(JSON.stringify(metadata)+'\n');await file.sync();}
  finally {await file.close();}
  const directory=await open(dir,'r');
  try {await directory.sync();}
  finally {await directory.close();}
}

async function readIntent(dir,entry,approved) {
  const intent=JSON.parse(await readPrivateFile(join(dir,entry.version+'-intent.json'),16384));
  assert.ok(intent.format===format && intent.version===entry.version && intent.sql_sha256===entry.sha256
    && digest(intent.before)===approved && intent.before.next?.version===entry.version,'writer_journal_intent_mismatch');
  return intent;
}

async function requirePreviousReadback(dir,cohort,{completed,state}) {
  if (completed===0) return;
  const previous=cohort.entries[completed-1];
  const names=(await readdir(dir)).filter(name=>name.startsWith(previous.version+'-outcome-')
    || name.startsWith(previous.version+'-reconcile-'));
  for (const name of names) {
    const receipt=JSON.parse(await readPrivateFile(join(dir,name),16384));
    if (['applied_and_independently_read_back','recorded'].includes(receipt.status) &&
        receipt.version===previous.version && receipt.sql_sha256===previous.sha256 &&
        receipt.state?.format===format && receipt.state.fence.project_ref===projectRef &&
        receipt.state.ordered_sha256===state.ordered_sha256 && receipt.state.role_sha256===state.role_sha256 &&
        receipt.state.retention_sha256===state.retention_sha256 && receipt.state.manifest_catalog_sha256===state.manifest_catalog_sha256
        && receipt.state.cohort_sha256===state.cohort_sha256) return;
  }
  throw Error('writer_journal_previous_independent_readback_required');
}

async function reconcile(owner,witness,cohort,entry,approved,dir) {
  const intent=await readIntent(dir,entry,approved);
  await owner.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  try {
    // The intent is persisted inside these same transaction locks before SQL.
    // Acquiring them proves its preceding transaction has ended, even if the
    // database pool kept the original backend process alive.
    await lockMigration(owner);
    const {state,rows}=await witnessed(owner,witness,cohort,{locked:true});
    requireFenced(state);
    assert.deepEqual(state.fence,intent.before.fence,'writer_journal_fence_changed');
    const recorded=rows.find(row=>row.version===entry.version);
    if (!recorded) assert.equal(digest(state),approved,'writer_journal_preimage_changed');
    const result={status:recorded?'recorded':'not_recorded',version:entry.version,sql_sha256:entry.sha256,state};
    await save(dir,entry.version+'-reconcile-'+randomUUID()+'.json',result);
    return result;
  } finally {await owner.query('ROLLBACK');}
}

async function migrate(owner,witness,cohort,entry,approved,dir,retry) {
  if (retry) {
    const previous=await reconcile(owner,witness,cohort,entry,approved,dir);
    if (previous.status==='recorded') return previous;
  }
  const before=await witnessed(owner,witness,cohort);
  requireFenced(before.state);
  assert.equal(before.state.next?.version,entry.version,'writer_journal_not_next');
  assert.equal(digest(before.state),approved,'writer_journal_preimage_changed');
  const attempt=randomUUID();
  let afterCatalog,attempted=false;
  try {
    await applyEntry(owner,entry,{before:before.rows,
      beforeBody:async db=>{
        const locked=await witnessed(db,witness,cohort,{locked:true});
        assert.deepEqual(locked,before,'writer_journal_locked_preimage_changed');
        await requirePreviousReadback(dir,cohort,locked);
        const intent={format,version:entry.version,sql_sha256:entry.sha256,before:locked.state,attempt};
        await save(dir,retry?entry.version+'-retry-'+attempt+'.json':entry.version+'-intent.json',intent);
        attempted=true;
      },
      afterBody:async db=>{afterCatalog=await readWriterJournalCatalog(db,before.completed+1);},
    });
    const after=await witnessed(owner,witness,cohort);
    assert.equal(after.completed,before.completed+1,'writer_journal_posthistory_changed');
    assert.deepEqual(after.state.fence,before.state.fence,'writer_journal_fence_changed');
    requireFenced(after.state);
    for (const [key,value] of Object.entries(afterCatalog)) {
      assert.equal(after.state[key],value,'writer_journal_catalog_readback_changed');
    }
    const result={status:'applied_and_independently_read_back',version:entry.version,sql_sha256:entry.sha256,state:after.state};
    await save(dir,entry.version+'-outcome-'+attempt+'.json',result);
    return result;
  } catch (error) {
    if (attempted) throw new Error('writer_journal_reconcile_required',{cause:error});
    throw error;
  }
}

export async function runWriterJournal(argv,{openConnection=connectWithPassword}={}) {
  const credentialPath=argv.at(-2)==='--credential-file'?argv.at(-1):null;
  const args=credentialPath?argv.slice(0,-2):argv;
  const [action,version,approved,path]=args;
  const inspect=action==='inspect' && args.length===1;
  assert.ok(inspect || ['apply','reconcile','retry'].includes(action) && args.length===4
    && /^\d{14}$/.test(version) && HASH.test(approved) && isAbsolute(path),
  'usage: apply.mjs --writer-journal {inspect | apply|reconcile|retry VERSION CAPTURE_SHA256 PRIVATE_DIRECTORY} --credential-file ABSOLUTE_PRIVATE_FILE');
  const cohort=await loadWriterJournalCohort();
  const entry=cohort.entries.find(item=>item.version===version);
  assert.ok(inspect || entry,'writer_journal_unknown_version');
  assert.ok(credentialPath && isAbsolute(credentialPath),'writer_journal_private_credential_file_required');
  assertCleanEnvironment(process.env);
  const dir=inspect?null:await privateDirectory(path);
  // The credential is passed only to the existing, project-pinned PostgreSQL
  // connector. The path and credential do not enter a capture or evidence file.
  const bytes=await readPrivateFile(credentialPath,1026);
  let password;
  try {password=new TextDecoder('utf-8',{fatal:true}).decode(bytes).replace(/\r?\n$/,'');}
  finally {bytes.fill(0);}
  assert.ok(password && Buffer.byteLength(password)<=1024 && !/[\r\n\0]/.test(password),'writer_journal_invalid_private_credential');
  const owner=await openConnection(password);
  let witness;
  try {
    witness=await openConnection(password);
    const pid=async db=>(await db.query('SELECT pg_backend_pid() AS pid')).rows[0].pid;
    assert.notEqual(await pid(owner),await pid(witness),'writer_journal_independent_connection_required');
    if (inspect) {
      const {state}=await witnessed(owner,witness,cohort);
      return {status:'observed',state,capture_sha256:digest(state)};
    }
    if (action==='reconcile') return await reconcile(owner,witness,cohort,entry,approved,dir);
    return await migrate(owner,witness,cohort,entry,approved,dir,action==='retry');
  } finally {try {await witness?.end();} finally {await owner.end();}}
}
