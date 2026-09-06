# Collect: Revolut reference implementation, 5 September 2026

Status: local candidate implemented and tested; design acceptance incomplete.
**100% fidelity is unverified. Production mobile acceptance remains blocked.**

## Scope and source

The owner's request covers the native mobile app, Admin panel, generated public
website and corresponding Flutter public shell. The installed
`/Users/jeanbosco/.codex/skills/revolut-design/SKILL.md` and its own-brand
adaptation rule govern this work. Collect's existing names, logo, geographic
payment rails, copy, permissions and backend behavior are retained.

| Target | Named reference | Comparator and limits |
|---|---|---|
| Mobile Home | Owner's Desktop cohort, DESK-003 | Blue Home component/pattern treatment; existing Collect balance, commands and density retained. |
| Mobile Groups | DESK-004 Invest | Teal colour/component comparator only; existing group list, membership and operations retained. |
| Mobile Activity | DESK-005 Payments | Purple list/component comparator; Collect activity records and actions retained. |
| Mobile Profile overview (`/settings`) | DESK-007 rewards | Vivid violet/blue colour/component comparator; existing identity and settings retained. No rewards feature added. |
| WhatsApp authentication | DESK-001 passcode | Blue-indigo colour comparator; existing phone/WhatsApp verification form, provider and sequence retained. |
| Focused tasks and Appearance | Neutral live cohort: LIVE-005/007/009/060 | Neutral black canvas and grouped widgets. Inter remains a provisional native typography adapter. |
| Admin overview, lists and details | Official Revolut Business 5 imagery, including `assets/public-business/bills-preview.png`; https://www.revolut.com/business/rb5/ | Component/pattern comparison only. These images do not establish complete authenticated table geometry, all desktop states or exact fidelity. |
| Public home | September 2026 UK public homepage, https://www.revolut.com/ | Live measured marketing typography and collected photographic composition. Full live browser screenshot comparison was unavailable because the source browser showed human verification. |
| Public details/legal and share links | Same public-web component vocabulary | Adapted content layouts and recovery states; no direct source comparator for Collect-specific content. |

The reference root is `/Users/jeanbosco/Documents/ChatGPT/Revolut`. Private
reference screenshots stay there. Public artwork and font provenance is recorded
in `assets/marketing/SOURCE.json`; the product logo manifest remains authoritative.
The app name remains Collect; no source wordmark, app icon or branded product
artwork was installed. Existing references to Revolut as a real payment option
are product content, not a rebranding.

## Changes

- Shared mobile/Admin tokens now use the selected neutral black/#161618 roles;
  quick actions are tonal and grouped panel backgrounds are consistent.
- Appearance's miniature Home uses the same chrome and action tokens. Its final
  updated golden was opened and reviewed separately after the native review
  exposed a stale preview fill.
- Shared screen headings wrap rather than shrinking; secondary labels and
  table text use restrained weights. Focus borders remain visible.
- Admin uses Collect's own logo, pill selection, semantic selected state,
  neutral tables, search and empty-state components.
- Marketing uses the collected Aeonik Pro Regular/Medium faces, with 48/48
  phone and 84/84 desktop headline roles, pill controls and the public
  photographic composition. Inter remains the mobile/Admin font adapter.
- The static site's navigation supports focus containment, Escape, focus return,
  background inertness, menu-link dismissal and resize recovery. Legal/share
  routes retain their own content and destinations.
- At 320 CSS pixels, hero grids, phone illustration containers and legal content
  reflow within the viewport. This fixes observed clipping without hiding text
  or disabling horizontal-overflow checks.

## Reviewed content and baseline changes

Product and legal copy were compared with a separately generated HEAD-version
static site. The full diff is
`.cache/revolut-design-20260905/website-content-diff.txt`.
All 16 route headings, introductions and body content are preserved. The public
home's illustrative phone, with sample time/balance/member records, is replaced
by the editorial photograph. A responsive menu adds a desktop-only duplicate of
the Get the App CTA. Content checks normalize only this exact duplicate; all 15
non-home content hashes are unchanged. The home hash changes only for removal
of the illustrative phone. No legal, service or provider-boundary copy is waived.

All 13 changed Flutter golden images were opened and visually reviewed by the
implementing agent before baseline refresh: member authentication, Home, Groups,
Contribute entry, Activity, Profile, Group Detail, contribution review, Ledger,
offline recovery, Appearance, Admin overview and public home. Member images are
390×844; Admin/public are 1440×900. The public golden explicitly preloads its
photographic assets and font faces; the final review includes restored original
Collect copy. Updated images establish local regression expectations only.
They do not establish owner approval, native artifact acceptance or 100% fidelity.

## Palette follow-up and native capture diagnosis

The initial pass reused a purple Groups background and neutral Profile/login
surfaces. The current skill explicitly maps those existing routes to teal,
violet/blue and blue-indigo. These mismatches are now corrected through shared
semantic tokens. Overview grouped panels follow their route family; the colour
wash scrolls away with content. Focused descendant tasks remain neutral.

All five supplied originals were opened. Their embedded colour profile is
**HP 524sf**; reading raw RGB bytes does not reproduce the displayed colour.
Measurements now convert that profile to sRGB with LittleCMS, preserving every
original file. Coordinates, raw/converted samples, hashes and panel samples
are in `REVOLUT_PALETTE_MEASUREMENTS_2026-09-05.json`. Native DPR, source build
and exact font provenance remain unknown.

Old product-palette colours were removed from app/Admin/web styling, generated
group covers, export surfaces and Android launch/notification colours. Saved
legacy group colour values are mapped only for display. Four edit-and-save
regressions prove that a name edit preserves each original colour value. Own
logo and icon pixels remain unchanged. Source hygiene now rejects returning
old UI colour literals; only the four explicit saved-data mapping keys remain.

The new `integration_test/mobile_design_review_app.dart` is an interactive
synthetic target guarded to non-release `dev` builds with explicit evidence
mode. It uses the normal Android rendering surface, with no integration-test
surface conversion. UI identities are checked immediately before and after
framebuffer captures. Installed APK bytes are checked against the candidate.

**Correction to the preliminary rendering finding:** the agent initially
misread reduced full-screen previews as missing navigation/search content.
Reopening detail crops shows the content in the original files. The four
navigation regions are pixel-identical across the two isolated emulators;
the 2.0× Groups and Activity search-label regions are also pixel-identical.
The historical instrumented Settings crop contains all four navigation icons
and labels. No missing-glyph app or integration-renderer defect is established
by these files. Wrong-route log-timed captures remain rejected. Original images
are preserved; inspection crops do not replace them.

The 2.0× light-theme native run did expose a separate, reproducible issue:
white status-bar icons remained over the pale canvas. The system-bar annotation
now uses the resolved runtime theme, including System mode. Android UI trees
also exposed missing assistive tap actions in shared account list tiles and
the group chooser. Those actions and group-type choices now invoke the same
callbacks through semantics. Regression tests exercise actual confirmation,
navigation, selection and theme changes.

Current public control evidence `WEB-STATE-001` supplies the marketing CTA's
#1F1F1F paint, 0.85 hover opacity, 16/22 Aeonik control type, blue/white keyboard
focus rings and transition curves. The static website now follows those states.
Collect retains its 44 CSS-pixel minimum target (the observed source is 42px),
forced-colour focus and reduced-motion behavior. Public SSO variables and POS
images are kept in their source contexts, not treated as native or authenticated
Admin tokens.

The comparison register now records the full colour-role scope: overview and
authentication, neutral/tonal surfaces, text/icons, actions, overlays/menus,
selection/focus/validation, semantic statuses, loading/recovery, themes,
customisation, web and PWA lifecycle. The five named mobile families are examples,
not a coverage limit. Current native success/light/interaction and authenticated
Admin source gaps remain explicitly unverified.

The earlier runs below remain historical evidence and are not current native
acceptance for the changed palette and accessibility fixes.

## Earlier verification (before the explicit palette follow-up)

Evidence is retained under `.cache/revolut-design-20260905/`. Checks and remaining
findings are recorded below. No physical-phone data,
production repository fixture behavior, payment control or production service
was changed by this work.

| Check | Actual result and scope | Evidence |
|---|---|---|
| Full Flutter suite | 631 passed; one stale assertion expected the retired single-font gate ID. That assertion was updated to the new surface-scoped ID and its targeted rerun passed. All 632 cases have passing evidence across those runs. | `full-tests.log`, `security-rerun.log` |
| Final Appearance correction | 74 interaction, completion and golden tests passed after the final preview correction. | `preview-regression-final.log` |
| Dart analysis | No issues after the final preview correction. | `analyze-verified.log` |
| Source hygiene | Pass; own-logo hash, approved assets, font scope, fixture isolation and product boundaries retained. | `source-hygiene.json` |
| Reference integrity | Pass: 876 collection records, 1,397 historical raw token declarations, 184 recent media entries. This verifies the reference bundle, not Collect fidelity. | `reference-integrity.log` |
| Admin browser | 23 routes × 3 viewports = 69 passing captures, named controls, measured targets, keyboard and semantic checks. The old Members “WhatsApp” column assertion was corrected to the existing “Account / contact” header, reflecting feature-phone members. | `admin-final/admin_browser_qa.json` |
| Public route browser | 16 routes × 3 viewports, share-link states and phone/tablet menus: 92 captures, all checks pass. | `website-routes-verified/route_rendered_qa.json` |
| Public compact accessibility | Home, privacy and group savings at 320×740, normal/forced colours with reduced motion: all 6 checks pass. Browser text zoom was not measured. | `website-accessibility/report.json` |
| Public build/content | All 56 checks pass. The home illustration delta is documented above; all product/legal copy is retained. | `website-quality.json` |
| Native default routes | Final Android fixture run: 42/42 routes passed, with 42 screenshots. Source fingerprints are identical before and after the run. Corrected Appearance preview inspected in the final native capture. | `android-routes-verified/summary.json`, `android-routes-verified/candidate.json` |
| Native material states | 31/31 states passed at 1.6× text, high contrast and reduced motion. All 31 primary images and 7 additional scroll/discovery images were visually inspected, using original detail views and inspection sheets. This does not stand in for the contract's 2.0× variant. | `android-states-accessible/summary.json`, `inspection-sheet-1.png` through `inspection-sheet-4.png` |

Native runs use the separate `app.cool.mobile.dev` package on `emulator-5554`,
Android 16/API 36, physical screenshot size 1080×2340 and density 440 dpi.
They contain synthetic test repositories. The physical Pixel and the existing
production app's signed-in store were not used for these tests. The state run
precedes the final Appearance preview-only correction; that screen is covered
by the later 74-test regression and final route candidate.

The preliminary interpretation of the Settings instrumented image was
withdrawn after original-detail inspection, as recorded above. Mismatched
framebuffer captures remain inadmissible. No historical fixture image supplies
owner acceptance or establishes the full production artifact matrix.

The design contract remains valid; its 33 gate tests and 131 assertions pass.
The production acceptance gate remains blocked, as required.

## Comparison and operational record

`revolut-surface-comparisons-2026-09-05.json` enumerates all 134 required mobile
cases, 69 Admin route/viewport cases and 48 public route/viewport cases. It
distinguishes fixture runtime results from fidelity. No row has been promoted
to a 100% visual pass based on a screenshot or checklist count.

| Criterion | Procedure / observed result | Status | Responsible role / closure |
|---|---|---|---|
| F01 / R001, R009, R010: product scope | Repository routes, own-logo hash, terminology and the old/new public content diff checked; actual payment rules retained. | Pass for implemented scope | Product/engineering: retain this boundary in subsequent work. |
| F02 / R002–R008: evidence provenance | Exact selected native originals and Business/public artwork opened; source paths and hashes recorded. Native source build/region/scale and full authenticated Admin comparator remain unknown. | Unverified for complete fidelity | Design: supply or capture missing exact comparator states and metadata. |
| V02 / R021–R030: typography | Collected public fonts loaded in runtime and goldens; member/Admin Inter remains an explicitly provisional native adapter. | Unverified for exact native type equivalence | Design: establish native font and metrics from authoritative evidence. |
| A02 / R029, R030, R048, R073, R094: reflow | Native 1.6× state run and 2.0× widget interaction coverage; public 320 CSS px checks pass. Full native variant matrix and browser text zoom remain open. | Unverified for complete scope | Accessibility/QA: finish the exact matrix on the candidate. |
| A03 / R044, R045, R047, R049, R050, R074, R092: focus | Real Tab/Shift-Tab/Escape menu containment and recovery, Admin record/navigation/dialog keyboard procedures pass. | Pass for tested browser paths | QA: preserve the existing route matrix. |
| F03 / R051–R060, R069, R070: recovery | Fixture auth validation, payment review, missing groups, offline/sync, permissions and deletion-confirmation states exercised. No real payment or deletion submitted. | Pass for fixture procedures; live outcome unverified | QA/operator: controlled candidate UAT with admissible identities and data. |

## Remaining acceptance work

`MOBILE-DESIGN-100` still returns **blocked**, with no numerical score. Its 134
required case-acceptance records and 22 owner-annotation closures are not approved
and bound to the current production APK/AAB. The gate also reports missing or
stale source/contract/reference/version and release-build bindings. Fixture
screenshots cannot replace those requirements. No required case, criterion,
threshold or approval condition was removed.

Full authenticated Admin comparisons, exact native typography, all native
variant/keyboard states, actual assistive-technology use, installed-PWA
session/offline/update behavior and production performance remain unverified.
The live website source presented a human-verification screen in the browser;
available collected imagery and computed metrics were used without bypassing it.

The five quality results remain independent:

- **Visual fidelity:** improved and locally reviewed; full equivalence unverified.
- **Task usability:** fixture and browser procedures above pass; real financial
  outcomes were outside these design-only tests.
- **Accessibility:** tested subsets pass; complete assistive-technology and
  variant acceptance remains open.
- **Performance:** no production profiling result; debug emulator jank is not a
  production benchmark.
- **Runtime resilience:** fixture recovery checks pass; installed PWA and live
  operator/session recovery need their own evidence.

Deployment: **not performed**. Owner/partner acceptance: **not granted**. These
results are a local QA candidate and evidence record, not a production GO.

## Final follow-up verification

This record supersedes the earlier palette and provisional rendering findings.
The final source fingerprint is
`4f3234305fee179a809bf4af074858d78264f57c3bc8fbe9ae196f56c28f8714`.
The isolated `app.cool.mobile.dev` APK, version `1.2.4+23`, is
`622c6555cd8e52fafaa525538d54805a1ee31a8970be8fea4881c1810ba3e234`.
The QA target has its own recorded hash. This is a debug fixture APK and is
not a production APK/AAB acceptance record.

| Check | Final result | Evidence under `.cache/revolut-design-20260905/` |
|---|---|---|
| Full Flutter suite | **642 passed** after the palette and accessibility corrections | `final-full-tests.log` |
| Focused regressions | **110 passed**; includes unchanged saved group colours, semantic account confirmation, group chooser navigation, group-type selection and runtime system-bar theme changes | `native-accessibility-regressions-complete.log` |
| Analysis | **No issues** | `final-analyze.log` |
| Admin browser | **69 passing route/viewport captures** from the palette build; the later mobile-only fixes do not change used Admin components | `admin-palette/admin_browser_qa.json` |
| Website browser | **92 passing captures**, plus current pointer hover, real Tab focus, forced colours and reduced-motion checks | `website-final/route_rendered_qa.json`, `website-final/control-states.json` |
| Website quality | **56 checks pass** | `website-final/quality.json` |
| Native artifact | Source unchanged across build; installed APK hash matches exactly on isolated `emulator-5558` | `native-verified/candidate.json`, `native-verified/installed-apk.json` |
| Native target rendering | **14 captures**: five main dark families, Appearance, return navigation, account/sign-out and five light-mode captures at **2.0×** text. Current main-screen content is pixel-identical to the previously reviewed palette captures. | `native-verified/summary.json`, `native-verified/default-visual-continuity.json` |
| Native accessibility corrections | Light status icons are visibly dark; account rows expose native clickable semantics; group selection opens the amount field with the keyboard at 2.0×. The blank amount keeps Continue disabled. Fixture sign-out returns to the blank WhatsApp form. | `native-verified/large-text-light/`, `native-verified/account-flow/`, `native-verified/screenshots/auth.png` |
| Native runtime | No Flutter/fatal errors in the current app process; font scale restored to 1.0 | `native-verified/summary.json` |
| Source hygiene / whitespace | Pass; original logo remains unchanged, obsolete UI palette is rejected and only explicit legacy data bridges remain | `source-hygiene-final.json`; `git diff --check` |
| Production design gate | **Blocked: 165 failures, no score**. Case approvals, owner-annotation closures and current production artifact bindings remain required. | `mobile-design-gate-final.json` |

The public review gallery is `http://collect.localhost:4191/`; it presents local
native/browser captures, not an installed or publicly deployed product. Source
references remain private. These checks do not establish unseen native light,
high-contrast, success/loading/focus colours, exact native font metrics, complete
authenticated Admin source parity, or full production accessibility/PWA acceptance.
The 22 owner annotations and all case approval requirements remain intact.
No real OTP, payment, production data change, release approval or distribution
was performed.
