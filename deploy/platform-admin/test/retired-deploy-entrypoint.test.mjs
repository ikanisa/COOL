import test from 'node:test';
import assert from 'node:assert/strict';
import {access, readFile} from 'node:fs/promises';

test('the retired local production deploy entrypoint stays unavailable', async () => {
  const pkg = JSON.parse(await readFile(new URL('../package.json', import.meta.url)));
  assert.equal(pkg.scripts.deploy, undefined);
  assert.ok(Object.values(pkg.scripts).every(command => !command.includes('wrangler.self-hosted.jsonc')));
  await assert.rejects(access(new URL('../wrangler.self-hosted.jsonc', import.meta.url)), {code: 'ENOENT'});
});
