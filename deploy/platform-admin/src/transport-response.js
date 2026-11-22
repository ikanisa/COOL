import {boundedBytes, cancelObserved} from './transport-body.js';
import {forwardResponseCookie} from './transport-cookies.js';
import {protectedHeaders, refuse} from './transport-failure.js';
import {GOOGLE_CALLBACK} from './transport-request.js';

const DROP_RESPONSE = new Set([
  'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
  'te', 'trailer', 'transfer-encoding', 'upgrade', 'content-length',
  'content-encoding', 'etag', 'last-modified', 'age', 'expires',
  'access-control-allow-origin', 'access-control-allow-credentials',
  'access-control-allow-methods', 'access-control-allow-headers',
]);
const DOCUMENTS = new Map([
  ['/v1/security/challenge', 'collect.turnstile.v1'],
  ['/v1/auth/google/callback', 'collect.google.callback.v1'],
  ['/privacy/account-deletion', 'collect.privacy.portal.v1'],
  ['/privacy/account-deletion/', 'collect.privacy.portal.v1'],
]);
const GATEWAY_DOCUMENT_CSP = "default-src 'none'; sandbox";
const PRIVACY_DOCUMENT_CSP = "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; object-src 'none'";
const TURNSTILE_SCRIPT = 'https://challenges.cloudflare.com/turnstile/v0/api.js?onload=collectChallengeReady&amp;render=explicit';
// Exact token-free errors emitted by the current shared Google callback helper.
const GOOGLE_NATIVE_ERRORS = new Set([
  'invalid_google_sign_in', 'google_cancelled', 'google_use_email_sign_in',
  'google_sign_in_unconfirmed',
]);

function nativeGoogleRedirect(upstream, route, method) {
  if (method !== 'GET' || route.functionName !== 'collect-api' || route.logicalPath !== GOOGLE_CALLBACK ||
      upstream.status !== 302 || upstream.headers.get('X-Collect-Document') !== 'collect.google.native.v1') return false;
  const location = upstream.headers.get('location');
  if (!location) return false;
  let target;
  try { target = new URL(location); } catch { return false; }
  if (target.href !== location || target.protocol !== 'collect:' || target.host !== 'auth' ||
      target.pathname !== '/google' || target.username || target.password || target.port || target.hash) return false;
  const keys = [...target.searchParams.keys()];
  if (keys.length !== 2 || new Set(keys).size !== 2 || !/^[A-Za-z0-9_-]{43}$/.test(target.searchParams.get('state') ?? '')) return false;
  return keys.includes('code') ? /^[A-Za-z0-9_-]{43}$/.test(target.searchParams.get('code') ?? '') :
    keys.includes('error') && GOOGLE_NATIVE_ERRORS.has(target.searchParams.get('error'));
}

/** The fixed Supabase gateway replaces HTML MIME and CSP. Restore only the
 * current marked renderers, never arbitrary upstream HTML or a permissive CSP.
 * Exact opener shapes deliberately fail closed when a renderer changes. */
function documentPolicy(document, text, upstreamPolicy, frontendOrigin, allowedFrontends) {
  const invalid = () => refuse(502, 'proxy_document_unqualified');
  if (!/^\s*(?:<!doctype html[^>]*>\s*)?<html\b/i.test(text) || !/<\/html>\s*$/i.test(text)) invalid();
  const scripts = [...text.matchAll(/<script\b[^>]*>/gi)].map(match => match[0]);
  const styles = [...text.matchAll(/<style\b[^>]*>/gi)].map(match => match[0]);
  if ((text.match(/<script\b/gi) ?? []).length !== scripts.length ||
      (text.match(/<style\b/gi) ?? []).length !== styles.length ||
      (text.match(/<\/script\s*>/gi) ?? []).length !== scripts.length ||
      (text.match(/<\/style\s*>/gi) ?? []).length !== styles.length) invalid();
  let policy; let originalPolicy;
  if (document === 'collect.privacy.portal.v1') {
    const script = scripts[0]?.match(/^<script type="module" src="((?:\/functions\/v1\/collect-api)?\/privacy\/account-deletion\/assets\/)client\.js">$/);
    const links = [...text.matchAll(/<link\b[^>]*>/gi)].map(match => match[0]);
    if (scripts.length !== 1 || styles.length !== 0 || !script || links.length !== 1 ||
        links[0] !== '<link rel="stylesheet" href="' + script[1] + 'style.css">') invalid();
    policy = originalPolicy = PRIVACY_DOCUMENT_CSP;
  } else if (document === 'collect.turnstile.v1') {
    const nonce = scripts[0]?.match(/^<script nonce="([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})">$/)?.[1];
    if (!nonce || scripts.length !== 2 || styles.length !== 1 || styles[0] !== '<style nonce="' + nonce + '">' ||
        scripts[1] !== '<script nonce="' + nonce + '" src="' + TURNSTILE_SCRIPT + '" async defer>') invalid();
    const prefix = `default-src 'none'; script-src 'nonce-${nonce}' https://challenges.cloudflare.com; style-src 'nonce-${nonce}'; frame-src https://challenges.cloudflare.com; connect-src https://challenges.cloudflare.com; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors `;
    policy = prefix + frontendOrigin;
    // The frozen backend emits 'self' plus its configured frontend origins.
    // A gateway-free response may retain that exact bounded renderer policy.
    if (upstreamPolicy.startsWith(prefix)) {
      const ancestors = upstreamPolicy.slice(prefix.length).trim().split(/\s+/);
      if (ancestors[0] === "'self'" && ancestors.slice(1).every(origin => allowedFrontends.has(origin))) originalPolicy = upstreamPolicy;
    }
  } else if (document === 'collect.google.callback.v1') {
    const nonce = scripts[0]?.match(/^<script nonce="([A-Za-z0-9_-]{43})">$/)?.[1];
    if (!nonce || scripts.length !== 1 || styles.length !== 0) invalid();
    policy = originalPolicy = `default-src 'none'; script-src 'nonce-${nonce}'; frame-ancestors 'none'; base-uri 'none'`;
  } else invalid();
  if (upstreamPolicy !== GATEWAY_DOCUMENT_CSP && upstreamPolicy !== policy && upstreamPolicy !== originalPolicy) invalid();
  return policy;
}

function responseHeaders(upstream, route, isolateAdminSession) {
  const headers = new Headers();
  for (const [name, value] of upstream.headers) {
    if (name === 'set-cookie' || DROP_RESPONSE.has(name)) continue;
    headers.append(name, value);
  }
  forwardResponseCookie(upstream, headers, route, isolateAdminSession);
  return protectedHeaders(headers);
}

export async function qualifyResponse(upstream, {route, method, signal, maxResponseBytes, isolateAdminSession, frontendOrigin, allowedFrontends}) {
  const nativeCallback = nativeGoogleRedirect(upstream, route, method);
  if (!nativeCallback && (upstream.status >= 300 && upstream.status < 400 || upstream.headers.has('location'))) {
    cancelObserved(upstream.body); refuse(502, 'proxy_redirect_denied');
  }
  const encoding = upstream.headers.get('content-encoding');
  if (encoding && encoding.trim().toLowerCase() !== 'identity') {
    cancelObserved(upstream.body); refuse(502, 'proxy_encoding_unqualified');
  }
  const size = upstream.headers.get('content-length');
  if (size !== null && (!/^[0-9]+$/.test(size) || Number(size) > maxResponseBytes)) {
    cancelObserved(upstream.body); refuse(502, 'proxy_response_too_large');
  }
  const output = await boundedBytes(upstream.body, maxResponseBytes, signal, 502, 'proxy_response_too_large');
  const response = responseHeaders(upstream, route, isolateAdminSession);
  const mime = upstream.headers.get('content-type')?.split(';')[0].trim().toLowerCase();
  const document = DOCUMENTS.get(route.logicalPath);
  if (upstream.ok && document) {
    if (upstream.headers.get('X-Collect-Document') !== document || !response.has('Content-Security-Policy')) refuse(502, 'proxy_document_unqualified');
    if (!['GET', 'HEAD'].includes(method) || !['text/plain', 'text/html'].includes(mime)) refuse(502, 'proxy_document_unqualified');
    if (method !== 'HEAD') {
      const text = new TextDecoder('utf-8', {fatal: true}).decode(output);
      response.set('Content-Security-Policy', documentPolicy(document, text,
        upstream.headers.get('Content-Security-Policy'), frontendOrigin, allowedFrontends));
    }
    // HEAD has no renderer body/nonce proof. Keep its original restrictive
    // policy and empty-body semantics; never fetch or retry a GET for it.
    response.set('Content-Type', 'text/html; charset=utf-8');
    // Keep marked service documents intact through frontend intermediaries,
    // including automatic analytics injection, without relaxing their CSP.
    response.set('Cache-Control', 'private, no-store, max-age=0, no-transform');
  } else if (!nativeCallback && mime === 'text/html') refuse(502, 'proxy_document_unqualified');
  return new Response(method === 'HEAD' || [204, 205, 304].includes(upstream.status) ? null : output,
    {status: upstream.status, statusText: upstream.statusText, headers: response});
}
