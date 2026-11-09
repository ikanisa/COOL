> This document records the A04.1 merge. Its original decisions remain in force except for the explicitly traced A04.2 presentation integration correction in `55_A04_Post_Command_Integration.md`. Current source: 0.20.0-a04.2.

# A04 consolidation decisions — 0.20.0-a04.1

## Outcome and authority boundary

One active implementation overlay combines six continuations against the common v0.17 baseline. No new financial ledger, settlement authority or authentication fallback is introduced. The original archives remain unchanged on Drive. Their embedded file manifests and ZIP integrity were verified before use.

Canonical v0.19 is the starting point. Changes are applied as three-way deltas against v0.17, not by copying entire older trees over newer source. Owner-bound v0.18 recovery is explicitly accounted for as a source and retained through its canonical successor. Input variants that are not selected verbatim are content-addressed under `history/a04-blobs`; these are non-active provenance, not alternative build candidates.

## Counts and scope

- 7 original archives including the common baseline; 4725 original file occurrences accounted for.
- 787 logical overlay paths mapped to resulting files and decisions.
- 21 paths have differing overlapping workstream changes; 14 merge events required deliberate resolution.
- 73 web handoff files are byte-identical across all input copies; the canonical reference is retained unchanged. The SMS wrapper README is preserved and indexed, not treated as executable source.

## Important conflict resolutions

| Path | Decision |
|---|---|
| `.github/workflows/burimunsi-native.yml` | Preserve native-build qualified build/artifact/instrumentation workflow; add UI generator and resource checks and UI catalog trigger. No production signing or deployment gate relaxed. |
| `START_HERE.md` | Retain source-specific provenance without using it as current acceptance. Current A04 identity and evidence boundary take precedence; every original differing byte version is preserved and indexed. |
| `VERIFICATION.md` | Retain source-specific provenance without using it as current acceptance. Current A04 identity and evidence boundary take precedence; every original differing byte version is preserved and indexed. |
| `contracts/financial-operation-reconciliation.json` | Cumulative contract: mandatory owner-bound recovery v1 plus economic status v2; financial-only and original-token-only legacy fallback superseded. Two primary snapshots are explicitly not atomic together. |
| `native/burimunsi/app/build.gradle.kts` | Combine owner-recovery application baseline, offline/testOnly nativeTest sandbox and UI dependencies; align versionCode 20/versionName with A04. Existing toolchain dependency pins preserved, not asserted resolved. |
| `native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/data/ApiClient.kt` | Three-way integration retains canonical managed-auth/response validation and native-build guards; no bearer fallback or acceptance of HTML API responses. |
| `native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/data/NativeRepository.kt` | Compose v18 immutable owner/grant/installation recovery and canonical session-generation guards with financial v2 effect validation. Persist new owner/group, never rebind legacy evidence, validate before dispatch, no SENT/UNKNOWN POST; verify cache then journal deletion; warn on reversed/corrected effects. |
| `native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/storage/AndroidOperationStore.kt` | Persist financial ownerAccountId/groupId without guessing legacy identity; retain v18 verification that terminal deletion actually removed durable journal bytes. |
| `native/burimunsi/app/src/main/kotlin/rw/ikanisa/burimunsi/ui/BuriViewModel.kt` | Retain canonical foreground/session gates and recovery-specific errors; add UI navigation-only checkpoints and financial reversal/correction warnings. Unresolved commands survive restored screens; no automatic retry. |
| `native/burimunsi/http-tests/HttpChecks.kt` | Preserve canonical recovery headers and API rejection cases together with native-build transport boundary checks; test harness remains synthetic, not hosted-account acceptance. |
| `native/burimunsi/repository-tests/RepositoryChecks.kt` | Keep canonical/v18 actual repository cases and adapt proof fixtures to mandatory v2 readback. Financial-only cases are superseded by A04Checks.kt, including version/owner/effect failures, rotation, legacy proof, changed effect and cleanup ordering. |
| `native/burimunsi/scripts/verify_all.sh` | Combine canonical suite chain with SMS reliability, UI resource and UI syntax checks; preserve all available host suites. Android build remains a separate gate. |
| `release/file-manifest.json` | Original per-stream manifests/inventories are preserved as blobs. Current metadata is regenerated; its output digest is bound by the complete file manifest/outer archive rather than a circular ledger self-reference. |
| `release/production-evidence.json` | Retain source-specific provenance without using it as current acceptance. Current A04 identity and evidence boundary take precedence; every original differing byte version is preserved and indexed. |
| `release/source-change-inventory.json` | Original per-stream manifests/inventories are preserved as blobs. Current metadata is regenerated; its output digest is bound by the complete file manifest/outer archive rather than a circular ledger self-reference. |
| `release/toolchain.json` | Preserve native-build toolchain and instrumentation pins; update candidate identity only. Android build execution remains false. |
| `release/upgrade-from-0.17.0.json` | Retain source-specific provenance without using it as current acceptance. Current A04 identity and evidence boundary take precedence; every original differing byte version is preserved and indexed. |
| `scripts/apply_to_collect.py` | Retain canonical exact-hash/no-local-overwrite protections, preserve all seven input baselines, and explicitly import UI generator/catalog/tests. No broad new path permissions. |
| `supabase/functions/_shared/domain/burimunsi/postgres-records-store.js` | Keep v18 immutable original/current session and receipt recovery query; compose financial primary-attestation snapshot and parameterized command-effect SQL reader. No new writer or ledger. |
| `supabase/functions/_shared/domain/burimunsi/records-service.js` | Retain canonical records/history and freshly reloaded actor authorization. Require primary command snapshots for both v1 recovery and v2 economic status; no ordinary-reader downgrade. |
| `tests/overlay_safety_test.py` | Retain UI support-path tests and common canonical safety tests; duplicate prior-source upgrade assertions consolidated. A04 merge tests exercise each actual archive baseline and unknown-local-edit refusal plus clean/repeat application. |

## Recovery is cumulative, not an either/or fallback

A newly prepared journal captures request UUID, original session-token hash and owner/group. A future login never rewrites that origin. The first server read is the exact v18 `operation-recovery.v1` proof: current authorization and original/current canonical principal, operator, group, installation, grant ID and version must agree. Only a committed proof permits the second status-v2 read for the same original request under the same live session witness. The client also verifies contract version, exact projected fields, operation and supported economic effect.

The financial continuation's v2-only and original-token-only legacy behavior is superseded deliberately. Ownerless legacy journals can recover after token rotation only through the stronger original-session v1 proof followed by strict v2 status. They are never rebound, guessed, silently recreated or cleared to recover from an error. If either endpoint is unsupported or inconsistent, evidence remains unresolved. The new `A04Checks.kt` replaces financial-only fixture assumptions with this cumulative rule while retaining the original canonical and v18 suites.

Both server endpoints use primary-qualified read snapshots and reload current authority. The reads are separate: a concurrent change can occur between them. A missing/pending/conflicting second response fails closed. A passed response represents the financial effect at that second snapshot, not a permanent guarantee against later reversal. Real schema, primary routing and transaction behavior still require PostgreSQL qualification.

Verified financial-cache deletion happens before verified journal deletion. Failure at either step leaves the original operation blocked. Reversed/corrected results terminate only the historical operation and display explicit review messages; a successful initial POST must not return a fresh-credit success for those effects. No SENT/UNKNOWN dispatch is retried; read-only checking does not POST.

## SMS, native build and UI preservation

SMS R1 capture/classification, binding/SIM decisions, duplicate/multipart handling, queue persistence, acknowledgements, retries, replacement safeguards and host fault-injection suites are retained. The upstream Collect receiver pins are not rewritten. Synthetic/AES-GCM/host-process evidence is not carrier or Android durability acceptance.

The native-build workflow, offline/testOnly sandbox, APK selection/manifest inspectors and instrumentation-log qualification remain intact. UI adds eight authored checks to the native set; the exact expected union is 23 test identities per flavor. The old Staff-only test name is superseded by a flavor-aware test retaining Staff isolation assertions and exercising the receiving flavor rather than skipping it. No APK or instrumentation result is manufactured from this test list.

UI typography, transition behavior, navigation-only restoration, localization, keyboard behavior, accessibility source rules and twelve journey harnesses are combined with canonical generation/foreground gates. Four canonical recovery messages and two financial warnings were added to the shared English/Kinyarwanda catalog. Regenerated resources have matching keys. Unresolved journals survive repeated navigation restoration and cannot become automatic POSTs. Fluent translation review and installed-screen/TalkBack acceptance remain external.

## Safe intake and provenance

The installer retains exact recognized source-byte upgrades and refuses unknown local edits. Baselines cover all seven supplied archives. `a04-import-manifest.json` lists the exact namespaced runtime/support selection. Delivery-only metadata, historical evidence, architecture contracts and package tests remain in this complete source delivery rather than being copied indiscriminately into Collect. Temporary checkout tests cover clean dry run, application, repeatability and conflicts; the user's actual checkout is untouched.

`a04-merge-ledger.json` records every input ZIP member and its preservation location, each logical path's version hashes, changed streams, result hash, rationale and test references. Original release manifests are archived rather than masquerading as current evidence. The two explicitly documented self-reference exceptions are bound by the outer complete file manifest and final ZIP checksum. This is traceability and local engineering verification, not independent security certification.

## Reproduce and finish external acceptance

See START_HERE and VERIFICATION. Run the supplied regression command into a new directory, then inspect source hashes and every exit code. Current evidence is adjacent to the active tree, never inherited from prior logs. Retain the production-promotion gate and receiving upload hold until real Collect/PostgreSQL reconciliation, canonical session/worker/source/scheduler acceptance, pinned Android dependency resolution/build, installed variants, real carrier/SIM/reboot/replacement durability, TalkBack and language review are completed. Applying the overlay to the actual working checkout remains a separately reviewed action.
