# Protected-object transfer coordinator

This is a **synthetic-qualified, locally journaled coordinator**, not a live
Supabase migration or a complete protected-object importer. `transferObject`
hard-refuses plans in `managed` mode before creating a journal or calling an
adapter. A managed Storage HTTP adapter candidate is included, but its managed
methods also refuse before credentials, metadata or network access. There is no
qualified production adapter, credential supervisor, database importer, fence
attestation or cutover path here. The owner-selected
destination remains the existing production project; no hosted staging service
is involved.

The library takes trusted, explicitly supplied adapters; they are executable
code and can perform arbitrary work. The synthetic-plan endpoint checks and the
included loopback adapter are accidental-use controls, **not** a sandbox. In
particular, a callback could ignore its supplied endpoint, signal, or claimed
create-only behavior. The included synthetic adapters restrict their HTTP
requests to a plan-pinned loopback endpoint. The implementation does not acquire
or persist provider credentials: a future reviewed supervisor must supply them
privately, avoid logs, verify roles, and enforce the actual request and provider
scope. This library is not evidence that any given credential is safe or that
provider/proxy logs are redacted.

## Synthetic owner-scope calculation

`scope-rebind.mjs` calculates a candidate metadata rebind in memory for the
observed SMS-receipt and payment-evidence descriptor shapes. It accepts only a
canonical JSON plan with an independently supplied SHA-256 and `mode` set to
`synthetic`. The plan includes an explicit source/target owner mapping and a
decision-reference digest, the original reservation descriptor and fingerprint,
the committed put intent, and the matching object metadata. The calculation
checks the original hashes, matching scopes and metadata, object key, AAD,
plaintext digest and key identifier. It then calculates new reservation,
intent and private application-object fingerprints for the proposed owner while
retaining the original object key, ciphertext digest, size, AAD, request digest
and operation ID. The returned object is frozen and always has
`writeAuthorized: false`. The mode field does not prove that caller-supplied
data is synthetic.

This is a calculation, not a migration procedure. The supplied decision digest
and source values are assertions, not proof of identity, approval, actual
database contents, stored ciphertext, encryption-key compatibility, a stable
source snapshot or device replay. It cannot determine whether preserving the
request digest remains appropriate after other identity or source changes. It
does not inspect all journal fields, locks, triggers, authorizations, related
rows or provider-side metadata; it writes nothing and must not be used as
permission to rewrite live metadata. The plan and result contain private
identifiers and must stay in trusted memory. Its focused synthetic checks run
with:

```sh
node --test scripts/supabase/current-pg-transfer/object-transfer/scope-rebind.test.mjs
```

## Contract

`planDigest(plan)` computes a SHA-256 of bounded, recursively key-sorted compact
JSON. `transferObject({plan, expectedPlanSha256, journalRoot, journalKey,
source, target, requestMs})` requires the independently reviewed digest, a
32-byte journal key, an existing physically addressed 0700 directory owned by
the current user, and trusted adapters. `requestMs` defaults to 30 seconds and
is restricted to 1–30,000 ms per call. The current plan shape is:

```text
format: "collect.protected-object-transfer.v1"
operation_id: UUID v4
mode: "synthetic" ("managed" plans cannot be sent or reconciled)
source: {origin, bucket, key, object_id, version, etag, bytes,
         ciphertext_sha256, namespace_sha256, binding_sha256, key_aad_sha256}
target: {origin, bucket, key, namespace_sha256, key_aad_sha256}
authority: {source_identity_sha256, target_identity_sha256,
            source_fence_sha256, target_fence_sha256, mapping_sha256}
```

The source and target must be different object locations; names and keys are
bounded, and selected bytes are 1–8,000,000 bytes. The key/AAD hashes must
match, but they are assertions: this code does **not** hold the encryption key,
decrypt a payload, validate AAD, verify a principal mapping, inspect Storage
tables, or prove the source and target key material is compatible. The SHA-256
is of the exact protected ciphertext bytes, never a decrypted SMS-body or
application-payload hash. The source database object version and the ETag are
distinct preimages, and neither is assumed to be a content hash. Supabase's
[S3 compatibility documentation](https://supabase.com/docs/guides/storage/s3/compatibility)
states bucket S3 versioning is not enabled. Its [standard-upload documentation](https://supabase.com/docs/guides/storage/uploads/standard-uploads)
describes refusing an existing object by default unless upsert is enabled; an
actual target implementation and concurrent-create behavior still require
qualification on the chosen deployment.

The adapters receive an `AbortSignal` and must verify their own endpoint and
authority before every operation, independently enforce a network and response
size bound, and ensure `createOnly` is atomic with respect to all writers.
`source.read({signal})` returns all `source` fields, `identity_sha256`,
`fence_sha256` and a Buffer `body`; `source.inspect({signal})` returns the same
fields without the body. `target.inspect({signal})` returns its plan origin,
bucket, key, namespace digest, target identity and fence digests,
`private_bucket:true`, and either `state:'absent', absence_verified:true` or
`state:'present'` with `object_id`, `version`, `etag` and Buffer `body`.
`target.createOnly(bytes,{signal})` performs one atomic create-if-absent and
returns `{accepted:true}` only for an acknowledged create. Any other outcome,
including an error, timeout, conflict or malformed result, is unconfirmed.
Adapters and their authority evidence are trusted inputs, not independently
attested by this component. A preflight absence check alone cannot protect
against an independent writer; target create-only atomicity is mandatory.

`supabase-adapter.mjs` now supplies candidate source/target adapters. The
managed factory pins the target to the named Supabase project and requires a
reviewed plan digest, but all of its methods fail closed before invoking the
credential or metadata callbacks. The synthetic factory runs the same HTTP
logic only against plan-pinned `127.0.0.1` HTTP endpoints. It accepts a
`credentialSource` returning a private Buffer and a `metadataSource` callback;
neither is a verified production supervisor or source of authority. Credentials
are not written to the journal, though Node's HTTP header strings cannot be
reliably erased. A credential fingerprint is retained only in the adapter's
memory and changes within that instance cause refusal.

For a source, the metadata callback returns the exact source-plan fields plus
`identity_sha256` and `fence_sha256`. For a target, it returns `origin`,
`bucket`, `key`, `namespace_sha256`, `identity_sha256`, `fence_sha256`, and
`state`; a present object additionally needs `object_id`, `version`, `etag`,
and `bytes`. These are assertions from that callback, not verified database or
fence observations. The candidate brackets body reads with metadata checks,
verifies the private bucket, checks HEAD/GET size and ETag, and compares source
ciphertext to the reviewed SHA-256. Creates use `POST` with `x-upsert:false`,
and a 2xx still requires independent metadata and exact-byte readback before
the adapter reports acceptance. Conflicts, redirects, timeouts, malformed or
oversized responses, changed credentials and uncertain readbacks do not trigger
an automatic retry.

The HTTP implementation uses Node's built-in client with no proxy agent,
automatic redirects, retry, custom CA or configurable fetch hook. HTTPS forces
certificate validation and the plan-pinned hostname. A synthetic self-signed
loopback TLS server was rejected; that does not test a valid hosted certificate,
managed networking, trusted system roots, a production role or provider logs.
The TLS test requires an `openssl` executable; it generates and removes its
own short-lived synthetic key and certificate in a private temporary directory.

Before reading credentials or issuing HTTP, the candidate rejects observable
Node preload/debug/CA settings, dynamic-loader and TLS environment variables,
proxy variables, explicit preload/loader arguments, and Node's loaded extra-CA
set. Bucket and Storage error JSON are bounded and reject duplicate keys,
including escaped aliases and duplicates in nested objects, before their
identity or visibility fields are used. These checks do not prove a clean
process: a preload or native loader can execute before this code and alter the
environment or runtime. A trusted launcher must therefore start the reviewed
Node binary in a clean environment, with reviewed system trust, no preload or
debugging options, and protected stdout/stderr **before** making any credential
available. That launcher and its end-to-end custody remain unimplemented.

After a fresh operation directory and encrypted intent are fsynced, the
coordinator checks source metadata and ciphertext, rechecks the source, and
requires a verified private target with the key absent. It fsyncs an encrypted
attempt marker **before** the sole `createOnly` invocation. After an acknowledged
create, it rechecks source metadata and verifies target ciphertext bytes before
writing and fsyncing an encrypted `content_verified` outcome. A preexisting
object is classified as a conflict only after its identity, fence, private
namespace, object metadata and bounded body are verified by the adapter; an
incomplete observation is refused. This outcome does
not establish a cross-service snapshot, provider atomicity, decryptability,
application metadata commit, restored access or production cutover. A target
object found before dispatch is a conflict even if its bytes match.

An existing operation directory always returns `reconcile_required` without a
new upload. If dispatch or its acknowledgement is uncertain, or a post-send
check/journal write fails, the outcome is `dispatch_unconfirmed`; no automatic
retry is attempted. `reconcileObject(...)` uses only `source.inspect` and
`target.inspect`, decrypts and verifies the stored plan and attempt marker, and
performs no journal writes. A matching object yields
`matching_content_at_readback` **without creation attribution**. An absent
readback is just `absent_at_readback`: an earlier timed-out request may still
commit, so neither result authorizes retry. Verify the original process and
provider outcome before any separately designed recovery action.

Journal records use AES-256-GCM with fresh random nonces and bind the operation
ID and record name as associated data. Directories, file ownership, mode,
symlinks, file replacement, exclusive creation and fsync are checked using the
existing private-archive helpers. The journal key, exact reviewed plan and its
independent digest require separate protected custody; losing the key can make
readback impossible. Process inspection, swap, immutable JavaScript strings,
host compromise, same-user races and storage-device failure remain outside the
library's protection. A timed-out, uncooperative adapter can continue after the
function returns. Its upload buffer is held intact until that adapter's promise
settles to avoid corrupting a late request; a permanently hung adapter can retain
up to one bounded object buffer per unsettled operation.

## Verification

```sh
node --test --test-concurrency=1 scripts/supabase/current-pg-transfer/object-transfer/supabase-adapter.test.mjs scripts/supabase/current-pg-transfer/object-transfer/transfer.test.mjs
```

The suite uses fake records, private temporary directories and ephemeral
loopback HTTP/TLS servers. It covers exact copies, existing-key refusal, concurrent
same/different operation IDs, source or target drift, journal tampering,
unconfirmed responses, a late send after timeout, process death after a server
receives an upload, and read-only reconciliation without a second write. The
coordinator-only loopback server enforces `If-None-Match: *`; the separate
Supabase-shaped fake exercises `x-upsert:false`. Neither is a Supabase server,
so the tests do not establish real Supabase concurrency or response semantics.

Before production integration, at minimum: finish and independently verify the
source/target fence and writer-exclusion procedure; bind a reviewed real plan
and cloud-primary principal mapping to actual metadata; implement and test a
scoped managed Storage adapter and private credential supervisor; verify exact
provider read/create semantics and logs; verify decryption/key/AAD compatibility;
implement atomic application reservation/intent/object and receipt graph writes;
classify retention and recovery; and prove restart, unknown-outcome reconciliation,
and end-to-end recovery with real managed roles and authorized live checks. The
current coordinator performs none of those production steps.
