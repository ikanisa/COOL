# Collect Mobile UI Implementation Goalbook

Prepared: 2026-05-31
Source report:
`docs/design/COLLECT_ASSET_SCREEN_UI_UX_UPDATE_REPORT_2026-05-31.md`
Asset reference folder: `/Users/jeanbosco/Downloads/Collect`
Implementation repo: `/Volumes/PRO-G40/COOL`

## Master Goal

Implement the full Collect Flutter mobile UI/UX upgrade identified in the
asset-screen analysis report, using all supplied screens as design references,
including the Buro/crypto finance remix screens for fintech interaction and
visual patterns.

The implementation must remain Collect-specific:

- Keep Collect as a Rwanda-first, Collect ID-only, MoMo/SMS-first Groups app.
- Preserve the primary mobile tabs: `Home`, `Groups`, and `Settings`.
- Use Buro/crypto screens only for reusable design patterns such as financial
  hierarchy, amount entry, compact transaction rows, segmented controls,
  bottom navigation, and post-action state handling.
- Do not add crypto trading, token assets, APY/staking, cards, portfolio,
  buy/sell/convert, Buro naming, or Buro product concepts.
- Keep changes additive and inside the existing Flutter app structure unless a
  small shared component extraction clearly reduces duplication.

## Definition Of Done

The UI upgrade is complete only when:

1. The app theme reflects the reference system: off-white/white surfaces,
   charcoal text, crimson high-intent actions, subdued status colors, and
   precision financial typography.
2. All P0 flows from the report are implemented: design tokens/components,
   auth/onboarding/profile, contribution/payment, home/member dashboard, group
   detail/share/join/settings.
3. All P1 support surfaces are implemented or intentionally deferred with a
   documented reason: owner health, members, ledger, settings, support,
   privacy, notifications, Android/iPhone platform states.
4. Payment and SMS trust-boundary copy is complete. No blank state messages
   remain on payment, auth, profile, SMS, privacy, or error screens.
5. Member-visible screens do not expose admin-only manual allocation actions.
6. iPhone group creation still uses the product-required warning:
   `group creation is available only on Android`.
7. `flutter analyze` passes.
8. Focused widget tests pass for the updated flows and components.
9. A screenshot or manual render pass confirms mobile layout quality for the
   representative screens listed in the validation matrix.

## Non-Negotiable Product Boundaries

- Use `Groups`, not goals or funds as the app navigation concept.
- User identity is the generated 6-digit Collect ID. Do not add real names,
  display names, avatars, or anonymity choices to member onboarding.
- Profile owns Collect ID and MoMo number.
- Group creation uses group name, optional description, and receiver MoMo
  synced from creator profile with edit capability where already supported.
- Android group creation requires SMS access education/consent.
- iPhone users can join and contribute, but cannot create groups.
- Contributions create payment intents and launch MoMo USSD through `tel:`.
- Confirmation comes from MoMo SMS ingestion/allocation and ledger posting,
  not from contributor-entered transaction IDs.
- Receiver MoMo details stay inside owner/payment/review flows, not public
  share surfaces.

## Phase 0 - Baseline And Guardrails

### Goal 0.1 - Freeze The Reference Scope

Objective:
Make the downloaded screen folder and the analysis report the controlling UI
reference for the implementation pass.

Implementation tasks:

- Keep `COLLECT_ASSET_SCREEN_UI_UX_UPDATE_REPORT_2026-05-31.md` as the design
  source of truth for this pass.
- Treat all 117 screens as references.
- Preserve the distinction between reusable Buro design patterns and forbidden
  Buro/crypto product concepts.

Acceptance criteria:

- The implementation goalbook and report are both present in `docs/design`.
- Any future PR/commit for this redesign can cite the goal IDs in this file.
- No new route or screen introduces crypto/trading language.

Validation:

- Manual review of changed copy and route names.
- `rg -n "Bitcoin|BTC|crypto|token|staking|APY|Buro|BURO|buy|sell|convert" lib`
  should only show intentional test/reference exclusions, not app UI copy.

## Phase 1 - Design System Foundation

### Goal 1.1 - Rebuild Color Tokens Around The Reference Palette

Objective:
Move the Flutter UI from generic blue/navy fintech styling to the Collect
reference system: off-white surfaces, charcoal text, crimson actions, subdued
status colors.

Likely files:

- `lib/app/theme/collect_colors.dart`
- `lib/app/theme/collect_theme.dart`
- `lib/app/theme/collect_component_tokens.dart`
- `lib/app/theme/app_tokens.dart` if still used
- `test/features/design_system_components_test.dart`

Implementation tasks:

- Add or remap color semantics for:
  - `paper`
  - `surfaceLow`
  - `surfaceHigh`
  - `inkBlack`
  - `actionCrimson`
  - `criticalCrimson`
  - `outlineSoft`
  - `successInk`
  - `dangerSoft`
- Make high-intent primary actions use crimson or charcoal according to
  component context.
- Keep semantic success/warning/danger states legible but quieter than primary
  CTAs.
- Rebase dark mode deliberately instead of letting old blue tokens leak into
  the new light identity.

Acceptance criteria:

- Primary action/focus color matches the reference crimson family.
- Page background is calm white/off-white, not blue-tinted.
- Status chips do not visually compete with primary payment actions.
- Existing widgets compile without raw color regressions.

Validation:

- `flutter analyze`
- Design system component widget test.
- Visual check of `/dev/design-system` in debug mode if runnable.

### Goal 1.2 - Finalize Typography For Money, IDs, And Metadata

Objective:
Make the app amount-first and identifier-safe across all financial screens.

Likely files:

- `lib/app/theme/collect_typography.dart`
- `lib/shared/widgets/collect_components.dart`
- `lib/shared/widgets/amount_input.dart`

Implementation tasks:

- Add dedicated typography helpers:
  - `amountDisplay`
  - `amountHero`
  - `amountCompact`
  - `collectIdDisplay`
  - `transactionMeta`
  - `eyebrowLabel`
- Use tabular figures for all amounts, Collect IDs, timestamps, transaction
  references, OTP fields, and USSD/reference codes.
- Keep standard text letter spacing at `0`; reserve tracking for mono labels
  and ID slots.
- Ensure long amounts scale down without truncating critical currency values.

Acceptance criteria:

- RWF amounts are the dominant visual element on home, group detail,
  contribution, payment status, and ledger screens.
- Collect IDs render distinctly and can be copied where relevant.
- Transaction metadata uses a consistent mono style.

Validation:

- Widget tests for amount display and Collect ID display.
- Visual check with long RWF values.

### Goal 1.3 - Add Missing Shared UI Components

Objective:
Create reusable components required by the reference screens so feature screens
do not duplicate layout and styling.

Likely files:

- `lib/shared/widgets/collect_components.dart`
- Optional new files under `lib/shared/widgets/`
- `test/features/design_system_components_test.dart`
- `test/features/widgets_test.dart`

Implementation tasks:

- Add or complete:
  - `AmountEntryPanel`
  - `FinancialListRow`
  - `CollectIdDisplay`
  - `OtpCodeField` or equivalent six-slot input
  - `BottomActionSurface`
  - `MinimalStatePanel`
  - `NotificationUpdateRow`
  - `SearchWithClearField`
  - `EmptySearchState`
  - `PaymentReviewSummary`
- Reduce card overuse by using list rows, separators, whitespace, and bottom
  action surfaces where the references do.
- Keep touch targets at least 50px for payment CTAs and at least 44px for
  secondary controls.

Acceptance criteria:

- Feature screens can compose the new flows without raw colors or ad hoc
  spacing.
- All new components are semantic and accessible.
- Text inside buttons and compact rows does not overflow.

Validation:

- Component widget tests.
- `flutter analyze`.

## Phase 2 - Auth, Onboarding, Profile

### Goal 2.1 - Rebuild First-Run Splash And Onboarding

Objective:
Replace sparse onboarding with a Collect-specific first-run experience grounded
in MoMo group collection and SMS-verified ledgers.

Likely files:

- `lib/features/status/production_state_screens.dart`
- `lib/app/router.dart`
- `test/persona_uat_smoke_test.dart`

Implementation tasks:

- Use `Collect` as the first-viewport signal.
- Replace generic copy such as "Curated Intelligence" or empty state messages.
- Explain the core loop: sign in, Collect ID, MoMo profile, join/create group,
  contribute, SMS-confirmed ledger.
- Keep the start action clear and route to auth.

Acceptance criteria:

- First-run screen reads as Collect, not a generic finance/productivity app.
- The screen contains no blank message strings.
- Primary CTA routes correctly.

Validation:

- Widget test for onboarding copy and route.

### Goal 2.2 - Implement WhatsApp Phone Sign-In And OTP UX

Objective:
Match the reference auth flow with Rwanda-first phone entry, OTP verification,
resend handling, and useful success/failure states.

Likely files:

- `lib/features/auth/auth_screen.dart`
- `lib/features/status/production_state_screens.dart`
- `lib/app/router.dart`
- `test/persona_uat_smoke_test.dart`

Implementation tasks:

- Add phone number form with Rwanda-first `+250` treatment while still
  supporting international numbers if backend allows it.
- Add clear "Send code" CTA and security note.
- Add six-slot OTP input with numeric keyboard behavior.
- Add resend countdown copy/state.
- Upgrade auth success and failure state screens with useful messages and
  retry/continue actions.

Acceptance criteria:

- User can understand whether the code is WhatsApp/SMS-delivered.
- Invalid OTP state gives retry and resend actions.
- Successful OTP routes to profile setup/readiness.

Validation:

- Widget tests for phone entry, OTP input, success/failure copy.
- Existing auth smoke tests still pass or are updated to the new UI.

### Goal 2.3 - Convert Profile Into A Three-Step Setup Wizard

Objective:
Make profile setup match the reference Collect ID, MoMo link, and notification
readiness flow.

Likely files:

- `lib/features/profile/profile_setup_screen.dart`
- `lib/features/status/production_state_screens.dart`
- `lib/shared/repositories/collect_repository.dart` if state support is needed
- `test/persona_uat_smoke_test.dart`

Implementation tasks:

- Step 1: show generated 6-digit Collect ID with copy/security explanation.
- Step 2: link primary MoMo number with privacy and verification copy.
- Step 3: notifications/device readiness explanation and completion CTA.
- Add a robust MoMo missing state reachable from contribution attempts.
- Do not ask for real names, display names, avatars, or anonymity settings.

Acceptance criteria:

- Profile setup always shows Collect ID when available.
- MoMo missing state has a direct "Link MoMo number" action.
- Completed profile returns the user to the appropriate prior flow or home.

Validation:

- Widget tests for profile wizard steps.
- Persona smoke test for incomplete profile gating.

## Phase 3 - Contribution And Payment Flow

### Goal 3.1 - Split Contribution Into Amount Entry And Review

Objective:
Upgrade the current single-card contribution screen into a reference-grade
payment intent flow.

Likely files:

- `lib/features/payments/contribution_flow_screen.dart`
- `lib/app/router.dart`
- `lib/shared/widgets/amount_input.dart`
- `lib/shared/widgets/collect_components.dart`

Implementation tasks:

- Make amount entry full-screen and amount-first.
- Show group title, purpose/description, target account/receiver label, and
  MoMo/USSD note.
- Keep quick amount chips.
- Add explicit review step showing:
  - Amount
  - Group
  - Receiver label
  - Receiver MoMo number
  - Collect ID/reference
  - Edit amount/details affordance
- Create the payment intent only after the review confirmation if the current
  repository flow supports it safely.

Acceptance criteria:

- User reviews receiver and amount before MoMo handoff.
- Invalid/zero amount is blocked with clear inline copy.
- Async action disables the CTA to prevent double intent creation.

Validation:

- Widget tests for invalid amount, quick chips, review step, and intent route.

### Goal 3.2 - Rebuild MoMo Handoff And Waiting Screens

Objective:
Make the USSD handoff and waiting-for-SMS screens clear, accurate, and
trustworthy.

Likely files:

- `lib/features/status/production_state_screens.dart`
- `lib/features/payments/contribution_flow_screen.dart`
- `lib/features/payments/payment_intent_status_screen.dart`

Implementation tasks:

- Handoff screen must explain that the system dialer opens to complete MoMo.
- If the app launches only `*182#`, copy must not claim a dynamic full USSD
  code exists.
- Waiting screen must show:
  - Amount
  - Group
  - Reference/payment intent
  - "Listening for MoMo SMS" state
  - Expected timing
  - Refresh/status action
  - Retry/help path
- Add `PaymentPipelineIndicator` to waiting and status screens.

Acceptance criteria:

- User understands what happens outside the app.
- User understands that ledger confirmation is automatic through SMS parsing.
- Waiting screen is actionable and not just "Waiting."

Validation:

- Widget tests for handoff copy and waiting state.
- Manual check on Android route behavior if device is available.

### Goal 3.3 - Complete Payment Status States

Objective:
Make success, pending, expired, and needs-review states production-grade.

Likely files:

- `lib/features/payments/payment_intent_status_screen.dart`
- `lib/features/status/production_state_screens.dart`
- `lib/shared/widgets/collect_components.dart`

Implementation tasks:

- Pending: show amount, receiver, status, reference, refresh, and help.
- Success: show payment recorded, amount, group, ledger update, receipt/details
  action, and group action.
- Expired: show timeout reason, try again, group, and help actions.
- Needs review: show member-safe details and support path; do not expose admin
  allocation controls.

Acceptance criteria:

- No payment state has empty message copy.
- All states have a primary next action and a safe secondary action.
- Needs-review member copy is clear but role-safe.

Validation:

- Widget tests for all payment states.
- Persona UAT smoke updates for payment progression.

## Phase 4 - Home, Groups, Join, Share, Group Detail

### Goal 4.1 - Upgrade Home And Member Dashboard

Objective:
Make the home screen match the reference "active overview" and Buro-style
financial summary patterns while preserving Collect navigation.

Likely files:

- `lib/features/home/home_screen.dart`
- `lib/features/collections/collections_screen.dart`
- `lib/shared/providers/collect_app_state.dart`
- `lib/shared/widgets/collect_components.dart`

Implementation tasks:

- Add active overview:
  - Total collected/confirmed support
  - Active group count
  - Pending verification count
  - SMS/system integrity state
- Add primary collection rows with ID, title, raised amount, receiver label,
  and quick contribute/share action.
- Add member dashboard section with recent confirmations and pending payments.
- Improve empty and empty-search states.

Acceptance criteria:

- Home is amount-first and actionable.
- User can see group/payment health without opening each group.
- Empty states explain what to do next.

Validation:

- Widget tests for empty home, populated home, pending payment state.

### Goal 4.2 - Upgrade Group Detail

Objective:
Make group detail the central contribution decision screen.

Likely files:

- `lib/features/collections/collection_detail_screen.dart`
- `lib/shared/widgets/collect_components.dart`
- `lib/shared/models/collect_models.dart` if target support exists/needs UI

Implementation tasks:

- Show group ID/short code with copy action.
- Show title and description/purpose.
- Show total raised, optional target/progress if model supports it, and member
  count.
- Show receiver label and verified/synced status.
- Show recent confirmed contributions with initials/Collect ID, amount,
  timestamp, transaction ID when available.
- Add bottom or prominent "Contribute" CTA.

Acceptance criteria:

- User can verify they are contributing to the right group/receiver.
- Contribution CTA is always easy to find.
- Recent activity rows match financial row style.

Validation:

- Widget test for owner/member group detail states.

### Goal 4.3 - Upgrade Join And Share Flows

Objective:
Make joining and sharing clear, copyable, and privacy-safe.

Likely files:

- `lib/features/collections/group_link_screen.dart`
- `lib/features/collections/share_screen.dart`
- `lib/features/collections/invite_screen.dart`
- `lib/app/router.dart`

Implementation tasks:

- Join portal:
  - Six-digit code entry
  - QR scanner entry point if supported or disabled explanatory control
  - Link paste fallback
  - Confirmation screen with group and receiver label
- Share portal:
  - QR code
  - Copy link
  - WhatsApp/SMS/share sheet actions where supported
  - Group code
  - Privacy note that receiver MoMo is not exposed publicly

Acceptance criteria:

- Shared receiver/payment details remain protected.
- Copy and QR paths work.
- Invalid/expired links have useful recovery actions.

Validation:

- Widget tests for share copy UI and invalid/expired link states.

### Goal 4.4 - Upgrade Group Creation And Management

Objective:
Bring create/manage screens up to the reference group setup and settings
standard while preserving the product boundary.

Likely files:

- `lib/features/collections/collection_create_screen.dart`
- `lib/features/collections/collection_manage_screen.dart`
- `lib/features/collections/group_creation_platform.dart`
- `lib/features/status/production_state_screens.dart`

Implementation tasks:

- Create group:
  - Step or section for name/description.
  - Receiver MoMo synced from profile, editable with clear trust copy.
  - SMS permission education before or during creation on Android.
  - Success state with share/open actions.
- Manage group:
  - Group profile fields.
  - Receiver details.
  - Optional target amount if model supports it.
  - Public/private ledger setting only if product/backend supports it.
  - Close group warning state if behavior exists or is planned.
- iPhone creation restricted state keeps exact warning string.

Acceptance criteria:

- Android creator flow clearly explains SMS requirement.
- iPhone path clearly allows joining/contributing but blocks creation.
- Manage screen does not promise unsupported backend behavior.

Validation:

- Widget tests for Android/iPhone platform branching.
- Creation form validation tests.

## Phase 5 - Ledger, Owner, Members, Settings, Support

### Goal 5.1 - Upgrade Ledger And Activity

Objective:
Make ledger screens dense, searchable, and financially precise.

Likely files:

- `lib/features/ledger/ledger_screen.dart`
- `lib/shared/widgets/collect_components.dart`
- `lib/shared/providers/collect_app_state.dart`

Implementation tasks:

- Add filters: all, confirmed, pending, needs review, mine where data supports
  it.
- Add search where useful.
- Use right-aligned RWF financial rows.
- Show transaction ID/timestamp in mono.
- Add empty ledger state with "Contribute now".
- Add member-safe needs-review row.

Acceptance criteria:

- Ledger can be scanned quickly.
- Confirmed and review states are visibly distinct.
- Empty ledger is actionable.

Validation:

- Widget tests for ledger empty, confirmed, and review rows.

### Goal 5.2 - Upgrade Owner Dashboard And Members

Objective:
Turn owner and members screens from menu/list shells into operational group
health views.

Likely files:

- `lib/features/status/production_state_screens.dart`
- `lib/shared/providers/collect_app_state.dart`
- `lib/shared/widgets/collect_components.dart`

Implementation tasks:

- Owner dashboard:
  - Total raised
  - Pending intents
  - Needs-review count
  - SMS access
  - Receiver configured
  - Recent activity
  - Manage/share/member actions
- Members:
  - Search
  - Collect ID/member label
  - Role/status
  - Contribution total where available
  - Empty and empty-search states

Acceptance criteria:

- Owner can see group operational health in one screen.
- Members screen is useful beyond just listing labels.

Validation:

- Widget tests for owner health data states and members empty/populated states.

### Goal 5.3 - Upgrade Settings, Notification Center, Privacy, And Support

Objective:
Complete the non-payment utility surfaces so the app feels production-grade.

Likely files:

- `lib/features/settings/settings_screen.dart`
- `lib/features/status/production_state_screens.dart`
- `lib/app/router.dart`
- Optional new `lib/features/notifications/notification_center_screen.dart`

Implementation tasks:

- Settings:
  - Collect ID card
  - Linked MoMo status
  - Notifications
  - SMS access
  - Privacy/security
  - Help/support
  - Account/session
- Notification center:
  - Contribution confirmed
  - Group update
  - Goal/target reached if product supports targets
  - Security notice
  - Empty state
- Privacy/syncing:
  - Explain SMS parsing boundary
  - Explain what leaves the device
  - Explain retention/audit boundary
  - Explain Android owner limitation
- Help center:
  - FAQ/category rows
  - Existing support request form
  - Submitted state
- Connection error:
  - Retry action
  - Offline explanation

Acceptance criteria:

- There is no blank privacy/help/error copy.
- Notification center is reachable from Home or Settings.
- Privacy copy is truthful to current backend behavior.

Validation:

- Widget tests for settings routes, privacy copy, support submit state, and
  connection retry.

## Phase 6 - Quality Gates And Evidence

### Goal 6.1 - Focused Test Coverage

Objective:
Add enough coverage to protect the redesigned flows without making the suite
fragile.

Required tests:

- Design component rendering for new shared widgets.
- Auth phone and OTP flow.
- Profile wizard and incomplete profile gating.
- Contribution amount validation and review step.
- Payment handoff/waiting/status states.
- Group detail amount/receiver rendering.
- Share QR/copy UI.
- Android/iPhone platform states.
- Ledger empty/confirmed/review rows.
- Settings/help/privacy/notification routes.

Acceptance criteria:

- Updated focused tests pass.
- Existing release/docs tests still pass or are updated only when expected UI
  copy changed.

Validation commands:

- `flutter analyze`
- `flutter test test/features/design_system_components_test.dart`
- `flutter test test/features/widgets_test.dart`
- `flutter test test/persona_uat_smoke_test.dart`
- Broader `flutter test` when the targeted suite is stable.

### Goal 6.2 - Manual Mobile Render Verification

Objective:
Catch layout, overflow, and hierarchy issues that tests will not catch.

Representative screens to verify:

- Onboarding/splash
- WhatsApp sign-in
- OTP verification
- Profile setup Collect ID
- Profile setup MoMo
- Home populated
- Home empty
- Group detail populated
- Group create Android
- Group creation restricted iPhone
- Share group
- Join group
- Contribution amount
- Contribution review
- MoMo handoff
- Waiting for SMS
- Payment success
- Payment expired
- Payment needs review
- Ledger populated
- Ledger empty
- Owner dashboard
- Members list
- Settings
- Privacy/syncing
- Help/support
- Connection error

Acceptance criteria:

- No obvious text overlap.
- No clipped critical amounts, IDs, phone numbers, or CTA labels.
- Bottom navigation, live status pill, and bottom CTAs do not overlap.
- Screens remain usable at common compact Android viewport sizes.

Validation:

- Flutter integration screenshot pass, manual emulator/device pass, or browser
  render pass where feasible.
- Save evidence path or notes in release/design docs if this becomes a
  readiness gate.

## Sequencing Rules

- Do Phase 1 before broad screen rewrites. Tokens/components first prevent
  repeated raw styling.
- Do Phase 3 before lower-priority utility polish. Contribution/payment is the
  highest-risk user journey.
- Do not add unsupported backend promises just because a reference screen shows
  them. If a target, notification, QR scanner, or close-group feature lacks
  backend support, implement truthful UI or mark it blocked.
- When changing outward-facing copy, keep it concise and product-accurate.
- Keep admin-only allocation/review actions out of member screens unless role
  checks already protect them.

## Blocker Register

Known potential blockers:

- Target amount support may not exist consistently in the current models or
  backend. If absent, render optional target UI only when data is available.
- QR scanner support may require native permissions/dependencies. If not
  present, provide QR display and link/code entry first.
- Notification center may need real notification/event data. If backend data is
  absent, create a route-ready UI with repository-backed available events and
  truthful empty state.
- Dynamic USSD codes may not exist. Do not display generated codes unless the
  payment intent actually provides them.
- Android SMS access behavior must remain aligned with platform and privacy
  constraints.

## Implementation Tracking Table

| Goal | Priority | Status | Exit evidence |
| --- | --- | --- | --- |
| 0.1 Reference scope freeze | P0 | Complete | Report and goalbook present; `rg` boundary scan over `lib` shows no Buro/crypto/trading UI copy, only infrastructure/token false positives. |
| 1.1 Color token rebuild | P0 | Complete | Crimson/charcoal/off-white token migration implemented; `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub` passed. |
| 1.2 Typography finalization | P0 | Complete | Amount, Collect ID, transaction metadata, OTP, and eyebrow helpers added; focused tests passed. |
| 1.3 Shared components | P0 | Complete | Amount entry, Collect ID, OTP, financial row, minimal state, notification, search, filters, bottom action, and review components are used across updated screens. |
| 2.1 First-run onboarding | P0 | Complete | Onboarding renders Collect-first MoMo/SMS loop copy and is covered by compact route render matrix. |
| 2.2 WhatsApp/OTP auth | P0 | Complete | Rwanda-first WhatsApp phone entry, OTP field, retry copy, and auth-result states covered by persona tests. |
| 2.3 Profile wizard | P0 | Complete | Three-step Collect ID, MoMo, and device-readiness wizard plus no-profile gate covered by persona tests. |
| 3.1 Amount + review contribution | P0 | Complete | Amount entry, review summary, receiver/MoMo/Collect ID check, and intent creation-before-handoff covered by persona tests. |
| 3.2 MoMo handoff + waiting | P0 | Complete | USSD handoff, waiting state, no-paste-SMS copy, and pipeline indicator are implemented and route-render tested. |
| 3.3 Payment states | P0 | Complete | Pending, confirmed, expired, and needs-review member-safe states covered by persona tests. |
| 4.1 Home/member dashboard | P0 | Complete | Amount-first home overview, pending integrity state, recent activity, and empty states implemented and route-render tested. |
| 4.2 Group detail | P0 | Complete | Group code, receiver boundary, amount summary, recent activity, and contribute CTA implemented; target remains data-dependent and not promised when unsupported. |
| 4.3 Join/share flows | P0 | Complete | Join portal, code/link entry, QR explanatory fallback, share QR/copy/actions, and public receiver privacy note covered by tests. |
| 4.4 Group create/manage | P0 | Complete | Android owner setup, receiver MoMo sync/edit, SMS education, management health, target-limit, close-boundary copy, and iPhone restriction covered by tests. |
| 5.1 Ledger/activity | P1 | Complete | Search, all/confirmed/pending/needs-review/mine filters, right-aligned RWF rows, pending intent rows, and empty-search state covered by ledger tests. |
| 5.2 Owner/members | P1 | Complete | Owner health dashboard and searchable member list implemented; contribution totals remain intentionally absent until backend supplies per-member totals. |
| 5.3 Settings/support/privacy/notifications | P1 | Complete | Settings, notification center, privacy/data, help/support, account/session, legal terms/privacy, connection/sync copy, and support submit states implemented and tested. |
| 6.1 Focused test coverage | P0 | Complete | `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart test/persona_uat_smoke_test.dart` passed with 36 tests. |
| 6.2 Manual render verification | P1 | Complete | Compact mobile route render matrix at 390x844 covers representative onboarding, auth, profile, home, group, join, share, contribution, payment, ledger, owner, members, settings, privacy, help, notification, offline, and sync routes with no Flutter layout exceptions. `flutter run --no-pub -d web-server --web-hostname 127.0.0.1 --web-port 53535` served the Flutter HTML bundle; device screenshots were not captured in this pass because the local headless browser path did not emit an image. |

## Final Implementation Objective

After executing this goalbook, the Flutter app should feel like a complete,
production-grade Collect mobile experience: a precise, amount-first,
SMS-verified MoMo group collection app with clear trust boundaries, strong
payment-state handling, and a polished fintech interface derived from every
provided screen reference without importing unrelated Buro/crypto product
features.
