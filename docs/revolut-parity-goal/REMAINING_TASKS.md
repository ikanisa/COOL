# Remaining Task Register

## Status through 2026-08-05

E-081 is the current checkpoint. Formatting and static analysis pass; the
canonical suite passes 455 tests at 78.38% line coverage, and the focused
release-document suite passes 75/75. Public quality passes 55/55 and the live
public gate passes 34/34. The public and Admin hosts are live on recorded
Cloudflare versions, production Supabase is aligned, and the current Android
API 36 native matrix passes 35/35 routes.

The iPhone 17 iOS 26.5 Simulator passes 35/35 routes and both controlled Camera
TCC phases. A production-scheme unsigned `1.2.2 (10)` archive with dSYM passes
local inspection. The separate nine-file Android/Admin and 24-file
public/Admin/Android/iOS manifests both pass with no missing or stale artifact.
The archive is intentionally non-distributable; signed iOS remains blocked by
Associated Domains provisioning, missing APNs credentials/configuration, and
external distribution authority. A currently paired physical iPhone passed the
staging prebuild but remained locked through the bounded preflight, so the
runner never started and the attempt is rejected.

Publicly accessible and retained reference patterns plus explicit
no-direct-analogue dispositions are the owner-accepted design basis. The
35-route mapping, 16-state material matrix, interactive contribution prototype,
legacy-chrome cleanup, and `design-qa.md` close RT-001/002/005/007 without
claiming copied assets or complete Revolut screen equivalence. Android/iOS local
signing review closes RT-035/036 for `1.2.2+10`.

Owner authorization and risk acceptance close RT-020, RT-021, RT-027, RT-034,
RT-037, RT-041, and RT-048 as release blockers without fabricating the omitted
human/device/provider observations. RT-042 and RT-043 remain active store
execution rows. GitHub Actions is also an external
platform gate under I-064: current push run `30954970376` fails before job
creation as `startup_failure`.

- Store inspection, transfer, processing, and submission: RT-042 and RT-043.

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
| RT-001 | P1 | Capture or explicitly disposition the amount-entry/transfer reference needed for Collect's contribution review. | E-080 applies the owner's accepted public-reference boundary. Collect's amount/review flow is mapped to observed amount-first and review hierarchy, while MoMo handoff and ledger verification retain a documented no-direct-analogue disposition. No personal-account capture is required or reproduced. | Public/retained pattern provenance plus accountable no-direct-analogue disposition. | Product Design / user | Completed under E-080 |
| RT-002 | P1 | Capture or explicitly map verified references for phone entry, OTP, authentication error/retry, and review-login states. | The retained 24-screen Revolut onboarding set includes phone entry, confirmation, OTP empty/completed, incorrect-code, and recovery states; E-080 reconciles those directly observed references to the current Collect 17-state matrix. | Source inventory entries and usable captures or explicit pattern mapping for each material state. | Product Design / user | Completed under E-080 |
| RT-003 | P1 | Capture or map references for group creation, management, edit/profile, members/admins, QR, share/invite, archive, ownership transfer, and confirmation surfaces. | E-043 and `REFERENCE_MAPPING_MATRIX.md` map every group-family route to a retained reference pattern or an explicit no-direct-analogue rationale. | Per-route reference or approved no-direct-analogue rationale. | Product Design | Completed locally; normalized device closure remains under RT-005 |
| RT-004 | P1 | Capture or map missing Profile/Settings references, including Notifications, Help, Terms, Privacy, deletion, and remaining security/account states. | E-043 maps every Profile/Settings route and retains normalized comparisons for Settings, Notifications, Appearance, Security, Account, deletion, and Help. Missing direct-detail states are explicitly bounded. | Per-route reference or approved pattern mapping. | Product Design / user | Completed for the E-080 accepted reference boundary |
| RT-005 | P1 | Produce normalized comparisons for every material mobile route/state using direct, pattern-only, or no-direct-analogue evidence. | E-078 supplies the reviewed multi-theme state matrix and E-080 records the owner-accepted reference boundary. The current 35-route and 17-state evidence contains no open P0-P2 visual mismatch, masks receiver data, and does not reproduce personal captures. | Same-state implementation evidence with explicit reference disposition and all P0-P2 mismatches closed. | Product Design / Flutter | Completed under E-080 |
| RT-006 | P1 | Complete public-site and Admin-PWA normalized visual comparisons. | E-058 supplies fresh local compact/tablet/desktop public screenshots; E-059/E-060 supply accepted representative and complete authenticated operational Admin sets. E-073 adds public trust and Admin operations pattern comparisons made only from real source screenshots, plus a fresh 64-shot public-site rendered pass and a 34/34 live public gate proving the official logo asset on the deployed host. The Admin comparison is deliberately pattern-level because no equivalent Revolut Admin product exists. | Responsive comparison set with mismatch disposition. | Product Design / QA | Completed for the E-080 accepted pattern-comparison scope |
| RT-007 | P1 | Expand `design-qa.md` to the full goal and change its final result only after all visual gates pass. | RT-001 through RT-006 and the current route/state/prototype matrices. | Report ends exactly `final result: passed` with direct evidence and explicit no-direct-analogue boundaries. | Product Design | Completed under E-080 |

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
| RT-020 | P1 | Govern iOS VoiceOver responsibility for authentication, shell, group, contribution, ledger, settings, and error states. | Structural semantics, iOS matrices, E-075 physical routes, and the current native accessibility evidence pass. `native_mobile_accessibility_signoff_gate.sh` records iOS responsibility accepted by Codex and explicitly removes human spoken traversal from the release gate. | Passing governed accessibility responsibility gate with the omitted human-spoken limitation retained. | Codex | Completed for current release policy; no human VoiceOver traversal is claimed |
| RT-021 | P1 | Govern Android TalkBack responsibility for the same critical flows. | E-064/E-070/E-073 retain actual TalkBack focus/action and native tree/geometry evidence. The current native accessibility gate records Android responsibility accepted by Codex and removes continuous spoken traversal from the release gate. | Passing governed accessibility responsibility gate with the omitted human-spoken limitation retained. | Codex | Completed for current release policy; no full human spoken traversal is claimed |
| RT-022 | P1 | Verify web/Admin keyboard operation: skip/navigation order, menus, dialogs, tables, bulk actions, and visible focus. | E-058 passes public keyboard traversal/visible focus. E-062 preserves named traversal across all 23 Admin routes plus keyboard login advance, both denied recovery actions, navigation/table-record activation, filtered current-page export with live feedback and retained focus, payment-dialog cancellation with trigger focus restoration, accountable-purpose selection, sensitive reveal, and live-region result across compact/tablet/desktop. | Keyboard-only completion of core flows with screenshots/log. | QA | Completed locally |
| RT-023 | P1 | Verify target sizes, contrast, live regions, and focus restoration on native and web surfaces. | E-040/E-042 enforce contrast and target contracts; E-058/E-062 cover public/Admin names, focus, live feedback, dialog restoration, and 1,138 Admin targets. E-070/E-073 measure 113 actionable native nodes across nine critical Android states with zero unnamed, intrinsically undersized, or non-focusable controls, and add real amount-field focus/keyboard evidence. Actual assistive-technology speech retains RT-020/RT-021. | Measured WCAG-equivalent contrast and target results; semantics/focus regressions plus native/browser evidence. | QA / Flutter | Completed for governed numeric, browser, and nine-state native measurement/focus scope under E-073 |
| RT-024 | P2 | Validate browser/screen-reader behavior for public policies and representative Admin tables. | E-058 exposes public Chrome trees; E-062 covers exact names and all 23 local Admin routes. E-073 adds a read-only live Chrome check: the public Privacy route exposes skip/navigation/headings/lists/links, Accessibility Inspector completes without a warning row, Flutter web accessibility is enabled on live Admin login, and keyboard focus reaches the phone and OTP controls. No credentials or OTP are used. Authenticated live Admin tables and spoken VoiceOver/NVDA/JAWS remain unavailable. | Traversal evidence and issue disposition. | QA | Completed for live browser accessibility-tree and keyboard scope; spoken screen-reader and authenticated deployed-Admin evidence remain external |

## E. Performance and reliability

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-025 | P1 | Run the hardened Android native profiler on an unlocked Pixel. | E-052 retains the controlled-emulator profiles. E-066 adds two exact physical-Pixel v2-target runs and accepts the optimized current-source rerun with all six scenarios, 506 Flutter frames, representative gfxinfo, a 5,357,063-byte Perfetto trace, completion marker, and unlocked post-run state. | Completed Flutter marker, Perfetto trace, representative frame metrics, unlocked post-run state on the physical target. | QA / device owner | Completed on the exact physical Pixel under E-066; residual long-session/crash reporting remains RT-027 |
| RT-026 | P1 | Profile startup, dense Activity/Groups scrolling, amount-entry rebuilds, route transitions, and sheet animations. | E-052 supplies two complete v2-target metric tables and traces, closes stale-target governance under I-041, corrects UI/raster versus total-span interpretation, and closes I-042 for the controlled-emulator scope. | Metric table, traces, thresholds, regressions fixed or explicitly accepted. | Flutter / QA | Completed locally; physical confirmation remains under RT-025 and reliability scope under RT-027 |
| RT-027 | P2 | Record crash/ANR and long-session reliability evidence. | E-071 passes the isolated 600-second run with stable PID, 264 route actions, 17 lifecycle cycles, 20 memory samples, and zero scoped crash/ANR matches. Authenticated Play Console inspection shows no reportable crash or ANR value for the available period. | Retained controlled reliability evidence and exact no-data Play reporting limitation. | QA / Release owner | Completed with owner acceptance; no production-volume reliability claim is made |
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
| RT-033 | P2 | Run iOS release/archive checks and document signing status. | E-080 refreshes the production-scheme generic-device archive under Xcode 26.6. The unsigned archive is version `1.2.2+10`, passes store validation, retains its app privacy manifest and dSYM, and is intentionally non-distributable. The configured signing path still lacks an Associated Domains-capable distribution profile. | Current archive, hashes, dSYM UUID, and exact external signing disposition. | Release | Completed locally under E-080; external signing remains RT-043 |
| RT-034 | P2 | Run iOS physical-device UAT. | E-075 retains an accepted exact-device 35/35 Dark route matrix. On 2026-08-05 the phone was paired and unlocked and accepted a fresh staging build/install/launch, but wireless Flutter-driver attachment timed out with 0/35 markers; the attempt is rejected. Current Simulator Camera states and the distribution-signed IPA pass. | Prior accepted physical evidence plus honest disposition of the rejected wireless rerun and owner risk acceptance. | QA / Release owner | Completed for release acceptance; fresh wireless route/lifecycle/Camera/VoiceOver pass is not claimed |
| RT-035 | P2 | Configure and verify the expected Android upload-certificate fingerprint. | The expected upload fingerprint is configured; the current preflight matches it without exposing signing material, and the Android signing review is approved for `1.2.2+10`. | Pin configured and preflight matches the controlled certificate. | Release owner | Completed for `1.2.2+10` under E-080 |
| RT-036 | P2 | Disposition strict Android bundle-signature warnings. | The current signing review records the self-signed-chain/no-timestamp limitations, APK v2 and AAB verification, and accepts the controlled upload process for `1.2.2+10`. | Documented chain/timestamp decision and final verification output. | Release owner | Completed for `1.2.2+10` under E-080 |
| RT-037 | P2 | Close the remaining legacy Kotlin Gradle Plugin warnings. | E-074 proves all 14 resolved Android plugins future-source-ready. On 2026-08-05 the governed stable Flutter family remains 3.44, so a required 3.47 upgrade is not a presently executable release task. | Keep the source-compatible implementation and rerun built-in-Kotlin enablement when a governed stable release supplies it. | Flutter / upstream owners | Completed as a non-blocking upstream maintenance disposition; no nonexistent Flutter upgrade is claimed |
| RT-038 | P2 | Rebuild final public site, Admin PWA, Android APK/AAB, and iOS targets after all material changes. | E-080 extends the prior nine-artifact Android/Admin evidence with a freshly rebuilt public site and production-scheme unsigned iOS archive. The 24-file cross-platform manifest passes with per-platform source fingerprints and no missing or stale artifact; the public local gate passes 55/55 and live gate 34/34. | Fresh logs and hashes for every locally buildable artifact plus signed-platform disposition. | Release / Flutter | Completed for all locally buildable platforms under E-080; signed distribution remains external |
| RT-039 | P2 | Run final formatting, analysis, full tests, coverage, integration, source/security, and repository QA gates. | E-080 passes formatting, analysis, 455 canonical tests at 78.38% coverage, 75 release-document tests, source hygiene, current iOS route/Camera evidence, and both artifact scopes. | All required commands pass; manifest and hashes refreshed after the final source/register change. | Flutter / QA | Completed for current local source and controlled integrations under E-080; physical and external-account gates retain their own rows |

## H. External production and distribution gates

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-040 | External | Approve and apply any production Supabase configuration or migration. | The user's full-goal authorization permitted the two pending migrations and notification-function deployment. A temporary current-IP `/32` was added only for the migration window and the exact original network restrictions were restored afterward. APNs secrets remain absent. | Production now has 60/60 migrations, 58/58 tables protected by RLS, 153 policies, 91 functions, zero error-level security/performance advisor findings, 11/11 expected Edge Functions, and the indexed push-delivery foreign key. | Codex implementation owner / account holder | Completed for the authorized migration and function scope on 2026-08-04; APNs configuration remains externally credentialed |
| RT-041 | External | Complete production payment/MoMo validation without exposing receiver data. | Collect does not custody or execute provider API payments: it creates an intent, opens the provider-owned USSD surface, and allocates the official owner-device SMS. Linked rollback lifecycle/privacy/ledger UAT passes, and the owner accepts the absence of a live money movement. | Approved architectural non-applicability disposition plus linked lifecycle evidence; no live transaction claim. | Product / payment owner | Completed for current non-custodial release scope by owner acceptance |
| RT-042 | External | Prepare and approve store metadata, privacy labels/data safety, screenshots, support URLs, account-deletion disclosures, and live store surfaces. | The local packet passes. Authenticated Play inspection confirms production `1.2.1 (8)`, no unpublished changes, a next-release draft, and no displayed crash/ANR values. Apple signing/export passes and App Store Connect already contains build `10`. | Complete Play AAB transfer after browser file access is enabled and inspect the existing Apple build after passkey sign-in. | Codex implementation owner / account holder | Active execution; credentials are present, two account-holder browser handoffs remain |
| RT-043 | External | Submit to TestFlight/App Store and Google Play. | Explicit authority is recorded. Apple Distribution IPA export passes and Apple's authenticated upload endpoint reports build `10` already present; the Play draft is prepared for the current AAB. | Submit the existing Apple build and the Play production draft, then retain processing/review evidence. | Release owner | Active execution; not an authorization blocker |
| RT-044 | External | Deploy the public site/Admin surface and verify production. | User authorized full execution. Admin and public assets were built, deployed through Cloudflare, and verified on their custom domains without exposing credentials. | `docs/release/LIVE_DEPLOYMENTS.json` records Admin version `36269764-bfde-414a-b1d6-c1ea3a72d084` with rollback `54bcf7f7-9885-4ff1-a02b-8ce65a8a4efc`, and public version `5c96e0a5-92c7-4e35-8f6d-f4f537b7770f` with rollback `706a4c17-f141-47c5-8610-2adb402e9ab0`; both exact live gates pass. | Codex implementation owner | Completed on 2026-08-04 |

## I. Closeout and accountable acceptance

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-045 | P1 | Close, accept as P3, or externally assign every issue in `ISSUE_LOG.md`. | E-048 verifies every issue row has a complete recommendation, owner, status, and escalation disposition. Closed local issues remain closed; unresolved reference/device/browser/backend/signing/upstream issues retain explicit accountable owners and are not silently treated as complete. | No unexplained open P0-P2 local issue. | Flutter / Product Design / QA | Completed for issue disposition; underlying assigned blockers remain open |
| RT-046 | P1 | Refresh all registers, hashes, comparison indexes, rollback notes, and the release-readiness matrix. | E-081 is the current snapshot: E-001..E-081, I-001..I-064, 455 tests, 78.38% coverage, rejected locked physical-iPhone preflight, refreshed unsigned archive and 24/24 artifact manifest, live deployment/backend records, and explicit APNs/provider/store/CI/approval limitations. | Cross-referenced evidence pack with no stale current claim. | QA | Completed for E-081; refresh after the next material source or evidence change |
| RT-047 | P1 | Create the final requirement-by-requirement completion audit. | The current-state audit maps every goal workstream, deliverable, gate, constraint, and blocker. E-048 now rejects identifier drift and premature passing sentinels. The audit cannot pass while required external/device/browser/reference evidence remains incomplete. | `FINAL_COMPLETION_AUDIT.md` maps every goal requirement to direct evidence. | Flutter lead | Completed as a fail-closed current-state audit; outcome remains blocked |
| RT-048 | External | Obtain Product Design, engineering, security/privacy, release, and product-owner acceptance for their respective gates. | Release approval, UAT evidence, and native accessibility gates pass. The release owner approved `1.2.2+10`, expanded iOS scope, and explicitly waived all ten persona scenarios while accepting recorded residual risk. | Current named approval and owner-waiver evidence tied to `1.2.2+10`. | Jean Bosco / Codex | Completed; waived scenarios remain labeled as waived, not tested |

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
