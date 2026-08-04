# Collect screen-by-screen UX audit — 2026-08-04

## Scope and rule

Reviewed the current member app, public website, and Admin route inventory against
`DESIGN.md`. The review covers journey clarity, screen density, loading and
feedback states, motion, responsiveness, accessibility, and source-level
performance risks. No new product capability, marketing claim, policy, route,
or data was introduced. The only behavior completed was the already-visible
Groups search control, which previously navigated back to its own route.

## Findings and disposition

| Priority | Finding | Disposition |
|---|---|---|
| P1 | Offline recovery status rows overflowed at 320 px and 200% text. | Fixed with an adaptive stacked status layout; compact reduced-motion route matrix passes. |
| P1 | The Groups search affordance was active but returned to `/groups`, so it did not perform the action it announced. | Fixed using the existing group title, description, type, and purpose data; clear/no-result recovery added. |
| P1 | Failure to open the MoMo USSD handoff was silent. | Fixed with a short, actionable snackbar after the app returns to the group. |
| P2 | Persistent bottom and rail navigation blurred the full background on every frame despite an almost-opaque surface. | Removed the two persistent `BackdropFilter` operations; appearance remains defined by the existing opaque gradient, border, and shadow. |
| P2 | Home, group detail, Settings, Security, Help, Offline, Sync, Notifications, and loading states repeated labels, actions, or explanatory copy. | Removed only the duplicated UI described below. Legal and security-critical copy remains intact. |
| P2 | Wide member layouts could stretch content across the full remaining viewport. | Added an 840 px maximum content width while preserving the existing rail breakpoint and phone layout. |
| P2 | Long group names were cut to one line beside the balance on a 390 px screen. | Existing group rows now allow two title lines without moving or hiding the balance. |
| P2 | Notification, profile, group-create, group-profile, and QR-join failures could expose raw exception text. | Replaced with stable, user-safe recovery messages. |
| Open evidence boundary | Source and rendered-route checks do not replace sustained physical-device performance, spoken assistive-technology traversal, or human comfort review. | Keep these as release gates; do not infer them from green widget or browser checks. |

## Member app: every registered journey

| Route/screen | Review outcome |
|---|---|
| `/` launch | Keep. Focused launch state, no premature navigation or data. |
| `/auth` | Keep. Single-task phone/OTP flow, clear failure and retry states. |
| `/home` | Cleaned. Removed duplicate Create/Settings chrome actions and the repeated `TOTAL COLLECTED` eyebrow; retained one balance title and four existing quick actions. |
| `/offline` | Cleaned and fixed. Removed the duplicate page heading, shortened existing recovery copy, and made status rows large-text safe. |
| `/sync` | Cleaned and fixed. Removed the duplicate page heading, shortened existing recovery copy, and made status rows large-text safe. |
| `/groups` | Fixed. Existing Search now filters current groups and has clear/no-result recovery. Removed the duplicate empty-state hero and allowed long group names to use two lines. Existing Create and Supported controls remain. |
| `/groups/join` | Keep compatibility behavior. No new join UI invented. |
| `/groups/scan` | Feedback fixed. Camera/permission/recovery states remain explicit, and failed QR joins no longer expose raw exceptions. |
| `/groups/create` | Feedback fixed. Existing platform gate and stepped owner workflow remain; failed saves no longer expose raw exceptions. |
| `/groups/:id` | Cleaned. Replaced the misleading search-shaped group-title control and duplicate Share/Manage actions with a plain back header; hero actions remain the task surface. |
| `/groups/:id/members` | Keep. Search and membership states are already task-focused. |
| `/groups/:id/manage` | Keep. Owner operations remain grouped and role-bounded. |
| `/groups/:id/profile` | Feedback fixed. Raw save exceptions no longer reach the screen. |
| `/groups/:id/contribute` | Feedback fixed. A failed MoMo USSD launch now produces a concise recovery message. Existing review, duplicate-intent, expiry, and error states remain. |
| `/groups/:id/share` | Keep. QR and share/save feedback already exist. |
| `/groups/:id/invite` | Keep compatibility behavior; no duplicate journey added. |
| `/groups/:id/ledger` | Keep. Filter/sort and verified-ledger boundaries remain clear. Dense-list physical profiling remains an external gate. |
| `/contribute` | Keep. Existing group selection reuses the same contribution flow. |
| `/activity` | Keep. Existing search/filter, empty/no-result, and dense-list blur limit remain. |
| `/settings` | Cleaned. Removed Home, Notifications, and Help top actions that duplicated primary navigation and settings rows. |
| `/settings/profile` | Feedback fixed. Existing identity editing and validation remain, and failed saves no longer expose raw exceptions. |
| `/settings/account` | Keep. Sensitive account actions remain explicit and sheet-based. |
| `/settings/notifications` | Cleaned. Removed the repeated information banner, retained the permission action, added a compact live saving indicator, and made errors safe. |
| `/settings/appearance` | Keep. Preview and three existing modes remain; compact/200% layout is covered. |
| `/settings/security` | Cleaned. Removed the repeated eyebrow and Account/Privacy hero actions; retained the security warning and detailed rows. |
| `/settings/account/delete` | Keep. Auditable request boundary and destructive-action clarity remain. |
| `/settings/privacy` | Keep compatibility behavior. |
| `/settings/help` | Cleaned. Removed the decorative “How can we help?” block; existing problem categories and contact/policy routes remain unchanged. |
| `/settings/legal/terms` | Keep. Legal copy is intentionally not compressed or rewritten. |
| `/settings/legal/privacy` | Keep. Privacy copy is intentionally not compressed or rewritten. |
| `/app`, `/invite/:publicId` | Keep registered compatibility redirects; no extra screens invented. |
| `/share/invalid`, `/share/expired` | Keep registered recovery redirects. |
| `/share/expired/request` | Keep existing recovery request route. |
| `/c/:slug` | Keep existing group deep-link resolution and error recovery. |

## Public website: every registered surface

| Route/screen | Review outcome |
|---|---|
| `/` | Keep. Current rendered mobile surface has one headline, short supporting copy, three clear existing actions, and one product visual. |
| `/group-savings` | Keep current product explanation and action hierarchy. |
| `/diaspora` | Keep current audience-specific explanation; no claims added. |
| `/insurance` | Keep current bounded informational content; no coverage claim added. |
| `/craas` | Keep current service explanation; no product capability added. |
| `/community-groups` | Keep current group-oriented journey. |
| `/our-partners` | Keep current partnership enquiry boundary. |
| `/trust`, `/security` | Keep trust/security content; do not shorten safeguards for visual minimalism. |
| `/privacy`, `/account-deletion`, `/data-deletion`, `/terms` | Keep policy and request content unchanged. |

The retained `current-live-config` Admin-render directory contains a stale
public-landing build rather than authenticated Admin screen evidence. It must
not be used as proof of current Admin visual readiness.

## Admin: every registered surface

| Route/screen | Review outcome |
|---|---|
| `/admin/login`, `/admin/denied` | Keep fail-closed access and denial states. |
| `/admin` | Keep operations overview hierarchy. Current automated persona coverage exists; refreshed authenticated visual evidence is still required for release. |
| `/admin/groups`, `/admin/groups/:id` | Keep list/detail pattern and bounded actions. |
| `/admin/members`, `/admin/members/:id` | Keep list/detail pattern and private-data boundary. |
| `/admin/payment-intents`, `/admin/payment-intents/:id` | Keep list/detail review pattern. |
| `/admin/payment-events`, `/admin/payment-events/:id` | Keep SMS parsing review and explicit reparse action. |
| `/admin/allocations`, `/admin/exceptions`, `/admin/ledger` | Keep reconciliation and exception surfaces. |
| `/admin/receivers`, `/admin/receivers/:id` | Keep receiver list/detail access boundary. |
| `/admin/sms`, `/admin/sms/:id` | Keep metadata/detail separation. |
| `/admin/audit-logs` | Keep immutable review surface. |
| `/admin/settings`, `/admin/feature-flags` | Keep explicit configuration/action patterns. |
| `/admin/system-health`, `/admin/admin-users` | Keep operational detail/list patterns. |
| unknown Admin route | Keep existing recovery with Overview and Login actions. |

## Loading, motion, responsiveness, and performance

- Screen-level loading now presents one progress title plus skeletons; the
  former explanatory sentence remains available to assistive technology.
- Existing route transitions remain short and centralized, and resolve to zero
  duration when reduced motion is requested. No decorative animation was added.
- Member content is capped at 840 px on wide viewports. Existing navigation rail,
  compact phone, 200% text, dark/light, high-contrast, and reduced-motion paths
  remain part of the route matrices.
- Persistent navigation no longer performs full-surface background blur.
- Activity and ledger still need sustained physical-device profiling with
  production-like row counts; this audit does not convert source review into a
  measured frame-time claim.

Reference criteria: [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices),
[adaptive and responsive design](https://docs.flutter.dev/ui/adaptive-responsive),
and [Flutter accessibility](https://docs.flutter.dev/ui/accessibility).

## Final verification

- Flutter analysis: pass, no findings.
- Full Flutter suite: 444 tests pass.
- Coverage: 9,689 of 12,297 lines, 78.79%.
- Member browser route render: 35 of 35 routes pass at 390x844;
  32 product screens and 3 compatibility routes.
- Compact member route matrix at 320 px, 200% text, and reduced motion: pass.
- Tablet/high-contrast, light/dark/system appearance, standard/large phone,
  interaction-target, and accessibility-label matrices: pass.
- Deterministic golden suite: 14 checks pass after visual review and checksum
  refresh for the eight intentionally changed baselines.
- Physical Android profile-mode performance: blocked because governed device
  `13111JEC215558` is not connected and authorized over ADB. No frame-time,
  jank, or launch-performance claim is made for this revision.
