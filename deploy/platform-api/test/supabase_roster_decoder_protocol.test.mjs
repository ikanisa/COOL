import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHash, createHmac, webcrypto} from 'node:crypto';
import {createRosterDecoderBridge, RosterDecoderBridgeError, ROSTER_DECODER_BRIDGE_LIMITS} from '../../../supabase/functions/_shared/roster_decoder_bridge.mjs';

// Offline protocol fixtures only. The signed supervisor is modeled here; these
// tests do not run Python codecs, validate a deployed decoder, or send HTTP.
const ENDPOINT = 'https://decoder.collect.example/decode';
const LOGICAL_URL = 'https://roster-decoder.internal/decode';
const SECRET = 'synthetic-roster-hmac-secret-32-bytes-minimum';
const BUILD = 'b'.repeat(64);
const NOW = Date.parse('2026-10-20T12:00:00Z');
// The caller supplies receipt.extraction_id (processingId), not an HTTP request ID.
const REQUEST_ID = '11111111-1111-4111-8111-111111111111';
const RESERVATION_ID = '22222222-2222-4222-8222-222222222222';
const NONCES = ['33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444'];
const POLICY = 'collect-roster-decoder-v1';
const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const HEADER = 'Member name\tMoMo name\tMoMo number';
const TSV = HEADER + '\nSynthetic member\tSynthetic MoMo\t0780000000';
const TOOLCHAIN = Object.freeze({python: '3.12', pillow: '12.3.0', pypdfium2: '5.2.0', pypdf: '6.19.0', openpyxl: '3.1.5', defusedxml: '0.7.1'});
const SOURCE = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO3Z9ioAAAAASUVORK5CYII=', 'base64');
const PDF_SOURCE = Buffer.from('%PDF-1.7 synthetic offline protocol fixture');
const REQUEST_FIELDS = ['request_id', 'reservation_id', 'source_sha256', 'mime', 'kind', 'content_base64', 'policy_version', 'nonce', 'issued_at'].sort();
const sha = value => createHash('sha256').update(value).digest('hex');
const hmac = (value, secret = SECRET) => createHmac('sha256', Buffer.from(secret, 'utf8')).update(Buffer.from(value, 'utf8')).digest('hex');

function signed(payloadObject, {payload, signature, outer = {}, secret = SECRET} = {}) {
  const raw = payload ?? JSON.stringify(payloadObject);
  return new Response(JSON.stringify({payload: raw, signature: signature ?? hmac(raw, secret), ...outer}), {
    status: 200, headers: {'Content-Type': 'application/json', 'Cache-Control': 'no-store'},
  });
}

function attestation(request, {tsv = TSV} = {}) {
  const kind = request.kind;
  return {
    contract_version: 1, request_id: request.request_id, reservation_id: request.reservation_id,
    nonce: request.nonce, issued_at: Math.floor(NOW / 1000), kind, mime: request.mime,
    decoder_build_sha256: BUILD, ok: true, policy_version: POLICY, toolchain: {...TOOLCHAIN},
    source_sha256: request.source_sha256, source_size: Buffer.from(request.content_base64, 'base64').length,
    derived_sha256: kind === 'xlsx' ? sha(tsv) : null,
    frames: kind === 'image' ? 1 : 0, pages: kind === 'pdf' ? 1 : 0,
    pixels: kind === 'xlsx' ? 0 : 1, expanded_bytes: kind === 'image' ? 4 : 32,
    derived_content: kind === 'xlsx' ? tsv : null,
  };
}

function logical(body, {url = LOGICAL_URL, method = 'POST', contentType = 'application/json', signal} = {}) {
  return new Request(url, {method, headers: {'Content-Type': contentType},
    ...(['GET', 'HEAD'].includes(method) ? {} : {body: typeof body === 'string' ? body : JSON.stringify(body)}),
    ...(signal ? {signal} : {}),
  });
}

function fixture({mime = 'image/png', source = SOURCE, secret = SECRET, config = {}} = {}) {
  const input = {schema_version: 1, source_sha256: sha(source), decoder_build_sha256: BUILD,
    mime_type: mime, content_base64: Buffer.from(source).toString('base64')};
  const state = {calls: [], clock: NOW, respond: ({body}) => signed(attestation(body), {secret})};
  let nonceIndex = 0;
  const options = {
    protocol: 'roster-hmac-v1', endpoint: ENDPOINT, secret, approvedBuildSha256: BUILD,
    cryptoImpl: webcrypto, now: () => state.clock, nonceFactory: () => NONCES[nonceIndex++ % NONCES.length],
    fetchImpl: async (input, init) => {
      const request = new Request(input, init);
      const raw = await request.text();
      const body = JSON.parse(raw);
      const entry = {request, raw, body, init}; state.calls.push(entry);
      assert.equal(request.url, ENDPOINT);
      assert.equal(request.method, 'POST');
      assert.equal(request.headers.get('Content-Type'), 'application/json');
      assert.equal(request.headers.get('Content-Length'), String(Buffer.byteLength(raw, 'utf8')));
      assert.equal(request.headers.get('Authorization'), 'Roster-HMAC ' + hmac(raw, secret));
      assert.equal(request.redirect, 'error');
      assert.deepEqual(Object.keys(body).sort(), REQUEST_FIELDS);
      assert.equal(body.request_id, REQUEST_ID); assert.equal(body.reservation_id, RESERVATION_ID);
      assert.equal(body.policy_version, POLICY);
      assert.equal(body.issued_at, Math.floor(NOW / 1000));
      assert.equal(body.source_sha256, sha(source)); assert.equal(body.content_base64, Buffer.from(source).toString('base64'));
      assert.equal(body.mime, mime);
      assert.equal(body.kind, mime === XLSX_MIME ? 'xlsx' : mime === 'application/pdf' ? 'pdf' : 'image');
      assert.ok(request.signal instanceof AbortSignal);
      return state.respond(entry);
    }, ...config,
  };
  const bridge = createRosterDecoderBridge(options);
  return {input, state, options, bridge,
    call: (body = input, requestOptions = {}, context = {}) => bridge.fetch(logical(body, requestOptions), {
      requestId: REQUEST_ID, reservationId: RESERVATION_ID, ...context,
    }),
  };
}

function refusal(expected) {
  const codes = Array.isArray(expected) ? expected : [expected];
  return error => error instanceof RosterDecoderBridgeError && codes.includes(error.code) &&
    !error.message.includes(SECRET) && !error.message.includes('synthetic private transport detail');
}
const INVALID_RESPONSE = ['roster_decoder_response_invalid', 'roster_decoder_response_mismatch'];

test('single-frame image mapping follows exact signed bytes, request context and source lineage', async () => {
  const f = fixture();
  f.state.respond = ({body}) => {
    const payload = ' \n' + JSON.stringify(attestation(body), null, 2) + '\n';
    return signed(null, {payload});
  };
  const response = await f.call();
  assert.equal(response.status, 200); assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.deepEqual(await response.json(), {source_sha256: f.input.source_sha256, decoder_build_sha256: BUILD,
    content: [{type: 'input_image', image_url: 'data:image/png;base64,' + SOURCE.toString('base64')}]});
  assert.equal(f.state.calls.length, 1); assert.equal(f.state.calls[0].body.nonce, NONCES[0]);
});

test('verified XLSX maps its signed canonical TSV, including UTF-8, to input_text', async () => {
  const f = fixture({mime: XLSX_MIME, source: Buffer.from('PK\x03\x04synthetic-workbook')});
  const tsv = HEADER + '\nUmuryango é\tSynthetic MoMo\t0780000000';
  f.state.respond = ({body}) => signed(attestation(body, {tsv}));
  const response = await f.call();
  assert.deepEqual(await response.json(), {source_sha256: f.input.source_sha256, decoder_build_sha256: BUILD,
    content: [{type: 'input_text', text: tsv}]});
  assert.equal(f.state.calls.length, 1);
});

test('verified PDF maps exactly its original bytes to the fixed input_file contract', async () => {
  const f = fixture({mime: 'application/pdf', source: PDF_SOURCE});
  const response = await f.call();
  assert.equal(response.status, 200); assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.deepEqual(await response.json(), {source_sha256: sha(PDF_SOURCE), decoder_build_sha256: BUILD,
    content: [{type: 'input_file', filename: 'roster.pdf',
      file_data: 'data:application/pdf;base64,' + PDF_SOURCE.toString('base64')}]});
  assert.equal(f.state.calls.length, 1);
});

for (const [name, change] of [
  ['missing protocol without fallback', options => {delete options.protocol;}],
  ['protocol', options => {options.protocol = 'bearer';}],
  ['short UTF-8 key', options => {options.secret = 'x'.repeat(31);}],
  ['HTTP endpoint', options => {options.endpoint = 'http://decoder.collect.example/decode';}],
  ['endpoint credentials', options => {options.endpoint = 'https://user:synthetic@decoder.collect.example/decode';}],
  ['endpoint query', options => {options.endpoint = ENDPOINT + '?forward=1';}],
  ['endpoint fragment', options => {options.endpoint = ENDPOINT + '#fragment';}],
  ['wrong endpoint path', options => {options.endpoint = 'https://decoder.collect.example/other';}],
  ['unapproved build digest', options => {options.approvedBuildSha256 = 'not-a-sha';}],
]) {
  test('configuration rejects ' + name + ' without transport', () => {
    let calls = 0;
    const options = {protocol: 'roster-hmac-v1', endpoint: ENDPOINT, secret: SECRET,
      approvedBuildSha256: BUILD, fetchImpl: () => {calls++; throw new Error('must not dispatch');}, cryptoImpl: webcrypto};
    change(options);
    assert.throws(() => createRosterDecoderBridge(options), refusal('roster_decoder_config_invalid'));
    assert.equal(calls, 0);
  });
}

test('key minimum is measured in UTF-8 bytes, as in the actual supervisor', async () => {
  const secret = 'é'.repeat(16); assert.equal(Buffer.byteLength(secret), 32);
  const f = fixture({secret}); assert.equal((await f.call()).status, 200); assert.equal(f.state.calls.length, 1);
});

for (const [name, change] of [
  ['extra logical field', body => {body.extra = true;}],
  ['missing logical field', body => {delete body.mime_type;}],
  ['wrong schema', body => {body.schema_version = 2;}],
  ['malformed base64', body => {body.content_base64 = '!not-base64';}],
  ['noncanonical base64', body => {body.content_base64 = body.content_base64 + '\n';}],
  ['unsupported MIME', body => {body.mime_type = 'image/gif';}],
  ['empty source', body => {body.content_base64 = ''; body.source_sha256 = sha(Buffer.alloc(0));}],
]) {
  test('logical request rejects ' + name + ' before transport', async () => {
    const f = fixture(); const body = {...f.input}; change(body);
    await assert.rejects(f.call(body), refusal(['roster_decoder_request_invalid', 'roster_decoder_source_mismatch', 'roster_decoder_content_limit']));
    assert.equal(f.state.calls.length, 0);
  });
}

for (const [name, change] of [
  ['source digest', body => {body.source_sha256 = 'a'.repeat(64);}],
  ['approved build', body => {body.decoder_build_sha256 = 'a'.repeat(64);}],
]) {
  test('logical request rejects changed ' + name + ' before transport', async () => {
    const f = fixture(); const body = {...f.input}; change(body);
    await assert.rejects(f.call(body), refusal(['roster_decoder_source_mismatch', 'roster_decoder_request_invalid', 'roster_decoder_response_mismatch']));
    assert.equal(f.state.calls.length, 0);
  });
}

for (const requestOptions of [
  {url: 'https://other.example/decode'}, {url: LOGICAL_URL + '?extra=1'},
  {method: 'PUT'}, {method: 'GET'}, {contentType: 'text/plain'},
]) {
  test('logical URL/method/type is checked: ' + JSON.stringify(requestOptions), async () => {
    const f = fixture(); await assert.rejects(f.call(f.input, requestOptions), refusal('roster_decoder_request_invalid'));
    assert.equal(f.state.calls.length, 0);
  });
}

for (const context of [{requestId: 'not-a-uuid'}, {reservationId: 'not-a-uuid'}, {requestId: REQUEST_ID.toUpperCase().replace('1111', 'ABCD')}]) {
  test('canonical context UUIDs are required: ' + JSON.stringify(context), async () => {
    const f = fixture(); await assert.rejects(f.call(f.input, {}, context), refusal('roster_decoder_request_invalid'));
    assert.equal(f.state.calls.length, 0);
  });
}

test('malformed JSON, source beyond 5MiB and logical envelope beyond 8MiB do not dispatch', async () => {
  const malformed = fixture(); await assert.rejects(malformed.call('{'), refusal('roster_decoder_request_invalid'));
  assert.equal(malformed.state.calls.length, 0);
  const large = fixture({source: Buffer.alloc(5 * 1024 * 1024 + 1, 65)});
  await assert.rejects(large.call(), refusal(['roster_decoder_content_limit', 'roster_decoder_request_invalid']));
  assert.equal(large.state.calls.length, 0);
  const envelope = fixture(); await assert.rejects(envelope.call(' '.repeat(8 * 1024 * 1024 + 1)), refusal(['roster_decoder_content_limit', 'roster_decoder_request_invalid']));
  assert.equal(envelope.state.calls.length, 0);
});

for (const [field, value] of [
  ['request_id', RESERVATION_ID], ['reservation_id', REQUEST_ID], ['nonce', NONCES[1]],
  ['source_sha256', 'a'.repeat(64)], ['source_size', SOURCE.length + 1],
  ['decoder_build_sha256', 'a'.repeat(64)], ['policy_version', 'other-policy'],
  ['mime', 'image/jpeg'], ['kind', 'xlsx'], ['contract_version', 2], ['ok', false],
]) {
  test('valid HMAC does not bypass signed ' + field + ' binding', async () => {
    const f = fixture(); f.state.respond = ({body}) => signed({...attestation(body), [field]: value});
    await assert.rejects(f.call(), refusal(INVALID_RESPONSE)); assert.equal(f.state.calls.length, 1);
  });
}

for (const [name, mutate] of [
  ['extra inner field', body => {body.extra = true;}],
  ['missing inner field', body => {delete body.toolchain;}],
  ['changed toolchain', body => {body.toolchain.pillow = 'unapproved';}],
  ['extra toolchain field', body => {body.toolchain.extra = 'unapproved';}],
  ['noninteger metrics', body => {body.pixels = 1.5;}],
  ['inconsistent image metrics', body => {body.expanded_bytes = 5;}],
  ['unexpected image text', body => {body.derived_content = 'unapproved OCR'; body.derived_sha256 = sha(body.derived_content);}],
]) {
  test('signed response rejects ' + name, async () => {
    const f = fixture(); f.state.respond = ({body}) => {const result = attestation(body); mutate(result); return signed(result);};
    await assert.rejects(f.call(), refusal([...INVALID_RESPONSE, 'roster_decoder_content_limit'])); assert.equal(f.state.calls.length, 1);
  });
}

for (const delta of [-31, 31]) {
  test('signed response outside freshness window is rejected (' + delta + 's)', async () => {
    const f = fixture(); f.state.respond = ({body}) => signed({...attestation(body), issued_at: Math.floor(NOW / 1000) + delta});
    await assert.rejects(f.call(), refusal('roster_decoder_response_stale')); assert.equal(f.state.calls.length, 1);
  });
}

for (const delta of [-30, 30]) {
  test('signed response at the inclusive freshness boundary is accepted (' + delta + 's)', async () => {
    const f = fixture(); f.state.respond = ({body}) => signed({...attestation(body), issued_at: Math.floor(NOW / 1000) + delta});
    assert.equal((await f.call()).status, 200); assert.equal(f.state.calls.length, 1);
  });
}

test('noninteger response timestamp is not accepted as a date', async () => {
  const f = fixture(); f.state.respond = ({body}) => signed({...attestation(body), issued_at: Math.floor(NOW / 1000) + 0.5});
  await assert.rejects(f.call(), refusal([...INVALID_RESPONSE, 'roster_decoder_response_stale'])); assert.equal(f.state.calls.length, 1);
});

for (const [name, respond] of [
  ['extra envelope field', ({body}) => signed(attestation(body), {outer: {extra: true}})],
  ['wrong signature', ({body}) => signed(attestation(body), {signature: '0'.repeat(64)})],
  ['wrong signing secret', ({body}) => signed(attestation(body), {secret: SECRET + '-other'})],
  ['signature for different exact payload bytes', ({body}) => {
    const result = attestation(body); return signed(null, {payload: JSON.stringify(result, null, 2), signature: hmac(JSON.stringify(result))});
  }],
  ['nonstring signed payload', () => new Response(JSON.stringify({payload: {}, signature: '0'.repeat(64)}), {headers: {'Content-Type': 'application/json'}})],
  ['invalid outer JSON', () => new Response('{', {headers: {'Content-Type': 'application/json'}})],
]) {
  test('response authentication rejects ' + name, async () => {
    const f = fixture(); f.state.respond = respond;
    await assert.rejects(f.call(), refusal(['roster_decoder_response_invalid', 'roster_decoder_authentication_failed']));
    assert.equal(f.state.calls.length, 1);
  });
}

test('previous signed response cannot satisfy a fresh nonce and transport is never retried', async () => {
  const f = fixture(); let previous;
  f.state.respond = ({body}) => {previous = attestation(body); return signed(previous);};
  assert.equal((await f.call()).status, 200);
  f.state.respond = () => signed(previous);
  await assert.rejects(f.call(), refusal('roster_decoder_response_mismatch'));
  assert.equal(f.state.calls.length, 2); assert.notEqual(f.state.calls[0].body.nonce, f.state.calls[1].body.nonce);
});

test('nonce factory reuse is refused before a second transport', async () => {
  const f = fixture({config: {nonceFactory: () => NONCES[0]}});
  assert.equal((await f.call()).status, 200);
  await assert.rejects(f.call(), refusal('roster_decoder_nonce_reused')); assert.equal(f.state.calls.length, 1);
});

test('attested animated image remains unavailable', async () => {
  const animated = fixture(); animated.state.respond = ({body}) => signed({...attestation(body), frames: 2});
  await assert.rejects(animated.call(), refusal('roster_decoder_content_unavailable')); assert.equal(animated.state.calls.length, 1);
});

for (const [field, value] of [
  ['request_id', RESERVATION_ID], ['reservation_id', REQUEST_ID], ['nonce', NONCES[1]],
  ['source_sha256', 'a'.repeat(64)], ['source_size', PDF_SOURCE.length + 1],
  ['decoder_build_sha256', 'a'.repeat(64)], ['policy_version', 'other-policy'],
  ['mime', 'image/png'], ['kind', 'image'],
]) {
  test('PDF mapping requires signed ' + field + ' binding', async () => {
    const f = fixture({mime: 'application/pdf', source: PDF_SOURCE});
    f.state.respond = ({body}) => signed({...attestation(body), [field]: value});
    await assert.rejects(f.call(), refusal(INVALID_RESPONSE)); assert.equal(f.state.calls.length, 1);
  });
}

for (const [name, values] of [
  ['frames', {frames: 1}], ['zero pages', {pages: 0}], ['too many pages', {pages: 21}],
  ['zero pixels', {pixels: 0}], ['expanded byte ceiling', {expanded_bytes: 32 * 1024 * 1024 + 1}],
  ['invented derived text', {derived_content: 'invented OCR'}],
  ['invented derived hash', {derived_sha256: 'a'.repeat(64)}],
]) {
  test('PDF mapping refuses invalid signed safety metrics: ' + name, async () => {
    const f = fixture({mime: 'application/pdf', source: PDF_SOURCE});
    f.state.respond = ({body}) => signed({...attestation(body), ...values});
    await assert.rejects(f.call(), refusal(INVALID_RESPONSE)); assert.equal(f.state.calls.length, 1);
  });
}

test('previous signed PDF proof cannot satisfy a new processing nonce', async () => {
  const f = fixture({mime: 'application/pdf', source: PDF_SOURCE}); let previous;
  f.state.respond = ({body}) => {previous = attestation(body); return signed(previous);};
  assert.equal((await f.call()).status, 200);
  f.state.respond = () => signed(previous);
  await assert.rejects(f.call(), refusal('roster_decoder_response_mismatch'));
  assert.equal(f.state.calls.length, 2); assert.notEqual(f.state.calls[0].body.nonce, f.state.calls[1].body.nonce);
});

test('PDF original source hash mismatch and source above 5MiB never dispatch', async () => {
  const changed = fixture({mime: 'application/pdf', source: PDF_SOURCE});
  await assert.rejects(changed.call({...changed.input, source_sha256: 'a'.repeat(64)}), refusal('roster_decoder_source_mismatch'));
  assert.equal(changed.state.calls.length, 0);
  const large = fixture({mime: 'application/pdf', source: Buffer.alloc(5 * 1024 * 1024 + 1, 65)});
  await assert.rejects(large.call(), refusal('roster_decoder_request_invalid')); assert.equal(large.state.calls.length, 0);
});

for (const [name, tsv, digest] of [
  ['wrong derived digest', TSV, 'a'.repeat(64)],
  ['wrong TSV header', 'Other\tHeader\tFields\nA\tB\tC'],
  ['extra TSV columns', HEADER + '\nA\tB\tC\tD'],
  ['carriage return', HEADER + '\nA\rB\tC\tD'],
  ['NUL character', HEADER + '\nA\0B\tC\tD'],
  ['too many rows', HEADER + '\n' + Array(501).fill('A\tB\tC').join('\n')],
  ['UTF-8 text exceeds byte limit', HEADER + '\n' + 'é'.repeat(32000) + '\tB\tC'],
]) {
  test('signed XLSX rejects ' + name, async () => {
    const f = fixture({mime: XLSX_MIME, source: Buffer.from('PK\x03\x04synthetic-workbook')});
    f.state.respond = ({body}) => signed({...attestation(body, {tsv}), ...(digest ? {derived_sha256: digest} : {})});
    await assert.rejects(f.call(), refusal([...INVALID_RESPONSE, 'roster_decoder_content_limit'])); assert.equal(f.state.calls.length, 1);
  });
}

test('bounded signed payload and raw response refuse oversized data', async () => {
  const payload = fixture(); payload.state.respond = ({body}) => signed(null, {payload: JSON.stringify(attestation(body)) + ' '.repeat(560001)});
  await assert.rejects(payload.call(), refusal(['roster_decoder_content_limit', 'roster_decoder_response_invalid'])); assert.equal(payload.state.calls.length, 1);
  const wire = fixture(); wire.state.respond = () => new Response(' '.repeat(600001), {headers: {'Content-Type': 'application/json'}});
  await assert.rejects(wire.call(), refusal(['roster_decoder_content_limit', 'roster_decoder_response_invalid'])); assert.equal(wire.state.calls.length, 1);
});

for (const mime of ['image/png', 'application/pdf']) {
  test('full 5MiB attested ' + mime + ' fits the separate bounded decode envelope', async () => {
    // Synthetic bytes exercise bridge transport bounds; decoder codec safety is separate.
    const source = Buffer.alloc(5 * 1024 * 1024, 65);
    const f = fixture({mime, source});
    const response = await f.call(), raw = await response.text();
    assert.equal(ROSTER_DECODER_BRIDGE_LIMITS.sourceBytes, 5 * 1024 * 1024);
    assert.equal(ROSTER_DECODER_BRIDGE_LIMITS.directResponseBytes, 7_100_000);
    assert.ok(Buffer.byteLength(raw, 'utf8') > 262144, 'Decode cap must not inherit the smaller AI-response cap');
    assert.ok(Buffer.byteLength(raw, 'utf8') <= 7_100_000);
    const content = JSON.parse(raw).content;
    assert.deepEqual(content, mime === 'application/pdf'
      ? [{type: 'input_file', filename: 'roster.pdf', file_data: 'data:application/pdf;base64,' + source.toString('base64')}]
      : [{type: 'input_image', image_url: 'data:image/png;base64,' + source.toString('base64')}]);
    assert.equal(f.state.calls.length, 1);
  });
}

for (const status of [302, 401, 409, 422, 429, 503]) {
  test('HTTP ' + status + ' is unavailable with no redirect or automatic retry', async () => {
    const f = fixture(); f.state.respond = () => new Response(null, {status, headers: {Location: 'https://other.example/decode'}});
    await assert.rejects(f.call(), refusal('roster_decoder_unavailable')); assert.equal(f.state.calls.length, 1);
    assert.equal(f.state.calls[0].request.signal.aborted, true, 'Early refusal must close the transport');
  });
}

test('response Content-Type refusal closes transport without mapping content or retrying', async () => {
  const f = fixture(); f.state.respond = () => new Response('not JSON', {headers: {'Content-Type': 'text/plain'}});
  await assert.rejects(f.call(), refusal('roster_decoder_response_invalid')); assert.equal(f.state.calls.length, 1);
  assert.equal(f.state.calls[0].request.signal.aborted, true);
});

test('network errors are sanitized and never retried', async () => {
  const f = fixture(); f.state.respond = () => {throw new Error('synthetic private transport detail ' + SECRET);};
  await assert.rejects(f.call(), refusal('roster_decoder_unavailable')); assert.equal(f.state.calls.length, 1);
});

test('caller abort before dispatch and during transport never yields mapped content', async () => {
  const before = fixture(), early = new AbortController(); early.abort();
  await assert.rejects(before.call(before.input, {signal: early.signal}), refusal('roster_decoder_aborted')); assert.equal(before.state.calls.length, 0);
  const during = fixture(), controller = new AbortController();
  during.state.respond = ({request}) => new Promise((resolve, reject) => {
    request.signal.addEventListener('abort', () => reject(new DOMException('synthetic aborted transport', 'AbortError')), {once: true});
    controller.abort();
  });
  await assert.rejects(during.call(during.input, {signal: controller.signal}), refusal('roster_decoder_aborted')); assert.equal(during.state.calls.length, 1);
});

test('20-second transport timeout aborts once and its timer is cleared without waiting', {concurrency: false}, async () => {
  const originalSet = globalThis.setTimeout, originalClear = globalThis.clearTimeout;
  let timer, callback, cleared = false;
  globalThis.setTimeout = (fn, delay, ...args) => {
    const handle = originalSet(fn, delay, ...args);
    if (delay === 20000) {timer = handle; callback = () => fn(...args);}
    return handle;
  };
  globalThis.clearTimeout = handle => {if (handle === timer) cleared = true; return originalClear(handle);};
  try {
    const f = fixture();
    f.state.respond = ({request}) => new Promise((resolve, reject) => {
      assert.equal(typeof callback, 'function', 'The bridge must install its documented 20s timeout');
      request.signal.addEventListener('abort', () => reject(new DOMException('synthetic timeout', 'AbortError')), {once: true});
      callback();
    });
    await assert.rejects(f.call(), refusal('roster_decoder_aborted'));
    assert.equal(f.state.calls.length, 1); assert.equal(cleared, true);
  } finally {
    if (timer) originalClear(timer);
    globalThis.setTimeout = originalSet; globalThis.clearTimeout = originalClear;
  }
});

test('deadline still aborts a stalled response body after successful headers', {concurrency: false}, async () => {
  const originalSet = globalThis.setTimeout, originalClear = globalThis.clearTimeout;
  let timer, deadline, cleared = false, cancelled = false, pulls = 0;
  globalThis.setTimeout = (fn, delay, ...args) => {
    const handle = originalSet(fn, delay, ...args);
    if (delay === 20000) {timer = handle; deadline = () => fn(...args);}
    return handle;
  };
  globalThis.clearTimeout = handle => {if (handle === timer) cleared = true; return originalClear(handle);};
  try {
    const f = fixture();
    f.state.respond = () => new Response(new ReadableStream({
      pull() {
        pulls++;
        assert.equal(typeof deadline, 'function');
        deadline();
        // No bytes or EOF: successful headers must not defeat the deadline.
      },
      cancel() {cancelled = true;},
    }, {highWaterMark: 0}), {headers: {'Content-Type': 'application/json'}});
    await assert.rejects(f.call(), refusal('roster_decoder_aborted'));
    assert.equal(f.state.calls.length, 1);
    assert.equal(pulls, 1);
    assert.equal(cancelled, true);
    assert.equal(cleared, true);
    assert.equal(f.state.calls[0].request.signal.aborted, true);
  } finally {
    if (timer) originalClear(timer);
    globalThis.setTimeout = originalSet; globalThis.clearTimeout = originalClear;
  }
});
