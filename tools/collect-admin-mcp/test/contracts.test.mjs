import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { coreSorts, coreStatuses } from '../../../supabase/functions/_shared/domain/admin_search.js';
import { marker, permission } from '../../../supabase/functions/_shared/domain/admin_records.js';
import { PUBLIC_CONFIG } from '../../../deploy/platform-supabase-free/public-config.mjs';
import { READ_CONTRACT, canonicalRequestId } from '../src/tools.mjs';
import { ADMIN_ORIGIN } from '../src/config.mjs';

test('MCP search, status and ordering allowlists match the current canonical Supabase read contract', () => {
  assert.deepEqual([...READ_CONTRACT.areas].sort(), Object.keys(coreSorts).sort());
  assert.deepEqual([...READ_CONTRACT.areas].sort(), Object.keys(permission).sort());
  assert.deepEqual(marker, { contract_version: 2, model: 'canonical_evidence_ledger' });
  for (const area of READ_CONTRACT.areas) {
    assert.deepEqual(READ_CONTRACT.sorts[area], Object.keys(coreSorts[area]));
    assert.deepEqual(READ_CONTRACT.statuses[area], coreStatuses[area]);
    assert.equal(READ_CONTRACT.permissions[area], `${permission[area]}.read`);
  }
});

test('MCP request identity retains its independent vector and the current Supabase bridge namespace', async () => {
  const source = await readFile(new URL('../../../supabase/functions/_shared/domain/admin_bridge.js', import.meta.url), 'utf8');
  assert.match(source, /collect-admin:\$\{account\.principal_id\}:\$\{key\}/);
  const result = canonicalRequestId('33333333-3333-4333-8333-333333333333', 'review-original-1234');
  assert.equal(result, 'dc06158e-d29e-47a3-800c-06355d0b842c');
  assert.notEqual(result, canonicalRequestId('11111111-1111-4111-8111-111111111111', 'review-original-1234'));
  assert.notEqual(result, canonicalRequestId('33333333-3333-4333-8333-333333333333', 'review-original-1235'));
});

test('MCP origin equals the current Supabase public host fixed Admin origin', () => {
  assert.equal(ADMIN_ORIGIN, 'https://platform-admin.collect.ikanisa.com');
  assert.equal(PUBLIC_CONFIG.backend, 'supabase');
  assert.equal(PUBLIC_CONFIG.frontendOrigin, ADMIN_ORIGIN);
});
