# Provider finality content binding — 29 September 2026

**Local corrections verified; F08/F10 and production acceptance remain open.**
All database work used the task-owned `collect_fin_concurrency_qa_20260929`
Supabase fixture on port 55722, verified by Docker labels and configuration.
Only synthetic users, receipts and RWF 2,500 payments were involved. Scheduled
jobs were disabled. No hosted project, real provider or customer data was used.

## Defects reproduced and corrected

The rollback-only [135 baseline](baseline-135.sql) produced all three
[unsafe success acknowledgements](baseline-135-result.txt): a new request with
the same confirmation ID but a changed amount was accepted; reusing a request
ID and supplied digest with contradictory fields returned a replay; a rejection
with a wrong network, transaction, receiver and amount canceled the candidate.
The baseline transaction rolled back.

[Migration 136](../../../supabase/migrations/20260929130000_provider_finality_content_binding.sql)
now:

- Compares every stored confirmation field before accepting the same confirmation
  again, including event time and evidence hash. Direct confirmation calls use
  the same payment advisory lock as the gateway before locking the payment row.
- Stores a server-computed digest of normalized RPC inputs independently of the
  caller's payload hash. It includes the event, payment, network, transaction,
  confirmation, receiver, amount, event instant, evidence, reason and reference.
  Timestamps bind the instant independently of session timezone.
- Retains historical requests unchanged with a null input digest. Their complete
  prior RPC identity cannot be reconstructed safely, so replay requires
  reconciliation. No historical input or approval was invented.
- Requires complete provider identity for rejection and stores an immutable
  rejection record behind the gateway. Rejection replay must match that record;
  an Admin compensation is not treated as a prior provider rejection.
- Revokes the legacy three-argument rejection entrypoint and makes it fail closed.
  Its missing identity fields cannot support the new contract. Existing service
  grants on confirmation/gateway are preserved rather than regranted, so an
  earlier approved-wrapper restriction is not silently reopened by this migration.

The staged reconciliation finalizer now takes the payment advisory lock before
the payment row lock. Proposal, approval and finalization also reject nonfinite
evidence times. These edits are **staged source corrections**; the complete
maker/checker deployment and concurrency matrix has not been executed here.

## Verified evidence

| Evidence | Result and scope |
| --- | --- |
| [135-to-136 upgrade](upgrade-136.json) | Applied on the existing synthetic review candidate; the [before](pre-upgrade-snapshot.json) and [after](post-upgrade-snapshot.json) four-row financial/evidence digest remained `13294d6d27906507707607c98da6a553685eae04f69d18c99e7ab3ff54c52659`. |
| [Clean 136 replay](clean-136-replay.json) | All 136 application migrations passed from the isolated Supabase platform bootstrap. |
| [Clean 138 replay](clean-138-replay.json) | All **138/138** application migrations passed on PostgreSQL 17.6, including the notification fencing and Admin retry corrections. |
| [Adversarial UAT source](../../../scripts/tests/financial_finality_content_uat.sql) and [138 output](content-uat-138.stderr) | **78 checks passed**, covering valid normalized/timezone/optional-evidence retries, altered inputs under same/new request IDs, direct helpers, legacy null-digest replay denial, candidate-bound rejection, actual Admin compensation, and role/grant boundaries. Every rejected call compares complete rows across 15 financial/evidence/audit tables. All changes roll back. Earlier 136/137 outputs are also retained. |
| [Confirmation/rejection ordering](ordering-result-137.txt) | Both orderings passed with complete rejection identity and no lasting financial change. |
| [Same-confirmation conflicting-evidence race](changed-evidence-race.json) | On migration 137, both workers waited on the payment advisory lock; exactly one succeeded, one conflict was rejected, one balanced receipt journal persisted, and no processing request was orphaned. |
| [138 duplicate SMS race](seed-race-138.json) | One review candidate, one ignored duplicate and no credit. |
| [138 identical confirmation race](identical-finality-race-138.json) | Two workers produced two processed request IDs but one confirmation, one balanced receipt journal and RWF 2,500. The exact request replay succeeded using the same fixed event instant. |
| [138 Admin reversal race](reversal-race-138.json) | One fresh compensation and one replay produced one balanced reversal journal and zero remaining confirmed balance. |
| [Final snapshot](final-snapshot-138.json) | One reversed synthetic payment, one receipt journal, one reversal journal and zero confirmed balance; 21 covered rows. |

The older direct-USSD concurrency helper and the current identical-finality
harness now preserve the same fixture event instant on retries. Changing `now()`
between calls was changed content, not an identical provider retry. Financial
harness guards were updated for exactly the known 136–138 schema versions;
syntax checks passed. During the new race run, harness version-expression and
expected-winner checks needed correction; final retained passing results use
the corrected harness. No failing run was treated as acceptance.

## Remaining acceptance and rollout work

1. Coordinate the gateway/rejection contract with every service caller. Legacy
   requests lacking verified input identity require an explicit reconciliation
   path; do not fabricate a digest or silently reprocess them.
2. Complete representative historical upgrades, cross-payment duplicate
   references, historical reversal variants and the approved late-receipt policy.
3. Execute the staged maker/checker workflow, revocation races, wrapper/direct
   concurrency and both deployment-order permission scenarios on the full schema.
4. Authenticate actual independent provider/statement evidence and read back the
   authorized deployed functions and grants. These synthetic calls do not prove
   provider authenticity or final settlement.
5. Run signed-device, exact frozen-candidate and operating acceptance. F02, F07,
   F08, F09, F10, D09 and O10 remain open.

Local fixture backups were retained and their archive tables of contents checked
before task-owned resets. Other local fixtures and the recovered Git checkout
were preserved. The [verification manifest](verification-manifest.json) binds
the final source files and retained result artifacts for this packet.
