# Collect MoMo SMS Production QA Report

Audit date: 2026-08-20

Scope: the complete standalone SMS-first MoMo journey across Android permission and
live receipt, encrypted local queuing, Supabase ingestion, OpenAI parsing,
payment-intent matching, transaction and balanced-ledger posting, payer/group
balances, notifications, mobile UI, database controls, deployment, physical
Android verification, and Google Play submission.

## Decision

Public launch decision: **NO-GO**.

The code-owned security remediation is implemented and the database, Edge
source and Admin PWA are production-reconciled, but the resulting journey is
not provider-complete, artifact-frozen, physically accepted or release-approved.
Earlier version `1.2.2+20` APK/AAB hashes, physical install
evidence and Play submission records predate the current authorization,
atomic-ingestion and release-control changes. They remain
historical evidence only and cannot approve the current source tree.

Real payment/SMS testing, credential/PIN/OTP handling, Play upload and rollout
remain explicitly authorization-gated. The 79-migration chain, 10 reviewed Edge
Functions, public site and Admin PWA are now reconciled to production. The
source can become a release candidate only after provider secrets/readiness,
authenticated real-receipt smoke and exact balance reconciliation pass, the
final artifacts pass physical UAT,
and Google separately approves restricted SMS access and the release.

## Product Boundary

- Collect is a standalone group-contribution system. It does not add a banking,
  escrow, or manual-confirmation subsystem. A complete, high-confidence OpenAI
  parse posts only through the locked exact-match database allocator.
- Android requests only `RECEIVE_SMS` for this feature. It does not request
  `READ_SMS`, `SEND_SMS`, Call Log, contacts, storage, or inbox-history access.
- SMS parsing is performed by the OpenAI Responses API in the Supabase Edge
  Function using strict structured output. There is no deterministic
  transaction parser fallback and the model cannot select the receiver, group,
  payer, or payment intent.
- One exact match atomically creates the payment, allocation, group credit,
  payer credit, intent transition, audit event, and notification. Incomplete,
  duplicate, low-confidence, unmatched, or ambiguous events post nothing.

## Production Deployment Boundary

- The current reviewed local schema contains 79 migrations and ends at
  `20260820160000_restore_momo_sms_standalone`.
- The final tail adds request-bound attested creation, privacy and receiver
  authorization closure, parser leasing, atomic ingestion, and non-DML client
  privilege revocation. Linked production UAT now covers this tail.
- Linked production reconciliation proves 79/79 migrations, 336/336 schema
  objects, 60/60 RLS tables, 153 policies, clean error-level advisors and both
  rollback-only SMS/ledger and Admin security UATs.
- The deployed inventory contains exactly 10 functions; all 19 downloaded
  source files match the repository. Strict readiness still fails on absent
  `FCM_SERVICE_ACCOUNT_JSON`, `STRIPE_SECRET_KEY`, and
  `STRIPE_WEBHOOK_SECRET`; no secret values were recorded.

## Current End-to-End Evidence

Current database evidence is synthetic and rollback-only; deployment evidence
is current production readback:

- Group creation UAT proves exact capability payload binding, single use,
  owner membership, private/public-requested states, share rotation, removed
  member denial, delegated-admin receiver denial and balance contracts.
- Linked rollback UAT and the privacy lifecycle UAT prove payer identity,
  matching, ambiguity, replay, exactly one collection credit and one member
  credit after automatic allocation, scoped reads and immutable ledger behavior.
- Admin security UAT proves permission-scoped raw-SMS metadata/reveal/reparse,
  admin role controls and audited actions.
- A true concurrent-join UAT proves one active membership, one join audit and
  one owner notification from two simultaneous requests.
- Supabase contract tests cover the forward migrations, Edge integration,
  automatic balanced ledger posting, idempotency, and browser/service grant
  boundaries.

Any earlier production OpenAI/parser exercise predates the current atomic
ingestion and parser-leasing tail and does not prove the present full chain.

## Android Evidence

- Historical version 20 installation on the Pixel 4a proved package launch and
  a denied SMS-permission baseline only. It did not prove permission grant,
  revocation recovery, authenticated creation, real share/join, carrier SMS or
  reconciled payer/group balances.
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
| Flutter non-golden suite | Pass; 492 tests |
| Security hygiene focused suite | Pass, including strict dotenv controls |
| Supabase contract suite | Pass, 68 tests |
| Parser/ingestion Edge type check | Pass; `deno check` clean |
| Migration chain validation | Pass, 79 migrations |
| Group creation journey rollback UAT | Pass |
| Linked contribution rollback UAT | Pass |
| Admin security rollback UAT | Pass |
| Privacy lifecycle rollback UAT | Pass |
| Concurrent join UAT | Pass; one membership, audit and notification |
| Governed golden suite | Pass; 14 tests and 13 pinned baselines |
| Deno Edge suite | Pass; 11 tests |
| Android production-debug JVM tests | Pass |
| Fresh production APK/AAB and artifact manifest | Pass locally; exact hashes recorded above |
| Mobile release gate | Blocked only on current `android_release_signing_review` approval |
| Local public website quality gate | Pass; 56 checks |
| Rendered public group-link browser QA | Pass; 48 route/viewport results, 12 link scenarios, 76 screenshots, no failures |
| Live public website gate | Pass; 35/35 including `/c/*`, all sitemap routes, assets, security and accessibility signals |
| Authoritative production schema inventory | Pass via linked management path; 79 migrations, 336 objects, 60/60 RLS tables, 153 policies |
| Admin PWA full 28-route by 3-viewport matrix | Pass; 84/84 screenshots, zero failures |
| Admin PWA production deployment | Pass; version `ff6801b3-447d-45d0-8d50-f5369dcbce2d`, custom-domain gate and exact bundle hashes |
| Provider readiness and physical end-to-end UAT | Blocked/pending; FCM and Stripe secrets absent, real-device receipt chain not claimed |

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

1. Provision the least-privilege FCM credential and either provision governed
   Stripe live credentials or explicitly remove Stripe/diaspora from release
   scope; rerun strict readiness and provider UAT.
2. One authorized low-value end-to-end receipt, intent, payment, ledger, payer,
   group, notification, and balance reconciliation.
3. Fresh exact APK/AAB build, signing approval, physical two-user permission,
   share/QR/join/payment/SMS/notification/balance UAT and human TalkBack review.
4. Google restricted-SMS approval, artifact processing, tester/public
   availability and staged 1-hour/24-hour/72-hour monitoring.

No production mutation, live payment, PIN/OTP entry, carrier
SMS, Play approval or public availability is claimed by this report.
