import {MANAGED_SUPABASE_ORIGIN} from '../../../supabase/functions/_shared/deployment-profile.js';
import {managedBrowserCookies} from './transport-cookies.js';
import {refuse} from './transport-failure.js';

export const SUPABASE_ORIGIN = MANAGED_SUPABASE_ORIGIN;
export const GOOGLE_CALLBACK = '/v1/auth/google/callback';
export const FRONTENDS = new Set(['https://collect.ikanisa.com', 'https://admin.collect.ikanisa.com', 'https://platform-admin.collect.ikanisa.com', 'https://admin-supabase-qa.collect.ikanisa.com']);
const METHODS = new Set(['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']);
const FORWARD_HEADERS = new Set([
  'accept', 'accept-language', 'authorization', 'apikey', 'cookie', 'origin',
  'content-type', 'idempotency-key', 'x-request-id', 'range', 'if-match',
  'x-collect-admin', 'x-collect-requested-with', 'x-collect-csrf',
  'x-collect-review-reason', 'x-collect-gateway-key-id', 'x-collect-gateway-signature',
  'sec-fetch-site', 'sec-fetch-mode', 'sec-fetch-dest',
]);
const SPOOFED_AUTHORITY = new Set([
  'x-collect-actor', 'x-collect-original-path', 'x-collect-user-id',
  'x-collect-session-id', 'x-collect-authenticated-user', 'x-collect-verified',
  'x-forwarded-host', 'x-original-url', 'x-rewrite-url', 'forwarded',
]);

/** Validate the original raw path when the frontend host exposes it. Never
 * percent-decode a route into a second protocol or silently normalize dots. */
export function routeCollectTarget(rawTarget) {
  if (typeof rawTarget !== 'string' || !rawTarget.startsWith('/') || rawTarget.startsWith('//') ||
      /[\\\x00-\x20\x7f#]/.test(rawTarget)) refuse(400, 'proxy_path_invalid');
  const question = rawTarget.indexOf('?');
  const path = question < 0 ? rawTarget : rawTarget.slice(0, question);
  if (path.includes('%') || path.includes('//') || path.split('/').some(segment => segment === '.' || segment === '..') ||
      !/^\/[A-Za-z0-9._~\/-]*$/.test(path)) refuse(400, 'proxy_path_invalid');
  const query = question < 0 ? '' : rawTarget.slice(question);
  let functionName; let logicalPath = path;
  for (const name of ['collect-api', 'admin-api']) {
    const prefix = '/functions/v1/' + name;
    if (path.startsWith(prefix + '/')) { functionName = name; logicalPath = path.slice(prefix.length); break; }
  }
  if (path.startsWith('/functions/') && !functionName) refuse(404, 'proxy_route_not_allowed');
  if (functionName === 'admin-api' && !logicalPath.startsWith('/api/admin/')) refuse(404, 'proxy_route_not_allowed');
  const memberRoute = logicalPath.startsWith('/v1/') || logicalPath === '/privacy/account-deletion' || logicalPath.startsWith('/privacy/account-deletion/');
  if (functionName === 'collect-api' && !memberRoute) refuse(404, 'proxy_route_not_allowed');
  if (!functionName) {
    if (path.startsWith('/api/admin/')) functionName = 'admin-api';
    else if (memberRoute) functionName = 'collect-api';
    else return null;
  }
  return {path, logicalPath, query, functionName,
    upstream: SUPABASE_ORIGIN + '/functions/v1/' + functionName + logicalPath + query};
}

export function transportOrigin(value) {
  if (typeof value !== 'string' || value !== value.trim()) throw new TypeError('Invalid proxy origin');
  const parsed = new URL(value);
  if (parsed.origin !== value || parsed.username || parsed.password || parsed.pathname !== '/' || parsed.search || parsed.hash ||
      parsed.protocol !== 'https:' || parsed.port) throw new TypeError('Invalid proxy origin');
  return value;
}

export function admitRequest(request, rawTarget, frontendOrigin, isolateAdminSession) {
  const url = new URL(request.url);
  if (url.origin !== frontendOrigin || url.username || url.password || url.hash) refuse(421, 'proxy_origin_invalid');
  const host = request.headers.get('host');
  if (host && host !== url.host) refuse(421, 'proxy_origin_invalid');

  const canonical = url.pathname + url.search;
  const route = routeCollectTarget(rawTarget ?? canonical);
  if (!route) return null;
  // An old Flutter form cannot submit to a newly signed-in managed account.
  const adminRoute = route.functionName === 'admin-api';
  if (isolateAdminSession && adminRoute && route.path !== route.logicalPath) refuse(410, 'admin_realm_retired');
  if (route.path + route.query !== canonical) refuse(400, 'proxy_path_invalid');
  if (!METHODS.has(request.method)) refuse(405, 'proxy_method_invalid');
  for (const name of SPOOFED_AUTHORITY) if (request.headers.has(name)) refuse(400, 'proxy_authority_invalid');

  const callback = route.functionName === 'collect-api' && route.logicalPath === GOOGLE_CALLBACK && request.method === 'GET';
  const providerNavigation = callback && request.headers.get('sec-fetch-mode') === 'navigate' && request.headers.get('sec-fetch-dest') === 'document';
  const origin = request.headers.get('origin');
  if (origin && origin !== frontendOrigin && !(providerNavigation && origin === SUPABASE_ORIGIN)) refuse(403, 'proxy_origin_denied');
  const browserSite = request.headers.get('sec-fetch-site');
  if (browserSite === 'cross-site' && !providerNavigation) refuse(403, 'proxy_origin_denied');

  const read = ['GET', 'HEAD'].includes(request.method);
  const adminRead = adminRoute && read;
  // A same-origin Admin read can omit Origin. Sibling origins cannot inherit it.
  if (adminRead && !origin && ![null, 'none', 'same-origin'].includes(browserSite)) refuse(403, 'proxy_origin_denied');
  if (adminRoute && !read && request.method !== 'OPTIONS' && origin !== frontendOrigin) refuse(403, 'proxy_origin_denied');
  if (route.logicalPath === '/v1/security/challenge') {
    for (const key of ['attempt_id', 'parent_origin', 'theme']) {
      if (url.searchParams.getAll(key).length > 1) refuse(400, 'proxy_path_invalid');
    }
    const parent = url.searchParams.get('parent_origin');
    if (parent && parent !== frontendOrigin) refuse(403, 'proxy_origin_denied');
  }
  // Admin reads can rotate custody. The Google callback can commit an exchange.
  const effectful = callback || (adminRoute || !read) && request.method !== 'OPTIONS';
  return {route, effectful, inferOrigin: adminRead && !origin, read};
}

export function upstreamRequest(request, admission, bytes, signal, frontendOrigin, isolateAdminSession) {
  const {route, inferOrigin, read} = admission;
  const headers = new Headers();
  for (const [name, value] of request.headers) if (FORWARD_HEADERS.has(name)) headers.set(name, value);
  if (isolateAdminSession) managedBrowserCookies(headers, route);

  // Owner metadata opt-in and native device proof are restricted to their consumers.
  if (route.functionName === 'admin-api' && route.logicalPath === '/api/admin/auth/session' && request.method === 'GET' &&
      request.headers.get('x-collect-owner-identity-version') === '1') {
    headers.set('X-Collect-Owner-Identity-Version', '1');
  }
  if (route.functionName === 'admin-api' && route.logicalPath === '/api/admin/burimunsi/access' && request.method === 'POST') {
    const device = request.headers.get('x-burimunsi-device');
    if (device !== null) {
      if (!/^[a-f0-9]{64}$/.test(device)) refuse(400, 'proxy_device_proof_invalid');
      headers.set('X-BuriMunsi-Device', device);
    }
  }
  if (inferOrigin) headers.set('Origin', frontendOrigin);
  headers.set('Cache-Control', 'no-store');
  headers.set('Accept-Encoding', 'identity');
  return new Request(route.upstream, {
    method: request.method, headers, body: read ? undefined : bytes, redirect: 'manual', cache: 'no-store', signal,
  });
}
