// Exercise the real HTTP fixture's boundaries before it is used in a browser.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createLocalBrowserFixture } from '../qa/local_browser_api_fixture.mjs';

const fixture = createLocalBrowserFixture();
const server = createServer(async (request, response) => {
  let bytes = '';
  for await (const chunk of request) bytes += chunk;
  const handled = await fixture.handle(request, response,
    new URL(request.url, 'http://127.0.0.1').pathname, bytes ? JSON.parse(bytes) : {});
  if (!handled) { response.writeHead(404); response.end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
let passed = 0;
const check = (condition) => { assert(condition); passed++; };
async function request(path, payload, token) {
  const response = await fetch(origin + path, {
    method: 'POST', headers: { 'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(payload),
  });
  return { status: response.status, body: await response.json() };
}
try {
  check((await request('/auth/v1/otp', { email: 'operator-a@example.invalid', create_user: false })).status === 200);
  for (const payload of [
    { phone: '+250788969001', create_user: false },
    { email: 'unapproved@example.invalid', create_user: false },
    { email: 'operator-a@example.invalid', create_user: true },
    { email: 'operator-a@example.invalid' },
  ]) check((await request('/auth/v1/otp', payload)).status === 403);
  for (const payload of [
    { email: 'operator-a@example.invalid', type: 'sms', token: '123456' },
    { email: 'operator-a@example.invalid', type: 'email', token: '000000' },
    { email: 'operator-a@example.invalid', type: 'email', token: '123456', phone: '+250788969001' },
  ]) check((await request('/auth/v1/verify', payload)).status === 403);
  const a = await request('/auth/v1/verify', { email: 'operator-a@example.invalid', type: 'email', token: '123456' });
  const b = await request('/auth/v1/verify', { email: 'operator-b@example.invalid', type: 'email', token: '123456' });
  check(a.status === 200 && b.status === 200 && a.body.user.id !== b.body.user.id);
  check(a.body.user.email === 'operator-a@example.invalid' && !!a.body.user.email_confirmed_at && !a.body.user.phone);
  check(a.body.access_token !== b.body.access_token);
  const approval = await request('/rest/v1/rpc/admin_get_operator_approval_v1', { p_user_id: a.body.user.id }, a.body.access_token);
  check(approval.status === 200 && approval.body.provider === 'email' && approval.body.mode === 'email' && approval.body.admin_access === true);
  check((await request('/rest/v1/rpc/admin_get_operator_approval_v1', { p_user_id: b.body.user.id }, a.body.access_token)).status === 403);
  check((await request('/rest/v1/rpc/admin_current_user', {}, 'synthetic-unissued-token')).status === 403);
  check((await request('/auth/v1/logout', {}, a.body.access_token)).status === 200);
  check((await request('/rest/v1/rpc/admin_current_user', {}, a.body.access_token)).status === 403);
  check((await request('/rest/v1/rpc/admin_current_user', {}, b.body.access_token)).status === 200);
  fixture.setRevoked(true);
  check((await request('/rest/v1/rpc/admin_current_user', {}, b.body.access_token)).status === 403);
  check(!JSON.stringify(fixture.calls).includes(a.body.access_token) && !JSON.stringify(fixture.calls).includes('operator-a@example.invalid'));
  console.log(JSON.stringify({ status: 'pass', passed, hosted_calls: 0, provider_calls: 0, database_calls: 0,
    scope: 'Synthetic loopback transport boundaries only; no current server authorization claim' }));
} finally { await new Promise(resolve => server.close(resolve)); }
