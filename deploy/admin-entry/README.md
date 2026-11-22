# Legacy Collect Admin entry

The `collect-admin` Worker hands the original and former preview browser addresses to Collect’s React Admin at `https://platform-admin.collect.ikanisa.com`. The former Admin16 security-stage browser address goes to the qualification deployment of the same React application at `https://admin-supabase-qa.collect.ikanisa.com`. Each destination owns its sign-in, permissions and application requests. This entry has no asset, service, email or data bindings.

The standalone Cloudflare Pages project at `cool-admin-212.pages.dev` uses [the Pages entrypoint](pages/entry.mjs) to open the same production console.

## Browser handoff

GET and HEAD document requests for `/`, `/index.html`, `/admin` and `/admin/*` receive the small original-origin handoff document. It reads the browser’s complete address, including the fragment. It opens a clean path or hash bookmark through React’s hash router, keeping the route’s encoded query. Ordinary requests for other origins, subresources, API-like paths and writes are denied by this Worker.

A legacy cookie, browser history state, an active controller, existing web storage, cache or discoverable IndexedDB database, unavailable storage or an ambiguous address keeps the original tab open. Version 41 could cache private same-origin GETs. The handoff checks for the presence of a cache without opening any stored response. A separate-tab link starts React with its own account. If the fragment and the path identify different Admin tasks, both choices are available. If the fragment is only a section marker, the original address stays intact and the compatible task can be opened separately. Credentials issued by the old host and keys for old pending requests stay there. The handoff never reads stored values, transfers a session, submits an action or assigns a replacement request ID. The static separate-tab link also works with JavaScript disabled.

The exact `/custom-sw.js`, `/flutter_service_worker.js` and `/admin-shell-sw.js` URLs serve JavaScript on their original origin, including requests with a version query. The replacement waits for controlled tabs and unregisters on natural activation. Old tabs can keep their in-memory work. Closing a tab can lose its in-memory form or same-tab storage. Keep it open while recovering earlier work and use its original identity and authoritative request status before retrying. Offline clients can continue running their already-installed bundle. An installation under the immutable workers.dev hostname has its own browser origin. Disabling that version URL withdraws future network delivery; a cached copy there cannot receive the custom domains’ replacement worker.

## Preview routing and rollback

The custom domains and providers on 20 November 2026 were verified before this candidate. Use current provider readback to establish the preimage for any traffic change.

| Address | Existing Worker | Existing custom-domain ID |
| --- | --- | --- |
| `admin.collect.ikanisa.com` | `collect-admin` | `c14ccadca041ce108f86bfa9343a17c862e0cac1` |
| `admin-preview.collect.ikanisa.com` | `collect-admin-cloudflare` | `3ab2d2558839aa529912d0677296663edca566aa` |
| `admin16-security-stage.collect.ikanisa.com` | `collect-admin16-security-stage-20261016` | `b8abed652e70cda2ba582ae5193751bc9d44d0cd` |

The security-stage Worker accepts only its own origin and forwards `/api/admin/*` to its existing `collect-api16-security-stage-20261016` service. Its deployed module returns 404 for every other `/api` path. Its regular and version workers.dev URLs were disabled and its schedule was empty. V5 was `88fc6555-3b79-44f4-8d2e-fea97e8d2676`, preceded by v4 `4b9e6daf-6615-4304-b3fd-bc9815d7a6d9`. Its published service worker enumerates 150 path/digest pairs.

The former preview has a separate custom-domain owner and a confirmed every-minute UTC cron. Its deployed version 7 module dispatches the email outbox and expires D1 sessions, rate limits and old challenges. The preview’s regular workers.dev address and version previews were disabled. The original entry’s regular workers.dev address returned 403, while its enabled immutable version 41 URL served Flutter publicly. This candidate disables version previews on the original Worker and keeps its regular alias bound to the existing origin denial.

1. Record the current custom domains, zone routes, deployments, original Worker subdomain settings and preview schedule. Save exact immutable versions and public recovery artifacts.
2. Preserve the three existing preview backend paths and the security-stage `/api/admin/*` path with the unbound zone routes in [preview-backend-routes.json](preview-backend-routes.json). The Worker Routes API creates an unbound route with the `script` field omitted. Confirm each exact pattern has no assigned Worker. Each existing custom-domain Worker continues serving its own requests. Its bare gateway heartbeat accepts an empty query only.
3. The two candidate front routes `admin-preview.collect.ikanisa.com/*` and `admin16-security-stage.collect.ikanisa.com/*` on `collect-admin` can then take the remaining browser traffic. The four more-specific patterns take precedence. Keep both existing custom-domain Workers, versions, service/data bindings and schedules. Verify all three old browser origins, both destination environments, the backend ownership, the original immutable preview’s withdrawal and the retained cron before accepting the transition. [Cloudflare route matching](https://developers.cloudflare.com/workers/configuration/routing/routes/) · [Cloudflare cron triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/)
4. To reverse this change, remove the newly created broad route on each affected host first. Confirm each underlying custom domain again serves its previous version. Then remove only the corresponding new unbound route IDs. Restore the original entry’s recorded version and Worker preview setting if that reversal is authorized. Server rollback cannot reconstruct browser state that a user has already closed or cleared.

Current-source and installed-state evidence are separate. Original entry v42 was `ef67525c-163c-4929-a288-3409c7e5abf3`. V41 was `2dce5a15-6902-40ee-96eb-added7ae52f8`. The v41 public build identifies clean revision `f0b8b37a0e5c7e97a222127924fb3a7942e74ed2`. Its distributed worker enumerates 151 public cache URLs. The recovery copy includes those and both root service-worker scripts. Preview v7 was `780ee26c-2301-451e-be8a-39e7b359b57a`, preceded by v6 `6ec67d36-2093-4cb0-a1f7-1b0e983dd144`. The separate October 16 retained build registers `admin-shell-sw.js`. The public preview v7 bootstrap has a different main bundle and an inert custom-worker version placeholder. [Provider deployment history](../../docs/implementation/2026-11-20-admin-provider-deployments.json) · [Public host evidence](../../docs/implementation/2026-11-20-public-admin-hosts.json)

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

The dedicated Chromium checks take production- and qualification-origin React builds with their adjacent receipts, or a retained predecessor directory. Set `CHROME_PATH` to a local Chromium executable when needed. The React test fulfills all network requests inside the browser and exercises anonymous, permitted and denied routes with synthetic accounts. The service-worker test uses a loopback server, two controlled tabs and a synthetic open editor.

```sh
node deploy/admin-entry/test/browser.mjs "$REACT_ADMIN_PACKAGE" "$REACT_ADMIN_QA_PACKAGE"
node deploy/admin-entry/test/worker-lifecycle.mjs "$ORIGINAL_V41_RESTORE" "$ORIGINAL_V41_RECEIPT"
node deploy/admin-entry/test/worker-lifecycle.mjs "$ARCHIVED_PREVIEW_SHELL"
node deploy/admin-entry/test/worker-lifecycle.mjs "$SECURITY_STAGE_RESTORE" "$SECURITY_STAGE_RECEIPT"
```
