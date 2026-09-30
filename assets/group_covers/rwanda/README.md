# Collect Rwanda group-cover bank

The current `catalog.v1.json` and runtime records contain **42 active concepts**.
The identifiers are intentionally retained; no concepts are added or renumbered to
make the historical count of 44 appear correct.

## Runtime inventory

There are **42 WebP covers** (768 × 1024 pixels) and **42 WebP thumbnails**
(192 × 256 pixels), for **84 runtime images totaling 4,488,758 bytes**.
Covers total 4,077,622 bytes; thumbnails total 411,136 bytes. On 26 September 2026,
all 84 original Drive files were downloaded, decoded and compared with their
recorded sizes, dimensions and SHA-256 hashes in the runtime and approval manifests.
This is integrity evidence, not native UI, crop, cultural or visual acceptance.
The prior 4,651,698-byte summary was stale; correcting it is not compression or a
bundle-size reduction. Per-image records and approved hashes were preserved.

The originals are in `source/` and their provenance records are in `production/`.
The catalog lists 42 current source references and six superseded wedding versions;
these PNG bytes were not checked in this runtime-only verification. Full-resolution
originals, prompts and research remain separate from the bundled covers and thumbs.

The [production and integration plan](../../../docs/plans/rwanda-group-asset-bank-2026-09-06/README.md)
and [promptbook](../../../docs/plans/rwanda-group-asset-bank-2026-09-06/production/PROMPTBOOK.md)
provide concept and generation context. Dedicated Buri munsi and Gikundiro images
remain outside generic suggestions and defaults. Six wedding concepts use version 2.
The catalog and its review statuses are unchanged; local cultural/language review,
final crop approval, native acceptance and application distribution are separate gates.

## Read-only runtime check

From a complete checkout containing the catalog, runtime images and approval manifest:

```bash
ruby scripts/qa/group_runtime_integrity.rb --root . --json
```

This command checks catalog/manifest consistency, both runtime directories, sizes
and hashes. It checks that dimension metadata is positive but does not decode images.
The separate delivery evidence records the full image decode and actual dimension
checks performed on 26 September 2026. It does not verify other approved assets.

The review gallery remains a review tool, not the member app; its launcher is
`python3 scripts/assets/serve_rwanda_group_bank.py --port 4194`. The existing bank
helper is `python3 scripts/assets/rwanda_group_asset_bank.py validate`.

`revolut-design` is the sole design authority. This catalog and integrity report
create no group types, financial capabilities, new approvals or release acceptance.
