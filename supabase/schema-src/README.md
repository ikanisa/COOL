# Curated Collect PostgreSQL baseline

This is a shape-preserving PostgreSQL17 translation of the final17 Cloudflare
migrations. It does not restore the historic210-file Supabase lineage. The
generator reads the current17 input bodies, executes them in in-memory SQLite
to resolve additive changes, and records their hashes and effective object names.

The app schema retains97 table names, column names, text JSON/UTC timestamps and
bigint integer values for the canonical domain adapter. It translates all169
effective source triggers and34 explicit indexes, adds case-folded Admin email
uniqueness, and makes both views security-invoker views. Foreign keys are added
after all tables exist so the source session/factor and privacy cycles remain
enforceable. Constraints and source guards are not disabled for import.

The sole source-guard method replacement is
`auth_mfa_verified_session`: its new proof is real Supabase Auth session/factor
and AMR evidence, not a copied authenticator secret or fabricated local counter.
Additional guards bind mutations to the managed principal/session, validate Auth
session projections, serialize collection accounting and fence final SMS,
payment-evidence and roster-source application commits on their exact retained
object, owner, entity, purpose and plaintext hash. Managed MFA freshness
comes from auth.mfa_amr_claims and the verified JWT AMR timestamp; calling the
helper again cannot make an old proof fresh.

`collect_runtime` is a NOLOGIN/NOBYPASSRLS backend role with app DML and narrowly
defined private custody access. A separately provisioned, protected Edge runtime
login assumes it transaction-locally. It has no Auth table grants or schema DDL.
Anonymous/authenticated client roles have no app/private access. The Edge service
verifies the real user with Supabase, sets the original JWT claims as transaction
context and runs only server-owned parameterized domain SQL. There is no exposed
raw SQL executor or abbreviated financial RPC. Financial routes remain the
canonical domain adapters. Their batch transaction takes the adapter's global
advisory lock; private.lock_collections and the accounting trigger provide an
additional shared collection lock before committed snapshots.

The private Storage journal has six tables: one immutable provider namespace,
first-ciphertext reservations, put intents, individual upload attempts, canonical
object metadata and delete intents. The original `object_metadata` name is a
read-only security-invoker view. Pending encrypted payloads have durable per-owner
count/byte budgets and can clear only after their source reference commits or
exact verified erasure commits. Their binding/tombstone remains. Unknown uploads
remain unresolved and block erasure; neither timeout nor a404 clears them.
Namespace origin/bucket changes require reviewed migration rather than silently
reusing a journal for a different provider. There are no client custody grants.

Physical erasure retains the source's implemented generic-upload scope. It
requires live reviewer/MFA authority and the exact current source policy, claim,
effect, subject barrier and passed transaction guards. Financial evidence, raw
SMS and roster copies remain retained. A deferred constraint rejects metadata
erasure without its final committed dual-absence receipt and retained tombstone.
Actual native provider proof and the application retention class inventory are
still integration acceptance requirements; the database cannot independently
establish an HTTP object's absence from a caller's JSON representation.

The expanded copy catalog is `supabase/retention-inventory.json`. Application
inspection, approval schema identity and every effect transaction bind its
private and managed-copy observations. `private.retention_managed_inventory`
requires a current privacy reviewer with fresh managed MFA and returns only
bounded subject-scoped row counts and opaque hashes. It changes no Auth or
Storage schema/data and grants no raw managed-table access. It covers linked
session/token/factor/recovery/WebAuthn/flow records and exactly owned Storage
catalog/version/multipart mirrors. Unknown managed relations fail closed; a
missing/public bucket, unavailable mirror, or unmapped principal is explicitly
unverified. Shared provider configuration has schema coverage without a claim
that it is an owned subject copy. Historic unlinked identifiers, provider
logs/backups and processor copies remain blocked external classes. Private and
managed classes accept only explicit retain/blocked decisions. BFF credential
revocation during approved access quarantine requires its own policy decision.

Only the67 static role/capability definitions are seeded. They grant no user
access. No owner identity, live sessions, provider credentials, application data,
messages, jobs or external effects are seeded or activated.

Run `python3 supabase/schema-src/generate_baseline.py --check` for byte-level
source/SQL/manifest drift checking. Generation without --check updates only the
owned generated source files; the actual migration must match baseline.sql.

The SQL tests use a clearly marked synthetic managed-Auth fixture on isolated
local PostgreSQL. They test reconstruction, constraints and selected financial,
Auth/rate, revocation, receipt, MoMo, privacy and storage failure cases. The
storage SQL suite includes atomic spool clearing/rollback, changed scope/hash,
tombstones, durable budgets, retention hold/reviewer revocation and incomplete
erasure rejection. Creation of169
triggers is not exhaustive populated-path equivalence. Complete handler,
concurrency, provider, hosted17.11, native, import and recovery acceptance remains
bound to the integration evidence. Test-only reversal orchestration is in
pg_temp and is never installed as a production API.
