# Decoder SQL admission: completed local acceptance

The additive ordinal-194 migration accepts the current six-field decoder receipt toolchain (Python 3.12, Pillow 12.3.0, pypdfium2 5.2.0, pypdf 6.19.0, openpyxl 3.1.5 and defusedxml 0.7.1). Otherwise-valid fresh receipts carrying individually old Pillow 12.0.0 or pypdf 6.7.0 are rejected. The dependency lock also includes et-xmlfile 2.0.0; it remains outside the existing six-field receipt contract.

Actual acceptance attempt5 passed on 2026-10-01 at 22:17:52 UTC. The canonical maintained installer replayed all 197 current migrations into a task-owned network-none PostgreSQL 17.6 container. The before/after source manifests match exactly; the 196 earlier migration files retained their bytes, and the newly observed receipt-source-busy migration was included. That unrelated migration has installation evidence here, without a separate behavior-acceptance claim.

| Actual check | Result |
| --- | --- |
| Live immediate predecessor (193 migrations) refuses the current fixture before writes | Pass |
| Effective catalog before/after ordinal194 | Only two private decoder version literals changed |
| Public guarded wrapper, function OIDs/owners/config/ACL, session/authority/recovery functions and recovery inventory | Preserved |
| Resource integrity and exact toolchain denials | 31 checks passed |
| Preview/review/commit/reload and lost cleanup acknowledgement compatibility | Passed |
| Fresh-auth transfer, authority, bytes, logout and proof lineage | 51 assertions passed |
| Actual two-worker overlapping races | All seven passed |
| Ruby table and complete database-control baselines | 162 table baselines and controls restored |
| Outer application-table readback | All 228 checked tables restored |
| Source/captured-source/migration-path drift | None across 209 frozen inputs |
| Owned SQL proof containers | All three observed absent after removal |

The migration replaces the private revoked alias established by the historical recovery wrapper; the public guarded wrapper is preserved. No historical migration or recorded receipt is rewritten. Catalog comparison proves the only effective admission changes are the two dependency pins.

The affected resource fixtures now respect current actor/global quota ordering while still independently triggering global request, byte and cost denial. A separate synthetic actor supplies the global-only usage. The compatibility fixture uses a unique synthetic phone distinct from the canonical installer's owner. The three rollback SQL suites restored every outer application-table fingerprint.

The concurrency fixture uses the existing current request-bound v2 feature API with its observed revision, exact request IDs, original controller SID and bounded deadline. Its seven original race identities, denial/overlap helpers and first six race bodies are byte-preserved. Cleanup additionally restores only the captured feature head and exact fixture-owned request/event records. Six named resource/governance triggers are disabled only within the quiet isolated QA cleanup transaction after target, catalog, XID and ownership checks, then restored. Full table and control hashes must match before commit. No runtime/backend permission or production cleanup bypass was added. PostgreSQL sequence counters are neither reset nor claimed restored.

Every failed attempt remains intact. Attempts1 and2 stopped before target creation/SQL when observed migration counts exceeded their frozen expected sets. Attempt3 retained its invalid-hour filename snapshot and genuine quota-order failure. Attempt4 completed the normalized196 replay and all three SQL suites, then failed on the obsolete feature RPC; cleanup also refused changed feature/head/event baselines and rolled back. All owned targets were removed. The historical attempt1 field naming a concurrent migration proves only a newly observed path between enumerations; origin and writing time were not established.

This is normalized local acceptance: the row-free Auth/storage platform and task-local normalized PostgreSQL superuser do not attest managed installer privileges, GoTrue/Auth-provider runtime, production policy/data, hosted migration history or parity, provider behavior or deployment. No provider/hosted/shared-database calls were made. The locally normalized migration filenames have a separate byte-preserving receipt; hosted history access remains unverified.

Read `batch.json`, `attempt5/result.json`, `source-freeze-attempt5.json`, `post-acceptance-readback.json`, `fixture-preservation-attempt5.json` and `attempt-history-readback.json` for exact identities, source manifests, logs and failure provenance. The completed dependency remediation is separately bound by its existing decoder-dependency-batch1 receipt.
