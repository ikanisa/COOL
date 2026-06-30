# Mobile On-Device QA Report - 2026-06-30

Device: Pixel 4a `13111JEC215558`
Android: 13
Display: 1080x2340, density 440
Package: `app.cool.mobile`

## Decision

Engineering device QA is partially passed with performance and human accessibility caveats.

The physical Pixel route matrix passed for all 51 configured mobile routes and produced screenshots for every route. Release APK structural accessibility evidence also passed for the onboarding and deep-link guard surfaces. Performance evidence is not clean: both route traversal and profile-mode runs recorded jank/skipped frames that should remain a release-quality finding.

This report does not replace human TalkBack auditory traversal. The native accessibility signoff gate remains NO-GO until Android TalkBack auditory review, iOS VoiceOver traversal or approved waiver, and final native accessibility decision are signed.

## Evidence

| Area | Result | Evidence |
| --- | --- | --- |
| Physical screen-by-screen route matrix | Pass: 51/51 screenshots, no missing or failed screenshots | `.cache/android_route_visual_evidence/20260630T_device_screen_by_screen_debug_upload_key/summary.json` |
| Route screenshots | Pass: physical Pixel screenshots captured | `.cache/android_route_visual_evidence/20260630T_device_screen_by_screen_debug_upload_key/screenshots/` |
| Route contact sheet | Pass: generated | `.cache/android_route_visual_evidence/20260630T_device_screen_by_screen_debug_upload_key/contact_sheets/collect-mobile-route-contact-sheet.png` |
| Android release accessibility structure | Pass: active package matched, labels exposed, settings restored | `.cache/android_accessibility_pixel4a/20260630T_device_screen_by_screen_release/summary.json` |
| Android profile performance | Pass as evidence capture, not pass as smoothness signoff | `.cache/mobile_native_performance_profile/20260630T_device_screen_by_screen_profile/summary.json` |
| Perfetto trace | Captured, 8,100,825 bytes | `.cache/mobile_native_performance_profile/20260630T_device_screen_by_screen_profile/timeline.binpb` |
| Android `gfxinfo` | Captured | `.cache/mobile_native_performance_profile/20260630T_device_screen_by_screen_profile/gfxinfo.txt` |

## Screen Coverage

The route matrix covered entry, onboarding, auth, profile, permission recovery, home, groups, group creation and scan, group detail, joined state, owner compatibility redirects, share/invite/deep-link states, contribution, payment handoff and payment states, ledger, manage, group profile, members, settings, account, privacy/legal/help, notifications, offline, and sync.

Result: all 51 route captures passed with non-empty screenshots and no `Screen not found` or unavailable-screen assertions.

Important limitation: this is an integration-driven route matrix with fixture data and direct route pumping. It verifies renderability, route coverage, screenshot output, and absence of Flutter UI exceptions. It does not prove every real gesture path, external SMS/payment provider path, or human comprehension path.

## Accessibility Findings

Passed checks:

- Release APK was installed on the Pixel before structural accessibility capture.
- Captures kept `app.cool.mobile` focused.
- Launch onboarding exposed 6 labeled nodes.
- Deep-link onboarding guard exposed 6 labeled nodes.
- Accessibility, enabled services, and font-scale settings were restored after the run.

Critical findings:

- Android TalkBack human auditory traversal is still not signed. Structural node evidence cannot certify spoken order, pronunciation, or comprehension.
- Onboarding labels are too verbose and duplicated in places. Example from deep-link guard: the product description is exposed twice in one label, and the step/status content is repeated.
- Launch sign-in exposes repeated `WhatsApp` labels, which can make TalkBack traversal noisy.

## Performance Findings

Profile evidence:

- Scenario duration: 12 seconds.
- Perfetto trace: 8,100,825 bytes.
- Max skipped frames in logcat: 69.
- `gfxinfo` total frames: 3.
- `gfxinfo` janky frames: 1.
- `gfxinfo` janky percent: 33.33%.
- 90th/95th/99th percentile frame time: 34ms.

Route traversal also recorded:

- `Skipped 106 frames! The application may be doing too much work on its main thread.`
- `Davey! duration=1780ms`.

Interpretation: the app can complete the device scenarios, but the evidence does not support claiming a fully smooth native experience. The `gfxinfo` sample is small, so it should be treated as a warning signal, not a complete performance benchmark.

## Build And Device Notes

- The first physical route matrix attempt failed before launch because local production-debug signing attempted to match the Play app-signing certificate. The rerun used `COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY=false`, which is the correct local upload-key/debug setting identified by the Gradle failure.
- Installing the debug route-test package required uninstalling the existing release package because signatures differed.
- The release APK was reinstalled before structural accessibility testing.

## Required Follow-Up

1. Fix noisy TalkBack labels on onboarding and sign-in surfaces.
2. Add route-matrix accessibility coverage beyond the two current structural captures, especially home, groups, contribution, payment intent, ledger, and settings.
3. Profile the route traversal jank: startup, first onboarding render, payment flow render, and route-matrix teardown should be separated so the main-thread stall is attributable.
4. Complete Android TalkBack human auditory traversal and record the signoff only after the reviewer confirms order, pronunciation, labels, and comprehension.
5. Complete iOS VoiceOver traversal or record an explicit scoped waiver before claiming full native mobile accessibility readiness.
