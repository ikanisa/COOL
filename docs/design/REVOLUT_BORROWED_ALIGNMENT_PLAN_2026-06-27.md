# Revolut-Quality Alignment Plan

Date: 2026-06-29
Repo: `/Volumes/PRO-G40/COOL`
Scope: Flutter member app, Flutter Admin PWA, public web entry points, native platform surfaces, design docs, runtime assets, evidence scripts, and release gates.

## Goal

Move COOL from "Revolut-inspired" to **100 percent Revolut-quality alignment with Collect-owned runtime assets**.

The target is not copied branding. The target is full alignment of typography rhythm, logo treatment quality, color discipline, iconography consistency, navigation rhythm, surface styling, financial hierarchy, marketing visuals, launch/splash polish, and evidence gates against the supplied Revolut screenshot benchmark while shipping clean Collect-owned assets.

## Current Contradictions

- `lib/app/theme/collect_typography.dart` names `Hanken Grotesk`, `Inter`, and `Roboto`, but the app does not bundle font files and does not use the Revolut typeface.
- `docs/archive/2026-06/design/TYPOGRAPHY.md` is stale and names a different fallback set.
- `DESIGN.md`, `docs/design/DESIGN_SYSTEM.md`, `docs/archive/2026-06/design/UI_UX_REFERENCE_RESEARCH.md`, and older parity reports previously used a brand-separation direction that has now been superseded.
- Older wording in docs and scripts referred to a Collect runtime kit as a runtime input; the active decision is Collect-owned runtime assets with Revolut screenshots as the quality benchmark.
- Runtime assets under `assets/brand/` are Collect-owned and should remain the clean source unless a separately approved replacement kit is supplied.
- The existing visual parity evidence proves route coverage and quality improvements, but human visual and human listening signoff remain separate review activities.

## Runtime Inputs

Store or reference the active inputs before implementation:

- Collect-owned runtime logo, wordmark, app icon, launcher icon, splash, social preview, favicon, and product media assets.
- Provenance for every runtime asset source and destination path.
- Revolut screenshot benchmark for background, surface, semantic, dark/light mode, navigation, hierarchy, and component-state quality.
- Approved icon mapping, including where the current Material icon set remains the practical implementation choice.
- Approved product boundary for Collect-specific Rwanda/MoMo flows so missing Revolut-native products are replaced by Revolut-quality equivalents instead of generic placeholders.

If a required Collect asset is unavailable, mark it as a blocker in the evidence report. Do not use external screenshots or unapproved third-party brand material as shipped runtime assets.

## Implementation Workstreams

### 1. Typography

- Keep approved local font files under the dedicated runtime font path, `assets/fonts/collect/`.
- Register the font family in `pubspec.yaml`.
- Keep the current registered family as the primary family and remove misleading open-font documentation.
- Add a test or audit check that fails unless the runtime font family is registered or the missing font input is explicitly recorded in the blocker register.
- Verify Android, iOS, and web builds embed or load the font consistently.

### 2. Brand Assets

- Keep `CollectBrandMark` runtime output on the clean Collect-owned wordmark/lockup.
- Replace launcher icons, Android adaptive icon layers, iOS app icon, web favicon, manifest icons, splash assets, and share-preview assets only with clean Collect-owned assets or a separately approved replacement kit.
- Document every asset source, destination path, dimensions, and approval status.
- Add an audit check that fails unless documented Collect-owned runtime brand assets are installed.

### 3. Color And Token Migration

- Keep the Revolut-quality token map in `lib/app/theme/collect_colors.dart` or a dedicated token file.
- Preserve Collect's four primary colors exactly: `#8885F0`, `#3CD070`, `#D38B96`, and `#FF5E43`. They are the only distinct brand-color exception to the Revolut alignment target.
- Replace or confirm launch/splash background colors with a Revolut-like treatment that keeps the four-primary distinction intact.
- Keep semantic contrast checks and large-text checks as hard gates.

### 4. Component Alignment

- Rework top chrome, bottom navigation, action rows, cards, input fields, filters, chips, sheets, empty states, loading states, and payment status panels to match the Revolut-quality component model.
- Move component-level styling into shared primitives first, then update feature screens.
- Replace generic Material icons only where a documented approved equivalent exists.

### 5. Route-By-Route Screen Alignment

- Build a reference matrix for every Revolut screenshot and every Collect production route.
- Align Home, Groups, Group Detail, Payment, QR/Share, Profile, Settings, Notifications, Permissions, Offline/Sync, Legal, and Admin views to the closest approved Revolut pattern.
- Where Collect has Rwanda/MoMo-specific behavior, preserve the required behavior but make the visual treatment, hierarchy, terminology, and density match the Revolut-quality benchmark.

### 6. Admin PWA Alignment

- Apply the same Revolut token, typography, icon, and surface system to Admin.
- Keep Admin data privacy masking, evidence mode, and role/security behavior intact.
- Add desktop and mobile Admin screenshot contact sheets to the final evidence bundle.

### 7. Public Web Alignment

- Update `main_public.dart` routes and public landing/policy pages to use the same runtime typography, color system, Collect-owned assets, buttons, navigation, and footer discipline.
- Remove stale public-site language that says the site is intentionally not copied from Revolut.
- Keep external claims approval-gated before public release.

### 8. Evidence And Gates

- Update `scripts/collect_mobile_design_compliance_audit.sh` so it enforces Revolut-quality alignment and Collect-owned runtime assets.
- Add font registration, runtime asset, platform icon, and web manifest checks.
- Regenerate mobile route screenshots, Admin screenshots, public web screenshots, and contact sheets.
- Run visual comparison against the full Revolut reference set plus the clean Collect runtime asset kit.
- Keep privacy gates: screenshots must not expose raw SMS, OTPs, PINs, private phone numbers, provider tokens, or production customer data.

## Acceptance Criteria

The repo can claim 100 percent Revolut-quality alignment only when:

- Approved runtime fonts are bundled and used by member, admin, and public surfaces.
- Collect-owned brand assets are installed, documented, and used consistently while preserving the four required primary colors as the only distinct palette.
- Revolut color/component/navigation tokens drive all shared UI primitives.
- Every production route has fresh nonblank screenshot evidence.
- Mobile, Admin PWA, and public web contact sheets are reviewed against the approved Revolut reference set.
- The design compliance audit enforces the new Revolut-quality plus Collect-owned runtime asset contract.
- Any remaining Collect-specific product behavior is explicitly mapped to a Revolut-like visual pattern.
- Human visual signoff and accessibility signoff are recorded in the parity checklist.

## Execution Order

1. Install and document the clean Collect runtime brand kit.
2. Update typography and asset registration.
3. Migrate shared theme tokens and shared components.
4. Align route families in priority order: Home, Groups, Payments, QR/Share, Profile/Settings, Status/Permissions, Admin, Public Web.
5. Update evidence scripts and tests.
6. Regenerate route, Admin, and public contact sheets.
7. Complete human visual/accessibility signoff.
8. Publish the final parity evidence report.
