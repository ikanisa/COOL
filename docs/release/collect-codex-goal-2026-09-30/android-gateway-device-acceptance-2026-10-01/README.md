# Android Gateway device acceptance — current local evidence

The corrected current Kotlin suite passed **39/39**. The new read-only device
runner passed **9 synthetic safety/parser tests**, and the no-send probe passed
**5 synthetic tests** with clean three-file Flutter analysis. These are separate
scoped executions, not one physical or whole-release acceptance run.

Actual ADB discovery found **zero targets**. No organization-owned handset or
emulator was available. No Android Keystore, installed signing/enrollment,
network/SIM/radio, physical crash or carrier/callback acceptance was executed.
No SMS, backend call, device mutation, permission grant or account provisioning
occurred. Production acceptance remains false.

## Actual correction and tests

`android/app/src/test/kotlin/app/cool/mobile/gateway/GatewayTransportTest.kt`
previously assumed the fake connection started within a 50 ms deadline. The
first current run compiled and executed 38 tests, with one failure because its
connection count was zero when the deadline expired before I/O began. That raw
failed attempt is retained in `native-jvm-attempt1`.

The timeout test now synchronizes the fake output-start seam before asserting
timeout disconnection, uses a bounded caller and verifies exactly one request.
A new test holds a synthetic signer through the deadline and proves no connection
can open after abandonment, including a following request on the same worker.
Production transport and all other gateway runtime sources were preserved.
`native-jvm-attempt2` contains the actual final compile, JUnit `OK (39 tests)`
result, exact copied source and pinned cached dependency hashes. Backend and
sender seams are fake; no HTTPS or Android sender is invoked by these tests.

`scripts/android_gateway_device_acceptance.py` executes only bounded read-only
ADB/APK inspection commands. It refuses missing, unauthorized, ambiguous,
emulated and unverified hardware targets; it has no emulator fallback, install,
permission grant, data clearing, logcat, enrollment or send command. Reports
contain hashed serials and strict projections rather than raw device/package
output. APK inspection requires the restricted package/launcher, expected
permission declarations and one verified APK signer. It does not attest
installed-artifact parity or store signing. Nine synthetic tests cover the
refusals, command limits, independent unknown/denied permissions and privacy.
`actual-device-preflight.json` is the real empty ADB result.

The new `integration_test/gateway_device_no_send_test.dart` uses the actual
`gatewayMain` entrypoint selected by `GatewayActivity`. Its shared test-only
probe invokes only initialize, identity twice and status. A configured or
unpaused build is refused. It checks stable public identity and bounded public
key hash, preserving independent local observations and redacting installation
ID/key/SPKI values and malformed-input errors. It never requests permissions,
heartbeats, reconciles, provisions or dispatches. Initialization may create local
test-installation Keystore metadata when the real device test is eventually run.
Its five **synthetic** safety cases do not prove Keystore behavior. An initial
three-import lint failure and the earlier four-case scope are retained separately.

## Bounded packaging readiness

A new source06-derived exact workcopy was prepared at
`/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-gateway-build-07`.
Its 1,905 selected source files matched pristine source06, external manifest SHA
`3dde2f704488a7a18d7d9f916f2451d76a8662bb79619b788d792706d11ba42f`.
The earlier source06/build06 and their packet were left intact. Only generated
public SDK metadata and previously verified offline package/plugin bindings were
rebased inside this separate workspace.

One `:app:dependencies` check for `internal_gatewayDebugRuntimeClasspath` used
offline mode, no daemon, two workers, a bounded 1 GiB JVM, existing unsigned QA
mode and an explicitly empty native gateway host. It reached its **120-second
deadline**, exited 143 after task-owned termination, and produced no
`BUILD SUCCESSFUL` marker. All selected source hashes remained unchanged.
There was no observed dependency-resolution failure message, which does **not**
establish resolved dependencies. Graph readiness remains unverified. No APK
compile, installation, signer-key read or retry followed. The raw command/output,
generated-binding hashes, deadline and source readback are retained in
`offline-gradle-readiness.*`.

This workcopy is an exact source06 dependency prerequisite, not a current-source
APK and not an executed native smoke target. Its generated bindings are separate
from immutable source06. The new probe and Kotlin test correction will require
their own later source/build binding before device acceptance.

## Remaining practical gates

Connect an unlocked organization-owned test handset with USB debugging
authorized, then rerun the read-only runner to a fresh output. Follow
`DEVICE_ACCEPTANCE.md` for exact non-enrolled test-installation/signing guards,
the local-only probe and independent real permission/network/SIM/radio states.
Retain actual public signing parity and Android/Keystore/process-restart evidence;
never infer them from synthetic tests or an emulator. Full APK packaging,
reviewed gateway dependency graph, hosted enrollment/current authority,
controlled power-loss/Keystore failure, real multipart/callback/provider evidence,
privacy/MDM/retention, installed Revolut comparator/accessibility evidence and
owner release approval remain open. Real SMS/carrier testing requires its own
controlled authorized stage and was not performed here.

`verification.json`, copied current sources and `MANIFEST.json` bind this packet.
All physical, carrier, deployment, trust/freeze and production approval flags
remain false. Earlier gateway/API/widget evidence is historical and is not
aggregated into the counts above.
