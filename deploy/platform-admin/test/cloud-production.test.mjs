import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createAdminWorker} from '../src/index.js';

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
    {headers: {Cookie: '__Host-collect_admin=old_fixture; __Host-collect_admin_rrlduytparvsjfmegalh=cloud_fixture'}},
  ), {...config.vars, ASSETS: {fetch: unexpected}, PLATFORM_API: {fetch: unexpected}});
  assert.equal(response.status, 200);
  assert.equal(calls, 1);
  assert.ok(config.assets.run_worker_first.includes('/api/*'));
});

test('guest and logout responses on managed production preserve the prior issuer cookie', async () => {
  const {vars} = JSON.parse(await readFile(new URL('../wrangler.supabase.jsonc', import.meta.url)));
  let calls = 0;
  const worker = createAdminWorker({fetchImpl: async request => {
    calls++;
    assert.equal(request.headers.get('Cookie'), null);
    return Response.json({user: null}, {headers: {
      'Set-Cookie': '__Host-collect_admin=; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=0',
    }});
  }});
  const response = await worker.fetch(new Request(vars.ADMIN_ORIGIN + '/api/admin/auth/session',
    {headers: {Cookie: '__Host-collect_admin=old_fixture; another=private_fixture'}}), vars);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Set-Cookie'),
    '__Host-collect_admin_rrlduytparvsjfmegalh=; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=0');
  for (const method of ['GET', 'POST']) {
    const retired = await worker.fetch(new Request(vars.ADMIN_ORIGIN + '/functions/v1/admin-api/api/admin/auth/session',
      {method, headers: {Origin: vars.ADMIN_ORIGIN, Cookie: '__Host-collect_admin_rrlduytparvsjfmegalh=new_fixture'}}), vars);
    assert.equal(retired.status, 410);
    assert.equal(retired.headers.get('Set-Cookie'), null);
  }
  assert.equal(calls, 1);
});
