import {renderLocalChallengeDocument} from './local-challenge.mjs';
import {createCollectTransport, SUPABASE_ORIGIN} from './supabase-transport.js';
import {verifyDeploymentProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
import {versionedStatic} from './static-recovery.js';

const PRODUCTION_ADMIN_ORIGIN = 'https://platform-admin.collect.ikanisa.com';
const API_ROOT = '/api';
const MANAGED_ROOTS = [API_ROOT, '/v1', '/functions', '/privacy/account-deletion'];

function failure(status, code, message) {
  return Response.json({error: {code, message}}, {status, headers: {
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
  }});
}

function hasRoot(path, root) {
  return path === root || path.startsWith(root + '/');
}

async function managedHost(env, fetchImpl, explicitProfile) {
  const profile = await verifyDeploymentProfile(env);
  if (env.SUPABASE_URL !== profile.supabase_origin || env.SUPABASE_INTERNAL_URL !== undefined ||
      explicitProfile && (env.ADMIN_ORIGIN !== profile.admin_origin ||
        env.APP_ENVIRONMENT !== undefined && env.APP_ENVIRONMENT !== profile.environment)) {
    throw new Error('Backend profile mismatch');
  }
  return {
    transport: createCollectTransport({
      frontendOrigin: env.ADMIN_ORIGIN,
      isolateAdminSession: env.ADMIN_ORIGIN === PRODUCTION_ADMIN_ORIGIN && profile.supabase_origin === SUPABASE_ORIGIN,
      ...(explicitProfile ? {allowedFrontendOrigins: [profile.public_origin, profile.member_api_origin, profile.admin_origin]} : {}),
      fetchImpl,
    }),
    challenge: {
      origin: env.ADMIN_ORIGIN,
      ...(explicitProfile ? {allowedOrigins: [profile.admin_origin]} : {}),
    },
  };
}

async function legacyApi(request, env, path) {
  if (!path.startsWith('/api/admin/')) return failure(404, 'not_found', 'This service route is unavailable.');
  if (!env.PLATFORM_API?.fetch) return failure(503, 'service_unavailable', 'The workspace service is unavailable.');
  try {
    // The existing account session remains bound to the original Admin origin.
    const response = await env.PLATFORM_API.fetch(request);
    const output = new Response(response.body, response);
    output.headers.set('Cache-Control', 'no-store');
    output.headers.set('X-Content-Type-Options', 'nosniff');
    output.headers.set('Referrer-Policy', 'no-referrer');
    return output;
  } catch {
    return failure(503, 'service_unavailable', 'The workspace service is unavailable.');
  }
}

async function serveAssets(request, url, assets, managed) {
  if (managed && url.pathname.startsWith('/_build/')) return versionedStatic(request, assets);
  // Typed deep links and worker installs use the same physical shell.
  const shell = managed && ['GET', 'HEAD'].includes(request.method) && (url.pathname === '/' || hasRoot(url.pathname, '/admin'));
  const response = await assets.fetch(shell ? new Request(new URL('/index.html', url), request) : request);
  if (response.headers.get('Content-Type')?.split(';', 1)[0].trim().toLowerCase() !== 'text/html') return response;
  const output = new Response(response.body, response);
  // The service worker verifies the exact shell bytes across intermediaries.
  output.headers.set('Cache-Control', 'no-store, no-transform');
  return output;
}

export function createAdminWorker({fetchImpl = (request, init) => globalThis.fetch(request, init)} = {}) {
  return {
    async fetch(request, env) {
      const url = new URL(request.url);
      if (url.origin !== env.ADMIN_ORIGIN) return failure(403, 'origin_denied', 'This workspace origin is unavailable.');
      const backend = env.COLLECT_BACKEND ?? 'supabase';
      const managed = backend === 'supabase';
      const explicitProfile = env.COLLECT_DEPLOYMENT_PROFILE !== undefined || env.COLLECT_DEPLOYMENT_PROFILE_SHA256 !== undefined;
      if (!managed && (backend !== 'cloudflare' || explicitProfile)) {
        return failure(503, 'backend_configuration_invalid', 'The workspace backend is unavailable.');
      }
      if (managed) {
        let host;
        try {
          host = await managedHost(env, fetchImpl, explicitProfile);
        } catch {
          return failure(503, 'backend_configuration_invalid', 'The workspace backend is unavailable.');
        }
        const parent = renderLocalChallengeDocument(request, host.challenge);
        if (parent) return parent;
        if (MANAGED_ROOTS.some(root => hasRoot(url.pathname, root))) {
          return await host.transport(request) ?? failure(404, 'not_found', 'This service route is unavailable.');
        }
      } else if (hasRoot(url.pathname, API_ROOT)) {
        return legacyApi(request, env, url.pathname);
      }
      return serveAssets(request, url, env.ASSETS, managed);
    },
  };
}

export default createAdminWorker();
