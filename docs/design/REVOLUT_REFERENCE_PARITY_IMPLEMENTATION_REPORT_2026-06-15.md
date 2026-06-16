# Revolut Reference Parity Implementation Report

Date: 2026-06-15
Reference folder: `/Users/jeanbosco/Downloads/Revolut10`
Implementation goal: `docs/design/REVOLUT_REFERENCE_100_PERCENT_PARITY_GOAL_2026-06-15.md`

## Status

Implementation pass completed locally, with a follow-up strict visual pass after the user rated the app **5/10** against the Revolut references. This work improves the Flutter member app, Admin PWA, design assets, design docs, and evidence tooling toward the 100 percent parity goal. Current evidence includes member browser/CDP route screenshots, fresh post-background Flutter-test member-shell screenshots, physical Android route evidence, Pixel 4a 200% font-scale route screenshots, Pixel 4a TalkBack structural node captures, Admin PWA login screenshots, authenticated Admin PWA browser screenshots with masked evidence data, fresh Admin component screenshots, code-owned 200% text-scale/semantics coverage for the Home Momentum feed, and reference/implementation contact sheets.

Latest manual audit: `docs/design/REVOLUT_REFERENCE_MANUAL_PARITY_AUDIT_2026-06-15.md`. Current working baseline is improved from the user's **5/10** assessment because fresh post-background screenshots now exist, but it is still not a defensible 10/10 without final human visual and auditory accessibility signoff.

## Reference Coverage

All 11 reference screenshots currently present in `/Users/jeanbosco/Downloads/Revolut10` are in scope:

- `IMG_2739.PNG`
- `IMG_2740.PNG`
- `IMG_2741.PNG`
- `IMG_2742.PNG`
- `IMG_2747.PNG`
- `IMG_2748.PNG`
- `IMG_2749.PNG`
- `IMG_2750.PNG`
- `IMG_2751.PNG`
- `IMG_2752.PNG`
- `IMG_2755.PNG`

The reference set covers home/account balance, invest education, payments/contact lists, crypto/asset states, rewards/points, marketplace/product grids, media card feeds, watchlist cards, top chrome, and bottom navigation. `IMG_2743.PNG` was previously listed in the draft report but is not present in the folder on 2026-06-15.

| Reference | Pattern used | Collect translation |
| --- | --- | --- |
| `IMG_2739.PNG` | Home/account balance hero and action row | Home money hero, public ID pill, group-state pill, circular actions, anchored bottom nav |
| `IMG_2740.PNG` | Invest/education card rhythm | Collect-owned financial-state and group education cards, no investment claims |
| `IMG_2741.PNG` | Payment/contact list density | Groups, activity rows, contribution/payment detail rows |
| `IMG_2742.PNG` | Asset/state trading hierarchy | Payment status hierarchy translated to MoMo/USSD state, not crypto/trading |
| `IMG_2747.PNG` | Rewards/points surface | Group momentum and contribution-progress cards |
| `IMG_2748.PNG` | Marketplace/product grid | Home visual rail and generated product-art surfaces |
| `IMG_2749.PNG` | Media/content card feed | Collect-owned product visuals for MoMo, group momentum, and QR/share |
| `IMG_2750.PNG` | Watchlist/list card hierarchy | Admin dense tables and member financial rows |
| `IMG_2751.PNG` | Alternate top chrome and content stacking | Member top chrome pills, search/action density, screen-header glass panels |
| `IMG_2752.PNG` | Product-state and card depth | Shared glass card depth, gradients, shadows, and product-state surfaces |
| `IMG_2755.PNG` | Compact bottom navigation variant | Dark anchored glass bottom navigation with selected capsule |

## Implemented Changes

### Flutter Member App

- Replaced the runtime screen-background tokens with exact color families extracted from the supplied Revolut PNG backgrounds: account navy `#000840`, payments purple `#181038`, asset navy `#101830`, rewards violet `#302878`, wealth teal `#102028`, and stock teal-black `#001010`. Collect primary colors remain for components, actions, brand accents, chips, and illustrations.
- Corrected the earlier background gap by routing those extracted families through `CollectColors.screenGradientForPath()` and `CollectBackgroundRouteScope`, so Home, Groups, payment/ledger, share/rewards, profile/readiness, settings/legal, offline, and sync screens no longer share one generic dark canvas.
- Changed member top chrome to use dark ink pill/circle controls with high-contrast foreground text and icons.
- Changed bottom navigation to a darker anchored glass bar with selected capsule treatment.
- Upgraded shared `ScreenHeader` surfaces into tokenized glass/gradient header bands so secondary routes no longer start with repetitive plain text blocks.
- Refreshed shared `ScreenHeader` again into a dark, high-contrast finance-grade header with official `CollectBrandMark`, shield marker, and tokenized action capsules.
- Added blur-backed `CollectCard` surfaces to make translucent cards behave more like premium glass panels.
- Added shared `CollectVisualFeatureCard` so group, contribution, and payment-state routes can use Collect-owned generated visuals in their first viewport.
- Redesigned the Home total card into a stronger first-viewport money hero with larger amount hierarchy, darker gradient depth, public ID pill, and group-state pill.
- Reworked Home action controls into circular, thumb-first action buttons with labels, closer to the Revolut action-row rhythm.
- Added a rich visual rail on Home using Collect-owned generated assets and Flutter-rendered text.
- Added a data-backed Home Momentum feed using Collect-owned generated media, public group amount progress, supporter counts, share/payment context, and privacy-safe semantics.
- Added a Collect-owned Home rewards/discovery hub to better match the reference rewards/media/product density without copying merchant brands, marketplace grids, or Revolut labels.
- Removed verbose explanatory visible labels from the touched mobile/admin surfaces; labels now stay one line with ellipsis on shared headers, empty/loading states, Home reward/momentum cards, and admin table/status/header primitives.
- Made the Home visual rail and action strip adapt to 200% text scale without clipping critical actions.
- Fixed Pixel 4a 200% font-scale overflows in Home actions, visual group metrics, payment status cards, payment state hero rows, and expanded icon button rows.
- Added route-specific rich visuals on group detail, contribution entry, and payment status using the group momentum and MoMo signal assets.
- Added product-context visual cards to settings, privacy, notifications, support, and legal routes so utility surfaces no longer rely only on text/card stacks.

### Collect-Owned Assets

Generated assets:

- `assets/brand/generated/collect_visual_momo_signal.png`
- `assets/brand/generated/collect_visual_group_momentum.png`
- `assets/brand/generated/collect_visual_qr_share.png`

The assets are generated by:

- `scripts/generate_collect_visual_assets.py`

These are Collect-owned product visuals and do not copy or embed any Revolut reference screenshot.

### Admin PWA

- Fixed the mobile login clipping root cause by calculating card width from actual compact horizontal padding.
- Removed the visible prefilled admin phone number from the login form so screenshot evidence does not expose a real/private phone number.
- Applied the extracted reference-background canvas to the admin login and Admin PWA shell backgrounds.
- Gave the login card stronger glass/border/shadow treatment.
- Tightened admin page headers into bordered, premium panels.
- Upgraded admin data tables with rounded surfaces, heading treatment, denser row sizing, and subtle shadows.
- Upgraded the Admin shell, sidebar, mobile nav, topbar, page headers, filter bar, metric cards, status chips, empty states, pagination, and detail panels toward a darker operational fintech console.

### Evidence Tooling

- Added `scripts/generate_visual_evidence_contact_sheets.py` to create contact sheets from the actual Revolut reference folder inventory, Collect route screenshots, and Admin PWA screenshots.
- Added `scripts/collect_visual_evidence_capture.sh`.
  - Default mode creates contact sheets from the newest available route/admin PNG evidence and records a freshness caveat.
  - `COLLECT_VISUAL_EVIDENCE_FRESH=1` runs a non-Chrome Flutter-test screenshot capture path and then generates contact sheets.
- Updated `scripts/admin_pwa_render_smoke.sh` so mobile Admin PWA screenshots use CDP viewport emulation instead of a cropped raw Chrome screenshot.
- Updated `scripts/mobile_route_render_smoke.sh` to use a longer default CDP wait for release-web route screenshots so slower direct routes such as shared links and payment status do not produce blank bootstrap captures.
- Added `test/visual_evidence_capture_test.dart` as an opt-in visual capture harness. The mobile capture now renders all materialized production routes inside `CollectShell` using an injected shell path, avoiding local Chrome/CDP failures while still exercising the member chrome.
- Fixed an Admin PWA mobile overflow in queue signal chips that the new visual evidence harness exposed.
- Added `scripts/android_route_visual_evidence.sh`, which runs the physical Android route matrix and exports 54 route PNG screenshots plus a mobile contact sheet.
- Masked receiver MoMo numbers in payment review/status screenshots after visual inspection found a raw test receiver number in the first physical-device evidence run.
- Added explicit Admin PWA evidence mode and `scripts/admin_pwa_authenticated_render_smoke.sh` so authenticated list/detail admin routes can be browser-rendered with masked deterministic test data without weakening production login.
- Added a focused Home large-text/semantics test in `test/features/mobile_completion_test.dart` for the Momentum feed at 200% text scale.
- Added Pixel-width 200% text-scale regression coverage for the payment handoff route.
- Fixed local Android tooling by making `adb` resolvable in current and future Codex shells, and added a compatibility `test-android-apps/SKILL.md` entry that points to the plugin's concrete Android QA skill.

### Documentation

- Updated `DESIGN.md` with the new generated visual assets and the rule for rich product surfaces.
- Updated `docs/design/DESIGN_SYSTEM.md` with the same asset map and component model changes.
- Updated the manual parity audit with the media/accessibility refresh evidence and the remaining real-device screen-reader boundary.
- Updated the manual parity audit with Pixel 4a large-text/TalkBack structural evidence and the remaining VoiceOver/human-auditory boundary.
- Added this implementation report.

## Current Evidence

Passed in this implementation pass:

- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub --concurrency=1 test/features/design_system_components_test.dart test/features/widgets_test.dart test/persona_uat_smoke_test.dart test/app_shell_test.dart`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/features/design_system_components_test.dart test/features/widgets_test.dart test/persona_uat_smoke_test.dart`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub test/app_shell_test.dart test/visual_evidence_capture_test.dart test/features/design_system_components_test.dart`
- `scripts/admin_pwa_release_build.sh`
- `scripts/android_route_visual_evidence.sh`
- `COLLECT_MOBILE_DESIGN_AUDIT_DIR=.cache/collect_mobile_design_compliance/20260615T_dark_header_refresh ANDROID_DEVICE_UAT_SUMMARY=.cache/android_route_visual_evidence/20260615T162547Z/android_device_uat/summary.json scripts/collect_mobile_design_compliance_audit.sh --json`
- `COLLECT_MOBILE_DESIGN_AUDIT_DIR=.cache/collect_mobile_design_compliance/20260615T_utility_visuals_refresh ANDROID_DEVICE_UAT_SUMMARY=.cache/android_route_visual_evidence/20260615T162547Z/android_device_uat/summary.json scripts/collect_mobile_design_compliance_audit.sh --json`
- `COLLECT_MOBILE_DESIGN_AUDIT_DIR=.cache/collect_mobile_design_compliance/20260615T_admin_auth_refresh ANDROID_DEVICE_UAT_SUMMARY=.cache/android_route_visual_evidence/20260615T162547Z/android_device_uat/summary.json scripts/collect_mobile_design_compliance_audit.sh --json`
- `COLLECT_VISUAL_EVIDENCE_FRESH=1 COLLECT_VISUAL_EVIDENCE_DIR=/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_header_panel_full_fresh scripts/collect_visual_evidence_capture.sh`
- `COLLECT_VISUAL_EVIDENCE_FRESH=1 COLLECT_VISUAL_EVIDENCE_DIR=/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_rich_surfaces_fresh scripts/collect_visual_evidence_capture.sh`
- `scripts/collect_mobile_design_compliance_audit.sh --json`
- `scripts/admin_pwa_release_build.sh`
- `scripts/admin_pwa_render_smoke.sh`
- `MOBILE_ROUTE_RENDER_EVIDENCE_DIR=/Volumes/PRO-G40/COOL/.cache/mobile_route_render_smoke/20260615T_member_cdp_parity scripts/mobile_route_render_smoke.sh`
- `CHROME_CDP_HEADLESS_ARG=--headless=new ADMIN_PWA_AUTH_RENDER_EVIDENCE_DIR=.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry scripts/admin_pwa_authenticated_render_smoke.sh`
- `MOBILE_VISUAL_SOURCE_SUMMARY=.cache/android_route_visual_evidence/20260615T162547Z/screenshots/summary.json scripts/collect_visual_evidence_capture.sh`
- `COLLECT_VISUAL_EVIDENCE_FRESH=1 COLLECT_VISUAL_EVIDENCE_DIR=.cache/collect_visual_evidence/20260615T_dark_header_refresh scripts/collect_visual_evidence_capture.sh`
- `COLLECT_VISUAL_EVIDENCE_FRESH=1 COLLECT_VISUAL_EVIDENCE_DIR=.cache/collect_visual_evidence/20260615T_utility_visuals_refresh scripts/collect_visual_evidence_capture.sh`
- `COLLECT_VISUAL_EVIDENCE_FRESH=1 COLLECT_VISUAL_EVIDENCE_DIR=.cache/collect_visual_evidence/20260615T_media_a11y_refresh scripts/collect_visual_evidence_capture.sh`
- `COLLECT_MOBILE_DESIGN_AUDIT_DIR=.cache/collect_mobile_design_compliance/20260615T_media_a11y_refresh ANDROID_DEVICE_UAT_SUMMARY=.cache/android_route_visual_evidence/20260615T162547Z/android_device_uat/summary.json scripts/collect_mobile_design_compliance_audit.sh --json`
- `ANDROID_ROUTE_VISUAL_EVIDENCE_DIR=.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_normal ADB=/usr/local/Caskroom/android-platform-tools/36.0.2/platform-tools/adb ANDROID_UAT_DEVICE_ID=13111JEC215558 scripts/android_route_visual_evidence.sh`
- `ANDROID_ROUTE_VISUAL_EVIDENCE_DIR=.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_font2_retry3 ADB=/Users/jeanbosco/.cargo/bin/adb ANDROID_UAT_DEVICE_ID=13111JEC215558 scripts/android_route_visual_evidence.sh` with Android `font_scale=2.0`
- `COLLECT_MOBILE_DESIGN_AUDIT_DIR=.cache/collect_mobile_design_compliance/20260615T_pixel4a_large_text_talkback ANDROID_DEVICE_UAT_SUMMARY=.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_font2_retry3/android_device_uat/summary.json scripts/collect_mobile_design_compliance_audit.sh --json`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub --concurrency=1 test/features/mobile_completion_test.dart --plain-name 'home momentum feed supports large text and semantics'`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub --concurrency=1 test/features/design_system_components_test.dart test/features/mobile_completion_test.dart test/admin_pwa_test.dart`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub --concurrency=1 test/features/design_system_components_test.dart test/features/widgets_test.dart test/features/mobile_completion_test.dart test/admin_pwa_test.dart`
- `COLLECT_MOBILE_DESIGN_AUDIT_DIR=.cache/collect_mobile_design_compliance/20260615T_reference_background_compact_labels ANDROID_DEVICE_UAT_SUMMARY=.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_font2_retry3/android_device_uat/summary.json scripts/collect_mobile_design_compliance_audit.sh --json`
- `COLLECT_VISUAL_EVIDENCE_FRESH=1 COLLECT_VISUAL_EVIDENCE_DIR=.cache/collect_visual_evidence/20260615T_reference_background_compact_labels scripts/collect_visual_evidence_capture.sh`
- `COLLECT_VISUAL_EVIDENCE_FRESH=1 COLLECT_VISUAL_EVIDENCE_DIR=.cache/collect_visual_evidence/20260615T_route_aware_reference_backgrounds scripts/collect_visual_evidence_capture.sh`
- `COLLECT_VISUAL_EVIDENCE_DIR=.cache/collect_visual_evidence/20260615T_route_aware_reference_backgrounds COLLECT_MOBILE_DESIGN_AUDIT_DIR=.cache/collect_mobile_design_compliance/20260615T_route_aware_reference_backgrounds ANDROID_DEVICE_UAT_SUMMARY=.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_font2_retry3/android_device_uat/summary.json scripts/collect_mobile_design_compliance_audit.sh --json`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub --concurrency=1 test/features/mobile_completion_test.dart --plain-name 'payment handoff route tolerates Pixel width large text'`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub --concurrency=1 test/features/widgets_test.dart --plain-name 'payment status screen tolerates 200 percent text scale'`
- `/Volumes/PRO-G40/flutter_3_44/bin/flutter test --no-pub --concurrency=1 test/features/mobile_completion_test.dart test/features/widgets_test.dart test/persona_uat_smoke_test.dart test/features/design_system_components_test.dart`
- `bash -n scripts/android_route_visual_evidence.sh scripts/collect_visual_evidence_capture.sh && python3 -m py_compile scripts/generate_visual_evidence_contact_sheets.py`

Later rerun caveat:

- `ADMIN_PWA_SCREENSHOT_TIMEOUT_SECONDS=20 scripts/admin_pwa_render_smoke.sh` failed at `.cache/admin_pwa_render_smoke/20260615T165941Z/pwa-runtime.json` with `fetch failed` in the local Chrome/DevTools runtime step. The local HTTP server still served `/`, `main.dart.js`, `custom-sw.js`, and `manifest.json`. Keep the passing `.cache/admin_pwa_render_smoke/20260615T164756Z` evidence, but treat Admin browser reruns on this Mac as flaky.

Generated visual evidence:

- `/Volumes/PRO-G40/COOL/.cache/android_route_visual_evidence/20260615T162547Z/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/android_route_visual_evidence/20260615T162547Z/screenshots/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/android_route_visual_evidence/20260615T162547Z/contact_sheets/collect-mobile-route-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T163054Z/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T163054Z/contact_sheets/revolut-reference-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T163054Z/contact_sheets/collect-mobile-route-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T163054Z/contact_sheets/collect-admin-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_rich_surfaces_fresh/mobile/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_rich_surfaces_fresh/admin/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_rich_surfaces_fresh/contact_sheets/revolut-reference-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_rich_surfaces_fresh/contact_sheets/collect-mobile-route-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_rich_surfaces_fresh/contact_sheets/collect-admin-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/admin_pwa_render_smoke/20260615T164756Z/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/admin_pwa_render_smoke/20260615T164756Z/desktop-1440x900.png`
- `/Volumes/PRO-G40/COOL/.cache/admin_pwa_render_smoke/20260615T164756Z/mobile-390x844.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_mobile_design_compliance/20260615T_dark_header_refresh/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_dark_header_refresh/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_dark_header_refresh/contact_sheets/revolut-reference-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_dark_header_refresh/contact_sheets/collect-mobile-route-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_dark_header_refresh/contact_sheets/collect-admin-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_mobile_design_compliance/20260615T_utility_visuals_refresh/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_mobile_design_compliance/20260615T_admin_auth_refresh/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_utility_visuals_refresh/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_utility_visuals_refresh/mobile/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_utility_visuals_refresh/admin/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_utility_visuals_refresh/contact_sheets/revolut-reference-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_utility_visuals_refresh/contact_sheets/collect-mobile-route-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_utility_visuals_refresh/contact_sheets/collect-admin-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_media_a11y_refresh/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_media_a11y_refresh/mobile/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_media_a11y_refresh/mobile/home-390x844.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_media_a11y_refresh/admin/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_media_a11y_refresh/contact_sheets/revolut-reference-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_media_a11y_refresh/contact_sheets/collect-mobile-route-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_media_a11y_refresh/contact_sheets/collect-admin-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_mobile_design_compliance/20260615T_media_a11y_refresh/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_normal/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_font2_retry3/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_font2_retry3/contact_sheets/collect-mobile-route-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_font2_retry3/screenshots/mobile_route_home.png`
- `/Volumes/PRO-G40/COOL/.cache/android_accessibility_pixel4a/20260615T_large_text_retry3/device_settings_final.txt`
- `/Volumes/PRO-G40/COOL/.cache/android_accessibility_pixel4a/20260615T_talkback_structural_retry/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/android_accessibility_pixel4a/20260615T_talkback_structural_retry/shared_link_talkback.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_mobile_design_compliance/20260615T_pixel4a_large_text_talkback/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/mobile_route_render_smoke/20260615T_member_cdp_parity/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/mobile_route_render_smoke/20260615T_member_cdp_parity/contact_sheets/revolut-reference-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/mobile_route_render_smoke/20260615T_member_cdp_parity/contact_sheets/collect-mobile-route-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/mobile_route_render_smoke/20260615T_member_cdp_parity/contact_sheets/collect-admin-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry/contact_sheets/collect-admin-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry/admin-overview-1440x900.png`
- `/Volumes/PRO-G40/COOL/.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry/admin-groups-list-1440x900.png`
- `/Volumes/PRO-G40/COOL/.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry/admin-payment-events-390x844.png`
- `/Volumes/PRO-G40/COOL/.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry/admin-payment-intents-1440x900.png`
- `/Volumes/PRO-G40/COOL/.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry/admin-sms-detail-1440x900.png`
- `/Volumes/PRO-G40/COOL/.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry/admin-system-health-1440x900.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_reference_background_compact_labels/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_reference_background_compact_labels/mobile/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_reference_background_compact_labels/admin/summary.json`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_reference_background_compact_labels/contact_sheets/revolut-reference-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_reference_background_compact_labels/contact_sheets/collect-mobile-route-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_visual_evidence/20260615T_reference_background_compact_labels/contact_sheets/collect-admin-contact-sheet.png`
- `/Volumes/PRO-G40/COOL/.cache/collect_mobile_design_compliance/20260615T_reference_background_compact_labels/summary.json`

Fresh evidence counts:

- Physical Android mobile route PNGs: 54 of 54.
- Browser/CDP member route PNGs: 54 of 54 in `20260615T_member_cdp_parity`.
- Flutter-test member-shell mobile route PNGs: 54 of 54 in `20260615T_rich_surfaces_fresh`.
- Flutter-test member-shell mobile route PNGs after the dark-header refresh: 54 of 54 in `20260615T_dark_header_refresh`.
- Flutter-test member-shell mobile route PNGs after the utility-visual refresh: 54 of 54 in `20260615T_utility_visuals_refresh`.
- Flutter-test member-shell mobile route PNGs after the media/accessibility refresh: 54 of 54 in `20260615T_media_a11y_refresh`.
- Flutter-test member-shell mobile route PNGs after the reference-background/compact-label refresh: 54 of 54 in `20260615T_reference_background_compact_labels`.
- Pixel 4a normal-font physical mobile route PNGs: 54 of 54 in `20260615T_pixel4a_media_a11y_normal`.
- Pixel 4a 200% font-scale physical mobile route PNGs: 54 of 54 in `20260615T_pixel4a_media_a11y_font2_retry3`.
- Pixel 4a TalkBack structural captures: node-tree/screenshot evidence in `20260615T_talkback_structural_retry`, with device settings restored afterward.
- Admin PWA render-smoke PNGs: desktop 1440x900 and mobile 390x844 from rebuilt `build/web`, with unclipped mobile login after CDP viewport capture.
- Authenticated Admin PWA browser PNGs: 6 of 6 in `20260615T_admin_auth_parity_retry`, covering overview, groups, payment events, payment intents, SMS detail, and system health.
- Admin component PNGs: 5 from the non-Chrome Flutter-test evidence source.
- Contact sheets: Revolut reference set, Collect browser/CDP mobile route set, Collect physical Android mobile route set, Collect Admin set.
- Mobile capture runtime: `physical_android_integration_test` for the Android evidence and `flutter_test_repaint_boundary_member_shell` for `20260615T_reference_background_compact_labels`.
- Screenshot privacy review: payment surfaces now show masked receiver numbers such as `+250***3456`, not the full test MoMo number.

Important caveat: automated screenshots prove route rendering, privacy masking, broad visual coverage, and Pixel 4a 200% font-scale resilience. TalkBack was enabled for structural node capture, but this still does not replace human auditory signoff for subjective narration quality or iOS VoiceOver.

## Evidence Required Before Final 100 Percent Claim

Still required before a final 100 percent claim:

- iOS VoiceOver review and human auditory TalkBack/VoiceOver signoff. Pixel 4a 200% font-scale route proof and TalkBack structural capture now pass.
- Final human visual signoff against the full reference folder.

## Remaining Gaps

- Member route screenshot review has fresh browser/CDP evidence and fresh physical Android evidence.
- Admin login has fresh desktop/mobile browser evidence; authenticated list/detail design evidence now uses explicit masked evidence mode rather than a live production session.
- Rich visual treatment now covers Home story rail, Home Momentum feed, Share, group detail, contribution entry, payment status, settings, privacy, notifications, support, and legal routes; the remaining gap is product-justified marketplace/rewards/feed density rather than missing basic visual context.
- iOS VoiceOver and human auditory screen-reader review remain required.
- Local browser/CDP capture now passes for member route evidence, Admin login evidence, and authenticated Admin evidence after CDP viewport capture, longer route waits, and `--headless=new` retry.
- The final 100 percent claim still needs manual review against the reference folder, iOS VoiceOver checks, and human auditory screen-reader signoff.

## Boundary

Collect must not copy Revolut assets, trademarks, exact labels, component colors, screenshots, product claims, account names, tab names, or proprietary product behavior. Screen-background color matching is the explicit exception requested by the user; all product surfaces, runtime assets, copy, workflows, and component colors remain Collect-owned.
