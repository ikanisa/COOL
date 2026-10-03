# Collect architecture, delivery and operations review — 1 October 2026

**Decision: production NO-GO.** The current source has substantial implemented controls and a useful test infrastructure. Its delivery scripts, CI graph, evidence organisation, native release governance and operational acceptance do not yet establish a repeatable, protected production system. This review preserves valid local progress and identifies the remaining delivery failures and verification gaps.

## Scope and evidence

This is the architecture/delivery contribution to the wider critical review. It covers repository structure, dependency provenance, toolchain reproducibility, CI, release tooling, Supabase deployment contracts, Admin hosting/cache updates, native platform distribution, observability, recovery, capacity and cleanup. The other contributions own financial/security logic and product/design inspection.

The review reuses the root's recursive Git-visible inventory, then manually inspects the current runtime structure and representative high-risk consumers. It is not a claim that every one of the 307,482 visible files was manually read or every possible state executed. The root's `repository-summary.json`, `repository-inventory.json.gz`, `source-baseline.json` and compressed Git-status evidence record the 17:28 UTC source snapshot. The runtime-only static results in `architecture-static-verification.json` count **269 Dart sources, 77 TypeScript sources and 12 actual Edge entrypoints**. Worktree changes remain review inputs; HEAD alone does not identify all tested inputs.

The source snapshot is based on main `df1150ea118aa5dcc9ecb880c71873423081bffe`. Root verification reports the local HEAD and remote main are equal, but the recursive worktree has 296,704 individual dirty entries: 201 modified, one deleted and 296,502 untracked. Collapsed Git status had obscured the scale. The report itself and concurrent report additions naturally add further untracked evidence paths.

The root's current strict Flutter analysis passed. Its readback of the earlier 16:21 UTC acceptance packet matched 444 of 462 bindings; 18 differed, including Flutter/theme/pubspec and unattended MCP sources. Earlier 657 Admin and 413 MCP cases therefore remain evidence for their declared inputs, rather than automatic current-tree passes. The MCP aggregate refresh timed out after 120 seconds with 253 observed passing assertion lines and no observed failing assertion; it is incomplete rather than a suite pass. Strict TypeScript checking passed. The bounded targeted refresh is recorded separately below. No production deployment, database write, provider send, Keychain login, scheduler activation, store upload, source fix or deletion was performed for this review.

## What is already useful

- The repository has separate member, Admin, public and gateway entrypoints, shared theme adapters, contracts, scoped SQL/HTTP/native tests, explicit release approval gates, secret scanning and source manifests.
- Flutter is pinned by `.fvmrc` to 3.44.4; Deno is pinned by `.dvmrc` to 2.5.6. Dart, Edge, Ruby, Node and native dependency locks/provenance are present. Android production compile/runtime configurations use strict dependency locking at `android/app/build.gradle.kts:414`.
- Third-party changes are owned source forks rather than edits to an SDK cache. Their scope and upstream limitations are documented. The file_saver fork has a published-package comparison script used by CI.
- GitHub actions are pinned by commit SHA, checkout does not retain credentials, most workflow permissions are read-only, and the manual Supabase audit has a production-readiness environment and exact-commit input.
- The Admin service worker intentionally caches static assets only, omits credentials during install, refuses redirects, removes only owned/retired caches and excludes API responses. Those are valuable controls that should survive cache refactoring.
- Android release signing is checked against distinct upload/Play certificate identities. Restricted native permissions are declared, obsolete external storage permissions are removed, Firebase analytics collection defaults off, and the unsigned-QA path places an explicit non-release marker into artifacts.
- Recovery documentation recognises that successful restore exit codes do not prove ACL preservation, that Storage bytes are separate and that restoration can revive obsolete sessions or approvals.

These are implemented controls or source observations. Protected-merge enforcement, fresh signed artifacts, deployed definitions, devices, providers, on-call delivery and owner release acceptance remain separate evidence requirements.

## Prioritised findings

Severity uses P0 for launch-blocking authority/integrity/recovery acceptance, P1 for a delivery failure or material production risk, and P2 for controlled maintainability work. A source-confirmed failure is distinguished from a risk awaiting execution evidence.

### ARC-01 — P1: Linux CI calls a developer-specific Dart path

**Source-confirmed wiring failure:** `Makefile:3` defaults DART to `/Users/jeanbosco/Developer/flutter/bin/dart`; `Makefile:79` exports that value to the formatter. `.github/workflows/ci.yml:171` runs `make format-check` on `ubuntu-latest` after installing Flutter in its action-managed location, without a DART override. The dry run prints exactly `DART="/Users/jeanbosco/Developer/flutter/bin/dart" ruby scripts/qa/dart_format.rb --check`.

The Make defaults and workflow invocation were rechecked at final report readback and remain unchanged. This prevents a clean Linux runner from executing the formatting gate even if the source is formatted. The Ruby script's normal `dart` fallback cannot apply because Make has already supplied the absolute path. The same defaults reduce portability of local Make analyze/test commands.

**Recommendation:** Resolve pinned Flutter/Dart executables through the approved environment/FVM or PATH; retain explicit overrides for operator use. Make CI invocation explicit and validate existence/version before collecting pass evidence. **Acceptance:** execute the actual Make command in a clean Ubuntu checkout and demonstrate the formatter rejects a deliberately malformed fixture, then passes the reviewed source. Do not remove the formatting gate.

### ARC-02 — P1: current source violates the repository's hard CI size gate

**Reproduced static gate condition:** `.github/workflows/ci.yml:106` rejects runtime files over 1,200 lines. Current non-generated files exceed it: `lib/shared/repositories/collect_repository.dart` 1,830; `lib/admin/core/admin_roster_import.dart` 1,554; `lib/admin/core/admin_runtime.dart` 1,501; `lib/admin/admin_shell.dart` 1,237. Another 43 Dart files are between 501 and 1,200 lines; six Edge TypeScript files exceed 500 lines but none exceeds 1,200.

The four named sizes were rechecked after the concurrent Admin runtime edit; they still exceed the hard gate. This is an actual current-candidate CI blocker, separate from whether large files are inherently defective. The main repository class owns Auth subscriptions, cache, member actions, financial history, permissions, notification registration and realtime generations. The Admin runtime imports roughly 60 collaborators and joins 36 part files; a part split retains private scope/coupling rather than establishing independent module boundaries (`lib/admin/core/admin_runtime.dart:12`, `:72`).

**Recommendation:** Extract owned typed services by capability: member/session lifecycle, history reads, notification preferences, receipt transport, roster preparation/recovery and Admin operation controllers. Keep the current public APIs initially; move one boundary with its consumers and behaviour tests. Do not simply raise the budget, add lint exclusions or cut files at arbitrary line positions. **Acceptance:** actual hard size gate, strict analysis and affected boundary/consumer regressions pass on one frozen source candidate; auth-generation and exactly-once semantics remain invariant.

### ARC-03 — P1: Edge deploy/readiness inventory is obsolete

**Source-confirmed integration gap:** `scripts/supabase_deploy.sh:12` and `scripts/supabase_production_readiness.sh:12` each list eight expected functions, while 12 runtime directories contain `index.ts`. They omit `collect-android-gateway`, `collect-receipt-exception-worker`, `collect-receipt-supervisor` and `reconciliation-finalize`.

The deploy loop at `supabase_deploy.sh:121` therefore leaves those four handlers unchanged or absent. The readiness script's exact inventory comparison at `supabase_production_readiness.sh:1147` rejects a complete 12-handler deployment as unexpected, while an eight-handler inventory may satisfy its inventory check. This is not proof of the actual hosted state. `supabase/config.toml:391`, `:395`, `:400` and `:418` already contains the four function authentication blocks; configuration existence does not cause the manual loop to deploy them.

**Recommendation:** Maintain one reviewed release manifest of active, staged and retired endpoints, authentication mode, supported caller, secret requirements and rollout order. Derive deployment and readiness inventories from that manifest. Include the new non-JWT signature/scheduler boundaries explicitly, and preserve their independent handler authentication. **Acceptance:** source/deploy/probe inventory equality, immutable function hashes, migrated SQL dependencies, scheduler configuration and denial/positive HTTP readback in approved staging; then perform an authorised production readback.

### ARC-04 — P1: CI does not use the current Edge lock/test contract

**Source-confirmed current test-contract failure and lock-enforcement gap:** `.github/workflows/ci.yml:431` invokes `deno test` from the root with selected environment permission only; `:439` invokes unqualified `deno check`. Neither names `supabase/functions/deno.lock` nor `--frozen`. No root Deno config selects that nested lock.

The evolving test cohort also needs explicit safe permissions/fixtures: `collect-receipt-exception-worker/handler_test.ts:111` starts a loopback server; `collect-android-gateway/dispatch_observed_test.ts:24` reads retained decoder fixtures; worker `observed_test.ts:3` takes an observation-directory argument. The current controlled runner (`scripts/qa/run_edge_unit_tests.py:74`) names the frozen lock, loopback/read allowlists and an accepted SQL-observation packet. The GitHub workflow is not equivalent to that runner. The worker observation test explicitly throws `observed_fixture_directory_required` if its missing directory argument is not supplied; that is deterministic for the current all-files command. Existing offline safe-test passes do not establish that the workflow passes.

**Recommendation:** Split provider-free unit/transport tests from dated SQL decoder and sandbox integrations, wire each explicit prerequisite and narrowly allowlisted permission into CI, and enforce the nested lock during compile and execution. Keep skipped integration scope visible. Deno documents explicit frozen locks for reproducible CI. [Deno dependency management](https://docs.deno.com/runtime/packages/)

**Acceptance:** fresh-cache clean-runner compilation and tests with exact lock/runtime and denied unexpected network/provider access, plus a corrupted-lock negative case; evidence-dependent tests consume a generated, immutable packet rather than silently skipping or borrowing an unexplained dated directory.

### ARC-05 — P1: deployment entrypoint does not bind mutations to approved source/artifacts

**Source-confirmed omission:** `scripts/supabase_deploy.sh:53` correctly confirms the exact project and `:58` checks the linked target/URL. It validates migrations and dry-runs DB push, but then applies DB changes, deletes retired endpoints and deploys handlers without invoking the release approval/source binding used by the Android release lane. It has no clean-worktree/expected-commit or immutable-source assertion before the first mutation. Its connectivity fallback at `:95` changes the migration transport and sets `readiness_strict_platform=0` for the final check.

Confirmation of the target is necessary but insufficient to establish that a reviewed candidate is being released. A partial schema/functions rollout or source drift during iteration can produce mixed versions. The fallback should be an explicit reviewed execution route; a weaker platform-readiness result must not become GO.

**Recommendation:** Add a backend-specific reviewed candidate preflight covering migration prerequisites, source hashes, exported handler closure, approval scope, compatibility and rollback/roll-forward. Release from an immutable export rather than the changing workspace. Keep post-deploy readback mandatory and record partial failure per operation. **Acceptance:** fake CLI/transport regressions demonstrate rejection before mutation for dirty/unbound source, wrong target, stale approval and incomplete manifest; staging exercises a partial failure and recovers without data loss or double effects. Avoid a circular demand that all final production checks must pass before a necessary staging/remediation rollout.

### ARC-06 — P1: iOS publication governance is weaker than Android

**Source-confirmed gate gap:** `.github/workflows/ios-app-store.yml:30` has no protected `environment`, main-ref restriction or expected reviewed commit. It imports signing secrets even when optional uploads are false. iOS upload lanes `fastlane/Fastfile:146`, `:182`, `:238` and `:258` do not call the `release_go_preflight.sh` enforced by Android's production submission at `Fastfile:100`. `upload_review_build` checks the iOS package gate, but does not independently bind the IPA hash to an approved release candidate. `build_review_ipa` at `:222` repeats non-enforced `flutter pub get` after the workflow's enforced lock install.

TestFlight/internal upload, metadata publication and statutory production release need appropriately scoped authority; they should all identify the exact approved source/artifact. This finding does not assert misuse or actual secret exposure. Protection outside the YAML was not verified.

**Recommendation:** Separate credential-free compilation, signed candidate creation, controlled internal TestFlight distribution and public submission. Apply named environments/ref policy, expected commit and immutable IPA/source hashes to relevant jobs; import credentials only in the scoped signing/upload job and clean temporary material afterward. Keep `--enforce-lockfile` in every resolution step. GitHub environments support restrictions and protected secret access. [GitHub deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)

**Acceptance:** invalid ref/commit/approval/artifact tests fail before credential import/upload; protected environment enforcement is exported/read back; one signed IPA and its privacy/entitlement inspection is bound to the approved internal or public distribution decision.

### ARC-07 — P1: Admin update policy risks mixed versions and stale unversioned assets

**Source-confirmed policy; browser impact not reproduced:** `web/_headers:32` declares `/main.dart.js`, `/assets/*` and `/icons/*` immutable for one year, although builds keep those URLs stable. The hosting/live gates explicitly require that policy. The service worker uses content-derived cache names and reloads during install, which helps installation, but HTTP cache requests before worker control can still reuse stable URLs. `web/flutter_bootstrap.js:17` loads the application immediately and registers the worker only at load time; its worker URL also changes via query per candidate. The worker unconditionally calls `skipWaiting` at `scripts/templates/admin_pwa_service_worker.js:35`, claims existing clients and removes older caches at `:45`, while old pages may still execute old application bytes.

**Current deployment readback:** root's `admin-live.json` failed five required served-worker contracts (credential-free precache, redirect rejection, exact response URL, shell and static cache boundary), while its endpoint probes returned HTTP200. This establishes failed current deployment evidence, not a successful warm-upgrade check or a proof that a string-based checker exhaustively diagnoses the deployed worker.

**Recommendation:** Use content-versioned immutable asset URLs, or require revalidation for mutable bundle paths. Define an explicit N→N+1 policy for an open authenticated tab, lazy assets, multiple tabs, failed install and rollback; preserve static-only cache admission. Coordinate activation/reload with pending operator work instead of assuming immediate activation is always safe. Chrome describes first-visit control and the mixed-subresource risk from immediate activation. [Service worker lifecycle](https://developer.chrome.com/docs/workbox/service-worker-lifecycle), [Caching strategies](https://developer.chrome.com/docs/workbox/caching-strategies-overview)

**Acceptance:** two real hosted build versions, with changed main bundle/assets, prove first visit, existing HTTP cache without worker, installed warm upgrade, open multi-tab pending actions, interrupted install, offline and rollback. Assert expected bundle/resource hashes and no stale private state. A header or fresh-install pass alone cannot close this issue.

### ARC-08 — P1: operational toolchain can silently resolve an arbitrary latest CLI

`scripts/supabase_cli_helpers.sh:3` accepts any installed Supabase binary, then falls back at `:13` to unversioned `npx -y supabase` and at `:15` to `supabase@latest`. PostgreSQL client selection similarly accepts whatever installed client is found. This is materially different from the project's Flutter/Deno pins: migration dry-run/application/API semantics can change between operators or days.

**Recommendation:** Pin the reviewed CLI version and package integrity, require a known supported PostgreSQL client/server matrix and record the actual binary/version in deployment evidence. Use explicit offline/locked installation rather than latest resolution during a live operation. **Acceptance:** clean environment selects the same pinned toolchain and wrong/unknown versions fail before remote requests; migration and restore rehearsal uses that exact toolchain.

### ARC-09 — P1: fork/dependency governance is uneven across ecosystems

`pubspec.yaml` owns file_saver, Firebase Messaging and GoTrue forks. The Firebase fork explicitly says its upstream manifest records cached bytes, not independent authentication (`third_party/firebase_messaging/COLLECT_FORK.md:4`). GoTrue retains original hashes/licence but also has an Auth-sensitive behavioural delta (`third_party/gotrue/COLLECT_FORK.md:9`). CI compares only file_saver to a published archive at `.github/workflows/ci.yml:170`. Dependabot covers Actions, pub and Gradle, but not the Node tools or Ruby/Bundler cohorts (`.github/dependabot.yml:1`). Android has strict version locks, but no `android/gradle/verification-metadata.xml` was found; source-lock integrity does not attest signed artifact composition or vulnerability status.

**Recommendation:** Adopt one fork ownership/update policy and published archive comparisons for all owned forks; tie the behavioural regression suite to each delta. Add ecosystem maintenance/scanning for notification MCP, photography tools, Fastlane/Bundler, Edge imports and platform SDKs. Generate the final artifact SBOM/notices from observed packaged components; retain source SBOM as a separate layer. Review dependency checksum/signature verification rather than blindly trusting a generated baseline. [Android dependency verification](https://developer.android.com/build/dependency-verification)

**Acceptance:** upstream licence and published archive provenance, exact allowed deltas, frozen dependency verification, authenticated advisory triage and packaged AAB/IPA/web SBOM reconciliation. Current inventory/schema validators are useful evidence, not vulnerability or licence acceptance.

### ARC-10 — P1: evidence snapshots overwhelm the engineering workspace

The root inventory records **305,247 docs files / 30,932,849,991 logical bytes (about 28.81 GiB)**, against **2,224 hashed active source/config files / 157,645,348 bytes**. Much of the docs volume is repeated dated sources, attempted candidates, copied build/runtime material and test observations. That affects clone/review/search/format inventory cost and makes the many historical passes look deceptively current. The aggregate 296,502 untracked entries are not 296,502 independently reviewed source additions.

**Recommendation:** Preserve unique material first. Classify current source, required contracts/fixtures, retained release evidence and reproducible scratch artifacts. Create a hash manifest and content-addressed evidence archive with provenance, retention, encryption/access and restore tests. Keep concise indexed release reports and indispensable synthetic regression fixtures in the repo. Permanently delete only hash-verified redundant copies after their unique material and references are safely preserved. Do not ignore the entire docs tree to hide integration work, remove source snapshots used by release validation, or declare all untracked files disposable.

**Acceptance:** before/after file/class/byte counts; every removed path maps to an independently recoverable identical object or a justified reproducible discard; report/fixture links resolve; isolated clean checkout builds/tests without the archive; secret/customer-data classification and access controls remain enforced. The report requests recommendations, so no cleanup has been performed here.

### ARC-11 — P0: full recovery acceptance remains unproved for the current system

`docs/RECOVERY_RUNBOOK.md:3` records a September database rehearsal and explicitly leaves Storage/off-site/RPO/RTO open. Its convenience logical-backup script is only a partial public-schema export (`:53`). The current candidate includes many later migrations/functions and operational control records; an old database pass is not full current hosted recovery evidence.

**Recommendation:** Set accountable RPO/RTO and retention, recover database roles/grants/Auth/current financial records, Storage bytes if used, platform settings/secrets through approved managers, worker/host identities and artifact configuration into an isolated target with outbound queues disabled. Reconcile post-snapshot revocations and pending/uncertain work before reopening authority. Supabase documents that database backups exclude Storage objects and that new-project restores still require Edge/Auth/Realtime reconfiguration. [Supabase database overview](https://supabase.com/docs/guides/database/overview), [Restore to a new project](https://supabase.com/docs/guides/platform/clone-project)

**Acceptance:** current candidate and representative history restore with table/row/financial/ACL/config/object hashes, observed elapsed time and lost-data window, tested revocation replay, no external sends, independent verifier and recovery-owner signoff.

### ARC-12 — P1: monitoring, support and capacity objectives remain deployment gates

`docs/production/SECURITY_AND_OPERATIONS.md:11` explicitly says telemetry/on-call provision is not established. `lib/main.dart:31` and `lib/main_admin.dart:11` await initialisation before rendering. `lib/core/logging/app_logger.dart:6` is a local pretty logger; no global Flutter/PlatformDispatcher error capture or crash-report SDK wiring was found in runtime Dart. That is a source observation, not a demand to add a specific paid provider or to log personal data.

**Recommendation:** Provide safe startup failure/recovery, privacy-reviewed diagnostic capture, version/environment correlation, server operational metrics and named escalation paths. Monitor queue oldest age, unavailable/overflow, uncertain writes, rejection categories, OTP quotas, finality exceptions, notification dead letters and DB latency. Define p95/p99, capacity/backlog-drain, crash/ANR and support response objectives from representative workload and minimum devices. Existing unit tests and source thresholds do not measure those objectives.

**Acceptance:** synthetic fault injections produce fixed public errors and redacted actionable alerts delivered to the named duty owner; outage/queue/backpressure and long-session minimum-device runs meet approved budgets; no SMS bodies, credentials or identifying data leak through logs, exports or crash events. Verify alert silence/recovery and run a support/incident rehearsal.

### ARC-13 — P1: native store/artifact and platform policies need current proof

Android's main manifest declares `RECEIVE_SMS` at `android/app/src/main/AndroidManifest.xml:9`; Google Play classifies this in restricted SMS permissions. Source consent and sender filtering alone do not demonstrate approval for the exact distributed package. iOS declares a privacy manifest with an empty required-reason list (`ios/Runner/PrivacyInfo.xcprivacy:9`); this is not by itself a violation because SDK manifests may supply appropriate declarations, but the merged signed archive must be checked against actual API usage and current privacy answers.

The iOS workflow checks iOS SDK ≥26, which agrees with Apple's current Xcode 26/SDK26 upload requirements; deployment minimum 15.5 is distinct from the build SDK. Do not incorrectly raise the minimum OS to 26. The Android legacy Kotlin/DSL flags are a documented temporary supported path for Flutter3.44/AGP9, not proof of an incompatibility. Plan migration with all plugins before enabling built-in Kotlin. [Apple upload requirements](https://developer.apple.com/news/upcoming-requirements/), [Apple privacy manifests](https://developer.apple.com/documentation/BundleResources/privacy-manifest-files), [Play sensitive permissions](https://support.google.com/googleplay/android-developer/answer/16558241?hl=en-GB&rd=1), [Flutter built-in Kotlin migration](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin)

**Acceptance:** merged AAB/IPA permissions, SDK reason manifests, entitlement/APNS/association/backup policies and privacy answers; exact signed package/version Play SMS permission decision; installed low-end/minimum OS, real SIM and APNS/FCM journeys; store review/availability/readback. No store rejection or approval was observed during this review.

## Delivery and operations checklist

| Area | Current review result | Missing proof / accountable boundary |
|---|---|---|
| Trusted source | main SHA parity reported; immense dirty working set | Review/integrate relevant source, preserve evidence, protected merge and clean immutable build |
| Analysis | Current root strict analyzer pass | Affected consumer tests and clean-runner CI; prior proof readback/drift reconciliation |
| CI format and size | Concrete wiring/budget failures | ARC-01/02 fixes and actual Linux execution |
| Edge compile/tests | Frozen local tooling exists; workflow contract differs | Full current safe cohort plus explicit fixture/sandbox prerequisites; ARC-04 |
| CI service | Latest eight root-observed runs are `startup_failure` | Determine runner/platform startup cause and obtain successful required checks |
| Release workflow authority | Good Android preflight and manual read-only Supabase environment | iOS publication gates, backend immutable release binding and exported branch/environment enforcement |
| Dependencies | Version locks/source provenance present | Complete fork provenance/update ownership, advisory triage, packaged SBOM/notices and native integrity |
| Backend rollout | Target confirmation and dry run present | Single complete 12-function release manifest, migration/caller order, deploy hashes and post-rollout denial/positive tests |
| Admin hosting/PWA | Static-only source cache policy; current live gate fails five served-worker requirements | Two-version installed update/rollback, mutable URL policy, CSP/headers/Auth behaviour on actual hosting |
| Public hosting | Current root live gate33/36; four privacy/terms destinations404, content-evidence drift and single-request root latency failure | Exact current source→artifact→deployment binding, canonical headers/routes/media/SEO/live interaction acceptance |
| Android release | Strict production lock/signing protections and QA marker | Signed production artifact, Play permission readback, real device/provider lifecycle/capacity |
| iOS release | SDK floor enforced and owned plugin compatibility change | Protected signed artifact build, merged privacy/entitlements, physical/APNS/link lifecycle and store readback |
| Observability | Signal requirements documented | Provisioned redacted alerts, diagnostics, duty owner and incident drills |
| Availability/performance | Existing profile/SQL test tooling | Representative load/minimum hardware measurements and approved SLOs/budgets |
| Recovery | Historical database rehearsal and careful runbook | Current full-system isolated restore, objects/config/authority reconciliation, RPO/RTO/off-site acceptance |
| Cleanup/structure | Runtime modules exist; central libraries and evidence bloat persist | Bounded service extraction, one owner per boundary, preserved content-addressed archive and clean checkout proof |
| Pilot/support | Runbooks describe required process | Accountable staffed pilot, daily independent reconciliation, support workflow and stop conditions |

Root read the latest eight GitHub runs as completed `startup_failure`, including [the HEAD-related Gradle run](https://github.com/ikanisa/COOL/actions/runs/36751713381) and [a recent PR run](https://github.com/ikanisa/COOL/actions/runs/36751716611). Their startup failure reason was not attributed to the source findings above; a failed startup can occur before any job step. No all-green remote candidate run is established.

## Refactoring, restructuring and cleanup order

1. **Restore executable delivery contracts.** Fix portable tool selection and hard source-budget violations without weakening tests. Consolidate the Edge release manifest and wire the frozen current test graph. Make current local and remote results comparable.
2. **Freeze one reproducible candidate.** Select reviewed source from the dirty tree; bind locks, toolchain, build defines, migrations and handler closure. Build member/Admin/public/Android/iOS identities in isolation. Keep signed, unsigned and fixture artifacts distinguishable. Configure protected review/publication paths and verify them.
3. **Extract only justified ownership boundaries.** Preserve actual terminology, access controls and selected design. Move member/session/cache, history, notification and Admin workflow responsibilities behind typed interfaces. Retain exactly-once, uncertain-commit, revocation and versioned contract tests through every move. Avoid replacing the project or introducing a monorepo/package hierarchy merely to shorten files.
4. **Preserve then shrink evidence.** Root's manifest is the starting inventory. Hash-classify dated copies, retain unique sources/results and proof links, store immutable large evidence privately with a tested recovery/index and remove confirmed duplicates only. Keep synthetic source fixtures that test current consumers. Do not delete historical migrations or financial evidence as obsolete runtime code.
5. **Complete installed/deployed operation proof.** Two-version PWA upgrades, signed device/provider/store acceptance, complete backend readback, redacted telemetry, capacity and full recovery. Run a bounded staffed pilot with stop conditions; accountable GO comes from the release decision process after required gates close.

The detailed fix sequence should extend the existing production register IDs rather than create another independent release truth. This report records newly identified wiring defects and proposed closure evidence; it does not mark the 101 open production checks complete.

## Current MCP refresh

The package's `check` and `test` scripts run strict TypeScript checking and Node's `src/*.test.ts` suite. Inspection found injected Keychain/launchctl seams, temporary journals and synthetic stdio/HTTP fixtures. The refresh runs those exact bodies under credential-free environment, using installed Node24.19.0 and TypeScript; no install/preflight/live connection/scheduler command is invoked. `architecture-mcp-verification.json` and `architecture-mcp-check.txt` / `architecture-mcp-test.txt` preserve the initial incomplete outcome: type check exit0; aggregate timeout120s; 253 observed pass lines; zero observed fail lines; no suite-completion record. The timed-out wrapper did not publish its initial in-memory source-before map, so that initial command is not claimed as a complete unchanged-source acceptance packet. The separate `architecture-mcp-targeted-verification.json` and `architecture-mcp-targeted-tests.txt` record an explicit restore/inactive/emergency-latch subset, source-before/after hashes and a180s process-group timeout; they do not replace the full suite. **Actual targeted result:** PASS; 21 selected tests, 0 failures, 0 skipped; strict input hashes unchanged. This covers restored-evidence authority, inactive journals, signer/transport race guards and durable emergency disable in the two named test files. The full aggregate remains incomplete.

A passing fixture suite can refresh changed local MCP code evidence but cannot establish host scheduler installation, current enrollment, live sender takeover or provider delivery.

## Research limits

Official primary documentation was consulted for specific current uncertainties: Flutter/AGP compatibility, Deno locks, GitHub publication protections, native permissions/privacy/upload requirements, service-worker updates and recovery scope. Research does not prove this project's deployed configuration. No third-party blog assertions, invented global certification, readiness percentage or calendar estimate substitutes for the candidate's required evidence. The exact legal/regulatory and product-design reviews remain in their dedicated report contributions.
