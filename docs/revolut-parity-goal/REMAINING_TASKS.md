# Remaining Task Register

## Status at 2026-07-25

The current checkout has passed formatting, static analysis, 412 automated
tests with 77.83% line coverage, the numeric contrast and interaction-target
contracts, the 13-surface
golden matrix, the focused typography/asset contracts, the rebuilt static
public-site quality gate, the complete local Admin PWA wrapper, and fresh
Android production APK/AAB builds, and a current-source compile-only iOS
Simulator bundle with governed payload inspection. Retained iOS matrices cover
their recorded source states; current-source native recapture and extra
tablet/System variants remain open under intermittent I-027. The deployed Admin
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
| RT-006 | P1 | Complete public-site and Admin-PWA normalized visual comparisons. | Browser-level capture requires user permission under the selected design workflow. | Responsive comparison set with mismatch disposition. | Product Design / QA | Permission required |
| RT-007 | P1 | Expand `design-qa.md` to the full goal and change its final result only after all visual gates pass. | RT-001 through RT-006 and the matrix tasks below. | Report ends exactly `final result: passed` with direct evidence for each claim. | Product Design | Blocked |

## B. Mobile route, state, and live-behavior validation

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-008 | P1 | Rerun the hardened 35-route Android device matrix. | E-049 completes the controlled Android 16 emulator matrix; physical Pixel confirmation still requires an unlocked owner window. | Flutter completion marker, exactly 35 route-pass markers, unlocked post-run state, and retained screenshots/logs. | QA / device owner | Completed locally on controlled emulator; physical-device confirmation open |
| RT-009 | P1 | Exercise Android permission-dialog UX for Camera and Notifications, including deny, retry, and recovery. | E-054 completes the native Notifications deny/retry/grant sequence and closes the recovery lifecycle defects on the controlled emulator. E-050 proves restricted SMS is absent. Native Camera denial/retry and retained permission-dialog screenshots remain. | Dialog screenshots, state transitions, and no restricted SMS permission. | QA | In progress; Notifications complete, Camera/screenshots open |
| RT-010 | P1 | Validate SMS/contribution lifecycle behavior without reading SMS content: handoff, pending, confirmed, expired, duplicate, failed, and recovery states. | Controlled test backend/device data; no real payment. | End-to-end logs and screenshots proving privacy boundaries and ledger truth. | Flutter / QA | Open |
| RT-011 | P1 | Validate authentication, group lifecycle, contribution, offline/stale-cache, sync, and recovery against a controlled backend. | Approved non-production environment and test identities. | Route-by-route integration evidence with no production mutation. | Flutter / QA | Open |
| RT-012 | P1 | Exercise network loss/restoration while key routes are open. | Device/emulator network controls. | Offline, stale-cache, retry, and resync evidence with preserved state. | QA | Open |

## C. Responsive, theme, and platform matrix

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-013 | P1 | Complete full-route iOS checks at compact, standard, large-phone, and tablet targets. | Complete: the same fail-closed 35-route integration matrix passes on iPhone SE (3rd generation, 375x667 logical compact viewport), iPhone 17 Pro, iPhone 17 Pro Max, and iPad Pro 11-inch. Each target retains 35 screenshots with 26 distinct visual states. Compact review found an ellipsized Ledger total; the layout and regression were fixed and the native compact matrix was recaptured with the full amount visible. | Route matrix with screenshots and no overflow, clipping, unsafe-area, or navigation defects. | QA | Completed locally |
| RT-014 | P1 | Complete Android compact/large viewport checks. | E-049 covers the Pixel 4a-profile standard and 200%-text variants across all routes. E-053 adds 1440x3120 at 420 dpi System-Light/System-Dark runs with 35 retained screenshots each and closes the Settings contrast defect. | Critical-route screenshots and interaction smoke at both sizes. | QA | Completed locally on controlled Android emulator; physical-device confirmation remains RT-008 |
| RT-015 | P1 | Complete Light, Dark, and System matrices on Android and tablet, then spot-check all core routes on iOS. | All 35 member routes pass deterministic widget matrices; E-021 proves persisted System selection and native iOS response; E-035 adds native Light iPhone; E-049 adds Android Dark/Light; E-053 adds native Android System-Light/System-Dark across all 35 routes. The excluded iPad/System variants and final iOS spot checks remain. | Persisted selection, platform response, contrast, and route screenshots. | QA | In progress; Android Light/Dark/System and iPhone Light complete, iPad/System open |
| RT-016 | P1 | Capture native high-contrast behavior where supported for member and Admin surfaces. | E-035 passes all 35 iPhone routes with high contrast; E-049 passes all 35 Android routes with the framework high-contrast feature forced; the tablet widget matrix asserts the token layer. Platform-setting screenshots, Admin browser/native-equivalent evidence, and assistive-technology traversal remain. | Platform-setting selection plus readable boundary/focus screenshots. | QA | In progress; iPhone and controlled Android full-route variants complete |
| RT-017 | P1 | Validate reduced-motion behavior for navigation, sheets, lists, and amount entry. | E-046 proves zero-duration detail navigation, immediate modal open/close, immediate Activity list-filter selection, and zero-duration amount-receiver controls while a paired normal-motion regression preserves route animation. Every owned modal sheet, the Admin dialog, route controller, implicit animation, and keyboard-inset path now use the centralized motion policy. All 35 routes also render under reduced motion in the compact widget and E-035 native iPhone matrices. | Motion comparison and confirmation that core feedback remains understandable. | QA | Completed locally for Flutter interaction scope |
| RT-018 | P1 | Complete large-text checks across the core mobile route matrix. | All 35 routes pass compact 200% widget coverage, the corrected E-035 native iPhone matrix at 320%, and the E-049 controlled Android matrix at 200%. Tablet, assistive-technology, and retained interaction-review variants remain. | No clipped, hidden, or unreachable primary content; retained screenshots/tests. | Flutter / QA | In progress; iPhone 320% and Android 200% full-route variants complete |
| RT-019 | P1 | Complete Flutter-web responsive coverage for public and Admin at compact, tablet, and desktop sizes. | Browser automation requires user permission. | Browser screenshots, interaction smoke, and no horizontal/vertical content loss. | QA | Permission required |

## D. Accessibility and interaction

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-020 | P1 | Run VoiceOver traversal on iOS for authentication, five-tab shell, group, contribution, ledger, settings, and error states. | E-037 statically verifies stable labels and semantic tap actions across these critical routes; an actual simulator or physical iOS accessibility session is still required. | Reading-order, label, state, action, and focus evidence with defects closed. | QA | In progress; static semantics complete, VoiceOver traversal open |
| RT-021 | P1 | Run TalkBack traversal on Android for the same critical flows. | Unlocked Android device/emulator. | Reading-order, label, state, action, and focus evidence with defects closed. | QA | Open |
| RT-022 | P1 | Verify web/Admin keyboard operation: skip/navigation order, menus, dialogs, tables, bulk actions, and visible focus. | Browser automation requires user permission. | Keyboard-only completion of core flows with screenshots/log. | QA | Permission required |
| RT-023 | P1 | Verify target sizes, contrast, live regions, and focus restoration on native and web surfaces. | E-040 numerically enforces 4.5:1 text and 3:1 essential-control/focus roles. E-042 enforces 48 dp primary and 44 dp dense-icon targets across all 35 member routes, every full-height public route, compact Admin, shared Material themes, custom tap surfaces, and source literals. Native/browser target measurement, focus restoration, and live-region evidence still needs device/browser access. | Measured WCAG-equivalent contrast and target results; semantics/focus regressions plus native/browser evidence. | QA / Flutter | In progress; numeric contrast and full local target contract complete |
| RT-024 | P2 | Validate browser/screen-reader behavior for public policies and representative Admin tables. | Browser and assistive-technology access. | Traversal evidence and issue disposition. | QA | Open |

## E. Performance and reliability

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-025 | P1 | Run the hardened Android native profiler on an unlocked Pixel. | E-052 completes clean and repeated unlocked controlled-emulator runs with verified v2 target identity, six scenarios, 502/504 Flutter frames, representative gfxinfo, and 2,447,507/2,204,852-byte Perfetto traces; the connected physical Pixel was not used. | Completed Flutter marker, Perfetto trace, representative frame metrics, unlocked post-run state on the physical target. | QA / device owner | Controlled-emulator evidence complete; physical-Pixel repetition blocked |
| RT-026 | P1 | Profile startup, dense Activity/Groups scrolling, amount-entry rebuilds, route transitions, and sheet animations. | E-052 supplies two complete v2-target metric tables and traces, closes stale-target governance under I-041, corrects UI/raster versus total-span interpretation, and closes I-042 for the controlled-emulator scope. | Metric table, traces, thresholds, regressions fixed or explicitly accepted. | Flutter / QA | Completed locally; physical confirmation remains under RT-025 and reliability scope under RT-027 |
| RT-027 | P2 | Record crash/ANR and long-session reliability evidence. | The Play Developer Reporting collector now fails closed with structured output when `gcloud`/OAuth is unavailable and enumerates crash, ANR, startup, rendering, wakeup, and wakelock metric sets. A controlled device run and authorized reporting access remain required. | Local crash/ANR assessment, long-session result, and authorized reporting snapshot with scope limitations stated. | QA / Release owner | In progress; reporting auth external |
| RT-028 | P2 | Validate recovery after app background/foreground, process restart, and interrupted intents. | Widget lifecycle coverage now proves launch/resume sync, paused-state exclusion, overlap coalescing, failure containment, and later retry; operating-system process death and interrupted native intents still require device controls and safe fixtures. | State-restoration and no-duplication evidence. | Flutter / QA | In progress |

## F. Security, privacy, dependency, and policy

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-029 | P1 | Re-run final secret, private-data, unsupported-brand, and debug-fixture scans after all source changes. | E-045 adds one fail-closed, CI-wired current-source gate covering exclusive Inter, official-logo identity, prohibited product artwork, legacy typography/SVG/avatar paths, centralized feature typography, controlled font declarations, fixture isolation, tracked/untracked secret patterns, and product-boundary copy. Its machine-readable outputs pass with 0 failures, and all 86 non-failing risk markers have explicit safe dispositions without printing values. Repeat only after later material source changes. | Clean machine-readable scan outputs with reviewed exceptions. | Security / Flutter | Completed for current source state |
| RT-030 | P2 | Refresh the dependency, licence, vulnerability, and store-policy assessment against the final release graph. | The current graph is assessed in `DEPENDENCY_LICENSE_POLICY_ASSESSMENT.md`: compatible upgrades and `file_saver` 0.4.0 are applied, the unused platform-icon font dependency is removed, all 17 direct runtime licences are permissive, the resolver reports no advisory/discontinued/retracted package, and current Apple/Google policy controls are mapped. Any later package or store-rule change requires refresh. | Final resolver output, licence inventory, vulnerability result, policy checklist, and accountable store-form disposition. | Security / Release | Completed for current graph; final-release refresh required |
| RT-031 | P2 | Obtain accountable approval of the verified production-package permission mapping. | The rebuilt production APK for `app.cool.mobile` targets SDK 36, verifies with APK Signature Scheme v2, and contains only network state, Camera, Internet, Notifications, Vibrate, and the app-scoped receiver-protection permission; restricted SMS, broad media, and legacy storage permissions are absent. Store-form disposition remains external. | Release-owner/privacy approval tied to the current artifact hashes and store declarations. | Release / QA | Completed locally; final store approval external |
| RT-032 | P2 | Revalidate receiver-detail privacy, ledger authorization, deletion request, and audit boundaries in native integration flows. | Controlled backend/device environment. | Negative-path evidence showing fail-closed behavior. | Security / QA | Open |

## G. Build and release hardening

| ID | Priority | Remaining task | Dependency or blocker | Required exit evidence | Owner | Status |
|---|---|---|---|---|---|---|
| RT-033 | P2 | Run iOS release/archive checks and document signing status. | The generic-device Release archive passes unsigned; the configured signed attempt fails because the available wildcard provisioning profile lacks Associated Domains. Compatible profile creation and distribution require release-owner Apple account authority. | `IOS_RELEASE_ARCHIVE_ASSESSMENT.md`, retained unsigned archive, hashes, dSYM UUID, and exact signed-archive diagnostic. | Release | Completed locally; external signing blocked |
| RT-034 | P2 | Run iOS physical-device UAT. | Provisioned physical device and signing authority. | Critical-flow, theme, accessibility, lifecycle, and permission evidence. | QA / Release owner | External |
| RT-035 | P2 | Configure and verify the expected Android upload-certificate fingerprint. | Release-owner confirmation of the controlled certificate. | Pin configured and preflight matches the controlled certificate. | Release owner | External |
| RT-036 | P2 | Disposition strict Android bundle-signature warnings. | Release certificate/process confirmation. | Documented chain/timestamp decision and final verification output. | Release owner | External |
| RT-037 | P2 | Close the six-plugin legacy Kotlin Gradle Plugin warning. | Latest resolved releases of `file_saver`, `image_picker_android`, `mobile_scanner`, `share_plus`, `shared_preferences_android`, and `url_launcher_android` still apply KGP. | Upstream migrated releases or reviewed controlled vendor forks using built-in Kotlin; compatibility gate clean. | Flutter / upstream owners | Upstream-dependent |
| RT-038 | P2 | Rebuild final public site, Admin PWA, Android APK/AAB, and iOS targets after all material changes. | E-047 proves fresh local Admin and Android outputs plus a passing nine-artifact manifest after E-052. E-044 proves the retained current-source iOS compile-only scope without boot/install/launch. Retained iOS visual/archive evidence still predates I-030/E-043; current-source native recapture remains exposed to intermittent I-027, and signed iOS remains blocked by provisioning. | Fresh logs and hashes for every final artifact; complete Admin PWA wrapper output; signed-platform disposition; no unexplained warnings/failures. | Release / Flutter | Public/Admin/Android complete for current source; current-source iOS native recapture and external signing open |
| RT-039 | P2 | Run final formatting, analysis, full tests, coverage, integration, source/security, and repository QA gates. | Current source passes formatting, analysis, 412 tests, 77.83% coverage, E-052 repeat performance profiling, the consolidated E-045 source-hygiene gate, E-046 reduced-motion interaction coverage, numeric contrast and interaction-target contracts, the 13-surface golden matrix, native Light/accessibility integration, public/Admin gates, refreshed E-047 Android/Admin artifacts, and the universal contract. The nine-artifact manifest passes; final evidence consistency is rerun after the register refresh. | All required commands pass; manifest and hashes refreshed. | Flutter / QA | Current local source/artifact rerun passes; open device, browser, assistive-technology, backend, approval, and deployment matrices remain |

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
| RT-046 | P1 | Refresh all registers, hashes, comparison indexes, rollback notes, and the release-readiness matrix. | E-048 now machine-checks contiguous task/evidence/issue inventories, cross-references, coverage figures, release artifact hashes/sizes, and fail-closed sentinels. E-047 supplies the current artifact set and E-041 records the latest Mirroring blocker. | Cross-referenced evidence pack with no stale claims. | QA | Completed for the current evidence snapshot; rerun after any material change |
| RT-047 | P1 | Create the final requirement-by-requirement completion audit. | The current-state audit maps every goal workstream, deliverable, gate, constraint, and blocker. E-048 now rejects identifier drift and premature passing sentinels. The audit cannot pass while required external/device/browser/reference evidence remains incomplete. | `FINAL_COMPLETION_AUDIT.md` maps every goal requirement to direct evidence. | Flutter lead | Completed as a fail-closed current-state audit; outcome remains blocked |
| RT-048 | External | Obtain Product Design, engineering, security/privacy, release, and product-owner acceptance for their respective gates. | Complete evidence pack; the recorded Android signing and release-owner approvals are explicitly for `1.2.2+9`, while the current artifact is `1.2.2+10`. Shared gates now reject those stale approvals. | Named approvals tied to `1.2.2+10` and its current hashes, plus accepted residual risks. | Accountable reviewers | Open external gate; fresh artifact-bound approvals required |

## Immediate execution order

1. Obtain the missing matched Revolut references and finish mobile comparisons.
2. With browser permission, complete public/Admin responsive, keyboard,
   accessibility, and visual QA.
3. During an unlocked Pixel window, run the 35-route Android matrix, permission
   UX, theme/accessibility checks, and the native performance profile.
4. Extend the passed iPhone Light and combined accessibility route variants to
   native tablet/System variants and VoiceOver traversal.
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
