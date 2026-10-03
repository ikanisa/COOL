# Collect backend, security and financial-data review

Date: 1 October 2026. Review of the current working tree rooted at `/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL`, with reported base HEAD `df1150ea118aa5dcc9ecb880c71873423081bffe`. This is a review deliverable; no application remediation, hosted SQL, provider request, deployment or secret inspection was performed.

**Assessment: production acceptance remains NO-GO.** The backend contains meaningful protection for financial finality, identity, request replay, private imports and uncertain messaging. Several verified integration defects and unresolved operational decisions prevent release. This conclusion does not assert that the hosted application is insecure or unavailable: its current state could not be established.

## Coverage and evidence limits

The recursive inventory counted 188 migration SQL files, approximately 50,497 SQL lines, 77 Edge TypeScript files including 31 test files, and 82 MCP TypeScript/Swift source files including 30 test files. There are 12 Edge entrypoints. The inventory is broad; manual review was targeted to high-consequence boundaries and effective recent overrides, rather than a claim that every line received manual inspection. The final inventory metadata is retained in `backend-inventory.json`.

Deep reads covered OTP signatures and uncertain-send recovery; receipt ingestion and parser leasing; request-bound Play Integrity; intent/payer matching; provider-confirmation binding; two-person reconciliation and current Auth sessions; native push fencing and retry; operator SMS authority; roster extraction/provenance/resource boundaries; latest gateway, supervisor, operating-policy and exception-worker contracts; raw evidence custody; deletion-request handling; recovery and deployment scripts. Earlier working reports were used as leads and were checked against current source. Historical tests or local completion registers do not establish current hosting or live acceptance.

The parent review attempted read-only access to the linked Supabase project. Project details, migrations and advisors returned `INVALID_ARGUMENT`; the connection's project list did not include the linked project. This is an access/evidence limitation, not proof that the project was deleted, inactive or misconfigured. Deployed migrations, function hashes, effective ACLs/RLS, Auth, MFA, scheduled jobs, backup state and production data were not read back. No remote SQL was performed.

Fresh local checks:

| Check | Observed result | What it establishes |
| --- | --- | --- |
| Pinned Deno 2.5.6, frozen `supabase/functions/deno.lock`, cached-only, 11 selected unit files | **143 passed; 0 failed** | Local crypto/parser, OTP, reconciliation-response and notification orchestration behavior; no network/DB/provider permissions were granted and no external credentials were forwarded. |
| `scripts/migrations/validate_supabase_migrations.sh` | Pass | Historical file/pattern and version-prefix checks, not SQL execution, schema equivalence or complete migration acceptance. |
| `scripts/collect_edge_auth_contract_uat.sh` | **Fail** | The checker expects retired bank endpoints and old handler strings; it has not been maintained for the current function inventory and custom-auth handlers. Its failure does not prove the new handlers lack authentication. |

See `backend-unit.log`, `backend-unit.json`, `backend-static.json` and `backend-edge-auth-static.log`. The unit runner recorded test-file hashes and checked they did not change during its run; this is narrower than a complete transitive release binding. The inventory was subsequently captured across the reviewed backend scopes. No SQL UAT was rerun against a task-owned complete current database, and no MCP suite was rerun by this reviewer.

## Controls worth preserving

1. **SMS evidence is separated from settlement.** `20260928160000_sms_observation_never_settles.sql:6` replaces the old self-finalizer with an `sms_observed`/`awaiting_reconciliation` acknowledgement. The effective receipt v2 and Edge parser retain this distinction. `20260928171000_strict_intent_sms_match.sql:63` checks verified payer identity, exact intent/amount/receiver, attested raw evidence and time bounds; candidate payments remain in `review`.
2. **Financial finality is content-bound.** `20260929130000_provider_finality_content_binding.sql:25` compares confirmation identity and financial content, rather than allowing a transaction ID alone to overwrite a payment. Advisory and row locks protect duplicate/conflicting finality; immutable journals and compensating reversals preserve history.
3. **Reconciliation has a strong local separation-of-duties model.** `20260929170000_governed_reconciliation_workflow.sql:99` requires AAL2; proposals and approvals retain separate users/sessions; service finalization rechecks both under locks. `20260930213000_operator_email_auth.sql:112` adapts the actor check to approved email identity while retaining AAL2.
4. **OTP has signed and durable authority.** `_shared/signed_sms_hook.ts:3` verifies timestamped Standard Webhooks signatures; `auth-send-whatsapp-otp/handler.ts:128` uses only the signed hook. Durable reserve/begin/finish receipts bind hook ID and payload hash. Provider transport uncertainty does not trigger an automatic resend. The former direct static-secret OTP path is not present in the reviewed effective handler.
5. **Integrity binds evidence to the specific action.** `verify-play-integrity/index.ts:119` recomputes the request hash; `_shared/integrity_policy.ts:4` checks app/package, licensing, certificate, minimum version, device verdict and freshness. Capabilities are short-lived and redeemed against exact content. This follows Google's documented request-binding approach; integrity remains device/app/request trust rather than provider settlement proof. [Google Play standard requests](https://developer.android.com/google/play/integrity/standard).
6. **Notifications have server-side fencing.** September 29 delivery/retry/session migrations add claim tokens, attempt numbers, bounded backoff, session-bound registrations and durable completion. An accepted push transport response is not reported as device presentation or carrier delivery.
7. **Imports have unusually strong local controls.** The decoder uses an operator-configured endpoint, HMAC response binding and build fingerprint; resource reservations constrain expensive processing. AI candidates are non-submittable until deterministic/human review. Source/revision/request provenance and private recovery drafts remain distinct from final roster mutation.
8. **Automation authority is constrained.** Separate gateway device proofs, supervisor identity proofs and scheduler secrets are scoped independently. `20261001003338_unattended_operating_policy.sql:11` initializes Paused with emergency stop. New operational workers return explicit `financial_action=false` and `send_action=false` rather than interpreting a scan as delivery. The later Android dispatch contract is a separate permit/arm/attempt boundary.
9. **Financial and private source access is deliberate.** Many private schemas revoke client/service table access and expose scoped functions; raw SMS reveal requires a recorded reason and sensitive-access audit. New member activity is Rwanda/RWF/MoMo only, while historical bank records are retained as evidence.

## Findings requiring action

Priority terminology: P0 blocks financial/security acceptance; P1 should be resolved before the affected capability is released; P2 is controlled hardening or maintainability work. “Observed” means current source or a fresh local command; “unverified” means release evidence is missing. These are distinct findings, not claims of successful exploitation.

### BE-01 — P0: hosted parity and security acceptance cannot be established

**Evidence:** The review's connector could not read the linked project; the current migration chain has grown to 188 files, while existing September/October reports reference earlier 133/185/187-file candidates. `docs/release/PRODUCTION_REMAINING_TASKS_2026-09-30.md:3` explicitly retains production NO-GO and 101 open checks. Those are historical/current-register assertions, not a live hosting readback.

**Impact:** Local finality or session fixes cannot protect a hosted environment until exact source/configuration parity is established. Publishing a client against an older contract can fail money, roster, receipt, operator and gateway journeys.

**Recommendation / acceptance:** Backend/release owner must restore authorized read access, bind the frozen candidate to deployed migration/function/configuration hashes, compare effective owners/search paths/table and column grants/RLS/views/private helper grants, and execute the documented anonymous/member/operator/service/cross-group denial matrix in authorized staging. Preserve the failed access result as unknown. A hosted pass requires dated evidence; no absence of access should be converted into a pass or an outage diagnosis.

### BE-02 — P0: an independent finality evidence policy is still required

**Evidence:** The proposal API stores an evidence SHA-256 and operator-supplied reference/time (`20260929170000_governed_reconciliation_workflow.sql:124`; latest exact-amount proposal override in `20260930235000_exact_receipt_history_amounts.sql:24`). The checker and locked finalizer verify authorization, fingerprint/content and two-person approval. They do not themselves establish authenticity of the underlying provider statement or evidence bytes. The content policy states `provider_settlement_verified=false` (`20261001100000_receipt_financial_policy.sql:560`). Existing register F02 retains this decision.

**Impact:** A hash of untrusted evidence plus two approvals can become a durable internal reconciliation without proving actual provider settlement. Strong DB mechanics cannot supply the external financial fact.

**Recommendation / acceptance:** Finance and security must select the permitted independent statement/provider evidence route or formally approve a constrained reconciliation policy. Bind the retained source object, provenance, access control, provider/receiver/transaction/amount/currency/time and checker decision; define ambiguous matches, corrections and reversals. Accept only genuine authorized cases and adversarial mismatches with no ledger posting on untrusted or absent evidence. UI and receipt wording must remain aligned to the approved evidence level.

### BE-03 — P1, observed: canonical deploy/readiness inventories omit four current endpoints

**Evidence:** `scripts/supabase_deploy.sh:12` lists only eight expected functions and deploys only that array at line 121. It omits `reconciliation-finalize`, `collect-android-gateway`, `collect-receipt-supervisor` and `collect-receipt-exception-worker`, all present in current source/config. `scripts/supabase_production_readiness.sh:12` retains the same older inventory. Custom proof endpoints also need their configured `verify_jwt=false` boundary preserved.

**Impact:** `make supabase-deploy` cannot deliver the complete current backend. An eight-function readiness check cannot certify the full twelve-function product; new financial/gateway/worker capabilities can remain absent or stale even when this portion passes.

**Recommendation / acceptance:** Maintain one typed/versioned endpoint manifest consumed by deploy, auth smoke, secret-name/config checks, dependency binding and readiness. Review each new endpoint's custom authority instead of treating `verify_jwt=false` as automatically insecure. In an isolated/staging target, prove all twelve intended endpoints, exact auth modes and bundle identities; missing/stale/extra retired endpoints must block. This review did not deploy anything.

### BE-04 — P1, observed static gap: assisted SMS service bridge drops the originating operator session

**Evidence:** `collect-notification-operator/index.ts:47` checks `admin_current_user` using the caller JWT, then switches to `serviceClient().rpc` at line 58. `_shared/notification_operator.ts:73` forwards only `p_operator_user_id`. `collect_hybrid.operator_authorized` remains the September 3 definition (`20260903090000_hybrid_sms_notification_outbox.sql:270`) using service-role plus `permission_allowed`. The latest `caller_eligible` explicitly accepts a service JWT after approved-identity checking (`20260930233000_sensitive_admin_authority.sql:28`). Claim/content/confirm/send-start functions therefore have no original-session ID to recheck atomically with their mutation. This is different from the locked session checks in roster and reconciliation.

**Impact:** A logout/session invalidation between initial Edge authorization and the later sensitive service RPC is not fenced at the DB mutation. Durable role/approval checks remain valuable, but cannot prove the original live session. Revocation racing an unlocked stable authorization read also needs explicit ordering validation. No live exploit was attempted.

**Recommendation / acceptance:** Carry the validated original session ID through this service bridge; recheck current user, approval, role, permission and required assurance under the same existing lock discipline as the sensitive mutation. Retain the session in confirmation/send-start audit. Test both orderings of logout, expiry, identity/role revocation and confirmation/send-start, including same-user fresh-session replacement. A revoked winning transaction must prevent new sensitive reads and new send permits; a completed permitted operation must retain truthful immutable evidence.

The reason for this requirement is concrete: Supabase recommends checking the JWT's `session_id` against `auth.sessions` for sensitive actions that must stop after logout. [Supabase sessions](https://supabase.com/docs/guides/auth/sessions). A service-role invocation bypasses normal RLS, so the bridge must supply and enforce the application authorization it needs. [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security).

### BE-05 — P1, observed implementation gap: raw-evidence retention and deletion are not an operational workflow

**Evidence:** Raw receipt bodies are stored (`202605230001_collect_baseline.sql:124`). A trigger blocks all raw-row deletion and demands a governed retention migration (`20260903084000_hybrid_direct_ussd_financial_core.sql:373`). Recursive migration search found no implemented raw-SMS retention purge/redaction policy. `request_account_deletion` inserts a pending request (`20260531190000_mobile_production_state_support.sql:82`); no corresponding end-to-end execution/identity revocation/deletion receipt was found in the reviewed migration/Edge scope. Some later TTL/purge helpers cover metrics/private recovery, which does not establish raw or account deletion.

**Impact:** The system can receive a request yet indefinitely retain raw financial/identity data and restricted foreign-key records. Deleting Auth/profile records directly can fail or break evidence; treating a queued request as completed would be misleading.

**Recommendation / acceptance:** Privacy/backend/finance owners must approve a per-class schedule covering raw bodies, hashes, names, roster sources/drafts, messages, financial journals, audit, exports/backups and legal holds. Implement a governed, bounded redaction/deletion job that preserves legally required financial facts and irreversibility evidence, revokes sessions, records decisions and reports actual completion to the user. Prove scoped requests, duplicate requests, legal holds, partial failure/restart, derivative/export deletion and preservation of balances/journals. Do not weaken immutable journal retention simply to make account deletion pass.

### BE-06 — P1: Auth/MFA/OTP enablement remains configuration-sensitive

**Evidence:** Local `supabase/config.toml` disables all configured MFA enrollment/verification factors and contains an explicitly local test OTP. Production values were not read. Reconciliation requires AAL2; a release without an available configured factor cannot use that path. The signed OTP policy has no invented global quota (`20260930130000_signed_otp_uncertain_recovery.sql:3`); its private singleton requires owner configuration. The owner-selected email operator transition exists, while the register states hosted email/SMTP acceptance remains outstanding.

**Impact:** Member sign-in can be unavailable even though handler unit tests pass; reconciliations can be blocked by absent MFA; local test conveniences are unsafe if inadvertently mirrored into release. The source config alone does not establish a production vulnerability.

**Recommendation / acceptance:** Obtain hosted Auth/hook/provider/SMTP and factor readback, verify test mappings are absent there, configure approved OTP global/per-phone spend limits and upstream bot/source controls, and prove actual email/WhatsApp/MFA sign-in/recovery/cutover with bounded abuse cases. Verify provider outage, delivery ambiguity, template/language failure and secret rotation without blind resend. Keep local convenience separate from a validated release profile.

### BE-07 — P1, source gap with unverified edge mitigation: Play Integrity admission and quota resilience

**Evidence:** `verify-play-integrity/index.ts:119` authenticates and validates a bounded request, then calls Google decode at line 249 before DB capability mint. No per-user/global request reservation or decode-rate admission check is present in this handler. Capability mint expires older outstanding action tokens but does not bound upstream decode calls (`20260903084000_hybrid_direct_ussd_financial_core.sql:121`). No external gateway/WAF limit was read back.

**Impact:** A compromised authenticated identity can repeatedly consume backend/Google work or shared quota. Provider quota or outage can block legitimate group/SMS actions; request authenticity checks do not provide capacity fairness.

**Recommendation / acceptance:** Establish per-user/action and global admission budgets before Google work, fail closed with a stable retryable code, measure decode latency/quota and bound outstanding work. Avoid re-decoding the same uncertain token without a defined recovery policy. Test budget races, quota exhaustion/outage and legitimate queues at expected peak volumes. Retain request-hash/certificate/version/license validation. [Google Play Integrity overview and quotas](https://developer.android.com/google/play/integrity/overview).

### BE-08 — P1: the migration chain needs a canonical current-schema review and final reproducibility proof

**Evidence:** There are 188 migrations and about 50,497 SQL lines, with repeated function replacements across role, geography, payment-rail and receipt-policy changes. The latest worker migration rejects an unexpected predecessor by body digest (`20261001210000_receipt_worker_bounded_sweep.sql:13`). The static validator checks historical May patterns and truncates migration prefixes to twelve digits (`scripts/migrations/validate_supabase_migrations.sh:16`). It does not parse, execute or compare the full current chain. Existing broader clean/populated evidence belongs to named earlier candidates; its transitive freshness must be demonstrated, not assumed.

**Impact:** Developers can read a superseded function and misunderstand the actual contract. A strict predecessor check is good protection but also makes out-of-band SQL changes a release compatibility issue. A green grep-only validator is insufficient to assert an installable backend.

**Recommendation / acceptance:** Add a generated effective-schema/function/grant inventory for the frozen release and a clear domain/caller/owner map; keep applied history immutable. Replay the exact final chain under ordinary intended owners on empty and representative populated predecessor databases; verify late overrides, predecessor fingerprints, historical balances/ACLs, incompatibilities and rollback/roll-forward. Use full timestamp versions. Refactor current definitions and test entrypoints incrementally rather than squashing applied migrations or deleting historical bank evidence.

### BE-09 — P1: complete current-version recovery acceptance is absent

**Evidence:** `docs/RECOVERY_RUNBOOK.md:3` reports older database capture/restore success and explicitly leaves Storage/off-site/RPO/RTO acceptance open. `scripts/supabase_logical_backup.sh:9` truthfully declares a partial public export; actual dumps omit owners/privileges and private/Auth schemas. The runbook documents that restoring into a prebootstrapped target previously widened grants, demonstrating why data hashes alone are insufficient. Current 188-migration production recovery was not verified.

**Impact:** Losing private schemas, Auth state, Storage bytes, grants, provider settings or scheduled-worker state can prevent safe recovery or restore revoked authority. A partial public export cannot recover the product.

**Recommendation / acceptance:** Run an authorized isolated current-version restore covering all DB schemas/ACLs/roles/sequence state, Storage bytes, Auth/Edge/configuration and secret inventories through a trusted manager. Keep restored external sends disabled; reconcile post-snapshot revocations. Set accountable RPO/RTO, encrypt and test off-site copies, then measure the actual drill against them. Supabase confirms database backups do not include Storage object bytes. [Supabase backups](https://supabase.com/docs/guides/platform/backups).

### BE-10 — P1, observed: backend check entrypoints are inconsistent with the current suite

**Evidence:** The freshly executed `make`-referenced auth contract script fails on retired endpoints, custom-auth gateways and relocated handlers (`scripts/collect_edge_auth_contract_uat.sh:8`, log retained). CI discovers every `_test.ts` and invokes plain `deno test` (`.github/workflows/ci.yml:419`) without selecting the explicit `supabase/functions/deno.lock`/`--frozen` used by the reviewed local runner. It also includes decoder integration/observed-wire tests needing their separate configuration/evidence and read/network permissions. `scripts/qa/run_edge_unit_tests.py:19` documents a named Linux integration exclusion and required synthetic worker report, neither supplied by the plain CI command.

**Impact:** The canonical gate can fail because of stale checks or hidden fixture requirements; alternatively dependency resolution can differ from the accepted frozen local suite. Engineers may bypass useful protection to clear misleading failures.

**Recommendation / acceptance:** Make CI invoke maintained canonical unit/type/HTTP/decoder/SQL runners with explicit scopes and least permissions, the pinned runtime and frozen lock. Run the clean network-restricted CI recipe against a frozen candidate and retain genuine completion logs. Preserve separate Linux adapter and database integration acceptance; do not silently omit their release gate or weaken assertions. Replace source-string security inference with behavior tests of actual handlers where possible.

### BE-11 — P2: phone hashes are pseudonymous identifiers, not anonymized data

**Evidence:** `_shared/hash.ts:26` returns unkeyed SHA-256 of a normalized Rwanda number; SQL `_authenticated_momo_phone_hash` uses the same digest (`20260928170000_confirmed_momo_payer_posting.sql:57`). Rwanda numbers have a constrained input space, so equality/matching and dictionary reidentification remain possible. Access controls reduce exposure; no hash disclosure or breach was established.

**Impact:** Hashes in exports, telemetry, backups or AI-derived material may still identify a person. Calling them anonymous or granting broad access on that assumption would be unsafe.

**Recommendation / acceptance:** Treat existing hashes as personal/pseudonymous data in inventory and retention rules. Where the identifier's threat model warrants it, use a server-keyed, versioned HMAC with planned migration/rotation and explicit separation from publicly exchangeable request hashes. Prove Dart/native/SQL/Edge identity parity and historical matching before changing any financial identifier. First close access/retention/claims gaps; avoid an unplanned hash rewrite across ledgers.

### BE-12 — P1: operational controls are implemented but live operability is unverified

**Evidence:** Health samples are redacted and time-bounded; worker scans are capped and default operating mode is Paused. Actual deployment/scheduler credentials, enrolled device/supervisor identities, caps, on-call routes, real provider rates and meaningful alert delivery were not read. Synthetic `financial_action=false` or worker completion cannot prove a real SMS send or customer recovery.

**Impact:** A secure paused worker can leave backlog unprocessed; a locally passing health contract can remain disconnected from production monitoring. Silent transport uncertainty, receipt deferrals or depleted capacity can persist.

**Recommendation / acceptance:** Set a monitored service-level objective for authentication, receipt custody/parse/allocation/finality, notification registration/delivery and worker freshness. Define named on-call ownership and runbooks for oldest backlog, budget exhaustion, stale gateway/SIM, Integrity/OTP/push outages, key revocation and unknown outcomes. Demonstrate alerts with controlled staging faults and real authorized device/provider UAT; annotate observation/simulation/source/freshness in dashboards. Keep action caps, emergency stop and no-blind-retry semantics.

### BE-13 — P1: AI roster processing requires vendor/region/retention acceptance

**Evidence:** `_shared/openai_roster.ts:78` embeds complete image/PDF source content in a Responses request; the schema extracts full names and MoMo numbers. It uses `store:false` and blocks automatic submission. These are good controls, but source bytes still cross a third-party processing boundary. Approved vendor arrangements, processing location and applicable account retention settings were not read.

**Impact:** Imports may transfer group/member data outside the intended controller/processor/region arrangement. A non-stored response setting is not proof of zero retention for all provider logs or source handling.

**Recommendation / acceptance:** Document the exact data path and review processor terms, region/transfer authority, permitted purposes and actual retention settings; choose deterministic decoding where sufficient and expose a comprehensible authorized import disclosure. Prove source minimization, prompt-injection failure cases, strict output validation, budget isolation and deletion/hold behavior. OpenAI documents API retention/data-control settings separately from response storage. [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data).

## Full backend checklist and remaining acceptance

| Area | Current evidence | Required release proof |
| --- | --- | --- |
| Endpoint/caller architecture | Twelve source endpoints; shared helpers; strict newest worker contracts | Single maintained deployment/auth manifest, versioned caller map, BE-03 |
| Identity and sessions | Approved verified operator identities; AAL2 reconciliation; locked roster paths | Hosted Auth/MFA/email cutover; session-revocation matrix; assisted bridge BE-04 |
| Member/group isolation | Membership helpers, RPC-only profile writes, private-schema revokes | Current effective anonymous/member/owner/operator/service allow/deny and cross-group tests |
| RLS, column grants and views | Many explicit revokes and invoker views; old advisor records | Exact current deployed policy/ACL/owner/readback and reachable-privilege review |
| Native evidence trust | Request-bound attestation/certificate/version/licensing checks | Genuine signed-device verdict/replay/expiry/min-version/outage/quota tests |
| OTP authenticity/abuse | Signed hook; durable uncertainty and replay control | Real hook/provider/template delivery; upstream abuse controls and approved spend policy |
| Money/finality | Review candidates; bound confirmation; immutable journals/reversals | Independent source authenticity; finance-approved state meanings; exact reconciliation |
| Idempotency/concurrency | Advisory/row locks, durable request IDs/fences | Frozen current SQL/HTTP/device races, timeouts and both revocation orderings |
| Input/output contracts | Body bounds, exact integers, stable public failures, strict newer ACKs | Whole consumer path/legacy payload coverage, no raw/provider/SQL leakage corpus |
| Resource/cost fairness | Roster reservations; bounded batches and locked scheduler budget | Integrity admission; representative load/bot/quotas; cost alarms and approved caps |
| API failure/timeouts | Strong bounded newer handlers; receipt parser retries retain custody | Stalled body/DB/provider tests for every exposed endpoint and delivery scheduler |
| Data lifecycle | Immutable financial evidence, private draft/metric TTL helpers | Per-class retention, legal hold, executed account deletion/correction, BE-05 |
| AI/file safety | HMAC/build-bound decoder, file/resource checks, human/deterministic review | Linux sandbox runtime proof, exact provider data settings and privacy acceptance |
| Notifications | Registration/session/attempt fencing and provider-aware retry | Actual APNS/FCM/SIM delivery, taps, invalid-token behavior, recipient revocation |
| Gateway/supervisor/MCP | Separate proofs and identities; owner-private Keychain/profile safeguards | Installed helper/runtime integrity, enrollment/revocation, real device/SIM and host lifecycle |
| Automation | Paused by default, cap reservations, emergency stop, audit | Approved mode/caps/schedule; live freshness/stop/recovery without escalating scope |
| Observability/incidents | Redacted enums/health freshness/exception inbox | Exported live dashboards, owned alert delivery, security and money incident drills |
| Performance/scalability | New relational/keyset paging and bounded sweep indexes | Representative-volume latency/plans, migration-lock times, connection/queue limits |
| Migrations/backward compatibility | 188 ordered files and predecessor protection | Current ordinary-owner clean/populated replay, old-client rollout/recovery proof |
| Backups/DR | Truthful partial exporter and detailed runbook | Current full restore, Storage/off-site bytes, grant equivalence, RPO/RTO |
| Secret/provider management | Service credentials server-side; distinct custom proof boundaries | Redacted history/archive exposure review, rotated keys where needed, live old-key denial |
| Release supply chain | Runtime and dependency locks present; safe unit proof | Clean CI frozen resolution, trusted build/source/artifact parity and accountable release approval |

## Refactoring and cleanup sequence

1. **Before feature release:** fix the endpoint manifest/checker/CI contract, close the assisted operator session gap, approve independent finality evidence and obtain hosted readback. These have direct release consequences.
2. **Before routine operations:** complete governed deletion/retention, current restore acceptance, Integrity/OTP admission and monitoring/alert ownership. Bind device/provider acceptance to the exact signed client/API versions.
3. **Maintainability:** publish a generated effective-schema/API/grant inventory and domain ownership map for financial core, operator authority, receipts/gateway, imports, notifications and operations. Separate tests by unit/HTTP/SQL/Linux/device/hosted category with explicit prerequisites. Keep migrations as historical changes and review the effective current definitions; do not delete applied SQL or hidden financial evidence to reduce file count.
4. **Code cleanup:** expand tightly compressed security-critical one-line functions when that measurably improves review; consolidate repeated validators/response contracts only through their real consumers and negative tests. Avoid a wholesale rewrite or extra architecture layers. Retire obsolete executable tests/checkers and deployment manifests after the maintained replacement proves equivalent intended controls. Archive repetitive dated evidence with a manifest and canonical index rather than deleting unique source/evidence material.

The backend's strongest local protections should survive this work. Release acceptance requires their exact deployed form, independent business evidence and working recovery/operations; the available local passes cannot supply those facts.
