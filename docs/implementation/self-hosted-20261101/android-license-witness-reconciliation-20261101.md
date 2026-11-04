# Android source and retained QA notice reconciliation

Read-only observation on 1 November 2026 against canonical main commit
`14f32d43961cd566e8834dae841ba67e475b21f5`. This reconciles existing witnesses
and a retained **unsigned, QA-marked** Android bundle. It is not a final signed
artifact inventory, licence approval, asset-rights decision, advisory review,
store acceptance or distribution clearance. No files were changed by the
checks, and no Flutter/Gradle command, installation or network request ran.

## Current source inputs

| Input | Current SHA-256 |
| --- | --- |
| `pubspec.yaml` | `be5c802769c475d24a9ec30c549059dda4163e9e053d5a4c3af41e7653afcf39` |
| `pubspec.lock` | `192c2f830a63b0b06b1a02bb97ce261e7c4832cee9ec16059731cce9edd18d5d` |
| `android/app/gradle.lockfile` | `b6460f5358a436118c2341a46da9c04ba48eaf71a07282ffe7833380b4c53b29` |
| `android/app/build.gradle.kts` | `d92fbd9817cf0485e75b25bb6fb7287646f06d2e7217d998b18d4f6902bbdd5e` |
| `android/settings.gradle.kts` | `4e28cd700c06e79ddaa3a7ea03f92db887f4a16a51d2db45c4783e0bae657c5a` |
| `assets/licenses/ios-native-NOTICES.txt` | `1156f83d834d603f19e530d80d9690750812c7c355ad0706d37f0b35ffabdc09` |
| `assets/typefaces/Inter-Variable.ttf` | `29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031` |
| `assets/typefaces/OFL-Inter.txt` | `5b9321a4298cfeb6b34354164a1c3afc3db114569984c502b9b35d988fd58c57` |

The manifest, both locks, composite notice asset, Inter files and Android
settings above match the retained b0a73 QA stage's corresponding bytes. The
current Android app build script differs from that stage, whose SHA-256 is
`140b6dcd9abeaa731718b18848be6d359d54c9361995229293db87ed3d8e5f05`.
Matching selected inputs or lock identities does not establish current source
closure, actual final graph, packaged membership, or final build equivalence.

The source asset inventory function checked 95 declared paths, with no missing
paths, marketing-image hash mismatches, or group source/derivative hash
mismatches. Six marketing images, 42 group sources and 84 runtime derivatives
matched their recorded hashes. This is integrity and
provenance evidence, not artwork, trademark or redistribution approval. The
source inventory still labels the 84 derivatives as generated provenance with
licence review pending and the six marketing images as provenance only.

## Retained Dart witnesses and current-lock delta

The earlier source inventory and witness are at:

```
/Users/jeanbosco/Library/Caches/collect-supabase-native-qualification-20261020/aab-current-schema-license-witness1/declared-license-run1/current-declared-inventory.json
SHA-256 f36e13224e87fa4eb84a77948c60ca1cd4b6030fcc0a8be792bb0d6882f046fd

/Users/jeanbosco/Library/Caches/collect-supabase-native-qualification-20261020/aab-current-schema-license-witness1/declared-license-run1/current-declared-cached-license-witnesses.json
SHA-256 92e37c3f4e28c6c76f337e707a2c456a8d9f613d96428223ffc9306392fd30ce
```

The earlier inventory has 151 Dart entries; the current lock has 155. All 151
shared names match by version, source, origin and lock integrity, and none was
removed. The `logging` relationship changed from transitive to direct dev;
the current lock therefore is not identical to the earlier lock. Four hosted
entries were added. The retained separately bound delta is:

```
/Users/jeanbosco/Library/Caches/collect-supabase-native-qualification-20261020/native-dependency-governance-execution1/FOUR-TEXT-DELTA.json
SHA-256 c96392c0006ffeaeda7669e615375123b2a28189ad551a967a082440f4adce20
```

The earlier witness identifies 143 local-text Dart packages and eight Flutter
SDK packages outside its explicit cache-root scope. All 143 earlier metadata
and licence-text files still matched the witness's recorded byte counts and
hashes. In the current package configuration, 141 point to the same roots;
the two vendored fork roots point to this canonical checkout instead of the
historical T7 checkout. Their current `pubspec.yaml` and `LICENSE` bytes also
match the earlier witness pins. These checks do not authenticate cached package
archives or establish what a final artifact contains.

Each four-package delta identity, cached `pubspec.yaml` name/version and full
licence text matched the retained delta. The licence-text hashes below bind the
individual full texts, not a licence approval:

| Added locked package | Cached `LICENSE` SHA-256 |
| --- | --- |
| `realtime_client 2.13.0` | `334dd6820e2eaeab2064e7c59001b810566728a28a41a7c1dbf69bbee17d0936` |
| `supabase_common 0.1.2` | `be8c4de36f5c20598e7dcb2dd8d33d398d3c74fda7f9d33d902804302abf41f2` |
| `web_socket 1.0.1` | `cbe822ef3446af4366b2b82c48b0979d0b12865edfe74c22b9aa617fc362d6e0` |
| `web_socket_channel 3.0.3` | `a4b5d7d31626e90b77e8696f1c47643aa31f52e17c1907c1ab60b068110e6e10` |

## Retained QA graph and notice readback

The existing b0a73 content receipt is
`/Volumes/PRO-G40/.codex-collect-production-goal-20261023/backend/android-b0a73-stage-preparation1/artifact-inspection1/CONTENT-RESULT.json`,
SHA-256 `5cbd25471de1fb09eaba59e9c6eafb158cc4f4895d884108a36cf305c5647801`.
The named QA AAB was rehashed read-only and matched its recorded SHA-256
`477cac19e4d6b24494032f659a2945332aa7c9a3236be7fe30926050b25b08df`.
Its recorded runtime and compile graph files also matched their respective
SHA-256 pins `20bb8fa08b757b0c29cbc7dc2f281f1616c78da4de468e6c796e928149eb2056`
and `e1b02a4614a72a7a1fe97beff81fc8306c55dba4e8279060fccf9293e84767fb`.
The 157 Maven runtime coordinates in that historical graph exactly match the
current `productionReleaseRuntimeClasspath` lock entries as a set. The old
graph includes 16 project components as well. Lock-set equality does not prove
a fresh resolution, final R8 membership or packaged native contents.

The QA AAB's named `base/assets/flutter_assets/NOTICES.Z` member had compressed
SHA-256 `c539e912d0b7cf7ab2a66c62ebfa5b74a01e4dbbd8128cc0aa1cee573e6ac035`
and expanded SHA-256
`1d038f357355c376cd3bee437a29cdbb55d6e507c511f7ec20a6af86a4ce8985`.
The exact current composite notice asset occurred once in the expanded bytes.
Each of the four cached full licence texts above occurred in a section whose
heading exactly named its package. These are observations of this QA bundle,
not claims about a later artifact or the full native dependency set.

The earlier c393 QA AAB SHA-256
`c393d2b6bb493220524f68acf600046a89e95c1f2ee397771ef17c47d4addc30` was
also rehashed. Its expanded notice SHA-256 is
`ba0f83b6498fbfa3842453928a57966818474320d0fbc8c44a6a34ec2c525979`;
the entire 1,642,209-byte expansion is an exact prefix of the b0a73 QA
expansion. The historical review
`/Volumes/T7/01 Projects/COLLECT/docs/implementation/supabase-uat/ANDROID_DIRECT_POM_AND_FLUTTER_NOTICE_REVIEW_20261024.json`,
SHA-256 `e712d74dc8b7b6a6c612c6f6735a451a16a0b865909cf3e9e64c9c594e8078b6`,
recorded one framework and 1,594 engine required named full bodies matched for
that earlier notice. The complete-prefix comparison carries those exact bytes
into the later QA notice; it does not independently assess additional native
terms or the final release. The inspected local SDK `engine.version` file is
`a10d8ac38de835021c8d2f920dbf50a920ccc030`, matching the historical review; no
SDK command established which installation a future build will consume.

## Remaining boundary

This document is a human-readable reconciliation of separately retained sources;
it does not replace a newly generated, machine-checkable witness for the final
source freeze. Refresh the source-locked witness if inputs change; resolve the
actual final build's graphs and archive membership; review applicable native
terms, image and trademark rights, advisories and notice obligations; and
verify the submitted signed artifact. The exact libyuv/protobuf upstream joins
and complete native distribution terms remain unproved. The prior scoped
protobuf QA attribution is not a final-runtime or rights conclusion.
