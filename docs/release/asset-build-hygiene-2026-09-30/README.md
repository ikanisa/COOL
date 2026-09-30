# Local asset, source and build hygiene — 30 September 2026

## Completed local cleanup (L21)

The dated result is `L21-verification.json`. It binds the sources at that
execution, preserved originals and execution evidence by SHA256. The later
logout, native resource and L17 UI changes require fresh closure evidence. Its scope
is local cleanup; it grants no design, native, hosted or production acceptance.

| Change | Evidence and reason |
| --- | --- |
| Reconcile the seven original absent indexed assets | The six rw39/rw40 derivatives/originals and the diaspora screenshot were already intentionally retired from active catalogues and manifests. All 174 active approved visual assets exist and match. Missing approved files still fail; absent Git index paths are reported separately. Restoring retired product references would introduce unsupported capabilities. |
| Remove two unused Dart files | `admin_metric_card.dart` and `revolut_launcher.dart` were unreachable from all three runtime entrypoints and had no executable callers. Their exact source and hashes are retained in `removed-source/` and `removed-source.json`. The dated graph reached all 194 then-present runtime files, with no missing imports; later client additions require a fresh graph. |
| Narrow the marketing asset declaration | The six referenced Rwanda PNGs remain bundled. The two `PROMPTS*.json` files remain in the repository as provenance and are excluded from the app bundle. All 95 current declared assets/fonts/licenses have documented usage. |
| Retain necessary dependencies | Every direct dependency has runtime, test/tool or implicit SDK usage. `cupertino_icons` supplies the Cupertino icon font; `flutter_lints` supplies analyzer rules. No dependency or version was removed. |
| Refresh stale Public illustrations | Seven unchanged PNGs came from a real current Flutter release build, real routes, verified served bytes and separate visual inspection. Public captions identify interface previews with example data. `media-current/` preserves the previous native images and provenance and records exact publication hashes. |
| Preserve dated partial source evidence | The analyzer/formatter exclude only `docs/release/**/source-snapshot/**`, this packet's exact `removed-source/`, and the exact approved dated `admin-roster-reload`, browser-lifecycle and accessibility source-copy roots. Active app, test, integration, tool and vendored code stay covered; archives remain byte-identical. |

L21 affected regressions passed **76 tests**: 40 asset integrity, 11 asset
integration, 17 media provenance, 6 reachability and 2 MoMo-only negative tests.
The original L22 source SBOM and formatter scopes added 10 tests at that execution: **86 then-verified owned tests altogether**. Later supply-chain, native export and observed graph tests are reported separately. Build, schema, analyzer and decoding checks
are separate checks, not added to those test counts.

Other passed checks include full decoding of all 174 approved PNG/WebP images,
42 group concepts and 84 runtime WebP files, fixture isolation, product/source
integrity, and a genuine static Public build with 55 artifact hashes and seven
byte-identical media copies. Decoding does not approve visual design or rights.

## Public media scope and open findings

`media-current/capture-report.json` preserves the first Flutter **3.44.3** build.
`media-pinned-current/capture-report.json` records the later exact **3.44.4**
build following the mounted logout correction, with runtime fingerprint
`aa22e9fdc2826af2480d7c4e2e4563d1209f5a49cbd2277ea9a3eec994acc382`.
Native resource and L17 changes invalidate that fingerprint; its bytes remain
preserved dated evidence. Both used Chromium 151.0.7922.34. All served successful responses
are hash-bound. Remote resources were blocked before HTTP; the renderer's
default Roboto font requests are recorded explicitly. No hosted service,
provider or database was called. Fixture code is confined to the capture tool.

The fresh seven-image inspection in `media-pinned-current/visual-review.json`
explicitly corrects the earlier visual finding: Security has a visible Back
arrow; the empty Back capsule is on Terms. The direct group-detail route has an
empty painted navigation capsule; several settings headings
are painted but absent from the queried semantics tree. These are open design
and accessibility findings. The review passes only authenticity/readability and
use as clearly captioned interface illustrations. Native/design/production
acceptance flags are false. Images were not edited.

Both native recapture attempts failed during simulator creation with EPERM.
The exact commands, exit codes and CoreSimulator evidence are retained in
`native-capture-environment-failure.json`. Native acceptance remains open.
Failed browser attempts are retained separately from successful attempts 5 and 6.

## Pinned tooling and L22 progress

The exact installed `.fvmrc` SDK is
`/Volumes/PRO-G40/Development/Flutter/flutter`, Flutter 3.44.4,
revision `ad70ec4617166f1c38e5d2bfd388af71fda14f06`, Dart 3.12.2.
The similarly named `flutter_3_44_codex` tree reports 3.44.3; SDK names are not
version proof. The earlier illustration capture remains accurately scoped.

`pinned-flutter-validation/` records fresh isolated Pub cache restoration with
`--enforce-lockfile`, unchanged `pubspec.yaml`/lock hashes, capture-target analysis
and the two negative payment tests. Initial analyzer/formatter failures from
archival package copies remain retained. `pinned-flutter-validation-attempt3/`
records clean non-writing formatting, full fatal analysis and archive byte
preservation after the narrow tooling corrections.

The dated `source-dependency-inventory-final.json` and `source-sbom-final.cdx.json` record
362 package occurrences, 358 deduplicated package components and 95 declared
asset components: **453 CycloneDX 1.6 components**. Coverage includes six fully
hash-pinned decoder wheels for Linux aarch64/Python3.12 and its digest-pinned OCI
base. Every local evidence file is checked before SBOM generation. Its document
structure passes the retained [official CycloneDX 1.6 schema](https://cyclonedx.org/schema/bom-1.6.schema.json)
offline. Schema hashes and official repository origin are in `schema/`.

The dated earlier inventory/SBOM is retained. Source changes correctly make its
reproduction fail; it is not a current candidate. Unknown license evidence,
platform coverage and advisory acceptance are not invented. Source inventory
does not certify complete resolved Android/Deno graphs, installed artifacts,
decoder image platform attestation, native signed contents or license approval.

Native work is recorded independently from the earlier source SBOM. `native-export-attempt2/` records actual development lint with
zero errors / 40 warnings and 12 passing JVM tests. `native-inventory-attempt4/`
records 172 runtime components, 834 edges and 141external AAR/JAR byte hashes;
64 compile components, 247 edges and 47 external artifact hashes. Strict-lock
failures and subsequent corrective attempts are retained separately; graph
resolution alone is not lock enforcement or native build acceptance.
`native-corrections/` preserves the exact source of three redundant/unreferenced
resources and the manifest before removal of the optional square roundIcon
declaration. All official PNG bytes remain unchanged.
The prior dev lint XML and all 40 warning locations are preserved in
`prior-lint-warning-inventory.json`; that historical report is not current
release analysis. Native source exports omit ignored signing/provider/private
files and document derived local SDK bindings.

### Actual local Android release compilation

`native-export-attempt12-current/` records a clean **739-file native source
export**, exact Flutter 3.44.4, enforced Pub lock restoration and a real offline
`assembleProductionRelease` with explicit `collectUnsignedLocalQa=true`.
The resulting unsigned APK is 96,462,648 bytes, SHA256
`c44637cfee291569e8926e2742d5cf8e904eaf23b652fb82851c1bc4f34e4ba5`.
Its ZIP integrity, QA marker and unsigned rejection by actual `apksigner` were
verified. Actual merged manifest and APK badging contain no obsolete external
storage permissions and no optional roundIcon declaration. The five density
launcher images have identical decoded pixels to the preserved official sources.

The full normal `lintProductionRelease` command passed with **zero errors and
37 warnings**. Of the original 40 messages, 8 were corrected and 32 were individually
retained for explicit reasons. Removing the false circular icon declaration
exposed 5 different square-icon shape advisories. These are individually retained
to preserve the approved brand artwork. `native-corrections/WARNINGS.md` and
`final-warning-dispositions.json` retain every location, reason and supporting
API reference; no lint suppression or bitmap edit was used. Actual native JVM
results report **12 tests in 3 suites, zero failures/errors/skips**.

This artifact predates final L17/L20 and subsequent identity changes. Its
runtime inputs remain dated evidence; it is not the current candidate until
rebuilt against the final source set. It grants no provider, device, native
visual, signing or store acceptance.

`native-signing-fence-attempt13/` independently exercised actual Gradle default
assemble/bundle task graphs: both refused missing production signing inputs.
A malformed local QA property also refused. The production store wrapper
forces QA=false and rejects QA-marked packages.

### Reviewed Android dependency locking

The app-only strict `android/app/gradle.lockfile` binds 184 selected modules across
production compile/runtime configurations, SHA256
`e75fcc377acd2127fdf6bc8f151cf29288083fc786bfc673c7b2d75606b55957`.
`native-lock-enforcement-attempt9/` records actual lock generation and strict
resolution of both configurations. Runtime has 173 components / 995 edges and 141
external AAR/JAR artifacts; compile has 64 components / 296 edges and 47 artifacts.
The runtime external byte-hash set matches the pre-lock baseline exactly.
Missing whole-lock and missing-entry probes in attempt10 both fail closed.

`native-observed-sbom.cdx.json` contains 200 deduplicated components and actual
observed graph dependencies; its inventory retains 188 external artifact
occurrences with byte hashes and constraint edge scope. It passes the retained
official CycloneDX 1.6 schema and deterministic reproduction. These are observed
external artifacts and local project identities, not project-source or signed
package attestations, license approval or advisory clearance.

`wrapper-provenance-attempt16/` records an additional concrete correction:
the app requested Gradle 9.1.0 while its launcher JAR matched the official
Gradle 2.10 JAR. The app launcher/scripts/properties were regenerated offline
from the existing verified 9.1.0 distribution, with its official ZIP checksum
pinned. The new JAR also matches Gradle's official 9.1.0 checksum. All prior
wrapper bytes/hashes are preserved. Two actual wrapper executions from fresh
isolated homes respectively reject a bad checksum and accept the verified
local ZIP. No shared SDK tree was changed. The vendored fork's unexecuted 8.7
properties receive only their official checksum declaration; its absent
launcher JAR was not invented. [Official Gradle checksum reference](https://gradle.org/release-checksums/)

The root-owned production Deno collector now covers 45 remote and 5 npm lock
identities, declared edges and integrity rejection. Its current 14 source SBOM
regression tests passed independently. The dated 453-component aggregate above
must be regenerated after the full source freeze to include the new lock graph.

`archival-scope-current.json` confirms 362 active Dart source files stay covered
and 2065 dated archival source files retain their exact hashes. Later source
additions need a fresh formatter/analyzer gate and scope inventory.

`source-inventory-after-wrapper-attempt17/` is the later reproducible source
inventory: 598 package occurrences, 593 deduplicated package components and
95 declared asset components, or **688 CycloneDX components**. All 94 source
input hashes are verified. It includes the corrected official wrapper/checksum
pins, reviewed app Gradle lock and production Deno lock. Offline schema validation
passes; artifact compilation, advisory clearance and license approval remain
outside that inventory. The earlier aggregate documents remain preserved.

`reachability-diagnostic-after-wrapper.json` reaches all 195 currently observed
runtime Dart files with no missing imports, unreachable runtime files or
unresolved bundled asset paths. It is a diagnostic snapshot while other client
UI work continues, and must be rebound for the final L21 certificate.

The next Public media recorder binds all three vendored package source trees,
their declaration/license/provenance, analyzer options and generated package/plugin
bindings before and after the actual build/capture. It retains separate before/
after fingerprint logs. Historical reports remain unchanged.

### Local Auth fork source coverage

`local-fork-coverage-attempt19/` proves the collectors include the new local
gotrue 2.27.1 override and the existing file_saver fork. The dated gate passes
**41 actual tests**: 19 source supply-chain, 3 exact native source export and
19 Public media tests, with 43 Ruby assertions. Recorder syntax, deterministic
Dart-only SBOM reproduction and the retained offline CycloneDX schema also pass.
All 139 owned collector/declaration/fork source inputs remain byte-identical
through that execution. Its 167 components cover Dart locks and local forks;
this is deliberately separate from the pending final aggregate inventory.

The gotrue comparison retains all 79 original cached source files: three common
files changed, and the invalidation helper plus two provenance files are added.
The original MIT LICENSE is unchanged. Local tree digests bind the regular
file manifest and are never labeled as published archive digests. New fork
files, mutations, missing provenance, path/version mismatches and symlinks are
rejected by the relevant source or SBOM checks. Native exports include the
fork runtime/license/provenance and omit recognized private key files.

Public runtime freshness now includes declared local fork libraries and their
provenance. The seven existing published previews require recapturing after
the final shared runtime and Auth freeze. This packet runs no Flutter/native
build and does not close final current-runtime acceptance, upstream archive
authenticity, license approval or external release gates.

### Actual isolated unsigned iOS compilation

`native-export-attempt18-ios/` records a fresh 744-file source-only export taken
before the approved gotrue authentication fork. Exact Flutter 3.44.4 configuration,
enforced Pub restoration and actual generic-device Xcode release production
compilation passed. Pub, Pod and both Swift Package lock files stayed
byte-identical. All 744 exported source files remained unchanged; generated
package/plugin/SDK bindings are separately hashed.

The compiled `Collect.app` identifies app.cool.mobile version 1.2.4+23 and actual
iOS arm64 platform. Its 199 regular files total 41,575,135 bytes; the file manifest
is bound in `artifact-verification.json`. Actual `codesign` rejects the unsigned
bundle; no root signature or provisioning profile exists. A separate local QA
sidecar marks signing/store/provider acceptance false. The build emitted 24 raw
warning strings, including 4 duplicate Swift diagnostic renderings, and preserves
the full output plus warning inventory. No application Runner source warning
was reported. Successful compilation does not approve plugin runtime behavior,
physical native UI, notification providers or a store release.

The final current-source Android/iOS/Public-media and aggregate SBOM rebind
remains pending. The new gotrue source/library/license/provenance must be included
once its owner freezes it; the successful pre-fork build remains dated evidence. Physical native acceptance and
signed store artifacts require their separate release inputs.

### Firebase native scene return contract correction

`ios-warning-source-review-attempt20/` individually records the 20 primary iOS
compiler/tool diagnostics and 4 duplicate Swift renderings from the preserved
pre-fork build. Exact source bytes support each disposition; no warning flags
were suppressed. The review identifies one concrete defect: Firebase Messaging
16.5.0 implemented the scene connection callback as `void`, while the pinned
Flutter protocol requires `BOOL` to report whether connection options were
consumed.

`firebase-scene-compatibility-attempt21/` preserves all 148 original cached
package files and the pinned SDK protocol, dispatch and existing engine tests.
The bounded local fork retains every runtime/platform file and the unchanged
BSD-3-Clause license. Its only common-file changes remove workspace metadata
and correct the iOS callback signature/return. All 112 upstream test/example
files remain in the dated source snapshot. Original Dart, Android and macOS
runtime bytes are unchanged.

The return follows the existing FCM message-id selection policy: a handled FCM
notification consumes options; nil, empty and unrelated options remain available
to later plugins and Flutter fallback/deep-link handling. The original callback
notification/action/setup body stays intact. Exact extracted callback, protocol
and actual pinned dispatch compile/run on macOS Foundation stand-ins in **8 cases
with 18 assertions**. The original callback fails the native return-contract
compile check. A second gate compiles the complete real Objective-C plugin for
iOS arm64 against retained iOS 27, Flutter and Firebase headers: original source
fails and corrected source produces a 170,240-byte object. Return-contract
warnings alone are promoted to errors; other upstream diagnostics remain visible.

Exact Flutter 3.44.4 offline resolution and enforced-lock restoration bind the
approved local plugin override. Only the Firebase Messaging lock entry changes;
all 167 package versions and prior direct/dev declarations remain unchanged,
including the gotrue and web bindings. These gates establish the source correction
and local dependency binding. Final whole-app current-source Android/iOS builds,
compiled-artifact inspection and source/media/SBOM rebind remain pending.

`local-fork-coverage-attempt22/` refreshes the source collector checks after that
binding: **42 actual tests** (19 source supply-chain, 3 native export, 20 Public
media), 46 Ruby assertions, 178 exact source inputs unchanged, and 167 Dart-only
SBOM components. Recorded framework output verifies those counts. Recorder syntax,
deterministic SBOM reproduction and offline schema validation pass. This dated
packet covers all three forks; final aggregate source inventory remains separate.

### Remaining local acceptance gates

After the Auth 149, Admin and shared UI owners freeze their final source:

1. Run exact pinned full formatter/fatal analyzer and refresh explicit active-source
   coverage, preserving the narrowly approved historical/upstream evidence cohorts.
2. Refresh asset integrity, source reachability, affected regressions and the L21
   source-bound cleanup certificate; preserve all prior reports.
3. Recapture and visually inspect all seven real Public routes, publish unchanged
   capture bytes with current provenance, and run the real Public production builder.
4. Export final sources to new isolated native workspaces; run actual unsigned
   Android/iOS compilation, JVM/lint gates, artifact/merged-manifest inspection and
   current default signing-refusal checks. Confirm the corrected scene return warning
   is absent from the complete final iOS build.
5. Regenerate aggregate source and observed native inventories/SBOMs, verify source/
   artifact hashes, deterministic reproduction/schema and final L21/L22 local closure.

Freeze inputs include application/test/tool/web/legal/asset/native source, all
three fork trees, pubspec/lock, analyzer settings, generated package/plugin binding,
and the actual build/collector/recorder callers. New shared runtime changes require
new dated native/media evidence. Physical device/provider and signed store release
acceptance remain separate from these locally executable gates.

## Reproduce scoped checks

```sh
ruby scripts/tests/asset_manifest_integrity_test.rb
ruby scripts/tests/asset_hygiene_integration_test.rb
ruby scripts/tests/public_app_media_test.rb
python3 scripts/tests/runtime_reachability_test.py
python3 scripts/tests/supply_chain_source_test.py
ruby scripts/tests/dart_format_test.rb
ruby scripts/qa/asset_manifest_integrity.rb --json
ruby scripts/qa/group_runtime_integrity.rb --root . --json
python3 scripts/supply_chain/inventory.py --output docs/release/asset-build-hygiene-2026-09-30/source-dependency-inventory-final.json --check
python3 scripts/supply_chain/source_sbom.py --inventory docs/release/asset-build-hygiene-2026-09-30/source-dependency-inventory-final.json --output docs/release/asset-build-hygiene-2026-09-30/source-sbom-final.cdx.json --check
python3 scripts/supply_chain/validate_source_sbom.py docs/release/asset-build-hygiene-2026-09-30/source-sbom-final.cdx.json
```

For subsequent source changes, generate new dated evidence and preserve this
packet. Do not regenerate old hashes to conceal drift. No external release,
hosting, signing or provider change was performed.
