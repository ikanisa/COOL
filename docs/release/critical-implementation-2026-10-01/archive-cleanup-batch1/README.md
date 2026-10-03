# ARC-10 preservation-first evidence cleanup review

The read-only inventory and concrete first-batch recommendation are complete. **ARC-10 remains open. No original evidence has been archived, restored, relocated or deleted.** This packet proposes only the next reversible preservation work and the exact evidence required before root assigns removal. It does not confer release, retention, customer-data, signing or production approval.

## Verified inventory and boundaries

The live metadata census ran from **2026-10-01 22:55:11 to 22:57:12 UTC** over `docs/release`, including Git-ignored files and excluding only this new packet. It recorded **361,062 regular files**, **64,276 directories** and **35,754,404,784 logical bytes (33.30 GiB)**. Two absolute symlinks were recorded by target hash/existence and were not traversed. There were **zero metadata read errors**. This is a live census during independent work, not an immutable release snapshot or all-computer inventory.

The final path/extension classification below gives priority to compiler/dependency caches and compiled artifacts before copied-source trees. It is a metadata heuristic: a class does not establish identical content, discardability, regeneration, sensitivity or approval. [`class-refinement.json`](class-refinement.json) supersedes only the preliminary class totals in the compression receipt.

| Class | Files | Logical bytes |
| --- | ---: | ---: |
| Copied source/candidate trees | 280,343 | 21,303,923,040 |
| Dependency/compiler caches | 2,809 | 7,555,060,222 |
| Binary archives/generated components | 236 | 1,683,763,793 |
| Execution logs/text evidence | 36,386 | 1,451,175,667 |
| Structured reports/manifests/data | 13,031 | 1,359,093,104 |
| Unclassified authored/copied code | 23,113 | 1,232,912,826 |
| Images/visual evidence | 2,414 | 510,415,852 |
| Compiled/packaged artifacts | 1,033 | 433,182,063 |
| Other unclassified | 1,067 | 218,908,085 |
| Report documents/pages | 630 | 5,970,132 |

The largest families are `admin-full-coverage-2026-09-30` (19,081,744,863 bytes), `roster-fresh-auth-2026-09-30` (4,413,936,035), `data-correctness-2026-09-30` (3,456,811,790), `generated-query-benchmark-2026-10-01` (1,604,432,334), `collect-codex-goal-2026-09-30` (1,521,450,221) and `cache-session-2026-10-01` (1,128,003,603). Full original paths, sizes, modes, timestamps, inode/link metadata and original classifications are retained in [`file-inventory.jsonl.gz`](file-inventory.jsonl.gz).

The raw **160,031,459-byte** new metadata table was replaced, with root's explicit output-only authorization, by deterministic **9,073,149-byte** gzip. Every decompressed byte, all **361,062 rows** and the original SHA-256 were verified equal before only our new raw table was removed. Original inventory SHA-256: `36ea95cba947e5e9a192fc4060bb120a1c0bcb9f1529f73aea0131f840ceee16`; compressed SHA-256: `07180c98f80c739038a56a2869bca3978d8f0197aed7598764833f1f75796022`. This representation change is not an archive or deletion of pre-existing evidence. See [`inventory-representation.json`](inventory-representation.json).

Logical bytes are not physical savings. Allocated-block sums can double-count hardlinks/clones; no physical deduplication or safely reclaimable-byte total was proved. Moving unique bytes to the same PRO-G40 volume is not an independent backup and may initially consume additional space.

## Bounded content identity findings

Only **110 explicitly selected files / 847,224,544 logical bytes** were fully hashed with regular-file/alias/drift checks. This does not imply hash-level coverage of the entire tree. See [`bounded-duplicates.json`](bounded-duplicates.json).

* The **98 files / 73,167,256 bytes** in two historical Firebase Clang module-cache trees are **98 distinct content hashes**. They are generated relocation candidates, not duplicates. Matching prior/current PCM basenames repeatedly contain different bytes.
* Eight prior APK paths within the active `native-gateway-observation-2026-10-01/root197-correction/actual-native{1..4}` family are byte-identical: each **96,528,208 bytes**, SHA-256 `fd4eae394552d0725ffb971910d7f2ee58045aaf339dc0a42a7c3d707dffcf67`. All are deferred because their active evidence/path/epoch consumers and signing context must be preserved. The seven repeated copies total **675,697,456 logical bytes**, with no proven physical saving or removal authority.
* Selected locks and Inter font bytes in two dated data-correctness source exports match, while their selected theme source bytes differ. Both source epochs and all unique material remain. Font equality is not a rights/usage approval.
* **49 same-basename groups have different hashes** in this small bounded set. Basename similarity, a dated directory or untracked/ignored status cannot justify deletion.

## Actual consumers and integrity links

The maintained static scan checked **1,359 source/config files**, found **153 consumer files / 349 literal or directory references**, and had zero skips/read errors. No direct `lib` runtime reference to `docs/release` was found in that bounded literal scan; indirect/computed dependencies are unproved. Reader/writer labels are preliminary, and deliberate temporary test paths are not automatically missing-input defects. A final bounded reread found **152 unchanged consumers and one changed consumer** (`scripts/tests/privacy_request_intake_uat.py`); its old/current hashes are retained, with no interference in that independent work. New source files after the census are outside the reread.

[`consumer-repair-matrix.json`](consumer-repair-matrix.json) records nine explicitly reviewed groups. Public quality/render validation loads the historical baseline, current contract and both historical/current content comparisons from this tree. Product capability tests load a dated before-source manifest. Android JVM harnesses import a Python helper from a dated report folder. Admin tests load observed SQL fixtures and frozen executed-source/result evidence. Runtime-control gates load spec/contract/inventory fixtures; upgrade tests load original legacy SQL, synthetic seed and dated hosted migration metadata. The Firebase callback probe reads the **original upstream source snapshot**. These are live engineering dependencies: broad deletion would break genuine checks.

The maintained release exporter intentionally excludes `docs/release`. That exclusion is not evidence that a fresh build/test environment is archive-independent. Some maintained Admin acceptance wrappers explicitly copy dated prerequisites back into private test exports. The minimum source/fixture/helper closure must be deliberately preserved or promoted first, with unchanged semantics, exact hashes, sensitivity review and real isolated test execution.

For the proposed cache batch, the review read **2,362 concise report/text/metadata files** in the bounded root/asset-hygiene/original-review scope. A second pass streamed **1,477 selected report/manifest/index/hash metadata files**, one compressed repository inventory, and all seven large metadata indexes skipped initially, without saving their bodies; these latter passes had zero read errors. No exact original-path or digest reference to an individual cache object appeared in these selected pre-existing indexes. The original `ios-source-compile1/verification.json` nevertheless names **both entire cache trees** in historical commands at lines **70 and 213**. Each of the 98 descendant paths has an explicit mapping to those affected tree consumers and to our new exact-path inventories.

These are bounded checks, not proof that arbitrary unnamed/computed references or deep copied/generated manifests are absent. [`exact-index-consumers.json`](exact-index-consumers.json), [`compressed-index-consumers.json`](compressed-index-consumers.json), [`large-index-consumers.json`](large-index-consumers.json) and [`bounded-link-review.json`](bounded-link-review.json) retain scopes, exact consumer hashes, per-path findings and unresolved limits. The current public contract's actual comparison path and expected digest were also verified; that small required comparison remains in the repo.

**No indexed holes are acceptable.** Preserve every original dated report, command and hash index unchanged. Before removing an original object, append an immutable relocation catalog mapping its exact original relative path, SHA-256, size and source/evidence epoch to the exact encrypted repository, full snapshot ID and snapshot path. A separately assigned fail-closed resolver must verify all affected original path/digest references against the archived/restored payload. Empty files, symlinks, rewritten historical manifests or a path-only “archived” label must never masquerade as original verified bytes. Unknown incoming-index consumers and new source/index drift block execution until the relevant removal cohort is rechecked.

## Outside-checkout recoverable storage proposal

Proposed location, **not created**: `/Volumes/PRO-G40/Application Data/Codex/Collect-Evidence-Objects/v1`. Use a pinned maintained encrypted content-addressed engine selected by the owner, rather than implementing new cryptography. Restic is a researched candidate; it is not installed on the observed PATH or approved by this task. Its official format documents content-addressed storage, encrypted/authenticated data and metadata, and snapshot provenance. An independent whole-file SHA/size catalog must preserve every original path and epoch even where engine chunks are deduplicated. [Official repository format](https://restic.readthedocs.io/en/stable/100_references.html)

Keep payloads and sensitive path/provenance catalogs encrypted, proposed directories `0700` and local private manifests `0600`. Separate public sanitized receipts from internal source/synthetic fixtures and restricted customer/auth/operational or unreviewed bodies. Default unreviewed bodies to restricted/unknown; this inventory has not performed customer/secret content classification. Identify named custodians, an independent restore verifier and approved key escrow/recovery. A second encrypted copy on an approved separate failure domain is required before unique originals are removed. No network transfer, key generation, storage installation, global configuration change or permissions grant has occurred.

Retention remains an owner decision: identify class schedules, legal/incident/release holds, archive capacity/location, key custodians and permitted access/transfer. Do not invent a legal retention period or automatically expire/prune objects. Keep all proposed objects and catalogs until the governing decisions and recoverability proof exist. See [`object-store-proposal.json`](object-store-proposal.json) and [`primary-source-research.json`](primary-source-research.json).

## Exact first batch and execution prerequisites

Only these two trees are proposed, through the **98-path exact manifest**, with every unique byte preserved first:

* `docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/ios-source-compile1/prior-module-cache/`
* `docs/release/asset-build-hygiene-2026-09-30/firebase-scene-compatibility-attempt21/ios-source-compile1/current-module-cache/`

All 98 paths are currently ignored by the existing explicit `.gitignore:132` cache rule; none are tracked. That status is supporting classification evidence only. The independently repeated full source hash/size/mode check matched **98/98**. Original-path provenance, logical sizes, modes, timestamps, inode metadata and hashes are in [`first-batch-candidate-manifest.json`](first-batch-candidate-manifest.json). Owner/group/ACL/xattr requirements still need capture before an archival operation. Keep `verification.json`, current object, compiler stdout/stderr/dependency/diagnostic records, response arguments, all source/license/comparator snapshots and every other sibling untouched.

[`first-batch-plan.json`](first-batch-plan.json) gives the ordered operation contract. After exact source/index freeze and fresh readback, preserve the complete cohort in the approved encrypted engine, run a full stored-data integrity check, then have an independent reader restore the exact snapshot to a **fresh private outside-checkout target**. Compare all 98 paths, whole-file hashes, sizes, modes and required metadata. Default structural checks do not replace full data reads. [Official integrity check](https://restic.readthedocs.io/en/stable/045_working_with_repos.html#checking-integrity-and-consistency), [Official restore procedure](https://restic.readthedocs.io/en/stable/050_restore.html)

The future verifier must demonstrate rejection of a missing/wrong object, changed source, wrong repository/snapshot, tampered payload/index, traversal and symlink alias using isolated test fixtures. Bind the restore receipt to the repository/snapshot/catalog/tool identities, verify second-copy/key recovery, and resolve every original index/command/fixture link. A source reread is not an archive restore; the existing **98/98** check therefore confers no restoration acceptance.

Run the Firebase probe and the recorded full original/current source compile with **new caches** from the preserved pinned source/SDK/header closure. Then prove a fresh isolated source export and affected/full required tests with the archive absent, no symlink/global mount and no hidden historical-output fallback. Promote required synthetic fixtures/helpers under separate assigned ownership where necessary; public contracts can remain concise in-repo evidence. Root must review those results and assign exact removal ownership. Remove only still-matching manifest-listed originals, record actual before/after file/class/byte counts, and prove all affected archive resolutions after removal. No command to remove originals is supplied or executed here.

## Remaining acceptance gaps

* No archive engine/repository or independent archive restore has been established.
* No originals have been removed; there are no genuine before/after cleanup counts or physical savings.
* Customer/secret sensitivity, owner/group/ACL/xattr metadata, permitted access/transfer, class retention/holds, key recovery and separate-copy availability remain unverified.
* The durable immutable relocation resolver and original-index reconciliation have not been implemented or executed.
* Required fixture/helper promotion and a clean build/test run with the archive absent remain unproved.
* Arbitrary computed/unnamed/deep copied-source links and independent post-census changes require fresh scoped review before any removal.

The completed outcome is a verified read-only inventory, bounded byte-identity review, critical consumer map and concrete preservation-first recommendation. The original ARC-10 acceptance remains **open** until actual preservation, restoration, link resolution, isolated verification and approved exact removal evidence exist.
