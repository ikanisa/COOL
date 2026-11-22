# Managed Supabase SMS: closed receipt-message slice

This directory contains an isolated Cloudflare Worker integration and a
Hyperdrive-oriented PostgreSQL adapter. **The production Worker entry point is
hard-closed in source**: `MANAGED_SMS_ISOLATION_QUALIFIED=false` returns 503
before request handling, database connection or provider dispatch. An
environment variable cannot change that source-level gate. The code has not
been deployed, connected to Supabase or exercised against a real phone, carrier,
Hyperdrive configuration or SMS provider.

The implemented handler covers only the existing OpenSMS receipt contract:
`POST /functions/v1/collect-sms/v1/messages` and scoped
`GET /functions/v1/collect-sms/v1/messages/:id`. It accepts only the existing
`app_` bearer-token form, forwards to the existing gateway application for
application-token lookup and `messages:write`/`messages:read` plus receipt-kind
checks, and requires the existing `Idempotency-Key` for message creation. A
receipt read precheck binds the exact stored message ID, nonempty application
identity, receipt kind and active token's read scope; the actual gateway response
is buffered, bounded and validated before any body or history is returned.
Unexpected or ambiguous response data fails closed. The existing application
stores the request digest and rejects reuse of that key with different content. A lost result remains unknown; no replacement POST or
automatic retry is made by this integration. The separately implemented reader
can reconcile an original message ID when the application has read scope.

Origin and physical route are checked against the exact configured HTTPS Worker
origin. Forwarded host, scheme, IP and Cloudflare-looking request headers never
establish authority. Browser origins are restricted to the verified Admin or
Worker origin. Receipt-route preflights check the exact requested method and
allowed headers without creating a database admission; no browser credential
cookies are enabled. Allowed origins receive CORS headers on success and denial.
Request bodies have a five-second total read deadline, are
canceled on abort/timeout, and only receipt payloads enter the handler. All
responses use `Cache-Control: no-store`. The local Worker does not dispatch FCM,
callbacks or scheduler work; external fetch is disabled in this slice. However,
the database's existing message triggers can enqueue FCM or webhook work for
other active consumers. Local flags do not isolate those consumers. Before any
activation, establish project-wide scheduler/device-consumer isolation and
reconcile all triggered rows and unknown external outcomes. Device, staff, OTP,
campaign and administrative routes remain closed: in particular this is
**not an operational phone-to-carrier SMS gateway**, and no device HMAC/replay
or queue transition is claimed. The existing gateway's application-token authentication is bearer-based;
it must not be described as per-request HMAC authentication.

## Database and fence boundary

Each request must acquire the existing durable SMS work admission and hold its
transaction-scoped shared advisory WORK lease. Every business transaction
rechecks the exact admission/epoch/source tuple, establishes
`SET LOCAL ROLE collect_sms_runtime`, sets the SMS verification and fence GUCs
locally, and takes the existing serial writer transaction lock. Each business
transaction also locks and rechecks the current token-to-application mapping,
receipt kind and required scope before executing gateway SQL; a concurrent token
revocation or rotation is ordered against receipt insertion by that row lock.
Login, role attributes and selected effective privileges are checked inside
each transaction; no caller can supply SQL, a database URL, a role or fence
tuple through HTTP.

An unacknowledged COMMIT is not retried, rolled back on a replacement backend,
or returned as success: the original work is marked unresolved and the
connection is quarantined. An acknowledged rollback after an access denial or a
server-proven SQL data/constraint error is treated as a confirmed no-commit
outcome. An unknown, revoked or disallowed credential yields an empty 404 only
after confirmed rollback and settled work; a malformed lookup, lost rollback
acknowledgement or other ambiguous database result remains a 503 and unresolved.
Ambiguous errors and COMMIT outcomes remain unresolved. A close
acknowledgement is reconciled only through the original admission status. A
timed-out operation remains unknown even if a late database operation later
completes. If the response deadline expires while the original work is still
finishing, a bounded background owner retains the pool until that work finishes.
If its grace expires, the pool is not deliberately terminated or reused; the
isolate's eventual lifetime and cleanup remain unconfirmed.

The expected dedicated login is `collect_sms_edge`, a non-superuser NOINHERIT
login with no role memberships other than `collect_sms_runtime`, no app/private
schema usage, no database or public-schema CREATE, and no ability to bypass RLS.
`collect_sms_runtime` must be NOLOGIN, NOINHERIT and non-privileged; its SMS
schema usage and lack of schema CREATE are checked. These checks are necessary
but do **not** prove the absence of every accessible SECURITY DEFINER function,
PUBLIC privilege, dangerous role edge or project-wide privileged runtime. A
complete independently reviewed effective-grant and code inventory is needed.
No credentials are stored in this directory. The Hyperdrive binding supplies
its connection string to the Worker at runtime; its configuration must point
to a dedicated, appropriately protected login rather than a service-role or
owner credential. `COLLECT_SMS_UNVERIFIED_APPROVAL_CLAIM_SHA256` is only a
shape-checked configuration claim: it is not verified against an approval,
source identity or authority, and cannot enable the source-closed entry point.

Cloudflare documents that Hyperdrive uses transaction pooling and supports
transaction-level advisory locks; session state does not persist between
transactions. It also warns that postgres.js `prepare:false` is unreliable
with its pooler. This adapter explicitly passes `{prepare:true,simple:false}`
to **every** `unsafe()` call, not just the client constructor. Type discovery
remains enabled: the local postgres.js 3.4.7 fixture stalled on a cold
`reserve()` with `fetch_types:false`. The separate Hyperdrive configuration
must have query caching **disabled at the provider**, because the Worker cannot
attest that setting from the binding. A boolean environment claim is not proof.
Actual hosted transaction affinity, role behavior, TLS, query caching, timeout,
connection cleanup and capacity are untested.

Sources: [Cloudflare Postgres.js guidance](https://developers.cloudflare.com/hyperdrive/examples/connect-to-postgres/postgres-drivers-and-libraries/postgres-js/),
[Hyperdrive pooling and transaction locks](https://developers.cloudflare.com/hyperdrive/concepts/how-hyperdrive-works/),
[disabling Hyperdrive query caching](https://developers.cloudflare.com/hyperdrive/concepts/query-caching/).

## Required integration before any activation

1. Qualify and install the exact SMS schema, forced-RLS policies, immutable
   replay/evidence constraints, SMS fence functions and triggers under the
   reviewed production migration plan. The coordinator's latest read-only
   catalog observation found `collect_sms_runtime` absent; this is a snapshot,
   not an assertion of current state.
2. Install and verify a managed deployment identity compatible with the exact
   existing canonical `collect.deployment.v1` profile, `mode=managed`,
   `environment=production` and Supabase origin
   `https://rrlduytparvsjfmegalh.supabase.co`. The handler passes its profile
   SHA-256 to `collect_sms.work_register`, which calls the existing immutable
   deployment assertion. The versioned migration
   `20261117065536_collect_cloud_runtime_binding.sql` defines the binder for
   this exact project and production profile.
3. Provision the dedicated database principal and cache-disabled Hyperdrive
   configuration, then independently verify the actual role graph, grants,
   owner/default privileges, TLS, no-cache setting and transaction-pool
   behavior. Supabase project-wide privileged functions and control-plane
   administrators may still bypass this boundary; the Worker alone does not
   establish isolation from them.
4. Choose and route an actual Worker origin, update the authorized application
   transport and per-device issuer/origin transition, and verify bearer-key
   custody, revocation and reconciliation. The worker's URL is intentionally
   separate from the managed Supabase Auth issuer. Device enrollment, signed
   device requests, retry/evidence and no-duplicate physical send remain
   separate implementation and real-device qualification work.
5. Resolve unauthenticated admission pressure before activation. Syntactically
   valid but unauthenticated bearer tokens currently create a durable work
   admission before the database authenticates them; repeated requests could
   consume shared working-admission capacity. The later stopped-admission chain
   supports archiving settled zero-uncertainty admissions, so its observed
   100,000 bound is not a lifetime cap in that chain, but managed portability,
   archival operation and effective abuse controls remain unproven. A safe
   pre-auth design must preserve the fence's no-unadmitted-work invariant; no
   Cloudflare rate limit or provider isolation is asserted here.
6. Freeze the complete transitive source/dependency and Worker bundle identity,
   conduct independent security review, qualify hosted behavior and only then
   replace the hard-coded closure in a separately reviewed change. The example
   configuration supplies no route, account, binding ID or secrets.

## Local verification and CI dependencies

`deno.lock` pins the application runtime dependencies Hono 4.13.16 and
postgres.js 3.4.7. `package-lock.json` pins those packages and esbuild 0.28.2;
install from the approved registry/cache with `npm ci` to verify the lock.
The optional local Workerd smoke
uses Miniflare `5.20261012.0-beta` from the existing
`deploy/platform-api/package-lock.json`; it is not a runtime dependency.

From this directory, with Deno 2.9.6 and cached locked npm packages:

```sh
deno check --cached-only --frozen-lockfile --lock=deno.lock --node-modules-dir=none src/worker.ts
deno test --cached-only --frozen-lockfile --lock=deno.lock --node-modules-dir=none test/worker.test.ts test/transactions.test.ts test/handler-access.test.ts
./test/run-local-postgres.sh
python3 test/signal-cleanup.test.py
```

The last command creates and destroys its own fresh PostgreSQL 17 cluster,
using an isolated temporary directory and an ephemeral loopback port. Override
`COLLECT_SMS_TEST_PG_BIN` with the directory of CI's PostgreSQL 17 tools and
`COLLECT_SMS_TEST_DENO_BIN` if needed. Its bootstrap owner is a **local synthetic
superuser**, not evidence that managed Supabase's `postgres` role has the same
powers. Its minimal fence functions are test doubles, not production migrations.
The fixture verifies real role settings, local GUC reset, concurrent sessions,
fence tuple use and advisory lock release. It exercises both revocation/insert
lock orderings, rotated-token lookup, repeated deterministic conflicts under a
synthetic eight-working-admission limit, and a real COMMIT whose synthetic
acknowledgement is delayed. It does not simulate Hyperdrive.
The signal test uses additional fresh local clusters and test-owned fake
binaries; it verifies TERM and INT to either the shell or its process group and
retention on an unconfirmed synthetic startup or stop. The fixture tracks its
active child and verifies its own server identity before stopping or deleting
anything. If startup, stop or process identity is unconfirmed it retains the
directory. An uncatchable kill or machine failure cannot guarantee cleanup;
CI timeouts should allow at least 25 seconds after TERM for cleanup before any
forced kill. The HTTP adapter tests use synthetic transactions, not Hyperdrive.

To build the Worker with the pinned npm packages:

```sh
npm ci
npm run build
```

For the optional local emulator smoke, install the pinned dependencies in
`deploy/platform-api` and run `NODE_PATH=../platform-api/node_modules node test/bundle.test.cjs`
from this directory. The build maps Deno `npm:` imports to the pinned packages
and explicitly selects postgres.js's `workerd` implementation. Version checks
and these tests are not a substitute for freezing and independently verifying
the transitive source and bundle. The example uses compatibility date
`2026-10-19`, which the locally available Workerd supports.

The initial Miniflare smoke unexpectedly fetched Cloudflare's generic
`workers.cloudflare.com/cf.json` metadata and wrote an emulator cache. No
project credentials, SMS data or project API were involved; the task-created
cache was removed. The revised smoke sets `cf:false`, disables telemetry and
generic CF metadata fetching, and refuses Worker outbound fetches. It is a
local test only.
