# Revolut Alignment Blocker Register

Date: 2026-06-27
Repo: `/Volumes/PRO-G40/COOL`
Current decision: **CODE-OWNED MOBILE ALIGNMENT PASS**

The repo has the alignment contract, intake paths, route-reference mapping, token switchpoints, current source consolidation, repo-local Inter UI and Inter Display font files, runtime brand/media/icon inputs, component-token specification, passing current-source Android device UAT, fresh 55-route mobile screenshots, and a code-owned visual review against the supplied screenshot set.

Public release, store submission, or external brand claims still require the normal release-owner approval path. That governance approval is separate from this mobile code-owned implementation pass.

## Preserved Color Distinction

The four primary colors are not blockers and must be preserved exactly:

- `#8885F0`
- `#3CD070`
- `#D38B96`
- `#FF5E43`

## Runtime Inputs

| Key | Required input | Status | Current evidence | Next action |
| --- | --- | --- | --- | --- |
| collect_font_files | Repo-local UI/display font files and weight/style variants | Installed and validated | `assets/fonts/collect/CollectRuntime-*.otf`, `assets/fonts/collect/CollectDisplay-*.otf`, `pubspec.yaml`, `collect_font_installed_or_blocked` | Keep stable unless typography is refactored deliberately; replace `Collect Display` with licensed Aeonik/Aeonik Pro only if official files are supplied |
| collect_font_license_metadata | Sanitized font provenance metadata | Installed | `assets/fonts/collect/PROVENANCE.md` | Keep provenance current |
| collect_logo_wordmark_assets | Collect-owned runtime logo and wordmark assets | Installed and validated | `assets/brand/collect_runtime/logos/wordmark.png`, `CollectRuntimeAssets.wordmarkAssetPath`, `mobile_brand_asset_contract` | Keep Collect-owned source artwork synced into the runtime path |
| collect_platform_icon_assets | Collect-owned Android, iOS, web icon and adaptive icon assets | Installed and validated | `assets/brand/collect_runtime/app_icons/app_icon.png`, `collect-web-512.png`, `web/icons/collect-web-512.png`, `platform_metadata_colors_match_contract` | Keep generated Collect app icon synced |
| collect_splash_launch_assets | Collect-owned splash and launch artwork | Installed and validated | `assets/brand/collect_runtime/splash/splash_mark.png`, `splash_background.png`, `native_android_launch_splash_contract` | Keep generated Collect mark/background synced |
| collect_icon_set_mapping | Collect icon mapping | Installed | `assets/brand/collect_runtime/icons/icon-mapping.json` | Keep synced with `CollectIcons` |
| collect_component_tokens | Component, surface, chrome, nav, and motion tokens | Installed and validated | `docs/design/collect_runtime_tokens/collect_component_tokens_2026-06-29.json`, `collect_runtime_component_token_switchpoints` | Keep synced with `CollectRuntimeTokens` |
| collect_semantic_icon_keywords | Icon-first keyword mapping for support, members, amount, type, public/private, QR, receiver, owner, and visibility metadata | Installed and enforced | `lib/app/theme/collect_semantic_icons.dart`, `docs/design/collect_runtime_tokens/collect_semantic_icon_keywords_2026-06-30.json`, `icon_first_metadata_and_group_name_contract` | Add new operational metadata keywords to the mapping before adding visible labels |
| collect_route_reference_matrix | Route-to-reference mapping for the supplied screenshots | Source mapped and reviewed | `DESIGN.md`, `docs/design/DESIGN_SYSTEM.md`, `docs/design/REVOLUT10_SCREENSHOT_ROUTE_REVIEW_MATRIX_2026-06-27.md`, fresh contact sheets | Replace mappings only if new screenshots are supplied |
| collect_public_web_assets | Collect-owned public web imagery and share-preview assets | Installed | `assets/brand/collect_runtime/media/share-preview.png` and `scripts/public_website_audit_evidence.sh` | Validate live public site during release evidence refresh |

## Validation And Signoff Blockers

| Key | Required proof | Status | Current evidence | Next action |
| --- | --- | --- | --- | --- |
| android_device_uat_current_source | Passing Android device UAT after the latest integration-test assertion fixes | Pass | `.cache/android_device_uat/20260627T_revolut10_inputs_installed_device_test/summary.json` | Keep as current evidence until source changes |
| revolut10_visual_signoff | Visual review against all 11 supplied screenshots and current app screenshots | Pass | `.cache/mobile_route_render_smoke/20260627T121726Z/contact_sheets/` and `docs/design/REVOLUT10_SCREENSHOT_ROUTE_REVIEW_MATRIX_2026-06-27.md` | Re-review when screenshots or UI source changes |
| mobile_findings_follow_up | Fix legal wrapping, Settings chrome, dialog styling, dense truncation, payment review hierarchy, and utility trust panels | Implemented and re-evidenced | `account_legal_screens.dart`, `settings_screen.dart`, `collect_group_cards.dart`, `collect_feature_surfaces.dart`, `payment_support_recovery_screens.dart`, `collection_create_screen.dart`, `group_qr_scanner_screen.dart`, `.cache/flutter_visual_evidence_revolut_followup_20260627/mobile/summary.json` | Refresh mobile route screenshots and compare against the Revolut10 matrix after any further UI changes |
| android_accessibility_structural_uat | Native Android structural accessibility capture with TalkBack enabled | Pass | `.cache/android_accessibility_pixel4a/20260629T053724Z/summary.json`, `scripts/android_accessibility_structural_evidence.sh --json`, `docs/design/ANDROID_TALKBACK_REVIEW_PACKET_2026-06-29.md` | Human listening signoff, if required, uses the review packet |
| public_member_admin_visual_matrices | Complete public, member, and admin route-breadth visual evidence | Pass | `.cache/public_visual_evidence/20260627T_public_matrix_fixed/summary.json`, `.cache/mobile_route_render_smoke/20260627T_postfix_fixed_clean/summary.json`, `.cache/collect_visual_evidence/20260627T_admin_workflow_controls/admin/summary.json` | Refresh these matrices after any public, member, or admin UI source change |
| admin_workflow_security_follow_up | Add admin workflow guidance, current-page exports, persisted operator notes/SLA policy, group support-status write action, feature-flag toggle action, and close arbitrary-user permission probing | Implemented in source; linked Supabase readiness blocked because remote is missing the latest migration | `admin_list_runtime.dart`, `admin_detail_runtime.dart`, `20260627143000_restrict_admin_permission_helper_probing.sql`, `20260627183000_add_admin_operator_note_rpc.sql`, `20260627184500_add_admin_queue_sla_policies.sql`, `20260627190000_add_admin_collection_status_rpc.sql`, `20260627191000_add_admin_feature_flag_toggle_rpc.sql`, `supabase_production_readiness.sh`, `test/admin_pwa_test.dart`, `test/supabase_contract_test.dart`, `.cache/collect_visual_evidence/20260627T_admin_workflow_controls/admin/summary.json` | Apply `20260627191000` to linked Supabase after explicit production-DB approval, rerun readiness, then add further domain-specific write actions only where operations policy defines a safe action |
| admin_visual_route_matrix | Expanded admin mobile/desktop visual route proof | Pass | `.cache/collect_visual_evidence/20260627T_admin_workflow_controls/admin/summary.json`, `test/visual_evidence_capture_test.dart` | Refresh when admin routes or workflow UI changes |
| supabase_linked_readiness | Linked COOL Supabase migration, schema, RLS, advisor, privilege, UAT, Edge Function, Auth, and platform gates | Blocked: remote missing `20260627191000` | `scripts/supabase_production_readiness.sh --json` passes project health, local migration validation, and linked error-level advisors, then reports `migrations local=49 remote=48 missing=1 extra=0` and `MISSING 20260627191000`; `20260627171000_harden_diaspora_stripe_table_grants.sql`, `20260627183000_add_admin_operator_note_rpc.sql`, `20260627184500_add_admin_queue_sla_policies.sql`, `20260627190000_add_admin_collection_status_rpc.sql`, `20260627191000_add_admin_feature_flag_toggle_rpc.sql`, `test/supabase_contract_test.dart` | Apply `20260627191000` to linked Supabase after explicit production-DB approval and rerun `scripts/supabase_production_readiness.sh --json` before backend release signoff |
| android_release_artifacts | Current signed production APK/AAB and release artifact manifest | Pass | `scripts/release_artifact_manifest.sh --json` generated `2026-06-29T06:35:00Z` with 10/10 fresh artifacts; `scripts/flutter_mobile_release_gate.sh --json` generated `2026-06-29T06:35:03Z` with APK/AAB freshness and signature checks passing; `scripts/release_status.sh --json` reports `GO` with no blocker keys | Rebuild APK/AAB and Admin PWA after any further Android/mobile/admin-web source change |

## Unblocked Foundation

| Key | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| four_primary_colors_preserved | Preserve the four distinct primary colors | Preserved | `DESIGN.md`, `CollectColors.brandPrimaryHexes`, `four_primary_color_distinction_contract` |
| alignment_contract_written | Replace old brand-separation direction with Collect runtime alignment contract | Complete | `DESIGN.md`, `docs/design/DESIGN_SYSTEM.md`, `docs/design/REVOLUT_BORROWED_ALIGNMENT_PLAN_2026-06-27.md` |
| intake_paths_created | Create repo-local intake paths for approved inputs | Complete | `assets/fonts/collect/README.md`, `assets/brand/collect_runtime/README.md`, this register |
| runtime_switchpoints_created | Route current runtime brand fallbacks through Collect runtime switchpoints | Complete | `CollectRuntimeAssets`, `CollectBrandMark`, `LaunchSplashScreen`, `collect_runtime_asset_switchpoints` |
| component_token_switchpoints_created | Route shared component styling through Collect runtime token switchpoints | Complete | `CollectRuntimeTokens`, `CollectColors.screenGradientForPath`, `secondaryColorRoles`, `collect_runtime_component_token_switchpoints` |
| route_reference_matrix_created | Map the 11 supplied screenshots to COOL route families | Complete | `DESIGN.md`, `docs/design/DESIGN_SYSTEM.md`, `docs/design/REVOLUT10_SCREENSHOT_ROUTE_REVIEW_MATRIX_2026-06-27.md` |
