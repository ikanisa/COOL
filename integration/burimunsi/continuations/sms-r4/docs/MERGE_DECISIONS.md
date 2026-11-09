# R3 merge decisions

Inspected baseline: `SMS_Policies_R2_Source_2026-11-09.zip`, SHA-256 `4175a7cd8508769dc17a005d7c6031198e7821c4ccbeec53cc08bde3c7fbf5d2`.

| Path/workstream | Decision |
|---|---|
| All R2 `src/` policy/adapters | Keep byte-for-byte. No change to classification grammar, acknowledgement contracts, retry policy or existing worker/source admission. |
| All R2 `fixtures/` and `vendor/` | Keep byte-for-byte. The original 40 pinned dependency hashes still apply. |
| `SnapshotCodec.kt`, `JournalFormat.kt`, `JournalQueueStore.kt` | Add to shared source. Stronger persistence checks supplement, not rewrite, R2's state machine. |
| `host/kotlin/.../HostFileJournal.kt` | Add outside the mobile installer tree. Plaintext synthetic-only host adapter, explicitly not a production Android port. |
| `tests/persistence/PersistenceChecks.kt` | Add standalone executable Kotlin suite including real child-process termination/reopen tests. |
| `tests/python/test_persistence_delivery.py` | Add R2 preservation and additive-upgrade tests for both applications. |
| Existing R2 tests and `scripts/install_overlay.py` | Preserve byte-for-byte. Installer's existing directory discovery includes new shared sources but excludes `host/`. |
| `scripts/verify.py` | Extend input hashing to host/provenance, include R3 suite, retain inherited suites, expose external encryption/anti-rollback gate. |
| R2 README/integration/coverage decisions | Retain in `docs/R2_*.md` as historical descriptions. Current README and integration guidance supersede their pending-port status. |
| Current evidence/manifests/status | Regenerate from this R3 source; do not relabel R2 logs as R3 execution. |

No merge into a live A03/A04 consolidated source candidate or actual Collect checkout is claimed. There is no unreviewed overwrite of canonical/owner-recovery/financial/UI/SMS/operations continuations. The current contribution is an additive SMS persistence workstream with pinned dependencies and explicit remaining native reconciliation.
