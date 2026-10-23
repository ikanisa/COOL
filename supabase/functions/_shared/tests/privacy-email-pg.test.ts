import {loadReviewedPlatformFixture} from '../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import {initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest} from './helpers/fenced-unit.js';
import assert from 'node:assert/strict';
import {connection, PostgresDatabase} from './helpers/fenced-postgres.js';
import {digest} from '../domain/core.js';
import {projectSession} from './helpers/module-domain-auth.js';
import {handlePrivacyEmailAuth} from './helpers/module-domain-privacy_email_auth.js';
import {privacyRpc} from './helpers/module-domain-privacy.js';
import {inventoryPrivateRetention} from './helpers/module-private-retention.js';
import {adminEmailFixtureDatabase} from './helpers/admin-email-fixture.js';

// Synthetic managed Auth rows and intercepted HTTP are fixtures, not proof of
// GoTrue delivery/signatures. Every tested SQL helper and application projection
// below executes against the real, disposable PostgreSQL database. Run with
// --allow-net=127.0.0.1:55439; no other network access is needed or permitted.
const database = Deno.env.get('COLLECT_PRIVACY_EMAIL_TEST_DATABASE_URL');
const project = 'https://privacy-email-pg.synthetic.invalid';
const purpose = 'account_deletion_request';
const signatures: Record<string, string> = {
  prepare: '?::text,?::text,?::text,?::text',
  send_claim: '?::text,?::text,?::uuid',
  send_finish: '?::text,?::text,?::uuid,?::text',
  verify_claim: '?::text,?::text,?::uuid',
  verify_finish: '?::text,?::text,?::uuid,?::text',
  consume: '?::text,?::text,?::uuid',
  status: '?::text,?::text',
  cancel: '?::text,?::text,?::uuid',
  cleanup_claim: '?::text,?::text,?::uuid,?::uuid',
  cleanup_finish: '?::text,?::text,?::uuid,?::uuid,?::text',
};
type Claims = Record<string, any>;
type Member = {auth: string; principal: string; email: string; original: string; at: number; claims: Claims};
type Flow = {id: string; hash: string; context: string; mode: string; member: Member | null; created: number; operation: string};

fencedTest({
  name: 'actual privacy email helpers preserve existing subjects, durable operations and exact candidate retirement',
  ignore: !database, sanitizeOps: false, sanitizeResources: false,
  fn: async t => {
    const url = new URL(database!);
    assert.equal(url.hostname, '127.0.0.1');
    assert.ok(url.port==='55439'||(Deno.env.get('COLLECT_CI_SYNTHETIC')==='true'&&['55441','55443'].includes(url.port)));
    assert.equal(url.pathname, '/collect_privacy_email_test');
    const adminUrl = new URL(url); adminUrl.pathname = '/postgres';
    const admin = connection(adminUrl.href);
    if (!(await admin`SELECT 1 FROM pg_database WHERE datname='collect_privacy_email_test'`).length)
      await admin.unsafe('CREATE DATABASE collect_privacy_email_test');
    await admin.end();
    const sql = connection(database!);await initializeSqlFixture(sql);
    const originalFetch = globalThis.fetch;
    try {
      const setup = await sql.reserve();
      try {
        await setup.unsafe('DROP SCHEMA IF EXISTS api,private,app,auth,realtime CASCADE');
        await setup.unsafe(await Deno.readTextFile(new URL('../../../tests/sql/00_local_auth_fixture.sql', import.meta.url)));
        // The minimal local fixture predates this managed field. Never execute
        // this fixture adjustment against a hosted Supabase Auth schema.
        await setup.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');
        const reviewedPlatform=await loadReviewedPlatformFixture(new URL('../../../../',import.meta.url));await reviewedPlatform.apply(text=>setup.unsafe(text));
      } finally { setup.release();await initializeSqlFixture(sql); }

      let publicId = 940000;
      const at = async () => (await sql`SELECT app.unixepoch() AS value`)[0].value as number;
      const dbFor = (claims: Claims = {}) => new PostgresDatabase(sql, claims);
      const call = (db: any, name: string, ...args: unknown[]) => {
        assert.ok(Object.hasOwn(signatures, name));
        return db.prepare(`SELECT private.privacy_email_${name}(${signatures[name]}) AS result`).bind(...args).first('result');
      };
      const denied = (action: () => Promise<unknown>) => assert.rejects(action,
        (error: any) => error.message === 'privacy_email_denied' && error.code === '42501');
      const claimsFor = (auth: string, session: string, event: unknown): Claims => ({
        sub: auth, session_id: session, role: 'authenticated', aal: 'aal1', aud: 'authenticated',
        iss: project + '/auth/v1', exp: Math.floor(Date.now() / 1000) + 3600,
        amr: [{method: 'otp', timestamp: event}],
      });
      async function member(label: string, linked = true, confirmedEmail?: string): Promise<Member> {
        const auth = crypto.randomUUID(), principal = crypto.randomUUID(), original = crypto.randomUUID();
        const email = confirmedEmail ?? label + '@privacy.example.test', stamp = new Date().toISOString(), now = await at();
        await sql`INSERT INTO auth.users(id,email,email_confirmed_at) VALUES(${auth},${email},now())`;
        await sql`INSERT INTO app.users(id,email,public_id,full_name,created_at,updated_at)
          VALUES(${principal},${email},${String(++publicId)},'Synthetic privacy member',${stamp},${stamp})`;
        if (linked) await sql`INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)
          VALUES(${auth},${principal},'synthetic-private-privacy-fixture')`;
        await sql`INSERT INTO auth.sessions(id,user_id) VALUES(${original},${auth})`;
        if (linked) await sql`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)
          VALUES(${original},${principal},'member',${now - 600},${now - 600},${now + 3600})`;
        return {auth, principal, email, original, at: now, claims: claimsFor(auth, original, now - 600)};
      }
      async function candidate(m: Member, event: unknown, projected = true) {
        const session = crypto.randomUUID(), now = await at(), claims = claimsFor(m.auth, session, event);
        await sql`INSERT INTO auth.sessions(id,user_id) VALUES(${session},${m.auth})`;
        if (projected) {
          assert.ok(Number.isSafeInteger(event));
          await sql`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)
            VALUES(${session},${m.principal},'member',${event as number},${now},${now + 3600})`;
        }
        return {session, claims};
      }
      async function flow(m: Member | null, label = '', delivered = true): Promise<Flow> {
        const context = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
          .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
        const id = crypto.randomUUID(), hash = await digest(context), mode = m ? 'current_session' : 'portal_bootstrap';
        const db = dbFor(m?.claims), result = await call(db, 'prepare', id, mode, m ? null : label, hash);
        assert.equal(result.created, true);
        if (delivered) {
          const nonce = crypto.randomUUID();
          assert.equal((await call(db, 'send_claim', id, hash, nonce)).claimed, true);
          assert.equal((await call(db, 'send_finish', id, hash, nonce, 'accepted')).challenge.delivery_status, 'accepted');
        }
        return {id, hash, context, mode, member: m, created: result.challenge.created_at, operation: crypto.randomUUID()};
      }
      const admit = (f: Flow) => call(dbFor(f.member?.claims), 'verify_claim', f.id, f.hash, f.operation);
      const consume = (f: Flow, claims: Claims) => call(dbFor(claims), 'consume', f.id, f.hash, f.operation);
      const snapshot = async (id: string) => JSON.stringify(await sql`SELECT * FROM private.supabase_otp_challenges WHERE id=${id}`);
      const identities = async () => (await sql`SELECT
        (SELECT count(*)::int FROM app.users) AS users,
        (SELECT count(*)::int FROM private.auth_principal_links) AS links`)[0];

      await t.step('native preparation captures the original mapped pair and forbids contact or context substitution', async () => {
        const m = await member('native-prepare'), f = await flow(m), before = await identities();
        const value = (await call(dbFor(m.claims), 'status', f.id, f.hash)).challenge;
        assert.equal(value.expected_auth_user_id, m.auth); assert.equal(value.expected_user_id, m.principal);
        assert.equal(value.initiating_session_id, m.original); assert.equal(value.initiating_user_revision, 1);
        assert.equal(value.identity_value, m.email);
        assert.equal((await call(dbFor(m.claims), 'prepare', f.id, f.mode, null, f.hash)).created, false);
        await denied(() => call(dbFor(m.claims), 'prepare', f.id, f.mode, null, 'f'.repeat(64)));
        await denied(() => call(dbFor(), 'prepare', f.id, 'portal_bootstrap', m.email, f.hash));
        await assert.rejects(() => call(dbFor(m.claims), 'prepare', crypto.randomUUID(), f.mode, m.email, f.hash),
          (error: any) => error.message === 'privacy_email_invalid');
        for (const claims of [{}, {...m.claims, sub: crypto.randomUUID()}, {...m.claims, session_id: crypto.randomUUID()}])
          await denied(() => call(dbFor(claims), 'status', f.id, f.hash));
        assert.deepEqual(await identities(), before);
      });

      await t.step('concurrent send and verify admission each have one real committed winner; nonces and receipts are immutable', async () => {
        const m = await member('concurrent'), f = await flow(m, '', false), senders = [crypto.randomUUID(), crypto.randomUUID()];
        const sent = await Promise.all(senders.map(n => call(dbFor(m.claims), 'send_claim', f.id, f.hash, n)));
        assert.equal(sent.filter(r => r.claimed).length, 1);
        const winner = senders[sent.findIndex(r => r.claimed)], loser = senders[sent.findIndex(r => !r.claimed)];
        await denied(() => call(dbFor(m.claims), 'send_finish', f.id, f.hash, loser, 'accepted'));
        await call(dbFor(m.claims), 'send_finish', f.id, f.hash, winner, 'accepted');
        const operations = [crypto.randomUUID(), crypto.randomUUID()];
        const claimed = await Promise.allSettled(operations.map(op => call(dbFor(m.claims), 'verify_claim', f.id, f.hash, op)));
        assert.equal(claimed.filter(r => r.status === 'fulfilled' && r.value.claimed).length, 1);
        const selected = claimed.findIndex(r => r.status === 'fulfilled' && r.value.claimed), operation = operations[selected];
        assert.equal((await call(dbFor(m.claims), 'verify_claim', f.id, f.hash, operation)).claimed, false);
        const state = await snapshot(f.id);
        await denied(() => call(dbFor(m.claims), 'verify_finish', f.id, f.hash, operations[1 - selected], 'rejected'));
        assert.equal(await snapshot(f.id), state);
        await call(dbFor(m.claims), 'verify_finish', f.id, f.hash, operation, 'unconfirmed');
        await denied(() => call(dbFor(m.claims), 'verify_claim', f.id, f.hash, crypto.randomUUID()));
        await denied(() => sql`UPDATE private.supabase_otp_challenges SET privacy_context_hash=${'e'.repeat(64)} WHERE id=${f.id}`);
        await denied(() => sql`UPDATE private.supabase_otp_challenges SET privacy_verify_receipts='{}'::jsonb WHERE id=${f.id}`);
      });

      await t.step('five definite rejected operations remain individually replayable and a sixth admission is denied', async () => {
        const m = await member('attempt-budget'), f = await flow(m), operations: string[] = [];
        for (let i = 0; i < 5; i++) {
          const op = crypto.randomUUID(); operations.push(op);
          assert.equal((await call(dbFor(m.claims), 'verify_claim', f.id, f.hash, op)).claimed, true);
          await call(dbFor(m.claims), 'verify_finish', f.id, f.hash, op, 'rejected');
        }
        await denied(() => call(dbFor(m.claims), 'verify_claim', f.id, f.hash, crypto.randomUUID()));
        for (const op of operations) {
          const replay = await call(dbFor(m.claims), 'verify_claim', f.id, f.hash, op);
          assert.equal(replay.claimed, false); assert.equal(replay.challenge.verification_state, 'rejected');
          assert.equal(replay.challenge.verification_operation_id, op);
        }
        const row = (await sql`SELECT attempts,(SELECT count(*)::int FROM jsonb_object_keys(privacy_verify_receipts)) AS n
          FROM private.supabase_otp_challenges WHERE id=${f.id}`)[0];
        assert.equal(row.attempts, 5); assert.equal(row.n, 5);
      });

      await t.step('real consumption requires a distinct same-member session and numeric original OTP event before immutable proof', async () => {
        const m = await member('native-consume'), f = await flow(m); await admit(f);
        const valid = await candidate(m, f.created), other = await member('native-wrong-subject');
        const wrong = await candidate(other, f.created);
        for (const claims of [m.claims, wrong.claims,
          {...valid.claims, amr: [{method: 'otp', timestamp: String(f.created)}]},
          {...valid.claims, amr: [{method: 'oauth', timestamp: f.created}]},
          {...valid.claims, amr: [{method: 'otp', timestamp: f.created - 1}]},
          {...valid.claims, amr: [{method: 'otp', timestamp: (await at()) + 60}]}])
          await denied(() => consume(f, claims));
        await denied(() => call(dbFor(valid.claims), 'consume', f.id, f.hash, crypto.randomUUID()));
        const result = await consume(f, valid.claims);
        assert.deepEqual(result.proof, {purpose, challenge_id: f.id, user_id: m.principal, auth_user_id: m.auth,
          initiating_session_id: m.original, session_id: valid.session, method: 'otp', authenticated_at: f.created,
          expires_at: result.challenge.expires_at});
        await denied(() => consume(f, valid.claims));
        const proof = await snapshot(f.id);
        await denied(() => sql`UPDATE private.supabase_otp_challenges SET privacy_verified_session_id=${crypto.randomUUID()} WHERE id=${f.id}`);
        assert.equal(await snapshot(f.id), proof);
        assert.equal((await sql`SELECT auth_at FROM app.auth_sessions WHERE id=${valid.session}`)[0].auth_at, f.created);
        // Existing intake authority is fresh managed/canonical session authority;
        // it is not restricted to a phone identity or a new purpose policy.
        assert.equal(await dbFor(valid.claims).prepare('SELECT private.assert_actor(NULL,NULL,NULL,1,300) AS id').first('id'), m.principal);
      });

      await t.step('changed revision and revoked original session deny consumption after candidate creation', async () => {
        for (const reason of ['revision', 'revoked']) {
          const m = await member('original-' + reason), f = await flow(m); await admit(f);
          const next = await candidate(m, f.created), before = await snapshot(f.id);
          if (reason === 'revision') await sql`UPDATE app.users SET revision=revision+1 WHERE id=${m.principal}`;
          else await sql`UPDATE app.auth_sessions SET revoked_at=app.unixepoch(),revocation_reason='synthetic_switch' WHERE id=${m.original}`;
          await denied(() => consume(f, next.claims)); assert.equal(await snapshot(f.id), before);
        }
      });

      await t.step('local latest-reservation and cancellation fences do not imply provider-causal OTP binding', async () => {
        const m = await member('local-latest'), old = crypto.randomUUID(), hash = 'a'.repeat(64), now = await at();
        // Historical reservation is fixture data; current prepare is the real
        // helper. The assertion concerns local row ordering only.
        await sql`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,
          registration_allowed,created_at,expires_at,delivery_status,privacy_mode,privacy_context_hash,privacy_verification_state,privacy_cleanup_state)
          VALUES(${old},${await digest('email:' + m.email)},'email',${m.email},'member',0,${now - 100},${now + 200},'accepted',
          'portal_bootstrap',${hash},'not_started','not_started')`;
        const latest = await flow(null, m.email);
        await denied(() => call(dbFor(), 'verify_claim', old, hash, crypto.randomUUID()));
        await call(dbFor(), 'cancel', latest.id, latest.hash, null);
        await denied(() => admit(latest));
        await denied(() => call(dbFor(), 'status', latest.id, 'b'.repeat(64)));
      });

      // A strict fake GoTrue boundary. It reads/removes actual fixture Auth rows;
      // it never performs HTTP and does not emulate PostgreSQL authorization.
      const tokenClaims = new Map<string, Claims>();
      const sent: Array<{email: string; create_user: unknown}> = [], verifiedEmails: string[] = [], loggedOut: string[] = [];
      const sendOutcome = new Map<string, 'accepted' | 'rejected' | 'unknown'>();
      let verifyTokenResult: string | null = null, verifyOutcome: 'accepted' | 'rejected' | 'lost' = 'accepted';
      const token = (claims: Claims) => {
        const value = [btoa('{"alg":"synthetic-http-fixture-only"}'), btoa(JSON.stringify(claims)), 'fixture'].join('.');
        tokenClaims.set(value, claims); return value;
      };
      globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
        const request = new Request(input, init), target = new URL(request.url);
        assert.equal(target.origin, project, 'All outside HTTP is denied by this fixture');
        assert.equal(request.redirect, 'error');
        assert.equal(request.headers.get('apikey'), 'sb_publishable_synthetic_privacy_pg_only');
        if (target.pathname === '/auth/v1/user' && request.method === 'GET') {
          assert.equal(target.search, '');
          const captured = request.headers.get('Authorization')?.replace(/^Bearer /, ''), claims = tokenClaims.get(captured ?? '');
          assert.ok(claims, 'Only explicitly captured fixture tokens may be used');
          const rows = await sql`SELECT a.* FROM auth.users a JOIN auth.sessions s ON s.user_id=a.id
            WHERE a.id=${claims.sub} AND s.id=${claims.session_id}`;
          if (!rows.length) return Response.json({error_code: 'invalid_session'}, {status: 401});
          const row = rows[0];
          return Response.json({id: row.id, email: row.email,
            email_confirmed_at: row.email_confirmed_at?.toISOString(), phone: row.phone,
            phone_confirmed_at: row.phone_confirmed_at?.toISOString(), app_metadata: {provider: 'email'}, user_metadata: {}});
        }
        if (target.pathname === '/auth/v1/otp' && request.method === 'POST') {
          assert.equal(target.search, ''); const body = await request.json();
          assert.equal(body.create_user, false); assert.ok(typeof body.email === 'string');
          assert.deepEqual(Object.keys(body).sort(), ['create_user', 'email', 'gotrue_meta_security']);
          sent.push({email: body.email, create_user: body.create_user});
          const result = sendOutcome.get(body.email) ?? 'accepted';
          return result === 'accepted' ? Response.json({}) : Response.json({error_code: 'synthetic_rejection'}, {status: result === 'rejected' ? 422 : 503});
        }
        if (target.pathname === '/auth/v1/verify' && request.method === 'POST') {
          assert.equal(target.search, ''); const body = await request.json();
          assert.equal(body.type, 'email'); assert.equal(body.token, '184275');
          verifiedEmails.push(body.email);
          if (verifyOutcome === 'rejected') return Response.json({error_code: 'otp_expired'}, {status: 401});
          if (verifyOutcome === 'lost') throw new TypeError('Synthetic lost provider verify body');
          assert.ok(verifyTokenResult);
          return Response.json({access_token: verifyTokenResult, refresh_token: 'synthetic-privacy-refresh-only', token_type: 'bearer'});
        }
        if (target.pathname === '/auth/v1/logout' && target.search === '?scope=local' && request.method === 'POST') {
          const captured = request.headers.get('Authorization')?.replace(/^Bearer /, ''), claims = tokenClaims.get(captured ?? '');
          assert.ok(claims); loggedOut.push(claims.session_id);
          await sql`DELETE FROM auth.sessions WHERE id=${claims.session_id} AND user_id=${claims.sub}`;
          return new Response(null, {status: 204});
        }
        assert.fail('Unapproved synthetic HTTP endpoint: ' + request.method + ' ' + target.pathname + target.search);
      };
      const baseBody = (f: Flow) => ({contract_version: 1, purpose, mode: f.mode, challenge_id: f.id, challenge_context: f.context});
      async function controller(operation: string, body: object, bearer: string | null = null, port?: any) {
        const db = port ?? dbFor();
        const env = {DB: db, SUPABASE_URL: project, SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_synthetic_privacy_pg_only', AUTH_MEMBER_REGISTRATION_ENABLED: 'false'};
        const response = await handlePrivacyEmailAuth(new Request('https://privacy.example.test/v1/privacy/email/' + operation,
          {method: 'POST', headers: {'Content-Type': 'application/json', ...(bearer ? {Authorization: 'Bearer ' + bearer} : {})}, body: JSON.stringify(body)}), env);
        assert.ok(response); return {status: response.status, body: await response.json()};
      }
      async function controllerFlow(m: Member | null, email = '') {
        const context = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
          .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
        const f: Flow = {id: crypto.randomUUID(), hash: await digest(context), context, mode: m ? 'current_session' : 'portal_bootstrap',
          member: m, created: 0, operation: crypto.randomUUID()};
        const bearer = m ? token(m.claims) : null;
        const result = await controller('challenge', {...baseBody(f), ...(m ? {} : {email})}, bearer);
        assert.equal(result.status, 202); f.created = result.body.created_at;
        return {f, bearer, result};
      }
      function lostReply(name: string) {
        const db = dbFor(); let fired = false;
        return {setClaims: (claims: Claims) => db.setClaims(claims), batch: (statements: any[]) => db.batch(statements),
          prepare(text: string) {
            const wrap = (statement: any): any => ({bind: (...values: unknown[]) => wrap(statement.bind(...values)),
              async first(column?: string) {
                const row = await statement.first(column);
                if (!fired && text.includes('private.privacy_email_' + name + '(')) {
                  fired = true; throw Error('Synthetic committed ' + name + ' reply lost');
                }
                return row;
              }, all: () => statement.all(), run: () => statement.run(), raw: () => statement.raw()});
            return wrap(db.prepare(text));
          }};
      }

      await t.step('one portal OTP projects only an existing mapped member and reaches unchanged fresh review-only intake', async () => {
        const m = await member('portal-success'), before = await identities(), {f, result} = await controllerFlow(null, m.email);
        assert.equal(result.body.delivery_status, 'not_disclosed');
        assert.ok(!JSON.stringify(result.body).includes(m.auth)); assert.ok(!JSON.stringify(result.body).includes(m.principal));
        const next = await candidate(m, f.created, false); verifyTokenResult = token(next.claims);
        const count = verifiedEmails.length;
        const accepted = await controller('verify', {...baseBody(f), operation_id: f.operation, code: '184275'});
        assert.equal(accepted.status, 200); assert.equal(verifiedEmails.length, count + 1);
        assert.equal(accepted.body.user.id, m.principal); assert.equal(accepted.body.user.auth_user_id, m.auth);
        assert.equal(accepted.body.purpose_proof.initiating_session_id, null);
        assert.equal(accepted.body.auth_event.timestamp, f.created);
        assert.equal((await sql`SELECT auth_at FROM app.auth_sessions WHERE id=${next.session}`)[0].auth_at, f.created);
        const env = {DB: dbFor(next.claims)}, actor = await projectSession(env, {claims: next.claims,
          user: {...accepted.body.user, id: m.auth}, token: verifyTokenResult}, {existingLinkOnly: true});
        assert.equal(actor.userId, m.principal); assert.equal(actor.user.auth_user_id, m.auth);
        assert.equal(actor.authAt, f.created);
        const intake: any = await privacyRpc('request_account_deletion_v1', {p_request_id: crypto.randomUUID(), p_reason: 'Synthetic privacy review'}, env, actor);
        assert.equal(intake.handled, true); assert.equal(intake.value.state, 'pending_review');
        for (const flag of ['erasure_completed', 'account_access_restricted', 'auth_removed', 'retention_approval_granted', 'processor_operation_started'])
          assert.equal(intake.value[flag], false);
        assert.deepEqual(await identities(), before);
        const replay = await controller('verify', {...baseBody(f), operation_id: f.operation, code: '184275'});
        assert.equal(replay.status, 200); assert.equal(replay.body.verification_state, 'verified');
        assert.ok(!Object.hasOwn(replay.body, 'access_token')); assert.equal(verifiedEmails.length, count + 1);
      });

      await t.step('portal post-send receipts conceal accepted, rejected and uncertain eligibility without saying email was sent', async () => {
        const bodies: any[] = [];
        for (const outcome of ['accepted', 'rejected', 'unknown'] as const) {
          const email = 'portal-opacity-' + outcome + '@privacy.example.test'; sendOutcome.set(email, outcome);
          const {f, result} = await controllerFlow(null, email);
          assert.equal(result.status, 202); assert.equal(result.body.delivery_status, 'not_disclosed');
          const status = await controller('status', baseBody(f)); assert.equal(status.status, 200);
          assert.equal(status.body.delivery_status, 'not_disclosed');
          for (const body of [result.body, status.body]) {
            for (const key of ['identity_value', 'expected_auth_user_id', 'expected_user_id', 'email', 'send_outcome']) assert.ok(!Object.hasOwn(body, key));
            assert.equal(body.verification_state, 'not_started'); assert.equal(body.candidate_cleanup, 'not_required');
          }
          bodies.push(Object.keys(result.body).sort());
          verifyOutcome = 'rejected';
          const rejected = await controller('verify', {...baseBody(f), operation_id: f.operation, code: '184275'});
          assert.equal(rejected.status, 401); assert.equal(rejected.body.code, 'privacy_email_code_rejected');
        }
        verifyOutcome = 'accepted'; assert.deepEqual(bodies[0], bodies[1]); assert.deepEqual(bodies[1], bodies[2]);
      });

      await t.step('actual controller refuses unmapped and wrong native subjects before any candidate projection or contact linking', async () => {
        const unmapped = await member('portal-unmapped', false), {f} = await controllerFlow(null, unmapped.email);
        const fresh = await candidate(unmapped, f.created, false), before = await identities(); verifyTokenResult = token(fresh.claims);
        const refused = await controller('verify', {...baseBody(f), operation_id: f.operation, code: '184275'});
        assert.equal(refused.status, 503); assert.equal(refused.body.outcome, 'unconfirmed');
        assert.equal((await sql`SELECT count(*)::int AS n FROM app.auth_sessions WHERE id=${fresh.session}`)[0].n, 0);
        assert.equal((await sql`SELECT count(*)::int AS n FROM private.auth_principal_links WHERE auth_user_id=${unmapped.auth}`)[0].n, 0);
        assert.deepEqual(await identities(), before);
        const m = await member('native-controller'), other = await member('native-controller-other');
        // Even a matching confirmed contact cannot replace the immutable subject.
        await sql`UPDATE auth.users SET email=${m.email} WHERE id=${other.auth}`;
        const native = await controllerFlow(m), wrong = await candidate(other, native.f.created, false); verifyTokenResult = token(wrong.claims);
        const wrongResult = await controller('verify', {...baseBody(native.f), operation_id: native.f.operation, code: '184275'}, native.bearer);
        assert.equal(wrongResult.status, 503);
        assert.equal((await sql`SELECT count(*)::int AS n FROM app.auth_sessions WHERE id=${wrong.session}`)[0].n, 0);
        assert.ok(!loggedOut.includes(m.original)); assert.ok(!loggedOut.includes(wrong.session), 'Unproven wrong-subject token must not become cleanup authority');
      });

      await t.step('lost committed send claims and outcomes preserve the original ID and never automatically resend', async () => {
        for (const lost of ['prepare', 'send_claim', 'send_finish']) {
          const context = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
            .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
          const f: Flow = {id: crypto.randomUUID(), hash: await digest(context), context, mode: 'portal_bootstrap', member: null, created: 0, operation: crypto.randomUUID()};
          const body = {...baseBody(f), email: 'lost-' + lost + '@privacy.example.test'}, before = sent.length;
          const failed = await controller('challenge', body, null, lostReply(lost));
          assert.equal(failed.status, 503); assert.equal(failed.body.challenge_id, f.id);
          const current = await controller('status', baseBody(f)); assert.equal(current.status, 200);
          assert.equal(current.body.challenge_id, f.id);
          const replay = await controller('challenge', body); assert.equal(replay.status, 202);
          assert.equal(sent.length - before, lost === 'send_finish' ? 1 : 0);
          assert.equal((await sql`SELECT count(*)::int AS n FROM private.supabase_otp_challenges WHERE id=${f.id}`)[0].n, 1);
        }
      });

      await t.step('lost verify admission and true lost provider response stay held without token reconstruction or another verify', async () => {
        const m = await member('lost-verify-admission'), first = await controllerFlow(null, m.email), before = verifiedEmails.length;
        const body = {...baseBody(first.f), operation_id: first.f.operation, code: '184275'};
        assert.equal((await controller('verify', body, null, lostReply('verify_claim'))).status, 503);
        assert.equal((await controller('verify', body)).status, 503); assert.equal(verifiedEmails.length, before);
        const other = await member('lost-verify-body'), second = await controllerFlow(null, other.email);
        const unknownCandidate = await candidate(other, second.f.created, false); verifyTokenResult = token(unknownCandidate.claims);
        verifyOutcome = 'lost'; const calls = verifiedEmails.length;
        const lost = await controller('verify', {...baseBody(second.f), operation_id: second.f.operation, code: '184275'});
        assert.equal(lost.status, 503); assert.equal(lost.body.candidate_cleanup, 'unconfirmed');
        assert.equal((await controller('verify', {...baseBody(second.f), operation_id: second.f.operation, code: '184275'})).status, 503);
        assert.equal(verifiedEmails.length, calls + 1); verifyOutcome = 'accepted';
        const cancelled = await controller('cancel', {...baseBody(second.f), operation_id: second.f.operation});
        assert.equal(cancelled.body.candidate_cleanup, 'unconfirmed');
        assert.ok(!loggedOut.includes(unknownCandidate.session));
        assert.equal((await sql`SELECT count(*)::int AS n FROM auth.sessions WHERE id=${unknownCandidate.session}`)[0].n, 1,
          'A true unknown candidate remains unresolved, never guessed from session time');
      });

      await t.step('lost consume acknowledgement retains actual immutable proof and status without recovering lost session tokens', async () => {
        const m = await member('lost-consume'), {f} = await controllerFlow(null, m.email), next = await candidate(m, f.created, false);
        verifyTokenResult = token(next.claims); const before = verifiedEmails.length;
        const body = {...baseBody(f), operation_id: f.operation, code: '184275'};
        const failed = await controller('verify', body, null, lostReply('consume'));
        assert.equal(failed.status, 503); assert.equal(failed.body.outcome, 'unconfirmed');
        const status = await controller('status', baseBody(f)); assert.equal(status.body.verification_state, 'verified');
        assert.ok(!Object.hasOwn(status.body, 'access_token')); assert.ok(!Object.hasOwn(status.body, 'refresh_token'));
        assert.equal((await controller('verify', body)).status, 200); assert.equal(verifiedEmails.length, before + 1);
        assert.equal((await sql`SELECT privacy_verified_session_id::text FROM private.supabase_otp_challenges WHERE id=${f.id}`)[0].privacy_verified_session_id, next.session);
        assert.ok(loggedOut.includes(next.session), 'Only the received server-local candidate may receive best-effort local logout');
        // No claim is made that best-effort cleanup erased its local projection.
      });

      await t.step('exact received candidate cleanup accepts provider204 after original revocation and changed account, and preserves replacement', async () => {
        const m = await member('cleanup-exact'), {f, bearer} = await controllerFlow(m), next = await candidate(m, f.created, false);
        const candidateToken = token(next.claims); verifyTokenResult = candidateToken;
        const accepted = await controller('verify', {...baseBody(f), operation_id: f.operation, code: '184275'}, bearer);
        assert.equal(accepted.status, 200); const replacement = await candidate(m, f.created);
        await sql`UPDATE app.auth_sessions SET revoked_at=app.unixepoch(),revocation_reason='synthetic_account_switch' WHERE id=${m.original}`;
        await sql`DELETE FROM auth.sessions WHERE id=${m.original}`;
        await sql`UPDATE app.users SET access_status='suspended',revision=revision+1,email='changed-local-cleanup@privacy.example.test' WHERE id=${m.principal}`;
        await sql`UPDATE auth.users SET email='changed-managed-cleanup@privacy.example.test' WHERE id=${m.auth}`;
        const before = loggedOut.length;
        const retired = await controller('cancel', {...baseBody(f), operation_id: f.operation, candidate_access_token: candidateToken});
        assert.equal(retired.status, 200); assert.equal(retired.body.candidate_cleanup, 'confirmed');
        assert.deepEqual(loggedOut.slice(before), [next.session]);
        assert.equal((await sql`SELECT count(*)::int AS n FROM auth.sessions WHERE id=${next.session}`)[0].n, 0);
        const projection = (await sql`SELECT revoked_at,revocation_reason FROM app.auth_sessions WHERE id=${next.session}`)[0];
        assert.ok(projection.revoked_at); assert.equal(projection.revocation_reason, 'privacy_email_candidate_cleanup');
        assert.equal((await sql`SELECT revoked_at FROM app.auth_sessions WHERE id=${replacement.session}`)[0].revoked_at, null);
        assert.equal((await sql`SELECT count(*)::int AS n FROM auth.sessions WHERE id=${replacement.session}`)[0].n, 1);
        assert.equal((await sql`SELECT privacy_verified_session_id::text,privacy_cleanup_state FROM private.supabase_otp_challenges WHERE id=${f.id}`)[0].privacy_verified_session_id, next.session);
      });

      await t.step('recorded historical proof authorizes only exact expired-flow retirement, not a fresh sign-in or replacement cleanup', async () => {
        const m = await member('cleanup-historical'), old = (await at()) - 600, next = await candidate(m, old), replacement = await candidate(m, old);
        const id = crypto.randomUUID(), context = 'c'.repeat(64), operation = crypto.randomUUID(), nonce = crypto.randomUUID();
        const receipts = {[operation]: {state: 'verified', admitted_at: old}};
        // postgres@3.4.7 serializes a server-inferred jsonb parameter itself.
        // A pre-stringified receipt becomes a JSON string, violating the actual
        // object's shape. Use the driver's explicit JSON parameter instead.
        assert.equal((await sql`SELECT jsonb_typeof(${sql.json(receipts)}::jsonb) AS kind`)[0].kind, 'object');
        // Fully retained historical proof is a fixture: this test exercises the
        // current retirement helpers after expiry without manufacturing freshness.
        await sql`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,
          created_at,expires_at,delivery_status,attempts,consumed_at,privacy_mode,privacy_context_hash,privacy_expected_auth_user_id,
          privacy_expected_user_id,privacy_initiating_session_id,privacy_initiating_user_revision,privacy_verification_state,
          privacy_verification_operation_id,privacy_verify_receipts,privacy_verified_auth_user_id,privacy_verified_user_id,
          privacy_verified_session_id,privacy_verified_amr_at,privacy_cleanup_state)
          VALUES(${id},${await digest('email:' + m.email)},'email',${m.email},'member',0,${old},${old + 300},'accepted',1,${old + 1},
          'current_session',${context},${m.auth},${m.principal},${m.original},1,'verified',${operation},
          ${sql.json(receipts)}::jsonb,${m.auth},${m.principal},${next.session},${old},'not_started')`;
        await denied(() => call(dbFor(replacement.claims), 'cleanup_claim', id, context, operation, nonce));
        await assert.rejects(() => dbFor(next.claims).prepare('SELECT private.assert_actor(NULL,NULL,NULL,1,300)').first(),
          (error: any) => error.message === 'fresh_auth_required');
        assert.equal((await call(dbFor(next.claims), 'cleanup_claim', id, context, operation, nonce)).claimed, true);
        await denied(() => call(dbFor(next.claims), 'cleanup_finish', id, context, operation, crypto.randomUUID(), 'confirmed'));
        await sql`DELETE FROM auth.sessions WHERE id=${next.session}`;
        assert.equal((await call(dbFor(next.claims), 'cleanup_finish', id, context, operation, nonce, 'confirmed')).challenge.cleanup_state, 'confirmed');
        assert.equal((await sql`SELECT revoked_at FROM app.auth_sessions WHERE id=${replacement.session}`)[0].revoked_at, null);
      });

      await t.step('runtime column ACL and invoker gate deny privacy-row DML while original phone admission and proof remain usable', async () => {
        const m = await member('phone-preservation'), phone = '+250788123456', now = await at(), id = crypto.randomUUID();
        await sql`UPDATE app.users SET phone=${phone} WHERE id=${m.principal}`;
        await sql`UPDATE auth.users SET phone=${phone.slice(1)},phone_confirmed_at=now() WHERE id=${m.auth}`;
        const next = await candidate(m, now), db = dbFor(next.claims);
        await db.prepare(`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,
          registration_allowed,created_at,expires_at,delivery_status) VALUES(?,?,'phone',?,'member',0,?,?,'reserved')`)
          .bind(id, await digest('phone:' + phone), phone, now, now + 300).run();
        await db.prepare("UPDATE private.supabase_otp_challenges SET delivery_status='accepted',attempts=1,consumed_at=? WHERE id=?").bind(now, id).run();
        assert.equal(await db.prepare('SELECT private.record_managed_phone_verification(?) AS id').bind(id).first('id'), id);
        assert.equal(await db.prepare('SELECT private.managed_phone_binding(?,?,?,?) AS allowed').bind(m.principal, id, phone, next.session).first('allowed'), true);
        const m2 = await member('privacy-write-gate'), f = await flow(m2);
        await denied(() => dbFor(m2.claims).prepare("UPDATE private.supabase_otp_challenges SET delivery_status='accepted' WHERE id=?").bind(f.id).run());
        await assert.rejects(() => dbFor(m2.claims).prepare('UPDATE private.supabase_otp_challenges SET privacy_cancelled_at=? WHERE id=?').bind(now, f.id).run(),
          (error: any) => error.code === '42501');
        const columns = await sql`SELECT a.attname,has_column_privilege('collect_runtime',a.attrelid,a.attname,'INSERT') AS i,
          has_column_privilege('collect_runtime',a.attrelid,a.attname,'UPDATE') AS u FROM pg_attribute a
          WHERE a.attrelid='private.supabase_otp_challenges'::regclass AND a.attname LIKE 'privacy_%' AND a.attnum>0`;
        assert.ok(columns.length > 0); for (const c of columns) {assert.equal(c.i, false); assert.equal(c.u, false);}
        assert.equal((await sql`SELECT relrowsecurity FROM pg_class WHERE oid='private.supabase_otp_challenges'::regclass`)[0].relrowsecurity, true);
        for (const role of ['anon', 'authenticated']) {
          const reserved = await sql.reserve();
          try {
            await reserved.unsafe('BEGIN'); await reserved.unsafe('SET LOCAL ROLE ' + role);
            await assert.rejects(() => reserved.unsafe('SELECT * FROM private.supabase_otp_challenges'), (error: any) => error.code === '42501');
          } finally {await reserved.unsafe('ROLLBACK'); reserved.release();}
          assert.equal((await sql`SELECT has_function_privilege(${role},'private.privacy_email_prepare(text,text,text,text)','EXECUTE') AS allowed`)[0].allowed, false);
        }
        const helpers = await sql`SELECT p.proname,p.prosecdef,p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='private' AND p.proname LIKE 'privacy_email_%'`;
        assert.ok(helpers.length >= 10);
        for (const helper of helpers) {assert.equal(helper.prosecdef, true); assert.deepEqual(helper.proconfig, ['search_path=pg_catalog']);}
        assert.equal((await sql`SELECT count(*)::int AS n FROM pg_constraint c WHERE c.conrelid='private.supabase_otp_challenges'::regclass
          AND c.contype='f' AND c.confrelid IN('auth.users'::regclass,'auth.sessions'::regclass)`)[0].n, 0);
        assert.equal((await sql`SELECT count(*)::int AS n FROM app.ledger_entries`)[0].n, 0);
      });

      let inventoryReviewer: {db: ReturnType<typeof adminEmailFixtureDatabase>; principal: string} | null = null;
      await t.step('private copy inventory retains native subject attribution after contact change and flags unresolved verification', async () => {
        const m = await member('inventory-subject'), f = await flow(m); await admit(f);
        await call(dbFor(m.claims), 'verify_finish', f.id, f.hash, f.operation, 'unconfirmed');
        await sql`UPDATE app.users SET email='inventory-local-changed@privacy.example.test' WHERE id=${m.principal}`;
        await sql`UPDATE auth.users SET email='inventory-managed-changed@privacy.example.test' WHERE id=${m.auth}`;
        // A current Admin BFF and actual email proof are required independently
        // of truthful optional managed MFA. No owner connection or role-catalog
        // edit substitutes for either native authorization layer.
        const roleCatalogBefore = await sql`SELECT role,permission FROM app.admin_account_role_capabilities ORDER BY role,permission`;
        assert.deepEqual(roleCatalogBefore.filter((row: {permission: string; role: string}) => row.permission === 'privacy.review').map((row: {permission: string; role: string}) => row.role), ['owner']);
        async function reviewerActor(label: string, role: 'admin' | 'owner', email?: string) {
          const reviewer = await member(label, true, email), session = crypto.randomUUID(), factor = crypto.randomUUID();
          const now = await at(), stamp = new Date().toISOString(), admin = crypto.randomUUID(), publicId = crypto.randomUUID();
          const hash = await digest('synthetic-privacy-reviewer-cookie:' + admin), origin = 'https://privacy-admin.example.test';
          await sql`INSERT INTO app.admin_grants(user_id,permission,granted_by,granted_at) VALUES(${reviewer.principal},'privacy.review','synthetic-fixture',${stamp})`;
          await sql`INSERT INTO auth.sessions(id,user_id,aal,factor_id) VALUES(${session},${reviewer.auth},'aal2',${factor})`;
          await sql`INSERT INTO auth.mfa_factors(id,user_id,status) VALUES(${factor},${reviewer.auth},'verified')`;
          await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at) VALUES(${session},'totp',to_timestamp(${now}))`;
          await sql`INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES(${session},${reviewer.principal},'admin',${now - 5},${now - 5},${now + 3600})`;
          await sql`INSERT INTO app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter)
            VALUES(${factor},${reviewer.principal},'Synthetic reviewer','{"managed_by":"supabase"}','verified',${now},${session},${now},0)`;
          const raw = dbFor({...claimsFor(reviewer.auth, session, now - 5), aal: 'aal2', amr: [{method: 'otp', timestamp: now - 5}, {method: 'totp', timestamp: now}]});
          await raw.prepare('SELECT private.record_mfa_projection(?::uuid)').bind(factor).first();
          await raw.prepare('UPDATE app.auth_sessions SET assurance_level=2,mfa_at=?,mfa_factor_id=? WHERE id=?').bind(now, factor, session).run();
          await sql`INSERT INTO app.admin_users(id,email,role,status,password_hash,created_at,updated_at)
            VALUES(${admin},${reviewer.email},${role},'active','synthetic-managed',${now},${now})`;
          await sql`INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)
            VALUES(${admin},${reviewer.principal},'synthetic-local-privacy-reviewer',${stamp})`;
          await sql`INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
            SELECT ${hash},${publicId},a.id,a.auth_version,s.id,${origin},s.auth_at,s.expires_at
            FROM app.admin_users a CROSS JOIN app.auth_sessions s WHERE a.id=${admin} AND s.id=${session}`;
          await sql`INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)
            VALUES(${hash},${reviewer.auth},${session},'{}')`;
          const account = {id:admin, token_hash:hash, origin, public_id:publicId};
          const db = adminEmailFixtureDatabase(raw, account);
          await assert.rejects(() => inventoryPrivateRetention({DB:raw}, m.principal),
            (error:any) => error.code === '42501' && error.message === 'admin_email_denied');
          await assert.rejects(() => inventoryPrivateRetention({DB:db}, m.principal),
            (error:any) => error.code === '42501' && error.message === 'recent_email_sign_in_required');
          // These are explicit local managed-service facts for this exact
          // original OTP event. Only the real kernel inserts dedicated proof.
          const challenge = crypto.randomUUID(), otpAt = now - 5;
          await sql`INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at)
            VALUES(${session},'otp',to_timestamp(${otpAt}))`;
          await sql`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,
            registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)
            VALUES(${challenge},${await digest('email:' + reviewer.email)},'email',${reviewer.email},'admin',0,
              ${otpAt - 1},${otpAt + 299},1,${otpAt},'accepted')`;
          await raw.prepare('SELECT private.admin_email_record_initial(?::text,?::text,?::text,?::text,?::text) AS result')
            .bind(admin, hash, origin, publicId, challenge).first('result');
          const status = await raw.prepare('SELECT private.admin_email_status(?::text,?::text,?::text,?::text) AS result')
            .bind(admin, hash, origin, publicId).first('result');
          assert.equal(status.email_verified_at, otpAt); assert.ok(status.proof_id);
          const links = (await sql`SELECT a.email AS admin_email,u.email AS app_email,managed.email AS managed_email,
            a.role,l.user_id,b.auth_user_id::text AS auth_user_id,c.auth_session_id,c.public_id
            FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id
            JOIN app.users u ON u.id=l.user_id JOIN app.admin_sessions c ON c.user_id=a.id
            JOIN private.bff_sessions b ON b.token_hash=c.token_hash JOIN auth.users managed ON managed.id=b.auth_user_id
            WHERE a.id=${admin} AND c.token_hash=${hash}`)[0];
          assert.equal(links.admin_email, reviewer.email); assert.equal(links.app_email, reviewer.email);
          assert.equal(links.managed_email, reviewer.email); assert.equal(links.role, role);
          assert.equal(links.user_id, reviewer.principal); assert.equal(links.auth_user_id, reviewer.auth);
          assert.equal(links.auth_session_id, session); assert.equal(links.public_id, publicId);
          return {db, principal:reviewer.principal, challenge};
        }
        const originalReviewer = await reviewerActor('inventory-reviewer', 'admin');
        await assert.rejects(() => inventoryPrivateRetention({DB:originalReviewer.db}, m.principal),
          (error:any) => error.code === '42501' && error.message === 'permission_denied');
        const reviewer = await reviewerActor('inventory-owner', 'owner', 'info@ikanisa.com'), db = reviewer.db;
        assert.deepEqual(await sql`SELECT role,permission FROM app.admin_account_role_capabilities ORDER BY role,permission`, roleCatalogBefore);
        const result = await inventoryPrivateRetention({DB: db}, m.principal);
        assert.equal(result.classes['private:supabase_otp_challenges'].count, 1);
        assert.equal(result.classes['private:supabase_otp_challenges'].rows[0].lifecycle.unresolved, true);
        assert.equal(result.in_flight_unresolved, true);
        assert.equal(result.external_copy_disposition, 'blocked');
        const own = (await inventoryPrivateRetention({DB:db}, reviewer.principal)).classes['private:supabase_otp_challenges'];
        assert.equal(own.count, 1, 'Only the reviewer exact original Admin OTP copy is attributable');
        assert.equal(own.rows[0].key_sha256, await digest(reviewer.challenge));
        assert.equal(own.rows[0].lifecycle.active, false); assert.equal(own.rows[0].lifecycle.unresolved, false);
        inventoryReviewer = {db, principal: reviewer.principal};
      });

      await t.step('cancelled expired unconfirmed verification alone keeps private inventory unresolved after active admission has ended', async () => {
        assert.ok(inventoryReviewer, 'The actual managed reviewer must be established first');
        const m = await member('inventory-expired-unconfirmed'), old = (await at()) - 600;
        const id = crypto.randomUUID(), operation = crypto.randomUUID();
        // Historical unresolved state is fixture data, not an aging-clock or
        // mutable-identity shortcut. Its active predicate is deliberately false.
        await sql`INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,
          created_at,expires_at,delivery_status,attempts,privacy_mode,privacy_context_hash,privacy_expected_auth_user_id,
          privacy_expected_user_id,privacy_initiating_session_id,privacy_initiating_user_revision,privacy_verification_state,
          privacy_verification_operation_id,privacy_verify_receipts,privacy_cancelled_at,privacy_cleanup_state)
          VALUES(${id},${await digest('email:' + m.email)},'email',${m.email},'member',0,${old},${old + 300},'unknown',1,
          'current_session',${'d'.repeat(64)},${m.auth},${m.principal},${m.original},1,'unconfirmed',${operation},
          ${sql.json({[operation]: {state: 'unconfirmed', admitted_at: old}})}::jsonb,${old + 2},'unconfirmed')`;
        const row = (await sql`SELECT expires_at,privacy_cancelled_at,consumed_at,privacy_verified_user_id
          FROM private.supabase_otp_challenges WHERE id=${id}`)[0];
        assert.ok(row.expires_at < await at()); assert.ok(row.privacy_cancelled_at !== null);
        assert.equal(row.consumed_at, null); assert.equal(row.privacy_verified_user_id, null);
        const result = await inventoryPrivateRetention({DB: inventoryReviewer.db}, m.principal);
        const otp = result.classes['private:supabase_otp_challenges'];
        assert.equal(otp.count, 1); assert.equal(otp.rows[0].key_sha256, await digest(id));
        assert.equal(otp.rows[0].lifecycle.active, false);
        assert.equal(otp.rows[0].lifecycle.unresolved, true);
        // These are the other branches in the aggregate. Neither may mask a
        // regression which drops the OTP unresolved predicate.
        assert.equal(result.classes['private:admin_invitation_attempts'].count, 0);
        assert.equal(result.classes['private:storage_put_intents'].count, 0);
        assert.equal(result.in_flight_unresolved, true);
        assert.equal(result.external_copy_disposition, 'blocked');
      });

      await t.step('portal verified-only canonical identity retains the consumed copy after both contacts change', async () => {
        assert.ok(inventoryReviewer, 'The actual managed reviewer must be established first');
        const m = await member('inventory-portal-verified'), f = await flow(null, m.email);
        await admit(f); const next = await candidate(m, f.created);
        const consumed = await consume(f, next.claims);
        assert.equal(consumed.challenge.expected_user_id, null);
        assert.equal(consumed.challenge.expected_auth_user_id, null);
        assert.equal(consumed.proof.user_id, m.principal);
        const localEmail = 'inventory-portal-local-changed@privacy.example.test';
        const managedEmail = 'inventory-portal-managed-changed@privacy.example.test';
        await sql`UPDATE app.users SET email=${localEmail} WHERE id=${m.principal}`;
        await sql`UPDATE auth.users SET email=${managedEmail} WHERE id=${m.auth}`;
        const row = (await sql`SELECT privacy_expected_user_id,privacy_verified_user_id,identity_value,consumed_at
          FROM private.supabase_otp_challenges WHERE id=${f.id}`)[0];
        assert.equal(row.privacy_expected_user_id, null); assert.equal(row.privacy_verified_user_id, m.principal);
        assert.equal(row.identity_value, m.email); assert.notEqual(row.identity_value, localEmail);
        assert.notEqual(row.identity_value, managedEmail); assert.ok(row.consumed_at !== null);
        assert.equal((await sql`SELECT count(*)::int AS n FROM app.admin_principal_links WHERE user_id=${m.principal}`)[0].n, 0);
        assert.equal((await sql`SELECT phone FROM app.users WHERE id=${m.principal}`)[0].phone, null);
        const result = await inventoryPrivateRetention({DB: inventoryReviewer.db}, m.principal);
        const otp = result.classes['private:supabase_otp_challenges'];
        assert.equal(otp.count, 1); assert.equal(otp.rows[0].key_sha256, await digest(f.id));
        assert.equal(otp.rows[0].lifecycle.active, false); assert.equal(otp.rows[0].lifecycle.unresolved, false);
        assert.equal(result.classes['private:admin_invitation_attempts'].count, 0);
        assert.equal(result.classes['private:storage_put_intents'].count, 0);
        assert.equal(result.in_flight_unresolved, false);
        assert.equal(result.external_copy_disposition, 'blocked');
      });
    } finally {globalThis.fetch = originalFetch; await finishSqlFixtureWork();await sql.end();}
  },
});
