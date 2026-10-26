import {fixtureEnvironment,finishFixtureWork} from '../../../supabase/functions/_shared/tests/helpers/fenced-unit.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash, createHmac, randomUUID} from 'node:crypto';
import {fixture, admin, authorization, setupMfa, totp} from './support/auth_fixture.mjs';
import {functionRpc} from '../../../supabase/functions/_shared/domain/roster.js';
import {createRosterDecoderBridge} from '../../../supabase/functions/_shared/roster_decoder_bridge.mjs';

// Execute the actual Supabase caller and bridge against the existing isolated
// D1/trigger harness. Every decoder/provider transport is controlled in process.
// Signed parser summaries and header fixtures do not prove real decoder safety,
// provider/model capability, hosted configuration, or PostgreSQL admission.
const hash = value => createHash('sha256').update(value).digest('hex');
const key = Buffer.from(Array.from({length: 32}, (_, index) => index + 1)).toString('base64');
const secret = 'isolated-roster-supervisor-fixture-key-0123456789';
const build = 'a'.repeat(64);
const endpoint = 'https://decoder.example/decode';
const toolchain = {python: '3.12', pillow: '12.3.0', pypdfium2: '5.2.0',
  pypdf: '6.19.0', openpyxl: '3.1.5', defusedxml: '0.7.1'};
const encoder = new TextEncoder();

class PrivateObjects {
  constructor() { this.objects = new Map(); }
  async put(name, body) { this.objects.set(name, body); return {key: name}; }
  async get(name) {
    const body = this.objects.get(name);
    return body === undefined ? null : {size: encoder.encode(body).byteLength, text: async () => body};
  }
}

async function base(t) {
  const f = await fixture();
  t.after(() => f.close());
  const operator = await admin(f);
  await f.db.prepare('INSERT INTO admin_grants(user_id,permission,granted_at) VALUES(?,?,?)')
    .bind(operator.id, 'roster.import', new Date().toISOString()).run();
  let session = await f.login(operator.identity);
  const mfa = await setupMfa(f, session);
  const verified = await f.call('/v1/auth/mfa/verify', {factor_id: mfa.factor.id,
    challenge_id: mfa.challenge.id, code: totp(mfa.factor.totp.secret)}, authorization(session));
  assert.equal(verified.status, 200);
  session = verified.body;
  const found = await f.actor(session);
  assert.equal(found.status, 200);
  const actor = {...found.body, permissions: new Set(found.body.permissions)};
  const policy = {schema_version: 1, status: 'approved', enabled: true,
    purpose: 'collect_roster_pdf_image_extraction', provider: 'openai',
    responses_endpoint: 'https://api.openai.com/v1/responses',
    decoder_url: 'https://roster-decoder.internal/decode', approval_id: randomUUID(),
    approval_evidence_sha256: 'b'.repeat(64), decoder_build_sha256: build,
    project_id: 'fixture-project', organization_id: 'fixture-organization', model: 'fixture-vision-model',
    processing_region_evidence_ref: 'fixture:processing', retention_evidence_ref: 'fixture:retention',
    decoder_processor_evidence_ref: 'fixture:decoder', decoder_region_evidence_ref: 'fixture:region',
    decoder_retention_evidence_ref: 'fixture:decoder-retention',
    approved_at: new Date(Date.now() - 60000).toISOString(),
    valid_until: new Date(Date.now() + 3600000).toISOString()};
  const raw = JSON.stringify(policy);
  const env = {DB: f.db, PRIVATE_MEDIA: new PrivateObjects(), DATA_ENCRYPTION_KEY: key,
    DATA_KEY_ID: 'auth-test-v1', ROSTER_AI_APPROVAL_JSON: raw, ROSTER_AI_APPROVAL_SHA256: hash(raw),
    ROSTER_DECODER_BUILD_SHA256: build, OPENAI_PROJECT_ID: policy.project_id,
    OPENAI_ORGANIZATION_ID: policy.organization_id, ROSTER_AI_MODEL: policy.model,
    OPENAI_API_KEY: 'isolated-fixture-provider-key-0123456789'};
  fixtureEnvironment(env);t.after(()=>finishFixtureWork());
  return {f, actor, session, env, policy};
}

function source(kind = 'image', large = false) {
  const bytes = kind === 'pdf'
    ? Buffer.from('%PDF-1.7\n' + (large ? 'controlled-fixture\n'.repeat(17000) : 'controlled-fixture'))
    : Buffer.from([137, 80, 78, 71, 13, 10, 26, 10, 0]);
  return {contract_version: 1, request_id: randomUUID(), source_type: kind,
    filename: kind === 'pdf' ? 'members.pdf' : 'members.png',
    mime_type: kind === 'pdf' ? 'application/pdf' : 'image/png',
    content_base64: bytes.toString('base64'), ai_consent: true,
    consent_version: 'roster-ai-extraction-v1'};
}

function responseRows() {
  return {object: 'response', status: 'completed', error: null, incomplete_details: null, tools: [],
    output: [{type: 'message', role: 'assistant', status: 'completed', content: [{type: 'output_text',
      annotations: [], text: JSON.stringify({rows: [{source_row: 1, member_name: 'Alice Smith',
        momo_name: 'Alice Smith', momo_number: '0788123456', confidence: 1}]})}]}]};
}

function transports(t, b, {badSignature = false, afterDecode, providerReply} = {}) {
  const seen = {decoder: [], provider: []};
  const previous = globalThis.fetch;
  t.after(() => { globalThis.fetch = previous; });
  globalThis.fetch = async (url, init) => {
    assert.equal(url, 'https://api.openai.com/v1/responses', 'No uncontrolled outbound transport');
    seen.provider.push(JSON.parse(init.body));
    return providerReply ? providerReply() : Response.json(responseRows());
  };
  b.env.ROSTER_DECODER = createRosterDecoderBridge({protocol: 'roster-hmac-v1', endpoint,
    secret, approvedBuildSha256: build, fetchImpl: async (url, init) => {
      assert.equal(url, endpoint);
      assert.equal(init.redirect, 'error');
      assert.equal(init.headers.Authorization,
        'Roster-HMAC ' + createHmac('sha256', secret).update(init.body).digest('hex'));
      assert.equal(Number(init.headers['Content-Length']), Buffer.byteLength(init.body));
      const wire = JSON.parse(init.body);
      assert.deepEqual(Object.keys(wire).sort(), ['request_id', 'reservation_id', 'source_sha256',
        'mime', 'kind', 'content_base64', 'policy_version', 'nonce', 'issued_at'].sort());
      seen.decoder.push(wire);
      const payload = JSON.stringify({contract_version: 1, request_id: wire.request_id,
        reservation_id: wire.reservation_id, nonce: wire.nonce, issued_at: Math.floor(Date.now() / 1000),
        kind: wire.kind, mime: wire.mime, decoder_build_sha256: build, ok: true,
        policy_version: 'collect-roster-decoder-v1', toolchain,
        source_sha256: wire.source_sha256, source_size: Buffer.from(wire.content_base64, 'base64').length,
        derived_sha256: null, frames: wire.kind === 'image' ? 1 : 0,
        pages: wire.kind === 'pdf' ? 1 : 0, pixels: 1,
        expanded_bytes: wire.kind === 'image' ? 4 : 0, derived_content: null});
      if (afterDecode) await afterDecode(wire);
      return Response.json({payload, signature: badSignature ? '0'.repeat(64)
        : createHmac('sha256', secret).update(payload).digest('hex')});
    }});
  return seen;
}

test('actual caller binds processing/import lineage and forwards signed original image', async t => {
  const b = await base(t), body = source(), seen = transports(t, b);
  const result = (await functionRpc('prepare-roster-import', body, b.env, b.actor)).value;
  const row = await b.f.db.prepare('SELECT * FROM roster_imports WHERE id=?').bind(result.import_id).first();
  const receipt = JSON.parse(row.source_receipt_json);
  const processing = await b.f.db.prepare('SELECT * FROM roster_processing_records WHERE import_id=?')
    .bind(row.id).first();
  assert.equal(seen.decoder.length, 1);
  assert.equal(seen.decoder[0].request_id, receipt.extraction_id);
  assert.equal(seen.decoder[0].request_id, processing.id);
  assert.notEqual(seen.decoder[0].request_id, body.request_id);
  assert.equal(seen.decoder[0].reservation_id, row.id);
  assert.equal(seen.decoder[0].source_sha256, row.source_sha256);
  assert.equal(processing.policy_sha256, b.env.ROSTER_AI_APPROVAL_SHA256);
  assert.equal(processing.approval_id, b.policy.approval_id);
  assert.equal(processing.decoder_build_sha256, build);
  assert.deepEqual(seen.provider[0].input[0].content,
    [{type: 'input_image', image_url: 'data:image/png;base64,' + body.content_base64}]);
  assert.equal(seen.provider[0].store, false);
  assert.equal(seen.provider[0].model, b.policy.model);
  assert.equal(result.requires_human_review, true);
  assert.equal(result.can_submit, false);
  assert.equal(row.state, 'preview_ready');
});

test('PDF larger than old decode cap reaches Responses only as fixed original input_file', async t => {
  const b = await base(t), body = source('pdf', true), seen = transports(t, b);
  assert.ok(body.content_base64.length > 262144);
  const result = (await functionRpc('prepare-roster-import', body, b.env, b.actor)).value;
  assert.deepEqual(seen.provider[0].input[0].content, [{type: 'input_file', filename: 'roster.pdf',
    file_data: 'data:application/pdf;base64,' + body.content_base64}]);
  assert.equal(result.source_sha256, hash(Buffer.from(body.content_base64, 'base64')));
  assert.equal(result.requires_human_review, true);
});

test('Responses result cap stays 262144 after successful larger PDF decode', async t => {
  const b = await base(t), body = source('pdf', true);
  const seen = transports(t, b, {providerReply: () => Response.json({padding: 'x'.repeat(262144)})});
  await assert.rejects(() => functionRpc('prepare-roster-import', body, b.env, b.actor),
    error => error.code === 'roster_provider_response_too_large');
  assert.equal(seen.decoder.length, 1);
  assert.equal(seen.provider.length, 1);
  assert.equal((await b.f.db.prepare('SELECT state FROM roster_imports').first()).state, 'ambiguous');
});

test('failed supervisor authentication never dispatches extraction', async t => {
  const b = await base(t), seen = transports(t, b, {badSignature: true});
  await assert.rejects(() => functionRpc('prepare-roster-import', source(), b.env, b.actor),
    error => error.code === 'roster_decoder_authentication_failed');
  assert.equal(seen.provider.length, 0);
  assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM roster_dispatch_phases WHERE phase=?')
    .bind('extract').first()).n, 0);
  assert.equal((await b.f.db.prepare('SELECT state FROM roster_imports').first()).state, 'ambiguous');
});

test('explicit consent remains required before source retention or decoder dispatch', async t => {
  const b = await base(t), seen = transports(t, b);
  await assert.rejects(() => functionRpc('prepare-roster-import', {...source('pdf'), ai_consent: false},
    b.env, b.actor), error => error.code === 'roster_confirmation_required');
  assert.equal(seen.decoder.length, 0);
  assert.equal(seen.provider.length, 0);
  assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM roster_imports').first()).n, 0);
});

test('approval replacement during decode prevents provider dispatch', async t => {
  const b = await base(t);
  const seen = transports(t, b, {afterDecode: () => { b.env.ROSTER_AI_APPROVAL_SHA256 = 'c'.repeat(64); }});
  await assert.rejects(() => functionRpc('prepare-roster-import', source(), b.env, b.actor),
    error => error.code === 'roster_extraction_unavailable');
  assert.equal(seen.decoder.length, 1);
  assert.equal(seen.provider.length, 0);
  assert.equal((await b.f.db.prepare('SELECT state FROM roster_imports').first()).state, 'ambiguous');
});

test('session revocation during decode is enforced by current database guard', async t => {
  const b = await base(t);
  const seen = transports(t, b, {afterDecode: () => b.f.db.prepare('UPDATE auth_sessions SET revoked_at=? WHERE id=?')
    .bind(new Date().toISOString(), b.actor.sessionId).run()});
  await assert.rejects(() => functionRpc('prepare-roster-import', source(), b.env, b.actor));
  assert.equal(seen.decoder.length, 1);
  assert.equal(seen.provider.length, 0);
  assert.equal((await b.f.db.prepare('SELECT state FROM roster_imports').first()).state, 'ambiguous');
});

for (const [name, corrupt] of [
  ['changed filename', item => ({...item, filename: 'members.pdf'})],
  ['changed source bytes', item => ({...item, file_data: 'data:application/pdf;base64,JVBERi0xLjc='})],
  ['remote URL', () => ({type: 'input_file', filename: 'roster.pdf', file_url: 'https://example.com/roster.pdf'})],
  ['file ID', () => ({type: 'input_file', filename: 'roster.pdf', file_id: 'file-fixture'})],
  ['additional file ID', item => ({...item, file_id: 'file-fixture'})],
]) {
  test('caller rejects PDF decoder content with ' + name, async t => {
    const b = await base(t), seen = transports(t, b), signed = b.env.ROSTER_DECODER;
    b.env.ROSTER_DECODER = {async fetch(request, context) {
      const direct = await (await signed.fetch(request, context)).json();
      direct.content[0] = corrupt(direct.content[0]);
      return Response.json(direct);
    }};
    await assert.rejects(() => functionRpc('prepare-roster-import', source('pdf'), b.env, b.actor),
      error => ['roster_decoder_lineage_invalid', 'roster_rows_invalid'].includes(error.code));
    assert.equal(seen.decoder.length, 1);
    assert.equal(seen.provider.length, 0);
    assert.equal((await b.f.db.prepare('SELECT state FROM roster_imports').first()).state, 'ambiguous');
  });
}

test('caller rejects input_file for an image reservation', async t => {
  const b = await base(t), seen = transports(t, b), signed = b.env.ROSTER_DECODER;
  b.env.ROSTER_DECODER = {async fetch(request, context) {
    const direct = await (await signed.fetch(request, context)).json();
    direct.content = [{type: 'input_file', filename: 'roster.pdf',
      file_data: 'data:application/pdf;base64,' + source().content_base64}];
    return Response.json(direct);
  }};
  await assert.rejects(() => functionRpc('prepare-roster-import', source(), b.env, b.actor),
    error => error.code === 'roster_decoder_lineage_invalid');
  assert.equal(seen.decoder.length, 1);
  assert.equal(seen.provider.length, 0);
});
