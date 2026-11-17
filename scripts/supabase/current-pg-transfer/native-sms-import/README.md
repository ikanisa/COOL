# Synthetic native SMS prerequisite import

This is a **single-database, synthetic-only PostgreSQL 17 candidate**. It is
not a production importer or authorization to migrate live data. Every entry
point rejects managed mode before invoking the supplied connector. The caller's
`connect` function is trusted executable code, and the fixture database name,
role and socket checks can be imitated. Run it only in the owned synthetic test
harness. It never contacts Supabase or Storage, copies object bytes, issues
credentials, or writes to `auth.users` and the existing Auth link.

## Supported graph

The importer moves a closed set of 1–64 synthetic SMS graphs from `src` to
`app` and `private` in one transaction. Each graph contains one SMS receipt,
accepted parse attempt, canonical transaction, accepted transaction-source
link, simplified native origin, completed job, collection scope and synthetic
native lineage. The fixture rejects unrelated source SMS graph rows, any
pre-existing target graph rows, conflicts and duplicates, unresolved uploads,
delete tombstones, unsettled observation/Storage intents, leases, retries,
unsupported job phases and non-successful outcomes. It requires matching
accepted source and job relations and the same parse-attempt ID through the
transaction, source link and job lineage. For this accepted native-writer
shape, the transaction ID must equal the UUID SMS source ID, and the job's
source fingerprint must equal the synthetic lineage's observation fingerprint.
The simplified origin table has no separate fingerprint column, and neither
value is recomputed from the original request. Its supported financial facts are
narrowed to incoming successful positive RWF transactions that are already
linked and have no conflict, with the selected amount, currency, event,
outcome and capture mode matching the linked job. The job's wallet balance must
be a nonnegative safe integer.
Other job facts are preserved, but are not comprehensively validated here.

The actual local source was still changing in the latest count-only diagnostic:
it observed 33 receipt/transaction/job/origin paths, including 10 financially
linked and 23 unlinked. Fourteen had an unknown selected comparison involving transaction and job facts,
and three had unknown job-wallet comparisons. These are unfenced point-in-time observations, not
a completeness or compatibility proof. This candidate requires the entire
source fixture SMS graph to fit its one closed cohort; it cannot select only
the 10 linked records while leaving 23 outside the source set. It must not be
applied to that live source as a partial-cohort adapter.

The explicitly selected local and cloud owner/Auth IDs must each have a valid
fixture account and link. Only `sms_receipts.owner_user_id` and the principal
field of the origin and synthetic lineage are mapped to the existing cloud
primary. Graph IDs, account/grant/session/request IDs, fingerprints, timestamps
and other represented fields are preserved; the receipt records the original
owner. No identity is inferred from email and the target Auth link is not
changed. The selected source SMS receipts must have null managed-session and
receiver-hash references. Their native capture/admitting session IDs are
retained **as historical references**, not presented as live sessions.

Each SMS requires a synthetic dependency row matching its collection, source
and target principals and historical account, installation, grant, session and
request IDs. It also requires fixture assertions that account/grant access is
inert, sessions revoked, the mapping reviewed and native replay disabled.
These are caller-supplied test data, not evidence of real account revocation,
identity authority, request validity, or actor shutdown. The real origin also
references immutable observation requests and observations and other actual
private relations. This fixture does not reproduce or transfer those tables,
real account/PIN or device/token records, foreign keys, all RLS policies,
triggers or their credential lifecycle.

Synthetic source and target object-proof rows must match after the selected
owner substitution, including object key, entity, purpose, plaintext digest,
ciphertext digest and AAD text. No bytes or provider responses are verified.
The real Storage reservations, intents and object metadata bind owner scope;
their request fingerprints and encryption/AAD dependencies require a
separate qualified migration and cryptographic verification. The fixture's
matching proof rows do **not** establish that changing an owner is safe with
unchanged ciphertext or fingerprints, nor that replay under the mapped owner
is valid. Preserved fingerprints are historical values; this candidate does
not rederive them for the new identity. Target native replay must remain
disabled until real provenance, credential and Storage semantics are resolved.
The fixture preserves a shaped `facts_sha256` value, but does not recover and
rehash all original model/output/facts inputs of the native finish routine. A
64-character digest is not proof that the retained original parse payload
matches it.

## Operation and reconciliation

`captureSyntheticNativeSmsPlan` validates the fixture graph and returns a
canonical `planJson`, `expectedPlanSha256` and `writeAuthorized: false`. The
caller supplies a 32-byte HMAC key and must independently evaluate the plan
and identity mapping. `importSyntheticNativeSmsGraph` rechecks the locked
preimage, target identity and postimage, writes eight target tables and a
receipt atomically, and checks the resulting graph. The caller must protect
plans, identifiers, HMACs, key material and process logs; the module copies and
clears its key where feasible. An identical already-committed operation is
recognized by receipt and postimage.

If COMMIT acknowledgement is lost, the operation returns
`commit_unconfirmed_do_not_retry`. `reconcileSyntheticNativeSmsGraph` checks the
receipt, target identity and selected postimage in a separate read-only
snapshot. An absent receipt returns `receipt_not_visible_do_not_retry`, which
is not evidence that the prior transaction stopped. There is no durable
independent dispatch journal, so a supervisor must resolve an uncertain
outcome before a new attempt. Reconciliation checks target visibility, schema
and row-security state after taking access-share locks, preventing hidden rows
or concurrent target DDL from being silently verified. These locks do not
block ordinary DML: success describes one snapshot and needs independent target
writer exclusion for final cutover verification.

The writing path takes relation locks before reading and rejects fixture
catalog drift, inheritance, RLS, inaccessible tables, unsupported sizes,
identity/fence changes and any open/uncertain synthetic admissions. It pins
the catalog and selected JSON helper. Unlike the separate financial fixture,
the added native target tables have no database-enforced statement fence;
fixture privileges and the synthetic operator must be isolated and trusted.
A privileged actor able to change helper definitions concurrently also requires
independent exclusion. These checks are not proof of live provider, device or
cross-database quiescence, nor of the current production schema or privileges.
The local source has demonstrably continued changing; any real candidate needs
a fresh complete capture under an effective, independently verified freeze.

The two synthetic schemas live in the same database, so its transaction and
locks do not establish atomicity between a local database, managed Supabase,
external Storage and mobile devices. Real work still needs compatible managed
migrations and privileges, a complete observation/request/provenance and
identity adapter, safe handling of device credentials and offline queues,
verified Storage migration and owner-scope/key/AAD treatment, source/target
writer exclusion, a coordinated backup/recovery protocol, a durable
uncertain-outcome journal, and fresh end-to-end reconciliation. It does not
cover all SMS types, all transaction sources, other users or collections,
reversals, multiple sources per transaction, incomplete history or any change
to managed Supabase.

## Run the owned fixture

```sh
COLLECT_SYNTHETIC_PG_BIN=/absolute/physical/postgresql-17/bin \
  node --test --test-concurrency=1 \
  scripts/supabase/current-pg-transfer/native-sms-import/import.test.mjs
```

The tests create and remove an owned socket-only PostgreSQL cluster. They
exercise conflict/attempt/fact checks, unsafe dependencies, source and catalog
drift, identity and target conflicts, writer locking, rollback, uncertain
COMMIT, target RLS and postimage tampering. A two-record synthetic chain runs
this SMS importer followed by the separately pinned financial importer and
verifies two posted ledger entries. This proves only the represented fixture.
The two importers commit separately: between their commits a target transaction
can say `linked` while its payment and ledger rows do not yet exist. A future
real executor needs effective target writer/reader exclusion for the entire
intermediate period and must resolve any uncertain commit before releasing it;
the SMS receipt alone is not evidence that the financial graph is complete.

An optional portability check creates and removes a uniquely labelled,
networkless container from the pinned Supabase PostgreSQL 17 image and checks
the fixture catalog digests; it does not connect to any existing database:

```sh
COLLECT_SYNTHETIC_DOCKER_CONTEXT=colima-supabase-local \
  node scripts/supabase/current-pg-transfer/native-sms-import/synthetic-linux-catalog.mjs
```
