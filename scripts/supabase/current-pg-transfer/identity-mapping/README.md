# Owner identity mapping verification

This component implements a narrow, callable PostgreSQL verification for the
owner's decision that the specified local and cloud accounts are the same
person and the **existing cloud account remains primary**. It neither inserts
nor updates identities or links, migrates business rows or objects, nor copies
sessions, password material, refresh tokens or device credentials. The current
cloud `private.auth_principal_links` row is preserved. Successful verification
is not authorization to rewrite historical foreign keys or to perform cutover.

Both source and target must already be **fenced**, with the exact separately
reviewed fence, database, role and source/profile identities in the private
plan and no unsettled or uncertain fence admissions. Each side uses a
`REPEATABLE READ READ ONLY` transaction and SHARE table locks on Auth users,
application users, principal links and fence controls. The source deployment
identity is also locked and checked. The lock is recursive and acquired before
the first snapshot query. Each inspected relation must be an ordinary standalone
table with neither inherited parents nor children; the data queries also use
`ONLY`. The held table locks prevent attaching an inheritance relation during
verification. These locks can block identity writes and inheritance DDL;
they are held only for the verification and are not a full-database quiescence
proof. A schema-capable actor can replace a trigger function while the table
locks are held; its later replacement can remain invisible to a repeatable-read
snapshot. Independently enforce exclusion of every schema-capable actor across
verification and the eventual import. This component does not establish that
exclusion and reports `schema_actor_exclusion_verified: false`. The result
states only `selected_identity_snapshot_verified`, with `write_authorized:
false`; neither it nor the callback grants authority to make external writes.
The two snapshots are independently opened. Only selected identity
fields are pinned: Auth ID, email and confirmation/deletion/ban booleans; app
user ID, phone, email, public ID, access status and revision. They are not a
complete user-row or business-history preimage.

The exact current source and target Auth IDs and linked app IDs must be
identified from controlled records and bound to a reviewed private plan. The
`owner_decision` literal and `decision_reference_sha256` are assertions carried
by that plan, not cryptographic proof of the owner's instruction. An
independent supervisor must retain and verify the actual decision evidence,
identity descriptors, source-set digest and plan digest. The module requires
both linked Auth emails to match after conservative ASCII-only normalization;
this is a corroborating drift check on the owner's decision, never a rule that
matching emails alone establish identity. Suspended/deleted app users, deleted
or presently banned Auth users, missing/ambiguous links, changed selected
preimages and target key collisions fail closed.

## Two explicitly pinned read strategies

* `strict_parameter_redaction` selects the exact reviewed IDs with bound
  parameters. Before sending any ID, phone, email or public-ID parameters it
  requires transaction-local `log_parameter_max_length=0` and
  `log_parameter_max_length_on_error=0`. Current hosted `postgres` was observed
  without the SET privilege for the first superuser-context parameter. It must
  not be bypassed for this path.
* `bounded_zero_bind` sends **no bound identity values** and interpolates only
  a validated small integer limit (1–32). It reads selected fields for every
  linked user and selected app-user key fields up to `max_accounts` on **each**
  side, then compares them in memory. A count above the bound, dangling links,
  insufficient unfiltered SELECT visibility, non-text or nondeterministically
  collated identity keys, or any change from the four baseline unique user
  indexes causes refusal. Before transferring selected rows to the client,
  SQL checks a 1,024-byte raw per-row and 16,384-byte aggregate limit across
  both sides; oversized records are refused without fetching their payload. A read-only 13 November 2026 cloud catalogue check
  found those four key columns and indexes compatible; this is not an actual
  production identity verification or a guarantee they remain unchanged.

Even the zero-bind path handles real identity data in process memory and
returns it over the database connection. Its SQL contains no identity values,
not a guarantee that the provider, network proxy, crash dumps, server errors,
logging extensions or compromised host cannot retain sensitive information.
Review those controls and use a trusted local supervisor and private transport.
The secret 32-byte HMAC key is copied and wiped where feasible; JavaScript
strings, driver buffers and the caller's own key cannot be reliably erased.
Keyed fingerprints are sensitive correlation material and need protected
custody. No raw email or user ID is returned by the module's normal result.

## Integration interface

`identity.mjs` exports `identityPlanDigest(plan)`,
`inspectOwnerIdentity({sourceClient,targetClient,plan,expectedPlanSha256,key,mode,onVerified})`
and `translateOwnerAppUserId(capability,sourceAppUserId)`. Clients must be
fresh, dedicated instances of the repository-pinned `pg` client. The managed
target is restricted to the exact project direct endpoint or its session
pooler, with verified TLS and no custom CA or hostname verifier. Source is a
reviewed loopback or Unix-socket connection. A synthetic target is restricted
to fixture database/socket names; that is an accidental-use guard, not host
attestation. The caller retains responsibility for a client rejected before
admission; after both are admitted the module consumes and closes them.

A private plan has this exact outer structure (values are illustrative, not an
executable plan):

```js
{
  format: 'collect.current-pg-identity-mapping.v1',
  project_ref: 'rrlduytparvsjfmegalh',
  source_set_sha256: '<reviewed 64-hex source-set digest>',
  decision_reference_sha256: '<reviewed 64-hex decision-evidence digest>',
  owner_decision: 'same_person_keep_cloud_primary',
  read_strategy: 'bounded_zero_bind', // or strict_parameter_redaction
  max_accounts: 2,
  source: { identity: sourceIdentity, auth_user_id: '<UUID>', app_user_id: '<private ID>', record_hmac: null },
  target: { identity: targetIdentity, auth_user_id: '<UUID>', app_user_id: '<private ID>', record_hmac: null },
  statement_timeout_ms: 3000,
  total_timeout_ms: 15000
}
```

Each `identity` contains exactly `transport: {kind,host,port}`, `database`,
`session_user`, `current_user`, `project_ref`, `baseline_manifest_sha256`,
`source_sha256`, decimal-string `epoch`, `mode: 'fenced'`, `operation_id`, and
`profile_sha256` (required for the source; `null` for managed target). Values
must come from independently inspected current systems; placeholders above
are not a production configuration.

First, with both `record_hmac` fields `null`, call `inspectOwnerIdentity` with
`mode: 'capture'` and an independently checked plan digest. It returns only
keyed source/target fingerprints and non-sensitive status. Capture is not an
approval. Put those fingerprints into the private plan, independently review
and pin the resulting plan digest, reconnect both clients, and call with
`mode: 'verify'`. If supplied, `onVerified` receives an opaque capability valid
only during that callback; `translateOwnerAppUserId(capability, sourceAppUserId)`
returns the chosen existing target app ID only for the exact approved source
app ID. The capability expires on callback exit, failure or timeout. Transaction
IDs and backend IDs are checked again before rollback.

The callback and its process are **trusted integration code**, not a sandbox.
They must only construct private in-memory work and must not issue SQL on the
owned clients, dispatch provider effects or start external writes. A caller
already holding database credentials could end a transaction and write outside
this helper; the module is not a defense against such a caller. A target import
must revalidate the same plan, actual rows, mappings, catalog and fence inside
its own qualified write transaction and preserve source provenance. User ID
translation alone does not authorize changes to request hashes, cryptographic
AAD, source IDs, immutable proof fields, membership scope or financial records.

## Verification and remaining work

From the active repository root (PostgreSQL 17 binaries and a non-root OS user
are required):

```sh
node --test --test-concurrency=1 scripts/supabase/current-pg-transfer/identity-mapping/identity.test.mjs
```

The test starts a private Unix-socket PostgreSQL 17 fixture and uses synthetic
identities. It exercises the owner's explicit decision, exact links, repeated
verification, source/target changes, email mismatch, collisions, immutable-link
guard, unsettled admissions, read-only transactions, concurrent mutation,
parameter logging privilege failure, bounded zero-bind operation and catalogue
drift. For both read strategies and both sides, it also rejects existing parent
or child inheritance, checks a child committed while lock acquisition waits,
and verifies that locked relations block child writes and inheritance DDL. It
is not a real customer-data or hosted-system test. SIGKILL or host
failure can leave owned fixture evidence under the shared fixture's documented
cleanup rules.

A protected real source/target identity plan and key-providing supervisor do
not yet exist. Neither path proves simultaneous whole-database snapshots,
complete account-link/catalogue security, live Supabase transport, cross-table
mapping, pending effects, storage encryption compatibility, or provider log
custody. The actual historical data importer, durable business receipts,
per-device re-enrollment and direct-production cutover remain separate work.
