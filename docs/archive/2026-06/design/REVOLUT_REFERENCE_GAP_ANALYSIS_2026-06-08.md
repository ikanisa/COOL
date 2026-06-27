# Revolut Reference Comparative Gap Report - Collect Mobile

Date: 2026-06-11

## Scope And Design Basis

This report compares the Collect Flutter mobile design system against the supplied Revolut reference direction in `/Users/jeanbosco/Downloads/Revolut10`, the repo-owned prior ten-screen Revolut analysis, and the enforceable Collect redesign contract in `DESIGN.md`.

Direct inspection of `/Users/jeanbosco/Downloads/Revolut10` remains blocked from this checkout: shallow `stat`, one-level `find`, `rg --files`, and parent `Downloads` listing calls did not return and were killed. The code-owned remediation below therefore fixes the design-system contract and known implementation gaps without claiming a fresh pixel-by-pixel review of that blocked folder. No AAB rebuild was performed.

This older gap report is superseded by `docs/design/REVOLUT_BORROWED_ALIGNMENT_PLAN_2026-06-27.md` for brand direction. The current target is borrowed Revolut alignment using approved fonts, assets, colors, labels, tabs, component patterns, and route mappings where available.

## Enforceable Color Contract

Collect uses four main primary colors:

| Role | Hex | Usage |
| --- | --- | --- |
| Periwinkle | `#8885F0` | Brand lead, focus energy, gradient stop |
| Mint | `#3CD070` | Positive brand accent, success energy, gradient stop |
| Rose | `#D38B96` | Warm brand accent, emotional/supporting gradient stop |
| Orange | `#FF5E43` | Primary action, urgent/action accent, gradient stop |

Paper `#FAF8F5` is the canvas/foundation color, not a primary color. Ink `#252044` is the high-contrast support token for text and operational chrome, not a primary color.

Secondary colors stay tokenized for readability, glass, borders, focus, and semantic status containers. They are not alternate brand palettes.

## Current Compatibility Score

Current source-level compatibility score: `94/100`.

This is a source and design-contract score, not final screenshot parity. It improved because the palette contract is corrected to four primaries, the compliance gate enforces that contract, Home now uses shared top chrome, raw admin colors are tokenized, shared cards have blur, the bottom navigation has a stronger glass selected capsule, status panels render their trust copy, and the report no longer preserves contradictory palette language. It is not a defensible `100/100` until the blocked Revolut10 folder is readable and fresh route screenshots are manually compared.

## Gap Closure Matrix

| Area | Previous finding | Remediation status | Remaining risk |
| --- | --- | --- | --- |
| Reference access | `/Users/jeanbosco/Downloads/Revolut10` blocked filesystem inspection. | Not code-owned. Calls were stopped rather than allowed to hang. | Fresh pixel-level comparison still requires readable reference assets. |
| Color contract | Docs/tests/scripts drifted between four, five, and six-color language. | Fixed: `DESIGN.md`, `CollectColors`, tests, audit scripts, and design docs enforce four main primary colors. | Future docs must not re-add Paper or Ink as primaries. |
| Home top chrome | Home used custom brand/action header instead of shared Revolut-style chrome. | Fixed: Home now uses `CollectTopChrome` with avatar, search, notifications, and profile actions. | Fresh screenshots should verify spacing against reference. |
| Canvas/glass | Shared gradient and glass tokens existed but docs were contradictory. | Fixed at token and contract level; member routes still inherit gradient through shell/scaffold. | Some dense routes may still need visual tuning after screenshot review. |
| Bottom nav | Rounded glass nav existed but selected state needed refinement. | Fixed: selected capsule now uses tokenized gradient, stronger blur, and rounded glass treatment. | Subjective polish still benefits from screenshot review. |
| Cards | Glass opacity existed; raw admin colors could break token discipline. | Fixed: admin login colors are tokenized through `CollectColors`; shared cards now apply blur by emphasis level. | Full parity still requires visual review. |
| Lists/status screens | Secondary routes could read as thin panel stacks; shared status panels accepted but did not render the `message` copy. | Fixed: `MinimalStatePanel` now renders its message, preserving trust/legal/status context while keeping the compact hero structure. | Final density/polish still requires screenshot comparison. |
| Iconography | Some local Material icons remained in shared/admin controls. | Existing shared member chrome uses `CollectIcons`; admin-only login icons remain acceptable operational chrome. | Member-facing icon scan should remain part of future route review. |
| Validation | Old gate checked stale palette assumptions. | Fixed: `four_primary_color_distinction_contract` and `revolut_borrowed_alignment_contract` are the audit gates. | Full route smoke/manual comparison must run after reference access is restored. |

## Current Findings

1. **Four primary colors are now the only main primary palette.** Paper and Ink are deliberately support tokens.
2. **Home chrome is aligned to the shared fintech pattern.** The remaining brand mark is preserved as a visible product signal below the top chrome.
3. **Admin raw colors no longer violate the shared token discipline.** Admin stays operational, but it no longer introduces ungoverned color literals.
4. **Glass depth and bottom navigation have been improved at shared-component level.** This fixes the code-owned source gap without route-by-route churn.
5. **Reference asset access is the only unresolved blocker.** It is not safe to claim exact Revolut10 visual parity while that directory blocks basic filesystem inspection.
6. **Trust/legal/status screens now render their intended message copy.** Final 100/100 visual parity still needs screenshot comparison.

## Required Manual Follow-Up For 100/100 Claim

1. Make `/Users/jeanbosco/Downloads/Revolut10` readable or place the reference images in a readable evidence folder.
2. Capture current route screenshots at 390x844 and one larger viewport.
3. Compare Home, Groups, Settings, payment, privacy, SMS permission, offline, and legal screens against the reference patterns.
4. Tune bottom-nav capsule, glass blur, and dense status/legal layouts from screenshots.

## Validation Boundary

No AAB rebuild was run. This report covers source design-system alignment, documentation consistency, audit-gate corrections, and code-owned UI fixes only.
