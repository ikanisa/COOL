# Android background sender — local T12 evidence

The internal gateway now reconstructs the signed backend and durable journal in a
bounded, nonexported JobScheduler service. The handset starts locally paused.
An explicit “Allow governed dispatch” intent clears only that local pause after
exact enrollment and configured-host checks. Every receipt still needs the
backend’s current mode, limits, fresh device observations, live lease/fence,
backend-derived grant and original final-arm acknowledgement. No hosted change,
real device, key creation or SMS was performed.

The current source passes 38 focused native recovery tests and compilation of
the entire internal_gateway source against cached Android36, matching Flutter
embedding and lifecycle APIs. Source and cached-binary drift are empty.
`native-uat/` preserves the runner, helpers, shims and source bytes captured before
imports/execution. These tests use synthetic keys/AES and filesystem shims.
They do not execute Android Keystore, OS scheduling, a carrier or SmsManager.

The preceding complete native run passed151 tests. Five later file changes add
read-target rotation and its integration test; those affected suites pass38
in the final run. `prior-native-attempt2/` remains a preceding-byte proof,
not a fresh151-case claim for the final bytes. `prior-native-attempt1/` preserves
an earlier149-case run. All three include full native API compilation.

The parent’s scoped Flutter integration retained455 positive tests and one
fixture failure: the large-text test leaked a SemanticsHandle after its layout
assertions passed. The owned test now disposes that handle in an explicit
try/finally. The affected file then passed20 tests and focused analysis on
unchanged captured inputs. Both raw runs are retained. This packet does not
invent a new456-case aggregate. The gateway uses existing Collect tokens and
components; no visual-fidelity or full design-acceptance claim is made.

Cancellation shares a barrier with actual invocation admission. Arm HTTP runs
outside the journal lock so emergency pause can persist while it is pending.
A newer pause/close invalidates older queued Allow intents. The cycle checks
stop again after heartbeat and before consuming a grant. Restart preserves a
reserved/unknown invocation and reconciles its original UUID instead of sending
again. Health and reconciliation remain available while locally paused.

Each recovery batch allows at most two original-request reads plus two callback
uploads. The read cursor rotates retained unknown UUIDs and is saved as bounded
JobScheduler metadata. A crash may repeat safe reads; it never replays a saved
mutation or restores a grant/arm’s body or send authority. Unknown records and
late callbacks remain retained. Capacity exhaustion fails closed.

Only the internal_gateway source manifest adds the persisted service and boot
permission. Production source excludes gateway code and SMS/phone/boot
permissions. This is source/API evidence; merged-manifest, Gradle/lint/APK,
signature and release-artifact checks remain pending. Existing offline Gradle
readiness already failed to complete in its bounded prior attempt; this slice
did not repeat that unrelated dependency attempt.

The schedule uses bounded backoff and opportunistic Android job execution.
Physical boot, Doze/force-stop, restart/power-loss, permission/SIM and carrier
validation remain open. An already admitted carrier invocation cannot be
retracted by a subsequent pause. The terminal-attempt server archive ACK is
still unavailable, and callback observations never establish carrier delivery.
The exact remaining work and current source hashes are in `completion.json`.

The read-only AI team review in `review.json` reports its narrow scope and fixes;
it is not external certification. The unchanged Task09–10 SQL/Edge proof remains
in the separate sealed `../android-dispatch-authority/` packet.
