#!/usr/bin/env node
// Browser proof of the compiled production Dart storage adapter, using only
// synthetic values and a fresh local browser profile. No application build.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { chromium } = require(process.env.PAYMENT_HELP_PLAYWRIGHT ||
  '/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core');

const compiled = path.resolve(process.argv[2] || '');
const output = path.resolve(process.argv[3] || '');
if (!fs.statSync(compiled).isFile() || !process.argv[3]) {
  throw new Error('Usage: node payment_help_storage_browser.cjs harness.js result.json');
}
const ownerA = '11111111-1111-4111-8111-111111111111';
const ownerB = '22222222-2222-4222-8222-222222222222';
const payload = JSON.stringify({ request: 'synthetic-original-request', reference: 'synthetic-evidence-only' });
const databaseName = 'collect.payment_help.v1';
const checks = [];
const errors = [];
const network = [];
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'payment-help-web-profile-'));
let context;
const server = http.createServer((request, response) => {
  if (request.url === '/harness.js') {
    response.writeHead(200, { 'Content-Type': 'application/javascript' });
    response.end(fs.readFileSync(compiled));
  } else if (request.url === '/') {
    response.writeHead(200, { 'Content-Type': 'text/html' });
    response.end('<!doctype html><meta charset="utf-8"><title>Payment Help storage proof</title><script defer src="harness.js"></script>');
  } else {
    response.writeHead(404); response.end();
  }
});
const call = (page, operation, owner, value = '') => page.evaluate(async ({ operation, owner, value }) =>
  JSON.parse(await window.paymentHelpWebCall(operation, owner, value)), { operation, owner, value });
const ok = (result) => { assert.equal(result.ok, true, JSON.stringify(result)); return result.value; };
const check = (name, detail = {}) => checks.push({ name, passed: true, ...detail });

async function launch() {
  context = await chromium.launchPersistentContext(profile, {
    executablePath: process.env.PAYMENT_HELP_CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
  });
  await context.route('**/*', (route) => {
    if (new URL(route.request().url()).origin === origin) return route.continue();
    network.push(route.request().url()); return route.abort();
  });
  context.on('page', (page) => page.on('pageerror', (error) => errors.push(error.message)));
  const page = await context.newPage();
  await page.goto(origin);
  await page.waitForFunction(() => typeof window.paymentHelpWebCall === 'function');
  return page;
}

async function inspect(page, owner) {
  return page.evaluate(async ({ databaseName, owner }) => {
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`collect.payment_help.v1:${owner}`)));
    const id = Array.from(hash, (b) => b.toString(16).padStart(2, '0')).join('');
    const database = await new Promise((resolve, reject) => {
      const request = indexedDB.open(databaseName, 1);
      request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
    });
    try {
      const record = await new Promise((resolve, reject) => {
        const tx = database.transaction('records', 'readonly');
        let value; tx.objectStore('records').get(id).onsuccess = (event) => { value = event.target.result; };
        tx.oncomplete = () => resolve(value); tx.onabort = () => reject(tx.error);
      });
      if (!record) return { missing: true };
      let exportRejected = false;
      try { await crypto.subtle.exportKey('raw', record.key); } catch (_) { exportRejected = true; }
      return { id, fields: Object.keys(record).sort(), extractable: record.key.extractable,
        algorithm: record.key.algorithm, usages: record.key.usages, exportRejected,
        nonce: Array.from(record.nonce), ciphertext: Array.from(new Uint8Array(record.ciphertext)) };
    } finally { database.close(); }
  }, { databaseName, owner });
}

async function alter(page, kind) {
  return page.evaluate(async ({ databaseName, ownerA, ownerB, kind }) => {
    const hash = async (owner) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',
      new TextEncoder().encode(`collect.payment_help.v1:${owner}`))), (b) => b.toString(16).padStart(2, '0')).join('');
    const a = await hash(ownerA); const b = await hash(ownerB);
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open(databaseName, 1);
      request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
    });
    try {
      await new Promise((resolve, reject) => {
        const tx = db.transaction('records', 'readwrite'); const store = tx.objectStore('records');
        store.get(a).onsuccess = (event) => {
          const record = event.target.result;
          if (kind === 'copy-owner') store.put(record, b);
          else { new Uint8Array(record.ciphertext)[0] ^= 1; store.put(record, a); }
        };
        tx.oncomplete = resolve; tx.onabort = () => reject(tx.error);
      });
    } finally { db.close(); }
  }, { databaseName, ownerA, ownerB, kind });
}

let origin;
(async () => {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
  let page = await launch();
  await page.evaluate(async () => {
    localStorage.setItem('finance-proof-sentinel', 'unchanged');
    sessionStorage.setItem('session-proof-sentinel', 'unchanged');
    document.cookie = 'proof_sentinel=unchanged; SameSite=Strict';
    const db = await new Promise((resolve, reject) => {
      const request = indexedDB.open('collect.finance.proof.sentinel', 1);
      request.onupgradeneeded = () => request.result.createObjectStore('finance');
      request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
    });
    await new Promise((resolve, reject) => {
      const tx = db.transaction('finance', 'readwrite'); tx.objectStore('finance').put('unchanged', 'sentinel');
      tx.oncomplete = resolve; tx.onabort = () => reject(tx.error);
    }); db.close();
  });
  ok(await call(page, 'write', ownerA, payload));
  const initial = await inspect(page, ownerA);
  assert.equal(initial.extractable, false); assert.equal(initial.exportRejected, true);
  assert.deepEqual(initial.algorithm, { name: 'AES-GCM', length: 256 });
  assert.deepEqual(initial.fields, ['ciphertext', 'key', 'nonce', 'version']);
  assert.equal(initial.nonce.length, 12); assert.equal(initial.id.includes(ownerA), false);
  assert.equal(Buffer.from(initial.ciphertext).includes(Buffer.from('synthetic-evidence-only')), false);
  check('ciphertext-only record with nonextractable persistent AES-256 key and hashed owner key');

  await page.reload(); await page.waitForFunction(() => typeof window.paymentHelpWebCall === 'function');
  assert.equal(ok(await call(page, 'read', ownerA)), payload);
  check('committed reload restores original body using structured-cloned key');
  ok(await call(page, 'write', ownerA, payload));
  const rewritten = await inspect(page, ownerA);
  assert.notDeepEqual(rewritten.nonce, initial.nonce); assert.notDeepEqual(rewritten.ciphertext, initial.ciphertext);
  check('fresh 96-bit nonce for each encryption');

  ok(await call(page, 'write', ownerB, 'synthetic-owner-b'));
  ok(await call(page, 'clear', ownerA));
  assert.equal(ok(await call(page, 'read', ownerA)), null);
  assert.equal(ok(await call(page, 'read', ownerB)), 'synthetic-owner-b');
  check('targeted owner clear preserves other owner');
  ok(await call(page, 'write', ownerA, payload));
  await alter(page, 'copy-owner');
  const moved = await call(page, 'read', ownerB);
  assert.equal(moved.ok, false); assert.match(moved.error, /unreadable/);
  check('owner additional authenticated data rejects copied ciphertext');

  await alter(page, 'tamper');
  const corrupt = await inspect(page, ownerA);
  assert.equal((await call(page, 'read', ownerA)).ok, false);
  assert.equal((await call(page, 'write', ownerA, 'replacement-must-not-write')).ok, false);
  assert.deepEqual((await inspect(page, ownerA)).ciphertext, corrupt.ciphertext);
  check('tamper blocks read and overwrite while preserving ciphertext');
  ok(await call(page, 'clear', ownerA)); ok(await call(page, 'clear', ownerB));

  const second = await context.newPage(); await second.goto(origin);
  await second.waitForFunction(() => typeof window.paymentHelpWebCall === 'function');
  const crossTab = await Promise.all([call(page, 'claim', ownerA, 'tab-a-immutable-body'), call(second, 'claim', ownerA, 'tab-b-immutable-body')]);
  assert.equal(ok(crossTab[0]), ok(crossTab[1]));
  assert.equal(ok(await call(second, 'read', ownerA)), crossTab[0].value);
  check('cross-tab lock covers complete read claim committed write', { winners: 1 });
  ok(await call(page, 'clear', ownerA));
  const sameTab = await Promise.all([call(page, 'claim', ownerA, 'same-tab-a'), call(page, 'claim', ownerA, 'same-tab-b')]);
  assert.equal(ok(sameTab[0]), ok(sameTab[1]));
  check('independent same-instance calls cannot bypass async lock zone');

  const beforeAbort = ok(await call(page, 'read', ownerA));
  await page.evaluate(() => {
    window.originalProofPut = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function (...args) {
      const request = window.originalProofPut.apply(this, args);
      if (this.name === 'records') request.addEventListener('success', () => request.transaction.abort(), { once: true });
      return request;
    };
  });
  const aborted = await call(page, 'write', ownerA, 'aborted-write-must-not-acknowledge');
  assert.equal(aborted.ok, false); assert.match(aborted.error, /did not commit/);
  await page.evaluate(() => { IDBObjectStore.prototype.put = window.originalProofPut; delete window.originalProofPut; });
  assert.equal(ok(await call(page, 'read', ownerA)), beforeAbort);
  check('request success followed by transaction abort is failure and preserves previous record');

  const oversized = await call(page, 'write', ownerA, 'x'.repeat(1024 * 1024 + 1));
  assert.equal(oversized.ok, false); assert.match(oversized.error, /limit/);
  assert.equal(ok(await call(page, 'read', ownerA)), beforeAbort);
  check('oversized input does not replace recovery');
  const ambient = await page.evaluate(async () => {
    const db = await new Promise((resolve) => { const r = indexedDB.open('collect.finance.proof.sentinel', 1); r.onsuccess = () => resolve(r.result); });
    const finance = await new Promise((resolve) => { const tx = db.transaction('finance'); const r = tx.objectStore('finance').get('sentinel'); let v; r.onsuccess = () => { v = r.result; }; tx.oncomplete = () => resolve(v); }); db.close();
    return { local: { ...localStorage }, session: { ...sessionStorage }, cookie: document.cookie, finance };
  });
  assert.deepEqual(ambient.local, { 'finance-proof-sentinel': 'unchanged' });
  assert.deepEqual(ambient.session, { 'session-proof-sentinel': 'unchanged' });
  assert.equal(ambient.cookie, 'proof_sentinel=unchanged'); assert.equal(ambient.finance, 'unchanged');
  check('no local session cookie or finance namespace mutation');

  await context.close(); context = null;
  page = await launch();
  assert.equal(ok(await call(page, 'read', ownerA)), beforeAbort);
  check('browser process restart restores committed request and nonextractable key');

  await page.evaluate(() => Object.defineProperty(navigator, 'locks', { configurable: true, value: undefined }));
  const noLocks = await call(page, 'write', ownerA, 'must-not-write-without-lock');
  assert.equal(noLocks.ok, false); assert.match(noLocks.error, /unavailable/);
  await page.reload(); await page.waitForFunction(() => typeof window.paymentHelpWebCall === 'function');
  assert.equal(ok(await call(page, 'read', ownerA)), beforeAbort);
  check('missing cross-tab lock blocks operation without plaintext fallback');
  for (const capability of ['indexedDB', 'subtle']) {
    await page.evaluate((capability) => {
      if (capability === 'indexedDB') Object.defineProperty(window, 'indexedDB', { configurable: true, value: undefined });
      else Object.defineProperty(crypto, 'subtle', { configurable: true, value: undefined });
    }, capability);
    const unavailable = await call(page, 'read', ownerA);
    assert.equal(unavailable.ok, false); assert.match(unavailable.error, /unavailable/);
    await page.reload(); await page.waitForFunction(() => typeof window.paymentHelpWebCall === 'function');
    assert.equal(ok(await call(page, 'read', ownerA)), beforeAbort);
    check(`missing ${capability} fails closed and preserves recovery`);
  }
  await page.evaluate(() => {
    window.originalProofPut = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function () { throw new DOMException('Synthetic storage failure', 'QuotaExceededError'); };
  });
  assert.equal((await call(page, 'write', ownerA, 'quota-failure-must-not-write')).ok, false);
  await page.evaluate(() => { IDBObjectStore.prototype.put = window.originalProofPut; delete window.originalProofPut; });
  assert.equal(ok(await call(page, 'read', ownerA)), beforeAbort);
  check('synchronous storage failure aborts transaction without unhandled error or replacement');
  assert.deepEqual(network, []); assert.deepEqual(errors, []);
  const report = { outcome: 'passed', checks, browser: await context.browser().version(),
    compiled_sha256: crypto.createHash('sha256').update(fs.readFileSync(compiled)).digest('hex'),
    source_sha256: Object.fromEntries([
      'lib/shared/repositories/payment_help_storage_web.dart',
      'lib/shared/repositories/payment_help_storage_contract.dart',
      'test/browser/payment_help_storage_harness.dart',
      'scripts/qa/payment_help_storage_browser.cjs',
    ].map((name) => [name, crypto.createHash('sha256').update(fs.readFileSync(path.resolve(__dirname, '../..', name))).digest('hex')])),
    external_requests: network, page_errors: errors, local_only: true };
  fs.writeFileSync(output, `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify({ outcome: report.outcome, checks: checks.length, output }));
})().catch((error) => {
  fs.writeFileSync(output, `${JSON.stringify({ outcome: 'failed', checks, error: error.stack, external_requests: network, page_errors: errors }, null, 2)}\n`);
  console.error(error.stack); process.exitCode = 1;
}).finally(async () => {
  if (context) await context.close();
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(profile, { recursive: true, force: true });
});
