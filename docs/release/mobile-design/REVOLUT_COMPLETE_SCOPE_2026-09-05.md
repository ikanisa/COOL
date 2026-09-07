# Collect: complete design scope, 5 September 2026

The subsequent owner-selected group-card change is recorded in
`REVPOINTS_GROUP_CARDS_2026-09-05.md`. That follow-up has newer Home/Groups
captures and regression evidence. Counts and run bindings below describe this
earlier complete-scope pass; they do not certify the later card implementation.

**Local implementation and review candidate. Visual acceptance is unverified;
MOBILE-DESIGN-100 remains blocked. This is not an approved production release.**

This continues `revolut-surface-comparisons-2026-09-05.json` after the owner's instruction to
cover all screens, assets, UI elements and flows across mobile, Admin and the
website. The earlier report and failed/intermediate evidence remain historical.
The machine-readable record is
`revolut-complete-scope-verification-2026-09-05.json`; it records actual run status,
evidence hashes and source-binding limits rather than treating all captures as
one immutable release build.

## Review entry points

- Local gallery: <http://collect.localhost:4191/>. Six searchable tabs cover
  Mobile, Admin, Website, Assets, Elements and Flows. Captures open at their
  original resolution; mobile variants identify Android or iOS, and website
  entries also link to full-page captures.
- Generated gallery: `.cache/revolut-design-20260905/review/index.html`.
- Source inventory: `.cache/revolut-design-20260905/exhaustive-inventory.json`.
- Required fidelity cases: `revolut-surface-comparisons-2026-09-05.json`.

## Complete scope inventory

| Area | Enumerated scope | What the inventory establishes |
|---|---:|---|
| Mobile | 42 route cases, 56 material state cases | Executable fixture matrices, including signed-in/out, membership, geographic rails, creation, contributions, menus, confirmations, loading, errors, recovery and the Rwanda photo collection. |
| Admin | 23 routes at 4 widths; 21 flows at 4 widths | 92 route/viewport checks and 84 interaction/viewport checks. |
| Website | 16 routes at 4 widths | 64 first viewports, 64 full pages, 48 responsive menus and 16 share-flow captures: 192 images. |
| Dart UI | 133 source files; 392 UI/state/painter declarations; 359 interaction/presentation call sites | Source locations and shared-component coverage, including alternate or potentially unused branches. |
| Website UI | 3,516 rendered HTML elements | Page, class and link inventory from the generated site. |
| Assets | 48 runtime/resource files; 239 referenced icon symbols | Hashes for 29 images, 3 text fonts and 16 platform resources; 238 original glyph previews and one data-selected icon resolver. |
| Behavioral checks | 650 named Flutter tests | Passing named behavior assertions, including the 13 golden cases and photo cancellation/selection/save. |

Static inventory is not branch coverage or source-image equivalence. Named tests
and native fixtures do not establish real external-provider outcomes. The
gallery labels these distinctions and keeps the required acceptance cases open.

## Implemented changes

Mobile overview colours follow the selected owner references: blue Home,
teal Groups, purple Activity, violet/blue Profile and blue-indigo authentication.
Focused tasks use the neutral canvas, grouped surfaces and restrained state
colours. Shared tokens also govern sheets, dialogs, menus, input fields,
navigation, generated group media, loading, recovery and the Appearance preview.
Collect's own identity and existing product terms remain in place.

The shared confirmation sheet provides full consequence text, safe insets,
scrolling, accessible actions and large-text stacking. It is used for account
sign-out/delete, unsaved profile changes and invitation replacement. Activity
filtering and group administration sheets scroll to their final actions.
Country selection covers the underlying shell and preserves 200% text. Member
filters/sorting, legal headings, contribution actions and group-photo labels
reflow at large text. Scanner controls retain contrast over a light or camera
surface. Image failures render the existing neutral fallback.

Admin now uses consistent neutral tables, panels, forms, empty states and
confirmation surfaces. Nested page navigators no longer suppress the persistent
header's accessible controls. Country, operator and Home controls provide
48-pixel targets. Compact overview rows wrap. Narrow dialogs scroll, and safety
notices display their full consequences. Login artwork remains visible against
its background. Flow tests open and cancel dialogs before mutations.

The public website uses the collected public-web typography and photographic
composition with Collect content. Page and menu controls have responsive,
keyboard, focus, reduced-motion and recovery handling. Decorative phone controls
are inert illustrations. Legal and diaspora text contrast defects were fixed;
the 320-pixel hero reflows without reducing its headline role. Lower-page panels,
phone illustrations and the PWA manifest follow the selected surface roles.

The owner's image annotation replaces the reference portrait with an original
generated young adult Rwandan woman and the reference sky with Kigali hills.
Four additional original scenes cover community savings, everyday payments,
banking conversations and shared goals. All six original PNGs, generation
prompts and SHA-256 hashes are recorded under `assets/marketing/`. These are
fictional generated illustrations. The previous reference artwork is retained
only in the local historical evidence cache and is absent from the runtime
asset inventory.

The website uses the portrait/sky in its hero and the remaining photos in
relevant page sections. The app offers five scenic/group choices when creating
or editing a group, alongside the existing device-photo choice. Cancelling
leaves the group unchanged; selecting previews the photo; the existing Save
action applies it. The sheet scrolls, follows reduced-motion settings and
exposes named actions. Group titles wrap at large text instead of truncating
beside the photo controls.

The three new homepage photo captions and navigation arrows were visually
reviewed. Removing only that section recovers the prior governed content hash
`93ab5c339b121c92f6c9b52730f2bb95299f14bed0e7eff9b2c13a8c88e41595`.
The updated visible-content hash is
`a0b19e5bd9838068cc6b4dddcc3db7cf169e05702268b77f69a43900c827b56b`;
all existing product/financial text remains unchanged. The public quality gate
retains its exact content checks for all 16 routes.

## Verification and visual review

The final complete Flutter run passes all **650 named tests**, with no test
errors. The 13 golden files were visually reviewed before their earlier refresh;
the final suite and SHA-256 manifest verification pass. Dart analysis, source
hygiene, public quality checks and the 33 gate-contract tests (131 assertions)
are recorded in the verification JSON. No visual baseline or gate threshold was
changed to conceal a failing screen.

Browser route checks pass at **320, 390, 834 and 1440 CSS pixels**. Admin tests
exercise real accessible controls, focus, scrolling, country scopes, selection
and dialog cancellation. Public checks include page identity, horizontal
overflow, menus, keyboard containment/Escape/focus restoration and share states.
Computed public text contrast passes for **4,262 text observations**. Four
image-backed observations remain unverified by that flat-colour calculation.
The homepage contact action uses a dark pill so its label retains contrast
against the brighter part of the Kigali sky. The remaining image-backed text
is the hero heading and introduction, visually reviewed at 320 and 1440 pixels.

Native evidence includes Android and iOS dark/default and light/200%-text
fixture runs, with high contrast and reduced motion on the latter. The final
Rwanda light/200%-text runs pass **56/56 material states on Android and 56/56
on iOS**, with all 56 primary captures per platform and additional scroll
captures retained. The new photo collection, selected preview and option labels
were visually checked on both platforms. Earlier dark runs cover the original
54-state matrix and remain earlier evidence. The exact recorded runs and
available before/after source fingerprints are in
the JSON record. Later fixes are not retroactively attributed to earlier builds.
Android-only creation remains Android-only: the four corresponding iOS state
cases assert the existing redirect to Groups.

The implementing agent reviewed native contact sheets and original detail
images, all Admin route/flow layouts, public full-page layouts, runtime image
assets and the 238 glyph previews. The final fixes were checked again in their
relevant captures. Contact sheets support layout inspection; they do not prove
pixel equality or sentence-level visual review of a long legal page. Browser
text/contrast checks supplement the long-page review. This is agent review,
not owner acceptance.

## Harness corrections retained in the audit trail

- State coverage increased from 31 to 54, then 56 cases for the Rwanda photo
  collection and selection; no required case was removed.
- Large-text search activation uses its stable tooltip; off-screen action taps
  first scroll into view and settle before activation.
- iOS screenshot accounting counts all required primary captures separately
  from additional scroll/recovery images. The extra images are retained.
- The state screenshot validator permits only the four asserted iOS creation
  redirects to share a destination. Android duplicates and unrelated iOS
  duplicates still fail. Its independent regression assertions pass.
- Two Home membership cases had identical first viewports at 200% text. Their
  original top views are retained; the primary view now frames My groups and
  asserts two memberships versus one. Screenshot diversity thresholds remain
  unchanged. Small hash differences in scroll captures were not accepted as
  proof of a meaningful state difference.
- Earlier iOS runs that passed the app test but failed capture accounting or
  diversity remain failed historical runs. Fresh runs establish the corrected
  result; their old summaries/logs were not rewritten as passes.

## Remaining acceptance work

The requested skill explicitly says: **“Missing evidence is unverified, never an
automatic pass.”** Source:
[/Users/jeanbosco/.codex/skills/revolut-design/SKILL.md](/Users/jeanbosco/.codex/skills/revolut-design/SKILL.md).
This rule requires the missing comparisons to stay open after local work.

Exact native typography remains provisional Inter; current public-web Aeonik
does not establish native font equivalence. Official Business imagery supports
an Admin pattern adaptation, but does not establish every authenticated desktop
screen, state or dimension. Unseen source loading/error/light/accessibility
states cannot receive an invented 100% score. The source cohorts and limits are
recorded in the comparison register and earlier report.

MOBILE-DESIGN-100 still requires **134 approved case records and 22 owner
annotation closures**, together with current source/reference/contract/version
and production APK/AAB bindings. Existing open findings and the separate
developer-account UAT record remain intact. Test totals and local screenshots
cannot provide those approvals.

TalkBack/VoiceOver operation, native OS permission/picker/share surfaces,
real authentication delivery, bank/MoMo outcomes, signed-in physical-device UAT
and deployment/provider/store acceptance are separate from these fixtures.
The isolated Android emulator and iOS simulator contain synthetic data; existing
signed-in devices, payment behavior and production access controls were preserved.
No production deployment or approved distribution occurred.
