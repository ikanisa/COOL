# Collect Runtime Asset Intake

Date: 2026-06-29
Repo: `/Volumes/PRO-G40/COOL`

## Purpose

This is the intake map for Collect-owned runtime assets. It keeps the stable
asset switchpoints that were introduced during the Revolut-alignment work, but
the source assets are now Collect-owned generated/source variants rather than
external screenshots or an external brand kit.

## Preserved Distinction

The four primary colors remain fixed and must not be replaced:

- Periwinkle `#8885F0`
- Mint `#3CD070`
- Rose `#D38B96`
- Orange `#FF5E43`

These are the active Collect brand colors.

## Intake Paths

| Input | Destination | Runtime use |
| --- | --- | --- |
| Typography files | `assets/fonts/collect/` | Registered in `pubspec.yaml`, then used by `CollectTypography` |
| Collect logo and wordmark assets | `assets/brand/collect_runtime/logos/wordmark.png` | `CollectBrandMark`, headers, share cards, public web |
| Collect app icon and adaptive icon layers | `assets/brand/collect_runtime/app_icons/app_icon.png`, `assets/brand/collect_runtime/app_icons/collect-web-512.png` | Android, iOS, web manifest, favicon |
| Collect splash and launch artwork | `assets/brand/collect_runtime/splash/splash_mark.png`, `assets/brand/collect_runtime/splash/splash_background.png` | Android launch, iOS launch storyboard, web boot surface |
| Icon mapping | `assets/brand/collect_runtime/icons/` | `CollectIcons` and approved substitutes |
| Collect product/media imagery | `assets/brand/collect_runtime/media/share-preview.png`, `assets/brand/collect_runtime/media/` | Rich cards, Home, Groups, public web |
| Token guidance | `docs/design/collect_runtime_tokens/` | Theme, component, semantic, and contrast mapping |

## Intake Rules

- Do not put secrets, credentials, private correspondence, or unpublished commercial terms in runtime assets.
- Keep approval/license metadata in docs with sanitized names, timestamps, and source references.
- Every runtime asset must have a source path, destination path, dimensions, and approval status.
- Current installed inputs are routed through `CollectRuntimeAssets`; keep these
  paths stable unless the app registry is renamed in a dedicated refactor.
- Runtime images must be Collect-owned generated/source artwork. Do not use
  third-party screenshots as shipped runtime assets.
- Missing required inputs must be recorded in `docs/design/MOBI_REVOLUT_100_PERCENT_ALIGNMENT_MATRIX.md`.
