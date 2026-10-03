# Local receipt scheduler operating tools

This slice implements private preparation, explicit activation, finite status,
urgent disable and manual original-operation reconciliation for Collect's
bounded receipt-operations runner. Preparation stays inactive. The installed
Codex profile still exposes exactly its existing five read tools; this slice
does not widen that profile or change the shadow monitor.

No real launchd job was observed, installed, enabled, bootstrapped, disabled or
booted out during this proof. No hosted request, owner sign-in, Keychain access
or SMS operation was performed. The launchctl seam and owner observations in
tests are synthetic; filesystem publication and Python preparation are actual.

## Usable entrypoint

From `tools/collect-notification-mcp`, the additive package script is
`pnpm unattended:schedule`. Its implementation is
`src/unattended_schedule_cli.ts`, runnable with the pinned installed Node:

```text
/Volumes/PRO-G40/Development/Node/bin/node --experimental-strip-types src/unattended_schedule_cli.ts prepare --deployment ABSOLUTE_NEW_PRIVATE_DIRECTORY --profile ABSOLUTE_PRIVATE_ENROLLED_PROFILE --interval-seconds 60 --max-events 5
/Volumes/PRO-G40/Development/Node/bin/node --experimental-strip-types src/unattended_schedule_cli.ts status --deployment ABSOLUTE_PRIVATE_DIRECTORY
/Volumes/PRO-G40/Development/Node/bin/node --experimental-strip-types src/unattended_schedule_cli.ts activate --deployment ABSOLUTE_PRIVATE_DIRECTORY --request-id ORIGINAL_ACTIVATION_UUID
/Volumes/PRO-G40/Development/Node/bin/node --experimental-strip-types src/unattended_schedule_cli.ts disable --deployment ABSOLUTE_PRIVATE_DIRECTORY --request-id ORIGINAL_DISABLE_UUID
/Volumes/PRO-G40/Development/Node/bin/node --experimental-strip-types src/unattended_schedule_cli.ts reconcile --deployment ABSOLUTE_PRIVATE_DIRECTORY --request-id RETAINED_ORIGINAL_UUID --lookup-id DISTINCT_MANUAL_LOOKUP_UUID
```

These are command shapes, not execution receipts. Activation and disable are
actual local daemon operations when an operator explicitly invokes them.
Activation also needs a fresh verified selected email-owner session and an
authoritatively active, matching v3 enrolled profile; those live prerequisites
were not available or exercised here. No credentials are accepted in CLI
arguments or forwarded to launchctl.

Preparation requires a new mode-0700 directory and a mode-0600 metadata-only
profile, with private helper and journal paths. It binds the exact source tree,
installed Node, helper, profile, `pnpm-lock.yaml`, installed dependency bytes,
in-tree dependency link literals, wrapper and plist. It neither installs
dependencies nor creates/signs with a key. `profile_verified:false` in the
preparation manifest denotes the absence of live authority proof.

The job label is fixed to `com.ikanisa.collect.receipt-operations` in the current
user's GUI launchd domain. The gated entrypoint is `unattended_host_tick.ts`.
`RunAtLoad` and `KeepAlive` are false. StartInterval is 60–3,600 seconds and each
existing bounded tick processes at most 1–10 selected events. The private shell
wrapper verifies bound runtime hashes and link literals before importing Node
modules. Each tick also checks the exact profile/helper/activation bindings and
the durable local stop latch. Current backend principal, policy, run lease and
quota authority remain enforced by signed service operations; unattended ticks
do not load an operator GoTrue token.

## Original operations and emergency stop

An activation retains its exact UUID, 30-second deadline, preparation/profile
hashes, principal/key and owner/session evidence in an exclusive, fsynced,
read-back checkpoint before the first mutation. Separate immutable claims
precede `enable` and `bootstrap`. A timeout, process crash or uncertain daemon
response never permits mutation replay. Manual `reconcile` requires a distinct
lookup UUID and reads only the exact known job and disabled override.

Disable does not require the helper or owner credentials. It retains an
activation-bound original and publishes/readbacks a permanent local disable
latch **before even read-only daemon observation**. If launchd is unavailable,
malformed or has a conflicting job, future local ticks are blocked and no
daemon mutation occurs. The original remains unknown for manual reconciliation.
When host identity is verified, separate original claims precede `disable` and
`bootout`; neither command is repeated automatically. A second disable intent
or activation of the same retained deployment is refused. Resumption requires
a separately prepared, validated deployment.

The latch does not prove that an already running process stopped or that an
already submitted signed request failed. Exact host absence plus the disabled
override can produce `SCHEDULER_DISABLE_OBSERVED`; a loaded/running or unknown
job remains an unknown disable outcome. Status reports retained local metadata
separately from the redacted current host projection. It always reports
`cadence_verified:false` and makes no carrier-delivery claim.

## Current proof and retained predecessors

`attempt3-urgent-stop/verification.json` is the current affected receipt:

- 43/43 focused scheduler-control tests passed, with no failures, skips or
  cancellations. This includes real private temporary preparation, inactive
  gating, exact original-before-command publication, concurrency, deadline and
  persistence refusal, unknown command recovery, helper drift, redaction, and
  urgent-stop timeout/malformed/conflicting-host cases.
- TypeScript `tsc --noEmit` passed. All 91 bound source inputs, 1,608 installed
  dependency/Node files and dependency link literals were unchanged before and
  after the run. The exact command and raw safe logs are retained.
- `scope-association.json` associates the initial successful 16-test existing
  scheduler file through its unchanged 19 relative-import inputs, pinned Node,
  installed dependencies and link literals. It separately associates the
  successful 12-test Python preparer scope through its unchanged two sources.
  Neither scope was rerun. The original Python binary hash was not captured,
  so the Python association is a source association rather than a historical
  interpreter-binary attestation.

The original combined Node run failed: 56 cases contained 27 passes and 29
fixture setup failures caused by an order-sensitive identity comparison in the
new deployment reader. Its successful existing scheduler file is separately
identified, not relabeled as an aggregate pass. `attempt2` passed 40 controls
and TSC after that fix; it predates the material urgent-stop review correction.
Both original receipts remain unchanged. `setup-failure.json` retains the
earlier inventory failure against an absent package-lock file; the preparer
now binds the repository's actual `pnpm-lock.yaml` and bounded normal in-tree
pnpm dependency links.

`source/` contains read-back copies of the exact 91 final affected-run inputs.
`source-bindings.json` maps their hashes. This is a scoped implementation
checkpoint, not a reviewed production candidate, approval or whole-suite pass.
No cross-version totals are added.

## Remaining acceptance

The current broad history/candidate regression remains open after earlier
profile/signer changes and two retained incomplete timeouts. This slice does
not repeat that scope or turn the earlier 146-case history result into a
current aggregate.

Actual owner/session authority, enrolled hardware key possession, installation
and running-host behavior, scheduled cadence/restart recovery, process-stop
acceptance and deployed backend policy still require their own governed proof.
Physical Android dispatch, handset/carrier behavior, financial acceptance and
production release remain separate. These controls do not enable sending by
default, change any installed host allowlist or establish those proofs.
