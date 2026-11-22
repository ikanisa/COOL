import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {hash} from './migrations.mjs';

const checkout=new URL('../../../',import.meta.url);
export const projectRef='rrlduytparvsjfmegalh';
const variants=new Map([
  ['20261114110001','scripts/supabase/retention-convergence/managed-branch-1100-candidate.sql'],
  ['20261116163801','supabase/managed-migration-history/retained/20261116163801_collect_storage_lifecycle_retention_managed_convergence.sql'],
]);
const captures=new Map([
  ['cloud-history-20261120.json',[82,'02304f771accf67aa95a4e960dcc247644f06c266fb68a05db948fa01034b303','016f380fa575dc1f648c3a5733b6fe10125e393c88f570a9039eec1928ac2e4f']],
  ['cloud-history-20261120-epoch44.json',[89,'6ff5c9035113c0c17085eadbccf0c9dfc1c8cf928fbeb76f1e229ca11844f11f','32b54a36d3469d735c8b4b20016591813b66242e6dcdb9db981b4c46bd7fe7d5']],
]);

// Matches the database history aggregate ordered by version COLLATE "C".
export function historyDigest(rows) {
  return hash(rows.map(row=>[row.version,row.name,row.sha256].join(':')).join('\n'));
}

export function validateHistoryReceipt(record) {
  assert.equal(record?.format,'collect.managed-migration-history.v1','managed history format changed');
  assert.equal(record.project_ref,projectRef,'managed history project changed');
  assert.ok(Array.isArray(record.history) && record.history.length>0,'managed history rows missing');
  assert.equal(record.migration_count,record.history.length,'managed history count changed');
  let previous='';
  for (const entry of record.history) {
    assert.match(entry.version,/^\d{14}$/,'invalid migration version');
    assert.match(entry.name,/^[a-z0-9_]+$/,'invalid migration name');
    assert.match(entry.sha256,/^[a-f0-9]{64}$/,'invalid migration digest');
    assert.equal(entry.entries,1,'expected one statement body for '+entry.version);
    assert.ok(entry.version>previous,'duplicate or unordered migration '+entry.version);
    previous=entry.version;
  }
  assert.equal(historyDigest(record.history),record.ordered_sha256,'managed history digest changed');
}

export async function readRecordedHistory(filename) {
  const capture=captures.get(filename);
  assert.ok(capture,'unrecognized recorded history');
  const [count,digest,receiptHash]=capture;
  const bytes=await readFile(new URL('supabase/managed-migration-history/'+filename,checkout));
  assert.equal(hash(bytes),receiptHash,'retained managed receipt changed: '+filename);
  const record=JSON.parse(bytes);
  validateHistoryReceipt(record);
  assert.equal(record.migration_count,count);
  assert.equal(record.ordered_sha256,digest);
  for (const entry of record.history) await readRecordedSql(entry);
  return {record,receiptSha256:receiptHash};
}

export async function readRecordedSql(entry) {
  const path=variants.get(entry.version) ?? `supabase/migrations/${entry.version}_${entry.name}.sql`;
  const bytes=await readFile(new URL(path,checkout));
  assert.equal(hash(bytes),entry.sha256,'recorded migration source changed: '+path);
  return bytes.toString('utf8');
}
