# Increment 11 adapted-file review — 29 September 2026

**Scope:** the ten locally adapted files among the twelve decision paths in the Payment Decoding and Intent Decoding Drive ZIPs. This resolves the requested file-by-file diff review, not G05's protected one-commit release freeze or production acceptance.

The archived ZIP SHA-256 values were rechecked against the preserved reconciliation manifest: Payment `8796e4fe961352db5f023209027f000f406aec36f6665d083e8e0b656d57acd6`; Intent `729ea922cb13f67b6eef123b546a2e6db639fde08839ddef13dfafb54b702eec`. Each selected `source/` file matched its archive-file SHA-256 before diffing. The two dated branch reports still match their archive bytes exactly. Nine of the ten adapted files still match the 28 September current-file hashes; CI changed later through locked dependency and fork checks. The present CI SHA-256 is `b4d976e8fa1e36cdacc69fdad95ef41a74b8f7473275e9b7d2be225ebd29b690`.

| Adapted file | Review disposition |
| --- | --- |
| `.github/workflows/ci.yml` | Both archives differ in which payment/intent source check is named. Current CI runs `make qa-tooling-test`, which invokes **both** source checks and the candidate-runner tests; its full Flutter job discovers both branches' Dart tests. A separate narrow `verify_candidate.py --run` step was removed, but the current analyze job adds non-writing format, fatal whole-app analysis, enforced lock resolution and the published `file_saver` fork comparison. The old design-scoring commands were retired under G06; current source-integrity checks are not visual acceptance. Hosted CI execution remains unverified. |
| `lib/shared/models/collect_payment_json.dart` | Keeps the Payment branch's positive exact integer amount, alias-conflict, identifier and zoned-calendar validation. Replaces the Intent branch's separate helpers with the same shared checked helpers; typed DateTime retains its instant. Adds bounded confidence validation. The branch tests still exercise both decoder families. |
| `lib/shared/models/collect_payment_models.dart` | Keeps the Intent branch's required identity/status, lifetime and amount checks while adding Payment branch contribution checks. It rejects historical transfer destination metadata from an active MoMo intent and unknown-currency parsed events. This is an intentional Rwanda-only restriction; representative historical-client and deployed schema behavior remain D08/D09/X02 work. |
| `scripts/qa/candidate_check_scope.json` | Contains all four Payment/Intent Dart test files in both format and test scopes, plus later receipt/cache/UI cases. No branch suite was dropped. |
| `scripts/tests/payment_decoding_source_test.py` | Adjusts the CI assertion from a direct Python step to `make qa-tooling-test`; substantive amount, identity and timestamp source assertions remain. |
| `scripts/tests/payment_intent_source_test.py` | Updates assertions for the unified checked-helper names and formatter layout; substantive required fields, exact amount, zoned date and no-external-call checks remain. |
| `test/payment_cache_integrity_test.dart` | Formatter-only changes. Existing valid-cache and whole-snapshot rejection cases remain. |
| `test/payment_intent_cache_boundary_test.dart` | Keeps Intent branch cache cases and adds rejection of legacy transfer destination metadata rather than inferring an active MoMo route. Other differences are formatting. |
| `test/payment_intent_decoding_test.dart` | Formatter-only changes; all Intent branch amount, identity, timestamp, routing and error-safety cases remain. |
| `test/payment_json_integrity_test.dart` | Formatter-only changes; all Payment branch amount, identifier, currency and timestamp cases remain. |

## Current local verification

- `flutter test --no-pub` on the four Payment/Intent Dart files: **229 passed**; retained [run log](flutter-payment-union.log), SHA-256 `194b50d549cd43414b9081d674b06b92b918b054b81f903c5f900958c58c2193`.
- `python3 -m unittest` on both source-wiring files: **24 passed**; retained [run log](python-payment-union.log), SHA-256 `b83727e4d931e3c56dcc5227e11bdffb9126d443423a6099353a7b5662ca78e1`.
- `make qa-tooling-test`: passed, including candidate-runner tests and both branch source tests; retained [run log](qa-tooling.log), SHA-256 `24e0625548fa2d5b0252f27ca2d46c3843aae4e4302856282116ae778eafca5b`.
- `make source-integrity-json`: passed with 174/174 approved visual asset bytes, fixture isolation, secret scan and zero product-boundary hits. This checks source integrity, not UI/UX acceptance.
- `python3 scripts/qa/verify_candidate.py --repo .`: 58 format targets and 25 test files validated as a **ready, unexecuted** scope. The focused branch tests above were executed separately.

## Still open

The checkout is uncommitted, hosted CI has not run on the selected source, the latest prior whole-app Flutter run had five visual differences, and deployed response schemas and historical bank/diaspora records have not been acceptance-tested against the narrowed Rwanda-only readers. Re-run all gates after the reviewed source is frozen, then bind the result to signed artifacts and deployed-state readback. G05, D08, D09, Q03, X01 and X02 remain open.
