import test from 'node:test';
import assert from 'node:assert/strict';
// Load the actual handler graph with the existing Node-only, DB-denied resolver.
await import('./helpers/node-postgres-import.mjs');
const {default: worker} = await import('../domain/index.js');

// These tests use the real gateway handler with synthetic storage and SQL
// interfaces. They do not contact a provider or a database.
function fixture(pauseSetting) {
  const credential = {
    id: crypto.randomUUID(), binding_id: crypto.randomUUID(), binding_version: 1,
    owner_user_id: crypto.randomUUID(), receiving_account_id: crypto.randomUUID(),
    originating_session_id: crypto.randomUUID(), binding_created_at: '2026-10-01T00:00:00Z',
    subscription_evidence: '{}', public_code: '250788123456', provider: 'mtn_momo',
    recipient_name: 'Synthetic receiver', currency: 'RWF', timezone: 'Africa/Kigali',
    receiver_hash: 'a'.repeat(64),
  };
  const statements = [], batches = [], stored = [], deferred = [];
  const db = {
    prepare(sql) {
      const statement = {
        sql, values: [],
        bind(...values) { this.values = values; return this; },
        async first() {
          if (sql.includes('FROM momo_gateway_credentials c JOIN momo_gateway_bindings')) return credential;
          if (sql.includes('FROM sms_receipts s JOIN momo_gateway_captures')) return null;
          throw new Error('Unexpected synthetic read: ' + sql);
        },
        async run() { throw new Error('Receipt processing must not run after ingestion.'); },
        async all() { throw new Error('Receipt processing must not read a backlog.'); },
      };
      statements.push(statement);
      return statement;
    },
    async batch(batch) { batches.push(batch); return batch.map(() => ({results: [], meta: {changes: 1}})); },
  };
  const env = {
    DB: db, MOMO_PROCESSING_PAUSED: pauseSetting, ALLOWED_ORIGINS: '',
    DATA_KEY_ID: 'synthetic', DATA_ENCRYPTION_KEY: Buffer.alloc(32, 7).toString('base64'),
    PRIVATE_MEDIA: {async put(...args) { stored.push(args); }},
    AI: {async run() { throw new Error('Provider call is forbidden in this fixture.'); }},
  };
  const ctx = {waitUntil(promise) { deferred.push(Promise.resolve(promise).catch(() => {})); }};
  const body = {
    client_envelope_id: crypto.randomUUID(), raw_sender: 'SYNTHETIC', raw_body: 'synthetic receipt',
    gateway_binding_id: credential.binding_id, gateway_binding_version: credential.binding_version,
    service_centre_at: null, captured_at: '2026-10-30T10:00:00Z', inbox_received_at: null,
    source_mode: 'live', subscription_id: null, complete: true,
  };
  return {env, ctx, body, statements, batches, stored, deferred};
}

test('gateway capture stays held even when the processing pause setting drifts', async () => {
  for (const setting of ['false', 'true', 'TRUE', '', undefined]) {
    const f = fixture(setting);
    const response = await worker.fetch(new Request('https://synthetic.example/v1/momo/gateway/ingest', {
      method: 'POST', headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + 'a'.repeat(64)},
      body: JSON.stringify(f.body),
    }), f.env, f.ctx);
    const body = await response.json();
    assert.equal(response.status, 503, JSON.stringify(body));
    assert.equal(body.code, 'gateway_upload_held');
    assert.equal(body.receipt, undefined);
    assert.equal(f.stored.length, 0);
    assert.equal(f.batches.length, 0);
    assert.equal(f.statements.length, 0);
    assert.equal(f.deferred.length, 0, 'No background receipt processing may be started by a held upload.');
    await Promise.all(f.deferred);
  }
});

test('the shared scheduled entrypoint never starts the unqualified receipt queue', async () => {
  for (const setting of ['true', 'false', 'TRUE', '', undefined]) {
    const f = fixture(setting);
    await worker.scheduled({}, f.env, f.ctx);
    assert.equal(f.deferred.length, 0);
    assert.equal(f.statements.length, 0);
  }
});
