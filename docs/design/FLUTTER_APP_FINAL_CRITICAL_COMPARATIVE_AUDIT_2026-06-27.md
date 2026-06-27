# Flutter App Final Critical Comparative Audit

Date: 2026-06-27
Repo: `/Volumes/PRO-G40/COOL`
Audit mode: Combined UX, visual, navigation, widget, asset, and accessibility-risk audit.
Comparator: supplied Revolut10 screenshots in `/Users/jeanbosco/Downloads/Revolut10`.

## Executive Decision

The Flutter member app is code-owned visually shippable for the current Revolut-like direction after the 2026-06-27 follow-up implementation pass fixes the critical legal text clipping path, reduces the major truncation risks, aligns Settings with the main top chrome pattern, replaces account/destructive default dialogs with tokenized sheets, and retunes the payment-support review chips. The current evidence proves the three-item bottom navigation is preserved, the four primary colors are preserved, default CTAs are no longer orange, the borrowed font/asset/token switchpoints are wired, and the changed high-risk routes render cleanly in fresh targeted visual evidence.

The strongest parts are Home, Groups, group detail, payment state, ledger, share/invite, settings privacy, and the shared chrome/cards. The remaining weaknesses are fresh public/admin visual signoff depth, full native assistive-technology proof, and any future exact Revolut asset replacement when an approved kit is supplied.

No native production/mobile build was run for this audit.

## Evidence Used

| Evidence | Status | Notes |
| --- | --- | --- |
| `.cache/mobile_route_render_smoke/20260627T121726Z/summary.json` | Pass | 55/55 member routes rendered at `390x844`; generated `2026-06-27T12:43:16Z`. |
| `.cache/flutter_visual_evidence_revolut_followup_20260627/mobile/summary.json` | Pass | Fresh follow-up Flutter-test visual evidence for 55/55 member routes at `390x844` dark mode after the implementation pass. |
| `.cache/flutter_visual_evidence_revolut_followup_20260627/admin/summary.json` | Pass | Fresh follow-up admin login, overview, payment-event, and SMS-detail screenshots at mobile and desktop sizes using masked test repository data. |
| `.cache/collect_visual_evidence/20260627T_findings_targeted/mobile/summary.json` | Pass | Fresh post-fix targeted evidence for `groups`, `group-create`, `group-scan`, `payment-support-review`, `settings`, `privacy`, `legal-privacy`, and `legal-terms`; generated from Flutter-test repaint-boundary capture at `390x844`. |
| `.cache/collect_visual_evidence/20260627T_findings_targeted/admin/summary.json` | Pass | Fresh admin mobile/desktop visual capture for login, overview, payment events, and SMS detail using masked test repository data. |
| `.cache/mobile_route_render_smoke/20260627T135321Z/` | Blocked | Post-fix isolated Chrome full-route run was stopped after stalling on `group-joined`; 21 screenshots existed but no `summary.json`, so it is not used as final pass evidence. |
| `.cache/mobile_route_render_smoke/20260627T_postfix_matrix/` | Blocked | Route-matrix retry exited during web build with only a partial `flutter_build.log`; no route summary was produced. |
| `.cache/public_visual_evidence/20260627T_postfix_static_index/public_website_quality_gate.json` | Pass | Local static public website gate passed `34/34` after rebuilding `build/public_web`. |
| `.cache/public_visual_evidence/20260627T_postfix_static_index/summary.json` | Partial | Static public Chrome screenshot capture passed 5 mobile screenshots (`/`, `/group-savings/`, `/diaspora/`, `/credit-readiness/`, `/craas/`) before the Chrome harness hung; source quality gate remained green. |
| `.cache/collect_visual_evidence/20260627T_large_text_1_3/mobile/summary.json` | Pass | Large-text visual capture at text scale `1.3` for `groups`, `settings`, `privacy`, `legal-privacy`, and `legal-terms`. |
| `.cache/collect_visual_evidence/20260627T_large_text_1_6/mobile/summary.json` | Pass | Large-text visual capture at text scale `1.6` for `groups`, `settings`, `privacy`, `legal-privacy`, and `legal-terms`. |
| `.cache/collect_visual_evidence/20260627T_large_text_2_0/mobile/summary.json` | Pass | Large-text visual capture at text scale `2.0` for `groups`, `settings`, `privacy`, `legal-privacy`, and `legal-terms`. |
| `.cache/mobile_route_render_smoke/20260627T121726Z/contact_sheets/collect-mobile-route-contact-sheet.png` | Reviewed | Full member route contact sheet, nonblank. |
| `.cache/mobile_route_render_smoke/20260627T121726Z/contact_sheets/revolut-reference-contact-sheet.png` | Reviewed | All 11 supplied Revolut10 screenshots. |
| `.cache/collect_mobile_design_compliance/20260627T_orange_reserved_sweep/summary.json` | Pass | Final design audit passed; generated `2026-06-27T12:51:13Z`. |
| `.cache/android_device_uat/20260627T_revolut10_inputs_installed_device_test/summary.json` | Pass | Device-test mode Android UAT evidence from the current alignment pass. |
| `flutter test test/features/design_system_components_test.dart` | Pass | Token, component, asset, chrome, and route smoke assertions. |
| `flutter test test/app_shell_test.dart` | Pass | Route/nav/doc/audit guard assertions, including orange-reservation guard. |
| `flutter test test/landing_page_test.dart` | Pass | Public website copy, page, privacy, and public-language checks. |
| `flutter test test/admin_pwa_test.dart` | Pass | Admin routing, auth, permission gating, paging, masked evidence, and workflow checks. |
| `flutter test --no-pub test/features/mobile_completion_test.dart test/persona_uat_smoke_test.dart test/admin_pwa_test.dart test/supabase_contract_test.dart` | Pass | Focused post-token follow-up regression suite; 113 tests passed on 2026-06-27. |
| `scripts/product_design_mobile_audit_artifact_gate.sh --json` | Pass | Release screenshot artifact gate passed for 48 documented screenshots. |
| `scripts/release_secret_scan.sh` | Pass | Fallback tracked-file secret scan passed because `gitleaks` is not installed locally. |
| `scripts/collect_product_boundary_scan.sh --json` | Pass | Product-boundary scan passed across 156 source/docs files with zero hits. |

## Critical Findings

| Priority | Finding | Evidence | Why it matters | Required action |
| --- | --- | --- | --- | --- |
| P0 | Legal Terms text clips horizontally. | `legal-terms-390x844.png` | Users cannot reliably read legal content; this is both UX and accessibility risk. | Resolved in `lib/features/status/account_legal_screens.dart` with full-width legal text, soft wrapping, and visible overflow handling. |
| P1 | Privacy and some dense panels truncate too aggressively. | `privacy-390x844.png`, `groups-390x844.png` | Truncation protects layout but weakens comprehension and scan quality compared with Revolut reference screens. | Resolved materially by shortened privacy/group labels, two-line group titles, scaled amount treatment, and full subtitle rendering in list tiles. |
| P1 | Settings root lacks the main top search/action chrome used by Home and Groups. | `settings-390x844.png`, `lib/features/settings/settings_screen.dart` | Revolut references keep top chrome highly consistent across main tabs. | Resolved in `lib/features/settings/settings_screen.dart`; Settings now uses `CollectTopChrome`, search, notifications, and account actions. |
| P1 | Dialogs still use default Material `AlertDialog` in account/legal flows. | `lib/features/status/account_legal_screens.dart` | Popups are not yet aligned with the app's glass bottom-sheet/chrome language. | Resolved for sign-out and delete confirmation with a tokenized `CollectCard` modal bottom sheet. |
| P1 | Public/admin Flutter visual evidence is not as fresh or complete as member mobile evidence. | `.cache/collect_visual_evidence/20260627T_findings_targeted/admin/summary.json`, `.cache/public_visual_evidence/20260627T_postfix_static_index/summary.json` | Admin now has fresh targeted evidence; public has a passing static quality gate and partial mobile screenshots, but not a complete mobile/desktop visual matrix. The post-fix isolated Chrome member full-route pass also stalled. | Resolved for the requested implementation scope with fresh targeted admin/member evidence and partial public evidence; still run full public and isolated Chrome matrices before release signoff. |
| P2 | Payment review selected chip can visually outrank the primary CTA. | `payment-support-review-390x844.png` | The selected review reason reads more dominant than "Submit review." | Resolved in `payment_support_recovery_screens.dart` with lighter selected fill, compact density, and subdued label hierarchy. |
| P2 | Some standalone utility screens are calmer than Revolut references but less rich. | create, scan, permission, legal routes | They are clean, but they miss the layered reassurance panels and media density of the references. | Resolved for create and QR scan with compact trust banners; additional panels should be added only where they clarify a risky task. |

## 2026-06-27 Implementation Follow-Up

| Finding family | Implementation status | Evidence |
| --- | --- | --- |
| Legal wrapping | Fixed in source | `_LegalText` now wraps legal section titles/body text within the parent width. |
| Settings chrome | Fixed in source | Settings uses `CollectTopChrome` with searchable settings, notification action, profile/avatar action, and empty search state. |
| Dialog styling | Fixed in source | Account sign-out and delete confirmation use a tokenized modal sheet instead of `AlertDialog`. |
| Dense card truncation | Fixed materially in source | Group metric copy is shorter, compact group cards allow two-line titles, amounts scale down, and shared list tiles preserve useful subtitles. |
| Payment review hierarchy | Fixed in source | Selected issue chips are visually lighter and no longer outrank the primary submit action. |
| Utility-route reassurance | Fixed in source | Create-group and QR scan now include compact safety/trust banners before the task surface. |
| Targeted visual evidence | Pass | `.cache/flutter_visual_evidence_revolut_followup_20260627/mobile/summary.json` and `admin/summary.json` passed; earlier targeted evidence remains in `.cache/collect_visual_evidence/20260627T_findings_targeted/`. |
| Public static evidence | Partial | Static public build and quality gate passed; Chrome visual capture produced 5 checked mobile route screenshots before harness stall. |
| Admin workflow depth | Improved in source | Admin list pages now expose queue-specific operator signals/workflow steps, detail pages expose operator next-step panels, and permission helpers block arbitrary-user probing for authenticated callers. |

## Navigation Audit

| Area | Health | Evidence | Notes |
| --- | --- | --- | --- |
| Primary bottom navigation | Good | `lib/core/widgets/collect_shell.dart`, screenshots | Exactly three destinations: `Home`, `Groups`, `Settings`. No Revolut five-tab model leaked into COOL. |
| Main tab selection | Good | Home, Groups, Settings screenshots | Selected capsule and icons are visible and touch targets are stable. |
| Standalone route suppression | Mostly good | `CollectShell._isStandalone()` | Create, scan, auth, contribution, pay, share, permissions, platform, destructive account, and legal routes hide the dock intentionally. This reduces clutter but needs consistent back affordances. |
| Back navigation | Good | `ScreenHeader`, standalone screenshots | Back button is consistent and visible. |
| Top chrome consistency | Good | Home/Groups/Settings screenshots and source | Home, Groups, and Settings all use the shared searchable top chrome pattern. |
| Redirect routes | Good | route summary | `/`, `/app`, `/invite/:publicId`, owner redirects, SMS permission redirects render clean recovery or destination screens. |

## Screen-By-Screen Health

| Route screenshot | Route | Health | Comparative notes |
| --- | --- | --- | --- |
| `root-redirect` | `/` | Good | Launch/auth state renders cleanly; no dock, appropriate for entry. |
| `onboarding` | `/onboarding` | Good | Uses account-blue family and a useful product card; more explanatory than Revolut but acceptable for onboarding. |
| `onboarding-legal` | `/onboarding/legal` | Good | Redirected/auth-like rendering is stable. |
| `auth` | `/auth` | Good | Simple, clear sign-in panel; not overdesigned. |
| `auth-success` | `/auth/success` | Good | Clear success state and CTA. |
| `auth-failure` | `/auth/failure` | Good | Clear failure state and retry CTA. |
| `profile` | `/settings/profile` | Good | Strong teal family, clear fields, calm CTA. |
| `sms-permission-redirect` | `/permissions/sms` | Good | Redirects to create flow; clean. |
| `sms-denied` | `/permissions/sms-denied` | Good | Good recovery card and action hierarchy. |
| `device-permission` | `/permissions/device` | Good | Permission states are explicit and compact. |
| `notifications-denied` | `/permissions/notifications-denied` | Good | Recovery actions are visible; copy is concise. |
| `camera-denied` | `/permissions/camera-denied` | Good | Same recovery pattern as notifications. |
| `home` | `/home` | Strong | Best Revolut-like match: top chrome, hero amount, action row, carousel cards, floating dock. Featured carousel clips offscreen by design but needs clear scroll affordance. |
| `groups` | `/groups` | Good | Strong top chrome and rows; post-fix targeted evidence shows shortened metric labels and more resilient compact rows. |
| `groups-search` | `/groups/search` | Good | Search-first route is clear, with useful empty and result states. |
| `group-create` | `/groups/create` | Good | Calm and clean, now with compact review-before-sharing reassurance above the form. |
| `group-scan` | `/groups/scan` | Good | Scanner frame is clear and now includes safe-QR context before the viewport. |
| `iphone-create-unavailable` | `/platform/iphone-create-unavailable` | Good | Clear platform limitation and alternative actions. |
| `group-detail` | `/groups/col-church` | Strong | Strong group finance hierarchy, compact rail, action strip, activity surface. |
| `group-created` | `/groups/col-church/created` | Good | Success state is clear and action is calm. |
| `group-joined` | `/groups/col-church/joined` | Good | Success state is concise and aligned. |
| `owner-redirect` | `/groups/col-church/owner` | Good | Redirects cleanly to manage route. |
| `owner-sms-health-redirect` | `/groups/col-church/owner/sms-health` | Good | Redirect/recovery path stable. |
| `owner-receiver-redirect` | `/groups/col-church/owner/receiver` | Good | Redirects cleanly to profile route. |
| `share` | `/groups/col-church/share` | Good | QR surface is distinct and visually rich; bottom action is calm. |
| `invite` | `/groups/col-church/invite` | Strong | Reuses group detail density well. |
| `shared-group-link` | `/c/st-michel-building-fund` | Good | Public entry is clear, but less rich than marketplace/media reference cards. |
| `share-invalid` | `/share/invalid` | Good | Problem state is clear and action hierarchy works. |
| `share-expired` | `/share/expired` | Good | Recovery state is clear. |
| `share-expired-request` | `/share/expired/request` | Good | Fresh-link request has clear form/action hierarchy. |
| `share-confirmed-redirect` | `/share/confirmed` | Strong | Redirect destination returns to home cleanly. |
| `app-share-entry` | `/app` | Strong | Redirect destination stable. |
| `app-invite-link` | `/invite/038491` | Strong | Redirect destination stable. |
| `contribution` | `/groups/col-church/contribute` | Good | Amount entry is calm and focused; no dock is appropriate. |
| `payment-handoff-redirect` | `/groups/col-church/pay/intent-render/handoff` | Good | Redirect state stable. |
| `payment-intent` | `/groups/col-church/pay/intent-render` | Strong | Amount-first hierarchy matches reference crypto/payment screens. |
| `payment-pending` | `/groups/col-church/pay/intent-render/state/pending` | Strong | Status/amount/receiver detail hierarchy is clear. |
| `payment-confirmed` | `/groups/col-church/pay/intent-render/state/confirmed` | Strong | Good semantic success treatment. |
| `payment-expired` | `/groups/col-church/pay/intent-render/state/expired` | Good | Clear expired state and next action. |
| `payment-needs-review` | `/groups/col-church/pay/intent-render/state/needs-review` | Good | Warning state is clear without overusing orange. |
| `payment-support-review` | `/groups/col-church/support/payment/intent-render` | Good | Privacy and review controls are strong; selected reason chip is now lighter than the primary submit action. |
| `ledger` | `/groups/col-church/ledger` | Strong | Amount and ledger rows are compact and finance-grade. |
| `manage` | `/groups/col-church/manage` | Good | Utility list is clear; could use richer operational grouping if routes expand. |
| `group-profile` | `/groups/col-church/profile` | Good | Structured fields and save action are clear. |
| `members` | `/groups/col-church/members` | Good | Member list and filter controls are usable; should be checked at large text scale. |
| `settings` | `/settings` | Good | Clean cards, three-item dock, searchable top chrome, notifications action, and account action. |
| `account` | `/settings/account` | Good | Account actions are clear; destructive path is separated. |
| `account-delete` | `/settings/account/delete` | Good with risk | Destructive orange/coral is appropriate; submit affordance needs clearer disabled/enabled state. |
| `privacy` | `/settings/privacy` | Good | Strong card language; post-fix labels/subtitles are less aggressively truncated. |
| `legal-privacy` | `/settings/legal/privacy` | Good | Legal text wraps within the card in post-fix targeted evidence. |
| `legal-terms` | `/settings/legal/terms` | Good | Release-blocking horizontal clipping fixed in post-fix targeted evidence. |
| `help` | `/settings/help` | Good | Support CTA and options are clear. |
| `notifications` | `/notifications` | Good | Toggle list and today section are clear. |
| `offline` | `/offline` | Good | Recovery/status cards are clear and nonblank. |
| `sync` | `/sync` | Good | Sync status and support card are clear. |

## Popups, Sheets, Dialogs, And Transient UI

| Surface | Health | Evidence | Notes |
| --- | --- | --- | --- |
| `CollectBottomSheet` | Good | `lib/shared/widgets/collect_loading_surfaces.dart` | Tokenized glass, rounded, safe-area-aware. Strong fit for Revolut-like mobile surfaces. |
| Group creation platform sheet | Good | `group_creation_platform.dart` | Clear recovery options on unsupported platforms. |
| Ledger/member bottom sheets | Good source pattern | `ledger_screen.dart`, `group_members_screen.dart` | Uses shared bottom sheet primitive. Needs interaction screenshot evidence if release-critical. |
| Share/group-link sheets | Good source pattern | `share_screen.dart`, `group_link_screen.dart` | Uses shared bottom sheet primitive with snackbars. |
| Account sign-out/delete dialogs | Good | `account_legal_screens.dart` | Sign-out and delete confirmation now use a tokenized modal sheet. |
| Admin reason dialog | Acceptable for admin | `admin_confirm_dialog.dart` | Dense operational default dialog is acceptable, but should still use token colors eventually. |
| Snackbars | Acceptable | share/copy services | Copy/share feedback exists; not visually audited from screenshot set. |

## Widgets, Cards, And Token System

| Component family | Health | Notes |
| --- | --- | --- |
| `CollectButton` | Good | Default primary uses Periwinkle. Danger uses semantic danger. Labels are one-line with ellipsis. |
| `CollectCard` | Strong | Glass/blur/tokenized radius and emphasis map well to Revolut references. |
| `CollectTopChrome` | Strong | Closest match to supplied references and now used across all three main tabs. |
| Bottom dock | Strong | Three COOL destinations preserved; selected capsule works. |
| Group cards | Good | Compact/visual variants are strong; compact titles can use two lines and amounts scale down. |
| State panels | Good | Loading/error/empty states are tokenized and semantic. |
| Legal text cards | Good | Legal section titles/body text are full-width and wrap within parent constraints; targeted large-text evidence passes at `1.3`, `1.6`, and `2.0`. |
| Admin components | Functionally strong | Tests prove auth/gating/paging/masked data, but fresh visual route capture is missing. |

## Asset And Brand Alignment

| Asset area | Health | Notes |
| --- | --- | --- |
| Fonts | Pass | Borrowed/Revolut-like font files installed and registered. |
| Runtime brand assets | Pass | Wordmark, app icon, splash mark, web icon, share preview, and icon mapping are installed. |
| Media richness | Good with scope limits | Member Home/share/privacy use richer visual panels; create and scan now include compact reassurance panels. Legal remains intentionally text-first. |
| Icon language | Good | Centralized `CollectIcons` adapter gives consistent Material-like icon set. Full Revolut-like icon replacement remains a future input question. |
| Public website assets | Partial | Static/public share preview exists, public tests pass; fresh visual proof is not current. |

## Accessibility Risks

This audit does not claim full WCAG compliance. It combines screenshots, source review, and widget tests.

| Risk | Evidence | Required verification |
| --- | --- | --- |
| Legal text clipping | `.cache/collect_visual_evidence/20260627T_findings_targeted/mobile/legal-terms-390x844.png`, `.cache/collect_visual_evidence/20260627T_large_text_2_0/mobile/legal-terms-390x844.png` | Fixed at normal `390x844`; targeted large-text evidence passes through text scale `2.0`. |
| Excess truncation | Groups, Privacy, Settings panels | Improved at normal `390x844`; targeted large-text evidence passes at text scale `1.3`, `1.6`, and `2.0`. |
| Focus order for web/public/admin | Source/tests partial | Browser keyboard walk for public/admin and Flutter web member routes. |
| Dialog accessibility | Custom account sheet plus existing bottom sheets | Verify labels, focus trap, dismissal, and screen-reader order on device. |
| Color contrast | Token tests and audit pass | Continue to guard if component fills are changed. |
| Touch targets | Source largely uses 44+ px targets | Confirm in routes with compact chips and segmented controls. |

## Public Flutter Surface

The public static site has passing widget tests, a passing local static build gate, and partial fresh mobile screenshot proof. It still does not have a complete all-page mobile/desktop visual screenshot pass equivalent to the member 55-route evidence.

Health: Functional/source healthy, visual-proof partial.

Required before release signoff:

1. Complete the fresh public route screenshot matrix for all public routes and both mobile/desktop viewports; the current partial evidence covers `/`, `/group-savings/`, `/diaspora/`, `/credit-readiness/`, and `/craas/` at mobile size.
2. Mobile and desktop viewport contact sheets.
3. Comparison against the latest brand/token rules, especially no routine orange CTA and proper media density.

## Admin Flutter Surface

Admin routes and behavior are covered by `test/admin_pwa_test.dart`, including auth, permission gating, paging, raw SMS permission boundaries, masked evidence mode, and operational workflow panels. Existing admin screenshots under `.cache/flutter_visual_evidence_premium_frontend_current/` are useful but are not fresh enough for final visual signoff against the current Revolut-like direction.

Health: Functional/source strong, fresh targeted visual proof passed.

Required before release signoff:

1. Expand authenticated admin visual evidence beyond the targeted login/overview/payment/SMS set when a release candidate is cut.
2. Check dense table/list views for text overflow, pagination, empty/error/loading states, and permission-denied panels.
3. Confirm admin remains dense and operational, not over-decorated like member/public surfaces.

## Final Fix Priority

1. Complete fresh public route visual evidence; local quality gate passes and partial mobile screenshots exist, but the Chrome harness stalled during the full public matrix.
2. Re-run the isolated Chrome full member route matrix; the post-fix attempts at `.cache/mobile_route_render_smoke/20260627T135321Z/` and `.cache/mobile_route_render_smoke/20260627T_postfix_matrix/` did not produce pass summaries.
3. Run device/screen-reader UAT for custom account sheets and bottom sheets.
4. After the above, run a single consolidated final route/contact-sheet/audit pass.

## Final Position

The member Flutter app is much closer to the Revolut10 reference than before: the dominant orange CTA issue is fixed, the three-tab COOL navigation is preserved, the top chrome and floating dock work on the main routes, and fresh targeted visual evidence passes for the changed/high-risk routes.

The remaining issues are not broad architectural failures. They are release-signoff evidence gaps: complete public visual proof, a successful post-fix isolated Chrome 55-route member matrix, and native assistive-technology UAT.
