# Final frozen Gateway native candidate — attempt 176

Status: **PASS for the captured local unsigned Gateway candidate**.

The retained native export received exactly five stronger candidate runtime/test
files, preserving its prior bytes in `before-native-overlay`. The final Android
map contains 80 files. Every candidate Android hash matches the accepted export
except the owned Gradle adapter, whose final SHA-256 is
`266d289dd88f97fd0e06ed4f98abdf8c178560c0131ef8ce041d5a38a26d4e13`.

## Executed proof

- One offline cached Gateway Release assemble/lint and selected Debug JVM
  invocation passed in 337.07 seconds; 40 tasks executed and 735 were cached.
- Actual Gradle `GatewaySafetyTest` and `GatewayDispatchArmTest`: **41 passed**,
  zero failures, errors or skips. The worker classpath uses the pinned real
  `org.json:json:20250517` test dependency.
- The existing standalone dispatch/archive harness passed **124 tests**, including
  SIM binding, fresh pre-invocation clock/arm/grant checks and V2 archive/dispatch
  fixtures. Its real Android API compilation also passed in the same harness.
- Release lint: **zero errors, 40 warnings**. These warnings remain recorded in
  `lint-warnings.json`; this receipt does not claim a warning-free build.
- Captured Flutter intermediates remained byte-identical. Flutter compilation,
  pub resolution and dependency graph generation were not rerun.

The previously accepted attempt 175 exact 48 real-JSON cases and attempt 174
50 passing controls remain separate dated evidence. No unified 98-case final
Gradle run is claimed.

## Final APK

Path:
`/Users/jeanbosco/Library/Caches/collect-native-hygiene-20260930/artifacts-final-gateway-attempt176/app-internal_gateway-release-unsigned.apk`

- SHA-256: `a9fe16524f3b13f7bc85b40efb00875ab44bb17925a97163e5d9a12c364c3f1e`
- Size: 82,297,842 bytes.
- Inter bytes match source SHA-256
  `29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031`.
- No Aeonik payload/family, no `POST_NOTIFICATIONS`, and neither notification
  plugin is present in DEX. The unchanged adapter preserves non-Gateway plugin
  registration and Firebase Core, as established in attempt 173.
- The local unsigned QA marker is present; signature readback confirms the APK
  is unsigned. Its expected verifier exit code of 1 is recorded explicitly.

## Handover inputs

- `verification.json`: terminal package, source and test receipt.
- `execution.json`: exact commands, elapsed times and log hashes.
- `final-flat-native-inputs-after.json`: the final flat Android source map required
  by the frozen-source packager.
- `exact-candidate-native-overlay.json`: five unchanged candidate file overlays.
- `standalone-dispatch-archive/validation.json`: existing harness receipt and
  exact source hashes.
- `jvm-test-results`: actual selected Gradle JUnit XML.

This acceptance applies to the frozen captured candidate and owned Gradle
corrections. Later co-resident backend, MCP, Gateway or test changes in the shared
checkout are outside this artifact. It provides no production/iOS, physical
device, provider, signing, store or deployment acceptance. Session 14431 is
terminal; no owned native runner remains.
