# Component and journey contracts

This closes the gap between a visual reference and an implementable interaction. It is a target-product specification method, not a recovered Revolut component API. Use it for shared components or significant flow work, in the target repository's existing format.

Every source-specific component name below is a reference label. Implement the target's own app/feature names and logo assets. Use [brand adaptation](brand-adaptation.md) for equivalent logo placement, sizing, responsive/theme and interaction behavior while retaining the complete source asset library as reference.

The target's existing workflows and domain contracts govern behavior. Financial, identity, permission and provider examples apply only when those actual target capabilities are in scope. Reusing a source screen's colours or layout never adds its banking fields, reviews, identity checks or business sequence. Use [screen typologies](screen-typologies.md) to choose presentation independently of business function.

## Record for each shared component

| Contract field | Required decision |
|---|---|
| Purpose and consumers | User task, surfaces and routes that use it; avoid a universal component for unrelated jobs |
| Source | Cohort, exact image/page, date, state and confidence; direct, pattern or adaptation |
| Anatomy and constraints | Named subparts, alignment, content order, min/max width, wrapping and overflow; distinguish fixed decoration from growing content |
| Tokens | Semantic roles, source values and units, theme variants, source provenance, provisional values and platform mapping |
| Inputs and outputs | Data and events, default selection, required fields, real state authority, navigation effect |
| State model | Applicable resting, pressed, hover, focus, selected, loading, disabled, invalid, empty, partial, stale and error states; inapplicable states explained |
| Interaction | Touch/keyboard/screen-reader behavior, dismissal, focus, scrolling, shortcuts, destructive consequences |
| Content | Visible and accessible names, help, error cause/recovery, truncation policy, number/date/currency formatting |
| Adaptation | Small/large viewport, enlarged text, safe areas, keyboard, orientation, reduced motion and theme transitions |
| Evidence | Target implementation location/build, source/target screenshots and actual runtime tests; unresolved differences |

Keep source primitives separate from semantic roles and component aliases. For example, `foreground.secondary` describes a role, not a proven native hex. Resolve the actual value from the chosen cohort or mark the target value provisional. Record font file and loaded face/weight/metrics; CSS family declarations alone do not prove the intended face rendered. Avoid arbitrary global radii or spacing derived from a single screen. Optional typed token interchange is described in [quality-standard.md](quality-standard.md), B13.

## Contracts most likely to fail when copied from screenshots

| Component | Source anchor | Target behavior and state contract | Evidence still needed |
|---|---|---|---|
| Bank recipient form | LIVE-053/054/056 | Country and currency remain independent; Individual/Business changes personal-name versus company fields. Preserve relevant inputs and explicitly handle incompatible values. Retain accessible field names after entry. Validate near fields and focus/announce errors. Never save a recipient from navigation alone. | Filled, invalid, corrected, loading, duplicate-recipient and completed target states; current captures are blank forms |
| Card recipient form | LIVE-057/058; prefer LIVE-058's non-personal blank state | Keep My card/Someone else's selection, card number and the relevant name fields. Do not import bank-specific country/currency or Individual/Business controls from the adjacent contract. Keep the primary action above the keypad, labels meaningful after entry, and errors recoverable. | Filled, invalid, loading, keyboard/accessibility and completed target states; card-recipient capture does not establish bank-form or transfer-outcome behavior |
| Amount entry | LIVE-060/062/063 | Distinguish send from request, source account from denomination, and schedule from immediate action. Localised display must preserve exact domain amount/precision. Review material recipient/source/fees/rate/outcome before commitment when applicable. | Non-zero, insufficient balance, limits, quote expiry, review and outcome; current source evidence is partial |
| Primary action | Selected form/primer, including LIVE-023/058 | One stable geometry across enabled/loading/disabled; activation announces progress and prevents unintended repeat submission. Explain a non-obvious disabled reason through accessible help. Error recovery preserves appropriate input. | Real loading/error timing and assistive announcement; disabled grey text in a screenshot is not automatically a contrast violation |
| Picker or modal | LIVE-032 versus LIVE-062; historical onboarding confirmation | Correct presentation for that route. Specify initial focus, keyboard traversal, current selection, cancel/commit, back/dismiss, focus return and scroll position. Web modal background is inert. | Real interaction and full long-content behavior; one raised-looking frame does not establish modality |
| Theme editor | LIVE-009/011 | Keep draft selection separate from saved preference. Cancel restores the saved value; Apply commits only changed settings. System follows OS changes. Update status/navigation bars and illustrations together. | Only Dark selected preview observed; light/system runtime and Apply/Cancel persistence require target tests |
| Permission primer | LIVE-023 | Explain the requested capability before the OS prompt. Close/cancel preserves the task. Allowed, denied and restricted states have suitable next actions; text input remains available where the product supports it. Re-prompt behavior follows platform rules. | OS prompt, denial, later recovery and resumed composer were not captured |
| Security action | LIVE-013 | Preserve urgent-action hierarchy, clear labels and usable hit regions. State which routes merely navigate and which can change account/card state. Help remains reachable during an incident. | Destination flows, low-vision use, gesture/keyboard targets and task completion |
| Navigation and rows | LIVE-051, settings and original overview cohort | Stable selected destination; preserve branch/scroll context. Row whole-hit-region and accessory actions must not conflict. Expose meaningful names/status. Clear the final row and action above floating navigation. | Long lists, back restoration, focus and text-scale variants |
| Operational table | Business workflow documentation; POS-002 is a separate static light Orders comparator | Identify account/workspace, column semantics, sort/filter/page state and selection scope. Distinguish current page from all results. Preserve detail-return context. Support partial failures and conflicting edits. | Full current authenticated desktop comparator and target operational tests; do not invent official table geometry |
| Website hero and menu | Current UK homepage/styles | Preserve real typography/crop/art direction at matching width. Menu works with keyboard and touch; headings and primary CTA lead to real content. Hero loading reserves geometry. Motion has applicable accessible alternatives. | Full conversion path, all breakpoints, loaded fonts, menu semantics and field performance |

## Financial journey state model

Use the product's actual supported states. The following is an implementation adaptation; source captures do not prove Revolut's internal machine.

| Transition | UI obligation | Required target evidence |
|---|---|---|
| Draft → validation | Show specific correctable fields without losing unaffected data | Invalid/valid transition, focus and announcement |
| Valid draft → review | Show destination, source, amount, currency, material fees/rate and timing | Confirm displayed values match the domain request |
| Review → authorising/submitting | Make progress explicit; prevent accidental repeated activation | Rapid double activation and latency test with synthetic/staging data |
| Submitting → confirmed/pending/failed | Render the provider/backend result truthfully | Controlled responses for each state |
| Submitting → timeout/unknown | Explain uncertainty and provide status checking; do not assume failure and blindly resend | Timeout after server acceptance; status reconciliation without a second financial instruction |
| Pending → updated outcome | Preserve transaction identity and update relevant lists/details together | Resume/reload/reconnect with authoritative status |
| Quote expires or recipient/source changes | Revalidate affected facts and renew review where required | Old quote, source/currency switch and changed amount |
| Authentication expires | Recover an appropriate draft after reauthentication; recheck sensitive facts | Expiry at draft/review/submission without false completion |

Testing these behaviors belongs in an authorised target test environment. Reviewing this skill does not authorise transactions in a personal reference account.

## Motion and responsive decisions

For each meaningful transition, specify trigger, start/end state, interrupt/cancel behavior, duration/easing source or labelled provisional target choice, reduced-motion equivalent and focus continuity. Screenshots cannot establish timing or haptics. Historical CSS motion tokens do not establish the current native animation.

Specify layout rules in terms of content and available space before choosing breakpoints. For a recipient form, field help and the primary action must remain reachable with keyboard and enlarged text. For an operator table, document which columns remain essential, whether a horizontal data region is justified, and how its headers and row actions remain usable. For a marketing hero, select source-appropriate phone/desktop imagery and wrapping rather than scaling the entire desktop composition.

Apply the relevant [operational tests](operational-checklist.md) and record remaining unknowns in the [comparison record](comparison-template.md).

## Corrections demonstrated in the isolated skill trial

A dark sheet body is insufficient when its library header remains white. Inspect the whole portalled surface and all descendants against the matching sheet source. Keep title, description, selector, footer, scrim and focus states coherent. Parent screen variables may not reach portals.

Use stable input labels plus `aria-describedby` for validation. In the trial an error inside a label changed the field's accessible name; explicit naming corrected it. Preserve entered values when a selector opens/closes and show the selected item when the user returns. Radio groups need coherent tab stops and arrow selection; dialog Escape must clear application state as well as close the native dialog.

A rendered count must derive from the target's actual data or an explicitly named fixture. A visual reference never justifies a fictitious balance or task count. Each visible action must retain its target meaning; an Add command cannot simply reuse an unrelated details action.

Validate the screenshot artifact itself. The local tools returned blank/wrongly framed clips even when DOM state was correct; full-frame captures with inspected content replaced them. Use settled states, named viewport/phone bounds and source plus implementation in the same review. See [trial record](reconciliation-and-skill-trial.md).

The [later narrow-layout/table check](state-lifecycle-validation.md#later-continuation-320px-reflow-and-table-access) found clipped tab pills even though document scroll width passed. Compare controls with their actual clipping ancestors. For a table that needs horizontal scrolling, expose a named focusable region, meaningful column headers and the current sort state; verify keyboard scrolling and actual row order. This improves target access while preserving the source-derived appearance. It is not evidence of spoken screen-reader success.

The [quota/rotor follow-up](remaining-validation.md) demonstrates a further modal rule: a recovery notice outside an open native dialog may be visible behind its scrim but absent from its accessible context. Render field-relevant warnings inside the dialog, associate them through `aria-describedby`, and verify their clearance after the underlying write succeeds. Keep saved-draft claims conditional on observed storage outcomes.

The [committed-draft tests](draft-persistence-validation.md) require truthful saving, committed, failed and conflicting states. Do not announce durability on request success alone. Defer explicit refresh while writing; prevent stale windows from erasing newer work; preserve user text on rejected writes. The tested gallery database is an example, not a source-native implementation or universal product requirement.
