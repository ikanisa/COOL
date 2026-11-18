import assert from 'node:assert/strict';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { openApplicationWork } from '../../application-fence.js';
import { createOpenSmsReceiptTransport } from '../../opensms-receipts.js';
import { drainBuriMunsiPaymentSms } from '../../domain/burimunsi/payment-sms-delivery.mjs';
import { renderPaymentSms } from '../../domain/burimunsi/payment-sms-template.mjs';

const sha = x => createHash('sha256').update(x).digest('hex');
const group = '11111111-1111-4111-8111-111111111111';
const scope = 'app_synthetic';
const project = 'https://rrlduytparvsjfmegalh.supabase.co';
const source = 'a'.repeat(64);
const to = '+250780000000';
const point = '2026-11-18T22:05:00.000Z';
const reference = 'FIXTURE-01';
const text = 'BuriMunsi: Ubwizigame bwa 1,250 RWF bwanditswe. Igiteranyo cyawe cyanditswe muri iri tsinda ku 2026-11-19 00:05 CAT: 28,750 RWF. Ref: FIXTURE-01.';
const row = {
  phase: 'send', collection_id: group, application_id: scope,
  attempt_id: '22222222-2222-4222-8222-222222222222', claim_token: '33333333-3333-4333-8333-333333333333',
  message_id: scope + ':payment:entry-1', idempotency_key: 'payment:entry-1', destination: to, destination_sha256: sha(to),
  posted_at: point, posted_reference: reference, amount_rwf: 1250, member_balance_rwf: 28750,
  not_after: '2026-11-19T00:05:00.000Z',
};
const available = {
  BURIMUNSI_PAYMENT_SMS_ENABLED: 'true', BURIMUNSI_PAYMENT_SMS_COLLECTION_ID: group,
  BURIMUNSI_PAYMENT_SMS_ENABLED_AT: '2026-11-18T12:00:00.000Z',
  COLLECT_RECEIPT_SMS_ENABLED: 'true', COLLECT_RECEIPT_SMS_APPROVAL_SHA256: 'b'.repeat(64),
  OPENSMS_RECEIPT_APPLICATION_ID: scope, OPENSMS_RECEIPT_APPLICATION_TOKEN: 'synthetic_key'.repeat(3),
  OPENSMS_RECEIPT_BASE_URL: project + '/functions/v1/collect-sms', SUPABASE_URL: project, APP_ENVIRONMENT: 'production',
  COLLECT_SMS_ENABLED: 'true', COLLECT_SMS_DISPATCH_PAUSED: 'false', COLLECT_SMS_CORE_SOURCE_SHA256: source, BUILD_SOURCE_ID: source,
};

async function run({ job = row, allow = true, lost = false, config = {} } = {}) {
  let admission;
  const backend = {
    async register(id, sourceSha256, kind) {
      admission = { contractVersion: 1, admissionId: id, epoch: 1, sourceSha256, kind, state: 'active', mode: 'open' };
      return admission;
    },
    async lease() { return { row: admission, assert: async () => admission, release: async () => {} }; },
    async status() { return {...admission, found: admission !== undefined}; },
    async close(id, epoch, sourceSha256, state, reason, externalDispatches, uncertainDispatches) {
      return { ...admission, state, reason, externalDispatches, uncertainDispatches };
    },
  };
  const work = await openApplicationWork({ backend, sourceSha256: source, kind: 'jobs' });
  const operations = [];
  const database = {
    applicationWork: work, async context() {},
    async transaction(f) {
      return f({ async unsafe(sql, args) {
        const op = /private\.burimunsi_(\w+)_payment_sms/.exec(sql)?.[1];
        operations.push([op, args]);
        return [{ result: op === 'claim' ? (job ? [job] : []) : op === 'prepare' ? allow : true }];
      } });
    },
  };
  const outcome = { providerAccepted: true, state: 'delivered', evidenceSha256: 'c'.repeat(64) };
  const makeTransport = () => ({
    async submit(message) {
      operations.push(['post', message]);
      if (lost) throw Error('synthetic missed reply');
      return outcome;
    },
    async inspectRecorded(message) { operations.push(['get', message]); return outcome; },
  });
  try {
    const result = await drainBuriMunsiPaymentSms(
      { ...available, ...config, DB: database, COLLECT_FENCE_WORK: work }, { makeTransport },
    );
    return { result, operations };
  } finally {
    await work.finish();
  }
}

test('renders the retained Kinyarwanda v2 wording and Kigali midnight with the original member balance', () => {
  assert.equal(renderPaymentSms({ amount: 1250, memberBalance: 28750, recordedAt: point, reference }), text);
  assert.throws(() => renderPaymentSms({ amount: 1250, memberBalance: 28750, recordedAt: point, reference: 'bad ref' }));
});

test('reserves and arms the exact receipt before the one POST', async () => {
  const { result, operations } = await run();
  assert.deepEqual(operations.map(([k]) => k), ['claim', 'prepare', 'post', 'finish']);
  assert.deepEqual(operations[0][1], [group, available.BURIMUNSI_PAYMENT_SMS_ENABLED_AT, scope, 1]);
  assert.equal(operations[1][1][3], sha(text));
  assert.deepEqual(operations[2][1], { messageId: row.message_id, to, notAfter: row.not_after, text });
  assert.deepEqual(operations[3][1].slice(3), ['accepted', 'delivered', 'c'.repeat(64)]);
  assert.equal(result.processed, 1);
});

test('changed recipient, a refused prepare or missing eligible work can never POST', async () => {
  const changed = await run({ job: { ...row, destination_sha256: '0'.repeat(64) } });
  assert.deepEqual(changed.operations.map(([op]) => op), ['claim', 'finish']);
  assert.equal(changed.result.outcome, 'suppressed');
  const declined = await run({ allow: false });
  assert.deepEqual(declined.operations.map(([op]) => op), ['claim', 'prepare']);
  assert.equal(declined.result.outcome, 'suppressed');
  assert.deepEqual((await run({ job: null })).result, { status: 'complete', processed: 0 });
});

test('lost submission acknowledgement is recorded and the original ID is read with no destination', async () => {
  const missed = await run({ lost: true });
  assert.equal(missed.result.outcome, 'unknown');
  const original = await run({ job: { ...row, phase: 'inspect', destination: null, body_sha256: sha(text) } });
  assert.deepEqual(original.operations.map(([op]) => op), ['claim', 'get', 'finish']);
  assert.deepEqual(original.operations[1][1], {
    messageId: row.message_id, text, notAfter: row.not_after, destinationSha256: sha(to),
  });
});

test('recovers the exact wire receipt by commitment and rejects the wrong phone using only GET', async () => {
  const available_at = '2026-11-18T23:05:00.000Z';
  const values = [row.message_id, scope, 'receipt', to, text, '80', row.not_after, available_at, ''];
  const payload_digest = sha('collect-sms-payload-v1\n' + values.map(v => Buffer.byteLength(v) + ':' + v).join(''));
  let reads = 0;
  const transport = createOpenSmsReceiptTransport({
    origin: available.OPENSMS_RECEIPT_BASE_URL, applicationId: scope, token: available.OPENSMS_RECEIPT_APPLICATION_TOKEN,
  }, { fetchImpl: async (url, options) => {
    assert.equal(options.method, 'GET');
    assert.equal(url, available.OPENSMS_RECEIPT_BASE_URL + '/v1/messages/' + encodeURIComponent(row.message_id));
    reads++;
    return Response.json({ message: {
      message_id: row.message_id, application_id: scope, kind: 'receipt', to, text, priority: 80,
      not_after: row.not_after, available_at, payload_digest, state: 'delivered', campaign_id: null, content_redacted_at: null,
    } });
  } });
  const stored = { messageId: row.message_id, text, notAfter: row.not_after, destinationSha256: sha(to) };
  assert.equal((await transport.inspectRecorded(stored)).state, 'delivered');
  await assert.rejects(transport.inspectRecorded({ ...stored, destinationSha256: '0'.repeat(64) }), /opensms_receipt_unconfirmed/);
  assert.equal(reads, 2);
});

test('default-off and rejects a drifted gateway target or pause before any work', async () => {
  const result = await run({ config: { BURIMUNSI_PAYMENT_SMS_ENABLED: 'false' } });
  assert.deepEqual(result, { result: { status: 'disabled', processed: 0 }, operations: [] });
  for (const config of [{ OPENSMS_RECEIPT_BASE_URL: 'https://fixture.example' }, { COLLECT_SMS_DISPATCH_PAUSED: 'true' },
    { COLLECT_SMS_CORE_SOURCE_SHA256: 'd'.repeat(64) }]) {
    await assert.rejects(run({ config }), /burimunsi_payment_sms_unconfirmed/);
  }
});
