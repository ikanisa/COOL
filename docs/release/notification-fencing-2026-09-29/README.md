# Notification ownership and recovery — 29 September 2026

**Local implementation and bounded tests pass; O05/S10 and release acceptance
remain open.** All SQL ran in the verified task-owned local Supabase fixture
`collect_fin_concurrency_qa_20260929`, port 55722. Test data was synthetic and
no push provider was called.

## Corrections

[Migration 137](../../../supabase/migrations/20260929140000_notification_delivery_fencing.sql)
and the matching dispatcher introduce a required versioned claim contract,
owner-bound claim token/expiry, exact attempt/token completion, and a pre-send
lease check. Both claim arguments are required. Old positional and named
one-argument clients fail before receiving sendable claims; the old unfenced
completion overload is removed.

Claim, completion and device registration use device-before-delivery-before-event
locking. Token reassignment is rejected while a live claim exists. Ordinary API
roles cannot directly mutate token rows. Sign-out disables pending delivery;
an in-flight claim's expiry still protects immediate reassignment. Exhausted
claims become terminal instead of being stranded in an unclaimable queue.
Operator retry preserves cumulative attempt history and checks current ownership.

[Migration 138](../../../supabase/migrations/20260929150000_notification_retry_eligibility.sql)
makes the Admin retry count use the same owner, enabled-provider/token and claim
expiry rules as the retry action, so operators are not offered an ineligible retry.

The worker claims one delivery immediately before sending, bounds RPC/provider
work and invocation duration, and does not downgrade an accepted send when
completion persistence fails. FCM response-body failures after HTTP acceptance
do not automatically become transport retries. See [code validation](CODE_VALIDATION.md)
for exact pinned-runtime tests, source hashes and provider-response boundaries.

## Database and concurrency evidence

| Artifact | Result |
| --- | --- |
| [Corrected 137 upgrade](upgrade-137.json) | Applied after the clean 136 financial fixture. |
| [138 upgrade](upgrade-138.json) | Applied to the synthetic 137 fixture. |
| [Full clean replay](../financial-content-binding-2026-09-29/clean-138-replay.json) | **138/138** application migrations passed on PostgreSQL 17.6. |
| [Rollback UAT](../../../scripts/tests/notification_delivery_fencing_uat.sql), [upgrade output](uat-138.stdout), [clean output](clean-138-uat.stdout) | **52 checks passed** on both the upgrade and clean 138 schemas. Cases include role denials, old/version-mismatched calls, wrong/stale fences, backoff, fifth-attempt exhaustion, ownership changes, sign-out, invalid devices, preserved attempt history and actual authenticated Admin read/retry/audit behavior. All fixture writes rolled back. |
| [Two-session harness](../../../scripts/tests/notification_delivery_concurrency_uat.rb), [137 result](concurrency-result.json), [138 result](concurrency-138-result.json) | Worker A held one uncommitted claim; overlapping worker B claimed zero. Token reassignment demonstrably waited on A, then failed after A committed. Original ownership and attempt 1 remained intact. Synthetic users/rows and worker sessions were removed; the before/after digests across 18 covered tables matched. |
| [Pinned code evidence](code-validation.json) | Deno **2.5.6** type checking and **22 focused tests** passed; 14 source/configuration fingerprints remained unchanged during the run. |

The first unpublished draft of 137 applied locally but failed expired-lease UAT
because its `ON CONFLICT` columns collided with PL/pgSQL output names. The
[draft error](draft-uat.stderr) and [draft source identity](draft-upgrade-137.json)
are retained. The conflict target now names the unique constraint. Review also
tightened the claim protocol before final replay. The task-owned fixture was
backed up and reset; no hosted migration was changed, and draft results are not
passing evidence. Corrected migration 137 is SHA-256
`abbd69486171002e0ce6bcdc7046e0170e6412ec03b022c1127ef31cd6572275`.

## Remaining acceptance

- Respect provider-specific `Retry-After`, introduce/test jitter, and rehearse
  real outage, quota and representative-throughput behavior. Current SQL uses
  fixed exponential backoff.
- Verify coordinated migration/worker deployment, scheduler operation, dead-letter
  support and real APNS/FCM delivery on supported devices, including account
  switch and delayed/in-flight provider outcomes.
- A provider-accepted message cannot be recalled by the database. These controls
  do not establish exactly-once delivery or complete installed-device privacy.
- Privileged database/service administrators retain trusted mutation powers;
  the ordinary API boundary is enforced and tested, not a tamper-proof database.
- Complete approved budgets, monitoring, support drills and frozen-candidate
  acceptance before production. O05, S10, P07 and related release tasks remain open.

The [verification manifest](verification-manifest.json) records source/result
hashes for this snapshot. Hosted permissions, configuration and provider state
were not refreshed by these local tests.
