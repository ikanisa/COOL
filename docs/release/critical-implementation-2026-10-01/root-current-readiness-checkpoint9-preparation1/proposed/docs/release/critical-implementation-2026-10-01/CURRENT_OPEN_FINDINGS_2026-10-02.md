# Current open critical findings

As of 2026-10-02T18:52:57.531299+00:00: **33 of 40 original findings remain open in full. Production NO-GO; implementation goal active.**

The previous 37 count included ARC-01, ARC-02, BE-10 and PD-12; those now meet their original criteria. ARC-04, PD-02 and PD-14 retain earlier closure scopes. Original 102 production rows and 24 local rows are unchanged.

[Full implementation register](IMPLEMENTATION_REGISTER.md) records original titles, acceptance criteria, current local results and bound evidence.

| ID | Remaining work or evidence |
| --- | --- |
| BE-01 | Fresh deployed migration, function, grants/RLS and configuration parity; authorized runtime denial tests. Linked-project read access was refused. |
| BE-02 | Implement retained, authenticated payment evidence through reconciliation, correction and reversal. Concrete route-neutral proposal reviewed; evidence route decision pending. |
| BE-03 | Current13 endpoint manifest is wired locally; verify deployed bundle identities, JWT/custom authority and missing/retired endpoints. |
| BE-04 | Local originating-session race/provenance checks pass; finish candidate/legacy capability disposition and actual deployed confirmation/send-start behavior. |
| BE-05 | Complete approved retention/erasure schedule, legal holds, derivative/export/backup deletion, restart/duplicate handling and truthful completion. |
| BE-06 | Verify actual Auth, MFA, OTP, CAPTCHA, provider/recovery, abuse protection and rotation configuration. |
| BE-07 | Verify real Google Play Integrity admission, quota/budget, outage behavior and operational alarms. |
| BE-08 | Resolve ownership/history/body provenance across 209 migrations. Latest 1,095-input / 668-source verification and 69 unchanged tests preserve 127 mappings, 74 classifications, 58 callers and 84 lineage uncertainties; three computed hash matches do not resolve these records. |
| BE-09 | Restore the whole current DB, Storage, Auth, configuration and revocation state with accepted RPO/RTO; 27 local DB recovery checks are narrower. |
| BE-11 | Treat phone hashes as pseudonymous identifiers; approve/enforce retention, access and key migration. |
| BE-12 | Prove deployed SLOs, alert routing, duty ownership, runbooks and fault recovery. |
| BE-13 | Approve AI processor/vendor/project/region/retention/spend/accuracy/deletion controls; source tests do not supply that approval. |
| ARC-03 | Local manifest-derived unsigned probes pass 22 inventory and 3 regression tests. Verify actual deployed hashes/migrations/scheduler and approved staging/production positive-denial HTTP behavior. |
| ARC-05 | Exercise source/artifact approval-bound deployment, partial failure handling and recovery. |
| ARC-06 | Prove protected iOS environments/reviewers and a current signed IPA publication path. |
| ARC-07 | Exercise two actual hosted Admin builds: warm update, multiple tabs, offline/interruption and rollback. |
| ARC-08 | Accept the shipping client/server/archive admission and real restore path; 39 local Linux adapter tests pass, earlier macOS failures remain recorded. |
| ARC-09 | Complete exact lint tooling binary admission/resolution, then current AAB and artifact-bound SBOM/reader verification. R8 9.1.29 probe2 and lint/publisher metadata pass only their scopes; licence/fork/frozen/advisory and AAB/IPA/web acceptance remains open. |
| ARC-10 | Prove encrypted evidence archive, key recovery, independent restore and clean consumers before removing unique evidence. |
| ARC-11 | Accept full financial/object/history/Auth/revocation recovery and RPO/RTO; local committed DB recovery is insufficient. |
| ARC-12 | Verify real alert ownership, backpressure/capacity, device floors, long sessions and incident/support handling. |
| ARC-13 | Prove signed native permissions/entitlements, SMS/SIM, APNS/FCM and store/device policies. |
| PD-01 | Complete installed mobile, Admin and website Revolut comparisons/interactions and owner acceptance for material routes/states. |
| PD-03 | Establish selected font distribution rights and accept fallback layouts if required. |
| PD-04 | Exercise a real account-deletion channel without the app, including acknowledgement, status, duplicates and failures. |
| PD-05 | Publish/verify legal destinations, retained-data anchor and truthful privacy outcomes; live readback found 404s and differing HTML. |
| PD-06 | Prove users can follow installed deletion instructions without assistance. |
| PD-07 | Accept actual availability/provider claims, conversion and support behavior. |
| PD-08 | Exercise real TalkBack/VoiceOver transitions, error states and recovery. |
| PD-09 | Verify compact/large screens, enlarged text/amounts and keyboard boundaries on installed targets. |
| PD-10 | Prove generated and installed PWA identity, scope and deep links. |
| PD-11 | Complete current route/role/state browser and visual evidence; current 29-route inventory and affected tests are corrected. |
| PD-13 | Align received/pending/reconciled/confirmed/ambiguous/corrected/reversed wording with the approved actual financial evidence level. |

The maintained mapper passes 69 recorded tests, reused for unchanged mapper/test bytes. Latest current 209-migration generation and independent verification pass at source epoch 0843 in 4.518 and 5.127 seconds, each within 30 seconds, with 1,095 held input rows, 668 maintained sources, 718 callers, 2,543 objects and 4,157 grants. Three literal replacement candidates compute to catalog hashes; all 127 unresolved functions (36 application/public, 91 platform), 34 candidate reviews/37 candidates, 74 classifications, 58 unresolved callers and 84 lineage uncertainties remain unresolved. Only the reader caller input changes from the 69-test epoch; the other 1,094 input rows and all coverage fields remain unchanged. Ownership, body provenance, history and full-system recovery acceptance remain open.

Archived app/native outcomes and the failed AAB9 remain in their original source scopes. The current 2,563-source map 0843bf6a… is bound to fence f5448ce9…; the current APP map is 46a85b4c…. Actual probe2 passes in 188.523 seconds: AGP selects R8 9.1.29 and invokes its version method from the exact 56,139,715-byte raw publisher JAR, SHA-256 9a7d1e9e…. Required source/APP/SDK/protected guards pass, and shrinking/lint remain enabled. This probe runs no current APP compilation, fresh runtime/compile graphs or AAB. Lint metadata3 passes in 11.051 seconds with 70 components, 181 edges, 69 POMs and no binary artifacts. Separate publisher metadata verifies 69 POMs/eight modules: seven direct variant bindings, one external bridge and 61 POM-only filenames still unprojected; no binaries downloaded. Exact full-AAB admission was assembled in 0.071 seconds; AAB execution did not occur. Full tooling binaries, standard resolution, the unchanged current-source AAB and artifact/SBOM consumers remain pending. No package or release acceptance is claimed.

PD-12 retains closure of its original current-index reconciliation criterion, revalidated for source epoch 0843 by separate integrator criterion-review2. The actual reader matches 133 facts across 33 sets and records exactly three expected archived-vs-current Android differences, with no other reported drift or unknown physical entries; exit 1 preserves those explicit historical differences. Eighteen unchanged reader tests, schema validation and authority hygiene are bound. Captured inventory completeness beyond listed leaves remains unknown. Whole graph, native, visual, font-rights, provider, package and release acceptance remain unverified.

Cloudflare/browser and hosted-project readback limits remain recorded. No production deployment, signing, provider configuration, payment, external message or Git publication occurred in this work.

The [payment evidence proposal](be02-evidence-admission-preparation1/README.md) remains reviewed and uninstalled. [BE-08 latest current 209-migration verification](root-be08-post-r8-reader-current 209-migration1/readback.json) retains unresolved ownership/history/body scope. [ARC-03 integration](arc03-probe-plan-integration1/readback.json) records local probe verification. [PD-12 criterion-review2](root-pd12-current-epoch-criterion-review2/review.json) revalidates original current-index closure for the declared epoch. [R8 probe2](root-arc09-r8-probe-observation2/terminal.json), [lint metadata3](root-lint32-tooling-metadata-resolution3/readback.json) and [publisher metadata](arc09-lint32-selected-publisher-metadata-acquisition1/readback.json) remain distinct from full binary/AAB acceptance.