import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const checkout = new URL('../../../', import.meta.url);
const historyDirectory = new URL('supabase/managed-migration-history/', checkout);
const managedVariants = new Map([
  ['20261114110001', 'scripts/supabase/retention-convergence/managed-branch-1100-candidate.sql'],
  ['20261116163801', 'supabase/managed-migration-history/retained/20261116163801_collect_storage_lifecycle_retention_managed_convergence.sql'],
]);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

async function verifyHistory(filename, expectedCount, expectedDigest) {
  const record = JSON.parse(await readFile(new URL(filename, historyDirectory), 'utf8'));
  assert.equal(record.project_ref, 'rrlduytparvsjfmegalh');
  assert.equal(record.format, 'collect.managed-migration-history.v1');
  assert.equal(record.migration_count, expectedCount);
  assert.equal(record.history.length, record.migration_count);
  let previous = '';
  const ordered = [];
  for (const entry of record.history) {
    assert.match(entry.version, /^\d{14}$/);
    assert.match(entry.name, /^[a-z0-9_]+$/);
    assert.equal(entry.entries, 1, entry.version);
    assert.ok(entry.version > previous, `duplicate or unordered version ${entry.version}`);
    const path = managedVariants.get(entry.version) ?? `supabase/migrations/${entry.version}_${entry.name}.sql`;
    const digest = hash(await readFile(new URL(path, checkout)));
    assert.equal(digest, entry.sha256, path);
    ordered.push(`${entry.version}:${entry.name}:${digest}`);
    previous = entry.version;
  }
  // Independently aggregated inside the managed database, using version COLLATE "C".
  assert.equal(hash(ordered.join('\n')), record.ordered_sha256);
  assert.equal(record.ordered_sha256, expectedDigest);
  return record;
}

test('both managed checkpoints match their exact migration bodies and the successor preserves the original prefix', async () => {
  const initial = await verifyHistory('cloud-history-20261120.json', 82,
    '02304f771accf67aa95a4e960dcc247644f06c266fb68a05db948fa01034b303');
  const successor = await verifyHistory('cloud-history-20261120-epoch44.json', 89,
    '6ff5c9035113c0c17085eadbccf0c9dfc1c8cf928fbeb76f1e229ca11844f11f');
  assert.deepEqual(successor.history.slice(0, initial.history.length), initial.history);
  assert.deepEqual(successor.previous_capture, {
    file: 'cloud-history-20261120.json', migration_count: initial.migration_count,
    ordered_sha256: initial.ordered_sha256,
  });
  assert.deepEqual(successor.catalog.verified_forward_migrations,
    successor.history.slice(initial.history.length).map(entry => entry.version));
});
