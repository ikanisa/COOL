import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { packagePwa, verifyPwaPackage } from '../../scripts/package-pwa.mjs';

const icon = fileURLToPath(new URL('../../public/icons/collect-web-512.png', import.meta.url));

async function fixture(t) {
  const base = await fs.mkdtemp(path.join(os.tmpdir(), 'collect-admin-pwa-'));
  t.after(() => fs.rm(base, { recursive: true, force: true }));
  const input = path.join(base, 'vite');
  const output = path.join(base, 'candidate');
  await fs.mkdir(path.join(input, 'assets'), { recursive: true });
  await fs.mkdir(path.join(input, 'icons'));
  await fs.copyFile(icon, path.join(input, 'icons/collect-web-512.png'));
  await fs.writeFile(path.join(input, 'assets/admin-entry.js'), 'import "./chunk-xyz.js";');
  await fs.writeFile(path.join(input, 'assets/chunk-xyz.js'), 'console.log("synthetic chunk")');
  await fs.writeFile(path.join(input, 'assets/app-def.css'), 'body { color: black; }');
  await fs.writeFile(path.join(input, 'index.html'), `<!doctype html><html><head>
    <title>Collect Admin</title><meta name="description" content="Collect platform operations console.">
    <link rel="icon" href="./icons/collect-web-512.png">
    <link rel="manifest" href="./manifest.json"><link rel="stylesheet" href="./assets/app-def.css">
    <script type="module" src="./assets/admin-entry.js"></script></head><body><div id="root"></div></body></html>`);
  return { base, input, output };
}

test('packages exact versioned assets with a static-only, unqualified worker', async (t) => {
  const { input, output } = await fixture(t);
  const result = await packagePwa(input, output);
  assert.match(result.assetId, /^[a-f0-9]{64}$/);
  assert.equal(result.qualificationComplete, false);
  const html = await fs.readFile(path.join(output, 'index.html'), 'utf8');
  assert.match(html, new RegExp(`/_build/${result.assetId}/assets/admin-entry\\.js`));
  const entry = html.match(/src="([^"]+admin-entry\.js)"/)?.[1];
  const manifestUrl = html.match(/href="([^"]+manifest\.json)"/)?.[1];
  assert.equal(new URL(entry, 'https://admin.example.test/admin/groups/one').pathname, `/_build/${result.assetId}/assets/admin-entry.js`);
  assert.equal(new URL(manifestUrl, 'https://admin.example.test/admin/groups/one').pathname, '/manifest.json');
  const manifest = JSON.parse(await fs.readFile(path.join(output, 'manifest.json'), 'utf8'));
  assert.equal(manifest.name, 'Collect Admin');
  assert.equal(manifest.scope, '.');
  assert.equal(manifest.icons[0].src, `./_build/${result.assetId}/icons/collect-web-512.png`);
  const worker = await fs.readFile(path.join(output, 'custom-sw.js'), 'utf8');
  assert.match(worker, /credentials: 'omit'/);
  assert.match(worker, /crypto\.subtle\.digest\('SHA-256'/);
  assert.doesNotMatch(worker, /\bskipWaiting\s*\(|\bclients\.claim\s*\(/);
  assert.deepEqual(await verifyPwaPackage(output), { cacheEntries: 7 });
  await assert.rejects(packagePwa(input, output), { code: 'EEXIST' });
});

test('rejects a changed packaged asset and reserved API files', async (t) => {
  const { input, output } = await fixture(t);
  const result = await packagePwa(input, output);
  await fs.writeFile(path.join(output, '_build', result.assetId, 'assets/admin-entry.js'), 'changed');
  await assert.rejects(verifyPwaPackage(output), /integrity failed/);
  await fs.mkdir(path.join(input, 'api'));
  await fs.writeFile(path.join(input, 'api/private.json'), '{}');
  await assert.rejects(packagePwa(input, `${output}-other`), /reserved or sensitive/);
});

test('rejects a changed worker, hosting rules, and unbound static files', async (t) => {
  const { input, output } = await fixture(t);
  await packagePwa(input, output);
  const worker = path.join(output, 'custom-sw.js');
  const originalWorker = await fs.readFile(worker);
  await fs.appendFile(worker, '\n// different worker bytes\n');
  await assert.rejects(verifyPwaPackage(output), /audited template/);
  await fs.writeFile(worker, originalWorker);

  const headers = path.join(output, '_headers');
  const originalHeaders = await fs.readFile(headers);
  await fs.writeFile(headers, '/*\n  X-Robots-Tag: index\n');
  await assert.rejects(verifyPwaPackage(output), /hosting rules/);
  await fs.writeFile(headers, originalHeaders);

  await fs.writeFile(path.join(output, 'unexpected.txt'), 'unbound static file');
  await assert.rejects(verifyPwaPackage(output), /cache inventory/);
});

test('rejects an absolute Vite asset base and an unapproved icon', async (t) => {
  const { input, output } = await fixture(t);
  const htmlPath = path.join(input, 'index.html');
  const html = await fs.readFile(htmlPath, 'utf8');
  await fs.writeFile(htmlPath, html.replace('./assets/admin-entry.js', '/assets/admin-entry.js'));
  await assert.rejects(packagePwa(input, output), /relative Vite asset base/);
  await fs.writeFile(htmlPath, html);
  await fs.writeFile(path.join(input, 'icons/collect-web-512.png'), 'not the Collect icon');
  await assert.rejects(packagePwa(input, output), /approved asset/);
});
