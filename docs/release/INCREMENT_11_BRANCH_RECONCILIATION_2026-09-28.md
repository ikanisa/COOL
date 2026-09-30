# Increment 11 branch reconciliation — current checkout

**Status: source decisions and adapted-file diff review recorded; one-commit release freeze open.** The
preserved Payment Decoding and Intent Decoding ZIPs each contain 112 installer
candidate paths. A fresh byte comparison found 108 shared paths, 104 identical
shared paths, **four conflicting shared paths and four unique paths per branch**.
The exact archive/current SHA-256 values for all twelve decision paths are in
`/Volumes/PRO-G40/COOL_Drive_Review_2026-09-28/branch-reconciliation-20260928/manifest.json`.
All twelve exist in the current checkout. Two historical documentation files
still match their respective archive bytes; the other ten are later local
adaptations. Their [file-by-file review](increment-11-adapted-review-2026-09-29/README.md)
verified the ZIP bytes again, examined every archive-to-current diff and
reran both branch suites. Current CI changed after the 28 September manifest;
the review records its current hash and gate disposition.

| Path | Archive relationship | Current selection and reason |
| --- | --- | --- |
| `.github/workflows/ci.yml` | Conflict | Retain the current combined CI. Its full Flutter test job covers both branch suites, with current source-integrity and hardening checks. Hosted execution remains unverified. |
| `scripts/qa/candidate_check_scope.json` | Conflict | Retain the current union: all four Payment/Intent Dart test files are declared in the candidate scope. Recheck the scope against the final commit. |
| `lib/shared/models/collect_payment_json.dart` | Conflict | Retain the locally adapted broad payment decoder. It rejects invalid amounts, identifiers and timestamps while serving current Rwanda MoMo intents. Both branches' focused behavioral suites pass. |
| `lib/shared/models/collect_payment_models.dart` | Conflict | Retain the locally adapted Rwanda-only models and strict decoder calls. The historical bank-SMS sender fallback is not a current product route. Verify deployed response schemas before release. |
| `docs/release/PAYMENT_DECODING_2026-09-27.md` | Payment only | Retain as dated Payment branch evidence; current bytes match the archive. |
| `scripts/tests/payment_decoding_source_test.py` | Payment only | Retain the current adapted source-wiring test; it passes with the Intent branch source test. |
| `test/payment_cache_integrity_test.dart` | Payment only | Retain the current adapted cache behavior tests in the full Flutter suite. |
| `test/payment_json_integrity_test.dart` | Payment only | Retain the current adapted strict payment JSON cases in the full Flutter suite. |
| `docs/release/PAYMENT_INTENT_DECODING_2026-09-27.md` | Intent only | Retain as dated Intent branch evidence; current bytes match the archive. |
| `scripts/tests/payment_intent_source_test.py` | Intent only | Retain the current adapted source-wiring test; it passes with the Payment branch source test. |
| `test/payment_intent_cache_boundary_test.dart` | Intent only | Retain the current adapted whole-snapshot rejection cases in the full Flutter suite. |
| `test/payment_intent_decoding_test.dart` | Intent only | Retain the current adapted intent amount, route and timestamp cases in the full Flutter suite. |

The four Dart suites passed **229 tests** together. The two Python source-wiring
suites passed **24 tests** together. Their logs and SHA-256 hashes are in the
external reconciliation manifest. These are local dirty-tree results; the
Python checks validate source wiring rather than executing Flutter behavior.
The latest full Flutter run remains 1,366 passes with five unresolved visual
differences. No test or documentation file from either branch was dropped.

**Next:** resolve deployed and historical-client schema compatibility, freeze
one protected reviewed commit, and rerun the complete candidate gate on those
exact bytes. The current local diff review does not close G05 or authorize
release.
