# Bounded local scheduler storage and diagnostics

This slice extends the actual `unattended:schedule status` and prepared-host
tick path with finite storage observations, admission limits and redacted tick
evidence. New preparations send both stdout and stderr to `/dev/null`; they no
longer append every invocation to an indefinitely growing `tick.log`.

No actual launchd job was observed or controlled, and no credential, Keychain,
hosted backend or live MCP call occurred. The installed five-read profile was
not edited. Activation remains explicit and preparation stays inactive.

## Operator behavior

The existing entrypoint and strict arguments remain:

```text
pnpm unattended:schedule status --deployment ABSOLUTE_PRIVATE_PREPARED_DIRECTORY
pnpm unattended:schedule reconcile --deployment ABSOLUTE_PRIVATE_PREPARED_DIRECTORY --request-id RETAINED_ORIGINAL_UUID --lookup-id DISTINCT_LOOKUP_UUID
pnpm unattended:schedule disable --deployment ABSOLUTE_PRIVATE_PREPARED_DIRECTORY --request-id ORIGINAL_DISABLE_UUID
```

These describe usable commands; they are not host execution receipts. Updated
sources and plist bytes require a new private preparation with immutable
bindings. This slice does not rewrite old deployments or remove old log files.

Status includes `storage` with finite states, counted entries/bytes, a capacity
observation and `last_tick`. It reports no file names, paths, private contents,
native errors or stacks. A count with `complete:false` describes only the
bounded prefix actually inspected. Unknown filesystem/space observations,
invalid private records or an exhausted reserve block admission. Read-only
status still works when daemon observation times out.

The fixed local ceilings are:

| Region | Entry ceiling | Byte ceiling | Admission reserve |
| --- | ---: | ---: | ---: |
| Control originals and lookups | 512 | 1 MiB | 8 entries / 128 KiB |
| Existing action journal/history | 32,768 | 64 MiB | 256 entries / 16 MiB |
| Tick diagnostics | 32,768 | 16 MiB | 4 entries / 8 KiB |

Normal admission also needs at least 32 MiB observed available on both bound
filesystems. Journal/control records remain limited to 65,536 bytes each;
diagnostic records are limited to 2,048 bytes each. Scans are private,
descriptor/metadata bounded and return unavailable after a ten-second deadline.
Their read-only pending OS I/O may survive that deadline; this is not a promise
that a stalled filesystem process exits on time.

Normal activation and a new prepared tick check admission before effects.
Emergency disable bypasses the scanner/budget and retains its durable local
latch before daemon observation, as in the preceding sealed operating-tools
slice. Capacity is not an obstacle to plain investigation: a manual host lookup
can return the finite observation with `lookup_retained:false` when it cannot
safely append evidence. Its operation outcome remains unknown; it does not
close the original or authorize replay.

## Crash and uncertainty semantics

Each admitted tick first publishes, fsyncs and reads back a metadata-only
`diagnostics/UUID.run.json` with `started_unconfirmed`, the exact preparation
hash and principal. It then invokes the existing bounded runner once. A finite
terminal projection is appended as `UUID.closed.json`, bound to the original
start digest. These diagnostic UUIDs are local observation identifiers and
never replace business request UUIDs.

An absent, stale, malformed or unclosed observation is distinguished explicitly
from a current terminal observation. Any unconfirmed start remains visible even
when another concurrent tick has a terminal record. Unknown runner results and
errors produce `TICK_OUTCOME_UNCONFIRMED`; raw result extras are omitted. No
diagnostic is evidence of current authorization, an overall healthy scheduler,
carrier delivery or completed business work.

After runner invocation, terminal-record publication failure returns
`business_handled:null` and the bounded original business request UUID when
available. The start remains unconfirmed. Pre-invocation refusal can report
`business_handled:false`. The caller never retries the runner or creates a new
business UUID to recover a diagnostic failure; existing immutable journal and
schedule-window rules remain responsible for original-request recovery.

## Reserve bound

A maximum ten-event new batch invokes at most fourteen signed operations:
begin, list, ten ensures, backlog and complete. Each original has at most three
published journal records. Run/claim-link/closure adds at most three records.
Each history-head scan can publish at most 32 immutable segments (4,096
transitions / 128); conservatively counting both scheduler and runner-claim
scans adds 64. Two diagnostic records bring the bound to 111 publications,
plus a publication temporary at a time. At the existing 65,536-byte record
ceiling this remains below the 256-entry / 16-MiB journal reserve. Recovery's
single original lookup/closure plus conservative history scans and diagnostics
also fits that reserve. Exact source paths are bound in the final snapshot.

These are conservative admission margins, not reserved disk allocation or a
transactional global quota. Unrelated concurrent writers or actual disk failure
can still prevent publication. Stop is attempted without budget admission; no
claim is made that it can write on a physically full or failed filesystem.

## Source-bound verification

The final current receipt is `attempt3-uncertainty/verification.json`:

- 62/62 affected control tests passed; no failures, skips or cancellations.
  TypeScript checking passed. All 92 captured inputs, 1,608 installed
  dependency/Node files and dependency link literals were unchanged.
- The added cases cover capacity exhaustion and finite-prefix scanning,
  unknown/low free space, private-file tampering, scanner timeouts, stop during
  exhaustion, investigation without new evidence, started-before-run readback,
  concurrent/crashed starts, stale projections, terminal persistence failure
  and redaction.
- An actual synthetic P-256 Edge-handler → journal → runner → scheduler case
  completed five signed in-memory HTTP calls, then failed terminal publication
  on the actual private filesystem. Restart retained the same original UUID,
  backed off with still five calls, and kept the old start unconfirmed. It
  exercises the existing implementation, without hosted data or live authority.
- The changed Python preparer suite passed 12/12 in the initial run of this
  leaf. Its two source inputs are unchanged in the final snapshot and are
  associated without rerunning it. The historical Python binary hash was not
  captured before that run; `toolchain.json` records the subsequent observation
  and this precise limitation.
- The prior successful existing scheduler16 scope has unchanged nineteen
  transitive sources and the same pinned Node/dependency/link bytes. The prior
  successful log and sealed manifest are hash-associated; it was not rerun.

The first attempt's 60/61 Node result and TSC failure are retained unchanged.
They exposed a hardlink fixture pointing at the protected profile instead of
an independent journal record, a missing test type import and an overly broad
statfs seam type. `attempt2` passed 61 plus TSC, but predates the reviewed
post-invocation uncertainty correction. Neither predecessor is relabeled as
the final current result. Results from different scopes/versions are not added.

`final-source/` and `final-source-bindings.json` preserve/read back the exact 92
current affected-run inputs. The earlier `source/` and association belong to
attempt2. The new leaf does not mutate any sealed historical packet or assert
a reviewed production candidate, full current suite or production acceptance.

## Open limits

No record is evicted, silently truncated, compacted or rewritten. Diagnostic
retention is bounded by admission and remains an operational maintenance task;
canonical archival, restoration and retention acceptance remain open. Current
broad history/candidate regression also remains open from the earlier signer/
profile slice; its old 146-case result is not a current aggregate.

Actual host installation, cadence, crash/restart behavior and process-stop
acceptance still require governed host proof. A local stop latch does not prove
that in-flight signed work stopped. Deployed authority, hardware key possession,
physical Android, carrier, financial and production acceptance remain separate.
