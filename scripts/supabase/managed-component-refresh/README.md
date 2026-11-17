# Managed Auth and Storage count preflight

This directory contains a **count/catalogue-only**, fixed-project Management
API preflight. It has no real-data capture, restore, configuration mutation,
schema migration or automatic retry mode. Each invocation selects exactly one
of `auth` or `storage`, sends one project-identity GET and one fixed read-only
count query, and writes private aggregate evidence. It uses the repository's
existing component count compiler/parser and Management HTTPS transport. The
request contains no caller-provided SQL or database password.

`SOURCE-PINS.json` binds this operator, its tests, the two count compilers and
reference files, the shared codec/custody/transport modules, and the physical
Node executable. Supply an independently reviewed SHA-256 of the exact manifest
bytes with `--pins-sha256`. The operator verifies these sources before and
after the count request, and refuses drift. These checks do not prevent a
same-user replace-and-restore race or attest OS libraries and the running host.
The historical Auth and Storage wrappers and their receipts are unchanged.

Run under a trusted user with a clean environment. A launcher must supply the
already-authorized Management token privately in the environment variable
`COLLECT_COMPONENT_PREFLIGHT_ACCESS_TOKEN`; the only accepted command-line
token argument is the literal variable name. The operator removes the variable
from its process environment after reading it, never writes it intentionally,
and does not print it. JavaScript strings, Node/TLS/OS copies, swap and crash
reports cannot be guaranteed erased. Do not paste a token into shell history,
arguments, output or a repository file. Proxy, Node preload, alternate CA and
related environment overrides are refused; launch with a clean environment
before Node starts.

The output directory must be a **new** absolute physical child of an existing
current-owner 0700 directory outside both Collect checkouts. The operator
creates that child with mode 0700 and its files exclusively with mode 0600.
Choose a separate fresh child for each component/attempt. It records an intent
before obtaining the token or sending a request, and never overwrites an older
attempt. `COUNTS.json` is the existing parser's validated table counts and, for
Storage, anonymous per-snapshot aggregates. `RESULT.json` pins its file bytes,
canonical parsed value, query, component reference, source manifest and
request. Console output contains only paths, hashes, bounded counts and status.
Small aggregates can still be sensitive; keep all files private.

The response must have the expected schema and exact project identity. The
wrapper independently rejects duplicate JSON keys in the outer response and
in its encoded payload, extra identity fields, and inputs above the parser's
wire bound before the existing parser checks all count-specific fields. Owned
response buffers are cleared where feasible. On failure, preserve the attempt
directory and `FAILED.json`/`INTENT.json` if present; error text is restricted
to fixed codes. A lost response does not prove whether the server processed the
read, and a new attempt is never automatic.

Invocation shape after the source pin has been independently reviewed and the
token supplied privately by the trusted launcher:

```sh
/Volumes/PRO-G40/Development/Node/bin/node \
  scripts/supabase/managed-component-refresh/preflight.mjs \
  --component auth \
  --pins-sha256 REVIEWED_SOURCE_PINS_SHA256 \
  --output-dir /physical/private-parent/new-auth-preflight \
  --token-env COLLECT_COMPONENT_PREFLIGHT_ACCESS_TOKEN
```

Use `--component storage` and a different new output child for Storage. A
successful count receipt may say bounds were exceeded; that is an observation,
not permission to capture. Even an in-bounds receipt proves neither component
quiescence nor completeness of any other service. The PostgreSQL transaction
requests rollback; the Management response does not attest a native rollback
command-completion message. A later encrypted capture needs its own reviewed
source, exact current counts/reference, new request and independent custody.

Run the non-network synthetic suite from the repository root:

```sh
node --test --test-concurrency=1 scripts/supabase/managed-component-refresh/preflight.test.mjs
```

The tests inject fake project/transport responses and synthetic tokens only.
They do not contact a provider or query real Auth or Storage data. The operator
must be independently reviewed and source-frozen before any provider call.
