import {isManagedAdminBrowserOrigin} from './admin-security.js';
import {COLLECT_SUPABASE_ORIGIN, isGoogleProviderNavigation} from './runtime-env.js';

const projectHostname = new URL(COLLECT_SUPABASE_ORIGIN).hostname;
const loopbackHosts = new Set(['localhost', '127.0.0.1', '[::1]']);
const loggedPorts = new Set(['', '80', '443', '9000', '9999']);
const loggedFetchSites = new Set(['same-origin', 'same-site', 'cross-site', 'none']);
const allowedHeaders = [
  'Authorization', 'Content-Type', 'apikey', 'Idempotency-Key', 'X-Request-ID',
  'X-Collect-Admin', 'X-Collect-CSRF', 'X-Collect-Requested-With', 'X-Collect-Review-Reason',
].join(',');

export function requestTransportProfile(request) {
  const {protocol, hostname, port} = new URL(request.url);
  const site = request.headers.get('Sec-Fetch-Site');
  let host = 'other';
  if (hostname === projectHostname) host = 'project';
  else if (loopbackHosts.has(hostname)) host = 'loopback';
  return {
    protocol: protocol === 'http:' || protocol === 'https:' ? protocol : 'other',
    host,
    port: loggedPorts.has(port) ? port : 'other',
    sec_fetch_site: loggedFetchSites.has(site) ? site : 'other',
    origin_present: request.headers.has('Origin'),
  };
}

export function logicalRequest(request, functionName) {
  const url = new URL(request.url);
  const prefix = [`/functions/v1/${functionName}`, `/${functionName}`].find(
    value => url.pathname === value || url.pathname.startsWith(`${value}/`),
  );
  if (!prefix) throw new Error('Wrong function prefix.');

  // Supabase can supply an internal HTTP URL for this exact project host.
  // Restore its public scheme from the fixed origin.
  if (url.protocol === 'http:' && url.hostname === projectHostname && !url.port) {
    url.protocol = 'https:';
  }
  url.pathname = url.pathname.slice(prefix.length) || '/';

  const headers = new Headers(request.headers);
  headers.delete('X-Collect-Original-Path');
  headers.delete('X-Collect-Actor');
  return new Request(url, {
    method: request.method,
    headers,
    body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
    duplex: 'half',
    signal: request.signal,
  });
}

function origins(value) {
  return value.split(',').map(origin => origin.trim()).filter(Boolean);
}

export function mergeCollectOrigins(env) {
  const allowed = origins(env.ALLOWED_ORIGINS ?? '');
  const admin = origins(env.ADMIN_ORIGINS ?? env.ADMIN_ORIGIN ?? '');
  env.ALLOWED_ORIGINS = [...new Set([...allowed, ...admin])].join(',');
}

// A null return denies the browser origin. An empty object admits requests
// without an Origin header without adding CORS headers.
export function browserCors(env, request, admin, challengeParent) {
  const origin = request.headers.get('Origin');
  const allowed = origins(admin ? env.ADMIN_ORIGINS ?? env.ADMIN_ORIGIN : env.ALLOWED_ORIGINS ?? '');
  if (!origin) return {};
  if (!allowed.includes(origin) && origin !== challengeParent &&
      !(admin && isManagedAdminBrowserOrigin(env, origin)) && !isGoogleProviderNavigation(request)) {
    return null;
  }

  const headers = {
    'Access-Control-Allow-Origin': origin,
    Vary: 'Origin',
    'Access-Control-Allow-Methods': 'GET,HEAD,POST,PATCH,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': admin ? `${allowedHeaders},X-Collect-Owner-Identity-Version` : allowedHeaders,
    'Access-Control-Max-Age': '600',
  };
  if (admin) {
    headers['Access-Control-Allow-Credentials'] = 'true';
    headers['Access-Control-Expose-Headers'] = 'X-Collect-Evidence-Sensitivity';
  }
  return headers;
}

export async function edgeHttpResponse(response, request, {functionName, path, admin, cors}) {
  if (admin && response.status === 403) {
    const failure = await response.clone().json().catch(() => null);
    if (failure?.error?.code === 'origin_rejected') {
      console.error(JSON.stringify({
        service: 'collect_platform_api', event: 'admin_transport_rejected',
        profile: requestTransportProfile(request),
      }));
    }
  }

  const contentType = response.headers.get('Content-Type') ?? '';
  let body = response.body;
  if (response.ok && path.startsWith('/privacy/account-deletion') &&
      /text\/(?:html|javascript)|application\/javascript/.test(contentType)) {
    const prefix = `/functions/v1/${functionName}`;
    body = (await response.text())
      .replaceAll('/v1/', `${prefix}/v1/`)
      .replaceAll('/privacy/account-deletion', `${prefix}/privacy/account-deletion`);
  }
  const copy = new Response(body, response);
  if (response.ok && /text\/html/i.test(contentType)) {
    if (path === '/v1/security/challenge') copy.headers.set('X-Collect-Document', 'collect.turnstile.v1');
    if (/^\/privacy\/account-deletion\/?$/.test(path)) copy.headers.set('X-Collect-Document', 'collect.privacy.portal.v1');
  }
  for (const [key, value] of Object.entries(cors)) copy.headers.set(key, value);
  return copy;
}
