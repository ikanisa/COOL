# Borrowed Revolut Asset Intake

Date: 2026-06-27
Repo: `/Volumes/PRO-G40/COOL`

## Purpose

This is the intake map for borrowed Revolut-like material. It prevents the repo from faking alignment with untracked substitutes by requiring every font, asset, icon, and token input to live in an expected path with provenance.

## Preserved Distinction

The four primary colors remain fixed and must not be replaced:

- Periwinkle `#8885F0`
- Mint `#3CD070`
- Rose `#D38B96`
- Orange `#FF5E43`

These are the only intentional visual distinction from the Revolut alignment target.

## Intake Paths

| Input | Destination | Runtime use |
| --- | --- | --- |
| Borrowed/Revolut-like font files | `assets/fonts/revolut/` | Registered in `pubspec.yaml`, then used by `CollectTypography` |
| Logo and wordmark assets | `assets/brand/revolut_borrowed/logos/wordmark.png` | `CollectBrandMark`, headers, share cards, public web |
| App icon and adaptive icon layers | `assets/brand/revolut_borrowed/app_icons/app_icon.png`, `assets/brand/revolut_borrowed/app_icons/web-512.png` | Android, iOS, web manifest, favicon |
| Splash and launch artwork | `assets/brand/revolut_borrowed/splash/splash_mark.png`, `assets/brand/revolut_borrowed/splash/splash_background.png` | Android launch, iOS launch storyboard, web boot surface |
| Icon set or mapping | `assets/brand/revolut_borrowed/icons/` | `CollectIcons` and approved substitutes |
| Product/media imagery | `assets/brand/revolut_borrowed/media/share-preview.png`, `assets/brand/revolut_borrowed/media/` | Rich cards, Home, Groups, public web |
| Token guidance | `docs/design/revolut_borrowed_tokens/` | Theme, component, semantic, and contrast mapping |

## Intake Rules

- Do not put secrets, credentials, private correspondence, or unpublished commercial terms in runtime assets.
- Keep approval/license metadata in docs with sanitized names, timestamps, and source references.
- Every runtime asset must have a source path, destination path, dimensions, and approval status.
- Current installed inputs are routed through `RevolutBorrowedAssets`; if a later exact kit is supplied, replace files in place without changing runtime paths.
- Missing required inputs must be recorded in `docs/design/REVOLUT_ALIGNMENT_BLOCKER_REGISTER_2026-06-27.md`.
- Do not claim 100 percent borrowed Revolut alignment while current device UAT or visual signoff remains open.
