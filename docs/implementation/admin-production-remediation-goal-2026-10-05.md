> Historical source-checkout snapshot for publication review. Its prior local and hosted claims do not establish acceptance of this isolated candidate. See the publication-isolation inventory for source bytes and outstanding verification.

# Active goal: Collect Admin production readiness

Created 5 October 2026 in Codex chat `01a1067a-029c-7a63-81f8-6ff9171ca83d`. Status: **active; implementation started; production acceptance open**.

The controlling finding set is [the Admin readiness review](admin-production-readiness-qa-2026-10-05.md), ADM-01–ADM-17 and its six hosted release gates. This checkpoint tracks implementation and accepted proof; it does not replace the review or turn its historical evidence into current acceptance.

## Outcome and boundaries

Deliver the requested Admin workflows through the canonical Cloudflare frontend, APIs and clean database, close all reproduced defects and functional gaps, then verify the intended production deployment and external lifecycle. No legacy Supabase data import is required by the owner's clean-database direction. Preserve existing dirty/recovered work and Collect identity. Admin is the sole product surface in scope.

Efficient Codex governs execution. Revolut Design is the sole visual authority: Business/operator web patterns, existing semantic tokens and licensed Inter; dedicated-column tables and horizontally accessible narrow layouts everywhere except Overview. Native Computer Use verifies real interactions. Auth/session, financial-ledger and Admin-operation engineering skills apply to their actual boundaries. Missing comparator or external evidence remains unverified.

Goal completion requires both integrated implementation and actual production acceptance. Local tests, a build, preview deployment, a provider-accepted email or a recovery bookmark cannot close hosted role, delivered-email, production, spoken accessibility, performance or restoration gates by themselves.

## Milestones and acceptance

| Milestone | Finding coverage | Closure proof | Status |
| --- | --- | --- | --- |
| 1. Runtime and security reliability | ADM-02, ADM-10, ADM-13 | Real-shell unchanged-session draft/search/page/recovery preservation; revocation fences; cold deep-link/login/Back/reload; audit-failure rollback and lost-response recovery | In progress |
| 2. Authoritative people and contributions | ADM-03–05, ADM-14, ADM-16 | Admin/Staff/App/Direct identity and six-digit IDs; full authorized WhatsApp/MoMo number/optional code; per-group/overall aggregates; normalized intent-aware search; complete summary links | In progress |
| 3. Operating workflows and transaction evidence | ADM-06–08, ADM-15, ADM-17 | Reconciliations/SMS list/detail; Staff private create/propose only; Admin publication; source SMS facts, fixed-width public reference, payer insights; MoMo-confirmed member allocation; complete paging | Open |
| 4. Tables, navigation and accessibility | ADM-09, ADM-11–13 | Dedicated columns on every non-Overview listing/subpage; readable label/value semantics; row-wide keyboard navigation; allocation status and numeric amounts; responsive native UAT | In progress |
| 5. Exact release and operation proof | ADM-01 plus six release gates | Frozen source/artifact/backend/configuration identity, current CI and independent review; target-specific gates; hosted role/provider UAT; monitoring/recovery/load/device evidence; approved production cutover and readback | Open |

## One writer per boundary

| Owner | Current write boundary | Integration contract |
| --- | --- | --- |
| `admin_runtime_fix` | Cloudflare entrypoint/session/router and focused runtime tests | Canonical actor/session/role/permission authority remains stable on identical poll. Validated return destination survives restore/login. Root owns list-page declarative detail URLs. |
| `admin_backend_qa` | Admin Worker account-security flows and accounts tests | Security mutation and conditional success audit share one guarded atomic batch; no API schema change. Release Worker ownership before new role/route changes. |
| `admin_people_backend` | Core/operations projections, additive people migration 0008 and focused backend tests | Send schema/payload contract before large edits; root integrates Dart consumers. No fabricated provider facts or broad Staff permissions. |
| Root | Integration, Admin table/detail/account UI, goal/evidence and subsequent release workflow | Preserve shared primitives/legacy consumers; coordinate future ownership of workflows, permissions and schema numbers. Own the single final build. |

No worker performs independent deployment, provider/hosted mutation, broad aggregate reruns or a parallel frontend build. Workers do not recursively delegate. Existing source owners must release files before reassignment.

## Reusable starting evidence and preservation

Starting HEAD: `eed1925260780d079a638603f22837f095f943be`; the existing dirty working tree is the implementation base, not a clean-HEAD substitute. Before remediation, 274 relevant working source/test/migration/package files were saved with hashes in `.cache/admin-production-remediation-20261005/working-source-baseline.json` and `working-source-baseline.tar.gz`; initial Git status was saved alongside them.

The preceding review's 100 Flutter, 96 backend and 25 anonymous hosted passes are baseline proof only. Refresh affected tests and downstream evidence after changes; preserve still-valid unrelated proof. Final checks must use a frozen integrated source and exact artifact identity. Run `make revolut-design-authority` after shared-component/theme/reference changes; it checks authority hygiene, not visual parity.

The old disposable UAT server is stopped and its local session signed out. Root will start one explicitly owned replacement runtime after integration. Production/preview login tabs are preserved. No provider, production data or deployment change has yet been made under this goal.

## External dependencies retained

Owner activation must use the intended hosted invitation/password workflow; no credential/session bypass. Actual mail receipt, independent Admin/Staff access and controlled financial review/posting remain required. Production cutover needs a concrete verified artifact, target and rollback plan before an irreversible decision. Redacted monitoring, a disposable recovery drill with measured RPO/RTO, exact-source CI, hosted load budgets and intended physical-browser/spoken-reader evidence remain open.

## Next dependency

Integrate the runtime/security slices and agree the authoritative people API contract. Root converts detail facts and related records to readable tables, then integrates complete typed listing columns without changing authorization meaning. Update this checkpoint with actual changes, test results, external gates and active owners at each usable milestone.

## Implementation checkpoint: integrated local slices

The active goal has implementation, not only a plan. Still **no production-ready declaration or production deployment**.

| Work | Current implementation and proof | Remaining closure |
| --- | --- | --- |
| Runtime/session | Canonical authority, guarded pending responses, local deep-link return, unchanged-poll draft/search/page/recovery preservation; initial worker 26 tests and updated root runtime regression retained in `.cache/admin-production-remediation-20261005/runtime/` | Repeat native reload/Back and hosted expiry/revocation after final integrated artifact |
| Security accounts | Conditional security audit shares credential transaction; initial 18 failure/recovery cases passed. UI handles unknown password outcomes by clearing secrets, blocking replay, and directing authentication/reset recovery. Team data is a table with recorded name and six-digit ID. | Final current-Worker account regression; actual hosted invitation/password/reset/role UAT |
| People | Additive 0008, immutable global six-digit namespace, explicit linked/unlinked operators, App/Direct distinction, full authorized contacts, optional zero-preserving code, confirmed allocation/posting totals, honest missing names, normalized intent/ranked search. Worker final 32 cases passed. Supporting member registration uses the same in-batch allocator; 19 consumer cases passed. | Final integrated source/role/aggregate/native checks |
| Tables | Shared dedicated-column table, exact whole amount formatting, readable selectable facts, interactive horizontal thumb and arrows, row activation. Six core areas and Team/detail/related views use it. Initial 59 integration cases passed before subsequent Staff/name edits. | Remaining gateway/email/member receipt tables and fresh integrated checks/native accessibility |
| Staff/private groups | Separate `collections.create`; private-only draft or atomic active owner/receiver setup, no broad Staff edit/publication. Backend proof included in worker 32 tests. | Root UI form/native active create and server role negatives |
| Reconciliation | Additive 0009; member-first identity proposal, no Staff financial effect, independent Admin approval, immutable request/audit/financial facts, version/conflict/replay/unknown recovery, complete related paging. Initial 13 backend cases passed. | New typed UI integration; recorded-name eligibility regression; hosted two-operator UAT |
| Related paging | API per-relation exact totals and deterministic pages; detail UI exposes previous/next and refreshes complete state on resource version change | Meaningful final >200 UI/service test and native navigation |
| SMS/public references | Strict immutable source-fact module and additive 0010 are being tested; unknown SMS facts remain null; public transaction reference always fixed-width and stable | Parser/schema failure proof, transaction joins/payer insights, UI, actual receiver source storage and device/provider acceptance |

Current owners: `admin_runtime_fix` owns only new reconciliation Dart/API/tests; `admin_backend_qa` owns only new SMS module/0010/tests; `admin_people_backend` owns gateway/email/member receipt Dart tables/tests. Root owns released backend/core integration, operating/account UI and release evidence. No parallel builds/deployments.

Visual comparison used named **public Business/operator promotional adaptations**, not an authenticated table parity claim: `enterprise.png` (SHA256 `cc4d984177ef14a987baa9c07ce6cdc36af6ffc9827b4431f2d5697eeba215dd`) and `bills-preview.png` (SHA256 `d142f7fcb0fd7098e2574e98bad74da84c4d4a849d48d65ce9de9cc0fc56e849`) under the owner's Revolut reference library. They support dark operational composition and receipt context only; full live table geometry remains unverified. Existing licensed Inter and Collect semantic tokens are retained. `make revolut-design-authority` exited 0 after shared table changes; that is hygiene proof, not visual fidelity.


## Current integration checkpoint: source review corrections

Status remains **active**. The previous goal turn made concrete source changes and produced regression evidence; no blocked audit applies. No hosted mutation or release has occurred.

- Runtime routing, narrow grants, full system-directory contacts/totals, dedicated-column table primitives, Team role policy and transaction facts are integrated. Root's latest affected contract/UI run passed **55/55** in `root-contract-tests.log` under `.cache/admin-production-remediation-20261005/`; it includes invalid SMS calendar/offset/context, independent source lineage, and retired raw-allocation denial. Four earlier label/route regressions were fixed and the affected 18 cases passed in `ui-columns-routes-current.log`.
- Reconciliation backend recorded-name/number eligibility and complete source projection passed 14 cases. The current typed reconciliation API/real-shell suite passed **12/12**, analyzer clean, input hashes unchanged, in `reconciliation/verified-tests.log`. The released slice retains pending intents across polling and navigation; a further storage slice is implementing original-key recovery across browser hard reload.
- SMS API/pages passed **13/13**, analyzer clean, in `admin-sms-ui/`. Gateway/email/member-receipt tables retain their released **24/24** proof under `.cache/admin-production-remediation/integrations-tables/`. Current account backend passed **18/18**; current transaction core/operations passed **38/38** before the reviewed-member correction below. These are local scoped results, not a single frozen final source claim.
- Read-only independent source review found three additional P1 integration issues: member facts were offered at transaction creation although review requires an existing transaction; receiver storage/producer was absent; and explicit contradictory SMS recipient facts were not checked. Creation now offers only receiver facts. Backend ownership is closing the other paths with immutable reviewed-member source lineage (migration 0011), same-kind recipient guards, and capture-only enrolled gateway grants/durable signed ingress (0012). Original public IDs and their prefix provenance remain immutable; source evidence never claims provider confirmation or settlement.
- The canonical build script now records actual tracked and untracked working inputs, fails if they change during build, hashes the emitted main asset and declares the minimum required source schema. CI reuses this exact Cloudflare artifact rather than compiling a different Admin entrypoint. Fresh independent CI remains unverified. Build metadata stays a candidate, with hosted migration acceptance false.
- Candidate configuration includes a private receiver payload binding and redacted structured health logs, with invocation logs disabled and query strings redacted. Two focused health-schema tests passed. The bucket is not yet provisioned, logging/alerts are not live-accepted, and no real gateway source has been captured.

Current ownership: `admin_people_backend` owns source-lineage/recipient-guard backend integration, gateway member-review coupling, migrations 0010/0011 and focused tests; `admin_backend_qa` owns the separate receiver ingress module, migration 0012 and focused tests, coordinating shared gateway verification with the former; `admin_runtime_fix` owns the shared pending-attempt store and reconciliation adoption/tests. Root owns other Dart consumers, Worker routing/configuration, release scripts/CI, and the single final integrated build/native UAT.

Root has prepared, but not started, a replacement ephemeral local runtime in `local-uat/server.mjs`, using current migrations, 230 synthetic people, three groups and explicitly synthetic source receipts. It exercises canonical extraction/transaction/evidence-review APIs; direct fixture receipt insertion is labelled and cannot count as enrolled device/provider acceptance. The hosted preview sign-in screen was freshly inspected through Computer Use. No Owner activation, credential entry, invitation/reset dispatch, production financial action, deployment or source publication was performed.

## Recovery and ingress integration checkpoint

The goal remains **active**, with hosted acceptance and production cutover open. All implementation ownership below has been released to root; independent workers are reviewing the remaining release and receiver boundaries read-only.

- Reviewed-member SMS lineage, same-kind known-recipient contradiction guards and complete payer history are integrated in migrations 0010/0011 and current operations/gateway/core modules. The released focused backend proof passed **69 cases** (19 SMS, 10 gateway, 28 operations and 12 core), with preserved immutable public references. Evidence: `.cache/admin-production-remediation/member-sms-lineage/`.
- Capture-only enrolled-device grants, conditional private R2 persistence/readback, signed exact-byte ingress and actor-scoped durable request lookup are integrated in receiver ingress migration 0012 and Worker routing. **16 receiver, 18 accounts and 14 reconciliation cases** passed against isolated current Worker/D1/R2. Source-captured receipt metadata is distinct from provider confirmation, sending and financial authority. No hosted bucket or device authority was provisioned. Evidence: `.cache/admin-production-remediation-20261005/receiver-ingress/`.
- Shared per-tab recovery now retains strict bounded intents and original keys until the same authorized session expires, capped at eight hours from original creation. This corrects an independently identified P1: a 15-minute expiry could erase the key of a committed journal. **21 store/API/real-shell cases** passed, including a 30-minute reload, unchanged-session preservation, changed-authority clearing, lookup-first recovery and explicit unchanged confirmation. Scoped analyzer is clean. Evidence: `reconciliation/pending-store-*` in the current remediation cache.
- SMS and operating forms use the same storage contract before transport. The integrated run passed all **14 SMS and 9 operating cases**, including hard reload and 409 `request_pending` retention. Its two receiver failures were a test harness bound and a real AlertDialog/table intrinsic-size defect; both were corrected. The affected receiver suite then passed **14/14**, including missing/wrong-type names and MoMo routes, stale identities, readonly Staff, complete capture paging, original-key reload and explicit identical retry. Restored new-grant confirmation refetches the exact original active device/payee and frozen versions before enabling retry. Evidence: `receiver-pending-consumers-tests.log` and `receiver-pending-consumers-current.log`.
- Both Admin build paths now remove only generated Aeonik Pro assets and their manifest entries before hashing. Licensed Inter and all other generated asset bytes are preserved; source fonts and mobile configuration are unchanged. The helper passed **18 focused tests**, including a copied real build, malformed/unsafe paths and rollback. This is output-pruning proof, not a font licence grant. Evidence: `.cache/admin-production-remediation/admin-font-assets/`.

The next release dependency is the single frozen canonical Admin build, source/asset identity and fresh native full-stack UAT against the owned disposable 230-person runtime. Real hosted Owner activation, delivered email, independent roles, approved migration/device/provider/financial acceptance, exact-source CI, monitoring/recovery/load/spoken-reader proof and production readback remain required.

## Native and release isolation checkpoint

The goal remains **active**. Local implementation and verification have progressed; the six hosted gates remain open. No source publication, deployment, hosted account/financial mutation or external email was performed under this goal.

- The canonical candidate with main asset SHA256 `9a11fc071e8dd9a2572b423e3683ac9f64b631c8e531519e919543bf906437ba` passed source/artifact/preflight checks. Its 154 emitted files and exact manifests are preserved in `frozen-candidate/artifact-main-9a11fc071e8d.tar.gz`, archive SHA256 `750a9d69284456f3409d9a62ea43e778b8d0b3c466191300862d159f6b2e36b7`. Existing native proof is bound to this historical candidate; subsequent source fixes require a new build and native acceptance. `release_admissible` remains false.
- Native Mac Chrome against the owned ephemeral Worker/D1/R2 runtime confirmed the 233-person system directory, App/Direct identity, normalized full-phone and Staff-intent search, dedicated transaction facts, selectable accessible detail values, resource row-body navigation, cookie-backed detail reload, and unchanged-session draft/page preservation over more than one 60-second poll. Group membership paging reached all **230** members across five pages. At **320×740**, keyboard focus and right-arrow keys exposed later dedicated table columns. This is desktop native/viewport evidence, not physical-phone or spoken-screen-reader acceptance.
- Local Staff UAT confirmed readonly payees and Team route denial. A member-first ALICE proposal produced an authoritative **Pending** receipt while allocated totals remained zero; it is proposal-only proof, not approved allocation or posting. Two earlier group snapshots show the seeded Public Approved group despite their filenames and must not be used as successful private creation proof. Two semantic/offscreen Open actions selected adjacent records; those automation steps are excluded pending fresh visible-pointer/keyboard verification. Source row callbacks bind the exact row, but that alone does not close the observed interaction uncertainty.
- Native follow-up identified two genuine defects: the Flutter engine decoded punctuation in the reported browser URI, losing a phone-search return destination after detail reload; and Staff group confirmation rejected server-fixed private/sponsorship fields before transport. The route adapter passed **10** focused cases and the Staff recovery slice passed **11**, including original-key reload/lookup-first behavior. Both fixes await the next exact-artifact native UAT. A still-armed, disposable local POST lost-response fault will verify successful private creation and receipt recovery without a second write.
- A final table census found request history and saved operation/email receipts still combined data. Those shared surfaces now use dedicated columns; Record ID is a selectable detail-table field. Five focused table/keyboard/navigation/paging cases passed. The final integrated Admin runtime/UI suite passed **190/190** in `all-admin-runtime-current-tests.log`. A previously incorrect import in the non-canonical privacy review was corrected to preserve full Admin import closure.
- The output helper now supplies Flutter's hardcoded default `Roboto` family from the same bundled licensed Inter bytes. The strict manifest/preflight checks reject foreign or missing fallback assets and preserve product Inter typography. All **47** assets/preflight helper cases passed; browser absence of the former external font request still requires the rebuilt candidate. The design-authority hygiene check passed; visual parity remains unverified.
- An attached managed candidate worktree rooted at base `eed1925260780d079a638603f22837f095f943be` isolates Admin/frontend/backend/test/release changes from the large recovered dirty checkout. The first admitted overlay has 369 changes and complete local Dart import closure. It retains HEAD mobile/platform, unrelated shared module/package inputs and ordinary SQL CI behavior. Subsequent released corrections are being admitted by one owner. Fresh dependency resolution, aggregate tests/build/source seals and exact CI execution are still required on that isolated source before publication.

Evidence is under `.cache/admin-production-remediation-20261005/native/`, `frozen-candidate/`, `publication-isolation/`, `staff-group-recovery/` and the route/request-table proof files. Current ownership: root owns integrated checks, canonical rebuild, native UAT, goal evidence and external acceptance preparation; `release_candidate_review` owns only the isolated overlay/evidence; `admin_acceptance_matrix` is a bounded read-only source reviewer. No worker runs a parallel Flutter process or performs provider/publication actions.

## Current continuation — 14 October 2026

The intended production-readiness objective is **incomplete**. The Codex goal tool
currently reports `usageLimited`; it has not been marked complete. Work continues
under the owner's explicit continuation request. Prior dated snapshots above are
historical proof, not acceptance of the current source or deployed application.

The T7 workspace is reconnected. Recovered source and collision preimages were
preserved, then reviewed Admin paths were admitted into the attached managed
`admin-readiness-final/COLLECT` checkout. Unrelated mobile/platform/package work
is excluded. Actual D1/R2 backend tests pass 176/176. Native Mac Chrome verified
dedicated tables, normalized phone search, paging retained across session refresh,
Direct-person payment identity/totals, transaction payer insights and original
reconciliation receipts. Staff successfully created a private draft and submitted
a pending member proposal while privileged controls remained denied.

Native journal fault injection committed one posting, withheld the response and
recovered the original receipt after reload without a second posting. Request
history now accepts actual SMS and reconciliation receipt schemas and retains
read-only historical scope compatibility. Terminal membership/journal recovery
keeps exact resource, version, actor and original-key fences.

Final review also corrected misleading payee state-conflict guidance, added the
explicit group-suspension receiver workflow with validated authority/lock-fenced
navigation, moved transaction money/status columns before long metadata, and
identified the need for exact journal context/lines at permanent-posting review.
Final aggregate checks, canonical artifact identity and affected native followups
must bind those released changes before publication or hosted activation.

The current findings, proof boundaries and six remaining hosted gates are in
[the 14 October Admin UAT review](admin-production-readiness-uat-2026-10-14.md).
Fresh remote read-only evidence confirms pending migrations 0008–0012 and the
older production application. Owner activation, private receiver storage and
approved device identity, delivered provider lifecycle, current successful CI,
hosted financial/recovery/performance/device acceptance and approved production
cutover/readback remain open. Local passes and a draft PR cannot close them.


## Owner table clarification — 15 October 2026

The owner selected tables on **every** page, including Overview. The current
implementation adds an Overview summary/operator table, server-backed core
column ordering and concept-aware search, plus explicitly scoped loaded-page
search/filter/sort on other multi-row tables. See
[the table update](admin-smart-tables-2026-10-15.md). The broader production
readiness goal and six hosted gates remain incomplete. Prior card-exception
language above records historical direction only.
