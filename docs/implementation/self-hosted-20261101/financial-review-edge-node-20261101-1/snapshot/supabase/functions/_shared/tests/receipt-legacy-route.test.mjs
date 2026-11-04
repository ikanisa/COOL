import {test} from 'node:test';
import assert from 'node:assert/strict';

await import('./helpers/node-postgres-import.mjs');
const {receiptRoute} = await import('../domain/receipts.js');

test('legacy bearer receipt route never reads plaintext, even with its former grant', async () => {
  const inaccessible = new Proxy({}, {get() { throw Error('unexpected data access'); }});
  const url = 'https://collect.example/v1/receipts/12345678-1234-4234-8234-123456789abc';
  for (const permissions of [new Set(), new Set(['sms.raw.reveal'])]) {
    for (const reason of [undefined, 'Inspect retained original source']) {
      const request = new Request(url, {headers: reason ? {'X-Collect-Review-Reason': reason} : {}});
      await assert.rejects(
        () => receiptRoute(request, inaccessible, {permissions}),
        error => error.status === 410 && error.code === 'receipt_access_retired',
      );
    }
  }
});

test('receipt route does not intercept unrelated paths or methods', async () => {
  const base = 'https://collect.example/v1/receipts/12345678-1234-4234-8234-123456789abc';
  assert.equal(await receiptRoute(new Request(base, {method: 'POST'}), {}, {}), null);
  assert.equal(await receiptRoute(new Request('https://collect.example/v1/receipts'), {}, {}), null);
});
