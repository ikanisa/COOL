# Source-pinned managed component capture successor

This is a separate, live-capable successor to the hard-disabled
`capture-runner.mjs`. It is intended for independent review before any
provider operation. Creating or testing it does not capture data, restore data,
or modify Supabase. The project owner has already authorized the direct
production migration; the `READ_ONLY_CAPTURE` dispatch value is a technical
guard against an accidental invocation, not a request for further approval.

The live entry point requires its own independently recorded
`LIVE-SOURCE-PINS.json` SHA-256, the existing offline compiler source pin, a
private plan and plan SHA-256, two fresh private output directories, and the
fixed dispatch value. It accepts only the specific previously observed Auth
and Storage count RESULT paths and SHA-256 values compiled into the successor.
The paths, hashes, fixed project, organization, read-only SQL, and regenerated
query are checked before the provider call. A new or copied count receipt needs
a newly reviewed successor and new pins; copying a plan alone cannot change
the authoritative count path.

At the start of an attempted capture, an exclusive mode-0600
`CAPTURE-ONCE.json` is created in the authorized count-result directory before
the plan's own `CLAIM.json`. This prevents an ordinary replay of that count
receipt, even via a second plan. It deliberately adds a sidecar to the fresh
count directory and does not modify the existing count, intent, or result
bytes. Claim, partial output and outcome must be preserved. A missing outcome
after the count claim is an unconfirmed attempt; it must never be interpreted
as proof that no provider query occurred. A local owner can manually remove a
file, so the claim is an operator safeguard rather than tamper-proof storage.

The live API token is supplied only through
`COLLECT_COMPONENT_CAPTURE_ACCESS_TOKEN`, never a command argument. It is
validated and removed from the child environment before execution. Only the
fixed Supabase HTTPS API endpoint can be called. Its project lookup precedes
one read-only capture query; there is no retry. The pinned JSON scanner rejects
duplicate decoded keys. Owned transport buffers are cleared when practical,
but runtime/TLS copies and JavaScript strings cannot be assured zeroized.
Archive and key files are separated into fresh physical, mode-0700 private
directories and written mode-0600. Independent custody is not established by
separate directory names.

The live entry point rejects all Node execution arguments and nonempty
`NODE_*`, `OPENSSL_*`, `SSL_*`, `SSLKEYLOGFILE`, `LD_*`, `DYLD_*` and proxy
environment settings; the pinned Node binary must be
launched directly under a clean, trusted environment. A preload or compromised
binary can act before process-level checks run, so those checks do not establish
the trustworthiness of the operating system or launcher. When the provider
project response contains both `ref` and `id`, each non-null identifier must
equal the exact authorized project reference.

The internal synthetic-only path cannot select a live transport, cannot pass a
token, and accepts only private `/private/tmp/collect-component-capture-test-`
paths. Before its fixture can be parsed, it writes `SYNTHETIC-ONLY.json` in
the synthetic archive directory; its plan claim and outcome also state the
synthetic mode and that no provider query occurred. Temporary fixture outputs
must not be represented as production evidence.

The offline plans and counts describe earlier point-in-time reads, not
quiescence. Catalogue and bounded row measurements are checked again by the
compiled capture query, but concurrent writers are not fenced. Auth sequence
state and Storage metadata are captured separately from application data and
from Storage object bodies. Native final ROLLBACK command completion is not
observed by the Management API adapter. Readback of an encrypted file is not a
production restore test, cross-component recovery proof, or cutover
qualification. Each actual capture must receive a separately reviewed
isolation/restore supervisor pinned to its new output hashes; the historical
supervisor cannot be pointed at these new results.

An operator invocation, after independent review and fresh source/hash checks,
uses `capture-live.mjs` with `--plan`, `--plan-sha256`, `--pins-sha256`,
`--live-pins-sha256`, `--archive-dir`, `--key-dir`, and
`--dispatch READ_ONLY_CAPTURE`. Supply all seven values explicitly. This file
does not authorize omitting any operational gate or relabeling a partial or
unconfirmed outcome as success.
