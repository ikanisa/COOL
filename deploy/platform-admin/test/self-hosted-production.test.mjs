import test from 'node:test';
import assert from 'node:assert/strict';
import {access, readFile} from 'node:fs/promises';
import {createAdminWorker} from '../src/index.js';

test('the retired local production deploy entrypoint stays unavailable', async () => {
  const pkg = JSON.parse(await readFile(new URL('../package.json', import.meta.url)));
  assert.equal(pkg.scripts.deploy, undefined);
  assert.ok(Object.values(pkg.scripts).every(command => !command.includes('wrangler.self-hosted.jsonc')));
  await assert.rejects(access(new URL('../wrangler.self-hosted.jsonc', import.meta.url)), {code: 'ENOENT'});
});

test('the managed transport fixture forwards an Admin session only to the nominated Cloud project', async () => {
  // This is a synthetic transport fixture, not an approved production deployment.
  const config = JSON.parse(await readFile(new URL('../wrangler.supabase.jsonc', import.meta.url)));
  assert.equal(config.vars.SUPABASE_URL, 'https://rrlduytparvsjfmegalh.supabase.co');
  let calls = 0;
  const worker = createAdminWorker({fetchImpl: async request => {
    calls++;
    assert.equal(request.url,
      'https://rrlduytparvsjfmegalh.supabase.co/functions/v1/admin-api/api/admin/auth/session');
    assert.equal(request.headers.get('Origin'), 'https://platform-admin.collect.ikanisa.com');
    assert.equal(request.headers.get('Cookie'), '__Host-collect_admin=cloud_fixture');
    return Response.json({user: null});
  }});
  const unexpected = () => { throw Error('Unexpected legacy service or static-asset use'); };
  const response = await worker.fetch(new Request(
    'https://platform-admin.collect.ikanisa.com/api/admin/auth/session',
    {headers: {Cookie: '__Host-collect_admin=cloud_fixture'}},
  ), {...config.vars, ASSETS: {fetch: unexpected}, PLATFORM_API: {fetch: unexpected}});
  assert.equal(response.status, 200);
  assert.equal(calls, 1);
  assert.ok(config.assets.run_worker_first.includes('/api/*'));
});
