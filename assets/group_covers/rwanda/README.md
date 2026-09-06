# Collect Rwanda group-cover bank

This folder currently contains a **40-concept production catalogue**, not generated image files. All concepts are prompt-ready and runtime readiness is false.

The [production and integration plan](../../../docs/plans/rwanda-group-asset-bank-2026-09-06/README.md) explains the cultural context, picker journey, filtering and durable save work. The [40 standalone prompts](../../../docs/plans/rwanda-group-asset-bank-2026-09-06/production/PROMPTBOOK.md) are exported from catalog.v1.json.

Future generated originals belong in source/, reviewed app covers in covers/, thumbnails in thumbs/, and provenance/review records in production/. These are planned paths; no placeholder photos are created to represent unfinished work. Runtime bundling must explicitly include only approved derivatives and a small runtime index.

Run python3 scripts/assets/rwanda_group_asset_bank.py validate or export from the repository root. The helper uses no paid API and makes no network calls. Built-in image generation runs once per exported job; save-source stores a returned PNG without overwriting an existing file.

The existing marketing assets remain separate. DESIGN.md remains the sole design authority. This catalogue creates no group types, financial capabilities, user approvals or production acceptance.
