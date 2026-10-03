# Root execution recipe

Use the reviewed `pd12-current-index-refresh-preparation2` unchanged: `packet-files.json` SHA256 `d8f17787a81bd5f3b9a63cf2ccdd8e6ba60883f4abaa422ac4728c5b9fa0ae4b`; helper SHA256 `ef0943912db73ec253b31d072ce1cf6bcefd9464119558e746b42b59c83ef4df`. No duplicate reader suite is needed while its actual source hashes remain `447c8c053e90824b440204b302354b3545e7a8aca63a1077ce99c45081f90119` and tests `0f259d90b65bb0f247bbc8f8eb045c20bae0bcc293e66b6288a8d3ac76aab736`; root already passed all 18 tests.

After root has actually applied Android3 and captured the final aggregate and APP manifest, copy `refresh-inputs.pending.json` into a separate root-owned input file. Keep the sealed template untouched. Fill only these six required fields:

| Field | Actual value to supply |
|---|---|
| `recorded_at_utc` | Actual UTC time of this preparation/readback. |
| `new_root_fence` | Record for the actual final selected2563 fence, containing `source_files_identity` and `source_manifest_sha256`. |
| `new_APP_manifest` | Record for an immutable workspace copy of the actual current privateAPP manifest, containing `source_files`, `file_count:2561` and `source_manifest_sha256`. |
| `android3_overlay` | Record for the actual applied root/privateAPP settings overlay receipt. |
| `android3_settings_after_pointer` | JSON pointer in that actual receipt whose value is the observed final settings SHA256. Read its actual structure; do not guess a pointer. |
| `archived_android3_settings` | Raw-file record for the actually preserved original settings bytes. The expected original byte identity is 840 bytes, SHA256 `3c06abd940c572639def32654d82f851002cf8ed23f4cdac4416e97fc5bd862d`; the archive file must actually exist and match. |

A JSON document record has workspace-relative `path`, actual `bytes`, actual `sha256` and `content:"json"`. The raw original settings record may use `content:"text"`. Root's prospective preservation path `docs/release/critical-implementation-2026-10-01/root-arc09-r8-integration1/before/privateAPP/android/settings.gradle.kts` was absent when this recipe was prepared; it is a target, not observed evidence. Root will provide its final actual path and digest. The new aggregate/APP/overlay pins are still pending here.

Leave all `AAB_*` fields null and `AAB_artifacts:[]` while no later AAB result exists. The helper already retains the exact AAB9 failure packet and dated independent outcome. Source refresh does not depend on future packaging success. If root later supplies a current AAB outcome, all corresponding source/result/built pointers and values must bind that actual epoch; a built claim also needs exact retained artifact bytes. Do not attach AAB9's source epoch to a later source record.

Run from COOL with the pinned Python, a completed actual input file, and a fresh nonexistent output directory:

```sh
/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3 -I -B \
  /Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/critical-implementation-2026-10-01/pd12-current-index-refresh-preparation2/refresh_current_index.py \
  --root /Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL \
  --inputs /ABSOLUTE/ACTUAL-ROOT-INPUTS.json \
  --output /Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/critical-implementation-2026-10-01/ROOT-FRESH-OUTPUT
```

The command creates four files when current AAB fields remain null:

- `source-domains.json`: actual current scope projection and retained original byte references.
- `acceptance-status.json`: proposed current summary with the previous readback clearly historical and new reader state pending.
- `current-candidate-evidence-index.json`: proposed current index, original 26 set identifiers retained, actual current named digests and old failures preserved.
- `refresh-plan-readback.json`: preparation metadata; it is not an actual current reader result or manual criterion decision.

An actual supplied later AAB outcome additionally creates `latest-AAB-retained-artifacts.json`. No maintained file is written by this helper. Retain the fresh output directory at its recorded path because the proposed index refers to its `source-domains.json`.

Root reviews the generated documents and applies only current index/schema/acceptance-summary changes. The schema proposal is `proposed/docs/release/revolut-design/current-candidate-evidence-index.schema.json` SHA256 `c51219cc40f5efba28d4a935d2dceef73e3cd845f5625ecacb934992c420d33e`; the separate schema-only patch is `fa00201df6053cc3e7afe22654684adb142cfd74ec2c4f6b472e240797583974`. Add actual later current209 generation/verification references when available, retaining the original69-test packet as dated evidence. Validate the actual final index against the maintained schema, then run the actual reader with independently pinned original decision receipts:

```sh
/Volumes/PRO-G40/Development/Python/codex-agents-venv/bin/python3 -I -B \
  /Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/scripts/audits/collect_current_evidence_index.py \
  --root /Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL \
  --index /Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/docs/release/revolut-design/current-candidate-evidence-index.json \
  --integrator-review-sha256 22712311d208f663c3441ea7653062904158bd828df558b3f543d4b4d17092f4 \
  --integrator-checkpoint-sha256 d97783a187ea844818d72ba7bd5e0b872a00e94d3c119cb5864fcde743a18804
```

The review pin names `root-pd12-original-criterion-review1/review.json`; the checkpoint pin names `root-current-readiness-integration8/receipt.json`. Their scoped decision applies only to recorded `1c55…`. Both `reader_grants_closure:false` and legacy `PD12_closed:false` remain machine no-grant flags. A later manual root review can bind immutable refreshed candidate/summary snapshots without another reader source change.

Preserve the actual command receipt/stdout/stderr, including genuine drift, incomplete entries and errors. After actual Android3, the direct oldabf-versus-liveAPP comparison is expected to reveal three Android differences; the reader must hash them rather than predeclare the count. Current selected2563/current known2556/current tooling5 should not have unexplained drift. Full input graph, physical SDK reconstruction, current whole native tests, full visual/font/provider/package/release acceptance stay unverified. Root runs `make revolut-design-authority` after reference changes; its hygiene result does not grant visual acceptance. No canonical counter or acceptance-criterion change is part of this recipe.


# Actual execution and final private data

Root subsequently supplied and applied Android3. The actual aggregate fence is `root-arc09-r8-integration1/final-current-source-fence.json`, SHA256 `f5448ce9a3e70623493035eaf37eb600d78c924d977e191e452ab9073b630333`; selected2563 map is `0843bf6a287e35284487a2f44f33f2740191809d18f2982a8eab2eb3e3796ada`. The retained current APP manifest is `current-APP-manifest.json`, SHA256 `7f896d80db4f79c8b5f75743ff1dfeb30dd6cc51951f2ac6214ad3eb3c2f8df1`, APP map `46a85b4c758bee9613fed36fa7b18ea376ef24d5d3d4a94b9eeec1b251efdb11`. The actual overlay and preserved original settings are independently pinned in `refresh-inputs.actual.json`; its settings pointer is `/changed_settings/actual_after/sha256`. The earlier absent/pending observations above remain historical preparation context.

The reviewed helper actually exited0 in0.124007s under90s; stdout/stderr empty and its owned process group absent. Exact argv, input/helper pins, UTC and lifecycle outcome are in `helper-command.json`. `generated-data1` preserves all four exact helper outputs. No later AAB was supplied; AAB9 remains the last dated failure and current packaging pending.

The actual current209 packet was then appended as data: `root-be08-post-r8-reader-current2091/packet-files.json` SHA256 `ac6b4a91b81391f3f4af2e069a51b7a7dfc55a2cdacdca6b83d68427331beb19`; `readback.json` SHA256 `7f86a9c7747bb46ca55e3f4a764a2384cabdcf4cf2caee868bdf8e118af60ed5`. All14 payloads were hash checked. Their current generation/semantic verification, unchanged1095 held inputs,668 maintained sources, source epoch and unresolved127 are bound in16 added facts and one artifact set. Original26 set identifiers remain; final preparation has130 facts/33 sets. `generated-data2` retains the append before schema correction.

The first actual private Draft2020-12 validation failed on two helper-output data defects: an out-of-enum integration state and missing required pointer on a text-includes fact. That failed result is preserved in `private-schema-validation.json`. Only private final data was corrected: integration state is `unapplied-private-proposal` and the text-includes fact has `pointer:""`. The helper/source/schema remain unchanged. `private-schema-validation-corrected.json` records actual PASS with zero errors.

Apply only the three reviewed data files from **`generated-data3`** to their names under `docs/release/revolut-design/`: `current-candidate-evidence-index.json`, `current-candidate-evidence-index.schema.json`, `acceptance-status.json`. Preserve maintained before bytes and mark actual application/readback in root's own receipt. Keep the sealed `generated-data1/source-domains.json` at its original path because the final index references it. The final live-summary document fences the prepared acceptance-status bytes; the actual reader against maintained data is pending until root applies them. No reader/tests/build/provider or maintained writes were executed by this packet.

Root uses the unchanged maintained reader command and independent original-review/checkpoint pins above, retains genuine three Android drift rows and all incomplete/unknown scopes, and runs reference-authority hygiene. Root's later manual review may separately bind immutable refreshed index/status and actual reader output. This packet grants no current manual closure: the original decision remains declared1c55, which differs from current0843. Root owns canonical closure/count decisions. No future AAB, complete packagedSBOM, full current native, whole input graph, physical SDK, font/visual/provider or release result is inferred.
