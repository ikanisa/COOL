# MOBILE-DESIGN-100 critical analysis — 6 September 2026

## Executive finding

`MOBILE-DESIGN-100` is still a valid release control, but its current output must be read correctly. The Android gate reports **166 blockers**: **9 release/provenance fields, 134 required case records and 23 annotation closures**. These are not 166 confirmed visual defects. Most are missing or unbound acceptance evidence. The gate is correctly blocked because the current acceptance record contains no approved cases, no approval, no bound release artifacts and no current fingerprints.

The scoped Rwanda group-photo work does not change that conclusion. Its six Android photo-journey checks pass on a disposable debug fixture, but that fixture is not the exact production APK/AAB and is not the complete route/state matrix. It is valid feature evidence, not whole-app release acceptance.

## Current evidence

The current fingerprint command returns:

| Field | Current value | Assessment |
|---|---|---|
| Source | `a8a9d2bd099b3077bc69808b738f78d4b654d79c7f98c621c1fc0e39abc23b63` | Current workspace source; not bound into acceptance |
| Contract | `4cb47860f3259577f4cb3ba67ddd6ab15825fbe75b0a44afb59cb23704e396b7` | Current contract; acceptance is null |
| References | `3557088dcfd23756d0e61e5b2b98987d3adebfe79be483fd8a00bde1e1582170` | Current reference set; acceptance is null |
| Version | `1.2.4+23` | Current app version; no accepted release artifact is bound |

`ruby scripts/qa/mobile_design_gate.rb` returns Android `BLOCKED`. The iOS command also returns `BLOCKED`; its shorter output stops at the missing IPA and missing iOS build provenance, so it must not be interpreted as an iOS pass.

## Finding-by-finding assessment

| Current gate finding | Still relevant? | Critical assessment and advice |
|---|---|---|
| Acceptance must be mobile-only and approved | Yes | This is a governance condition. The acceptance file is intentionally `blocked`, with no owner approval. Do not change it to `approved` from local test results. |
| Stale or absent source, contract, reference and version fingerprints | Yes | The current source has changed since the older candidate records. Rebuild and bind the final artifacts only after source, contract and reference files are frozen. |
| Open findings remain | Yes | The four named findings remain open in the acceptance record: `EXACT-NATIVE-CANDIDATE`, `COMPLETE-CASE-MATRIX`, `NATIVE-ACCESSIBILITY` and `FINAL-VISUAL-REVIEW`. Their existence is still justified. |
| Missing or mismatched Android APK/AAB | Yes for release | A debug feature APK is not the required production APK/AAB. The gate expects the fixed production artifact paths and exact hashes. A local QA build cannot satisfy this field. |
| Release build provenance does not match current source | Yes | The build must be generated from the same source hash, version and artifact hashes recorded in `.cache/mobile-design-build/android.json`; an older candidate cannot be reused after source changes. |
| 134 missing Android cases | Yes as an acceptance obligation; no as a defect count | The contract requires 134 named route/state/variant cases. Existing diagnostic runs cover portions of them, but they are not individually recorded with current-artifact hash, original comparison, review notes and accessibility/interaction results. Reconcile valid evidence into the case register rather than rerunning blindly or claiming all 134 are broken. |
| 23 unclosed annotations | Yes as an acceptance obligation; mixed as implementation status | Several annotations have local corrections and passing tests. They remain open because the acceptance file has no verified annotation entries linked to accepted cases. Close each with a regression test, current native evidence and reviewer notes; do not infer closure from a widget test alone. |
| `EXACT-NATIVE-CANDIDATE` | Yes | The group-photo APK proves one scoped journey only. It does not prove the complete app, release signing, AAB/IPA parity or all route states. |
| `COMPLETE-CASE-MATRIX` | Yes | Full route, membership, geographic, loading, error, offline, keyboard, large-text, light/theme and recovery coverage is still not individually accepted. |
| `NATIVE-ACCESSIBILITY` | Yes, partially reduced | Android keyboard and enlarged-text subsets pass, including the new group-photo journey. Screen-reader tasks, full focus traversal, iOS native behavior and the complete matrix remain open. |
| `FINAL-VISUAL-REVIEW` | Yes | Individual corrections and selected comparisons were inspected. The complete current native route/state set has not received an approved visual review against the exact original references. |

## Items that are stale or need relabelling

The gate itself is current for this workspace. Some supporting documents are historical and should not be used as the current count:

- `REVOLUT_SURFACES_2026-09-05.md` reports **165** failures. The current gate reports **166**.
- Older reports refer to **22** annotation closures. The current contract contains **23** annotations.
- `OWNER_ANNOTATIONS_2026-09-06.md` says the MoMo-code backend migration “has not been deployed.” That statement predates the verified deployment and is now stale for backend status, although it does not close any mobile-design acceptance case.
- `GAP_CLOSURE_2026-09-06.md` and `NATIVE_KEYBOARD_AND_FOCUS_2026-09-06.md` use the current **166**-finding boundary and remain aligned.

These older documents should be retained for audit history, with a superseded/current-status note. They should not be silently rewritten to manufacture a cleaner history.

## What remains genuinely open

The material release blockers are:

1. Freeze the final mobile source and reference set, then build the exact production Android APK/AAB and iOS IPA.
2. Record current source, contract, reference, version and artifact hashes in the governed provenance files.
3. Complete the 134-case register on the exact artifacts, including route/state screenshots, original-reference links, interaction checks, accessibility checks and reviewer notes.
4. Reconcile all 23 annotations. Mark an item verified only when its test and current case evidence are linked.
5. Complete native screen-reader and platform checks and the full visual comparison review.
6. Obtain the required owner approval, then rerun Android and iOS gates independently.

The rule should remain fail-closed. The right next action is evidence reconciliation and exact-artifact acceptance, not changing the threshold, lowering the count, treating the debug fixture as production, or converting diagnostic passes into approval.

## Sources

- [Design authority and MOBILE-DESIGN-100](../../../DESIGN.md#mobile-design-100--critical-non-waivable-release-blocker)
- [Mobile parity contract](mobile-parity-contract.json)
- [Current acceptance record](mobile-parity-acceptance.json)
- Gate command: `ruby scripts/qa/mobile_design_gate.rb` (Android) and `ruby scripts/qa/mobile_design_gate.rb --ios` (iOS)
- [Scoped group-photo verification](../../plans/rwanda-group-asset-bank-2026-09-06/NATIVE-VERIFICATION.json)
