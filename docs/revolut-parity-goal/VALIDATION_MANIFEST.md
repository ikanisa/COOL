# Validation Manifest

## Snapshot

- Repository: `/Volumes/PRO-G40/COOL`
- Evidence date: 2026-07-28
- Flutter: 3.44.4 stable, revision `ad70ec4617`
- Dart: 3.12.2 stable on macOS arm64
- Scope: current dirty worktree containing the Revolut-parity implementation
- Release conclusion: not release-ready; local engineering gates below do not
  replace device, visual, signing, store, production, or owner approval gates

## Verified local gates

| Gate | Command or evidence | Result |
|---|---|---|
| Formatting | `dart format --output=none --set-exit-if-changed lib test integration_test` | Passed, 185 files checked |
| Static analysis | `flutter analyze` | Passed, no issues found |
| Patch hygiene | `git diff --check` | Passed |
| Full automated suite | `flutter test --coverage --no-pub --reporter compact` | E-065 current-source pass: 433 tests. Log: `.cache/revolut_parity_validation/canonical_test_20260728T1505Z.log`; SHA-256: `1a144519f8562bf59079165d478f7c904f4f3efef0d4fc902749ba55c70b4881` |
| Line coverage | `coverage/lcov.info` | E-065 current source: 9,555 of 12,203 lines, 78.30% |
| Coverage integrity | SHA-256 | `d8e3f1ed0b98c9bcc932ef40941f0e53ad37454baff365b1abc84276d25cbd0f` |
| Numeric contrast contract | `flutter test --no-pub test/features/theme_contrast_contract_test.dart` | Passed, 14 focused cases. Normal text/status/action pairs meet at least 4.5:1; essential enabled-control and focus boundaries meet at least 3:1 across light, dark, both high-contrast themes, Admin status chips, and every route-gradient stop |
| Interaction-target contract | `flutter test --no-pub test/features/interaction_target_contract_test.dart` | Passed, 4 focused cases. Primary actions are at least 48 dp and dense icon controls at least 44 dp across light, dark, both high-contrast themes, all 35 member routes, every full-height public route, compact Admin, custom tap surfaces, and literal source declarations |
| Lifecycle-focused tests | App shell, repository, mobile completion, persona, and pending-intent suites | Passed; launch/resume sync, overlap coalescing, notification-state refresh, failure containment, later retry, durable process-restart restoration, matching-only clear, and streamed App Link intake are covered |
| Dependency and policy contract | `flutter pub outdated --json`, direct licence inventory, `DEPENDENCY_LICENSE_POLICY_ASSESSMENT.md`, and release-document regression | Passed for the current graph; `app_links` 7.2.1 is explicitly governed, the unused platform-icon font dependency is removed, 18 direct runtime packages have permissive licence dispositions, and the resolver reports 0 advisory-affected, 0 discontinued, and 0 retracted packages |
| Consolidated source hygiene | `scripts/revolut_parity_source_hygiene_gate.sh --json`, `assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256`, `test/features/runtime_component_contract_test.dart`, and `test/security_hygiene_test.dart` | Passed with 0 failures and CI wiring. Exact Inter typeface/licence set; exactly 26 path-and-hash-approved product visuals with zero missing, unexpected, malformed, duplicated, or drifted entries; zero SVG/SVGZ/ICO product assets; official-logo hash identity; zero legacy typography/SVG/avatar references; centralized feature typography; controlled font declarations; fixture isolation; redacted tracked/untracked secret scan; and zero unsupported product-boundary hits. The allowlist manifest SHA-256 is `e9bd65a5136aecad99f494495f4ba64d4ee8990407fa681ed7506a40628d94ba`. All 86 non-failing inventory markers received explicit safe dispositions. Retained 2026-07-25 evidence SHA-256: `9cd9463ef211adc4eb743d01f2ceb22fb17915b83bf223301c1422c5e9be8166` and `272f68d404b1b30aff23db688db1de84caca77db8df90b3dc1509fa646676c3d`; the current canonical 433-test suite also passes. |
| Public/Admin focused tests | `flutter test --no-pub test/landing_page_test.dart test/admin_pwa_test.dart` | Passed, 45 tests including compact 200% text, deterministic filtered evidence rows, denied recovery, accountable sensitive reveal, one-node Admin navigation semantics, and full desktop record-control targets |
| Public responsive browser matrix | `scripts/public_website_route_rendered_qa.js` against the current local static build | Passed under E-058: 16 routes x compact/tablet/desktop = 48 results, with 64 screenshots including compact menus, named controls, landmarks, keyboard traversal, visible focus, and no overflow. Report SHA-256 is `af1cd854ec7e08d2201756145bc2084c89ddc2133119a94ef574665a486dff66` |
| Complete local Admin browser matrix | `scripts/admin_pwa_authenticated_render_smoke.sh` plus `scripts/admin_pwa_browser_qa.mjs` against the masked evidence build | Passed under E-062 after six release-style captures and all 23 Admin routes x 3 viewports with 69 browser-matrix screenshots. Route-specific semantics, navigation-present/absent responsive contracts, overflow, exact AX names, generic traversal, all critical keyboard flows, live feedback, and focus restoration pass. The matrix measures 1,138 visible enabled targets: 69/69 target checks pass with zero genuine sub-44 CSS-pixel violations; 24 viewport-edge clips are retained separately. Report SHA-256 is `da777a9803c4ccdcd994faeedbb444b85c6da53915ccbb8b064de6154283f96d`; summary SHA-256 is `977167f1c7186a7c69dc52f5d3b16ea226d88053c5747a259011b9d87d01826b`. Local RT-019/RT-022 scope and Admin-browser target measurement under RT-023 are complete while deployed-host, native measurement, and actual screen-reader scope remain open |
| Static public site build | `PUBLIC_BUILD_DIR=build/public_web ruby scripts/public_static_site_build.rb` | Passed, 33 generated files |
| Admin PWA release wrapper | `COLLECT_ADMIN_WHATSAPP_PHONE=250795588248 FLUTTER=/Users/jeanbosco/Developer/flutter/bin/flutter /bin/bash scripts/admin_pwa_release_build.sh` | E-065 clean rebuild passed with the documented public support number; manifest and hosting gates passed, official icon hash was pinned, `custom-sw.js` was present, and `main.dart.js` is 3,191,665 bytes with SHA-256 `1b2945c6c9e6ad0d83e7efb633f98c0c7704b394179149ff8e7d4b8eb646145d`. The deployed Admin host remains separately unverified |
| Release artifact freshness | `/bin/bash scripts/release_artifact_manifest.sh --json` | E-065 passes: all nine retained Android/Admin artifacts are present and fresh. Manifest `output/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_2026-07-28.sha256` has SHA-256 `8fb297f43eca9102cd619fe6a57ea5eea451a3d58383e498f1b03d829b81e3bc` |
| Android production APK assembly | `flutter build apk --release --no-pub --flavor production --dart-define=FLAVOR=production` | E-065 clean rebuild: 76,551,255 bytes, SHA-256 `0b99c69e8328ffc31dbbc085598ba41391015110d627b8cd8c98e9bd8bc73c24` |
| Android production signature and permissions | Android SDK `apksigner verify --verbose --print-certs` plus package/permission inspection | Passed with APK Signature Scheme v2 and one signer; package `app.cool.mobile`, target SDK 36; restricted SMS, broad media, and legacy storage permissions absent |
| Android production app bundle | `flutter build appbundle --release --flavor production --dart-define=FLAVOR=production --no-pub` | E-065 clean rebuild: 67,779,569 bytes, SHA-256 `72f816815f9a99e4d295a032599209b6a4296df64de3aa7ca8b0938bb41a3026` |
| Android current-source payload proof | Packaged `libapp.so` byte-string and bundle-index inspection | Clean APK/AAB AOT contains neither removed `Screen actions` nor `Primary screen actions`. Packaged governed payload is the official Collect PNG, Inter variable font, and tree-shaken Material Icons only, with no SVG/SVGZ/ICO or legacy typeface payload. |
| Android bundle signature | `jarsigner -verify` | Passed; strict mode warns about the self-signed certificate chain and absent timestamp |
| Android signing preflight | `scripts/android_release_signing_preflight.sh --json` | Passed; configured signing material exists and Gradle verification succeeds without exposing secrets. The upload certificate pin is not configured, so accountable fingerprint confirmation remains open |
| Artifact-version approval gates | `scripts/release_approval_evidence_gate.sh --json`, `scripts/flutter_mobile_release_gate.sh --json`, and `scripts/release_status.sh --json` | Correctly blocked: current `1.2.2+10` signing and owner approvals are still recorded for `1.2.2+9`; recorder and approval packet now require an explicit matching artifact version |
| Google Play optimization gate | `scripts/google_play_optimization_gate.sh --json` | Local package identity, target API 36, fresh APK/AAB, 16 KB alignment, production permission scope, App Links, policy URLs, readiness packet, upload tooling, and Play Integrity checks pass. The gate remains truthfully blocked on an owner-approved feature graphic and refreshed native screenshots, Reporting API authentication, and live Play Console review |
| Aggregate signing guard | Task-graph guard and regression test | Hardened so aggregate release tasks cannot bypass production-signing checks |
| Controlled Android route matrices | `scripts/android_device_uat.sh` on an isolated Pixel 4a-profile API 36 ARM64 emulator | E-049 passes default Dark and Light/200%-text/high-contrast/reduced-motion. E-053 adds a 1440x3120/420 dpi large viewport under native platform System-Light and System-Dark; both emitted the completion marker, exactly 35/35 route passes, 35/35 screenshots, no timeout/UI exception, and an unlocked post-run state. The first Light review exposed and closed I-043 before accepted recapture. The earlier physical Pixel attempt remains invalid, and physical confirmation is still open |
| Android device-UAT evidence guard | Completion marker, exact route-pass count, declared variant/display metadata, screenshot count/manifest, lock-state check, and regression contract | Hardened; summary evidence records model, Android release/SDK, physical and override size/density, platform night mode, variant configuration, screenshot count/manifest, and completion state instead of relying on an implicit build configuration |
| Physical Pixel 4a preflight | `ANDROID_UAT_DEVICE_ID=13111JEC215558 ANDROID_UAT_FLAVOR=dev ANDROID_UAT_TEST_TARGET=integration_test/mobile_route_matrix_device_uat_test.dart ... ./scripts/android_device_uat.sh` | Correctly stopped before test/install under E-063 because the exact Google Pixel 4a (`sunfish`, Android 13/API 33) was securely locked. `.cache/android_device_uat/20260728-physical-pixel-preflight-locked/summary.json` records `status=fail`, `reason=locked`, `runner=not_started`; log SHA-256 is `6a0bc31c0f1560dc57bdddf8bcaa1560b6f5f22d66667a1a8688f92bafc50a9b`. This proves the fail-closed safety guard, not RT-008 or RT-025 completion |
| Controlled Android TalkBack Home/Groups audit | Current dev fixture APK plus TalkBack 16 on the Pixel 4a-profile API 36 emulator | E-064 binds the real TalkBack service with touch exploration, captures before/after focus screenshots and Android accessibility trees, and closes one redundant whole-toolbar stop plus duplicate Home hero-action labels. The focused semantics regression and static analysis pass. Evidence: `.cache/talkback_uat/20260728-e064-home-sequence/`. RT-021 remains open beyond Home/Groups and for spoken-output/physical confirmation |
| Android dev-package permission metadata | `ANDROID_PERMISSION_PACKAGE=app.cool.mobile.dev scripts/android_permission_device_evidence.sh --json` on the controlled API 36 emulator | Passed; restricted SMS permissions absent and expected runtime permissions limited to Camera and Notifications, both denied before action. E-054 completes native Notifications denial/retry/grant and E-056 completes native Camera denial/education/retry/grant/recovery |
| Android notification permission-dialog recovery | `scripts/android_permission_dialog_uat.sh` plus `integration_test/mobile_permission_device_uat_test.dart` on the isolated API 36 emulator | E-054 passed: native Deny, Collect recovery-visible, retry, native Allow, recovery-pass, and Flutter completion markers are retained with hashed host/device/dialog-action logs. I-044 lifecycle/context races were fixed and covered. The harness refuses physical targets by default and stores no notification/message/customer data. |
| Android Camera permission-dialog recovery | `scripts/android_camera_permission_dialog_uat.sh` plus `integration_test/mobile_camera_permission_device_uat_test.dart` on the isolated API 36 emulator | E-056 passed with four visually reviewed screenshots: native deny prompt, Collect privacy education, native allow prompt, and recovered scanner without stale error text. The accepted summary, device log, harness, dialog-action log, and screenshot manifest are hash-pinned; the harness refuses physical targets by default and retains no camera frames or customer data. |
| Android interrupted-intent recovery | `scripts/android_interrupted_intent_uat.sh` plus `integration_test/mobile_interrupted_intent_evidence_app.dart` on the isolated API 36 emulator | E-057 passed: the intent was persisted before process death, PID 7627 was force-stopped, a distinct PID 7737 cold-recovered the first group, a warm App Link opened the second group in the same process, and a final cold restart proved completed intents were not replayed. Four screenshots/UI trees were reviewed and all hashes reverified; summary SHA-256 is `a946f809429c458f8ddbaaef4f785aed87d1239c5f4d6504dd9abbe9ce270213`. |
| Post-upgrade Android integration build | `COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY=false flutter build apk --debug --flavor dev --dart-define=FLAVOR=dev --no-pub` plus merged-APK permission inspection | Passed; APK SHA-256 `5fa1dc6ea959822b1367da42ca9099dbf4d1cdd862b05ae694aacceb2463a901`, target SDK 36, with restricted SMS, broad media, and legacy external-storage permissions absent |
| Android native performance evidence | Clean dev profile and repeat, target-verified `integration_test/mobile_performance_device_uat_test.dart`, Flutter frame timings, Perfetto, gfxinfo, and `scripts/mobile_native_performance_profile.sh --json` on the controlled API 36 emulator | E-052 passes two representative v2-target runs after remediation. The repeat records 504 frames: Groups 0/154, Activity 0/191, amount entry 1/45, route 1/31, sheet 0/51, and cold startup 3/32 UI-or-raster budget misses; every scenario p90 UI/raster duration is below 16.667 ms. `totalSpan` latency is retained separately. Stale v1-on-v2 AOT output was rejected. I-042 is closed locally; physical-device, long-session, crash/ANR, and authorized reporting evidence remain open |
| iOS simulator build and launch | XcodeBuildMCP `build_run_sim` on iPhone 17 Pro | Passed after a clean dependency reset and CocoaPods synchronization; app installed and launched. Build log: `/Users/jeanbosco/Library/Developer/XcodeBuildMCP/workspaces/COOL-58529b6536d2/logs/build_run_sim_2026-07-24T18-07-36-914Z_pid10006_ac2c6e09.log` |
| iOS Release generic-device archive | Current-source unsigned `xcodebuild archive` with store validation enabled | E-065 passed: arm64 archive for `app.cool.mobile` 1.2.2 (10) retained at `.cache/ios_release_archive/20260728-e065/Collect-unsigned.xcarchive`; app binary SHA-256 `047ea05a5ec909381986e23cae3acd676758e0a16773ab1320555e1e47560a99`, Info.plist SHA-256 `998e48672822db966eaec5ddd9cfcb63f6d862c865ac05bb508912f631f260a2`, archive-log SHA-256 `3b540f040ac6753a2392654a67cec93a602ded0af72abae9be654ca7034ea3b0`, and dSYM UUID `D467626B-D459-319F-98B0-4C145E58CF35`. The archive is intentionally unsigned and non-distributable; signed distribution remains open |
| Current-source iOS Simulator compile | XcodeBuildMCP `build_sim` using `Runner.xcworkspace`, `Runner`, and the controlled iPhone 17 destination | E-065 passed in 15.132 seconds after CocoaPods synchronization. Built `Collect.app` is `app.cool.mobile` 1.2.2 (10); `App.framework/App` SHA-256 is `5161e93fd02ab719fc5528a214a6e3a72678c72c0b9c46b84f3b6c51cd1d573b`. Bundle inspection finds only Inter, Material Icons, and the official PNG among governed payload and neither removed toolbar label. Log: `/Users/jeanbosco/Library/Developer/XcodeBuildMCP/workspaces/COOL-58529b6536d2/logs/build_sim_2026-07-28T14-55-04-110Z_pid44015_3d0b1105.log` |
| Current-source iPhone Dark route matrix | `scripts/ios_simulator_route_uat.sh` on iPhone 17 | E-055 passed 35/35 routes and screenshots with 26 distinct states. Evidence: `.cache/ios_simulator_route_uat/20260728T043400Z-current-source-default-dark/`; summary/log/screenshot-manifest SHA-256 values are `a39346c0fb8c2156405f4db42cfb8e0bfb5b3aec1da0cb4636b262e7c6e3de5c`, `8f28e91da91025a98f348d81cdeec649949ce2ae2fa0f93cbc5556ba59e76873`, and `f256653229ed96459d9eac2e3cffe1896b939d0509a5138f1f43f01521823a10`. |
| Current-source iPhone System-Light route matrix | `scripts/ios_simulator_route_uat.sh` on iPhone 17 | E-055 passed 35/35 routes and screenshots with 26 distinct states after visual review exposed and closed the auth inverse-color defect. Evidence: `.cache/ios_simulator_route_uat/20260728T044200Z-current-source-system-light-fixed/`; summary/log/screenshot-manifest SHA-256 values are `5230252e93e02f2e0b00d155715c602caa95d8954b94a936e01512377803a774`, `0de7394421d59fdb820890d818c9b24aab5d55a2c9a4398e95a8f516fe1eef0c`, and `0bae4fc1c4713cf370fa0f6ed411b40c7404d8770c36308e27f978912f56039f`. |
| Current-source iPhone large-text action-label matrix | `scripts/ios_simulator_route_uat.sh` on iPhone 17, Dark, text scale 1.2 | E-063 passed 35/35 routes and screenshots with 26 distinct states after fixing Home quick-action label truncation. Evidence: `.cache/ios_simulator_route_uat/20260728-e063-large-labels-dark/`; summary/log/screenshot-manifest SHA-256 values are `07db8e7183043794868897c7da065a9ecbb575a40c9704687c2e114a3957ada7`, `3d0ae597128e639a70d4b640f7c8b026bb89be8cde5ad18e908fc56fe3904de7`, and `cb4996e3a2336e740f511bf3388277748720baa74ecf2376428791d55246c83d`. The accepted before/after comparison SHA-256 is `e589a3c2cb55890398823d94fb29585295b1fb32f728aa7d081511c728020bf4`; the route is fixture-backed Simulator evidence, not VoiceOver or physical-device proof |
| Current-source iPad System accessibility route matrix | `scripts/ios_simulator_route_uat.sh` on iPad Pro 11-inch (M5), System, 200% text, high contrast, and reduced motion | E-055 passed 35/35 routes and screenshots with 26 distinct states after visual review exposed and closed the truncated auth wordmark. Evidence: `.cache/ios_simulator_route_uat/20260728T051000Z-current-source-ipad-system-accessibility-fixed/`; summary/log/screenshot-manifest SHA-256 values are `96a051dff3047cb3c10b37e73ecc71b560006d3f45393181c5cb562dc759cf18`, `d0d54fc3274f1c399f049a49bfc208fdb71f41b6b1ca80c87024f3164e1ecb01`, and `1d0754961bae46ce95adeb486cc559170b0d22bb28ceee1b4534dafab0cb4305`. |
| iOS configured signing path | Signed `xcodebuild archive` without provisioning updates | Blocked precisely: available wildcard profile lacks the Associated Domains capability and entitlement; no signed archive produced |
| iOS System theme runtime | Appearance selected-state snapshot, iOS Light/Dark switch, policy screenshots, and relaunch | Passed; the open policy surface updated in place and System remained selected after relaunch |
| High-contrast runtime themes | Focused member/Admin source and runtime theme-selection tests | Passed; light/dark variants expose stronger boundaries and 3 px focus rings |
| iOS adaptive Home smoke matrix | XcodeBuildMCP builds and captures on iPhone 17 Pro, iPhone 17 Pro Max, and iPad Pro 11-inch (M5) | Passed for the captured Home state; iPad selected a persistent navigation rail and showed no visible clipping or overflow |
| Complete member responsive route matrix | All 35 routes at 320x568/200%/reduced motion, 390x844, 430x932, and 834x1194/high contrast | Passed without Flutter UI exceptions; launch, Activity, shared financial rows, and Ledger were corrected during the audit |
| Native iOS four-target route matrix | `scripts/ios_simulator_route_uat.sh` on iPhone SE (3rd generation), iPhone 17 Pro, iPhone 17 Pro Max, and iPad Pro 11-inch with route-resolution markers and retained fixture screenshots | Passed on every target; each resolved all 35 routes, retained all 35 screenshots with 26 distinct states, kept every image above the evidence floor, and left the simulator booted. Compact visual review found and closed an ellipsized Ledger total before final recapture |
| All-route theme and high-contrast widget matrices | `test/persona_uat_smoke_test.dart` | Passed: all 35 routes at Light, Dark, System-Light, and System-Dark with expected brightness; all 35 tablet routes assert the high-contrast runtime token layer |
| Native iOS Light route variant | `IOS_UAT_THEME_MODE=light` with variant-aware `scripts/ios_simulator_route_uat.sh` on iPhone 17 Pro | Passed after a fresh uninstall/build/install: 35/35 routes, 35/35 screenshots, 26 distinct states, matching completion/variant markers, and booted post-run simulator. Evidence: `.cache/ios_simulator_route_uat/20260724T182000Z-iphone17pro-light/` |
| Native iOS combined accessibility variant | Dark, 320% text, high contrast, and reduced motion with variant-aware `scripts/ios_simulator_route_uat.sh` on iPhone 17 Pro | Initial run exposed I-029 on Appearance; after the responsive fix, the corrected run passed 35/35 routes, 35/35 screenshots, 26 distinct states, matching completion/variant markers, and no Flutter exceptions. Evidence: `.cache/ios_simulator_route_uat/20260724T182500Z-iphone17pro-accessibility-fixed/` |
| Historical rejected iPad/System attempts | Original iPad, disposable cloned iPad, and iPhone 17 Pro System-Light through `scripts/ios_simulator_route_uat.sh` | Correctly excluded under I-027/E-036 because build/variant markers were invalid. E-055 supersedes this historical gap with accepted current-source iPhone System-Light and iPad System/accessibility matrices; the rejected evidence remains retained only to prove the fail-closed harness behavior. |
| Critical-flow semantics matrix | `test/persona_uat_smoke_test.dart` across authentication, five shell destinations, group, contribution, ledger, settings, and offline routes | Passed; controls expose stable labels and semantic tap actions. Duplicate bottom-navigation labels and missing shared top-chrome actions were corrected. VoiceOver/TalkBack traversal remains open. |
| Completion-audit fail-closed guard | `FINAL_COMPLETION_AUDIT.md` plus `completion audit remains fail closed while goal evidence is open` | Passed; all 10 workstreams, 10 required deliverables, and 7 gates are inventoried, while both completion and Product Design QA remain blocked until direct evidence closes the open scope. |
| Evidence consistency gate | `scripts/revolut_parity_evidence_consistency_gate.sh --source-only --json` and `scripts/revolut_parity_evidence_consistency_gate.sh --full --json`, plus the premature-completion regression | E-065 passes in both modes: contiguous E-001..E-065, I-001..I-052, and RT-001..RT-048 inventories; 26 unfinished tasks; both blocked completion sentinels; 78.30% current coverage; and all nine fresh artifacts with the recorded manifest hash. |
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
- Physical Android route confirmation, SMS, and lifecycle
  matrix. E-049/E-053 complete controlled Android standard/accessibility/large/
  System route matrices; E-054 completes native Notifications denial/retry/
  grant and closes its resume/context races; E-056 completes controlled-emulator
  Camera denial/education/retry/grant/recovery with retained screenshots.
  E-057 completes controlled-emulator process restart, interrupted App Link,
  matching-clear, and no-replay recovery. QR detection, production-package,
  live-backend, server-side idempotency, and physical-device confirmation
  remain open.
- Actual screen-reader traversal and deployed-host verification for the public
  and Admin web surfaces.
- VoiceOver/TalkBack plus
  physical-device reduced-motion comfort confirmation. E-046 verifies Flutter
  navigation, sheets, list filtering, and amount controls under reduced motion
  while preserving normal motion. Framework high-contrast selection, iOS
  System response, the complete widget route matrix, native Light, and the
  full-route iPhone 320%/high-contrast/reduced-motion variant are verified.
  E-053 verifies all 35 Android routes at a large viewport in native
  System-Light and System-Dark.
  E-055 verifies current-source iPhone Dark/System-Light and iPad System/200%-
  text/high-contrast/reduced-motion route matrices; E-036 remains invalid
  historical evidence by design.
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
- The release build prints legacy-KGP warnings for `file_saver` and
  `mobile_scanner`; the stricter compatibility gate detects direct
  Kotlin-plugin markers in six resolved plugins (`file_saver`,
  `image_picker_android`, `mobile_scanner`, `share_plus`,
  `shared_preferences_android`, and `url_launcher_android`). Migration
  requires upstream releases or controlled vendoring.

## Evidence rule

This manifest records commands that actually ran in this checkout. It must be
updated after any material implementation change and cannot be used as proof of
store submission, public deployment, live payment behavior, or production data
readiness.
