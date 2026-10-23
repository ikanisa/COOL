import test from 'node:test';
import assert from 'node:assert/strict';
import { adminHealthComponent, recordAdminHealth } from '../src/observability.mjs';

test('health events have a closed schema without contact, credential, SMS, URL or provider context', () => {
  const rows = [], emit = value => rows.push(JSON.parse(value));
  recordAdminHealth('unexpected_failure', 'sms', emit);
  assert.deepEqual(rows, [{ service: 'collect_admin', schema_version: 1, event: 'unexpected_failure', component: 'sms' }]);
  for (const privateValue of ['+250788123456', 'owner@example.com', 'https://example.com/setup?token=secret', 'raw SMS body', 'provider-secret']) {
    recordAdminHealth(privateValue, 'sms', emit);
    recordAdminHealth('unexpected_failure', privateValue, emit);
  }
  assert.equal(rows.length, 1);
});
test('health routing emits only a module label, never record IDs or query values', () => {
  assert.equal(adminHealthComponent('/api/admin/auth/setup?token=secret'), 'auth');
  assert.equal(adminHealthComponent('/api/admin/sms/receipts/member/private-id/content'), 'sms');
  assert.equal(adminHealthComponent('/api/gateway/receiver-receipts'), 'gateway');
  assert.equal(adminHealthComponent('/api/admin/reconciliations/private-id'), 'reconciliation');
});
