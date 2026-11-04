// Isolated PostgreSQL regression for the actual receipt producer and worker.
// This is not a provider test or permission to activate receipt processing.
import assert from 'node:assert/strict';
import {digest} from '../domain/core.js';
import {encrypt} from '../domain/encryption.js';
import {MOMO_SCHEMA_VERSION,MOMO_JOB_CHECKPOINT,processMomoJob,processingInsert,drainMomoJobs} from '../domain/momo_pipeline.js';

const stamp = () => new Date().toISOString();
const epoch = () => Math.floor(Date.now() / 1000);
const deferred = () => {
  let resolve;
  const promise = new Promise(r => { resolve = r; });
  return {promise, resolve};
};

// Called only after the runner proves its dedicated loopback cluster identity
// and applies the exact reviewed synthetic migration fixture.
export async function verifyMomoOutboxOnPostgres({sql, db, member, sid}) {
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
    DATA_ENCRYPTION_KEY: btoa('r'.repeat(32)), MOMO_PROCESSING_PAUSED: 'false'};
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
  // Observe the actual adapter's batch/execute transaction, without replacing
  // its SQL. The hook pauses only after the specified SQL statement has
  // completed and before that same transaction can commit.
  const pauseAfter = (predicate, reached, release) => {
    const watched = new db.constructor(db.sql, db.claims, db.applicationWork);
    const statement = watched.statement.bind(watched); let paused = false;
    watched.statement = async (tx, item) => {
      const result = await statement(tx, item);
      if (!paused && predicate(item.sql)) { paused = true; reached.resolve(); await release.promise; }
      return result;
    };
    return watched;
  };
  const pauseBefore = (predicate, reached, release) => {
    const watched = new db.constructor(db.sql, db.claims, db.applicationWork);
    const statement = watched.statement.bind(watched); let paused = false;
    watched.statement = async (tx, item) => {
      if (!paused && predicate(item.sql)) { paused = true; reached.resolve(); await release.promise; }
      return statement(tx, item);
    };
    return watched;
  };
  const waitForRowLock = async prefix => {
    const deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      const [row] = await db.sql`select count(*)::int as n from pg_stat_activity
        where datname=current_database() and pid<>pg_backend_pid() and wait_event_type='Lock' and query like ${prefix + '%'}`;
      if (row.n > 0) return;
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    throw new Error('Expected independent PostgreSQL row-lock waiter was not observed: ' + prefix);
  };
  const waitPast = async expires => {
    const deadline=Date.now()+5000;
    while(epoch()<=expires&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,20));
    assert(epoch()>expires,'Synthetic lease expiry deadline');
  };
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

  // A lease that expires BEFORE dispatch may be reclaimed. The stale owner
  // cannot acquire the pre-dispatch marker after the replacement takes over.
  const preflight = await prepareCapture('SYNTHETIC_PREFLIGHT_' + crypto.randomUUID());
  await db.batch([preflight.insert, preflight.queue]);
  const preflightRead = deferred(), releasePreflight = deferred(); let preflightCalls = 0;
  const preflightWorker = processMomoJob({...base, PRIVATE_MEDIA: {async get(key) {
    preflightRead.resolve(); await releasePreflight.promise; return getObject(key);
  }}, AI: {async run() { preflightCalls++; return {response: preflight.output}; }}}, preflight.id);
  try {
    await Promise.race([preflightRead.promise, preflightWorker.then(() => { throw new Error('Preflight worker did not reach the storage barrier.'); })]);
    await sql`update app.momo_processing_jobs set lease_until=${epoch() - 1} where raw_sms_id=${preflight.id}`;
    const replacement = await processMomoJob({...base, PRIVATE_MEDIA: {get: getObject}, AI: {async run() {
      preflightCalls++; return {response: preflight.output};
    }}}, preflight.id);
    assert.equal(replacement.relation, 'accepted');
  } finally { releasePreflight.resolve(); }
  assert.equal((await preflightWorker).state, 'superseded');
  assert.equal(preflightCalls, 1);
  findings.push('expired_preflight_reclaims_once_and_fences_old_dispatch');

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
    assert.equal(replacement.state, 'not_claimed');
    await drainMomoJobs({...base, MOMO_PROCESSING_PAUSED:'false', PRIVATE_MEDIA:{get:getObject}, AI:{async run(){
      staleProviderCalls++; return {response:stale.output};
    }}});
    const [parked]=await sql`select state,last_error from app.momo_processing_jobs where raw_sms_id=${stale.id}`;
    assert.equal(parked.state,'needs_review');assert.equal(parked.last_error,MOMO_JOB_CHECKPOINT.unknown);
  } finally { releaseAi.resolve(); }
  const staleResult = await staleWorker;
  assert.equal(staleResult.state, 'superseded');
  const staleCounts = await counts(stale.id);
  assert.equal(staleCounts.attempts, 0); assert.equal(staleCounts.links, 0);
  assert.equal(staleCounts.ledger, before.ledger);
  assert.equal(staleProviderCalls, 1, 'An expired dispatched attempt must not invoke a replacement.');
  findings.push('expired_dispatched_attempt_is_parked_and_stale_result_cannot_commit');

  // Real two-connection race: the parking UPDATE owns the row but has not
  // committed when the provider returns. The finishing batch must wait, then
  // observe the committed unknown state and roll back every candidate fact.
  const parkedRace = await prepareCapture('SYNTHETIC_PARK_FIRST_' + crypto.randomUUID());
  await db.batch([parkedRace.insert, parkedRace.queue]);
  const parkAi = deferred(), releaseParkAi = deferred(), finishStarting = deferred(), releaseFinishStarting = deferred(), parkLocked = deferred(), releaseParkLock = deferred();
  const parkingDb = pauseAfter(text => text.startsWith("UPDATE momo_processing_jobs SET state='needs_review',last_error="),parkLocked,releaseParkLock);
  const parkFinishingDb = pauseBefore(text => text.startsWith('UPDATE momo_processing_jobs SET lease_token=lease_token'),finishStarting,releaseFinishStarting);
  let parkCalls = 0, parkWorker, parking;
  try {
    parkWorker = processMomoJob({...base,DB:parkFinishingDb,PRIVATE_MEDIA:{get:getObject},AI:{async run(){
      parkCalls++; parkAi.resolve(); await releaseParkAi.promise; return {response:parkedRace.output};
    }}},parkedRace.id);
    await Promise.race([parkAi.promise,parkWorker.then(()=>{throw Error('Parking race did not reach provider');})]);
    const expires=epoch()+2;
    await sql`update app.momo_processing_jobs set lease_until=${expires} where raw_sms_id=${parkedRace.id}`;
    releaseParkAi.resolve();
    await Promise.race([finishStarting.promise,parkWorker.then(()=>{throw Error('Finishing transaction did not reach its row lock');})]);
    await waitPast(expires);
    parking = drainMomoJobs({...base,DB:parkingDb,MOMO_PROCESSING_PAUSED:'false',PRIVATE_MEDIA:{get:getObject},AI:{async run(){parkCalls++;}}});
    await Promise.race([parkLocked.promise,parking.then(()=>{throw Error('Parking race did not lock job');})]);
    releaseFinishStarting.resolve();
    releaseParkLock.resolve();
    assert.equal((await parkWorker).state,'superseded'); await parking;
    const [row]=await sql`select state,last_error from app.momo_processing_jobs where raw_sms_id=${parkedRace.id}`;
    assert.equal(row.state,'needs_review');assert.equal(row.last_error,MOMO_JOB_CHECKPOINT.unknown);
    const observed=await counts(parkedRace.id);assert.equal(observed.attempts,0);assert.equal(observed.links,0);assert.equal(parkCalls,1);
  } finally {
    releaseParkAi.resolve();releaseFinishStarting.resolve();releaseParkLock.resolve();
    await Promise.allSettled([parkWorker,parking].filter(Boolean));
  }
  findings.push('parking_lock_wins_and_stale_completion_rolls_back_all_facts');

  // The finishing batch holds the row lock, passes the initial moving-clock
  // guard and inserts a parse attempt, then pauses until after expiry. The
  // terminal guard must roll the entire batch back before parking can commit.
  const finishingRace = await prepareCapture('SYNTHETIC_FINISH_FIRST_' + crypto.randomUUID());
  await db.batch([finishingRace.insert, finishingRace.queue]);
  const finishAi = deferred(), releaseFinishAi = deferred(), finishLocked = deferred(), releaseFinishLock = deferred();
  const finishingDb = pauseAfter(text => text.startsWith('INSERT INTO momo_parse_attempts'),finishLocked,releaseFinishLock);
  let finishCalls=0,finishWorker,finishParking;
  try {
    finishWorker=processMomoJob({...base,DB:finishingDb,PRIVATE_MEDIA:{get:getObject},AI:{async run(){
      finishCalls++;finishAi.resolve();await releaseFinishAi.promise;return {response:finishingRace.output};
    }}},finishingRace.id);
    await Promise.race([finishAi.promise,finishWorker.then(()=>{throw Error('Finishing race did not reach provider');})]);
    const expires=epoch()+2;
    await sql`update app.momo_processing_jobs set lease_until=${expires} where raw_sms_id=${finishingRace.id}`;
    releaseFinishAi.resolve();
    await Promise.race([finishLocked.promise,finishWorker.then(()=>{throw Error('Finishing race did not lock job');})]);
    await waitPast(expires);
    finishParking=drainMomoJobs({...base,MOMO_PROCESSING_PAUSED:'false',PRIVATE_MEDIA:{get:getObject},AI:{async run(){finishCalls++;}}});
    await waitForRowLock("UPDATE momo_processing_jobs SET state='needs_review',last_error=");
    releaseFinishLock.resolve();
    assert.equal((await finishWorker).state,'superseded');await finishParking;
    const [row]=await sql`select state,last_error from app.momo_processing_jobs where raw_sms_id=${finishingRace.id}`;
    assert.equal(row.state,'needs_review');assert.equal(row.last_error,MOMO_JOB_CHECKPOINT.unknown);
    const observed=await counts(finishingRace.id);assert.equal(observed.attempts,0);assert.equal(observed.links,0);assert.equal(finishCalls,1);
  } finally {
    releaseFinishAi.resolve();releaseFinishLock.resolve();
    await Promise.allSettled([finishWorker,finishParking].filter(Boolean));
  }
  findings.push('lease_expiry_while_finishing_lock_held_rolls_back_and_parks');

  // A different owner holds a row lock without changing its row version. The
  // finishing UPDATE begins while the lease is valid and is observed waiting;
  // after wall-clock expiry its post-lock guard must roll back all facts.
  const waitFinish=await prepareCapture('SYNTHETIC_WAIT_FINISH_'+crypto.randomUUID());
  await db.batch([waitFinish.insert,waitFinish.queue]);
  const waitFinishAi=deferred(),releaseWaitFinishAi=deferred(),ownerFinishLocked=deferred(),releaseOwnerFinish=deferred();
  let waitFinishWorker,finishBlocker,waitFinishCalls=0;
  try{
    waitFinishWorker=processMomoJob({...base,PRIVATE_MEDIA:{get:getObject},AI:{async run(){
      waitFinishCalls++;waitFinishAi.resolve();await releaseWaitFinishAi.promise;return {response:waitFinish.output};
    }}},waitFinish.id);
    await Promise.race([waitFinishAi.promise,waitFinishWorker.then(()=>{throw Error('Waiting finisher did not reach provider');})]);
    const expires=epoch()+2;
    await sql`update app.momo_processing_jobs set lease_until=${expires} where raw_sms_id=${waitFinish.id}`;
    finishBlocker=sql.begin(async tx=>{await tx`select raw_sms_id from app.momo_processing_jobs where raw_sms_id=${waitFinish.id} for update`;ownerFinishLocked.resolve();await releaseOwnerFinish.promise;});
    await ownerFinishLocked.promise;releaseWaitFinishAi.resolve();
    await waitForRowLock('UPDATE momo_processing_jobs SET lease_token=lease_token');
    await waitPast(expires);releaseOwnerFinish.resolve();await finishBlocker;
    assert.equal((await waitFinishWorker).state,'superseded');
    const observed=await counts(waitFinish.id);assert.equal(observed.attempts,0);assert.equal(observed.links,0);assert.equal(waitFinishCalls,1);
    await drainMomoJobs({...base,MOMO_PROCESSING_PAUSED:'false',PRIVATE_MEDIA:{get:getObject},AI:{async run(){waitFinishCalls++;}}});
    const [row]=await sql`select state,last_error from app.momo_processing_jobs where raw_sms_id=${waitFinish.id}`;
    assert.equal(row.state,'needs_review');assert.equal(row.last_error,MOMO_JOB_CHECKPOINT.unknown);assert.equal(waitFinishCalls,1);
  }finally{releaseWaitFinishAi.resolve();releaseOwnerFinish.resolve();await Promise.allSettled([waitFinishWorker,finishBlocker].filter(Boolean));}
  findings.push('lease_expiry_during_unmodified_row_lock_wait_prevents_stale_facts');

  // Apply the same contention to the pre-dispatch marker. It may begin its
  // UPDATE while valid, but a wait past expiry must roll its marker back and
  // must never invoke the external provider.
  const waitDispatch=await prepareCapture('SYNTHETIC_WAIT_DISPATCH_'+crypto.randomUUID());
  await db.batch([waitDispatch.insert,waitDispatch.queue]);
  const dispatchRead=deferred(),releaseDispatchRead=deferred(),ownerDispatchLocked=deferred(),releaseOwnerDispatch=deferred();
  let waitDispatchWorker,dispatchBlocker,waitDispatchCalls=0;
  try{
    waitDispatchWorker=processMomoJob({...base,PRIVATE_MEDIA:{async get(key){dispatchRead.resolve();await releaseDispatchRead.promise;return getObject(key);}},
      AI:{async run(){waitDispatchCalls++;return {response:waitDispatch.output};}}},waitDispatch.id);
    await Promise.race([dispatchRead.promise,waitDispatchWorker.then(()=>{throw Error('Waiting dispatch did not reach storage');})]);
    const expires=epoch()+2;
    await sql`update app.momo_processing_jobs set lease_until=${expires} where raw_sms_id=${waitDispatch.id}`;
    dispatchBlocker=sql.begin(async tx=>{await tx`select raw_sms_id from app.momo_processing_jobs where raw_sms_id=${waitDispatch.id} for update`;ownerDispatchLocked.resolve();await releaseOwnerDispatch.promise;});
    await ownerDispatchLocked.promise;releaseDispatchRead.resolve();
    await waitForRowLock('UPDATE momo_processing_jobs SET last_error=');
    await waitPast(expires);releaseOwnerDispatch.resolve();await dispatchBlocker;
    assert.equal((await waitDispatchWorker).state,'superseded');assert.equal(waitDispatchCalls,0);
    const [row]=await sql`select state,last_error from app.momo_processing_jobs where raw_sms_id=${waitDispatch.id}`;
    assert.equal(row.state,'processing');assert.equal(row.last_error,MOMO_JOB_CHECKPOINT.preflight);
    const observed=await counts(waitDispatch.id);assert.equal(observed.attempts,0);assert.equal(observed.links,0);
    // Prevent this deliberately expired preflight fixture from being picked
    // up by later, unrelated drain assertions in this same synthetic suite.
    await sql`update app.momo_processing_jobs set state='needs_review',lease_token=null,lease_until=null,last_error='synthetic_test_held' where raw_sms_id=${waitDispatch.id}`;
  }finally{releaseDispatchRead.resolve();releaseOwnerDispatch.resolve();await Promise.allSettled([waitDispatchWorker,dispatchBlocker].filter(Boolean));}
  findings.push('lease_expiry_during_dispatch_lock_wait_never_calls_provider');

  const uncertain = await prepareCapture('SYNTHETIC_UNKNOWN_' + crypto.randomUUID());
  await db.batch([uncertain.insert, uncertain.queue]);
  let uncertainCalls = 0;
  const uncertainResult = await processMomoJob({...base, PRIVATE_MEDIA: {get: getObject}, AI: {async run() {
    uncertainCalls++; throw new Error('Synthetic response lost after dispatch');
  }}}, uncertain.id);
  const [uncertainJob] = await sql`select state,last_error,attempt_count from app.momo_processing_jobs where raw_sms_id=${uncertain.id}`;
  assert.equal(uncertainCalls, 1);
  assert.equal(uncertainResult.state, 'needs_review');
  assert.equal(uncertainJob.state, 'needs_review');
  assert.equal(uncertainJob.last_error,MOMO_JOB_CHECKPOINT.unknown);
  assert.equal(uncertainJob.attempt_count, 1);
  assert.equal((await processMomoJob({...base,PRIVATE_MEDIA:{get:getObject},AI:{async run(){uncertainCalls++;}}},uncertain.id)).state,'not_claimed');
  assert.equal(uncertainCalls,1);
  findings.push('lost_provider_response_is_durable_unknown_and_never_automatically_retried');

  // A successful marker commit whose reply is lost must not cause a send, and
  // cannot later be treated as a safe preflight retry.
  const lostMarker=await prepareCapture('SYNTHETIC_MARKER_' + crypto.randomUUID());
  await db.batch([lostMarker.insert,lostMarker.queue]);let markerCalls=0;
  let lostDb;
  lostDb=new Proxy(db,{get(target,key){
    if(key==='withSession')return()=>lostDb;
    if(key==='batch')return async statements=>{const marker=statements.some(item=>item.sql?.startsWith('UPDATE momo_processing_jobs SET last_error='));
      const result=await target.batch(statements);if(marker)throw Error('synthetic marker commit ACK lost');return result;};
    const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;
  }});
  const unconfirmed=await drainMomoJobs({...base,DB:lostDb,MOMO_PROCESSING_PAUSED:'false',PRIVATE_MEDIA:{get:getObject},AI:{async run(){markerCalls++;}}},{limit:1});
  assert.deepEqual(unconfirmed.results,[{state:'awaiting_lease_reconciliation'}]);
  const [marked]=await sql`select state,last_error from app.momo_processing_jobs where raw_sms_id=${lostMarker.id}`;
  assert.equal(marked.state,'processing');assert.equal(marked.last_error,MOMO_JOB_CHECKPOINT.dispatch);assert.equal(markerCalls,0);
  await sql`update app.momo_processing_jobs set lease_until=${epoch()-1} where raw_sms_id=${lostMarker.id}`;
  await drainMomoJobs({...base,MOMO_PROCESSING_PAUSED:'false',PRIVATE_MEDIA:{get:getObject},AI:{async run(){markerCalls++;}}});
  const [markerParked]=await sql`select state,last_error from app.momo_processing_jobs where raw_sms_id=${lostMarker.id}`;
  assert.equal(markerParked.state,'needs_review');assert.equal(markerParked.last_error,MOMO_JOB_CHECKPOINT.unknown);assert.equal(markerCalls,0);
  findings.push('lost_dispatch_marker_ack_never_sends_or_reclaims_ambiguously');

  const localFailure=await prepareCapture('SYNTHETIC_SAFE_RETRY_' + crypto.randomUUID());
  await db.batch([localFailure.insert,localFailure.queue]);let localCalls=0;
  const failed=await processMomoJob({...base,PRIVATE_MEDIA:{async get(){throw Error('synthetic storage unavailable');}},AI:{async run(){localCalls++;}}},localFailure.id);
  assert.equal(failed.state,'retry');assert.equal(localCalls,0);
  const [safe]=await sql`select state,last_error from app.momo_processing_jobs where raw_sms_id=${localFailure.id}`;
  assert.equal(safe.state,'retry');assert.equal(safe.last_error,MOMO_JOB_CHECKPOINT.retry);
  await sql`update app.momo_processing_jobs set available_at=0 where raw_sms_id=${localFailure.id}`;
  const resumed=await drainMomoJobs({...base,MOMO_PROCESSING_PAUSED:'false',PRIVATE_MEDIA:{get:getObject},AI:{async run(){localCalls++;return {response:localFailure.output};}}},{limit:1});
  assert.equal(resumed.results[0].relation,'accepted');assert.equal(localCalls,1);
  findings.push('pre_dispatch_failure_retries_safely_after_backoff');

  const legacy=[];
  for(const [state,error] of [['processing',null],['retry','extraction_temporarily_unavailable'],['pending',null]]){
    const entry=await prepareCapture('SYNTHETIC_LEGACY_'+crypto.randomUUID());await db.batch([entry.insert,entry.queue]);
    await sql`update app.momo_processing_jobs set state=${state},attempt_count=1,last_error=${error},lease_token=${state==='processing'?'legacy-owner':null},lease_until=${state==='processing'?epoch()-1:null} where raw_sms_id=${entry.id}`;
    assert.equal((await processMomoJob({...base,PRIVATE_MEDIA:{get:getObject},AI:{async run(){throw Error('legacy must not send');}}},entry.id)).state,'not_claimed');
    legacy.push(entry.id);
  }
  await drainMomoJobs({...base,MOMO_PROCESSING_PAUSED:'false',PRIVATE_MEDIA:{get:getObject},AI:{async run(){throw Error('legacy must not send');}}});
  for(const raw of legacy){const [row]=await sql`select state,last_error from app.momo_processing_jobs where raw_sms_id=${raw}`;assert.equal(row.state,'needs_review');assert.equal(row.last_error,MOMO_JOB_CHECKPOINT.unknown);}
  findings.push('legacy_ambiguous_pending_retry_and_expired_processing_are_parked');

  return {checks: findings, synthetic_provider_calls: {unexpired_overlap: providerCalls,
    expired_overlap: staleProviderCalls, lost_response: uncertainCalls, lost_marker_ack:markerCalls},
    unresolved: ['Provider-outcome reconciliation and authorized release/activation remain outside this synthetic test.'],
    actual_provider_calls: 0, scheduled_jobs_activated: false, production_acceptance: false};
}
