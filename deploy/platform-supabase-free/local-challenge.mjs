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

// Kept as source text: a bundler may add outer helpers to executable functions.
// The nonce inline script must remain self-contained after Wrangler/esbuild.
const PARENT_CONTROLLER_SOURCE = String.raw`function parentController(origin) {
  'use strict';
  const operations = {
    'admin.email_otp.send': 'Request an email code',
    'admin.email_otp.verify': 'Verify the original email code',
    'admin.password.sign_in': 'Sign in with your existing password',
  };
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
  const b64 = /^[A-Za-z0-9_-]+$/;
  const form = document.getElementById('pairing-form');
  const input = document.getElementById('pairing');
  const connect = document.getElementById('connect');
  const cancel = document.getElementById('cancel');
  const status = document.getElementById('status');
  const task = document.getElementById('task');
  const mount = document.getElementById('challenge');
  let started = false, terminal = false, descriptor = null, offer = null;
  let frame = null, timer = null, active = null, deadline = 0;
  const fail = () => { throw new Error('unverified'); };
  const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
  const exact = (value, keys) => object(value) &&
    Object.keys(value).sort().join(',') === [...keys].sort().join(',');
  function parse(text) {
    const value = JSON.parse(text);
    // Every wire object in this protocol is flat. Count decoded member names
    // before schema checking so JSON.parse cannot hide duplicate keys.
    const names = (text.match(/"(?:\\.|[^"\\])*"\s*:/g) || []).map(member =>
      JSON.parse(member.slice(0, member.lastIndexOf(':')).trim()));
    if (new Set(names).size !== names.length) fail();
    return value;
  }
  function canonical(value) {
    return JSON.stringify(Object.fromEntries(Object.keys(value).sort().map(key => [key, value[key]])));
  }
  function decode(text, length) {
    if (typeof text !== 'string' || !b64.test(text) || text.length % 4 === 1) fail();
    const raw = atob(text.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(text.length / 4) * 4, '='));
    const bytes = Uint8Array.from(raw, char => char.charCodeAt(0));
    const encoded = btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    if (encoded !== text || length !== undefined && bytes.length !== length) fail();
    return bytes;
  }
  function pairing(text) {
    if (typeof text !== 'string' || text.length > 4096) fail();
    const value = parse(text);
    if (!exact(value, ['type', 'attempt_id', 'operation', 'admin_origin', 'loopback_port', 'expires_at_ms', 'listener_public_key_ed25519']) ||
        value.type !== 'collect.admin.human_challenge.pairing.v1' || !uuid.test(value.attempt_id) ||
        !Object.hasOwn(operations, value.operation) || value.admin_origin !== origin ||
        !Number.isSafeInteger(value.loopback_port) || value.loopback_port < 1024 || value.loopback_port > 65535 ||
        !Number.isSafeInteger(value.expires_at_ms) || value.expires_at_ms <= Date.now() ||
        value.expires_at_ms > Date.now() + 120_000) fail();
    decode(value.listener_public_key_ed25519, 32);
    return value;
  }
  function remaining() {
    return descriptor ? Math.min(descriptor.expires_at_ms - Date.now(), deadline - performance.now()) : 0;
  }
  function show(message, state) {
    status.textContent = message;
    status.dataset.state = state;
    if (terminal) status.focus();
  }
  function detach() {
    if (timer !== null) clearTimeout(timer);
    timer = null;
    window.removeEventListener('message', message);
    frame?.remove(); frame = null;
    cancel.disabled = true;
  }
  function abandon(messageText, state = 'failed') {
    terminal = true;
    active?.abort(); active = null;
    detach(); offer = null; descriptor = null;
    show(messageText, state);
  }
  async function reply(path, method, body, maximum, expectedStatus) {
    if (remaining() <= 0) fail();
    const controller = new AbortController(); active = controller;
    const timeout = setTimeout(() => controller.abort(), Math.min(12_000, remaining()));
    const url = 'http://127.0.0.1:' + descriptor.loopback_port + path;
    try {
      const response = await fetch(url, {
        method, mode: 'cors', credentials: 'omit', cache: 'no-store', redirect: 'error', signal: controller.signal,
        headers: { Accept: 'application/json', 'X-Collect-Handoff-Version': '1',
          'X-Collect-Handoff-Attempt': descriptor.attempt_id,
          ...(body ? { 'Content-Type': 'application/json' } : {}) },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      if (response.status !== expectedStatus || response.redirected || response.type === 'opaque' ||
          response.url && response.url !== url || !/^application\/json(?:\s*;|$)/i.test(response.headers.get('Content-Type') || '')) fail();
      const length = response.headers.get('Content-Length');
      if (length && (!/^\d+$/.test(length) || Number(length) > maximum)) { await response.body?.cancel(); fail(); }
      const reader = response.body?.getReader(); if (!reader) fail();
      const chunks = []; let size = 0;
      try {
        while (true) {
          const next = await reader.read(); if (next.done) break;
          size += next.value.length;
          if (size > maximum) { await reader.cancel(); fail(); }
          chunks.push(next.value);
        }
      } finally { reader.releaseLock(); }
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      return parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
    } finally {
      clearTimeout(timeout);
      if (active === controller) active = null;
    }
  }
  async function verify(value, key) {
    if (!exact(value, ['type', 'payload_base64url', 'signature_ed25519_base64url']) ||
        value.type !== 'collect.admin.human_challenge.signed_offer.v1' ||
        typeof value.payload_base64url !== 'string' || value.payload_base64url.length > 4096) fail();
    const bytes = decode(value.payload_base64url), signature = decode(value.signature_ed25519_base64url, 64);
    if (!await crypto.subtle.verify({ name: 'Ed25519' }, key, signature, bytes)) fail();
    const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes), payload = parse(text);
    if (!exact(payload, ['type', 'attempt_id', 'operation', 'admin_origin', 'loopback_port', 'nonce', 'issued_at_ms', 'expires_at_ms']) ||
        payload.type !== 'collect.admin.human_challenge.offer_payload.v1' || canonical(payload) !== text ||
        ['attempt_id', 'operation', 'admin_origin', 'loopback_port', 'expires_at_ms'].some(key => payload[key] !== descriptor[key]) ||
        !Number.isSafeInteger(payload.issued_at_ms) || payload.issued_at_ms > Date.now() ||
        payload.issued_at_ms < descriptor.expires_at_ms - 120_000 || remaining() <= 0) fail();
    decode(payload.nonce, 32);
    return payload;
  }
  async function complete(candidate) {
    if (terminal || !offer || remaining() <= 0) return;
    terminal = true; detach();
    const expected = candidate.token !== undefined ? 'accepted_for_one_cli_operation'
      : candidate.error === 'cancelled' ? 'cancelled_without_auth'
      : ['expired', 'timeout'].includes(candidate.error) ? 'expired_without_auth' : 'failed_without_auth';
    let body = { type: 'collect.admin.human_challenge.complete.v1', attempt_id: descriptor.attempt_id,
      operation: descriptor.operation, nonce: offer.nonce, widget_attempt_id: descriptor.attempt_id, ...candidate };
    show('Transferring verification to your terminal…', 'connecting');
    try {
      const ack = await reply('/v1/collect-admin/human-challenge/complete', 'POST', body, 1024, 202);
      if (!exact(ack, ['type', 'attempt_id', 'operation', 'status', 'session_confirmed']) ||
          ack.type !== 'collect.admin.human_challenge.ack.v1' || ack.attempt_id !== descriptor.attempt_id ||
          ack.operation !== descriptor.operation || ack.status !== expected || ack.session_confirmed !== false) fail();
      show(expected === 'accepted_for_one_cli_operation'
        ? 'Verification transferred. Return to your terminal for the sign-in result.'
        : 'Verification ended without a sign-in request. Return to your terminal.',
      expected === 'accepted_for_one_cli_operation' ? 'complete' : 'cancelled');
    } catch {
      show('The handoff is unconfirmed. Check the original terminal result. Do not repeat this attempt.', 'unconfirmed');
    } finally { body = null; offer = null; descriptor = null; }
  }
  async function message(event) {
    if (terminal || !frame || event.origin !== origin || event.source !== frame.contentWindow) return;
    if (document.visibilityState !== 'visible' || remaining() <= 0) {
      abandon('Verification ended because this page is no longer active or the attempt expired.', 'expired'); return;
    }
    const data = event.data;
    const token = exact(data, ['type', 'attempt_id', 'token']) && typeof data.token === 'string' &&
      data.token.length >= 1 && data.token.length <= 2048 && /^[^\u0000-\u0020\u007f]+$/.test(data.token);
    const error = exact(data, ['type', 'attempt_id', 'error']) &&
      ['cancelled', 'expired', 'unavailable', 'timeout', 'invalid_token'].includes(data.error);
    if ((!token && !error) || data.type !== 'collect.turnstile.v1' || data.attempt_id !== descriptor.attempt_id) {
      await complete({ error: 'invalid_token' }); return;
    }
    await complete(token ? { token: data.token } : { error: data.error });
  }
  form.addEventListener('submit', async event => {
    event.preventDefault(); if (started) return;
    try {
      if (window.location.origin !== origin || window.location.pathname !== '/admin/auth/local-challenge' ||
          window.location.search || window.location.hash || window.top !== window ||
          !window.isSecureContext || document.visibilityState !== 'visible' || !crypto?.subtle) fail();
      descriptor = pairing(input.value);
    } catch {
      show('Use fresh pairing details from your terminal in a supported, foreground Collect page.', 'failed');
      input.focus(); return;
    }
    started = true; input.value = ''; input.disabled = true; connect.disabled = true; cancel.disabled = false;
    deadline = performance.now() + Math.min(120_000, descriptor.expires_at_ms - Date.now());
    timer = setTimeout(() => abandon('This attempt expired. Return to your terminal; nothing was retried.', 'expired'), remaining());
    task.textContent = operations[descriptor.operation];
    show('Connecting to the terminal on this computer. Allow the browser connection if asked.', 'connecting');
    try {
      const key = await crypto.subtle.importKey('raw', decode(descriptor.listener_public_key_ed25519, 32), { name: 'Ed25519' }, false, ['verify']);
      if (terminal) return;
      const value = await reply('/v1/collect-admin/human-challenge/offer', 'GET', null, 8192, 200);
      if (terminal) return;
      offer = await verify(value, key);
      if (terminal) return;
      if (document.visibilityState !== 'visible') fail();
      frame = document.createElement('iframe');
      frame.title = 'Collect security verification'; frame.referrerPolicy = 'no-referrer';
      frame.setAttribute('sandbox', 'allow-scripts allow-same-origin');
      const url = new URL('/functions/v1/collect-api/v1/security/challenge', origin);
      url.search = new URLSearchParams({ attempt_id: descriptor.attempt_id, parent_origin: origin, theme: 'auto' }).toString();
      frame.src = url.href;
      window.addEventListener('message', message);
      mount.appendChild(frame);
      show('Complete the security check below. Your sign-in continues in the terminal.', 'verifying');
    } catch {
      if (!terminal) abandon('The local connection could not be verified. Check your terminal and browser permissions; this attempt was not retried.');
    }
  });
  cancel.addEventListener('click', async () => {
    if (!started || terminal) return;
    if (offer) await complete({ error: 'cancelled' });
    else abandon('Verification cancelled. Return to your terminal.', 'cancelled');
  });
  document.addEventListener('visibilitychange', () => {
    if (started && !terminal && document.visibilityState !== 'visible') {
      abandon('Verification ended when this page was hidden. Return to your terminal.', 'cancelled');
    }
  });
  window.addEventListener('pagehide', () => {
    if (started) abandon('Verification ended. Check the original terminal result.', 'unconfirmed');
  });
}`;

export function renderLocalChallengeDocument(request, options = {}) {
  const url = new URL(request.url);
  if (!parentPath(url.pathname)) return null;
  const validOptions = options !== null && typeof options === 'object' &&
    Object.getPrototypeOf(options) === Object.prototype &&
    Object.keys(options).every(key => key === 'origin');
  const origin = validOptions && Object.hasOwn(options, 'origin') ? options.origin : ADMIN;
  const headers = new Headers({
    'Cache-Control': 'private, no-store, max-age=0, no-transform', 'CDN-Cache-Control': 'no-store',
    'Netlify-CDN-Cache-Control': 'no-store', 'Surrogate-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
    'Cross-Origin-Resource-Policy': 'same-origin', 'Cross-Origin-Opener-Policy': 'same-origin',
    'X-Frame-Options': 'DENY',
  });
  const refuse = (status, code) => {
    headers.set('Content-Type', 'application/json; charset=utf-8');
    return new Response(JSON.stringify({ code }), { status, headers });
  };
  if (!validOptions || !ORIGINS.has(origin)) return refuse(503, 'parent_configuration_invalid');
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
