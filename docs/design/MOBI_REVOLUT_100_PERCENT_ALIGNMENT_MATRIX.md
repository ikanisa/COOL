# MOBI/Revolut 100% Alignment Matrix

Date: 2026-07-02
Repo: `/Volumes/PRO-G40/COOL`
Comparator repos and references:
- MOBI Flutter app: `/Volumes/PRO-G40/MOBI/mobi_app`
- Revolut reference screenshots: `/Users/jeanbosco/Downloads/Revolut10`

## Decision

Collect member mobile must target **100% MOBI/Revolut experiential parity**: the app should feel, move, scan, and compose like MOBI's mature Flutter shell and Revolut's fintech mobile references, while preserving Collect's real product facts: Rwanda group collections, RWF, MoMo/USSD, Collect ID privacy, QR/share, member activity, and owned/approved runtime assets.

This matrix replaces the old scattered design reports, blocker registers, signoff checklists, Stitch briefs, and historical parity packets. Those documents must not override this file, `DESIGN.md`, or `docs/design/DESIGN_SYSTEM.md`.

This file is the single repo-level comparative implementation table. It maps
every MOBI/Revolut design target to Collect owner files, gates, evidence, and
deletion decisions.

## Non-Negotiable Target

| Area | MOBI/Revolut target | Collect implementation requirement | Current owner files | Deletion/contradiction rule |
| --- | --- | --- | --- | --- |
| Overall feel | Premium, dark-first, immersive, financial, compact, glass-heavy, high-confidence. | Every member screen must read as a fintech-grade mobile surface, not a generic Material utility app. | `DESIGN.md`, `docs/design/DESIGN_SYSTEM.md`, `lib/app/theme/`, `lib/shared/widgets/` | Delete docs that describe Collect as an open-ended redesign, generic app shell, or older asset-screen remix. |
| Product boundary | Keep real product behavior, but present it with benchmark-grade fintech UX. | Do not import MOBI mobility concepts or Revolut banking claims. Translate their interaction structure into group collection flows. | `lib/features/collections/`, `lib/features/payments/`, `lib/features/settings/` | Delete docs that ask a tool to invent a new product direction from scratch. |
| Primary nav | Revolut/MOBI thumb-first bottom dock with selected capsule, stable labels, strong glass. | Bottom chrome must be black/glass, rounded, anchored, selected capsule, no generic NavigationBar look. If product scope needs more destinations, add them as real Collect equivalents, not placeholders that lie. | `lib/core/widgets/collect_shell.dart` | Delete docs that freeze older navigation rules when they block benchmark parity work. |
| Shell architecture | MOBI-style reusable shell, route matrix, responsive rail, preserved app rhythm. | Keep shell primitives centralized; migrate toward branch-state preservation when route depth requires it. | `lib/app/router.dart`, `lib/core/widgets/collect_shell.dart` | Delete docs that treat route coverage as a historical audit instead of an active contract. |
| Route transitions | Soft slide/fade/scale, reduced-motion aware, no abrupt generic route jumps. | All production routes use centralized `CustomTransitionPage` policy and `CollectMotion`. | `lib/app/router.dart`, `lib/app/theme/collect_motion.dart` | Delete docs that only discuss static screenshots and ignore motion. |
| First viewport | Revolut-style dominant amount/state/card within first view. | Home, Groups, detail, contribution, ledger, share, settings, profile, legal, offline, and recovery routes must have a clear first-viewport purpose. | `lib/features/**`, route PNG evidence | Delete docs that accept sparse empty cards as complete UX. |
| Backgrounds | Revolut vertical gradient families. | Route backgrounds map to the 11 screenshot families and never fall back to one generic dark surface. | `CollectColors.screenGradientForPath()` | Delete docs that propose alternate palettes or local route gradients as primary direction. |
| Glass surfaces | Black chrome, translucent panels, subtle borders, readable blur. | Cards, sheets, nav, action controls, search/filters use shared glass tokens. | `collect_chrome.dart`, `collect_foundation.dart`, `collect_scaffold_chrome.dart` | Delete docs that permit plain Material cards as the member-app default. |
| Typography | MOBI/Revolut rhythm: tight, compact, high-weight money/display hierarchy. | Use Collect Runtime/Display fonts, tabular numerals, zero letter spacing, compact labels. | `collect_typography.dart`, `collect_runtime_typography.dart`, `pubspec.yaml` | Delete docs that name older fallback font systems as current target. |
| Colors | Revolut/MOBI-style dark gradients plus disciplined semantic accents. | Preserve current four Collect brand colors as approved runtime accents: `#8885F0`, `#3CD070`, `#D38B96`, `#FF5E43`; use route backgrounds and glass tokens for the Revolut feel. | `collect_colors.dart`, `DESIGN.md` | Delete docs that expand the brand palette, make orange default for all CTAs, or treat Paper as a primary. |
| Icons | MOBI-style icon-led communication. | Use semantic icons for amount, members, support, group type, privacy, QR, receiver, owner, visibility, and status. | `collect_semantic_icons.dart`, `collect_runtime_tokens/` | Delete docs that encourage visible explanatory labels where an icon/state can carry meaning. |
| Cards | Revolut/MOBI compact finance cards, media-rich when useful, no blank covers. | Group cards, home cards, ledger cards, payment cards, setting rows, and modal cards use consistent shared primitives. | `collect_group_cards.dart`, `collect_financial_components.dart` | Delete docs that preserve old downloaded mockup card systems as active guidance. |
| Loading | MOBI-style consistent async handling plus shape-specific skeletons. | Use `CollectAsyncStateView`, `CollectScreenLoadingState`, and `LoadingSkeleton` variants on all primary async screens. | `collect_loading_surfaces.dart` | Delete docs that allow blank/loading spinners as the main route experience. |
| Error/empty states | Concise, actionable, icon-led, no paragraph-first dead ends. | Empty/error/recovery states use shared panels, direct action, and one-line copy where possible. | `collect_state_feedback.dart`, `collect_state_panels.dart` | Delete docs that keep long instructional prose as the default. |
| Offline/sync | MOBI `ConnectivityOverlay` awareness and visible recovery. | Offline/sync must become explicit recovery states, not generic redirects, when the product relies on network state. | `lib/app/router.dart`, state widgets | Delete docs that call redirects sufficient offline UX. |
| Permissions | Native-feeling, task-timed, recovery-oriented. | SMS, camera, gallery, notification, and platform limitations appear at the decision point with compact recovery UI. | `native_permission_sheets.dart`, scanner/create routes | Delete docs that leave permission state as generic warning copy. |
| QR/share | Revolut-style modal task focus. | QR/share screen must minimize wasted first-viewport space and prioritize QR, share/save, identity, and privacy state. | `share_screen.dart`, route evidence | Delete docs that accept decorative blank space over task efficiency. |
| Settings | MOBI/Revolut compact account hub. | Settings should be a dense account/status/action surface with clear rows, toggle state, support/legal grouping, and bottom dock continuity. | `settings_screen.dart` | Delete docs that leave Settings as a plain list without account state hierarchy. |
| Accessibility | MOBI component semantics plus Collect 200% text and privacy constraints. | 48x48 Android, 44x44 iOS, semantics/tooltips, no color-only state, reduced motion, no leaked raw phone/SMS/MoMo data. | tests, TalkBack packet, route evidence | Delete docs that claim full human accessibility signoff without current evidence. |
| Evidence | Collect must keep stronger proof than MOBI if it claims parity. | Route render smoke, design compliance audit, Android UAT evidence, static analysis, and focused tests must pass before saying code-owned complete. | `scripts/mobile_route_render_smoke.sh`, `scripts/collect_mobile_design_compliance_audit.sh`, `scripts/android_device_uat.sh` | Delete stale evidence docs that conflict with current matrix or current route counts. |
| Admin boundary | MOBI role-aware architecture is useful, but Collect member app must stay clean. | Admin remains separate from member mobile UX unless explicitly scoped; member app never exposes admin surfaces. | `lib/admin/`, `lib/main_admin.dart` | Delete docs that blur member UX with admin dashboard expectations. |
| Release wording | Internal design parity is not external filing or store submission. | External filings, public claims, legal notices, app-store submission, and other external submissions still require explicit human approval. | release docs | Delete design docs that use external approval blockers to weaken code-owned UI direction. |

## Revolut Reference Route Mapping

| Screenshot | Reference pattern | Collect route family | Required implementation behavior |
| --- | --- | --- | --- |
| `IMG_2739.PNG` | Account home, large amount, black dock, compact top controls. | `/home`, `/auth`, launch/onboarding. | Dominant RWF/collection state, compact identity, circular actions, black glass dock. |
| `IMG_2740.PNG` | Wealth/education teal surface. | `/groups/create`, `/settings/profile`, permission/recovery. | Vertical teal gradient, clear task promise, compact recovery/status panels. |
| `IMG_2741.PNG` | Payments/contact list. | `/groups`, `/groups/:id`, `/groups/:id/members`, `/c/:slug`. | Dense group/contact rows, right-aligned RWF/status, icon metadata. |
| `IMG_2742.PNG` | Asset/payment state. | Contribution, payment status, ledger. | Dominant amount, progress/status, transaction rows, direct action. |
| `IMG_2747.PNG` | Payment details/list continuation. | Group detail and member activity. | Compact support/activity rows with strong hierarchy and privacy-safe identity. |
| `IMG_2748.PNG` | Asset detail or payment progress. | Contribution review and ledger detail. | Amount-first review, verified state, concise steps. |
| `IMG_2749.PNG` | Rewards/violet action surface. | QR/share, invite, settings root. | Rich violet surface, QR/share task focus, compact action buttons. |
| `IMG_2750.PNG` | Marketplace/list card density. | Public groups and group discovery. | Media-backed group cards, no blank covers, compact metadata. |
| `IMG_2751.PNG` | Content/legal/settings dark surface. | Account, privacy, help, terms. | Dense legal/settings rows, readable text, no decorative brand-card headers. |
| `IMG_2752.PNG` | Content/details continuation. | Privacy/legal/detail routes. | Plain finance-grade header, readable panels, safe text scaling. |
| `IMG_2755.PNG` | Invest/teal-black status. | Offline/sync and system state. | Explicit recovery, network/sync state, direct retry or next action. |

## MOBI Comparator Matrix

| MOBI source | Pattern to match in Collect | Collect action |
| --- | --- | --- |
| `lib/core/router/app_router.dart` | Route constants, guarded redirects, root-navigator full-page routes, deferred heavy routes. | Keep route inventory explicit; consider deferred heavy routes and branch-preserving shell where route depth grows. |
| `lib/app.dart` | Shell owns auth/role side effects, notification sync, responsive rail, and bottom nav. | Keep Collect shell side effects minimal but centralize navigation, haptics, rail, and route background scope. |
| `lib/shared/widgets/mobi_bottom_nav.dart` | Floating black/glass dock, selected pill, semantics, tooltip, press scale/opacity. | Match tactile press feedback and selection clarity in `CollectShell`. |
| `lib/shared/widgets/mobi_top_command_bar.dart` | Compact avatar/search/action command bar. | Use equivalent top chrome only where it adds value; avoid redundant search bars on sparse primary routes. |
| `lib/shared/widgets/mobi_async_state_view.dart` | One reusable async-state renderer. | Expand `CollectAsyncStateView` usage across primary screens. |
| `lib/shared/widgets/connectivity_overlay.dart` | Debounced offline banner and safe-area awareness. | Replace `/offline` and `/sync` redirects with real recovery UI. |
| `lib/shared/widgets/loading_skeleton.dart` | Reusable loading skeletons. | Keep shape-specific Collect skeletons and require them for every route with async startup. |
| `lib/shared/widgets/mobi_state_banner.dart` | Inline status/permission banners. | Continue consolidating permission/status UI into shared components. |
| `design.md` | Fewer words, fewer competing actions, more meaning through widgets. | Enforce icon-first metadata and one-line copy in all member routes. |

## Comparative Implementation Table

| Area | MOBI evidence | Revolut reference behavior | Collect target | Collect implementation files | Gate/evidence | Contradiction handling |
| --- | --- | --- | --- | --- | --- | --- |
| Product frame | `mobi_app/design.md` pushes fewer words, grouped widgets, and stronger meaning through UI. | Financial app feels compact, confident, dark, and amount/status first. | Collect remains a Rwanda group-collections product, but the member app must feel like premium fintech, not a generic Material utility. | `DESIGN.md`, `docs/design/DESIGN_SYSTEM.md`, `lib/features/collections/**`, `lib/features/payments/**` | `scripts/revolut_parity_signoff_gate.sh --json` | Delete docs that describe Collect as a general redesign exercise or argue against benchmark convergence. |
| Shell/router | `MobiShell` uses `StatefulNavigationShell`, branch navigation, rail/bottom behavior, and centralized side effects. | Thumb-first navigation keeps context stable while moving across finance areas. | Member Home, Groups, and Settings preserve branch state and use one premium shell. | `lib/app/router.dart`, `lib/core/widgets/collect_shell.dart` | `test/app_shell_test.dart`, design compliance branch-shell checks | Delete three-tab or path-only shell guidance that blocks branch preservation. |
| Bottom dock | `mobi_bottom_nav.dart` uses floating black/glass chrome, selected pill, semantics, tooltip, and press feedback. | Black rounded dock with selected capsule and restrained labels. | Collect bottom chrome must read as black/glass fintech nav with stable selected state. | `lib/core/widgets/collect_shell.dart`, `lib/shared/widgets/collect_chrome.dart` | Route screenshots, widget tests | Delete docs that permit generic Material `NavigationBar` as the active target. |
| Responsive nav | `MobiShell` switches to rail on larger widths. | Finance apps keep hierarchy clear across phone/tablet without changing product meaning. | Collect keeps phone-first dock and uses responsive rail where shell width requires it. | `lib/core/widgets/collect_shell.dart` | `flutter test --no-pub test/app_shell_test.dart` | Delete docs that freeze mobile-only shell assumptions as design law. |
| Top command/chrome | `mobi_top_command_bar.dart` provides avatar/search/actions in compact chrome. | Circular profile/action controls with low copy. | Use compact command controls where they improve task speed; avoid duplicated search on sparse screens. | `lib/shared/widgets/collect_scaffold_chrome.dart`, feature screens | Route evidence and design compliance text scans | Delete docs requiring paragraph-first headers or large decorative top cards. |
| Background system | MOBI uses immersive dark surfaces and product-specific gradients. | Revolut uses route-specific dark gradient families. | Route backgrounds map to Collect/Revolut families and never fall back to one flat generic surface. | `lib/app/theme/collect_colors.dart`, `lib/shared/widgets/screen_scaffold.dart` | `scripts/collect_mobile_design_compliance_audit.sh --json` | Delete alternate palette documents that supersede the current gradient contract. |
| Glass/card system | MOBI groups content into reusable translucent surfaces. | Premium finance cards are compact, layered, and readable. | Member cards, sheets, nav, and action panels use shared glass and finance primitives. | `lib/shared/widgets/collect_chrome.dart`, `collect_foundation.dart`, `collect_financial_components.dart`, `collect_group_cards.dart` | Component tests and route screenshots | Delete old card-system docs that promote plain Material cards or downloaded mockup remnants. |
| Typography | MOBI favors short labels, strong hierarchy, and compact rhythm. | Revolut uses display money/status hierarchy with dense secondary labels. | Use Collect runtime/display fonts, tabular numerals, zero letter spacing, and smaller panel headings. | `lib/app/theme/collect_typography.dart`, `collect_runtime_typography.dart`, `pubspec.yaml` | `test/features/design_system_components_test.dart` | Delete old typography docs that name superseded fallback systems as current. |
| Color discipline | MOBI keeps strong accent meaning without one-note screens. | Revolut dark bases use controlled semantic accents. | Preserve four Collect brand colors as accents, with Paper only as canvas and dark glass as the dominant mobile feel. | `lib/app/theme/collect_colors.dart`, `DESIGN.md` | Design compliance color checks | Delete docs expanding the brand palette or making orange/Paper the primary mobile identity. |
| Icon language | MOBI uses icons and badges to reduce text load. | Revolut communicates metadata through compact icon rows. | Use semantic icons for money, members, privacy, QR, receiver, owner, status, and support. | `lib/app/theme/collect_semantic_icons.dart`, `docs/design/collect_runtime_tokens/**` | Semantic icon checks | Delete docs that ask for visible instructional labels where icons/state should carry meaning. |
| First viewport | MOBI surfaces the most important user state immediately. | Revolut first screens lead with amount, payment state, card, or task. | Home, Groups, detail, contribution, ledger, share, settings, legal, offline, and recovery screens all show useful content above the fold. | `lib/features/**` | `scripts/mobile_route_render_smoke.sh` | Delete screenshot reports that accepted sparse or blank first viewports as complete. |
| Loading/skeletons | `mobi_async_state_view.dart` and `loading_skeleton.dart` centralize async UX. | Finance apps avoid blank waiting screens and generic spinners. | Primary async screens use `CollectAsyncStateView`, screen loading states, and shape-specific skeletons. | `lib/shared/widgets/collect_loading_surfaces.dart`, feature screens | Design compliance async checks, `test/features/mobile_completion_test.dart` | Delete docs that allow one-off blank loading or spinner-only startup. |
| Error/empty states | `mobi_state_banner.dart` keeps state compact and actionable. | Empty/error states are short, icon-led, and action-oriented. | Use shared feedback/state panels with direct next action and minimal copy. | `lib/shared/widgets/collect_state_feedback.dart`, `collect_state_panels.dart` | Widget tests and route screenshots | Delete old long-copy state guidance. |
| Offline/sync | `connectivity_overlay.dart` gives visible network state. | Premium finance apps show recovery states when network affects money flows. | `/offline` and `/sync` render real recovery screens with retry/next actions and privacy-safe status. | `lib/features/status/connection_recovery_screens.dart`, `lib/app/router.dart` | Route screenshot evidence and compliance checks | Delete docs saying redirects alone are sufficient offline UX. |
| Permissions | MOBI uses inline banners and recovery-oriented state. | Native-feeling permission asks appear at task time. | SMS, camera, notifications, gallery, and platform limits use compact recovery UI at the decision point. | `lib/features/status/native_permission_sheets.dart`, scanner/create/share flows | Route render smoke and mobile completion tests | Delete generic warning-copy permission guidance. |
| QR/share | MOBI/Revolut task screens are immediate and focused. | QR/invite style surfaces prioritize the object and primary action. | Share route reduces blank top space, prioritizes QR/share/save, and hides private group title leakage. | `lib/features/collections/share_screen.dart` | Route screenshots and privacy checks | Delete docs that accept decorative blank space over QR task efficiency. |
| Group discovery | MOBI list/card density keeps low-data surfaces useful. | Revolut list surfaces stay dense and scannable. | Groups screen includes compact action/discovery modules even with low data. | `lib/features/collections/collections_screen.dart`, group cards | Widget tests and route screenshots | Delete docs that treat sparse low-data groups as finished. |
| Group detail/activity | MOBI uses grouped cards with clear status and action zones. | Revolut details emphasize amount/status/progress and recent activity. | Detail, members, manage, profile, contribution, and ledger screens use compact finance hierarchy. | `lib/features/collections/**`, `lib/features/ledger/**` | Mobile route render smoke | Delete older route-count docs that omit current detail subroutes. |
| Payments/contribution | MOBI/Revolut amount-first flows avoid noisy copy. | Payment review/status pages lead with amount, progress, and next action. | Contribution/payment flows lead with RWF, MoMo/USSD context, status, and support without leaking sensitive data. | `lib/features/payments/**`, collection action widgets | Product boundary and route smoke gates | Delete banking/crypto guidance that adds false product claims. |
| Settings/account/legal | MOBI account areas are compact hubs. | Revolut settings/legal screens are dense, readable, and utility-first. | Settings is an account/status/action hub; legal/privacy/help stay readable with bottom dock continuity. | `lib/features/settings/**` | Route screenshots, accessibility docs | Delete docs that leave settings as a plain unstructured list. |
| Public links/deep links | MOBI preserves shell context around guarded routes. | Shared links resolve to clear task state. | `/c/:slug`, `/invite/:publicId`, `/share/*`, and `/app` render privacy-safe link/recovery states. | `lib/app/router.dart`, `lib/features/collections/group_link_screen.dart` | Route render smoke and async compliance checks | Delete docs using obsolete compatibility routes as current route inventory. |
| Accessibility | MOBI widgets carry semantics/tooltips and compact affordances. | Premium app polish includes reachable tap targets and readable scaling. | Maintain 48x48 Android, 44x44 iOS, semantics, reduced motion, text scaling, and no color-only state. | Tests, `docs/release/NATIVE_MOBILE_ACCESSIBILITY_SIGNOFF_CHECKLIST_2026-06-30.md` | Automated tests plus blocked human signoff gate | Keep human accessibility signoff as governance, but retarget it to this matrix. |
| Privacy/data safety | MOBI side effects are centralized and scoped. | Finance UX avoids leaking sensitive numbers or account state. | No raw SMS, OTP, phone, MoMo receiver, provider token, or production customer data in UI evidence. | Scripts, docs, tests, route evidence | Boundary scans and secret handling fields | Delete old evidence that encourages raw sensitive capture. |
| Admin/member boundary | MOBI role-aware shell is useful, but Collect member app must stay member-only. | Consumer fintech apps do not expose back-office controls in the customer shell. | Admin remains separate from member mobile UX. | `lib/admin/**`, `lib/main_admin.dart`, member router | `scripts/collect_product_boundary_scan.sh --json` | Delete docs blurring member UX with admin dashboard requirements. |
| Evidence pipeline | MOBI is the comparator; Collect needs stronger proof before claiming parity. | Screenshots must match route inventory and current code. | Use current route render smoke, Android UAT, design compliance, signoff gate, static analysis, and focused tests. | `scripts/mobile_route_render_smoke.sh`, `scripts/product_design_mobile_audit_artifact_gate.sh`, `scripts/collect_mobile_design_compliance_audit.sh` | Current `.cache/mobile_route_render_smoke/*/summary.json` and `.cache/android_device_uat/*/summary.json` | Delete or retarget frozen June 26 screenshot bundles and stale completion reports. |
| Release wording | MOBI/Revolut parity is a code-owned internal design target. | Public/store/accessibility claims require real approval. | Keep external submissions and maximum accessibility claims blocked until explicit human approval. | Release docs and signoff scripts | `native_mobile_accessibility_signoff_gate.sh --json` | Do not use external approval blockers to weaken the code-owned UI target. |

## Current Gap Table

| Severity | Gap | Why it blocks 100% feel | Required fix | Current status |
| --- | --- | --- | --- | --- |
| P0 | Contradictory active design docs exist beside the source of truth. | Engineers can follow stale three-tab/no-parity/no-go docs instead of the current benchmark. | Delete old active design reports and keep this single matrix plus `DESIGN.md` and `DESIGN_SYSTEM.md`. | Implemented: active stale design/release UX artifacts are deleted or retargeted; current gates reject the old June 26 screenshot bundle as source of truth. |
| P1 | Offline/sync routes redirect instead of showing recovery. | MOBI has real connectivity awareness; Revolut-grade finance apps do not hide network state. | Build explicit offline/sync screens with state, action, and route evidence. | Implemented: `/offline` and `/sync` now render explicit recovery screens with `CollectConnectivityBanner`, action rows, privacy-safe copy, route screenshot evidence, and gate checks. |
| P1 | Share route has too much blank first-viewport space. | Task screens must feel immediate and useful. | Raise QR/sheet task content and reduce decorative empty area. | Implemented: share no longer uses spacer-only blank top space, QR content is first-viewport focused, and privacy-safe QR context is enforced without visible group-title leakage. |
| P1 | Groups can feel sparse with low data. | Revolut/MOBI list surfaces stay visually dense even with little data. | Add richer empty/low-data state and compact discovery/action modules. | Implemented: low-data groups now show a compact `Groups quick actions` strip for scan/create/supported actions, covered by widget test and design audit. |
| P1 | Current shell is path-selected, not branch-preserving. | MOBI's shell better preserves native tab mental model. | Move to `StatefulShellRoute.indexedStack` when tab stacks deepen. | Implemented: member Home, Groups, and Settings now run inside `StatefulShellRoute.indexedStack` branches with explicit initial locations; `CollectShell` drives selection from `StatefulNavigationShell.currentIndex` and switches tabs with `goBranch`. |
| P2 | Some screens still use local state/loading instead of one async pattern. | Users feel inconsistent startup/error behavior. | Consolidate on `CollectAsyncStateView` and shape skeletons. | Implemented: primary screens use route-specific `CollectScreenLoadingState`, group members and public group-link recovery use `CollectAsyncStateView`, and the compliance gate blocks one-off member-route loading/error fallbacks. |
| P2 | Old release/design evidence mentions older route counts and old decisions. | Stale docs create false confidence or false blockers. | Delete or retarget references to this matrix. | Implemented for current references: stale design/release artifacts were deleted or retargeted; current gate uses fresh route and Android evidence paths when supplied. |

## Required Current Evidence

| Gate | Required status before claiming code-owned alignment | Command/source |
| --- | --- | --- |
| Static analysis | Pass | `/Volumes/PRO-G40/flutter_3_44/bin/flutter analyze --no-pub` |
| Design compliance | Pass | `scripts/collect_mobile_design_compliance_audit.sh --json` |
| Route screenshots | Pass for every production member route | `scripts/mobile_route_render_smoke.sh` |
| Android UAT | Pass or current blocker summary | `scripts/android_device_uat.sh` |
| Focused tests | Pass for changed shell/design/docs | `test/app_shell_test.dart`, `test/features/design_system_components_test.dart`, `test/release_docs_test.dart` |
| Matrix consistency | Pass | `scripts/revolut_parity_signoff_gate.sh --json` |
| Product boundary | Pass | `scripts/collect_product_boundary_scan.sh --json` |

## Deletion Register

Delete design docs that conflict with this matrix after any still-current fact is merged here, `DESIGN.md`, or `docs/design/DESIGN_SYSTEM.md`.

| Delete class | Why |
| --- | --- |
| Historical parity evidence/signoff packets | They encode old NO-GO or old human-signoff framing as active design guidance. |
| Blocker registers that weaken the current code-owned direction | The matrix is the blocker/gap register now. |
| Stitch/open-ended redesign briefs | They invite a tool to invent a design direction instead of matching MOBI/Revolut. |
| Old downloaded-screen goalbooks | They preserve older Buro/crypto/remix guidance and three-tab assumptions. |
| Old typography/color/research docs | They contain superseded palette/font/reference boundaries. |
| Previous weak MOBI comparison outputs | They argued against visual convergence and are superseded by this table. |

## Active Deletion Decision

The following active files or folders are superseded and must stay deleted:

- `docs/release/product_design_mobile_audit_2026-06-26/`
- `docs/release/COLLECT_PREMIUM_MOBILE_FRONTEND_COMPLETION_REPORT_2026-06-27.md`
- `docs/release/CRITICAL_NATIVE_MOBILE_EXPERIENCE_AUDIT_2026-06-29.md`
- `docs/release/MOBILE_ON_DEVICE_QA_REPORT_2026-06-30.md`
- `docs/release/MOBILE_SCREEN_ROUTE_UAT_REVIEW_2026-06-30.md`
- `docs/design/ANDROID_TALKBACK_REVIEW_PACKET_2026-06-29.md`
- `docs/design/COLLECT_MOBI_REVOLUT_REPO_LEVEL_IMPLEMENTATION_TABLE_2026-07-02.md`

They are not retained as active guidance because they preserve stale route
counts, old NO-GO wording, frozen screenshot evidence, pre-parity design
direction, or a second design authority beside this matrix. Current evidence
must come from fresh route-render and Android UAT artifacts.
