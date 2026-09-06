# Remaining Revolut design gaps — implementation and acceptance

The owner's goal remains active. This work improves Collect's mobile, Admin and
public surfaces against the cohorts in `DESIGN.md`. It does not certify 100%
fidelity or authorize mobile production distribution.

| Requirement | Current result | Remaining evidence |
| --- | --- | --- |
| Mobile typography | Shared secondary titles, amounts and action labels use regular/medium weights; settings rows are lighter. | Exact source-native font provenance and production state review. |
| Home hierarchy and spacing | More space around the balance and actions on tall displays; compact, landscape and enlarged-text layouts reclaim it. Appearance preview uses Explore Groups. | All corresponding production/membership/loading/error cases and owner annotations. |
| Mobile state acceptance | Existing 134 cases, 23 annotations and ten criteria remain intact. | Mandatory gate is blocked with 166 findings: 134 cases, 23 annotation closures and nine approval/artifact/source fields. |
| Native keyboard/accessibility | 36 Android scenarios passed with actual OS input, keyboard, portrait/landscape and normal/200% text. OS settings restored; disposable AVD stopped. | iOS keyboard, native reader tasks and production candidate acceptance. Android evidence is bound to its retained fixture APK; the later public-shell brace formatting is outside that APK. |
| Exact mobile candidate | Final iOS fixture: 42/42 routes and screenshots; all 219 installed bundle files matched the retained app during the run. | Production APK/AAB/IPA binding and `make mobile-design-gate` approval. No mobile distribution performed. |
| Admin precision | Shared titles, metrics and compact table values use lighter roles. | Full authenticated Revolut Business desktop/table comparator remains unavailable. |
| Admin behavior | 23 routes at four widths passed: 92 captures covering navigation, tables, keyboard, named controls, target sizes and browser errors. | Live authenticated operator/session/permission behavior remains separate from fixture coverage. |
| Website composition | Photo-overlay navigation, measured editorial spacing, stronger heading contrast and a clear CTA hierarchy. Flutter header stays pinned and adapts after the hero. Fourteen owner-marked headings now center beside their content; Premium finance uses equal columns and the four Growth Engines cards share a desktop row. | Owner visual acceptance remains separate. |
| Website media/responsiveness | Current native images retain unedited pixels. All 16 routes at four widths plus share/menu states passed; 70 photo-text contrast observations passed. The later owner layout review passed 144 checks across nine widths. | Platforms outside the recorded browser matrix. |
| Installed web behavior | Both surfaces installed and launched as standalone Chrome windows with correct identity/deep links. A controlled retained-build upgrade to the deployed Admin bundle passed source/version, cache replacement, offline sign-in shell and online recovery checks. Temporary apps/profiles were removed. | Actual preexisting customer-session upgrade continuity and other OS/browser install flows remain unverified. Public marketing has no offline service worker. |
| Deployment parity | Public and Admin are published. Their active Cloudflare versions and all 49 public / 65 Admin served asset hashes match the recorded clean release builds. | GitHub hosted CI could not start because the account is locked for billing. The branch remains separate from main. |

## Implementation and review evidence

Baseline: `55783168128c10e9a5671fe519c6242c0a036e7a`.
Release checkout: `.cache/revolut-gap-closure-20260906/release-source`, branch
`codex/revolut-gap-closure-20260906`. Concurrent Rwanda image-bank work stays in
the original checkout and is excluded from the selected release changes.

- Home and section typography corrections use shared tokens/components. Collect
  names, routes, balances, geographic payment rails and access controls remain
  authoritative.
- Both public implementations use the existing Rwanda illustrations. The static
  hero keeps one primary action and readable secondary links. Measured scrims
  resolve the two initial wide-screen heading-contrast failures.
- The Flutter header reflows at 320 px with 200% text and changes contrast as the
  hero leaves the viewport. A regression test verifies pinned navigation.
- Eleven changed golden images were visually reviewed before updating their
  baselines. Tolerance stayed at 0.0005. Goldens are regression evidence only.
- Admin browser evidence now compiles into staging and retains an independent
  copy. This prevents another Flutter target build from removing fonts/assets
  from a review already in progress. Missing font files fail before browser QA.
- Public CI watches styles, media/runtime dependencies and media tests. Its
  seven media tests reject edited images and app-source changes. The iOS media
  hash excludes only injected Android `google-services.json`, which is ignored
  by Git and cannot affect these iOS fixture images. The mobile production gate
  retains its independent complete source and artifact requirements.

| Evidence | Result and scope |
| --- | --- |
| `.cache/revolut-gap-closure-20260906/responsive/` | 81 responsive widget checks passed; no OS reader acceptance implied. |
| `.cache/revolut-gap-closure-20260906/golden-review/review.json` | 11 changed regression images reviewed. |
| `.cache/revolut-gap-closure-public-goldens-verified.log` | 19 public/golden tests passed. |
| `.cache/revolut-gap-closure-pinned-header.log` | Six public tests passed, including pinned navigation and enlarged text. |
| `.cache/revolut-gap-closure-admin-tests.log` | 27 Admin tests passed after correcting the obsolete 69-capture assertion to 92. |
| `.cache/revolut-gap-closure-analyze-final.log` | No analysis issues. |
| `.cache/revolut-gap-closure-full-tests-final.log` | Broad run: 748 passed, three failed. The obsolete Admin count was subsequently fixed and its 27-test suite passed. Two asset checks remain pending as explained below. |
| `.cache/revolut-gap-closure-20260906/ios-release-media/summary.json` | Final native fixture: 42/42 routes and screenshots. Full source and runtime fingerprints stable during the run. |
| `.cache/revolut-gap-closure-20260906/ios-release-media/installed-reviewed-bundle.json` | All 219 installed files matched the retained bundle during the run. |
| `.cache/revolut-gap-closure-20260906/ios-release-media/website-review.json` | All eight final website captures are byte-identical to the native images already visually reviewed; no image edits. |
| `.cache/revolut-gap-closure-20260906/android-keyboard-final/report.json` | 36/36 real Android keyboard scenarios passed. Retained fixture APK and driver hashes recorded. |
| `.cache/revolut-gap-closure-20260906/admin-retained/browser-qa/admin_browser_qa.json` | 92/92 fixture route/viewport checks passed; full required matrix. |
| `.cache/revolut-gap-closure-20260906/public-routes-final/route_rendered_qa.json` | 64 route/viewport combinations, 16 share cases, 192 screenshots; passed. |
| `.cache/revolut-gap-closure-20260906/public-photo-contrast-final/report.json` | 70 observations passed across nine widths; actual image pixels sampled behind text. |
| `.cache/revolut-gap-closure-20260906/public-quality-isolated.json` | Clean isolated checkout passed 56/56 public quality checks. |
| `.cache/revolut-gap-closure-20260906/public-installed-pwa-standalone/report.json` | Chrome install, selected standalone window mode, identity and deep link passed. Public offline support is not established. |
| `.cache/revolut-gap-closure-20260906/admin-installed-pwa/report.json` | Chrome install, standalone mode, identity, protected-route redirect, offline sign-in shell and online recovery passed. |
| `.cache/revolut-gap-closure-20260906/admin-installed-update-activated/report.json` | Nine checks passed in a controlled local upgrade from the retained older bundle to the exact deployed Admin bundle, including activated cache replacement and source revision. |
| `.cache/revolut-gap-closure-20260906/admin-current-installed-live/report.json` | Nine checks passed in a fresh installed Chrome app on the live Admin domain: current source/bundle, only the active cache, identity, deep link, offline sign-in shell and online recovery. |
| `.cache/revolut-gap-closure-20260906/owner-layout-verified.json` | All 144 unique layout checks passed for the owner annotations. |
| `.cache/revolut-gap-closure-20260906/owner-partners-live-review/report.json` | All 27 Partners layout checks passed on the public domain across nine widths. |
| `.cache/revolut-gap-closure-20260906/owner-layout-live-gate.json` | Public live routes and content: 35/35 passed. |
| `.cache/revolut-gap-closure-20260906/public-live-assets-final.json` | All 49 public files match deployed source `0e5f06000838cd0d431fe5b3bc2711c0588c0cf6`. |
| `.cache/revolut-gap-closure-20260906/admin-live-assets-final.json` | All 65 Admin files match deployed source `2e6b3ff1ae4880f5c6b9a779c9817536d7455fc4`. |
| `.cache/revolut-gap-closure-20260906/mobile-design-gate-final.json` | Blocked; all existing acceptance requirements retained. |

The two remaining broad-suite failures concern the unapproved Rwanda source
image bank: runtime asset inventory and source hygiene. These failures were
also reproduced in the isolated checkout for the preexisting tracked image
`assets/group_covers/rwanda/source/rw-01-neighbourhood-ikimina-v1.png`. Its records say
`generated_unreviewed` and `runtime_ready: false`. None of those source images
was added to the approved product manifest or the deployed asset selection.
The eight reviewed native website captures were separately reconciled into the
approved product-image inventory; replaced captures remain in the historical
media directory with a replacement record.

The Chrome installation review uses the actual browser PWA install/launch and
user display-mode APIs in an isolated profile, following the
[Chrome DevTools PWA protocol](https://chromedevtools.github.io/devtools-protocol/tot/PWA/).
It is not a claim about Safari, mobile installation, screen readers or an
existing customer's session.

The initial update review read the cache before service-worker activation had
finished. A separate reproduction showed that this installed Playwright
runtime returned immediately even for an asynchronous predicate resolving to
`false`. The corrected review polls an awaited Boolean explicitly, then checks
the activated worker, removal of the old cache, bundle hash and source revision.
All nine controlled update checks passed. Earlier unsuccessful reports remain
as historical evidence; they do not establish a production update defect.

Public Worker version `453a68f9-31ee-41cc-b7c3-c7eaf8f2febb` and Admin Worker
version `f4a222a0-aec9-424f-9a5a-309549439559` each have 100% traffic in the
provider readback. Full deployment and rollback metadata is recorded in
`docs/release/LIVE_DEPLOYMENTS.json`.


## Follow-up website rows and native iOS keyboard review

The later website annotations are published from `0e5f06000838cd0d431fe5b3bc2711c0588c0cf6`.
The complete 494-check layout review passed locally and on the live domain
across thirteen widths. It covers the requested four-card rows, two rows for
eight-item sections, all five Group Savings steps on one wide desktop row,
six Insurance barriers on one wide desktop row, and the two marked partner
bullet removals. The sixteen-route visible-content comparison confirms only
those two removals. See `WEBSITE_OWNER_LAYOUT_2026-09-06.md` for exact scope,
breakpoints and evidence.

The new guarded iOS debug fixture and host driver disable text-entry emulation.
The driver exposes only fixture navigation and read-only geometry, binds its
control endpoint to loopback, and requires the specifically named disposable
Collect simulator. It is not imported by production code. Flutter analysis
and the simulator build passed. All 219 installed bundle files matched the
retained candidate during the active run; source, contract and reference
fingerprints were stable before and after the review.

At 390 by 844 points with the platform default text size, actual native-keyboard
input passed for sign-in, the Rwanda MoMo-number editor, and the diaspora
account-number editor. The focused fields and enabled actions were visible
and hit-testable above keyboard insets of 308 or 335 points. No form action was
submitted. The diaspora draft survived a rotation round trip and the action
was reachable again in portrait.

The landscape observation at 844 by 390 points left Save below the 208-point
keyboard. A native drag dismissed the keyboard and exposed Save with the draft
preserved. Keyboard-open action behavior remains unclosed; this is not a pass
for the full landscape or enlarged-text matrix. MoMo-code, contribution,
group creation/join and search coverage also remain to be completed for iOS.
The stream's H.264 encoder failure was recovered with its supported MJPEG
setting. Native keyboard coaching was dismissed in the designated Collect
window. The driver and mirror were stopped and that simulator was restored to
its original shutdown state; other simulators were left running.

Evidence: `.cache/revolut-gap-closure-20260906/ios-keyboard/review-summary.json`,
its case JSON/PNG files, `candidate-before.json`,
`candidate-after-fingerprint.json`, and `installed-reviewed-bundle.json`.
The root workspace gate still reports 166 failures: 134 required cases, 23
annotation closures, and nine source/artifact/approval fields. The isolated
checkout's gate report lacks the root workspace's private references and
release evidence, so its shorter failure list is not a reduction in required
acceptance. No acceptance case, annotation, threshold or approval was changed.
