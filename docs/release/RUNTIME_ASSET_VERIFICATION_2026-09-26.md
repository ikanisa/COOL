# Runtime asset verification — 26 September 2026

## Correction and scope

The actual catalog and runtime records identify 42 concepts, not the stale runtime
header's 44. The 84 derivative records total 4,488,758 bytes, not 4,651,698. Only
those two summary fields are corrected in the runtime manifest. Every record,
source reference, version, per-image size/dimension/hash and review string is
unchanged. The approval manifest and catalog are unchanged. No image is rewritten,
removed or regenerated. The 162,940-byte difference is a reporting correction,
not an image optimization or bundle-size reduction.

All 84 original Drive WebPs were downloaded and checked byte-for-byte against the
recorded hashes, their byte sizes and dimensions, with a successful full decoder
load of each image. Covers are 768 × 1024; thumbnails are 192 × 256. The source
PNGs and other platform/marketing assets were not downloaded or byte-verified.
This verifies 84 of 174 approved asset paths, not the complete approval inventory.
Source-hash references for 42 active concepts match approval metadata only.

## Implementation

`group_runtime_integrity.rb` verifies the catalog/runtime concept set, versions,
canonical paths, paired cover/thumbnail roles, aggregate counts and totals,
approval references, directory inventory and actual runtime hashes/sizes. It
rejects duplicate JSON keys/IDs, invalid numeric fields, malformed or oversized
input, unexpected visual assets and nonregular entries. Its filesystem reads use
the existing manifest-integrity helper. No approvals are written or inferred.
It ignores regular nonvisual directory metadata, but does not silently traverse
nested directories. It assumes a trusted, quiescent checkout; it is not a sandbox
against hard-link aliases or concurrent parent-directory substitution.

The command has no network or write behavior. It does not decode images or prove
visual quality. CI runs the new unit suite and the real runtime consistency check,
then retains the existing wider hygiene and application checks.

```bash
ruby scripts/tests/group_runtime_integrity_test.rb
ruby scripts/qa/group_runtime_integrity.rb --root . --json
```

Exit codes are 0 for the scoped integrity pass, 1 for invalid or inconsistent
inputs, and 2 for blocked execution. A pass does not establish full repository
integrity, native compatibility, visual approval, or release readiness.

## Application boundary

The cumulative delivery is a partial source overlay. Apply its hash-checked
installer only to an authorized full checkout matching Increment 07 plus the
inspected bank README and runtime manifest. Keep backups and stop on conflicts.
The catalog, approved hash list and runtime assets must already exist. Uploading
an overlay to the delivery folder does not apply it to the original repository.
No Flutter application execution, payment/ledger change, migration, live Supabase
setting change or deployment is part of this increment. `revolut-design` remains
the sole design authority. See the delivery receipt for actual filing outcomes.
