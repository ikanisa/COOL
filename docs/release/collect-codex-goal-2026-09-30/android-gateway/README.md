# Internal Android gateway implementation

> Owner scope amended 1 October 2026: use revolut-design directly as the sole design skill. The separate mandatory mobile checklist and its gates were removed. Changed package bytes are outside previous integrity attestations; dated product observations retain their original scope.

The separate `internal_gateway` flavor uses package `app.cool.mobile.gateway`,
`GatewayActivity` and `lib/main_gateway.dart` / `gatewayMain`. The member
production flavor and existing `MainActivity` retain their existing entrypoint.
The native sender checks the exact flavor. Building this flavor with the member
Dart target cannot initialize its gateway bridge.

The implementation remains unavailable for new sends: the current real backend
returns only `GATEWAY_DISPATCH_AUTHORITY_PENDING`; its heartbeat does not attest
current device activation or grant authority. The handset starts durably paused,
has no local resume/force-send control, accepts no SMS body/recipient/grant from
the Dart interface, and cannot turn the current response into a live grant.
No gateway was installed or enrolled, and no endpoint, OTP, provider or physical
SMS was invoked for this packet. This is local implementation evidence.

## Implemented boundaries

- Android Keystore creates a P-256 signing key and AES-256-GCM storage key.
  Enrollment pins installation UUID, public SPKI fingerprint and app signing
  certificate fingerprint. Matching a flavor/certificate/document does not
  establish owner activation. Changed/lost identities fail closed.
- `noBackupFilesDir` + encrypted `AtomicFile` journals retain attempt and HTTP
  request identities before the corresponding invocation/write, with explicit
  fsync and established markers. Missing/corrupt established journals refuse
  operation. Journals contain hashes/callback metadata and observed codes, not
  SMS body or destination. Keystore keys have no plaintext export/fallback.
- Every attempt records `invocation_started_at` before the one app-level
  `SmsManager.sendMultipartTextMessage` call. The final permission/SIM and grant
  expiry gates are checked again after durable I/O. An already reserved attempt
  is never invoked again, including when the framework call throws.
- Sent and delivery PendingIntents are explicit, immutable, one-shot and
  independently correlated by device, attempt, fence, segment, stable callback
  UUID and private nonce. Their manifest receiver is non-exported. Generic or
  contradictory callbacks remain unknown; missing segments remain pending.
  Pausing does not discard evidence for prior attempts.
- SMS permission, phone-state permission, Internet connectivity/validation,
  selected SMS subscription, SIM readiness and telephony service are separate
  observations. A network connection is no carrier proof. The SIM revision hash
  describes a local Android subscription selection, not ownership or an ICCID.
- Requests authenticate exact UTF8 envelope bytes with DER ECDSA/SHA256 and the
  SPKI fingerprint. The host is exactly
  `lhbowpbcpwoiparwnwgt.supabase.co`; the endpoint is
  `/functions/v1/collect-android-gateway`. No member/operator JWT, Supabase
  service key or arbitrary host/RPC is stored on the handset. Redirects are
  disabled; request/response limits are 32/64 KiB, HTTP connect/read limits are
  seven seconds and the request/signing task deadline is fifteen seconds.
- An uncertain HTTP mutation retains its original request UUID and exact request
  digest in encrypted storage. Manual reconciliation reads those original UUIDs;
  it validates the recorded action/result before acknowledging them, and never
  replays a mutation. At most four reads/new callback reports occur per manual
  action. There is no scheduler, automatic retry, background send loop or gateway boot
  receiver. The full dependency-merged manifest remains unverified. The native action may take up to sixty seconds; its UI timeout is
  sixty-five seconds. Emergency pause bypasses queued network work.
- The narrow UI displays separate observations and aggregate evidence, permits
  permission review, public-identity copy and installation-bound enrollment
  document application, and keeps emergency pause available during loading or
  failure. It does not expose private keys, tokens, numbers, body text, arbitrary
  grants or arbitrary backend configuration. A provisioned document remains
  locally pending; server activation/revocation is unknown under the initial DTO.

The shared wire authority is
[`../android-gateway-identity/CONTRACT.md`](../android-gateway-identity/CONTRACT.md).
The native adapter strictly projects the current refusal-only contract. A later
grant/authority DTO requires a coordinated backend and handset change; the
present bridge deliberately refuses arbitrary future successful grant objects.

## Build and checks

Use the pinned installed Flutter SDK and the explicit gateway target:

```sh
flutter build apk --debug --no-pub --flavor internal_gateway --target lib/main_gateway.dart
```

The public Gradle property `collectGatewayHost` defaults to empty, keeping
gateway network access unavailable. A future governed enrollment build can use
the exact approved host; every other value is rejected. The property is not a
credential or activation. Use the existing explicit `collectUnsignedLocalQa`
property for source-only QA builds; store signing is a separate gate.

Offline JVM checks compile actual pure production source with cached Kotlin
2.3.20, JUnit 4.13.2 and the test-only cached JSON parser. Their fake backend,
fake HTTPS connections and fake sender perform no network or SMS operation:

```sh
python3 docs/release/collect-codex-goal-2026-09-30/android-gateway/run_native_checks.py --packet /absolute/new-evidence-directory
python3 docs/release/collect-codex-goal-2026-09-30/android-gateway/run_android_api_checks.py --packet /absolute/new-api-evidence-directory
flutter test --no-pub --concurrency=1 test/gateway --reporter expanded
flutter analyze --no-pub lib/gateway lib/main_gateway.dart test/gateway
make revolut-design-authority
```

Each JVM/API attempt retains source snapshots, hashes, actual command, dependency
hashes, exit status and output. The API compile uses real cached Android36 and
Flutter engine APIs plus an explicitly labeled BuildConfig flavor stub; it
cannot establish APK packaging or Android execution. Failed/time-bounded attempts
are retained beside passing attempts. `verification.json` records final results.

## Retained final verification

`verification.json` binds the current source to these actual offline results:

- `jvm-attempt08`: **38/38** tests pass (22 journal/dispatch/crypto,
  11 strict wire/timestamp, five bounded fake-HTTPS transport tests).
- `flutter-final04`: **18/18** pass (nine safety/model/UI, four real enrollment
  dialog lifecycle regressions, five synthetic state captures). Bundled Inter
  and SDK MaterialIcons are loaded in `captures04`; all five pixels were
  inspected. The captures are Flutter test surfaces, not installed-device proof.
- `dart-analysis-current` reports no issues; `design-authority` passes sole
  authority hygiene. Source hashes were checked after validation.
- `android-api-attempt02` compiled all 13 native files against the cached
  Android36/Flutter engine APIs. `android-api-delta01` recompiles the final three
  timestamp-normalization files against those retained classes, verifying that
  all ten remaining files and every API dependency are byte-identical. This
  current binding is an incremental API compile, with an explicit BuildConfig
  stub; it is not a clean full Gradle/APK rebuild.

The offline Gradle prerequisite attempt reached Flutter plugin Kotlin compilation
and exceeded its bound before application dependency resolution. The actual
`assembleInternal_gatewayDebug` attempt was cancelled after a selected Dart
header fix changed its source capture, before app compilation. It produced no
APK and no artifact is accepted. Both attempts and their exclusions are retained.
The gateway dependency graph is currently unreviewed/unlocked; the existing
strict production flavor locks remain unchanged. APK packaging, merged-manifest
readback, real signing and installation therefore remain open.

The four enrollment lifecycle tests retain root's controller-lifetime repair;
closing or receiving an asynchronous enrollment result does not dispose the
still-animating dialog input. No passing result from earlier reruns is added to
these final counts. Earlier Ahem-font captures and interrupted/timed-out attempts
remain evidence of those attempts and are excluded from visual comparison.

## Remaining sender acceptance

The server business-authority/grant issuer, run-bound receipt policy/caps,
activation/revocation readback and automatic operating mode are outside this
initial foundation. No public server arm issuer exists. A future sender must
accept only an authenticated server grant bound to device/job/attempt/fence,
exact destination/body hashes, segment count and expiry. The already implemented
pure engine validates those bindings and never retries an invocation reservation.

Journal retention is deliberately capped at 100 attempts and 64 HTTP mutation
receipts. Limits refuse operation. A reviewed retention/archive/reconciliation
procedure is still required before unattended service; deleting local journal
files is not a recovery procedure. Full OS crash/power-loss/Keystore-loss,
permission/SIM change, radio loss, dual SIM, multipart edge, pause/revoke race,
reboot, missing/delayed callback and handset/carrier acceptance remain open.

Android's [SmsManager documentation](https://developer.android.com/reference/android/telephony/SmsManager)
describes per-part callbacks and notes that a non-default SMS application can
cause the system to write sent messages to the SMS provider. Those OS records
have separate device privacy/retention implications. Local encrypted application
journals do not remove them. Framework sent status and delivery callbacks are
observations and do not certify recipient handset delivery.
The implementation follows [PendingIntent](https://developer.android.com/reference/android/app/PendingIntent),
[AtomicFile](https://developer.android.com/reference/android/util/AtomicFile) and
[Android Keystore](https://developer.android.com/privacy-and-security/keystore)
platform contracts; real device behavior still needs acceptance.

## Selected design authority

Only the owner-selected `revolut-design` skill is used. This native operator
utility adapts the quiet profile/settings task family from the September 2026
user desktop atlas, `DESK-014` (private original inspected). Collect keeps its
own identity and gateway operations. Light mode is an explicit Collect shared
theme adaptation; it is not proven against an equivalent current native source.
The UI uses existing Collect semantic colors/theme/spacing and `CollectHeadingText`. The standalone
gateway uses its own Navigator and has no inherited GoRouter back control.
No new palette, independent visual specification or source artwork is installed.

Loading, offline/not-enrolled, native failure, pending document, disabled network
actions, emergency pause and public enrollment dialog have implementation tests.
Installed Android screenshots, state-appropriate comparator registry bindings,
all supported orientations/keyboard/text/accessibility cases, independent visual
review and owner acceptance for this exact new artifact remain unverified.
Production readiness therefore remains open. A passing
theme-authority hygiene check does not certify visual fidelity.
