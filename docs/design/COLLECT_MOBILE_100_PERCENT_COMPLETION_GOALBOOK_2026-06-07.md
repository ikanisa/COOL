# Collect Mobile 100% Completion Goalbook

Prepared: 2026-06-07
Repo: `/Volumes/PRO-G40/COOL`
Scope: Collect Flutter mobile app only. The Admin PWA is excluded except where
mobile release gates require it as existing release evidence.

## Master Goal

Bring the Collect Flutter mobile app to a verified 100% screen, popup, wizard,
accessibility, platform-native, and validation-complete state for the current
Groups/SMS-first product.

100% means every current and missing mobile user journey is implemented,
reachable, privacy-safe, accessible, responsive, tested, rendered, and backed by
fresh evidence from the exact current worktree. It does not mean "the code looks
complete" or "route tests did not fail."

## Non-Negotiable Completion Rules

- Preserve the mobile shell contract: `Home`, `Groups`, `Settings`.
- Keep Collect as a Rwanda-first MoMo group collection app.
- Use Collect ID as the member-facing identity. Do not add names, avatars,
  anonymity pickers, public phone numbers, manual SMS paste, or contributor
  self-reported transaction IDs.
- Receiver MoMo details, raw SMS, PINs, OTPs, support evidence, and private
  phone numbers stay out of public group, share, notification, and ledger
  surfaces.
- iPhone users can join and contribute; group creation remains Android/web
  owner-side because SMS verification needs Android access.
- No route, test, or screen may reintroduce Buro, crypto, wallet, staking,
  token, buy/sell/convert, or legacy workflow concepts.
- Do not call the app 100% until every evidence gate below passes on the final
  tree.

## Required 100% Capability Set

### 1. Route And Screen Completeness

All routes in `collectRoutePaths` must render without exceptions in widget
tests, physical-device route matrix, and browser/mobile-render smoke where
applicable.

Required route groups:

- Onboarding, legal consent, auth success/failure.
- Home, Groups, Settings shell routes.
- Profile setup, readiness, account, delete request, privacy, help, legal.
- SMS, notification, camera, offline, sync, and platform-unavailable states.
- Groups list, join portal, scanner, create wizard, detail, success/joined.
- Group profile, settings, members, ledger, share QR/deep link.
- Owner lifecycle: leave, close, transfer owner, remove member.
- Contribution, MoMo waiting, payment status, payment state details.
- Payment support review and fresh-link request.
- Invalid, expired, and not-found recovery states.

Acceptance evidence:

- `test/app_shell_test.dart` route registration covers every route.
- `integration_test/mobile_route_matrix_device_uat_test.dart` includes every
  route that should render on device.
- `scripts/mobile_route_render_smoke.sh` screenshot summary covers the stable
  mobile route set and reports nonblank captures.

### 2. Popup, Sheet, Dialog, Snackbar Completeness

Required transient UI:

- Sort sheets for groups, ledger, and members.
- QR share/save snackbars.
- Sign-out and account-delete confirmations.
- Owner lifecycle confirmations.
- Permission recovery sheets/screens for SMS, notifications, and camera.
- Payment support review wizard with issue category, safe-note guidance,
  submit state, failure state, and success state.
- Fresh-link request flow for expired links.

Acceptance evidence:

- Widget tests tap each popup/sheet/dialog entry point.
- Every destructive action requires confirmation.
- Snackbars and sheets avoid private receiver/SMS/PIN/OTP leakage.

### 3. Wizard And Core Flow Completeness

Required wizards:

- Onboarding: product purpose, privacy boundary, setup/permission summary,
  terms/privacy acceptance.
- Auth: WhatsApp phone entry, OTP send, real resend cooldown, verify,
  failure/retry, legal-consent gate.
- Profile setup: Collect ID, MoMo input, device readiness, back controls,
  validation, saving, completion.
- Create group: basics, receiver/SMS readiness, visual profile, final review,
  create success, SMS-denied recovery.
- Contribution: amount entry, validation, review, duplicate pending-intent
  guard, MoMo handoff, cancel, waiting, expired retry, support review.
- Owner lifecycle: leave, close, transfer owner, remove member.

Acceptance evidence:

- Focused widget tests cover happy path, validation failure, cancel/back, and
  submitted states for each wizard.
- Persona smoke tests cover member, contributor, owner, and recovery journeys.

### 4. Native Mobile UI And Accessibility

Every user-facing mobile screen must pass:

- Minimum interactive targets: Android 48x48 and iOS 44x44 logical pixels.
- Labels for custom icon/tap controls.
- No color-only status.
- Visible loading, disabled, focused, error, empty, success, and submitted
  states.
- 200% text-scale usability without clipped primary actions or unreadable
  critical information.
- Reduced-motion compliance through `CollectMotion`.
- Compact phone, tall phone, landscape, and tablet/foldable layout review.
- TalkBack and VoiceOver manual checks on representative flows.

Acceptance evidence:

- Flutter accessibility guideline tests for tap target, iOS tap target,
  labeled tap target, and text contrast.
- Large-text widget tests at `TextScaler.linear(2)`.
- Fresh screenshots for representative mobile viewports and at least one
  physical Android device pass.

### 5. Architecture And State Completeness

Implementation must stay modular:

- Feature screens use repository/provider interfaces, not cross-feature
  internals.
- Local/seeded repository behavior supports all new flows.
- Live Supabase paths use existing RPC/support-request surfaces unless a
  documented migration is truly required.
- Support requests remain privacy-safe and do not store raw SMS bodies in the
  mobile UI path.
- Route constants, route builders, tests, and docs remain synchronized.

Acceptance evidence:

- `flutter analyze` passes.
- Repository and route tests cover seeded/local behavior.
- Supabase contract tests continue to pass where support APIs are referenced.

## Execution Phases

### Phase 0 - Stabilize Tooling And Current Tree

Goal:
Make the worktree analyzable before claiming any implementation progress.

Tasks:

- Clear stale hung local validation processes from previous runs without
  killing unrelated Dart MCP servers.
- Prefer the pinned repo toolchain:
  `/Volumes/PRO-G40/flutter_3_44/bin/flutter`.
- Run checks serially, not in parallel.
- Use `--no-pub` after dependency state is known-good.
- If Flutter startup hangs, record process state and remediation steps before
  continuing broad validation.

Required commands:

```sh
/Volumes/PRO-G40/flutter_3_44/bin/flutter --version
/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed lib test integration_test
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub
```

Exit criteria:

- Formatter either passes or reports concrete file edits to apply.
- Analyzer gives actionable output or tooling blocker is documented with exact
  process state.

### Phase 1 - Fix And Finish Current Mobile Completion Patch

Goal:
Make the currently added completion screens compile, render, and behave
correctly.

Tasks:

- Fix any analyzer errors from the new routes, provider overrides, auth consent
  gate, create wizard, payment review, owner lifecycle, and permission recovery.
- Ensure `/onboarding/*` and `/auth/*` are standalone shell routes without
  bottom navigation.
- Ensure `/auth` cannot send OTP until legal consent is accepted.
- Ensure owner lifecycle success actions never navigate to a locally removed
  group.
- Ensure fresh-link, support-review, and owner lifecycle local methods work in
  seeded mode and are privacy-safe in live mode.

Exit criteria:

- `flutter analyze --no-pub` passes.
- Targeted tests for new mobile completion routes pass.

### Phase 2 - Complete Remaining Missing Behavior

Goal:
Close any product gaps that remain after Phase 1.

Tasks:

- Add explicit notification denied/recoverable state tests.
- Add scanner camera-denied tests and QR recovery path tests.
- Add OTP resend cooldown test with fake time or controlled pump duration.
- Add create-group step validation and review tests.
- Add payment duplicate-intent guard tests.
- Add owner lifecycle confirm/cancel/submit tests.
- Add sync-message rendering test.
- Add terms/privacy acceptance test and direct `/auth` legal gate test.

Exit criteria:

- Focused widget test suite covers all added flows and failure states.
- Persona smoke suite covers representative mobile routes and privacy
  boundaries.

### Phase 3 - Accessibility, Responsive, And Visual Evidence

Goal:
Prove 2026-grade native mobile UX rather than assuming it.

Tasks:

- Add accessibility guideline tests for representative route groups.
- Add 200% text-scale tests for onboarding, auth, profile, create group,
  contribution, payment status, ledger, members, settings, and permission
  screens.
- Run `scripts/mobile_route_render_smoke.sh` and review screenshot summary.
- Run `scripts/android_device_uat.sh` when a physical Android device is
  connected.
- Capture or refresh evidence references in release/design docs.

Exit criteria:

- Accessibility tests pass.
- Route render smoke reports nonblank captures.
- No obvious clipping, overlap, or hidden primary actions in screenshot review.

### Phase 4 - Release And Regression Gates

Goal:
Prove the mobile completion work did not regress product boundaries, backend
contracts, release gates, or privacy.

Required serial commands:

```sh
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub \
  test/app_shell_test.dart \
  test/features/mobile_completion_test.dart \
  test/features/design_system_components_test.dart \
  test/features/widgets_test.dart \
  test/persona_uat_smoke_test.dart \
  test/shared/collect_repository_test.dart \
  test/supabase_contract_test.dart

./scripts/collect_product_boundary_scan.sh --json
./scripts/mobile_route_render_smoke.sh
./scripts/release_artifact_manifest.sh --json
./scripts/flutter_mobile_release_gate.sh --json
```

Physical-device commands when available:

```sh
/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub integration_test/mobile_route_matrix_device_uat_test.dart -d <android-device-id>
./scripts/android_device_uat.sh
```

Exit criteria:

- All code-owned gates pass.
- Remaining blockers, if any, are external release signoff/UAT blockers and are
  documented separately from code completion.

## Tool, Skill, Agent, Plugin, And MCP Usage

Use these capabilities deliberately:

- Flutter engineer: route wiring, widget implementation, analyzer/test fixes.
- Accessibility and Inclusive Design: semantic labels, tap targets, contrast,
  TalkBack/VoiceOver checklist, large text.
- Adaptive, Responsive, and Platform-Native UI: compact/expanded widths,
  orientation, safe areas, platform permission flows.
- Flutter Design System and Tokenization: keep new components on Collect
  tokens, no raw colors in feature screens.
- Flutter Clean Architecture and Modularization: repository/provider boundaries
  and seeded/live behavior separation.
- Flutter and Full-Stack Test Pyramid: unit, widget, route matrix,
  integration, release smoke gates.
- Product Design audit lens: verify every flow has one primary action, clear
  recovery, privacy boundary, and no workflow-heavy dead ends.
- Dart MCP/package inspection when package APIs are uncertain.
- Browser/Chrome only for local rendered route screenshots or CDP smoke review.
- Supabase tooling only for live support/RPC contract verification, not for
  inventing new backend schemas unless implementation proves it is required.

## Completion Scorecard

Use this scorecard before calling the app 100%.

| Area | Required evidence | Status rule |
| --- | --- | --- |
| Route completeness | route constants, widget route test, device matrix | Pass only if every current route renders |
| Popup/sheet/dialog completeness | focused tap tests and privacy review | Pass only if every entry point is reachable |
| Wizard completeness | happy/fail/back/cancel/submit tests | Pass only if all required states are covered |
| Accessibility | Flutter guideline tests plus manual SR checklist | Pass only with automated and manual evidence |
| Responsive UI | 200% tests and screenshot review | Pass only if critical text/actions remain usable |
| Product boundary | boundary scan and copy review | Pass only with zero forbidden public UI hits |
| Privacy | tests/searches for raw SMS/PIN/OTP/private leakage | Pass only with no public leakage |
| Release gates | analyzer, tests, route smoke, artifact gates | Pass only on the exact final tree |

## Current Known Risks To Resolve First

- The latest mobile completion implementation is not yet analyzer-proven.
- Local SDK startup previously hung for `dart --version`, `dart format`,
  `flutter analyze`, and broad Git checks. Phase 0 must stabilize this before
  any final readiness claim.
- State/provider test overrides and new route widgets must be analyzer-checked.
- The first implementation pass added many surfaces quickly; focused tests must
  prove each entry point, not just route construction.

## Final Definition Of Done

The Collect mobile app reaches 100% only when:

1. Every capability in this goalbook is implemented.
2. Every exit criterion from Phases 0-4 passes.
3. Evidence files or command outputs identify the exact current worktree.
4. Any remaining release blockers are external/manual blockers, not missing
   code, missing screens, missing popups, missing tests, or unverified UI.
5. A final requirement-by-requirement audit confirms no item in this goalbook
   is incomplete, indirectly verified, or unverified.
