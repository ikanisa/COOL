import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {attestAdminEmailAccount} from '../domain/admin_email_policy.js';
import {handleAdminInvitation} from './helpers/module-domain-admin_invitation.js';
import {ApiError} from '../domain/core.js';

// Intended target: _shared/tests/admin-invitation.test.mjs. Actual controller,
// intercepted GoTrue HTTP, and an in-memory durable-attempt/claim model only.
// This is not proof of SQL authority, locking, trigger, or hosted mail behavior.
const NOW = 1_792_497_600;
const PROJECT = 'https://collect-invitation.invalid';
const SERVICE_KEY = 'sb_secret_synthetic_invitation_only_0123456789';
const OWNER_ID = '11111111-1111-4111-8111-111111111111';
const PUBLIC_ID = '22222222-2222-4222-8222-222222222222';
const PRINCIPAL_ID = '33333333-3333-4333-8333-333333333333';
const SUBJECT_ID = '44444444-4444-4444-8444-444444444444';
const PROVIDER_ID = '55555555-5555-4555-8555-555555555555';
const ORIGIN = 'https://platform-admin.collect.ikanisa.com';
const EMAIL = 'synthetic.staff@example.invalid';
const KEY = 'invite-original-0001';
const BODY = {email: EMAIL, role: 'staff', displayName: 'Synthetic Staff'};
const OWNER = {id: OWNER_ID, token_hash: 'a'.repeat(64), origin: ORIGIN, public_id: PUBLIC_ID,
  principal_id: PRINCIPAL_ID, role: 'owner', email: 'info@ikanisa.com',
  permissions: ['admin_users.manage'], issued_assurance_level: 1, issued_mfa_at: null,auth_user_id:PROVIDER_ID,auth_session_id:PUBLIC_ID,auth_version:1};
const SQL = {
  prepare: 'SELECT private.admin_invitation_prepare(?,?,?,?,?,?,?,?,?,?,?,?) AS result',
  claim: 'SELECT private.admin_invitation_claim(?,?,?,?,?::uuid,?::uuid) AS result',
  finish: 'SELECT private.admin_invitation_finish(?,?,?,?,?::uuid,?::uuid,?,?) AS result',
  recover: 'SELECT private.admin_invitation_recover(?,?,?,?,?) AS result',
};
const phaseFor = text => Object.keys(SQL).find(phase => SQL[phase] === text);
const apiError = (status, code) => error => error instanceof ApiError && error.status === status && error.code === code;
const resultOf = (row, extra = {}) => ({requestId: row.requestId, id: row.id,
  principalId: row.principalId, email: row.email, emailStatus: row.emailStatus,
  operation: row.operation, accessStatus: row.accessStatus, ...extra});

class Statement {
  values = [];
  constructor(db, sql) { this.db = db; this.sql = sql; }
  bind(...values) { this.values = values; return this; }
  first() { return this.db.transition(this.sql, this.values); }
}
class Database {
  trace = []; records = new Map(); keys = new Map(); subjects = new Map(); claimed = 0;
  constructor(options) {
    this.options = options;
    if (options.subject) this.subjects.set(options.subject.id, {...options.subject});
  }
  prepare(sql) {
    assert.ok(phaseFor(sql), 'Only the four private invitation protocol functions may be called');
    return new Statement(this, sql);
  }
  async transition(sql, args) {
    const phase = phaseFor(sql);
    this.trace.push({phase, args: [...args]});
    assert.deepEqual(args.slice(0, 4), [OWNER.id, OWNER.token_hash, OWNER.origin, OWNER.public_id]);
    assert.equal(args.length, {prepare: 12, claim: 6, finish: 8, recover: 5}[phase]);
    if (this.options.failBefore?.[phase]) throw new Error(this.options.failBefore[phase]);
    if (phase === 'prepare') {
      const [, , , , key, kind, candidate, principalCandidate, email, role, display, bodyHash] = args;
      const retained = this.keys.get(key);
      if (retained) {
        if (retained.row.bodyHash !== bodyHash || retained.row.operation !== kind) {
          throw new Error('admin_invitation_idempotency_conflict');
        }
        const value = resultOf(retained.row, {replayed: true, duplicate: retained.duplicate});
        if (this.options.prepareBarrier) await this.options.prepareBarrier();
        return {result: value};
      }
      if (kind === 'invite') {
        const original = [...this.records.values()].find(row => row.email === email && row.operation === 'invite');
        if (original) {
          this.keys.set(key, {row: original, duplicate: true});
          return {result: resultOf(original, {replayed: true, duplicate: true})};
        }
      }
      let subject;
      if (kind === 'resend') {
        subject = this.subjects.get(candidate);
        if (!subject || subject.accessStatus !== 'invited') throw new Error('admin_invitation_subject_unavailable');
        assert.equal(email, null); assert.equal(role, null); assert.equal(display, null);
      } else {
        subject = {id: candidate, principalId: principalCandidate, email, role, display,
          accessStatus: 'invited'};
        this.subjects.set(candidate, subject);
      }
      const row = {...subject, requestId: crypto.randomUUID(), operation: kind, bodyHash,
        emailStatus: this.options.registered ? 'already_registered' : 'reserved', claim: null};
      this.records.set(row.requestId, row); this.keys.set(key, {row, duplicate: false});
      const value = resultOf(row, {replayed: false, duplicate: false});
      if (this.options.losePrepareReply) {this.options.losePrepareReply = false; throw new Error('synthetic committed prepare reply lost');}
      if (this.options.prepareBarrier) await this.options.prepareBarrier();
      return {result: value};
    }
    if (phase === 'recover') {
      const retained = this.keys.get(args[4]);
      return {result: retained ? resultOf(retained.row, {found: true, replayed: true, duplicate: retained.duplicate}) : {found: false}};
    }
    const row = this.records.get(args[4]);
    assert.ok(row, 'Claims and finalization must use an existing durable request ID');
    if (phase === 'claim') {
      if (this.options.revokedAtClaim) throw new Error('admin_invitation_authority');
      const claimed = row.emailStatus === 'reserved' && row.claim === null;
      if (claimed) {row.claim = args[5]; row.emailStatus = 'dispatching'; this.claimed++;}
      if (this.options.loseClaimReply) {this.options.loseClaimReply = false; throw new Error('synthetic committed claim reply lost');}
      return {result: resultOf(row, {claimed, replayed: !claimed, duplicate: false,
        ...(this.options.claimMismatch ? {principalId: crypto.randomUUID()} : {})})};
    }
    assert.equal(args[5], row.claim, 'Only the actual claim token may finalize the attempt');
    assert.ok(['accepted', 'rejected', 'unknown', 'already_registered'].includes(args[6]));
    assert.ok([null, 'provider_rejected', 'provider_outcome_unknown', 'provider_response_unconfirmed', 'email_exists'].includes(args[7]),
      'Only a closed safe provider error may be persisted');
    row.emailStatus = args[6]; row.safeError = args[7];
    if (this.options.loseFinishReply) {this.options.loseFinishReply = false; throw new Error('synthetic committed finish reply lost');}
    return {result: resultOf(row, {replayed: false, duplicate: false})};
  }
}

function request(path, {method = 'POST', key = KEY, body = BODY} = {}) {
  return new Request(ORIGIN + '/api/admin' + path, {method,
    headers: {'Content-Type': 'application/json', Origin: ORIGIN, ...(key === null ? {} : {'Idempotency-Key': key})},
    ...(method === 'GET' ? {} : {body: JSON.stringify(body)})});
}
async function decoded(response) {
  assert.ok(response instanceof Response);
  return {status: response.status, body: await response.json()};
}
async function fixture(options, check) {
  const db = new Database(options), calls = [];
  const env = {DB: db, SUPABASE_URL: PROJECT, SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY};
  const previousFetch = globalThis.fetch, previousNow = Date.now;
  Date.now = () => NOW * 1000;
  globalThis.fetch = async (input, init) => {
    const outbound = new Request(input, init), body = await outbound.json();
    const call = {url: outbound.url, method: outbound.method, redirect: outbound.redirect, headers: outbound.headers, body};
    calls.push(call);
    if (options.provider) return options.provider(call);
    if (options.network) throw new Error('synthetic provider private detail ' + SERVICE_KEY + ' ' + EMAIL);
    if (options.status) return Response.json({error_code: options.providerCode ?? 'synthetic_rejection',
      msg: 'synthetic private body ' + SERVICE_KEY + ' ' + EMAIL}, {status: options.status});
    if (options.malformed) return new Response('{', {status: 200, headers: {'Content-Type': 'application/json'}});
    return Response.json({id: PROVIDER_ID, email: body.email,
      invited_at: new Date(NOW * 1000).toISOString(), email_confirmed_at: null, ...options.dto});
  };
  const invoke = (path = '/team/invite', {body = BODY, account = OWNER, emailAt=NOW-2, emailProof=true, ...controls} = {}) => {
    if(emailProof&&account&&['id','public_id'].every(key=>typeof account[key]==='string'&&account[key].length===36)&&/^[a-f0-9]{64}$/.test(account.token_hash??''))attestAdminEmailAccount(account,{contract_version:1,public_session_id:account.public_id,email_verified_at:emailAt,proof_id:PROVIDER_ID});
    const req = request(path, {...controls, body});
    return handleAdminInvitation(req, env, account, body, path);
  };
  try {await check({db, calls, invoke, recover: key => invoke('/team/invitation-status', {method: 'GET', key: key ?? KEY})});}
  finally {
    globalThis.fetch = previousFetch; Date.now = previousNow;
    // Assertions outside fetch cannot be swallowed into an expected unknown result.
    for (const call of calls) {
      assert.equal(call.url, PROJECT + '/auth/v1/invite'); assert.equal(call.method, 'POST');
      assert.equal(call.redirect, 'error'); assert.equal(call.headers.get('apikey'), SERVICE_KEY);
      assert.equal(call.headers.has('Authorization'), false, 'Secret API keys are not duplicated into user bearer authority');
      assert.equal(call.body.email, EMAIL, 'Only the durable approved recipient may be sent to GoTrue');
      assert.deepEqual(call.body, {email: call.body.email, data: {collect_invitation: true}});
    }
  }
}
function phases(db) {return db.trace.map(call => call.phase);}
function failure(reply, status, code, outcome) {
  assert.equal(reply.status, status); assert.equal(reply.body.ok, false);
  assert.equal(reply.body.error.code, code); assert.equal(reply.body.outcome, outcome);
}
function safe(reply) {
  const raw = JSON.stringify(reply.body);
  for (const secret of [SERVICE_KEY, EMAIL, 'synthetic provider private detail', 'synthetic private body', 'provider_token', 'refresh_token']) {
    assert.equal(raw.includes(secret), false, 'Public responses must not contain private provider material');
  }
}

test('managed Admin invitation controller preserves durable attempts and one-send claims', {concurrency: false}, async t => {
  for (const [name, patch] of [
    ['non-owner role', {role: 'admin'}], ['different owner email', {email: EMAIL}], ['missing permission', {permissions: []}],
    ['missing Admin ID', {id: undefined}],
    ['missing public ID', {public_id: undefined}], ['bad token hash', {token_hash: 'unsafe'}], ['bad origin', {origin: 'http://example.invalid'}],
  ]) await t.test(name + ' is refused before SQL or provider access', async () => {
    await fixture({}, async ({db, calls, invoke}) => {
      await assert.rejects(invoke('/team/invite', {account: {...OWNER, ...patch}}), apiError(403, 'owner_required'));
      assert.deepEqual(phases(db), []); assert.equal(calls.length, 0);
    });
  });
  for(const emailAt of [null,NOW-301])await t.test('missing/stale independent email proof is refused before SQL/provider: '+emailAt,async()=>fixture({},async({db,calls,invoke})=>{
    const candidate={...OWNER};if(emailAt===null)attestAdminEmailAccount(candidate,{contract_version:1,public_session_id:PUBLIC_ID,email_verified_at:null,proof_id:null});
    await assert.rejects(invoke('/team/invite',{account:candidate,emailProof:emailAt!==null,emailAt}),apiError(403,'recent_email_sign_in_required'));
    assert.deepEqual(phases(db),[]);assert.equal(calls.length,0);
  }));
  await t.test('AAL1 without factor is accepted with genuine-shaped independent email proof',async()=>fixture({},async({invoke})=>{
    assert.equal((await decoded(await invoke('/team/invite',{account:{...OWNER,issued_assurance_level:1,issued_mfa_at:null}}))).status,200);
  }));
  await t.test('proof expiry at SQL admission keeps the dedicated email recovery code',async()=>fixture({failBefore:{prepare:'recent_email_sign_in_required'}},async({calls,invoke})=>{
    await assert.rejects(invoke('/team/invite'),apiError(403,'recent_email_sign_in_required'));assert.equal(calls.length,0);
  }));
  for (const key of [null, '', 'short', 'has space here', 'nonascii-é', 'a'.repeat(201)]) {
    await t.test('invalid original request key is refused: ' + JSON.stringify(key), async () => {
      await fixture({}, async ({db, calls, invoke}) => {
        await assert.rejects(invoke('/team/invite', {key}), apiError(400, 'invitation_request_key_required'));
        assert.deepEqual(phases(db), []); assert.equal(calls.length, 0);
      });
    });
  }
  await t.test('freshness and ASCII request-key boundaries are accepted', async () => {
    for (const at of [NOW - 300, NOW]) for (const key of ['abcdefgh', 'a'.repeat(200)]) {
      await fixture({}, async ({invoke}) => {assert.equal((await decoded(await invoke('/team/invite', {key,
        account: {...OWNER}, emailAt:at}))).status, 200);});
    }
  });
  for (const body of [{email: 'bad', role: 'staff'}, {email: ' INFO@IKANISA.COM ', role: 'staff'},
    {email: EMAIL, role: 'owner'}, {...BODY, displayName: 'x'.repeat(121)}, {...BODY, displayName: 'bad\nname'}]) {
    await t.test('invalid business invitation is refused before SQL/provider: ' + JSON.stringify(body), async () => {
      await fixture({}, async ({db, calls, invoke}) => {
        await assert.rejects(invoke('/team/invite', {body}), apiError(400, 'invalid_invitation'));
        assert.deepEqual(phases(db), []); assert.equal(calls.length, 0);
      });
    });
  }
  await t.test('normalizes business content without forwarding roles, IDs, locale or token metadata to GoTrue', async () => {
    await fixture({}, async ({invoke, db, calls}) => {
      const reply = await decoded(await invoke('/team/invite', {body: {...BODY, email: ' Synthetic.Staff@Example.Invalid ',
        displayName: '  Synthetic Staff  ', data: {role: 'owner'}, locale: 'rw', token: 'not-a-credential'}}));
      assert.equal(reply.status, 200); assert.equal(reply.body.ok, true); assert.equal(reply.body.emailStatus, 'accepted');
      assert.equal(reply.body.duplicate, false); assert.equal(reply.body.accessStatus, 'invited'); safe(reply);
      assert.deepEqual(phases(db), ['prepare', 'claim', 'finish']); assert.equal(calls.length, 1);
      assert.deepEqual(calls[0].body, {email: EMAIL, data: {collect_invitation: true}});
      assert.deepEqual(db.trace[0].args.slice(8, 11), [EMAIL, 'staff', 'Synthetic Staff']);
      const row = db.records.get(reply.body.requestId); assert.equal(row.id, reply.body.id);
      assert.equal(row.emailStatus, 'accepted'); assert.equal(db.claimed, 1);
    });
  });
  await t.test('same-key normalized replay retains immutable IDs and digest despite fresh candidate UUIDs', async () => {
    await fixture({}, async ({invoke, db, calls}) => {
      const first = await decoded(await invoke());
      const second = await decoded(await invoke('/team/invite', {body: {...BODY, email: ' SYNTHETIC.STAFF@example.invalid ', displayName: ' Synthetic Staff '}}));
      assert.equal(second.status, 200); assert.equal(second.body.replayed, true); assert.equal(second.body.duplicate, false);
      assert.equal(second.body.requestId, first.body.requestId); assert.equal(second.body.id, first.body.id);
      assert.equal(db.records.size, 1); assert.equal(db.subjects.size, 1); assert.equal(calls.length, 1);
      const prepares = db.trace.filter(call => call.phase === 'prepare');
      assert.equal(prepares[0].args[11], prepares[1].args[11], 'Digest excludes random candidate IDs and normalizes business content');
      assert.equal(db.claimed, 1);
    });
  });
  await t.test('same key with different business content conflicts without a second provider call', async () => {
    await fixture({}, async ({invoke, calls, db}) => {
      await invoke(); await assert.rejects(invoke('/team/invite', {body: {...BODY, role: 'admin'}}), apiError(409, 'idempotency_conflict'));
      assert.equal(calls.length, 1); assert.equal(db.records.size, 1); assert.equal(db.claimed, 1);
    });
  });
  for (const state of ['reserved', 'accepted']) await t.test('new-key alias of an original ' + state + ' attempt cannot claim or send', async () => {
    await fixture({losePrepareReply: state === 'reserved'}, async ({invoke, calls, db, recover}) => {
      const first = await decoded(await invoke());
      if (state === 'reserved') failure(first, 503, 'invitation_operation_unknown', 'operation_unknown');
      else assert.equal(first.status, 200);
      const original = [...db.records.values()][0], before = db.trace.length, sent = calls.length;
      const alias = await decoded(await invoke('/team/invite', {key: 'different-original-key'}));
      failure(alias, 409, 'invitation_existing_request', 'existing_request');
      assert.equal(alias.body.duplicate, true); assert.equal(alias.body.requestId, original.requestId); assert.equal(alias.body.id, original.id);
      assert.deepEqual(phases(db).slice(before), ['prepare']); assert.equal(calls.length, sent); assert.equal(db.records.size, 1);
      const status = await decoded(await recover(KEY)); assert.equal(status.status, 200);
      assert.equal(status.body.found, true); assert.equal(status.body.requestId, original.requestId);
    });
  });
  await t.test('competing same-key first callers acquire only one claim and perform one provider operation', async () => {
    let arrived = 0, release;
    const bothPrepared = new Promise(resolve => {release = resolve;});
    await fixture({prepareBarrier: async () => {if (++arrived === 2) release(); await bothPrepared;}}, async ({invoke, db, calls}) => {
      const replies = await Promise.all([invoke(), invoke()]);
      for (const response of replies) assert.ok([200, 503].includes(response.status));
      assert.equal(calls.length, 1); assert.equal(db.claimed, 1); assert.equal(db.records.size, 1);
      assert.equal(db.trace.filter(call => call.phase === 'claim').length, 2);
    });
  });
  for (const state of ['unknown', 'dispatching', 'rejected']) await t.test('retained ' + state + ' attempt is never dispatched again', async () => {
    await fixture({network: true}, async ({invoke, db, calls}) => {
      await invoke(); const row = [...db.records.values()][0]; row.emailStatus = state;
      const before = db.trace.length, reply = await decoded(await invoke());
      failure(reply, state === 'rejected' ? 422 : 503, state === 'rejected' ? 'invitation_rejected' : 'invitation_delivery_unknown',
        state === 'rejected' ? 'delivery_rejected' : 'delivery_unknown');
      assert.deepEqual(phases(db).slice(before), ['prepare']); assert.equal(calls.length, 1);
    });
  });
  await t.test('already-registered prepared target returns notification-pending without claim/provider', async () => {
    await fixture({registered: true}, async ({invoke, db, calls}) => {
      const reply = await decoded(await invoke()); failure(reply, 409, 'invitation_notification_required', 'notification_pending');
      assert.equal(reply.body.emailStatus, 'already_registered'); assert.deepEqual(phases(db), ['prepare']); assert.equal(calls.length, 0); safe(reply);
    });
  });
  await t.test('resend uses only the durable subject identity, ignoring caller email/role metadata', async () => {
    await fixture({subject: {id: SUBJECT_ID, principalId: PRINCIPAL_ID, email: EMAIL, accessStatus: 'invited'}}, async ({invoke, db, calls}) => {
      const reply = await decoded(await invoke('/team/' + SUBJECT_ID + '/resend', {body: {email: 'other@example.invalid', role: 'owner'}}));
      assert.equal(reply.status, 200); assert.equal(reply.body.id, SUBJECT_ID); assert.equal(reply.body.operation, 'resend');
      assert.equal(calls.length, 1); assert.equal(calls[0].body.email, EMAIL);
      assert.equal(db.trace[0].args[6], SUBJECT_ID);
    });
  });
  for (const status of [400, 401, 403, 422, 429]) await t.test('provider ' + status + ' is retained as rejected without retry or raw error leakage', async () => {
    await fixture({status}, async ({invoke, db, calls, recover}) => {
      const reply = await decoded(await invoke()); failure(reply, 422, 'invitation_rejected', 'delivery_rejected'); safe(reply);
      assert.equal(calls.length, 1); assert.equal([...db.records.values()][0].safeError, 'provider_rejected');
      const found = await decoded(await recover()); assert.equal(found.body.emailStatus, 'rejected'); safe(found);
      await invoke(); assert.equal(calls.length, 1);
    });
  });
  await t.test('native email_exists is notification-pending and never triggers an alternate mailer', async () => {
    await fixture({status: 422, providerCode: 'email_exists'}, async ({invoke, calls, db}) => {
      const reply = await decoded(await invoke()); failure(reply, 409, 'invitation_notification_required', 'notification_pending');
      assert.equal([...db.records.values()][0].safeError, 'email_exists'); await invoke(); assert.equal(calls.length, 1); safe(reply);
    });
  });
  for (const options of [{status: 503}, {network: true}, {malformed: true},
    {dto: {email: 'wrong@example.invalid'}}, {dto: {email_confirmed_at: new Date(NOW * 1000).toISOString()}},
    {dto: {id: 'not-a-uuid'}}, {dto: {invited_at: 'not-a-date'}}]) {
    await t.test('uncertain provider result remains unknown with one send: ' + JSON.stringify(options), async () => {
      await fixture(options, async ({invoke, calls, db, recover}) => {
        const reply = await decoded(await invoke()); failure(reply, 503, 'invitation_delivery_unknown', 'delivery_unknown'); safe(reply);
        assert.equal([...db.records.values()][0].emailStatus, 'unknown'); await invoke(); assert.equal(calls.length, 1);
        const found = await decoded(await recover()); assert.equal(found.body.emailStatus, 'unknown'); safe(found);
      });
    });
  }
  await t.test('possibly committed provider send with lost acknowledgement remains unknown and is never replayed', async () => {
    let acceptedEffects = 0;
    await fixture({provider: () => {acceptedEffects++; throw new Error('synthetic committed provider reply lost');}}, async ({invoke, calls, recover}) => {
      const reply = await decoded(await invoke()); failure(reply, 503, 'invitation_delivery_unknown', 'delivery_unknown');
      const found = await decoded(await recover()); assert.equal(found.body.emailStatus, 'unknown');
      await invoke(); assert.equal(calls.length, 1); assert.equal(acceptedEffects, 1); safe(reply);
    });
  });
  await t.test('lost prepare acknowledgement returns operation-unknown and GET recovers original IDs without claiming', async () => {
    await fixture({losePrepareReply: true}, async ({invoke, db, calls, recover}) => {
      const reply = await decoded(await invoke()); failure(reply, 503, 'invitation_operation_unknown', 'operation_unknown');
      const row = [...db.records.values()][0], before = db.trace.length, found = await decoded(await recover());
      assert.equal(found.status, 200); assert.equal(found.body.found, true); assert.equal(found.body.requestId, row.requestId);
      assert.equal(found.body.id, row.id); assert.equal(found.body.emailStatus, 'unknown');
      assert.deepEqual(phases(db).slice(before), ['recover']); assert.equal(calls.length, 0);
    });
  });
  await t.test('lost claim acknowledgement does not send and leaves an unreplayed uncertain claim', async () => {
    await fixture({loseClaimReply: true}, async ({invoke, db, calls, recover}) => {
      const reply = await decoded(await invoke()); failure(reply, 503, 'invitation_operation_unknown', 'operation_unknown');
      assert.equal(db.claimed, 1); assert.equal(calls.length, 0);
      const again = await decoded(await invoke()); failure(again, 503, 'invitation_delivery_unknown', 'delivery_unknown');
      assert.equal(db.claimed, 1); assert.equal(calls.length, 0);
      assert.equal((await decoded(await recover())).body.emailStatus, 'unknown');
    });
  });
  await t.test('lost finish reply stays operation-unknown until GET reads actual committed acceptance', async () => {
    await fixture({loseFinishReply: true}, async ({invoke, db, calls, recover}) => {
      const reply = await decoded(await invoke()); failure(reply, 503, 'invitation_operation_unknown', 'operation_unknown'); safe(reply);
      assert.equal(reply.body.emailStatus, 'unknown'); assert.equal(calls.length, 1);
      const before = db.trace.length, found = await decoded(await recover());
      assert.equal(found.status, 200); assert.equal(found.body.found, true); assert.equal(found.body.emailStatus, 'accepted');
      assert.equal(found.body.requestId, reply.body.requestId); assert.equal(found.body.id, reply.body.id);
      assert.deepEqual(phases(db).slice(before), ['recover']);
      const replay = await decoded(await invoke()); assert.equal(replay.status, 200); assert.equal(replay.body.replayed, true);
      assert.equal(calls.length, 1); assert.equal(db.claimed, 1);
    });
  });
  for (const message of ['admin_invitation_authority', 'synthetic database private detail ' + SERVICE_KEY]) {
    await t.test('finalization failure after provider acceptance is operation-unknown: ' + message.split(' ')[0], async () => {
      await fixture({failBefore: {finish: message}}, async ({invoke, calls, db, recover}) => {
        const reply = await decoded(await invoke()); failure(reply, 503, 'invitation_operation_unknown', 'operation_unknown'); safe(reply);
        assert.equal(calls.length, 1); assert.equal([...db.records.values()][0].emailStatus, 'dispatching');
        assert.equal((await decoded(await recover())).body.emailStatus, 'unknown'); await invoke(); assert.equal(calls.length, 1);
      });
    });
  }
  for (const phase of ['prepare', 'claim']) await t.test('database authority refusal at ' + phase + ' prevents provider access', async () => {
    await fixture({failBefore: {[phase]: 'admin_invitation_authority'}}, async ({invoke, calls}) => {
      await assert.rejects(invoke(), apiError(403, 'admin_access_changed')); assert.equal(calls.length, 0);
    });
  });
  await t.test('revocation observed at claim prevents send after preparation', async () => {
    await fixture({revokedAtClaim: true}, async ({invoke, db, calls}) => {
      await assert.rejects(invoke(), apiError(403, 'admin_access_changed'));
      assert.deepEqual(phases(db), ['prepare', 'claim']); assert.equal(db.claimed, 0); assert.equal(calls.length, 0);
    });
  });
  await t.test('claim identity mismatch cannot dispatch provider data', async () => {
    await fixture({claimMismatch: true}, async ({invoke, calls}) => {
      const reply = await decoded(await invoke()); failure(reply, 503, 'invitation_operation_unknown', 'operation_unknown'); assert.equal(calls.length, 0);
    });
  });
  await t.test('status lookup for an unknown key is read-only and returns found=false', async () => {
    await fixture({}, async ({recover, db, calls}) => {
      const found = await decoded(await recover('never-seen-key'));
      assert.deepEqual(found, {status: 200, body: {ok: true, found: false}});
      assert.deepEqual(phases(db), ['recover']); assert.equal(db.records.size, 0); assert.equal(calls.length, 0);
    });
  });
  await t.test('status database failure never dispatches or invents an accepted receipt', async () => {
    await fixture({failBefore: {recover: 'synthetic database private detail ' + SERVICE_KEY}}, async ({recover, db, calls}) => {
      const reply = await decoded(await recover()); failure(reply, 503, 'invitation_operation_unknown', 'operation_unknown'); safe(reply);
      assert.deepEqual(phases(db), ['recover']); assert.equal(calls.length, 0);
    });
  });
  await t.test('unowned path and wrong method cannot reach SQL or provider', async () => {
    await fixture({}, async ({invoke, db, calls}) => {
      assert.equal(await invoke('/team/other'), null);
      await assert.rejects(invoke('/team/invite', {method: 'GET'}), apiError(405, 'method_not_allowed'));
      await assert.rejects(invoke('/team/invitation-status'), apiError(405, 'method_not_allowed'));
      assert.deepEqual(phases(db), []); assert.equal(calls.length, 0);
    });
  });
});
