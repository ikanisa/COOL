# Legacy Collect Admin entry

The `collect-admin` Worker hands the original and former preview browser addresses to Collect’s React Admin at `https://platform-admin.collect.ikanisa.com`. The former Admin16 security-stage browser address goes to the qualification deployment of the same React application at `https://admin-supabase-qa.collect.ikanisa.com`. Each destination owns its sign-in, permissions and application requests. This entry has no asset, service, email or data bindings.

The standalone Cloudflare Pages project at `cool-admin-212.pages.dev` uses [the Pages entrypoint](pages/entry.mjs) to open the same production console.

## Browser handoff

GET and HEAD document requests for `/`, `/index.html`, `/admin` and `/admin/*` receive the small original-origin handoff document. It reads the browser’s complete address, including the fragment. It opens a clean path or hash bookmark through React’s hash router, keeping the route’s encoded query. Ordinary requests for other origins, subresources, API-like paths and writes are denied by this Worker.

A legacy cookie, browser history state, an active controller, existing web storage, cache or discoverable IndexedDB database, unavailable storage or an ambiguous address keeps the original tab open. The handoff checks for the presence of a cache without opening any stored response. A separate-tab link starts React with its own account. If the fragment and the path identify different Admin tasks, both choices are available. If the fragment is only a section marker, the original address stays intact and the compatible task can be opened separately. Credentials issued by the old host and keys for old pending requests stay there. The handoff never reads stored values, transfers a session, submits an action or assigns a replacement request ID. The static separate-tab link also works with JavaScript disabled.

The exact `/custom-sw.js`, `/flutter_service_worker.js` and `/admin-shell-sw.js` URLs serve JavaScript on their original origin, including requests with a version query. The replacement waits for controlled tabs and unregisters on natural activation. Old tabs can keep their in-memory work. Closing a tab can lose its in-memory form or same-tab storage. Keep it open while recovering earlier work and use its original identity and authoritative request status before retrying. Offline clients can continue running their already-installed bundle. An installation under the immutable workers.dev hostname has its own browser origin. Disabling that version URL withdraws future network delivery; a cached copy there cannot receive the custom domains’ replacement worker.

## Preview routes

The four backend patterns in [preview-backend-routes.json](preview-backend-routes.json) keep the existing preview and qualification API owners in place. The broader routes on those hosts serve the React handoff. The preview backend also owns its scheduled jobs. Record the current domain owners, routes and schedules before changing them. Verify the handoff and each retained backend route after the change.

## Local verification

Run the route, storage-preservation and lifecycle contracts from the repository root.

```sh
node --test scripts/tests/admin_entry_test.mjs deploy/admin-entry/pages/test.mjs
```

The dedicated Chromium checks take production- and qualification-origin React builds with their adjacent receipts, or a retained predecessor directory. Set `CHROME_PATH` to a local Chromium executable when needed. The React test fulfills all network requests inside the browser and exercises anonymous, permitted and denied routes with synthetic accounts. The service-worker test uses a loopback server, two controlled tabs and a synthetic open editor.

```sh
node deploy/admin-entry/test/browser.mjs "$REACT_ADMIN_PACKAGE" "$REACT_ADMIN_QA_PACKAGE"
node deploy/admin-entry/test/worker-lifecycle.mjs "$ORIGINAL_V41_RESTORE" "$ORIGINAL_V41_RECEIPT"
node deploy/admin-entry/test/worker-lifecycle.mjs "$ARCHIVED_PREVIEW_SHELL"
node deploy/admin-entry/test/worker-lifecycle.mjs "$SECURITY_STAGE_RESTORE" "$SECURITY_STAGE_RECEIPT"
```
