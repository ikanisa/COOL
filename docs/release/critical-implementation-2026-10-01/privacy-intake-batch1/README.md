# BE05 privacy intake: accepted local slice

Dated 2 October 2026 (Kigali). Actual final SQL acceptance completed at 2026-10-01T22:58:48.107142+00:00. This batch implements intake and own-request status. Full BE05 remains open.

The additive `20261002031500_privacy_request_intake.sql` migration derives the subject from Auth, requires an actual live and fresh session for submission, serializes duplicate requests, rejects UUID/payload conflicts, bounds reasons and alternate UUID bindings, and returns a minimized pending receipt. Ordinary members inherit no platform-owner or roster authority. The original `request_account_deletion(text)` retains its UUID return contract and now uses the guarded path. New status is own-only; the existing approved platform-admin legacy SELECT remains available with a live SID. Direct request writes and private-table/helper access are revoked from client and service roles.

Actual acceptance:

- All 200 captured migrations through `20261002040000` replayed. The independent `20261002030000` telemetry and `20261002040000` unarmed-closure migrations are included, without attributing their changes to this slice.
- 53 new SQL checks passed: trusted subject/session fences, reason limits, exact replay, equivalent requests, conflicts, historical adoption, private immutability, bounded UUIDs, own/outsider/Admin access, expired/revoked/malformed/stale sessions and denied anonymous/service access.
- The maintained legacy privacy/financial fixture and the new intake fixture passed. Complete retained-row hashes across 242 tables match after each rollback. A real REPEATABLE READ call was refused with SQLSTATE 40001.
- Six real two-transaction races passed, each with an observed PostgreSQL advisory-lock wait: same UUID, equivalent UUIDs, changed payload, cross-subject collision, revocation winning, and intake winning before revocation. A revoked SID subsequently failed status access.
- All 213 financial/resource table snapshots stayed unchanged. Every existing realtime row was preserved; exactly ten new audit invalidations contained only `id`, `area=audit` and `created_at`, matching five request and five intake audit records. Five canonical requests and six submission bindings were observed.
- Eleven existing effective Auth/Admin helper definitions and ACLs and 336 existing foreign keys were preserved. This migration adds exactly three private foreign keys; four later additions belong to the included unarmed-closure migration.
- The owned network-disabled/no-port database was removed and absence was verified. At completion, captured source hashes and the complete 200-migration path set matched.

Post-run source limit: the sealing readback observed a newly added `20261002041000_receipt_successor_approvals.sql`, making the current chain 201. Every tested input byte remains unchanged. This later migration was not executed in attempt3, so this receipt cannot certify the complete current 201 chain. Its exact path and hash are retained in `final-source-readback.json`.

Original failures remain intact. Preflight1 captured 197 before a new migration appeared and recorded a case-sensitive cleanup-readback failure; a separate readback proves its target absent. Preflight2 passed against 198. Attempt1 replayed 199 and passed the legacy fixture, then failed on the new synthetic Admin role's missing required reason. Attempt2 replayed 200 and passed SQL/race behavior, then correctly failed an overly broad unchanged-row assertion on ten expected audit invalidations. Attempt3 retains all financial assertions and separately proves their exact publication.

This is a normalized local database proof using the maintained row-free Auth/Storage platform shape and PostgreSQL 17.6. It does not attest signed JWTs, GoTrue, Storage runtime, hosted migration history, managed installer permissions or a deployed environment. The legacy fixture exercises populated financial behavior within a rolled-back transaction; the concurrent snapshot describes the actual retained local baseline, not a populated production ledger.

Policy/scope/retention review, holds, processing, derivative deletion, Auth/principal handling, native cleanup, exports, processors, backup/restore evidence and full BE05 acceptance remain pending. Client fresh-auth UX and CI/deployment integration are also outside this batch. No erasure, account restriction, Auth removal, processor operation or completion authority is enabled.

See [interface and boundaries](interface-and-boundaries.md), [final receipt](batch.json), [actual completed result](attempt3/result.json), and [source readback](final-source-readback.json). `seal.json` records every packet artifact except itself.
