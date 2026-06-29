# Critical Native Mobile Experience Audit - 2026-06-29

Scope: Collect Flutter mobile member app in `/Volumes/PRO-G40/COOL`, with emphasis on maximum native mobile feel: loading, transitions, feedback, accessibility, performance, platform adaptation, route evidence, and release confidence.

This report is intentionally critical. The app is not broken at compile level, and it has a stronger design/test foundation than a typical prototype. The original issue was that the implementation proved mostly static screen rendering, not a complete native mobile experience.

Implementation update on 2026-06-29: the first remediation pass added code-owned route transitions, screen loading states, haptics, pull-to-refresh, stronger route UAT assertions, a native interaction compliance gate, and a profile-mode performance evidence runner. The remaining gap is measured device proof: current profile-mode performance, human TalkBack/VoiceOver traversal, and broader device-form-factor evidence.

## Standards Consulted

- Flutter app architecture guide: https://docs.flutter.dev/app-architecture/guide
- Flutter architectural overview: https://docs.flutter.dev/resources/architectural-overview
- Flutter accessibility: https://docs.flutter.dev/ui/accessibility
- Flutter adaptive and responsive UI: https://docs.flutter.dev/ui/adaptive-responsive
- Flutter performance best practices: https://docs.flutter.dev/perf/best-practices
- Flutter testing overview: https://docs.flutter.dev/testing/overview
- Apple Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines
- Android performance vitals: https://developer.android.com/topic/performance/vitals
- Material Design progress indicators and motion guidance: https://m3.material.io

## Local Evidence Reviewed

- Main router and route registry: `lib/app/router.dart`
- Shell, bottom navigation, and gradient chrome: `lib/core/widgets/collect_shell.dart`
- Motion tokens: `lib/app/theme/collect_motion.dart`
- Loading primitives: `lib/shared/widgets/collect_loading_surfaces.dart`
- Repository loading/error state: `lib/shared/repositories/collect_repository.dart`, `lib/shared/providers/collect_app_state.dart`
- Auth, groups, payment, share, profile, scanner, settings, and status screens under `lib/features/`
- Android and iOS platform metadata: `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
- Route/device/evidence scripts: `scripts/collect_mobile_design_compliance_audit.sh`, `scripts/mobile_route_render_smoke.sh`, `scripts/android_accessibility_structural_evidence.sh`
- Tests: `test/app_shell_test.dart`, `test/features/design_system_components_test.dart`, `test/features/mobile_completion_test.dart`, `integration_test/mobile_route_matrix_device_uat_test.dart`
- Existing visual evidence: `.cache/flutter_visual_evidence_premium_frontend_current/mobile/summary.json`, `.cache/android_device_uat_premium_frontend/summary.json`

## Validation Run In This Audit

Initial audit passed:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/design_system_components_test.dart test/features/mobile_completion_test.dart
```

Initial audit failed:

```bash
MOBILE_ROUTE_RENDER_SUMMARY=.cache/flutter_visual_evidence_premium_frontend_current/mobile/summary.json \
ANDROID_DEVICE_UAT_SUMMARY=.cache/android_device_uat_premium_frontend/summary.json \
COLLECT_MOBILE_DESIGN_AUDIT_DIR=.cache/collect_mobile_design_compliance/20260629T_native_experience_audit \
scripts/collect_mobile_design_compliance_audit.sh --json
```

Failure causes:

- Raw UI colors in `lib/features/auth/widgets/auth_action_dock.dart`.
- Stale visual route evidence still includes the deleted auth-result routes, while the active route list no longer registers those routes.

Continuation validation after remediation passed:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/features/design_system_components_test.dart test/features/mobile_completion_test.dart
MOBILE_ROUTE_RENDER_SUMMARY=.cache/flutter_visual_evidence_native_transition_loading_current/mobile/summary.json \
ANDROID_DEVICE_UAT_SUMMARY=.cache/android_device_uat_premium_frontend/summary.json \
COLLECT_MOBILE_DESIGN_AUDIT_DIR=.cache/collect_mobile_design_compliance/20260629T_native_interaction_contract_current \
scripts/collect_mobile_design_compliance_audit.sh --json
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/release_docs_test.dart
```

Performance evidence runner validation:

```bash
bash -n scripts/mobile_native_performance_profile.sh
MOBILE_PERF_DEVICE_ID=__missing_collect_perf_device__ \
MOBILE_PERF_EVIDENCE_DIR=.cache/mobile_native_performance_profile/20260629T_blocked_probe \
scripts/mobile_native_performance_profile.sh --json
```

The performance runner correctly returned `status=blocked` and exit code `99` when the configured Android device was unavailable. That is not performance proof; it is only proof that the performance gate fails closed instead of pretending device evidence exists.

## Executive Assessment

Current native mobile experience rating after the code-owned remediation pass: **7.8 / 10**.

Code-owned visual polish is strong in places: route-mapped gradients, glass bottom navigation, branded assets, large route screenshot coverage, semantic tests, Android/iOS platform folders, camera/share/notification/permission dependencies, focused widget coverage, route transitions, screen-level loading states, haptics, and adaptive pull-to-refresh.

But the app is not yet a maximum native mobile experience. The highest-confidence remaining gaps are:

- No current profile-mode performance evidence for startup, frame timing, scroll jank, or expensive effects.
- Accessibility evidence is mostly structural/widget-level; current human TalkBack/VoiceOver traversal is not proven.
- Expanded light/dark/compact/large-phone/tablet visual evidence is still not current.
- Offline/connectivity still needs a deterministic cache/connectivity model rather than inferred error text.
- iOS-specific behavior, including VoiceOver, share/photo/QR permission flows, keyboard behavior, and back gestures, is not proven.

## Strengths To Preserve

- `CollectMotion` already centralizes motion durations and respects reduced motion through `MediaQuery.disableAnimations`.
- `CollectShell` provides a premium, safe-area-aware bottom navigation shell with semantic labels.
- `LoadingSkeleton` and `LoadingStatePanel` exist and expose live-region semantics.
- `CollectState` includes `isLoading` and `lastError`, and repository initial load sets `isLoading`.
- The app has substantial widget coverage for launch, routes, large text, design components, loading primitives, and mobile completion flows.
- Android manifest declares concrete native capabilities for camera, notifications, app links, edge-to-edge, resize behavior, and predictive-back callback.
- iOS metadata includes camera/photo usage descriptions and launch storyboard support.
- There is prior evidence for 55 Flutter-rendered mobile routes at 390x844 and an Android route matrix pass.

## Critical Findings

### P0-1. App-wide screen transitions are absent

Evidence:

- Static scan of `lib/app/router.dart`: `GoRoute(` = 52, `ShellRoute(` = 1, `pageBuilder:` = 0, `CustomTransitionPage` = 0, `PageRouteBuilder` = 0, route transition widgets = 0.
- Routes are declared through `builder:` rather than a shared page/transition factory.
- `CollectMotion` exists but is not used by the router.

Impact:

- Navigation feels abrupt and web-like.
- Primary flows such as onboarding to auth, groups to detail, contribute to payment, and payment to status have no spatial continuity.
- Back/forward direction, modal/full-screen intent, and reduced-motion behavior are not centrally controlled.

Required remediation:

- Add a route-page helper, for example `collectRoutePage(state, child, transitionKind)`, returning `CustomTransitionPage`.
- Use route intent categories:
  - primary tab switch: subtle fade/scale or no cross-axis motion;
  - push detail: slide/fade from trailing edge;
  - auth/onboarding: forward slide/fade;
  - payment and QR/share: modal-up or contained transition;
  - success/confirmation: emphasized fade/scale.
- Route all production `GoRoute`s through that helper.
- Add widget tests that assert production routes use `pageBuilder`/custom transitions and that reduced motion returns zero-duration transitions.

### P0-2. Loading state exists but is not connected to most user screens

Evidence:

- `collectRepositoryProvider` triggers `repository.loadInitial()` asynchronously when Supabase exists.
- `loadInitial()` sets `isLoading: true`, fetches profile, collections, payment intents, contributions, notification preferences, and events, then sets `isLoading: false`.
- `realtimeSyncStatusProvider` maps `isLoading` to `RealtimeSyncStatus.syncing`.
- `ScreenScaffold` only turns sync/loading into a small banner, not a screen-level skeleton or transition state.
- Static scan of repository-backed feature files found most screens using `collectRepositoryProvider` without direct loading awareness; examples include auth, collection create/detail/manage, collections, group profile, share, home, ledger, contribution, payment, profile, settings, notifications, privacy, and payment support.

Impact:

- On live data, users can see empty/default/fixture-like surfaces before real data lands.
- Initial load, refresh, retry, and sync states are not visually distinguished.
- The app can feel jumpy even if the data layer is technically correct.

Required remediation:

- Introduce a typed screen state model for every data-backed route: `initialLoading`, `refreshing`, `empty`, `content`, `error`, `offlineStale`.
- Use `LoadingStatePanel`, route-specific skeletons, and `AnimatedSwitcher` to move between states.
- Differentiate first load from pull-to-refresh/background sync.
- Add tests for each critical route asserting initial loading and refresh behavior, not just final content render.

### P0-3. Current visual evidence is stale against the active route graph

Evidence:

- The current `collectRoutePaths` list has 51 entries including debug.
- The current router no longer registers standalone auth result routes.
- The existing visual summary `.cache/flutter_visual_evidence_premium_frontend_current/mobile/summary.json` still contains stale deleted auth-result routes.
- `scripts/collect_mobile_design_compliance_audit.sh --json` failed because the smoke summary contained unregistered auth-result routes.

Impact:

- The repo can appear design-complete while evidence belongs to an older route graph.
- Release reports risk overstating current route coverage.

Required remediation:

- Regenerate current route screenshots after route changes.
- Make route evidence generated from `collectRoutePaths` instead of duplicated lists.
- Fail if screenshots contain extra routes, missing routes, or stale route names.

### P0-4. Device route UAT can pass removed/stale paths

Evidence:

- `integration_test/mobile_route_matrix_device_uat_test.dart` still includes paths not in the active route list, including `/settings/readiness`, `/groups/join`, and `/groups/col-church/pay/intent-render/waiting`.
- The test only asserts `tester.takeException() == null` and `CollectApp` exists after pumping each route.

Impact:

- A stale or removed path can render the generic "screen not found" recovery screen and still satisfy the test.
- Native route UAT can produce false confidence.

Required remediation:

- Generate integration route specs from `collectRoutePaths`.
- For each route, assert an expected unique text/semantic marker, not just `CollectApp`.
- Split redirect routes from real screens and assert final expected destination.

### P1-1. Auth dock has raw platform colors outside the token system

Evidence:

- Current design compliance gate failed on `CupertinoColors.white` and `Color(0xFF0066CC)` in `lib/features/auth/widgets/auth_action_dock.dart`.

Impact:

- Auth is one of the highest-frequency flows; raw colors break the design-token contract and can drift from light/dark/accessibility contrast decisions.

Required remediation:

- Replace raw colors with `CollectColors`/component tokens.
- Add a focused test or audit assertion for auth native controls.

### P1-2. No haptic feedback layer

Evidence:

- Static scan found `HapticFeedback` usage count = 0 across `lib/**/*.dart`.

Impact:

- QR scan success/failure, tab selection, primary payment action, OTP submit, create group, save profile, share/save QR, and destructive account actions lack tactile confirmation.
- This is a noticeable native-feel gap.

Required remediation:

- Add a `CollectHaptics` service/helper with platform-appropriate methods.
- Trigger light selection feedback for nav/filter changes, medium feedback for successful submits, warning/error feedback for failed scan/payment states, and confirmation feedback for share/save actions.
- Respect accessibility and platform constraints.

### P1-3. No pull-to-refresh or gesture-based refresh pattern

Evidence:

- Static scan found `RefreshIndicator` usage count = 0 across `lib/**/*.dart`.
- Screens rely on explicit action icons or background sync banners.

Impact:

- Home, groups, group detail, ledger, payment status, notifications, and members feel less native and less discoverable.

Required remediation:

- Add `RefreshIndicator.adaptive` or platform-appropriate pull-to-refresh for scrollable data screens.
- Connect refresh to repository methods with visible refreshing state and stale-content preservation.

### P1-4. Performance readiness is not proven

Evidence:

- No current profile/release-mode performance run was found for startup, frame timing, scroll jank, or memory.
- Existing evidence is mostly static screenshots and widget/integration render checks.
- The UI uses costly visual effects in places, including blur/glass (`BackdropFilter`), gradients, opacity, image fades, large rich cards, and bottom chrome.

Impact:

- The app may pass screenshots and tests while still janking on mid-tier Android devices.
- Native feel depends heavily on first paint, input latency, and scroll performance.

Required remediation:

- Add profile-mode scenarios for launch to first usable home, groups scroll, group detail, QR scanner open, contribution to payment, payment refresh, and settings.
- Capture Flutter DevTools timeline/frame data or `integration_test` timeline summaries.
- Add budget thresholds before release claims: startup, worst-frame, missed frames, memory, and screenshot route render time.

### P1-5. Accessibility proof is incomplete for maximum native readiness

Evidence:

- Widget tests use semantics in many places, and `scripts/android_accessibility_structural_evidence.sh` can capture Android accessibility node trees.
- The script explicitly says structural evidence does not replace human auditory TalkBack review.
- No current iOS VoiceOver traversal proof was generated in this audit.

Impact:

- Screen-reader order, spoken clarity, modal focus, route-change announcements, dynamic loading announcements, and payment status comprehension remain unproven.

Required remediation:

- Run current Android TalkBack human traversal for auth, home, groups, scanner, contribution, payment, share, settings, and error states.
- Run or explicitly waive iOS VoiceOver with a recorded scope decision.
- Add tests for route-change and loading live-region semantics.

### P1-6. Offline/connectivity state is inferred from errors, not a native connectivity/cache model

Evidence:

- `connectivityStatusProvider` derives offline/degraded state from `lastError` string contents such as socket/network/offline/connection.
- No dedicated connectivity dependency or local cache layer is visible in the current dependency graph.

Impact:

- Users may get late or inaccurate offline state.
- There is no clear stale-cache experience for critical routes.

Required remediation:

- Add an explicit connectivity source and persistent local cache for groups, profile, ledger, and pending payment state.
- Model `offlineStale` separately from `error`.
- Add retry/backoff and "last updated" context where useful.

### P1-7. Native platform adaptation is partial

Evidence:

- Android manifest is reasonably native-aware: camera, notifications, app links, `adjustResize`, edge-to-edge, predictive-back callback.
- iOS `Info.plist` includes camera/photo strings and launch screen support.
- App UI is mostly custom Material/Flutter design; only auth dock uses Cupertino button styling in the current diff.
- iOS supported orientations include landscape, but the visual evidence is primarily 390x844 portrait.

Impact:

- iOS navigation, back-swipe expectations, sheet behavior, orientation behavior, and keyboard ergonomics are not fully proven.

Required remediation:

- Decide whether the product supports portrait only on phones; if so, constrain and document it.
- Test iOS simulator/device flows for auth keyboard, QR permission, share sheet, photo picker, and back gestures.
- Use adaptive dialogs/sheets/progress where platform conventions materially differ.

### P2-1. Static visual evidence is too narrow

Evidence:

- Current accepted Flutter visual evidence is dark mode at 390x844.
- Tests cover some 200% text scale and theme parity, but the screenshot matrix is not broad enough for maximum native confidence.

Impact:

- Compact phones, large phones, landscape, iPad/tablet, light mode, and 200% text scale screenshots can regress without being caught in the primary evidence bundle.

Required remediation:

- Expand screenshot matrix to:
  - 360x780 compact phone;
  - 390x844 baseline;
  - 430x932 large phone;
  - landscape phone;
  - tablet/iPad width;
  - light and dark;
  - 200% text for critical flows.

### P2-2. Route and evidence docs overstate completion

Evidence:

- Existing design docs say the current mobile design pass is code-owned complete.
- The current audit gate fails and evidence is stale against route changes.

Impact:

- Engineering and release governance can make decisions from stale status language.

Required remediation:

- Amend completion wording to "visual pass complete for previous route graph" until fresh evidence is regenerated.
- Add a release rule that route graph changes invalidate route screenshots and design compliance summaries.

## Recommended Implementation Roadmap

### Phase 1: Native Motion And Loading Foundation

1. Add route transition helper and migrate all production routes to `pageBuilder`.
2. Add route intent metadata and tests for transition coverage.
3. Add screen-level loading/refresh/empty/error state wrappers.
4. Add `AnimatedSwitcher` transitions using `CollectMotion`.
5. Add `CollectHaptics` and wire high-value actions.

Exit criteria:

- Route transition static check passes.
- Reduced motion test passes.
- Loading-state tests exist for auth, home, groups, group detail, payment, notifications, and settings.

### Phase 2: Evidence And QA Hardening

1. Regenerate visual route evidence from the active route list.
2. Remove stale route specs and generate route UAT specs from one source.
3. Add expected screen markers to device UAT.
4. Expand screenshot matrix beyond dark 390x844.
5. Re-run `collect_mobile_design_compliance_audit.sh --json` to pass.

Exit criteria:

- No stale/extra routes in evidence.
- Device route UAT fails on 404/recovery screens unless recovery is the expected screen.
- Light/dark/compact/large-text evidence exists.

### Phase 3: Native Device Readiness

1. Run Android physical or emulator profile-mode performance scenarios.
2. Run iOS simulator/device smoke for auth, share, photo picker, QR permission, and keyboard flows.
3. Run Android TalkBack traversal and iOS VoiceOver review or recorded iOS scope waiver.
4. Add explicit connectivity/offline cache model.

Exit criteria:

- Startup/frame/scroll metrics are recorded.
- Accessibility traversal signoff is current.
- Offline and degraded network behavior is deterministic and tested.

## Release Readiness Position

Not ready to claim "maximum native mobile experience" today.

Ready to claim:

- The app compiles and passes focused widget tests.
- The app has a substantial design system and route-render evidence foundation.
- Previous route evidence covered a broad 390x844 dark-mode route set.

Not ready to claim:

- Native-feeling navigation.
- Consistent perceived loading.
- Current fresh visual evidence for the active route graph.
- Current TalkBack/VoiceOver readiness.
- Profile-mode performance readiness.
- Full adaptive device coverage.

## Immediate Top Five Fixes

1. Done: implement app-wide route transitions with reduced-motion support.
2. Done: wire loading/refresh states across repository-backed screens.
3. Done: regenerate route visual evidence and remove stale route specs.
4. Done: replace raw auth colors with design tokens.
5. Done: add haptics and pull-to-refresh to the primary native flows.

## Current Next Fixes

1. Run `scripts/mobile_native_performance_profile.sh --json` on an unlocked Android device and attach the generated `summary.json`, `timeline.binpb`, and screenshots.
2. Run Android TalkBack human traversal and store the signoff beside the structural accessibility evidence.
3. Run iOS simulator/device smoke for auth keyboard, QR permission, share sheet, photo picker, back gestures, and VoiceOver.
4. Expand route screenshot evidence beyond dark 390x844 to compact phone, large phone, light mode, and 200 percent text for critical flows.
5. Add an explicit connectivity/cache model for offline stale data instead of deriving connectivity from error strings.

## Dirty Worktree Note

This audit was run on a dirty working tree with existing local changes in auth, routing/evidence scripts, iOS scheme, pubspec files, tests, and generated evidence references. The report did not attempt to revert or normalize those changes.
