## Deep Link Site

This folder is the hostable fallback site for `https://cool.app`.

Expected behavior:

- If the app is installed, `https://cool.app/basket` and `https://cool.app/invite/<CODE>` should open the app directly.
- If the app is not installed, the site attempts `cool://...` first, then redirects to Google Play or the App Store.

Files:

- `index.html`: primary landing page with store redirect logic
- `404.html`: fallback page for hosts that serve a custom 404 for unknown routes
- `_redirects`: Netlify-style rewrite so all paths resolve to `index.html`
- `.well-known/assetlinks.json`: Android app-links association file
- `.well-known/apple-app-site-association`: iOS universal-links association file
- `assets/store-links.js`: generated store URL config consumed by the fallback site
- `../release_metadata.json`: source-of-truth metadata for association hosts, paths, package ids, and store identifiers

Regenerate the checked-in association files whenever release metadata changes:

```bash
dart tool/deep_link_release_assets.dart --generate
```

Release validation:

```bash
dart tool/deep_link_release_assets.dart --check
```

That check must pass before a release candidate is considered ready.

Current production blockers:

- populate `android.playAppSigningSha256CertFingerprint` in `deeplinks/release_metadata.json`
- populate `ios.teamId` in `deeplinks/release_metadata.json`
- populate `ios.appStoreId` in `deeplinks/release_metadata.json`
- rerun `dart tool/deep_link_release_assets.dart --generate`

Current app identifiers already wired in this repo:

- Android package id: `app.cool.mobile`
- iOS bundle id: `app.cool.mobile`

Still required from external console access:

- Apple Team ID plus populated AASA app details for the production app
- Google Play App Signing SHA-256 fingerprint
- final App Store listing ID
