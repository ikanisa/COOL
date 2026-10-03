import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {runInNewContext} from 'node:vm';
import {test} from 'node:test';
const source = await readFile(new URL('../qa/public_browser_app_media.mjs', import.meta.url), 'utf8');
const begin = source.indexOf('// BEGIN strict served-resource observer');
const end = source.indexOf('// END strict served-resource observer');
assert(begin > 0 && end > begin, 'Actual recorder observer must be identifiable');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const observe = runInNewContext(source.slice(begin, end) + '\nobserveServedResource', {hash, URL, Error, decodeURIComponent});
const origin = 'http://127.0.0.1:45678';
const bytes = Buffer.from('actual compiled fixture bytes');
const response = (path, body, status = 200) => ({status: () => status, url: () => origin + path, body});
const fixture = () => ({build: {'main.dart.js': hash(bytes), 'index.html': hash(bytes)}, served: {}, errors: [], pending: []});
const record = (f, r) => observe(r, origin, f.build, f.served, f.errors, f.pending, 'home');

test('Successful local response binds exact body bytes and root document path', async () => {
  const f = fixture(); record(f, response('/main.dart.js', async () => bytes)); record(f, response('/', async () => bytes));
  await Promise.all(f.pending); assert.equal(f.errors.length, 0); assert.deepEqual(f.served, f.build);
});
test('Changed or undeclared actual resource fails without certifying its bytes', async () => {
  for (const [path, value] of [['/main.dart.js', Buffer.from('different bytes')], ['/undeclared.js', bytes]]) {
    const f = fixture(); record(f, response(path, async () => value)); await Promise.all(f.pending);
    assert.equal(f.errors.length, 1); assert.match(f.errors[0].message, /Served resource differs/); assert.equal(Object.keys(f.served).length, 0);
  }
});
test('Delayed navigation body rejection is handled before caller drain, retained and fails closed', async () => {
  const f = fixture(); let rejectBody; const body = new Promise((_, reject) => {rejectBody = reject;});
  const unexpected = []; const observer = reason => unexpected.push(reason); process.on('unhandledRejection', observer);
  try {
    record(f, response('/main.dart.js', () => body)); rejectBody(Error('Protocol error (Network.getResponseBody): No data found for resource'));
    await new Promise(resolve => setImmediate(resolve)); await Promise.all(f.pending);
    assert.equal(unexpected.length, 0); assert.equal(f.errors.length, 1); assert.equal(f.errors[0].resource, 'main.dart.js');
    assert.match(f.errors[0].message, /Protocol error/); assert.equal(Object.keys(f.served).length, 0);
  } finally {process.off('unhandledRejection', observer);}
});
test('Synchronous body and invalid response URL errors are recorded without escaping event listener', async () => {
  for (const r of [response('/main.dart.js', () => {throw Error('synchronous read failure');}), {status: () => 200, url: () => 'invalid', body: async () => bytes}]) {
    const f = fixture(); assert.doesNotThrow(() => record(f, r)); await Promise.all(f.pending); assert.equal(f.errors.length, 1);
  }
});
test('Remote and non-200 responses grant no served-byte proof and are not read', async () => {
  const f = fixture(); const noRead = () => {throw Error('body must not be read');};
  record(f, response('/missing.js', noRead, 404)); record(f, {status: () => 200, url: () => 'https://remote.invalid/main.dart.js', body: noRead});
  await Promise.all(f.pending); assert.equal(f.errors.length, 0); assert.equal(Object.keys(f.served).length, 0);
});
