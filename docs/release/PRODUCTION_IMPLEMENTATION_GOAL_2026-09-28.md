# Collect production implementation goal

**Goal:** close every still-open acceptance item in the [100-task register](PRODUCTION_READINESS_REMAINING_TASKS_2026-09-28.md) and both crosscutting checks, then obtain one accountable GO decision for the exact signed and deployed candidate. The current inventory has **99 production task acceptances still open plus X01 and X02**; G06 is locally implemented. This document is the execution contract; the [task-by-task audit](PRODUCTION_TASK_IMPLEMENTATION_AUDIT_2026-09-28.md) is the evidence ledger. **Current release decision: NO-GO.**

## Rules for closing an item

1. Preserve the recovered, dirty checkout and every unique Drive/recovery source. Record a baseline of branch, remote, working-tree changes and SHA-256 before any reconciliation; do not reset or overwrite user work. Review imported material by product boundary and by exact file/hash.
2. For each ID, record the owner, source change or decision, exact commit/artifact hash, test environment and date, negative cases, independent review, remaining risk and acceptance evidence. A local change is `Local` or `Partial` until the acceptance text in the register is satisfied. Historical logs, synthetic fixtures and source-string tests never stand in for a deployed or physical result.
3. Keep the owner-selected `revolut-design` skill as the sole UI/UX authority for mobile, Admin and public web. Reconcile every relevant route and loading, empty, failure, geographic, membership, responsive and accessibility state through shared tokens/components. Preserve Collect terminology, capabilities and access controls. X01 stays open until comparator images, interaction/accessibility evidence and owner review all refer to the exact candidate.
4. Maintain the Rwanda-only MoMo boundary. X02 requires current deployed routes, support/privacy text, store declarations and historically retained financial controls. Do not infer settlement from USSD launch or SMS observation.
5. Stop a release when an ID lacks its acceptance evidence, when source and artifact identities differ, or when an external owner/provider/store/legal decision is missing. The final decision is a recorded owner action after the pilot, not a computed completion percentage.

## Execution sequence and dependencies

| Gate | Work and linked IDs | Exit evidence |
| --- | --- | --- |
| 0. Trusted source | G01–G10, G06; contain open sharing and any actual credential exposure, preserve all edits, reconcile imports, review a single protected commit. | Restricted Drive access readback, exposure decision, verified rotations where required, clean reviewed release source, source-to-release manifest, protected policy export and accountable owner. |
| 1. Security and money boundary | S01–S10, F01–F10, D01–D10; approve the threat model and finality levels before enabling posting, then complete identity, receipt, ledger, reconciliation, grants, paging and migration work. | Full-schema clean **and realistic upgrade** rehearsals, concurrency and rollback/roll-forward results, role-negative tests, provider authenticity, balanced immutable journals, safe error corpus and authorized deployed readback. The [current synthetic clean result](financial-core-2026-09-28/README.md) is a useful partial checkpoint. |
| 2. Native and member journeys | M01–M10, U01–U05, U09–U10, X01–X02; finish owner-bound links, encrypted receipt recovery, platform capability truth, MoMo and localization/accessibility states. | Signed Android/iOS artifacts, exact merged permissions/entitlements, Play SMS policy decision, real SIM and supported-device matrix, process/backup/key-loss tests, device performance and dated owner visual review. |
| 3. Admin, public and privacy | U06–U08, P01–P10, A01–A10; finish each declared Admin operation, deployed public/Admin separation, AI review controls, asset provenance and legal/vendor/data lifecycle decisions. | Route/role and real browser evidence, secure import/export, PWA update/logout tests, data-deletion/retention trace, vendor and cross-border determinations, approved claims and asset/license readback. |
| 4. Whole-candidate QA and operations | Q01–Q10, O01–O10; freeze one candidate, resolve exact dependencies, execute full tests/builds, deploy only through protected gates, restore, monitor and rehearse incident response. | Full Flutter/native/Edge/SQL/integration results tied to the same commit; signed artifact and deployed hashes; restore/RPO/RTO, alerts, capacity/cost and support drills; bounded pilot with daily reconciliation and stop criteria. |
| 5. Production decision | Every ID plus X01/X02 | No open acceptance gap or unapproved deferral; exact release gates report GO; responsible owner signs the production decision for the tested artifact/deployment. |

Gate 0 may progress alongside isolated implementation, but hosted migration, provider testing and public claims require the trusted source and authorized target. Financial approval precedes any live finality. Visual review and whole-candidate QA repeat whenever later changes alter the candidate. A failed check returns the affected IDs to open, with its evidence preserved.

## Current next actions

- Finish review of the current dirty source and the [financial replay/upgrade/restore packet](financial-core-2026-09-28/README.md); extend the small synthetic historical upgrade to representative volume and concurrent duplicate/conflict/reversal cases, then rehearse authorized hosted/full-environment recovery plus compatible rollback/roll-forward. Apply the staged reconciliation design only after its independent evidence boundary is approved.
- Resolve the five retained visual differences and missing comparator material under `revolut-design`; run the installed member, Admin and public route/state matrix on candidate artifacts.
- Run the complete Flutter, native, Edge, SQL and tooling gates on one protected frozen commit. Record exact failed/skipped counts, hashes and environment. The earlier full Flutter result predates later changes.
- Obtain the concrete external evidence pack: Drive ACL and exposure/rotation decisions, authorized Supabase readback, provider/real-SIM and signed-device results, Google Play restricted-SMS decision, legal/privacy/vendor determinations, Git/CI protection and owner release authority.
- Rehearse restore, monitoring, support and rollback; run a bounded pilot only after prerequisites pass, then record the GO/NO-GO decision.

Update the register and audit as evidence changes. Do not mark this goal complete because a file exists, a test passes in isolation, or a task is locally implemented.
