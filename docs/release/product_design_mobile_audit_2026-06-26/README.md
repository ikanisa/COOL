# Collect Flutter Mobile App Product Design Audit

Date: 2026-06-26
Surface: Flutter mobile app rendered in Codex in-app browser
Viewport: 390 x 844
Build mode: Flutter web review bundle with `COLLECT_MOBILE_EVIDENCE_MODE=true`
Evidence folder: `docs/release/product_design_mobile_audit_2026-06-26/screenshots/`
Manifest: `docs/release/product_design_mobile_audit_2026-06-26/screenshot_manifest.json`

## Current Follow-Up Evidence

The audit screenshots in this folder are the 48-screen pre-fix product-design
audit evidence. Current post-fix route evidence for the premium frontend pass
was captured separately with Flutter test rendering because local Chrome
headless/CDP capture hung before DevTools readiness in this session.

- Current mobile route evidence:
  `.cache/flutter_visual_evidence_premium_frontend/mobile/summary.json`
- Runtime: `flutter_test_repaint_boundary_member_shell`
- Viewport/theme: `390x844`, dark mode
- Coverage: `56` of `56` mobile route-smoke routes
- Design compliance route gate: pass when
  `MOBILE_ROUTE_RENDER_SUMMARY=.cache/flutter_visual_evidence_premium_frontend/mobile/summary.json
  ANDROID_DEVICE_UAT_SUMMARY=.cache/android_device_uat_premium_frontend/summary.json
  scripts/collect_mobile_design_compliance_audit.sh --json` is used
- Android device UAT: pass at
  `.cache/android_device_uat_premium_frontend/summary.json`, using
  `emulator-5554`, target
  `integration_test/mobile_route_matrix_device_uat_test.dart`, timeout `900`
  seconds, and log SHA-256
  `079ca95a033f3e3718ee1de2228564a0e11f35717310ef01ca11004266163d2f`.

## Audit Scope

This audit reviews the Flutter mobile app UI/UX first, using current-run screenshots captured from the app already launched in Codex's in-app browser at `http://127.0.0.1:57124/#/home`.

The audit covers:

- Onboarding and authentication
- Profile setup and readiness
- Home and primary navigation
- Group discovery, search, join, QR scan, creation, detail, share, and link states
- Contribution and payment status journeys
- Ledger, management, members, and group profile routes
- Permission, platform, notification, offline, and sync states
- Settings, account, privacy, legal, help, and deletion routes

This audit does not cover admin PWA, public marketing site, native device permission dialogs, physical camera/SMS behavior, keyboard-only traversal, screen-reader output, or live Supabase data. Those need separate device and accessibility testing.

## Executive Summary

The app has a strong, coherent visual identity: dark mobile-first surfaces, glass-like controls, high energy accent actions, consistent iconography, and a clear bottom navigation model. The product story is also coherent: Collect is about group savings, MoMo payment verification, QR/link sharing, and a confirmed ledger.

The main UX risk is not lack of polish. It is functional clarity under real mobile constraints. Several important screens use fixed bottom controls and dense cards that visually compete with the bottom navigation. Long labels are clipped, hero cards truncate instructional copy, and some key decision screens do not make the next step obvious enough without scrolling or prior product knowledge.

Top priorities:

1. Fix bottom-action and bottom-navigation overlap risk across create, payment, legal, settings, and recovery screens.
2. Reduce truncation in hero cards, search fields, group names, and status labels.
3. Make payment status states easier to distinguish at a glance.
4. Clarify critical flows with one visible primary action and one visible recovery action per screen.
5. Add stronger form guidance, validation, and disabled-state explanations on create, fresh-link, delete, and support-review screens.

## Evidence Summary

Captured screens: 48

Console errors during capture: 0

All screenshots were captured from the current Codex in-app browser session. No prior screenshots were used as audit evidence.

## Overall Strengths

- Distinctive visual system: the app avoids generic Material defaults and feels product-specific.
- Primary navigation is stable: Home, Groups, and Settings are consistently visible.
- Key domain objects are visible early: total collected, group cards, member count, QR/share, payment state, ledger.
- Recovery states exist: SMS denied, camera denied, notification denied, offline, sync, expired link, invalid link, support review.
- Privacy/legal/account surfaces are present, which is important for a finance-adjacent group payments product.
- Icons reinforce core functions: groups, QR, ledger, settings, payment, notifications.
- Demo data is realistic enough to audit core journeys.

## Cross-App UX Risks

### P1: Fixed bottom controls compete with content and navigation

Screens affected: create group, payment intent, payment waiting, legal pages, settings, fresh-link request, account deletion, some permission states.

The app often has three stacked vertical systems: scrollable content, a fixed action panel, and the fixed bottom navigation. At 390 x 844 this compresses content and can hide important form state, explanations, and secondary actions.

Recommendation:

- Reserve a predictable safe-area spacer above bottom navigation.
- Use one bottom action system at a time. If a screen needs a persistent CTA, consider hiding bottom navigation for modal/task flows.
- Keep critical form fields above the fold and put long explanations in scrollable content, not clipped cards.

### P1: Text truncation weakens comprehension

Screens affected: onboarding, home, group detail, payment intent, settings, legal, fresh-link request, share group.

Examples visible in screenshots:

- Onboarding hero text ends with an ellipsis.
- Home search field and group names truncate aggressively.
- Group detail title truncates the group name in the hero card.
- Payment status chip/title truncates "Waiting for MoMo SMS verificat..."
- Settings hero text truncates "Profile, alerts, access, and priv..."
- Fresh-link hero text truncates "Expired links do not reveal receiv..."

Recommendation:

- Avoid ellipsis in instructional copy. Let it wrap to two or three lines.
- Use shorter labels where space is constrained.
- For long group names, show a short display name plus a detail screen where the full name is readable.
- Treat payment and legal copy as content that must be read, not decorative card text.

### P1: Payment states need clearer differentiation

Screens affected: payment intent, waiting, pending, confirmed, expired, needs review, support review.

The payment screens are visually polished, but the status language and layout are too similar across states. Users need to instantly know whether they should wait, open MoMo, retry, request support review, or return to ledger.

Recommendation:

- Give each payment state a unique header pattern: status, meaning, required action, and fallback.
- Use consistent severity color semantics: pending/waiting, success, expired/error, needs review/support.
- Put the most likely action first. Example: "Open MoMo", "I completed payment", "Request review", "Try again", "Open ledger".

### P2: Some icon-only controls need stronger accessible labels and visual affordance

Screens affected: home top actions, group detail action row, settings cards, share modal close.

The visual language uses icons heavily. That works for scan/share/settings after learning, but the first-time experience depends on labels and semantics.

Recommendation:

- Keep visible labels under the most important icon actions on first-use screens.
- Verify semantics labels for all icon buttons.
- Ensure tap targets remain at least 44 x 44 logical pixels.

### P2: Dark visual style risks contrast issues in secondary text

Screens affected: settings, legal, ledger, payment, onboarding, permission screens.

The white primary text is strong, but gray secondary text on purple/black cards may be marginal in some states, especially over image-backed cards.

Recommendation:

- Audit contrast for small secondary text, disabled text, and text over generated card images.
- Avoid putting required instructions over busy media unless a strong scrim guarantees contrast.

## Journey 1: Launch, Onboarding, Authentication

Screens:

- `01-launch.png`
- `02-onboarding.png`
- `03-auth-phone.png`
- `04-auth-success.png`
- `05-auth-failure.png`

Health: Good foundation with clarity risks.

What works:

- Onboarding is clear about the core product: MoMo groups verified by SMS.
- Step indicator gives orientation.
- Checklist pattern helps explain the journey.
- Auth success/failure routes exist, which is good for recovery design.

Issues:

- The onboarding hero copy truncates before completing the explanation.
- The step tabs are compact and may be hard to tap accurately.
- "Sign in with WhatsApp" in the checklist may conflict with the app's wider SMS/MoMo framing unless WhatsApp is truly the auth path.
- Auth screens need to make the expected credential or phone format immediately clear.

Recommendations:

- Let onboarding hero copy wrap fully.
- Make the primary CTA language specific to the next step, not generic "Continue" on every page.
- Add explicit recovery paths on auth failure: retry, change phone, contact support.
- Confirm that auth channel naming is consistent across product copy: WhatsApp, SMS, MoMo, and Collect ID each mean different things to users.

## Journey 2: Profile Setup and Readiness

Screens:

- `06-profile-setup.png`
- `07-profile-readiness.png`

Health: Present but likely under-explained.

What works:

- Profile setup and readiness are separate routes.
- The app acknowledges prerequisites before group actions.

Issues:

- The readiness concept may not be self-explanatory for contributors.
- If profile setup blocks group creation, users need to know exactly what is missing and why.

Recommendations:

- Show a compact readiness checklist: identity, phone, MoMo receiver, permissions.
- Use task-specific copy: "Complete this to create a group" or "Complete this to receive group payments."
- Put the blocked action and the missing requirement on the same screen.

## Journey 3: Home and Primary Navigation

Screen:

- `08-home.png`

Health: Strong visual entry point, moderate scanability risk.

What works:

- Total collected is prominent and product-specific.
- Primary actions are visible: Create, Join, Scan QR, Share.
- Featured groups and My groups create a useful hierarchy.
- Bottom navigation is clear and stable.

Issues:

- The top search field truncates after a short string and competes with two icon buttons.
- The QR icon shows a tooltip-like label during capture, which can overlap nearby content.
- Horizontal cards are partially cut at the right edge. This communicates carousel affordance, but it also hides important group information.
- The first viewport is dense: logo, search, two top icons, total card, four action buttons, Featured Groups, My groups, and bottom nav.

Recommendations:

- Consider a two-row top bar: identity/profile plus search, then compact utility icons.
- Use a bottom sheet or dedicated "Actions" rail if four quick actions become too crowded.
- Make carousel clipping intentional with enough peeking to signal scroll, not accidental truncation.

## Journey 4: Groups List and Search

Screens:

- `09-groups-list.png`
- `10-groups-search.png`

Health: Good structure, needs stronger search affordance.

What works:

- Group cards show type, name, amount, and member count.
- The list matches the home card language.

Issues:

- Search and group discovery are visually similar to the home experience, so the user may not understand what is different.
- Long group names and category labels are clipped.
- Empty and zero-result search behavior should be verified separately.

Recommendations:

- Make the Groups route a true management/discovery space: tabs for My groups, Invites, Discover, Recent.
- Use a clear search placeholder such as "Search groups or Collect ID".
- Include a visible empty state and recent searches for first-time users.

## Journey 5: Group Creation

Screen:

- `11-group-create.png`

Health: Functionally minimal but under-guided.

What works:

- The form is simple.
- Primary CTA is highly visible.

Issues:

- The screen has large unused vertical space while the CTA is pinned near bottom navigation.
- Required fields are not clearly marked.
- There is no visible explanation of what kind of group can be created or what SMS/MoMo requirement applies.
- The fixed CTA plus bottom nav makes this feel like a modal flow embedded in a tab shell.

Recommendations:

- Add short guidance below the title: "Create a group to collect confirmed MoMo contributions."
- Mark required fields and show helper text for group name and description.
- Hide bottom navigation during creation or move the CTA into the form flow.
- Show disabled-state reasoning if profile/readiness/SMS access blocks creation.

## Journey 6: Join, Scan, Shared Links

Screens:

- `12-group-scan.png`
- `13-join-portal.png`
- `14-shared-group-link.png`
- `16-group-created.png`
- `17-group-joined.png`
- `46-share-invalid.png`
- `47-share-expired.png`
- `48-fresh-link-request.png`

Health: Broadly covered, recovery needs clearer language.

What works:

- QR scanning, link joining, invalid link, expired link, and fresh-link request states exist.
- Recovery routes reduce dead ends.
- The fresh-link request has a primary action and QR fallback.

Issues:

- Fresh-link hero copy truncates important privacy/recovery context.
- The reason field in fresh-link request is large but underspecified.
- Scan and join flows need clearer fallback for users without camera access or with poor network.
- Invalid and expired link screens should explain what data is and is not exposed.

Recommendations:

- Give link problem screens a consistent structure: problem, why it happened, what to do next.
- Label the fresh-link text area with a more concrete prompt: "Tell the group admin why you need a new link."
- On scan route, make manual code entry visible as a fallback.
- Keep privacy reassurance visible and not truncated.

## Journey 7: Group Detail, Share, Members, Profile, Manage

Screens:

- `15-group-detail.png`
- `18-share-group.png`
- `28-manage-group.png`
- `29-group-profile.png`
- `30-members.png`

Health: Strong group object model, some function ambiguity.

What works:

- Group detail puts amount, member count, actions, and activity together.
- Share modal is visually distinct and QR code is prominent.
- Members, manage, and profile have dedicated surfaces.

Issues:

- The group name truncates in the hero card, even on the primary detail screen.
- The action row uses icon-only buttons. For a finance-adjacent product, receipt, QR, share, and manage actions need labels or tooltips.
- Share modal appears visually lower on the screen, with a large blank gradient above. This may feel like a partially opened bottom sheet.
- QR share close button is clear, but modal state and background behavior need testing.

Recommendations:

- Show the full group name either in the header or the hero body.
- Add visible labels under group detail action icons, at least for the first visit.
- In share modal, either center the sheet vertically or make it a full bottom sheet with clear drag affordance.
- For manage/profile, group settings should be grouped by risk: identity, receiver, permissions, members, delete/archive.

## Journey 8: Contribution and Payment

Screens:

- `19-contribution.png`
- `20-payment-intent.png`
- `21-payment-waiting.png`
- `22-payment-pending.png`
- `23-payment-confirmed.png`
- `24-payment-expired.png`
- `25-payment-needs-review.png`
- `26-payment-support-review.png`

Health: Core journey exists, but action/state hierarchy needs tightening.

What works:

- Payment amount is prominent.
- Payment status routes cover the expected lifecycle.
- "Open ledger" gives a clear post-payment destination.
- Support review exists for ambiguous states.

Issues:

- Payment intent screenshot shows content cut by the fixed bottom action panel.
- Status chips and titles are clipped in narrow width.
- The same visual template is used for materially different states; this can slow comprehension.
- Users may not know when to wait versus retry versus request support.
- Support-review needs clearer evidence expectations and privacy warning.

Recommendations:

- Use a state-specific payment header:
  - Pending: "Waiting for MoMo confirmation"
  - Confirmed: "Payment confirmed"
  - Expired: "Payment link expired"
  - Needs review: "We need help matching this payment"
- Add one-line "What happens next" text on every payment state.
- Keep the primary CTA above the bottom nav without covering payment details.
- On support review, explicitly say not to paste raw SMS or sensitive data unless the product supports secure handling.

## Journey 9: Ledger

Screen:

- `27-ledger.png`

Health: Strong screen.

What works:

- Ledger summary card is clear.
- Search, status filter, and sort are visible.
- Activity rows are readable and include status, sender/Collect ID, amount, time, and reference.

Issues:

- Filter chips may be hard to operate if they open bottom sheets that compete with navigation.
- Pending and confirmed entries are mixed visually; the pending state needs more warning or pending emphasis.

Recommendations:

- Add a clear visual separation between pending and confirmed entries.
- Ensure filters use large tap targets and visible selected state.
- Add export/share functions only if clearly scoped and privacy-safe.

## Journey 10: Permissions, Device, Platform, Offline, Sync

Screens:

- `31-sms-denied.png`
- `32-device-permission.png`
- `33-notifications-denied.png`
- `34-camera-denied.png`
- `35-iphone-create-unavailable.png`
- `36-notifications.png`
- `37-offline.png`
- `38-sync.png`

Health: Good coverage with copy and layout refinements needed.

What works:

- The app anticipates denied permissions and platform limitations.
- Primary actions like "Open app settings" and "Try again" are visible.
- Offline and sync routes exist.

Issues:

- Permission cards truncate explanatory copy.
- SMS access screen has significant empty vertical space while bottom navigation remains present.
- iPhone create unavailable must be very clear about what is unavailable and what the user can still do.
- Native permission prompts were not tested in this web review.

Recommendations:

- Make permission recovery screens task-specific:
  - "Enable SMS to create a receiver group"
  - "Enable camera to scan group QR"
  - "Enable notifications for payment updates"
- Put fallback actions on every permission screen.
- Hide or de-emphasize bottom navigation when a permission issue blocks the current task.

## Journey 11: Settings, Account, Privacy, Legal, Help

Screens:

- `39-settings.png`
- `40-account.png`
- `41-account-delete.png`
- `42-privacy-data.png`
- `43-legal-terms.png`
- `44-legal-privacy.png`
- `45-help-support.png`

Health: Complete surface, but content density and bottom nav need work.

What works:

- Settings has clear account center framing.
- Dark mode toggle is discoverable.
- Account, readiness, privacy, legal, delete, and help routes are present.
- Account deletion has explicit reason choices and a disabled submit button.

Issues:

- Settings hero text truncates.
- Settings cards are partly hidden behind bottom navigation at the bottom of the viewport.
- Legal text starts well but is constrained by bottom nav; long legal content needs better reading ergonomics.
- Delete request has a disabled Submit button without visible explanation of how to enable it.
- Privacy and legal routes need careful contrast checks for paragraph text.

Recommendations:

- Use a simpler settings list with less decorative height for operational settings.
- Add enough bottom padding to every scrollable settings/legal screen.
- On account deletion, make the selected reason state and enablement condition explicit.
- Consider hiding bottom nav on legal documents to maximize readable area and reduce accidental navigation.

## Screen-by-Screen Step List

| Step | Screenshot | Route | General health | Main note |
| --- | --- | --- | --- | --- |
| 1 | `01-launch.png` | `/` | Needs review | Launch route captured as redirect/root state; verify loading and redirect timing on device. |
| 2 | `02-onboarding.png` | `/onboarding` | Good with risk | Clear product story, but hero copy truncates. |
| 3 | `03-auth-phone.png` | `/auth` | Needs review | Auth expectations and recovery must be explicit. |
| 4 | `04-auth-success.png` | `/auth/success` | Good | Success state exists; verify next action clarity. |
| 5 | `05-auth-failure.png` | `/auth/failure` | Needs review | Failure state exists; needs strongest retry/support guidance. |
| 6 | `06-profile-setup.png` | `/settings/profile` | Needs review | Profile setup should show required fields and why they matter. |
| 7 | `07-profile-readiness.png` | `/settings/readiness` | Needs review | Readiness should become a checklist, not an abstract status. |
| 8 | `08-home.png` | `/home` | Strong with risk | Excellent product entry; dense top area and clipped cards. |
| 9 | `09-groups-list.png` | `/groups` | Good | Familiar card pattern; needs clearer group management hierarchy. |
| 10 | `10-groups-search.png` | `/groups/search` | Needs review | Search affordance and empty states need verification. |
| 11 | `11-group-create.png` | `/groups/create` | Needs improvement | Minimal form, too little guidance, bottom CTA/navigation conflict. |
| 12 | `12-group-scan.png` | `/groups/scan` | Needs device test | Camera route exists; web screenshot cannot prove native scan behavior. |
| 13 | `13-join-portal.png` | `/groups/join` | Good with risk | Join route exists; fallback and manual entry need prominence. |
| 14 | `14-shared-group-link.png` | `/c/st-michel-building-fund` | Good with risk | Link state exists; full group identity and privacy copy matter. |
| 15 | `15-group-detail.png` | `/groups/col-church` | Strong with risk | Strong group summary; group name and action meanings need clearer labels. |
| 16 | `16-group-created.png` | `/groups/col-church/created` | Good | Confirmation route exists; verify next best action. |
| 17 | `17-group-joined.png` | `/groups/col-church/joined` | Good | Confirmation route exists; verify group detail transition. |
| 18 | `18-share-group.png` | `/groups/col-church/share` | Good with risk | QR is clear; modal position and title truncation need refinement. |
| 19 | `19-contribution.png` | `/groups/col-church/contribute` | Needs review | Contribution entry needs amount guidance and error states. |
| 20 | `20-payment-intent.png` | `/groups/col-church/pay/intent-render` | Needs improvement | Critical details are compressed by fixed bottom action panel. |
| 21 | `21-payment-waiting.png` | `/groups/col-church/pay/intent-render/waiting` | Needs review | Waiting state should say what to do and when to stop waiting. |
| 22 | `22-payment-pending.png` | `/groups/col-church/pay/intent-render/state/pending` | Needs review | Pending state needs clearer distinction from waiting. |
| 23 | `23-payment-confirmed.png` | `/groups/col-church/pay/intent-render/state/confirmed` | Good | Confirmation state should lead to ledger and group detail. |
| 24 | `24-payment-expired.png` | `/groups/col-church/pay/intent-render/state/expired` | Needs review | Expired state needs direct retry/create-new-payment action. |
| 25 | `25-payment-needs-review.png` | `/groups/col-church/pay/intent-render/state/needs-review` | Needs improvement | Needs-review state must explain evidence and privacy clearly. |
| 26 | `26-payment-support-review.png` | `/groups/col-church/support/payment/intent-render` | Needs review | Support review form needs guidance, validation, and safe-data wording. |
| 27 | `27-ledger.png` | `/groups/col-church/ledger` | Strong | Clear summary, filters, sort, and entries. |
| 28 | `28-manage-group.png` | `/groups/col-church/manage` | Needs review | Management actions should be grouped by risk and role. |
| 29 | `29-group-profile.png` | `/groups/col-church/profile` | Good with risk | Good dedicated group profile; verify full receiver/member context. |
| 30 | `30-members.png` | `/groups/col-church/members` | Needs review | Members surface needs role, invite, and access-state clarity. |
| 31 | `31-sms-denied.png` | `/permissions/sms-denied` | Good with risk | Clear action, but explanatory copy truncates. |
| 32 | `32-device-permission.png` | `/permissions/device` | Needs review | Needs task-specific explanation and fallback actions. |
| 33 | `33-notifications-denied.png` | `/permissions/notifications-denied` | Good with risk | Recovery exists; verify native settings handoff. |
| 34 | `34-camera-denied.png` | `/permissions/camera-denied` | Good with risk | Recovery exists; add manual join fallback. |
| 35 | `35-iphone-create-unavailable.png` | `/platform/iphone-create-unavailable` | Needs review | Platform limitation must be precise and reassuring. |
| 36 | `36-notifications.png` | `/notifications` | Good | Notification center exists; verify empty/read/unread states. |
| 37 | `37-offline.png` | `/offline` | Good | Offline route exists; verify retry and stale data messaging. |
| 38 | `38-sync.png` | `/sync` | Needs review | Sync should show last synced, queued changes, and retry. |
| 39 | `39-settings.png` | `/settings` | Good with risk | Strong account center, but bottom nav covers lower settings content. |
| 40 | `40-account.png` | `/settings/account` | Needs review | Account/session management must make sign-out and risk clear. |
| 41 | `41-account-delete.png` | `/settings/account/delete` | Needs improvement | Disabled submit has no visible enablement guidance. |
| 42 | `42-privacy-data.png` | `/settings/privacy` | Good with risk | Privacy route exists; verify readability and export/delete flows. |
| 43 | `43-legal-terms.png` | `/settings/legal/terms` | Needs review | Legal content is readable but bottom nav reduces document ergonomics. |
| 44 | `44-legal-privacy.png` | `/settings/legal/privacy` | Needs review | Same as terms; needs contrast and reading-order checks. |
| 45 | `45-help-support.png` | `/settings/help` | Good with risk | Help route exists; verify contact, escalation, and FAQ actions. |
| 46 | `46-share-invalid.png` | `/share/invalid` | Good | Invalid-link state prevents a dead end. |
| 47 | `47-share-expired.png` | `/share/expired` | Good | Expired-link state exists; needs direct fresh-link path. |
| 48 | `48-fresh-link-request.png` | `/share/expired/request?slug=st-michel-building-fund` | Good with risk | Useful recovery flow; hero copy truncates and reason field needs guidance. |

## Accessibility Risks From Screenshots

These are likely risks only. Screenshots alone cannot prove WCAG compliance.

- Contrast risk: secondary gray text on dark purple cards and image-backed hero cards.
- Reading order risk: dense visual cards may not map cleanly to semantic order in Flutter web/native semantics.
- Focus risk: icon-only controls and custom cards need visible focus states.
- Target-size risk: compact tabs, chips, and top-bar icon controls may be below comfortable touch size if padding is not enforced.
- State communication risk: payment states rely on visual chips and color; ensure text labels and semantics communicate the state.
- Error recovery risk: disabled buttons and form requirements need explicit spoken/visible explanations.
- Motion/timing risk: launch redirects, waiting states, and sync states need announcements for assistive tech.

## Function-by-Function Recommendations

### Authentication

- Use one consistent auth channel name.
- Show phone format and error state.
- Add retry, change number, and support actions.

### Group creation

- Add helper text and required markers.
- Explain why SMS/MoMo permissions matter before the user hits a blocker.
- Remove bottom nav from the creation task or add larger bottom padding.

### Join and QR

- Provide manual code entry on scan/camera-denied paths.
- Keep privacy and receiver-exposure explanations fully visible.
- Make invalid/expired/fresh-link recovery language consistent.

### Group detail

- Show full group name.
- Label all action icons.
- Separate member, ledger, payment, share, and settings actions by importance.

### Contribution and payment

- Make amount entry and payment lifecycle state-specific.
- Give every state one recommended action and one fallback.
- Avoid clipping payment details behind persistent controls.

### Ledger

- Keep the current summary/filter/activity structure.
- Strengthen pending versus confirmed visual separation.
- Add privacy-safe export/share only if required.

### Permissions and platform limits

- Connect every permission request to the exact user task.
- Add fallback actions.
- Test native permission dialogs separately on Android and iOS.

### Settings, privacy, legal

- Add bottom scroll padding.
- Reduce decorative card height on operational settings.
- Treat legal/privacy pages as reading surfaces, not dashboard cards.
- Explain disabled destructive actions.

## Recommended Fix Order

1. Layout safety: add bottom safe-area padding and remove bottom nav from task-critical modal flows.
2. Text clarity: remove truncation from instructional and legal/recovery copy.
3. Payment hierarchy: redesign payment states around status, meaning, action, fallback.
4. Form guidance: add required markers, helper text, validation, and disabled-state explanations.
5. Accessibility pass: contrast, semantics labels, focus states, tap targets, and screen-reader announcements.
6. Device UAT: Android SMS, camera QR, notifications, offline/sync, and native settings handoff.

## Evidence Limits

- Captures were made through Flutter web in Codex's in-app browser, not native Android/iOS.
- Screenshots prove visual states, not tap success, keyboard traversal, screen-reader order, native permissions, or live payment/SMS integration.
- The route set was broad and representative, but some internal component states such as validation errors, loading skeletons, empty searches, filter sheets, and modal confirmations require interactive testing.
- Product Design context preflight did not complete in this run, so the report uses the current app, route matrix, screenshots, and local source files as grounding.
