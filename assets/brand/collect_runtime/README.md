# Collect Runtime Brand Kit

This directory keeps the stable runtime asset paths used by the mobile app,
Admin PWA, splash screens, web manifest, and public-share surfaces. The current
source of truth is Collect-owned artwork under `assets/brand/generated/` and
`assets/brand/source_variants/`.

Expected runtime inputs:

- `logos/wordmark.png` for `CollectBrandMark`.
- `app_icons/app_icon.png` for Flutter app-icon surfaces.
- `app_icons/collect-web-512.png` for web manifest/favicon replacement.
- `splash/splash_mark.png` and `splash/splash_background.png` for launch surfaces.
- `media/share-preview.png` for public and share-preview surfaces.
- `icons/` for the approved icon set or mapping assets.
- `media/` for Revolut-like product/media imagery.

The four Collect primary colors remain preserved:
`#8885F0`, `#3CD070`, `#D38B96`, and `#FF5E43`.

Current status: installed and Collect-owned. `CollectRuntimeAssets` keeps the
legacy class name and routes runtime brand surfaces through these stable paths
to avoid broad app churn. See `PROVENANCE.md` for source and replacement rules.
