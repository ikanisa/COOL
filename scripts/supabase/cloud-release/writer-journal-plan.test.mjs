import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {historyDigest,readRecordedHistory} from './recorded-history.mjs';
import {loadWriterJournalCohort} from './writer-journal-plan.mjs';

const file='cloud-history-20261120-epoch44.json';
const checkpoints=[
  [90,'08c5f41cfaa401ba23d4840c1607fc31d37031f408076b6533fd112cd8b3a812'],
  [91,'de570e4a3082918e86f9428b682554c80f4ef0142dc9350b31b68f0b372e7357'],
  [92,'99a0bf87620c448ef2f1f2ecab3d2df699c95fd34fbaedbb5aaead1ba56db3f8'],
  [93,'0baa8365b91ebf8c796eeb126eb8bdcbf2669c943dff4dc58019bae5fffe2c35'],
];
const snapshot=(record,history)=>({...record,history,migration_count:history.length,ordered_sha256:historyDigest(history)});

test('the four source migrations extend the exact receipt and every intermediate checksum matches',async()=>{
  const {plan,entries,compareHistory}=await loadWriterJournalCohort(),{record}=await readRecordedHistory(file);
  assert.equal(plan.predecessor.migration_count,89);
  assert.equal(plan.already_recorded.row,68);
  assert.equal(plan.already_recorded.version,'20261117060642');
  assert.deepEqual(entries.map(entry=>entry.version),['20261121111000','20261121111100','20261121142500','20261121182000']);
  assert.deepEqual(plan.migrations.map(({expected_history:h})=>[h.migration_count,h.ordered_sha256]),checkpoints);
  const history=[...record.history];
  for(let i=0;i<=entries.length;i++) {
    assert.deepEqual(compareHistory(snapshot(record,history)),{
      scope:'supplied_history_file',matching_migrations:i,remaining_versions:entries.slice(i).map(entry=>entry.version),
    });
    if (i<entries.length) {
      const {version,name,sha256}=entries[i];
      history.push({version,name,sha256,entries:1});
    }
  }
});

test('external records must be from the same project and match an exact ordered prefix',async()=>{
  const {entries,compareHistory:verify}=await loadWriterJournalCohort(),{record}=await readRecordedHistory(file);
  const additions=entries.map(({version,name,sha256})=>({version,name,sha256,entries:1}));
  const [first,second]=additions;
  assert.throws(()=>verify({...record,project_ref:'different-project'}),/project changed/);
  assert.throws(()=>verify({...record,ordered_sha256:'f'.repeat(64)}),/digest changed/);
  assert.throws(()=>verify(snapshot(record,record.history.slice(0,-1))),/outside this managed cohort/);
  const changedPrerequisite=record.history.map(row=>row.version==='20261117060642'?{...row,sha256:'0'.repeat(64)}:row);
  assert.throws(()=>verify(snapshot(record,changedPrerequisite)),/expected cohort prefix/);
  assert.throws(()=>verify(snapshot(record,[...record.history,second])),/expected cohort prefix/);
  assert.throws(()=>verify(snapshot(record,[...record.history,{...first,sha256:'f'.repeat(64)}])),/expected cohort prefix/);
  assert.throws(()=>verify(snapshot(record,[...record.history,{...first,entries:2}])),/one statement body/);
  assert.throws(()=>verify(snapshot(record,[...record.history,first,first])),/duplicate or unordered/);
  assert.throws(()=>verify(snapshot(record,[...record.history,...additions,{...first,version:'20261121183000'}])),/outside this managed cohort/);
});

test('the offline command accepts a captured history file and rejects execution arguments',()=>{
  const cli=fileURLToPath(new URL('./writer-journal-plan.mjs',import.meta.url));
  const path=fileURLToPath(new URL('../../../supabase/managed-migration-history/'+file,import.meta.url));
  const command=args=>execFileSync(process.execPath,[cli,...args],{encoding:'utf8',env:{},stdio:'pipe'});
  const plan=JSON.parse(command(['--verify-history',path]));
  assert.equal(plan.status,'offline_source_plan');
  assert.equal(plan.supplied_history.matching_migrations,0);
  assert.ok(plan.migrations.every(step=>!Object.hasOwn(step,'sql')));
  assert.throws(()=>command(['--apply']),error=>error.status===1 && error.stderr.includes('usage:'));
});

test('managed apply dispatch admits only an explicit reviewed writer-journal command', async()=>{
  const {runCloudRelease}=await import('./apply.mjs');
  const openConnection=async()=>assert.fail('invalid requests must refuse before connecting');
  const knownVersion='20261121111000',fingerprint='a'.repeat(64);
  for (const args of [
    [],['--schema','extra'],['--writer-journal'],['--writer-journal','inspect'],['--writer-journal','inspect','extra'],
    ['--writer-journal','apply',knownVersion,fingerprint],
    ['--writer-journal','retry',knownVersion,'unapproved','/tmp'],
    ['--writer-journal','apply','19990101000000',fingerprint,'/tmp'],
  ]) await assert.rejects(runCloudRelease(args,{openConnection}),/explicit_phase_required|usage:|unknown_version|private_credential_file_required/);
});
