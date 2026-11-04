import {wrapFixtureModule} from './helpers/fenced-module.js';
import {test} from './helpers/fenced-node-test.js';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {isAbsolute, join} from 'node:path';
import {pathToFileURL} from 'node:url';

// Actual controller + actual SMTP port; five strict synthetic SQL helper ports.
// Selection is supplied as a protected SQL result, not recreated from email.
// No SQL authority/locking, real provider, TLS, delivery or client proof.
const root = process.env.COLLECT_AUTH_SOURCE_ROOT;
assert.ok(typeof root === 'string' && isAbsolute(root), 'Provide the coherent actual _shared graph.');
const actual = async name => {if(name==='postgres.js')return import('./helpers/fenced-postgres.js');return wrapFixtureModule(name,await import(pathToFileURL(join(root, name)).href));};
const {handleAdminInvitationV2} = await actual('domain/admin_invitation_v2.js');
const {ApiError} = await actual('domain/core.js');
const {attestAdminEmailAccount}=await actual('domain/admin_email_policy.js');
const {createWorkspaceSmtpEmail} = await actual('workspace-smtp-email.js');

const NOW = 1_792_497_600;
const ORIGIN = 'https://platform-admin.collect.ikanisa.com';
const PROJECT = 'https://invitation-v2.synthetic.invalid';
const EMAIL = 'synthetic.staff@example.invalid';
const SENDER = 'info@ikanisa.com';
const OWNER_ID = '11111111-1111-4111-8111-111111111111';
const PUBLIC_ID = '22222222-2222-4222-8222-222222222222';
const PRINCIPAL = '33333333-3333-4333-8333-333333333333';
const STAFF = '44444444-4444-4444-8444-444444444444';
const MANAGED = '55555555-5555-4555-8555-555555555555';
const REQUEST_ID = '66666666-6666-4666-8666-666666666666';
const SOURCE_ID = '77777777-7777-4777-8777-777777777777';
const OTHER_ID = '88888888-8888-4888-8888-888888888888';
const KEY = 'v2-original-request-0001';
const SECRET_KEY = 'sb_secret_synthetic_v2_only';
const PASSWORD = 'synthetic-not-a-real-workspace-app-password';
const DETAIL = 'synthetic-private-provider-or-sql-detail';
const MIME_ID = '<synthetic-v2-operation@ikanisa.com>';
const BODY = {email: EMAIL, role: 'staff', displayName: 'Synthetic Staff'};
const OWNER = {id: OWNER_ID, public_id: PUBLIC_ID, token_hash: 'a'.repeat(64), origin: ORIGIN,
  role: 'owner', email: SENDER, permissions: ['admin_users.manage'], issued_assurance_level: 1, issued_mfa_at: null,principal_id:PRINCIPAL,auth_user_id:MANAGED,auth_session_id:SOURCE_ID,auth_version:1};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const clone = value => structuredClone(value);
const SQL = {
  prepare: 'SELECT private.admin_invitation_v2_prepare(?,?,?,?,?,?,?,?,?,?,?,?,?::uuid) AS result',
  claim: 'SELECT private.admin_invitation_v2_claim(?,?,?,?,?::uuid,?::uuid) AS result',
  finish: 'SELECT private.admin_invitation_v2_finish(?,?,?,?,?::uuid,?::uuid,?,?) AS result',
  recover: 'SELECT private.admin_invitation_v2_recover(?,?,?,?,?) AS result',
  list: 'SELECT private.admin_invitation_v2_list(?,?,?,?) AS result',
};
const smtpAccepted = extra => ({messageId: MIME_ID, response: '250 2.0.0 accepted',
  accepted: [EMAIL], rejected: [], rejectedErrors: [], envelope: {from: SENDER, to: [EMAIL]}, ...extra});

class Statement {
  constructor(db, sql) {this.db = db; this.sql = sql; this.args = [];}
  bind(...args) {this.args = args; return this;}
  first() {return this.db.transition(this.sql, this.args);}
}
class Database {
  constructor(options) {this.options = options; this.trace = []; this.violations = []; this.keys = new Map(); this.row = null; this.claims = 0;}
  must(condition, message) {if (!condition) {this.violations.push(message); throw new Error(message);}}
  equal(value, expected, message) {try {assert.deepEqual(value, expected);} catch {this.must(false, message);}}
  prepare(sql) {this.must(Object.values(SQL).includes(sql), 'Only the five closed v2 helper functions are allowed'); return new Statement(this, sql);}
  result(extra = {}) {return {result: {...clone(this.row), ...extra}};}
  async transition(sql, args) {
    const phase = Object.keys(SQL).find(key => SQL[key] === sql);
    this.trace.push({phase, args: clone(args)});
    this.equal(args.slice(0, 4), [OWNER_ID, OWNER.token_hash, ORIGIN, PUBLIC_ID], 'Actual captured actor tuple must reach every helper');
    this.must(args.length === {prepare: 13, claim: 6, finish: 8, recover: 5, list: 4}[phase], 'Closed helper arity');
    if (this.options.failBefore === phase) throw new Error(this.options.sqlError ?? DETAIL);
    if (phase === 'list') {
      const invitation = this.row ? clone(this.row) : this.makeRow('invite', STAFF, EMAIL, null);
      return {result: {permissionsByRole: {owner: ['admin_users.manage'], admin: [], staff: []},
        members: this.options.listMembers ?? [{id: invitation.id, email: EMAIL, role: 'staff', status: invitation.accessStatus, publicId: '001234',
          displayName: 'Synthetic Staff', createdAt: new Date(NOW * 1000).toISOString(),
          invitedAt: null, acceptedAt: null, invitation}]}};
    }
    if (phase === 'prepare') {
      const [, , , , key, operation, subject, newPrincipal, email, role, display, bodyHash, source] = args;
      this.must(UUID.test(subject) && UUID.test(newPrincipal) && /^[a-f0-9]{64}$/.test(bodyHash), 'Prepare receives fresh candidate IDs and a body hash');
      if (operation === 'invite') this.equal([email, role, display, source], [EMAIL, BODY.role, BODY.displayName, null], 'Closed Add Staff values');
      else {
        this.equal([email, role, display], [null, null, null], 'Existing staff routes cannot override identity or role');
        if (operation === 'resend') this.must(['accepted', 'rejected'].includes(this.options.qualifiedHistory), 'Resend fixture needs explicitly prequalified terminal history');
      }
      const retained = this.keys.get(key);
      if (retained) {
        if (retained.hash !== bodyHash || retained.operation !== operation) throw new Error('admin_invitation_idempotency_conflict');
        return this.result({duplicate: retained.duplicate, replayed: true});
      }
      if (this.row) {
        this.keys.set(key, {hash: bodyHash, operation, duplicate: true});
        return this.result({duplicate: true, replayed: true});
      }
      this.row = this.makeRow(operation, subject, email ?? EMAIL, source);
      this.keys.set(key, {hash: bodyHash, operation, duplicate: false});
      if (this.options.losePrepare) throw new Error(DETAIL);
      return this.result({replayed: false, duplicate: false});
    }
    if (phase === 'recover') return this.keys.has(args[4]) ? this.result({found: true, replayed: true, duplicate: this.keys.get(args[4]).duplicate}) : {result: {found: false}};
    this.must(this.row && args[4] === this.row.requestId, 'Claim/finish must retain the prepared request ID');
    if (phase === 'claim') {
      this.must(UUID.test(args[5]), 'Dispatch nonce is a server UUID');
      if (this.options.denyClaim) throw new Error('admin_invitation_authority');
      if (this.options.claimState) {this.row.emailStatus = this.options.claimState; return this.result({claimed: false});}
      const claimed = this.row.emailStatus === 'reserved' && !this.claim;
      if (claimed) {this.claim = args[5]; this.row.emailStatus = 'dispatching'; this.claims++;}
      if (this.options.loseClaim) throw new Error(DETAIL);
      return this.result({claimed: this.options.loseRace ? false : claimed,
        ...(this.options.claimOverride ?? {})});
    }
    this.must(args[5] === this.claim, 'Finish uses the exact dispatch nonce');
    this.must(['accepted', 'rejected', 'unknown', 'already_registered'].includes(args[6]), 'Closed terminal state');
    this.must([null, 'provider_rejected', 'provider_outcome_unknown', 'provider_response_unconfirmed', 'email_exists'].includes(args[7]), 'No raw provider/SQL error enters a receipt');
    this.row.emailStatus = args[6]; this.safeError = args[7];
    if (this.options.loseFinish) throw new Error(DETAIL);
    return this.result();
  }
  makeRow(operation, subject, email, source) {
    const kind = this.options.messageKind ?? 'access_notice';
    return {contractVersion: 2, id: subject, requestId: REQUEST_ID, principalId: PRINCIPAL,
      email, emailStatus: this.options.initialState ?? 'reserved', accessStatus: kind === 'access_notice' ? 'active' : 'invited',
      operation, messageKind: kind, templateVersion: kind === 'access_notice' ? 'access_notice_v1' : 'managed_invite_v1',
      managedAuthUserId: kind === 'access_notice' ? MANAGED : this.options.nativeManagedId ?? null,
      noticeOrigin: kind === 'access_notice' ? this.options.noticeOrigin ?? ORIGIN : null,
      sourceRequestId: source, duplicate: false, replayed: false};
  }
}
function request(path, {method = 'POST', key = KEY, body = BODY} = {}) {
  return new Request(ORIGIN + '/api/admin' + path, {method,
    headers: {'Content-Type': 'application/json', Origin: ORIGIN, ...(key === null ? {} : {'Idempotency-Key': key})},
    ...(method === 'GET' ? {} : {body: JSON.stringify(body)})});
}
async function decoded(response) {assert.ok(response instanceof Response); return {status: response.status, body: await response.json()};}
async function fixture(options, check) {
  const db = new Database(options), http = [], smtp = [], constructions = [], completions = [], deadlines = [];
  let sentReady; const sendReady = new Promise(resolve => {sentReady = resolve;});
  const env = {DB: db, SUPABASE_URL: PROJECT, SUPABASE_SERVICE_ROLE_KEY: SECRET_KEY};
  const enableNotice = () => {
    const binding = createWorkspaceSmtpEmail({COLLECT_NOTICE_SMTP_PASSWORD: PASSWORD}, {createTransport(config) {
      constructions.push(config);
      return {async sendMail(mail) {smtp.push(mail); sentReady(); return options.smtpReply ? options.smtpReply(mail) : smtpAccepted();}, close() {}};
    }});
    env.AUTH_EMAIL_FROM = SENDER;
    env.AUTH_EMAIL = {provider: binding.provider, send(message) {const promise = binding.send(message); completions.push(promise); return promise;}};
  };
  if (!options.missingNotice) enableNotice();
  if (options.noticeMarker) {env.AUTH_EMAIL_FROM = SENDER; env.AUTH_EMAIL = {provider: 'workspace_smtp_v1', unavailable: true};}
  if (options.foreignNotice) {env.AUTH_EMAIL_FROM = SENDER; env.AUTH_EMAIL = {provider: 'legacy_http', send() {throw new Error('Wrong provider must not run');}};}
  const previousFetch = globalThis.fetch, previousNow = Date.now;
  const previousSet = globalThis.setTimeout, previousClear = globalThis.clearTimeout;
  Date.now = () => NOW * 1000;
  if (options.captureDeadline) {
    globalThis.setTimeout = (callback, milliseconds) => {if(milliseconds!==10000)return previousSet(callback,milliseconds);const timer = {callback, milliseconds}; deadlines.push(timer); return timer;};
    globalThis.clearTimeout = timer => {if(!deadlines.includes(timer))previousClear(timer);};
  }
  globalThis.fetch = async (input, init) => {
    const req = new Request(input, init), call = {url: req.url, method: req.method, headers: req.headers,
      redirect: req.redirect, signal: init.signal, body: JSON.parse(init.body)};
    http.push(call);
    if (options.nativeReply) return options.nativeReply(call);
    return Response.json({id: MANAGED, email: EMAIL, email_confirmed_at: null, invited_at: new Date(NOW * 1000).toISOString()});
  };
  const invoke = (path = '/team/v2/invite', {body = BODY, account = OWNER, emailAt=NOW-2, emailProof=true, ...controls} = {}) => {
    if(emailProof&&account)attestAdminEmailAccount(account,{contract_version:1,public_session_id:account.public_id,email_verified_at:emailAt,proof_id:MANAGED});
    return handleAdminInvitationV2(request(path, {...controls, body}), env, account, body, path);
  };
  try {await check({db, env, invoke, http, smtp, constructions, completions, enableNotice, deadlines, sendReady});}
  finally {
    globalThis.fetch = previousFetch; Date.now = previousNow;
    globalThis.setTimeout = previousSet; globalThis.clearTimeout = previousClear;
    assert.deepEqual(db.violations, []);
    for (const call of http) {
      assert.equal(call.url, PROJECT + '/auth/v1/invite'); assert.equal(call.method, 'POST');
      assert.equal(call.redirect, 'error'); assert.ok(call.signal instanceof AbortSignal);
      assert.equal(call.headers.get('apikey'), SECRET_KEY); assert.equal(call.headers.has('Authorization'), false);
      assert.deepEqual(call.body, {email: EMAIL, data: {collect_invitation: true}});
    }
  }
}
const error = (status, code) => value => value instanceof ApiError && value.status === status && value.code === code;
const phases = db => db.trace.map(call => call.phase);
function safePublic(body) {
  const text = JSON.stringify(body);
  for (const value of [PRINCIPAL, MANAGED, PASSWORD, SECRET_KEY, OWNER.token_hash, DETAIL]) assert.equal(text.includes(value), false);
  for (const key of ['principalId', 'managedAuthUserId', 'claim', 'claimNonce', 'noticeOrigin', 'templateVersion']) assert.equal(Object.hasOwn(body, key), false);
}
function failure(reply, status, code, outcome) {
  assert.equal(reply.status, status); assert.equal(reply.body.ok, false);
  assert.equal(reply.body.error.code, code); if (outcome) assert.equal(reply.body.outcome, outcome); safePublic(reply.body);
}

test('actual versioned staff invitation controller', {concurrency: false}, async t => {
  await t.test('frozen v1 routes are never intercepted', async () => fixture({}, async f => {
    for (const path of ['/team/invite', '/team/invitation-status', '/team/' + STAFF + '/resend', '/team'])
      assert.equal(await f.invoke(path, {account: null}), null);
    assert.deepEqual(f.db.trace, []); assert.deepEqual(f.http, []); assert.deepEqual(f.smtp, []);
  }));
  for (const [name, change] of [
    ['non-owner', {role: 'admin'}], ['wrong owner identity', {email: EMAIL}],
    ['missing permission', {permissions: []}],
  ]) await t.test(name + ' has no DB/provider effect', async () => fixture({}, async f => {
    await assert.rejects(f.invoke(undefined, {account: {...OWNER, ...change}}), error(403, 'owner_required'));
    assert.deepEqual(f.db.trace, []); assert.deepEqual(f.http, []); assert.deepEqual(f.smtp, []);
  }));
  for(const emailAt of [null,NOW-301])await t.test('missing/stale email proof has no SQL/provider effect: '+emailAt,async()=>fixture({},async f=>{
    const candidate={...OWNER};if(emailAt===null)attestAdminEmailAccount(candidate,{contract_version:1,public_session_id:PUBLIC_ID,email_verified_at:null,proof_id:null});
    await assert.rejects(f.invoke(undefined,{account:candidate,emailProof:emailAt!==null,emailAt}),error(403,'recent_email_sign_in_required'));
    assert.deepEqual(f.db.trace,[]);assert.deepEqual(f.http,[]);assert.deepEqual(f.smtp,[]);
  }));
  await t.test('AAL1 without authenticator is accepted with independent email proof',async()=>fixture({},async f=>{
    const reply=await decoded(await f.invoke(undefined,{account:{...OWNER,issued_assurance_level:1,issued_mfa_at:null}}));assert.equal(reply.status,200);
  }));
  await t.test('proof expiry at SQL admission keeps dedicated recent-email recovery',async()=>fixture({failBefore:'prepare',sqlError:'recent_email_sign_in_required'},async f=>{
    await assert.rejects(f.invoke(),error(403,'recent_email_sign_in_required'));assert.deepEqual(f.http,[]);assert.deepEqual(f.smtp,[]);
  }));
  for (const key of [null, 'short', 'invalid key']) await t.test('missing/invalid stable key is refused: ' + String(key), async () => fixture({}, async f => {
    await assert.rejects(f.invoke(undefined, {key}), error(400, 'invitation_request_key_required')); assert.deepEqual(f.db.trace, []);
  }));
  for (const body of [{...BODY, messageKind: 'auth_invite'}, {...BODY, subject: 'Override'}, {...BODY, loginUrl: 'https://other.invalid/'}, {...BODY, role: 'owner'}])
    await t.test('caller cannot choose kind/content/privilege: ' + Object.keys(body).at(-1), async () => fixture({}, async f => {
      await assert.rejects(f.invoke(undefined, {body}), error(400, 'invalid_invitation')); assert.deepEqual(f.db.trace, []);
    }));
  for (const email of ['.staff@example.invalid', 'staff.@example.invalid', 'staff..member@example.invalid',
    'staff@-example.invalid', 'staff@example-.invalid', 'staff@example..invalid', 'staff\u0000@example.invalid'])
    await t.test('unsupported mailbox is refused before prepare: ' + JSON.stringify(email), async () => fixture({}, async f => {
      await assert.rejects(f.invoke(undefined, {body: {...BODY, email}}), error(400, 'invalid_invitation'));
      assert.deepEqual(f.db.trace, []); assert.equal(f.http.length, 0); assert.equal(f.smtp.length, 0);
    }));
  await t.test('SQL-selected notice uses actual SMTP port, fixed token-free content and a typed public receipt', async () => fixture({}, async f => {
    const reply = await decoded(await f.invoke()); assert.equal(reply.status, 200); assert.equal(reply.body.outcome, 'accepted');
    assert.equal(reply.body.contractVersion, 2); assert.equal(reply.body.messageKind, 'access_notice');
    assert.equal(reply.body.noticeStatus, 'accepted'); assert.equal(Object.hasOwn(reply.body, 'emailStatus'), false); safePublic(reply.body);
    assert.equal(f.http.length, 0); assert.equal(f.smtp.length, 1);
    const mail = f.smtp[0]; assert.equal(mail.subject, 'Your invitation to Collect');
    assert.equal(mail.text, `You have been invited to Collect.\n\nOpen Collect and sign in with the email address that received this invitation. Request a secure sign-in code to continue.\n\nOpen Collect: ${ORIGIN}/#/admin/login\n\nThis invitation does not sign you in. If you were not expecting it, contact your super admin.\n\nCollect\ninfo@ikanisa.com\n`);
    assert.equal(createHash('sha256').update(mail.html).digest('hex'), 'bdb4e31a4c60b980794eab3730a9f5b3a73f839b3bc01934f4a2d4f53ceaae98',
      'Controller forwards every approved HTML byte after ordinary-link substitution');
    assert.deepEqual(mail.envelope, {from: SENDER, to: [EMAIL]});
    assert.deepEqual(mail.text.match(/https:\/\/\S+/g), [ORIGIN + '/#/admin/login']);
    assert.equal(/password|recovery|magic|access_token|refresh_token|\b\d{6}\b/i.test(mail.text), false);
    assert.deepEqual(phases(f.db), ['prepare', 'claim', 'finish']); assert.equal(f.db.claims, 1);
  }));
  await t.test('SQL-selected native invitation never uses SMTP', async () => fixture({messageKind: 'auth_invite'}, async f => {
    const reply = await decoded(await f.invoke()); assert.equal(reply.status, 200); assert.equal(reply.body.emailStatus, 'accepted');
    assert.equal(reply.body.messageKind, 'auth_invite'); assert.equal(Object.hasOwn(reply.body, 'noticeStatus'), false);
    assert.equal(f.http.length, 1); assert.equal(f.smtp.length, 0); safePublic(reply.body);
  }));
  await t.test('unknown native dispatch never falls back to SMTP and same-key replay does not send again', async () => fixture({messageKind: 'auth_invite',
    nativeReply: () => {throw new Error(DETAIL + ' ' + SECRET_KEY);}}, async f => {
    failure(await decoded(await f.invoke()), 503, 'invitation_delivery_unknown', 'delivery_unknown');
    failure(await decoded(await f.invoke()), 503, 'invitation_delivery_unknown', 'delivery_unknown');
    assert.equal(f.http.length, 1); assert.equal(f.smtp.length, 0); assert.equal(f.db.claims, 1);
  }));
  for (const options of [{missingNotice: true}, {noticeMarker: true}, {foreignNotice: true}])
    await t.test('non-sendable notice transport is checked before claim and SAME key can resume', async () => fixture(options, async f => {
      const first = await decoded(await f.invoke()); failure(first, 503, 'invitation_transport_unavailable', 'transport_unavailable');
      const retained = first.body.requestId; assert.deepEqual(phases(f.db), ['prepare']); assert.equal(f.db.claims, 0);
      assert.equal(f.db.row.emailStatus, 'reserved'); assert.equal(f.smtp.length, 0); assert.equal(f.http.length, 0);
      f.enableNotice(); const resumed = await decoded(await f.invoke()); assert.equal(resumed.status, 200);
      assert.equal(resumed.body.requestId, retained); assert.equal(resumed.body.noticeStatus, 'accepted');
      assert.equal(f.db.claims, 1); assert.equal(f.smtp.length, 1);
    }));
  await t.test('retained foreign notice origin is never silently rewritten or claimed', async () => fixture({noticeOrigin: 'https://qa-admin.collect.ikanisa.com'}, async f => {
    failure(await decoded(await f.invoke()), 503, 'invitation_transport_unavailable', 'transport_unavailable');
    assert.deepEqual(phases(f.db), ['prepare']); assert.equal(f.smtp.length, 0); assert.equal(f.http.length, 0);
  }));
  await t.test('new-key duplicate of reserved notice returns conflict without claiming', async () => fixture({missingNotice: true}, async f => {
    await f.invoke(); f.enableNotice();
    const duplicate = await decoded(await f.invoke(undefined, {key: KEY + '-alias'}));
    failure(duplicate, 409, 'invitation_existing_request', 'existing_request'); assert.equal(duplicate.body.requestId, REQUEST_ID);
    assert.equal(f.db.claims, 0); assert.equal(f.smtp.length, 0);
  }));
  await t.test('accepted same-key replay is known receipt only; new-key alias never becomes acceptance', async () => fixture({}, async f => {
    await f.invoke(); const replay = await decoded(await f.invoke()); assert.equal(replay.status, 200); assert.equal(replay.body.outcome, 'accepted');
    failure(await decoded(await f.invoke(undefined, {key: KEY + '-alias'})), 409, 'invitation_existing_request', 'existing_request');
    assert.equal(f.smtp.length, 1); assert.equal(f.db.claims, 1);
  }));
  await t.test('a lost claim race does not send', async () => fixture({loseRace: true}, async f => {
    failure(await decoded(await f.invoke()), 503, 'invitation_delivery_unknown', 'delivery_unknown');
    assert.equal(f.smtp.length, 0); assert.equal(f.http.length, 0); assert.equal(phases(f.db).includes('finish'), false);
  }));
  for (const override of [
    {email: 'other@example.invalid'}, {managedAuthUserId: OTHER_ID},
    {noticeOrigin: 'https://qa-admin.collect.ikanisa.com'},
    {messageKind: 'auth_invite', templateVersion: 'managed_invite_v1', noticeOrigin: null},
  ]) await t.test('prepared-to-claim descriptor mutation stops before provider: ' + Object.keys(override)[0], async () => fixture({claimOverride: override}, async f => {
    failure(await decoded(await f.invoke()), 503, 'invitation_operation_unknown', 'operation_unknown');
    assert.equal(f.smtp.length, 0); assert.equal(f.http.length, 0); assert.equal(phases(f.db).includes('finish'), false);
  }));
  await t.test('current SQL authority denial at claim is not treated as transport failure or acceptance', async () => fixture({denyClaim: true}, async f => {
    await assert.rejects(f.invoke(), error(403, 'admin_access_changed')); assert.equal(f.smtp.length, 0); assert.equal(f.http.length, 0);
  }));
  await t.test('actual SMTP port refuses generated-ID-only result; controller records unknown and never resends', async () => fixture({smtpReply: () => ({messageId: MIME_ID})}, async f => {
    const reply = await decoded(await f.invoke()); failure(reply, 503, 'invitation_delivery_unknown', 'delivery_unknown');
    assert.equal(reply.body.noticeStatus, 'unknown'); assert.equal(f.db.row.emailStatus, 'unknown');
    await f.invoke(); assert.equal(f.smtp.length, 1); assert.equal(f.db.claims, 1); assert.equal(f.http.length, 0);
  }));
  await t.test('lost claim acknowledgment preserves IDs and never retries an unconfirmed claim', async () => fixture({loseClaim: true}, async f => {
    const reply = await decoded(await f.invoke()); failure(reply, 503, 'invitation_operation_unknown', 'operation_unknown');
    assert.equal(reply.body.requestId, REQUEST_ID); await f.invoke();
    assert.equal(f.smtp.length, 0); assert.equal(f.http.length, 0); assert.equal(f.db.claims, 1);
  }));
  await t.test('lost finish acknowledgment returns unknown; read-only original-key recovery does not send', async () => fixture({loseFinish: true}, async f => {
    const reply = await decoded(await f.invoke()); failure(reply, 503, 'invitation_operation_unknown', 'operation_unknown');
    assert.equal(reply.body.requestId, REQUEST_ID); assert.equal(reply.body.noticeStatus, 'unknown');
    const before = f.db.trace.length;
    const recovered = await decoded(await f.invoke('/team/v2/invitation-status', {method: 'GET', body: {}}));
    assert.equal(recovered.status, 200); assert.equal(recovered.body.found, true); assert.equal(recovered.body.noticeStatus, 'accepted');
    assert.equal(Object.hasOwn(recovered.body, 'outcome'), false); assert.deepEqual(phases(f.db).slice(before), ['recover']);
    assert.equal(f.smtp.length, 1); assert.equal(f.http.length, 0); safePublic(recovered.body);
  }));
  await t.test('late SMTP completion after observational timeout has no receipt-upgrade or retry authority', async () => {
    let resolveSend; const pending = new Promise(resolve => {resolveSend = resolve;});
    try {await fixture({captureDeadline: true, smtpReply: () => pending}, async f => {
      const operation = f.invoke(); await f.sendReady;
      assert.equal(f.deadlines.length, 1); assert.equal(f.deadlines[0].milliseconds, 10000); f.deadlines[0].callback();
      failure(await decoded(await operation), 503, 'invitation_delivery_unknown', 'delivery_unknown');
      assert.equal(f.db.row.emailStatus, 'unknown'); const finishes = phases(f.db).filter(phase => phase === 'finish').length;
      resolveSend(smtpAccepted()); await f.completions[0];
      assert.equal(f.db.row.emailStatus, 'unknown'); assert.equal(phases(f.db).filter(phase => phase === 'finish').length, finishes);
      await f.invoke(); assert.equal(f.smtp.length, 1); assert.equal(f.http.length, 0);
    });} finally {resolveSend(smtpAccepted());}
  });
  await t.test('native confirmed-after-prepare remains native notification_pending with no SMTP fallback', async () => fixture({messageKind: 'auth_invite', claimState: 'already_registered'}, async f => {
    const reply = await decoded(await f.invoke()); failure(reply, 409, 'invitation_notification_required', 'notification_pending');
    assert.equal(reply.body.messageKind, 'auth_invite'); assert.equal(f.http.length, 0); assert.equal(f.smtp.length, 0); assert.equal(f.db.claims, 0);
  }));
  await t.test('repair forwards explicit source lineage through the 13th argument and emits a distinct notice receipt', async () => fixture({}, async f => {
    const reply = await decoded(await f.invoke('/team/v2/' + STAFF + '/access-notice', {body: {sourceRequestId: SOURCE_ID}}));
    assert.equal(reply.status, 200); assert.equal(reply.body.operation, 'notice_repair'); assert.equal(reply.body.sourceRequestId, SOURCE_ID);
    const args = f.db.trace[0].args; assert.equal(args[5], 'notice_repair'); assert.equal(args[6], STAFF); assert.equal(args[12], SOURCE_ID);
    assert.equal(f.smtp.length, 1); assert.equal(f.http.length, 0);
  }));
  await t.test('resend forwards only the retained staff target; a body override is rejected', async () => fixture({qualifiedHistory: 'accepted'}, async f => {
    await assert.rejects(f.invoke('/team/v2/' + STAFF + '/resend', {body: {email: 'other@example.invalid'}}), error(400, 'invalid_invitation'));
    assert.deepEqual(f.db.trace, []);
    const reply = await decoded(await f.invoke('/team/v2/' + STAFF + '/resend', {body: {}}));
    assert.equal(reply.status, 200); assert.equal(reply.body.operation, 'resend'); assert.equal(f.db.trace[0].args[6], STAFF);
  }));
  await t.test('typed team overview is owner-only metadata and needs no mutation key', async () => fixture({}, async f => {
    const reply = await decoded(await f.invoke('/team/v2', {method: 'GET', key: null, body: {}}));
    assert.equal(reply.status, 200); assert.equal(reply.body.contractVersion, 2);
    assert.equal(reply.body.members[0].invitation.messageKind, 'access_notice');
    assert.equal(reply.body.members[0].invitation.noticeStatus, 'unknown');
    assert.equal(Object.hasOwn(reply.body.members[0].invitation, 'emailStatus'), false);
    assert.equal(reply.body.members[0].publicId, '001234');
    safePublic(reply.body.members[0].invitation); assert.deepEqual(phases(f.db), ['list']);
    assert.equal(f.smtp.length, 0); assert.equal(f.http.length, 0);
  }));
  await t.test('typed list preserves exact linked owner/staff public IDs and explicit null for an unlinked account', async () => {
    const member = (id, email, role, publicId) => ({id, email, role, publicId, status: 'active',
      displayName: 'Synthetic account', createdAt: new Date(NOW * 1000).toISOString(), invitedAt: null, acceptedAt: null, invitation: null});
    const members = [member(OWNER_ID, SENDER, 'owner', '000001'), member(STAFF, EMAIL, 'staff', '001234'),
      member(OTHER_ID, 'unlinked@example.invalid', 'admin', null)];
    await fixture({listMembers: members}, async f => {
      const reply = await decoded(await f.invoke('/team/v2', {method: 'GET', key: null, body: {}}));
      assert.equal(reply.status, 200);
      assert.deepEqual(reply.body.members.map(row => [row.id, row.publicId]),
        [[OWNER_ID, '000001'], [STAFF, '001234'], [OTHER_ID, null]]);
      assert.ok(reply.body.members.every(row => Object.hasOwn(row, 'publicId')));
      assert.deepEqual(phases(f.db), ['list']); assert.equal(f.smtp.length, 0); assert.equal(f.http.length, 0);
    });
  });
  await t.test('the public ID projector preserves opaque string bytes rather than trimming or casting', async () => fixture({listMembers: [{
    id: STAFF, email: EMAIL, role: 'staff', status: 'active', publicId: ' 001234 ', displayName: null,
    createdAt: new Date(NOW * 1000).toISOString(), invitedAt: null, acceptedAt: null, invitation: null}]}, async f => {
    const reply = await decoded(await f.invoke('/team/v2', {method: 'GET', key: null, body: {}}));
    assert.equal(reply.status, 200); assert.equal(reply.body.members[0].publicId, ' 001234 ');
  }));
  for (const [name, value] of [['number', 1234], ['empty', ''], ['NUL', '00\u0000001'],
    ['DEL', '00\u007f001'], ['C1', '00\u0085001'], ['oversized', '0'.repeat(65)], ['missing', undefined]])
    await t.test('invalid or absent public ID fails closed rather than inventing a fallback: ' + name, async () => {
      const member = {id: STAFF, email: EMAIL, role: 'staff', status: 'active', displayName: null,
        createdAt: new Date(NOW * 1000).toISOString(), invitedAt: null, acceptedAt: null, invitation: null,
        ...(name === 'missing' ? {} : {publicId: value})};
      await fixture({listMembers: [member]}, async f => {
        failure(await decoded(await f.invoke('/team/v2', {method: 'GET', key: null, body: {}})), 503, 'invitation_list_unknown');
        assert.deepEqual(phases(f.db), ['list']); assert.equal(f.smtp.length, 0); assert.equal(f.http.length, 0);
      });
    });
  await t.test('adding public IDs does not bypass fresh owner email proof for the list', async () => fixture({}, async f => {
    await assert.rejects(f.invoke('/team/v2', {method: 'GET', key: null, body: {},
      account: {...OWNER},emailAt:NOW-301}), error(403, 'recent_email_sign_in_required'));
    assert.deepEqual(f.db.trace, []); assert.equal(f.http.length, 0); assert.equal(f.smtp.length, 0);
  }));
});
