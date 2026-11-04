import {loadReviewedPlatformFixture} from '../../../../scripts/supabase/testing/curated-platform-fixture.mjs';
import {initializeSqlFixture,finishSqlFixtureWork} from './helpers/fenced-postgres.js';
import {fencedTest} from './helpers/fenced-unit.js';
import {assert, assertEquals} from 'jsr:@std/assert@1.0.14';
import {connection,PostgresDatabase} from './helpers/fenced-postgres.js';
import {createHandler} from './helpers/real-handler.js';
import {encrypt} from './helpers/module-domain-encryption.js';
import {callTool} from '../../../../tools/collect-admin-mcp/src/tools.mjs';
import {parseSession} from '../../../../tools/collect-admin-mcp/src/api.mjs';

// Local integration evidence only: real handlers/transactions, synthetic GoTrue.
// No hosted Supabase, delivery service, financial posting or real OTP is used.
const database = Deno.env.get('COLLECT_ADMIN_HISTORY_TEST_DATABASE_URL');
const adminOrigin = 'https://admin.example';
const issuer = 'https://synthetic-history-supabase.example';
const password = 'synthetic-local-fixture-password-only';
const code = '111111';

type ManagedSession = {
  id: string;
  claims: Record<string, any>;
  accessToken: string;
  refreshToken: string;
  user: Record<string, any>;
};
type Actor = {
  authId: string;
  principalId: string;
  accountId: string;
  email: string;
  factorId: string;
  initialRole: 'owner' | 'admin' | 'staff';
  managed: ManagedSession;
  cookie: string;
  csrf: string;
};
type GroupInput = {
  title: string;
  slug: string;
  description: string;
  collection_type: string;
  owner_user_id: string;
  receiver: {label: string; network: string; momo_number_or_code: string};
  reason: string;
};
type Commit = {requestId: string; collectionId: string; sessionId: string};
class SyntheticLostReply extends Error {}

// Independent MCP contract oracle: do not import the backend's ID computation.
async function expectedCanonicalRequestId(principalId: string, originalKey: string) {
  const bytes = await crypto.subtle.digest('SHA-256',
    new TextEncoder().encode(`collect-admin:${principalId}:${originalKey}`));
  const hex = Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-8${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

function accessToken(claims: Record<string, any>) {
  return btoa(JSON.stringify({alg: 'ES256', typ: 'JWT'})) + '.' +
    btoa(JSON.stringify(claims)) + '.synthetic-not-a-hosted-signature';
}
function sessionResponse(session: ManagedSession) {
  return {
    access_token: session.accessToken, refresh_token: session.refreshToken,
    expires_in: 900, token_type: 'bearer', user: session.user,
  };
}

fencedTest({
  name: 'Admin history on local PostgreSQL: own receipts, committed lost reply and current authority fences',
  ignore: !database && Deno.env.get('COLLECT_CI_SYNTHETIC') !== 'true',
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async (t) => {
    assert(database, 'COLLECT_ADMIN_HISTORY_TEST_DATABASE_URL is required in CI.');
    const target = new URL(database!);
    assert(
      ['postgres:', 'postgresql:'].includes(target.protocol) &&
      target.hostname === '127.0.0.1' &&
      ((target.password === 'collect_local_fixture_only' &&
        (target.port === '55439' || (Deno.env.get('COLLECT_CI_SYNTHETIC') === 'true' && target.port === '55441'))) ||
       (Deno.env.get('COLLECT_CI_SYNTHETIC') === 'true' && target.port === '55443' && target.password.length > 0)) &&
      target.pathname === '/collect_admin_history_test' &&
      target.username === 'collect_test' &&
      !target.search && !target.hash,
      'Only the dedicated synthetic Admin-history loopback database is allowed.',
    );
    const sql = connection(database!);await initializeSqlFixture(sql);
    const nativeFetch = globalThis.fetch;
    let server: Deno.HttpServer | undefined;
    const fixtures = new Map<string, Actor>();
    const tokens = new Map<string, {actor: Actor; session: ManagedSession}>();
    const reauthCandidates = new Set<string>();
    const unexpectedAuthRequests: string[] = [];
    const authRequests: string[] = [];
    const mutationAttempts = new Map<string, number>();

    try {
      // Match the existing PostgreSQL integration setup, independent of cwd.
      const present = await sql`select to_regclass('app.users') as present`;
      if (!present[0].present) {
        const setup = await sql.reserve();
        try {
          await setup.unsafe(await Deno.readTextFile(new URL('../../../tests/sql/00_local_auth_fixture.sql', import.meta.url)));
          const reviewedPlatform=await loadReviewedPlatformFixture(new URL('../../../../',import.meta.url),{includeMfaRetirementMigration:true});
          assert(reviewedPlatform.names.length === 13, 'Exactly thirteen reviewed curated migrations are required for MFA retirement.');
          await reviewedPlatform.apply(text => setup.unsafe(text));
        } finally {
          setup.release();await initializeSqlFixture(sql);
        }
      }

      // Local GoTrue native facts must agree with the confirmed /user DTO.
      await sql.unsafe('ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz');

      async function publicId() {
        const [row] = await sql`select lpad((coalesce(max(public_id::integer),-1)+1)::text,6,'0') as id
          from app.users where public_id<>'999999'`;
        assert(/^[0-9]{6}$/.test(row.id) && row.id !== '999999');
        return row.id;
      }
      async function prepareSession(actor: Actor, method: 'otp' | 'password' = 'otp') {
        const id = crypto.randomUUID(), stamp = Math.floor(Date.now() / 1000) - 4;
        await sql`insert into auth.sessions(id,user_id,aal,not_after)
          values(${id},${actor.authId},'aal1',now()+interval '2 hours')`;
        await sql`insert into auth.mfa_amr_claims(session_id,authentication_method,updated_at)
          values(${id},${method},to_timestamp(${stamp}))`;
        const factors = await sql`select id,status from auth.mfa_factors
          where id=${actor.factorId} and user_id=${actor.authId}`;
        assertEquals(factors.length, 1, 'The synthetic managed user must own its seeded MFA factor.');
        assert(['unverified', 'verified'].includes(factors[0].status));
        const user = {
          id: actor.authId, email: actor.email, email_confirmed_at: new Date().toISOString(),
          factors: [{id: factors[0].id, factor_type: 'totp', status: factors[0].status}],
          app_metadata: {provider: 'email'}, user_metadata: {},
        };
        const claims = {
          sub: actor.authId, session_id: id, role: 'authenticated', aal: 'aal1',
          aud: 'authenticated', iat: stamp, exp: stamp + 900, iss: issuer + '/auth/v1',
          amr: [{method, timestamp: stamp}],
        };
        actor.managed = {id, claims, accessToken: accessToken(claims),
          refreshToken: 'synthetic-history-refresh-' + id, user};
        tokens.set(actor.managed.accessToken, {actor, session: actor.managed});
      }
      async function approvedActor(role: 'owner' | 'admin' | 'staff'): Promise<Actor> {
        const actor = {
          authId: crypto.randomUUID(), principalId: crypto.randomUUID(), accountId: crypto.randomUUID(),
          email: '', factorId: crypto.randomUUID(), initialRole: role,
          managed: undefined as unknown as ManagedSession, cookie: '', csrf: '',
        };
        actor.email = role === 'owner' ? 'info@ikanisa.com' : 'history-' + role + '-' + actor.accountId + '@example.test';
        const stamp = Math.floor(Date.now() / 1000) - 4, now = new Date().toISOString();
        await sql`insert into auth.users(id,email,email_confirmed_at)values(${actor.authId},${actor.email},now())`;
        await sql`insert into auth.mfa_factors(id,user_id,status)values(${actor.factorId},${actor.authId},'unverified')`;
        await sql`insert into app.users(id,email,public_id,full_name,member_type,created_at,updated_at)
          values(${actor.principalId},NULL,${await publicId()},${'Synthetic History ' + role},'operator',${now},${now})`;
        await sql`insert into private.auth_principal_links(auth_user_id,user_id,proof_reference)
          values(${actor.authId},${actor.principalId},'synthetic-local-history-auth')`;
        await sql`insert into app.admin_users(id,email,role,status,display_name,created_at,updated_at)
          values(${actor.accountId},${actor.email},${role},'invited',${'Synthetic History ' + role},${stamp},${stamp})`;
        await sql`insert into app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)
          values(${actor.accountId},${actor.principalId},'synthetic-local-history-fixture',${now})`;
        await prepareSession(actor);
        fixtures.set(actor.email, actor);
        return actor;
      }

      const admin = await approvedActor('admin'), staff = await approvedActor('staff');
      // A non-operator canonical owner makes private group creation a real
      // operating-domain effect, without inventing any payment/ledger authority.
      const owner = crypto.randomUUID(), stamp = new Date().toISOString();
      await sql`insert into app.users(id,email,public_id,full_name,member_type,created_at,updated_at)
        values(${owner},${'history-owner-' + owner + '@example.test'},${await publicId()},
        'Synthetic History Group Owner','app',${stamp},${stamp})`;

      server = Deno.serve({hostname: '127.0.0.1', port: 0, onListen: () => {}}, async (request) => {
        const url = new URL(request.url), path = url.pathname;
        authRequests.push(request.method + ' ' + path);
        if (path === '/auth/v1/user' && request.method === 'GET') {
          const found = tokens.get((request.headers.get('Authorization') ?? '').slice(7));
          return found ? Response.json(found.session.user) : Response.json({error_code: 'invalid_token'}, {status: 401});
        }
        if (path === '/auth/v1/otp' && request.method === 'POST') {
          const body = await request.json();
          return fixtures.has(body.email)
            ? Response.json({message_id: 'synthetic-no-email-or-OTP-delivery'})
            : Response.json({error_code: 'invalid_email'}, {status: 400});
        }
        if (path === '/auth/v1/verify' && request.method === 'POST') {
          const body = await request.json(), actor = fixtures.get(body.email);
          if (!actor || body.token !== code) return Response.json({error_code: 'invalid_otp'}, {status: 400});
          const at = Math.floor(Date.now() / 1000);
          const pending = await sql`select challenge_id from private.admin_email_operations
            where admin_id=${actor.accountId} and original_session_id=${actor.managed.id}
              and mode='reauth' and verification_state='verifying'`;
          assert(pending.length <= 1, 'Only the actual one-shot email verification intent may create a candidate.');
          let session = actor.managed;
          if (pending.length === 1) {
            // Synthetic GoTrue creates a distinct managed candidate. The actual
            // BFF email helpers record and retire it; never replace the original.
            const sid = crypto.randomUUID();
            assert(sid !== actor.managed.id);
            await sql`insert into auth.sessions(id,user_id,aal,not_after)
              values(${sid},${actor.authId},'aal1',now()+interval '2 hours')`;
            session = {id: sid, claims: {...actor.managed.claims, session_id: sid, aal: 'aal1',
              iat: at, exp: at + 900, amr: [{method: 'otp', timestamp: at}]},
              accessToken: '', refreshToken: 'synthetic-history-candidate-' + sid,
              user: {...actor.managed.user}};
            reauthCandidates.add(sid);
          } else {
            // The real initial OTP event occurs now, after the reserved challenge.
            session.claims = {...session.claims, iat: at, exp: at + 900,
              amr: [{method: 'otp', timestamp: at}]};
          }
          await sql`insert into auth.mfa_amr_claims(session_id,authentication_method,updated_at)
            values(${session.id},'otp',to_timestamp(${at}))
            on conflict(session_id,authentication_method) do update set updated_at=excluded.updated_at`;
          session.accessToken = accessToken(session.claims);
          tokens.set(session.accessToken, {actor, session});
          return Response.json(sessionResponse(session));
        }
        if (path === '/auth/v1/logout' && request.method === 'POST') {
          const found = tokens.get((request.headers.get('Authorization') ?? '').slice(7));
          assert(found && url.searchParams.get('scope') === 'local' && reauthCandidates.has(found.session.id),
            'Only an owned synthetic email candidate may be retired by the local Auth model.');
          assert(found.session.id !== found.actor.managed.id, 'Never retire the original BFF-managed session.');
          await sql`delete from auth.mfa_amr_claims where session_id=${found.session.id}`;
          await sql`delete from auth.sessions where id=${found.session.id} and user_id=${found.actor.authId}`;
          reauthCandidates.delete(found.session.id);
          for (const [token, value] of tokens) if (value.session.id === found.session.id) tokens.delete(token);
          return new Response(null, {status: 204});
        }
        if (path === '/auth/v1/token' && url.searchParams.get('grant_type') === 'password' && request.method === 'POST') {
          const body = await request.json(), actor = fixtures.get(body.email);
          return actor && body.password === password
            ? Response.json(sessionResponse(actor.managed))
            : Response.json({error_code: 'invalid_credentials'}, {status: 400});
        }
        unexpectedAuthRequests.push(request.method + ' ' + path);
        return Response.json({error_code: 'unexpected_local_auth_request'}, {status: 500});
      });
      const fixtureOrigin = `http://127.0.0.1:${(server.addr as Deno.NetAddr).port}`;
      // Reject every unqualified destination; only this local GoTrue mock can
      // receive a fetch. PostgreSQL uses its separate, validated loopback URL.
      globalThis.fetch = (input, init) => {
        const raw = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
        const url = new URL(raw);
        if (url.origin !== issuer || !url.pathname.startsWith('/auth/v1/')) {
          return Promise.reject(new Error('Admin history fixture forbids outbound/provider fetch.'));
        }
        return nativeFetch(fixtureOrigin + url.pathname + url.search, init);
      };
      const env = {
        COLLECT_DATABASE_URL: database!, SUPABASE_URL: issuer,
        SUPABASE_PUBLISHABLE_KEY: 'synthetic-public-key', SUPABASE_SERVICE_ROLE_KEY: 'synthetic-server-key',
        ALLOWED_ORIGINS: adminOrigin, ADMIN_ORIGIN: adminOrigin,
        DATA_KEY_ID: 'synthetic-history-data-v1',
        DATA_ENCRYPTION_KEY: btoa(String.fromCharCode(...new Uint8Array(32).fill(7))),
        MOMO_PROCESSING_PAUSED: 'true', APP_ENVIRONMENT: 'test',
        SESSION_KEY_ID: 'synthetic-history-bff-v1',
        SESSION_ENCRYPTION_KEY: btoa(String.fromCharCode(...new Uint8Array(32).fill(8))),
      };
      let observedError: unknown;
      const handler = createHandler('admin-api', () => ({...env,
        INTERNAL_ERROR_OBSERVER: (error: unknown) => { observedError = error; }}));
      async function call(actor: Actor, path: string, options: {
        body?: unknown; method?: string; key?: string; cookie?: string; csrf?: string;
      } = {}) {
        const method = options.method ?? (options.body === undefined ? 'GET' : 'POST');
        if (method === 'POST' && path === '/operations/groups' && options.key) {
          mutationAttempts.set(options.key, (mutationAttempts.get(options.key) ?? 0) + 1);
        }
        observedError = undefined;
        const response = await handler(new Request('https://backend.example/functions/v1/admin-api/api/admin' + path, {
          method, headers: {
            Origin: adminOrigin, 'Content-Type': 'application/json', 'X-Collect-Requested-With': 'collect-admin',
            ...(options.cookie ?? actor.cookie ? {Cookie: options.cookie ?? actor.cookie} : {}),
            ...(options.csrf ?? actor.csrf ? {'X-Collect-CSRF': options.csrf ?? actor.csrf} : {}),
            ...(options.key ? {'Idempotency-Key': options.key} : {}),
          },
          ...(options.body === undefined ? {} : {body: JSON.stringify(options.body)}),
        }));
        if (response.status === 503 && observedError) throw observedError;
        if (response.ok && method === 'GET' && /^\/(operations|reconciliations)\/requests(?:[/?]|$)/.test(path)) {
          const history = await response.clone().json();
          assertEquals(history.contract_version, 2, 'History/recovery must retain the MCP contract version.');
          assertEquals(history.model, 'canonical_evidence_ledger', 'History/recovery must retain its canonical model.');
        }
        return response;
      }
      async function value(response: Response, status = 200) {
        const body = await response.json();
        assertEquals(response.status, status, JSON.stringify(body));
        return body;
      }
      function bindCookie(actor: Actor, response: Response, body: Record<string, any>) {
        const cookie = response.headers.get('Set-Cookie');
        assert(cookie, 'Expected an origin-bound Admin session cookie.');
        assert(cookie?.includes('HttpOnly') && cookie.includes('Secure') && cookie.includes('SameSite=Strict'));
        assert(/^[a-f0-9]{64}$/.test(body.csrfToken));
        assertEquals(JSON.stringify(body).includes('access_token'), false);
        actor.cookie = cookie.split(';')[0]; actor.csrf = body.csrfToken;
      }
      async function seedHistoricalMfa(actor: Actor) {
        // Privileged synthetic historical facts only. This does not exercise a
        // retired runtime endpoint, runtime proof function or cookie upgrade.
        const session = actor.managed, at = Math.floor(Date.now() / 1000);
        await sql`update auth.mfa_factors set status='verified'
          where id=${actor.factorId} and user_id=${actor.authId}`;
        await sql`update auth.sessions set aal='aal2',factor_id=${actor.factorId}
          where id=${session.id} and user_id=${actor.authId}`;
        await sql`insert into auth.mfa_amr_claims(session_id,authentication_method,updated_at)
          values(${session.id},'totp',to_timestamp(${at}))
          on conflict(session_id,authentication_method) do update set updated_at=excluded.updated_at`;
        await sql`insert into app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter)
          values(${actor.factorId},${actor.principalId},'Historical synthetic factor','{"managed_by":"supabase"}','verified',${at},${session.id},${at},0)
          on conflict(id) do update set status='verified',verified_at=excluded.verified_at`;
        await sql`insert into private.managed_mfa_proofs(session_id,user_id,factor_id,verified_at_epoch)
          values(${session.id},${actor.authId},${actor.factorId},${at})`;
        await sql`update app.auth_sessions set assurance_level=2,mfa_at=${at},mfa_factor_id=${actor.factorId}
          where id=${session.id} and user_id=${actor.principalId}`;
        await sql`update app.admin_sessions set issued_assurance_level=2,issued_mfa_at=${at},issued_mfa_factor_id=${actor.factorId}
          where auth_session_id=${session.id}`;
        session.user.factors = [{id: actor.factorId, factor_type: 'totp', status: 'verified'}];
        session.claims = {...session.claims, aal: 'aal2',
          amr: [...(session.claims.amr ?? []).filter((event: Record<string, any>) => event.method !== 'totp'),
            {method: 'totp', timestamp: at}]};
        session.accessToken = accessToken(session.claims);
        tokens.set(session.accessToken, {actor, session});
        const custody = {...env, DATA_KEY_ID: env.SESSION_KEY_ID,
          DATA_ENCRYPTION_KEY: env.SESSION_ENCRYPTION_KEY};
        const ciphertext = await encrypt(custody, new TextEncoder().encode(JSON.stringify({
          access_token: session.accessToken, refresh_token: session.refreshToken,
        })), `bff:${session.id}:${actor.authId}`);
        await sql`update private.bff_sessions set token_ciphertext=${ciphertext}
          where auth_session_id=${session.id}`;
        const [projected] = await sql`select assurance_level,mfa_at,mfa_factor_id
          from app.auth_sessions where id=${session.id}`;
        assertEquals(Number(projected.assurance_level), 2);
        assertEquals(projected.mfa_factor_id, actor.factorId);
        assertEquals(Number(projected.mfa_at), at);
      }
      async function newSignIn(actor: Actor, historicalMfa: boolean) {
        await prepareSession(actor, 'password');
        const response = await call(actor, '/auth/login', {body: {email: actor.email, password}});
        const body = await value(response);
        bindCookie(actor, response, body);
        assertEquals(body.user.assuranceLevel, 1);
        if (historicalMfa) await seedHistoricalMfa(actor);
      }
      async function freshEmail(actor: Actor) {
        const originalCookie = actor.cookie, originalCsrf = actor.csrf, originalSid = actor.managed.id;
        const before = await value(await call(actor, '/auth/email-verification'));
        assertEquals(before.emailVerifiedAt, null, 'A new BFF cannot inherit the prior cookie email proof.');
        // Preserve the actual identity cooldown. No challenge/clock/proof is
        // backdated, erased, relabelled or replayed to shorten this native case.
        const deadline = performance.now() + 62_500;
        for (;;) {
          assert(performance.now() < deadline, 'The bounded real identity-cooldown poll expired.');
          const [row] = await sql`select app.unixepoch() as at,coalesce(max(created_at)+60,0) as ready
            from private.supabase_otp_challenges where identity_type='email'
              and identity_value=${actor.email} and surface='admin'`;
          assert(performance.now() < deadline, 'The bounded real identity-cooldown observation expired.');
          const at = Number(row.at), ready = Number(row.ready);
          assert(Number.isSafeInteger(at) && Number.isSafeInteger(ready) && ready <= at + 60);
          if (at >= ready) break;
          assert(performance.now() < deadline, 'The real identity cooldown did not elapse within the bounded62.5s wait.');
          await new Promise(resolve => setTimeout(resolve, Math.min(250, Math.max(1, deadline - performance.now()))));
        }
        const receipt = await value(await call(actor, '/auth/email/request', {body: {}}), 202);
        assertEquals(Object.keys(receipt).sort(), ['challenge_id', 'delivery_status', 'expires_in', 'retry_after']);
        assertEquals(receipt.delivery_status, 'accepted'); assertEquals(receipt.retry_after, 60);
        const response = await call(actor, '/auth/email/verify', {body: {challenge_id: receipt.challenge_id, code}});
        const verified = await value(response);
        assertEquals(response.headers.get('Set-Cookie'), null);
        assertEquals(Object.keys(verified).sort(), ['contractVersion', 'emailVerifiedAt', 'sessionId']);
        assertEquals(verified.contractVersion, 1); assertEquals(verified.sessionId, before.sessionId);
        assert(typeof verified.emailVerifiedAt === 'string' && Number.isFinite(Date.parse(verified.emailVerifiedAt)));
        assertEquals(await value(await call(actor, '/auth/email-verification')), verified);
        assertEquals([actor.cookie, actor.csrf, actor.managed.id], [originalCookie, originalCsrf, originalSid]);
        const [operation] = await sql`select original_session_id,verified_session_id,cleanup_state
          from private.admin_email_operations where challenge_id=${receipt.challenge_id}`;
        assertEquals(operation.original_session_id, originalSid); assert(operation.verified_session_id !== originalSid);
        assertEquals(operation.cleanup_state, 'confirmed');
        assertEquals(Number((await sql`select count(*) as n from auth.sessions where id=${operation.verified_session_id}`)[0].n), 0);
        assertEquals(Number((await sql`select count(*) as n from app.auth_sessions where id=${operation.verified_session_id}`)[0].n), 0);
        assertEquals(Number((await sql`select count(*) as n from auth.sessions where id=${originalSid}`)[0].n), 1);
      }
      const groupInput = (label: string): GroupInput => {
        const suffix = crypto.randomUUID();
        return {
          title: 'Synthetic ' + label + ' history group', slug: 'history-' + label + '-' + suffix,
          description: 'Synthetic private group; no payment or settlement claim.', collection_type: 'ikimina',
          owner_user_id: owner, receiver: {label: 'Synthetic receiver', network: 'mtn_momo', momo_number_or_code: '250788123491'},
          reason: 'Synthetic local Admin history integration; no financial posting.',
        };
      };
      async function committed(actor: Actor, key: string, input: GroupInput): Promise<Commit> {
        const aliases = await sql`select * from app.admin_bridge_requests where admin_user_id=${actor.accountId} and idempotency_key=${key}`;
        assertEquals(aliases.length, 1);
        const alias = aliases[0];
        assertEquals(alias.request_id, await expectedCanonicalRequestId(actor.principalId, key));
        assertEquals(alias.operation, 'operations.groups.POST');
        const receipts = await sql`select * from app.request_receipts where user_id=${actor.principalId} and request_id=${alias.request_id}`;
        assertEquals(receipts.length, 1);
        assertEquals(receipts[0].operation, 'admin.bridge.groups.post.');
        assertEquals(receipts[0].session_id, alias.session_id);
        const receipt = JSON.parse(receipts[0].response_json);
        assertEquals(receipt.status, 'succeeded'); assertEquals(receipt.resource_type, 'groups');
        assertEquals(receipt.request_id, alias.request_id);
        const groups = await sql`select * from app.collections where slug=${input.slug}`;
        assertEquals(groups.length, 1);
        const group = groups[0];
        assertEquals(group.id, receipt.resource_id); assertEquals(group.title, input.title);
        assertEquals(group.creator_user_id, owner); assertEquals(group.visibility_status, 'private');
        assertEquals(Number(group.is_platform_sponsored), 0); assertEquals(Number(group.revision), 1);
        const memberships = await sql`select * from app.memberships where collection_id=${group.id}`;
        assertEquals(memberships.length, 1); assertEquals(memberships[0].user_id, owner);
        assertEquals(memberships[0].role, 'owner'); assertEquals(Number(memberships[0].active), 1);
        const audits = await sql`select * from app.audit_log where actor_user_id=${actor.principalId} and request_id=${alias.request_id}`;
        assertEquals(audits.length, 1); assertEquals(audits[0].entity_type, 'collection');
        assertEquals(audits[0].entity_id, group.id); assertEquals(audits[0].actor_session_id, alias.session_id);
        assertEquals(Number((await sql`select count(*) as n from app.payments where collection_id=${group.id}`)[0].n), 0);
        assertEquals(Number((await sql`select count(*) as n from app.ledger_entries where collection_id=${group.id}`)[0].n), 0);
        return {requestId: alias.request_id, collectionId: group.id, sessionId: alias.session_id};
      }
      const originalIdempotencyKey = 'history-staff-' + crypto.randomUUID();
      const adminKey = 'history-admin-' + crypto.randomUUID();
      const staffInput = groupInput('staff'), adminInput = groupInput('admin');
      let staffCommit: Commit, adminCommit: Commit;
      let momoCodeFixtureOwner: Actor | undefined;
      const lookup = (actor: Actor, key: string, base = '/operations') =>
        call(actor, base + '/requests/' + encodeURIComponent(key));
      // Stop after the first failed subcase; never replay a failed qualification.
      async function step(name: string, fn: () => Promise<void>) {
        assert(await t.step(name, fn), 'Admin history case failed: ' + name);
      }

      await step('two approved Admin/Staff actors traverse real BFF OTP admission and genuine initial email proof at AAL1', async () => {
        for (const actor of [admin, staff]) {
          const otp = await value(await call(actor, '/auth/otp', {body: {email: actor.email}}));
          const response = await call(actor, '/auth/verify', {body: {challenge_id: otp.challenge_id, code}});
          const body = await value(response);
          bindCookie(actor, response, body);
          assertEquals(body.user.id, actor.accountId); assertEquals(body.user.role, actor.initialRole);
          assertEquals(body.user.assuranceLevel, 1);
          const email = await value(await call(actor, '/auth/email-verification'));
          assert(typeof email.emailVerifiedAt === 'string' && Number.isFinite(Date.parse(email.emailVerifiedAt)));
          const current = await value(await call(actor, '/auth/session'));
          assertEquals(current.user.assuranceLevel, 1);
        }
      });

      await step('OTP-backed role catalogs and assisted-SMS view exclude MFA while preserving every other permission', async () => {
        const teamOwner = await approvedActor('owner');
        momoCodeFixtureOwner = teamOwner;
        const otp = await value(await call(teamOwner, '/auth/otp', {body: {email: teamOwner.email}}));
        const response = await call(teamOwner, '/auth/verify', {body: {challenge_id: otp.challenge_id, code}});
        const signedIn = await value(response); bindCookie(teamOwner, response, signedIn);
        const catalog = await value(await call(teamOwner, '/team/v2'));
        assertEquals(catalog.contractVersion, 2);
        for (const role of ['owner','admin','staff']) {
          const stored = Array.from(await sql`select permission from app.admin_account_role_capabilities where role=${role} order by permission`).map(row => {assert(typeof row === 'object' && row !== null && 'permission' in row && typeof row.permission === 'string');return row.permission;});
          assert(stored.includes('auth.mfa.enroll'));
          assertEquals([...catalog.permissionsByRole[role]].sort(), stored.filter(permission => permission !== 'auth.mfa.enroll'));
        }
        for (const actor of [admin,staff,teamOwner]) {
          const available = Array.from(await sql`select permission from app.admin_account_role_capabilities where role=${actor.initialRole} and permission<>'auth.mfa.enroll' order by permission`).map(row => {assert(typeof row === 'object' && row !== null && 'permission' in row && typeof row.permission === 'string');return row.permission;});
          const granted = new Set(Array.from(await sql`select permission from app.admin_grants where user_id=${actor.principalId} order by permission`).map(row => {assert(typeof row === 'object' && row !== null && 'permission' in row && typeof row.permission === 'string');return row.permission;}));
          assertEquals(available.filter(permission => !granted.has(permission)), actor.initialRole === 'owner' ? ['assisted_sms.manage','assisted_sms.read'] : []);
          const expected = available.filter(permission => granted.has(permission));
          const view = await new PostgresDatabase(sql,actor.managed.claims).prepare('SELECT permission FROM assisted_sms_current_sessions WHERE admin_id=? ORDER BY permission').bind(actor.accountId).all();
          assertEquals(view.results.map((row:any) => row.permission), expected);
          assertEquals((await sql`select count(*)::int as n from app.admin_grants where user_id=${actor.principalId} and permission='auth.mfa.enroll'`)[0].n,1);
        }
      });

      await step('member MoMo-code POST/PATCH validation preserves optional strings and historical facts', async () => {
        // Reuse the already admitted synthetic Owner fixture. This keeps the
        // Admin/Staff history assertions at their exact original one row.
        assert(momoCodeFixtureOwner, 'The existing Owner OTP fixture must be established first.');
        const actor = momoCodeFixtureOwner;
        const reason = 'Synthetic local member-code validation; no provider or financial posting.';
        const profile = {
          display_name: 'Synthetic MoMo Code Member', member_type: 'direct',
          momo_provider: staffInput.receiver.network,
          momo_number: staffInput.receiver.momo_number_or_code,
          reason,
        };
        const financialState = async () => Array.from(await sql`select
          (select count(*)::int from app.payments) as payments,
          (select count(*)::int from app.ledger_entries) as ledger_entries`);
        const financeBefore = await financialState();
        const storedProfile = async (id: string) => {
          const rows = await sql`select id,public_id,full_name,phone,email,member_type,momo_provider,momo_number,momo_pay_code,revision
            from app.users where id=${id}`;
          assertEquals(rows.length, 1);
          return rows[0];
        };
        const businessState = async (id: string | null = null) => ({
          users: Array.from(await sql`select id from app.users order by id`),
          aliases: Array.from(await sql`select idempotency_key,request_id from app.admin_bridge_requests
            where admin_user_id=${actor.accountId} order by idempotency_key`),
          receipts: Array.from(await sql`select request_id,operation,response_json from app.request_receipts
            where user_id=${actor.principalId} and operation like 'admin.bridge.users.%' order by request_id`),
          // These are successful user-mutation audits, not operational error logs.
          audits: Array.from(await sql`select action,entity_id,request_id,details_json from app.audit_log
            where actor_user_id=${actor.principalId} and action like 'admin.bridge.users.%' order by id`),
          profile: Array.from(await sql`select id,full_name,momo_pay_code,revision from app.users where id=${id}`),
        });
        const invalidCodes = [
          {label: 'letters', value: 'ABCD', code: 'invalid_momo_code'},
          {label: 'short', value: '123', code: 'invalid_momo_code'},
          {label: 'long', value: '1234567890', code: 'invalid_momo_code'},
          {label: 'unicode', value: '１２３４', code: 'invalid_momo_code'},
          {label: 'number', value: 8000, code: 'invalid_parameter'},
        ];
        for (const invalid of invalidCodes) {
          const before = await businessState();
          const denied = await value(await call(actor, '/operations/users', {
            method: 'POST', key: 'momo-code-create-' + invalid.label + '-' + crypto.randomUUID(),
            body: {...profile, momo_pay_code: invalid.value},
          }), 400);
          assertEquals(denied.error.code, invalid.code);
          assertEquals(await businessState(), before, 'Invalid POST must not create a member, alias, receipt or successful mutation audit.');
        }
        const creates = [
          {label: 'omitted', fields: {}, expected: ''},
          {label: 'null', fields: {momo_pay_code: null}, expected: ''},
          {label: 'empty', fields: {momo_pay_code: ''}, expected: ''},
          {label: 'minimum', fields: {momo_pay_code: '0012'}, expected: '0012'},
          {label: 'maximum', fields: {momo_pay_code: '000000123'}, expected: '000000123'},
        ];
        let memberId = '', creationRequestId = '';
        for (const sample of creates) {
          const receipt = await value(await call(actor, '/operations/users', {
            method: 'POST', key: 'momo-code-create-' + sample.label + '-' + crypto.randomUUID(),
            body: {...profile, ...sample.fields},
          }));
          assertEquals(receipt.status, 'succeeded'); assertEquals(receipt.resource_type, 'users');
          assert(typeof receipt.resource_id === 'string' && typeof receipt.request_id === 'string');
          const row = await storedProfile(receipt.resource_id);
          assertEquals(row.member_type, 'direct'); assertEquals([row.phone, row.email], [null, null]);
          assert(typeof row.public_id === 'string' && /^[0-9]{6}$/.test(row.public_id));
          assertEquals(row.momo_pay_code, sample.expected);
          if (!memberId) { memberId = receipt.resource_id; creationRequestId = receipt.request_id; }
        }
        assert(memberId && creationRequestId);
        for (const invalid of invalidCodes) {
          const row = await storedProfile(memberId), before = await businessState(memberId);
          const denied = await value(await call(actor, '/operations/users/' + memberId, {
            method: 'PATCH', key: 'momo-code-patch-' + invalid.label + '-' + crypto.randomUUID(),
            body: {momo_pay_code: invalid.value, expected_version: Number(row.revision), reason},
          }), 400);
          assertEquals(denied.error.code, invalid.code);
          assertEquals(await businessState(memberId), before, 'Invalid PATCH must not change the member, alias, receipt or successful mutation audit.');
        }
        const updates = [
          {label: 'empty', fields: {momo_pay_code: ''}, expected: ''},
          {label: 'maximum', fields: {momo_pay_code: '000000123'}, expected: '000000123'},
          {label: 'null', fields: {momo_pay_code: null}, expected: ''},
          {label: 'minimum', fields: {momo_pay_code: '0012'}, expected: '0012'},
          {label: 'trimmed', fields: {momo_pay_code: ' 008000 '}, expected: '008000'},
          {label: 'omitted', fields: {display_name: 'Synthetic MoMo Code Member Updated'}, expected: '008000'},
        ];
        for (const sample of updates) {
          const row = await storedProfile(memberId);
          const receipt = await value(await call(actor, '/operations/users/' + memberId, {
            method: 'PATCH', key: 'momo-code-patch-' + sample.label + '-' + crypto.randomUUID(),
            body: {...sample.fields, expected_version: Number(row.revision), reason},
          }));
          assertEquals(receipt.status, 'succeeded'); assertEquals(receipt.resource_id, memberId);
          assertEquals((await storedProfile(memberId)).momo_pay_code, sample.expected);
        }
        // Privileged LOCAL fixture arrangement only, like seedHistoricalMfa.
        // This does not claim that the runtime accepts new nonnumeric codes.
        const originalReceipt = Array.from(await sql`select * from app.request_receipts
          where user_id=${actor.principalId} and request_id=${creationRequestId}`);
        assertEquals(originalReceipt.length, 1);
        const historicalCode = 'Historical synthetic code';
        await sql`update app.users set momo_pay_code=${historicalCode},revision=revision+1,
          updated_at=${new Date().toISOString()} where id=${memberId}`;
        const historic = await storedProfile(memberId);
        await value(await call(actor, '/operations/users/' + memberId, {
          method: 'PATCH', key: 'momo-code-retain-history-' + crypto.randomUUID(),
          body: {display_name: 'Synthetic Historical Code Member', expected_version: Number(historic.revision), reason},
        }));
        const retained = await storedProfile(memberId);
        assertEquals(retained.momo_pay_code, historicalCode, 'Omission preserves existing history without revalidating or rewriting its code.');
        assertEquals(Number(retained.revision), Number(historic.revision) + 1);
        const beforeExplicit = await businessState(memberId);
        const denied = await value(await call(actor, '/operations/users/' + memberId, {
          method: 'PATCH', key: 'momo-code-explicit-history-' + crypto.randomUUID(),
          body: {momo_pay_code: historicalCode, expected_version: Number(retained.revision), reason},
        }), 400);
        assertEquals(denied.error.code, 'invalid_momo_code');
        assertEquals(await businessState(memberId), beforeExplicit, 'An explicitly supplied invalid code is not grandfathered.');
        await value(await call(actor, '/operations/users/' + memberId, {
          method: 'PATCH', key: 'momo-code-correct-history-' + crypto.randomUUID(),
          body: {momo_pay_code: '00001234', expected_version: Number(retained.revision), reason},
        }));
        assertEquals((await storedProfile(memberId)).momo_pay_code, '00001234');
        assertEquals(Array.from(await sql`select * from app.request_receipts
          where user_id=${actor.principalId} and request_id=${creationRequestId}`), originalReceipt);
        assertEquals(await financialState(), financeBefore, 'Member-code tests must not post payments or ledger entries.');
      });

      await step('lost response occurs after real Staff private-group commit; lookup recovers without resend', async () => {
        let lost = false;
        try {
          const response = await call(staff, '/operations/groups', {body: staffInput, key: originalIdempotencyKey});
          assertEquals(response.status, 200);
          // The actual handler has finished. Independent SQL proves its durable
          // effect before a synthetic client-boundary loss discards its reply.
          staffCommit = await committed(staff, originalIdempotencyKey, staffInput);
          await response.body?.cancel();
          throw new SyntheticLostReply('Synthetic response loss AFTER actual PostgreSQL commit.');
        } catch (error) {
          if (!(error instanceof SyntheticLostReply)) throw error;
          lost = true;
        }
        assert(lost); assertEquals(mutationAttempts.get(originalIdempotencyKey), 1);
        const recovered = await value(await lookup(staff, originalIdempotencyKey));
        assertEquals(recovered.status, 'succeeded'); assertEquals(recovered.request_id, staffCommit.requestId);
        assertEquals(recovered.receipt.resource_id, staffCommit.collectionId);
        assertEquals(mutationAttempts.get(originalIdempotencyKey), 1, 'Recovery must not resend the POST.');
        assertEquals(await committed(staff, originalIdempotencyKey, staffInput), staffCommit);
      });

      await step('own list and original-key lookup expose only each actor canonical receipts', async () => {
        const receipt = await value(await call(admin, '/operations/groups', {body: adminInput, key: adminKey}));
        adminCommit = await committed(admin, adminKey, adminInput);
        assertEquals(receipt.request_id, adminCommit.requestId);
        for (const [actor, key, expected] of [[staff, originalIdempotencyKey, staffCommit], [admin, adminKey, adminCommit]] as const) {
          for (const base of ['/operations', '/reconciliations']) {
            const history = await value(await call(actor, base + '/requests?limit=25&offset=0'));
            assertEquals(history.total, 1); assertEquals(history.rows.length, 1);
            assertEquals(history.rows[0].idempotency_key, key); assertEquals(history.rows[0].id, expected.requestId);
            assertEquals(history.rows[0].scope, 'groups.post'); assertEquals(history.rows[0].status, 'succeeded');
            assertEquals(history.rows[0].receipt.resource_id, expected.collectionId);
            const own = await value(await lookup(actor, key, base));
            assertEquals(own.status, 'succeeded'); assertEquals(own.request_id, expected.requestId);
          }
        }
      });

      await step('foreign histories disclose no identifiers; trailing and extra request segments return 404', async () => {
        for (const [actor, ownKey, foreignKey, foreignCommit] of [
          [staff, originalIdempotencyKey, adminKey, adminCommit], [admin, adminKey, originalIdempotencyKey, staffCommit],
        ] as const) {
          for (const base of ['/operations', '/reconciliations']) {
            const foreign = await value(await lookup(actor, foreignKey, base));
            assertEquals(foreign.status, 'not_found');
            assertEquals(Object.hasOwn(foreign, 'request_id'), false);
            assertEquals(Object.hasOwn(foreign, 'receipt'), false);
            assertEquals(JSON.stringify(foreign).includes(foreignCommit.requestId), false);
            assertEquals(JSON.stringify(foreign).includes(foreignCommit.collectionId), false);
            for (const suffix of ['/', '/' + ownKey + '/', '/' + ownKey + '/extra']) {
              const absent = await value(await call(actor, base + '/requests' + suffix), 404);
              assertEquals(absent.error.code, 'not_found');
            }
          }
        }
      });

      await step('same-session replay retains one effect; changed body under the original key returns 409', async () => {
        const replay = await value(await call(staff, '/operations/groups', {body: staffInput, key: originalIdempotencyKey}));
        assertEquals(replay.request_id, staffCommit.requestId);
        const conflict = await value(await call(staff, '/operations/groups', {
          body: {...staffInput, title: 'Conflicting title must never commit'}, key: originalIdempotencyKey,
        }), 409);
        assertEquals(conflict.error.code, 'request_conflict');
        assertEquals(await committed(staff, originalIdempotencyKey, staffInput), staffCommit);
      });

      await step('retired MFA routes have no provider, factor, cookie, proof or audit effect', async () => {
        for (const actor of [admin, staff]) {
          const snapshot = async () => ({
            tuple: Array.from(await sql`select to_jsonb(s) as app,to_jsonb(c) as cookie,to_jsonb(b) as bff
              from app.auth_sessions s join app.admin_sessions c on c.auth_session_id=s.id
              join private.bff_sessions b on b.token_hash=c.token_hash where s.id=${actor.managed.id}`),
            factors: Array.from(await sql`select id,user_id,status from auth.mfa_factors where user_id=${actor.authId} order by id`),
            proofs: Array.from(await sql`select * from private.admin_sensitive_email_proofs where admin_id=${actor.accountId} order by challenge_id`),
            audit: Array.from(await sql`select * from app.admin_account_audit where subject_id=${actor.accountId} order by id`),
          });
          const before = await snapshot(), cookie = actor.cookie, csrf = actor.csrf, calls = authRequests.length;
          for (const path of ['enroll','challenge','verify','cancel-enrollment','unenroll','unknown/nested']) {
            const response = await call(actor, '/auth/mfa/' + path, {body: {
              factor_id: actor.factorId, challenge_id: crypto.randomUUID(), code,
            }});
            const denied = await value(response, 410);
            assertEquals(denied.error.code, 'mfa_not_available');
            assertEquals(response.headers.get('Set-Cookie'), null);
            assertEquals([actor.cookie, actor.csrf], [cookie, csrf]);
            assertEquals(authRequests.length, calls);
            assertEquals(await snapshot(), before);
          }
          const current = await value(await call(actor, '/auth/session'));
          assertEquals(current.user.assuranceLevel, 1);
          assertEquals(current.user.permissions.includes('auth.mfa.enroll'), false);
        }
      });

      await step('historical managed AAL2 remains truthful after initial-email history writes and MCP authority stays current', async () => {
        for (const actor of [admin, staff]) {
          await seedHistoricalMfa(actor);
          const current = await value(await call(actor, '/auth/session'));
          assertEquals(current.user.assuranceLevel, 2);
          assertEquals(current.user.permissions.includes('auth.mfa.enroll'), false);
          assert(current.user.permissions.includes('account.manage'));
          assert(current.user.permissions.includes('collections.create'));
        }
        // The initial POST, deliberate same-session replay and changed-body
        // conflict are three attempts but still exactly one canonical effect.
        const attemptsBeforeMcp = mutationAttempts.get(originalIdempotencyKey);
        assertEquals(attemptsBeforeMcp, 3, 'Count only the three explicit POSTs already exercised above.');
        const mcp = {config:{origin:adminOrigin},withAuthority:async(permission:any,perform:any)=>{
          const user = parseSession(await value(await call(staff,'/auth/session')));
          assertEquals([user.id,user.principalId,user.role,user.assuranceLevel],[staff.accountId,staff.principalId,'staff',2]);
          assert([permission].flat().filter(Boolean).every(p=>user.permissions.includes(p)));
          const result = await perform({user,get:async(path:string)=>{assert(path.startsWith('/api/admin/'));return value(await call(staff,path.slice('/api/admin'.length)));}});
          assertEquals(parseSession(await value(await call(staff,'/auth/session'))),user); return result;
        }};
        assertEquals((await callTool(mcp,'collect_admin_session',{},undefined)).data.account.principalId,staff.principalId);
        const ownMcp = await callTool(mcp,'collect_admin_list_requests',{limit:25},undefined);
        assertEquals([ownMcp.data.total,ownMcp.data.rows.map((r:any)=>[r.id,r.idempotency_key,r.receipt.resource_id])],[1,[[staffCommit.requestId,originalIdempotencyKey,staffCommit.collectionId]]]);
        const recoveredMcp = await callTool(mcp,'collect_admin_get_request_status',{idempotency_key:originalIdempotencyKey},undefined);
        assertEquals([recoveredMcp.data.status,recoveredMcp.data.request_id,recoveredMcp.data.receipt.resource_id],['succeeded',staffCommit.requestId,staffCommit.collectionId]);
        assertEquals([recoveredMcp.data.recovery.automatic_retry,recoveredMcp.data.recovery.write_permitted],[false,false]);
        assertEquals(mutationAttempts.get(originalIdempotencyKey), attemptsBeforeMcp, 'MCP list/recovery must never add another POST.');
      });

      await step('new sign-in requires its own CSRF and recent email; historical AAL2 cannot replay an old-session write', async () => {
        const oldCookie = staff.cookie, oldCsrf = staff.csrf;
        await newSignIn(staff, false);
        assert(staff.cookie !== oldCookie); assert(staff.csrf !== oldCsrf);
        const csrf = await value(await call(staff, '/operations/groups', {
          body: staffInput, key: originalIdempotencyKey, csrf: oldCsrf,
        }), 403);
        assertEquals(csrf.error.code, 'csrf_rejected');
        const emailRequired = await value(await call(staff, '/operations/groups', {
          body: staffInput, key: originalIdempotencyKey,
        }), 403);
        assertEquals(emailRequired.error.code, 'recent_email_sign_in_required');
        await seedHistoricalMfa(staff);
        const historicalProofAlone = await value(await call(staff, '/operations/groups', {
          body: staffInput, key: originalIdempotencyKey,
        }), 403);
        assertEquals(historicalProofAlone.error.code, 'recent_email_sign_in_required');
        await freshEmail(staff);
        const conflict = await value(await call(staff, '/operations/groups', {
          body: staffInput, key: originalIdempotencyKey,
        }), 409);
        assertEquals(conflict.error.code, 'request_conflict');
        const attempts = mutationAttempts.get(originalIdempotencyKey);
        const recovered = await value(await lookup(staff, originalIdempotencyKey));
        assertEquals(recovered.receipt.resource_id, staffCommit.collectionId);
        assertEquals(mutationAttempts.get(originalIdempotencyKey), attempts);
        await sql`update auth.sessions set not_after=now()-interval '1 second' where id=${staffCommit.sessionId}`;
        const ended = await call(staff, '/operations/requests', {cookie: oldCookie});
        await value(ended, 401);
        assertEquals((await value(await lookup(staff, originalIdempotencyKey))).status, 'succeeded');
        assertEquals(await committed(staff, originalIdempotencyKey, staffInput), staffCommit);
      });

      await step('revoked history grant denies current and fresh cookie sessions without erasing receipts', async () => {
        await sql`delete from app.admin_grants where user_id=${staff.principalId} and permission='account.manage'`;
        for (const path of ['/operations/requests', '/operations/requests/' + originalIdempotencyKey,
          '/reconciliations/requests', '/reconciliations/requests/' + originalIdempotencyKey]) {
          const denied = await value(await call(staff, path), 403);
          assertEquals(denied.error.code, 'permission_required');
        }
        await newSignIn(staff, true);
        const current = await value(await call(staff, '/auth/session'));
        assertEquals(current.user.assuranceLevel, 2);
        assertEquals(current.user.permissions.includes('account.manage'), false);
        const denied = await value(await lookup(staff, originalIdempotencyKey), 403);
        assertEquals(denied.error.code, 'permission_required');
        assertEquals(await committed(staff, originalIdempotencyKey, staffInput), staffCommit);
      });

      await step('role change revokes the old Admin cookie; new approved Staff session recovers only its own history', async () => {
        const endedSession = admin.managed.id;
        const [beforeRole] = await sql`select role,auth_version from app.admin_users where id=${admin.accountId}`;
        assertEquals(beforeRole.role, 'admin');
        await sql`update app.admin_users set role='staff' where id=${admin.accountId}`;
        const [afterRole] = await sql`select role,auth_version from app.admin_users where id=${admin.accountId}`;
        assertEquals(afterRole.role, 'staff');
        assertEquals(afterRole.auth_version, beforeRole.auth_version, 'Role-only revocation must not rely on a version bump.');
        assert((await sql`select revoked_at from app.auth_sessions where id=${endedSession}`)[0].revoked_at !== null);
        assertEquals(Number((await sql`select count(*) as n from app.admin_sessions where user_id=${admin.accountId}`)[0].n), 0);
        await value(await lookup(admin, adminKey), 401);
        await value(await call(admin, '/operations/requests'), 401);
        await newSignIn(admin, true);
        const current = await value(await call(admin, '/auth/session'));
        assertEquals(current.user.role, 'staff');
        const recovered = await value(await lookup(admin, adminKey));
        assertEquals(recovered.request_id, adminCommit.requestId);
        assertEquals((await value(await lookup(admin, originalIdempotencyKey))).status, 'not_found');
        assertEquals(await committed(admin, adminKey, adminInput), adminCommit);
      });

      assertEquals(unexpectedAuthRequests, []);
      assertEquals(reauthCandidates.size, 0, 'Every actual email candidate was retired without touching the original session.');
      // Canonical effects are private collections, never fabricated finance.
      assertEquals(Number((await sql`select count(*) as n from app.payments where collection_id in (${staffCommit!.collectionId},${adminCommit!.collectionId})`)[0].n), 0);
      assertEquals(Number((await sql`select count(*) as n from app.ledger_entries where collection_id in (${staffCommit!.collectionId},${adminCommit!.collectionId})`)[0].n), 0);
    } finally {
      globalThis.fetch = nativeFetch;
      try { await server?.shutdown(); }
      finally { await finishSqlFixtureWork();await sql.end({timeout: 1}); }
    }
  },
});
