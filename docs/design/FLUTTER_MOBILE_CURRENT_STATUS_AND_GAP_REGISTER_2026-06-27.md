# Flutter Mobile Current Status And Gap Register

Date: 2026-06-27

Scope: COOL Flutter mobile app Revolut-benchmarked Collect runtime alignment, based on current source, installed Collect runtime inputs, fresh route screenshots, passing Android UAT, and final design compliance evidence.

## Non-Negotiable Product Decisions

- Preserve exactly three bottom navigation destinations: `Home`, `Groups`, and `Settings`.
- Do not introduce Revolut's five-tab destination model into the COOL shell.
- Preserve the four Collect primary colors as the only deliberate brand-color distinction:
  - Periwinkle `#8885F0`
  - Mint `#3CD070`
  - Rose `#D38B96`
  - Orange `#FF5E43`
- Use Periwinkle, not Orange, for default dominant CTAs and selected controls. Orange remains available only for urgent, destructive, alert, notification, or small accent states.
- Preserve full secondary/support colors through named tokens for surfaces, borders, focus, and semantic foreground/container roles.
- Use the supplied `Revolut10` screenshots and the Collect runtime kit as the active reference contract, but keep Collect-specific Rwanda group collection, MoMo, QR/share, contribution, settings, and admin behavior.

## Current Source Status

| Area | Status | Evidence |
| --- | --- | --- |
| Bottom navigation | Source aligned | `lib/core/widgets/collect_shell.dart` contains only `/home`, `/groups`, `/settings` and labels `Home`, `Groups`, `Settings`. |
| Top chrome | Source aligned to supplied screenshots | `lib/shared/widgets/collect_top_chrome.dart` uses 58 px circular/avatar action controls and black glass search treatment. |
| Route background families | Source mapped | `CollectColors.screenGradientForPath()` maps Home, Groups, payment/contribution, share/settings, wealth/profile, content/legal, offline/sync, notifications, and admin families to extracted Revolut-like background tokens. |
| Four primary colors | Source locked | `CollectColors.brandPrimaryHexes` and design audit contract preserve `#8885F0`, `#3CD070`, `#D38B96`, `#FF5E43`. |
| Default CTA color | Source corrected and guarded | `CollectColors.actionColor` resolves to Periwinkle `#8885F0`; routine landing, public static CTA, and group-card decorative surfaces no longer use Orange; `urgentAction`/`brandAction` preserve Orange `#FF5E43` for non-default high-emphasis accents. |
| Full secondary colors | Source exposed | `CollectRuntimeTokens.secondaryColorRoles` and `secondaryColorHexes` expose full support and semantic token roles. |
| Card radius and compact density | Source aligned further | `CollectRadius.card = 32`; Groups uses `GroupCardVariant.compact` for the primary mobile list. |
| Payment status UAT assertions | Source patched, not device-proven | `integration_test/app_uat_smoke_test.dart` now scrolls to `Verification trail` and accepts multiple `Activity` labels. |
| Brand/font switchpoints | Inputs installed, pending validation | `CollectRuntimeTypography`, `pubspec.yaml`, and `CollectRuntimeAssets` now route through installed `assets/fonts/collect/` and `assets/brand/collect_runtime/` inputs. `Collect Runtime` is backed by Inter and `Collect Display` is backed by Inter Display to better match the Revolut10 UI/body and display rhythm while exact Aeonik files remain unavailable. |
| Naming cleanup | Source/docs checked | Targeted search found no partner-framed runtime names or old brand-separation language in active design/theme/pubspec paths checked for this register. |

## Existing Evidence Inventory

| Evidence | Status | Path |
| --- | --- | --- |
| Full web route render smoke | Pass | `.cache/mobile_route_render_smoke/20260627T121726Z/summary.json` reports `status=pass`, `route_count=55`, viewport `390x844`, generated `2026-06-27T12:43:16Z`. |
| Mobile contact sheet | Pass | `.cache/mobile_route_render_smoke/20260627T121726Z/contact_sheets/collect-mobile-route-contact-sheet.png`. |
| Revolut10 reference contact sheet | Pass | `.cache/mobile_route_render_smoke/20260627T121726Z/contact_sheets/revolut-reference-contact-sheet.png`. |
| Mobile design compliance audit | Pass | `.cache/collect_mobile_design_compliance/20260627T_orange_reserved_sweep/summary.json`. |
| Android device UAT first run | Failed before app tests were patched | `.cache/android_device_uat/20260627T_revolut10_alignment/summary.json`. |
| Android device UAT upload-debug run | Failed before app tests were patched | `.cache/android_device_uat/20260627T_revolut10_alignment_upload_debug/summary.json`. |
| Android device UAT fixed-source attempt | Failed on assertions now patched in source | `.cache/android_device_uat/20260627T_revolut10_alignment_fixed/summary.json`; stale failure log cites missing visible `Verification trail` and duplicate `Activity`. |
| Current post-patch Android device UAT | Pass | `.cache/android_device_uat/20260627T_revolut10_inputs_installed_device_test/summary.json`. |
| Screenshot route review matrix | Pass | `docs/design/REVOLUT10_SCREENSHOT_ROUTE_REVIEW_MATRIX_2026-06-27.md` maps and reviews all 11 supplied screenshots against COOL route families. |
| Visual review against all supplied screenshots | Pass | Fresh current mobile/reference contact sheets reviewed and recorded in `docs/design/REVOLUT10_SCREENSHOT_ROUTE_REVIEW_MATRIX_2026-06-27.md`. |
| Inter typography refresh matrix | Pass | `.cache/mobile_visual_evidence_matrix/20260630T_inter_typography/summary.json` captures Home, Groups, and Settings after the Inter/Inter Display swap across compact, baseline, large, light, dark, and 200% text states. |

## Gap Register

| ID | Gap | Current impact | Required fix or proof | Approval needed before execution |
| --- | --- | --- | --- | --- |
| G1 | Android UAT not rerun after current assertion patches | Fixed | Current-source Pixel 4a UAT passed at `.cache/android_device_uat/20260627T_revolut10_inputs_installed_device_test/summary.json` | No |
| G2 | Android UAT used upload-debug signing, not Play app-signing overwrite path | Accepted for mobile code-owned UAT | Current UAT used local upload-debug signing override; Play signing remains a release-governance question, not a mobile UI gap | Release approval only |
| G3 | Collect runtime/Revolut-aligned font files | Fixed | Inter UI/body and Inter Display font bundles installed, registered, provenance-recorded, and audit-passed; licensed Aeonik/Aeonik Pro remains optional only if official files are supplied | No |
| G4 | Collect runtime/Revolut-like brand/media/icon kit | Fixed | Runtime assets installed, switchpoints wired, route screenshots and audit passed | No |
| G5 | Icon mapping still local | Fixed | Icon mapping file installed while runtime continues to use `CollectIcons` as the adapter layer | No |
| G6 | Existing web route evidence URL was temporary | Fixed | Fresh route evidence generated at `.cache/mobile_route_render_smoke/20260627T121726Z/summary.json`; the temporary URL is no longer used as proof | No |
| G7 | Full visual screenshot review is not signed off | Fixed for code-owned mobile review | Fresh contact sheets reviewed and matrix signed as code-owned mobile visual QA | No |
| G8 | Old parity docs still contain historical "Revolut-style" language | Release-facing docs can be confused with current Collect runtime alignment status | Fixed by archive notices in the 2026-06-18 evidence/checklist docs | No |
| G9 | Route evidence may not cover every latest design nuance | Fixed for current mobile source | 55-route screenshot pass, contact-sheet review, Android UAT, and final design audit are current | No |
| G10 | Public/admin surfaces need the same proof level | Moved out of mobile gap scope | Public share-preview assets are installed; admin/public release proof remains separate release evidence, not a Flutter mobile blocker | Release scope only |

## Fix Sequence

1. Source contract is frozen: three bottom nav items, four primary colors, full secondary colors, Collect runtime-like route family mapping, installed runtime inputs, and code-owned validation evidence.
2. Current-source Android UAT is green.
3. Current 55-route screenshot render and contact sheets are green.
4. Historical docs are archived and cannot override the current Collect runtime alignment contract.
5. Font, brand, media, icon mapping, and token inputs are installed and validated by the final audit. Font runtime now uses Inter for UI/body and Inter Display for large heading/money hierarchy.
6. Release-owner approval remains separate from this mobile code-owned implementation pass.

## Approval Gate

Current mobile code-owned action is complete. Rerun the evidence only after source, supplied screenshots, or runtime Collect inputs change.
