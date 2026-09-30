# Admin roster reload recovery — local implementation

## Implemented

Migration `20260930120000` adds session-owned private editor drafts and immutable staged review/commit intents. It preserves migration 142 source, extraction, review and commit provenance. The RPCs recheck the original live Auth session, owner role, approvals, permissions and feature flag on every dispatch. A read-only recovery call never invokes extraction, review or commit.

The browser sessionStorage bookmark accepts an exact nine-field schema of version, owner digest, upload/source digest, group/import/checkpoint references and pending request/digest. It contains no roster rows, names, phone numbers, file bytes, group title, reason or Auth credentials. Storage failure displays a warning and never claims reload durability. Session invalidation removes the reference and private memory values; stream errors and completion invalidate the gateway.

`Save recovery draft` persists bounded private values on the server. Unsaved later changes are explicitly identified as lost on reload. A saved draft uses compare-and-swap checkpoint IDs; a competing tab cannot silently overwrite it. Unknown draft acknowledgements retry the exact same checkpoint and payload. Checking recovery explicitly adopts the latest server draft and clears ambiguous in-memory save state.

Review and commit buttons first stage the exact UTF8 JSON text and SHA256. Staging only stores an intent. Explicit execution requires human affirmation and returns an ACK bound to request, import, kind and exact digest, wrapping the unchanged 142 receipt. Recovery of a pending submission requires renewed UI affirmation and visits to all row pages. No write runs automatically after recovery. Matching stored completed commit receipts can acknowledge a lost response without another submission.

An upload reference with no source receipt requires discarding the reference and reattaching the original source: no browser bytes exist to reconstruct it. Awaiting preparation remains uncertain and can be checked again without retrying the provider. Failed and expired preparation remain closed to writes.

## Bounds and expiry

- Every server editor/intent payload is limited to 512,000 UTF8 bytes; editor/review arrays contain 1–500 typed rows.
- At most 40 intents per import, 100 unexpired intents per session and 200 per actor.
- At most 20 active editor drafts per session and 40 per actor. Existing 142 source creation retains its 100-per-actor/day limit.
- Recovery expires with the original source's 24-hour expiry; saving does not extend it.
- Expired uncommitted recovery returns no editor rows or pending payload. Committed 142 provenance remains available to the original authorized session.
- `collect_hybrid.purge_expired_roster_recovery(limit)` is an explicit owner-only maintenance function. It deletes at most `limit` expired drafts and `limit` expired intents per call using bounded `SKIP LOCKED` selection; it never deletes 142 source/review/commit rows. No scheduler or provider is introduced.
- Direct payload-table access and private helpers are revoked from anon, authenticated and service_role.

## Verified locally

`attempt1/validation.json` binds 214 unchanged source/runtime/SQL/test/font/lock inputs to:

- 90 passing integrated roster tests, including actual 142 deterministic and synthetic AI SQL receipt decoders;
- 57 passing XLSX/parser regression tests;
- one passing Chrome test using actual sessionStorage;
- eight-file analyzer with no issues;
- Ruby syntax validation for the new concurrency harness.

The sole skipped test is the actual 144 SQL output decoder. Migration 144 SQL/application, rollback fixture assertions and real two-session races are prepared for root's exclusive task database execution; they are not claimed as executed in this packet. The fixture AI result is synthetic and no provider/Auth HTTP service is called.

## Root execution handoff

1. Preserve a fresh backup and full data/control fingerprints of the exact task fixture before 144. Apply the frozen 144 migration as the normal installer only after 143 is accepted; record 144 in the local migration registry according to the existing root-owned rehearsal procedure.
2. Execute `scripts/tests/roster_import_reload_receipts_uat.sql` and `scripts/tests/roster_import_reload_adversarial_uat.sql` using exact fixture container `supabase_db_collect_fin_concurrency_qa_20260929`, port 55722, role postgres and `PGOPTIONS=-c collect.roster_provenance_qa=isolated_clone`. Both require 144 registry entries, latest 20260930120000, cron launcher off and net batch 0; both roll back. Preserve stdout/stderr and prove all baseline fingerprints restored.
3. After another backup, run `scripts/tests/roster_import_reload_concurrency_uat.rb` with `COLLECT_ROSTER_PROVENANCE_QA=isolated_clone`, a NEW absolute `COLLECT_ROSTER_CHECKPOINT` and `COLLECT_ROSTER_RELOAD_MIGRATION_SHA=751be9afb6a1da5e221160b0201b0c3b7c532dc56f170f630ca03870929455b9`. It asserts task labels/port/registry, captures checkpoint before seeds, and proves actual blocked waits in six scenarios: duplicate draft, competing checkpoint CAS, duplicate staged review, recovery racing commit, concurrent commit replay and feature revocation racing recovery. It restores all table/control fingerprints with exact top/owned-child XID attribution; sequence counters are not reset.
4. Run `validate.py` with `ROSTER_RELOAD_SQL_RECEIPTS` pointing to the root-written 144 receipt stdout and `COLLECT_ROSTER_RELOAD_PACKET` pointing to a NEW output directory. The runner refuses to overwrite prior evidence and then includes the actual 144 decoder and receipt SHA in its manifest.

No hosted mutations, provider calls, store/device proof or production release are claimed.

## Actual144 receipt continuation

Root applied migration144 only in the owned local database fixture, and retained rollback receipt/adversarial checks plus six real two-session races. `attempt2-actual144/validation.json` binds that root receipt input and all source files. All213 inputs stayed unchanged:91 integrated roster tests passed (actual144 decoder executed with no skip),57 XLSX regressions passed, the actual Chromium bookmark test passed, eight-item scoped analysis was clean, and concurrency source syntax passed. `sources-attempt2-actual144/` preserves and rechecks every bound source file. This supersedes the earlier missing144-decoder limitation of attempt1; actual full-page browser integration is tracked separately in the local browser lifecycle packet.

## Current shell/browser continuation

The authorized Admin logout mounted guard changes a runtime input included in this validator. Prior attempt2 remains preserved as dated evidence. Current `attempt3-current-logout/validation.json` rebinds all checks to the fixed shell with actual root-owned144 receipts:91 roster tests with actual142/144 decoding and no skip,57 file/XLSX tests,1 Chromium bookmark test, clean eight-item analysis and Ruby syntax. All213 inputs were unchanged and all213 source copies were hash-verified under `sources-attempt3-current-logout/`. Validation SHA-256: `ec522ced797605ec2e8c34e095eb07923572954b5307c84ad6b8cd7bc05b3058`.

The actual normal-entrypoint browser companion now passes full page reload, separate tabs/CAS, staged/lost review and commit responses, explicit fresh affirmation, live revocation, actual SDK A→B→A, real storage quota, missing unacknowledged source, cross-tab logout and installed PWA offline reload with zero uncaught errors. Its16 declared lifecycle cases and37 assertions are source-bound to557 unchanged inputs. The separate local-browser packet describes the synthetic loopback transport limits; actual SQL semantics remain bound to the root-owned database fixtures. No hosted/provider/device/store/design acceptance is claimed.
