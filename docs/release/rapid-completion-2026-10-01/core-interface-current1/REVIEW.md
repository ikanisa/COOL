# Current affected core interface acceptance

**13 tests passed**, zero failures/errors/skips/unfinished:

- Seven selected shared cases: distinct group/hero headings at 320px and
  normal/enlarged text; whole quick-action words at 320px/390px; semantic
  bottom-navigation keyboard routing; Members search focus with 200% text
  and keyboard insets.
- One existing Admin header case: country/operator semantics and 48px operator
  targets at compact, tablet and desktop widths.
- Five existing keyboard cases: card/row focus, activation and visible contrast
  through the normal/dark/high-contrast themes and enlarged text.

The two changed views, `group_members_screen.dart` and
`collection_detail_screen.dart`, plus named shared header/runtime/pubspec,
font, fixture and test inputs match the current root and the Inter APFS clone.
They were unchanged through all checks. No source overlay or repeated analyzer
was needed because there was no actual root/export Dart drift. Locked package
bindings were reused; no Pub resolution was repeated.

The shared and keyboard cases explicitly load the actual bundled Inter bytes.
The existing Admin header harness checks semantics and target sizes; it does
not certify exact native font rendering or a Revolut comparator match.

This replaces dated currentness only for the affected core behaviors. It does
not rerun the complete 27-case shared or 120-case interface suite, close all
surface states, or assert physical-device/provider/native-visual acceptance.
No source, browser/native/static build, golden or SQL operation was performed.

[Exact current source bindings](current-source-export-bindings.json).
[Terminal scoped validation](validation.json).
