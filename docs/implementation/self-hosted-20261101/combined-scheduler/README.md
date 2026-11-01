# Combined scheduler qualification — 1 November 2026

## Later complete-current run

The final maintained current native run 4 passed all **24
scheduler scenarios on the complete 25-migration chain**. Its result is
[`mobile-validation/current-native-final-4/RESULT.json`](../mobile-validation/current-native-final-4/RESULT.json),
with broader qualification-source SHA-256
`fcf1ead40a86061a9454f25f1fa80900d7c3bd025b5483b7765bae92a98cff9a`.
The real immutable database identity was retained; Cron/Vault/`pg_net` remain
explicit doubles, and no provider, native-extension or production acceptance
is inferred. Earlier failed attempts and the distinct passing run 2 remain preserved.
The earlier 24-chain receipt below is unchanged and retains its original scope.

## Qualified result and exact scope

`ddd017c6-ecf4-4931-bd57-5f75a9f8adb0.json` records **24 passing scenarios**, zero failures, on a fresh task-owned PostgreSQL 17.11 database. The database contains the original sixteen migrations and the eight reviewed additions that existed at this capture. Its real immutable deployment identity was bound before the source was initialized. The normal `postgres` owner had neither superuser nor RLS bypass privileges. No profile-assertion double was used.

The backend source bundle contained 252 files and had SHA-256 `f3503b1b54ca4a08906a46ddd6da60ef6e63fb408b59e8499025230e517d6f65` both before and after the run. The exact migration, profile, renderer and installed artifact digests are in the receipt. This is a complete **24-migration** result for those bytes. The later gateway fencing migration 25 and later host changes require their own current-chain result; this receipt is not relabeled as that result.

The native test installed the main jobs lane first, then the contribution-email lane. Both installed inactive. Real PostgreSQL functions, privileges, transactions, admission journals, locks and control transitions were exercised. Cron, Vault and `pg_net` interfaces were explicit SQL doubles: no real extension worker, HTTP queue worker, SMTP service or message provider ran.

## What the native checks established

| Boundary | Observed result |
| --- | --- |
| Immutable database identity | Missing identity, a mismatched digest and an independently valid sibling profile were refused. An exact original binding was read back without replacing it. |
| Inactive installation | Combined coverage was verified, with zero active jobs, zero queued requests and zero lifecycle obligations. |
| Function inventory | Unexpected routines, main and email body changes, security mode, null-input behavior, owner and ACL changes invalidated coverage. |
| Schedule identity | A changed email Cron command invalidated coverage. |
| Current source | A changed configured source could not admit a dispatch. |
| Original dispatch identity | The original probes and their readback identities were retained; replay did not create another send. |
| Active scheduling | Both active schedules were counted and blocked fencing. |
| Unknown outcomes | Timeout and unknown results paused work; a later `reviewed_unknown` label did not settle the local lifecycle. |
| Generation-bound evidence | A wrong-generation proof did not clear the retained obligation. |
| Email application journal | A linked inner email dispatch was counted once with its outer dispatch. An orphan unknown added another obligation. |
| Final drain | The controller remained `quiescing`, with three unproven lifecycle obligations. The test did not manufacture a completed drain. |

The final scheduler state was `coverageVerified=true`, `blocking=true`, `namedActiveJobs=0`, `pendingNativeRequests=0`, `reviewedUnknownDispatches=2`, and `lifecycleUnproven=3`. The fixture retains that state. These are successful safety assertions about a deliberately unresolved fixture, not release admission.

## Failure retained and correction

`54bd0333-e744-484f-9641-453280441780.json` preserves the initial native failure. It exposed two real defects: changing a main scheduled function while retaining its recognized guard prefix, or changing a main helper body, did not invalidate combined scheduler coverage. The original prefix-only inventory was insufficient.

The corrected email installation artifact now includes exact source-bound manifests for the main and email routines. It verifies body hashes, signatures, defaults, argument modes, return metadata, language, volatility, parallel/support properties, null-input contract, security mode, search path and owner, while retaining the closed routine inventory, ACL checks and existing admission guards. The same native mutations then invalidated coverage as required. This correction changes the operator/rendered installation artifact; none of the original migration files was rewritten.

The initial receipt also contains dependent harness failures caused by JSONB argument encoding and a refused direct controller mutation. They are not reported as ten separate product defects. The harness now uses an explicit text-to-JSONB cast and tests configured-source drift without bypassing the controller. `a70cf9e9-308e-4f4e-8840-a4c7f3069c02.json` separately retains a zero-test setup refusal for missing Deno `uid` permission.

## Maintained entrypoint and remaining acceptance

`scripts/supabase/testing/combined-self-hosted-scheduler.ts` now derives its migration inventory from the exact reviewed current-chain helper, preserving the old receipt's original scope. It requires a fresh original 16 integration template, its task-owned local cluster descriptor, an explicit synthetic flag and a freshly generated source manifest. Each invocation creates another database; it does not reset an existing fixture. The current CI orchestrator supplies a new output directory and validates the complete receipt.

Production acceptance still needs the actual pinned stack and Cron/Vault/`pg_net` services, real private-network routing, provider configuration and approved bounded dispatch receipts, operational key custody, source-bound owner approval and real backlog/crash/recovery evidence. All installations remain inactive until those gates are satisfied. An accepted SMTP request or gateway job is not recipient delivery.
