**Findings**
- [P2] Visual implementation screenshot could not be captured
  Location: full app/theme validation.
  Evidence: source brand assets and generated native icon assets can be compared, but no rendered Flutter app screen was captured for home/create-group theme validation.
  Impact: icon fidelity can be reviewed from generated evidence, but Product Design QA cannot certify the rendered app UI yet.
  Fix: run the route render smoke or app screenshot capture after the Flutter test/build runner responds, then compare the rendered home/create-group states against the generated brand sheet.

**Open Questions**
- None for the icon source. Native launcher assets now use the provided four-color circular rule image, not the full wordmark.
- None for the wordmark source. In-app brand assets now include the provided periwinkle Collect wordmark image.

**Implementation Checklist**
- Keep official brand constants in lib/app/theme/collect_colors.dart.
- Keep accessible semantic aliases for buttons and status UI; do not use raw decorative colors for small white-text controls.
- Keep Android manifest on generated mipmap launcher assets.
- Keep generated Android/iOS launcher assets in sync with assets/brand/generated/collect_app_icon_rule.png.
- Keep in-app wordmark usage in sync with assets/brand/generated/collect_wordmark_periwinkle.png.
- Run focused Flutter tests and mobile route screenshot capture before marking visual QA passed.

**Follow-up Polish**
- Consider a tighter center-safe crop only if the four-color rule mark loses edge detail on-device.
- Add a real in-app brand animation only if a splash or brand moment is intentionally designed.

source visual truth path: /tmp/codex-remote-attachments/019ea2f3-08c6-7573-95ac-5d17dac77062/5876CCD8-FF59-419B-B9D1-A01212F48E8C/1-Photo-1.jpg; /tmp/codex-remote-attachments/019ea2f3-08c6-7573-95ac-5d17dac77062/A7B6D850-803D-4089-B90D-D1E510C63813/1-Photo-1.jpg; /Volumes/PRO-G40/COOL/assets/brand/generated/collect_logo_color_variants_sheet.png; /Volumes/PRO-G40/COOL/assets/brand/generated/collect_logo_color_cycle_icon.gif
implementation screenshot path: /Volumes/PRO-G40/COOL/.cache/design_qa/collect-app-icon-rule-comparison.png; /Volumes/PRO-G40/COOL/.cache/design_qa/collect-wordmark-rule-comparison.png
viewport: 1088x620 icon rule comparison; 1088x620 wordmark comparison; app screen viewport blocked
state: brand token integration, Android launcher icon, home/create-group brand accents
full-view comparison evidence: /Volumes/PRO-G40/COOL/.cache/design_qa/collect-app-icon-rule-comparison.png; /Volumes/PRO-G40/COOL/.cache/design_qa/collect-wordmark-rule-comparison.png
focused region comparison evidence: icon comparison confirms the generated native launcher source adheres to the provided four-color circular rule image; wordmark comparison confirms the repo wordmark asset adheres to the provided periwinkle Collect wordmark image; app UI focused regions remain blocked pending render capture
patches made since the previous QA pass: official tokens added, group/profile swatches updated, home hard-coded brand remnants tokenized, Android native color resources updated, Android mipmap launcher PNGs regenerated from the provided four-color rule image, iOS AppIcon PNGs regenerated from the provided four-color rule image, generated brand GIF/contact sheet added, provided periwinkle wordmark added as assets/brand/generated/collect_wordmark_periwinkle.png, focused token tests added, direct Dart formatting completed with no source changes
final result: blocked
