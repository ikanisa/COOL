# Synthetic device-commissioning receipt foundation

**Fixture only; not a production migration, route, credential, or device
transition.** `fixture-schema.sql` can be installed only by the named fixture
bootstrap user in a socket-only PostgreSQL cluster and database with the
fixture-specific names used in `fixture.test.mjs`. Those names are accidental
use guards, not an attestation that a server is trustworthy. The fixture uses
only generated synthetic values and a fixture-only target project name.

This model explores a receipt transaction required by
[`authority-transition.md`](../../../native/burimunsi/configuration/authority-transition.md).
It records a transition UUID and every declared binding: installation,
application and role; distinct source and target API, Auth and gateway
digests; source and target-primary account digests and account/group mapping;
source-fence, target-fence and reconciliation evidence digests; sealed-queue digest,
generation, revision and watermark; target device-key and approving-operator
digests; and expiry. The fixture compares JSONB values structurally; it does
not preserve original JSON bytes or detect duplicate input keys already lost by
a JSON parser.

An identical issue returns its original stored receipt; a changed binding with
the same transition ID fails. Unique constraints refuse a second transition
using the same installation generation or target key. Consumption checks the
receipt ID, installation and target key, and records one consumption request.
An identical consumption retry returns the same acknowledgement; a different
request conflicts. Status is a read-only lookup using the complete expected
binding. It returns either the stored receipt and consumption or
`absent_at_snapshot`. An absent snapshot does **not** prove an earlier
transaction cannot still commit; establish the prior transaction's outcome
before retrying after a lost acknowledgement. Issue and consumption results
become durable only when the surrounding transaction commits.

The fixture requires `READ COMMITTED`, limits first issuance to a future expiry
of at most 15 minutes, and refuses first consumption after expiry. Default
deferred constraint checks also test expiry before commit; a caller can set
constraints immediate, so those checks alone do **not** guarantee commit-time
expiry. A trusted request boundary and transaction discipline are required.
Existing committed issue and consumption results remain available for an exact
retry after expiry; the receipt itself is not thereby renewed.

## Reproduce

From the current repository root, run:

```sh
node --test --test-concurrency=1 scripts/supabase/device-commissioning/fixture.test.mjs
```

The test uses the repository's owned PostgreSQL 17 fixture helper, a private
Unix socket, generated fake records and a non-superuser fixture runtime role.
It checks the accidental-install guard, exact and conflicting replays,
different transition/key collisions, concurrent issue and consumption,
rollback, in-flight and committed status, isolation level, expiry, default
deferred commit checks, and the fixture role's denied table access. The fixture
stops and removes its owned cluster when cleanup is confirmed. These tests do
not qualify a managed Supabase role, a live deployment, device, TLS connection,
provider, or hosted logs.

## Signed protocol and synthetic transport

`protocol.mjs` implements a bounded, canonical-JSON Ed25519 protocol candidate.
The synthetic transport verifies separate operator and device signatures over
the exact action and complete binding, compares the operator and device public
key fingerprints with that binding, pins the target project, cloud-primary
account digest and three target endpoint digests, and produces target-signed
receipt and one-use acknowledgement envelopes. A copied request cannot be
changed to a different action, account, custody binding or device key without
new signatures. Operators and devices must use different keys, and the target
signing key must be different from both. `verifyEnvelope` verifies a signature
and key identifier only: it does not establish receipt freshness, accepted
account or endpoint identity, or source/target authority on its own.

`synthetic-transport.mjs` accepts only the literal fake project and
`https://synthetic-only.invalid/commissioning/v1`; the exported production
transport always returns 503. The synthetic handler enforces exact field sets,
canonical UTF-8 JSON, a 16 KiB body limit, body-read and adapter deadlines,
separate signature domains, a maximum 15-minute initial lifetime, and a
non-cacheable response. A timeout or failed commit acknowledgement returns
`unconfirmed`; a signed, authenticated status request reads the stored result.
An absent snapshot does not prove a prior transaction cannot still commit.
After expiry, status remains available but issue and consume fail closed.

The test-only adapter stores signed bytes in an owned PostgreSQL fixture
transaction so the same transition and consume request return the same
envelopes after commit, including concurrent requests and lost acknowledgements.
The tests also check denial of altered bindings, duplicate/noncanonical JSON,
wrong signatures, other routes, oversized or stalled bodies, unknown commit
responses, and timestamp expiry. The handler rechecks expiry immediately before
reporting an issue or consumption success; if the operation committed but the
deadline passed before its response, the outcome is `unconfirmed` and remains
available through status. This response check does not prove that the database
commit occurred before expiry: the fixture's deferred check can be forced
immediate, and a real production transaction boundary remains necessary. The
tests include Node's native Ed25519 signing
against Web Crypto verification and vice versa. The adapter is fixture code
with a test-owned privileged table; it is not a production storage adapter.

```sh
node --test --test-concurrency=1 scripts/supabase/device-commissioning/synthetic-transport.test.mjs
deno test scripts/supabase/device-commissioning/edge-smoke.test.ts
```

Local Deno also passed a synthetic full request/receipt/acknowledgement smoke
with in-memory persistence. This does not establish support in a deployed Supabase Edge runtime or Android
Keystore, nor does it establish key custody or a trusted clock. Ed25519 public
keys are raw 32-byte keys in canonical unpadded base64url, and signatures are
64-byte values in the same encoding. Production key rotation needs an
independently reviewed verifier-key history: the candidate recognizes only its
configured signing-key ID, and an old receipt cannot be recovered through a
handler configured solely with a new key.

The `authorize` callback in the synthetic handler is a test double. A valid
signature or a caller-supplied digest is not evidence that the operator has
cloud-account authority, that the source queue is sealed, that unknown effects
are resolved, or that either application fence is settled. Those claims must
be established by trusted production adapters and transaction/fencing controls
before any route is enabled. In particular, the fixture's deferred expiry
constraint can be forced immediate, and its transaction commits cannot be
atomically coupled to an independently moving source queue. The protocol code
does not approve or perform the Android authority transition.

## Required work before any production integration

- Authenticate and authorize the operator, existing cloud-primary account,
  installation and newly enrolled device key. A digest supplied to this fixture
  is merely a claim; it is not proof or a signature. Design and verify a
  target-issued, authenticated receipt and replay-safe wire protocol.
- Independently prove the source fence, settled or retained unknown effects,
  historical account/group mapping, queue seal and watermark. Implement a
  durable per-device journal and preserve new SMS in a separate held generation
  while re-enrolling. This model neither reads a real queue nor changes Android.
- Bind the operation to the actual application fence and service identity,
  restrict transaction ownership and logging, qualify hosted PostgreSQL
  role/RLS/privileges and protect against schema changes. The fixture's UUID is
  not a production bearer credential or cryptographic receipt.
- Design retention classification, subject lookup, expiry/deletion and recovery
  for any real receipt relation. The current Collect private-retention catalog
  fails closed on unclassified private tables; this fixture makes no catalog
  change and must not be installed there.
- Review and test real per-device rebind, recovery from unknown commits,
  old-authority resolution, non-financial and financial effects, and monitored
  rollout on the intended device. No current managed build hold is lifted by
  these fixture results.
