# Managed SMS gateway: synthetic ingress and nonce candidate

This directory contains a **qualification-only** request witness, fenced nonce
adapter and unversioned SQL candidate. It installs no route, does not change
`deploy/collect-sms/src/edge.ts`, and cannot enable the production gateway.
The existing gateway still returns 503 for a managed profile. The signer and
verifier here accept only a managed **qualification** profile and explicitly
synthetic proof; the exported unavailable response remains 503. No provider,
real credential, actual local source or production data is accessed by tests.

The existing managed-native-ingress protocol is restricted to the BuriMunsi
`collect-api` route and uses `collect_runtime`. The SMS gateway has a separate
`collect_sms_runtime` role, bearer/device authentication and work wrappers;
reusing the native route signature or granting its nonce function to SMS is
not qualified. This candidate therefore uses a separate, domain-separated SMS
witness. It binds method, exact logical SMS path/query, selected application
headers including Authorization, Origin and Idempotency-Key, the complete
bounded body, profile/proof digests, issued time and random nonce. It strips
forwarded and caller-supplied witness headers, rejects Worker subrequest markers,
limits body size/read time and accepts only the existing SMS function prefixes.
Encoded colon in message IDs remains usable; encoded path separators are
refused. A signed witness is ingress evidence, not a device, application or
staff credential.

Verification returns an opaque one-use token. A genuine `ApplicationWork`
context must assert its lease before and after a bounded nonce claim; only an
acknowledged `true` claim releases the original request. A claimer can only be
minted from an actual `GatewayDatabase` and the exact work context. The factory
uses `GatewayDatabase.prototype.withApplicationWork` to create a fresh wrapper
bound to that work, even when its input wrapper was previously bound to another
admission. An arbitrary callback, a claimer minted for another work context or
a reused claimer is rejected before any SQL. The original claim promise is
tracked by that work. A timeout or lost acknowledgement abandons the work and
cannot be converted into a settled request. A false/duplicate claim, expired
witness, aborted request, altered body/header/path or reused token is not
dispatched. The caller must still use the unchanged SMS app and its actual
authentication, permissions, idempotency and uncertain-outcome handling.

`synthetic-nonce-candidate.sql` is not a versioned migration and must not be
applied to production. It proposes a private nonce ledger and a separate
`collect_sms.consume_ingress_nonce` SECURITY DEFINER entrypoint. Its claim
requires the existing SMS work-write assertion and the exact admission's bound
deployment profile, serializes capacity/expiry and inserts a nonce once.
Direct ledger access is revoked; only the SMS runtime gets function execution.
A returned SQL `true` is provisional until the enclosing transaction commits;
`synthetic-nonce-adapter.mjs` expects a work-bound `GatewayDatabase.first()`
that returns after COMMIT acknowledgement. A timeout must never retry or
assume the first claim rolled back.

## Evidence and limits

- Synthetic tests cover witness tampering, expiration, replay, body bounds,
  cancellation, key separation, claim timeout and preserved unknown work. A
  cached Deno test passes the released request to the **actual SMS Hono app**
  with a fake DB and checks device tokens, revocation, application/device scope
  and no app dispatch on claim refusal. It reproduces the independent v1
  counterexample with work A and a database previously bound to work B: the
  arbitrary callback is refused before SQL, and a legitimate minted claimer
  executes under work A. A work-B claimer cannot be used for work A. The v1
  bytes are preserved in `v1-frozen/` as evidence; those relocated files are
  not a separately runnable package.
- A disposable PostgreSQL 17 test executes the nonce SQL with a restricted
  synthetic SMS role. It checks two-session serialization, rollback, expired
  and wrong-profile refusal and direct-table denial. Its work/deployment
  assertion functions are test doubles. It does not prove the actual managed
  SMS fence, real database grants, COMMIT delivery, load or replay persistence.
- Neither the proof record nor `CF-Worker` absence attests Cloudflare request
  provenance. No real frontdoor, direct-backend denial, Deno provider routing,
  management configuration or client path has been inspected by this candidate.
  No real TLS/DB endpoint, `COLLECT_SMS_DATABASE_URL` role, root CA or provider
  privilege graph has been qualified. The existing generic gateway connection
  accepts caller-configured database destinations/CA and is not by itself a
  managed-project identity proof.
- A real rollout requires an independently reviewed versioned nonce migration,
  exact predecessor/history and catalogue/role/ACL checks, retention and
  recovery classification for the new private table, a qualified managed
  identity binding, SMS source/epoch fence, dedicated role and pinned TLS
  endpoint, independently reviewed frontdoor/key custody and actual enforcement
  at both the proxy and Edge handler. The body/clock/nonce limits and loss of
  an upstream acknowledgement need real provider and load qualification.
- Existing SMS clients and server-to-server receipt/Auth-hook callers must reach
  the qualified frontdoor without losing their bearer or idempotency contract;
  current direct Supabase origins and the optional maintenance-token path need
  explicit routing decisions and end-to-end tests. A Cloudflare Worker marker
  may affect server-to-server callers. Android queue/revocation/SIM/FCM behavior,
  callbacks and uncertain dispatch recovery remain unverified on real devices.

A prior identity-chain experiment in another directory omitted four migrations
between archive and deployment identity. It is a synthetic subset, not proof of
complete history. The actual ordered source includes member history, guest auth,
notification channels and the SMS gateway migration before deployment identity,
and the SMS application-fence migration later. Do not invent history entries or
use the incomplete experiment as authorization.

## Tests

```sh
node --test scripts/supabase/managed-sms-gateway/synthetic-ingress.test.mjs
node --test --test-concurrency=1 scripts/supabase/managed-sms-gateway/synthetic-nonce-pg.test.mjs
deno test --cached-only --no-lock scripts/supabase/managed-sms-gateway/gateway-app-integration.test.ts
```

The Deno test uses cached dependencies without network access. The OS, Node,
Deno, shared libraries and dependency cache remain trusted. The tests do not
establish deployment or authorize enabling the feature.
