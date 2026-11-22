import {PARENT_CONTROLLER_SOURCE} from './local-challenge-controller.mjs';

// Dedicated human-only parent document. The host must opt in to this route;
// importing this module neither starts a listener nor changes global headers.
const ADMIN = 'https://platform-admin.collect.ikanisa.com';
const PATH = '/admin/auth/local-challenge';
const ORIGINS = new Set([ADMIN, 'https://admin-supabase-qa.collect.ikanisa.com']);

function parentPath(path) {
  // Decode only to recognize and reject aliases; never admit a decoded route.
  let candidate = path;
  for (let pass = 0; pass < 2; pass++) {
    if (candidate.toLowerCase().replace(/\\/g, '/').replace(/\/{2,}/g, '/').startsWith(PATH)) return true;
    try { const decoded = decodeURIComponent(candidate); if (decoded === candidate) break; candidate = decoded; }
    catch { return candidate.toLowerCase().startsWith('/admin/auth/local-challenge'); }
  }
  return candidate.toLowerCase().replace(/\\/g, '/').replace(/\/{2,}/g, '/').startsWith(PATH);
}

export function renderLocalChallengeDocument(request, options = {}) {
  const url = new URL(request.url);
  if (!parentPath(url.pathname)) return null;
  const validOptions = options !== null && typeof options === 'object' &&
    Object.getPrototypeOf(options) === Object.prototype &&
    Object.keys(options).every(key => ['origin', 'allowedOrigins'].includes(key));
  const origin = validOptions && Object.hasOwn(options, 'origin') ? options.origin : ADMIN;
  // Explicit origins come only from the host's verified deployment profile.
  // The browser request and the pairing descriptor never choose this list.
  const configured = validOptions && Object.hasOwn(options, 'allowedOrigins') ? options.allowedOrigins : [...ORIGINS];
  const allowedOrigins = Array.isArray(configured) && configured.length > 0 && configured.length <= 4 && configured.every(value => {
    try { const target = new URL(value); return typeof value === 'string' && target.origin === value &&
      target.protocol === 'https:' && !target.port && !target.username && !target.password; } catch { return false; }
  }) ? new Set(configured) : null;
  const headers = new Headers({
    'Cache-Control': 'private, no-store, max-age=0, no-transform', 'CDN-Cache-Control': 'no-store',
    'Surrogate-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
    'Cross-Origin-Resource-Policy': 'same-origin', 'Cross-Origin-Opener-Policy': 'same-origin',
    'X-Frame-Options': 'DENY',
  });
  const refuse = (status, code) => {
    headers.set('Content-Type', 'application/json; charset=utf-8');
    return new Response(JSON.stringify({ code }), { status, headers });
  };
  if (!validOptions || !allowedOrigins?.has(origin)) return refuse(503, 'parent_configuration_invalid');
  if (url.pathname !== PATH || request.url.includes('\\')) return refuse(404, 'parent_path_invalid');
  if (url.origin !== origin || url.username || url.password ||
      request.headers.has('host') && request.headers.get('host') !== url.host) return refuse(421, 'parent_origin_invalid');
  if (request.url.includes('?') || request.url.includes('#')) return refuse(400, 'parent_path_invalid');
  if (request.headers.get('sec-fetch-site') === 'cross-site' ||
      request.headers.has('origin') && request.headers.get('origin') !== origin) return refuse(403, 'parent_origin_denied');
  if (request.method !== 'GET') { headers.set('Allow', 'GET'); return refuse(405, 'parent_method_invalid'); }
  const nonce = [...crypto.getRandomValues(new Uint8Array(24))].map(value => value.toString(16).padStart(2, '0')).join('');
  headers.set('Content-Type', 'text/html; charset=utf-8');
  headers.set('Content-Security-Policy', `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self' http://127.0.0.1:*; frame-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; object-src 'none'`);
  headers.set('Permissions-Policy', 'loopback-network=(self), local-network=(), camera=(), microphone=(), geolocation=()');
  return new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Security verification · Collect</title>
<style nonce="${nonce}">
:root{color-scheme:light dark;--canvas:#f7f7f8;--ink:#191c1f;--secondary:#45454a;--field:#fff;--border:#b8b8be;--focus:#000;--action:#3656fd;--error:#b3261e;--success:#137a3f}*{box-sizing:border-box}body{margin:0;background:var(--canvas);color:var(--ink);font:400 1rem/1.5 Inter,system-ui,sans-serif}main{width:min(100%,44rem);margin:0 auto;padding:clamp(24px,7vh,72px) clamp(16px,4vw,40px)}header{font-size:1.25rem;font-weight:700;margin-bottom:2rem}h1{font-size:clamp(1.75rem,1.5rem + 1vw,2.25rem);line-height:1.2;margin:0 0 1rem}p{max-width:38rem;margin:0 0 1.5rem;color:var(--secondary)}label{display:block;font-weight:500;margin-bottom:.5rem}textarea{display:block;width:100%;min-height:9rem;padding:14px;border:1px solid var(--border);border-radius:12px;background:var(--field);color:var(--ink);font:inherit;resize:vertical}small{display:block;color:var(--secondary);margin:.5rem 0 1.25rem}button{font:500 1rem/1.4 Inter,system-ui,sans-serif;min-height:48px;padding:12px 24px;border:1px solid transparent;border-radius:999px;cursor:pointer;background:var(--action);color:#fff}button:disabled{opacity:.55;cursor:default}button.secondary{background:transparent;color:var(--ink);border-color:var(--border)}button:focus-visible,textarea:focus-visible{outline:3px solid var(--focus);outline-offset:3px}.actions{display:flex;gap:12px;flex-wrap:wrap}#status{margin:1.5rem 0;overflow-wrap:anywhere}#status[data-state=failed],#status[data-state=unconfirmed],#status[data-state=expired]{color:var(--error)}#status[data-state=complete]{color:var(--success)}#task:empty{display:none}iframe{display:block;border:0;width:100%;height:380px;background:transparent}noscript{display:block;margin:1rem 0;color:var(--error)}@media(prefers-color-scheme:dark){:root{--canvas:#000;--ink:#f4f4f4;--secondary:#c9c9ce;--field:#161618;--border:#5a5a62;--focus:#fff;--error:#ff8c78;--success:#73e39b}}@media(max-width:360px){button{width:100%}}
</style></head><body><main><header>Collect</header><h1>Complete security verification</h1><p>Connect to the sign-in you started in your terminal on this computer. This page transfers only the security check; your sign-in stays in the terminal.</p>
<form id="pairing-form"><label for="pairing">Pairing details from your terminal</label><textarea id="pairing" rows="5" maxlength="4096" required autocomplete="off" autocapitalize="off" spellcheck="false" aria-describedby="pairing-help"></textarea><small id="pairing-help">Paste the public pairing details. Do not enter an email, password or sign-in code.</small><div class="actions"><button id="connect" type="submit">Connect</button><button id="cancel" class="secondary" type="button" disabled>Cancel</button></div></form>
<p id="task"></p><p id="status" role="status" aria-live="polite" aria-atomic="true" tabindex="-1">Ready for your terminal pairing details.</p><div id="challenge"></div><noscript>JavaScript is required for this security check. Return to your terminal.</noscript></main><script nonce="${nonce}">(${PARENT_CONTROLLER_SOURCE})(${JSON.stringify(origin)});</script></body></html>`, { status: 200, headers });
}
