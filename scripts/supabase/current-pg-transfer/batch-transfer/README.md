# Encrypted batch quarantine and receipt

This is a narrow, real-callable PostgreSQL transaction building block. It moves
an already prepared, authenticated encrypted batch into a quarantine relation
and records the receipt in the **same row and transaction**. It does not read
the local PostgreSQL source, insert application/Auth/Storage rows, resolve or
merge identities, perform provider calls, or authorize a cutover. A receipt
proves only the exact encrypted envelope and plan were observed in the journal;
it does not prove that its contents came from the asserted source, that a
mapping is authorized, that any business rows were transferred, or that a
complete backup exists.

## Current installation blocker

`candidate-schema.sql` is **synthetic-only**. It explicitly refuses outside a
fixture-named database reached over a Unix socket with the synthetic cluster
name. This is an accidental-use guard, not an attestation of host ownership.
The new private relation is
not in Collect's current retention catalogue: adding it unchanged would cause
the unknown-private-class checks in `private-retention.js` and the retention
manifest SQL to refuse. It also is not included in a reviewed current-cloud
recovery plan. Do not weaken those guards or install the fixture SQL on the
managed project. A separate reviewed migration must establish retention and
erasure classification, encrypted custody, recovery coverage, role/default
ACLs and the compatible relation before any real staging run. That migration
must produce the exact catalogue expected by this library or the library must
be separately reviewed and repinned.

The user confirmed on 13 November 2026 that the local and cloud accounts with
the previously observed matching email belong to the same person, and directed
that the existing cloud account remain primary while both sets of records are
preserved. That decision does not approve automatic merging of rows, replacement
of immutable principal links, reuse of sessions, or any particular historical
mapping. This component neither applies nor verifies that decision.

The library has a managed endpoint mode for that future qualified schema, but
no reviewed real source/target plan, source exporter, complete private mapping
artifact, secure key provider or production installer is supplied. The user
request uses the existing production project directly; the tests below use disposable
local databases, not a hosted staging project.

## Protocol

- A plan is independently reviewed and pinned by its SHA-256 of recursively
  key-sorted compact UTF-8 JSON. It includes a UUID operation and source-batch
  identity, source identity and source-set digests, a keyed commitment to the
  supplied plaintext, exact expected managed fence/profile metadata, and
  per-relation source/target names, explicit columns, stable keys and mapping
  digests. The digests are assertions from the reviewed source/plan process;
  this component does not independently inspect either source rows or mappings.
- `sourceSnapshotHmac(key, plaintext)` derives a domain-separated HMAC key from
  the supplied 32-byte key. `sealBatch(plan, reviewedPlanSha256, plaintext,
  key)` checks that commitment, encrypts with AES-256-GCM and a fresh random
  96-bit nonce, and authenticates the exact plan digest as associated data.
  Both helpers first copy ordinary Buffer inputs. Staging and readback copy the
  supplied envelope and key before evaluating the plan, authenticating or
  accessing the client, then hash and send that same authenticated copy.
  SharedArrayBuffer-backed, resizable and proxied Buffer inputs, and input
  records with accessors, are refused.
  Preserve the exact envelope and the separately secured key: resealing the
  same plaintext generates different ciphertext and correctly conflicts with
  an already staged batch. Never log keys, plaintext, mappings or envelopes.
- `stageEncryptedBatch(client, input)` authenticates the envelope and HMAC in
  memory before connecting it to a transaction. It verifies the target
  connection policy, PG17 backend, `postgres` session/role, project, exact
  fenced controller identity, deployment-profile hash and the absence of
  unsettled or uncertain admissions. It takes the existing controller's two
  advisory locks and row lock, then a quarantine table lock, and checks the
  pinned logged table/constraint/index/trigger/function catalogue and direct
  ACLs, rejects rewrite rules, requires `fsync` and `full_page_writes`, and
  sets transaction-local `synchronous_commit=on`. Before sending any ciphertext
  or identifying query parameters it sets and checks both
  `log_parameter_max_length=0` and `log_parameter_max_length_on_error=0` for
  the transaction. It verifies the inserted
  envelope digest and receipt fields before committing. These PostgreSQL
  settings do not establish an independent copy or provider recovery. It
  inserts only when both operation ID and `(source identity, source batch ID)`
  are absent. An exact prior receipt returns `exact_replay`; any conflict
  returns `batch_collision`. It never overwrites a row.
- If a COMMIT acknowledgement is lost, the method closes the connection and
  returns `commit_unconfirmed`; it never retries. On a fresh, dedicated client,
  `reconcileEncryptedBatch(client, input)` takes the same advisory locks and
  checks the same identity, catalogue, plan and encrypted bytes. It returns
  `staged_receipt_verified` or `receipt_absent_at_readback`; the latter does
  not automatically authorize a retry. The locks serialize cooperating
  transactions, not privileged actors that bypass the protocol.

The plan target is a direct Supabase DB endpoint or the project's session
pooler, exact database name and TLS-verified host, with the expected immutable
deployment-profile hash, fence baseline/source hashes, epoch and operation ID.
The test-only target kind is restricted to fixture database names and the
test's private Unix socket. The destination identity check depends on the
existing fence/profile objects being genuine and unmodified: full owner,
inherited roles, default privileges, function/catalogue DDL, concurrent
operator control and provider TLS trust must be independently qualified.
The caller must supply an exclusive connected `pg` 8.16.3 Client; after
admission the library closes it on every result. On validation failure before
admission, the caller retains responsibility for the connection.

PostgreSQL 17 normally restricts setting `log_parameter_max_length` to a
superuser or a role granted SET on that parameter. If the exact session cannot
set both limits, the transaction refuses before transmitting the envelope. The
synthetic test grants that permission only inside its disposable cluster; this
project does not grant it on the managed service. Whether the managed operator
can or should receive that privilege is unverified.

These limits suppress PostgreSQL's ordinary **bind-parameter** logging, not all
logging. In a synthetic test, an intentional CHECK failure still caused the
server to include part of the failing bytea row in an error DETAIL despite both
limits being zero. Provider and proxy logs, audit extensions, statement/error
details, driver instrumentation, pre-existing logs, and their access and
retention policies are outside this library's control. Ciphertext is not
plaintext, but its retention and custody still require an independent reviewed
control before any real staging call; the component makes no no-logs claim.

`plan` has exactly these top-level fields:

```
format: "collect.pg-quarantine-plan.v1"
project_ref: "rrlduytparvsjfmegalh"
operation_id, source_batch_id: UUID strings
source_identity_sha256, source_set_sha256, source_snapshot_hmac: 64 lowercase hex characters
target: {kind, host, port, database, baseline_manifest_sha256, source_sha256,
         epoch, fence_operation_id, profile_sha256}
relations: [{source_schema, source_table, target_schema, target_table,
             columns: [{source, target, type}],
             key: [{source, target}], mapping_sha256}]
```

The per-relation schemas are restricted to `app`, `private`, `collect_sms`
and `auth`. `type` is descriptive metadata and never interpolated as SQL.
The key pairs must appear in the column mapping. Canonical plans are capped at
65,536 bytes and bounded in nesting and collection size; plaintext batches are
limited to 1–4,194,304 bytes. The source set, snapshots and
individual mapping digests must be independently captured and reviewed; prefer
a keyed digest for low-entropy private mappings. `planDigest(plan)` is a
review helper, not approval. Pass the separately retained digest as
`expectedPlanSha256` together with `plan`, `envelope`, and the 32-byte `key`.
The caller must protect the reviewed plan and key independently.

Returned objects contain only an aggregate status and explicit false flags for
business import, identity resolution and cutover. Encrypted buffers and keys
remain sensitive. Temporary decrypted Buffers are overwritten after validation,
including GCM authentication failure, but Node, PostgreSQL, crash dumps, swap,
process inspection and the caller's original plaintext cannot be reliably
erased by this library. Trusted process, database and key custody are necessary.

## Verification

From the active repository root:

```sh
node --test --test-concurrency=1 scripts/supabase/current-pg-transfer/batch-transfer/quarantine.test.mjs
```

The test creates a fresh PG17 cluster in a private temporary directory, listens
only on its private Unix socket, uses a non-superuser/no-bypass-RLS `postgres`
owner and synthetic data, and tears it down. `COLLECT_SYNTHETIC_PG_BIN` may
point to a different local PG17 toolchain. It uses the existing pinned `pg`
8.16.3 driver, without installing dependencies or accessing live systems.

It exercises exact replay, changed contents under the same operation, unique
source-batch collisions, concurrent identical and conflicting claims, rollback
before commit, both lost and unsent COMMIT acknowledgements, fresh readback,
fence/profile/trigger drift, authenticated encryption and redacted output.
The tests do not establish managed privilege compatibility, retention coverage,
source authenticity, mapping authority, financial invariants or production
recovery. A future domain importer still needs reviewed identity decisions,
complete business/partial-key and FK checks, target preimage and postimage
verification, graph ordering, object journals, exact replay, uncertain-commit
reconciliation and authorization for each write.
