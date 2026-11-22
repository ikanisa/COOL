export const SCRIPT_PATH = '/admin-entry-handoff.js';

// This document runs only on a retired origin. Keep the original tab available
// whenever the browser cannot prove that leaving it is a clean navigation.
export function handoffDocument(destination, preserve) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>Open Collect Admin</title>
<style>
:root{color-scheme:light dark;font:100%/1.55 Inter,system-ui,sans-serif;background:#f8f9fb;color:#171b20}
main{max-width:31rem;margin:12vh auto;padding:1.5rem}h1{font-size:clamp(1.75rem,5vw,2.4rem);line-height:1.15;margin:0 0 1rem}
p{margin:0 0 1.5rem;color:#596574}a{display:inline-block;padding:.65rem 1rem;margin:0 .45rem .7rem 0;border-radius:.7rem;font-weight:650}
a:first-of-type{color:white;background:#2446f6;text-decoration:none}a+a{color:#203cca}a:focus-visible{outline:3px solid #3656fd;outline-offset:3px}
[hidden]{display:none}@media(prefers-color-scheme:dark){:root{background:#111318;color:#f4f6f9}p{color:#b7c0cd}a:first-of-type{color:#111318;background:#93a7ff}a+a{color:#b6c3ff}}
</style></head><body><main${preserve ? ' data-preserve' : ''}>
<h1>Open Collect Admin</h1><p id="guidance">Keep this tab open if you have unfinished work. Collect Admin opens in a new tab and uses its own sign-in.</p>
<a id="primary" href="${destination}/#/admin" target="_blank" rel="noopener noreferrer">Open Collect Admin in a new tab</a>
<a id="alternative" href="${destination}/#/admin" target="_blank" rel="noopener noreferrer" hidden>Open the address path instead</a>
</main><script src="${SCRIPT_PATH}" defer></script></body></html>`;
}

// Fixed code and a fixed destination. Nothing from a request is inserted into
// HTML or JavaScript. Reading length never opens an old operator's stored data.
export function handoffScript(destination) {
  return String.raw`'use strict';
(async () => {
  const address = new URL(window.location.href);
  const home = '${destination}/#/admin';
  const primary = document.getElementById('primary');
  const alternative = document.getElementById('alternative');
  const guidance = document.getElementById('guidance');
  function safeRoute(raw) {
    if (!raw || raw.length > 2000 || /[#\\\x00-\x20\x7f]/.test(raw)) return null;
    const path = raw.split('?')[0];
    if (path !== '/admin' && !path.startsWith('/admin/')) return null;
    let parsed;
    try {
      parsed = new URL(raw, address.origin);
      if (parsed.pathname !== path || parsed.origin !== address.origin) return null;
      if (path.includes('//') || path.split('/').some(part => /[%/\\\x00-\x20\x7f]/.test(decodeURIComponent(part)))) return null;
    } catch { return null; }
    if (/(?:^|\/)(?:api|auth|functions|rest|graphql|rpc)(?:\/|$)/i.test(decodeURIComponent(path))) return null;
    // Setup links and bearer/auth callback material are issued by the old host.
    // The destination's own sign-in issues an account-specific replacement.
    if (path === '/admin/setup' || sensitiveQuery(parsed.searchParams)) return null;
    return raw;
  }
  function sensitiveQuery(params) {
    for (const [key, value] of params) {
      if (/^(?:token|access_token|refresh_token|id_token|provider_token|code|state|otp|password|csrf_token|token_hash|error_description|key|request_id|idempotency_key)$/i.test(key)) return true;
      if (/^(?:returnTo|redirect|next)$/i.test(key) && !/^\/admin(?:\/[A-Za-z0-9._~:-]+)*\/?$/.test(value)) return true;
    }
    return false;
  }
  const documentPath = address.pathname === '/' || address.pathname === '/index.html';
  const pathRoute = documentPath ? null : safeRoute(address.pathname + address.search);
  const fragment = address.hash.slice(1);
  const fragmentTask = fragment.split('#')[0];
  const fragmentRoute = safeRoute(fragmentTask);
  const primaryRoute = fragmentRoute || pathRoute;
  const destination = primaryRoute ? '${destination}/#' + primaryRoute : home;
  primary.href = destination;
  const conflict = pathRoute && fragmentRoute && pathRoute !== fragmentRoute;
  if (conflict) {
    alternative.href = '${destination}/#' + pathRoute;
    alternative.hidden = false;
    primary.textContent = 'Open the bookmarked route';
    guidance.textContent = 'This address contains two Admin routes. Choose which one to open in a new tab. This tab keeps the original address.';
  }
  const uncertain = conflict || (fragment && (!fragmentRoute || fragment !== fragmentTask)) || (!documentPath && !pathRoute) ||
    (documentPath && address.search);
  if (uncertain || document.querySelector('main[data-preserve]')) return;
  try {
    // Version 41 could cache private same-origin GETs as well as public assets.
    // Check only whether these stores exist. Never enumerate records or read a cached response.
    if (!window.caches || (await window.caches.keys()).length) return;
    if (window.indexedDB?.databases && (await window.indexedDB.databases()).length) return;
    if (window.navigator.serviceWorker?.controller || window.history.state != null ||
        window.sessionStorage.length || window.localStorage.length) return;
  } catch { return; }
  window.location.replace(destination);
})();`;
}
