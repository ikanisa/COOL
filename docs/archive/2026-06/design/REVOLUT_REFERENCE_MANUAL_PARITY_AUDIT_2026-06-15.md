# Revolut Reference Manual Parity Audit

Date: 2026-06-15
Repo: `/Volumes/PRO-G40/COOL`
Reference folder: `/Users/jeanbosco/Downloads/Revolut10`
Reference count inspected: 11 PNG screenshots

## Verdict

Current status: **not yet 100 percent parity**.

The latest implementation pass moves Collect materially closer to the Revolut reference quality: the mobile app now has darker first-viewport chrome, stronger money/payment hierarchy, richer generated product visuals, a data-backed Home Momentum feed, masked receiver MoMo display, anchored bottom navigation, utility-route product-context cards, and fresh 54-route visual evidence. The Admin PWA has a stronger login and denser operational surfaces. The user then reset the honest visual baseline to **5/10** and required screen backgrounds to match the shared Revolut screenshot backgrounds exactly while keeping Collect primary colors for everything else.

Honest current rating against the supplied references:

| Area | Working status | Reason |
| --- | --- | --- |
| Mobile app visual parity | In progress from 5/10 | The new background token now uses extracted Revolut reference background colors, Home has a richer Collect-owned rewards/discovery hub, and fresh post-background screenshots now exist for 54/54 member routes. Human visual scoring is still required before claiming 10/10. |
| Admin panel visual parity | In progress from 5/10 | The Admin shell, topbar, navigation, page headers, filters, metrics, tables, empty states, and detail cards now use a darker operational fintech console treatment, with fresh Flutter-test admin screenshots. Production-session browser proof is still separate. |
| Assets and product richness | In progress | Current MoMo, group momentum, QR, Home story rail, Home Momentum cards, and the new Home rewards/discovery hub improve density, but they are still legacy Collect-generated assets. The 100 percent alignment pass must replace them with borrowed Revolut assets or Revolut-like equivalents. |
| Evidence strength | Strong code-owned evidence | Pixel 4a normal/200% route evidence, TalkBack structural capture, fresh 54-route Flutter-test screenshots, fresh admin screenshots, and design compliance now pass. Human auditory screen-reader and final visual signoff remain outside automation. |
| Brand alignment | Failing current target | The app has route-aware Revolut background colors and stronger fintech rhythm, but it does not yet bundle the Revolut font, partnership logos, approved icons, platform assets, or full token system. |

Overall current working baseline: **above the user-rated 5/10 baseline, but not yet a defensible 10/10**. Fresh post-background evidence now exists, but the repo should not claim 10/10 or 100 percent parity until iOS VoiceOver, human auditory screen-reader signoff, and final human visual review against all 11 references pass.

## Evidence Reviewed

- Reference contact sheet: `.cache/collect_visual_evidence/20260615T_utility_visuals_refresh/contact_sheets/revolut-reference-contact-sheet.png`
- Fresh mobile contact sheet: `.cache/collect_visual_evidence/20260615T_utility_visuals_refresh/contact_sheets/collect-mobile-route-contact-sheet.png`
- Fresh admin component contact sheet: `.cache/collect_visual_evidence/20260615T_utility_visuals_refresh/contact_sheets/collect-admin-contact-sheet.png`
- Latest mobile/admin contact sheets after the media/accessibility pass: `.cache/collect_visual_evidence/20260615T_media_a11y_refresh/contact_sheets/collect-mobile-route-contact-sheet.png` and `.cache/collect_visual_evidence/20260615T_media_a11y_refresh/contact_sheets/collect-admin-contact-sheet.png`
- Latest Home route evidence after the Momentum feed: `.cache/collect_visual_evidence/20260615T_media_a11y_refresh/mobile/home-390x844.png`
- Member browser/CDP route evidence: `.cache/mobile_route_render_smoke/20260615T_member_cdp_parity/summary.json`
- Member browser/CDP contact sheet: `.cache/mobile_route_render_smoke/20260615T_member_cdp_parity/contact_sheets/collect-mobile-route-contact-sheet.png`
- Physical Android route evidence: `.cache/android_route_visual_evidence/20260615T162547Z/summary.json`
- Pixel 4a normal-font route evidence: `.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_normal/summary.json`
- Pixel 4a 200% font-scale route evidence: `.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_font2_retry3/summary.json`
- Pixel 4a 200% font-scale contact sheet: `.cache/android_route_visual_evidence/20260615T_pixel4a_media_a11y_font2_retry3/contact_sheets/collect-mobile-route-contact-sheet.png`
- Pixel 4a TalkBack structural capture: `.cache/android_accessibility_pixel4a/20260615T_talkback_structural_retry/summary.json`
- Passing Admin PWA render-smoke: `.cache/admin_pwa_render_smoke/20260615T164756Z/summary.json`
- Authenticated Admin PWA browser evidence: `.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry/summary.json`
- Authenticated Admin PWA contact sheet: `.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry/contact_sheets/collect-admin-contact-sheet.png`
- Design compliance audit: `.cache/collect_mobile_design_compliance/20260615T_admin_auth_refresh/summary.json`
- Latest design compliance audit after the media/accessibility pass: `.cache/collect_mobile_design_compliance/20260615T_media_a11y_refresh/summary.json`
- Latest design compliance audit after Pixel 4a large-text/TalkBack pass: `.cache/collect_mobile_design_compliance/20260615T_pixel4a_large_text_talkback/summary.json`
- Latest fresh post-background visual evidence: `.cache/collect_visual_evidence/20260615T_reference_background_compact_labels/summary.json`
- Latest fresh post-background mobile contact sheet: `.cache/collect_visual_evidence/20260615T_reference_background_compact_labels/contact_sheets/collect-mobile-route-contact-sheet.png`
- Latest fresh post-background admin contact sheet: `.cache/collect_visual_evidence/20260615T_reference_background_compact_labels/contact_sheets/collect-admin-contact-sheet.png`
- Latest fresh post-background reference contact sheet: `.cache/collect_visual_evidence/20260615T_reference_background_compact_labels/contact_sheets/revolut-reference-contact-sheet.png`
- Latest design compliance audit after reference-background/compact-label pass: `.cache/collect_mobile_design_compliance/20260615T_reference_background_compact_labels/summary.json`
- Latest route-aware background visual evidence: `.cache/collect_visual_evidence/20260615T_route_aware_reference_backgrounds/summary.json`
- Latest route-aware background mobile contact sheet: `.cache/collect_visual_evidence/20260615T_route_aware_reference_backgrounds/contact_sheets/collect-mobile-route-contact-sheet.png`
- Latest route-aware background design compliance: `.cache/collect_mobile_design_compliance/20260615T_route_aware_reference_backgrounds/output.json`

## Reference-To-Collect Review

| Reference | Revolut pattern observed | Collect match | Result |
| --- | --- | --- | --- |
| `IMG_2739.PNG` | Dark home balance hero, action row, ID issue card, bottom nav | Home route has dark money hero, circular actions, bottom nav, and activity cards | Strong match |
| `IMG_2740.PNG` | Single dominant invest education card on dark gradient | Collect uses MoMo/group education cards and generated visuals without investment claims | Good translation |
| `IMG_2741.PNG` | Dense payments/contact list with dark top chrome | Groups, members, ledger, and payment routes now have darker shared headers and compact rows | Good, still lighter list density |
| `IMG_2742.PNG` | Asset state with action-required card and transaction list | Payment status/state routes use amount-first cards, masked receiver, and status pipeline | Strong product translation |
| `IMG_2747.PNG` | Alternate payment/contact list with bottom nav | Invite, members, and ledger screens cover this pattern with safe group identities | Good |
| `IMG_2748.PNG` | Crypto/asset list with action card | Payment pending/expired/needs-review routes cover equivalent state hierarchy without crypto behavior | Strong translation |
| `IMG_2749.PNG` | Rewards points surface with product tiles | Home visual rail and data-backed Momentum cards cover this category with Collect-owned group/payment context | Good, still fewer tiles |
| `IMG_2750.PNG` | Marketplace brand grid and content feed | Collect has generated visuals and a Momentum feed, but not an equivalent dense marketplace/grid surface | Partial |
| `IMG_2751.PNG` | Rich media card feed and bottom nav | Home, group profile, and Momentum cards include richer visuals; feed depth is still lower | Good, not equal density |
| `IMG_2752.PNG` | Large image-led promotional cards | QR/share, group visuals, and Momentum cards improve this; fewer image-led stacked offers exist | Good, not equal density |
| `IMG_2755.PNG` | Invest watchlist, chips, dense market rows | Admin tables and member ledger rows translate density; no misleading invest/watchlist behavior is copied | Good translation |

## Improvements Completed In This Continuation

- Reworked shared `ScreenHeader` from a pale card into a dark, high-contrast finance-grade glass header.
- Preserved `CollectBrandMark` inside the new header so the brand source of truth remains asset-backed.
- Added tokenized shield/brand/action capsule treatment for secondary routes.
- Refreshed Flutter-test visual evidence after the utility visual-card change at `.cache/collect_visual_evidence/20260615T_utility_visuals_refresh`.
- Added generated-asset product-context cards to settings, privacy, notifications, support, and legal routes to reduce the remaining text-heavy utility-screen gap.
- Added authenticated Admin PWA browser evidence at `.cache/admin_pwa_authenticated_render_smoke/20260615T_admin_auth_parity_retry` using masked evidence-mode data.
- Added a data-backed Home Momentum feed using Collect-owned generated media for public groups, amount progress, supporter counts, and privacy-safe share/payment context.
- Added code-owned Home 200% text-scale and semantics coverage, including labels for Momentum cards and overflow protection for the Home visual rail/action strip.
- Refreshed Flutter-test mobile/admin contact sheets and design compliance evidence at `.cache/collect_visual_evidence/20260615T_media_a11y_refresh` and `.cache/collect_mobile_design_compliance/20260615T_media_a11y_refresh`.
- Fixed real Pixel 4a 200% font-scale overflows in Home actions, visual group metrics, payment status cards, payment state heroes, and expanded button rows.
- Passed Pixel 4a physical 54-route evidence at normal font scale and 200% Android font scale.
- Enabled TalkBack on Pixel 4a, captured structural accessibility node trees/screenshots, and restored device accessibility settings to `font_scale=1.0`, `accessibility_enabled=0`, `enabled_accessibility_services=null`.
- Extracted exact screen-background color families from all 11 Revolut PNG references and moved `screenBase`, `screenGradient`, and `adminScreenGradient` to those reference-background tokens: `#000840`, `#181038`, `#101830`, `#302878`, `#102028`, and `#001010`.
- Fixed the route application gap: `CollectShell` now passes the active route into `CollectBackgroundRouteScope`, and `CollectGradientBackground` uses `CollectColors.screenGradientForPath()` to apply account blue, payments purple, asset navy, rewards violet, wealth teal, content dark, and invest teal-black backgrounds to the matching route families.
- Added a Collect-owned Home rewards/discovery hub to close the `IMG_2749.PNG` to `IMG_2752.PNG` density gap without copying rewards brands or marketplace content.
- Upgraded the Admin shell/topbar/nav/page/table/filter/detail primitives toward a darker operational fintech console.
- Removed verbose explanatory visible labels from the touched mobile/admin surfaces and enforced one-line ellipsized labels on shared section headers, empty/loading states, Home reward/momentum cards, and admin status/table/header primitives.
- Replaced blank image-less group card covers with Collect-owned generated media selected from group context, improving Groups/Home public group density without copying marketplace or reward assets.
- Refreshed post-background Flutter-test evidence at `.cache/collect_visual_evidence/20260615T_reference_background_compact_labels`, covering 54/54 member routes and 5 admin screenshots.
- Refreshed design compliance at `.cache/collect_mobile_design_compliance/20260615T_reference_background_compact_labels` with passing reference/background, route, Android UAT, and token checks.

## Remaining Work For 10/10

- Complete iOS VoiceOver and human auditory screen-reader signoff. Pixel 4a 200% font-scale route evidence and TalkBack structural node captures now pass, but automated node capture is not a substitute for a person listening to full narration quality.
- Add production-backed marketplace/rewards/feed equivalents or Revolut-like placeholders so the missing Revolut-native product density is not left as generic Collect content.
- Repeat production-session Admin browser render smoke reliably if live credentials are supplied; the authenticated design evidence now uses explicit masked evidence mode.

## Boundary

The old brand-separation boundary is superseded by `docs/design/REVOLUT_BORROWED_ALIGNMENT_PLAN_2026-06-27.md`. Current evidence is not enough for 100 percent borrowed Revolut alignment because the app still lacks approved Revolut fonts, platform assets, runtime logos, iconography, and complete brand-token migration.
