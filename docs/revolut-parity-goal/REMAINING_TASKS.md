# Remaining Task Register

## Status at 2026-07-28

The current checkout has passed formatting, static analysis, 433 automated
tests with 78.30% line coverage, the numeric contrast and interaction-target
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
| RT-001 | P1 | Capture a verified Revolut amount-entry/transfer reference at the same state needed for Collect's contribution review. | E-041 records the current iPhone Mirroring blocker: the paired device was not found after reconnect and must be restored to a nearby/recently-unlocked/then-locked mirroring state. | Opened source capture with provenance and viewport/state notes. | Product Design / user | Blocked on phone-mirroring availability |
| RT-002 | P1 | Capture or explicitly map verified references for phone entry, OTP, authentication error/retry, and review-login states. | Lower/authenticated Revolut states are not yet in the evidence set, and the current phone-mirroring attempt is blocked under E-041. | Source inventory entries and usable captures for each material state. | Product Design / user | Blocked on phone-mirroring availability |
| RT-003 | P1 | Capture or map references for group creation, management, edit/profile, members/admins, QR, share/invite, archive, ownership transfer, and confirmation surfaces. | E-043 and `REFERENCE_MAPPING_MATRIX.md` map every group-family route to a retained reference pattern or an explicit no-direct-analogue rationale. | Per-route reference or approved no-direct-analogue rationale. | Product Design | Completed locally; normalized device closure remains under RT-005 |
| RT-004 | P1 | Capture or map missing Profile/Settings references, including Notifications, Help, Terms, Privacy, deletion, and remaining security/account states. | E-043 maps every Profile/Settings route and retains normalized comparisons for Settings, Notifications, Appearance, Security, Account, deletion, and Help. Missing direct-detail states are explicitly bounded. | Per-route reference or approved pattern mapping. | Product Design / user | Completed locally; direct auth/amount references remain RT-001/RT-002 |
| RT-005 | P1 | Produce normalized side-by-side comparisons for every remaining mobile route and material state. | RT-001 through RT-004 and final route states. | Same viewport/state source and implementation composites; all P0-P2 mismatches closed. | Product Design / Flutter | Open |
| RT-006 | P1 | Complete public-site and Admin-PWA normalized visual comparisons. | E-058 supplies fresh local compact/tablet/desktop public screenshots; E-059/E-060 supply accepted representative and complete authenticated operational Admin sets. They have not been normalized against verified Revolut references and do not cover a deployed host. | Responsive comparison set with mismatch disposition. | Product Design / QA | In progress; local browser capture complete for public and authenticated Admin operations, reference comparison open |
| RT-007 | P1 | Expand `design-qa.md` to the full goal and change its final result only after all visual gates pass. | RT-001 through RT-006 and the matrix tasks below. | Report ends exactly `final result: passed` with direct evidence for each claim. | Product Design | Blocked |

## B. Mobile route, state, and live-behavior validation

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-008 | P1 | Rerun the hardened 35-route Android device matrix. | E-049 completes the controlled Android 16 emulator matrix. E-063 identifies the exact connected Google Pixel 4a (`13111JEC215558`, `sunfish`, Android 13/API 33), but its secure lock screen triggered the hardened preflight and recorded `runner=not_started`; physical confirmation still requires an unlocked owner window. | Flutter completion marker, exactly 35 route-pass markers, unlocked post-run state, and retained screenshots/logs. | QA / device owner | Completed locally on controlled emulator; exact physical Pixel present but securely locked, so physical confirmation remains open |
| RT-009 | P1 | Exercise Android permission-dialog UX for Camera and Notifications, including deny, retry, and recovery. | E-054 completes native Notifications denial/retry/grant; E-056 completes native Camera denial, Collect privacy education, retry, grant, and recovered scanner with four retained screenshots. E-050 proves restricted SMS is absent. | Dialog screenshots, state transitions, and no restricted SMS permission. | QA | Completed locally on the controlled emulator; physical confirmation remains RT-008 |
| RT-010 | P1 | Validate SMS/contribution lifecycle behavior without reading SMS content: handoff, pending, confirmed, expired, duplicate, failed, and recovery states. | Controlled test backend/device data; no real payment. | End-to-end logs and screenshots proving privacy boundaries and ledger truth. | Flutter / QA | Open |
| RT-011 | P1 | Validate authentication, group lifecycle, contribution, offline/stale-cache, sync, and recovery against a controlled backend. | Approved non-production environment and test identities. | Route-by-route integration evidence with no production mutation. | Flutter / QA | Open |
| RT-012 | P1 | Exercise network loss/restoration while key routes are open. | Device/emulator network controls. | Offline, stale-cache, retry, and resync evidence with preserved state. | QA | Open |

## C. Responsive, theme, and platform matrix

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-013 | P1 | Complete full-route iOS checks at compact, standard, large-phone, and tablet targets. | Complete: the same fail-closed 35-route integration matrix passes on iPhone SE (3rd generation, 375x667 logical compact viewport), iPhone 17 Pro, iPhone 17 Pro Max, and iPad Pro 11-inch. Each target retains 35 screenshots with 26 distinct visual states. Compact review found an ellipsized Ledger total; the layout and regression were fixed and the native compact matrix was recaptured with the full amount visible. | Route matrix with screenshots and no overflow, clipping, unsafe-area, or navigation defects. | QA | Completed locally |
| RT-014 | P1 | Complete Android compact/large viewport checks. | E-049 covers the Pixel 4a-profile standard and 200%-text variants across all routes. E-053 adds 1440x3120 at 420 dpi System-Light/System-Dark runs with 35 retained screenshots each and closes the Settings contrast defect. | Critical-route screenshots and interaction smoke at both sizes. | QA | Completed locally on controlled Android emulator; physical-device confirmation remains RT-008 |
| RT-015 | P1 | Complete Light, Dark, and System matrices on Android and tablet, then spot-check all core routes on iOS. | All 35 member routes pass deterministic widget matrices; E-021 proves persisted System selection and native iOS response; E-035 adds native Light iPhone; E-049/E-053 add Android Dark/Light/System; E-055 adds current-source iPhone Dark/System-Light and iPad System across all 35 routes. | Persisted selection, platform response, contrast, and route screenshots. | QA | Completed locally for the controlled Android/iOS simulator matrix; physical confirmation remains separate |
| RT-016 | P1 | Capture native high-contrast behavior where supported for member and Admin surfaces. | E-035 passes all 35 iPhone routes with high contrast; E-049 passes all 35 Android routes with the framework high-contrast feature forced; E-055 passes all 35 iPad routes with framework high contrast, System mode, 200% text, and reduced motion. Platform-setting screenshots, Admin browser/native-equivalent evidence, and assistive-technology traversal remain. | Platform-setting selection plus readable boundary/focus screenshots. | QA | In progress; controlled iPhone, Android, and iPad full-route variants complete |
| RT-017 | P1 | Validate reduced-motion behavior for navigation, sheets, lists, and amount entry. | E-046 proves zero-duration detail navigation, immediate modal open/close, immediate Activity list-filter selection, and zero-duration amount-receiver controls while a paired normal-motion regression preserves route animation. Every owned modal sheet, the Admin dialog, route controller, implicit animation, and keyboard-inset path now use the centralized motion policy. All 35 routes also render under reduced motion in the compact widget and E-035 native iPhone matrices. | Motion comparison and confirmation that core feedback remains understandable. | QA | Completed locally for Flutter interaction scope |
| RT-018 | P1 | Complete large-text checks across the core mobile route matrix. | All 35 routes pass compact 200% widget coverage, the corrected E-035 native iPhone matrix at 320%, E-049 controlled Android at 200%, and E-055 iPad at 200%. E-055 exposed and closed the truncated auth wordmark; E-063 then exposed and closed iPhone Home quick-action truncation at the platform Large/1.2-text setting, added a max-lines regression, and accepted a fresh 35/35 Dark route recapture. Assistive-technology traversal remains under RT-020/RT-021. | No clipped, hidden, or unreachable primary content; retained screenshots/tests. | Flutter / QA | Completed locally for controlled iPhone, Android, and iPad route matrices, including E-063 iPhone Large text |
| RT-019 | P1 | Complete Flutter-web responsive coverage for public and Admin at compact, tablet, and desktop sizes. | E-058 passes 16 public routes x 3 viewports. E-062 supersedes the local Admin rerun and passes all 23 routes x 3 viewports with 69 screenshots, including login/denied navigation-absent contracts, authenticated navigation, route semantics, target measurement, and no horizontal overflow. Deployed-host verification remains separately governed under RT-043. | Browser screenshots, interaction smoke, and no horizontal/vertical content loss. | QA | Completed locally |

## D. Accessibility and interaction

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-020 | P1 | Run VoiceOver traversal on iOS for authentication, five-tab shell, group, contribution, ledger, settings, and error states. | E-037 statically verifies stable labels and semantic tap actions across these critical routes; an actual simulator or physical iOS accessibility session is still required. | Reading-order, label, state, action, and focus evidence with defects closed. | QA | In progress; static semantics complete, VoiceOver traversal open |
| RT-021 | P1 | Run TalkBack traversal on Android for the same critical flows. | E-064 binds TalkBack 16 with touch exploration on the controlled Pixel 4a-profile emulator, captures real focus/tree evidence, and closes redundant Home/Groups toolbar plus duplicate hero-action announcements. Authentication, contribution, ledger, settings, error/recovery, continuous swipe order, action completion, spoken-output review, and physical confirmation remain. | Reading-order, label, state, action, and focus evidence with defects closed. | QA | In progress; Home/Groups chrome and hero-action semantics pass under actual controlled-emulator TalkBack |
| RT-022 | P1 | Verify web/Admin keyboard operation: skip/navigation order, menus, dialogs, tables, bulk actions, and visible focus. | E-058 passes public keyboard traversal/visible focus. E-062 preserves named traversal across all 23 Admin routes plus keyboard login advance, both denied recovery actions, navigation/table-record activation, filtered current-page export with live feedback and retained focus, payment-dialog cancellation with trigger focus restoration, accountable-purpose selection, sensitive reveal, and live-region result across compact/tablet/desktop. | Keyboard-only completion of core flows with screenshots/log. | QA | Completed locally |
| RT-023 | P1 | Verify target sizes, contrast, live regions, and focus restoration on native and web surfaces. | E-040 numerically enforces 4.5:1 text and 3:1 essential-control/focus roles. E-042 enforces 48 dp primary and 44 dp dense-icon targets across all 35 member routes, every full-height public route, compact Admin, shared Material themes, custom tap surfaces, and source literals. E-058 adds public named controls/visible focus. E-062 measures 1,138 visible enabled Admin targets across 69 Chrome route/viewport results with zero genuine sub-44 CSS-pixel violations. E-064 adds actual TalkBack focus evidence for individual Home/Groups top-chrome controls and removes the redundant whole-toolbar focus stop. Broader native rendered-target measurement and focus restoration remain open. | Measured WCAG-equivalent contrast and target results; semantics/focus regressions plus native/browser evidence. | QA / Flutter | In progress; numeric contracts, complete local Admin browser measurement, and scoped Android TalkBack focus pass; broader native measurement/focus closure open |
| RT-024 | P2 | Validate browser/screen-reader behavior for public policies and representative Admin tables. | E-058 exposes public Chrome accessibility trees; E-062 preserves exact AX-name and unnamed-control checks across all 23 Admin routes while adding rendered target measurement, and I-049 is closed. This is not actual VoiceOver/NVDA/JAWS traversal. | Traversal evidence and issue disposition. | QA | In progress; browser accessibility trees complete locally, screen-reader speech/traversal open |

## E. Performance and reliability

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-025 | P1 | Run the hardened Android native profiler on an unlocked Pixel. | E-052 completes clean and repeated unlocked controlled-emulator runs with verified v2 target identity, six scenarios, 502/504 Flutter frames, representative gfxinfo, and 2,447,507/2,204,852-byte Perfetto traces. E-063 confirms the exact physical Pixel is connected but securely locked; no profiler was started. | Completed Flutter marker, Perfetto trace, representative frame metrics, unlocked post-run state on the physical target. | QA / device owner | Controlled-emulator evidence complete; exact physical Pixel present but securely locked, so repetition remains blocked |
| RT-026 | P1 | Profile startup, dense Activity/Groups scrolling, amount-entry rebuilds, route transitions, and sheet animations. | E-052 supplies two complete v2-target metric tables and traces, closes stale-target governance under I-041, corrects UI/raster versus total-span interpretation, and closes I-042 for the controlled-emulator scope. | Metric table, traces, thresholds, regressions fixed or explicitly accepted. | Flutter / QA | Completed locally; physical confirmation remains under RT-025 and reliability scope under RT-027 |
| RT-027 | P2 | Record crash/ANR and long-session reliability evidence. | The Play Developer Reporting collector now fails closed with structured output when `gcloud`/OAuth is unavailable and enumerates crash, ANR, startup, rendering, wakeup, and wakelock metric sets. A controlled device run and authorized reporting access remain required. | Local crash/ANR assessment, long-session result, and authorized reporting snapshot with scope limitations stated. | QA / Release owner | In progress; reporting auth external |
| RT-028 | P2 | Validate recovery after app background/foreground, process restart, and interrupted intents. | E-057 combines the existing launch/resume, paused-state, overlap, failure-containment, and retry regressions with controlled Android process death, distinct cold restart, warm same-process App Link delivery, matching-only clear, and no-replay evidence. The fixture harness refuses physical targets and performs no production mutation. | State-restoration and no-duplication evidence. | Flutter / QA | Completed locally for widget and controlled-emulator scope; physical/live-backend confirmation remains separate |

## F. Security, privacy, dependency, and policy

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-029 | P1 | Re-run final secret, private-data, unsupported-brand, and debug-fixture scans after all source changes. | E-045 adds one fail-closed, CI-wired current-source gate covering exclusive Inter, official-logo identity, prohibited product artwork, legacy typography/SVG/avatar paths, centralized feature typography, controlled font declarations, fixture isolation, tracked/untracked secret patterns, and product-boundary copy. Its machine-readable outputs pass with 0 failures, and all 86 non-failing risk markers have explicit safe dispositions without printing values. Repeat only after later material source changes. | Clean machine-readable scan outputs with reviewed exceptions. | Security / Flutter | Completed for current source state |
| RT-030 | P2 | Refresh the dependency, licence, vulnerability, and store-policy assessment against the final release graph. | The current graph is assessed in `DEPENDENCY_LICENSE_POLICY_ASSESSMENT.md`: compatible upgrades and `file_saver` 0.4.0 are applied, `app_links` 7.2.1 is explicitly governed for recoverable native link intake, the unused platform-icon font dependency is removed, all 18 direct runtime licences are permissive, the resolver reports no advisory/discontinued/retracted package, and current Apple/Google policy controls are mapped. Any later package or store-rule change requires refresh. | Final resolver output, licence inventory, vulnerability result, policy checklist, and accountable store-form disposition. | Security / Release | Completed for current graph; final-release refresh required |
| RT-031 | P2 | Obtain accountable approval of the verified production-package permission mapping. | The rebuilt production APK for `app.cool.mobile` targets SDK 36, verifies with APK Signature Scheme v2, and contains only network state, Camera, Internet, Notifications, Vibrate, and the app-scoped receiver-protection permission; restricted SMS, broad media, and legacy storage permissions are absent. Store-form disposition remains external. | Release-owner/privacy approval tied to the current artifact hashes and store declarations. | Release / QA | Completed locally; final store approval external |
| RT-032 | P2 | Revalidate receiver-detail privacy, ledger authorization, deletion request, and audit boundaries in native integration flows. | Controlled backend/device environment. | Negative-path evidence showing fail-closed behavior. | Security / QA | Open |

## G. Build and release hardening

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-033 | P2 | Run iOS release/archive checks and document signing status. | The generic-device Release archive passes unsigned; the configured signed attempt fails because the available wildcard provisioning profile lacks Associated Domains. Compatible profile creation and distribution require release-owner Apple account authority. | `IOS_RELEASE_ARCHIVE_ASSESSMENT.md`, retained unsigned archive, hashes, dSYM UUID, and exact signed-archive diagnostic. | Release | Completed locally; external signing blocked |
| RT-034 | P2 | Run iOS physical-device UAT. | Provisioned physical device and signing authority. | Critical-flow, theme, accessibility, lifecycle, and permission evidence. | QA / Release owner | External |
| RT-035 | P2 | Configure and verify the expected Android upload-certificate fingerprint. | Release-owner confirmation of the controlled certificate. | Pin configured and preflight matches the controlled certificate. | Release owner | External |
| RT-036 | P2 | Disposition strict Android bundle-signature warnings. | Release certificate/process confirmation. | Documented chain/timestamp decision and final verification output. | Release owner | External |
| RT-037 | P2 | Close the remaining legacy Kotlin Gradle Plugin warnings. | The E-065 release build prints warnings for `file_saver` and `mobile_scanner`; the stricter compatibility scanner still detects direct Kotlin-plugin markers in six resolved plugins: `file_saver`, `image_picker_android`, `mobile_scanner`, `share_plus`, `shared_preferences_android`, and `url_launcher_android`. | Upstream migrated releases or reviewed controlled vendor forks using built-in Kotlin; compatibility gate clean. | Flutter / upstream owners | Upstream-dependent; two build warnings and six scanner-detected direct implementations remain |
| RT-038 | P2 | Rebuild final public site, Admin PWA, Android APK/AAB, and iOS targets after all material changes. | E-065 records clean current-source public/Admin/Android rebuilds, a current iOS Simulator build, and a current unsigned generic-device archive. All nine retained Android/Admin artifacts are fresh; packaged payload inspection rejects the removed semantics text and unapproved font/artwork. | Fresh logs and hashes for every final artifact; complete Admin PWA wrapper output; signed-platform disposition; no unexplained warnings/failures. | Release / Flutter | Completed locally under E-065; external signed iOS distribution remains blocked under RT-033/RT-043 |
| RT-039 | P2 | Run final formatting, analysis, full tests, coverage, integration, source/security, and repository QA gates. | E-065 passes the Flutter 3.44.4 canonical suite with 433 tests and 78.30% coverage, artifact freshness, source hygiene, analysis, formatting, and patch hygiene. Earlier integration/browser/native results remain explicitly scoped evidence. | All required commands pass; manifest and hashes refreshed. | Flutter / QA | Completed for current local source under E-065; physical-device, backend, deployed-host, and external-account gates retain their own task rows |

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
| RT-046 | P1 | Refresh all registers, hashes, comparison indexes, rollback notes, and the release-readiness matrix. | E-048 machine-checks contiguous inventories and fail-closed sentinels. E-065 is the current local source/artifact snapshot: E-001..E-065, I-001..I-052, 433 tests, 78.30% coverage, fresh hashes, current unsigned iOS archive, and explicit external limitations. E-041 remains the Mirroring blocker for missing Revolut reference states. | Cross-referenced evidence pack with no stale claims. | QA | Completed for the E-065 local snapshot; refresh again after the next material evidence or artifact change |
| RT-047 | P1 | Create the final requirement-by-requirement completion audit. | The current-state audit maps every goal workstream, deliverable, gate, constraint, and blocker. E-048 now rejects identifier drift and premature passing sentinels. The audit cannot pass while required external/device/browser/reference evidence remains incomplete. | `FINAL_COMPLETION_AUDIT.md` maps every goal requirement to direct evidence. | Flutter lead | Completed as a fail-closed current-state audit; outcome remains blocked |
| RT-048 | External | Obtain Product Design, engineering, security/privacy, release, and product-owner acceptance for their respective gates. | Complete evidence pack; the recorded Android signing and release-owner approvals are explicitly for `1.2.2+9`, while the current artifact is `1.2.2+10`. Shared gates now reject those stale approvals. | Named approvals tied to `1.2.2+10` and its current hashes, plus accepted residual risks. | Accountable reviewers | Open external gate; fresh artifact-bound approvals required |

## Immediate execution order

1. Obtain the missing matched Revolut references and finish mobile comparisons.
2. With browser permission, complete public/Admin responsive, keyboard,
   accessibility, and visual QA.
3. During an approved unlocked physical-device window, repeat the already
   accepted controlled-emulator Android route, permission, theme/accessibility,
   QR-detection, and native-performance checks.
4. Complete VoiceOver and TalkBack traversal plus physical-device reduced-
   motion, focus, target, and lifecycle confirmation; E-055 and E-063 close the
   current-source iPhone/iPad simulator route variants, including iPhone
   platform Large/1.2-text Home labels.
5. Complete controlled-backend lifecycle/offline/privacy integration evidence.
6. Refresh the deployed Admin host from the verified local PWA wrapper; obtain
   authorized Play reporting/Console evidence.
7. Resolve final signing, upload-certificate, Kotlin-plugin, and policy
   dispositions.
8. Re-run final gates after any later material source change, complete the
   final audit, and seek fresh artifact-bound `1.2.2+10` approvals.

## Truthful completion boundary

Local engineering completion does not authorize production mutation, real
payment execution, store upload, public deployment, or signing on the user's
behalf. Those items remain explicit external gates even if every local task
passes.
