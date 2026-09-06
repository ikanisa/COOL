# Collect Rwanda group-cover bank

This folder contains **44 active generated PNG photographs**, the 44-concept catalogue and a provenance record for every original. Each image is 1086 × 1448 pixels. The active set totals 98,796,942 bytes. Six previous wedding versions are preserved, making 50 source PNGs in total (113,087,135 bytes). Runtime readiness remains false.

The [production and integration plan](../../../docs/plans/rwanda-group-asset-bank-2026-09-06/README.md) explains the cultural context, picker journey, filtering and durable save work. The [44 standalone prompts](../../../docs/plans/rwanda-group-asset-bank-2026-09-06/production/PROMPTBOOK.md) are exported from catalog.v1.json.

The originals are in source/ and their provenance records are in production/. Versioned WebP covers in covers/ and thumbnails in thumbs/ are built: 88 derivatives total 4,651,698 bytes, with hashes and dimensions in runtime-manifest.json. pubspec.yaml bundles the cover and thumbnail folders; a generated Dart index supplies runtime metadata. Full-resolution originals, prompts and research are excluded from the bundle.

Open the [local review gallery](http://collect.localhost:4194/) to browse the saved images by group type, theme, search and explicit context. It previews tall, square, circular and landscape crops without changing source pixels. Start it with python3 scripts/assets/serve_rwanda_group_bank.py --port 4194. This gallery is a review tool, not the member app.

Dedicated Buri munsi and Gikundiro images are kept out of generic suggestions and defaults. The gallery has direct buttons to inspect them. All six wedding concepts use refreshed, vibrant version 2 images.

See [generation status and review work](../../../docs/plans/rwanda-group-asset-bank-2026-09-06/production/GENERATION-STATUS.md). All 44 current outputs received an initial scene inspection. Local cultural/language review, final crop approval, full native acceptance and application distribution remain pending. The shared picker is implemented locally and the atomic creation-media RPC is deployed with verified database readback; see [integration status](../../../docs/plans/rwanda-group-asset-bank-2026-09-06/INTEGRATION-STATUS.md).

Run python3 scripts/assets/rwanda_group_asset_bank.py validate or export from the repository root. The helper uses no paid API and makes no network calls. Built-in image generation runs once per exported job; save-source stores a returned PNG without overwriting an existing file.

The existing marketing assets remain separate. DESIGN.md remains the sole design authority. This catalogue creates no group types, financial capabilities, user approvals or production acceptance.
