# Governed retention inventory and SQL-row execution — 2026-11-01

## Implemented and qualified metadata inspection

`20261101014231_collect_retention_inventory_manifests.sql` was allocated by Supabase CLI 2.122.0. It introduces two private, immutable, client-inaccessible protocol tables and fresh-email-authorized Admin operations:

- `admin_capture_account_retention_inventory_v2`: captures one independently reviewed request/subject/source/review identity under an idempotent operation UUID.
- `admin_get_account_retention_inventory_page_v2`: resumes an exact manifest/root/page and can optionally recheck the current data commitment.

The selectors are compiled from the maintained application/private catalogs. SQL performs all descriptor enumeration in one statement; its `STABLE` helpers share that statement's MVCC snapshot. Each page contains at most 100 opaque descriptors and 128 KiB of JSON. Capture is bounded at 1,000,000 descriptors, including class markers. Enumeration itself applies the remaining budget inside its SQL queries. Exceeding the budget raises an error and rolls back every page and header. It never returns a truncated capture as complete. The operator must use a reviewed successor contract if the complete attributable scope exceeds this explicit budget.

Original application records, Auth secrets, Storage payloads and all provider services remain unchanged. Only hashes, limited lifecycle flags and immutable capture control metadata are retained. Page/root commitments bind the whole captured metadata scope. A resumed page checks current authority, source, request, review, hold and principal-mapping identity, the exact schema/security identity, and its stored page hash. Header integrity reads indexed page hashes/counts without detoasting every other descriptor page. `verify_current` re-enumerates the complete current scope and compares its root; an ordinary historical page returns `data_current: null` and makes no current-data assertion.

The schema identity includes app/private/Auth/Storage/Realtime/SMS/scheduler/Vault/pg_net/pg_cron and `supabase_migrations` relation definitions, constraints, view definitions, trigger definitions and enabled states, RLS/policies, ACLs, function definitions, role attributes and relevant role memberships. Unknown app/private/Auth/Storage/SMS relations fail closed. Provider and shared namespaces without a personal selector remain explicitly unverified. Their namespace presence and relation counts are not interpreted as an empty personal inventory.

Capture control tables have known request/subject attribution. They are retained protocol custody outside their own recursive source commitment, not a claim that no subject copies exist. Their schema, access rules and immutable history remain covered; they have no expiry or erasure adapter. Unverified/unknown guest-upgrade journals remain retained because their existence preserves the projection denial barrier.

`external:collect_ops`, `external:vault`, `external:net`, `external:cron`, `external:collect_sms` and `external:supabase_migrations` remain blocked copies. This includes job and email dispatch ledgers, unknown provider outcomes, credential references, HTTP queues/responses, cron history, the SMS gateway, device queues, service logs and installation receipts. `collect_ops.email_config` and `collect_ops.email_dispatches` are covered by the scheduler namespace. `app.notification_email_job_dispatches` is explicitly shared; pending/unknown dispatches are unresolved work, never a zero personal-copy assertion. Database backups must include those namespaces and the new private custody tables. A metadata capture is not a physical-object proof, provider-copy erasure receipt or backup/restore qualification.

## Native evidence

`retention-native-result.json` records fifteen passing scenarios on the dedicated PostgreSQL 17.11 UTC fixture. The fixture was provisioned with the unchanged original sixteen migrations and reviewed synthetic Realtime binding, then all eight additive migrations present at invocation were applied as a normal non-superuser owner. Retry databases were uniquely named clones of the preserved clean original16 fixture; no existing fixture or service data was reset. A separate cluster was necessary because the legitimate SMS runtime role adds a global owner membership and the historical Realtime fixture correctly refuses that changed metadata.

The qualified capture contained 5,748 descriptors on 58 pages, including 1,007 Auth rows, 1,006 Storage metadata rows, 1,001 retained Realtime messages and 2,505 notification rows. The v1 managed helper refused this scope at its existing 500-row bound, while v2 captured and resumed every descriptor. The qualification exercised a real SQL email-proof/authority chain, active hold and unresolved-OTP reporting, idempotency, wrong-root rejection, page immutability, current-data drift, atomic capacity failure, changed holds, unknown managed schema, session revocation and private-role denial. No raw synthetic secrets appeared in the page output. External requests were prohibited and their observed count was zero.

The row engine then independently qualified 85 projected sessions revoked in three chunks, while retaining all 85 native Auth session rows, followed by 2,505 notification deletions in 63 chunks and one row from each of the other three approved own-row classes. The other held subject retained all 2,506 of its notifications. Exact duplicate execution returned its original receipt without deleting another chunk. A wrong deployment policy pin, malformed policy, managed-provider erasure rule, active hold, unresolved-only scope and expired claim were all refused without effects. An expired policy required a new sealed manifest and an explicit continuation of the original immutable quarantine barrier; the prior SQL-only plan became superseded and could not acquire new claims.

This is a synthetic PostgreSQL qualification, not production acceptance. It uses local managed-service metadata doubles; real GoTrue/Storage/Realtime image compatibility, live object integrity, provider behavior and recovery remain separate release evidence. Financial source commitments remained unchanged; this retention fixture did not post a nonempty financial ledger. The separate backend qualification exercised 10,005 constrained ledger rows. The receipt pins the exact migration files tested, and `retention-source-pins.json` records owned runtime/compiler files captured after the run. The deployment-identity migration changed after this run, from its tested `7c562440...` version; the final combined-chain receipt must qualify that current version. Subsequent schema or catalog changes likewise require a new exact deployment receipt.

## Qualified SQL-row execution

Existing v1 erasure retains its exact owner-policy, writer-barrier, session, hold, source, immutable financial-record, physical-object and unknown-outcome checks. Its 500 context-row, 2,000 own-row, 20-object and 8 MiB limits are not changed by a metadata inspection API. The v1 engine uses full raw-row preimages, object body/version proofs and exact in-transaction comparison guards. Passing descriptor pages into those fields would not be equivalent.

`20261101020642_collect_retention_row_executor.sql`, also allocated by Supabase CLI 2.122.0, implements the separate v2 engine. It uses four private custody tables: immutable plan identity with controlled state transitions, immutable expiring claims, immutable per-row before/after commitments, and immutable operation outcomes. Raw tables and internal helpers are inaccessible to client roles, `service_role`, `collect_runtime` and the importer. Only the narrow fresh-authority SQL entrypoints are granted to the runtime. Existing statement admission fences remain on every new relation.

Only `notification_devices`, `notification_preferences`, `notification_events` and `support_requests` have an erasure adapter. Each chunk changes at most 40 rows from one class. The policy can retain these rows instead. Financial records, deletion/review records, session history and every other application class are retained or blocked. Private, managed, physical, provider and shared classes must be blocked. Native Auth users, sessions and refresh tokens are never deleted by this contract.

Before any own-row cleanup, the subject is quarantined using the existing irreversible writer barrier. Projected sessions are revoked in chunks of at most 40. Admin cookies and private BFF custody are handled in similarly bounded groups, and BFF revocation requires its separate explicit policy permission. The barrier remains if a request fails or a policy expires. Completion cannot be claimed while projected access remains. The existing account revision trigger is preserved: the executor reads the final locked user row after its AFTER trigger finishes, rather than treating an earlier `UPDATE RETURNING` image as the durable postimage.

Each transaction binds the current fresh email reviewer, subject and managed-principal mapping, exact policy bytes/revision, source, schema, request/review/hold identity and complete sealed manifest. The reviewer cannot be the subject. Claims expire after 1–120 seconds, require the current plan revision, and advance a monotonic fence. A stale claimant cannot mutate data. An uncertain HTTP response must be resolved by operation lookup or by replaying the same execution UUID, claim and fence; neither path creates another chunk.

The engine stores opaque original and resulting row descriptors for each authorized change. Before and after each chunk, it reconstructs the original comparison stream using only these committed deltas. Updated rows must still have the exact committed postimage; deleted preimages enter the comparison stream only, never the source database. Any unexpected row, cascade, changed source, missing postimage, financial-source change or altered control identity rolls back the complete chunk. No raw row, token, ciphertext or document body is copied into these journals. Original sources are preserved where the adapter does not explicitly authorize a SQL-row deletion.

Changing or expiring a policy cannot silently extend an old plan. A reviewer captures a new manifest of the actual remaining scope and obtains a new external owner decision. If a quarantine barrier already exists, the new policy must bind its original plan ID and exact barrier hash. Replacing an unfinished v2 SQL-only plan also requires its exact `superseded_plan_id`; an active lease prevents replacement. The old plan and every claim, delta and outcome remain retained. A replaced plan is marked superseded without rewriting its original approval or barrier.

`eligible_sql_dispositions_verified: true` means that the allowed SQL-row work under that plan completed. Responses continue to report `erasure_completed`, `all_data_erased`, `all_actual_copy_outcomes_verified` and `physical_objects_verified` as false. A recorded receipt is historical evidence, not a current provider observation. Current status can independently rerun the exact source check.

### Operator contract and activation

The migration creates no approved policy, erasure schedule or default decision. The independently approved compact JSON must be installed under `app.runtime_config.key = privacy:retention:approved:v2`, and the complete raw-byte SHA-256 must independently match `PRIVACY_RETENTION_V2_APPROVAL_SHA256` in the deployment. The production template leaves this value empty. General implementation authorization is not an account-erasure approval.

The policy is a closed contract: version 2, `scope: sql_rows_only`, policy and approval-evidence IDs, environment and synthetic flag, independent approver, approval/expiry timestamps, exact source/schema/manifest/request/subject/review identity, every captured class plus `access`, writer-fence evidence, blocked physical/provider/unmapped copies and explicit BFF revocation permission. Each rule has exactly `action`, `basis_reference` and a canonical UTC `deadline`. The action must be supported for its class; an erasure deadline must already have passed. A continuation is either null or the exact prior-barrier and supersession decision described above. The native runner contains the tested synthetic-only policy construction; those fixture approvals are not production evidence.

Use the existing authenticated Admin RPC transport with these names. Request fields are prefixed `p_` at that transport boundary:

| Operation | Required input | Result |
|---|---|---|
| `admin_capture_account_retention_inventory_v2` | `operation_id`, `request_id`, `expected_review_revision`, `expected_source_id` | Immutable manifest identity, complete class counts, page count and root. |
| `admin_get_account_retention_inventory_page_v2` | `manifest_id`, `manifest_sha256`, `page_number`; optional `verify_current` | Exact resumable descriptor page and explicit currentness state. |
| `admin_plan_account_retention_rows_v2` | `operation_id`, `manifest_id`, `manifest_sha256`, `policy_sha256`, `expected_source_id` | Exact approved SQL-only plan or refusal. |
| `admin_claim_account_retention_rows_v2` | `operation_id`, `plan_id`, `class_name`, `expected_revision`; optional `lease_seconds` | Immutable claim/fence/expiry. Start with class `access`. |
| `admin_execute_account_retention_rows_v2` | `operation_id`, `claim_id`, `fence` | Original outcome of one bounded chunk. |
| `admin_get_account_retention_rows_status_v2` | `plan_id`; optional `verify_current` | Plan progress, current barrier and supported completion flags. |
| `admin_get_account_retention_rows_operation_v2` | `operation_kind` (`plan`, `claim` or `execute`), `operation_id` | Historical operation evidence without reexecution. |

Record operation identities before transmission. Resolve an uncertain result before creating another execution identity. Continue by reading the plan revision, claiming the next bounded chunk, and inspecting the exact outcome. A refusal caused by new data, authority, holds or source/schema changes requires renewed review; it is not permission to relax the comparison or clear immutable journals.

### Bounds and remaining release evidence

V2 removes the old 500-context/2,000-own-row ceiling from this SQL-only workflow. It retains explicit complete-snapshot capacity of one million descriptors and a maximum of 40 changed rows per class chunk. Capture and full-root revalidation still read the attributable scope; they are not constant-time operations. The local test establishes resumability and correctness beyond the old bounds, not million-row throughput or an unlimited history contract. Production needs realistic size/query-plan/disk/work-mem qualification on its exact schema.

Large physical-object erasure, actual provider-copy disposition, backup expiry, other shared custodial copies and unlinked identifiers still require separately approved and verified adapters. V1's 20-object/8 MiB object limits are unchanged. The new execution contract deliberately does not label SQL absence as object/provider erasure. The new custody journals and original barriers also need backup/restore coverage and a future approved history lifecycle; none has an automatic TTL.

Final owned migration hashes:

| Migration | SHA-256 |
|---|---|
| `20261101014231_collect_retention_inventory_manifests.sql` | `cfe8da08a85db4309abb6eea5c8a8aca4d84171b64addec3733ba5af7aeb67b6` |
| `20261101020642_collect_retention_row_executor.sql` | `63262c3dbadeae748b87b490460462403101536ede6708b30a88b1ba23893346` |
