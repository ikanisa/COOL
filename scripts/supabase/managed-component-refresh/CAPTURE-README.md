# Managed Auth and Storage metadata: capture candidate

This directory contains an **offline-only capture plan** and a candidate runner
for project `rrlduytparvsjfmegalh`. The runner's live entry point is hard
disabled. Its only callable execution fixture uses an internally constructed,
in-memory response and a private synthetic `/private/tmp` directory. No capture
or restore has been executed by this candidate against the provider. The source
manifest and tests must be independently reviewed before a change to that gate.
Changing the gate also changes the source hash and requires a new manifest,
tests, and review; an old manifest never qualifies changed bytes.

`capture-plan.mjs` accepts a fresh private `RESULT.json` and its independently
observed SHA-256, verifies its count and intent receipts, fixed catalogue,
source manifest, project, state, runtime, and receipt semantics, then compiles
the fixed read-only component request locally. It writes a fresh mode-0700 plan
directory with mode-0600 `PLAN.json` and `CAPTURE-REQUEST.json`. The request
contains SQL and catalogue metadata, not provider cell values or credentials.
The output's SHA-256 must be recorded independently before further use.
The production planner requires an empty Node execution-argument list and
rejects nonempty `NODE_*`, `OPENSSL_*`, `SSL_*`, `SSLKEYLOGFILE`, `LD_*`,
`DYLD_*` and proxy environment settings. Launch the
pinned binary directly with a clean environment; code preloaded before this
check or a compromised binary is outside the process's ability to police.

The runner rechecks the immutable plan, counts and request, regenerates the
query, checks the fixed endpoint and read-only transaction, and requires fresh
private, separated archive and key directories. A one-use claim is durably
written before the proposed provider operation. A successful result or a
failure/unconfirmed outcome is then recorded; an absent outcome after a claim
means the outcome is **unconfirmed**, not that the query did not happen. There
is no automatic retry or automatic deletion of partial output. Manual recovery
must preserve and inspect the original claim, partial archive, and key.

The candidate HTTPS transport pins the expected Supabase project and
organization through the project API, requires the project to be active and
healthy, prohibits redirect and proxy/preload overrides, verifies normal TLS,
bounds response size and time, checks content length, and rejects duplicate
JSON keys. It clears its owned wire-chunk buffers and returned response buffer
where practical. JavaScript strings, TLS internals and runtime copies cannot be
reliably zeroized; this is a memory-handling limit, not a claim that all
plaintext disappears. No plaintext row or token is intentionally written to a
log or file. A token would be supplied only through
`COLLECT_COMPONENT_CAPTURE_ACCESS_TOKEN`, consumed once and removed from the
runner environment. Never put its value in command arguments or evidence.

The pinned Auth and Storage archive libraries assemble and validate bounded
response data, encrypt separate AES-256-GCM archives, and read them back with
the separately stored key. Those components include sensitive Auth rows and
Storage **metadata**. Storage object bodies, service configuration, provider
infrastructure, an operational Auth restore, and cross-component consistency
are outside this capture. The libraries explicitly state that independent key
custody has not yet been established. Archives and keys require physical
separation, secure custody and independently verified ciphertext copies.

Each count and each capture is a distinct point-in-time read while the project
may be active. Counts do not prove subsequent row totals, writer exclusion or
quiescence. Auth's sequence semantics and the Management API's final ROLLBACK
command-complete status are not proven by this capture. The catalogue comes
from prior observed metadata and is rechecked by the capture SQL; it is not an
attestation of currently deployed application source. Neither this candidate,
an encrypted readback, nor an inert data-only restore qualifies production
recovery or the migration cutover.

After a real encrypted capture, its actual result, ciphertext, snapshot and key
identifiers will be new and must be independently inspected and pinned. The
historical managed restore supervisor pins older results and is not a valid
supervisor for a new capture. A separately reviewed, bounded, isolated inert
restore supervisor and cleanup proof are still needed; this directory does not
offer a restore or provider write path.
