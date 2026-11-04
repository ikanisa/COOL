import {loadReviewedPlatformFixture} from '../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import {initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest} from './helpers/fenced-unit.js';
import {wrapFixtureModule} from './helpers/fenced-module.js';
import {fixtureAdminAccount,establishInitialAdminEmail,adminEmailFixtureDatabase} from './helpers/admin-email-fixture.js';
import assert from 'node:assert/strict';
import {isAbsolute, join} from 'node:path';
import {pathToFileURL} from 'node:url';

// Local integration qualification. Root alone executes real PostgreSQL. Managed
// fixture rows and intercepted SMTP/Auth HTTP prove no live send, TLS, inbox,
// provider signature or client acceptance. Permit only 127.0.0.1:55439 network.
const database = Deno.env.get('COLLECT_INVITATION_NOTICE_TEST_DATABASE_URL');
const sourceRoot = Deno.env.get('COLLECT_AUTH_SOURCE_ROOT');
assert.ok(sourceRoot && isAbsolute(sourceRoot), 'Use the absolute actual _shared graph being qualified.');
const actual = async (name: string) => {if(name==='postgres.js')return import('./helpers/fenced-postgres.js');return wrapFixtureModule(name,await import(pathToFileURL(join(sourceRoot, name)).href));};
const {connection, PostgresDatabase} = await actual('postgres.js');
const {digest} = await actual('domain/core.js');
const {handleAdminInvitationV2} = await actual('domain/admin_invitation_v2.js');
const {handleAdminAccounts} = await actual('domain/admin_accounts.js');
const {encrypt} = await actual('domain/encryption.js');
const {createWorkspaceSmtpEmail} = await actual('workspace-smtp-email.js');
const {inventoryPrivateRetention} = await actual('private-retention.js');

fencedTest({name: 'actual V2 invitation journal and callers keep locked notice selection, original intents and owner authority',
  ignore: !database, sanitizeOps: false, sanitizeResources: false, fn: async t => {
    const url = new URL(database!);
    assert.equal(url.hostname, '127.0.0.1'); assert.ok(url.port==='55439'||(Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'&&['55441','55443'].includes(url.port)));
    assert.equal(url.pathname, '/collect_invitation_notice_test');
    const adminUrl = new URL(url); adminUrl.pathname = '/postgres';
    const admin = connection(adminUrl.href);
    if (!(await admin`SELECT 1 FROM pg_database WHERE datname='collect_invitation_notice_test'`).length)
      await admin.unsafe('CREATE DATABASE collect_invitation_notice_test');
    await admin.end();
    const sql = connection(database!), originalFetch = globalThis.fetch;
    try {
      const setup = await sql.reserve();
      try {
        await setup.unsafe('DROP SCHEMA IF EXISTS api,private,app,auth,realtime CASCADE');
        await setup.unsafe(await Deno.readTextFile(new URL('../../../tests/sql/00_local_auth_fixture.sql', import.meta.url)));
        await setup.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
        const reviewedPlatform=await loadReviewedPlatformFixture(new URL('../../../../',import.meta.url));
        assert.ok(reviewedPlatform.names.some(name => name.endsWith('_collect_admin_invitation_access_notice_v2.sql')),
          'The canonical migration chain must include the additive V2 invitation migration.');
        await reviewedPlatform.apply(text => setup.unsafe(text));
      } finally {setup.release();await initializeSqlFixture(sql);}

      const auth = crypto.randomUUID(), principal = crypto.randomUUID(), staff = crypto.randomUUID(), factor = crypto.randomUUID();
      const stamp = new Date().toISOString(), at = Math.floor(Date.now() / 1000) - 1, origin = 'https://admin-notice.example';
      let publicId = 950000;
      await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${auth},'info@ikanisa.com',now())`;
      await sql`INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at)
        VALUES(${principal},'info@ikanisa.com',${String(++publicId)},'Synthetic Owner','operator',${stamp},${stamp})`;
      await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES(${auth},${principal},'synthetic-notice-owner')`;
      await sql`INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at)
        VALUES(${staff},'info@ikanisa.com','owner','active','synthetic-managed','Synthetic Owner',app.unixepoch(),app.unixepoch())`;
      await sql`INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)
        VALUES(${staff},${principal},'synthetic-fixture',${stamp})`;
      await sql`INSERT INTO auth.mfa_factors(id,user_id,status) VALUES(${factor},${auth},'verified')`;

      let browserNumber=0;
      async function browser(label: string, browserOrigin = origin) {
        const session = crypto.randomUUID(), publicSession = crypto.randomUUID(), cookie = await digest('synthetic-notice-cookie-' + label), hash = await digest(cookie);
        const initialAt=at-127+61*(browserNumber++);
        await sql`INSERT INTO auth.sessions(id,user_id,aal,factor_id) VALUES(${session},${auth},'aal2',${factor})`;
        await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at) VALUES(${session},'totp',to_timestamp(${at}))`;
        await sql`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)
          VALUES(${session},${principal},'admin',${initialAt},${initialAt},app.unixepoch()+3600)`;
        const claims = {sub: auth, session_id: session, role: 'authenticated', aal: 'aal2', amr: [{method: 'otp', timestamp: initialAt}, {method: 'totp', timestamp: at}]};
        const db = new PostgresDatabase(sql, claims);
        if (label === 'first') await sql`INSERT INTO app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter)
          VALUES(${factor},${principal},'Synthetic','{"managed_by":"supabase"}','verified',${at},${session},${at},0)`;
        await db.prepare('SELECT private.record_mfa_projection(?::uuid)').bind(factor).first();
        await db.prepare('UPDATE app.auth_sessions SET assurance_level=2,mfa_at=?,mfa_factor_id=? WHERE id=?').bind(at, factor, session).run();
        await sql`INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
          SELECT ${hash},${publicSession},a.id,a.auth_version,${session},${browserOrigin},s.auth_at,s.expires_at
          FROM app.admin_users a CROSS JOIN app.auth_sessions s WHERE a.id=${staff} AND s.id=${session}`;
        await sql`UPDATE app.admin_sessions SET issued_assurance_level=2,issued_mfa_at=${at},issued_mfa_factor_id=${factor} WHERE token_hash=${hash}`;
        await sql`INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext) VALUES(${hash},${auth},${session},'{}')`;
        const args=[staff,hash,browserOrigin,publicSession],account=await fixtureAdminAccount(sql,db,args);
        await establishInitialAdminEmail(sql,db,account);
        return {session,hash,cookie,claims,rawDb:db,db:adminEmailFixtureDatabase(db,account),args,account};
      }
      const owner = await browser('first'), second = await browser('second'), foreignOrigin = await browser('third', 'https://other-admin.example');
      const snapshots = async (request: string) => JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts WHERE request_id=${request}`);
      const counts = async () => (await sql`SELECT (SELECT count(*)::int FROM app.users) AS users,
        (SELECT count(*)::int FROM auth.users) AS managed,(SELECT count(*)::int FROM private.auth_principal_links) AS links`)[0];
      const rejects = (action: () => Promise<unknown>, message: string) => assert.rejects(action, (error: any) => error.message === message);
      const prepare = (key: string, email: string | null, options: any = {}, b = owner) => b.db.prepare('SELECT private.admin_invitation_v2_prepare(?,?,?,?,?,?,?,?,?,?,?,?,?::uuid) AS result')
        .bind(...b.args, key, options.kind ?? 'invite', options.subject ?? crypto.randomUUID(), crypto.randomUUID(), email,
          email === null ? null : 'staff', email === null ? null : 'Synthetic notice', options.bodyHash ?? 'b'.repeat(64), options.source ?? null).first('result');
      const recover = (key: string, b = owner) => b.db.prepare('SELECT private.admin_invitation_v2_recover(?,?,?,?,?) AS result').bind(...b.args, key).first('result');
      const claim = (request: string, nonce: string, b = owner) => b.db.prepare('SELECT private.admin_invitation_v2_claim(?,?,?,?,?::uuid,?::uuid) AS result').bind(...b.args, request, nonce).first('result');
      const finish = (request: string, nonce: string, state: string, b = owner, error: string | null = null) => b.db.prepare('SELECT private.admin_invitation_v2_finish(?,?,?,?,?::uuid,?::uuid,?,?) AS result').bind(...b.args, request, nonce, state, error).first('result');
      const v1Prepare = (key: string, email: string) => owner.db.prepare('SELECT private.admin_invitation_prepare(?,?,?,?,?,?,?,?,?,?,?,?) AS result')
        .bind(...owner.args, key, 'invite', crypto.randomUUID(), crypto.randomUUID(), email, 'staff', 'Synthetic notice', 'c'.repeat(64)).first('result');
      async function mapped(label: string) {
        const managed = crypto.randomUUID(), member = crypto.randomUUID(), email = label + '@notice.example.test';
        await sql`INSERT INTO app.users(id,email,public_id,created_at,updated_at) VALUES(${member},${email},${String(++publicId)},${stamp},${stamp})`;
        await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${managed},${email},now())`;
        await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES(${managed},${member},'synthetic-notice-member')`;
        return {managed, member, email};
      }
      const smtpMessages: any[] = [], nativeMessages: any[] = [];
      let smtpOutcome: 'accepted' | 'id_only' | 'throw' = 'accepted', nativeOutcome: 'accepted' | 'unknown' = 'accepted';
      let smtpHook: (() => Promise<void>) | null = null;
      const smtp = createWorkspaceSmtpEmail({COLLECT_NOTICE_SMTP_PASSWORD: 'synthetic-private-fixture-only'}, {createTransport(options: any) {
        assert.equal(options.host, 'smtp.gmail.com'); assert.equal(options.port, 465); assert.equal(options.secure, true);
        assert.equal(options.tls.rejectUnauthorized, true); assert.equal(options.pool, false);
        return {async sendMail(message: any) {
          smtpMessages.push(structuredClone(message));
          assert.deepEqual(message.envelope, {from: 'info@ikanisa.com', to: [message.to.address]});
          assert.equal(message.subject, 'Your invitation to Collect');
          assert.ok(message.text.includes(origin + '/#/admin/login')); assert.ok(!/token=|password=|\b\d{6}\b/.test(message.text));
          if (smtpHook) await smtpHook();
          if (smtpOutcome === 'throw') throw Error('Synthetic private SMTP reply');
          if (smtpOutcome === 'id_only') return {messageId: '<generated-only@synthetic.invalid>'};
          return {response: '250 2.0.0 Synthetic DATA accepted', accepted: [message.to.address], rejected: [],
            envelope: {from: 'info@ikanisa.com', to: [message.to.address]}, messageId: '<accepted@synthetic.invalid>'};
        }, close() {}};
      }});
      globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
        const request = new Request(input, init);
        assert.equal(request.url, 'https://synthetic-notice-auth.example/auth/v1/invite', 'All other HTTP is denied');
        assert.equal(request.method, 'POST'); assert.equal(request.redirect, 'error');
        const body = await request.json(); nativeMessages.push(body); assert.deepEqual(body.data, {collect_invitation: true});
        if (nativeOutcome === 'unknown') return Response.json({error_code: 'synthetic_unknown'}, {status: 503});
        const existing = await sql`SELECT id FROM auth.users WHERE lower(email)=${body.email}`;
        return Response.json({id: existing[0]?.id ?? crypto.randomUUID(), email: body.email, email_confirmed_at: null, invited_at: new Date().toISOString()});
      };
      async function controller(key: string, body: object, options: any = {}) {
        const b = options.browser ?? owner, path = options.path ?? '/team/v2/invite', method = options.method ?? (path.endsWith('invitation-status') || path === '/team/v2' ? 'GET' : 'POST');
        const env = {DB: options.db ?? b.db, SUPABASE_URL: 'https://synthetic-notice-auth.example',
          SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_synthetic_notice_only', SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_synthetic_notice_only',
          ...(options.transport === false ? {} : {AUTH_EMAIL: smtp, AUTH_EMAIL_FROM: 'info@ikanisa.com'})};
        const result = await handleAdminInvitationV2(new Request(b.account.origin + '/api/admin' + path,
          {method, headers: {'Idempotency-Key': key}}), env, b.account, body, path);
        assert.ok(result); return {status: result.status, body: await result.json()};
      }
      const body = (email: string) => ({email, role: 'staff', displayName: 'Synthetic notice'});
      function lostReply(name: string) {
        let fired = false;
        return {prepare(text: string) {const wrap = (statement: any): any => ({bind: (...values: unknown[]) => wrap(statement.bind(...values)),
          async first(column?: string) {const row = await statement.first(column); if (!fired && text.includes('private.admin_invitation_v2_' + name + '(')) {fired = true; throw Error('Synthetic committed ' + name + ' reply lost');} return row;},
          all: () => statement.all(), run: () => statement.run()}); return wrap(owner.db.prepare(text));}};
      }

      await t.step('real fresh owner MFA plus exact BFF tuple admits recovery and a typed team list', async () => {
        assert.deepEqual(await recover('not-prepared-yet'), {found: false});
        const list = await controller('list-not-an-intent', {}, {path: '/team/v2'});
        assert.equal(list.status, 200); assert.equal(list.body.contractVersion, 2);
        assert.equal(list.body.members.find((m: any) => m.id === staff).invitation, null);
        assert.equal((await sql`SELECT count(*)::int AS n FROM app.admin_grants WHERE user_id=${principal} AND permission='privacy.review'`)[0].n, 1);
      });

      await t.step('ordinary Add Staff locks automatic notice for a confirmed mapped member and native invitation for a new target', async () => {
        const m = await mapped('selection-mapped'), before = await counts(), notice = await prepare('selection-mapped-original', m.email);
        assert.equal(notice.messageKind, 'access_notice'); assert.equal(notice.managedAuthUserId, m.managed);
        assert.equal(notice.principalId, m.member); assert.equal(notice.noticeOrigin, origin); assert.equal(notice.templateVersion, 'access_notice_v1');
        assert.deepEqual(await counts(), before);
        const fresh = await prepare('selection-new-original', 'selection-new@notice.example.test');
        assert.equal(fresh.messageKind, 'auth_invite'); assert.equal(fresh.managedAuthUserId, null); assert.equal(fresh.noticeOrigin, null);
        const replay = await prepare('selection-mapped-original', m.email); assert.equal(replay.requestId, notice.requestId); assert.equal(replay.messageKind, notice.messageKind);
        await rejects(() => prepare('selection-mapped-original', m.email, {bodyHash: 'd'.repeat(64)}), 'admin_invitation_idempotency_conflict');
      });

      await t.step('confirmed raw email without its authoritative mapping refuses before principal or staff creation', async () => {
        const email = 'unlinked-collision@notice.example.test', managed = crypto.randomUUID(), member = crypto.randomUUID();
        await sql`INSERT INTO app.users(id,email,public_id,created_at,updated_at) VALUES(${member},${email},${String(++publicId)},${stamp},${stamp})`;
        await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${managed},${email},now())`;
        const before = await counts(), attempts = (await sql`SELECT count(*)::int AS n FROM private.admin_invitation_attempts`)[0].n;
        await rejects(() => prepare('unlinked-collision-original', email), 'admin_invitation_identity_conflict');
        assert.deepEqual(await counts(), before); assert.equal((await sql`SELECT count(*)::int AS n FROM private.admin_invitation_attempts`)[0].n, attempts);
      });

      await t.step('missing notice transport retains a reserved receipt without a claim, then explicit same-key retry sends once', async () => {
        const m = await mapped('missing-transport'), key = 'missing-transport-original', before = smtpMessages.length;
        const unavailable = await controller(key, body(m.email), {transport: false});
        assert.equal(unavailable.status, 503); assert.equal(unavailable.body.outcome, 'transport_unavailable');
        const reserved = (await sql`SELECT state,claim_nonce FROM private.admin_invitation_attempts WHERE request_id=${unavailable.body.requestId}`)[0];
        assert.equal(reserved.state, 'reserved'); assert.equal(reserved.claim_nonce, null); assert.equal(smtpMessages.length, before);
        const accepted = await controller(key, body(m.email)); assert.equal(accepted.status, 200); assert.equal(accepted.body.messageKind, 'access_notice');
        assert.equal(accepted.body.noticeStatus, 'accepted'); assert.ok(!Object.hasOwn(accepted.body, 'emailStatus'));
        assert.equal(accepted.body.requestId, unavailable.body.requestId); assert.equal(smtpMessages.length, before + 1);
        assert.equal((await controller(key, body(m.email))).status, 200); assert.equal(smtpMessages.length, before + 1);
      });

      await t.step('native invitation uses only managed invite and unknown native outcomes never fall back to SMTP', async () => {
        const before = smtpMessages.length, native = nativeMessages.length;
        const accepted = await controller('native-accepted-original', body('native-accepted@notice.example.test'));
        assert.equal(accepted.status, 200); assert.equal(accepted.body.messageKind, 'auth_invite'); assert.equal(accepted.body.emailStatus, 'accepted');
        assert.ok(!Object.hasOwn(accepted.body, 'noticeStatus')); assert.equal(nativeMessages.length, native + 1); assert.equal(smtpMessages.length, before);
        nativeOutcome = 'unknown';
        const unknown = await controller('native-unknown-original', body('native-unknown@notice.example.test')); nativeOutcome = 'accepted';
        assert.equal(unknown.status, 503); assert.equal(unknown.body.outcome, 'delivery_unknown');
        const managed = crypto.randomUUID(); await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${managed},'native-unknown@notice.example.test',now())`;
        const duplicate = await controller('native-unknown-new-key', body('native-unknown@notice.example.test'));
        assert.equal(duplicate.status, 409); assert.equal(duplicate.body.requestId, unknown.body.requestId); assert.equal(duplicate.body.messageKind, 'auth_invite');
        assert.equal(smtpMessages.length, before); assert.equal(nativeMessages.length, native + 2);
      });

      await t.step('native target becoming confirmed before claim keeps its frozen kind and requires a separate repair receipt', async () => {
        const email = 'native-confirmed-before-claim@notice.example.test';
        const original = await prepare('native-confirmed-before-claim', email), managed = crypto.randomUUID();
        assert.equal(original.messageKind, 'auth_invite');
        await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${managed},${email},now())`;
        const before = smtpMessages.length, native = nativeMessages.length;
        const stopped = await claim(original.requestId, crypto.randomUUID());
        assert.equal(stopped.claimed, false); assert.equal(stopped.emailStatus, 'already_registered');
        assert.equal(stopped.messageKind, 'auth_invite'); assert.equal(stopped.noticeOrigin, null);
        const row = (await sql`SELECT claim_nonce,state FROM private.admin_invitation_attempts WHERE request_id=${original.requestId}`)[0];
        assert.equal(row.claim_nonce, null); assert.equal(row.state, 'already_registered');
        const image = await snapshots(original.requestId), identities = await counts();
        const repaired = await controller('native-confirmed-repair-original', {sourceRequestId: original.requestId},
          {path: '/team/v2/' + original.id + '/access-notice'});
        assert.equal(repaired.status, 200); assert.equal(repaired.body.messageKind, 'access_notice');
        assert.equal(repaired.body.operation, 'notice_repair'); assert.equal(repaired.body.sourceRequestId, original.requestId);
        assert.notEqual(repaired.body.requestId, original.requestId); assert.equal(repaired.body.id, original.id);
        assert.deepEqual(await counts(), identities); assert.equal(await snapshots(original.requestId), image);
        assert.equal(smtpMessages.length, before + 1); assert.equal(nativeMessages.length, native);
      });

      await t.step('explicit resend after known native acceptance may select current notice kind in a new lineage-bound intent', async () => {
        const email = 'explicit-current-resend@notice.example.test';
        const accepted = await controller('explicit-current-original', body(email));
        assert.equal(accepted.status, 200); assert.equal(accepted.body.messageKind, 'auth_invite');
        const original = (await sql`SELECT principal_id FROM private.admin_invitation_attempts WHERE request_id=${accepted.body.requestId}`)[0];
        const managed = crypto.randomUUID();
        await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${managed},${email},now())`;
        await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)
          VALUES(${managed},${original.principal_id},'synthetic-subsequently-established-link')`;
        const image = await snapshots(accepted.body.requestId), before = smtpMessages.length;
        const resent = await controller('explicit-current-resend', {}, {path: '/team/v2/' + accepted.body.id + '/resend'});
        assert.equal(resent.status, 200); assert.equal(resent.body.messageKind, 'access_notice');
        assert.equal(resent.body.operation, 'resend'); assert.equal(resent.body.sourceRequestId, accepted.body.requestId);
        assert.notEqual(resent.body.requestId, accepted.body.requestId); assert.equal(smtpMessages.length, before + 1);
        assert.equal(await snapshots(accepted.body.requestId), image);
      });

      await t.step('generated SMTP message ID without final DATA acceptance stays unknown and cannot be resent by replay', async () => {
        const m = await mapped('smtp-generated-only'), before = smtpMessages.length;
        smtpOutcome = 'id_only'; const result = await controller('smtp-generated-original', body(m.email)); smtpOutcome = 'accepted';
        assert.equal(result.status, 503); assert.equal(result.body.noticeStatus, 'unknown');
        assert.equal((await controller('smtp-generated-original', body(m.email))).status, 503);
        assert.equal((await controller('smtp-generated-next-key', body(m.email))).status, 409); assert.equal(smtpMessages.length, before + 1);
      });

      await t.step('V1 unknown history is immutable and a V2 duplicate remains its native unknown work without a new send', async () => {
        const old = await v1Prepare('v1-unknown-original', 'v1-unknown@notice.example.test'), nonce = crypto.randomUUID();
        await owner.db.prepare('SELECT private.admin_invitation_claim(?,?,?,?,?::uuid,?::uuid)').bind(...owner.args, old.requestId, nonce).first();
        await owner.db.prepare('SELECT private.admin_invitation_finish(?,?,?,?,?::uuid,?::uuid,?,?)').bind(...owner.args, old.requestId, nonce, 'unknown', null).first();
        const image = await snapshots(old.requestId), before = smtpMessages.length;
        const managed = crypto.randomUUID(); await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${managed},'v1-unknown@notice.example.test',now())`;
        const duplicate = await prepare('v2-alias-of-v1-unknown', 'v1-unknown@notice.example.test');
        assert.equal(duplicate.duplicate, true); assert.equal(duplicate.requestId, old.requestId); assert.equal(duplicate.messageKind, 'auth_invite');
        assert.equal(duplicate.emailStatus, 'unknown'); assert.equal(await snapshots(old.requestId), image); assert.equal(smtpMessages.length, before);
      });

      await t.step('explicit historical repair keeps the original registered receipt and member, and concurrent new keys share one repair', async () => {
        const m = await mapped('historical-repair'), original = await v1Prepare('v1-registered-original', m.email);
        assert.equal(original.emailStatus, 'already_registered'); const image = await snapshots(original.requestId), before = await counts();
        const results = await Promise.all(['repair-first-key', 'repair-second-key'].map(key => prepare(key, null, {kind: 'notice_repair', subject: original.id, source: original.requestId})));
        assert.equal(results.filter(r => !r.duplicate).length, 1); assert.equal(new Set(results.map(r => r.requestId)).size, 1);
        const repair = results.find(r => !r.duplicate)!; assert.equal(repair.messageKind, 'access_notice');
        assert.equal(repair.sourceRequestId, original.requestId); assert.notEqual(repair.requestId, original.requestId); assert.equal(repair.principalId, m.member);
        assert.deepEqual(await counts(), before); assert.equal(await snapshots(original.requestId), image);
        const alias = (await sql`SELECT request_id::text FROM private.admin_invitation_attempts WHERE source_request_id=${original.requestId} AND replayed_request_id IS NOT NULL`)[0].request_id;
        await rejects(() => claim(alias, crypto.randomUUID()), 'admin_invitation_invalid');
        const nonce = crypto.randomUUID(); assert.equal((await claim(repair.requestId, nonce)).claimed, true);
        await finish(repair.requestId, nonce, 'unknown');
        const again = await prepare('repair-after-unknown-key', null, {kind: 'notice_repair', subject: original.id, source: original.requestId});
        assert.equal(again.duplicate, true); assert.equal(again.requestId, repair.requestId); assert.equal(again.emailStatus, 'unknown');
        assert.equal(await snapshots(original.requestId), image);
      });

      await t.step('two actual dispatch claims have one winner and only the nonce and dispatch browser may finish', async () => {
        const m = await mapped('claim-race'), reserved = await prepare('claim-race-original', m.email), nonces = [crypto.randomUUID(), crypto.randomUUID()];
        const values = await Promise.all(nonces.map(nonce => claim(reserved.requestId, nonce)));
        assert.equal(values.filter(v => v.claimed).length, 1); const winner = nonces[values.findIndex(v => v.claimed)];
        await rejects(() => finish(reserved.requestId, nonces[values.findIndex(v => !v.claimed)], 'accepted'), 'admin_invitation_authority');
        await rejects(() => finish(reserved.requestId, winner, 'accepted', second), 'admin_invitation_authority');
        assert.equal((await finish(reserved.requestId, winner, 'accepted')).emailStatus, 'accepted');
        const other = await mapped('second-browser'), next = await prepare('second-browser-original', other.email), nonce = crypto.randomUUID();
        assert.equal((await claim(next.requestId, nonce, second)).claimed, true);
        await rejects(() => finish(next.requestId, nonce, 'accepted'), 'admin_invitation_authority');
        assert.equal((await finish(next.requestId, nonce, 'accepted', second)).emailStatus, 'accepted');
      });

      await t.step('retained origin, selected managed subject and current target fingerprint are rechecked before effects', async () => {
        const m = await mapped('subject-swap'), reserved = await prepare('subject-swap-original', m.email);
        await rejects(() => claim(reserved.requestId, crypto.randomUUID(), foreignOrigin), 'admin_invitation_identity_conflict');
        await sql`UPDATE auth.users SET email='old-subject-moved@notice.example.test' WHERE id=${m.managed}`;
        const replacement = crypto.randomUUID(); await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${replacement},${m.email},now())`;
        await rejects(() => claim(reserved.requestId, crypto.randomUUID()), 'admin_invitation_identity_conflict');
        const other = await mapped('target-edit'), pending = await prepare('target-edit-original', other.email), nonce = crypto.randomUUID();
        await claim(pending.requestId, nonce); const image = await snapshots(pending.requestId);
        await sql`UPDATE app.admin_users SET display_name='Changed approval' WHERE id=${pending.id}`;
        await rejects(() => finish(pending.requestId, nonce, 'accepted'), 'admin_invitation_identity_conflict'); assert.equal(await snapshots(pending.requestId), image);
      });

      await t.step('actual controller recovers lost committed prepare, claim and finish replies without a second SMTP effect', async () => {
        for (const lost of ['prepare', 'claim', 'finish']) {
          const m = await mapped('lost-' + lost), key = 'lost-' + lost + '-original', before = smtpMessages.length;
          const failed = await controller(key, body(m.email), {db: lostReply(lost)}); assert.equal(failed.status, 503); assert.equal(failed.body.outcome, 'operation_unknown');
          const status = await controller(key, {}, {path: '/team/v2/invitation-status'}); assert.equal(status.status, 200); assert.equal(status.body.found, true);
          const replay = await controller(key, body(m.email));
          assert.equal(replay.body.requestId, status.body.requestId);
          assert.equal(replay.status, lost === 'claim' ? 503 : 200);
          assert.equal(smtpMessages.length - before, lost === 'claim' ? 0 : 1);
          assert.equal((await sql`SELECT count(*)::int AS n FROM private.admin_invitation_attempts WHERE actor_id=${staff} AND idempotency_key=${key}`)[0].n, 1);
        }
      });

      await t.step('authority changes after synthetic SMTP acceptance keep the dispatch unknown with no late receipt upgrade or resend', async () => {
        const m = await mapped('callback-authority'), before = smtpMessages.length;
        smtpHook = async () => {await sql`UPDATE private.bff_sessions SET refresh_lease='synthetic-inflight-refresh' WHERE token_hash=${owner.hash}`;};
        let first: any;
        try {first = await controller('callback-authority-original', body(m.email));}
        finally {smtpHook = null; await sql`UPDATE private.bff_sessions SET refresh_lease=NULL WHERE token_hash=${owner.hash}`;}
        assert.equal(first.status, 503); assert.equal(first.body.outcome, 'operation_unknown');
        const result = await controller('callback-authority-original', body(m.email)); assert.equal(result.status, 503);
        assert.equal(result.body.noticeStatus, 'unknown'); assert.equal(smtpMessages.length, before + 1);
        assert.equal((await recover('callback-authority-original')).emailStatus, 'dispatching');
      });

      await t.step('version guards, read-only ACLs and immutable V2 descriptors prevent cross-version acceptance and direct mutation', async () => {
        const m = await mapped('version-guard'), value = await prepare('version-guard-original', m.email);
        await rejects(() => owner.db.prepare('SELECT private.admin_invitation_recover(?,?,?,?,?)').bind(...owner.args, 'version-guard-original').first(), 'admin_invitation_version_conflict');
        await rejects(() => owner.db.prepare('SELECT private.admin_invitation_claim(?,?,?,?,?::uuid,?::uuid)').bind(...owner.args, value.requestId, crypto.randomUUID()).first(), 'admin_invitation_version_conflict');
        await rejects(() => v1Prepare('v1-new-key-after-v2', m.email), 'admin_invitation_version_conflict');
        for (const assignment of ["message_kind='auth_invite'", "notice_origin='https://changed.example'", "contract_version=1", "managed_auth_user_id=gen_random_uuid()", "actor_principal_id=gen_random_uuid()::text"])
          await rejects(() => sql.unsafe('UPDATE private.admin_invitation_attempts SET ' + assignment + ' WHERE request_id=$1', [value.requestId]), 'admin_invitation_identity_conflict');
        const v1 = await v1Prepare('v1-retained-health', 'v1-retained-health@notice.example.test');
        assert.equal(v1.emailStatus, 'reserved');
        await rejects(() => recover('v1-retained-health'), 'admin_invitation_version_conflict');
        for (const role of ['anon', 'authenticated', 'collect_runtime']) {
          assert.equal((await sql`SELECT has_table_privilege(${role},'private.admin_invitation_attempts','INSERT') AS i,
            has_table_privilege(${role},'private.admin_invitation_attempts','UPDATE') AS u,has_table_privilege(${role},'private.admin_invitation_attempts','DELETE') AS d`)[0].i, false);
          const result = (await sql`SELECT has_table_privilege(${role},'private.admin_invitation_attempts','UPDATE') AS u,has_table_privilege(${role},'private.admin_invitation_attempts','DELETE') AS d`)[0]; assert.equal(result.u, false); assert.equal(result.d, false);
          assert.equal((await sql`SELECT has_function_privilege(${role},'private.admin_invitation_v1_prepare_legacy(text,text,text,text,text,text,text,text,text,text,text,text)','EXECUTE') AS allowed`)[0].allowed, false);
        }
        const helpers = await sql`SELECT p.proname,p.prosecdef,p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname LIKE 'admin_invitation_v2_%'`;
        for (const helper of helpers) {assert.equal(helper.prosecdef, true); assert.deepEqual(helper.proconfig, ['search_path=pg_catalog']);}
        assert.equal((await sql`SELECT relrowsecurity FROM pg_class WHERE oid='private.admin_invitation_attempts'::regclass`)[0].relrowsecurity, true);
        assert.equal((await sql`SELECT count(*)::int AS n FROM pg_constraint WHERE conrelid='private.admin_invitation_attempts'::regclass AND contype='f' AND confrelid='auth.users'::regclass`)[0].n, 0);
      });

      await t.step('current owner tuple and target status are checked on prepare, claim, recovery and finish', async () => {
        const m = await mapped('current-authority'), value = await prepare('current-authority-original', m.email), nonce = crypto.randomUUID();
        const bad = {...owner, args: [staff, 'f'.repeat(64), origin, owner.args[3]]};
        for (const action of [() => prepare('wrong-cookie-original', 'wrong-cookie@notice.example.test', {}, bad),
          () => claim(value.requestId, nonce, bad), () => recover('current-authority-original', bad)]) await rejects(action, 'admin_invitation_authority');
        await claim(value.requestId, nonce);
        await rejects(() => finish(value.requestId, nonce, 'accepted', bad), 'admin_invitation_authority');
        const journalBefore=JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY request_id`),smtpBefore=smtpMessages.length,nativeBefore=nativeMessages.length;
        await sql`UPDATE auth.mfa_factors SET status='unverified' WHERE id=${factor}`;
        try {
          for(const [b,expected] of [[owner,'admin_email_denied'],[{...owner,db:owner.rawDb},'admin_invitation_authority']] as const){
            // Current email-context denial and the invitation helper's wrapped
            // authority denial are distinct, equally required SQL boundaries.
            const actions=[()=>prepare('unverified-owner-denied',m.email,{},b),()=>claim(value.requestId,nonce,b),
              ()=>recover('current-authority-original',b),()=>finish(value.requestId,nonce,'accepted',b)];
            for(const action of actions)await assert.rejects(action,(error:any)=>error.code==='42501'&&error.message===expected);
          }
          assert.equal(JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY request_id`),journalBefore);
          assert.equal(smtpMessages.length,smtpBefore);assert.equal(nativeMessages.length,nativeBefore);
        } finally {await sql`UPDATE auth.mfa_factors SET status='verified' WHERE id=${factor}`;}
        await sql`UPDATE app.users SET access_status='suspended',revision=revision+1 WHERE id=${m.member}`;
        await rejects(() => finish(value.requestId, nonce, 'accepted'), 'admin_invitation_subject_unavailable');
      });

      let linkedPublicStaff: string | null = null, unlinkedPublicStaff: string | null = null;
      await t.step('team list derives a leading-zero public ID only through the authoritative staff-to-member link', async () => {
        const member = crypto.randomUUID(), managed = crypto.randomUUID(), email = 'public-id-linked@notice.example.test';
        await sql`INSERT INTO app.users(id,email,public_id,created_at,updated_at) VALUES(${member},${email},'000042',${stamp},${stamp})`;
        await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${managed},${email},now())`;
        await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)
          VALUES(${managed},${member},'synthetic-public-id-member')`;
        const prepared = await prepare('public-id-linked-original', email); linkedPublicStaff = prepared.id;
        const listed = await owner.db.prepare('SELECT private.admin_invitation_v2_list(?,?,?,?) AS result').bind(...owner.args).first('result');
        const row = listed.members.find((entry: any) => entry.id === prepared.id);
        assert.ok(row); assert.equal(row.publicId, '000042'); assert.equal(typeof row.publicId, 'string');
        for (const uuid of [prepared.id, member, managed]) assert.notEqual(row.publicId, uuid);
        const authoritative = (await sql`SELECT u.public_id FROM app.admin_principal_links l JOIN app.users u ON u.id=l.user_id
          WHERE l.admin_user_id=${prepared.id}`)[0];
        assert.equal(row.publicId, authoritative.public_id);
      });

      await t.step('same-email unlinked staff has null public ID and listing never creates an inferred identity link', async () => {
        const member = crypto.randomUUID(), managed = crypto.randomUUID(), unlinked = crypto.randomUUID();
        const email = 'public-id-unlinked@notice.example.test'; unlinkedPublicStaff = unlinked;
        await sql`INSERT INTO app.users(id,email,public_id,created_at,updated_at) VALUES(${member},${email},'000043',${stamp},${stamp})`;
        await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${managed},${email},now())`;
        await sql`INSERT INTO app.admin_users(id,email,role,status,display_name,created_at,updated_at)
          VALUES(${unlinked},${email},'staff','invited','Synthetic unlinked staff',app.unixepoch(),app.unixepoch())`;
        const before = (await sql`SELECT (SELECT count(*)::int FROM app.admin_principal_links) AS staff_links,
          (SELECT count(*)::int FROM private.auth_principal_links) AS auth_links`)[0];
        const listed = await owner.db.prepare('SELECT private.admin_invitation_v2_list(?,?,?,?) AS result').bind(...owner.args).first('result');
        const row = listed.members.find((entry: any) => entry.id === unlinked);
        assert.ok(row); assert.equal(row.publicId, null); assert.equal(row.id, unlinked);
        assert.equal((await sql`SELECT count(*)::int AS n FROM app.admin_principal_links WHERE admin_user_id=${unlinked}`)[0].n, 0);
        assert.equal((await sql`SELECT count(*)::int AS n FROM private.auth_principal_links WHERE auth_user_id=${managed}`)[0].n, 0);
        const after = (await sql`SELECT (SELECT count(*)::int FROM app.admin_principal_links) AS staff_links,
          (SELECT count(*)::int FROM private.auth_principal_links) AS auth_links`)[0];
        assert.deepEqual(after, before);
      });

      await t.step('actual typed team controller preserves nullable public IDs and requires current owner email proof, cookie, origin and session', async () => {
        assert.ok(linkedPublicStaff); assert.ok(unlinkedPublicStaff);
        const listed = await controller('public-id-list-check', {}, {path: '/team/v2'});
        assert.equal(listed.status, 200); assert.equal(listed.body.contractVersion, 2);
        assert.equal(listed.body.members.find((entry: any) => entry.id === linkedPublicStaff).publicId, '000042');
        assert.equal(listed.body.members.find((entry: any) => entry.id === unlinkedPublicStaff).publicId, null);
        const rejected = (action: () => Promise<unknown>, code: string) => assert.rejects(action,
          (error: any) => error.status === 403 && error.code === code);
        for (const account of [{...owner.account, token_hash: 'f'.repeat(64)},
          {...owner.account, origin: 'https://wrong-origin.example'}])
          await rejected(() => controller('public-id-denied-list', {}, {path: '/team/v2', browser: {...owner, account}}), 'recent_email_sign_in_required');
        await rejected(() => controller('public-id-wrong-session', {}, {path: '/team/v2', db: second.db}), 'admin_access_changed');
        await rejected(() => controller('public-id-cloned-email-proof-denied', {}, {path: '/team/v2',
          browser: {...owner, account: {...owner.account, issued_assurance_level: 1}}}), 'recent_email_sign_in_required');
        const journalBefore=JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY request_id`),smtpBefore=smtpMessages.length,nativeBefore=nativeMessages.length;
        await sql`UPDATE auth.mfa_factors SET status='unverified' WHERE id=${factor}`;
        try {
          // This helper is a direct domain caller, not the HTTP BFF. Its
          // unknown outer email-context error returns a non-disclosing 503.
          const denied=await controller('public-id-managed-mfa-denied',{}, {path:'/team/v2'});
          assert.equal(denied.status,503);assert.equal(denied.body.ok,false);
          assert.equal(denied.body.error.code,'invitation_list_unknown');assert.equal(Object.hasOwn(denied.body,'members'),false);
          await assert.rejects(()=>owner.db.prepare('SELECT private.admin_invitation_v2_list(?,?,?,?) AS result').bind(...owner.args).first('result'),
            (error:any)=>error.code==='42501'&&error.message==='admin_email_denied');
          await assert.rejects(()=>owner.rawDb.prepare('SELECT private.admin_invitation_v2_list(?,?,?,?) AS result').bind(...owner.args).first('result'),
            (error:any)=>error.code==='42501'&&error.message==='admin_invitation_authority');
        } finally {await sql`UPDATE auth.mfa_factors SET status='verified' WHERE id=${factor}`;}

        // Exercise the actual BFF chain: encrypted original cookie, current
        // synthetic GetUser, legacy cookie validation, email-status SQL, team.
        // The only HTTP interception is this exact GET; no Auth/provider write
        // or token-refresh request is accepted, and no real identity is used.
        const issuer='https://synthetic-notice-auth.example',keyId='synthetic-notice-bff',key=btoa(String.fromCharCode(...new Uint8Array(32).fill(31)));
        const encode=(value:unknown)=>btoa(JSON.stringify(value)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
        const access=encode({alg:'RS256',typ:'JWT'})+'.'+encode({...owner.claims,aud:'authenticated',iss:issuer+'/auth/v1',exp:Math.floor(Date.now()/1000)+3600})+'.synthetic-signature';
        const sessionCustody=async()=>JSON.stringify(await sql`SELECT to_jsonb(s) AS session,to_jsonb(c) AS cookie,to_jsonb(b) AS bff
          FROM app.auth_sessions s JOIN app.admin_sessions c ON c.auth_session_id=s.id JOIN private.bff_sessions b ON b.token_hash=c.token_hash
          WHERE c.token_hash=${owner.hash}`);
        const custodyBefore=await sessionCustody(),previousCipher=(await sql`SELECT token_ciphertext FROM private.bff_sessions WHERE token_hash=${owner.hash}`)[0].token_ciphertext;
        const cipher=await encrypt({DATA_KEY_ID:keyId,DATA_ENCRYPTION_KEY:key},new TextEncoder().encode(JSON.stringify({access_token:access,refresh_token:'synthetic-notice-refresh-never-dispatched'})),`bff:${owner.session}:${auth}`);
        const invitationFetch=globalThis.fetch;let authReads=0;
        const bff=()=>handleAdminAccounts(new Request(origin+'/api/admin/team/v2',{headers:{Cookie:'__Host-collect_admin='+owner.cookie,Origin:origin}}),
          {DB:owner.rawDb,SUPABASE_URL:issuer,SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_notice_only',ADMIN_ORIGIN:origin,SESSION_KEY_ID:keyId,SESSION_ENCRYPTION_KEY:key},{});
        try {
          await sql`UPDATE private.bff_sessions SET token_ciphertext=${cipher} WHERE token_hash=${owner.hash}`;
          globalThis.fetch=async(input:RequestInfo|URL,init?:RequestInit)=>{
            const request=new Request(input,init);assert.equal(request.url,issuer+'/auth/v1/user','Every other external request is denied');
            assert.equal(request.method,'GET');assert.equal(request.redirect,'error');assert.equal(request.headers.get('Authorization'),'Bearer '+access);authReads++;
            return Response.json({id:auth,email:'info@ikanisa.com',email_confirmed_at:stamp,factors:[{id:factor,factor_type:'totp',status:'verified'}]});
          };
          const beforeReads=authReads,valid=await bff();assert.ok(valid);assert.equal(valid.status,200);
          const validBody=await valid.json();assert.equal(validBody.contractVersion,2);assert.ok(Array.isArray(validBody.members));assert.equal(authReads,beforeReads+1);
          await sql`UPDATE auth.mfa_factors SET status='unverified' WHERE id=${factor}`;
          await rejected(bff,'admin_email_denied');assert.equal(authReads,beforeReads+2);
          // The stale synthetic GetUser factor cannot override managed SQL
          // truth. The same cookie succeeds again only after real fixture repair.
          await sql`UPDATE auth.mfa_factors SET status='verified' WHERE id=${factor}`;
          const restored=await bff();assert.ok(restored);assert.equal(restored.status,200);assert.equal(authReads,beforeReads+3);
        } finally {
          globalThis.fetch=invitationFetch;owner.rawDb.setClaims(owner.claims);
          await sql`UPDATE auth.mfa_factors SET status='verified' WHERE id=${factor}`;
          await sql`UPDATE private.bff_sessions SET token_ciphertext=${previousCipher} WHERE token_hash=${owner.hash}`;
        }
        assert.equal(await sessionCustody(),custodyBefore,'Original app session, cookie/AAL tuple and restored encrypted BFF custody remain exact');
        assert.equal(JSON.stringify(await sql`SELECT * FROM private.admin_invitation_attempts ORDER BY request_id`),journalBefore);
        assert.equal(smtpMessages.length,smtpBefore);assert.equal(nativeMessages.length,nativeBefore);
      });

      await t.step('new notice history retains exact target and historical actor attribution with no financial or erasure authority', async () => {
        const m = await mapped('retention-attribution'), value = await prepare('retention-attribution-original', m.email);
        const row = (await sql`SELECT actor_principal_id,principal_id,managed_auth_user_id::text FROM private.admin_invitation_attempts WHERE request_id=${value.requestId}`)[0];
        assert.equal(row.actor_principal_id, principal); assert.equal(row.principal_id, m.member); assert.equal(row.managed_auth_user_id, m.managed);
        const inventory = await inventoryPrivateRetention({DB: owner.db}, m.member);
        assert.equal(inventory.classes['private:admin_invitation_attempts'].count, 1); assert.equal(inventory.in_flight_unresolved, true);
        const actorExpected = (await sql`SELECT count(*)::int AS n FROM private.admin_invitation_attempts WHERE principal_id=${principal} OR actor_principal_id=${principal}`)[0].n;
        assert.equal((await inventoryPrivateRetention({DB: owner.db}, principal)).classes['private:admin_invitation_attempts'].count, actorExpected);
        assert.equal(inventory.external_copy_disposition, 'blocked');
        assert.equal((await sql`SELECT count(*)::int AS n FROM app.ledger_entries`)[0].n, 0);
        assert.equal((await sql`SELECT count(*)::int AS n FROM app.deletion_requests`)[0].n, 0);
      });
    } finally {globalThis.fetch = originalFetch; await finishSqlFixtureWork();await sql.end();}
  },
});
