import {privacyPortalCss, privacyPortalScript} from './privacy_portal_assets.js';
import {otpDeliveryAvailable} from './auth.js';

const route = '/privacy/account-deletion';
const assets = route + '/assets/';
const headers = Object.freeze({
  'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'X-Frame-Options': 'DENY',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()',
  'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; object-src 'none'",
});
const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>Account deletion request · Collect</title><link rel="stylesheet" href="${assets}style.css"><script type="module" src="${assets}client.js"></script></head>
<body><div id="page"><header><a class="identity" href="https://collect.ikanisa.com/" aria-label="Collect home">Collect</a><small>Privacy requests</small></header>
<main id="main"><h1>Account deletion</h1><p class="muted">Request deletion without installing the app.</p>
<p class="notice">A request starts a review. It does not erase records, close your account or move money.</p>
<noscript><p>JavaScript is needed for secure verification and request status. You can also <a href="mailto:info@ikanisa.com?subject=Collect%20account%20deletion">email Collect support</a> without installing the app. Do not send a PIN, password, code or identity-document image.</p></noscript>
<p id="status" role="status" aria-live="polite" aria-atomic="true"></p><p id="error" role="alert" hidden></p>
<section id="step-phone"><h2 tabindex="-1">Verify your number</h2><p>Use the Rwanda number registered with Collect. This does not create a new account.</p>
<form id="phone-form"><label for="phone">Registered number</label><input id="phone" name="phone" type="tel" inputmode="tel" autocomplete="tel" placeholder="+250 7…" pattern="\\+2507[2389][0-9]{7}" maxlength="13" aria-describedby="phone-help" required><p id="phone-help" class="hint">Enter +250 followed by your nine-digit number, without spaces. The code is sent through the configured WhatsApp verification service.</p><div class="actions"><button type="submit">Send verification code</button></div></form></section>
<div class="actions"><button id="use-email" class="secondary" type="button" hidden>Use email instead</button></div>
<section id="step-email" hidden><h2 tabindex="-1">Verify your email</h2><p>Use the email registered with Collect. This does not create an account.</p><form id="email-form"><label for="email">Registered email</label><input id="email" name="email" type="email" autocomplete="email" maxlength="254" required><div class="actions"><button type="submit">Request email code</button><button id="use-phone" class="secondary" type="button">Use WhatsApp instead</button></div></form></section>
<section id="step-email-code" hidden><h2 tabindex="-1">Enter your email code</h2><p>If the account can be verified, a code may arrive. Delivery is not disclosed.</p><form id="email-code-form"><label for="email-code">Email verification code</label><input id="email-code" name="email-code" type="text" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6,10}" minlength="6" maxlength="10" required><div class="actions"><button type="submit">Verify email code</button><button id="email-resend" class="secondary" type="button">Send new code</button></div></form></section>
<section id="step-email-unknown" hidden><h2 tabindex="-1">Verification unconfirmed</h2><p>A verification may have finished even if its response was lost. Status cannot recover a lost sign-in session. No deletion request has been submitted by this verification.</p><div class="actions"><button id="email-check" type="button">Check original verification</button><button id="email-cancel" class="secondary" type="button">Cancel verification</button></div></section>
<section id="step-code" hidden><h2 tabindex="-1">Enter your code</h2><p>Use the code sent for this request. Never share it with support.</p><form id="code-form"><label for="code">Verification code</label><input id="code" name="code" type="text" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" minlength="6" maxlength="6" required><div class="actions"><button type="submit">Verify code</button><button id="resend-code" class="secondary" type="button">Send new code</button></div></form></section>
<section id="step-request" hidden><h2 tabindex="-1">Request a review</h2><p>We will review eligible data, required financial records and any legal hold. Your account stays accessible while review is pending.</p><div class="actions"><button id="review-request" type="button">Review deletion request</button></div></section>
<section id="step-confirm" hidden><h2 tabindex="-1">Submit your request?</h2><p>This sends your account deletion request for review. It does not confirm deletion or change a provider payment.</p><div class="actions"><button id="submit-request" type="button">Submit request</button><button id="back-request" class="secondary" type="button">Back</button></div></section>
<section id="step-unknown" hidden><h2 tabindex="-1">Result not confirmed</h2><p>Your request may have been received. Check status before retrying. A retry sends the same request reference.</p><div class="actions"><button id="check-status" type="button">Check status</button><button id="retry-request" class="secondary" type="button" disabled>Retry same request</button></div></section>
<section id="step-received" hidden><h2 tabindex="-1">Request received</h2><dl class="surface"><dt>Request reference</dt><dd id="reference"></dd><dt>Received</dt><dd id="accepted-at"></dd><dt>Review</dt><dd id="review-state"></dd></dl><p>Keep your reference. Sign in here again to check status. Records have not been erased; retention and legal-hold review is still required.</p><div class="actions"><button id="check-received" type="button">Refresh status</button></div></section>
<div class="actions"><button id="clear" class="secondary" type="button" hidden>Clear and sign out</button></div></main>
<footer><p>Cannot verify your account? <a href="mailto:info@ikanisa.com?subject=Collect%20account%20deletion">Contact support</a> to agree a suitable identity-verification step. Do not send a PIN, password, one-time code, authenticator secret or identity-document image.</p><nav aria-label="Privacy information"><a href="https://collect.ikanisa.com/privacy/#account-and-data-deletion">Data and retention</a><a href="https://collect.ikanisa.com/account-deletion/">Deletion help</a></nav></footer></div>
<dialog id="verification" aria-labelledby="verification-title" hidden><h2 id="verification-title">Security verification</h2><button id="cancel-verification" class="secondary" type="button">Cancel</button></dialog></body></html>`;

/** Public presentation only. All identity, intake and status authority stays in
 * the existing authenticated API handlers and their atomic D1 guards. */
export function privacyPortalRoute(request, env) {
  const path = new URL(request.url).pathname;
  let body, type;
  if (path === route || path === route + '/') {
    const available = otpDeliveryAvailable(env);
    // A configured privacy email route still needs the existing challenge
    // document. Missing CAPTCHA binding remains visibly unavailable.
    const emailAvailable = Boolean(env.SUPABASE_URL && env.SUPABASE_PUBLISHABLE_KEY &&
      typeof env.TURNSTILE_SITE_KEY === 'string' && /^[A-Za-z0-9_-]{10,256}$/.test(env.TURNSTILE_SITE_KEY));
    body = html.replace('<body>', `<body data-verification-available="${available}" data-email-verification-available="${emailAvailable}">`);
    if (!available && !emailAvailable) {
      body = body.replace('<section id="step-phone">', `<section id="verification-unavailable"><h2>Contact Collect support</h2><p>Phone verification is currently unavailable. You can <a href="mailto:info@ikanisa.com?subject=Collect%20account%20deletion">request a review by email</a> without installing the app.</p></section><section id="step-phone" hidden>`);
    }
    if (!available && emailAvailable) body = body.replace('<section id="step-phone">', '<section id="step-phone" hidden>');
    type = 'text/html; charset=utf-8';
  } else if (path === assets + 'client.js') {
    body = privacyPortalScript;
    type = 'text/javascript; charset=utf-8';
  } else if (path === assets + 'style.css') {
    body = privacyPortalCss;
    type = 'text/css; charset=utf-8';
  } else return null;
  if (!['GET', 'HEAD'].includes(request.method)) {
    return new Response('Use GET or HEAD.', {status: 405, headers: {...headers, Allow: 'GET, HEAD', 'Content-Type': 'text/plain; charset=utf-8'}});
  }
  return new Response(request.method === 'HEAD' ? null : body, {headers: {...headers, 'Content-Type': type}});
}
