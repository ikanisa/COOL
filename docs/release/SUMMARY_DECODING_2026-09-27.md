# Increment 09 — legacy group-summary decoding and cache recovery

## Runtime changes

`CollectionSummary.fromJson` no longer substitutes zero when a legacy group total
or the current member's balance is absent. A payload must contain a non-null
`amount_raised_minor` or `amount_raised_rwf`, and a non-null
`current_user_balance_minor` or `current_user_balance_rwf`. Supplied zero is valid.
A missing/null contributor count remains unavailable rather than becoming zero.

Both amount aliases may be supplied only when they agree. A null unused alias may
coexist with a valid alternate alias. An invalid non-null alias is not ignored
just because the other alias is valid. Legacy numeric values must be finite,
whole-valued numbers within -9,007,199,254,740,991 to 9,007,199,254,740,991 inclusive.
This is a native/web exact-number transport boundary, not a payment limit. Strings,
booleans, fractions, infinity, NaN, conflicting aliases and out-of-range numbers
produce FormatException. Conversion to int happens only after validation. Signed
amounts remain signed; no new rule about withdrawals or negative balances is added.
Contributor counts must additionally be nonnegative.

The modern `balances` array's existing amount types, row currency restriction,
duplicate handling and explicit-empty-array behavior are retained. This increment
does not extend the new numeric bound to that branch. Missing/null currency still
uses the existing RWF default; nonblank legacy currency labels are preserved with
no conversion. Malformed currency metadata now produces a payload-safe
FormatException, including when it accompanies modern balances.

## Offline recovery versus live decoding

The cache deserializer omits an invalid per-group summary while retaining the
other cached groups and successfully decoded data. It does not fabricate a zero
aggregate or recompute a total from partial contribution history. Saved timestamps
are not changed. The existing cache read/sanitize/save code may persist the
sanitized snapshot; that serialization and storage lifecycle are unchanged.

Only FormatException from one summary is isolated. Non-map summaries and non-string
field keys are ignored. Other failures in profiles, groups or history are not
swallowed. The existing outer corrupt-cache behavior for those failures is not
changed. Existing account-ownership, country filtering, sign-out clear ordering,
cache version and recovery guards remain intact. Live decoding still uses the
strict factory and does not use this cache-only omission policy.

The existing contribution selector and group list already display unavailable
aggregates without substituting zero. Other consumers that call legacy summaryFor
can still derive totals; they are not repaired or certified here. Previously
rounded or fabricated numbers already serialized as valid modern zero/integer
records cannot be distinguished from legitimate values by this change. A live
refresh is needed to replace those records.

## Code and coverage

Changed files:
- lib/shared/models/collect_models.dart
- lib/shared/models/collect_summary_json.dart (new part)
- lib/shared/repositories/collect_offline_cache.dart
- test/group_summary_decoding_test.dart (new, 65 test cases after loop expansion)
- test/group_summary_cache_recovery_test.dart (new, 16 test cases after expansion)
- scripts/qa/candidate_check_scope.json
- docs/release/SUMMARY_DECODING_2026-09-27.md

All prior candidate validation targets remain in their original order; the five
new/changed Dart targets and two test suites are appended. Existing CI already runs
the candidate command and the full unit/widget suite; no CI step is removed.
`revolut-design` remains the sole design authority. No visual changes are made.

## Required full-checkout validation

Apply the included hash-checked installer to the corresponding authorized full
checkout after Increment 08, not to the delivery directory. The original model
and cache file hashes must match; stop on a conflict. Resolve the project's pinned
SDK and dependencies without silently upgrading them.

```bash
python3 installer/apply_patch.py /path/to/COOL --check
python3 installer/apply_patch.py /path/to/COOL --apply
cd /path/to/COOL
python3 scripts/qa/verify_candidate.py --check
python3 scripts/qa/verify_candidate.py --run
# Alternatively, after formatting/analyzing on the pinned SDK:
flutter test --no-pub test/group_summary_decoding_test.dart test/group_summary_cache_recovery_test.dart
```

The Dart tests were authored but not run in the delivery environment because its
Flutter/Dart SDK is absent. The partial overlay also lacks the full pubspec and
resolved dependencies. Source/installer tests are not Dart compilation, widget
execution, backend integration or release acceptance. No live account, SMS,
payment, ledger posting, configuration, or deployment is touched by this work.

## Language references

Dart documents that num.toInt truncates; the new legacy decoder checks exactness
first: https://api.dart.dev/dart-core/num/toInt.html
Dart native and web integer representations differ beyond 53 bits:
https://dart.dev/resources/language/number-representation
