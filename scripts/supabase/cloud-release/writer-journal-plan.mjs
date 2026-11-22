// Offline source plan. The SQL bodies are inputs to the owned fixture.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {SOURCE,body,chain,identity} from './migrations.mjs';
import {migrationBytes} from './retained-source.mjs';
import {historyDigest,projectRef,readRecordedHistory,validateHistoryReceipt} from './recorded-history.mjs';

const capture='cloud-history-20261120-epoch44.json';
const sources=[
  {name:'20261121111000_collect_scoped_writer_grants.sql',sha256:'b3efd73ed854a8d954af3e6c4d449377cfb36d1278de8a80335eea8d050602b4'},
  {name:'20261121111100_burimunsi_journal_subject_links.sql',sha256:'22e46ebe970d793038e904a2070da1562d7ac5e9161bdd76dd17dbd66b020368'},
  {name:'20261121142500_collect_storage_journal_insert_grants.sql',sha256:'4b00ed338ecf807f9a84d19001a9f4eeb68780d4e192ae453efd8f533e12b1c5'},
  {name:'20261121182000_burimunsi_journal_posting_subjects.sql',sha256:'035031f6796e0a39f5b57f3f1a8ab24f3f425303603b586ca306e28aec331b30'},
];

function reconcileHistoricalSelector(selected, history) {
  const recorded=new Map(history.map(row=>[row.version,row]));
  assert.equal(selected.length,71,'historical source selector changed');
  const matched=new Set();
  for (const entry of selected) {
    // The release rendered the local lifecycle precursor for this managed database.
    const lifecycle=entry.file==='20261116163800_collect_storage_lifecycle_retention.sql';
    const version=lifecycle?'20261116163801':entry.version;
    const row=recorded.get(version);
    assert.ok(row && !matched.has(version),'historical source missing or repeated: '+version);
    assert.equal(row.name,lifecycle?'collect_storage_lifecycle_retention_managed_convergence':entry.name);
    if (!lifecycle) assert.equal(row.sha256,entry.sha256,'historical source differs: '+version);
    matched.add(version);
  }
  assert.ok(matched.has('20261116163801'),'managed lifecycle variant missing');
}

export async function loadWriterJournalCohort() {
  const [{record,receiptSha256},selected]=await Promise.all([readRecordedHistory(capture),chain()]);
  reconcileHistoricalSelector(selected,record.history);
  const correction=record.history.find(row=>row.version==='20261117060642');
  assert.equal(correction?.name,'burimunsi_retention_text_subjects','text-subject prerequisite missing');
  assert.equal(correction.sha256,'fae5486220ef7f7aec99887faff6685ef69d3667adee8f1805341af258b171f2');
  const entries=[],steps=[],rows=[...record.history];
  for (const source of sources) {
    const entry=identity(source.name,(await migrationBytes(SOURCE,source)).toString('utf8'));
    assert.ok(entry.version>rows.at(-1).version,'cohort overlaps or reorders managed history');
    assert.notEqual(body(entry.sql),entry.sql,'expected one fenced migration transaction');
    entries.push(entry);
    rows.push({version:entry.version,name:entry.name,sha256:entry.sha256,entries:1});
    steps.push({file:entry.file,version:entry.version,sha256:entry.sha256,
      expected_history:{migration_count:rows.length,ordered_sha256:historyDigest(rows)}});
  }
  const plan={
    format:'collect.managed-writer-journal-plan.v1',status:'offline_source_plan',project_ref:projectRef,
    predecessor:{file:capture,receipt_sha256:receiptSha256,observed_at:record.observed_at,
      migration_count:record.migration_count,ordered_sha256:record.ordered_sha256},
    already_recorded:{row:record.history.indexOf(correction)+1,...correction},
    migrations:steps,
    required_installed_checks:[
      'Verify the managed project, current ordered history and any prior operation receipts before selecting the next migration.',
      'Confirm the operator, compatible runtime, drained work and the fenced control row on the managed database.',
      'Read the effective writer grants, table owners and inherited privileges checked by each grant migration.',
      'Verify the retention rows function owner, SECURITY DEFINER, ACL, search path and body SHA-256 25597e57accb602949e65108db895113ee66e657b5c20e4cc1fbbdabf266973a, and the two blocked journal classes.',
      'Confirm the private journal helper and authorized inventory preimages and the accepted payment/source relationships. Verify the inventory owner can read the configured Storage bucket id and public flag.',
      'Independently read back each committed SQL body, ordered history, effective grants and blocked retention dispositions while fenced.',
      'After authorized reopening, verify normal guarded writes, journal replay and the scheduler through the established service workflow.',
    ],
  };
  return {plan,entries,compareHistory:receipt=>compareHistory(receipt,plan)};
}

// Accept only an exported snapshot of the predecessor or an exact prefix.
// Its match describes the supplied file, independent of current installed state.
function compareHistory(receipt,plan) {
  validateHistoryReceipt(receipt);
  const completed=receipt.migration_count-plan.predecessor.migration_count;
  assert.ok(completed>=0 && completed<=plan.migrations.length,'history is outside this managed cohort');
  const expected=completed===0?plan.predecessor:plan.migrations[completed-1].expected_history;
  assert.equal(receipt.ordered_sha256,expected.ordered_sha256,'history differs from the expected cohort prefix');
  return {scope:'supplied_history_file',matching_migrations:completed,
    remaining_versions:plan.migrations.slice(completed).map(entry=>entry.version)};
}

if (import.meta.main) {
  try {
    const args=process.argv.slice(2);
    assert.ok(args.length===0 || args.length===2 && args[0]==='--verify-history',
      'usage: node scripts/supabase/cloud-release/writer-journal-plan.mjs [--verify-history FILE]');
    const {plan,compareHistory}=await loadWriterJournalCohort();
    if (args.length) plan.supplied_history=compareHistory(JSON.parse(await readFile(args[1],'utf8')));
    console.log(JSON.stringify(plan,null,2));
  } catch (error) {
    console.error(error.message);
    process.exitCode=1;
  }
}
