# Revolut design reference — mobile, web and PWA

**Latest Android continuation:** [Installed recovery, TalkBack output and retry correction](android-installed-reader-validation.md) adds named real speech-engine completions, a standalone Home shortcut, offline/restart recovery and the corrected unchanged-input retry. Source-native Light and authenticated desktop remain unverified; exact builds and remaining platform/reader limits are explicit.

**Earlier 6 September platform continuation:** [Installed iOS and mixed-version recovery](platform-and-update-validation.md) verifies the current storage-enabled iOS simulator task and eight same-schema update/rollback/migration checks. Source-native, authenticated desktop, spoken-output and broader platform boundaries remain explicit.

**Consolidated 5 September 2026 · Owner: Jean Bosco · Design target: faithful Revolut execution**

This is the working design contract for applying the selected Revolut visual typologies and colours to the owner's mobile apps, websites and PWAs. Preserve **each app's own name, logo, screens, navigation, workflows, task sequences, business logic and content**. Collect keeps Home, Groups and its existing operations; **Collect Home uses the blue Home treatment**. The apps do not need to perform the same functions or follow the same business flows as Revolut. Source-specific names/marks are evidence, not target branding. This clarified scope supersedes earlier partnership/lockup or business-flow-equivalence language.

Keep the complete Revolut reference asset library, including logos. Use its evidenced placement, sizing, responsive behavior, theme variants and interaction as a model for the target's own logo assets. Never replace the target's identity with the source mark. See [own-app identity and logo behavior](brand-adaptation.md).

The [screen typology and colour contract](screen-typologies.md) preserves blue Home, teal Invest, purple Payments, muted blue-violet Crypto, vivid violet/blue rewards and blue-indigo passcode as distinct source visual families. Map these onto actual target screens independently of their business purpose. Keep neutral tasks, overlays, scroll-state darkening and semantic error colours where the source shows them. Do not flatten this into one black/white or logo-coloured theme.

**The full applicable Revolut colour system is required.** Named screen colours and the Collect example do not cap its scope. Cover the matching gradients, tinted and neutral surfaces, typography/icon colours, controls, navigation, overlays, selection/focus, loading/disabled and semantic outcome states across mobile, web apps, websites and PWAs. Preserve source theme/platform context and research missing roles; this requirement is not a claim that every Revolut variant has already been captured.

The [colour-role evidence register](colour-role-evidence.md) makes that remit traceable: source/state support, unresolved roles and measured background observations with source hashes and embedded-colour-profile handling. Screenshot samples are rendered evidence; they are not exact native token exports or a fixed palette limit.

The [focused public-web/theme follow-up](state-theme-desktop-followup.md) adds current website hover/focus/selection, signed-out SSO form styling and 88 resolved web colour variables, plus five official static POS desktop references. Treat resolved web variables, depicted POS colours, native mode availability and actual native theme appearance as distinct kinds of evidence.

The user illustrates this with **Collect: blue Home, teal Groups, purple Activity, bright violet/blue Profile and blue-indigo WhatsApp login**. Collect is a reference example for the skill; no changes to Collect are requested by this clarification. In a separately requested implementation, preserve the target's actual name, logo artwork, feature names, navigation, workflows, content and logic; completely replace previous hardcoded/logo-derived UI colours with the selected reference palette. This applies to UI surrounding a logo as well as ordinary components. See the colour migration procedure in the screen typology contract.


**Latest reconciliation and trial:** all 30 supplied screenshots are accounted for, with 29 distinct comparators mapped into the 276-family / 1,122-state matrix. Twelve further native captures confirm main-tab colours, black Profile/utility surfaces, a separate authentication variation and visible switch treatments; five are partial frames. The colour evidence register now contains 35 review roles. [Read the findings and implementation lessons](reconciliation-and-skill-trial.md). Full source coverage and exact native tokens remain unverified; the isolated Fieldwork gallery tests selected application patterns without changing Collect or another existing app.

**Latest narrow-layout correction:** [320px reflow and table checks](state-lifecycle-validation.md#later-continuation-320px-reflow-and-table-access) fixed clipped website tabs and added named keyboard scrolling, column scopes and current sort state to the isolated gallery. This earlier pass extended implementation evidence; the later spoken-task results below supersede its screen-reader gap.

**Earlier state/lifecycle validation:** [6 September draft and quota results](draft-persistence-validation.md) fixes reproduced immediate-stop draft loss in the tested Android browser scope: committed status is shown after an IndexedDB transaction completes; 5/5 acknowledged drafts recovered. Pending writes defer updates, stale windows cannot overwrite newer drafts, and browser quota rejection/recovery is verified. Those results retain their original builds. Subsequent installed iOS tests cover the acknowledged storage implementation; the latest Android continuation covers the corrected retry build. The retry build still needs an iOS regression retest, and physical-device coverage remains open. Source-native Light and authenticated desktop remain unverified. See the [hashed ledger](state-lifecycle-validation.json).

**6 September source/Mac continuation:** [Three official visual references and current installed-Mac recovery](source-and-mac-validation.md) add contextual chart/processing colours and verify the acknowledged draft across ordinary app quit, origin-unavailable reload and local completion. These results do not close source-native, authenticated desktop or new spoken-output gaps.

## 1. Choose the right Revolut surface

**Latest public desktop supplement:** [six inspected historical previews](public-desktop-supplement.md) add light Passkeys/Privacy settings, login, missing-page and marketing compositions. The publisher's April 2025 cohort date controls their age, not its 2026 page title. Saved browser previews are scaled references; exact tokens, current native Light and authenticated desktop runtime remain unverified. Their separate ledger does not inflate the 923-record original inventory or mobile coverage.

Revolut has several visual systems serving different jobs. Select the relevant one before choosing colours or layouts.

| Surface | Reference | Visual structure |
|---|---|---|
| Consumer mobile overview | September 2026 live iOS Dark · Glow captures; original 1170×2532 captures and July iOS screens as separate cohorts | Compact avatar/search/action chrome; central primary value or activation proposition; short circular actions; wide tonal content; floating navigation |
| Consumer task/detail | September live settings, card settings and empty recipient/amount forms; July documents, converter, search, help and transaction captures as a separate cohort | Quiet canvas, clear heading, grouped rows, focused action, appropriate sheet or pushed screen |
| Mobile onboarding | 24 locally supplied Mobbin images | Direct title/input composition; distinct country picker, confirmation, OTP and recovery; blue/purple-to-black backdrop in this cohort |
| Public consumer website | UK homepage observed 5 September 2026 | Large photographic hero, editorial typography, short copy, rounded CTAs, staged sections, responsive menu |
| Business application | Official Business 5 text/illustrations, Business homepage depictions and 2025 AU admin guide | Account/widget hierarchy and review components; bulk work documented. Full desktop table geometry remains unverified |
| Consumer web application | Current signed-out SSO, official help and historical light Passkeys/Privacy previews; no complete current authenticated desktop comparator | Narrow settings columns and grouped utility surfaces in the historical cohort; documented web scope is narrower than mobile |
| PWA | Matching consumer/Business reference plus platform behavior | Selected product language with installed shell, browser history, safe areas, offline and update behavior |

Sources: [asset catalog](asset-catalog.md), [public source ledger](sources.md).

For current mobile work, start with the [native capture atlas](current-native-atlas.md) and [critical findings](native-design-findings.md). The broader [mobile inventory](mobile-screen-coverage.md) separates observed native compositions, historical originals, current store depictions and features without a direct visual. It enumerates screen/flow families and review states, not Revolut's internal route count. Recent AIR, mobile-plan, Private Markets, security and rewards research is in the [September source ledger](mobile-sources-20260905.md).

## 2. Source precedence

Apply the user's current direction, then the most specific applicable evidence: supplied current partner kit; current state-matched product captures/computed styles; official surface-specific guidance; dated official screenshots; versioned public implementation. Internal comparison reports provide context, not authority over the visible source. Brand colours and product semantic colours are distinct.

Use four labels: **official specification**, **observed**, **inferred/adapted**, and **unverified**. Record source version/date, platform, region, theme and viewport. Unknown fields remain unknown.

The archives contain contradictions: August Collect cleanup removed floating chrome; September instructions reinstated it on overview routes. MOBI uses its own four-colour palette. DineIn prescribes Sora/DM Sans and heavy typography. Those are product decisions, not universal Revolut specifications. The selected actual Revolut source controls this reference. [Conflict resolutions](research-gaps.md).

## 3. Mobile composition

Design the first viewport around one recognisable value or task. On an overview, put the balance/object and account selector above quick actions. Keep command chrome compact. Use short labels, legible leading icons and a clear trailing numeric edge. Group secondary content below the principal hierarchy. Avoid unnecessary cards around ordinary headings, forms and list sections.

The original overview cohort has coloured upper backgrounds fading toward near-black: blue Home, teal Invest, purple payment/discovery, and theme variations. July task captures include neutral black pages and raised dark overlays. Neither “every screen needs a gradient” nor “Revolut never uses gradients” matches the evidence.

The captured bottom navigation is a floating dark capsule. The five source destinations are Home, Invest, Payments, Crypto and RevPoints. They identify the source only: use the target's real destinations and existing feature names in the chosen shell. Replace branded source names such as RevPoints with the target's own terminology for an existing equivalent capability; do not invent missing products. Preserve selection, navigation depth, content clearance and platform back behavior.

The current appearance setting explicitly reads **Dark · Glow**. Live Invest is an activation proposition, Crypto shows an assessment-required card, and RevPoints shows an earning activation proposition above discovery shortcuts. AIR's empty conversation is bottom-oriented, with suggested prompts and a pill composer. The live Security hub has a dotted-wave header and two urgent actions, while store promotional panels show a different three-action arrangement. These are state/cohort differences to preserve, not inconsistencies to average. See [native findings](native-design-findings.md).

Distinguish a picker sheet, anchored menu, centred confirmation and full-page task. The onboarding phone confirmation is a centred rounded modal; the invalid-code image is a low-screen error surface. Inspect the chosen source before prescribing a presentation. [Detailed mobile patterns](mobile-patterns.md).

## 4. Typography

**1 October 2026 Aeonik integration:** the supplied Downloads archives contain **Aeonik TRIAL v2.000**, with Light 300, Regular 400 and Bold 700 plus italics. The [typography review and role adapter](typography.md) retains licensed **Aeonik Pro 500** as the desired marketing match and labels the local 400 preview as an approximation. Product Inter roles remain intact; whole currency/table values use Inter with verified tabular figures. Trial fonts stay in private local evaluation and are excluded from portable/release assets. The [machine-readable adapter](typography-adapter.json) records available weights, character coverage and source/adaptation boundaries.

The historical public UI Kit names **Inter** for product UI and **Aeonik Pro** for marketing. The live UK homepage identifies **Aeonik Pro, weight 500** for its heading and CTA. This differs from the historical marketing implementation's uppercase, weight-900 display styles. Screenshots alone do not establish the native font family.

At 390×844 CSS pixels, the live mobile website measured **48px heading / 48px line-height**, normal tracking, a 335px heading box and 20px left inset. At 1267×841, the desktop heading measured approximately **84.42px / 84.42px**, −2.08px tracking and a 1000px box. Its CTA measured 16px/22px, weight 500, 42px height, 10px 24px padding and a 9999px radius. These describe that rendered page, not universal app tokens. [Measurements and token sources](tokens.md).

Use the chosen original's logical viewport when measuring mobile. Do not treat 1170 image pixels as 1170 dp. The original cohort is consistent with 390×844 at 3×, but its files do not establish device/DPR metadata; that conversion remains an assumption. Exclude desktop mirroring chrome from the comparison coordinate model while retaining originals intact.

The current Mirroring images are 406×890, with the phone rectangle approximately x8..398, y38..882. This provides a raster comparison coordinate model only. Approximate Home measurements and their limitations are recorded in [native findings](native-design-findings.md). The screenshot-triggered bug-report banner is a capture artifact and must be excluded from normal-screen comparisons.

Preserve glyph shapes, numeric alignment, line wraps and hierarchy. Do not maximise font weight everywhere, shrink labels to fit, or clip enlarged text.

## 5. Colour, surfaces and artwork

Define semantic roles for foreground, secondary text, canvas, widget, input, navigation, action, success, warning, danger and focus, with appropriate light/dark and contrast behavior. The observed interfaces use white, black and tonal controls frequently; do not turn every action blue.

Open Banking guidance supplies source brand colours, logo geometry and partner lockups as reference evidence. It is not a full native design system or a direction to adopt that identity. Retain its source masters for comparison; apply equivalent evidenced placement, sizing and variant behavior to the target's own logo while preserving its proportions and clear space. The PDF's Black hex label is malformed; the token reference records the source defect explicitly. [Brand and product token tables](tokens.md).

Use the target's own verified logo/app icon, names and approved artwork in runtime output. Preserve source provenance and applicable usage scope for fonts/photography. Source-branded graphics stay as references and guide equivalent target artwork. A screenshot is evidence, not a runtime component or a background containing customer data. Personal balances, names, account identifiers and conversations never become reusable sample content.

## 6. Component contracts

| Component | Required implementation | Evidence |
|---|---|---|
| Overview shell | Compact top chrome; dominant value/object; actions; continuous content; clear navigation | Original mobile cohort |
| Search | Leading search affordance, query editing, clear/cancel, no-results recovery | July global search and currency picker |
| Quick action | Source-matched circular/tonal control, concise label, disabled/pressed states | Home, Crypto, card controls |
| Grouped row | Icon/avatar; primary/secondary text; trailing value/status/chevron; aligned insets | Settings, payments, statements |
| Content card | Full intended column width; source-matched crop/radius; one purpose | Discovery and overview widgets |
| Primary button | Strong contrast; source shape; stable disabled/loading dimensions | Onboarding and historical UI Kit |
| Amount flow | Clear source/recipient/amount; material facts visible before commitment | Official payment/exchange help; some exact geometry unverified |
| Overlay | Correct anchor/presentation/dismissal; focus, keyboard and safe-area handling | July overlays and onboarding |
| Detail/receipt | Dominant identity/status; grouped facts; contextual actions; truthful outcomes | Transaction/detail capture |
| Table/approval queue | Stable headers/columns; filtering; scan-friendly status; contextual bulk review | Bulk work documented by Business 5; table geometry is an implementation adaptation until a matching capture is available |

Primary actions, navigation, fields and recovery must function in the requested scope. Screenshot-backed forms and dead CTAs do not pass fidelity review.

Use the [component and journey contracts](component-contracts.md) to specify states, input behavior, semantics, responsive constraints and recovery. A visual anatomy table alone does not define a working component. Exact native tokens remain unverified where the current partner source is absent.

## 7. Web

Public marketing and application dashboards serve different tasks. The observed homepage pairs photography with large copy and compact CTAs; phone layouts change crop, line wrapping and menu structure. The mobile menu groups categories, has a clear close control, and retains login/signup actions.

Business web needs operational density. Its official redesign describes bulk editing/review and high transaction volumes. Use Business evidence for operator tables and workspace navigation; stretching a phone balance screen across desktop is not an authenticated Business reference. Exact interactive states not observed remain unverified.

Source payment-button guidance is integration-specific reference material. Preserve the target's actual payment service and supported behavior. A design-reference task does not add a Revolut-branded integration or change provider configuration. [Web patterns](web-patterns.md).

## 8. PWA and accessibility

No official public Revolut-specific PWA manual was established. This skill's PWA requirements adapt the selected visual system: coherent install identity, launch colour, safe areas, history, offline/read-only state, session expiry and update recovery. An installed icon does not prove offline behavior or native parity.

Revolut documents screen readers, text scaling, contrast options and reduced motion; its published statement also acknowledges remaining limitations. Test the actual target against applicable WCAG/platform requirements. Preserve hierarchy at enlarged text, meaningful focus and reachable controls. [PWA and accessibility](pwa-and-accessibility.md).

## 9. Implementation adapters

**Flutter:** use the existing semantic theme/ThemeExtension structure. Share overview chrome, grouped rows, quick actions, picker/confirmation surfaces and navigation. Adapt with constraints and text scaling; preserve scroll/branch state. Separate safe-area/keyboard insets from decorative spacing.

**Web/React:** use semantic CSS variables and shared primitives. Preserve imagery ratios and responsive art direction. Use semantic HTML, functioning dialogs/menus and browser history. Model tables, filters and selections explicitly.

**PWA:** extend the web application with manifest/launch assets, appropriate cache/session boundaries and version recovery. Avoid serving a stale design shell after an update.

These are implementation recommendations, not claims about Revolut's internal architecture. Preserve the chosen stack and repository conventions unless changing them is part of the request.

## 10. Acceptance

Use the [comparison template](comparison-template.md) and applicable [100 design checks](100-design-checks.md). Match platform, viewport, theme, density, scroll and keyboard state before comparing. Inspect reference and target together. Repair shared tokens/components before isolated screens.

“100% Revolut” is the selected visual typology/colour fidelity target, with own-app names, logos, workflows and product content as required adaptations. Record those mappings so they are not incorrectly flagged as defects. Test the target's existing tasks after styling; business-flow equivalence to Revolut is not an acceptance requirement. A completion statement needs full evidence for its declared scope and no unresolved material visual mismatch. Checklist completion, visual similarity, target workflow tests, deployment and product acceptance are separate results. This reference is ready to apply; it does not certify any existing app's design.

## 11. Comprehensive UI/UX quality

Use the [quality standard](quality-standard.md) and [operational checklist](operational-checklist.md) for a deep review across native mobile, authenticated web app, public website, PWA and Codex skill execution. The existing R001–R100 checks retain their IDs and link to measurable tests. Treat documented requirements, observed source compositions and target-product results as different evidence.

Assess visual fidelity, task completion, accessibility, performance and resilience separately. Record critical/high issues with an owner role, next action and evidence needed to close them. A missing screenshot is an evidence gap; a reproducible failed interaction is a product defect. Improvements to this reference close specification gaps only. The [quality gap register](quality-gap-register.md) records the re-audit of this package.
