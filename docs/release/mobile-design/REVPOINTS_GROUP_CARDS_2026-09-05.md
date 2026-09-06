# Owner-selected RevPoints group cards — 5 September 2026

Local implementation review. Complete mobile fidelity and production acceptance
remain unverified; MOBILE-DESIGN-100 is blocked.

Review: <http://collect.localhost:4191/group-cards.html>. This page places the
owner's unchanged reference beside explicitly labelled Collect captures.
The complete gallery keeps its six surfaces and marks older native evidence
as historical. The machine record is
`revpoints-group-cards-verification-2026-09-05.json`.

## Reference and adaptation

The owner selected `/Users/jeanbosco/Desktop/Revolut/Cards.png`, a 408 × 857
RevPoints image. Its SHA-256 is
`a724ba36d5b486141dde9419b4fd9702eee3562f0fd7cdf5b5f3b40fb8ba67c7`.
The first card is approximately 358 × 438 pixels at x22/y117. Its full photo,
rounded outline, top category caption and lower title/metadata fade govern the
new shared card component. Original app build, capture date and logical device
viewport are unknown; screenshot pixels are not exported native tokens.

Collect uses 24dp corners, the observed minimum proportions, 16dp content
insets, a 22dp title and 16dp metadata. Typography remains the existing Inter
adapter. The lower fade follows content height. Enlarged text, long titles and
multiple currency totals can increase card height. Header contrast and focus
indication are accessibility adaptations; exact source typography is unverified.

Home stays blue and Groups stays teal. This component reference does not change
page navigation, membership, geography, group creation or payment rules. Its
category captions supersede the previous icon-only rule for editorial cards;
dense task/list rows retain their existing presentation.

## Implementation

- All four GroupCard variants use one photo-card component. Home My groups,
  Featured groups, Groups and membership filters share the layout and spacing.
- Uploaded photos take priority. Original Rwanda assets supply illustrative
  defaults and failed-media fallbacks without changing stored group records.
- Group names, actual per-currency totals and supporter counts remain truthful.
  Unknown counts keep their unavailable state. Contribution and opening a group
  remain separate actions with their existing access rules.
- Loading uses the same card proportions and radius. Empty/error screens retain
  their real state. Tablet layouts use two columns; narrow and enlarged-text
  layouts grow without truncating titles or currency values.

## Verification

All 660 named Flutter tests pass, including 13 golden cases and 10 new editorial
card checks. The new checks cover all four variants in both themes at 200% text,
long names, multiple currencies, unknown counts, uploaded/malformed media and
separate touch/keyboard actions. Existing Home/Groups width and flow checks pass.

Only the Home and Groups baselines were updated for this change, after opening
and reviewing both new images. Previous copies remain under
`.cache/revolut-design-20260905/revpoints-group-cards/goldens-before/`.
The screenshot helpers wait for visible image decoding and use bounded frames
for intentionally animated loading states.

Flutter analysis passes with no issues. The source/asset hygiene gate passes,
including all 29 approved images. Design-gate enforcement tests pass: 33 tests,
131 assertions. The gallery passes image loading, navigation and horizontal
overflow checks at 320 and 1440 pixels.

The fresh disposable iOS run passes all 42 routes and retains 42 screenshots.
The implementing agent opened the new Home and Groups captures and reviewed
their card geometry, photo loading, typography and content fade. Before/after
source, contract and reference fingerprints match. Android's full 56-state
check also passes at 200% text, high contrast and reduced motion, retaining
56 state images and 16 additional scroll/recovery captures. The implementing
agent reviewed Groups offline, Home joined/mixed/discovery and Groups loading.
Both runs bind to source fingerprint
`2de75b2f041551745e53a782c9622bd7ca9f42614e19eb9c41b9514ba86b48e3`.

The final comparison has 16 labelled Collect captures beside the owner reference.
The main gallery has 387 mobile records, 176 Admin records, 128 website records,
287 asset records, 4,264 UI element records and 660 named behavioral checks.
These are review records, not counts of distinct approved screens. Older native
variants are retained and explicitly labelled historical.

## Acceptance boundary

The mandatory mobile gate reports 166 issues; this is a register of missing or
stale acceptance evidence, not 166 equivalent visual defects. All 134 required
cases and earlier annotations remain, with the new editorial-card annotation
added. No thresholds, required cases or production controls were weakened.
Owner acceptance, full source/state fidelity, release artifact binding and
production approval remain open. No signed-in personal device or production
payment data was changed.
