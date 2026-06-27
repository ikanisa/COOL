# Borrowed Revolut Brand Kit

Place only approved or repo-approved Revolut-like borrowed brand assets in this directory.

Expected runtime inputs:

- `logos/wordmark.png` for `CollectBrandMark`.
- `app_icons/app_icon.png` for Flutter app-icon surfaces.
- `app_icons/web-512.png` for web manifest/favicon replacement.
- `splash/splash_mark.png` and `splash/splash_background.png` for launch surfaces.
- `media/share-preview.png` for public and share-preview surfaces.
- `icons/` for the approved icon set or mapping assets.
- `media/` for Revolut-like product/media imagery.

The four Collect primary colors remain preserved as the only distinct palette:
`#8885F0`, `#3CD070`, `#D38B96`, and `#FF5E43`.

Current status: installed. `RevolutBorrowedAssets` now routes runtime brand
surfaces through the expected paths in this directory. See `PROVENANCE.md` for
source and replacement rules.
