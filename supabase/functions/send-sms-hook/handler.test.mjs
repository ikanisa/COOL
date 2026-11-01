import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac, createHash, randomBytes, webcrypto } from 'node:crypto';
import { createHandler } from './handler.mjs';

const NOW = 1793448000000;
const secretBytes = randomBytes(32);
const env = {
  APP_ENVIRONMENT: 'local', AUTH_PROJECT_ID: 'local-app',
  AUTH_SEND_SMS_SECRET: `v1,whsec_${secretBytes.toString('base64')}`,
  OPENSMS_BASE_URL: 'http://127.0.0.1:8787', OPENSMS_ALLOW_LOCAL_HTTP: 'true',
  OPENSMS_APPLICATION_ID: 'app_example',
  OPENSMS_APPLICATION_TOKEN: `app_${randomBytes(32).toString('base64url')}`,
  OPENSMS_SENDER_LABEL: 'Example App', OPENSMS_DISPATCH_TTL_SECONDS: '120',
};
const event = { user: { id: 'f744f76c-4b2e-4257-a9bd-fd07b972cdee', phone: '250788000001' }, sms: { otp: '571246', phone: '250788000001' } };
const sha256 = text => createHash('sha256').update(text).digest('hex');

function signed({ payload = event, raw = JSON.stringify(payload), id = 'msg_123456', timestamp = String(NOW / 1000), secret = secretBytes, headers = {}, method = 'POST' } = {}) {
  return new Request('http://localhost/send-sms-hook', {
    method, headers: {
      'content-type': 'application/json', 'webhook-id': id, 'webhook-timestamp': timestamp,
      'webhook-signature': `v1,${createHmac('sha256', secret).update(`${id}.${timestamp}.${raw}`).digest('base64')}`,
      ...headers,
    }, body: ['GET', 'HEAD'].includes(method) ? undefined : raw,
  });
}

function jobFrom(body, { state = 'accepted', availableAt = new Date(NOW).toISOString(), ...overrides } = {}) {
  const message = { ...body, application_id: env.OPENSMS_APPLICATION_ID, available_at: availableAt, campaign_id: null, state, cancel_requested: false, ...overrides };
  const fields = [message.message_id, message.application_id, message.kind, message.to, body.text, String(message.priority), message.not_after, message.available_at, message.campaign_id ?? ''];
  message.payload_digest = sha256('collect-sms-payload-v1\n' + fields.map(value => `${Buffer.byteLength(value)}:${value}`).join(''));
  message.text = '[OTP content hidden]';
  message.metadata = {};
  return message;
}

function service() {
  const jobs = new Map(), calls = [];
  return {
    jobs, calls,
    transport: async (url, options) => {
      calls.push({ url: String(url), ...options });
      assert.equal(options.redirect, 'error');
      assert.equal(options.headers.authorization, `Bearer ${env.OPENSMS_APPLICATION_TOKEN}`);
      assert.ok(options.signal instanceof AbortSignal);
      const path = new URL(url).pathname;
      if (options.method === 'GET') {
        const id = decodeURIComponent(path.slice('/v1/messages/'.length));
        const message = jobs.get(id);
        return Response.json(message ? { message, attempts: [], parts: [], history: [], audit: [] } : { error: { code: 'not_found' } }, { status: message ? 200 : 404 });
      }
      assert.equal(path, '/v1/messages');
      const body = JSON.parse(options.body);
      if (jobs.has(body.message_id)) return Response.json({ error: { code: 'idempotency_conflict' } }, { status: 409 });
      jobs.set(body.message_id, jobFrom(body));
      return Response.json({ message_id: body.message_id, state: 'accepted' }, { status: 202 });
    },
  };
}

function handler(service, overrides = {}, dependencies = {}) {
  return createHandler({ ...env, ...overrides }, { now: () => NOW, transport: service.transport, cryptography: webcrypto, ...dependencies });
}

test('valid signed OTP uses the actual OpenSMS transport contract and acknowledgement', async () => {
  const sms = service();
  const reply = await handler(sms)(signed());
  assert.equal(reply.status, 200);
  assert.deepEqual(await reply.json(), {});
  assert.equal(sms.calls.length, 2);
  const send = sms.calls[1], body = JSON.parse(send.body);
  assert.equal(body.kind, 'otp');
  assert.equal(body.to, '+250788000001');
  assert.equal(body.text, 'Example App: Your verification code is 571246. Do not share this code.');
  assert.equal(body.priority, 120);
  assert.equal(body.not_after, new Date(NOW + 120000).toISOString());
  assert.match(body.message_id, /^app_example:sbauth:[a-f0-9]{64}$/);
  assert.match(send.headers['idempotency-key'], /^sbauth-[a-f0-9]{64}$/);
  assert.ok(!sms.calls.some(call => call.url.includes('/otp/challenges')));
  assert.equal(reply.headers.get('cache-control'), 'no-store');
});

test('unsigned non-sending readiness probe returns401 and never calls OpenSMS', async () => {
  const sms = service();
  const reply = await handler(sms)(new Request('http://localhost/send-sms-hook', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' }));
  assert.equal(reply.status, 401);
  assert.deepEqual(await reply.json(), { error: { http_code: 401, message: 'Invalid hook signature.' } });
  assert.equal(sms.calls.length, 0);
});

test('signature verification binds the raw bytes, event ID and timestamp', async () => {
  for (const change of [
    { headers: { 'webhook-id': 'different_id' } },
    { headers: { 'webhook-timestamp': String(NOW / 1000 - 1) } },
    { headers: { 'webhook-signature': `v1,${randomBytes(32).toString('base64')}` } },
  ]) {
    const sms = service();
    assert.equal((await handler(sms)(signed(change))).status, 401);
    assert.equal(sms.calls.length, 0);
  }
  const request = signed();
  const tampered = new Request(request.url, { method: 'POST', headers: request.headers, body: JSON.stringify(event) + ' ' });
  const sms = service();
  assert.equal((await handler(sms)(tampered)).status, 401);
  assert.equal(sms.calls.length, 0);
});

test('old/future signatures and ID framing characters are rejected', async () => {
  for (const args of [
    { timestamp: String(NOW / 1000 - 301) }, { timestamp: String(NOW / 1000 + 301) },
    { id: 'msg.with.dot' }, { id: 'x'.repeat(129) }, { timestamp: '01' },
  ]) {
    const sms = service();
    assert.equal((await handler(sms)(signed(args))).status, 401);
    assert.equal(sms.calls.length, 0);
  }
});

test('signing-key rotation accepts either configured secret', async () => {
  const other = randomBytes(32);
  const sms = service();
  const secrets = `v1,whsec_${other.toString('base64')}|${env.AUTH_SEND_SMS_SECRET}`;
  assert.equal((await handler(sms, { AUTH_SEND_SMS_SECRET: secrets })(signed())).status, 200);
  assert.equal((await handler(sms, { AUTH_SEND_SMS_SECRET: secrets })(signed({ secret: other, id: 'another_event' }))).status, 200);
});

test('multiple signature candidates and unknown versions preserve supported verification', async () => {
  const request = signed();
  request.headers.set('webhook-signature', `v1,invalid v2,unrecognized ${request.headers.get('webhook-signature')}`);
  assert.equal((await handler(service())(request)).status, 200);
});

test('malformed payloads never reach the SMS API after successful signature verification', async () => {
  for (const payload of [
    null, [], {}, { ...event, sms: { ...event.sms, phone: '0788000001' } },
    { ...event, user: { id: 'invalid', phone: event.user.phone } },
    { ...event, sms: { ...event.sms, phone: '+250788000001\n' } },
    { ...event, sms: { ...event.sms, otp: 571246 } }, { ...event, sms: { ...event.sms, otp: '12345' } },
    { ...event, sms: { ...event.sms, otp: '12345678901' } }, { ...event, sms: { ...event.sms, otp: '12345x' } },
  ]) {
    const sms = service();
    assert.equal((await handler(sms)(signed({ payload }))).status, 400);
    assert.equal(sms.calls.length, 0);
  }
  assert.equal((await handler(service())(signed({ raw: '{bad json' }))).status, 400);
});

test('E164 phone with plus is preserved and no country is guessed', async () => {
  const sms = service();
  assert.equal((await handler(sms)(signed({ payload: { ...event, sms: { ...event.sms, phone: '+441234567890' } } }))).status, 200);
  assert.equal(JSON.parse(sms.calls[1].body).to, '+441234567890');
});

test('anonymous-account phone upgrade uses the signed new destination while user.phone is empty', async () => {
  const sms = service();
  const payload = {
    user: { ...event.user, phone: '', phone_change: '250788000002', is_anonymous: true },
    sms: { ...event.sms, phone: '250788000002' },
  };
  assert.equal((await handler(sms)(signed({ payload }))).status, 200);
  assert.equal(JSON.parse(sms.calls[1].body).to, '+250788000002');
});

test('phone-change OTP goes to signed sms.phone, never the account old phone', async () => {
  const sms = service();
  const payload = {
    user: { ...event.user, phone: '250788000001', phone_change: '250788000002' },
    sms: { ...event.sms, phone: '250788000002' },
  };
  assert.equal((await handler(sms)(signed({ payload }))).status, 200);
  assert.equal(JSON.parse(sms.calls[1].body).to, '+250788000002');
  assert.ok(!sms.calls[1].body.includes('+250788000001'));
});

test('signed sms.phone remains authoritative for MFA with a different account phone', async () => {
  const sms = service();
  const payload = { ...event, sms: { ...event.sms, phone: '+441234567890', sms_type: 'phone_challenge_mfa' } };
  assert.equal((await handler(sms)(signed({ payload }))).status, 200);
  assert.equal(JSON.parse(sms.calls[1].body).to, '+441234567890');
});

test('invalid or absent signed sms.phone never falls back to user.phone or phone_change', async () => {
  for (const phone of [undefined, null, '', 250788000002, '0788000002', '+250788000002\n', 'not-a-phone']) {
    const sms = service();
    const payload = { user: { ...event.user, phone_change: '250788000002' }, sms: { otp: event.sms.otp, ...(phone === undefined ? {} : { phone }) } };
    assert.equal((await handler(sms)(signed({ payload }))).status, 400);
    assert.equal(sms.calls.length, 0);
  }
});

test('body size is bounded with and without Content-Length', async () => {
  for (const headers of [{}, { 'content-length': '999999' }]) {
    const sms = service();
    const request = signed({ raw: 'x'.repeat(65537), headers });
    assert.equal((await handler(sms)(request)).status, 413);
    assert.equal(sms.calls.length, 0);
  }
});

test('unsupported method, content type, and browser Origin cannot submit SMS', async () => {
  const sms = service(), handle = handler(sms);
  assert.equal((await handle(signed({ method: 'GET' }))).status, 405);
  assert.equal((await handle(signed({ headers: { 'content-type': 'text/plain' } }))).status, 415);
  assert.equal((await handle(signed({ headers: { origin: 'https://app.example' } }))).status, 403);
  assert.equal(sms.calls.length, 0);
});

test('bad or privileged configuration fails closed without leaking the credential', async () => {
  for (const overrides of [
    { AUTH_SEND_SMS_SECRET: '' }, { AUTH_SEND_SMS_SECRET: 'v1,whsec_short' },
    { OPENSMS_APPLICATION_TOKEN: `root_${randomBytes(32).toString('base64url')}` },
    { OPENSMS_BASE_URL: 'https://user:password@sms.example.net' },
    { OPENSMS_BASE_URL: 'https://sms.example.net/v1' },
    { OPENSMS_BASE_URL: 'https://sms.example.net?token=secret' },
    { OPENSMS_BASE_URL: 'https://sms.example.invalid' },
    { OPENSMS_APPLICATION_ID: '' }, { AUTH_PROJECT_ID: '' },
    { OPENSMS_SENDER_LABEL: 'Bad\nlabel' }, { OPENSMS_DISPATCH_TTL_SECONDS: '301' },
  ]) {
    const sms = service();
    const reply = await handler(sms, overrides)(signed());
    assert.equal(reply.status, 503);
    assert.equal(await reply.text(), '{"error":{"http_code":503,"message":"SMS hook is not configured."}}');
    assert.equal(sms.calls.length, 0);
  }
});

test('HTTP requires local environment, explicit opt-in and a local/private host', async () => {
  for (const overrides of [
    { OPENSMS_ALLOW_LOCAL_HTTP: '' }, { APP_ENVIRONMENT: 'production' },
    { APP_ENVIRONMENT: 'staging' }, { OPENSMS_BASE_URL: 'http://203.0.113.3:8787' },
    { OPENSMS_BASE_URL: 'http://sms.example.net' },
  ]) assert.equal((await handler(service(), overrides)(signed())).status, 503);
  for (const host of ['host.docker.internal', 'localhost', '10.1.2.3', '192.168.1.2', '172.16.3.4', '[::1]']) {
    assert.equal((await handler(service(), { OPENSMS_BASE_URL: `http://${host}:8787` })(signed())).status, 200);
  }
  assert.equal((await handler(service(), { APP_ENVIRONMENT: 'production', OPENSMS_BASE_URL: 'https://sms.example.net' })(signed())).status, 200);
});

test('cold-start retries with a new signature timestamp reuse the durable accepted job', async () => {
  const sms = service();
  assert.equal((await handler(sms)(signed())).status, 200);
  assert.equal((await handler(sms, {}, { now: () => NOW + 10000 })(signed({ timestamp: String(NOW / 1000 + 10) }))).status, 200);
  assert.equal(sms.calls.filter(call => call.method === 'POST').length, 1);
  assert.equal(sms.calls.length, 3);
});

test('same event ID with a different signed OTP cannot acknowledge the original job', async () => {
  const sms = service(), handle = handler(sms);
  assert.equal((await handle(signed())).status, 200);
  assert.equal((await handle(signed({ payload: { ...event, sms: { ...event.sms, otp: '987654' } } }))).status, 409);
  assert.equal(sms.calls.filter(call => call.method === 'POST').length, 1);
});

test('provider acceptance followed by network failure is recovered without duplicate SMS', async () => {
  const sms = service();
  let loseReply = true;
  const transport = async (url, options) => {
    const reply = await sms.transport(url, options);
    if (loseReply && options.method === 'POST') { loseReply = false; throw new Error(`sensitive ${env.OPENSMS_APPLICATION_TOKEN} ${event.sms.otp}`); }
    return reply;
  };
  const handle = handler(sms, {}, { transport });
  const failed = await handle(signed());
  assert.equal(failed.status, 503);
  assert.ok(!(await failed.text()).includes(env.OPENSMS_APPLICATION_TOKEN));
  assert.equal((await handler(sms)(signed())).status, 200);
  assert.equal(sms.calls.filter(call => call.method === 'POST').length, 1);
});

test('concurrent cold handlers safely recover an idempotency conflict', async () => {
  const sms = service();
  let gets = 0, release;
  const firstGets = new Promise(resolve => { release = resolve; });
  const transport = async (url, options) => {
    if (options.method === 'GET' && ++gets <= 2) {
      if (gets === 2) release();
      await firstGets;
      return Response.json({}, { status: 404 });
    }
    return sms.transport(url, options);
  };
  const replies = await Promise.all([
    handler(sms, {}, { transport })(signed()),
    handler(sms, {}, { transport, now: () => NOW + 1000 })(signed({ timestamp: String(NOW / 1000 + 1) })),
  ]);
  assert.deepEqual(replies.map(reply => reply.status), [200, 200]);
  assert.equal(sms.jobs.size, 1);
});

test('failed, cancelled, uncertain or expired provider jobs are not acknowledged as success', async () => {
  for (const state of ['failed', 'partial', 'outcome_unknown', 'cancelled', 'expired']) {
    const sms = service();
    await handler(sms)(signed());
    for (const message of sms.jobs.values()) message.state = state;
    assert.equal((await handler(sms)(signed())).status, 503);
    assert.equal(sms.calls.filter(call => call.method === 'POST').length, 1);
  }
});

test('known job is validated against OpenSMS payload digest, namespace, and expiration', async () => {
  for (const change of [
    { payload_digest: '0'.repeat(64) }, { application_id: 'another_app' },
    { to: '+441234567890' }, { campaign_id: 'unexpected' }, { cancel_requested: true },
  ]) {
    const sms = service();
    await handler(sms)(signed());
    for (const message of sms.jobs.values()) Object.assign(message, change);
    assert.ok([409, 503].includes((await handler(sms)(signed())).status));
  }
  const sms = service();
  await handler(sms)(signed());
  assert.equal((await handler(sms, {}, { now: () => NOW + 121000 })(signed({ timestamp: String(NOW / 1000 + 121) }))).status, 503);
});

test('provider errors, redirects and malformed acknowledgements fail closed', async () => {
  for (const providerReply of [
    () => Response.json({ message_id: 'wrong', state: 'accepted' }, { status: 202 }),
    () => Response.json({ state: 'accepted' }, { status: 202 }),
    () => Response.json({}, { status: 200 }),
    () => Response.json({ message: `private ${event.sms.otp}` }, { status: 429 }),
    () => new Response('not JSON', { status: 202 }),
    () => new Response('x'.repeat(65537), { status: 202 }),
    () => new Response(null, { status: 302, headers: { location: 'https://attacker.example' } }),
  ]) {
    const sms = service();
    const transport = (url, options) => options.method === 'GET' ? Promise.resolve(Response.json({}, { status: 404 })) : Promise.resolve(providerReply());
    const reply = await handler(sms, {}, { transport })(signed());
    assert.equal(reply.status, 503);
    assert.ok(!(await reply.text()).includes(event.sms.otp));
  }
});

test('dispatch TTL stops an old, still-signature-valid event from creating a delayed OTP', async () => {
  const sms = service();
  assert.equal((await handler(sms)(signed({ timestamp: String(NOW / 1000 - 121) }))).status, 400);
  assert.equal(sms.calls.filter(call => call.method === 'POST').length, 0);
});

test('one total deadline aborts a stalled service and returns a safe hook error', async () => {
  let signal;
  const transport = (_url, options) => { signal = options.signal; return new Promise(() => {}); };
  const reply = await handler(service(), {}, { transport, timeoutMs: 15 })(signed());
  assert.equal(reply.status, 503);
  assert.ok(signal.aborted);
  assert.deepEqual(await reply.json(), { error: { http_code: 503, message: 'SMS service unavailable.' } });
});

test('a late GET result cannot cause a POST after the total deadline', async () => {
  const calls = [];
  let resolveGet;
  const transport = async (_url, options) => {
    calls.push(options.method);
    if (options.method === 'GET') return await new Promise(resolve => { resolveGet = resolve; });
    throw new Error('late sending must be blocked');
  };
  const reply = await handler(service(), {}, { transport, timeoutMs: 15 })(signed());
  assert.equal(reply.status, 503);
  resolveGet(Response.json({}, { status: 404 }));
  await new Promise(resolve => setTimeout(resolve, 5));
  assert.deepEqual(calls, ['GET']);
});

test('a stalled incoming body is cancelled at the same total deadline', async () => {
  const sms = service();
  let cancelled = false;
  const base = signed();
  const stream = new ReadableStream({ cancel() { cancelled = true; } });
  const request = new Request(base.url, { method: 'POST', headers: base.headers, body: stream, duplex: 'half' });
  const reply = await handler(sms, {}, { timeoutMs: 15 })(request);
  assert.equal(reply.status, 503);
  assert.ok(cancelled);
  assert.equal(sms.calls.length, 0);
});

test('project namespaces prevent one app event from deduplicating a different project', async () => {
  const sms = service();
  assert.equal((await handler(sms)(signed())).status, 200);
  assert.equal((await handler(sms, { AUTH_PROJECT_ID: 'local-second-app' })(signed())).status, 200);
  assert.equal(sms.jobs.size, 2);
});
