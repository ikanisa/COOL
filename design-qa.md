# Revolut Visual-Parity QA

## Comparison target

- Scope: Collect mobile shared shell, Home, Groups, global Contribute, global
  Activity, Profile/Settings, Group Detail, Contribution, and Ledger.
  All 35 member routes are implemented and mapped to a retained reference
  pattern or an explicit no-direct-analogue rationale. Full-goal comparison
  evidence remains open for direct authentication/OTP and amount-entry
  references and the remaining state-matched mobile material states. E-073
  completes the honest public trust and Admin operations pattern comparisons
  without claiming that Revolut has equivalent public/Admin products.
- Source visual truth:
  - `.cache/revolut_full_audit/20260723T200000/02-home-top.png`
  - `.cache/revolut_full_audit/20260723T200000/05-payments-top.png`
  - `.cache/revolut_full_audit/20260723T200000/06-crypto-top.png`
  - `.cache/revolut_full_audit/20260723T200000/10-profile-settings.png`
- Rendered implementation:
  - `.cache/revolut_phase1_qa/20260723/collect-home-pass2.jpg`
  - `.cache/revolut_phase1_qa/20260723/collect-groups-pass2.jpg`
  - `.cache/revolut_phase1_qa/20260723/collect-settings-pass3.jpg`
  - `.cache/revolut_phase2_qa/20260724/collect-group-detail-pass1.jpg`
  - `.cache/revolut_phase2_qa/20260724/collect-contribution-pass1.jpg`
  - `.cache/revolut_phase2_qa/20260724/collect-ledger-pass2.jpg`
  - `.cache/revolut_phase2_qa/20260724/collect-contribute-entry-pass1.jpg`
  - `.cache/revolut_phase2_qa/20260724/collect-activity-pass1.jpg`
  - `.cache/revolut_phase2_qa/20260724/collect-security-pass2.jpg`
  - `.cache/revolut_phase2_qa/20260724/collect-appearance-pass1.jpg`
- Full-view comparison evidence:
  - `.cache/revolut_phase1_qa/20260723/home-comparison-pass2.png`
  - `.cache/revolut_phase1_qa/20260723/groups-comparison-pass2.png`
  - `.cache/revolut_phase1_qa/20260723/settings-comparison-pass3.png`
  - `.cache/revolut_phase2_qa/20260724/group-detail-comparison-pass1.png`
  - `.cache/revolut_phase2_qa/20260724/ledger-comparison-pass2.png`
  - `.cache/revolut_phase2_qa/20260724/contribute-entry-comparison-pass1.png`
  - `.cache/revolut_phase2_qa/20260724/activity-comparison-pass1.png`
  - `.cache/revolut_phase2_qa/20260724/security-comparison-pass2.png`
  - `.cache/revolut_phase2_qa/20260724/appearance-comparison-pass1.png`
- Native viewport: iPhone 17 Pro simulator, 368 x 800 screenshot pixels.
- Source pixels: 316 x 696 for each phone-mirroring capture.
- Implementation pixels: 368 x 800 for each simulator capture.
- CSS size: not applicable; this is a native Flutter/iOS comparison.
- Density normalization: each source capture was resized to 368 x 800 before being placed beside the unscaled 368 x 800 simulator capture.
- State: light theme, signed-in evidence fixture, populated Home and Groups.
- Primary interactions checked: Home render, all five bottom-navigation
  destinations, global Contribute group selection, nested Contribution
  navigation and amount entry, confirmed-only global Activity, Groups list row
  semantics, Group Detail quick actions, Manage-to-Ledger navigation, Ledger
  filter/sort action semantics, Settings row semantics, and selected navigation
  state.
- Runtime errors checked: no Flutter error, unhandled exception, or runtime error was found in the captured native run log.

## Findings

No actionable P0, P1, or P2 differences remain within the compared Home,
Groups, Contribute entry, Activity, Settings, Group Detail, and Ledger scope.

The expanded full-goal QA remains blocked because there is no verified Revolut
amount-entry/transfer screenshot for a truthful Contribution side-by-side
comparison, direct authentication/OTP references remain incomplete, and the
implemented member routes do not yet have the complete state-matched normalized
matrix required for a passing result. The existing implementation
screenshots prove current rendered states only; they do not prove full source
parity.

- Fonts and typography: the app uses bundled Inter exclusively. The revised 400-700 weight range, balance hierarchy, compact labels, line heights, and truncation behavior are visibly close to the reference. No 900-weight emphasis remains in the compared shared shell and hero surfaces.
- Spacing and layout rhythm: Home now follows top chrome, balance, four quick actions, dense activity, then group content. Groups opens directly into a grouped list. Settings uses one identity block followed by a compact grouped control list. Phone padding is 16 px, routine cards are 16 px, featured cards are 20 px, sheets are 24 px, and the bottom bar is 60 px with a 44 px selected indicator.
- Colors and visual tokens: Home preserves the bright-blue-to-deep-navy reference family; Groups preserves the violet-to-deep-purple family; Settings uses the source's near-black profile canvas and neutral dark list panel. Chrome, muted glass, border opacity, and white foreground balance are consistent with the source.
- Image quality and asset fidelity: no source logo, illustration, or proprietary image was approximated. Standard actions use the existing icon library; group identity uses semantic circular icons because Collect has no user-photo source for these records.
- Copy and content: Collect-specific money, group, member, and activity content is retained. No Revolut trademarks, account identifiers, transaction copy, or product claims were copied.
- Navigation: the selected state, compact floating bar, contrast, and placement
  match the source geometry. The five functional destinations are Home, Groups,
  Contribute, Activity, and Profile. Contribute and Activity are Collect-native
  routes and do not copy unsupported Revolut products.

Focused-region comparisons were not required after the final passes because all normalized full-view comparisons are 368 x 800, displayed at original size, and the top chrome, identity/balance typography, quick actions, card/list rows, icon treatment, switches, and navigation labels are all legible in the same combined evidence.

### Group Detail pass 1

- Source: Crypto asset-detail archetype.
- Result: the compact command chrome, dominant amount, four quick actions, and
  grouped activity panel align with the source. Collect intentionally adds a
  group-type icon, group title, supporter count, and Collect-specific actions.
- Evidence:
  `.cache/revolut_phase2_qa/20260724/group-detail-comparison-pass1.png`.

### Ledger passes 1-2

- Pass 1 P2 finding: a summary row and duplicated group/sort control dock pushed
  the first transaction panel materially lower than the Payments reference.
- Fix: retained Search, Group, and Sort in the command chrome; replaced the
  large summary with a compact Ledger/total title row; removed the duplicated
  control dock and redundant Activity heading.
- Post-fix evidence:
  `.cache/revolut_phase2_qa/20260724/ledger-comparison-pass2.png`.
- Result: the transaction panel now begins immediately under the compact
  Ledger/total row, while the filter and sort functionality remains accessible
  from the top chrome.

### Global Contribute pass 1

- Source: Payments list archetype.
- Result: search chrome, circular semantic identity, compact two-line rows,
  trailing balances, and five-destination selected state align with the source.
- Functionality: selecting a group deep-links into the existing
  `/groups/:collectionId/contribute` flow; no payment-intent logic is
  duplicated.
- Evidence:
  `.cache/revolut_phase2_qa/20260724/contribute-entry-comparison-pass1.png`.

### Global Activity pass 1

- Source: Payments list archetype.
- Result: search/filter chrome, immediate confirmed-record panel, circular
  status identity, compact metadata, trailing amounts, and selected navigation
  align with the source.
- Functionality: the route reads only confirmed contribution records and
  deep-links each row to the existing group ledger. Pending payment intents do
  not appear.
- Evidence:
  `.cache/revolut_phase2_qa/20260724/activity-comparison-pass1.png`.

### Security passes 1-2

- Source: Security settings archetype.
- Pass 1 P2 finding: a duplicate compact title and persistent bottom navigation
  compressed the reference-style hero and pushed the final security row below
  the first viewport.
- Fix: retained a single back control, moved the route to the verified
  near-black profile canvas, and treated Security as a standalone detail
  screen.
- Result: one dominant security title, two compact quick actions, one
  high-visibility education panel, and a dense divided settings panel align
  with the source. Collect-specific account, SMS verification, receiver
  privacy, and deletion actions replace unsupported card/passcode products.
- Evidence:
  `.cache/revolut_phase2_qa/20260724/security-comparison-pass2.png`.

### Appearance pass 1

- Source: Theme preview archetype.
- Initial result: the near-black standalone canvas, compact back/title chrome,
  large selectable surfaces, obvious selected state, and restrained
  device-persistence note aligned with the source hierarchy.
- E-043 review finding: the three abstract mode cards still showed a mode icon
  rather than the selected Collect screen, while the verified source makes the
  live miniature screen the main preview.
- Fix: replaced the abstract cards with a live miniature Collect Home preview
  using the immutable official logo and truthful fixture content, followed by
  compact responsive Dark, Light, and System controls.
- Result: the preview-first interaction now matches the observed hierarchy.
  No Revolut theme, paid product, illustration, copy, or brand asset was
  introduced.
- Current evidence:
  `.cache/revolut_parity_mapping/20260724/appearance__theme.png`.

### Complete group and Settings reference mapping

- `docs/revolut-parity-goal/REFERENCE_MAPPING_MATRIX.md` now maps all 35 routes
  to a retained reference pattern or an explicit no-direct-analogue rationale.
- Group Detail, Manage, Group Profile, Members, and Ledger are reviewed
  together in
  `.cache/revolut_parity_mapping/20260724/group-mapping-contact.png`.
- Settings, profile editing, Notifications, Appearance, Security, Account,
  deletion, and Help are reviewed together in
  `.cache/revolut_parity_mapping/20260724/settings-mapping-contact.png`.
- QR, share/invite, group creation, archive, ownership transfer, deletion,
  legal, and recovery states are not falsely presented as Revolut screens.
- RT-003 and RT-004 are complete for mapping scope. Direct auth/OTP and
  amount-entry references plus RT-005 full normalized comparison closure remain
  open.

### Official-logo chrome correction

- Current-source visual review found that the default profile control could
  render an arbitrary text initial such as `0` when no profile image existed.
- Fix: default member chrome now uses only the immutable official Collect PNG;
  explicit route controls such as Back continue to use the approved icon
  library.
- The login lockup and core Home, Groups, Contribute, and Activity goldens now
  render the official mark deterministically.
- Evidence:
  `.cache/revolut_parity_mapping/20260724/official-logo-and-appearance-before-after.png`.

### Contribution source blocker

- Implementation evidence:
  `.cache/revolut_phase2_qa/20260724/collect-contribution-pass1.jpg`.
- The screen uses a counterparty header, dominant amount field, restrained copy,
  and pinned primary action.
- No captured reference represents the same amount-entry state. Comparing this
  screen against Home More, Theme, Payments list, or Crypto would be a
  state mismatch and cannot support a passing fidelity conclusion.

## Comparison history

### Home pass 1

- Earlier P2 finding: featured visual cards occupied the first content region, while the reference places a dense transaction surface directly beneath the quick actions.
- Fix: moved Activity ahead of group discovery, converted owned groups to a shared dense list, and restored a four-action row on iOS with a functional Groups action.
- Post-fix evidence: `.cache/revolut_phase1_qa/20260723/home-comparison-pass2.png`.
- Result: the above-the-fold hierarchy and density now align with the source.

### Groups pass 1

- Earlier P1 finding: a large balance hero consumed roughly one third of the screen and prevented the Payments-style list from starting beneath the search chrome.
- Fix: removed the populated-state Groups hero and placed the grouped money list immediately below the top chrome and section title.
- Post-fix evidence: `.cache/revolut_phase1_qa/20260723/groups-comparison-pass2.png`.
- Result: the list density, row anatomy, circular identity treatment, trailing amounts, dividers, and vertical start align with the source.

### Settings passes 1-3

- Earlier P1 finding: Settings still used the previous violet dashboard composition with a large account-number hero, search field, four quick actions, and several isolated cards. The source is profile-first and uses one identity block with a dense settings list on a near-black canvas.
- Fix: replaced the search chrome with a compact top action bar, rebuilt the identity block, consolidated real Collect controls into one divided list, reduced routine weights, and introduced the near-black Settings route gradient.
- Pass 2 P2 finding: the grouped panel retained a purple surface while the source uses a neutral charcoal panel.
- Fix: changed the Settings list surface to a neutral `#1B1B1F` to `#121216` gradient while preserving accessible white foregrounds and semantic controls.
- Post-fix evidence: `.cache/revolut_phase1_qa/20260723/settings-comparison-pass3.png`.
- Result: the identity-first composition, background, row density, dividers, trailing controls, and icon scale align with the source. A real profile photo and paid-plan card were not invented because Collect has no approved source data or corresponding product.

## Implementation checklist

- [x] Bundle and enforce Inter as the only runtime family.
- [x] Replace all feature-level Flutter and public-web raw typography with the
  central Inter typology and delete unsupported 750-950 weights.
- [x] Delete invented SVG/`C` branding and restore the official four-node
  Collect PNG across in-app, launch, Android, iOS, web, and Admin surfaces.
- [x] Reduce routine radii, page padding, hero weight, and navigation height.
- [x] Match the Home reference hierarchy with four quick actions and dense activity.
- [x] Match the Payments reference with a dense grouped Groups list.
- [x] Match the profile/settings reference with a near-black identity-first control surface.
- [x] Preserve existing routes, privacy boundaries, and real Collect actions.
- [x] Verify native Home-to-Groups navigation and row semantics.
- [x] Pass Flutter analysis, targeted route/widget tests, and release web build.
- [x] Verify Group Detail quick-action semantics and grouped activity.
- [x] Flatten Ledger into a Payments-style dense transaction screen.
- [x] Verify native Manage-to-Ledger navigation.
- [x] Implement the five-destination mobile shell.
- [x] Implement and compare global Contribute group selection.
- [x] Implement and compare confirmed-only global Activity.
- [x] Verify the new routes with focused widget tests and a native iOS run.
- [x] Implement dedicated Notifications, Appearance, Security, and Help routes.
- [x] Compare Security and Appearance against their matched references.
- [x] Map all 35 routes to retained references or explicit
  no-direct-analogue rationales.
- [x] Replace every default top-chrome text-initial fallback with the official
  Collect PNG and verify the logo in current goldens.
- [x] Hide archived groups from active discovery and contribution surfaces,
  preserve read-only ledger access, and fail closed on direct mutation routes.
- [x] Surface duplicate and expired contribution-intent states without
  duplicating ledger truth.
- [ ] Capture a verified Revolut amount-entry/transfer source.
- [ ] Implement and compare all remaining full-goal mobile, public, and Admin
  surfaces.
- [ ] Complete the device, accessibility, theme, performance, security, and
  release matrices.

## Follow-up polish

- P3: replace the simulator-only back-to-app status indicator in presentation captures by recording from a clean simulator session; it is not app content.
- P3: continue checking the five-destination labels at the remaining device
  widths and large text settings during the device matrix.
- P3: E-058 passes all 16 public routes at compact/tablet/desktop in local
  Chrome with visible focus, named controls, landmarks, and no overflow.
  E-059 accepts the critical Admin compact/tablet/desktop keyboard flows after
  compact filter, record-card, selected-navigation, and keyboard corrections.
  E-062 extends responsive, semantic, accessibility-tree, critical-keyboard,
  and target-size coverage to all 23 Admin routes with 69 clean screenshots.
  All 1,138 visible enabled targets are measured; all 69 route/viewport target
  checks pass with zero genuine sub-44 CSS-pixel violations. Login advances to
  OTP by keyboard; both denied recovery actions navigate; filtered export
  announces completion and retains focus; payment-dialog cancellation restores
  trigger focus; group-record, accountable-purpose, sensitive-reveal, and
  live-region flows pass in all three viewports. Normalized reference, native
  target/focus measurement, deployed-host, and actual screen-reader review
  remain.
- P3: Android release flavors now emit local APKs and the aggregate signing
  guard is hardened; the explicit production AAB passes basic verification,
  while upload-certificate pinning and device evidence remain release-workstream
  items rather than visual-parity proof. CI and repo-wide QA already use
  explicit production-flavor APK commands.
- P3: the current iOS simulator build installs and launches on iPhone 17 Pro;
  this closes build freshness only and does not replace normalized visual
  comparison or physical-device accessibility evidence.
- P3: a controlled Android 16 Pixel 4a-profile emulator now passes the hardened
  35-route matrix in both default Dark and Light/200%-text/high-contrast/
  reduced-motion variants. E-053 adds large 1440x3120 System-Light/System-Dark
  matrices with 35 retained screenshots each and closes a Settings light-theme
  contrast defect. E-054 passes native notification denial, Collect recovery,
  retry, and grant while closing resume/context races. E-056 passes native
  Camera denial, Collect privacy education, retry, grant, and recovered scanner
  with four retained screenshots after closing the permission/timing/stale-error
  defects. E-057 passes durable group-intent retention before process death,
  distinct cold-restart recovery, same-process warm App Link delivery, and
  no replay after matching clear. Dev-package metadata passes with restricted
  SMS absent. E-073 additionally measures 113 native actionable controls
  across nine critical Android states with zero unnamed, intrinsically
  undersized, or non-focusable results and closes the Home Profile/Settings
  naming ambiguity and adds focused TalkBack contribution action/amount entry.
  Complete TalkBack traversal/speech, physical iOS VoiceOver, and direct
  reference comparisons remain open.
- P3: native profiling now executes a target-verified six-scenario matrix on
  the controlled emulator. E-052 supersedes the original E-051 quality
  interpretation with two accepted v2-target runs after dense-list and
  amount-entry optimization. The repeat captured 504 Flutter-engine frames and
  a 2,204,852-byte Perfetto trace: Groups recorded 0/154 UI-or-raster budget
  misses, Activity 0/191, and amount entry 1/45, with p90 raster durations of
  2.285 ms, 2.642 ms, and 6.052 ms. I-042 is closed for the controlled-emulator
  scope. E-066 supplies the accepted exact-Pixel profile. E-071 adds an isolated
  600-second emulator session with one stable PID, 266 route actions, 17
  lifecycle cycles, and zero scoped crash/ANR matches. Physical/production
  soak and authorized Play crash/ANR reporting remain open.
- P3: Light, Dark, and persisted System appearance now work as distinct choices.
  System was verified on iPhone 17 Pro to respond live to iOS Light/Dark changes
  and survive relaunch. E-055 adds accepted current-source iPhone Dark and
  System-Light 35-route matrices; Android System-Light and System-Dark pass all
  35 routes at a large viewport. Screen-reader and physical-device coverage
  remain open.
- P3: member and Admin apps now expose real framework high-contrast themes with
  stronger boundaries and focus rings. A combined native iPhone run passed all
  35 routes with high contrast, 320% text, and reduced motion after exposing
  and closing an Appearance-card overflow. E-055 adds a current-source iPad
  System/200%-text/high-contrast/reduced-motion matrix after exposing and
  closing the truncated auth wordmark. Admin/browser and assistive-technology
  traversal remain open evidence items.
- P3: current-source E-055 iOS builds and complete route captures pass on iPhone
  17 Dark/System-Light and iPad Pro 11-inch System/200%-text/high-contrast/
  reduced-motion. Each accepted matrix resolves 35/35 routes, captures 35/35
  screenshots with 26 distinct states, and passed contact-sheet visual review.
  VoiceOver and physical-device closure remain separate.
- P3: E-063 adds a fresh iPhone 17 Dark matrix at the platform Large/1.2-text
  setting after direct native review exposed `Scan QR` and `Supported`
  ellipsizing on Home. The accepted implementation top-aligns the hero actions
  and permits two-line labels; a focused rendered-paragraph regression proves
  all four labels fit, and the accepted recapture resolves 35/35 routes with
  35/35 screenshots and 26 distinct states. The exact connected Pixel 4a
  remained securely locked, so the hardened Android preflight recorded
  `runner=not_started` before any build/install. This closes the local label
  defect and lock-safety issue, not VoiceOver/TalkBack or physical-device
  confirmation.
- P3: E-064 runs Android Accessibility Suite TalkBack 16 on the controlled
  Pixel 4a-profile emulator. The first Home/Groups pass exposed a redundant
  whole-toolbar focus stop and duplicate hero-action announcements. The
  accepted correction removes both while preserving individual labels and tap
  actions; paired focus screenshots and Android accessibility trees are
  retained. This is scoped Home/Groups TalkBack evidence, not complete
  critical-flow, spoken-audio, physical-device, or VoiceOver closure.
- P3: all 35 member routes now pass compact 320x568 at 200% text with reduced
  motion, standard 390x844, large 430x932, and tablet 834x1194 with high
  contrast widget matrices. Native iPhone maximum Dynamic Type plus Increase
  Contrast exposed and closed avatar containment and Ledger-total readability
  defects on Activity/Ledger, and the later 35-route 320% native traversal
  exposed and closed the Appearance-card overflow. Primary content remains
  scrollable, while some secondary labels ellipsize at the extreme scale.
  VoiceOver, browser, and physical-device accessibility variants remain open.
- P3: E-046 closes the Flutter reduced-motion interaction gap for detail
  navigation, modal sheets, Activity list filtering, and amount receiver
  controls while preserving normal route motion. The same work corrected the
  shared glass-sheet Material ink layer without changing any approved golden.
  Physical-device vestibular comfort confirmation remains separate evidence.

## July 30 current-source checkpoint

E-067 adds two accepted iPhone 17 matrices from the current July 30 working
tree:

- Dark: 35/35 routes, 35/35 screenshots, 26 distinct states;
- System on iOS Light: 35/35 routes, 35/35 screenshots, 26 distinct states.

The first Dark attempt is retained and rejected because its root redirect
asserted the visible Auth marker before the timer-driven transition finished
painting. The corrected harness uses a bounded marker wait without weakening
the exact-path, route-count, screenshot-count, variant, or diversity gates.

Direct review of Auth, Activity, Offline, Sync, Help, Contribution, Appearance,
Security, Group Detail, and Delete request found one remaining local P1:
Sync still placed three supporting rows before the recovery CTA. Offline and
Sync now use the plan's maximum of two supporting rows; the primary action is
visible without scrolling on the standard phone in both accepted variants.

Three normalized 316x696-per-panel pattern comparisons use only reference-safe
Revolut captures:

- `.cache/revolut_parity_comparisons/20260730-crp-current/01-value-hierarchy.png`;
- `.cache/revolut_parity_comparisons/20260730-crp-current/02-appearance.png`;
- `.cache/revolut_parity_comparisons/20260730-crp-current/03-security.png`.

The combined UX and screenshot-visible accessibility findings are recorded in
`docs/revolut-parity-goal/JULY_30_CURRENT_SOURCE_COMPARISON_REVIEW.md`.
The comparisons explicitly do not claim feature equivalence. None of the 36
personal-local-only captures is reproduced.

E-069 records the latest live iPhone Mirroring check. Mirroring briefly
connected, but the phone was not on Revolut and the session ended with
`iPhone in Use` before Revolut opened. No unrelated app or personal content was
retained as reference evidence. Direct Auth/OTP/amount/review capture therefore
remains blocked until the iPhone is locked and left unused for the complete
read-only capture session.

Verified local outcomes:

- Activity preserves group, date, compact reference, and amount in both
  variants.
- Auth keeps identity, instruction, input, and disabled primary action in one
  first-viewport task zone.
- Recovery states show one thesis, no more than two supporting rows, one
  primary recovery action, and a secondary privacy route.
- Help exposes task-led sign-in, contribution, QR/joining, membership/owner,
  and privacy/deletion categories.
- Appearance retains a preview-first Dark/Light/System hierarchy and System
  follows iOS Light.
- Security preserves a compact Collect-specific trust hierarchy without
  copying unsupported banking products.
- Disabled destructive styling is visibly distinct and remains numerically
  covered.
- Nine critical native Android states expose 113 named, focusable actionable
  nodes at the governed 44 dp minimum; the four viewport-edge clips were
  accepted only after full-size recapture.
- Home distinguishes the top-left `Profile` action from the top-right
  `Settings` action in the native accessibility tree.
- The contribution flow exposes one editable native amount node, opens the
  numeric keyboard under TalkBack focus, accepts `12,345`, and restores the
  original assistive-technology setting after the controlled run.
- Clean local Supabase replay and rollback-only lifecycle evidence pass for
  pending, confirmed, expired, duplicate, failed, recovery, idempotent
  allocation, ledger immutability, and scoped receiver/deletion/support/audit
  boundaries.
- The controlled emulator contribution route passes online, stale-cache
  offline, and authoritative online resync while restoring the exact initial
  radio state.
- Live Chrome exposes the public Privacy and Admin-login accessibility trees;
  the public host passes 34/34 and serves the official four-node logo.

Still unverified or blocked:

- direct Auth/OTP/error/retry and contribution amount/review references;
- state-matched completion of every mobile comparison family;
- VoiceOver/TalkBack end-to-end spoken reading order and actions;
- physical iOS, authenticated deployed Admin, Play reporting/Console, signing,
  store, production, deployment-change, and accountable approval gates;
- a single clean source revision for the final comparison and release pack.

These gaps keep RT-001, RT-002, RT-005, RT-007, and their dependent external
completion gates open.

final result: blocked
