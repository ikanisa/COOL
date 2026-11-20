# Collect integration contract — v0.3.0

## Authority and activation

Attach `/v1/burimunsi` only inside the current Collect Edge request admission, work-fence, cancellation and transaction framework. The `composeNativeRequest` admission object is **server-owned**, not an HTTP field. Enablement is off unless explicitly configured after qualification. The operator token never authorizes SMS ingestion, and the existing gateway token never authorizes financial reads.

The installed native client must use one exact HTTPS API origin. Never convert an HTTP 200 HTML application shell into a successful API response. Redirects and arbitrary caller-selected origins are rejected. No global Supabase password policy is weakened to accommodate four digits. No service-role key enters the Android application.

## Implemented HTTP surface

Requests use `X-BuriMunsi-Installation` and opaque Bearer authorization. Only sign-in uses the separately provisioned `X-BuriMunsi-Device` installation secret. Secrets belong in managed configuration, never in the package. All JSON success responses are `{ "ok": true, "data": ... }`; errors expose only bounded fixed codes. Mutation request bodies are bounded to 8 KiB. Native response buffers are bounded to 2 MB.

| Method/path suffix under `/v1/burimunsi` | Purpose |
|---|---|
| POST `/session/login` | `{phone,pin}`; managed device grant and rate limits required |
| GET `/session` | Current session/account version, scope and profile |
| POST `/session/logout` | Revoke operator session, preserve independent gateway queue |
| POST `/session/passcode` | `{current,newPin,confirm}`; revoke sessions after change |
| GET `/home` | Canonical total, today's canonical postings, counts and recent original payer facts |
| GET `/payments`, `/members`, `/ledger` | Scoped versioned pages; signed cursor, filter/query binding |
| GET `/payments/{id}`, `/members/{id}` | Existing canonical record identities; MoMo phone displayed as member identity |
| POST `/payments/{id}/allocate` | Single confirmed exception attribution with expected version and stable request UUID |
| POST `/members`; PATCH `/members/{id}` | Existing Direct-member command and collection-local membership state only |
| GET/POST/PATCH `/staff` | Admin staff lifecycle; no Admin creation via public route |
| GET `/sms`, `/sms/{id}` | Registered Admin receiving installation only |
| GET `/audit` | Scoped Admin operational audit metadata |
| GET `/gateway`; POST `/gateway/replace` | Registered receiver health and authorized singleton replacement |
| GET `/operations/{requestId}` | Read known outcome; absence means pending/unknown, not proof of rejection |
| GET `/members/{id}/ledger.csv` | Complete authorized bounded ledger, CSV-injection protection |

No public registration, email, OTP, bank-core API, second ledger, payment proposal or review-approval endpoint is introduced.

## Mandatory adapters still requiring implementation/integration

### Canonical transaction port

The concrete `PostgresNativeAuthority` and `PostgresCanonicalStore` now implement transaction setup, scoped SQL reads, canonical readback and retained idempotency records. `createPostgresNativePorts` wires those implemented adapters. The actual shared writer/member/identity/source/gateway command bridges remain missing; see `docs/09_Postgres_Adapter_and_Delivery.md`.

`ContributionService` and `MemberService` require `inCanonicalTransaction(fn)`. The callback must execute within one real Collect transaction and hold its canonical lock through session revalidation, receipt/membership checks, canonical posting, snapshots, audit and idempotency receipt. A memory implementation is forbidden outside tests.

Its transaction object exposes:

- `reloadActor(sessionId)` using current native account/grant/session versions.
- `retainedCommand(group,actor,request)` and `retainCommand(...)`, scoped to actor and originating session and checked against the exact body fingerprint.
- `lockReceipt(id,group)` with original financial facts, current version/state/conflict and verified binding lineage.
- `lockMember(id,group)` with current eligibility.
- `postCanonicalContribution(command)` using **the existing canonical financial writer**, returning transaction/member/amount/currency/ledger-entry IDs and canonical member/group snapshots.
- `loadApprovedPolicy`, `listEligibleMembers`, `listVerifiedIdentities`, `readCanonicalResult` for automatic matching. A name or suffix is never an identity grant. Identity reads must include all relevant effective-dated owners, not only currently active memberships.
- `assertAutomaticAdmission({groupId, transactionId, requestId, work})` for every automatic call. Use the current receipt-job lease and existing policy/hold locks in this SAME transaction before and after posting. See `docs/07_Job_Store_Integration.md`.
- `createDirectMember`, `setMembershipActive`, `enqueueEligibleRematch` using the existing shared-person and group-membership authority. Enrollment must not create a verified payment identity from a receipt.

The current reviewed writer must be refactored or extended explicitly for a narrowly scoped automated policy. Do not fabricate a second approver, bypass its guards, fabricate another ledger table or change shared payments merely to satisfy the port. The exact common-write refactor is **not implemented in this candidate**.

### Native operator SQL

`PostgresNativeAuthStore` has executable SQL for distributed limits, sessions and staff lifecycle, but requires `createOperatorPrincipal(tx,...)` to reuse the admitted existing Collect operator-user creation command. Session insertion now revalidates the exact device grant ID and token hash; missing session selectors fail closed. JSONB parameters now pass objects rather than pre-stringified JSON. No SQL was run against a real server here. Reconcile grants and application context against the complete current schema before turning `schema-proposal.sql` into a normal migration.

Operator and device provisioning are trusted server/MDM operations. The production Admin phone and initial secret must be supplied out of band. Staff account creation does not by itself authorize an arbitrary phone installation; a scoped device grant/account assignment is required before login.

### Source and records

`PostgresRecordsStore` reads current canonical memberships, transactions, payments, ledger and snapshots in repeatable-read context. Its `sourceReader` is mandatory for original raw SMS and must reuse Collect's existing authenticated decryption, storage retention and lineage rules. A raw-body SQL table or broader storage token must not substitute for it.

`private.burimunsi_transaction_scopes` is a candidate routing relation, **not** another transaction table. Population must derive the group from the admitted original gateway binding. A wallet ID alone is insufficient group authority. The new binding ingress/population hook remains to be implemented and tested.

### Job storage and gateway authority

v0.2.0 adds `PostgresReceiptJobStore` with parameterized SQL for immutable queue admission, database-time conditional leases, retained-source verification/reparse, bounded retries and durable checkpoints. The actual Collect admission, source-decryption and canonical-ingestion/outcome ports still require integration. The SQL is unapplied and tests use a SQL recorder, not PostgreSQL. Job completion follows an authoritative allocation outcome, not parsing alone. The worker/store are not wired into the current deployed scheduler. See `docs/07_Job_Store_Integration.md`.

The singleton gateway service requires existing binding/credential mutation under transaction and a final uniqueness barrier enforced at ingestion and pairing. The candidate scope table alone does not prevent unrelated legacy endpoints from creating or using another binding. Integrate and negatively test all such paths before calling T013 complete.

## Receiver reuse

`prepare_receiver.py` verifies 17 exact source Git blobs (bundled originals by default, including the isolated queue-disposition input) at the inspected commit before generating any Kotlin output. It leaves the original repository files untouched. `BuriCapturePolicy` filters unsupported/secret-bearing messages and unbound subscription metadata before retention. An uncertain inbox scan stops without advancing past possibly relevant data; it must not claim successful backfill.

The existing gateway v2 acknowledgement fields remain authoritative: `ok`, `receipt.contract_version == 2`, `stored`, `owner_user_id`, `client_envelope_id`, `raw_sms_id` and `body_sha256`. Native queue retirement requires all matching facts.

The new pairing bridge additionally requires a server-proven `collection_id` and explicit subscription mapping. A legacy unscoped response is rejected. The existing owner-directed upload hold remains `false`; this implementation does not authorize lifting it.

## Qualification sequence

1. Obtain authoritative working-tree and deployed schema identities; reconcile remote/current drift.
2. Integrate mandatory existing-command adapters and request/job admission without changing unrelated consumers.
3. Run proposed schema and existing/new backend suites in a disposable production-shaped database; prove rollback, concurrency, role checks and App/Admin parity.
4. Resolve production group/account/Admin/managed installations/provider fixtures; exercise controlled staging capture.
5. Build both native APKs, inspect merged manifests and DEX, run instrumentation and physical-device scenarios.
6. Obtain independent security, legal/operations and owner acceptance before signing, distribution, upload activation or pilot.

## Native continuation semantics

The command journal retains stable request IDs and numbered dispatch witnesses. A failed replay cannot certify that an earlier uncertain request failed. Staff commands now use this same journal and their retained-command outcomes are readable by the originating scope. Native session generations guard requests/cache/UI continuations, but full Android execution remains unverified. Component tests do not relax the original acceptance gates.
