# Collect Color Compliance Audit - 2026-06-08

## Status

This file records the color-system cleanup performed after the repo-wide audit.
The active design contract is now the four-primary-color Collect palette in
`DESIGN.md`, implemented through `CollectColors`. Paper `#FAF8F5` is the
canvas/foundation color, and Ink `#252044` is the high-contrast support token.

## Approved Primary Colors

| Role | Hex |
| --- | --- |
| Brand periwinkle | `#8885F0` |
| Brand dusty rose | `#D38B96` |
| Brand orange-red | `#FF5E43` |
| Brand mint green | `#3CD070` |

## Approved Canvas And Support Anchors

| Role | Hex |
| --- | --- |
| Paper canvas | `#FAF8F5` |
| Ink support | `#252044` |

## Cleanup Completed

- Superseded the older May 31 palette guidance so it no longer presents legacy
  reference colors as current implementation guidance.
- Aligned Android launch backgrounds with Paper canvas.
- Aligned iOS storyboard fallback backgrounds with the approved Paper launch
  surface.
- Removed separate iOS alternate-appearance launch assets.
- Added semantic color helpers for transparent surfaces, on-accent foregrounds,
  image overlays, camera scrims, export canvas/ink, selected chips, shadows, and
  granted/blocked statuses.
- Replaced duplicated group/profile palette option models with
  `CollectColors.brandPrimaryOptions`.
- Replaced raw member-facing overlay and selected-state colors with semantic
  `CollectColors` tokens.
- Converted QR/export rendering to Collect color aliases.
- Converted theme shadows and component button foregrounds to Collect tokens.

## Remaining Policy

Future color work should follow these rules:

- Feature, shared, core, and admin UI should not introduce literal color values.
- Screens should use `context.collectColors` or shared component APIs.
- The four brand primary colors belong in `CollectColors`, `DESIGN.md`, tests, and
  platform metadata only.
- Platform resources and web metadata must match the `DESIGN.md` palette.
- Camera and export surfaces may use special-case colors only through named
  tokens such as `cameraScrim`, `exportCanvas`, and `exportInk`.

## Enforcement

`scripts/collect_mobile_design_compliance_audit.sh --json` is the repo-owned
gate. It should be run after UI/theme changes and before release evidence is
refreshed.
