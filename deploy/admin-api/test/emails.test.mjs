import test from 'node:test';
import assert from 'node:assert/strict';
import { buildAccountEmail, buildTransactionalEmail } from '../src/emails.mjs';

const link = invite => `https://admin-preview.collect.ikanisa.com/#/admin/setup?token=${'0'.repeat(64)}&invite=${invite}`;
test('invitation has Collect branding and a real password button with matching plain-text fallback', () => {
  const message = buildAccountEmail({ kind: 'invite', link: link(true) });
  assert.equal(message.subject, 'Your invitation to Collect');
  assert.ok(message.html.includes('You have been invited to Collect.'));
  assert.ok(message.html.includes(`href="${link(true).replace('&', '&amp;')}"`));
  assert.match(message.html, />Set your password<\/a>/);
  assert.ok(!message.html.includes('Collect Admin'));
  assert.ok(!message.html.includes(`>${link(true)}<`));
  assert.ok(message.text.includes(link(true)));
  assert.ok(message.html.includes('24 hours'));
  assert.ok(message.html.includes('max-width:600px'));
  assert.ok(message.html.includes('max-width:620px'));
  assert.ok(message.html.includes('prefers-color-scheme:dark'));
  assert.ok(!/<script|<form|<iframe|<img/i.test(message.html));
});
test('reset email names Collect and preserves truthful expiry and password behavior', () => {
  const message = buildAccountEmail({ kind: 'reset', link: link(false) });
  assert.equal(message.subject, 'Reset your Collect password');
  assert.match(message.html, />Reset your password<\/a>/);
  assert.ok(message.html.includes('30 minutes'));
  assert.ok(message.html.includes('Your password will stay the same.'));
  assert.ok(!message.html.includes('24 hours'));
});
test('unsafe or malformed password URLs cannot enter an email', () => {
  for (const bad of [link(true).replace('https:', 'javascript:'), link(true).replace('admin-preview.collect.ikanisa.com', 'collect.ikanisa.com.attacker.invalid'), link(false), link(true).replace('0'.repeat(64), 'bad'), link(true).replace('/#/admin/setup', '/wrong#/admin/setup')]) {
    assert.throws(() => buildAccountEmail({ kind: 'invite', link: bad }));
  }
});
test('transactional content is escaped, preserves text and never generates arbitrary links', () => {
  const text = 'A <script>alert("x")</script> & receipt\n\nThanks.';
  const message = buildTransactionalEmail({ subject: 'Receipt <review>', text });
  assert.equal(message.text, text);
  assert.ok(message.html.includes('Receipt &lt;review&gt;'));
  assert.ok(message.html.includes('&lt;script&gt;'));
  assert.ok(!message.html.includes('<script>'));
  assert.throws(() => buildTransactionalEmail({ subject: 'Hello\nBcc: attacker', text }));
});
