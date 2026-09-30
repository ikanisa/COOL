# Candidate dependency and asset inventory — 2026-09-28

**Status: source inventory complete for the inputs listed below; release assurance open.**
This is a reproducible snapshot of repository declarations and lockfiles, not a
software bill of materials (SBOM) from a signed Android or iOS artifact. On 29
September, a fresh isolated Pub cache resolved the committed lock with
`flutter pub get --enforce-lockfile` on Flutter 3.44.4/Dart 3.12.2 without
changing either dependency input. No package upgrade, lockfile regeneration,
registry advisory query, or license approval was performed.

Run `python3 scripts/supply_chain/inventory.py --check` from the repository
root to compare the current inputs with
[`candidate-inventory.json`](candidate-inventory.json). Regenerate with
`python3 scripts/supply_chain/inventory.py` after reviewing input changes.
The script requires PyYAML and reads outside its output directory without
modifying dependency inputs. Its JSON includes SHA-256 for 64 source files,
each declared asset, and the 47-file local `file_saver` source tree. A passing
`--check` proves only that this candidate inventory is current for those
inputs; it does not attest a build or a registry package.

For the Android selected-component graph, run
`cd android && ./gradlew -I ../scripts/supply_chain/gradle_runtime_inventory.init.gradle :app:collectRuntimeGraph --offline --no-daemon`.
The retained log and normalized JSON record this command's current output.
Gradle metadata resolution does not identify which bytes a signed AAB packages.

## Coverage

| Evidence | Recorded | Boundary |
| --- | ---: | --- |
| Dart `pubspec.lock` | 167 packages: 26 direct main, 4 direct dev, 137 transitive | Hosted archive SHA-256 values are lockfile assertions, not installed-byte verification. |
| Local `file_saver` fork | Version `0.4.0+collect.1`; 47 source files; tree SHA-256 `167192b4fd44cc743298d67bd8d0a530d4be564b83e5281af31b7d3888729023` | [Published-source comparison](file-saver-fork-comparison.json) passed: 43 common files byte-identical, three modified and 138 non-runtime upstream files omitted; signed-artifact inclusion remains unverified. |
| Android Gradle | 4 plugin and 9 Maven declarations; app wrapper 9.1.0, fork wrapper 8.7; app wrapper JAR hash recorded. An [offline production runtime graph](android-production-runtime-resolved.json) now records 156 selected external modules and 16 project components; the [raw Gradle log](android-production-runtime-gradle.log) is retained. | Cached local resolution from a dirty checkout, not a signed AAB SBOM or a native dependency lock. Neither wrapper properties file pins a distribution SHA-256. |
| iOS | 1 CocoaPods lock entry (`Flutter`), 13 SwiftPM pins; duplicate `Package.resolved` data agrees | No fresh iOS native plugin graph or signed IPA inspection. |
| Supabase Edge | 4 external import occurrences, 2 unique URLs across 36 TypeScript files | One runtime `esm.sh` URL and three Deno standard-library test imports; no `deno.lock` or remote transitive graph. |
| Node tools | 32 npm lock entries; 26 pnpm lock entries | These are tooling graphs, not proven app runtime contents. npm license values come from lock metadata; pnpm lock has no license assertions. |
| Ruby release tooling | 97 Gemfile lock entries | Tooling graph only; per-gem license and advisories not checked. |
| Declared app assets | 97 existing paths: 84 WebP, 7 PNG, 3 TTF, 2 JSON, 1 license text | This is manifest-path coverage, not actual AAB/IPA inclusion or runtime reachability. |

The 42 Rwanda group image sources and 84 declared runtime derivatives match
the recorded SHA-256 values; all cataloged group derivatives are within the
declared asset paths. The marketing source hashes checked here also match.
These byte checks do not constitute visual, cultural, accessibility, or owner
acceptance.

## Critical release findings and corrections

| Priority | Finding and evidence | Why it matters; required closure |
| --- | --- | --- |
| P0 | `assets/marketing/SOURCE.json` describes the two bundled Aeonik Pro TTF files as retained from a public Revolut page. No Aeonik license or redistribution grant appears in the scanned typeface/source files. The fonts are declared in `pubspec.yaml`. | Public availability and source attribution do not establish a right to redistribute font binaries. Obtain and retain the applicable grant for the exact files and app/web distribution, or use an approved licensed font while following the owner-selected design authority. Confirm the signed bundle's font contents before release. This is a missing-evidence finding, not a legal conclusion about the owner's actual rights. |
| P0 | The Android project declares AGP 9.0.1 and Kotlin 2.3.20; the local plugin's Gradle source declares AGP 8.6.0, Kotlin 2.1.0, and coroutines 1.8.1. The offline `productionReleaseRuntimeClasspath` graph resolves 156 external modules and 16 project components without failure, but there is no Android dependency lock or signed-artifact component graph. | A selected metadata graph can include constraints and components not packaged in the AAB. Repeat resolution from the frozen commit, review plugin compatibility, generate a signed AAB/APK SBOM, and reconcile actual native libraries and notices. Do not infer a compatibility failure solely from declarations or a clean resolution. |
| P1 | The app's Gradle wrapper JAR is present and hashed in the candidate inventory, but neither Gradle wrapper properties file specifies `distributionSha256Sum`. | Verify the wrapper JAR provenance and official distribution digests, then pin and review them in the governed build path. A repository-local hash detects later change but does not establish the downloaded distribution's authenticity. |
| P0 for iOS release | `ios/Podfile.lock` lists only `Flutter` while the repository has 13 SwiftPM pins and multiple Flutter plugins. | The CocoaPods lock is insufficient evidence of the complete native dependency graph. Build from a clean pinned environment, inspect resolved SwiftPM/CocoaPods/plugin dependencies and the signed IPA, and attach an artifact SBOM before iOS approval. |
| P0 for Edge release | The runtime imports `@supabase/supabase-js@2.112.0` through `https://esm.sh/`; test files import `https://deno.land/std@0.224.0`. No Deno lock is present. | URL versions alone do not freeze the remote transitive bundle. Record a locked or vendored resolution and deployed function digest, then review the exact deployed graph and advisories. Keep runtime and test imports separate in the review. |
| P1 | The fork retains BSD-3-Clause text and an upstream-source description. The [complete published-source comparison](file-saver-fork-comparison.json) verified the official `file_saver` 0.4.0 archive SHA-256, every 184 upstream file, the 47-file fork, byte-identical license, 43 identical common files, three changed common files and 138 omitted examples/tests/docs. The Dart MIME change is formatter-equivalent. | Keep the comparison gate in CI, review native Gradle compatibility and retain license notices in distributed outputs. This source-level result does not prove the signed artifact's component graph or license clearance. |
| P1 | The npm photography tool's lock metadata includes Apache-2.0, LGPL-3.0-or-later, MIT, ISC, and 0BSD assertions, including platform-specific `sharp`/libvips packages. The pnpm notification tool and most other ecosystems have no local license assertions. | Review authoritative package license texts and obligations against *what is distributed*; a build-only tool differs from a bundled runtime component. Preserve required notices. Do not treat a lockfile SPDX field as completed clearance. |
| P1 | Inter has a local OFL-1.1 text; generated Rwanda image provenance and matching hashes are recorded, but 95 of 97 declared asset paths have no license assertion in this candidate inventory. | Retain creator/tool terms or owner grant and approval for published imagery, and verify every font/image/icon in the final artifact. The generated-image record proves source/provenance, not the full distribution-rights analysis. |
| P1 | No current advisory or package-maintenance query was run. | Check the exact resolved versions against authoritative ecosystem advisories and supplier records close to the release build, triage findings with reachable-impact evidence, and record the review date and decision. No current vulnerability status is asserted here. |

## Completion evidence needed

1. Freeze one source commit, toolchain, flavor, and deployment revision; keep
   the lockfiles and local fork hash in the release packet.
2. Repeat the Android Gradle graph from the isolated frozen build; resolve iOS
   native plugins and Deno transitives. Reconcile direct and transitive
   versions with the source inventory.
3. Generate a signed-artifact SBOM for the actual AAB/APK and IPA, plus a
   deployed Edge bundle inventory. Compare component names, versions,
   integrity, native libraries, and included assets with this candidate.
4. Review current official advisories and actual license notices/permissions,
   especially the Aeonik files and any shipped LGPL components. Record owner
   and legal approval where applicable.
5. Verify final artifact hashes, signing identity, version, and target store or
   deployment receipts. A passing source inventory alone cannot close a
   production release gate.
