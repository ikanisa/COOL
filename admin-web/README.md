# Collect React Admin

This package owns the Collect browser Admin, including its routes, permissions
presentation, and installable app shell. The Supabase Admin API owns session
admission, permissions and writes. BuriMunsi Staff and Admin Sync ship from
`native/burimunsi/`.

## Build and verify

Run from the repository root with Node 24.19.0, npm and Python 3.

```sh
npm ci --prefix admin-web
npm --prefix admin-web run typecheck
npm --prefix admin-web run lint
npm --prefix admin-web test
bash scripts/admin_pwa_release_build.sh --fixture
make admin-pwa-smoke
```

The fixture build writes `build/admin-web-fixture/` and uses
`http://127.0.0.1:4175` by default. The browser check uses the compiled package,
local synthetic sessions and the locked Playwright Core package. To use its
matching Chromium, run `admin-web/node_modules/.bin/playwright-core install --no-shell chromium`.
The smoke test can also use an installed Chrome via `ADMIN_PWA_CHROME`. CI runs
the compiled entry, receipt read recovery, browser Back and service-worker checks
before building the release profile.

## Build a managed release

`make admin-web-build` uses the selected public Supabase configuration. Supply
`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, the approved origins and the intended
CAPTCHA and Google settings. The validator accepts an explicit canonical
deployment profile and digest for the nominated Supabase Cloud project. The backend
serves the same-origin CAPTCHA document and applies its own security policy.
The Vite compiler receives only the validated public client values.

The release site is `build/admin-web/` with its paired `build/admin-web.json`
source and SHA-256 receipt outside the served directory. Use a fresh location
with `ADMIN_PWA_BUILD_DIR` for a subsequent build. The qualification profile
uses `build/admin-web-qualification/` through `--qualification`.

- `make admin-pwa-gate` checks the paired artifact and current source identity.
- `make admin-pwa-hosting-gate` also requires a reviewed Supabase target and
  checks the package's static headers and robots policy.
- `make admin-pwa-live-gate` compares the deployed static files and headers
  with the local React build. Hosting, role, payment and device acceptance
  still require separate evidence.

## Preserve pending work during an installed update

Finish or explicitly discard unsaved form edits in their current tabs. When a
new worker is waiting, enter `about:blank` in each open Admin tab. After the
last tab has left Admin, return online to Admin in those same tabs. Closing a
tab can discard its pending request references. Keep an installed window open
if it has pending work and offers no browser address bar.

Production moves from the self-hosted service to managed Supabase. React keeps
earlier per-tab requests, SMS management references, MFA, logout and privacy
review records in their original storage. Reconcile those original requests
against the previous service before submitting the work again. Production
React uses new managed storage keys even if an account and session appear
identical. QA continues to use its existing managed service and compatible keys.

To check an actual package with synthetic browser data, supply its matching
captured release index and restored static blobs. Use a new output file for
each run. Chromium resolves the two named Admin hosts only to loopback during
this check. Install the matching Playwright Chromium or set `ADMIN_PWA_CHROME`.

```sh
node admin-web/tests/browser/predecessor-transition.mjs production "$predecessors" "$production_site" "$production_result"
node admin-web/tests/browser/predecessor-transition.mjs qa "$predecessors" "$qa_site" "$qa_result"
```

The [Admin host](../deploy/platform-admin/README.md) serves the same build and
routes `/api/admin/**` to the approved Supabase project.
