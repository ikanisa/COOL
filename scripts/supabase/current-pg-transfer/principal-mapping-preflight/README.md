# Principal mapping: aggregate-only read-only preflight

This candidate observes one **explicitly supplied** local/cloud principal pair
under the owner's decision `same_person_keep_cloud_primary`. The existing cloud
Auth user and cloud application user are the selected target; the code does not
change either link, create or merge users, migrate rows, copy sessions or issue
provider writes. It returns aggregate counts and comparison flags only. Matching
email is corroboration of the owner's decision, never independent identity
proof or authorization to merge any other account.

The private plan must contain the four exact Auth/application IDs from controlled
evidence, the source profile digest, the owner-decision reference digest and the
source-set digest. This module does not discover which records are the same
person or prove those supplied evidence digests. No real plan, credential or
production observation was used to implement it. A separately reviewed
operator must obtain the intended connected clients and protect the plan; the
result is non-authorizing and is not a cutover or importer capability.

Each fresh, dedicated PostgreSQL 17 client is checked against its pinned
connection descriptor. The managed side is restricted to direct project host
`db.rrlduytparvsjfmegalh.supabase.co:5432`, database/session/current user
`postgres`, with the existing provider-root TLS validation and authorized peer
check. The source is a separately pinned local loopback or Unix socket. A
source deployment profile is read and its SHA-256 recomputed against the
reviewed digest. This does not attest the host, source-set contents, other
services or a cross-machine identity. Fixture socket names are accidental-use
guards, not network attestation. Live provider transport has not been tested
by this candidate.

The module opens separate repeatable-read, read-only transactions, acquires
recursive SHARE locks on the selected identity tables before each snapshot,
and checks ordinary standalone relation topology, schema/table SELECT
visibility, row security, deterministic text collations and selected column
types. Source deployment identity is also locked and checked. These locks can
briefly block identity writes or DDL. They do not establish full database or
provider quiescence, exclude every schema-capable actor or protect a later
import. Sessions are checked idle before beginning; admitted clients are
consumed and closed. Backend and transaction IDs, isolation and read-only state
are rechecked before rollback. The caller owns clients rejected before admission.

Identity values are never SQL parameters or interpolated into SQL: bounded
zero-bind reads fetch selected Auth, application and link fields for at most
`max_rows` (1–64) on each side, after server-side raw-size checks and a 32 KiB
combined raw-value cap. IDs, emails, phones and public IDs still transit the
database connection and exist in trusted process memory; JavaScript strings,
driver buffers, logs outside this process, swap and crash dumps cannot be
reliably cleared by this module. Normal results and sanitized errors include no
raw identity values. Even aggregate counts can reveal sensitive correlations
and must be handled under private custody.

Counts identify selected rows and links, dangling links, inactive selected
accounts, exact-key collisions with other cloud application users and exact
key overlaps involving unselected local application users. Selected Auth
emails use conservative ASCII lowercasing and space trimming; other cloud
Auth email matches are just counts. Uncomparable email values remain unknown.
Application-key comparisons use exact string equality under the checked
deterministic collations. These observations do not reproduce every unique
index, expression, normalization rule, cross-schema reference or business
invariant; zero counts are not proof that import will avoid every constraint.
Conflict counts are comparisons, not person counts or identity decisions.
Missing or mismatched selected records remain visible as counts; they are not
silently repaired or accepted as a safe transfer.

## Interface

`preflightPlanDigest(plan)` computes the canonical plan SHA-256.
`observePrincipalMapping({sourceClient,targetClient,plan,expectedPlanSha256})`
returns an `aggregate_observation` with `write_authorized:false`. Both clients
must already be connected using a private credential channel and must not be
shared with other work. The supervisor must independently verify the owner
decision, IDs, source-set evidence and plan digest before invoking this module.

The exact plan shape below is illustrative; placeholder identifiers are not
usable production values:

```js
{
  format: 'collect.principal-mapping-preflight.v1',
  project_ref: 'rrlduytparvsjfmegalh',
  owner_decision: 'same_person_keep_cloud_primary',
  decision_reference_sha256: '<independently reviewed 64-hex digest>',
  source_set_sha256: '<independently reviewed 64-hex digest>',
  max_rows: 32,
  statement_timeout_ms: 3000,
  total_timeout_ms: 15000,
  source: {
    kind: 'local', host: '127.0.0.1', port: 54322,
    database: 'postgres', session_user: 'postgres', current_user: 'postgres',
    profile_sha256: '<reviewed source profile digest>',
    auth_user_id: '<explicit local Auth UUID>', app_user_id: '<explicit local app ID>'
  },
  target: {
    kind: 'managed', host: 'db.rrlduytparvsjfmegalh.supabase.co', port: 5432,
    database: 'postgres', session_user: 'postgres', current_user: 'postgres',
    profile_sha256: null,
    auth_user_id: '<explicit existing cloud Auth UUID>', app_user_id: '<explicit existing cloud app ID>'
  }
}
```

The example port is illustrative; obtain the actual source descriptor from a
fresh trusted observation. Neither a SHA-256 label nor a matching email proves
the human identity decision. A later importer must independently revalidate
the actual mapping, source/target rows, catalogue, fencing, historical
references, object encryption and external effects in its own qualified path.

Run the owned synthetic PostgreSQL 17 tests from the physical checkout:

```sh
node --test --test-concurrency=1 scripts/supabase/current-pg-transfer/principal-mapping-preflight/*.test.mjs
```

Tests use invented accounts and an owned local socket-only cluster. They do not
establish live TLS, principal ownership, clean device/session state or
production readiness.
