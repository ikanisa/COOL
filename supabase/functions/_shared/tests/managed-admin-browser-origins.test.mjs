import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {
  adminBrowserOrigins, adminSessionOriginMatches, managedAdminChallengeParent, validateAdminOrigin,
} from '../admin-security.js';
import {challengeRoute} from '../domain/challenge.js';
import {canonicalProfile, MANAGED_SUPABASE_ORIGIN, verifyDeploymentProfile} from '../deployment-profile.js';

const project = MANAGED_SUPABASE_ORIGIN;
const hosts = ['https://platform-admin.collect.ikanisa.com', 'https://admin-supabase-qa.collect.ikanisa.com'];
const profile = {format: 'collect.deployment.v1', id: 'collect-managed-production-cloud', mode: 'managed',
  environment: 'production', supabase_origin: project, member_api_origin: project,
  admin_origin: project, public_origin: project, google_callback_origin: project};
const encoded = canonicalProfile(profile);
const env = {COLLECT_DEPLOYMENT_PROFILE: encoded, COLLECT_DEPLOYMENT_PROFILE_SHA256: createHash('sha256').update(encoded).digest('hex'),
  APP_ENVIRONMENT: 'production', SUPABASE_URL: project, ADMIN_ORIGIN: project, ADMIN_ORIGINS: project};

test('the deployed managed profile admits both browser hosts and keeps each session on its issuing host', async () => {
  assert.deepEqual(await verifyDeploymentProfile(env), profile);
  assert.deepEqual(adminBrowserOrigins(env), [project, ...hosts]);
  for (const origin of hosts) {
    const request = new Request(project + '/api/admin/auth/session', {headers: {Origin: origin}});
    assert.equal(validateAdminOrigin(request, env), origin);
    assert.equal(adminSessionOriginMatches(request, env, profile, {origin}), true);
    assert.equal(adminSessionOriginMatches(request, env, profile, {origin: hosts.find(host => host !== origin)}), false);
  }
});

test('the two public Admin hosts do not extend a different deployment profile', () => {
  for (const change of [{COLLECT_DEPLOYMENT_PROFILE_SHA256: '0'.repeat(64)}, {APP_ENVIRONMENT: 'qualification'},
    {SUPABASE_URL: 'https://different.example.invalid'}, {ADMIN_ORIGIN: 'https://different.example.invalid'}]) {
    assert.deepEqual(adminBrowserOrigins({...env, ...change}), [project]);
  }
});

for (const host of hosts) {
  test('the login verification document supports GET and HEAD on ' + new URL(host).hostname, async () => {
    const url = new URL('/v1/security/challenge', project);
    url.searchParams.set('attempt_id', '00000000-0000-4000-8000-000000000001');
    url.searchParams.set('parent_origin', host);
    for (const method of ['GET', 'HEAD']) {
      const request = new Request(url, {method, headers: {Origin: host}});
      const parent = managedAdminChallengeParent(request, env);
      assert.equal(parent, host);
      const response = await challengeRoute(request, {
        ...env, ALLOWED_ORIGINS: parent, TURNSTILE_SITE_KEY: 'synthetic_public_site_key',
      });
      assert.equal(response.status, 200);
      assert.equal(response.headers.get('Cache-Control'), 'no-store');
      const directives = response.headers.get('Content-Security-Policy').split('; ');
      assert.ok(directives.includes("frame-ancestors 'self' " + host));
      const body = await response.text();
      if (method === 'HEAD') assert.equal(body, '');
      else assert.ok(body.includes('Verify your request'));
    }
  });
}
