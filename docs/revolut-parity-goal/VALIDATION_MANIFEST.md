# Validation Manifest

## Snapshot

- Repository: `/Volumes/PRO-G40/COOL`
- Evidence date: 2026-07-25
- Flutter: 3.44.4 stable, revision `ad70ec4617`
- Dart: 3.12.2 stable on macOS arm64
- Scope: current dirty worktree containing the Revolut-parity implementation
- Release conclusion: not release-ready; local engineering gates below do not
  replace device, visual, signing, store, production, or owner approval gates

## Verified local gates

| Gate | Command or evidence | Result |
|---|---|---|
| Formatting | `dart format --output=none --set-exit-if-changed lib test integration_test` | Passed, 178 files checked and 0 changes required |
| Static analysis | `flutter analyze` | Passed, no issues found |
| Patch hygiene | `git diff --check` | Passed |
| Full automated suite | `flutter test --coverage --no-pub --reporter expanded` | Passed, 412 tests; retained log `.cache/revolut_parity_validation/canonical_test_20260725T0635Z.log` has SHA-256 `2d480ffc59c58dd31e0fca6f47ea570fee5abfb76ee49e60d0723fb87d4e61a1` |
| Line coverage | `coverage/lcov.info` | 9,255 of 11,892 lines, 77.83% |
| Coverage integrity | SHA-256 | `8bf5fbfd8dcfd2212061939f6caa0aaca781885c4b84f01152e9378f8c3c02bb` |
| Numeric contrast contract | `flutter test --no-pub test/features/theme_contrast_contract_test.dart` | Passed, 14 focused cases. Normal text/status/action pairs meet at least 4.5:1; essential enabled-control and focus boundaries meet at least 3:1 across light, dark, both high-contrast themes, Admin status chips, and every route-gradient stop |
| Interaction-target contract | `flutter test --no-pub test/features/interaction_target_contract_test.dart` | Passed, 4 focused cases. Primary actions are at least 48 dp and dense icon controls at least 44 dp across light, dark, both high-contrast themes, all 35 member routes, every full-height public route, compact Admin, custom tap surfaces, and literal source declarations |
| Lifecycle-focused tests | App shell, repository, mobile completion, and persona suites | Passed; launch/resume sync, overlap coalescing, notification-state refresh, failure containment, and later retry are covered |
| Dependency and policy contract | `flutter pub outdated --json`, direct licence inventory, `DEPENDENCY_LICENSE_POLICY_ASSESSMENT.md`, and release-document regression | Passed for the current graph; the unused platform-icon font dependency is removed, 17 direct runtime packages have permissive licence dispositions, and the resolver reports 0 advisory-affected, 0 discontinued, and 0 retracted packages |
| Consolidated source hygiene | `scripts/revolut_parity_source_hygiene_gate.sh --json` plus `test/security_hygiene_test.dart` | Passed with 0 failures and CI wiring. Exact Inter typeface/licence set, zero SVG/SVGZ/ICO product assets, official-logo hash identity, zero legacy typography/SVG/avatar references, centralized feature typography, controlled font declarations, fixture isolation, redacted tracked/untracked secret scan, and zero unsupported product-boundary hits. All 86 non-failing inventory markers received explicit safe dispositions. Evidence SHA-256: `9cd9463ef211adc4eb743d01f2ceb22fb17915b83bf223301c1422c5e9be8166` and `272f68d404b1b30aff23db688db1de84caca77db8df90b3dc1509fa646676c3d` |
| Public/Admin focused tests | `flutter test test/landing_page_test.dart test/admin_pwa_test.dart` | Passed, 39 tests including compact 200% text contracts |
| Static public site build | `PUBLIC_BUILD_DIR=build/public_web ruby scripts/public_static_site_build.rb` | Passed, 33 generated files |
| Admin PWA release wrapper | `COLLECT_ADMIN_WHATSAPP_PHONE=250795588248 FLUTTER=/Users/jeanbosco/Developer/flutter/bin/flutter /bin/bash scripts/admin_pwa_release_build.sh` | Passed locally with the documented public support number; manifest and hosting gates pass, official icon hash is pinned, `custom-sw.js` is present, and refreshed `main.dart.js` is 3,160,934 bytes with SHA-256 `b1083482f0de8fc7590e5b336ce574b31154e7b6a155774a1e39d029b1c0b2c0`. This does not prove the currently deployed Admin host, whose live JavaScript remains an older 3,139,261-byte artifact |
| Release artifact freshness | `/bin/bash scripts/release_artifact_manifest.sh --json` | Passed at 2026-07-25T04:38:16Z; all nine Android/Admin artifacts are present and newer than their source groups. `output/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_2026-07-25.sha256` was written with SHA-256 `2276f54f16eb70c3d094b7e733675c6d301684d4327936d4ede094a51b851290` |
| Android production APK assembly | `flutter build apk --release --no-pub --flavor production --dart-define=FLAVOR=production` | Passed after the E-052 performance changes; 76,436,535 bytes, SHA-256 `101af38789eaa6424b38382b7f788ef865812c6b04a91515e6a464ee6ef4f1b3` |
| Android production signature and permissions | Android SDK `apksigner verify --verbose --print-certs` plus package/permission inspection | Passed with APK Signature Scheme v2 and one signer; package `app.cool.mobile`, target SDK 36; restricted SMS, broad media, and legacy storage permissions absent |
| Android production app bundle | `flutter build appbundle --release --flavor production --dart-define=FLAVOR=production --no-pub` | Passed; 67,672,875 bytes, SHA-256 `0c88d2caf75182e4a6ae0d741713a54aaca038689613b6fc79fae83647788b2d` |
| Android current-source payload proof | Packaged `libapp.so` SHA comparison plus byte-string and bundle-index inspection | APK and AAB package identical current payload SHA-256 `ebfb5d1c551e485e43780c31a44528e5787b79b42e0cf0254dc387d402367a11`. Bundle inspection finds Inter and the official PNG mark among governed Flutter assets, with no SVG/SVGZ/ICO or legacy typeface payload. |
| Android bundle signature | `jarsigner -verify` | Passed; strict mode warns about the self-signed certificate chain and absent timestamp |
| Android signing preflight | `scripts/android_release_signing_preflight.sh --json` | Passed; configured signing material exists and Gradle verification succeeds without exposing secrets. The upload certificate pin is not configured, so accountable fingerprint confirmation remains open |
| Artifact-version approval gates | `scripts/release_approval_evidence_gate.sh --json`, `scripts/flutter_mobile_release_gate.sh --json`, and `scripts/release_status.sh --json` | Correctly blocked: current `1.2.2+10` signing and owner approvals are still recorded for `1.2.2+9`; recorder and approval packet now require an explicit matching artifact version |
| Google Play optimization gate | `scripts/google_play_optimization_gate.sh --json` | Local package identity, target API 36, fresh APK/AAB, 16 KB alignment, production permission scope, App Links, policy URLs, readiness packet, upload tooling, and Play Integrity checks pass. The gate remains truthfully blocked on an owner-approved feature graphic and refreshed native screenshots, Reporting API authentication, and live Play Console review |
| Aggregate signing guard | Task-graph guard and regression test | Hardened so aggregate release tasks cannot bypass production-signing checks |
| Controlled Android route matrices | `scripts/android_device_uat.sh` on an isolated Pixel 4a-profile API 36 ARM64 emulator | E-049 passes default Dark and Light/200%-text/high-contrast/reduced-motion. E-053 adds a 1440x3120/420 dpi large viewport under native platform System-Light and System-Dark; both emitted the completion marker, exactly 35/35 route passes, 35/35 screenshots, no timeout/UI exception, and an unlocked post-run state. The first Light review exposed and closed I-043 before accepted recapture. The earlier physical Pixel attempt remains invalid, and physical confirmation is still open |
| Android device-UAT evidence guard | Completion marker, exact route-pass count, declared variant/display metadata, screenshot count/manifest, lock-state check, and regression contract | Hardened; summary evidence records model, Android release/SDK, physical and override size/density, platform night mode, variant configuration, screenshot count/manifest, and completion state instead of relying on an implicit build configuration |
| Android dev-package permission metadata | `ANDROID_PERMISSION_PACKAGE=app.cool.mobile.dev scripts/android_permission_device_evidence.sh --json` on the controlled API 36 emulator | Passed; restricted SMS permissions absent and expected runtime permissions limited to Camera and Notifications, both denied before action. E-054 subsequently completes native Notifications denial/retry/grant; Camera native-dialog evidence remains open |
| Android notification permission-dialog recovery | `scripts/android_permission_dialog_uat.sh` plus `integration_test/mobile_permission_device_uat_test.dart` on the isolated API 36 emulator | E-054 passed: native Deny, Collect recovery-visible, retry, native Allow, recovery-pass, and Flutter completion markers are retained with hashed host/device/dialog-action logs. I-044 lifecycle/context races were fixed and covered. The harness refuses physical targets by default and stores no notification/message/customer data. Native Camera and retained dialog screenshots remain open |
| Post-upgrade Android integration build | `COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY=false flutter build apk --debug --flavor dev --dart-define=FLAVOR=dev --no-pub` plus merged-APK permission inspection | Passed; APK SHA-256 `5fa1dc6ea959822b1367da42ca9099dbf4d1cdd862b05ae694aacceb2463a901`, target SDK 36, with restricted SMS, broad media, and legacy external-storage permissions absent |
| Android native performance evidence | Clean dev profile and repeat, target-verified `integration_test/mobile_performance_device_uat_test.dart`, Flutter frame timings, Perfetto, gfxinfo, and `scripts/mobile_native_performance_profile.sh --json` on the controlled API 36 emulator | E-052 passes two representative v2-target runs after remediation. The repeat records 504 frames: Groups 0/154, Activity 0/191, amount entry 1/45, route 1/31, sheet 0/51, and cold startup 3/32 UI-or-raster budget misses; every scenario p90 UI/raster duration is below 16.667 ms. `totalSpan` latency is retained separately. Stale v1-on-v2 AOT output was rejected. I-042 is closed locally; physical-device, long-session, crash/ANR, and authorized reporting evidence remain open |
| iOS simulator build and launch | XcodeBuildMCP `build_run_sim` on iPhone 17 Pro | Passed after a clean dependency reset and CocoaPods synchronization; app installed and launched. Build log: `/Users/jeanbosco/Library/Developer/XcodeBuildMCP/workspaces/COOL-58529b6536d2/logs/build_run_sim_2026-07-24T18-07-36-914Z_pid10006_ac2c6e09.log` |
| iOS Release generic-device archive | Post-upgrade unsigned `xcodebuild archive` with store validation enabled | Passed for the captured pre-I-030 source: arm64 archive for `app.cool.mobile` 1.2.2 (10) retained at `.cache/ios_release_archive/20260724-post-upgrade/Collect-unsigned-final.xcarchive`; binary SHA-256 `8b8c192561289bb9bc84aea771144c7d7312ba6de79c1f1bd4e85a3710c5e12a`, Info.plist SHA-256 `e387409f4a0cfbdfeb5c3ba6d796c21d2ea505cda03b43536c0235bb212142bd`, dSYM UUID `4EDFC2BD-D3AC-319C-B11F-8866F61FF275`. E-044 supplies current-source simulator compilation; a current-source generic-device archive and signed distribution remain open |
| Current-source iOS Simulator compile | XcodeBuildMCP `build_sim` using `Runner.xcworkspace`, `Runner`, iPhone 17 Pro destination, and isolated `Collect-Codex` DerivedData | Passed in 7.061 seconds without boot/install/launch after synchronizing the Flutter-only CocoaPods sandbox from the `ios` working directory; Swift-package plugins are not duplicated as pods. Built `Collect.app` is `app.cool.mobile` 1.2.2 (10) with aggregate file checksum `f634a585b04e4349dbd433c870e66a196e96e35ec7e7036760164a41ae025743`. Bundle inspection finds the current E-043 identifiers, Inter, Material Icons, and the official PNG among governed Flutter font/brand assets. Log: `/Users/jeanbosco/Library/Developer/XcodeBuildMCP/workspaces/COOL-58529b6536d2/logs/build_sim_2026-07-25T00-39-52-571Z_pid10006_81ef570c.log` |
| iOS configured signing path | Signed `xcodebuild archive` without provisioning updates | Blocked precisely: available wildcard profile lacks the Associated Domains capability and entitlement; no signed archive produced |
| iOS System theme runtime | Appearance selected-state snapshot, iOS Light/Dark switch, policy screenshots, and relaunch | Passed; the open policy surface updated in place and System remained selected after relaunch |
| High-contrast runtime themes | Focused member/Admin source and runtime theme-selection tests | Passed; light/dark variants expose stronger boundaries and 3 px focus rings |
| iOS adaptive Home smoke matrix | XcodeBuildMCP builds and captures on iPhone 17 Pro, iPhone 17 Pro Max, and iPad Pro 11-inch (M5) | Passed for the captured Home state; iPad selected a persistent navigation rail and showed no visible clipping or overflow |
| Complete member responsive route matrix | All 35 routes at 320x568/200%/reduced motion, 390x844, 430x932, and 834x1194/high contrast | Passed without Flutter UI exceptions; launch, Activity, shared financial rows, and Ledger were corrected during the audit |
| Native iOS four-target route matrix | `scripts/ios_simulator_route_uat.sh` on iPhone SE (3rd generation), iPhone 17 Pro, iPhone 17 Pro Max, and iPad Pro 11-inch with route-resolution markers and retained fixture screenshots | Passed on every target; each resolved all 35 routes, retained all 35 screenshots with 26 distinct states, kept every image above the evidence floor, and left the simulator booted. Compact visual review found and closed an ellipsized Ledger total before final recapture |
| All-route theme and high-contrast widget matrices | `test/persona_uat_smoke_test.dart` | Passed: all 35 routes at Light, Dark, System-Light, and System-Dark with expected brightness; all 35 tablet routes assert the high-contrast runtime token layer |
| Native iOS Light route variant | `IOS_UAT_THEME_MODE=light` with variant-aware `scripts/ios_simulator_route_uat.sh` on iPhone 17 Pro | Passed after a fresh uninstall/build/install: 35/35 routes, 35/35 screenshots, 26 distinct states, matching completion/variant markers, and booted post-run simulator. Evidence: `.cache/ios_simulator_route_uat/20260724T182000Z-iphone17pro-light/` |
| Native iOS combined accessibility variant | Dark, 320% text, high contrast, and reduced motion with variant-aware `scripts/ios_simulator_route_uat.sh` on iPhone 17 Pro | Initial run exposed I-029 on Appearance; after the responsive fix, the corrected run passed 35/35 routes, 35/35 screenshots, 26 distinct states, matching completion/variant markers, and no Flutter exceptions. Evidence: `.cache/ios_simulator_route_uat/20260724T182500Z-iphone17pro-accessibility-fixed/` |
| Native iPad/System extension attempts | Original iPad, disposable cloned iPad, and iPhone 17 Pro System-Light through `scripts/ios_simulator_route_uat.sh` | Correctly excluded under I-027/E-036. Every new Xcode build failed to spawn `AssetCatalogSimulatorAgent`; the original iPad produced 0 routes/screenshots, while the clone and iPhone later attached to the stale `iphone17pro-accessibility-fixed` fixture and emitted 35 screenshots. The marker mismatch rejected both. The disposable clone was removed; no simulator data was erased. The harness now records build failure, observed variant identity, failure keys, and whether evidence was accepted. |
| Critical-flow semantics matrix | `test/persona_uat_smoke_test.dart` across authentication, five shell destinations, group, contribution, ledger, settings, and offline routes | Passed; controls expose stable labels and semantic tap actions. Duplicate bottom-navigation labels and missing shared top-chrome actions were corrected. VoiceOver/TalkBack traversal remains open. |
| Completion-audit fail-closed guard | `FINAL_COMPLETION_AUDIT.md` plus `completion audit remains fail closed while goal evidence is open` | Passed; all 10 workstreams, 10 required deliverables, and 7 gates are inventoried, while both completion and Product Design QA remain blocked until direct evidence closes the open scope. |
| Evidence consistency gate | `scripts/revolut_parity_evidence_consistency_gate.sh --full --json` plus the premature-completion regression | Final rerun validates required documents; contiguous E-001..E-054, I-001..I-044, and RT-001..RT-048 inventories; registered cross-references; complete issue dispositions; 10 workstreams and 10 deliverables; blocked sentinels; current coverage SHA-256; and all nine artifact hashes/sizes. The source-only mode is wired into CI, while full mode requires retained local coverage and release artifacts |
| Core-surface golden matrix | `flutter test --no-pub test/goldens/collect_core_surfaces_golden_test.dart` | Passed twice consecutively without updates after the current correction: 13 reviewed, unique, checksum-pinned baselines using real Inter/Material Icons, deterministic official-logo preloading, and a fixed evidence clock. The six official-logo/Appearance deltas were visually inspected and repinned; generated failure diagnostics were removed. Member surfaces render at 390x844; public/Admin render at 1440x900. |
| Complete route-reference mapping | `REFERENCE_MAPPING_MATRIX.md` plus normalized combined comparisons | Passed locally for mapping scope: all 35 routes have a retained reference pattern or explicit no-direct-analogue rationale; RT-003 and RT-004 are complete. Direct auth/amount captures and RT-005 full comparison closure remain open. |
| Native maximum text and contrast | iPhone 17 Pro at `accessibility-extra-extra-extra-large` plus Increase Contrast, Activity and Ledger | Passed after containing the avatar initial and keeping the full `RWF 35,000` Ledger total visible; simulator settings restored afterward |
| Universal/security source contracts | Focused gate reruns and full suite | Passed |

## Implemented risk coverage

- Five stable mobile destinations and guarded deep links.
- Confirmed-only Activity and centralized contribution routing.
- Exclusive bundled Inter and 400-700 typography source policy.
- Clean dependency resolution contains no legacy platform-icon package; local Admin and
  Android artifacts contain Inter plus the tree-shaken Material semantic-icon
  font and no Cupertino typeface. Flutter still emits its generic
  generic expected platform-icon diagnostic during tree shaking.
- Archived groups removed from active Home, Groups, and Contribute surfaces.
- Archived direct routes are read-only and preserve ledger access.
- Owner-only group mutation guards and self-target validation.
- Recoverable, keyboard-aware archive, transfer, and admin sheets.
- Live-region authentication and group-action error announcements.
- Matching active contribution intents are reused.
- Duplicate and expired contribution requests are explained before action.
- Account deletion requests require an explicit reason.
- Supported-group filtering has an explicit empty recovery state.
- Public page padding, CTA height, brand lockup, metrics, USSD card, and
  decorative phone preview remain stable at 320 px and 200% text.
- Admin mobile navigation, top bar, page headings, dense rows, horizontal
  scrolling, and record semantics adapt to compact and 200% text layouts.
- Critical member controls expose stable screen-reader labels and tap actions
  without duplicated bottom-navigation announcements.
- Android aggregate release-task detection now inspects the resolved task graph
  instead of only requested task names.
- Android physical-route evidence now fails closed without Flutter completion,
  all 35 route-pass markers, and an unlocked post-run device.
- Android permission evidence runs on the pinned macOS system Ruby and records
  only package metadata and app-op state.
- Native Android performance evidence rejects Notification Shade,
  dreaming-lock, missing Flutter completion, stale target identity,
  incomplete scenario/frame samples, and post-run lock states.
- Light, Dark, and System are distinct persisted theme modes; System follows
  native appearance and remains accessible at 320 px with 200% text.
- Member and Admin applications expose framework high-contrast light/dark
  themes instead of leaving the existing high-contrast tokens unreachable.
- Current iOS builds and all-route fixture matrices pass on compact,
  standard-phone, large-phone, and tablet simulators; tablet routes adapt to a
  navigation rail.
- All 35 member routes render at compact 200% text/reduced motion, standard,
  large-phone, and tablet/high-contrast widget configurations.
- All 35 routes resolve and retain nonblank native screenshots on the iPhone 17
  Pro simulator. The evidence harness fails closed on missing completion,
  route-count drift, undersized images, blank/low-diversity captures, timeout,
  or simulator-state loss.
- Native iPhone Activity and Ledger remain usable at maximum Dynamic Type with
  Increase Contrast; financial totals remain readable and chrome initials stay
  within their controls.
- A fresh full-route iPhone variant passes Light, and another passes Dark with
  320% text, high contrast, and reduced motion. The latter exposed and closed
  an Appearance-card overflow; primary content remains scrollable, though some
  secondary labels ellipsize at the extreme scale.
- SMS-access synchronization runs after launch and completed foreground
  resumes, ignores paused state, coalesces overlapping resume events, contains
  notification-permission failures, and retries on the next resume.
- The current dependency graph is compatible-upgraded, `file_saver` 0.4.0 is
  adopted, direct licences are inventoried, resolver advisories are clear, and
  the store-policy checklist is mapped to current official Apple/Google rules.
- Android manifest merging explicitly removes unnecessary legacy storage
  permissions introduced by `file_saver`; the rebuilt APK also excludes
  restricted SMS and broad media permissions.
- Android signing review and release-owner approval are version-bound to
  `pubspec.yaml`; legacy approval notes are parsed only to reject stale records,
  and new records require explicit `--artifact-version`.
- Play Developer Reporting helpers return structured blocked evidence when
  `gcloud`/OAuth is unavailable instead of crashing or implying metrics exist.

## Open validation gates

- iOS signed distribution archive and physical-device checks. Generic-device
  Release compilation and unsigned archive creation pass; the configured signed
  path is blocked on an Associated Domains-capable provisioning profile.
- Physical Android route confirmation, Camera-dialog UX, SMS, and lifecycle
  matrix. E-049/E-053 complete controlled Android standard/accessibility/large/
  System route matrices; E-054 completes native Notifications denial/retry/
  grant and closes its resume/context races. Process restart, interrupted
  intents, native restoration, Camera permission, retained dialog screenshots,
  and the locked physical Pixel remain open.
- Browser-level Flutter web responsive and keyboard matrix.
- Tablet Light/Dark/System coverage plus VoiceOver/TalkBack and
  physical-device reduced-motion comfort confirmation. E-046 verifies Flutter
  navigation, sheets, list filtering, and amount controls under reduced motion
  while preserving normal motion. Framework high-contrast selection, iOS
  System response, the complete widget route matrix, native Light, and the
  full-route iPhone 320%/high-contrast/reduced-motion variant are verified.
  E-053 verifies all 35 Android routes at a large viewport in native
  System-Light and System-Dark.
  Fresh iPad/System extension runs remain blocked by intermittent I-027; E-036
  is invalid evidence by design.
- Physical-device, long-session, and crash/ANR evidence. E-052 completes two
  optimized representative six-scenario runs and closes I-042 for the
  controlled-emulator scope.
- Authorized Play Developer Reporting metrics and account-controlled Console
  surface audit.
- Public web and Admin PWA browser visual and assistive-technology QA.
- Deployed Admin-host refresh and live verification. The complete local PWA
  wrapper passes with the public support number, but the current live host
  still serves the older icon/service-worker contract.
- Remaining Revolut reference capture and normalized comparisons.
- iOS signed distribution archive closure under release-owner authority.
- Final-release dependency/policy refresh, signed production-artifact
  inspection, store forms, signing, production, and owner approvals.
- Android upload-certificate pinning and plugin migration to built-in Kotlin.
- Fresh Android signing and release-owner approvals for `1.2.2+10`; existing
  `1.2.2+9` approval records are intentionally rejected.
- The current resolved versions of the six warned Android plugins
  still apply KGP; migration requires upstream releases or controlled vendoring.

## Evidence rule

This manifest records commands that actually ran in this checkout. It must be
updated after any material implementation change and cannot be used as proof of
store submission, public deployment, live payment behavior, or production data
readiness.
