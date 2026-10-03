# Shared worker inventory/database snapshot: private review packet

The reviewed proposal is implemented in private staging. Root is the sole promoter. No canonical, hosted, credential, native or scheduler source/configuration was written by this slice.

## Result and integration boundary

`--worker-snapshot` is opt-in on the existing source-contract-backed full database backup and isolated restore callers. The backup helper holds one ordinary `postgres` read-only REPEATABLE READ transaction, captures the original catalog and both bounded700 logical/object inventories inside it, runs full custom-format `pg_dump --snapshot=<that export>`, rechecks holder/catalog/source identity and reaps the holder before success publication. The standalone catalog query's exact pinned BEGIN/COMMIT wrapper is removed only for this held invocation; its canonical SQL source remains unchanged.

Inventories retain original keys, relocation binding, tier, logical/object hash, exact page byte/hash, count, cursor and empty terminal. Restore refuses unmatched/missing/extra/conflicting inputs, then invokes700's actual owner verifiers and independently re-enumerates both complete sets in one target read-only RR transaction. No filtered table/schema/data archive, grants, read/API widening, alternate credentials or production privileged-role fallback was introduced. Owner-only700 API definitions/body SHA/ACL/source SHA are checked before credential or Vault actions.

The existing pinned image, TLS CA/session-pooler/approved IP, non-echoed credentials, tmpfs, encrypted volume, report-source/catalog and isolated restore controls remain. The production connection remains its original `postgres` route. The helper bounds25 rows/page,4 MiB plus64 KiB/page,128 MiB inventory total,10,000 combined pages,900 seconds total,120 seconds per query,10-second lock timeout,30-second idle timeout, private errors and bounded process cleanup. Generated named snapshot containers are removed and absence is read back; cleanup uncertainty marks the capture failed. A worker association cannot be silently ignored by the restore caller. Catalog/query/network-probe files included below are unchanged dependencies, not promotion deltas.

## Accepted actual local proof

Command: `python3 .cache/receipt-worker-snapshot-capture-20261002/snapshot_uat.py --report-dir .cache/receipt-worker-snapshot-capture-20261002/proof/sql-attempt6`.

- 38 distinct accepted checks. The outer result includes30 driver checks; do not count its embedded driver list again. Raw73 outer commands and28 Ruby-command receipts are retained.
- 222 actual SQL source/tool/prerequisite bindings plus112 helper loaded dependency/source/tool records were captured and verified unchanged (the final readback file is authoritative for the actual helper-record count).
- The fixture reuses the exact sealed7006,560,610-byte full SQL input, SHA `c0afe5f1e7faf3610e6acda1228d1021052e6abd913980f4f39231be0fa5d311`; it does not replay or copy the earlier whole migration matrix/2.3 GiB packet.
- A real admitted maintenance batch and shipping worker-configuration producer on another ordinary `postgres` connection commit after export/first page. Fresh source cold-object/configuration facts change; held inventories and the full dump retain the export cohort. Actual source/restore archive association, complete catalogs (owners, ACLs, extensions, RLS and dependencies) and all272 tables/6,266 rows/4 sequence observations compare equal.
- The actual target RR reader verifies exact2,042 original logical keys and84 cold objects, including tier/relocation binding and object byte hashes. Original worker UUID lookup still returns original recorded evidence.
- Strict actual failures cover closed export import and pg_dump42704, association conflict, altered/missing page, missing terminal, internally coherent false tier, extra restored cold object, actual known corruption55000, rollback of that diagnostic corruption, holder departure/no success manifest, bounded lifetime expiry and source-binding drift. The corruption is a declared table-specific diagnostic transaction and rolls back its trigger/check/payload changes; no immutable global or shipped authority bypass was added.
- 12 owned source/restore targets from all six attempts are read back absent. Network is none, no published/listening ports; cron is off, HTTP is stopped in template1/batch0. Raw business state was restored before comparison; no durable business inactive overlay is claimed.

The local role split is explicit: holder/inventory/maintenance effective/session `postgres`, NOSUPERUSER; complete archive/restore effective/session isolated `supabase_admin`, SUPERUSER. The actual archive role successfully imports the ordinary owner's snapshot. Fixture-created owner-normalized DDL, CREATEDB/CREATEROLE/BYPASSRLS and managed pg_graphql member/nonmember normalization are local platform limitations. The original wrapper's actual definition/owner/ACL/config/dependency match after restore. This does not attest production `postgres` dump-role access or managed-owner parity.

## Separate source cohorts and unit proof

The accepted SQL/dump fixture has205 source migrations, selected from retained192 plus the real predecessor9 and exact430/500/corrected600/700. All205 hashes match the separately observed current207 source files. Current420 privacy status and800 repeat-run recovery are excluded. `proof/final-closure/canonical207-observation.json` is a file observation only; neither it nor source equality is a full207 replay/recovery claim. All nine proposal originals remain unchanged.

`proof/unit-attempt2` passes33 cases/155 assertions: new9 boundary cases/48 assertions at the proposed canonical test path, legacy13 source-contract/59 assertions,4 backup/23 assertions and7 restore/25 assertions. Five Ruby syntax commands pass. The earlier unit-attempt1 checks are the same scopes and are not added again. Private legacy test adaptations change only stage require/source-reading paths. The new canonical-relative test file was added after SQL attempt6; it changes no runtime source, and its own final unit/source before-after capture binds that exact test and all current staged sources.

## Retained failures

All attempts remain immutable evidence. Attempt1 found a real implementation defect: running the standalone catalog COMMIT destroyed the exported holder, causing actual pg_dump42704. The exact wrapper extraction/heartbeat correction is in the accepted helper. Attempt2 completed positive capture/restore but failed a negative test's expected42704 wording. Attempt3 similarly failed a page-mutation test that had not actually changed the first-page bytes. Attempt4 passed36 checks, before the two final role/tier cases. Attempt5 retained a test-only strict duplicate-key clone mutation refusal; the diagnostic clone was corrected without a product source change. Attempt6 is the final38-check accepted proof. One final absence-readback assertion initially expected capitalized Docker text; actual Docker29 lowercase no-such-object/empty-vector/negative-exit is now matched and documented in its receipt. No failure is reclassified as a pass.

## Promotion and review

Apply only the six exact `PROMOTION_MAP.json` changes, guarded by its old SHA/null target association. Unified review patches are in `patches/`; new helper/test have complete source patches. Unchanged staged network probe and catalog SQL, private drivers/legacy tests and raw proof are evidence/dependencies only. Do not promote them as product changes. No migration, MCP profile or sender authority is changed by this packet.

| Target | Exact predecessor SHA256 | New SHA256 |
|---|---|---|
| scripts/audits/collect_receipt_worker_snapshot.rb | new | 1032dcd0a9241bd574a923bc99b02676fe025d8c3a59537bb206ec9e949d3c1d |
| scripts/audits/collect_recovery_source.rb | 4a6a0d7f80628781bf18e6b7aa00ced630943f3af612247126e0bf21c3c760cc | 8a5d497cd75ecc2eaddf3c6195648c5e664f524b4688c87d2b2fdb083a49aeb0 |
| scripts/audits/collect_encrypted_database_backup.rb | 563697906caeec76fe1da346cc6fac8b4bb0f1c54320c382c9262bec5c2ef742 | 0feb1f4b5e534e1cd72f737522cc0c05682af6cba2e94060480afc88b5bd2ada |
| scripts/tests/production_archive_restore.rb | b4eb514956df738056479ed711b9e42a66e91d5d479ca01e9f68b0517a37c415 | 1d2d12d076b76d02d6a36b41cb0a0830188607119b3efca020f96009ea362867 |
| docs/platform/CURRENT_CANDIDATE_RECOVERY.md | f8531600e2fac860b9f44b4c44abcd168952ec51050c315159de2e56607760be | 52f26823f6b3b7cafe67e44fc12bd25c62ab9a7e6997b335be630cbf8727a8ca |
| scripts/tests/collect_worker_snapshot_test.rb | new | c274e3e48415dc2ea2a3a7bccf7c2aab9d2d3fa681e633ce0f8f9dcbc2c7ab9b |

## Remaining distinct acceptance

Real production owner/credential route and encrypted Vault crypto/remount workflow, full current207 graph, Storage object bytes, independent keys/offsite recovery, native Android/scheduler journals, unified pause/compromise/rollback overlay and owner RPO/RTO/device/provider/release acceptance remain separate. Global roles are captured separately; PostgreSQL sequences are not MVCC and the successful four sequence observations are not asserted to be export-instant sequence values. No financial action, provider send, live activation or production GO follows from this local packet.

Primary PostgreSQL17 contract references: [exported snapshot lifetime](https://www.postgresql.org/docs/17/functions-admin.html), [import before first query under RR](https://www.postgresql.org/docs/17/sql-set-transaction.html), [pg_dump snapshot](https://www.postgresql.org/docs/17/app-pgdump.html), [isolation and sequences](https://www.postgresql.org/docs/17/transaction-iso.html).
