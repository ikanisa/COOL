# Collect installed PWA offline investigation

15 September 2026, Africa/Kigali. This continues [PWA_CHECKPOINT.md](PWA_CHECKPOINT.md).
**Actual browser network blocking is verified before and after installed-app
reload. The browser's online-state flag still fails its separate check. The
expanded suite remains failed at 21 passing checks out of 22.**

The previous goal turn made progress by verifying and indexing the three
service-worker repairs. This continuation adds independent reproduction and
stronger runtime evidence. It changes the QA probe only; production worker,
packaging, application, assets and acceptance records were not changed.

## What the independent reproduction establishes

A minimal local HTML page uses the current Collect service-worker template,
a manifest and the existing public app icon. It contains no Flutter code,
authentication, customer data or provider configuration. The test uses an
owned Chrome profile and actual standalone installation on Chrome
152.0.7977.84, macOS 26.6.2, with Playwright 1.63.0.

The online-state problem reproduces in ordinary tabs and installed windows,
both before and after a fresh Chrome process starts. Context-level offline
emulation and direct CDP controls both report `navigator.onLine === false`
before reload, then `true` afterward. The defect therefore does not require
Flutter or an installed app window. The same page continues to display its
cached shell and fresh network requests fail.

The final minimal probe retains five failed indicator checks and adds five
separate network checks. All five network checks pass: every fresh request
fails with `net::ERR_INTERNET_DISCONNECTED` and the server receives none of
those requests. In the first three cases the origin is healthy; the two cold
restart cases also retain the explicitly declared origin-outage condition.
This diagnostic run has seven passes and five failures, including its two
shell/control observations. It is not an application acceptance run.

An [upstream Playwright issue](https://github.com/microsoft/playwright/issues/42174)
describes incorrect online state for newly created offline pages. In the
[associated closed proposal](https://github.com/microsoft/playwright/pull/42177),
a maintainer attributes the issue to Chromium and links a browser issue.
The browser issue itself was unavailable through the web tool, so its fix
status and affected versions are not asserted. These sources support the
environment diagnosis; our local evidence directly proves the reload symptom.
No library patch, downgrade, navigator-property override or fake offline event
was applied.

## Stronger checks on the actual Admin build

The existing lifecycle test retains all 20 earlier checks, including the
failing online-state assertion. Two new checks prove browser network blocking
before and after reload in the actual installed synthetic Admin build:

1. Restore the local origin after the separately tested cold-start outage.
2. Read a fresh synthetic response through the Node process, confirming the
   server is healthy and returns the expected synthetic actor.
3. Request a unique uncached URL from the installed browser window.
4. Require Chromium's `ERR_INTERNET_DISCONNECTED`, a failed browser fetch and
   no receipt of that probe at the server.
5. Repeat after reload, while also verifying the current cached shell,
   standalone window and service-worker control.

Both checks pass with a healthy origin. Reconnect then returns the fresh
expected response. This separates browser network emulation from server
outage and from the unreliable online-state flag. It does not establish
device-wide disconnection before process startup or real account/session
behavior. The original indicator failure remains visible as FQA-040, and the
Make target still returns nonzero.

## Evidence and continuity

Raw evidence: `.cache/fullstack-qa/20260914T151002Z/offline-investigation/`.

| Record | Result |
| --- | --- |
| `minimal-chrome-152/report.json` | Preserved harness failure: module import shape, zero runtime checks |
| `minimal-module-fixed/report.json` | Minimal page: two shell checks pass, five online-state checks fail |
| `minimal-network-proof/report.json` | Minimal page: seven passes, five retained online-state failures |
| `installed-network-proof/report.json` | Actual synthetic Admin installation: 21 passes, one retained indicator failure |
| `primary-source-notes.json` | Primary-source links, read limits and local inference |
| `source-checkpoint.json` | Source/artifact continuity, syntax check and preserved settings/acceptance |
| `profile-cleanup.json` | Three owned installations removed and verified; profiles deleted after process exit |
| `member-browser-discovery.json` | Bounded deployment/entrypoint source observations; runtime availability remains unverified |

All 413 application inputs and 154 original compiled fixture files still
match. The latest runtime probe binds its own current source and the actual
worker/build scripts. Node syntax and `git diff --check` pass. Of the 527
inputs in the preceding passing framework regression, only the lifecycle
probe now differs. Its new behavior ran in the current 22-case attempt.
The previous 87 Flutter, 132 Ruby and nine Python passes remain prior
regression evidence; they were not rerun solely for this probe change.

The earlier full Flutter result remains 867 passes and 74.65% measured line
coverage. Its continuity remains 611 unchanged inputs out of 615; CI,
Makefile and two expanded test files differ. No new full-suite result or
coverage measurement is claimed.

The original mobile acceptance file still contains zero accepted records.
Both mandatory platform gates remain blocked with 966 required cases each.
The user's settings hash is preserved. All three new test installations were
uninstalled with absence read back, then their owned profiles were removed
after process exit. Original build files, reports and screenshots remain.

## Remaining work

FQA-040 is now isolated to an emulated browser-state symptom with an upstream
Chromium attribution; it remains open. Actual physical offline startup,
readers, account/session/logout boundaries, drafts/actions, quota failures,
update compatibility and the supported browser/platform matrix remain open.
Source discovery identified separate public and Admin deployment manifests,
but does not establish whether a member browser service exists elsewhere.
Member availability and journeys therefore remain unverified.

The complete P0–P8 goal remains active. Native build capacity remains
unstable; no production deployment, migration, external message, store action,
device reset or release acceptance occurred.
