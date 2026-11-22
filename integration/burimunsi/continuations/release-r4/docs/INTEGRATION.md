# r4 integration decisions and entrypoints

## Exact scope and preimages

`integration/merge-ledger.json` pins the two original source archives and exact before/r2/r3/after bytes for every changed path. The tested baselines are M-Money 0.2.10 Build Security r1 and BuriMunsi canonical 0.19.0-canonical.1. They are not the final A03/A04 consolidated candidates. Eight M-Money paths and five BuriMunsi paths comprise this overlay.

The guard and adapter change from r3 in both products. `scripts/release_provenance.py` and `scripts/provenance_exchange.py` are new in both. Remaining r3 product hook/packager files are retained byte-for-byte. Authentication, financial authority, SMS behavior, storage policy and screens are not altered. Nonoverlay in-scope source paths are preserved. There is no automatic conflict resolution or workstream overwrite.

Use the fresh-output installer with default `--baseline original` or explicit `--baseline r2` / `--baseline r3`. Changed-path hashes must match before any output directory is created. The old checkouts are never modified. If output creation/copy is interrupted, keep it for inspection and retry to a new directory; an incomplete tree is not authoritative. The installer is not an atomic filesystem transaction.

The six provided patches correspond to original, r2 and r3 preimages, two products each. `verify_upgrades.py` verifies them and compares all four incremental upgrade inventories against direct installation. Inventory excludes fixed build/cache/VCS directories, as documented in `SECURITY_BOUNDARIES.md`; equivalence is within that source scope.

## Preserve combined application requirements

The adapter reads exact product identity from M-Money `app/build.gradle.kts` or BuriMunsi `release/canonical-integration-status.json`. Phase manifests default to `.release-evidence/<phase>/release-manifest.json`. Place `provenance.json` beside each application phase manifest. References within manifests remain relative to the phase directory.

Protected execution supplies an external absolute `RELEASE_TRUST_POLICY` and exact `RELEASE_TRUST_SHA256`. No usable values or trust roots are configured by this delivery. Missing configuration or provenance closes build/promotion even if all unsigned consistency fields match. The source phase does not authenticate producers and cannot authorize application building/promotion.

M-Money preserves its Gradle pre-release hook and CI hook before signing, plus its existing release CLI categories, stale-review and exact-artifact binding. The helper adapter offers only source/build phases; promotion must use the product release entrypoint, retaining the legacy acceptance policy:

```sh
python3 -B scripts/release_guard_adapter.py --phase build
python3 -B scripts/release_gate.py /work/legacy-release-evidence.json --artifact /work/exact-release.apk
```

BuriMunsi keeps its existing task-register and phase rules and adds the shared gate:

```sh
python3 -B native/burimunsi/scripts/release_readiness.py \
  --status release/task-status.json --evidence release/production-evidence.json --phase build
python3 -B native/burimunsi/scripts/release_readiness.py \
  --status release/task-status.json --evidence release/production-evidence.json --phase promotion
```

Both original acceptance records and exact artifact arguments are still hash-bound to the shared manifest. No task register was marked complete. Native task execution and hosted CI enforcement were not exercised here; wiring is tested statically and the local missing-evidence CLI paths are executed.

## Packaging continuity

M-Money retains r3's exact common source/evidence packager. Its old `source_files()` function remains for existing inventory consumers but no longer selects archive contents. Original native source checks run before shared publication. Unsupported legacy `--staging` and `--date` arguments fail explicitly; external consumers expecting product-prefixed metadata still require migration.

The archive layout is `source/`, `evidence/`, `PACKAGE-MANIFEST.json`. The packager checks collisions and exclusively creates outputs. Interruption between archive and sidecar publication can leave a retained archive without its checksum file; that incomplete delivery is not accepted or overwritten on retry. Use a new path after inspection.

Application full-source publication remains blocked on unresolved credential-like findings. Installing this overlay for analysis does not exempt those files from packaging scans. The historical input archives remain historical, not clean or production-designated r4 application deliverables.

r4 policy identity differs from r2/r3. Keep old records as history; do not timestamp-edit or relabel them as current. Product version strings stay at the tested application versions; the new guard version and current source digest identify the overlay change.
