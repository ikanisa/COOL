# Collect Premium Mobile Frontend Implementation Goal - 2026-06-26

## Objective

Implement the findings from
`docs/release/product_design_mobile_audit_2026-06-26/README.md` so the Collect
Flutter mobile app presents as a clean, premium, production-ready frontend.

The end state is not a more verbose app. The end state is a quieter, clearer,
more polished mobile product where essential tasks are obvious, explanatory
copy is short, critical content is never clipped, bottom controls do not fight
the navigation, and every important route has verified mobile evidence.

## Source Evidence

- Audit report:
  `docs/release/product_design_mobile_audit_2026-06-26/README.md`
- Captured route evidence:
  `docs/release/product_design_mobile_audit_2026-06-26/screenshots/`
- Capture manifest:
  `docs/release/product_design_mobile_audit_2026-06-26/screenshot_manifest.json`
- Mobile route source:
  `lib/app/router.dart`
- Mobile entrypoint:
  `lib/main.dart`
- Existing validation helper:
  `scripts/mobile_route_render_smoke.sh`

## Non-Negotiable UI Direction

### 1. Clean Premium App Rule

Every mobile screen must feel like a finished premium app surface:

- Calm hierarchy.
- Fewer competing elements above the fold.
- Clear primary action.
- Clear recovery action when needed.
- No accidental clipping.
- No visually crowded top bars.
- No repeated dashboard decoration where a task screen needs focus.
- No oversized explanatory panels when a compact label, helper text, or state
  line would do.

### 2. No Noisy Guidance Rule

The app must not solve clarity by adding long explanations everywhere.

Allowed copy:

- Short labels.
- One-line helper text.
- State-specific microcopy.
- Short recovery text.
- Concrete button labels.

Avoid:

- Paragraphs in hero cards.
- Multi-line explanations inside decorative cards.
- Generic tutorial language on task screens.
- Repeated mentions of the same concept on the same screen.
- Legal or privacy copy inside cramped dashboard-style cards.

### 3. No Truncation Rule

Instructional, legal, recovery, payment, and permission text must not rely on
ellipsis at the primary reading point.

Group names and user-generated labels may truncate in compact cards only when:

- the full value is visible on the detail screen, and
- the truncated card still communicates the user's next action.

### 4. One Bottom System Rule

A screen may use bottom navigation or a persistent bottom action panel, but not
both in a way that reduces content comprehension.

Task-focused routes may hide or visually de-emphasize the bottom navigation
when the route is a modal-style job:

- create group
- contribution and payment
- payment support review
- account deletion
- fresh-link request
- legal document reading
- permission recovery

If bottom navigation remains visible, scrollable content must include enough
safe-area padding so the last meaningful control or paragraph is not covered.

### 5. Payment Clarity Rule

Every payment route must answer four questions within the first viewport:

- What is the state?
- What does it mean?
- What should the user do next?
- What is the fallback if that does not work?

## Workstreams

### Workstream 1: Shared Layout And Chrome

Goal: make the app shell and shared route structure support clean task screens.

Implement:

- Audit `CollectShell`, shared scaffolds, route wrappers, bottom navigation,
  fixed action panels, and safe-area handling.
- Add or update shared primitives for task routes that need focused chrome.
- Ensure every scrollable route has bottom padding that accounts for bottom nav,
  fixed CTAs, keyboard, and safe area.
- Prevent tooltip or hover artifacts from appearing as persistent mobile UI.
- Keep tap targets at least 44 x 44 logical pixels.

Acceptance:

- No captured route shows meaningful content hidden under bottom navigation.
- No task route shows a persistent CTA compressed directly into bottom
  navigation.
- Bottom navigation is stable on Home, Groups, and Settings.
- Modal/task routes use a cleaner focused layout where appropriate.

### Workstream 2: Copy Compression And Truncation Removal

Goal: remove noisy explanatory guidance while preserving user confidence.

Implement:

- Replace long card explanations with short state lines.
- Remove ellipsis from instructional hero copy on onboarding, permission,
  payment, fresh-link, settings, and legal routes.
- Replace generic CTA labels with task-specific action labels.
- Keep product terms consistent: Collect ID, SMS, MoMo, WhatsApp, receiver, and
  ledger must each mean one thing.

Acceptance:

- Instructional and recovery cards do not end in ellipsis at 390 x 844.
- No screen uses long explanation blocks to compensate for unclear hierarchy.
- Primary CTAs are concrete, such as `Create group`, `Open MoMo`, `Request
  review`, `Request fresh link`, `Open settings`, or `Scan QR`.

### Workstream 3: Home And Group Discovery

Goal: make first-use navigation confident and less crowded.

Routes:

- `/home`
- `/groups`
- `/groups/search`

Implement:

- Reduce top-bar competition on Home.
- Keep total collected prominent but simplify surrounding actions.
- Make search intent clear without truncation.
- Improve horizontal group card peeking so it looks intentional.
- Add clear empty and zero-result states for group search.
- Consider tabs or sections for My groups, Discover, Invites, and Recent only
  if they reduce complexity.

Acceptance:

- Home still shows total collected, primary group actions, Featured Groups, and
  My groups.
- Search field reads cleanly at 390 x 844.
- Group cards do not hide the user's core decision.
- Search empty states are verified by widget or route tests.

### Workstream 4: Group Creation, Join, Scan, And Sharing

Goal: make group onboarding and recovery task-focused.

Routes:

- `/groups/create`
- `/groups/join`
- `/groups/scan`
- `/c/:slug`
- `/groups/:collectionId/share`
- `/share/invalid`
- `/share/expired`
- `/share/expired/request`

Implement:

- Add concise field helper text and required-state visibility for group create.
- Make blocked creation states explain the missing requirement in one line.
- Add manual join/code fallback where scan or camera access is unavailable.
- Improve invalid, expired, and fresh-link screens with one clear recovery
  action.
- Refine share QR presentation so it reads as a deliberate sheet or page, not a
  half-positioned modal.
- Ensure privacy/receiver-exposure copy is short and fully visible.

Acceptance:

- Group creation has clear required fields and a clean CTA.
- Scan flow has a visible fallback.
- Fresh-link request has a concrete text-area prompt and visible CTA.
- Share sheet title, QR, share, save, and close controls are visible and not
  cramped.

### Workstream 5: Group Detail, Management, Members, And Profile

Goal: make group operations readable and role-aware.

Routes:

- `/groups/:collectionId`
- `/groups/:collectionId/manage`
- `/groups/:collectionId/profile`
- `/groups/:collectionId/members`

Implement:

- Show the full group name on the detail route.
- Add visible labels or highly clear affordances for finance-adjacent icon
  actions.
- Group management actions by risk and user role.
- Make member roles, invite state, and access state visible.
- Ensure group profile shows receiver and privacy-sensitive details only where
  appropriate.

Acceptance:

- Group detail communicates amount, members, activity, and next actions without
  unexplained icon-only controls.
- Management actions are grouped and scannable.
- Members route shows role/access information, not only names.

### Workstream 6: Contribution And Payment Lifecycle

Goal: redesign payment routes around state, meaning, action, and fallback.

Routes:

- `/groups/:collectionId/contribute`
- `/groups/:collectionId/pay/:intentId`
- `/groups/:collectionId/pay/:intentId/waiting`
- `/groups/:collectionId/pay/:intentId/state/pending`
- `/groups/:collectionId/pay/:intentId/state/confirmed`
- `/groups/:collectionId/pay/:intentId/state/expired`
- `/groups/:collectionId/pay/:intentId/state/needs-review`
- `/groups/:collectionId/support/payment/:intentId`

Implement:

- Give each payment state a distinct header and state line.
- Keep amount, receiver, state, next action, and fallback visible.
- Use consistent severity semantics:
  - waiting/pending: neutral progress
  - confirmed: success
  - expired: action required
  - needs review: support required
- Add concise support-review guidance that does not ask users to expose raw SMS
  or sensitive data in an unsafe way.
- Ensure fixed CTAs do not cover payment details.

Acceptance:

- Every payment route answers the four Payment Clarity Rule questions.
- Payment states are visually distinguishable without relying on color alone.
- Support-review form has clear validation and safe-data wording.
- Payment route evidence at 390 x 844 shows no clipped primary content.

### Workstream 7: Ledger

Goal: preserve the strong ledger screen and clarify pending versus confirmed
activity.

Route:

- `/groups/:collectionId/ledger`

Implement:

- Keep the current summary, search, filter, sort, and activity structure.
- Strengthen visual separation between pending and confirmed entries.
- Ensure filter controls have clear selected state and large tap targets.
- Avoid adding export/share features unless privacy-safe requirements are
  explicitly defined.

Acceptance:

- Ledger remains simpler and more readable than the payment screens.
- Pending entries are clearly not confirmed ledger entries.

### Workstream 8: Permissions, Platform, Offline, Sync, Notifications

Goal: make blocked states precise and actionable without over-explaining.

Routes:

- `/permissions/sms-denied`
- `/permissions/device`
- `/permissions/notifications-denied`
- `/permissions/camera-denied`
- `/platform/iphone-create-unavailable`
- `/notifications`
- `/offline`
- `/sync`

Implement:

- Connect each permission to the task it unlocks.
- Add one fallback action to every blocked state where a fallback exists.
- Make iPhone limitations precise: what is unavailable, what still works, and
  what the user can do next.
- Make offline and sync states show last known state, queued work, and retry
  affordance when available.

Acceptance:

- Permission screens do not truncate required explanations.
- Each blocked route has one clear primary action and one clear fallback.
- Platform limitation wording is precise and not alarming.

### Workstream 9: Settings, Account, Privacy, Legal, Help

Goal: make account and compliance surfaces readable, calm, and operational.

Routes:

- `/settings`
- `/settings/account`
- `/settings/account/delete`
- `/settings/privacy`
- `/settings/legal/terms`
- `/settings/legal/privacy`
- `/settings/help`

Implement:

- Reduce decorative card height on Settings where it hides operational items.
- Keep account settings scannable with clear sections.
- Make account deletion disabled-state reasoning visible.
- Treat legal and privacy routes as reading surfaces: readable line length,
  adequate contrast, generous bottom padding, and no dashboard chrome that
  competes with text.
- Keep destructive actions clearly labeled and recoverable.

Acceptance:

- Settings lower content is not hidden under bottom navigation.
- Delete request shows why Submit is disabled until a reason is selected.
- Legal and privacy pages are readable at 390 x 844 without clipped text.

### Workstream 10: Accessibility And Responsive Quality

Goal: prove the clean premium frontend works beyond screenshots.

Implement:

- Verify semantic labels on all icon-only controls.
- Verify tap target sizes on tabs, chips, action icons, and bottom navigation.
- Verify color contrast for secondary text, disabled text, and text over image
  cards.
- Verify text-scale behavior for payment, legal, settings, home, group detail,
  and creation routes.
- Ensure status is never communicated by color alone.

Acceptance:

- Focused accessibility/widget tests cover the touched shared components and
  critical routes.
- No route depends on color alone to communicate payment, permission, or ledger
  state.
- Large text does not create clipped primary content on critical flows.

## Screen Coverage Matrix

Every route captured in the product-design audit must be reviewed during
implementation.

| Route group | Must fix before done |
| --- | --- |
| Launch/auth/onboarding | clipped copy, generic CTAs, auth recovery |
| Profile/readiness | checklist clarity, blocked-state guidance |
| Home/groups/search | dense top bar, search clarity, card clipping |
| Create/join/scan/share | form guidance, manual fallback, share sheet polish |
| Group detail/manage/profile/members | full names, labeled actions, role grouping |
| Contribution/payment | state clarity, CTA safety, support-review guidance |
| Ledger | pending/confirmed separation and filter usability |
| Permissions/platform | concise task-specific recovery |
| Notifications/offline/sync | status, retry, and stale-data clarity |
| Settings/account/privacy/legal/help | bottom padding, reading ergonomics, disabled-state clarity |

## Explicit Non-Goals

- Do not redesign the public marketing website in this goal.
- Do not redesign the Admin PWA in this goal.
- Do not add new payment providers or mutate production services.
- Do not weaken release, signing, UAT, Supabase, privacy, or artifact gates.
- App Store, Play Console, App Review, TestFlight, App Privacy, and
  release-owner actions are Codex-owned under delegated release authority; stop
  only for missing credentials, signing assets, account access, source-of-truth
  metadata, or production mutations that cannot be executed safely from the
  available workspace and account context.
- Do not add verbose education copy to mask unclear hierarchy.

## Implementation Order

1. Shared layout and bottom-safe-area primitives.
2. Copy compression and truncation removal.
3. Payment lifecycle state redesign.
4. Group create, join, scan, share, and recovery flows.
5. Home, groups, settings, legal, and account cleanup.
6. Accessibility and text-scale hardening.
7. Route evidence recapture and report update.

## Required Validation

Run with the pinned toolchain unless the repo explicitly changes its toolchain:

```bash
/Volumes/PRO-G40/flutter_3_44/bin/dart format --set-exit-if-changed .
/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze
/Volumes/PRO-G40/flutter_3_44/bin/flutter test
MOBILE_ROUTE_RENDER_EVIDENCE_DIR=.cache/mobile_route_render_premium_frontend scripts/mobile_route_render_smoke.sh
scripts/collect_mobile_design_compliance_audit.sh --json
scripts/release_secret_scan.sh
scripts/collect_product_boundary_scan.sh --json
```

If the full route smoke is too slow during iteration, run focused route
screenshots first, but final completion requires the route evidence pass.

## Current Progress Evidence - 2026-06-26

Code-owned frontend changes currently in the worktree cover the first pass of
shared chrome, copy compression, task-route bottom navigation hiding, payment
state actions, permission/recovery copy, and account/legal readability.

Validated in this iteration:

- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass, no
  analyzer issues.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
  test/persona_uat_smoke_test.dart`: pass, `36` tests.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
  test/app_shell_test.dart test/features/design_system_components_test.dart`:
  pass, `47` tests.
- `./scripts/product_design_mobile_audit_artifact_gate.sh --json`: pass,
  `48` route screenshots at `390x844` with valid PNG headers.
- `COLLECT_VISUAL_EVIDENCE_DIR=.cache/flutter_visual_evidence_premium_frontend
  COLLECT_VISUAL_THEME_MODE=dark COLLECT_VISUAL_MOBILE_VIEWPORT=390x844
  /Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
  test/visual_evidence_capture_test.dart`: pass, `56` mobile route PNGs at
  `390x844` plus `5` admin PNGs. Mobile summary:
  `.cache/flutter_visual_evidence_premium_frontend/mobile/summary.json`.
- `MOBILE_ROUTE_RENDER_SUMMARY=.cache/flutter_visual_evidence_premium_frontend/mobile/summary.json
  ANDROID_DEVICE_UAT_SUMMARY=.cache/android_device_uat_premium_frontend/summary.json
  scripts/collect_mobile_design_compliance_audit.sh --json`: pass for all `56`
  production route screenshots and the real Android device UAT summary.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`: pass, no
  analyzer issues after the fresh evidence capture.
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub
  test/release_docs_test.dart`: pass, `54` tests.
- `scripts/release_secret_scan.sh`: pass via tracked-file fallback scanner.
- `scripts/collect_product_boundary_scan.sh --json`: pass, `153` scanned files
  and `0` product-boundary hits.

Observed during validation:

- Running multiple Flutter test commands in parallel can trigger a local
  macOS native-asset signing race:
  `build/native_assets/macos/objective_c.dylib: No such file or directory`.
  Rerunning the affected target without a competing Flutter command passed.
- `scripts/mobile_route_render_smoke.sh` built the Flutter web bundle
  successfully, but local Chrome/Chromium headless screenshot capture currently
  hangs before DevTools readiness even for `about:blank`. The fresh accepted
  route evidence for this pass is therefore the Flutter-test
  `RepaintBoundary` capture suite above, not Chrome CDP evidence.
- Follow-up Android UAT used emulator `Pixel_5_API_34_Lite` as
  `emulator-5554`; earlier attempts exposed stale token references in shared
  widgets, now fixed with `CollectRadius.mdBorder` and `colors.orangePaint`.
- `scripts/android_device_uat.sh` now supervises Flutter UAT in a dedicated
  process group, writes timeout summaries, and treats Flutter test failure
  markers in the retained log as failed UAT even when `flutter drive` exits `0`.
- Direct Gradle isolation for `:app:assembleProductionDebug` passed and wrote
  `.cache/android_gradle_direct_uat/result.json` with `status: pass`,
  `exit_code: 0`, and `elapsed_seconds: 90`.
- Real emulator evidence now exists at
  `.cache/android_device_uat_premium_frontend/summary.json`: `emulator-5554`,
  target `integration_test/mobile_route_matrix_device_uat_test.dart`,
  `status: pass`, `exit_code: 0`, `timed_out: false`, timeout `900` seconds,
  and log SHA-256
  `079ca95a033f3e3718ee1de2228564a0e11f35717310ef01ca11004266163d2f`. The log
  includes `58` route pass markers through `/sync`.

## Completion Evidence Required

Completion is not proven until all of the following exist:

- Source changes implementing the workstreams above.
- Updated or added focused tests for changed shared components and routes.
- Current analyzer and test output.
- Current mobile route screenshot evidence at 390 x 844.
- Updated report comparing before/after status against the 48 audit routes.
- Explicit list of any remaining blockers, limited to native-device, signing,
  credential, account-access, store-console, or production-service blockers.

## Done Definition

This goal is done only when:

- All P1 audit findings are fixed in code-owned frontend surfaces.
- All P2 findings are either fixed or explicitly justified with current
  evidence.
- The app has no visible noisy explanatory guidance pattern replacing clean
  hierarchy.
- Critical copy is not clipped at 390 x 844.
- Bottom navigation and persistent actions do not obscure content.
- Payment states are visually and semantically distinct.
- Create, join, scan, share, payment, recovery, account, legal, and settings
  routes all have current accepted screenshots.
- Validation commands pass or produce only documented external/non-code
  blockers.
