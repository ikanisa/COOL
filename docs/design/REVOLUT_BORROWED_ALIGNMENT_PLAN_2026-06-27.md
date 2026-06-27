# Borrowed Revolut Alignment Plan

Date: 2026-06-27
Repo: `/Volumes/PRO-G40/COOL`
Scope: Flutter member app, Flutter Admin PWA, public web entry points, native platform surfaces, design docs, runtime assets, evidence scripts, and release gates.

## Goal

Move COOL from "Revolut-inspired" to **100 percent borrowed Revolut alignment**.

The target is not just similar polish. The target is full alignment of typography, logo treatment, color tokens, iconography, navigation rhythm, surface styling, financial hierarchy, marketing visuals, launch/splash treatment, and evidence gates against the approved borrowed Revolut source material.

## Current Contradictions

- `lib/app/theme/collect_typography.dart` names `Hanken Grotesk`, `Inter`, and `Roboto`, but the app does not bundle font files and does not use the Revolut typeface.
- `docs/archive/2026-06/design/TYPOGRAPHY.md` is stale and names a different fallback set.
- `DESIGN.md`, `docs/design/DESIGN_SYSTEM.md`, `docs/archive/2026-06/design/UI_UX_REFERENCE_RESEARCH.md`, and older parity reports previously used a brand-separation direction that has now been superseded.
- `scripts/collect_mobile_design_compliance_audit.sh` still enforces the old "Collect-owned" separation contract.
- Runtime assets under `assets/brand/` are Collect-generated assets, not a borrowed Revolut brand kit.
- The existing visual parity evidence proves route coverage and quality improvements, but not 100 percent brand alignment.

## Required Inputs

Store or reference the borrowed Revolut inputs before implementation:

- Revolut font files and license metadata.
- Revolut logo, wordmark, app icon, launcher icon, splash, social preview, and favicon assets.
- Revolut background, surface, semantic, dark/light mode, and contrast rules that preserve Collect's four required primary colors.
- Revolut icon set or approved icon mapping.
- Revolut navigation model, tab labels, card ordering, common account/payment terminology, and component-state examples.
- Approved product boundary for Collect-specific Rwanda/MoMo flows so missing Revolut-native products are replaced by Revolut-like equivalents instead of generic placeholders.

If an input is unavailable, mark it as a blocker in the evidence report. Do not hide missing borrowed Revolut material behind local substitutes.

## Implementation Workstreams

### 1. Typography

- Add approved Revolut font files under a dedicated runtime font path, for example `assets/fonts/revolut/`.
- Register the font family in `pubspec.yaml`.
- Replace `CollectTypography._family` with the approved Revolut family as the primary family and remove misleading open-font documentation.
- Add a test or audit check that fails unless the Revolut font family is registered or the missing font input is explicitly recorded in the blocker register.
- Verify Android, iOS, and web builds embed or load the font consistently.

### 2. Brand Assets

- Replace `CollectBrandMark` runtime output with the approved Revolut-aligned wordmark/lockup.
- Replace launcher icons, Android adaptive icon layers, iOS app icon, web favicon, manifest icons, splash assets, and share-preview assets.
- Document every asset source, destination path, dimensions, and approval status.
- Add an audit check that fails unless approved Revolut brand assets are installed or the missing asset input is explicitly recorded in the blocker register.

### 3. Color And Token Migration

- Create a Revolut token map in `lib/app/theme/collect_colors.dart` or a new dedicated token file.
- Preserve Collect's four primary colors exactly: `#8885F0`, `#3CD070`, `#D38B96`, and `#FF5E43`. They are the only distinct brand-color exception to the Revolut alignment target.
- Replace or confirm launch/splash background colors with a Revolut-like treatment that keeps the four-primary distinction intact.
- Keep semantic contrast checks and large-text checks as hard gates.

### 4. Component Alignment

- Rework top chrome, bottom navigation, action rows, cards, input fields, filters, chips, sheets, empty states, loading states, and payment status panels to match the borrowed Revolut component model.
- Move component-level styling into shared primitives first, then update feature screens.
- Replace generic Material icons with approved Revolut icons or a documented approved equivalent.

### 5. Route-By-Route Screen Alignment

- Build a reference matrix for every Revolut screenshot and every Collect production route.
- Align Home, Groups, Group Detail, Payment, QR/Share, Profile, Settings, Notifications, Permissions, Offline/Sync, Legal, and Admin views to the closest approved Revolut pattern.
- Where Collect has Rwanda/MoMo-specific behavior, preserve the required behavior but make the visual treatment, hierarchy, terminology, and density match the borrowed Revolut source.

### 6. Admin PWA Alignment

- Apply the same Revolut token, typography, icon, and surface system to Admin.
- Keep Admin data privacy masking, evidence mode, and role/security behavior intact.
- Add desktop and mobile Admin screenshot contact sheets to the final evidence bundle.

### 7. Public Web Alignment

- Update `main_public.dart` routes and public landing/policy pages to use the same borrowed Revolut typography, color system, assets, buttons, navigation, and footer discipline.
- Remove stale public-site language that says the site is intentionally not copied from Revolut.
- Keep external claims approval-gated before public release.

### 8. Evidence And Gates

- Update `scripts/collect_mobile_design_compliance_audit.sh` so it enforces borrowed Revolut alignment, not Collect-owned separation.
- Add font registration, runtime asset, platform icon, and web manifest checks.
- Regenerate mobile route screenshots, Admin screenshots, public web screenshots, and contact sheets.
- Run visual comparison against the full Revolut reference set plus any new approved borrowed Revolut assets.
- Keep privacy gates: screenshots must not expose raw SMS, OTPs, PINs, private phone numbers, provider tokens, or production customer data.

## Acceptance Criteria

The repo can claim 100 percent borrowed Revolut alignment only when:

- Approved Revolut fonts are bundled and used by member, admin, and public surfaces.
- Approved Revolut brand assets replace legacy Collect-generated runtime assets while preserving the four required primary colors as the only distinct palette.
- Revolut color/component/navigation tokens drive all shared UI primitives.
- Every production route has fresh nonblank screenshot evidence.
- Mobile, Admin PWA, and public web contact sheets are reviewed against the approved Revolut reference set.
- The design compliance audit enforces the new borrowed Revolut alignment contract.
- Any remaining Collect-specific product behavior is explicitly mapped to a Revolut-like visual pattern.
- Human visual signoff and accessibility signoff are recorded in the parity checklist.

## Execution Order

1. Install and document the borrowed Revolut brand kit.
2. Update typography and asset registration.
3. Migrate shared theme tokens and shared components.
4. Align route families in priority order: Home, Groups, Payments, QR/Share, Profile/Settings, Status/Permissions, Admin, Public Web.
5. Update evidence scripts and tests.
6. Regenerate route, Admin, and public contact sheets.
7. Complete human visual/accessibility signoff.
8. Publish the final parity evidence report.
