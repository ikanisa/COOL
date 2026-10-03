# Android Gateway — required real-device evidence

The current ADB preflight found no target. None of the physical-device steps
below has been completed. The Python parser and Dart probe harness use synthetic
test inputs; their passing results are not Android Keystore, SIM, carrier or
delivery acceptance.

Use an organization-owned test handset and approved test data. Retain a dated
source manifest, actual APK hash, package/version, signing certificate hash and
redacted device evidence for every executed stage. The owner-selected
`revolut-design` skill remains the sole visual authority; this is an operations
acceptance procedure, not an alternative UI specification.

## Availability and artifact identity

Connect the unlocked handset with USB debugging authorized. Run the read-only
preflight against its explicit serial; use a new evidence output each time:

```sh
python3 scripts/android_gateway_device_acceptance.py \
  --serial <organization-test-device-serial> \
  --output <new-private-evidence-directory>/device-preflight.json
```

An emulator, unauthorized/offline target, ambiguous target list or unverified
hardware classification blocks physical acceptance. `physical_candidate` is a
device property observation, not ownership or physical-handset attestation.
Record the actual handset/organization handoff separately. The runner retains
only the serial hash and strict metadata projections; it does not retain raw
package output, logcat, contact, subscription or SMS data.

Use the restricted `internal_gateway` flavor and `GatewayActivity` entrypoint,
package `app.cool.mobile.gateway`. For the offline smoke artifact, the native
`collectGatewayHost` property must be empty. Inspect the actual APK with:

```sh
python3 scripts/android_gateway_device_acceptance.py \
  --serial <organization-test-device-serial> \
  --apk <exact-gateway-test.apk> \
  --build-tools <pinned-android-sdk>/build-tools/36.0.0 \
  --output <new-private-evidence-directory>/device-and-apk-preflight.json
```

This verifies gateway package/launcher, its required permission declarations,
absence of member receiver/call/camera permissions, the APK bytes and one APK
signer. It does not install anything or establish parity with the installed APK.
Verify installed APK/signing parity separately before acceptance. A debug or
unsigned QA artifact is not registered release/store signing evidence. Preserve
the governed installation certificate/enrollment binding; do not clear app data
or overwrite an enrolled organization installation to make a test pass.

## Native no-send smoke

`integration_test/gateway_device_no_send_test.dart` supplies the real
`gatewayMain` entrypoint selected by `GatewayActivity`. It invokes only local
`initialize`, `identity` twice and `status`. It refuses a configured or unpaused
build, verifies stable public identity and public-key hash, and emits redacted
native permission, network, SIM, radio and subscription observations through the
integration-test result. It does not invoke heartbeat, reconciliation, enrollment,
permission requests or dispatch. Initialization can create the test installation's
local Android Keystore key and public metadata; there is no backend call or SMS.

After source/build readiness and the physical target are confirmed, execute the
dedicated entrypoint with the pinned Flutter runtime and governed dependencies:

Require a dedicated non-enrolled organization test installation and compatible
reviewed signer before invoking the build/install driver. Do not run this command
against an enrolled installation, because build tools may replace its artifact.
Keep its original data and signing/enrollment evidence intact.

```sh
ORG_GRADLE_PROJECT_collectGatewayHost= \
ORG_GRADLE_PROJECT_collectUnsignedLocalQa=true \
<pinned-flutter>/bin/flutter drive --no-pub \
  --flavor internal_gateway \
  --driver test_driver/integration_test.dart \
  --target integration_test/gateway_device_no_send_test.dart \
  -d <organization-test-device-serial>
```

Keep the native host empty in the exact built variant. Retain actual command
exit, explicit completion, emitted report, source/tool hashes and installed
certificate parity. This test's identity stability is **within one process**.
It does not establish hardware-backed key attestation, process-death persistence,
power-loss durability or enrollment approval. All returned physical/carrier
acceptance flags remain false until the corresponding external evidence exists.

## Independent physical states still requiring execution

| Required evidence | Exact acceptance limit |
| --- | --- |
| SEND_SMS denied and granted through approved Android settings | Native observation must change independently; a permission grant does not authorize dispatch. No live send in this stage. |
| READ_PHONE_STATE denied and restored | Denial must not fabricate SIM/radio/selected-subscription readiness. No phone, IMSI, ICCID or recipient values in retained evidence. |
| Wi-Fi/mobile network offline, connected but unvalidated, validated | Preserve each dimension separately; Internet readiness does not prove SIM/radio/carrier or backend authority. |
| Real SIM absent/locked/ready; selected default SMS SIM; dual-SIM ambiguity | Observe native flags and real handset settings. An emulator or fake observation cannot close this gate. |
| Radio out of service/airplane mode, then service restored | Verify actual radio state independently of Wi-Fi. Status reads only, no SMS invocation. |
| Repeated local probe after process death/restart | Verify the same public installation/key/certificate and unchanged journal counters. Do not clear data; do not infer power-loss durability from a process restart. |
| Controlled crash/power loss/storage failure and Keystore loss | A separately reviewed safe fault procedure is required. Preserve uncertainty; never manufacture an empty ready journal or retry a reserved attempt. |
| Current owner enrollment/activation/revocation and server freshness | Requires the separate approved hosted authority workflow and actual typed immutable receipts. A locally installed enrollment document remains pending evidence. |
| Physical framework sent/delivery callbacks and multipart correlation | Pure Kotlin callback fixtures are unit evidence only. Real carrier/provider testing needs its own controlled authorized send stage; it is outside this no-live-send run. A callback observation alone is not attested delivery. |
| Installed UI/state/accessibility/comparator review | Use the selected skill and actual installed artifact, including dark/light, large text, permission/error/offline/empty and focus states. No visual certification follows from compilation. |
| Release signing, MDM/privacy, retention/reconciliation and operational ownership | Requires actual approved artifact/distribution/control evidence and owner acceptance. No store or production readiness claim from these tests. |

Do not resume, arm or send to obtain a green status. Current dispatch authority
remains closed. Record missing or unavailable evidence directly; checklist
existence is not checklist completion.
