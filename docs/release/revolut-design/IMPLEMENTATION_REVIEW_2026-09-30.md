# Collect design implementation — updated 1 October 2026

The remaining design fixes are implemented across the member app, Admin and
public website. The owner-selected
[revolut-design skill](</Volumes/PRO-G40/Application Data/Codex/Codex-Home/skills/revolut-design/SKILL.md>)
is the sole design authority. Shared runtime tokens and components adapt that
skill while preserving Collect's identity, Rwanda workflows and access controls.

## What changed

- Marketing now uses the complete owner-provided Aeonik Pro Regular and Medium
  faces. Native and operator interfaces retain the selected Inter family;
  whole RWF values use tabular Inter. The compiled font files are hash checked.
- Native controls, cards, focus, disabled states and responsive chrome consume
  the selected shared adapters. Hero actions, ledger labels and management
  sheets retain complete text and reachable actions at enlarged sizes.
- The final full-screen review found three further mobile issues. Confirmation
  labels now remain inside their pill, photo-filter labels clear preceding
  controls, and Security uses the selected teal dotted-wave header. Causal
  regressions failed before the fixes and pass afterward.
- Admin records keep full titles, statuses and values, align monetary amounts,
  and reflow at narrow widths or enlarged text. Disabled FilledButton labels
  retain readable contrast. The current matrix includes all 28 registered routes.
- Website minification preserves descendant selectors and calculation spacing.
  Editorial labels and links occupy their intended rows; legal headings keep
  their spacing; supported-group cards have desktop insets. Legal pages show
  readable headings, the real app/support deletion path, working existing links,
  authored field definitions and each date once. Authored legal YAML is unchanged.
- Current member previews were rebuilt, separately inspected and published to
  the local website media packet. The static website was rebuilt from those
  current inputs.

## Current verification

| Surface | Current evidence | Result |
| --- | --- | --- |
| Member routes and states | 43 route cases + 56 state cases in iOS dark, Android dark and enlarged light iOS; 297 executions, 467 renders | Pass |
| Independent mobile review | All 297 main images; all 24 changed captures inspected, exact hashes reused for unchanged originals, enlarged helpers reviewed | Three findings closed; no further material findings |
| Native iOS capture | Seven actual OS captures; 465 current compiler/native inputs; all 204 installed bundle files equal the retained build | Pass |
| Admin | 28 routes × four viewports; 112 actual browser captures, independently reviewed; 321 compiled inputs current | Pass |
| Public website | 60 route/viewport cases + 16 share cases; 181 retained screenshots, with six long full-page outputs superseded by 175 original viewport segments | Pass |
| Website quality | 55 checks, including current source/media, exact product-copy contract and supported destinations | Pass |
| Website contrast | 3,422 flat-background text samples and 84 photography regions; rendered photography CSS equals its prepared source | Pass |

Native evidence is an iPhone 14 Simulator iOS debug build. The mobile matrix
uses actual widget routes and fixture states at 390 × 844, with real fonts;
its enlarged variant uses 3.2× text, high contrast and reduced motion. Admin
and static website evidence use the actual browser builds. These evidence
types are explicitly identified in their receipts rather than assigned a
fidelity percentage.

Long Privacy and Terms pages exceeded Chrome's full-page capture limit. The
capture runner now records overlapping original viewport segments and exact
scroll positions. All six affected outputs have current replacement evidence,
bound to the same unchanged 55-file build and passing route/contrast receipts.
No composite or edited screenshot substitutes for an original capture.

The [current evidence packet](verification/current-20261001/) includes source
bindings, causal regression logs, independent review records, native installed
readback, browser results and contrast checks. The
[route inventory](route-inventory.json) records 37 member patterns, 28 Admin
patterns, nine public Flutter fallback routes, 18 generated static HTML routes
and two static redirect patterns.

The legal rendering update has an explicit
[15-route text comparison](verification/current-legal-presentation-20261001/content-comparison.json).
Only privacy, terms, account deletion and data deletion changed visible copy.
The original historical content baseline and comparison retain their original
hashes. The content contract records rendering evidence and preserves its
existing legal/publication fields.

## Corrected earlier capture diagnosis

The previously reported three native capture defects were image-viewer
artifacts. Direct decoding and OCR of the original pixels confirm all four
navigation labels and the complete Terms opening. An unnecessary clipping
probe was reverted. The final capture runner settles rendering, binds an
immutable source export, keeps the installed app for readback and restores
the disposable simulator to Shutdown.

## Sole-authority cleanup

The [cleanup record](reference-cleanup.json) lists ten deleted competing files:
obsolete Admin/monochrome guidance, ignored export copies, generated concepts
and comparison mockups. Conflicting guidance was removed from retained reports.
Collect logos, artwork, requirements and regression captures remain product
evidence. No competing design authority was restored.

`make revolut-design-authority` verifies the selected skill/rule binding and
reference hygiene. The [verification inventory](verification-log-inventory.json)
distinguishes current receipts from retained historical attempts.
