// A missing content-addressed asset is never an SPA document. Recovery contains
// no caller data, account operation or retained predecessor/retention policy.
const PREFIX = '/_build/';
const MAIN = /^\/_build\/[a-f0-9]{64}\/main\.dart\.js$/;
const JAVASCRIPT = new Set(['text/javascript', 'application/javascript']);
const NO_STORE = {
  'Cache-Control': 'no-store, no-cache, max-age=0, must-revalidate, no-transform',
  'CDN-Cache-Control': 'no-store',
  'Surrogate-Control': 'no-store',
  Pragma: 'no-cache',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
};

// Source text stays self-contained when the Worker is bundled. It is a recovery
// controller, not a substitute application bundle: a service-worker digest check
// must still refuse it. No reload occurs until the operator presses the button.
export const STATIC_RECOVERY_SCRIPT = String.raw`(function collectStaticRecovery() {
  'use strict';
  function show() {
    if (!document.body || document.getElementById('collect-static-recovery') ||
        document.querySelector('flt-glass-pane, flutter-view, flt-scene-host, canvas, form, input, textarea, select, [contenteditable="true"]')) return;
    const panel = document.createElement('section');
    panel.id = 'collect-static-recovery';
    panel.setAttribute('role', 'alert');
    panel.setAttribute('aria-labelledby', 'collect-static-recovery-title');
    panel.style.cssText = 'box-sizing:border-box;width:calc(100% - 48px);max-width:440px;margin:clamp(32px,12vh,120px) auto;padding:24px 0;color:#191c1f;background:#fff;font:18px/1.5 Inter,system-ui,sans-serif;overflow-wrap:anywhere;';
    const title = document.createElement('h1');
    title.id = 'collect-static-recovery-title';
    title.textContent = "Collect couldn't load this page";
    title.style.cssText = 'font-size:clamp(24px,5vw,32px);font-weight:500;line-height:1.15;margin:0 0 16px;';
    const guidance = document.createElement('p');
    guidance.textContent = 'Finish any work in other Collect tabs, then close them and reopen this page online.';
    guidance.style.cssText = 'margin:0 0 24px;';
    const reopen = document.createElement('button');
    reopen.type = 'button';
    reopen.textContent = 'Reopen Collect';
    reopen.style.cssText = 'box-sizing:border-box;min-height:48px;max-width:100%;padding:12px 24px;border:1px solid #191c1f;border-radius:999px;background:#191c1f;color:#fff;font:500 18px/1.3 Inter,system-ui,sans-serif;white-space:normal;cursor:pointer;';
    reopen.addEventListener('click', function () { window.location.reload(); });
    panel.append(title, guidance, reopen);
    const mayFocus = document.activeElement === document.body;
    document.body.append(panel);
    if (mayFocus) reopen.focus();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', show, {once:true});
  else show();
})();
`;

function unavailable(request, main, status = 404) {
  const headers = new Headers(NO_STORE);
  headers.set('Content-Type', main ? 'text/javascript; charset=utf-8' : 'text/plain; charset=utf-8');
  headers.set('X-Collect-Static-Recovery', '1');
  const body = main ? STATIC_RECOVERY_SCRIPT : 'Admin static build is unavailable. Close all Admin tabs and reopen online.';
  // A script load must execute this explicit recovery controller. Returning an
  // HTML error or a non-2xx script response cannot show it in an old bootstrap.
  return new Response(request.method === 'HEAD' ? null : body, {status: main ? 200 : status, headers});
}

export async function versionedStatic(request, assets) {
  const path = new URL(request.url).pathname;
  if (!path.startsWith(PREFIX)) return null;
  if (!['GET', 'HEAD'].includes(request.method)) return new Response(null, {
    status: 405, headers: {...NO_STORE, Allow: 'GET, HEAD'},
  });
  const main = MAIN.test(path);
  let response;
  try {
    response = await assets.fetch(new Request(request, {redirect: 'manual'}));
    if (response.status === 304) {
      // A cached HTML fallback can also produce 304. Revalidate the actual
      // representation once, instead of authorizing it from an unknown MIME.
      const headers = new Headers(request.headers);
      headers.delete('If-None-Match');
      headers.delete('If-Modified-Since');
      headers.delete('Range');
      await response.body?.cancel();
      response = await assets.fetch(new Request(request, {headers, redirect: 'manual'}));
    }
  } catch {
    return unavailable(request, main, 503);
  }
  const mime = response.headers.get('Content-Type')?.split(';', 1)[0].trim().toLowerCase();
  if ((response.status === 200 || response.status === 206) && mime && mime !== 'text/html' &&
      (!main || JAVASCRIPT.has(mime)) && !response.headers.has('Set-Cookie')) return response;
  await response.body?.cancel();
  return unavailable(request, main, response.status >= 500 ? 503 : 404);
}
