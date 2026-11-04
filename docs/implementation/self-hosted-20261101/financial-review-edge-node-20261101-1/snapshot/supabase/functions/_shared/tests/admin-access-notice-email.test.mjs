import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {isAbsolute, join} from 'node:path';
import {pathToFileURL} from 'node:url';

// Actual pure renderer only. No DOM/browser, design comparison, SDK, SMTP,
// dependency resolution, provider authentication or delivery proof.
const root = process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(typeof root === 'string' && isAbsolute(root), 'Provide the coherent actual _shared graph.');
const {renderAdminAccessNotice} = await import(pathToFileURL(join(root, 'domain/admin_access_notice_email.js')).href);
const ORIGIN = 'https://platform-admin.collect.ikanisa.com';
const LOGIN = ORIGIN + '/#/admin/login';
const SUPPORT = 'mailto:info@ikanisa.com';
// Public UAT candidate1 HTML40ae51ce... with its sole slot replaced by LOGIN.
const APPROVED_HTML_SHA256 = 'bdb4e31a4c60b980794eab3730a9f5b3a73f839b3bc01934f4a2d4f53ceaae98';
const APPROVED_TEXT = `You have been invited to Collect.

Open Collect and sign in with the email address that received this invitation. Request a secure sign-in code to continue.

Open Collect: ${LOGIN}

This invitation does not sign you in. If you were not expecting it, contact your super admin.

Collect
info@ikanisa.com
`;

function visible(html) {
  return html.replace(/<head\b[^>]*>[\s\S]*?<\/head>/gi, ' ')
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<!--[\s\S]*?-->/g, ' ').replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;|&#160;/gi, ' ').replace(/\s+/g, ' ').trim();
}
function anchors(html) {
  return [...html.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)].map(match => {
    const attributes = match[1], hrefs = [...attributes.matchAll(/\bhref\s*=\s*(["'])(.*?)\1/gi)];
    assert.equal(hrefs.length, 1, 'Every link must have one quoted, unambiguous destination');
    return {href: hrefs[0][2], label: visible(match[2])};
  });
}
function contentSafety(result, origin = ORIGIN) {
  assert.deepEqual(Object.keys(result).sort(), ['html', 'subject', 'text']);
  for (const key of ['subject', 'text', 'html']) assert.equal(typeof result[key], 'string');
  assert.ok(result.subject.length > 0 && result.subject.length <= 200);
  assert.ok(result.text.length > 0 && result.text.length <= 20000);
  assert.ok(result.html.length > 0 && result.html.length <= 100000);
  assert.equal(/[\u0000-\u001f\u007f-\u009f]/.test(result.subject), false);
  assert.equal(/[\u0000-\u0009\u000b-\u001f\u007f-\u009f]/.test(result.text + result.html), false,
    'Bodies may contain LF, with no other protocol controls');
  const publicCopy = result.subject + '\n' + result.text + '\n' + visible(result.html);
  assert.match(publicCopy, /\bCollect\b/); assert.equal(/Collect\s+Admin/i.test(publicCopy), false);
  assert.equal(/\b\d{6,10}\b|access_token|refresh_token|token_hash|code_challenge|otp_secret|supabase\.co\/auth\/v1/i.test(publicCopy), false);
  assert.equal(/<(?:script|iframe|object|embed|form|base|link)\b/i.test(result.html), false);
  assert.equal(/\son[a-z]+\s*=|javascript:|vbscript:|@import\b|http-equiv\s*=\s*["']?refresh/i.test(result.html), false);
  assert.equal(/\b(?:src|srcset|poster|background|action)\s*=\s*["']\s*(?:https?:)?\/\//i.test(result.html), false);
  assert.equal(/url\s*\(\s*["']?\s*(?:https?:)?\/\//i.test(result.html), false);
  const links = anchors(result.html), loginLinks = links.filter(link => link.href === origin + '/#/admin/login');
  assert.equal(loginLinks.length, 1, 'Exactly one ordinary Collect login CTA');
  assert.equal(loginLinks[0].label, 'Open Collect');
  assert.ok(links.every(link => link.href === origin + '/#/admin/login' || link.href === SUPPORT),
    'Only the retained ordinary login and optional approved support mailto are linked');
  assert.equal(visible(result.html).includes('/#/admin/login'), false);
  assert.equal(/https?:\/\//i.test(visible(result.html)), false, 'HTML must not display a long login URL');
  assert.deepEqual(result.text.match(/https?:\/\/\S+/g), [origin + '/#/admin/login'],
    'Plain-text fallback retains the exact ordinary login URL without token/query parameters');
}

test('actual Collect access-notice renderer content and destination boundary', async t => {
  await t.test('Collect identity, one ordinary CTA, safe support and readable plain-text fallback', () => {
    const result = renderAdminAccessNotice(ORIGIN); contentSafety(result);
    assert.equal(result.subject, 'Your invitation to Collect'); assert.equal(result.text, APPROVED_TEXT);
    assert.equal(createHash('sha256').update(result.html).digest('hex'), APPROVED_HTML_SHA256,
      'All rendered HTML bytes must match the approved body, including its final LF');
    assert.deepEqual(renderAdminAccessNotice(ORIGIN), result, 'No timestamp, OTP or per-call token is generated');
    assert.equal(result.text.includes(LOGIN), true);
  });
  await t.test('a distinct retained exact origin changes only the ordinary destination', () => {
    const alternate = 'https://qa-admin.collect.ikanisa.com';
    const production = renderAdminAccessNotice(ORIGIN), result = renderAdminAccessNotice(alternate);
    contentSafety(result, alternate); assert.equal(result.subject, production.subject);
    assert.equal(result.text.replaceAll(alternate, ORIGIN), production.text);
    assert.equal(result.html.replaceAll(alternate, ORIGIN), production.html);
  });
  await t.test('HTML attribute escaping covers metacharacters even in an exact HTTPS origin', () => {
    const origin = 'https://a$&b.example.invalid';
    const result = renderAdminAccessNotice(origin);
    assert.equal(result.text.includes(origin + '/#/admin/login'), true);
    const links = anchors(result.html);
    assert.equal(links.filter(link => link.href === 'https://a$&amp;b.example.invalid/#/admin/login').length, 1);
    assert.equal(links.some(link => link.href === origin + '/#/admin/login'), false);
    assert.equal(/\son[a-z]+\s*=|javascript:/i.test(result.html), false);
  });
  for (const [name, origin] of [
    ['HTTP', 'http://platform-admin.collect.ikanisa.com'],
    ['protocol relative', '//platform-admin.collect.ikanisa.com'],
    ['credentials', 'https://user:secret@platform-admin.collect.ikanisa.com'],
    ['trailing path', ORIGIN + '/'], ['extra path', ORIGIN + '/unapproved'],
    ['query', ORIGIN + '?token=synthetic'], ['fragment', ORIGIN + '#unapproved'],
    ['LF', ORIGIN + '\n'], ['NUL', ORIGIN + '\u0000'], ['C1', ORIGIN + '\u0085'],
    ['JavaScript', 'javascript:alert(1)'], ['non-string', {origin: ORIGIN}],
  ]) await t.test('unsafe/non-exact origin refused: ' + name, () => {
    assert.throws(() => renderAdminAccessNotice(origin));
  });
});
