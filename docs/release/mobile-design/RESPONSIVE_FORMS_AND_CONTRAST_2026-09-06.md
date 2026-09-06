# Responsive forms and Rwanda hero contrast — 6 September 2026

Local corrections and verification for the ongoing Revolut design application. Collect keeps its own identity, route colour families, member data model, navigation and payment behavior.

## Changes

- `CollectFormViewport` retains the form subtree and focus while allowing content and the action dock to scroll together when a software keyboard leaves too little height. It is used by sign-in, profile editing and shared screens with bottom actions.
- The navigation rail scrolls within a short landscape viewport. Rwanda and diaspora profile editing no longer produce the observed rail overflow.
- Enlarged `CollectMobileInputField` labels wrap above the editable content. The native review exposed a truncated “Description, optional” label; it now remains complete at 200% text.
- The public hero scrim paints above both Rwanda photo layers and covers the text column. The Flutter public hero uses the matching stronger gradient. The selected Kigali portrait and other Rwanda assets are retained.

## Verified evidence

| Layer | Result | Evidence |
| --- | --- | --- |
| Full Flutter regression suite | 742 named tests passed in the final complete run | `.cache/revolut-design-20260906/full-tests-final.jsonl` |
| Full app responsive widget matrix | 56 route/variant cases, 24 keyboard layout simulations and 1 full-label regression; 185 PNGs | `test/features/mobile_responsive_matrix_test.dart`, `.cache/revolut-design-20260906/responsive-final/` |
| Android native fixture | 42 routes and 42 screenshots; dark, 200% text, high contrast, reduced motion; identical source fingerprints before and after | `.cache/revolut-design-20260906/exhaustive-android-responsive-final/summary.json` |
| Public website | 64 route/viewport and 16 share/viewport checks; 192 screenshots | `.cache/revolut-design-20260906/website-final/route_rendered_qa.json` |
| Photo-backed website text | 18 observations across 9 widths; minimum conservative contrast 6.01:1; rendered CSS matches source | `scripts/qa/public_photo_contrast_qa.mjs`, `.cache/revolut-design-20260906/website-photo-contrast-final/report.json` |
| Flat website text | 4,262 observations passed; the four hero observations deferred by the flat checker are covered by the photo checker | `.cache/revolut-design-20260906/website-flat-contrast.json` |
| Source checks | Analysis and design source hygiene passed; diff whitespace check passed | Retained local logs and `scripts/revolut_parity_source_hygiene_gate.sh` |

The photo check hides only glyph paint while preserving layout, decoded images and the actual crop and scrim. It measures the minimum contrast across every background pixel within the text line rectangles. These conservative rectangles include pixels outside the glyphs; the measurement is not a native Flutter or screen-reader test.

The widget keyboard captures reserve a black area for simulated keyboard insets. They verify retained field focus and reachable input/action text, not a real OS keyboard. All fixture records are synthetic. Permission status in the widget matrix is a declared denied fixture; the native run uses the installed permission plugin.

Only the public desktop golden changed in this pass. The previous and current images were inspected before replacing that baseline. The prior image is retained in `.cache/revolut-design-20260906/goldens-before/`; no other baseline was refreshed. Two existing regression helpers were adjusted to scroll their content lists after the rail and outer form viewport became scrollable. The final complete run passed after those corrections.

## Review and acceptance boundary

Open [the responsive review](http://collect.localhost:4191/responsive.html) or [the complete gallery](http://collect.localhost:4191/). The catalogue distinguishes current source-bound Android images, historical native images, widget simulations, browser captures and named test results.

`MOBILE-DESIGN-100` remains blocked. This pass does not close every required reference comparison, interaction/state assessment, actual OS keyboard or screen-reader check, current iOS rerun, or production artifact binding. No production release, deployment or 100% fidelity claim is made. Admin retains its prior evidence; no new Admin change or deployment was made in this pass. The developer-account UAT record, signed-in devices, existing user edits and production access controls were preserved.

Machine-readable verification: [responsive-contrast-verification-2026-09-06.json](responsive-contrast-verification-2026-09-06.json).
