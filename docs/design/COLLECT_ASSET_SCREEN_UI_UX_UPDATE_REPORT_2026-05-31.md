# Collect Flutter UI/UX Update Report From Downloaded Screen Assets

Date: 2026-05-31
Source asset folder: `/Users/jeanbosco/Downloads/Collect`
Flutter app reviewed: `/Volumes/PRO-G40/COOL`

Superseded palette note: this report is retained for historical screen-flow and
interaction-pattern context only. The active color contract is the June 8
Collect palette in `DESIGN.md`: six primary color tokens, four visible paint
colors, and semantic accessibility/status tokens. Any
older legacy palette direction from the downloaded
references is no longer current implementation guidance.

## Executive Assessment

The downloaded asset folder contains 117 `screen.png` references and matching
HTML exports across 9 Stitch/Buro/Collect screen batches. There are 81 unique
screen images after duplicate detection. All screens should be treated as
design references, including the Buro/crypto finance remix screens, because
they define useful fintech interaction patterns: high-value amount hierarchy,
fast numeric entry, compact financial rows, bottom navigation, live status
surfaces, asset/activity timelines, segmented filters, and decisive payment
state handling.

The current Flutter app already has a broad route surface for Collect, but the
implementation is still a simplified shell compared with the references. Many
routes exist but are under-designed, use sparse copy, omit expected steps, or
collapse multi-step financial flows into one card. The largest gaps are:

- The visual identity was inconsistent with the reference system at the time
  of this report. That earlier reference palette is now superseded by the
  Collect six-primary-token color contract in `DESIGN.md`.
- Several screens are present only as thin state cards with empty messages,
  which weakens trust in a payment/SMS verification product.
- The contribution flow lacks the full amount entry, review, USSD/handoff,
  waiting, status, retry, and receipt progression shown in the references.
- The onboarding/profile/auth flow is missing the detailed WhatsApp number
  entry, OTP keypad, Collect ID explanation, MoMo link, and notification setup
  wizard.
- Owner/member/ledger/support/settings surfaces exist, but do not yet match
  the density, search/filter capability, financial row clarity, or trust copy
  in the assets.

This report is a frontend implementation checklist. It should be executed
additively: keep the existing product boundary and routes, but upgrade tokens,
shared widgets, and screen layouts using every supplied reference.

## Source Inventory

### Screen Sets Reviewed

- `stitch_remix_of_buro_fintech_app`: Buro wallet, buy amount, market home,
  earn products, asset overview/detail/activity, and logo screens.
- `stitch_remix_of_buro_fintech_app 2`: Collect utility screens: owner
  dashboard, empty searches, notification center, privacy/syncing, settings,
  members, connection error, support, needs-review state.
- `stitch_remix_of_buro_fintech_app 3`: Collect group detail, contribution
  amount/review/USSD/pending screens, group settings, share portal.
- `stitch_remix_of_buro_fintech_app 4`: Collect first-run, auth result,
  create group, SMS permission, payment states, join confirmation, iPhone
  restriction, MoMo missing profile state.
- `stitch_remix_of_buro_fintech_app 5`: Refined Collect screens plus Buro
  systemized finance screens: home groups list, member dashboard, auth WhatsApp,
  profile setup, join portal, contribution amount, payment verification, ledger,
  market/asset/buy/order references.
- `stitch_remix_of_buro_fintech_app 6` and `8`: duplicate utility screen sets
  matching set 2.
- `stitch_remix_of_buro_fintech_app 7`: duplicate app state screen set matching
  set 4.
- `stitch_remix_of_buro_fintech_app 9`: refined Buro system screens using the
  older accent variants that are no longer active palette guidance.
- Root `collect_app_complete_ui.html`: consolidated HTML UI reference.

### Duplication Notes

- 117 total screen images.
- 81 unique image hashes.
- Sets 2, 6, and 8 duplicate the same utility screen group.
- Sets 4 and 7 duplicate the same onboarding/auth/payment-state group.
- Duplication should not be ignored, because it confirms which flows the design
  generation process emphasized repeatedly: empty/error states, owner health,
  profile/settings, SMS permission, auth, create group, and payment states.

## Design System Findings

### Palette

The active palette is no longer the downloaded reference palette. The current
implementation must use only the six Collect primary color tokens documented in
`DESIGN.md`, plus the approved semantic accessibility/status tokens defined in
`CollectColors`.

Current cleanup rule:

- Keep brand color decisions centralized in `lib/app/theme/collect_colors.dart`.
- Use `CollectColors.brandPaintOptions` for color-picking UI.
- Use semantic getters such as `actionColor`, `success`, `warning`, `danger`,
  `info`, `textPrimary`, `textSecondary`, and `textMuted` in screens.
- Do not introduce feature-level literal colors or older reference palettes.

### Typography

Reference system:

- Hanken Grotesk for sharp minimal product UI in some sets.
- Inter for precise financial data in set 5.
- JetBrains Mono or mono-style labels for metadata, OTP/Collect IDs,
  timestamps, transaction IDs, and short codes.
- Large amount display is central: the amount is the first visual anchor on
  wallet, group, contribution, and payment screens.

Current app gap:

- `CollectTypography` already includes Hanken Grotesk, Inter, and JetBrains
  Mono fallbacks, but screen usage is inconsistent.
- Some important labels are empty (`MoneyHeroCard(label: '')`, many state
  `message: ''`), so hierarchy becomes visually strong but semantically thin.

Required update:

- Define dedicated text helpers for:
  - `amountDisplay`: large tabular amount with currency treatment.
  - `collectIdDisplay`: spaced 6-digit Collect ID.
  - `transactionMeta`: mono metadata.
  - `eyebrowLabel`: uppercase system label with restrained tracking.
- Avoid negative letter spacing in Flutter. Use 0 letter spacing except
  deliberate mono/ID labels.

### Shape, Layout, and Depth

Reference system:

- Two directions appear in the assets:
  - Extreme minimalist Buro style: almost flat, 4px to 8px radii, heavy
    whitespace, bottom-border inputs, no heavy cards.
  - Refined Collect style: 20px margins, 24px large containers, 8px precision
    buttons/inputs, soft grey panels, minimal shadows.
- Buro finance screens offer useful structural references for bottom navigation,
  tab filters, amount pages, activity rows, and full-height transaction flows.

Current app gap:

- `CollectRadius` is currently 2/4/8 only, while design docs and references
  include 24px containers and 8px precision controls.
- `CollectCard` is used everywhere, which can make the UI card-heavy. Several
  references use whitespace, rows, thin separators, and anchored bottom action
  bars instead.

Required update:

- Expand radius tokens: `control: 8`, `panel: 16`, `heroPanel: 24`,
  `sheet: 24 or 28`, `pill: 999`.
- Make `CollectCard` not the default for every row. Add:
  - `FintechListRow` with right-aligned amount and bottom divider.
  - `AmountEntryPanel` with direct amount focus and keypad compatibility.
  - `BottomActionSurface` matching the fixed CTA treatment.
  - `MinimalStatePanel` for empty/error screens without nested cards.

## Product Boundary Guidance For Buro/Crypto References

All Buro/crypto screens should be used for design behavior, not copied product
content.

Useful patterns to adapt:

- Wallet home and market home: high-level financial summary, trend/time range
  tabs, compact account rows, persistent bottom nav.
- Buy amount entry: full-screen amount input, segmented Buy/Sell/Convert
  controls, numeric keypad, maximum amount/review CTA behavior.
- Asset detail screens: financial header, chart/time filters, balance insights,
  activity timeline, compact metadata rows.
- Order submitted: post-action confirmation with short next step and
  recommendation strip pattern. For Collect, this becomes payment submitted,
  verification pending, or contribution confirmed.
- Asset list: searchable, filterable, dense list with symbol/avatar, title,
  subtitle, amount/status, and sign-in CTA pattern.

Do not import as product concepts:

- Crypto asset trading, APY, staking, earn products, token mint addresses,
  crypto referrals, card products, portfolio allocation, token buy/sell/convert.
- Buro/BURO naming or logo.
- Any exact proprietary layout or brand copy. Use the pattern language only.

## Current Flutter Surface Reviewed

Important current files:

- Routing: `lib/app/router.dart`
- Theme: `lib/app/theme/collect_colors.dart`,
  `lib/app/theme/collect_typography.dart`,
  `lib/app/theme/collect_spacing.dart`,
  `lib/app/theme/collect_radius.dart`,
  `lib/app/theme/collect_theme.dart`
- Shared widgets: `lib/shared/widgets/collect_components.dart`,
  `lib/shared/widgets/screen_scaffold.dart`
- Main screens:
  - `lib/features/home/home_screen.dart`
  - `lib/features/collections/collections_screen.dart`
  - `lib/features/collections/collection_detail_screen.dart`
  - `lib/features/collections/collection_create_screen.dart`
  - `lib/features/collections/collection_manage_screen.dart`
  - `lib/features/collections/share_screen.dart`
  - `lib/features/collections/group_link_screen.dart`
  - `lib/features/payments/contribution_flow_screen.dart`
  - `lib/features/payments/payment_intent_status_screen.dart`
  - `lib/features/profile/profile_setup_screen.dart`
  - `lib/features/settings/settings_screen.dart`
  - `lib/features/status/production_state_screens.dart`

The app has a strong route foundation. The priority is not adding random new
routes; it is upgrading the existing routes into the full reference-grade UI
flows.

## Critical Gaps And Required Updates

### P0 - Design Tokens And Shared Components

1. Re-tokenize the app to the reference palette.
   - Update `CollectColors.light` to use Paper canvas, Periwinkle text,
     Orange action, soft pink/Orange containers, subdued green success, and
     restrained danger.
   - Keep system appearance but keep it on the unified Paper contract; do not let system appearance drive the
     light product aesthetic.

2. Add missing component primitives.
   - Full-screen amount entry with large RWF amount and numeric keypad-safe
     layout.
   - Segmented control for transaction scopes and contribution modes.
   - Financial list row with right-aligned RWF and mono metadata.
   - Search field with clear button and empty-search state.
   - Notification/update list row.
   - OTP/Collect ID six-slot input/display.
   - Bottom fixed action bar for payment flows.
   - State panel with icon, title, clear message, primary action, secondary
     action.

3. Reduce card overuse.
   - Use cards for group summaries, payment summaries, QR panels, and modal
     surfaces.
   - Use rows, dividers, whitespace, and bottom action bars for activity,
     settings, and payment progression.

4. Tighten accessibility and touch behavior.
   - Increase minimum CTA height from 44 to 50 where payment action is
     involved.
   - Ensure all icons used as buttons have tooltips and semantic labels.
   - Make transaction IDs, Collect IDs, QR links, and USSD codes selectable or
     copyable.

### P0 - Auth, OTP, Onboarding, Profile

Reference screens:

- `brand_intro_first_run_splash`
- `auth_whatsapp_sign_in`
- `auth_otp_verification`
- `auth_success_state`
- `auth_failure_state`
- `profile_setup_collect_id_mobile`
- `profile_setup_link_momo_mobile`
- `profile_setup_notifications_mobile`
- `profile_momo_missing_state`

Current gap:

- `OnboardingScreen` is a minimal "Track support" state.
- `AuthScreen` was not fully inspected here, but route outputs show the
  surrounding auth result states are currently sparse.
- `ProfileSetupScreen` only captures MoMo number and does not show the
  reference Collect ID, security note, or wizard progression.

Required updates:

- First-run splash should be product-specific, not generic "Curated
  Intelligence". Use Collect, group MoMo collection, SMS verified ledger.
- Auth should include WhatsApp phone number entry with Rwanda-first country
  code treatment and a clear "Send code" CTA.
- OTP should use six boxes, numeric keyboard, resend countdown, and failure
  recovery.
- Profile should become a 3-step wizard:
  - Show generated Collect ID with mono/spaced digits and privacy copy.
  - Link MoMo number with security explanation.
  - Configure notification/SMS readiness with clear permission reason.
- Add an explicit MoMo missing state that routes from any contribution attempt
  when the profile is incomplete.

### P0 - Contribution And Payment Flow

Reference screens:

- `group_contribute_amount`
- `contribute_amount_entry`
- `contribute_confirm_details`
- `contribute_ussd_instructions_mobile`
- `contribute_momo_handoff`
- `contribute_waiting_for_confirmation`
- `payment_verification_status`
- `payment_status_success`
- `payment_status_expired_retry`
- `payment_status_needs_review`

Current gap:

- `ContributionFlowScreen` combines amount entry and intent creation in one
  card. It does not provide a separate review step.
- `PaymentHandoffScreen` only says "Pay in MoMo." and opens `*182#`.
- `ReturnFromMomoWaitingScreen` only says "Waiting."
- `PaymentStateDetailScreen` has empty messages for confirmed/expired/review
  states.

Required updates:

- Split contribution into explicit screens or explicit internal steps:
  - Amount entry: large RWF number, quick chips, clear target account and
    group purpose.
  - Confirm details: amount, group, receiver label, receiver MoMo, Collect ID,
    fees/disclaimer, and edit affordance.
  - USSD/handoff: show the exact dialer behavior and what the user must do
    next. If the app only opens `*182#`, do not pretend a complete dynamic code
    exists.
  - Waiting: show "listening for MoMo SMS", expected time, refresh, retry/help.
  - Status: show payment intent amount, receiver, reference ID, provider,
    status pipeline, and ledger route.
- Add `PaymentPipelineIndicator` directly into payment status and waiting
  screens.
- For expired retry: explain timeout and provide "Try again", "Open group",
  and "Need help" actions.
- For needs review: show amount received, time, transaction ID, likely group,
  and support path. In member app, do not expose admin-only assignment actions
  unless role-gated.
- For success: show amount, group, ledger update confirmation, receipt/details,
  and "Go to group".

### P0 - Home, Groups, Member Dashboard

Reference screens:

- `home_groups_list`
- `member_dashboard`
- Buro `wallet_home_*` and `market_home_*` for financial summary patterns.

Current gap:

- `HomeScreen` has a bento grid and quick actions but lacks the reference
  "Active Overview", live collection rows, system integrity badge, and more
  disciplined group list.
- Empty state copy is too thin: "Create" and "Name, share."

Required updates:

- Home should open with:
  - Total collected / confirmed support.
  - Active groups count.
  - Pending verification count.
  - SMS/system integrity state.
  - Primary collection rows with ID, raised amount, receiver label, and quick
    contribute/share action.
- Add member dashboard pattern:
  - Recent confirmations.
  - Pending payments.
  - Quick "Join Group", "Contribute", "Ledger", "Profile" actions.
- Add empty and empty-search states with useful copy and reset/clear actions.
- Preserve three main tabs from the app design plan: Home, Groups, Settings.
  If Activity becomes a tab in a reference, adapt it as a Home section or group
  ledger route unless the product decision changes.

### P0 - Group Detail, Share, Join, Group Settings

Reference screens:

- `group_detail_school_fees_mobile`
- `group_detail_school_fees_fund`
- `join_group_portal`
- `join_group_confirmation`
- `share_group_portal_mobile`
- `group_settings_mobile`
- Buro asset detail/activity screens for chart/activity hierarchy.

Current gap:

- `CollectionDetailScreen` lacks visible target/progress support, receiver
  trust line, copyable group ID, and the richer recent contribution list.
- `ShareScreen` and `GroupLinkScreen` should be checked and upgraded against QR
  and code-entry references.
- `CollectionManageScreen` should be upgraded using group settings and owner
  dashboard references.

Required updates:

- Group detail should include:
  - Group ID / short code copy.
  - Title and optional purpose.
  - Total raised, optional target, percent funded when target exists.
  - Receiver label and verified/synced status.
  - Recent confirmed contributions with initials/Collect ID, amount, timestamp.
  - Sticky or bottom "Contribute" CTA.
- Join group should include:
  - Six-digit code entry.
  - QR scanner entry point.
  - Link paste fallback.
  - Confirmation card with receiver and group before joining.
- Share should include:
  - QR code.
  - Copy link.
  - WhatsApp/SMS/share sheet actions.
  - Group code.
  - Clear warning that receiver MoMo is not exposed in the public share link.
- Group settings should include:
  - Group name and description.
  - Receiver details.
  - Target amount.
  - Public ledger/privacy toggle if product allows it.
  - Close group warning state.

### P1 - Owner Health, Members, Ledger

Reference screens:

- `owner_dashboard_group_health`
- `group_members_list`
- `ledger_group_activity`
- `ledger_empty_state`
- Buro asset activity detail screens for timeline/list treatment.

Current gap:

- `GroupOwnerDashboardScreen` is currently a menu card, not a dashboard.
- `OwnerSmsHealthScreen` exposes readiness rows, but not the financial health
  summary shown in the references.
- `GroupMembersScreen` lacks search, contribution totals, and row density.
- `LedgerScreen` should be checked against ledger references for search/filter
  and confirmed/needs-review handling.

Required updates:

- Owner dashboard should show:
  - Total raised.
  - Target/progress.
  - Pending intents.
  - Needs-review count.
  - SMS access/receiver configured state.
  - Recent activity.
  - Manage/close collection actions.
- Members list should show:
  - Search.
  - Collect ID/member label.
  - Role/status.
  - Contribution total.
  - Empty and empty-search states.
- Ledger should show:
  - Search/filter chips: all, confirmed, pending, needs review, mine.
  - Confirmed transaction rows with right-aligned RWF.
  - Transaction ID/timestamp in mono.
  - Empty state with "Contribute now" action.
  - Needs-review rows with confidence and support path.

### P1 - Settings, Support, Privacy, Notifications

Reference screens:

- `user_profile_settings`
- `notification_center`
- `support_help_center`
- `privacy_syncing_explanation`
- `connection_error_state`

Current gap:

- `SettingsScreen` is structurally present, but rows are generic and do not yet
  match the richer profile overview reference.
- `HelpSupportScreen` is a form only; the reference includes FAQ categories and
  support navigation.
- `PrivacyDataScreen` is just a simple state screen.
- There is no obvious notification center route in `collectRoutePaths`.

Required updates:

- Settings should show:
  - Collect ID badge/card.
  - Linked MoMo status.
  - Notification preferences.
  - Privacy/security.
  - Help/support.
  - Account/session controls.
- Add notification center route/screen:
  - Contribution confirmed.
  - Group update.
  - Goal reached.
  - Security notice.
  - Empty state.
- Privacy/syncing should explain:
  - Which SMS messages are read.
  - What is parsed locally.
  - What is sent to Supabase.
  - Retention/audit boundary.
  - Owner-only Android SMS capture limitation.
- Help center should combine FAQ category rows with the existing support
  request form.
- Connection error should include retry and offline-safe explanation.

### P1 - Platform-Specific Android/iPhone States

Reference screens:

- `android_sms_permission_education`
- `iphone_group_creation_restricted`

Current gap:

- Both screens exist in simplified form but lack the explanatory depth from
  references.

Required updates:

- Android SMS permission screen should say:
  - Used to detect MoMo confirmations.
  - Only relevant payment confirmations are parsed.
  - Needed for owner-led automated ledger updates.
  - Include privacy link and continue/decline states.
- iPhone restricted screen should say:
  - iPhone users can join and contribute.
  - Group creation requires Android owner SMS capture for now.
  - Provide "Join group" and "Back to groups" actions.
  - Avoid promising a future feature unless the product commits to it.

### P2 - Motion, Microinteractions, And Polish

Required updates:

- Add gentle progress/transition states for:
  - OTP verification.
  - Payment intent creation.
  - USSD handoff.
  - Waiting for SMS.
  - Payment confirmed ring.
- Add copied-to-clipboard feedback for Collect IDs, group links, transaction
  IDs, and USSD/reference codes.
- Add selected/filter states that use Orange sparingly and clearly.
- Add skeletons for lists and payment status loads.
- Ensure bottom nav and persistent payment/live-status pill do not overlap
  bottom CTAs.

## Screen-By-Screen Implementation Matrix

| Reference group | Current Flutter surface | Required update |
| --- | --- | --- |
| Splash / brand intro | `/onboarding` | Replace generic state with Collect-specific first-run intro and trust copy. |
| WhatsApp sign-in | `/auth` | Add phone-number form, Rwanda country treatment, secure note, send code CTA. |
| OTP verification | `/auth` or child step | Add six-slot OTP UI, resend countdown, keypad-friendly behavior. |
| Auth success/failure | `/auth/success`, `/auth/failure` | Replace sparse cards with strong state panels, retry/continue actions, useful copy. |
| Profile Collect ID | `/settings/profile` or onboarding step | Show Collect ID first, mono/spaced display, copy/security explanation. |
| Link MoMo | `/settings/profile` | Add secured MoMo explanation, phone validation, save/verify state. |
| Notifications setup | `/permissions/device` | Add notification preference rows and complete setup CTA. |
| Home groups list | `/home`, `/groups` | Add active overview, live collection rows, system integrity badge, richer empty/search states. |
| Member dashboard | `/home` | Add activity/pending/quick action dashboard sections. |
| Join portal | `/c/:slug`, `/groups` | Add code entry, QR scan entry, link paste, confirmation route. |
| Group detail | `/groups/:collectionId` | Add target/progress, receiver verified line, group ID copy, sticky contribute CTA. |
| Group settings | `/groups/:collectionId/manage` | Add target, receiver, privacy/public ledger, close group warning. |
| Owner dashboard | `/groups/:collectionId/owner` | Convert menu into metrics dashboard with health/action rows. |
| Members list | `/groups/:collectionId/members` | Add search, contribution totals, role/status rows. |
| Share portal | `/groups/:collectionId/share` | Add QR, WhatsApp/SMS/share actions, copy link, group code. |
| Contribution amount | `/groups/:collectionId/contribute` | Make amount the full-screen hero, with quick values and bottom CTA. |
| Confirm details | New step or same flow state | Add explicit review of receiver/group/amount before MoMo handoff. |
| USSD instructions | `/pay/:intentId/handoff` | Explain dialer handoff, show reference/USSD behavior truthfully. |
| Waiting confirmation | `/pay/:intentId/waiting` | Add SMS listening state, timeout/help/retry, pipeline indicator. |
| Payment status | `/pay/:intentId`, `/pay/:intentId/state/:state` | Expand pending/success/expired/review screens with full state copy and actions. |
| Ledger activity | `/groups/:collectionId/ledger` | Add search/filter, right-aligned RWF rows, transaction metadata, empty state. |
| Notification center | Missing obvious route | Add route and screen under Home/Settings. |
| Privacy/syncing | `/settings/privacy`, `/sync` | Replace blank state with clear SMS/privacy architecture explanation. |
| Support help center | `/settings/help` | Add FAQ categories plus support request form. |
| Connection error | `/offline` | Add robust retry/offline copy and action. |
| Buro wallet/home | Shared patterns | Adapt amount hierarchy, bottom nav, compact rows, chart/timeline patterns. |
| Buro buy amount | Contribution amount | Adapt keypad, amount focus, segmented controls, review CTA. |
| Buro asset detail/activity | Group detail/ledger | Adapt chart/time-filter/activity hierarchy without crypto content. |
| Buro asset list | Groups/members/search | Adapt dense searchable list treatment. |
| Buro order submitted | Payment submitted/status | Adapt concise post-action state and "Done"/next-step behavior. |

## UI/UX Optimization Checklist

### Visual Optimization

- Replace broad blue emphasis with Orange/Periwinkle product identity.
- Use amount-first hierarchy on every financial screen.
- Keep page backgrounds calm and Paper.
- Use cards less often; prefer rows and whitespace where references do.
- Make primary CTA placement consistent: bottom bar on flow screens, inline on
  list/detail screens only when secondary.
- Align amounts right in rows and use tabular figures.

### Interaction Optimization

- Preserve user progress through contribution steps.
- Make all copyable financial identifiers selectable/copyable.
- Keep destructive/irreversible actions visually separate.
- Add clear secondary exits: edit amount, cancel, back to group, help.
- Use loading/disabled states on async actions to prevent double submission.

### Information Architecture Optimization

- Separate member, owner, and support/admin surfaces clearly.
- Keep receiver MoMo visibility within payment/review/owner surfaces, not
  public share surfaces.
- Do not expose admin allocation actions to normal members.
- Keep Android owner SMS capability separate from iPhone join/contribute
  capability.

### Accessibility Optimization

- Minimum payment CTA height should be 50px.
- Use semantic labels for status chips, QR, copy buttons, and payment pipeline.
- Ensure text does not truncate critical amounts, receiver numbers, or action
  labels.
- Provide non-color status cues through icons and text.
- Respect dynamic text by using `FittedBox`, `Flexible`, and multi-line
  handling only where appropriate.

### Performance Optimization

- Use `ListView.builder` for ledgers, members, notifications, and long groups.
- Keep QR generation scoped to the visible share screen.
- Avoid rebuilding repository-derived full lists unnecessarily; prefer selected
  providers for counts and focused data.
- Avoid heavy image assets for UI chrome; use vector/icon primitives.
- Keep animation subtle and disable/reduce under reduced motion.

## Recommended Execution Plan

### Phase 1 - Foundation

- Update `CollectColors`, radius, spacing, and component tokens to match the
  reference system.
- Add shared components: OTP/Collect ID display, financial row, amount entry,
  bottom action bar, state panel, notification row, search/empty-search.
- Update design system catalog tests/screens to reflect the new components.

### Phase 2 - Critical Flows

- Rebuild onboarding/auth/profile wizard.
- Rebuild contribution/payment progression.
- Rebuild payment status states and MoMo/SMS permission states.

### Phase 3 - Core App Screens

- Upgrade home, groups list, group detail, share, join, and group settings.
- Upgrade owner dashboard, members, ledger, privacy, help, notifications.

### Phase 4 - Verification

- Run Flutter analyze and focused widget tests.
- Add widget tests for:
  - OTP field behavior.
  - Contribution amount validation.
  - Confirm details routing.
  - Payment state rendering.
  - Share QR/copy UI.
  - iPhone/Android platform state copy.
- Capture screenshots for representative flows at mobile viewport sizes.

## Final Priority List

Highest priority:

1. Token migration to Orange/Periwinkle/Paper reference design.
2. Full contribution flow split into amount, confirm, handoff, waiting, status.
3. Profile/auth wizard with WhatsApp OTP, Collect ID, MoMo link, notifications.
4. Payment state screens with complete copy and useful next actions.
5. Home/group detail amount-first financial hierarchy.

Next priority:

6. Ledger/member/owner dashboard density and search/filter behavior.
7. Share/join QR/code/link polish.
8. Privacy/SMS permission/support/notification center completeness.
9. Buro-derived interaction polish: amount keypad behavior, time filters,
   compact activity rows, post-action states.

Do not defer:

- Copy completeness for payment and SMS trust boundaries.
- Correct distinction between Android owner creation and iPhone join/contribute.
- Avoiding crypto/trading product concepts while still using the fintech visual
  and interaction patterns.
