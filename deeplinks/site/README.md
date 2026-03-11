## Deep Link Site

This folder is the hostable fallback site for `https://cool.app`.

Expected behavior:

- If the app is installed, `https://cool.app/basket` and `https://cool.app/invite/<CODE>` should open the app directly.
- If the app is not installed, the site attempts `cool://...` first, then redirects to Google Play or the App Store.

Files:

- `index.html`: primary landing page with store redirect logic
- `404.html`: fallback page for hosts that serve a custom 404 for unknown routes
- `_redirects`: Netlify-style rewrite so all paths resolve to `index.html`
- `.well-known/assetlinks.json`: Android app-links association template
- `.well-known/apple-app-site-association`: iOS universal-links association template

Before production deployment, replace these placeholders:

- `com.example.cool_app` with the real Android package id
- `com.example.coolApp` with the real iOS bundle id
- `TEAMID` in `apple-app-site-association` with the real Apple Team ID
- `REPLACE_WITH_RELEASE_SHA256_FINGERPRINT` in `assetlinks.json` with the release signing fingerprint
- `id0000000000` in the App Store URL with the real App Store listing ID
