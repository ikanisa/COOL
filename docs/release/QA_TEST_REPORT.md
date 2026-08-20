# Collect MoMo SMS Production QA Report

Audit date: 2026-08-20

Scope: the complete standalone SMS-first MoMo journey across Android permission and
live receipt, encrypted local queuing, Supabase ingestion, OpenAI parsing,
payment-intent matching, transaction and balanced-ledger posting, payer/group
balances, notifications, mobile UI, database controls, deployment, physical
Android verification, and Google Play submission.

## Decision

Public launch decision: **NO-GO**.

The code-owned security remediation is implemented and locally validated, but
the resulting journey is not deployed, provider-integrated, artifact-frozen or
release-approved. Earlier version `1.2.2+20` APK/AAB hashes, physical install
evidence and Play submission records predate the current authorization,
provider-finality, atomic-ingestion and release-control changes. They remain
historical evidence only and cannot approve the current source tree.

Production database mutation, public-site deployment, real payment/SMS testing,
credential/PIN/OTP handling, Play upload and rollout remain explicitly
authorization-gated. The source can become a release candidate only after the
current 78-migration chain and reviewed Edge Functions are deployed to the
intended project, authenticated production smoke passes, a genuine provider
finality integration reconciles, the exact final artifacts pass physical UAT,
and Google separately approves restricted SMS access and the release.

## Product Boundary

- Collect is a standalone group-contribution system. It does not represent SMS
  as bank/provider settlement truth and does not invent banking, escrow or
  manual confirmation. A service-side provider/bank finality source is required
  before any collection or payer balance changes.
- Android requests only `RECEIVE_SMS` for this feature. It does not request
  `READ_SMS`, `SEND_SMS`, Call Log, contacts, storage, or inbox-history access.
- SMS parsing is performed by the OpenAI Responses API in the Supabase Edge
  Function using strict structured output. There is no deterministic
  transaction parser fallback and the model cannot select the receiver, group,
  payer, or payment intent.
- Native SMS can create only an `awaiting_provider_confirmation` candidate.
  The service-only confirmation contract owns the exactly-once two-entry ledger
  posting; rejection and replay remain explicit and audited.

## Production Deployment Boundary

- The current reviewed local schema contains 78 migrations and ends at
  `20260815085000_atomic_provider_finality_gateway`.
- The final tail adds request-bound attested creation, privacy and receiver
  authorization closure, provider finality, parser leasing, atomic ingestion,
  non-DML client privilege revocation and the signed replay-safe provider
  gateway. This tail has local reset/lint/UAT evidence only.
- The current read-only production recheck found 321/341 expected schema
  objects, with 20 missing objects spanning attested creation, atomic SMS
  ingestion, parser claiming, provider finality, the provider gateway and
  atomic profile/receiver updates. Strict readiness also stops on an
  unreviewed warning-level advisor inventory. No action in this QA refresh
  deploys or mutates production.
- Edge Function versions, secrets, project identity, auth/network/SSL/PITR
  state and migration history must be re-read authoritatively under strict
  readiness immediately before and after an explicitly authorized deployment.
- The 2026-08-15 read-only Edge inventory contains the ten previously deployed
  functions but not the new `provider-finality` function. Secret-name
  inventory also lacks `PAYMENT_PROVIDER_FINALITY_SECRET_CURRENT` and the
  previously open `FCM_SERVICE_ACCOUNT_JSON`; no secret values were read or
  recorded.

## Current End-to-End Evidence

Current evidence is synthetic, local and rollback-only:

- Group creation UAT proves exact capability payload binding, single use,
  owner membership, private/public-requested states, share rotation, removed
  member denial, delegated-admin receiver denial and balance contracts.
- Linked rollback UAT and the privacy lifecycle UAT prove payer identity,
  matching, ambiguity, replay, provider-finality state, no ledger before
  confirmation, exactly one collection credit and one member credit after
  confirmation, scoped reads and immutable ledger behavior.
- Admin security UAT proves permission-scoped raw-SMS metadata/reveal/reparse,
  admin role controls and audited actions.
- A true concurrent-join UAT proves one active membership, one join audit and
  one owner notification from two simultaneous requests.
- Supabase contract tests cover the forward migrations, Edge integration and
  browser/service grant boundaries. Dedicated Deno tests additionally prove
  signed-byte binding, key rotation, stale/tampered rejection, request-ID
  binding, strict versioned payload parsing, HTTP status mapping and exact RPC
  construction for the provider gateway.

Any earlier production OpenAI/parser exercise predates the provider-finality
boundary and does not prove the current capture-to-reconciliation chain.

## Android Evidence

- Historical version 20 installation on the Pixel 4a proved package launch and
  a denied SMS-permission baseline only. It did not prove permission grant,
  revocation recovery, authenticated creation, real share/join, carrier SMS or
  provider-confirmed balances.
- Current native source adds synchronized durable-queue access, authenticated
  owner binding and a server-verified Play Integrity capability request.
- Fresh local `1.2.2+20` production artifacts were built after the final source
  change. The APK SHA-256 is
  `85515923a7ca76dd03cb3443abb07236b609ab321b4e4062b9dd9db5c27e8bdb` and
  the AAB SHA-256 is
  `0922a26c55ce57629a848074b715476a2cf0ce3b13e99b4286eb3669fb30ef74`.
  Embedded production-runtime checks, upload-key signing preflight and APK/AAB
  signature checks pass. These are local candidate artifacts, not approved or
  physically accepted release artifacts.

## Verification Results

| Verification | Result |
| --- | --- |
| `flutter analyze` | Pass; no issues |
| Full `flutter test -r compact` | Pass; 510 tests |
| Security hygiene focused suite | Pass, including strict dotenv controls |
| Supabase contract suite | Pass, 68 tests |
| Provider gateway Deno tests/type check | Pass; 11 tests and `deno check` clean |
| Clean local migration replay and SQL lint | Pass, 78 migrations and zero lint issues |
| Group creation journey rollback UAT | Pass |
| Linked contribution rollback UAT | Pass |
| Admin security rollback UAT | Pass |
| Privacy/provider lifecycle rollback UAT | Pass |
| Concurrent join UAT | Pass; one membership, audit and notification |
| Governed golden suite | Pass; 14 tests and 13 pinned baselines |
| Android production-debug JVM tests | Pass |
| Fresh production APK/AAB and artifact manifest | Pass locally; exact hashes recorded above |
| Mobile release gate | Blocked only on current `android_release_signing_review` approval |
| Local public website quality gate | Pass; 56 checks |
| Rendered public group-link browser QA | Pass; 48 route/viewport results, 12 link scenarios, 76 screenshots, no failures |
| Live public website gate | Fail closed; 33/35, `/c/*` 404 and stale deployed brand hashes |
| Read-only production schema inventory | Fail closed; 321/341 objects, 20 missing |
| Admin PWA full 28-route by 3-viewport matrix | Pass; 84/84 screenshots, zero failures |
| Real provider, production deployment and physical end-to-end UAT | Pending; not claimed |

The Android build emits a non-blocking dependency warning that
`mobile_scanner` still applies the legacy Kotlin Gradle plugin. The current
release compiles and tests successfully; this dependency must be upgraded when
a compatible built-in-Kotlin release is available.

## Google Play State

- Historical version 20 processing/review records do not approve the current
  source or a future AAB.
- Restricted `RECEIVE_SMS` approval and release approval must be evidenced as
  separate Google decisions for the exact final AAB.
- The upload wrapper is now pinned to the canonical AAB, package and production
  track, revalidates its SHA-256 around the readiness gate and permits only a
  staged `inProgress` rollout. Upload still requires explicit action-time
  authority and an approved SMS declaration.

## Remaining External Gates

1. Authorized Supabase deployment and authenticated production negative/positive
   smoke across capabilities, receivers, privacy, joins, provider replay and
   grants.
2. Authorized Cloudflare deployment and live `/c/*` deep-link/fallback proof.
3. Approved provider/bank finality integration and one authorized low-value
   reconciliation with no ledger effect from SMS alone.
4. Fresh exact APK/AAB build, signing approval, physical two-user permission,
   share/QR/join/payment/SMS/notification/balance UAT and human TalkBack review.
5. Google restricted-SMS approval, artifact processing, tester/public
   availability and staged 1-hour/24-hour/72-hour monitoring.

No production mutation, provider settlement, payment, PIN/OTP entry, carrier
SMS, Play approval or public availability is claimed by this report.
