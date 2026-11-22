import {fixtureEnvironment,finishFixtureWork} from '../../../supabase/functions/_shared/tests/helpers/fenced-unit.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash, createHmac, randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {fixture, admin, authorization, setupMfa, totp} from './support/auth_fixture.mjs';
import {functionRpc, rosterRpc} from '../../../supabase/functions/_shared/domain/roster.js';
import {assertMutationAdmission} from '../../../supabase/functions/_shared/domain/mutations.js';
import {attestAdminEmailAccount,bindAdminEmailActor} from '../../../supabase/functions/_shared/domain/admin_email_policy.js';
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

// The D1 harness predates the Supabase BFF's email proof. Model the verified
// BFF account explicitly and bind it through the real in-process policy; this
// fixture does not prove the BFF SQL or an actual email delivery.
function bindSyntheticEmailProof(actor, ageSeconds = 0) {
  const account = {id: randomUUID(), principal_id: actor.userId, auth_user_id: randomUUID(),
    auth_session_id: actor.sessionId, token_hash: hash('synthetic-bff-token'),
    public_id: randomUUID(), origin: 'https://admin.example.invalid', auth_version: 1};
  attestAdminEmailAccount(account, {contract_version: 1, public_session_id: account.public_id,
    email_verified_at: Math.floor(Date.now() / 1000) - ageSeconds, proof_id: randomUUID()});
  bindAdminEmailActor(actor, account);
  return actor;
}

// This cross-runtime fixture executes Supabase JS against legacy D1 schema.
// Supabase's email-proof guard deliberately binds a null MFA timestamp, whereas
// D1's unmodified trigger requires a verified MFA timestamp. Adapt only this
// test SQL bind, and require the actual D1-verified actor/factor; this does not
// replace the separate real-PostgreSQL email-proof acceptance path.
function d1MutationCompatibility(db, actor) {
  return new Proxy(db, {get(target, key) {
    if (key === 'prepare') return sql => {
      const statement = target.prepare(sql);
      if (!sql.startsWith('INSERT INTO mutation_guards(')) return statement;
      return {bind(...values) {
        if (values[11] === 2) {
          assert.equal(values[12], null);
          assert.equal(values[1], actor.userId);
          assert.equal(values[2], actor.sessionId);
          assert.equal(actor.assuranceLevel, 2);
          assert.ok(Number.isSafeInteger(actor.mfaAt));
          values[12] = actor.mfaAt;
        }
        return statement.bind(...values);
      }};
    };
    const value = Reflect.get(target, key, target);
    return typeof value === 'function' ? value.bind(target) : value;
  }});
}

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
  const actor = bindSyntheticEmailProof({...found.body, permissions: new Set(found.body.permissions)});
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
  const env = {DB: d1MutationCompatibility(f.db, actor), PRIVATE_MEDIA: new PrivateObjects(), DATA_ENCRYPTION_KEY: key,
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
    : Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=', 'base64');
  return {contract_version: 1, request_id: randomUUID(), source_type: kind,
    filename: kind === 'pdf' ? 'members.pdf' : 'members.png',
    mime_type: kind === 'pdf' ? 'application/pdf' : 'image/png',
    content_base64: bytes.toString('base64'), ai_consent: true,
    consent_version: 'roster-ai-extraction-v1'};
}

test('D1 compatibility fixture still requires a current verified factor', async t => {
  const b = await base(t), options = {permission: 'roster.import', minimumAssurance: 2, freshSeconds: 300};
  await assertMutationAdmission(b.env, b.actor, [], options);
  const current = await b.f.db.prepare('SELECT mfa_factor_id FROM auth_sessions WHERE id=?').bind(b.actor.sessionId).first();
  assert.ok(current.mfa_factor_id);
  await b.f.db.prepare("UPDATE auth_mfa_factors SET status='revoked',revoked_at=? WHERE id=?")
    .bind(Math.floor(Date.now() / 1000), current.mfa_factor_id).run();
  await assert.rejects(() => assertMutationAdmission(b.env, b.actor, [], options), error => error.code === 'mfa_required');
});

test('roster extraction rejects missing or stale email proof before external work', async t => {
  const b = await base(t);
  const unbound = {...b.actor};
  const stale = bindSyntheticEmailProof({...b.actor}, 301);
  for (const actor of [unbound, stale]) {
    await assert.rejects(() => functionRpc('prepare-roster-import', source(), b.env, actor),
      error => error.status === 403 && error.code === 'recent_email_sign_in_required');
  }
});

function responseRows() {
  return {object: 'response', status: 'completed', error: null, incomplete_details: null, tools: [],
    output: [{type: 'message', role: 'assistant', status: 'completed', content: [{type: 'output_text',
      annotations: [], text: JSON.stringify({rows: [{source_row: 1, member_name: 'Alice Smith',
        momo_name: 'Alice Smith', momo_number: '0788123456', confidence: 1}]})}]}]};
}

function transports(t, b, {badSignature = false, afterDecode, providerReply, imageFrames = 1} = {}) {
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
        derived_sha256: null, frames: wire.kind === 'image' ? imageFrames : 0,
        pages: wire.kind === 'pdf' ? 1 : 0, pixels: wire.kind === 'image' ? imageFrames : 1,
        expanded_bytes: wire.kind === 'image' ? imageFrames * 4 : 0, derived_content: null});
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

test('signed multi-frame attestation produces actionable refusal without provider dispatch', async t => {
  const b = await base(t), seen = transports(t, b, {imageFrames: 2});
  await assert.rejects(() => functionRpc('prepare-roster-import', source(), b.env, b.actor),
    error => error.status === 400 && error.code === 'roster_animated_image_unsupported' && /static image/i.test(error.message));
  assert.equal(seen.decoder.length, 1);
  assert.equal(seen.provider.length, 0);
  assert.equal((await b.f.db.prepare('SELECT count(*) AS n FROM roster_dispatch_phases WHERE phase=?')
    .bind('extract').first()).n, 0);
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


// The historical producer is a byte-exact test-only source snapshot. Only
// its six static import specifiers are relocated, in memory, to the current
// fixture's dependencies. D1 and all provider responses remain synthetic.
const legacyRosterUrl = new URL('../../../supabase/functions/_shared/tests/fixtures/roster-legacy-20261101.js.txt', import.meta.url);
const domainUrl = new URL('../../../supabase/functions/_shared/domain/', import.meta.url);
const legacyRosterSha256 = '352746a1bacae1a05d1f760739efff04b89e4b921b22e05d96d414a67b648c52';
async function legacyRoster() {
  let source = await readFile(legacyRosterUrl, 'utf8');
  assert.equal(hash(source), legacyRosterSha256, 'Historical producer bytes must match the pinned pre-candidate server');
  for (const dependency of ['./admin_email_policy.js', '../application-fence.js', './core.js',
    './encryption.js', './mutations.js', './native_integrity.js']) {
    const from = `from '${dependency}';`;
    assert.equal(source.split(from).length, 2, `Exactly one historical import for ${dependency}`);
    source = source.replace(from, `from '${new URL(dependency, domainUrl).href}';`);
  }
  return import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
}
function responseWithSourceRow(sourceRow) {
  const result = responseRows();
  const data = JSON.parse(result.output[0].content[0].text);
  data.rows[0].source_row = sourceRow;
  result.output[0].content[0].text = JSON.stringify(data);
  return Response.json(result);
}
function countPuts(b) {
  let count = 0;
  const put = b.env.PRIVATE_MEDIA.put.bind(b.env.PRIVATE_MEDIA);
  b.env.PRIVATE_MEDIA.put = async (...args) => { count++; return put(...args); };
  return () => count;
}
const editableProposal = p => p.rows.map(({member_name, momo_name, momo_number}) => ({member_name, momo_name, momo_number}));
async function countRows(b, table) {
  assert.ok(['roster_revisions', 'roster_processing_records', 'roster_dispatch_phases', 'roster_members', 'collections', 'request_receipts'].includes(table));
  return (await b.f.db.prepare(`SELECT count(*) AS n FROM ${table}`).first()).n;
}
async function initialCipher(b, importId) {
  return (await b.f.db.prepare('SELECT preview_ciphertext FROM roster_revisions WHERE import_id=? AND revision_number=1').bind(importId).first()).preview_ciphertext;
}
async function reviewCipher(b, revisionId) {
  return (await b.f.db.prepare('SELECT preview_ciphertext FROM roster_revisions WHERE id=?').bind(revisionId).first()).preview_ciphertext;
}
function interceptRosterRead(db, sqlToIntercept, change) {
  return new Proxy(db, {get(target, prop) {
    if (prop === 'prepare') return sql => {
      const stmt = target.prepare(sql);
      if (sql !== sqlToIntercept) return stmt;
      return {bind: (...args) => ({first: async () => change(await stmt.bind(...args).first())})};
    };
    const value = Reflect.get(target, prop, target);
    return typeof value === 'function' ? value.bind(target) : value;
  }});
}

test('v5: old oversized AI receipt replays its initial bytes across review and commit', async t => {
  const b = await base(t), body = source(), puts = countPuts(b);
  const seen = transports(t, b, {providerReply: () => responseWithSourceRow(2147483648)});
  const legacy = await legacyRoster();
  const initial = (await legacy.functionRpc('prepare-roster-import', body, b.env, b.actor)).value;
  assert.equal(initial.rows[0].source_row, 2147483648);
  assert.equal(initial.can_submit, false);
  const sourceKey = (await b.f.db.prepare('SELECT source_object_key FROM roster_imports WHERE id=?').bind(initial.import_id).first()).source_object_key;
  const sourceCipher = b.env.PRIVATE_MEDIA.objects.get(sourceKey);
  const originalCipher = await initialCipher(b, initial.import_id);
  assert.deepEqual((await functionRpc('prepare-roster-import', body, b.env, b.actor)).value, initial);

  const reviewRequest = {p_import_id: initial.import_id, p_parent_revision_id: initial.revision_id,
    p_request_id: randomUUID(), p_rows: editableProposal(initial), p_reason: 'Reviewed against the retained source.'};
  const reviewed = (await rosterRpc('admin_review_roster_import', reviewRequest, b.env, b.actor)).value;
  assert.equal(reviewed.can_submit, true);
  const reviewedCipher = await reviewCipher(b, reviewed.revision_id);
  assert.deepEqual((await functionRpc('prepare-roster-import', body, b.env, b.actor)).value, initial);
  const beforeCommit = (await rosterRpc('admin_get_roster_import', {p_import_id: initial.import_id}, b.env, b.actor)).value;
  assert.equal(beforeCommit.state, 'preview_ready');
  assert.deepEqual(beforeCommit.preview, reviewed);

  const commitRequest = {p_import_id: initial.import_id, p_revision_id: reviewed.revision_id,
    p_reviewed_rows_sha256: reviewed.reviewed_rows_sha256, p_request_id: randomUUID(),
    p_human_affirmed: true, p_mode: 'create', p_collection_id: null,
    p_title: 'Controlled roster', p_reason: 'Owner confirmed the reviewed roster.'};
  const committed = (await rosterRpc('admin_commit_roster_import', commitRequest, b.env, b.actor)).value;
  const status = (await rosterRpc('admin_get_roster_import', {p_import_id: initial.import_id}, b.env, b.actor)).value;
  assert.equal(status.state, 'committed');
  assert.deepEqual(status.preview, {...reviewed, can_submit: false});
  assert.deepEqual(status.commit, committed);
  const counts = Object.fromEntries(await Promise.all(['roster_revisions', 'roster_processing_records', 'roster_dispatch_phases', 'roster_members', 'collections', 'request_receipts'].map(async table => [table, await countRows(b, table)])));
  assert.equal(counts.roster_revisions, 2);
  assert.equal(counts.roster_processing_records, 1);
  assert.equal(counts.roster_dispatch_phases, 2);
  assert.equal(counts.roster_members, 1);
  assert.equal(counts.collections, 1);

  assert.deepEqual((await functionRpc('prepare-roster-import', body, b.env, b.actor)).value, initial);
  assert.deepEqual((await rosterRpc('admin_review_roster_import', reviewRequest, b.env, b.actor)).value, reviewed);
  const commitReplay = (await rosterRpc('admin_commit_roster_import', commitRequest, b.env, b.actor)).value;
  assert.deepEqual(commitReplay, {...committed, replayed: true});
  await assert.rejects(() => functionRpc('prepare-roster-import', {...body, filename: 'changed.png'}, b.env, b.actor),
    error => error.code === 'roster_request_conflict');
  await assert.rejects(() => rosterRpc('admin_review_roster_import', {...reviewRequest, p_reason: 'A different request body.'}, b.env, b.actor),
    error => error.code === 'roster_request_conflict');
  const otherSession = bindSyntheticEmailProof({...b.actor, sessionId: randomUUID()});
  await assert.rejects(() => functionRpc('prepare-roster-import', body, b.env, otherSession),
    error => error.code === 'roster_request_conflict');
  const staleProof = bindSyntheticEmailProof({...b.actor}, 301);
  await assert.rejects(() => functionRpc('prepare-roster-import', body, b.env, staleProof),
    error => error.code === 'recent_email_sign_in_required');
  assert.equal(await initialCipher(b, initial.import_id), originalCipher);
  assert.equal(await reviewCipher(b, reviewed.revision_id), reviewedCipher);
  assert.equal(b.env.PRIVATE_MEDIA.objects.get(sourceKey), sourceCipher);
  assert.equal(puts(), 1);
  assert.equal(seen.decoder.length, 1);
  assert.equal(seen.provider.length, 1);
  for (const [table, count] of Object.entries(counts)) assert.equal(await countRows(b, table), count, table);
});

test('v5: original safe integer maximum remains replayable after an old server created it', async t => {
  const b = await base(t), body = source(), puts = countPuts(b);
  const seen = transports(t, b, {providerReply: () => responseWithSourceRow(Number.MAX_SAFE_INTEGER)});
  const legacy = await legacyRoster();
  const initial = (await legacy.functionRpc('prepare-roster-import', body, b.env, b.actor)).value;
  const cipher = await initialCipher(b, initial.import_id);
  assert.equal(initial.rows[0].source_row, Number.MAX_SAFE_INTEGER);
  assert.deepEqual((await functionRpc('prepare-roster-import', body, b.env, b.actor)).value, initial);
  assert.equal(await initialCipher(b, initial.import_id), cipher);
  assert.equal(await countRows(b, 'roster_revisions'), 1);
  assert.equal(puts(), 1);
  assert.equal(seen.decoder.length, 1);
  assert.equal(seen.provider.length, 1);
});

test('v5: actual caller emits a synthetic status packet for the Dart consumer', async t => {
  const b = await base(t), body = source(), seen = transports(t, b);
  const initial = (await functionRpc('prepare-roster-import', body, b.env, b.actor)).value;
  const reviewRequest = {p_import_id: initial.import_id, p_parent_revision_id: initial.revision_id,
    p_request_id: randomUUID(), p_rows: editableProposal(initial), p_reason: 'Reviewed against the retained source.'};
  const reviewed = (await rosterRpc('admin_review_roster_import', reviewRequest, b.env, b.actor)).value;
  const before = (await rosterRpc('admin_get_roster_import', {p_import_id: initial.import_id}, b.env, b.actor)).value;
  const commitRequest = {p_import_id: initial.import_id, p_revision_id: reviewed.revision_id,
    p_reviewed_rows_sha256: reviewed.reviewed_rows_sha256, p_request_id: randomUUID(),
    p_human_affirmed: true, p_mode: 'create', p_collection_id: null,
    p_title: 'Controlled roster', p_reason: 'Owner confirmed the reviewed roster.'};
  const receipt = (await rosterRpc('admin_commit_roster_import', commitRequest, b.env, b.actor)).value;
  const after = (await rosterRpc('admin_get_roster_import', {p_import_id: initial.import_id}, b.env, b.actor)).value;
  assert.equal(before.state, 'preview_ready');
  assert.deepEqual(before.preview, reviewed);
  assert.equal(after.state, 'committed');
  assert.deepEqual(after.preview, {...reviewed, can_submit: false});
  assert.deepEqual(after.commit, receipt);
  assert.equal(seen.decoder.length, 1);
  assert.equal(seen.provider.length, 1);
  // Synthetic values only. The later Dart run must consume these exact bytes.
  const packet = {initial, reviewed, before, after, receipt};
  t.diagnostic('V5_ROSTER_PACKET_BASE64 ' + Buffer.from(JSON.stringify(packet)).toString('base64'));
});

test('v5: new AI preview accepts the client maximum and requests it in the schema', async t => {
  const b = await base(t), body = source(), seen = transports(t, b, {providerReply: () => responseWithSourceRow(2147483647)});
  const preview = (await functionRpc('prepare-roster-import', body, b.env, b.actor)).value;
  assert.equal(preview.rows[0].source_row, 2147483647);
  assert.equal(seen.provider[0].text.format.schema.properties.rows.items.properties.source_row.maximum, 2147483647);
  assert.equal(seen.provider.length, 1);
  assert.equal(await countRows(b, 'roster_revisions'), 1);
});

for (const [label, bad] of [['above maximum', 2147483648], ['safe integer maximum', Number.MAX_SAFE_INTEGER],
  ['unsafe integer', Number.MAX_SAFE_INTEGER + 1], ['fraction', 1.5], ['zero', 0], ['negative', -1], ['string', '1']]) {
  test(`v5: new AI output with ${label} fails locally without a second dispatch`, async t => {
    const b = await base(t), body = source(), puts = countPuts(b);
    const seen = transports(t, b, {providerReply: () => responseWithSourceRow(bad)});
    await assert.rejects(() => functionRpc('prepare-roster-import', body, b.env, b.actor),
      error => error.code === 'roster_provider_response_invalid' && error.status === 502);
    const saved = await b.f.db.prepare('SELECT * FROM roster_imports WHERE user_id=? AND request_id=?').bind(b.actor.userId, body.request_id).first();
    assert.equal(saved.state, 'ambiguous');
    assert.equal(saved.error_code, 'roster_provider_response_invalid');
    assert.equal(await countRows(b, 'roster_revisions'), 0);
    assert.equal(await countRows(b, 'roster_processing_records'), 1);
    assert.equal(await countRows(b, 'roster_dispatch_phases'), 2);
    const sourceCipher = b.env.PRIVATE_MEDIA.objects.get(saved.source_object_key);
    await assert.rejects(() => functionRpc('prepare-roster-import', body, b.env, b.actor),
      error => error.code === 'roster_extraction_failed' && error.status === 409);
    assert.equal((await b.f.db.prepare('SELECT state FROM roster_imports WHERE id=?').bind(saved.id).first()).state, 'ambiguous');
    assert.equal(await countRows(b, 'roster_revisions'), 0);
    assert.equal(await countRows(b, 'roster_processing_records'), 1);
    assert.equal(await countRows(b, 'roster_dispatch_phases'), 2);
    assert.equal(b.env.PRIVATE_MEDIA.objects.get(saved.source_object_key), sourceCipher);
    assert.equal(puts(), 1);
    assert.equal(seen.decoder.length, 1);
    assert.equal(seen.provider.length, 1);
  });
}

for (const [label, field, replacement, expected] of [
  ['missing original revision', 'missing', null, 'roster_preview_unacknowledged'],
  ['wrong original request', 'request_id', randomUUID(), 'roster_preview_unacknowledged'],
  ['wrong parent', 'parent_revision_id', randomUUID(), 'roster_preview_unacknowledged'],
  ['wrong human flag', 'human_reviewed', 1, 'roster_preview_unacknowledged'],
  ['wrong rows digest', 'rows_sha256', 'f'.repeat(64), 'roster_preview_unacknowledged'],
  ['corrupt ciphertext', 'preview_ciphertext', '{}', 'storage_unavailable'],
]) {
  test(`v5: ${label} is rejected without rewriting or dispatching`, async t => {
    const b = await base(t), body = source(), puts = countPuts(b), seen = transports(t, b);
    const initial = (await functionRpc('prepare-roster-import', body, b.env, b.actor)).value;
    const cipher = await initialCipher(b, initial.import_id);
    const sql = 'SELECT * FROM roster_revisions WHERE import_id=? AND revision_number=1';
    // An adapter-only read fault. The protected database row is never altered.
    b.env.DB = interceptRosterRead(b.env.DB, sql, row => field === 'missing' ? null : {...row, [field]: replacement});
    await assert.rejects(() => functionRpc('prepare-roster-import', body, b.env, b.actor),
      error => error.code === expected);
    assert.equal(await initialCipher(b, initial.import_id), cipher);
    assert.equal(await countRows(b, 'roster_revisions'), 1);
    assert.equal(await countRows(b, 'roster_processing_records'), 1);
    assert.equal(await countRows(b, 'roster_dispatch_phases'), 2);
    assert.equal(puts(), 1);
    assert.equal(seen.decoder.length, 1);
    assert.equal(seen.provider.length, 1);
  });
}


test('v5: unavailable old decryption key cannot cause replay or provider fallback', async t => {
  const b = await base(t), body = source(), puts = countPuts(b), seen = transports(t, b);
  const initial = (await functionRpc('prepare-roster-import', body, b.env, b.actor)).value;
  const cipher = await initialCipher(b, initial.import_id);
  b.env.DATA_KEY_ID = 'fixture-unavailable-key';
  await assert.rejects(() => functionRpc('prepare-roster-import', body, b.env, b.actor),
    error => error.code === 'key_unavailable');
  assert.equal(await initialCipher(b, initial.import_id), cipher);
  assert.equal(await countRows(b, 'roster_revisions'), 1);
  assert.equal(puts(), 1);
  assert.equal(seen.decoder.length, 1);
  assert.equal(seen.provider.length, 1);
});

test('v5: transient initial revision read failure stays unknown without dispatch', async t => {
  const b = await base(t), body = source(), puts = countPuts(b), seen = transports(t, b);
  const initial = (await functionRpc('prepare-roster-import', body, b.env, b.actor)).value;
  const cipher = await initialCipher(b, initial.import_id);
  const failure = new Error('synthetic temporary database read failure');
  b.env.DB = interceptRosterRead(b.env.DB,
    'SELECT * FROM roster_revisions WHERE import_id=? AND revision_number=1', () => { throw failure; });
  await assert.rejects(() => functionRpc('prepare-roster-import', body, b.env, b.actor), error => error === failure);
  assert.equal(await initialCipher(b, initial.import_id), cipher);
  assert.equal(await countRows(b, 'roster_revisions'), 1);
  assert.equal(puts(), 1);
  assert.equal(seen.decoder.length, 1);
  assert.equal(seen.provider.length, 1);
});

for (const scenario of ['revoked session', 'changed session', 'expired email attestation']) {
  test(`v5: ${scenario} during initial replay prevents preview release`, async t => {
    const b = await base(t), body = source(), puts = countPuts(b), seen = transports(t, b);
    const initial = (await functionRpc('prepare-roster-import', body, b.env, b.actor)).value;
    const cipher = await initialCipher(b, initial.import_id);
    let barrier = false;
    b.env.DB = interceptRosterRead(b.env.DB,
      'SELECT * FROM roster_revisions WHERE import_id=? AND revision_number=1', async row => {
        assert.equal(barrier, false); barrier = true;
        if (scenario === 'revoked session') {
          const result = await b.f.db.prepare("UPDATE auth_sessions SET revoked_at=?,revocation_reason='synthetic_roster_revocation' WHERE id=? AND revoked_at IS NULL")
            .bind(Math.floor(Date.now() / 1000), b.actor.sessionId).run();
          assert.equal(result.meta.changes, 1);
          const revoked = await b.f.db.prepare('SELECT revoked_at,revocation_reason FROM auth_sessions WHERE id=?').bind(b.actor.sessionId).first();
          assert.ok(revoked.revoked_at > 0);
          assert.equal(revoked.revocation_reason, 'synthetic_roster_revocation');
        } else if (scenario === 'changed session') {
          b.actor.sessionId = randomUUID();
        } else {
          bindSyntheticEmailProof(b.actor, 301);
        }
        return row;
      });
    await assert.rejects(() => functionRpc('prepare-roster-import', body, b.env, b.actor));
    assert.equal(barrier, true);
    assert.equal(await initialCipher(b, initial.import_id), cipher);
    assert.equal(await countRows(b, 'roster_revisions'), 1);
    assert.equal(puts(), 1);
    assert.equal(seen.decoder.length, 1);
    assert.equal(seen.provider.length, 1);
  });
}

test('v5: new commit mode and destination must match the original reservation', async t => {
  const b = await base(t);
  const phones = ['0788123456', '0722123456', '0733123456', '0788456789'];
  let providerIndex = 0;
  const seen = transports(t, b, {providerReply: () => {
    const result = responseRows(), data = JSON.parse(result.output[0].content[0].text);
    data.rows[0].momo_number = phones[providerIndex++];
    result.output[0].content[0].text = JSON.stringify(data);
    return Response.json(result);
  }});
  async function prepareAndReview(body) {
    const initial = (await functionRpc('prepare-roster-import', body, b.env, b.actor)).value;
    const request = {p_import_id: initial.import_id, p_parent_revision_id: initial.revision_id,
      p_request_id: randomUUID(), p_rows: editableProposal(initial), p_reason: 'Reviewed source rows.'};
    return (await rosterRpc('admin_review_roster_import', request, b.env, b.actor)).value;
  }
  const requestFor = (preview, mode, collectionId) => ({p_import_id: preview.import_id,
    p_revision_id: preview.revision_id, p_reviewed_rows_sha256: preview.reviewed_rows_sha256,
    p_request_id: randomUUID(), p_human_affirmed: true, p_mode: mode,
    ...(collectionId === undefined ? {} : {p_collection_id: collectionId}),
    p_reason: 'Owner confirmed the reviewed roster.'});
  const create = await prepareAndReview(source());
  // An omitted unused target is equivalent to null for an unbound create.
  const created = (await rosterRpc('admin_commit_roster_import',
    {...requestFor(create, 'create', undefined), p_title: 'Controlled group'}, b.env, b.actor)).value;

  const unbound = await prepareAndReview(source());
  const before = {members: await countRows(b, 'roster_members'), receipts: await countRows(b, 'request_receipts')};
  await assert.rejects(() => rosterRpc('admin_commit_roster_import',
    {...requestFor(unbound, 'existing', created.collection_id), p_title: null}, b.env, b.actor),
    error => error.code === 'roster_collection_unavailable');
  assert.equal(await countRows(b, 'roster_members'), before.members);
  assert.equal(await countRows(b, 'request_receipts'), before.receipts);

  const bound = await prepareAndReview({...source(), collection_id: created.collection_id});
  const existing = requestFor(bound, 'existing', created.collection_id);
  for (const request of [
    {...existing, p_title: null, p_collection_id: randomUUID()},
    {...existing, p_title: 'Unused title'},
    {...existing, p_mode: 'create', p_collection_id: null, p_title: 'Retarget attempt'},
  ]) await assert.rejects(() => rosterRpc('admin_commit_roster_import', request, b.env, b.actor),
    error => error.code === 'roster_collection_unavailable');
  assert.equal(await countRows(b, 'roster_members'), before.members);
  assert.equal(await countRows(b, 'request_receipts'), before.receipts + 1); // Bound review only.
  // Omission and explicit null are both accepted for the unused title.
  const accepted = (await rosterRpc('admin_commit_roster_import', existing, b.env, b.actor)).value;
  assert.equal(accepted.collection_id, created.collection_id);
  const another = await prepareAndReview({...source(), collection_id: created.collection_id});
  const second = (await rosterRpc('admin_commit_roster_import',
    {...requestFor(another, 'existing', created.collection_id), p_title: null}, b.env, b.actor)).value;
  assert.equal(second.collection_id, created.collection_id);
  assert.equal(await countRows(b, 'roster_members'), before.members + 2);
  assert.equal(seen.provider.length, 4);
});

test('v5: a previously committed legacy request replays its original receipt', async t => {
  const b = await base(t), seen = transports(t, b);
  const groupInitial = (await functionRpc('prepare-roster-import', source(), b.env, b.actor)).value;
  const groupReview = (await rosterRpc('admin_review_roster_import', {p_import_id: groupInitial.import_id,
    p_parent_revision_id: groupInitial.revision_id, p_request_id: randomUUID(),
    p_rows: editableProposal(groupInitial), p_reason: 'Reviewed source.'}, b.env, b.actor)).value;
  const group = (await rosterRpc('admin_commit_roster_import', {p_import_id: groupInitial.import_id,
    p_revision_id: groupReview.revision_id, p_reviewed_rows_sha256: groupReview.reviewed_rows_sha256,
    p_request_id: randomUUID(), p_human_affirmed: true, p_mode: 'create', p_collection_id: null,
    p_title: 'Controlled group', p_reason: 'Confirmed source.'}, b.env, b.actor)).value;
  // The old server is used only to create the genuine synthetic historical
  // receipt; it is not part of the runtime or a historical production claim.
  const legacy = await legacyRoster();
  const oldBody = {...source(), source_type: 'text', content: 'Bob Jones,Bob Jones,0722123456'};
  delete oldBody.filename; delete oldBody.mime_type; delete oldBody.content_base64;
  delete oldBody.ai_consent; delete oldBody.consent_version;
  const oldInitial = (await legacy.functionRpc('prepare-roster-import', oldBody, b.env, b.actor)).value;
  const oldReview = (await legacy.rosterRpc('admin_review_roster_import', {p_import_id: oldInitial.import_id,
    p_parent_revision_id: oldInitial.revision_id, p_request_id: randomUUID(),
    p_rows: editableProposal(oldInitial), p_reason: 'Reviewed source.'}, b.env, b.actor)).value;
  const oldRequest = {p_import_id: oldInitial.import_id, p_revision_id: oldReview.revision_id,
    p_reviewed_rows_sha256: oldReview.reviewed_rows_sha256, p_request_id: randomUUID(),
    p_human_affirmed: true, p_mode: 'existing', p_collection_id: group.collection_id,
    p_title: null, p_reason: 'Confirmed source.'};
  const oldReceipt = (await legacy.rosterRpc('admin_commit_roster_import', oldRequest, b.env, b.actor)).value;
  const members = await countRows(b, 'roster_members');
  const replay = (await rosterRpc('admin_commit_roster_import', oldRequest, b.env, b.actor)).value;
  assert.deepEqual(replay, {...oldReceipt, replayed: true});
  assert.equal(await countRows(b, 'roster_members'), members);
  assert.equal(seen.provider.length, 1);
});
