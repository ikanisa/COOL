# Revolut Alignment Blocker Register

Date: 2026-06-27
Repo: `/Volumes/PRO-G40/COOL`
Current decision: **BLOCKED**

The repo has the alignment contract and intake paths, but it does not yet contain the approved borrowed Revolut font files, runtime brand kit, icon set, or component-token specification. Do not claim 100 percent borrowed Revolut alignment while any row below is `Blocked`.

## Preserved Color Distinction

The four primary colors are not blockers and must be preserved exactly:

- `#8885F0`
- `#3CD070`
- `#D38B96`
- `#FF5E43`

## Required Inputs

| Key | Required input | Status | Current evidence | Next action |
| --- | --- | --- | --- | --- |
| revolut_font_files | Approved Revolut UI font files and weight/style variants | Blocked | `assets/fonts/revolut/` contains only intake documentation | Add approved font files and register them in `pubspec.yaml` |
| revolut_font_license_metadata | Sanitized font approval/license metadata | Blocked | No approval metadata file is present | Add sanitized approval source, reviewer, and date |
| revolut_logo_wordmark_assets | Approved logo and wordmark assets | Blocked | `assets/brand/revolut_borrowed/logos/` is reserved but contains no approved runtime asset | Add approved runtime logo/wordmark assets |
| revolut_platform_icon_assets | Approved Android, iOS, web icon and adaptive icon assets | Blocked | Platform resources still use existing Collect-generated assets | Add platform-ready icon assets and wire build resources |
| revolut_splash_launch_assets | Approved splash and launch artwork | Blocked | `assets/brand/revolut_borrowed/splash/` is reserved, and platform launch resources still use current Collect fallbacks | Add approved splash assets and update Android/iOS/web launch surfaces |
| revolut_icon_set_mapping | Approved Revolut icon set or icon mapping | Blocked | Runtime icons still use `CollectIcons` and Material fallbacks | Add approved icon set or mapping matrix |
| revolut_component_tokens | Approved component, surface, chrome, nav, and motion tokens | Blocked | Current tokens are local Collect/Revolut-reference approximations | Add token spec and map it into theme/component tokens |
| revolut_route_reference_matrix | Revolut-like route-to-reference mapping | Blocked | Existing mapping uses local screenshot interpretation | Add approved route matrix for member, admin, and public web |
| revolut_public_web_assets | Approved public web imagery and share-preview assets | Blocked | `assets/brand/revolut_borrowed/media/` is reserved, and public web still uses current local brand assets | Add approved assets and update public surfaces |

## Unblocked Foundation

| Key | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| four_primary_colors_preserved | Preserve the four distinct primary colors | Preserved | `DESIGN.md`, `CollectColors.brandPrimaryHexes`, `four_primary_color_distinction_contract` |
| alignment_contract_written | Replace old "do not copy Revolut" direction with borrowed Revolut alignment contract | Complete | `DESIGN.md`, `docs/design/DESIGN_SYSTEM.md`, `docs/design/REVOLUT_BORROWED_ALIGNMENT_PLAN_2026-06-27.md` |
| intake_paths_created | Create repo-local intake paths for approved inputs | Complete | `assets/fonts/revolut/README.md`, `assets/brand/revolut_borrowed/README.md`, this register |
| runtime_switchpoints_created | Route current runtime brand fallbacks through borrowed Revolut switchpoints | Complete | `RevolutBorrowedAssets`, `CollectBrandMark`, `LaunchSplashScreen`, `revolut_borrowed_runtime_switchpoints` |
