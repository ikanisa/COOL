# MOBILE-DESIGN-100 audit and implementation

Status: **NO-GO for distribution. Rule and local corrections implemented; native release acceptance incomplete.**

Owner: Jean Bosco. Reviewer: Codex. Audit date: 2026-09-03 UTC / 2026-09-04 Kigali.
Repository baseline: `474fc32a`; changes remain uncommitted. This is a mobile
design audit, not a new production backend, payment, or store certification.
Repository: `/Volumes/PRO-G40/COOL`; evidence paths below are relative to it.

## Current native surfaces

Actual isolated Android captures after restoring the route-scoped reference
depth and floating navigation. This is local QA, not installed production acceptance.

![Current native mobile surfaces](</Volumes/PRO-G40/Agents/Codex/2026-05-15/Codex Professional Agents/desktop-output/flutter/collect-mobile-design-2026-09-03/mobile-surfaces.png>)

## Native before / after: financial readability and sign-in

These are actual Android fixture captures at 320dp / 200% text, normalized
side-by-side for inspection. In the first panel the leading `1,` in `1,234`
was scrolled out of view; the corrected field presents the full value. The
sign-in pair shows the corrected multiline button padding and alignment.

![Native Android amount and sign-in comparison](</Volumes/PRO-G40/Agents/Codex/2026-05-15/Codex Professional Agents/desktop-output/flutter/collect-mobile-design-2026-09-03/amount-auth-before-after.png>)

## Plan

1. Install a permanent repository rule and fail-closed distribution gate.
2. Capture the current mobile route matrix in a separate fixture-only Android
   app/emulator; preserve the user's physical phone and production data.
3. Review the route captures, Revolut references, and owner annotations.
4. Correct shared components and all affected membership/geographic states.
5. Test annotation regressions, compact/large-text layouts and interactions.
6. Build a candidate and collect fresh native evidence; do not distribute or
   declare GO until the acceptance record is complete and bound to that build.

## Why the installed app diverged

The reviewed public-group cards and the signed-in member list used different
components. Joining a public group removed it from discovery, then rendered it
through the plain member panel. Thus the same user could lose the reviewed card
design without a deployment failure. In addition, the installed 1.2.4+23 APK
matched an older local build, not every subsequent source edit. Old parity
completion documents also pointed at an Admin-only review. These are three
different failures: state coverage, build identity, and acceptance provenance.

A fourth cause was found during original-reference comparison: the shared
`CollectGradientBackground` had become a solid fill, and a source regression
test explicitly required that everywhere. That blanket rule contradicted the
reference standard. It is now replaced by central, route-scoped overview
tokens: account-blue Home, purple Groups/Activity, neutral task/detail pages,
light equivalents and solid high-contrast fallback. Phone navigation is now a
floating pill with selected-state feedback, at least 48dp targets, reduced-motion
support and labels that adapt without clipping. No product route was added.
The Appearance preview also consumes the same backdrop and navigation roles,
with explicit dark/light/high-contrast interaction tests, so its preview no
longer advertises the obsolete shell.

The physical installation was inspected read-only. It was not replaced, signed
out, uninstalled, cleared, or used for fixture/destructive tests in this audit.

## Permanent blocker implemented

`AGENTS.md` makes `DESIGN.md` / **MOBILE-DESIGN-100** mandatory for future work.
The JSON contract is a test/evidence inventory, not a competing design authority.
The gate requires all ten fixed criteria at 10/10 for every required case. It
does not calculate a cosmetic score from passing tests.

- 42 route entries, 30 additional states, 56 viewport/theme/accessibility
  variants and six keyboard cases: **134 required cases per platform**.
- 22 browser-annotation checks and ten supplied Revolut reference images.
- Current source, contract, reference and version hashes; actual native capture
  and comparison PNGs; installed APK/IPA identity; review notes and dates;
  interaction and accessibility evidence; no open findings.
- Original reference PNGs are mandatory for distribution, with checked hashes
  and dimensions. Each native comparison must name its original reference IDs.
  CI can validate the tracked reference manifest without accessing private pixels.
- Production wrappers record fresh APK+AAB or IPA build provenance and refuse
  source changes during the build. Fixture evidence cannot approve a release.
- Play upload, TestFlight upload, App Store submission and the mobile release
  gate invoke this check. CI validates the contract and regression-tests it.
- There is no skip, waiver, auto-approval or automatic golden-update option.
  Local QA builds remain possible while distribution is blocked.
- Historical GO documents now carry a warning; the prior Admin report is
  preserved separately. `design-qa.md` is the current blocked mobile index.

This is a repository release control, not a claim that an unrelated manual
upload outside these scripts is technically impossible.

### Original reference recovery

The ten tracked `references/revolut10/*-drive-preview.png` files are screenshots
of full browser previews. They are not the original 1170 × 2532 phone captures
and cannot establish pixel fidelity. The ten originals were recovered from
the owner's authenticated Google Drive; their source URLs, dimensions and
SHA-256 values are in `original-reference-manifest.json`. The original pixels
remain in ignored `.cache/design-parity-20260903/reference-originals/`, because
they include personal financial/contact details. None was added to Git or
published. The browser-preview comparison was rejected and replaced by an
original-to-native diagnostic comparison.

The original Home/Invest/Payments/Crypto/Rewards screens establish depth,
navigation, hierarchy and spacing—not permission to invent unsupported Collect
financial products. Current annotation-approved copy, identity and local rails
remain intact. Reference comparison prompted the shared-shell changes above;
it did not produce fabricated 100/100 acceptance scores.

## Journey review and implementation

All evidence below was captured during this audit in an isolated Android 16 /
API 36 emulator, package `app.cool.mobile.dev`, using deterministic fixtures.
Native Flutter integration captures are not browser screenshots. A separate
ADB compositor Home capture includes Android system chrome. Neither is proof
of the exact production APK's behaviour.

| Step | Surface / health | Findings and changes | Remaining evidence |
| --- | --- | --- | --- |
| 1 | Sign-in — locally improved | Country-aware phone validation retained. Native 200% review exposed clipped action labels; buttons now expand vertically and regression tests assert full label containment. The corrected native run shows full Send / Verify action labels. OTP states use a fake gateway only. | Real OTP delivery and TalkBack; OTP auto-scroll/error visibility still needs end-to-end review. |
| 2 | Home / discovery — corrected locally | Member and public groups now share the reviewed coloured-card presentation. Discovery, all-joined, mixed, empty, loading, error and offline variants tested. Dynamic Contribute / Contribute & Join preserved. Wide-grid cards have a usable fixed extent. | Exact release candidate on signed-in phone; complete variant matrix. |
| 3 | Groups / detail / management — improved locally | Removed redundant category labels, duplicate management hero and verbose share metadata. Group profile presents the actual payee; Save enables only for valid changed fields. Destructive confirmations retained. | Native camera denied/retry, actual join transitions, keyboard and back/unsaved-state coverage. |
| 4 | Rwanda / diaspora contribution — corrected locally | Correct country/rail routing retained. Zero/invalid amount and duplicate in-flight submission are blocked. At 320dp/200%, a native capture showed `1,234` visually truncated to `234`; currency now moves above the amount and measured text fits the complete formatted value. Quick picks remain 1,000 / 2,000 / 5,000 / 10,000. | Actual release build, native keyboard, pending/failure/recovery and provider hand-off. No payment was initiated. |
| 5 | Profile / account / settings — improved locally | Existing numeric-ID-only profile and WhatsApp brand icon retained. Compact headers and rows replace noisy explanatory banners. Notifications remain actionable via semantics. Bank details are stacked for small screens. Account sign-out confirmation and essential security warnings remain. | Full native light/landscape/tablet/large-text states and screen-reader traversal. |
| 6 | Permissions / safety / recovery — corrected locally | Consent facts are not treated as disposable copy. A clipped SMS explanation found in native screenshots was replaced with a complete scrollable sheet; Not now performs no permission request. Empty-state headings wrap at large text. | Full-sheet scroll/readback on final build, real permission deny/retry and screen readers. |
| 7 | Navigation / release handoff — improved and guarded | Four stable destinations: Home, Groups, Activity, Profile; reference-style floating pill, selected-state fill, consistent icon identity, minimum 48dp targets and reduced-motion support. Release scripts reject stale, incomplete, Admin-only, preview-only or non-native evidence. | Fresh controlled production build and all 134 accepted cases per target platform. |

### Route coverage inspected

42/42 route harness entries rendered and were visually inspected in the first
post-fix native pass. This is first-viewport coverage, not 42 completed user
journeys or an accessibility approval. Some routes are aliases/redirects.

| Family | Captured route IDs |
| --- | --- |
| Entry / home / discovery | root-redirect, root-signed-in, home, groups, contribute-entry, auth |
| Group / contribution | group-detail, contribution, public-buri-momo, diaspora-contribution, diaspora-public-buri-momo, diaspora-bank-transfer, group-create, group-profile, group-scan, manage, members, ledger, activity |
| Sharing / joining | invite, share, app-share-entry, app-invite-link, shared-group-link, share-expired, share-expired-request, share-invalid |
| Profile / settings | settings, profile-edit, account, account-delete, settings-notifications, settings-permissions, settings-appearance, settings-security, settings-bank-transfer |
| Legal / help / recovery | legal-privacy, legal-terms, privacy-alias, help, offline, sync |

Invalid/expired share fixtures currently exercise the safe redirect destination;
they are not evidence of payment error handling. Scanner fixture fallback is
not a camera permission/device test. Legal text was checked for layout, not
re-certified for legal sufficiency.

### Additional state captures

29/29 default-dark states passed: seven Home states; phone empty/valid,
confirmation, OTP empty/invalid; Rwanda amount empty/valid/invalid/quick-pick/
review; bank amount invalid/valid/review; empty groups/activity; account-delete
disabled/enabled/confirmation; SMS consent; missing group; offline/sync recovery.

The 320dp/200% text/reduced-motion run also rendered all 29 states. Crucially,
visual inspection found defects despite its green render result. The later
`compact-large-text-states-final-r2` run passed 29/29; every saved capture was
inspected. It confirms full RWF/EUR values and uncut auth action labels. It
also exposed headings still inheriting a one-line limit: explicit multi-line
limits and a smaller semantic review heading at large text were added next.
Their final native readback is tracked separately below.

`final-native-routes-r2` passed **42/42**, and
`compact-large-text-states-final-r3` passed **29/29**. All 71 captures were
inspected, confirming the corrected amounts, auth actions and complete headings.
These precede the final reference-shell restoration; subsequent shell captures
are separately recorded rather than being conflated with those earlier passes.

The OTP-empty and quick-pick captures show a scrolled viewport, not an accepted
top-of-page reference comparison. SMS/delete sheets extend below the first
viewport at 200% and need scroll-to-end proof. These captures remain diagnostic
evidence; they do not close release acceptance cases.

## Evidence and validation

Evidence root: `.cache/design-parity-20260903/` (local, not tracked).

| Evidence | Meaning |
| --- | --- |
| `before-native/` | 42 native baseline route captures / passing harness. |
| `after-native/` | 42 native route captures / passing first post-fix harness. |
| `after-states/` | 29 default-dark state captures / passing harness. |
| `compact-large-text-states-r2/` | 29 compact 200% captures; exposed amount truncation and action clipping. |
| `compact-large-text-states-final/` | Failed quick-pick interaction run (7/29), retained for traceability. |
| `compact-large-text-states-final-r2/` | **29/29 passed**, all captures inspected; full amounts/auth buttons verified, further heading corrections identified. |
| `final-native-routes-r2/` | **42/42 passed**, all captures inspected after the heading fixes. |
| `compact-large-text-states-final-r3/` | **29/29 passed**, all captures inspected; final heading and amount/auth fixes verified. |
| `shell-tests-r2.txt` | **67 passed**: scoped backdrop, minimum native navigation targets, reduced-motion, member/discovery, light mode and runtime component checks. |
| `reference-shell-native/` | **42/42 passed**, all screenshots inspected after restoring overview depth and floating navigation. |
| `reference-shell-large-text/` | **29/29 passed**, all captures inspected at 320dp / 200% text / reduced motion. |
| `reference-shell-final-native/` | **42/42 passed** after the Appearance correction. 41 PNGs are byte-identical to the already inspected shell run; the changed Appearance PNG was separately inspected. |
| `interaction-tests-shell-final.txt` | **13 passed**, including dark/light/high-contrast Appearance interactions. |
| `all-tests-verified-final-r2.txt` | **601 tests passed** on the final source. |
| `analyze-verified-final-r2.txt` | **No issues found** on the final source. |
| `contact/shell-golden-1..4.png` | Eight before/after baseline pairs inspected before the scoped-shell refresh. |
| `contact/routes-*.png`, `contact/states-*.png`, `contact/large-*.png` | Labelled comparison/contact sheets, not pixel-similarity scores. |
| `home-after/` | Focused Home layout/state images. |
| `native-home.png`, `native-home.xml` | ADB compositor screenshot and UI tree of the isolated interactive app; empty fixture state, not production user data. |
| `all-tests-final.txt` | 593 tests passed before the final sign-in regression was added. |
| `all-tests-final-r2.txt` | Intermediate failure: an older test pinned exactly two action-label lines; replaced with the readability requirement plus real containment assertions. |
| `all-tests-final-r3.txt` | **594 tests passed**, including final auth, full-value amount, notification semantics and SMS consent regressions. |
| `all-tests-final-r4.txt` | **595 tests passed**, including the explicit non-truncating heading regression. |
| `analyze-final-r2.txt` | **No issues found** after the sign-in adjustment. |
| `analyze-final-r3.txt` | **No issues found** after the final heading changes. |
| `release-gate-result.json` | Expected blocked distribution check, not a passing release result. |

The release gate regression suite passed **33 tests / 131 assertions**. It
rejects missing/partial scores, missing or altered screenshots, stale sources,
references and artifacts, web captures masquerading as native, missing
annotation checks, unsupported bypass flags, future review dates and missing
build provenance. Shell/Ruby syntax and diff checks are also required.
It additionally rejects missing/substituted original references, changed
dimensions/manifests, unmapped comparisons, and leaf artifact symlinks, while
supporting the controlled Android wrapper's external output-directory layout.

The final Appearance foreground refactor names the existing paper-on-dark
navigation colour as a semantic token; it does not change pixels. Final unit,
golden and analyzer checks cover it. Native screenshots remain diagnostic
fixture evidence, not claims of exact release-artifact/source acceptance.

The historical evidence checker passes its source-only CI check. Its wider
available-artifact check correctly fails: old coverage markers and August 20
artifact hashes do not match the current local files. Those old checksums were
not rewritten to create an approval. This reinforces EXACT-NATIVE-CANDIDATE.

Eight of thirteen golden baselines were updated only after side-by-side visual
inspection: Home, Groups, contribute entry, Activity, group detail, ledger,
offline and Appearance. Auth, profile, contribution review and remaining
baselines were preserved. The contribution-review test needed a pump after
entering an amount; its existing image was not overwritten to hide that issue.

The later reference-shell restoration changed eight baselines after a separate
before/after review: Home, Groups, contribute entry, Activity, profile, group
detail, ledger and offline. Across the whole audit, nine of thirteen images
changed. Auth, contribution review, public website and Admin baselines remain
unchanged. These are reviewed regression baselines, not release acceptance.
Appearance was subsequently reviewed again against the actual Home shell and
refreshed; the total remains nine changed baselines.

Failed intermediate runs are retained. These included a restored missing
`defaultTargetPlatform` import, a signing-environment mismatch on a dev build,
and the new sign-in clipping assertion before the inherited one-line button
style was explicitly overridden. The first final compact run stopped after
seven cases because the IME covered the quick-pick target; its harness now
dismisses the keyboard and scrolls to the visible control before tapping.
None of these failed runs is counted as a pass.

The first final route rebuild caught an overly broad local patch in an avatar
branch before installation (0/42 run); that patch was corrected. Subsequent
unit and analyzer passes are listed above. No failed candidate was distributed.
The new shell tests initially leaked a test-only semantics handle; explicit
`finally` disposal fixed the harness. The old source-hygiene blanket gradient
ban was replaced only for the central overview token module; arbitrary
feature-level gradients remain prohibited. A final contrast scan caught the
Appearance preview using an image-text role on its dark navigation; the
dedicated navigation foreground token resolved that without a colour change.

## Critical open release findings

1. **EXACT-NATIVE-CANDIDATE:** no fresh controlled production APK+AAB/IPA from
   this source has completed installed-artifact acceptance. The physical phone
   remains unchanged; an in-place QA update was requested, not assumed.
2. **COMPLETE-CASE-MATRIX:** the required 134 cases per platform are not yet
   individually accepted with source/artifact-bound comparisons and reviews.
   The 42 + 29 runs overlap requirements and must not be added as unique closed
   cases. Landscape, light, tablet, keyboard and several recovery states remain.
3. **NATIVE-ACCESSIBILITY:** widget semantics and large-text captures do not
   establish TalkBack/VoiceOver, actual focus traversal, contrast, target-size
   and native keyboard coverage for every required case. Flutter's official
   [release checklist](https://docs.flutter.dev/ui/accessibility) specifically
   calls for screen-reader and large-scale-factor testing.
4. **FINAL-VISUAL-REVIEW:** individual native fixes have been inspected and
   compared, but the full route/state reference-fidelity assessment remains
   unapproved. No 100/100 scores or owner approval were fabricated.

`mobile-parity-acceptance.json` intentionally remains **blocked**, with no
approved cases or invented artifact identities. The implementation and evidence
inventory can advance without weakening that state.

## Boundaries

The owner confirms permission for Revolut brand use. The design target is not
reduced on brand-permission grounds. Existing Collect identity and truthful
country/payment behaviour are retained. No new production writes, payments,
store submission, destructive member actions or changes to signed-in data are
part of this local audit. Accessibility and 100/100 acceptance require more than
screenshots alone. Missing evidence remains a release blocker.
