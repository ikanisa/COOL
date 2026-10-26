import {privacyPortalRoute} from '../../../../supabase/functions/_shared/domain/privacy_portal.js';
import {challengeRoute} from '../../../../supabase/functions/_shared/domain/challenge.js';
import {callbackResult} from '../../../../supabase/functions/_shared/domain/google_auth.js';

export const GATEWAY_CSP = "default-src 'none'; sandbox";
const project = 'https://rrlduytparvsjfmegalh.supabase.co';
const prefix = '/functions/v1/collect-api';
export async function renderedDocument(kind, frontendOrigin = 'https://admin.collect.ikanisa.com') {
  const env = {SUPABASE_URL: project, SUPABASE_PUBLISHABLE_KEY: 'synthetic-fixture-only',
    TURNSTILE_SITE_KEY: 'synthetic_fixture_turnstile_site_key', ALLOWED_ORIGINS: frontendOrigin,
    ADMIN_ORIGINS: frontendOrigin};
  let original; let marker; let path;
  if (kind === 'privacy') {
    path = '/privacy/account-deletion'; marker = 'collect.privacy.portal.v1';
    original = privacyPortalRoute(new Request(project + path), env);
  } else if (kind === 'challenge') {
    path = '/v1/security/challenge?attempt_id=ce2a0e28-5369-4c29-9d46-a1c033ed9b64&parent_origin=' + encodeURIComponent(frontendOrigin);
    marker = 'collect.turnstile.v1';
    original = await challengeRoute(new Request(project + path), env);
  } else if (kind === 'google') {
    path = '/v1/auth/google/callback'; marker = 'collect.google.callback.v1';
    original = callbackResult({surface: 'admin', return_origin: frontendOrigin},
      {state: 's'.repeat(43), code: 'c'.repeat(43)});
  } else throw new TypeError('Unknown fixture document');
  let html = await original.text();
  if (kind === 'privacy') {
    // Exact presentation-path projection in the frozen Edge serve.js adapter.
    html = html.replaceAll('/v1/', prefix + '/v1/').replaceAll('/privacy/account-deletion', prefix + '/privacy/account-deletion');
  }
  const originalPolicy = original.headers.get('Content-Security-Policy');
  return {html, marker, path, originalPolicy, reply({method = 'GET', policy = GATEWAY_CSP, body = html,
    status = 200, headers = {}} = {}) {
    const responseHeaders = new Headers(original.headers);
    responseHeaders.set('Content-Type', 'text/plain');
    responseHeaders.set('X-Collect-Document', marker);
    if (policy === null) responseHeaders.delete('Content-Security-Policy');
    else responseHeaders.set('Content-Security-Policy', policy);
    for (const [name, value] of Object.entries(headers)) {
      if (value === null) responseHeaders.delete(name); else responseHeaders.set(name, value);
    }
    return new Response(method === 'HEAD' ? null : body, {status, headers: responseHeaders});
  }};
}
