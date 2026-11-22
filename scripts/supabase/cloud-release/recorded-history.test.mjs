import assert from 'node:assert/strict';
import test from 'node:test';
import {readRecordedHistory} from './recorded-history.mjs';

test('both managed checkpoints match their exact migration bodies and the successor preserves the original prefix', async () => {
  const {record:initial} = await readRecordedHistory('cloud-history-20261120.json');
  const {record:successor} = await readRecordedHistory('cloud-history-20261120-epoch44.json');
  assert.deepEqual(successor.history.slice(0, initial.history.length), initial.history);
  assert.deepEqual(successor.previous_capture, {
    file: 'cloud-history-20261120.json', migration_count: initial.migration_count,
    ordered_sha256: initial.ordered_sha256,
  });
  assert.deepEqual(successor.catalog.verified_forward_migrations,
    successor.history.slice(initial.history.length).map(entry => entry.version));
});
