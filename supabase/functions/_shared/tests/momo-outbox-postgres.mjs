// Isolated PostgreSQL diagnostic for the actual receipt producer and worker.
// This is not a provider test or permission to activate receipt processing.
import assert from 'node:assert/strict';
import {digest} from '../domain/core.js';
import {encrypt} from '../domain/encryption.js';
import {MOMO_SCHEMA_VERSION,processMomoJob,processingInsert} from '../domain/momo_pipeline.js';

const stamp = () => new Date().toISOString();
const epoch = () => Math.floor(Date.now() / 1000);
const deferred = () => {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return {promise, resolve};
};

// Called only after the runner proves its dedicated loopback cluster identity
// and applies the exact reviewed synthetic migration fixture.
export async function inspectMomoOutboxOnPostgres({sql, db, member, sid}) {
  const account = crypto.randomUUID(), binding = crypto.randomUUID();
  const profile = {sender_allowlist: ['MTN MoMo'], currency_aliases: ['RWF'],
    incoming_prefixes: ['You have received'], transaction_id_prefixes: ['TxId:'],
    date_format: 'DMY_HMS', utc_offset_minutes: 120};
  const receiverHash = await digest('synthetic-only-receiver');
  await sql`insert into app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,currency,timezone,profile_status,profile_version,profile_json,created_at)
    values(${account},'mtn_momo','250788123456','Synthetic receiver',${receiverHash},'RWF','Africa/Kigali','approved','synthetic.v1',${JSON.stringify(profile)},${stamp()})`;
  await sql`insert into app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,version,status,created_at)
    values(${binding},${member},${account},1,'active',${stamp()})`;

  const objects = new Map();
  const base = {DB: db, COLLECT_FENCE_WORK: db.applicationWork, DATA_KEY_ID: 'synthetic-outbox',
    DATA_ENCRYPTION_KEY: btoa('r'.repeat(32)), MOMO_PROCESSING_PAUSED: 'true'};
  const providerOutput = reference => ({schema_version: MOMO_SCHEMA_VERSION,
    event_kind: 'incoming_receipt', payment_outcome: 'successful', transaction_id_raw: reference,
    original_transaction_id_raw: null, transaction_datetime_raw: '20/10/2026 11:30:00',
    principal_amount_raw: '1,000', currency_raw: 'RWF', payer_name_raw: 'Synthetic Payer',
    payer_identifier_raw: '**007', payment_reference_raw: null, fee_amount_raw: '0',
    wallet_balance_after_raw: '9000',
    evidence: {incoming_success: 'You have received RWF 1,000', principal: '1,000',
      transaction_id: reference, transaction_datetime: '20/10/2026 11:30:00',
      payer: 'Synthetic Payer **007', fee: 'Fee: 0', wallet_balance_after: 'Balance: 9000'}, issues: []});

  async function prepareCapture(reference) {
    const id = crypto.randomUUID(), key = 'sms/' + id;
    const body = `You have received RWF 1,000 from Synthetic Payer **007. TxId: ${reference} on 20/10/2026 11:30:00. Fee: 0. Balance: 9000.`;
    const bytes = new TextEncoder().encode(JSON.stringify({raw_sender: 'MTN MoMo', raw_body: body,
      received_at_device: '2026-10-20T11:30:00+02:00', completeness: 'complete'}));
    const bodyHash = await digest(body), plainHash = await digest(bytes),
      aad = `sms:${id}:${plainHash}`, cipher = await encrypt(base, bytes, aad), sealedHash = await digest(cipher),
      scope = {ownerId: member, entityId: id, purpose: 'sms_receipt'},
      metadata = {sha256: plainHash, source_fingerprint: 'a'.repeat(64)}, operation = crypto.randomUUID();
    objects.set(key, cipher);
    await sql.begin(async tx => {
      await tx`insert into private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
        values(${key},${'a'.repeat(64)},${scope},${aad},'synthetic-outbox',${plainHash},${cipher})`;
      await tx`insert into private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
        values(${operation},${key},${'b'.repeat(64)},${sealedHash},${cipher.length},${scope},${{}},${metadata},'committed')`;
      await tx`insert into private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
        values(${key},${operation},${'b'.repeat(64)},${sealedHash},${cipher.length},${scope},${{}},${metadata})`;
    });
    const insert = db.prepare(`INSERT INTO sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,received_at_device,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)`)
      .bind(id, member, sid, crypto.randomUUID(), bodyHash, receiverHash, key, plainHash, bytes.length, null, stamp());
    const queue = processingInsert(base, id, {bindingId: binding, bindingVersion: 1, mode: 'live'});
    return {id, key, cipher, insert, queue, output: providerOutput(reference)};
  }
  const data = raw => ({size: raw.cipher.length, text: async () => raw.cipher});
  const getObject = async key => {
    const cipher = objects.get(key);
    return cipher ? {size: cipher.length, text: async () => cipher} : null;
  };
  const counts = async raw => (await sql`select
    (select count(*)::int from app.sms_receipts where id=${raw}) as captures,
    (select count(*)::int from app.momo_processing_jobs where raw_sms_id=${raw}) as jobs,
    (select count(*)::int from app.momo_parse_attempts where raw_sms_id=${raw}) as attempts,
    (select count(*)::int from app.momo_transaction_sources where raw_sms_id=${raw}) as links,
    (select count(*)::int from app.ledger_entries) as ledger`)[0];
  const findings = [];

  const first = await prepareCapture('SYNTHETIC_ATOMIC_' + crypto.randomUUID());
  const before = await counts(first.id);
  await assert.rejects(() => db.batch([first.insert, first.queue, first.queue]));
  assert.deepEqual(await counts(first.id), before, 'A failed enqueue rolls back the source and job together.');
  await db.batch([first.insert, first.queue]);
  assert.deepEqual(await counts(first.id), {...before, captures: 1, jobs: 1});
  findings.push('actual_SQL_source_and_enqueue_commit_or_roll_back_together');

  const readReached = deferred(), releaseRead = deferred();
  let firstReads = 0, providerCalls = 0;
  const firstEnv = {...base, PRIVATE_MEDIA: {async get(key) {
    firstReads++;
    if (key === first.key) { readReached.resolve(); await releaseRead.promise; }
    return getObject(key);
  }}, AI: {async run() { providerCalls++; return {response: first.output}; }}};
  const workerOne = processMomoJob(firstEnv, first.id);
  try {
    await Promise.race([readReached.promise, workerOne.then(() => { throw new Error('First worker did not reach the storage barrier.'); })]);
    const competing = await processMomoJob({...firstEnv, PRIVATE_MEDIA: {get: getObject}}, first.id);
    assert.equal(competing.state, 'not_claimed');
    const [during] = await sql`select state,attempt_count from app.momo_processing_jobs where raw_sms_id=${first.id}`;
    assert.equal(during.state, 'processing'); assert.equal(during.attempt_count, 1);
  } finally { releaseRead.resolve(); }
  const firstResult = await workerOne;
  assert.equal(firstResult.relation, 'accepted');
  assert.equal(firstReads, 1); assert.equal(providerCalls, 1);
  assert.deepEqual(await counts(first.id), {...before, captures: 1, jobs: 1, attempts: 1, links: 1});
  findings.push('actual_SQL_overlapping_worker_cannot_claim_unexpired_lease');

  const stale = await prepareCapture('SYNTHETIC_STALE_' + crypto.randomUUID());
  await db.batch([stale.insert, stale.queue]);
  const aiStarted = deferred(), releaseAi = deferred(); let staleProviderCalls = 0;
  const pausedEnv = {...base, PRIVATE_MEDIA: {get: getObject}, AI: {async run() {
    staleProviderCalls++; aiStarted.resolve(); await releaseAi.promise; return {response: stale.output};
  }}};
  const staleWorker = processMomoJob(pausedEnv, stale.id);
  try {
    await Promise.race([aiStarted.promise, staleWorker.then(() => { throw new Error('Stale worker did not reach the provider barrier.'); })]);
    // This test-only update simulates lease expiry; it does not advance a real provider clock.
    await sql`update app.momo_processing_jobs set lease_until=${epoch() - 1} where raw_sms_id=${stale.id}`;
    const replacement = await processMomoJob({...base, PRIVATE_MEDIA: {get: getObject}, AI: {async run() {
      staleProviderCalls++; return {response: stale.output};
    }}}, stale.id);
    assert.equal(replacement.relation, 'accepted');
  } finally { releaseAi.resolve(); }
  const staleResult = await staleWorker;
  assert.equal(staleResult.state, 'superseded');
  const staleCounts = await counts(stale.id);
  assert.equal(staleCounts.attempts, 1); assert.equal(staleCounts.links, 1);
  assert.equal(staleCounts.ledger, before.ledger);
  assert.equal(staleProviderCalls, 2, 'The synthetic provider exposes the unresolved duplicate-call risk.');
  findings.push('actual_SQL_expired_worker_cannot_commit_after_replacement');

  const uncertain = await prepareCapture('SYNTHETIC_UNKNOWN_' + crypto.randomUUID());
  await db.batch([uncertain.insert, uncertain.queue]);
  let uncertainCalls = 0;
  const uncertainResult = await processMomoJob({...base, PRIVATE_MEDIA: {get: getObject}, AI: {async run() {
    uncertainCalls++; throw new Error('Synthetic response lost after dispatch');
  }}}, uncertain.id);
  const [uncertainJob] = await sql`select state,last_error,attempt_count from app.momo_processing_jobs where raw_sms_id=${uncertain.id}`;
  assert.equal(uncertainCalls, 1);
  assert.equal(uncertainResult.state, 'retry');
  assert.equal(uncertainJob.state, 'retry');
  assert.equal(uncertainJob.attempt_count, 1);

  return {checks: findings, synthetic_provider_calls: {unexpired_overlap: providerCalls,
    expired_overlap: staleProviderCalls, lost_response: uncertainCalls},
    unresolved: ['A lease can expire after an external request starts, allowing a second external request.',
      'A lost provider response is currently scheduled for retry without reconciliation.'],
    actual_provider_calls: 0, scheduled_jobs_activated: false, production_acceptance: false};
}
