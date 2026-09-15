# Collect Admin PWA lifecycle checkpoint

15 September 2026, Africa/Kigali. Execution timestamps are UTC on 14 September.
**Three service-worker defects are repaired locally. The final lifecycle run
has 19 passing checks and one failing installed-offline check; its result
remains failed. The full P0–P8 goal remains active.**

The current worker was packaged around the previously verified, synthetic
Admin build. All 413 application inputs and 154 original artifact files still
match their hashes. No Supabase client or provider is configured in that build.
This continuation tested Chromium's actual service-worker and installation
behavior, including a separate Chrome process restart. It did not rebuild or
deploy the production application.

## Reproduced defects and local repairs

| Finding | Reproduction | Repair and current evidence |
| --- | --- | --- |
| FQA-037: unusable navigation fallback | The worker cached `/` but looked for the deliberately excluded `/index.html` when an unvisited pathname was opened during an outage. The browser navigation failed. | Navigation reads the installed root shell from its specific cache. The unvisited-path fallback passes. Normal hash-route cold launch passed before and after; this finding concerns the fallback path. |
| FQA-038: shell-only updates remain stale | Changing only the packaged HTML produced identical cache names and worker bytes. A new navigation still read the previous shell. | The cache version includes the final HTML, asset paths/content and worker-template bytes. The updated shell is served after actual controller replacement, and the previous cache is retired. |
| FQA-039: non-asset responses enter the app cache | A synthetic same-origin endpoint returned `Cache-Control: no-store`. Its first actor response was cached and returned after the server switched actors. | Only declared static build assets and the app shell use the worker cache. Both response freshness and absence from Cache Storage pass. No production account-data exposure is asserted. |

The corrected baseline contains 12 checks and seven failures across those
three causes. Current corresponding checks pass in real Chromium. The worker
also removes a partial new cache when installation fails. An injected HTTP
503 during precaching leaves the previous controller and offline shell usable.
No application draft save, financial write or server authorization is inferred
from these shell tests.

The worker implementation now lives in
[admin_pwa_service_worker.js](../../../scripts/templates/admin_pwa_service_worker.js).
The production build script inserts the version and asset list from that
template. The manifest gate verifies the root-shell and static-asset cache
boundary. Target identity, routes, visual tokens and payment behavior were not
changed. The browser probe executes the actual Ruby packaging block inside
isolated staging directories; it does not maintain a separate worker implementation.

Serving the cached shell for navigation follows Chrome's documented
[application-shell model](https://developer.chrome.com/docs/workbox/app-shell-model).
The live application still requires its own authenticated backend evidence.

## Installed evidence and the unresolved check

The installed tests used macOS 26.6.2 and Chrome 152.0.7977.84, an empty,
task-created Chrome profile, and a loopback-only synthetic application. The
probe installed the PWA through CDP and explicitly selected the standalone
user preference. This is an actual installation and app window; the browser
display mode was not emulated with CSS.

The launch command returns a tab target above the page target, as reflected
in the primary [Puppeteer implementation](https://github.com/puppeteer/puppeteer/blob/main/packages/puppeteer-core/src/cdp/Browser.ts).
The probe binds the returned target to its actual browser window and page,
then checks computed standalone mode and rendered Admin workspace semantics.
The initial helper-tab and direct-ID attempts remain failed evidence.

Current verified installed observations are:

- Installation is present in Chrome's app registry and a matching standalone
  app window renders the synthetic Admin workspace.
- After closing Chrome completely, the installed app launches and renders the
  cached current shell while the local server destroys every request. A fresh
  non-asset request fails, verifying that the origin is unreachable.
- After reconnecting, a fresh synthetic actor response and the current shell
  are available.
- Every test installation was removed and removal was read back before its
  task-created profile was deleted.

**FQA-040 remains open.** In the final attempt, explicit network emulation and
`Network.overrideNetworkState` make `navigator.onLine` false before reload.
After the installed window reloads, the value is true again. The shell still
loads from its controlled cache, but the required emulation assertion fails.
Refreshing the automation context did not resolve it. The root cause remains
under investigation between the browser instrumentation and runtime; this is
not a demonstrated failure of Collect on a physically offline device.

The probe uses the separate network-rule and navigator-state controls in
the [current CDP Network API](https://github.com/ChromeDevTools/devtools-protocol/blob/master/pdl/domains/Network.pdl).
Cold launch with an unreachable application origin, precise offline emulation
across reload, and device-wide offline state before startup remain distinct
claims. The first has evidence; the latter two are not accepted here. The
Make target returns a failure rather than masking the unresolved check.

## Regression, source and evidence

Raw evidence: `.cache/fullstack-qa/20260914T151002Z/pwa-continuation/`.

| Evidence | Result |
| --- | --- |
| `before-corrected/report.json` | 12 checks, seven reproduced failures; source and original build unchanged |
| `after-controller-wait/report.json` | 12 worker checks pass; early captures checked only the Flutter container and do not prove completed rendering |
| `installed/report.json` | 15 browser checks pass, including failed-update recovery; installed mode was not enabled in this attempt |
| `final-context-refresh/report.json` | 20 checks, 19 pass, installed-target offline reload fails; current source bound and cleanup verified |
| `final-checks/flutter-focused.json` | 87 Flutter tests pass, zero failures or skips |
| `final-checks/tooling.json` | 132 Ruby tests / 663 assertions and nine Python tests pass |
| `final-checks/analysis.json`, `format.json`, `source-hygiene.json` | Analysis, changed-Dart formatting and repository source hygiene pass |
| `final-checks/pwa-manifest.json`, `pwa-hosting.json` | Packaged fixture manifest and hosting-file gates pass; not a live deployment check |
| `final-checks/android-design.json`, `ios-design.json` | Both mandatory native gates remain blocked |
| `source-checkpoint.json` | Current packaging/worker hashes, fixture continuity, preserved settings and acceptance verified |
| `profile-cleanup-first.json`, `profile-cleanup-final.json` | Six owned synthetic profiles removed after verified uninstall and process exit; builds and evidence retained |

All 527 recorded inputs remained unchanged during the framework checks.
The final lifecycle context-refresh instrumentation was added afterward and
executed in the final 20-case attempt. Production worker/packaging code and
Flutter test source remain unchanged from the passing regression. The
previous full Flutter run retains 867 passes and 74.65% measured line coverage;
611 of its 615 inputs are unchanged. CI, Makefile and the two expanded test
files differ. No new full-suite run or coverage measurement is claimed.

Failed attempts are retained, including an incorrect Flutter DOM selector,
an insufficient activation wait, helper-tab selection, tab/page target-ID
confusion and the offline-state failures. Earlier captures that are blank or
only show a mounted container cannot establish rendered acceptance. The final
probe waits for both the synthetic fixture marker and Admin workspace semantics.
The final installed screenshot was inspected and shows the Groups workspace.
No visual fidelity score or independent/owner acceptance was created.

Reproduction uses the new `admin-pwa-lifecycle-qa` target with
`ADMIN_PWA_FIXTURE_REPORT`, a new `ADMIN_PWA_LIFECYCLE_EVIDENCE` directory and
`ADMIN_PWA_LIFECYCLE_MODE=browser` or `installed`. Set `PLAYWRIGHT_CORE_PATH` to
the installed module. The build report must describe a current, verified,
backend-free synthetic build. Stale inputs and reused evidence directories
are rejected. The current installed run is expected to return nonzero while
FQA-040 remains unresolved.

## Remaining full-plan work

Complete installed offline control verification, actual session/logout/account
switch behavior, operator drafts/actions, quotas, reader tasks, update
compatibility and the remaining supported platform/browser matrix. A synthetic
actor endpoint does not establish production session or storage isolation.
Manual installation affordances and device-wide offline startup also remain open.
Member browser availability, the other Admin tasks, native/device/provider work,
performance/recovery and visual acceptance continue under [PLAN.md](PLAN.md).

Native capacity remains unresolved. Source, media, signed-in device data and
production access controls are preserved. No production deployment, migration,
external message, store publication or release approval occurred.
