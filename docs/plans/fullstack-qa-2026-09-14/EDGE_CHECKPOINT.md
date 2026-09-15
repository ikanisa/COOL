# Collect Edge HTTP and OTP checkpoint

15 September 2026, Africa/Kigali. Execution timestamps below are UTC on
14 September. **The OTP quota defect is fixed locally. The full P0–P8 goal
remains active and acceptance is incomplete.**

Current evidence passes 66 Edge HTTP checks, 94 PostgREST checks, all 22
selected SQL suites, two OTP concurrency scenarios, 54 Deno tests with 38
TypeScript file checks, 45 focused Flutter contract tests, and the QA runner
regression: 75 Ruby tests / 365 assertions plus nine Python tests. These are
overlapping layers, not an aggregate acceptance percentage.

## Reproduced defect and repair

FQA-035 concerns `auth-send-whatsapp-otp`. Its old handler ignored errors
from both the quota count and insert, then continued toward delivery. The
count and insert were also separate operations. The recording HTTP dependency
reproduced three failures: a failed count returned HTTP 200, a failed insert
returned HTTP 200, and eight simultaneous requests with four prior attempts
all succeeded, leaving twelve attempts in the model. Delivery was disabled.

The actual replayed database also denies `service_role` direct SELECT and
INSERT on `public.otp_rate_limits`. The old handler ignored those errors.
This privilege observation is bound to the local schema; hosted permissions
have not been checked in this continuation.

Migration `20260914213600_atomic_otp_rate_limit.sql` adds the service-only
`reserve_otp_request` RPC. A private phone-hash row serializes quota decisions.
The function validates hashes, counts the rolling ten-minute window after
acquiring that row, and records at most five accepted reservations. Existing
attempts still count. Anonymous users, members and browser operators cannot
reserve quota; direct table access remains denied. The private lock table has
RLS enabled and no client grants.

The Edge handler now requires a boolean reservation result. A missing RPC,
storage failure or malformed result returns the existing generic HTTP 502
OTP-unavailable response; exhausted quota returns 429. Only a successful
reservation reaches the existing delivery path. Failed delivery continues
to consume the reservation, preserving the original request-count policy.

Updating the lock row also rejects a stale repeatable-read snapshot. The
executed database race confirmed one successful transaction and one `40001`
serialization failure; a fresh retry was denied after quota filled. This is
consistent with PostgreSQL's documented
[row-lock behavior](https://www.postgresql.org/docs/17/explicit-locking.html).
No separate serializable-isolation acceptance is claimed.

The migration must be applied before deploying the changed Edge function.
No fallback bypasses a missing migration. Both changes remain local; no hosted
migration or function deployment was performed.

## Evidence and boundaries

Raw evidence is under
`.cache/fullstack-qa/20260914T151002Z/edge-http-continuation/`.

| Evidence | Verified outcome |
| --- | --- |
| `before-guard-corrected/report.json` | 64 checks with the three reproduced OTP failures |
| `current-source-final/report.json` | 66 checks pass against real Deno HTTP listeners loading all 11 actual Edge entrypoints; all 12 owned listeners closed |
| `sql-all-126/report.json` | All 22 selected SQL suites pass on schema 126; source/log hashes, rollback and cleanup verified |
| `sql-all-126/otp_rate_limit_uat.log` | 29 quota, ACL, validation, expiry, storage-failure and side-effect checks pass |
| `otp-concurrent-service-boundary/report.json` | Eight read-committed workers yield one acceptance and seven denials; two repeatable-read workers yield one acceptance and one serialization rejection; five attempts persist per phone |
| `postgrest-126/report.json` | 94 checks over 84 HTTP requests and persisted/source assertions; current OTP RPC and earlier Admin/session/roster cases pass |
| `upgrade-126.json` | Exactly the new migration was applied to the task-owned schema 125; migration metadata and DDL commit together |
| `deno-current-source.json` | Pinned Deno 2.5.6 passes 54 tests and 38 file checks across 11 entrypoints |
| `qa-tooling-current/report.json` | 75 Ruby tests / 365 assertions and nine Python tests pass on unchanged recorded inputs |
| `flutter-contracts-current/report.json` | 45 Flutter contract/security tests pass, zero failures or skips; source inputs unchanged |
| `advisors-126.json` | Pinned v2.101.0 query: zero ERROR/WARN, 232 INFO; all 94 direct-access checks for 47 policy-free RLS tables pass |
| `source-checkpoint.json` | All 126 migration hashes and current suite inputs verified; prior Flutter source comparison and preserved settings hash |
| `final-shutdown.json` | Only the original two databases remain; no original OTP attempts or lock rows; completed PostgreSQL shutdown and container exit 0; volume retained |

The Edge harness uses real requests and responses but a recording synthetic
Auth/PostgREST dependency. Its runtime permits only loopback networking,
explicitly denies provider endpoints, uses cached dependencies and receives
no inherited account credentials. Cases cover methods/CORS, missing and
invalid authorization, operator permissions, actor substitution, HMAC and
standard-webhook signatures, OTP storage failure and quota concurrency.
SMS attestation and provider transports retain their separate evidence needs.

The SQL concurrency tests use actual PostgreSQL transactions and verify that
all workers reached the shared barrier before release. Each test uses a
disposable database copy. The separate PostgREST test uses synthetic JWTs and
session records against real SQL. It verifies five persisted OTP reservations,
service-only RPC access, invalid-hash rejection and denied direct table access,
alongside the earlier Admin lifecycle and roster cases. It leaves no payment,
ledger, raw-SMS or notification-outbox rows. These layers do not yet prove
one integrated GoTrue → Edge → SQL → WhatsApp journey.

## Tooling, retained failures and current source

`make edge-http-test` runs the portable launcher with the exact `.dvmrc`
version. CI runs it after existing Deno checks and retains its evidence even
when a run fails. Hosted CI has not executed these changes. The launcher
records missing/wrong runtimes, incomplete reports, nonzero exits, timeouts,
truncated progress and changed/missing source as failures. Nine regressions
exercise those outcomes and credential/network isolation.

All failed attempts remain preserved. The initial permission-state assumption
was corrected before the three-defect baseline. Two later runs timed out while
closing test listeners; 64 passing partial checks did not make those runs pass.
The owned-listener cleanup was fixed and a completed 66-check report followed.
The first SQL concurrency fixture tried to read the counter as service role;
that denied read was moved to fixture setup before setting the service role.
The reservation itself still executes as service role.

The first focused Flutter run passed 44 checks and failed source hygiene.
The fallback secret scanner identified a static synthetic password-bearing
URL in a Ruby test fixture. That fixture now generates a random credential
at runtime; scanning rules and target assertions were preserved. An initial
URI-builder correction rejected underscores in the Docker hostname and
produced six Ruby test errors. Its failed log and the reporting-wrapper
failure are retained; the corrected fixture and final regressions pass.
No real credential exposure was found in this reproduction.

The prior full Flutter run still records 867 passes and 74.65% coverage.
613 of its 615 inputs are unchanged; only `Makefile` and
`.github/workflows/ci.yml` differ. No Dart, Flutter test, asset or platform input
changed during this continuation. The new 45-test run is focused evidence,
not a new execution of all 867 tests. The user's settings hash is unchanged.

The schema history is **124 clean migrations plus separate bounded upgrades
to 125 and 126**. The original chain file remains unchanged; the new chain is
`database-current-replay-chain-126.json` in the parent evidence directory.
An uninterrupted current-schema replay and a restore rehearsal remain open.

The advisor INFO observations comprise 93 unindexed foreign keys, 92 unused
indexes and 47 policy-free RLS tables. Direct client access checks pass;
representative workload measurements are still needed. This is the existing
pinned query, not a claim of latest or hosted-advisor parity. The quota index
was added for the reproduced OTP defect, not to suppress advisor findings.

Shared free space was 2.164 GiB at the source checkpoint and continues to
fluctuate. Native capacity remains unresolved. Broader route/state coverage,
Admin actions, installed PWA behavior, real Auth/provider/device journeys,
performance/recovery, public legal destinations, fresh native media and
independent/owner visual acceptance remain in the full plan.
MOBILE-DESIGN-100 remains mandatory; neither native platform is approved.
