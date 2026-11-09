# BuriMunsi — all remaining tasks

**All 65 tasks still have open production acceptance criteria in implementation candidate v0.1.0, dated 6 November 2026.** This does **not** mean they all need to be built from scratch: **15 have tested components, 14 have unverified source, 7 require integration, 12 are partially complete, 16 are externally blocked, and 1 has its implementation decision recorded.** [login-390](https://drive.google.com/file/d/11LrITxsLyFYbaFDuULYhqXvok9l1MLIf/view)

The distinction matters: **there is not yet a verified Android APK, real PostgreSQL integration, installed-phone validation, or production deployment.** Passing component tests does not close those requirements.    VERIFICATION

**Priority:** **P0** means release-blocking work. **P1** remains required unless its documented conditional scope is explicitly excluded. “Component tested” below means bounded tests passed—not that the complete production task is finished. [home-staff-360](https://drive.google.com/file/d/1SEpQSClRr-dbkhiCoUhzGjq-cAL2PHcg/view)

## 1. Foundation and production decisions — T001–T006

The native packaging direction is already recorded. These tasks finish the actual production inputs, source reconciliation, and supporting decisions. [login-390](https://drive.google.com/file/d/11LrITxsLyFYbaFDuULYhqXvok9l1MLIf/view)

| Task                                                | Current status     | What remains                                                                                                                                                                                           |
| --------------------------------------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **T001 · P0 — Source and environment verification** | Partial            | Reconcile the implementation with the actual Collect working checkout, preserving unrelated changes. Record the current source, schema/migrations, deployed functions, and authenticated API behavior. |
| **T002 · P0 — Production configuration**            | Externally blocked | Supply the real BuriMunsi group ID, receiving-account ID, business wallet/SIM, member roster, Admin phone, and device custodian. Confirm ownership and operation of WhatsApp support **0780025501**.   |
| **T003 · P0 — Native packaging and receiver reuse** | Decision recorded  | Run the pinned receiver extraction against the actual Collect checkout and qualify the standalone Kotlin/Compose module. Preserve the existing queue and acknowledgement controls.                     |
| **T004 · P0 — Devices and distribution**            | Externally blocked | Select the receiving phone, supported staff phones, Android versions, and internal distribution method. Confirm the provisional SDK and application-ID configuration against those choices.            |
| **T005 · P0 — Automatic member-matching policy**    | Component tested   | Approve and demonstrate the trusted unique identity rule using actual payment evidence. Masked suffixes or names alone must not authorize credit.                                                      |
| **T006 · P1 — Branding, fonts, and icons**          | Partial            | Confirm asset rights and the native font mapping. Compare the rendered native application against the frozen BuriMunsi prototype.                                                                      |

## 2. Authentication and staff access — T007–T012

Phone/PIN services and several authorization controls have component tests. Their real database integration, provisioning, and native session behavior still need completion. [login-390](https://drive.google.com/file/d/11LrITxsLyFYbaFDuULYhqXvok9l1MLIf/view)

| Task                                                    | Current status       | What remains                                                                                                                                                                                                        |
| ------------------------------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **T007 · P0 — Phone and four-digit sign-in**            | Component tested     | Integrate authentication with the real Collect runtime and PostgreSQL; qualify native sign-in over TLS. Preserve phone-only login, exactly four digits, and leading zeroes.                                         |
| **T008 · P0 — Four-digit passcode security**            | Component tested     | Test distributed guessing and throttling against the actual database. Qualify device restrictions, lockout/recovery, generic failures, audit alerts, and credential-storage protections.                            |
| **T009 · P0 — Admin provisioning**                      | Integration required | Implement the admitted operator-principal and device-grant provisioning commands using the real Admin phone. Deliver the initial passcode securely without embedding a master credential in the app.                |
| **T010 · P0 — Staff lifecycle and passcode changes**    | Component tested     | Connect staff creation, editing, disabling, reactivation, removal, resets, and own-passcode changes to real principals and persistence. Verify session revocation and native interactions.                          |
| **T011 · P0 — Group and action authorization**          | Component tested     | Apply and test group, role, and capability restrictions across every integrated endpoint: lists, details, totals, search, exports, updates, and mutations. Prove Staff cannot access SMS or gateway administration. |
| **T012 · P0 — Native sessions and independent capture** | Source unverified    | Compile and test session expiry, reauthentication, revocation, and cache clearing. Prove staff sign-out does not delete the receiving queue or revoke the independent gateway credential.                           |

## 3. One receiving phone and Staff isolation — T013–T016

The source-set separation exists, but the server-side single-gateway rule and actual installed-device boundaries are not yet qualified. [login-390](https://drive.google.com/file/d/11LrITxsLyFYbaFDuULYhqXvok9l1MLIf/view)

| Task                                                      | Current status       | What remains                                                                                                                                                                                       |
| --------------------------------------------------------- | -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **T013 · P0 — Exactly one active receiving installation** | Integration required | Connect the singleton-binding logic to actual pairing and ingestion. Enforce it atomically; reject concurrent enrollment and second-phone uploads. Device replacement must revoke its predecessor. |
| **T014 · P0 — Business-SIM binding**                      | Source unverified    | Test subscription-to-SIM mapping on the real phone, including missing metadata, SIM replacement, and dual-SIM conditions. Never relabel queued receipts after a binding change.                    |
| **T015 · P0 — SMS-free Staff variant**                    | Component tested     | Build both variants and inspect merged manifests, packaged components, and executable contents. Install the Staff app and prove it cannot request, read, recover, or intercept SMS.                |
| **T016 · P0 — Device credentials and replacement**        | Source unverified    | Qualify protected keys, token rotation, lost-device revocation, backup exclusion, and replacement reconciliation. Restoring an app backup must not clone gateway authority.                        |

## 4. SMS capture, queue durability, and recovery — T017–T023

The candidate reuses Collect’s existing receiver rather than replacing it. Actual extraction, compilation, recovery integration, and phone testing remain. [login-390](https://drive.google.com/file/d/11LrITxsLyFYbaFDuULYhqXvok9l1MLIf/view) [member-390](https://drive.google.com/file/d/11NnB1l3ZCUGGjKSW9HNAx5XTGuDimLyX/view)

| Task                                                       | Current status     | What remains                                                                                                                                                                              |
| ---------------------------------------------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **T017 · P0 — Incoming SMS receiver**                      | Source unverified  | Extract and compile the pinned receiver files. Test actual M-Money sender IDs, complete and multipart messages, and bounded broadcast handling on the intended carrier/device.            |
| **T018 · P0 — SMS privacy filtering**                      | Component tested   | Validate the native filtering hook against approved real messages. Prove OTPs, promotions, unrelated SIM traffic, and personal messages never enter the cloud receipt queue.              |
| **T019 · P0 — Encrypted durable outbox**                   | Source unverified  | Prove local commit, encryption, ownership, and immutable capture/binding metadata survive process death, reboot, retries, corruption, and storage failures.                               |
| **T020 · P0 — Durable acknowledgement and retries**        | Component tested   | Exercise the real ingress and queue-retirement path, including server commit followed by lost acknowledgement, partial acknowledgements, reconnects, and repeated uploads.                |
| **T021 · P0 — Background scheduling and battery behavior** | Externally blocked | Measure background capture/recovery under Doze, battery saver, manufacturer restrictions, denied permissions, reboot, and force-stop. Document required unlock/reopen behavior.           |
| **T022 · P0 — Historical recovery and queue capacity**     | Partial            | Complete the authorized historical-release/backfill path. Test overlapping scans, deduplication, cutoffs, uncertain sources, queue saturation, disk-full behavior, and recovery alerts.   |
| **T023 · P1 — Gateway diagnostics**                        | Source unverified  | Validate actual capture/upload times, pending counts and age, SIM/permission/network state, and redacted support diagnostics. A heartbeat must not be mistaken for successful processing. |

## 5. API ingress, parsing, and processing — T024–T030

Parsing and processing components have tests, but the production route, retained-source reader, job-store integration, and real provider corpus remain outstanding. [member-390](https://drive.google.com/file/d/11NnB1l3ZCUGGjKSW9HNAx5XTGuDimLyX/view)

| Task                                                    | Current status       | What remains                                                                                                                                                                                                             |
| ------------------------------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **T024 · P0 — Production API origin**                   | Partial              | Qualify authenticated pairing, upload, status, heartbeat, and revocation at one fixed TLS origin. Verify expected JSON and durable outcomes—not merely an HTTP 200 response.                                             |
| **T025 · P0 — Source provenance and ingress admission** | Integration required | Connect authenticated binding, group/wallet scope, source hashes, and policy versions to existing ingress. Test forged claims, stale credentials, wrong-wallet uploads, and replay.                                      |
| **T026 · P0 — Real provider test messages**             | Externally blocked   | Obtain authorized examples from the intended wallet: full/masked numbers, FT Ids, numeric formats, languages, failed/pending messages, reversals, and multipart cases. Keep private fixtures out of public repositories. |
| **T027 · P0 — Deterministic M-Money parser**            | Component tested     | Validate the implemented English receipt parser against the approved corpus. Add only required supported formats, preserving exact source facts and rejecting unsupported or invalid messages.                           |
| **T028 · P0 — Canonical transaction identity**          | Component tested     | Connect the transaction/source adapter to PostgreSQL. Prove duplicate observations create one economic transaction and conflicting references cannot produce additional credits.                                         |
| **T029 · P0 — Processing worker and scheduler**         | Component tested     | Wire the admitted durable job store and worker into the current Collect scheduler. Prove retained receipts are processed, with leases, retries, failure isolation, and alerts.                                           |
| **T030 · P1 — Optional routing-reference support**      | Partial              | Decide whether a real supported member/payment reference exists. When used, preserve it through storage, matching, and audit; otherwise document full-identity matching. Do not introduce invented `BM` codes.           |

## 6. Automatic allocation and the canonical ledger — T031–T038

**T032 is a central unfinished engineering task:** the orchestration exists, but its actual shared Collect writer and database transaction adapter are not finished. These requirements do not introduce manual payment approval. [member-390](https://drive.google.com/file/d/11NnB1l3ZCUGGjKSW9HNAx5XTGuDimLyX/view)

| Task                                                    | Current status                          | What remains                                                                                                                                                                                            |
| ------------------------------------------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **T031 · P0 — Existing-member matching**                | Component tested                        | Connect verified, effective-dated payment identities and active memberships to actual transaction data. Validate unknown, ambiguous, and third-party payer cases without guessing beneficiaries.        |
| **T032 · P0 — Atomic automatic posting**                | **Integration required**                | Implement the real canonical-writer adapter. Commit allocation, contribution entry, balance result, audit event, and idempotency outcome atomically. No second ledger or mobile-side balance writer.    |
| **T033 · P0 — Single-step exception allocation**        | Component tested                        | Connect the allocation panel/service to that same writer. Verify permissions, current versions, simultaneous staff actions, timeouts, and safe retries without double credit or another approval stage. |
| **T034 · P1 — Rematching after member enrollment**      | Integration required                    | Implement the persistent eligible-rematch queue and identity integration. New membership alone must not claim historical receipts based on a matching name or suffix.                                   |
| **T035 · P0 — Authoritative balances and ledger reads** | Source unverified                       | Run and qualify the actual SQL readers and snapshots. Verify complete history, pagination, and balance semantics; never substitute SMS wallet balance or fabricated opening entries.                    |
| **T036 · P0 — Reversals, corrections, and late events** | Externally blocked; engineering remains | Agree supported rules and implement immutable compensating entries through the actual writer. Test duplicates, conflicts, and late events; unsupported events must fail safely.                         |
| **T037 · P0 — App/Admin/provider reconciliation**       | Externally blocked                      | Execute controlled deposits and confirm identical native App and Collect Admin results for the same group, member, filters, and time basis, with receipt-to-ledger evidence.                            |
| **T038 · P1 — Concurrency and capacity**                | Partial                                 | Measure real PostgreSQL contention, peak receipt load, and outage recovery. Establish measured processing and backlog-drain targets rather than relying on test-adapter concurrency results.            |

## 7. Member management and records — T039–T042

The outstanding work connects member commands and record services to the existing shared Collect model, then validates native use. [member-390](https://drive.google.com/file/d/11NnB1l3ZCUGGjKSW9HNAx5XTGuDimLyX/view)

| Task                                                   | Current status       | What remains                                                                                                                                                                                      |
| ------------------------------------------------------ | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **T039 · P0 — Direct-member onboarding**               | Integration required | Connect existing Collect person/Direct-member creation and membership commands. Verify normalized MoMo numbers, duplicate detection, and enrollment without a member-app account.                 |
| **T040 · P0 — Safe membership and identity edits**     | Integration required | Implement the group-local command adapter and rules for deactivation, identity changes, and number recycling. Preserve historical links and prevent unintended changes to people in other groups. |
| **T041 · P1 — Transaction lists, search, and exports** | Component tested     | Qualify real SQL pagination and filters, complete authorized exports, and native document sharing. Complete large-export handling where required; preserve original payer names and FT Ids.       |
| **T042 · P0 — Refresh and offline records**            | Source unverified    | Test encrypted cache expiry, read-only offline access, reconnection, pagination, and uncertain-operation recovery in Android. Queued SMS must not inflate displayed server balances.              |

## 8. Native UI, navigation, and accessibility — T043–T048

The native screens are written in source, but they have not been compiled and rendered for comparison with your approved prototype. [member-390](https://drive.google.com/file/d/11NnB1l3ZCUGGjKSW9HNAx5XTGuDimLyX/view)    04_Task_Status

| Task                                                   | Current status     | What remains                                                                                                                                                                                                         |
| ------------------------------------------------------ | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **T043 · P0 — Eight native screens**                   | Source unverified  | Compile and exercise Sign in, Home, Payments, Payment detail, Members, Member ledger, SMS, and Settings. Verify four-icon navigation and seven-route Staff access.                                                   |
| **T044 · P1 — Visual fidelity**                        | Source unverified  | Compare native colours, geometry, typography, icon controls, and single-line ellipses against the frozen prototype. Test 320–430px-equivalent widths and 200% text scaling without truncating financial identifiers. |
| **T045 · P1 — Contextual panels and Android behavior** | Source unverified  | Test allocation, onboarding, profile, passcode, staff, gateway, raw SMS, history, help, and filters. Repair back-button, keyboard, safe-area, scrolling, restoration, and process-recreation issues.                 |
| **T046 · P1 — Approved wording and receipt semantics** | Source unverified  | Run native assertions and visual checks for all approved changes: phone-only/four-digit login; no invented IDs or removed labels; correct Messages shortcut; unchanged original SMS.                                 |
| **T047 · P1 — Accessibility and support**              | Source unverified  | Test TalkBack, focus, touch targets, non-colour status, large fonts, reduced motion, and financial confirmations. Verify WhatsApp support ownership and fallback behavior without automatically sharing receipts.    |
| **T048 · P1 — Languages and notifications**            | Externally blocked | Confirm release languages, timezone/display conventions, number formatting, and member-notification scope. Implement approved localization without translating original receipt evidence.                            |

## 9. Security, reliability, and acceptance testing — T049–T056

Existing tests cover bounded components. Independent security testing, real database invariants, physical SMS journeys, and final native acceptance remain open.    04_Task_Status

| Task                                                          | Current status     | What remains                                                                                                                                                                                                                |
| ------------------------------------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **T049 · P0 — Privacy, retention, and operating obligations** | Externally blocked | Have the responsible owners confirm SMS-processing authority, staff/member access, hosting/processors, retention/deletion, incident procedures, and applicable Rwanda/BNR or sandbox obligations.                           |
| **T050 · P0 — Native security hardening**                     | Source unverified  | Verify actual Keystore/encrypted storage, TLS validation, backup exclusion, logs, clipboard/screenshot policy, and exported components. Inspect built artifacts for secrets and unintended cleartext paths.                 |
| **T051 · P0 — Independent authorization and abuse tests**     | Partial            | Test deployed and installed boundaries: cross-group access, Staff SMS denial, replay, revocation races, forged receipts, PIN spraying, cache leakage, and reset abuse. Resolve critical/high findings.                      |
| **T052 · P0 — Parser and financial invariants**               | Component tested   | Extend executed suites to the actual PostgreSQL writer and supported reversal rules. Prove exact amounts, correct identities, atomic rollback, reference-conflict rejection, and no duplicate credit.                       |
| **T053 · P0 — Real phone-to-ledger journeys**                 | Externally blocked | Run authorized contributions through the actual carrier, SIM, receiving phone, backend, ledger, and Collect Admin. Include a Staff phone proving zero SMS access.                                                           |
| **T054 · P0 — Interruption and upgrade tests**                | Partial            | Test real capture interruption, lost acknowledgements, posting timeouts, offline periods, wrong SIM, revoked credentials, disk/queue saturation, historical replay, reboot, force-stop, and upgrades with pending receipts. |
| **T055 · P1 — Release performance**                           | Externally blocked | Measure optimized release size, startup, scrolling, memory, battery, network use, and backlog recovery on the selected low-end phone. Agree performance budgets from those results.                                         |
| **T056 · P0 — Final native acceptance**                       | Externally blocked | Compare actual native screenshots and interactions against the frozen design across roles, states, and sizes. Obtain explicit operational and visual acceptance from the responsible owners.                                |

## 10. Build, deployment, release, and operations — T057–T065

The source candidate is not a deployed release. These tasks establish repeatable builds, controlled activation, signed distribution, recovery, and operational ownership.    04_Task_Status

| Task                                                           | Current status     | What remains                                                                                                                                                                                                          |
| -------------------------------------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **T057 · P1 — CI and reproducible builds**                     | Partial            | Restore a working runner; run builds, lint, tests, manifest/APK checks, and secret/dependency scans. Complete resolved dependency locks and the software bill of materials. Exclude demo/review code and credentials. |
| **T058 · P0 — Signing and release identities**                 | Externally blocked | Confirm package IDs/version codes and signing-key custody/recovery. Produce optimized, signed, non-debuggable receiving and Staff artifacts; verify safe upgrades.                                                    |
| **T059 · P0 — Distribution and permissions**                   | Externally blocked | Qualify the selected installation, device-management, permission-grant, revocation, and signed-update process. Complete channel-specific requirements if Play distribution is chosen.                                 |
| **T060 · P0 — Database migrations and activation**             | Partial            | Reconcile the additive schema with current Collect guards, rehearse migrations and backups in staging, deploy a versioned backend, and prove safe worker activation and rollback.                                     |
| **T061 · P0 — Monitoring and alerts**                          | Partial            | Deploy redacted monitoring for capture gaps, queue/job age, unallocated backlog, parser failures, reference conflicts, ledger drift, and rejected access. Set thresholds and test actual escalation.                  |
| **T062 · P0 — Disaster recovery and emergency stop**           | Partial            | Rehearse database restoration, receiver replacement, credential revocation, emergency pause, and recovery. Prove no evidence loss, cloned gateway, or duplicate credit.                                               |
| **T063 · P0 — Bounded production pilot**                       | Externally blocked | Authorize participants, transaction limits, monitoring period, success/stop criteria, and on-call ownership. Reconcile every controlled receipt before expanding rollout.                                             |
| **T064 · P0 — Operational handover and release authorization** | Externally blocked | Deliver signed-artifact checksums, backend identity, trained Admin/staff, support and recovery instructions, and the release decision. Close required tasks and all critical financial/access issues.                 |
| **T065 · P1 — Ongoing maintenance ownership**                  | Externally blocked | Assign responsibility and cadence for updates, credential rotation, device health, daily reconciliation, incident handling, backup drills, and version-controlled future UI changes.                                  |

## The unfinished engineering that must not be mistaken for “waiting on credentials”

The implementation package explicitly identifies these six work packages as **remaining engineering**, not simply external approvals:

| Package                                        | Work still required                                                                                                                                                    |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **I01 — Canonical writer**                     | Implement the real shared financial writer adapter, database transaction handling, and durable idempotency receipts for automatic and exception allocation.            |
| **I02 — Collect member and operator commands** | Connect Direct-member/principal creation, group-local membership commands, and persistent safe rematching.                                                             |
| **I03 — Runtime integration**                  | Implement retained-source decryption and lineage, trusted transaction scope, durable processing-job storage, single-gateway enforcement, and Edge request composition. |
| **I04 — Real database qualification**          | Reconcile and rehearse the proposed schema under current guards and row-level security; test actual PostgreSQL behavior instead of mocked SQL calls.                   |
| **I05 — Native completion**                    | Compile, repair, and qualify receiver integration and screen fidelity; finish required large exports, approved localization, and supported reversal behavior.          |
| **I06 — Release engineering**                  | Complete resolved dependency locks, build inventory, performance evidence, deployed monitoring, fault/restore rehearsals, and release automation.                      |

These are the package’s own outstanding-work definitions.    03_Blockers_and_Next_Actions

## External inputs and access needed

These were the **recorded blockers at the last implementation run**, not newly checked live conditions.    03_Blockers_and_Next_Actions

| Blocker                                   | What is needed                                                                                                                                 |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **E01 — Backend environment**             | Access to the correct Supabase project or a suitable non-production environment with the current schema and execution controls.                |
| **E02 — Build and database tools**        | A functioning Android SDK/Gradle build environment, emulator or device connection, and disposable PostgreSQL database.                         |
| **E03 — CI runner**                       | A functioning GitHub Actions runner and investigation of the run that stopped before executing steps. Its cause was not established.           |
| **E04 — Authoritative production inputs** | Real group, wallet, SIM, roster, Admin phone, device custodian, receiving/staff phones, and distribution choices.                              |
| **E05 — Approved evidence and decisions** | Real provider fixtures, trusted identity policy, asset rights, support-number ownership, and applicable language/reference/reversal decisions. |
| **E06 — Devices and release authority**   | Physical phones, authorization for controlled deposits, signing custody, privacy/security acceptance, and pilot/release authorization.         |
| **E07 — Actual Collect checkout**         | Access to and reconciliation with the working checkout previously referenced, preserving its unrelated changes.                                |