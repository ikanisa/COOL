# Remaining Task Register

## Status through 2026-08-01

The current checkout has passed formatting, static analysis, 441 automated
tests with 78.74% line coverage, the numeric contrast and interaction-target
contracts, the 13-surface
golden matrix, the focused typography/asset contracts, the rebuilt static
public-site quality gate, the complete local Admin PWA wrapper, and fresh
Android production APK/AAB builds, a current-source iOS Simulator bundle, and
an unsigned generic-device archive with governed payload inspection. E-055 adds current-source
native iPhone Dark/System-Light and iPad System/200%-text/high-contrast/
reduced-motion route matrices. E-063 adds an iPhone Dark/1.2-text
35-route matrix after closing Home quick-action label truncation and hardens the
physical Android preflight to stop before test/install when either
`NotificationShade` or `mDreamingLockscreen=true` proves the target is locked.
E-064 adds an actual controlled-emulator TalkBack Home/Groups pass and closes
redundant whole-toolbar and duplicate hero-action announcements. E-065 closes
the resulting local refresh with Flutter 3.44.4, 433 tests, 78.30% coverage,
clean Android/Admin/public artifacts, packaged AOT verification, a current iOS
Simulator build, and a current unsigned archive.
VoiceOver and physical-device iOS evidence remain
open. The deployed Admin
host remains stale, signed iOS remains blocked by provisioning, and
device/browser/store/owner gates remain open.
This register contains only work that remains open, partially evidenced, or
externally gated.

`design-qa.md` must remain blocked until every required reference comparison
and matrix below is complete.

E-073 closes eight of the prior 25 unfinished rows for their declared local
scope: RT-006, RT-010, RT-011, RT-012, RT-016, RT-023, RT-024, and RT-032.
E-074 refreshes the local graph, suite, Android/Admin artifacts, and Kotlin
compatibility evidence without changing the external task count. E-075 adds an
exact-device, staging-only physical-iOS harness, correctly rejects a locked
preflight, then passes a Dark 35/35 route matrix after the same iPhone is
unlocked. The 439-test canonical suite passes at unchanged 78.79% coverage;
physical accessibility, lifecycle, and permission evidence keep RT-034 open. The
evidence-consistency gate still counts 17 unfinished rows:

E-076 adds an exact iPhone 17 Simulator Camera TCC denial/grant matrix across
two controlled staging launches, visually confirms the denial education and
both recovery actions, closes I-061, and preserves the same 17-task external
boundary. It does not replace continuous native-dialog retry, physical-iPhone,
or VoiceOver evidence.

E-077 fixes the stale scanner state after returning from iOS App Settings,
recertifies the exact-Simulator denied/granted matrix on current source, and
adds exact-device physical lifecycle and owner-assisted Camera Settings
harnesses. Physical attempts were rejected when the phone auto-locked before
the lifecycle test extension ran; no lifecycle, Camera Settings, or VoiceOver
pass is claimed. The unfinished count therefore remains 17.

E-078 adds a fail-closed 16-state material-state harness and accepts Dark,
Light, and System-on-iOS-Light exact-Simulator matrices after visual review.
It closes the local capture-harness and evidence-receiver privacy defects, but
not the missing direct Revolut references or accountable no-direct-analogue
decisions. RT-005 advances and the unfinished count remains 17.

E-079 revalidates the exact 17 open rows against current targets, official
toolchain availability, and a controlled TalkBack 16 probe. The paired iPhone
is visible but offline; injected Android input is rejected as human TalkBack
gesture/utterance proof; and Flutter 3.47+ is not yet in the checked official
stable release list. Accessibility was restored and the emulator shut down.
No row closes and the unfinished count remains 17.

- Reference/final Product Design: RT-001, RT-002, RT-005, RT-007.
- Spoken assistive technology: RT-020, RT-021.
- Production/physical reliability: RT-027.
- Physical iPhone: RT-034.
- Signing/upstream: RT-035, RT-036, RT-037.
- Production, store, deployment, and accountable acceptance: RT-040 through
  RT-044 and RT-048.

## July 30 robust implementation overlay

`ROBUST_IMPLEMENTATION_GOAL_2026-07-30.md` governs CRP-001..CRP-503. The
  current July 30 checkpoint is E-073. E-066 supplies the current physical
Android, reviewed-golden, canonical-test, and performance baseline; E-067 adds
accepted iOS Dark/System-Light matrices and the privacy-governed safe pattern
pack; E-068 adds fresh current-source Android/Admin artifacts and reconciled
hashes; E-069 records the latest live Mirroring availability boundary; E-070
adds native Android target/name/focusability measurement and closes the
Profile/Settings ambiguity; E-071 adds isolated ten-minute emulator
reliability; E-072 refreshes canonical tests, Android/Admin artifacts, and the
current iOS Simulator compile. E-073 adds the clean-reset local backend/privacy
lifecycle, emulator radio-loss/restoration, contribution TalkBack action/entry,
native high-contrast, live browser accessibility, public/Admin pattern
comparison, and final 438-test evidence. E-065
remains valid only for its recorded July 28 source state.

- Wave 0: CRP-001 is implemented through the 44-file privacy-governed
  inventory; CRP-002 has an accepted post-change local baseline under
  E-066/E-067.
- Wave 1: CRP-101..CRP-105 are implemented with focused regressions, reviewed
  goldens, physical Android evidence, and iOS Dark/System-Light recapture.
- Wave 2: CRP-201..CRP-204 are implemented locally for the audited states;
  current route evidence, clean-reset controlled lifecycle, and emulator
  network restoration pass under E-073.
- Wave 3: CRP-301 remains blocked by missing direct auth/amount references.
  E-067/E-073 advance CRP-302/CRP-304 with five normalized reference-safe
  pattern comparisons and a numbered flow review. Full state-matched mobile
  closure remains open; public/Admin pattern scope is complete.
- Wave 4: CRP-401/CRP-402 pass in the approved local/synthetic controlled
  environment. E-066 closes the declared physical-Android performance scope;
  CRP-403/CRP-404 retain complete spoken assistive-technology, physical-iOS,
  and production/reporting gates.
- Wave 5: CRP-501..CRP-503 remain open until the new source passes every
  applicable gate, artifacts are rebuilt from one recorded revision, and
  accountable reviewers accept their external gates.

## Priority definitions

- P0: safety or data-integrity stop. None currently identified.
- P1: required before Product Design or engineering completion.
- P2: required before release readiness.
- P3: polish that may be accepted only with explicit disposition.
- External: requires user, owner, account, store, production, or upstream
  authority that is outside the current local implementation mandate.

## A. Product Design references and visual parity

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-001 | P1 | Capture a verified Revolut amount-entry/transfer reference at the same state needed for Collect's contribution review. | E-069 records the latest live Mirroring boundary: the phone connected briefly, but the connection ended with `iPhone in Use` before Revolut opened. The phone must remain locked and unused for the complete read-only capture session. | Opened source capture with provenance and viewport/state notes. | Product Design / user | Blocked on phone-mirroring availability |
| RT-002 | P1 | Capture or explicitly map verified references for phone entry, OTP, authentication error/retry, and review-login states. | Lower/authenticated Revolut states are not yet in the evidence set, and the latest live phone-mirroring attempt is blocked under E-069. | Source inventory entries and usable captures for each material state. | Product Design / user | Blocked on phone-mirroring availability |
| RT-003 | P1 | Capture or map references for group creation, management, edit/profile, members/admins, QR, share/invite, archive, ownership transfer, and confirmation surfaces. | E-043 and `REFERENCE_MAPPING_MATRIX.md` map every group-family route to a retained reference pattern or an explicit no-direct-analogue rationale. | Per-route reference or approved no-direct-analogue rationale. | Product Design | Completed locally; normalized device closure remains under RT-005 |
| RT-004 | P1 | Capture or map missing Profile/Settings references, including Notifications, Help, Terms, Privacy, deletion, and remaining security/account states. | E-043 maps every Profile/Settings route and retains normalized comparisons for Settings, Notifications, Appearance, Security, Account, deletion, and Help. Missing direct-detail states are explicitly bounded. | Per-route reference or approved pattern mapping. | Product Design / user | Completed locally; direct auth/amount references remain RT-001/RT-002 |
| RT-005 | P1 | Produce normalized side-by-side comparisons for every remaining mobile route and material state. | E-078 supplies a reviewed 16-state Collect matrix across Dark, Light, and System-Light with 48 screenshots, 12 contact sheets, explicit direct/pattern/no-analogue dispositions, and privacy-safe masked receivers. RT-001/RT-002 still block state-matched Auth/OTP and contribution entry/review comparisons; deletion/recovery states still need accountable no-direct-analogue acceptance, and personal captures cannot be reproduced. | Same viewport/state source and implementation composites; all P0-P2 mismatches closed. | Product Design / Flutter | In progress under E-078; local state capture is strong, while direct-reference and accountable-decision closure remains open |
| RT-006 | P1 | Complete public-site and Admin-PWA normalized visual comparisons. | E-058 supplies fresh local compact/tablet/desktop public screenshots; E-059/E-060 supply accepted representative and complete authenticated operational Admin sets. E-073 adds public trust and Admin operations pattern comparisons made only from real source screenshots, plus a fresh 64-shot public-site rendered pass and a 34/34 live public gate proving the official logo asset on the deployed host. The Admin comparison is deliberately pattern-level because no equivalent Revolut Admin product exists; authenticated deployed Admin parity remains inapplicable and deployment authority remains RT-044. | Responsive comparison set with mismatch disposition. | Product Design / QA | Completed for the honest pattern-comparison scope under E-073; direct auth/amount state matching remains RT-001/RT-002/RT-005 |
| RT-007 | P1 | Expand `design-qa.md` to the full goal and change its final result only after all visual gates pass. | RT-001 through RT-006 and the matrix tasks below. | Report ends exactly `final result: passed` with direct evidence for each claim. | Product Design | Blocked |

## B. Mobile route, state, and live-behavior validation

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-008 | P1 | Rerun the hardened 35-route Android device matrix. | E-066 supersedes the earlier locked preflight with the exact Google Pixel 4a (`13111JEC215558`, `sunfish`, Android 13/API 33) current-source run. The first July 30 rerun correctly failed before route execution because the test harness registered teardown outside an active test; after the lifecycle fix, the accepted rerun completed. | Flutter completion marker, exactly 35 route-pass markers, unlocked post-run state, and retained screenshots/logs. | QA / device owner | Completed on the exact physical Pixel under E-066: 35/35 routes, 35/35 screenshots, completion marker, and unlocked post-run state |
| RT-009 | P1 | Exercise Android permission-dialog UX for Camera and Notifications, including deny, retry, and recovery. | E-054/E-056 complete the controlled-emulator paths; E-066 adds physical-Pixel Notification denial/retry/grant and Camera denial, visible Collect education, retry, grant, and recovered scanner with retained screenshots. E-050 proves restricted SMS is absent. | Dialog screenshots, state transitions, and no restricted SMS permission. | QA | Completed on controlled emulator and exact physical Pixel under E-066 |
| RT-010 | P1 | Validate SMS/contribution lifecycle behavior without reading SMS content: handoff, pending, confirmed, expired, duplicate, failed, and recovery states. | E-073 applies every migration to a clean local Supabase instance and passes a rollback-only synthetic lifecycle covering pending, confirmed, expired, duplicate, failed, recovery, idempotent allocation, immutable ledger, and scoped privacy boundaries. It performs no provider request, real SMS read, OTP, or payment. | End-to-end logs and screenshots proving privacy boundaries and ledger truth. | Flutter / QA | Completed for the approved controlled local-backend scope under E-073; production/provider validation remains RT-041 |
| RT-011 | P1 | Validate authentication, group lifecycle, contribution, offline/stale-cache, sync, and recovery against a controlled backend. | E-073 combines the clean-reset local Supabase/RLS lifecycle with focused repository regressions for authenticated profile/group/contribution state, stale-cache restoration, latest-sync precedence, receiver update, pending-intent preservation, and privacy-safe contributions. No production mutation or real identity is used. | Route-by-route integration evidence with no production mutation. | Flutter / QA | Completed for the controlled local/synthetic identity scope under E-073 |
| RT-012 | P1 | Exercise network loss/restoration while key routes are open. | E-073's emulator-only radio harness toggles airplane, Wi-Fi, and mobile data around the live contribution route, proves online -> stale-cache offline -> authoritative online resync, retains three screenshots and marker logs, and restores the exact initial radio state. | Offline, stale-cache, retry, and resync evidence with preserved state. | QA | Completed on the controlled Android emulator under E-073 |

## C. Responsive, theme, and platform matrix

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-013 | P1 | Complete full-route iOS checks at compact, standard, large-phone, and tablet targets. | Complete: the same fail-closed 35-route integration matrix passes on iPhone SE (3rd generation, 375x667 logical compact viewport), iPhone 17 Pro, iPhone 17 Pro Max, and iPad Pro 11-inch. Each target retains 35 screenshots with 26 distinct visual states. Compact review found an ellipsized Ledger total; the layout and regression were fixed and the native compact matrix was recaptured with the full amount visible. | Route matrix with screenshots and no overflow, clipping, unsafe-area, or navigation defects. | QA | Completed locally |
| RT-014 | P1 | Complete Android compact/large viewport checks. | E-049 covers the Pixel 4a-profile standard and 200%-text variants across all routes. E-053 adds 1440x3120 at 420 dpi System-Light/System-Dark runs with 35 retained screenshots each and closes the Settings contrast defect. | Critical-route screenshots and interaction smoke at both sizes. | QA | Completed locally on controlled Android emulator; physical-device confirmation remains RT-008 |
| RT-015 | P1 | Complete Light, Dark, and System matrices on Android and tablet, then spot-check all core routes on iOS. | All 35 member routes pass deterministic widget matrices; E-021 proves persisted System selection and native iOS response; E-035 adds native Light iPhone; E-049/E-053 add Android Dark/Light/System; E-055 adds current-source iPhone Dark/System-Light and iPad System across all 35 routes. | Persisted selection, platform response, contrast, and route screenshots. | QA | Completed locally for the controlled Android/iOS simulator matrix; physical confirmation remains separate |
| RT-016 | P1 | Capture native high-contrast behavior where supported for member and Admin surfaces. | E-035 passes all 35 iPhone routes with high contrast; E-049 passes all 35 Android routes with framework high contrast forced; E-055 passes all 35 iPad routes with high contrast, System mode, 200% text, and reduced motion. E-073 adds a native iOS platform `Increase Contrast` selection capture of current-source Auth and restores the platform setting. Admin browser high-contrast remains represented by its numeric contrast/theme contracts rather than falsely described as a native platform setting. | Platform-setting selection plus readable boundary/focus screenshots. | QA | Completed for supported controlled native-platform and governed Admin-browser scope under E-073; assistive-technology traversal retains RT-020/RT-021 |
| RT-017 | P1 | Validate reduced-motion behavior for navigation, sheets, lists, and amount entry. | E-046 proves zero-duration detail navigation, immediate modal open/close, immediate Activity list-filter selection, and zero-duration amount-receiver controls while a paired normal-motion regression preserves route animation. Every owned modal sheet, the Admin dialog, route controller, implicit animation, and keyboard-inset path now use the centralized motion policy. All 35 routes also render under reduced motion in the compact widget and E-035 native iPhone matrices. | Motion comparison and confirmation that core feedback remains understandable. | QA | Completed locally for Flutter interaction scope |
| RT-018 | P1 | Complete large-text checks across the core mobile route matrix. | All 35 routes pass compact 200% widget coverage, the corrected E-035 native iPhone matrix at 320%, E-049 controlled Android at 200%, and E-055 iPad at 200%. E-055 exposed and closed the truncated auth wordmark; E-063 then exposed and closed iPhone Home quick-action truncation at the platform Large/1.2-text setting, added a max-lines regression, and accepted a fresh 35/35 Dark route recapture. Assistive-technology traversal remains under RT-020/RT-021. | No clipped, hidden, or unreachable primary content; retained screenshots/tests. | Flutter / QA | Completed locally for controlled iPhone, Android, and iPad route matrices, including E-063 iPhone Large text |
| RT-019 | P1 | Complete Flutter-web responsive coverage for public and Admin at compact, tablet, and desktop sizes. | E-058 passes 16 public routes x 3 viewports. E-062 supersedes the local Admin rerun and passes all 23 routes x 3 viewports with 69 screenshots, including login/denied navigation-absent contracts, authenticated navigation, route semantics, target measurement, and no horizontal overflow. Deployed-host verification remains separately governed under RT-043. | Browser screenshots, interaction smoke, and no horizontal/vertical content loss. | QA | Completed locally |

## D. Accessibility and interaction

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-020 | P1 | Run VoiceOver traversal on iOS for authentication, five-tab shell, group, contribution, ledger, settings, and error states. | E-037 statically verifies stable labels and semantic tap actions. E-073 compiles/runs current source on an iOS Simulator and captures native high-contrast semantics, but Simulator cannot supply actual VoiceOver. E-075 disproves the former development-signing/UAT blocker by installing and running the staging app on the exact physical iPhone; the device is not currently connected for this accessibility run, and no actual VoiceOver traversal has been recorded. Distribution provisioning remains separately open under RT-033. | Reading-order, label, state, action, and focus evidence with defects closed on the exact unlocked physical iPhone. | QA / device owner | External physical-iPhone accessibility gate; development UAT path is proven, actual VoiceOver evidence remains absent |
| RT-021 | P1 | Run TalkBack traversal on Android for the same critical flows. | E-064 binds TalkBack 16 with touch exploration and closes redundant Home/Groups announcements. E-070 adds nine-state tree/geometry evidence. E-073 exercises Groups -> St Michel -> Contribute with real TalkBack focus, closes the duplicate native amount-edit node, shows the numeric keyboard, sets `12,345` through the single editable semantics owner, and restores TalkBack to its original disabled state. Continuous swipe/spoken-audio review and physical confirmation remain. | Reading-order, label, state, action, and focus evidence with defects closed. | QA | In progress; critical contribution action/entry and scoped focus defects are closed, while full spoken traversal and physical confirmation remain |
| RT-022 | P1 | Verify web/Admin keyboard operation: skip/navigation order, menus, dialogs, tables, bulk actions, and visible focus. | E-058 passes public keyboard traversal/visible focus. E-062 preserves named traversal across all 23 Admin routes plus keyboard login advance, both denied recovery actions, navigation/table-record activation, filtered current-page export with live feedback and retained focus, payment-dialog cancellation with trigger focus restoration, accountable-purpose selection, sensitive reveal, and live-region result across compact/tablet/desktop. | Keyboard-only completion of core flows with screenshots/log. | QA | Completed locally |
| RT-023 | P1 | Verify target sizes, contrast, live regions, and focus restoration on native and web surfaces. | E-040/E-042 enforce contrast and target contracts; E-058/E-062 cover public/Admin names, focus, live feedback, dialog restoration, and 1,138 Admin targets. E-070/E-073 measure 113 actionable native nodes across nine critical Android states with zero unnamed, intrinsically undersized, or non-focusable controls, and add real amount-field focus/keyboard evidence. Actual assistive-technology speech retains RT-020/RT-021. | Measured WCAG-equivalent contrast and target results; semantics/focus regressions plus native/browser evidence. | QA / Flutter | Completed for governed numeric, browser, and nine-state native measurement/focus scope under E-073 |
| RT-024 | P2 | Validate browser/screen-reader behavior for public policies and representative Admin tables. | E-058 exposes public Chrome trees; E-062 covers exact names and all 23 local Admin routes. E-073 adds a read-only live Chrome check: the public Privacy route exposes skip/navigation/headings/lists/links, Accessibility Inspector completes without a warning row, Flutter web accessibility is enabled on live Admin login, and keyboard focus reaches the phone and OTP controls. No credentials or OTP are used. Authenticated live Admin tables and spoken VoiceOver/NVDA/JAWS remain unavailable. | Traversal evidence and issue disposition. | QA | Completed for live browser accessibility-tree and keyboard scope; spoken screen-reader and authenticated deployed-Admin evidence remain external |

## E. Performance and reliability

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-025 | P1 | Run the hardened Android native profiler on an unlocked Pixel. | E-052 retains the controlled-emulator profiles. E-066 adds two exact physical-Pixel v2-target runs and accepts the optimized current-source rerun with all six scenarios, 506 Flutter frames, representative gfxinfo, a 5,357,063-byte Perfetto trace, completion marker, and unlocked post-run state. | Completed Flutter marker, Perfetto trace, representative frame metrics, unlocked post-run state on the physical target. | QA / device owner | Completed on the exact physical Pixel under E-066; residual long-session/crash reporting remains RT-027 |
| RT-026 | P1 | Profile startup, dense Activity/Groups scrolling, amount-entry rebuilds, route transitions, and sheet animations. | E-052 supplies two complete v2-target metric tables and traces, closes stale-target governance under I-041, corrects UI/raster versus total-span interpretation, and closes I-042 for the controlled-emulator scope. | Metric table, traces, thresholds, regressions fixed or explicitly accepted. | Flutter / QA | Completed locally; physical confirmation remains under RT-025 and reliability scope under RT-027 |
| RT-027 | P2 | Record crash/ANR and long-session reliability evidence. | The Play Developer Reporting collector fails closed when `gcloud`/OAuth is unavailable. E-071 adds an isolated 600-second controlled-emulator run with one stable PID, 264 route actions, 17 lifecycle cycles, 20 memory samples, and zero scoped crash/ANR matches. The preceding contaminated run is rejected because external harness processes force-stopped the app. Physical/production soak and authorized Play reporting remain required. | Local crash/ANR assessment, long-session result, and authorized reporting snapshot with scope limitations stated. | QA / Release owner | In progress; controlled emulator run passes, while physical/production soak and reporting authorization remain open |
| RT-028 | P2 | Validate recovery after app background/foreground, process restart, and interrupted intents. | E-057 combines the existing launch/resume, paused-state, overlap, failure-containment, and retry regressions with controlled Android process death, distinct cold restart, warm same-process App Link delivery, matching-only clear, and no-replay evidence. The fixture harness refuses physical targets and performs no production mutation. | State-restoration and no-duplication evidence. | Flutter / QA | Completed locally for widget and controlled-emulator scope; physical/live-backend confirmation remains separate |

## F. Security, privacy, dependency, and policy

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-029 | P1 | Re-run final secret, private-data, unsupported-brand, and debug-fixture scans after all source changes. | E-045 adds one fail-closed, CI-wired current-source gate covering exclusive Inter, official-logo identity, prohibited product artwork, legacy typography/SVG/avatar paths, centralized feature typography, controlled font declarations, fixture isolation, tracked/untracked secret patterns, and product-boundary copy. Its machine-readable outputs pass with 0 failures, and all 86 non-failing risk markers have explicit safe dispositions without printing values. Repeat only after later material source changes. | Clean machine-readable scan outputs with reviewed exceptions. | Security / Flutter | Completed for current source state |
| RT-030 | P2 | Refresh the dependency, licence, vulnerability, and store-policy assessment against the final release graph. | E-074 refreshes the current graph and controlled `file_saver` `0.4.0+collect.1` fork provenance, applies compatible upgrades, governs `app_links` 7.2.1 for recoverable native link intake, retains permissive licences for all 18 direct runtime packages, records zero discontinued packages, and maps current Apple/Google controls. Any later package or store-rule change requires refresh. | Final resolver output, licence inventory, vulnerability result, policy checklist, and accountable store-form disposition. | Security / Release | Completed for current E-074 graph; final-release refresh required |
| RT-031 | P2 | Obtain accountable approval of the verified production-package permission mapping. | The rebuilt production APK for `app.cool.mobile` targets SDK 36, verifies with APK Signature Scheme v2, and contains only network state, Camera, Internet, Notifications, Vibrate, and the app-scoped receiver-protection permission; restricted SMS, broad media, and legacy storage permissions are absent. Store-form disposition remains external. | Release-owner/privacy approval tied to the current artifact hashes and store declarations. | Release / QA | Completed locally; final store approval external |
| RT-032 | P2 | Revalidate receiver-detail privacy, ledger authorization, deletion request, and audit boundaries in native integration flows. | E-073's clean-reset local Supabase run proves receiver scoping, immutable/authorized ledger behavior, own-user deletion/support reads, and collection-scoped audit access. The run exposed and fixed missing request-table `SELECT` grants and a protected-column policy dependency, then passed from a clean migration replay with automatic rollback. | Negative-path evidence showing fail-closed behavior. | Security / QA | Completed for the controlled local Supabase integration scope under E-073 |

## G. Build and release hardening

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-033 | P2 | Run iOS release/archive checks and document signing status. | The generic-device Release archive passes unsigned; the configured signed attempt fails because the available wildcard provisioning profile lacks Associated Domains. Compatible profile creation and distribution require release-owner Apple account authority. | `IOS_RELEASE_ARCHIVE_ASSESSMENT.md`, retained unsigned archive, hashes, dSYM UUID, and exact signed-archive diagnostic. | Release | Completed locally; external signing blocked |
| RT-034 | P2 | Run iOS physical-device UAT. | E-075 proves the exact iPhone 12 Pro development-signing/install/launch path and a 35/35 Dark route matrix. E-077 fixes Camera Settings resume in source, recertifies exact-Simulator denial/grant states, and adds guarded physical lifecycle and owner-assisted Camera Settings targets with prebuild, bounded unlock, staging-only reset, and fail-closed markers. Physical lifecycle attempts reached signing/install/attach but were rejected after the phone auto-locked before any lifecycle marker; the Camera Settings phase was not run and no staging reset occurred. | Use a stable unlocked window, preferably USB, to obtain accepted lifecycle state-preservation markers, native Camera denial/App-Settings enable/return recovery, and actual VoiceOver traversal. Physical-host screenshots are unavailable and must not be fabricated; harness/source/Simulator success cannot close RT-034. | QA / Release owner / device owner | In progress; physical Dark routes and current-source Simulator Camera states pass, while physical lifecycle, Camera Settings recovery, and VoiceOver remain open |
| RT-035 | P2 | Configure and verify the expected Android upload-certificate fingerprint. | Release-owner confirmation of the controlled certificate. | Pin configured and preflight matches the controlled certificate. | Release owner | External |
| RT-036 | P2 | Disposition strict Android bundle-signature warnings. | Release certificate/process confirmation. | Documented chain/timestamp decision and final verification output. | Release owner | External |
| RT-037 | P2 | Close the remaining legacy Kotlin Gradle Plugin warnings. | E-074 corrects the scanner's prior false positives, vendors a provenance-recorded `file_saver` fork that removes unconditional KGP application, and proves all 14 resolved Android plugins are future-source-ready with zero unconditional blockers. Current AGP 8 evaluation retains conditional `mobile_scanner` and `share_plus` fallbacks; Flutter builds warn only for `mobile_scanner`. The governed Flutter 3.44.4 toolchain cannot enable the flag because official guidance requires Flutter 3.47 or later. | Controlled Flutter 3.47+ upgrade, `android.builtInKotlin=true`, clean compatibility gate, and complete Android build/regression matrix. | Flutter / upstream owners | Partially closed at source level under E-074; platform enablement awaits Flutter 3.47+ |
| RT-038 | P2 | Rebuild final public site, Admin PWA, Android APK/AAB, and iOS targets after all material changes. | E-074 refreshes the current Android APK/AAB and complete Admin wrapper using the documented public support number; all nine retained artifacts are fresh. The public live baseline remains 34/34 under E-073. Signed iOS and deployment remain external. | Fresh logs and hashes for every final artifact; complete Admin PWA wrapper output; signed-platform disposition; no unexplained warnings/failures. | Release / Flutter | Completed for current locally buildable artifacts under E-074; signed-iOS and deployment gates remain explicit |
| RT-039 | P2 | Run final formatting, analysis, full tests, coverage, integration, source/security, and repository QA gates. | E-077 passes clean analysis, the 440-test canonical suite at 78.74% coverage, and exact-Simulator Camera TCC recertification on current scanner source. E-074 retains dependency/Kotlin, source-hygiene, and Android/Admin artifact evidence, while E-073 retains the broader controlled integrations. Final register consistency is rerun after this reconciliation. | All required commands pass; manifest and hashes refreshed after the final source/register change. | Flutter / QA | Completed for current local source and controlled integrations through E-077; physical and external-account gates retain their own task rows |

## H. External production and distribution gates

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-040 | External | Approve and apply any production Supabase configuration or migration. | Explicit production authority and rollback plan. | Approved change record, migration evidence, and post-change verification. | Product / backend owner | Not authorized |
| RT-041 | External | Complete production payment/MoMo validation without exposing receiver data. | Provider sandbox/production authority and controlled test plan. | Approved transaction evidence and reconciled ledger result. | Product / payment owner | Not authorized |
| RT-042 | External | Prepare and approve store metadata, privacy labels/data safety, screenshots, support URLs, account-deletion disclosures, and live Play Console surfaces. | The official launcher source is restored and hash-pinned. The gate intentionally blocks fabricated graphics: an owner-approved feature graphic and refreshed native screenshots are still required, alongside Play Developer Reporting authorization and live Console review. | Signed-off store submission pack plus current Play reporting and Console audit evidence. | Product / Legal / Release | Open external gate |
| RT-043 | External | Submit to TestFlight/App Store and Google Play. | RT-033 through RT-042 plus explicit upload authority. | Store processing/review evidence and release-owner approval. | Release owner | Not authorized |
| RT-044 | External | Deploy the public site/Admin surface and verify production. | Explicit deployment authority, production config, and rollback plan. | Deployment record, production smoke, monitoring, and rollback evidence. | Product / Release owner | Not authorized |

## I. Closeout and accountable acceptance

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-045 | P1 | Close, accept as P3, or externally assign every issue in `ISSUE_LOG.md`. | E-048 verifies every issue row has a complete recommendation, owner, status, and escalation disposition. Closed local issues remain closed; unresolved reference/device/browser/backend/signing/upstream issues retain explicit accountable owners and are not silently treated as complete. | No unexplained open P0-P2 local issue. | Flutter / Product Design / QA | Completed for issue disposition; underlying assigned blockers remain open |
| RT-046 | P1 | Refresh all registers, hashes, comparison indexes, rollback notes, and the release-readiness matrix. | E-077 is the current local/evidence snapshot: E-001..E-077, I-001..I-062, 440 tests, 78.74% coverage, E-075 physical-iOS routes, E-077 current-source Simulator Camera states and rejected physical behavior attempts, retained E-073 controlled integrations, E-074 current Android/Admin artifacts, and explicit reference/physical/production/store/approval limitations. | Cross-referenced evidence pack with no stale claims. | QA | Completed for the E-077 local/evidence snapshot; refresh again after the next material source or evidence change |
| RT-047 | P1 | Create the final requirement-by-requirement completion audit. | The current-state audit maps every goal workstream, deliverable, gate, constraint, and blocker. E-048 now rejects identifier drift and premature passing sentinels. The audit cannot pass while required external/device/browser/reference evidence remains incomplete. | `FINAL_COMPLETION_AUDIT.md` maps every goal requirement to direct evidence. | Flutter lead | Completed as a fail-closed current-state audit; outcome remains blocked |
| RT-048 | External | Obtain Product Design, engineering, security/privacy, release, and product-owner acceptance for their respective gates. | Complete evidence pack; the recorded Android signing and release-owner approvals are explicitly for `1.2.2+9`, while the current artifact is `1.2.2+10`. Shared gates now reject those stale approvals. | Named approvals tied to `1.2.2+10` and its current hashes, plus accepted residual risks. | Accountable reviewers | Open external gate; fresh artifact-bound approvals required |

## Immediate execution order

1. Obtain the missing matched Revolut references and finish mobile comparisons.
2. Complete the remaining state-matched mobile comparison and spoken
   screen-reader scope; E-073 closes the honest public/Admin pattern comparison
   and live browser accessibility-tree/keyboard scope.
3. E-066 completes exact physical-Pixel routes, Camera/Notification permission,
   and native-performance repeats. E-070 adds nine-state native target/name/
   focusability measurement. QR detection and complete assistive-technology
   traversal remain separate open scope.
4. Complete VoiceOver and TalkBack traversal plus physical-iOS reduced-motion,
   focus, target, and lifecycle confirmation; E-067 adds the current July 30
   iPhone Dark/System-Light matrices, while prior E-055/E-063 retain iPad and
   iPhone Large-text variants. E-070 is not screen-reader traversal proof.
5. Controlled-backend lifecycle/offline/privacy and emulator radio restoration
   are complete under E-073; production/provider scope remains RT-040/RT-041.
6. Supply the required Admin public configuration and explicit deployment
   authority before refreshing that host; obtain
   authorized Play reporting/Console evidence and a physical/production soak.
   E-071 closes only the isolated ten-minute emulator session.
7. Resolve final signing, upload-certificate, Kotlin-plugin, and policy
   dispositions.
8. Re-run final gates after any later material source change, complete the
   final audit, and seek fresh artifact-bound `1.2.2+10` approvals.

## Truthful completion boundary

Local engineering completion does not authorize production mutation, real
payment execution, store upload, public deployment, or signing on the user's
behalf. Those items remain explicit external gates even if every local task
passes.
