# Workstream merge decisions

This is a targeted pure-policy consolidation, not an assertion that all parallel application branches have been merged.

| Existing input or overlap | Decision and resulting file |
|---|---|
| BuriMunsi SMS-R1 exact receipt parser | Preserve unchanged as a pinned dependency; `BuriSmsClassifier.kt` delegates to it and explicitly recognizes the supported profile. No receipt grammar broadening. |
| M-Money SMS v0.2.11 screening | Preserve original policy in `vendor/mmoney/core/LedgerRules.kt`; `MmoneySmsClassifier.kt` adds conservative malformed-money/control/multiple-statement abstention and delegates contradictory/invalid reference checks to the pinned `observeReferenceIdentity` policy. No server extraction or posting contract replaced. |
| Conflicting app semantics for historical SMS | Preserve the distinction: Buri requires original-PDU completeness, while M-Money can classify an exact provider body without claiming multipart evidence. |
| Different duplicate identities | Keep Buri capture/evidence identity and M-Money exact source/body deduplication distinct in `Duplicates.kt`; do not silently deduplicate Buri events solely by body text. |
| Different acknowledgement contracts | Separate `collectV2` and `mmoneyV1` validators. Never require or invent a server body digest that M-Money v1 does not supply. |
| Retry workers with different platform APIs | Consolidate decision rules in `Queue.kt` and `Retry.kt`, not Android scheduling or storage. No edits to WorkManager/JobScheduler or production worker call sites. |
| Buri gateway upload admission | Existing false admission remains unchanged in the pinned source. New module use is not authorization to enable live uploads. |
| Existing QueueStore/Room storage | Preserve unchanged. Introduce `QueueStorePort` as an integration contract; the fault-injection store is a test oracle, not a replacement production store. |
| Newer canonical, owner recovery, UI and operations continuations | Do not overwrite or claim merged. The additive installer refuses changed dependency hashes; manual reconciliation against the chosen candidate remains required. |
| Fixture missing sender | Preserve the original synthetic body and missing sender. New layer reports `INCOMPLETE` before classifier screening, rather than the inherited sender-policy-only `UNSUPPORTED` expectation. Both reject automatic upload; the distinction is explicit and tested. |

Every vendored source path, original path and SHA-256 is listed in `vendor/PROVENANCE.json`. Every delivered source path and SHA-256 is listed in `SOURCE_MANIFEST.json`. No source dependency was silently rewritten, and no original archive was replaced in Drive.

## Effective R1 acknowledgement dependency

The first combined host run exposed a harness composition error: the inherited R1 reliability test was compiled against raw upstream `ReceiptAckPolicy.kt`, rather than its deterministically prepared R1 output. Running the original, unchanged `prepare_receiver.py` produced the expected additional acknowledged-tombstone guard. The effective file and original recipe are now pinned separately in `vendor/buri/effective/` and `vendor/buri/recipe/`; the raw input is retained. The test runner uses the effective file for both inherited receiver suites. A Python test reconstructs the one-line transformation and checks byte equality. No baseline product regression was masked or inherited test weakened. The initial receiver harness also had its main-class package corrected.
