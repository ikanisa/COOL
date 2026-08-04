# Open Gate Revalidation

## Decision

The robust implementation goal remains **blocked, not failed**. The current
source and controlled local evidence remain valid through E-078, but none of
the 17 remaining RT rows can be closed truthfully from the targets,
toolchains, references, or account authority available on 2026-08-01.

This checkpoint is evidence E-079. It is deliberately a gate audit rather than
a visual, accessibility, build, or release pass.

## Reconciled open inventory

| Gate family | Open rows | Current boundary | Required next authority or state |
|---|---|---|---|
| Direct reference and final Product Design | RT-001, RT-002, RT-005, RT-007 | The 48 accepted Collect captures do not create missing Revolut Auth, OTP, amount-entry, or review references. Pattern-only and no-direct-analogue dispositions remain explicit. | User-assisted read-only Revolut capture, or accountable Product Design acceptance of the bounded no-direct-reference dispositions. |
| Spoken assistive technology | RT-020, RT-021 | Simulator/native trees, focus geometry, contribution entry, and an emulator TTS-audio-focus probe are available. Continuous human gesture traversal, utterance review, and physical confirmation are not. | Unlocked physical iPhone/Android targets and an accessibility reviewer who can perform and attest the declared VoiceOver/TalkBack flows. |
| Reliability and physical iOS | RT-027, RT-034 | Controlled emulator soak and current Simulator Camera states pass. The paired iPhone is presently visible but offline. | Stable unlocked physical targets, owner-assisted lifecycle/Camera actions, and authorized production/Play reporting. |
| Signing and upstream platform | RT-035, RT-036, RT-037 | Local payload/signature inspection and plugin source migration pass. Upload-certificate authority is absent. Flutter 3.47 is not in the official stable release list checked on 2026-08-01. | Release-owner certificate data and a released governed Flutter 3.47+ toolchain. |
| Production, store, deployment, and acceptance | RT-040 through RT-044, RT-048 | Local artifacts and fail-closed governance pass; no external mutation is authorized. | Production identities/provider authority, store accounts, deployment authority, privacy/compliance evidence, and named accountable approvals. |

The authoritative unfinished count therefore remains **17**.

## TalkBack probe disposition

A controlled `Collect_Pixel4a_API36` Android 36 emulator was used with the
fixture-only `app.cool.mobile.dev` build and TalkBack
`16.0.0.738667889`. TalkBack bound successfully, touch exploration was active,
and TTS audio focus plus an emulator recording audio track were observable.

The probe is **rejected as continuous traversal evidence**:

- ADB-injected taps activated ordinary app actions while TalkBack requested
  audio focus.
- ADB-injected one-finger swipes did not advance TalkBack accessibility focus.
- The retained observations do not establish utterance content, utterance
  order, or human swipe traversal.

Accessibility was restored to disabled with no enabled service, and the
emulator was shut down. E-064/E-073 remain the strongest accepted RT-021
evidence; this checkpoint does not broaden their scope.

## Flutter built-in Kotlin disposition

The governed SDK remains Flutter 3.44.4. The official migration guide states
that enabling `android.builtInKotlin=true` requires Flutter 3.47 or later, while
the official stable release-notes index checked on 2026-08-01 lists 3.44.0 as
the latest stable family. RT-037 is therefore release-version-gated today; a
pre-release channel is not substituted for the required governed stable
toolchain.

- Official migration guide:
  <https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers>
- Official stable release index:
  <https://docs.flutter.dev/release/release-notes>

## Exit sequence

1. Capture or disposition the missing direct Revolut Auth/OTP/amount/review
   references; then finish RT-005 and obtain the RT-007 Product Design verdict.
2. Run human continuous VoiceOver and TalkBack traversal on exact physical
   targets, retaining utterance/action/focus findings without personal data.
3. Complete the physical iOS lifecycle/Camera Settings phases and physical or
   authorized production reliability evidence.
4. After Flutter 3.47+ is officially available in the governed channel, enable
   built-in Kotlin and rerun the compatibility, APK/AAB, device, and canonical
   matrices.
5. Obtain upload-certificate, production/provider, store, deployment,
   privacy/compliance, and named acceptance authority; execute each external
   gate separately.
6. Only then rerun all final source/full evidence gates and change the two
   completion sentinels from `blocked` to `passed`.

No upload, deployment, store submission, production change, or accountable
approval occurred in E-079.
