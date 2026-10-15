# Collect Admin accounts on Cloudflare

The account API runs in a Cloudflare Worker using D1 for users, password hashes,
sessions, invitations, reset challenges, email attempt metadata, audit events and
rate limits. Outbound account mail uses the native Cloudflare Email Service
`EMAIL.send()` structured builder with `info@ikanisa.com` as its fixed sender.
The sole main administrator is `info@ikanisa.com`. There is no Supabase account
client, public sign-up, default password, public owner-bootstrap endpoint, role
assignment from login data, or automatic owner elevation.

Accounts, Admin operating services, member services, gateway observation and email dispatch are implemented. The owner confirmed on 2026-10-04 that the
app is not in production: the operating backend will start fresh on Cloudflare,
with separate versioned D1 migrations and no Supabase data import. Existing
product contracts guide the new services. The six core Admin views use explicit
read APIs over the new tables. Reasoned, versioned and idempotent operating actions
are implemented in `operations.mjs`; member services, signed gateway/private
receipt review and leased email dispatch use the same fresh database. Active owner,
admin and staff accounts receive core read/account access; team management is
reserved to the protected owner.

## Fresh migration sequence

The sequence in `migrations/` is independent of `supabase/migrations/`:

- `0001_admin_accounts.sql`: Cloudflare administrators, staff, password sessions,
  invitation/recovery challenges and account audit records.
- `0002_collect_core.sql`: new operating tables for app users/profiles, Rwanda
  groups/memberships, MoMo payees/transactions/allocations, exact RWF journals,
  receipt ingress, a durable notification outbox, request replay and audit.
- `0003_posted_verification_guard.sql`: preserves the transaction verification
  evidence that authorized an already-posted payment journal.
- `0004_operating_actions.sql`: action reasons, versions, replay/audit controls,
  independent approval, settings and import/operating state.
- `0005_member_cloudflare.sql`: email-code sessions, member workflows, media,
  preferences and receipt ingress. Requires an empty payee table before its fresh
  schema rebuild; a nonempty table causes a preflight failure without deleting rows.
- `0006_gateway_cloudflare.sql`: signed gateway admission, immutable observation
  and audited private receipt review.
- `0007_email_only_dispatch.sql`: leased email dispatch and uncertain-outcome
  fencing, including preference/account checks before sending.
- `0008_admin_people.sql`: unified system-person identities and contribution projections.
- `0009_admin_reconciliation.sql`: member-bound proposals and independent reviews.
- `0010_admin_sms_facts.sql`: immutable extracted SMS facts and parser/source identity.
- `0011_admin_transaction_sms_lineage.sql`: transaction references and source-fact lineage.
- `0012_gateway_receiver_ingress.sql`: versioned receiver capture grants and private ingress.

These migrations create no example or imported operating records. Existing
Cloudflare accounts survive the additive second migration. Worker authorization,
operating services and concurrency/revocation controls have local test coverage;
actual hosted accounts, native devices and provider finality remain acceptance
work. Use D1 transactional batches and conditional writes for mutations; a
successful schema application does not prove those services exist.

Run the core schema's real local workerd/D1 tests with:

```sh
node --test test/collect-core-schema.test.mjs
```

Apply the intended database's pending migrations using the configured name:

```sh
npx wrangler d1 migrations apply collect-admin-accounts --remote --config ../admin.cloudflare.wrangler.jsonc
```

## Prerequisites and production binding

Use the repository's `deploy/admin.cloudflare.wrangler.jsonc` candidate integration configuration.
Its dedicated account database is provisioned and its isolated hosted origin is
`https://admin-preview.collect.ikanisa.com`. The existing
`deploy/admin.wrangler.jsonc` is preserved historical deployment configuration.
Publish the fresh Admin with `deploy/admin.cloudflare.wrangler.jsonc` and the
member surface with `deploy/member.cloudflare.wrangler.jsonc`.
It must specify:

- `main`: `admin-api/src/worker.mjs`.
- `compatibility_date`: `2026-10-04` or a verified later date.
- `ADMIN_DB`: the dedicated account D1 database, with `migrations_dir` pointing
  to `admin-api/migrations`. Do not bind an unrelated production database.
- `vars.ADMIN_ORIGIN`: the exact HTTPS admin origin, without a trailing slash,
  path, query or fragment; candidate origin
  `https://admin-preview.collect.ikanisa.com`. Switching to the operating Admin
  domain requires the separate full migration/cutover checks.
- `vars.ENVIRONMENT`: `production`.
- `send_email`: `[{"name":"EMAIL","allowed_sender_addresses":["info@ikanisa.com"]}]`.
- Static assets binding `ASSETS`, with `run_worker_first: ["/api/admin/*"]`.
- A paid Worker CPU budget of at least `limits.cpu_ms: 10000`, for the supported
  password hashing work factor; verify observed production CPU before launch.
- Every-minute Cron trigger for leased email dispatch and expired account cleanup.
- Private `MEMBER_MEDIA` R2 binding; verify device identities before gateway admission.
- Private `RECEIPT_PAYLOADS` R2 binding for `collect-admin-receipt-payloads`;
  verify that both private buckets have no public development URL or custom domain.
- `GATEWAY_ALLOWED_IDENTITIES`: approved `app_id` and `signing_certificate_sha256`
  pairs. The candidate intentionally uses `[]` and rejects enrollment until actual
  application/signing identity is approved. Do not substitute example identities.
- Member Worker `MEMBER_AUTH_PEPPER` secret, provisioned securely outside source; never log it.

Before production activation, onboard `ikanisa.com` into **Cloudflare Email
Service / Email Sending** and verify its sending DNS records and sender domain.
The Cloudflare account/token needs permission for Email Sending. Legacy Email
Routing with only preverified destination addresses does not meet arbitrary team
invitation requirements. Test an authorized new recipient and confirm provider
acceptance and mailbox arrival separately. A local stub or `wrangler whoami` does
not establish these gates.

The Cloudflare Workers API returns `messageId` on acceptance. This API reports
`emailStatus: accepted` only after that response and successful local metadata
updates. Acceptance is not a promise of inbox delivery. Failed or uncertain sends
return 503 to the owner and remain visible as `emailStatus: failed` in the team
list. The account stays invited. Resending generates a new single-use link.

## Install and verify

From this directory:

```sh
npm ci --ignore-scripts
npm run check
npm test
```

Wrangler 4.147.0 currently includes Miniflare 5.20261001.0-alpha as its own
dependency. Tests use that exact bundled runtime through its documented v4 option
converter, real workerd and real SQLite D1. Email is intercepted by an in-memory
test service; no external mail, deployments or databases are touched. The
password implementation is also compared with native Node WebCrypto at the full
600,000 work factor. Tests do not shorten the work factor.

## Initialize the owner

Run these only against the intended Cloudflare database. Remote migrations change
the hosted development database; confirm its configured identity first.
The database must already exist and its actual ID must be in the configuration.

```sh
npx wrangler d1 migrations apply collect-admin-accounts --remote --config ../admin.cloudflare.wrangler.jsonc
npm run bootstrap -- --remote --config ../admin.cloudflare.wrangler.jsonc
```

Bootstrap uses authenticated Cloudflare CLI access to insert an **invited** owner
record. Re-running it preserves an existing account and credentials. It never
prints a password or setup token. It cannot activate an account.

After email sending is configured, open the admin sign-in screen, choose password
recovery and enter `info@ikanisa.com`. The owner receives a 24-hour setup link at
that inbox. Set a password and then sign in. Only after inbox verification can
the owner invite admins or staff. Normal password reset links last 30 minutes.

## Local preview

`wrangler.local.jsonc` targets the local database, `http://localhost:8795` and
`build/admin-cloudflare`. Build the admin Flutter bundle before starting it.

```sh
npx wrangler d1 migrations apply ADMIN_DB --local --config wrangler.local.jsonc
npm run bootstrap -- --local --config wrangler.local.jsonc
npm run dev
```

Local preview intentionally disables all email sending and never invokes
Wrangler's email simulator, because that simulator logs complete secret-bearing
links. No local owner password is seeded. The login/setup screens remain
reviewable, and the test suite exercises authenticated states without creating a
real-world identity or sending mail. Local cookie exceptions apply only when
`ENVIRONMENT=local` **and** the request hostname is a loopback hostname. Do not
deploy the local configuration or use it for a public preview.

## API contract

All routes are under `/api/admin`. JSON POST requests must carry the configured
origin. Browser requests are same-origin, use credentialed HttpOnly cookies, and
receive no CORS allowlist. Tokens are never returned by API responses.

| Method and route | Request | Result |
|---|---|---|
| `GET /auth/session` | Cookie if present | `{user:null,expiresAt:null}` or `{user:{id,email,role,sessionId,expiresAt,permissions},expiresAt}` |
| `POST /auth/login` | `{email,password}` | Session result and fresh secure cookie |
| `POST /auth/logout` | `{}` | `{ok:true}`; deletes current session |
| `POST /auth/forgot-password` | `{email}` | Uniform 202 acknowledging request; no delivery or account-existence claim |
| `POST /auth/complete-password` | `{token,password,invite:boolean}` | `{ok:true}`; requires sign-in afterward |
| `POST /auth/change-password` | `{currentPassword,newPassword}` | `{ok:true}`; all sessions invalidated |
| `GET /team` | Owner cookie | `{members,currentEmail,canManage:true}` |
| `POST /team/invite` | `{email,role:"admin"\|"staff"}` | 201 `{ok:true,emailStatus:"accepted"}` |
| `POST /team/:id/resend` | `{}` | `{ok:true,emailStatus:"accepted"}`; pending invites only |
| `POST /team/:id/revoke` | `{}` | `{ok:true}`; owner cannot be revoked |
| `GET /core/overview` | Active account cookie; optional `country=RW` | Authoritative record counts, measurement time and count metrics; no estimated financial balances |
| `GET /core/groups`, `/core/users`, `/core/members`, `/core/payees`, `/core/transactions`, `/core/ledgers` | Active account cookie and corresponding read permission | `{rows,total}` from the fresh tables |

Core list filters are `search` (up to 200 printable characters), `status` (native
statuses for that view), `limit` (1–100), `offset` (0–2147483647), `sort`
(`created_at_desc` or `created_at_asc`) and `country` (`RW` only). Unknown or
duplicate filters are rejected. Search is literal rather than a SQL wildcard;
Users/Members search only public Collect ID and display name, never hidden
contact values. Contact/payment routes are masked in list output. Members are
distinct app users with an active membership, separate from the admins/staff
account roster.

Core GET lists remain read-only; operating actions are exposed through the separate `/operations` routes. Count and page share a D1 transaction, including a fresh
session/version/expiry check. Money is exact integer RWF with bounded aggregates;
transaction confirmation is labelled as recorded evidence. Fresh transaction
UUIDs do not masquerade as legacy SMS receipt identifiers. Unimplemented historical transports remain unavailable; fresh operating actions
and details use explicit Cloudflare contracts. Core read tests use synthetic local
fixtures only, and do not seed the hosted workspace or deliver mail.

Member fields are `id,email,role,status,createdAt,invitedAt,acceptedAt,emailStatus`.
Roles are `owner/admin/staff`; status is `active/invited/revoked`. Dates are ISO
8601 or null. Failure shape is `{error:{code,message}}`. Statuses distinguish 400
validation, 401 sign-in/session failure, 403 access denial, 409 stale/duplicate
state, 413 oversized requests, 429 throttling and 503 unavailable services.

Invitation/reset URLs are
`https://admin-preview.collect.ikanisa.com/#/admin/setup?token=…&invite=true|false`
for the current hosted candidate (the origin is taken from `ADMIN_ORIGIN`).
The token remains in the fragment, outside server URL query logs. The frontend
must remove the fragment token from browser history after capturing it and must
not persist it in local storage, analytics or logs. The user submits it only in
the password completion JSON body over HTTPS.

## Security invariants

- PBKDF2-HMAC-SHA256 with 600,000 iterations, random 256-bit salt, 256-bit output,
  and pinned `@noble/hashes` portable implementation. Workers' native PBKDF2 cap
  currently rejects OWASP's work factor; there is no weak-work fallback.
- Passwords accept 12–128 Unicode characters, bounded to 512 UTF-8 bytes. Login
  checks valid and unknown accounts using equivalent password work.
- Session secrets and setup tokens have 256 random bits; only SHA-256 hashes are
  stored in D1. The UI sees a separate public session UUID, never the bearer.
- Production cookie: `__Host-collect_admin`, Secure, HttpOnly, SameSite=Strict,
  Path=/, eight-hour expiry. Revocation, reset and password change revoke sessions.
- D1 atomic batches and conditional updates enforce one winner for concurrent
  token acceptance. User authorization and challenge generations fence old
  sessions/links, revoked users and replaced invitations.
- Fixed sender and database constraints protect owner identity. Only the owner
  can view/manage team access. A pending account has no session or permissions.
- Durable per-IP and per-email counters constrain login, reset and invite
  abuse. Counters hash identifiers rather than storing raw IP addresses.
- Reset acknowledgments are deliberately enumeration resistant. Provider
  delivery runs in `waitUntil`; its outcome is stored for the owner without
  revealing whether an address exists to the unauthenticated requester.
- No request bodies, passwords, cookies, setup tokens or provider exception
  messages are logged by this Worker. API responses use no-store/no-referrer.

## Verified sources

- [Cloudflare Workers Email Service API](https://developers.cloudflare.com/email-service/api/send-emails/workers-api/)
- [Cloudflare Email Sending setup](https://developers.cloudflare.com/email-service/get-started/send-emails/)
- [Cloudflare send binding restrictions](https://developers.cloudflare.com/email-service/configuration/send-bindings/)
- [Cloudflare workerd PBKDF2 cap change, still open on 2026-10-04](https://github.com/cloudflare/workerd/pull/7550)
- [OWASP password storage work factors](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [noble-hashes source and security documentation](https://github.com/paulmillr/noble-hashes)

The dedicated hosted D1 database and account migration were provisioned on
2026-10-04. Readback confirmed the sole owner is invited with no password set.
The Cloudflare dashboard showed `ikanisa.com` sending Enabled and DNS Configured.
The account Worker was deployed at the candidate origin and accepted one owner
setup request; D1 readback recorded native email-provider acceptance. Unrelated
staff-recipient delivery, authenticated hosted sessions, paid-worker CPU behavior
and full operational migration remain independent verification gates. See the
architecture account implementation checkpoint.

## Historical acceptance evidence — 4 October 2026

See [current implementation status](../../docs/architecture/cloudflare-migration-2026-10-04/ACCOUNT_IMPLEMENTATION_STATUS.md),
[operating API](../../docs/architecture/cloudflare-migration-2026-10-04/OPERATIONS_API.md),
and [gateway API](../../docs/architecture/cloudflare-migration-2026-10-04/GATEWAY_API.md).
The latest complete backend suite passed 96/96, including session revocation,
single-winner OTP/refresh and exact-target logout regressions. The dedicated
`cloudflare-backend` CI job runs the locked dependencies, syntax checks and this
local workerd/D1 suite without hosted credentials or external email. Both preview Workers and all seven
migrations are deployed. The owner reported inbox arrival, but must choose a
password to activate the invited account. Native device and authenticated hosted
role journeys remain unverified. No legacy data import or old project deletion
is required.

## Current Admin acceptance — 14 October 2026

The current complete Admin API suite passed **176/176** against ephemeral D1/R2,
with external email disabled and explicitly synthetic receiver material. The
isolated candidate includes migrations through 0012; a fresh remote listing
confirmed 0008–0012 remain pending on `collect-admin-accounts`. The earlier
deployment/inbox observations above do not establish current hosted acceptance.

See [the current Admin UAT review](../../docs/implementation/admin-production-readiness-uat-2026-10-14.md).
Before hosted mutation, refresh exact target/bucket/account identity and preserve
recovery evidence. Use the intended Owner activation flow rather than creating a
duplicate Owner. The preview origin is not a production binding. Current-source
CI, delivered provider lifecycle, approved receiver identity, authenticated hosted
role/finance UAT, measured restore/performance/device proof and production
readback remain required. Do not deploy the separate member surface as an Admin
release prerequisite.
