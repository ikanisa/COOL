# Revolut Alignment Blocker Register

Date: 2026-06-27
Repo: `/Volumes/PRO-G40/COOL`
Current decision: **CODE-OWNED MOBILE ALIGNMENT PASS**

The repo has the alignment contract, intake paths, route-reference mapping, token switchpoints, current source consolidation, repo-local Revolut-like font files, runtime brand/media/icon inputs, component-token specification, passing current-source Android device UAT, fresh 55-route mobile screenshots, and a code-owned visual review against the supplied screenshot set.

Public release, store submission, or external brand claims still require the normal release-owner approval path. That governance approval is separate from this mobile code-owned implementation pass.

## Preserved Color Distinction

The four primary colors are not blockers and must be preserved exactly:

- `#8885F0`
- `#3CD070`
- `#D38B96`
- `#FF5E43`

## Required Inputs

| Key | Required input | Status | Current evidence | Next action |
| --- | --- | --- | --- | --- |
| revolut_font_files | Revolut-like UI font files and weight/style variants | Installed and validated | `assets/fonts/revolut/RevolutBorrowed-*.otf`, `pubspec.yaml`, `revolut_font_installed_or_blocked` | Replace in place if an exact font kit is later supplied |
| revolut_font_license_metadata | Sanitized font provenance metadata | Installed | `assets/fonts/revolut/PROVENANCE.md` | Replace in place if an exact font kit is later supplied |
| revolut_logo_wordmark_assets | Borrowed runtime logo and wordmark assets | Installed and validated | `assets/brand/revolut_borrowed/logos/wordmark.png`, `RevolutBorrowedAssets.wordmarkAssetPath`, `mobile_brand_asset_contract` | Replace in place if an exact kit is later supplied |
| revolut_platform_icon_assets | Android, iOS, web icon and adaptive icon assets | Installed and validated | `assets/brand/revolut_borrowed/app_icons/app_icon.png`, `web-512.png`, `web/icons/revolut-borrowed-web-512.png`, `platform_metadata_colors_match_contract` | Replace in place if an exact kit is later supplied |
| revolut_splash_launch_assets | Splash and launch artwork | Installed and validated | `assets/brand/revolut_borrowed/splash/splash_mark.png`, `splash_background.png`, `native_android_launch_splash_contract` | Replace in place if an exact kit is later supplied |
| revolut_icon_set_mapping | Revolut-like icon set or icon mapping | Installed | `assets/brand/revolut_borrowed/icons/icon-mapping.json` | Replace in place if a full icon kit is later supplied |
| revolut_component_tokens | Component, surface, chrome, nav, and motion tokens | Installed and validated | `docs/design/revolut_borrowed_tokens/revolut10_component_tokens_2026-06-27.json`, `revolut_borrowed_component_token_switchpoints` | Keep synced with `RevolutBorrowedTokens` |
| revolut_route_reference_matrix | Route-to-reference mapping for the supplied screenshots | Source mapped and reviewed | `DESIGN.md`, `docs/design/DESIGN_SYSTEM.md`, `docs/design/REVOLUT10_SCREENSHOT_ROUTE_REVIEW_MATRIX_2026-06-27.md`, fresh contact sheets | Replace mappings only if new screenshots are supplied |
| revolut_public_web_assets | Public web imagery and share-preview assets | Installed | `assets/brand/revolut_borrowed/media/share-preview.png` and `scripts/public_website_audit_evidence.sh` | Validate live public site during release evidence refresh |

## Validation And Signoff Blockers

| Key | Required proof | Status | Current evidence | Next action |
| --- | --- | --- | --- | --- |
| android_device_uat_current_source | Passing Android device UAT after the latest integration-test assertion fixes | Pass | `.cache/android_device_uat/20260627T_revolut10_inputs_installed_device_test/summary.json` | Keep as current evidence until source changes |
| revolut10_visual_signoff | Visual review against all 11 supplied screenshots and current app screenshots | Pass | `.cache/mobile_route_render_smoke/20260627T121726Z/contact_sheets/` and `docs/design/REVOLUT10_SCREENSHOT_ROUTE_REVIEW_MATRIX_2026-06-27.md` | Re-review when screenshots or UI source changes |
| mobile_findings_follow_up | Fix legal wrapping, Settings chrome, dialog styling, dense truncation, payment review hierarchy, and utility trust panels | Implemented and re-evidenced | `account_legal_screens.dart`, `settings_screen.dart`, `collect_group_cards.dart`, `collect_feature_surfaces.dart`, `payment_support_recovery_screens.dart`, `collection_create_screen.dart`, `group_qr_scanner_screen.dart`, `.cache/flutter_visual_evidence_revolut_followup_20260627/mobile/summary.json` | Refresh mobile route screenshots and compare against the Revolut10 matrix after any further UI changes |
| admin_workflow_security_follow_up | Add admin workflow guidance and close arbitrary-user permission probing | Implemented, re-evidenced, and applied to linked COOL Supabase | `admin_list_runtime.dart`, `admin_detail_runtime.dart`, `20260627143000_restrict_admin_permission_helper_probing.sql`, `supabase_production_readiness.sh`, `test/supabase_contract_test.dart`, `.cache/flutter_visual_evidence_revolut_followup_20260627/admin/summary.json` | Rotate the pasted Supabase service credentials and keep future pushes aligned with migration history |

## Unblocked Foundation

| Key | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| four_primary_colors_preserved | Preserve the four distinct primary colors | Preserved | `DESIGN.md`, `CollectColors.brandPrimaryHexes`, `four_primary_color_distinction_contract` |
| alignment_contract_written | Replace old brand-separation direction with borrowed Revolut alignment contract | Complete | `DESIGN.md`, `docs/design/DESIGN_SYSTEM.md`, `docs/design/REVOLUT_BORROWED_ALIGNMENT_PLAN_2026-06-27.md` |
| intake_paths_created | Create repo-local intake paths for approved inputs | Complete | `assets/fonts/revolut/README.md`, `assets/brand/revolut_borrowed/README.md`, this register |
| runtime_switchpoints_created | Route current runtime brand fallbacks through borrowed Revolut switchpoints | Complete | `RevolutBorrowedAssets`, `CollectBrandMark`, `LaunchSplashScreen`, `revolut_borrowed_runtime_switchpoints` |
| component_token_switchpoints_created | Route shared component styling through borrowed token switchpoints | Complete | `RevolutBorrowedTokens`, `CollectColors.screenGradientForPath`, `secondaryColorRoles`, `revolut_borrowed_component_token_switchpoints` |
| route_reference_matrix_created | Map the 11 supplied screenshots to COOL route families | Complete | `DESIGN.md`, `docs/design/DESIGN_SYSTEM.md`, `docs/design/REVOLUT10_SCREENSHOT_ROUTE_REVIEW_MATRIX_2026-06-27.md` |
