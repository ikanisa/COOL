# Hosted security triage — retained readback, 30 September 2026

## Decision and scope

**Production remains NO-GO.** The retained hosted catalogue has **124 migrations**, ending at `20260906160000`, while the local candidate has **142**. All 18 local migrations numbered 125–142 are absent from this hosted ledger. Critical differences include the member-roster boundary, SMS financial finality, receipt protocol 2, notification fencing/session revocation, governed reconciliation and roster provenance. This is a confirmed deployment-control gap; it is not proof that every possible exploit has been exercised.

This report is a **read-only static triage of the supplied snapshots and local source**. No database, Auth, provider, GraphQL, hosted function, test, build or deployment was invoked for this review. The only repository edit is this report. Snapshot metadata does not establish the current live state after its observation time.

The catalogue was observed at **2026-09-29 23:02:28 UTC** (30 September in Kigali); advisor observations begin at `2026-09-29T22:59:14.915Z`. PostgreSQL reports `17.6`. `exposed_schemas` is **null/unavailable**, not an empty allowlist. The catalogue includes 139 tables, 151 policies, 100 triggers, 282 function metadata entries and five cron jobs. It does not include function bodies, column ACLs, view definitions/options, role membership, Auth provider settings, Edge source bundles, secrets or feature-flag values.

The security triage skill's source/control/sink and counterevidence method was applied. No applicable `SECURITY.md` was found by the policy resolver for `supabase`; product migrations, grants, policies and explicit local contract comments provide the boundary evidence. No whole-repository security certification is implied.

## Input integrity and corrected migration fingerprint

| Retained input | SHA-256 |
| --- | --- |
| `catalog-readback.json` | `4a13e77ee96b7e9916841dd10cd70608cbe91ae3cb4671909d3df35709b48954` |
| `security-advisors.json` | `b09efa4327c3abb614274907f1d29461488a9d4952d8539b857c154a1ff3c7f8` |
| `migration-drift.json` | `1df0f8c966ba2a6d92b5dfb92cf3c112193b0ad284c49f5295d291ac27a833d2` |
| `edge-functions.json` | `e921d9ee14933a030262716f9d423bb1b8ad768490852a7a352c92181dfd7a5b` |

The retained drift file records migration 142 at `46cc675c117a3fa6d438db8501a3e9643496a13a80305ae2a61071c27060d01e`. That source had a SQL parser defect and has been superseded by the corrected local file at **`75a315d8a41c2c19f62f2fcd4557e27cb7c14e3f9ebe251f57b18e748d7349d7`**. The contract is unchanged. The report verified that migrations 125–141 still match the retained drift fingerprints and that 142 now has the corrected hash. Do not deploy or represent the earlier 142 fingerprint as the accepted candidate. Preserve the original readback and retain a new candidate manifest and execution evidence.

## Highest-priority release blockers

| ID | Established fact and risk | Required action before release |
| --- | --- | --- |
| H01 | Hosted `finalize_attested_payment_sms(uuid)` still exists with service execution and missing migrations 129/133. The historical local implementation forwards a device-observed SMS into `process_provider_finality_event(..., 'payment.confirmed', ...)`. Function body parity and the actual deployed parser call path are not retained, so live exploitation is not claimed. | Prove the hosted body; apply the reviewed observation-only/receipt-v2 contract with compatible handlers. A stored/attested/parsed SMS must never alone confirm a payment, post a journal, allocate funds or advance balances. |
| H02 | Missing 125 leaves the recorded old source using public collection readability to authorize group-roster access. Its public-approved branch can admit a signed-in nonmember. This is separate from intended public directory/payment-route access. | Stage the membership-only replacement; prove unrelated authenticated users and platform staff without membership cannot read rosters through any wrapper. Preserve verified feature-phone claim membership. |
| H03 | Three bank ingestion functions remain ACTIVE (`ingest-bank-email`, `ingest-bank-sms`, `ingest-bank-statement`), old bank RPC grants remain, and cron job 6 `collect-daily-bank-reconciliation` is active. Missing 127 leaves the Rwanda/RWF/MoMo-only scope retirement absent. | Retire the three deployed handlers, revoke only the identified legacy bank/scope privileges as reviewed in 127, and explicitly disable/remove the bank cron after retention and rollback planning. Preserve historical records. Confirm no financial writes occur through removed rails. |
| H04 | Hosted notification claim/completion signatures are the old unfenced forms. No `collect-dispatch-notifications` cron is listed; migrations 137–139/141 are absent. | Upgrade SQL and compatible dispatch/send/client implementations together; configure Vault-backed scheduling while disabled, prove protocol-2 leases and session/token ownership, then deliberately enable one scheduler. |
| H05 | `reconciliation-finalize` is absent from the retained Edge inventory; governed reconciliation 140 and current-session/AAL2 hardening 141 are absent. Existing privileged finality RPC metadata is not equivalent to this governed service. | Deploy the reviewed finalizer only after SQL authorization/independent checker/evidence binding are proven. Retain negative and concurrency tests and verify finalizer bundle/configuration. |
| H06 | Hosted roster import is Edge version 1 and lacks migration 142. Authenticated raw-row writers `admin_add_assisted_roster` and `admin_create_assisted_group_with_roster` remain executable. | Release corrected 142, Edge contract 1 and matching Admin client as one compatible rollout. Keep the feature unavailable until original-byte source receipts, consent, immutable reviews and reference-only final commit all work. |
| H07 | Hosted Edge metadata includes versions/hashes but not downloaded source bundles; no local-to-hosted bundle equivalence is established. `verify_jwt:false` is used by webhook/internal functions and cannot alone establish an authentication bypass. | Verify actual signed webhook/internal-secret checks in exact staged bundles; unauthenticated/static-secret/replay calls must fail before SQL/provider work. Do not blindly flip gateway JWT verification for legitimate Auth hooks. |

**Bank cron detail:** the retained job 6 command MD5 `0682a2a141329919f696e8ec4627fb30` matches the literal historical SQL command `select public.run_daily_bank_reconciliation(current_date, 'scheduled daily reconciliation');`. Migration 127 revokes function/table privileges but does **not** unschedule that job. The historical function expressly permits `session_user` of `postgres`/`supabase_admin`, so grant revocation is insufficient if the cron still runs as its privileged installation owner. The job's runtime username and current body are missing from the snapshot; verify them and explicitly retire the job. Do not delete retained bank evidence to resolve the scope mismatch.

### Source anchors for H01–H07

- [20260903084000_hybrid_direct_ussd_financial_core.sql:1479](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260903084000_hybrid_direct_ussd_financial_core.sql:1479)
- [20260928160000_sms_observation_never_settles.sql:6](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260928160000_sms_observation_never_settles.sql:6)
- [20260928174000_attested_receipt_v2_contract.sql:7](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260928174000_attested_receipt_v2_contract.sql:7)
- [20260903091500_hybrid_member_directory_views.sql:289](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260903091500_hybrid_member_directory_views.sql:289)
- [20260914165641_restore_member_roster_membership_boundary.sql:6](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260914165641_restore_member_roster_membership_boundary.sql:6)
- [20260820162240_bank_transfer_only_financial_control_plane.sql:1157](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260820162240_bank_transfer_only_financial_control_plane.sql:1157)
- [20260820162240_bank_transfer_only_financial_control_plane.sql:3037](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260820162240_bank_transfer_only_financial_control_plane.sql:3037)
- [20260925190000_rwanda_momo_only.sql:523](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260925190000_rwanda_momo_only.sql:523)
- [20260929160000_notification_retry_schedule.sql:186](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260929160000_notification_retry_schedule.sql:186)
- [index.ts:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/functions/reconciliation-finalize/index.ts:1)
- [20260930100000_roster_import_provenance.sql:206](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260930100000_roster_import_provenance.sql:206)
- [handler.ts:278](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/functions/prepare-roster-import/handler.ts:278)

## Six anonymous SECURITY DEFINER routines

All six grants are confirmed in the retained metadata. Their **local intended behaviour** is constrained; anonymous execution alone is not an exploit. The deployed bodies are retained only as MD5s, so each supplied warning remains `needs_review` for hosted body/configuration parity. A blanket revoke or conversion to `SECURITY INVOKER` can break public policy pages, public contribution routes and RLS helpers.

| Routine | Local boundary/counterevidence | Concrete verification and negative tests |
| --- | --- | --- |
| `collection_is_public_approved(uuid)` | Returns a boolean for an approved, unarchived collection. It is used by read policies that cannot directly select a protected status column. No member names or private receiver details are returned. | Private, pending, archived and nonexistent IDs must return false. Verify the exact deployed predicate and every policy caller. Do not replace a helper with caller-level reads that fail column privileges. |
| `get_active_policy_document(text,text)` | Read-only projection of published, already-effective policy document content, with locale fallback. Its selected sections belong to the chosen document. | Draft/future versions must not escape via locale, kind or section joins. Verify projected columns and writable-schema/search-path privileges. Preserve public access to current legal notices. |
| `list_account_request_reasons(text,text)` | Read-only enabled, localized public reason options. No user's deletion/support request is returned. | Disabled options and unexpected request types must not expose private request records. Confirm fixed SQL, intended fallback and bounded response catalogue. |
| `public_collection_payment_route(uuid)` | The recorded-era local definition returns the active MTN/Airtel route only for approved, sponsored, unarchived public collections; this public payment destination is deliberate. Owner IDs and hashes remain excluded. | Private/member-created/pending/archived/unsponsored IDs return no route. After missing 127 is applied, require RWF and `diaspora_enabled=false` as well. Verify the exposed route is an approved public contribution destination, not a personal receiver record. |
| `user_can_read_collection(uuid,uuid)` | Local guard permits an arbitrary target user only to `service_role`; otherwise the supplied user must be `auth.uid()`. The public-approved branch intentionally permits directory visibility. | Anonymous and member A calls naming member B must not reveal B's private membership. Test null/default arguments, revoked claims and private IDs. Do not use this broad public-read helper to authorize a roster; H02 is the specific missing replacement. |
| `user_is_collection_admin(uuid,uuid)` | Same current-user/service exception guard, then platform/creator/active owner-admin-receiver checks, including verified claimed feature-phone membership. | Forged user UUID, inactive membership and unrelated users must fail; default anonymous/null calls must not become privileged. Verify the transitive `is_platform_admin` and claim predicate and schema CREATE privileges. |

- [20260730134500_grant_mobile_request_own_read.sql:11](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260730134500_grant_mobile_request_own_read.sql:11)
- [20260704120000_policy_documents_account_reasons.sql:143](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260704120000_policy_documents_account_reasons.sql:143)
- [20260704120000_policy_documents_account_reasons.sql:196](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260704120000_policy_documents_account_reasons.sql:196)
- [20260901200000_localize_public_group_payment_routes.sql:7](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260901200000_localize_public_group_payment_routes.sql:7)
- [20260903091000_hybrid_verified_account_claim.sql:84](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260903091000_hybrid_verified_account_claim.sql:84)
- [20260903091000_hybrid_verified_account_claim.sql:119](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260903091000_hybrid_verified_account_claim.sql:119)

Five routines retain `search_path=public`; the public route uses an empty search path and qualified names. This is not evidence that an attacker can create shadow objects: schema CREATE ACLs/role inheritance are absent. Verify those privileges before classifying a search-path exploit or mechanically changing established functions.

## GraphQL, public columns and private RPC storage

The scanner reports **19 anonymous** and **32 authenticated** GraphQL exposures. Exposure is a transport/permission fact; it does not automatically bypass RLS. The same object may appear once per role and is preserved twice in the appendix.

- **Intended public catalogues:** active brand/type/category/country rules, enabled support/payment entrypoints, published policy sections and published notification templates are used by sign-in/public/member experiences. Recorded policies restrict notification versions to published/effective versions whose template and event type are enabled. Keep intended public reads; verify drafts, internal template metadata and all mutation paths remain denied.
- **Highest-priority column verification:** `profiles` has a SELECT policy of `true`, with column grants rather than unrestricted table SELECT in local source. The later SMS-first migration explicitly revokes `SELECT(display_name, avatar_url, anonymity_default)` at lines 486–487; `public_profiles_view` intentionally projects a Collect ID label and no avatar. The table ACL alone cannot enumerate its column access. Obtain `information_schema.column_privileges`/column ACLs and view definition/options, then test GraphQL and REST selections for phone, MoMo identifiers/hashes, private names and internal fields. A publicly visible view does not prove that its base table exposes only the view's projection.
- **Collections:** the retained SELECT policy permits approved public rows or current-member readability. Local public-directory views are invoker/barrier views with an approved sponsored unarchived filter. Anonymous full-row/API introspection and aliased/nested GraphQL queries must not disclose private collection/receiver/member fields. Missing 127 still requires Rwanda-only filters and retirement of older expansion fields/routes.
- **Authenticated records:** `notification_events` and `notification_preferences` bind `user_id=auth.uid()`; support/deletion requests bind owner or platform authority. Verify member A cannot select, aggregate, mutate or traverse relationships into B's rows. Collection summary/contribution/member views require current invoker options and member boundaries; view names alone are not evidence of safety.
- **Admin catalogues:** navigation and queue specs have recorded `has_admin_permission('settings.read/manage', auth.uid())` policies. Authenticated GraphQL type visibility is not proof that a regular member can read or edit those rows. Negative tests must include an ordinary verified user, not merely anonymous.
- **Realtime invalidations:** recorded `app_realtime_events` allows all authenticated reads. Local schema contains only event ID, area and timestamp, and its emitter inserts the area, not a row payload. This is meaningful counterevidence to a private-record leak. Confirm the deployed columns/triggers still carry only non-sensitive invalidation metadata and assess aggregate activity visibility separately.

**46 RLS-without-policy findings:** every listed table has RLS enabled and no direct PUBLIC/anon/authenticated table ACL entry in the retained catalogue. These include private member identities, balances/journals, source evidence, device tokens, share secrets, approvals and bank records. The lack of permissive row policies is a deliberate default-deny design, with access mediated by narrow owner/service RPCs. For the supplied “no policy” condition, these 46 are `not_actionable` as a demand to add public policies. That verdict does not certify every privileged RPC, role hierarchy or historic bank surface. Do not add catch-all policies, force all tables to invoker access, or expose private schemas simply to silence the advisor.

**134 authenticated SECURITY DEFINER findings:** the architecture intentionally uses RPCs for controlled writes and sensitive reads. They are not individually cleared by this scoped review; each remains `needs_review` in the appendix. Prioritize legacy bank and raw-row writers, financial finality/reconciliation, raw SMS/reveal, role assignment, device registration and membership mutations. Require the actual body, current Auth/session/role checks, least-privilege grants and negative tests. Function execution grants by themselves establish neither authorization bypass nor correctness.

**Leaked-password protection warning:** the advisor recommends enabling compromised-password checks; the snapshot does not establish feature eligibility, enabled password sign-in/recovery paths or their approved threat model. Treat as `needs_review`. If password authentication remains supported, enable the available protection and test breached-password rejection through actual supported flows. If the product is OTP-only, verify passwords/sign-up/recovery cannot open an unintended alternate route and document applicability; do not claim the warning irrelevant from the app UI alone.

- [20260523204235_set_views_security_invoker.sql:4](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260523204235_set_views_security_invoker.sql:4)
- [202605270001_sms_first_group_payment_intents.sql:919](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/202605270001_sms_first_group_payment_intents.sql:919)
- [20260901200000_localize_public_group_payment_routes.sql:49](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260901200000_localize_public_group_payment_routes.sql:49)
- [202605250001_app_realtime_invalidation.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/202605250001_app_realtime_invalidation.sql:1)

## Missing migrations 125–142: exact deployment prerequisites

Each entry below is absent from the retained hosted ledger. Local existence is not deployment proof. Apply the ordered, reviewed graph to staging from the observed 124 state, not isolated fragments.

| Local ordinal/version | Control introduced | Required staging acceptance |
| --- | --- | --- |
| 125 / `20260914165641` — [20260914165641_restore_member_roster_membership_boundary.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260914165641_restore_member_roster_membership_boundary.sql:1) | Member-roster membership boundary | Public-approved visibility must not admit an unrelated signed-in user to roster rows; preserve linked/claimed active membership. |
| 126 / `20260914213600` — [20260914213600_atomic_otp_rate_limit.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260914213600_atomic_otp_rate_limit.sql:1) | Atomic OTP quota reservation | Concurrent/replayed requests cannot exceed actor/phone/network limits or send twice; provider failure/dry-run must not claim delivery. |
| 127 / `20260925190000` — [20260925190000_rwanda_momo_only.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260925190000_rwanda_momo_only.sql:1) | Rwanda RWF/MoMo-only scope | Block unsupported rails on profile/group/payment writes; retire bank RPCs, handlers and cron; inspect legacy rows before validating NOT VALID constraints. |
| 128 / `20260928150000` — [20260928150000_relational_member_history_pages.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260928150000_relational_member_history_pages.sql:1) | Relational member history pagination | Cross-member pages/counts must stay private and bounded; no whole-history materialization regression. |
| 129 / `20260928160000` — [20260928160000_sms_observation_never_settles.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260928160000_sms_observation_never_settles.sql:1) | SMS observation never settles | Receipt ingestion/parsing/finalizer path leaves payment, allocation, journals and balances unchanged without independent confirmation. |
| 130 / `20260928170000` — [20260928170000_confirmed_momo_payer_posting.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260928170000_confirmed_momo_payer_posting.sql:1) | Confirmed MoMo payer posting | Only verified provider finality posts correct payer/member credit once; wrong payer/reference/amount fails. |
| 131 / `20260928171000` — [20260928171000_strict_intent_sms_match.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260928171000_strict_intent_sms_match.sql:1) | Strict intent/SMS matching | Mismatched amount/receiver/reference/time/intent cannot gain allocation or finality. |
| 132 / `20260928172000` — [20260928172000_allow_incomplete_rwanda_onboarding_profile.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260928172000_allow_incomplete_rwanda_onboarding_profile.sql:1) | Incomplete Rwanda onboarding profile support | Allow genuine incomplete onboarding without granting payment/group capability prematurely. |
| 133 / `20260928174000` — [20260928174000_attested_receipt_v2_contract.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260928174000_attested_receipt_v2_contract.sql:1) | Attested receipt protocol 2 | Owner/envelope/body-bound durable ACK; missing/wrong version, lease, hash or capability fails closed; no legacy fallback. |
| 134 / `20260929110000` — [20260929110000_admin_notification_page_before_delivery_counts.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260929110000_admin_notification_page_before_delivery_counts.sql:1) | Admin notification pagination | Permission-bound filtering/paging precedes delivery counts; no cross-user or unbounded count reads. |
| 135 / `20260929120000` — [20260929120000_provider_finality_payment_lock_order.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260929120000_provider_finality_payment_lock_order.sql:1) | Provider-finality lock ordering | Concurrent SMS observation, provider finality and reversal cannot deadlock or create a duplicate/mixed financial transition. |
| 136 / `20260929130000` — [20260929130000_provider_finality_content_binding.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260929130000_provider_finality_content_binding.sql:1) | Provider-finality content binding | Same request ID with changed event/payment/amount/evidence payload fails; exact replay has no new financial writes. |
| 137 / `20260929140000` — [20260929140000_notification_delivery_fencing.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260929140000_notification_delivery_fencing.sql:1) | Notification delivery fencing | Stale claim/completion tokens and expired leases cannot mutate a newer delivery attempt. |
| 138 / `20260929150000` — [20260929150000_notification_retry_eligibility.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260929150000_notification_retry_eligibility.sql:1) | Notification retry eligibility | Permanent failures, revoked/changed tokens, disabled preferences and already accepted deliveries cannot be retried incorrectly. |
| 139 / `20260929160000` — [20260929160000_notification_retry_schedule.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260929160000_notification_retry_schedule.sql:1) | Notification protocol-2 schedule/backoff | Compatible claim/completion signatures, Retry-After/backoff and one disabled-by-default Vault-backed cron; validate secrets without logging them before deliberate enablement. |
| 140 / `20260929170000` — [20260929170000_governed_reconciliation_workflow.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260929170000_governed_reconciliation_workflow.sql:1) | Governed reconciliation | Distinct authorized maker/checker, evidence-bound approved review, finalizer-only commit, replay/content conflicts and rollback under failure. |
| 141 / `20260929180000` — [20260929180000_notification_registration_sessions.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260929180000_notification_registration_sessions.sql:1) | Actual Auth-session/device and Admin revocation fences | Cross-account/session token rebinding, stale unregister/dispatch, revoked approvals/roles and AAL2 finalization rejected under deterministic concurrency barriers. |
| 142 / `20260930100000` — [20260930100000_roster_import_provenance.sql:1](/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/supabase/migrations/20260930100000_roster_import_provenance.sql:1) | Roster source/extraction/review provenance | Corrected source hash, consent before extraction, immutable lineage, parent-linked human review, exact commit bindings and disabled legacy raw-row writers with matching Edge/Admin callers. |

## Ordered staging and release gates

1. **Freeze and preserve.** Retain a verified backup/restore procedure and the observed 124-state schema/ACL/function/trigger/job catalogue. Record current protected financial row counts/digests and legacy bank/scope data. Freeze corrected 142 and compatible Edge/Admin/mobile source/artifact hashes. The retained readback is evidence, not a script to apply.
2. **Complete body/privilege readback in an authorized run.** Obtain exact bodies and owners for the six anonymous routines and prioritized privileged RPCs; schema and column grants; view definitions/options; effective role inheritance; actual exposed API schemas; cron commands/owners; feature flags; protocol RPC values; deployed Edge bundles and Auth flow configuration. This report made none of those external calls.
3. **Rehearse the whole 124→142 transition in isolated staging.** Exercise legacy fixtures, existing invitations/device registrations/claims, same-user new sessions, existing financial evidence and bank history. Investigate every failure and retain failed-source evidence. Do not claim this passed from local empty-schema or handler-only tests.
4. **Coordinate producers and consumers.** During rollout, prevent old parsers/dispatchers/raw-row Admin clients from using removed signatures. Apply reviewed SQL and version-compatible handlers/client artifacts with controlled feature availability. Verify receipt contract 2 and notification claim protocol 2 explicitly. Incompatible clients must fail closed with usable recovery guidance.
5. **Retire bank execution separately.** Disable the active bank cron and deployed bank ingestion handlers after preserving required evidence; verify identified legacy RPC/table privileges are retired. Migration 127's revocations do not by themselves remove the owner-run scheduler. Check for other external schedules before declaring retirement complete.
6. **Keep the new notification scheduler disabled until tested.** Migration 139 deliberately creates a disabled `collect-dispatch-notifications` job. Configure the three named Vault values (`collect_notification_project_url`, `collect_notification_api_key`, `collect_notification_internal_secret`), verify exact handler auth/configuration, and prove delivery/fencing/backoff with test accounts and authorized sandbox providers. Then enable one schedule and record heartbeat, due/retry counts, failures and operator recovery.
7. **Deploy governed finality and provenance.** Verify `reconciliation-finalize` exists with JWT verification and caller-specific SQL authorization, with service finalization private. Verify roster source/review/commit endpoints and the matched UI contract. Operator approval of reviewed evidence and explicit human roster review are required; model output is never direct write authority.
8. **Capture post-deployment evidence.** Re-read migration versions plus exact content hashes/body signatures, ACLs/policies/triggers, protocol values, scheduler state and Edge bundle/config hashes. Execute approved negative/cross-account/concurrency/smoke scenarios and compare protected financial state. Only then assess the hosted portion of readiness; store/device/provider/legal gates remain separate.

## Minimum negative-test matrix

These are required tests to execute in authorized staging; none was executed in this review.

| Boundary | Negative/abuse case | Required invariant |
| --- | --- | --- |
| Anonymous public RPCs | Private/archived/pending/unsponsored collections; draft/future policy; disabled reasons; forged target user; null/default UUID | Only intended public facts appear; no private membership, personal receiver, identifiers or writable authority. |
| GraphQL and REST columns | Explicit private profile/payment/hash fields; nested relations, aliases, aggregates and views as anon/member A | Sensitive columns are absent/denied and B's private rows remain inaccessible; no reliance on the safe view's projection alone. |
| RLS/RPC administration | Ordinary user calls Admin read/write, changes permission names/actor IDs or writes private tables directly | Live approved role/permission/session is required; no direct private-table mutation. |
| Member roster | Signed-in outsider and platform staff without membership call every public roster wrapper | Private roster denied, including public-approved groups; active verified claimed member remains allowed. |
| SMS/financial finality | Valid-looking attested SMS, manipulated amount/receiver/reference, duplicate or changed confirmation payload | No money from SMS alone; independent evidence required; canonical exact replay makes no duplicate journal/allocation. |
| Receipt protocol | Missing/future/legacy version, wrong owner/envelope/body hash, expired/reused capability or processing lease | No false durable ACK or accepted parse; persisted evidence and retry semantics remain owner-bound. |
| OTP/internal Edge | Unsigned/static-secret/wrong signature, replay, concurrent quota use, provider dry-run/error | No unauthorized send, quota race or fabricated delivery acknowledgement. |
| Notification protocol/session | Old signature; stale token/claim; A→B registration, delayed A cleanup; revoke/delete session around dispatch; provider accepted but ACK lost | New owner/session unaffected; stale completion denied; no blind duplicate provider send or private wrong-recipient navigation. |
| Reconciliation | Self-approval, AAL1, expired approval, revoked role/session, changed evidence/hash, concurrent finalizers | No protected write; only actual authorized distinct checker and approved content can finalize once. |
| Roster provenance | Client-supplied digest/actor/model, missing original bytes/consent, changed replay, unreviewed/superseded/expired revision, wrong session | Reject safely; preserve immutable provenance; no membership or financial writes from extraction or raw legacy rows. |
| Retired bank/scope | All three old handlers, direct bank RPCs/tables, scheduler wake-up, USD/EUR/diaspora/Stripe/SEPA write paths | No new out-of-scope financial execution; historic evidence retained and readable only through approved archival access. |

## Advisor disposition inventory

**238 supplied findings are retained below without deduplication:** 46 RLS/no-policy, 19 anonymous GraphQL, 32 authenticated GraphQL, six anonymous SECURITY DEFINER, 134 authenticated SECURITY DEFINER and one password-protection warning. There are **0 confirmed exploit findings**, **192 needs-review findings**, and **46 not-actionable no-policy findings** in this static pass. The confirmed deployment gaps H01–H07 above are distinct from claiming a demonstrated vulnerability exploit.

`A001` etc. are this report's identifiers, not invented scanner IDs. The source preserves rule names and the exact original JSON index (`result.lints[i].findings[j]`), object/overload and role; original descriptions, metadata, severity and observation time remain in `security-advisors.json`. Confidence/rank applies to the limited static verdict, not overall safety. NR ranks 1–192 form one contiguous review queue, ordered by caller reachability, sensitivity and privileged mutation potential. No confirmed-exploit queue is populated.

Rationale keys:

- **D:** Default-deny private storage: recorded RLS plus no PUBLIC/anon/authenticated table ACL; absence of a permissive policy is not a defect to fix. Privileged RPC correctness is separate.
- **G:** GraphQL schema exposure needs exact column ACL/view/policy/relationship proof; intended public or owner/Admin-bound source controls are counterevidence, not a completed hosted test.
- **P:** Anonymous RPC is deliberately public or actor-bound in local source; exact hosted definition/control parity and schema privileges remain unverified. See the six-routine table.
- **R:** Authenticated SECURITY DEFINER is an intended controlled RPC pattern; this entry's complete transitive body/privilege/session boundary was not individually established in this scoped pass. Prioritize identified financial/bank/roster/auth paths and negative tests.
- **W:** Confirm actual supported password/recovery routes and provider configuration before deciding applicability or enabling the available control.

| ID / source JSON index | Rule / affected object (arguments preserve overloads) | Verdict / confidence | Review rank | Rationale |
| --- | --- | --- | --- | --- |
| A001 / `result.lints[0].findings[0]` | `rls_enabled_no_policy` — `collect_admin_access.whatsapp_approvals` | `not_actionable` / high | — | D |
| A002 / `result.lints[0].findings[1]` | `rls_enabled_no_policy` — `collect_hybrid.collection_balances` | `not_actionable` / high | — | D |
| A003 / `result.lints[0].findings[2]` | `rls_enabled_no_policy` — `collect_hybrid.group_creation_requests` | `not_actionable` / high | — | D |
| A004 / `result.lints[0].findings[3]` | `rls_enabled_no_policy` — `collect_hybrid.member_account_claims` | `not_actionable` / high | — | D |
| A005 / `result.lints[0].findings[4]` | `rls_enabled_no_policy` — `collect_hybrid.member_balances` | `not_actionable` / high | — | D |
| A006 / `result.lints[0].findings[5]` | `rls_enabled_no_policy` — `collect_hybrid.member_momo_identities` | `not_actionable` / high | — | D |
| A007 / `result.lints[0].findings[6]` | `rls_enabled_no_policy` — `collect_hybrid.member_receiving_assignments` | `not_actionable` / high | — | D |
| A008 / `result.lints[0].findings[7]` | `rls_enabled_no_policy` — `collect_hybrid.member_records` | `not_actionable` / high | — | D |
| A009 / `result.lints[0].findings[8]` | `rls_enabled_no_policy` — `collect_hybrid.momo_balance_snapshots` | `not_actionable` / high | — | D |
| A010 / `result.lints[0].findings[9]` | `rls_enabled_no_policy` — `collect_hybrid.momo_journal_entries` | `not_actionable` / high | — | D |
| A011 / `result.lints[0].findings[10]` | `rls_enabled_no_policy` — `collect_hybrid.momo_journal_lines` | `not_actionable` / high | — | D |
| A012 / `result.lints[0].findings[11]` | `rls_enabled_no_policy` — `collect_hybrid.momo_reconciliation_exceptions` | `not_actionable` / high | — | D |
| A013 / `result.lints[0].findings[12]` | `rls_enabled_no_policy` — `collect_hybrid.momo_reversal_requests` | `not_actionable` / high | — | D |
| A014 / `result.lints[0].findings[13]` | `rls_enabled_no_policy` — `collect_hybrid.receiving_assignment_requests` | `not_actionable` / high | — | D |
| A015 / `result.lints[0].findings[14]` | `rls_enabled_no_policy` — `collect_hybrid.roster_batches` | `not_actionable` / high | — | D |
| A016 / `result.lints[0].findings[15]` | `rls_enabled_no_policy` — `collect_hybrid.sms_notification_attempts` | `not_actionable` / high | — | D |
| A017 / `result.lints[0].findings[16]` | `rls_enabled_no_policy` — `collect_hybrid.sms_notification_claim_requests` | `not_actionable` / high | — | D |
| A018 / `result.lints[0].findings[17]` | `rls_enabled_no_policy` — `collect_hybrid.sms_notification_confirmations` | `not_actionable` / high | — | D |
| A019 / `result.lints[0].findings[18]` | `rls_enabled_no_policy` — `collect_hybrid.sms_notification_outbox` | `not_actionable` / high | — | D |
| A020 / `result.lints[0].findings[19]` | `rls_enabled_no_policy` — `collect_hybrid.sms_operator_heartbeats` | `not_actionable` / high | — | D |
| A021 / `result.lints[0].findings[20]` | `rls_enabled_no_policy` — `collect_hybrid.sms_receipt_member_consents` | `not_actionable` / high | — | D |
| A022 / `result.lints[0].findings[21]` | `rls_enabled_no_policy` — `collect_hybrid.sms_receipt_policies` | `not_actionable` / high | — | D |
| A023 / `result.lints[0].findings[22]` | `rls_enabled_no_policy` — `public.admin_queue_sla_policies` | `not_actionable` / high | — | D |
| A024 / `result.lints[0].findings[23]` | `rls_enabled_no_policy` — `public.bank_allocation_change_requests` | `not_actionable` / high | — | D |
| A025 / `result.lints[0].findings[24]` | `rls_enabled_no_policy` — `public.bank_destination_change_requests` | `not_actionable` / high | — | D |
| A026 / `result.lints[0].findings[25]` | `rls_enabled_no_policy` — `public.bank_evidence_events` | `not_actionable` / high | — | D |
| A027 / `result.lints[0].findings[26]` | `rls_enabled_no_policy` — `public.bank_statement_imports` | `not_actionable` / high | — | D |
| A028 / `result.lints[0].findings[27]` | `rls_enabled_no_policy` — `public.bank_statement_lines` | `not_actionable` / high | — | D |
| A029 / `result.lints[0].findings[28]` | `rls_enabled_no_policy` — `public.bank_transaction_allocations` | `not_actionable` / high | — | D |
| A030 / `result.lints[0].findings[29]` | `rls_enabled_no_policy` — `public.bank_transactions` | `not_actionable` / high | — | D |
| A031 / `result.lints[0].findings[30]` | `rls_enabled_no_policy` — `public.bank_transfer_destinations` | `not_actionable` / high | — | D |
| A032 / `result.lints[0].findings[31]` | `rls_enabled_no_policy` — `public.collection_share_secrets` | `not_actionable` / high | — | D |
| A033 / `result.lints[0].findings[32]` | `rls_enabled_no_policy` — `public.daily_bank_closes` | `not_actionable` / high | — | D |
| A034 / `result.lints[0].findings[33]` | `rls_enabled_no_policy` — `public.journal_entries` | `not_actionable` / high | — | D |
| A035 / `result.lints[0].findings[34]` | `rls_enabled_no_policy` — `public.journal_lines` | `not_actionable` / high | — | D |
| A036 / `result.lints[0].findings[35]` | `rls_enabled_no_policy` — `public.native_action_capabilities` | `not_actionable` / high | — | D |
| A037 / `result.lints[0].findings[36]` | `rls_enabled_no_policy` — `public.notification_deliveries` | `not_actionable` / high | — | D |
| A038 / `result.lints[0].findings[37]` | `rls_enabled_no_policy` — `public.notification_delivery_attempts` | `not_actionable` / high | — | D |
| A039 / `result.lints[0].findings[38]` | `rls_enabled_no_policy` — `public.notification_device_tokens` | `not_actionable` / high | — | D |
| A040 / `result.lints[0].findings[39]` | `rls_enabled_no_policy` — `public.payment_evidence_links` | `not_actionable` / high | — | D |
| A041 / `result.lints[0].findings[40]` | `rls_enabled_no_policy` — `public.payment_provider_confirmations` | `not_actionable` / high | — | D |
| A042 / `result.lints[0].findings[41]` | `rls_enabled_no_policy` — `public.provider_finality_requests` | `not_actionable` / high | — | D |
| A043 / `result.lints[0].findings[42]` | `rls_enabled_no_policy` — `public.raw_payment_evidence` | `not_actionable` / high | — | D |
| A044 / `result.lints[0].findings[43]` | `rls_enabled_no_policy` — `public.reconciliation_exceptions` | `not_actionable` / high | — | D |
| A045 / `result.lints[0].findings[44]` | `rls_enabled_no_policy` — `public.reconciliation_matches` | `not_actionable` / high | — | D |
| A046 / `result.lints[0].findings[45]` | `rls_enabled_no_policy` — `public.reconciliation_runs` | `not_actionable` / high | — | D |
| A047 / `result.lints[1].findings[0]` | `pg_graphql_anon_table_exposed` — `public.account_request_reason_options` | `needs_review` / medium | 79 | G |
| A048 / `result.lints[1].findings[1]` | `pg_graphql_anon_table_exposed` — `public.brand_entities` | `needs_review` / medium | 80 | G |
| A049 / `result.lints[1].findings[2]` | `pg_graphql_anon_table_exposed` — `public.collection_category_subtypes` | `needs_review` / medium | 81 | G |
| A050 / `result.lints[1].findings[3]` | `pg_graphql_anon_table_exposed` — `public.collection_purpose_templates` | `needs_review` / medium | 82 | G |
| A051 / `result.lints[1].findings[4]` | `pg_graphql_anon_table_exposed` — `public.collection_type_catalog` | `needs_review` / medium | 83 | G |
| A052 / `result.lints[1].findings[5]` | `pg_graphql_anon_table_exposed` — `public.collection_type_country_rules` | `needs_review` / medium | 84 | G |
| A053 / `result.lints[1].findings[6]` | `pg_graphql_anon_table_exposed` — `public.collections` | `needs_review` / medium | 1 | G |
| A054 / `result.lints[1].findings[7]` | `pg_graphql_anon_table_exposed` — `public.notification_channels` | `needs_review` / medium | 85 | G |
| A055 / `result.lints[1].findings[8]` | `pg_graphql_anon_table_exposed` — `public.notification_event_types` | `needs_review` / medium | 86 | G |
| A056 / `result.lints[1].findings[9]` | `pg_graphql_anon_table_exposed` — `public.notification_template_versions` | `needs_review` / medium | 87 | G |
| A057 / `result.lints[1].findings[10]` | `pg_graphql_anon_table_exposed` — `public.notification_templates` | `needs_review` / medium | 88 | G |
| A058 / `result.lints[1].findings[11]` | `pg_graphql_anon_table_exposed` — `public.payment_entrypoints` | `needs_review` / medium | 89 | G |
| A059 / `result.lints[1].findings[12]` | `pg_graphql_anon_table_exposed` — `public.policy_document_sections` | `needs_review` / medium | 90 | G |
| A060 / `result.lints[1].findings[13]` | `pg_graphql_anon_table_exposed` — `public.policy_documents` | `needs_review` / medium | 91 | G |
| A061 / `result.lints[1].findings[14]` | `pg_graphql_anon_table_exposed` — `public.profile_country_rules` | `needs_review` / medium | 92 | G |
| A062 / `result.lints[1].findings[15]` | `pg_graphql_anon_table_exposed` — `public.profiles` | `needs_review` / medium | 2 | G |
| A063 / `result.lints[1].findings[16]` | `pg_graphql_anon_table_exposed` — `public.public_collections_view` | `needs_review` / medium | 93 | G |
| A064 / `result.lints[1].findings[17]` | `pg_graphql_anon_table_exposed` — `public.public_profiles_view` | `needs_review` / medium | 94 | G |
| A065 / `result.lints[1].findings[18]` | `pg_graphql_anon_table_exposed` — `public.support_channels` | `needs_review` / medium | 95 | G |
| A066 / `result.lints[2].findings[0]` | `pg_graphql_authenticated_table_exposed` — `public.account_request_reason_options` | `needs_review` / medium | 96 | G |
| A067 / `result.lints[2].findings[1]` | `pg_graphql_authenticated_table_exposed` — `public.admin_navigation_items` | `needs_review` / medium | 97 | G |
| A068 / `result.lints[2].findings[2]` | `pg_graphql_authenticated_table_exposed` — `public.admin_queue_filter_options` | `needs_review` / medium | 98 | G |
| A069 / `result.lints[2].findings[3]` | `pg_graphql_authenticated_table_exposed` — `public.admin_queue_signals` | `needs_review` / medium | 99 | G |
| A070 / `result.lints[2].findings[4]` | `pg_graphql_authenticated_table_exposed` — `public.admin_queue_specs` | `needs_review` / medium | 100 | G |
| A071 / `result.lints[2].findings[5]` | `pg_graphql_authenticated_table_exposed` — `public.app_realtime_events` | `needs_review` / medium | 101 | G |
| A072 / `result.lints[2].findings[6]` | `pg_graphql_authenticated_table_exposed` — `public.brand_entities` | `needs_review` / medium | 102 | G |
| A073 / `result.lints[2].findings[7]` | `pg_graphql_authenticated_table_exposed` — `public.collection_category_subtypes` | `needs_review` / medium | 103 | G |
| A074 / `result.lints[2].findings[8]` | `pg_graphql_authenticated_table_exposed` — `public.collection_purpose_templates` | `needs_review` / medium | 104 | G |
| A075 / `result.lints[2].findings[9]` | `pg_graphql_authenticated_table_exposed` — `public.collection_type_catalog` | `needs_review` / medium | 105 | G |
| A076 / `result.lints[2].findings[10]` | `pg_graphql_authenticated_table_exposed` — `public.collection_type_country_rules` | `needs_review` / medium | 106 | G |
| A077 / `result.lints[2].findings[11]` | `pg_graphql_authenticated_table_exposed` — `public.collections` | `needs_review` / medium | 3 | G |
| A078 / `result.lints[2].findings[12]` | `pg_graphql_authenticated_table_exposed` — `public.member_collection_summary_view` | `needs_review` / medium | 4 | G |
| A079 / `result.lints[2].findings[13]` | `pg_graphql_authenticated_table_exposed` — `public.member_collections_view` | `needs_review` / medium | 5 | G |
| A080 / `result.lints[2].findings[14]` | `pg_graphql_authenticated_table_exposed` — `public.member_contributions_view` | `needs_review` / medium | 6 | G |
| A081 / `result.lints[2].findings[15]` | `pg_graphql_authenticated_table_exposed` — `public.mobile_account_deletion_requests` | `needs_review` / medium | 107 | G |
| A082 / `result.lints[2].findings[16]` | `pg_graphql_authenticated_table_exposed` — `public.mobile_support_requests` | `needs_review` / medium | 108 | G |
| A083 / `result.lints[2].findings[17]` | `pg_graphql_authenticated_table_exposed` — `public.notification_channels` | `needs_review` / medium | 109 | G |
| A084 / `result.lints[2].findings[18]` | `pg_graphql_authenticated_table_exposed` — `public.notification_event_types` | `needs_review` / medium | 110 | G |
| A085 / `result.lints[2].findings[19]` | `pg_graphql_authenticated_table_exposed` — `public.notification_events` | `needs_review` / medium | 111 | G |
| A086 / `result.lints[2].findings[20]` | `pg_graphql_authenticated_table_exposed` — `public.notification_preferences` | `needs_review` / medium | 112 | G |
| A087 / `result.lints[2].findings[21]` | `pg_graphql_authenticated_table_exposed` — `public.notification_template_versions` | `needs_review` / medium | 113 | G |
| A088 / `result.lints[2].findings[22]` | `pg_graphql_authenticated_table_exposed` — `public.notification_templates` | `needs_review` / medium | 114 | G |
| A089 / `result.lints[2].findings[23]` | `pg_graphql_authenticated_table_exposed` — `public.payment_entrypoints` | `needs_review` / medium | 115 | G |
| A090 / `result.lints[2].findings[24]` | `pg_graphql_authenticated_table_exposed` — `public.policy_acceptance_events` | `needs_review` / medium | 116 | G |
| A091 / `result.lints[2].findings[25]` | `pg_graphql_authenticated_table_exposed` — `public.policy_document_sections` | `needs_review` / medium | 117 | G |
| A092 / `result.lints[2].findings[26]` | `pg_graphql_authenticated_table_exposed` — `public.policy_documents` | `needs_review` / medium | 118 | G |
| A093 / `result.lints[2].findings[27]` | `pg_graphql_authenticated_table_exposed` — `public.profile_country_rules` | `needs_review` / medium | 119 | G |
| A094 / `result.lints[2].findings[28]` | `pg_graphql_authenticated_table_exposed` — `public.profiles` | `needs_review` / medium | 7 | G |
| A095 / `result.lints[2].findings[29]` | `pg_graphql_authenticated_table_exposed` — `public.public_collections_view` | `needs_review` / medium | 120 | G |
| A096 / `result.lints[2].findings[30]` | `pg_graphql_authenticated_table_exposed` — `public.public_profiles_view` | `needs_review` / medium | 121 | G |
| A097 / `result.lints[2].findings[31]` | `pg_graphql_authenticated_table_exposed` — `public.support_channels` | `needs_review` / medium | 122 | G |
| A098 / `result.lints[3].findings[0]` | `anon_security_definer_function_executable` — `public.collection_is_public_approved(target_collection_id uuid)` | `needs_review` / medium | 8 | P |
| A099 / `result.lints[3].findings[1]` | `anon_security_definer_function_executable` — `public.get_active_policy_document(p_kind text, p_locale text)` | `needs_review` / medium | 9 | P |
| A100 / `result.lints[3].findings[2]` | `anon_security_definer_function_executable` — `public.list_account_request_reasons(p_request_type text, p_locale text)` | `needs_review` / medium | 10 | P |
| A101 / `result.lints[3].findings[3]` | `anon_security_definer_function_executable` — `public.public_collection_payment_route(p_collection_id uuid)` | `needs_review` / medium | 11 | P |
| A102 / `result.lints[3].findings[4]` | `anon_security_definer_function_executable` — `public.user_can_read_collection(collection uuid, user_uuid uuid)` | `needs_review` / medium | 12 | P |
| A103 / `result.lints[3].findings[5]` | `anon_security_definer_function_executable` — `public.user_is_collection_admin(collection uuid, user_uuid uuid)` | `needs_review` / medium | 13 | P |
| A104 / `result.lints[4].findings[0]` | `authenticated_security_definer_function_executable` — `public.admin_add_assisted_roster(p_collection_id uuid, p_rows jsonb, p_request_id uuid, p_reason text)` | `needs_review` / low | 14 | R |
| A105 / `result.lints[4].findings[1]` | `authenticated_security_definer_function_executable` — `public.admin_assign_hybrid_receiving_route(p_collection_id uuid, p_member_record_id uuid, p_collection_receiver_id uuid, p_reason text, p_request_id uuid)` | `needs_review` / low | 123 | R |
| A106 / `result.lints[4].findings[2]` | `authenticated_security_definer_function_executable` — `public.admin_create_assisted_group(p_title text, p_reason text, p_request_id uuid)` | `needs_review` / low | 124 | R |
| A107 / `result.lints[4].findings[3]` | `authenticated_security_definer_function_executable` — `public.admin_create_assisted_group_with_roster(p_title text, p_rows jsonb, p_reason text, p_group_request_id uuid, p_roster_request_id uuid)` | `needs_review` / low | 15 | R |
| A108 / `result.lints[4].findings[4]` | `authenticated_security_definer_function_executable` — `public.admin_create_collect_payee(p_collection_id uuid, p_label text, p_momo_code text, p_network text, p_reason text)` | `needs_review` / low | 125 | R |
| A109 / `result.lints[4].findings[5]` | `authenticated_security_definer_function_executable` — `public.admin_create_platform_public_group(p_title text, p_description text, p_collection_type text, p_category_subtype text, p_purpose_label text, p_receiver_label text, p_momo_code text, p_network text, p_reason text)` | `needs_review` / low | 126 | R |
| A110 / `result.lints[4].findings[6]` | `authenticated_security_definer_function_executable` — `public.admin_get_bank_allocation_request(p_id uuid)` | `needs_review` / low | 16 | R |
| A111 / `result.lints[4].findings[7]` | `authenticated_security_definer_function_executable` — `public.admin_get_bank_destination(p_id uuid)` | `needs_review` / low | 17 | R |
| A112 / `result.lints[4].findings[8]` | `authenticated_security_definer_function_executable` — `public.admin_get_bank_destination_change_request(p_id uuid)` | `needs_review` / low | 18 | R |
| A113 / `result.lints[4].findings[9]` | `authenticated_security_definer_function_executable` — `public.admin_get_bank_evidence(p_id uuid)` | `needs_review` / low | 19 | R |
| A114 / `result.lints[4].findings[10]` | `authenticated_security_definer_function_executable` — `public.admin_get_bank_transaction(p_id uuid)` | `needs_review` / low | 20 | R |
| A115 / `result.lints[4].findings[11]` | `authenticated_security_definer_function_executable` — `public.admin_get_bank_transfer_intent(p_id uuid)` | `needs_review` / low | 21 | R |
| A116 / `result.lints[4].findings[12]` | `authenticated_security_definer_function_executable` — `public.admin_get_collect_transaction(p_id text)` | `needs_review` / low | 127 | R |
| A117 / `result.lints[4].findings[13]` | `authenticated_security_definer_function_executable` — `public.admin_get_collection(p_id uuid)` | `needs_review` / low | 128 | R |
| A118 / `result.lints[4].findings[14]` | `authenticated_security_definer_function_executable` — `public.admin_get_hybrid_sms_receipt(p_id uuid)` | `needs_review` / low | 22 | R |
| A119 / `result.lints[4].findings[15]` | `authenticated_security_definer_function_executable` — `public.admin_get_journal_entry(p_id uuid)` | `needs_review` / low | 129 | R |
| A120 / `result.lints[4].findings[16]` | `authenticated_security_definer_function_executable` — `public.admin_get_member_record(p_id uuid)` | `needs_review` / low | 130 | R |
| A121 / `result.lints[4].findings[17]` | `authenticated_security_definer_function_executable` — `public.admin_get_notification(p_id uuid)` | `needs_review` / low | 131 | R |
| A122 / `result.lints[4].findings[18]` | `authenticated_security_definer_function_executable` — `public.admin_get_payment(p_id uuid)` | `needs_review` / low | 23 | R |
| A123 / `result.lints[4].findings[19]` | `authenticated_security_definer_function_executable` — `public.admin_get_payment_event(p_id uuid)` | `needs_review` / low | 24 | R |
| A124 / `result.lints[4].findings[20]` | `authenticated_security_definer_function_executable` — `public.admin_get_payment_intent(p_id uuid)` | `needs_review` / low | 25 | R |
| A125 / `result.lints[4].findings[21]` | `authenticated_security_definer_function_executable` — `public.admin_get_queue_sla(p_queue_key text)` | `needs_review` / low | 132 | R |
| A126 / `result.lints[4].findings[22]` | `authenticated_security_definer_function_executable` — `public.admin_get_receiver(p_id uuid)` | `needs_review` / low | 133 | R |
| A127 / `result.lints[4].findings[23]` | `authenticated_security_definer_function_executable` — `public.admin_get_reconciliation_exception(p_id uuid)` | `needs_review` / low | 26 | R |
| A128 / `result.lints[4].findings[24]` | `authenticated_security_definer_function_executable` — `public.admin_get_reconciliation_run(p_id uuid)` | `needs_review` / low | 27 | R |
| A129 / `result.lints[4].findings[25]` | `authenticated_security_definer_function_executable` — `public.admin_get_sms_metadata(p_id uuid)` | `needs_review` / low | 28 | R |
| A130 / `result.lints[4].findings[26]` | `authenticated_security_definer_function_executable` — `public.admin_get_user(p_id uuid)` | `needs_review` / low | 134 | R |
| A131 / `result.lints[4].findings[27]` | `authenticated_security_definer_function_executable` — `public.admin_import_bank_statement(p_file_name text, p_file_hash text, p_period_start date, p_period_end date, p_lines jsonb, p_reason text)` | `needs_review` / low | 29 | R |
| A132 / `result.lints[4].findings[28]` | `authenticated_security_definer_function_executable` — `public.admin_list_allocations(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 30 | R |
| A133 / `result.lints[4].findings[29]` | `authenticated_security_definer_function_executable` — `public.admin_list_audit_logs(p_search text, p_status text)` | `needs_review` / low | 135 | R |
| A134 / `result.lints[4].findings[30]` | `authenticated_security_definer_function_executable` — `public.admin_list_bank_allocation_requests(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 31 | R |
| A135 / `result.lints[4].findings[31]` | `authenticated_security_definer_function_executable` — `public.admin_list_bank_destination_change_requests(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 32 | R |
| A136 / `result.lints[4].findings[32]` | `authenticated_security_definer_function_executable` — `public.admin_list_bank_destinations(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 33 | R |
| A137 / `result.lints[4].findings[33]` | `authenticated_security_definer_function_executable` — `public.admin_list_bank_evidence(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 34 | R |
| A138 / `result.lints[4].findings[34]` | `authenticated_security_definer_function_executable` — `public.admin_list_bank_transactions(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 35 | R |
| A139 / `result.lints[4].findings[35]` | `authenticated_security_definer_function_executable` — `public.admin_list_bank_transfer_intents(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 36 | R |
| A140 / `result.lints[4].findings[36]` | `authenticated_security_definer_function_executable` — `public.admin_list_collect_ledgers(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 136 | R |
| A141 / `result.lints[4].findings[37]` | `authenticated_security_definer_function_executable` — `public.admin_list_collect_payees(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 137 | R |
| A142 / `result.lints[4].findings[38]` | `authenticated_security_definer_function_executable` — `public.admin_list_collect_reconciliations(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 37 | R |
| A143 / `result.lints[4].findings[39]` | `authenticated_security_definer_function_executable` — `public.admin_list_collect_transactions(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 138 | R |
| A144 / `result.lints[4].findings[40]` | `authenticated_security_definer_function_executable` — `public.admin_list_collections(p_search text, p_status text)` | `needs_review` / low | 139 | R |
| A145 / `result.lints[4].findings[41]` | `authenticated_security_definer_function_executable` — `public.admin_list_collections(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 140 | R |
| A146 / `result.lints[4].findings[42]` | `authenticated_security_definer_function_executable` — `public.admin_list_country_scoped(p_rpc_name text, p_country text, p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 141 | R |
| A147 / `result.lints[4].findings[43]` | `authenticated_security_definer_function_executable` — `public.admin_list_feature_flags(p_search text, p_status text)` | `needs_review` / low | 142 | R |
| A148 / `result.lints[4].findings[44]` | `authenticated_security_definer_function_executable` — `public.admin_list_hybrid_sms_receipts(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 38 | R |
| A149 / `result.lints[4].findings[45]` | `authenticated_security_definer_function_executable` — `public.admin_list_journal_entries(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 143 | R |
| A150 / `result.lints[4].findings[46]` | `authenticated_security_definer_function_executable` — `public.admin_list_ledger(p_search text, p_status text)` | `needs_review` / low | 144 | R |
| A151 / `result.lints[4].findings[47]` | `authenticated_security_definer_function_executable` — `public.admin_list_members(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 145 | R |
| A152 / `result.lints[4].findings[48]` | `authenticated_security_definer_function_executable` — `public.admin_list_non_member_users(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 146 | R |
| A153 / `result.lints[4].findings[49]` | `authenticated_security_definer_function_executable` — `public.admin_list_notifications(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 147 | R |
| A154 / `result.lints[4].findings[50]` | `authenticated_security_definer_function_executable` — `public.admin_list_payment_events(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 39 | R |
| A155 / `result.lints[4].findings[51]` | `authenticated_security_definer_function_executable` — `public.admin_list_payment_intents(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 40 | R |
| A156 / `result.lints[4].findings[52]` | `authenticated_security_definer_function_executable` — `public.admin_list_payments(p_search text, p_status text)` | `needs_review` / low | 41 | R |
| A157 / `result.lints[4].findings[53]` | `authenticated_security_definer_function_executable` — `public.admin_list_payments(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 42 | R |
| A158 / `result.lints[4].findings[54]` | `authenticated_security_definer_function_executable` — `public.admin_list_platform_payee_candidates(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 148 | R |
| A159 / `result.lints[4].findings[55]` | `authenticated_security_definer_function_executable` — `public.admin_list_receivers(p_search text, p_status text)` | `needs_review` / low | 149 | R |
| A160 / `result.lints[4].findings[56]` | `authenticated_security_definer_function_executable` — `public.admin_list_reconciliation_exceptions(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 43 | R |
| A161 / `result.lints[4].findings[57]` | `authenticated_security_definer_function_executable` — `public.admin_list_reconciliation_runs(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 44 | R |
| A162 / `result.lints[4].findings[58]` | `authenticated_security_definer_function_executable` — `public.admin_list_settings(p_search text, p_status text)` | `needs_review` / low | 150 | R |
| A163 / `result.lints[4].findings[59]` | `authenticated_security_definer_function_executable` — `public.admin_list_sms_metadata(p_search text, p_status text)` | `needs_review` / low | 45 | R |
| A164 / `result.lints[4].findings[60]` | `authenticated_security_definer_function_executable` — `public.admin_list_unallocated(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 46 | R |
| A165 / `result.lints[4].findings[61]` | `authenticated_security_definer_function_executable` — `public.admin_list_users(p_search text, p_status text)` | `needs_review` / low | 151 | R |
| A166 / `result.lints[4].findings[62]` | `authenticated_security_definer_function_executable` — `public.admin_list_users(p_search text, p_status text, p_limit integer, p_offset integer, p_sort text)` | `needs_review` / low | 152 | R |
| A167 / `result.lints[4].findings[63]` | `authenticated_security_definer_function_executable` — `public.admin_manual_allocate_payment(p_event_id uuid, p_collection_id uuid, p_payment_intent_id uuid, p_reason text)` | `needs_review` / low | 47 | R |
| A168 / `result.lints[4].findings[64]` | `authenticated_security_definer_function_executable` — `public.admin_overview()` | `needs_review` / low | 153 | R |
| A169 / `result.lints[4].findings[65]` | `authenticated_security_definer_function_executable` — `public.admin_propose_bank_allocation(p_bank_transaction_id uuid, p_bank_transfer_intent_id uuid, p_reason text)` | `needs_review` / low | 48 | R |
| A170 / `result.lints[4].findings[66]` | `authenticated_security_definer_function_executable` — `public.admin_propose_bank_destination(p_beneficiary_name text, p_iban text, p_bic text, p_bank_name text, p_supports_instant boolean, p_reason text)` | `needs_review` / low | 49 | R |
| A171 / `result.lints[4].findings[67]` | `authenticated_security_definer_function_executable` — `public.admin_record_operator_note(p_entity_type text, p_entity_id uuid, p_body text)` | `needs_review` / low | 154 | R |
| A172 / `result.lints[4].findings[68]` | `authenticated_security_definer_function_executable` — `public.admin_reopen_daily_bank_close(p_close_id uuid, p_reason text)` | `needs_review` / low | 50 | R |
| A173 / `result.lints[4].findings[69]` | `authenticated_security_definer_function_executable` — `public.admin_reparse_payment_event(p_event_id uuid, p_reason text)` | `needs_review` / low | 51 | R |
| A174 / `result.lints[4].findings[70]` | `authenticated_security_definer_function_executable` — `public.admin_resolve_reconciliation_exception(p_exception_id uuid, p_resolution_note text, p_dismiss boolean)` | `needs_review` / low | 52 | R |
| A175 / `result.lints[4].findings[71]` | `authenticated_security_definer_function_executable` — `public.admin_retry_notification(p_event_id uuid, p_reason text)` | `needs_review` / low | 155 | R |
| A176 / `result.lints[4].findings[72]` | `authenticated_security_definer_function_executable` — `public.admin_reveal_raw_bank_evidence(p_event_id uuid, p_reason text)` | `needs_review` / low | 53 | R |
| A177 / `result.lints[4].findings[73]` | `authenticated_security_definer_function_executable` — `public.admin_reveal_raw_sms(p_sms_id uuid, p_reason text)` | `needs_review` / low | 54 | R |
| A178 / `result.lints[4].findings[74]` | `authenticated_security_definer_function_executable` — `public.admin_reverse_momo_payment(p_payment_id uuid, p_reason text, p_request_id uuid)` | `needs_review` / low | 55 | R |
| A179 / `result.lints[4].findings[75]` | `authenticated_security_definer_function_executable` — `public.admin_review_bank_allocation(p_request_id uuid, p_approve boolean, p_review_note text)` | `needs_review` / low | 56 | R |
| A180 / `result.lints[4].findings[76]` | `authenticated_security_definer_function_executable` — `public.admin_review_bank_destination_change(p_request_id uuid, p_approve boolean, p_review_note text)` | `needs_review` / low | 57 | R |
| A181 / `result.lints[4].findings[77]` | `authenticated_security_definer_function_executable` — `public.admin_run_bank_reconciliation(p_run_date date, p_reason text)` | `needs_review` / low | 58 | R |
| A182 / `result.lints[4].findings[78]` | `authenticated_security_definer_function_executable` — `public.admin_runtime_config()` | `needs_review` / low | 156 | R |
| A183 / `result.lints[4].findings[79]` | `authenticated_security_definer_function_executable` — `public.admin_set_collect_payee_status(p_payee_id uuid, p_active boolean, p_reason text)` | `needs_review` / low | 157 | R |
| A184 / `result.lints[4].findings[80]` | `authenticated_security_definer_function_executable` — `public.admin_set_feature_flag(p_key text, p_enabled boolean, p_reason text)` | `needs_review` / low | 158 | R |
| A185 / `result.lints[4].findings[81]` | `authenticated_security_definer_function_executable` — `public.admin_set_group_active(p_collection_id uuid, p_active boolean, p_reason text)` | `needs_review` / low | 159 | R |
| A186 / `result.lints[4].findings[82]` | `authenticated_security_definer_function_executable` — `public.admin_set_member_sms_receipt_consent(p_member_record_id uuid, p_enabled boolean, p_capture_method text, p_reason text)` | `needs_review` / low | 59 | R |
| A187 / `result.lints[4].findings[83]` | `authenticated_security_definer_function_executable` — `public.admin_set_sms_receipt_policy(p_collection_id uuid, p_enabled boolean, p_reason text)` | `needs_review` / low | 60 | R |
| A188 / `result.lints[4].findings[84]` | `authenticated_security_definer_function_executable` — `public.admin_system_health(p_id text)` | `needs_review` / low | 160 | R |
| A189 / `result.lints[4].findings[85]` | `authenticated_security_definer_function_executable` — `public.admin_update_collect_payee(p_payee_id uuid, p_label text, p_reason text)` | `needs_review` / low | 161 | R |
| A190 / `result.lints[4].findings[86]` | `authenticated_security_definer_function_executable` — `public.admin_update_collection_support_status(p_collection_id uuid, p_status text, p_reason text)` | `needs_review` / low | 162 | R |
| A191 / `result.lints[4].findings[87]` | `authenticated_security_definer_function_executable` — `public.admin_update_platform_public_group(p_collection_id uuid, p_title text, p_description text, p_collection_type text, p_category_subtype text, p_purpose_label text, p_receiver_label text, p_momo_code text, p_network text, p_reason text)` | `needs_review` / low | 163 | R |
| A192 / `result.lints[4].findings[88]` | `authenticated_security_definer_function_executable` — `public.admin_update_platform_public_group_metadata(p_collection_id uuid, p_title text, p_description text, p_collection_type text, p_category_subtype text, p_purpose_label text, p_receiver_label text, p_reason text)` | `needs_review` / low | 164 | R |
| A193 / `result.lints[4].findings[89]` | `authenticated_security_definer_function_executable` — `public.cancel_bank_transfer_intent(p_intent_id uuid)` | `needs_review` / low | 61 | R |
| A194 / `result.lints[4].findings[90]` | `authenticated_security_definer_function_executable` — `public.claim_verified_current_account()` | `needs_review` / low | 165 | R |
| A195 / `result.lints[4].findings[91]` | `authenticated_security_definer_function_executable` — `public.collection_is_public_approved(target_collection_id uuid)` | `needs_review` / low | 166 | R |
| A196 / `result.lints[4].findings[92]` | `authenticated_security_definer_function_executable` — `public.create_bank_transfer_intent(p_collection_id uuid, p_amount_minor bigint)` | `needs_review` / low | 62 | R |
| A197 / `result.lints[4].findings[93]` | `authenticated_security_definer_function_executable` — `public.create_contribution_intent(collection uuid, p_expected_amount_rwf bigint, p_sender_phone_hash text)` | `needs_review` / low | 167 | R |
| A198 / `result.lints[4].findings[94]` | `authenticated_security_definer_function_executable` — `public.create_mobile_support_request(request_subject text, request_message text)` | `needs_review` / low | 168 | R |
| A199 / `result.lints[4].findings[95]` | `authenticated_security_definer_function_executable` — `public.create_private_group_with_owner_attested(group_name text, group_description text, receiver_momo_number text, receiver_momo_number_hash text, receiver_label text, group_collection_type text, group_category_subtype text, group_purpose_label text, native_capability uuid)` | `needs_review` / low | 169 | R |
| A200 / `result.lints[4].findings[96]` | `authenticated_security_definer_function_executable` — `public.create_private_group_with_owner_media_attested(group_name text, group_description text, receiver_momo_number text, receiver_momo_number_hash text, receiver_label text, group_collection_type text, group_category_subtype text, group_purpose_label text, native_capability uuid, group_image_url text, group_accent_color_hex text)` | `needs_review` / low | 170 | R |
| A201 / `result.lints[4].findings[97]` | `authenticated_security_definer_function_executable` — `public.current_user_has_admin_permission(permission text)` | `needs_review` / low | 63 | R |
| A202 / `result.lints[4].findings[98]` | `authenticated_security_definer_function_executable` — `public.current_user_is_platform_admin()` | `needs_review` / low | 171 | R |
| A203 / `result.lints[4].findings[99]` | `authenticated_security_definer_function_executable` — `public.ensure_current_member_profile(p_whatsapp_phone text, p_country_code text)` | `needs_review` / low | 172 | R |
| A204 / `result.lints[4].findings[100]` | `authenticated_security_definer_function_executable` — `public.get_active_policy_document(p_kind text, p_locale text)` | `needs_review` / low | 173 | R |
| A205 / `result.lints[4].findings[101]` | `authenticated_security_definer_function_executable` — `public.get_bank_transfer_destination()` | `needs_review` / low | 64 | R |
| A206 / `result.lints[4].findings[102]` | `authenticated_security_definer_function_executable` — `public.get_bank_transfer_intent(p_id uuid)` | `needs_review` / low | 65 | R |
| A207 / `result.lints[4].findings[103]` | `authenticated_security_definer_function_executable` — `public.get_current_member_profile()` | `needs_review` / low | 174 | R |
| A208 / `result.lints[4].findings[104]` | `authenticated_security_definer_function_executable` — `public.get_group_share_code(p_collection_id uuid)` | `needs_review` / low | 175 | R |
| A209 / `result.lints[4].findings[105]` | `authenticated_security_definer_function_executable` — `public.get_owner_group_health(collection uuid)` | `needs_review` / low | 176 | R |
| A210 / `result.lints[4].findings[106]` | `authenticated_security_definer_function_executable` — `public.ingest_bank_evidence(p_channel text, p_source_uid text, p_raw_sender text, p_raw_body text, p_received_at timestamp with time zone, p_direction text, p_amount_minor bigint, p_currency text, p_bank_transaction_id text, p_end_to_end_id text, p_transfer_reference text, p_payer_name text, p_payer_account_last4 text, p_occurred_at timestamp with time zone, p_confidence numeric, p_parser_name text, p_parsed_json jsonb, p_headers jsonb)` | `needs_review` / low | 66 | R |
| A211 / `result.lints[4].findings[107]` | `authenticated_security_definer_function_executable` — `public.join_group_by_share_code(p_group_code text)` | `needs_review` / low | 177 | R |
| A212 / `result.lints[4].findings[108]` | `authenticated_security_definer_function_executable` — `public.join_group_by_slug(group_slug text)` | `needs_review` / low | 178 | R |
| A213 / `result.lints[4].findings[109]` | `authenticated_security_definer_function_executable` — `public.list_account_request_reasons(p_request_type text, p_locale text)` | `needs_review` / low | 179 | R |
| A214 / `result.lints[4].findings[110]` | `authenticated_security_definer_function_executable` — `public.list_current_member_collection_balances()` | `needs_review` / low | 180 | R |
| A215 / `result.lints[4].findings[111]` | `authenticated_security_definer_function_executable` — `public.list_current_member_payment_intents()` | `needs_review` / low | 67 | R |
| A216 / `result.lints[4].findings[112]` | `authenticated_security_definer_function_executable` — `public.list_current_user_bank_collection_summaries()` | `needs_review` / low | 68 | R |
| A217 / `result.lints[4].findings[113]` | `authenticated_security_definer_function_executable` — `public.list_current_user_bank_contributions()` | `needs_review` / low | 69 | R |
| A218 / `result.lints[4].findings[114]` | `authenticated_security_definer_function_executable` — `public.list_current_user_bank_transfer_intents()` | `needs_review` / low | 70 | R |
| A219 / `result.lints[4].findings[115]` | `authenticated_security_definer_function_executable` — `public.list_current_user_collection_summaries()` | `needs_review` / low | 181 | R |
| A220 / `result.lints[4].findings[116]` | `authenticated_security_definer_function_executable` — `public.list_current_user_collections(p_collection_id uuid)` | `needs_review` / low | 182 | R |
| A221 / `result.lints[4].findings[117]` | `authenticated_security_definer_function_executable` — `public.list_current_user_contributions()` | `needs_review` / low | 183 | R |
| A222 / `result.lints[4].findings[118]` | `authenticated_security_definer_function_executable` — `public.list_current_user_payment_intents()` | `needs_review` / low | 71 | R |
| A223 / `result.lints[4].findings[119]` | `authenticated_security_definer_function_executable` — `public.mark_bank_transfer_handoff_opened(p_intent_id uuid)` | `needs_review` / low | 72 | R |
| A224 / `result.lints[4].findings[120]` | `authenticated_security_definer_function_executable` — `public.mark_notification_event_read(p_event_id uuid)` | `needs_review` / low | 184 | R |
| A225 / `result.lints[4].findings[121]` | `authenticated_security_definer_function_executable` — `public.public_collection_payment_route(p_collection_id uuid)` | `needs_review` / low | 73 | R |
| A226 / `result.lints[4].findings[122]` | `authenticated_security_definer_function_executable` — `public.record_policy_acceptance(p_policy_kind text, p_policy_version text, p_locale text, p_source text)` | `needs_review` / low | 185 | R |
| A227 / `result.lints[4].findings[123]` | `authenticated_security_definer_function_executable` — `public.record_sms_access_consent(enabled boolean, momo_number_hash text, build_channel text, device_label text)` | `needs_review` / low | 74 | R |
| A228 / `result.lints[4].findings[124]` | `authenticated_security_definer_function_executable` — `public.register_notification_device(p_platform text, p_provider text, p_token text, p_environment text, p_locale text, p_app_version text)` | `needs_review` / low | 75 | R |
| A229 / `result.lints[4].findings[125]` | `authenticated_security_definer_function_executable` — `public.request_account_deletion(request_reason text)` | `needs_review` / low | 186 | R |
| A230 / `result.lints[4].findings[126]` | `authenticated_security_definer_function_executable` — `public.rotate_group_share_code(p_collection_id uuid)` | `needs_review` / low | 187 | R |
| A231 / `result.lints[4].findings[127]` | `authenticated_security_definer_function_executable` — `public.run_daily_bank_reconciliation(p_run_date date, p_reason text)` | `needs_review` / low | 76 | R |
| A232 / `result.lints[4].findings[128]` | `authenticated_security_definer_function_executable` — `public.unregister_notification_device(p_provider text, p_token text)` | `needs_review` / low | 77 | R |
| A233 / `result.lints[4].findings[129]` | `authenticated_security_definer_function_executable` — `public.update_bank_transfer_group_profile(p_collection_id uuid, p_group_name text, p_group_description text, p_group_image_url text, p_group_accent_color_hex text, p_group_is_public boolean, p_group_recurring_cadence text, p_group_collection_type text, p_group_category_subtype text, p_group_purpose_label text, p_group_is_recurring boolean)` | `needs_review` / low | 78 | R |
| A234 / `result.lints[4].findings[130]` | `authenticated_security_definer_function_executable` — `public.update_current_member_profile(p_country_code text, p_momo_provider text, p_momo_number text, p_revolut_link text, p_revolut_account text)` | `needs_review` / low | 188 | R |
| A235 / `result.lints[4].findings[131]` | `authenticated_security_definer_function_executable` — `public.update_current_member_profile(p_country_code text, p_momo_provider text, p_momo_number text, p_revolut_link text, p_revolut_account text, p_momo_pay_code text)` | `needs_review` / low | 189 | R |
| A236 / `result.lints[4].findings[132]` | `authenticated_security_definer_function_executable` — `public.user_can_read_collection(collection uuid, user_uuid uuid)` | `needs_review` / low | 190 | R |
| A237 / `result.lints[4].findings[133]` | `authenticated_security_definer_function_executable` — `public.user_is_collection_admin(collection uuid, user_uuid uuid)` | `needs_review` / low | 191 | R |
| A238 / `result.lints[5].findings[0]` | `auth_leaked_password_protection` — `Auth` | `needs_review` / low | 192 | W |

## Practical disposition

Keep the intended public catalogue and narrow actor-bound RPC interfaces. Preserve default-deny private storage. Resolve the verified hosted/local deployment gaps, retire the known legacy bank execution paths, and verify the exact hosted bodies/columns/roles before making targeted permission changes. The supplied warnings do not justify broad destructive revocations or enabling permissive RLS policies.
