# Payment and contribution decoding — Increment 11

## Contract and scope

`revolut-design` remains the sole design authority. This is a data-decoding change,
not a visual redesign, payment execution feature, provider integration, or release
approval. Preserve all earlier source changes from the filed Increment 10.

`PaymentIntentModel.fromJson` and `Contribution.fromJson` now reject missing,
nonpositive, fractional, nonfinite, nonnumeric, or out-of-range amounts instead of
substituting zero or truncating. Amounts must be exactly representable within
1–9,007,199,254,740,991. This is a transport bound, not a permitted MoMo transaction
limit. Existing provider and server limits still apply. Whole-valued doubles remain
accepted. A current/legacy alias may be absent or null when the other is valid;
when both are non-null each must be valid and their values must agree.

Missing or blank intent status is rejected, never inferred as `pending`. Existing
nonblank unknown statuses are preserved; the existing actionable-state getter
continues to accept only `pending`. Intent expiry must be strictly after creation.
Past expiry is not a decoding error: expired records remain available for history.

IDs and group IDs must be nonempty strings without surrounding whitespace or
ASCII controls. This does not enforce UUID syntax or validate ownership. Existing
current-field precedence is retained for `payment_id` versus `id`, and posting
time versus creation time: these can belong to different event/schema contexts
and are not treated as interchangeable aliases that must agree.

## Timestamp compatibility

Accept explicit DateTime objects and zoned ISO strings with calendar date, hours,
minutes, seconds, and up to six fractional-second digits. Preserve the instant and
normalize to UTC. The string grammar accepts `T`, `t`, or a space as the date/time
separator, dot or comma fractions, `Z`/`z`, and signed offsets in `+HH`, `+HHMM`, or
`+HH:MM` form. Four-digit years 0001–9999 are supported. The current cache serializes
UTC ISO values and the inspected backend supplies creation/expiry timestamps.

Missing dates, date-only or timezone-less strings, overflowed calendar dates,
invalid time or offset components, trailing junk, and precision beyond six fraction
digits are rejected. No decoding path uses the current time as a substitute.
The existing generic date helper is unchanged for other models. Error messages use
static field labels and do not include received values or source payloads.

The new decoder deliberately tightens historical input acceptance. A full checkout
must exercise real server payload fixtures and older supported cache fixtures
before release. A timestamp that was already fabricated and saved as valid ISO data
cannot be identified retrospectively by this change.

## Preserved behavior and limits

Public const constructors and all their defaults are unchanged. Direct constructor
callers are not validated by these factory guards. `ParsedPaymentEvent` is unchanged
and remains a separate outstanding decoder review. Absent/null rail and currency
metadata retain existing Rwanda/RWF compatibility defaults; explicit other values
are rejected. Receiver/network defaults, label formatting and transaction-reference
redaction in the cache retain prior behavior. This is not proof of receiver validity,
server authorization, contribution ownership, or backend financial correctness.

No RPC, USSD launch method, amount-entry formatter, SMS parser, ledger mutation,
authentication policy, database schema, dependency version, or asset is changed.
No request is sent or replayed by this decoder. Binding a created intent to its
specific request and checking expiry immediately before USSD handoff remain separate
end-to-end validation requirements; a successful decode is not payment approval.

## Cache policy

The existing cache serializer and cache lifecycle are preserved byte-for-byte.
Payment-row corruption is **not** isolated by dropping rows: doing so could preserve
an apparently complete history or a pending count inconsistent with its records.
A malformed payment/intent propagates through snapshot decoding. The existing cache
reader then returns no snapshot and removes the invalid cached payload. A fresh
server refresh is required. This trades offline availability for avoiding fabricated
financial evidence. The earlier per-group *summary* omission policy is unchanged.

## Tests and application validation

Two new suites contain 114 authored cases: 106 decoder cases and eight cache cases.
They cover numeric and alias boundaries, metadata, real zero rejection for payment
rows, absent status, safe errors, UTC/offset/leap-date parsing, expired and inverted
lifetimes, input preservation, legacy field precedence, serializer round-trips,
privacy redaction and the existing fail-closed cache read.

Thirteen executable Python checks verify source wiring only, not Dart semantics.
CI runs the source checks alongside the existing regressions. The existing
candidate scope adds both new Dart files and both test suites without
removing or reordering existing targets. Its analysis stage covers the full checkout.

Run against the complete authorized checkout with the pinned Flutter/Dart versions
and its existing locked dependencies already resolved:

```bash
python3 scripts/qa/verify_candidate.py --check
python3 scripts/qa/verify_candidate.py --run
bash scripts/qa/run_integrated_candidate_checks.sh
```

In this execution, no Dart or Flutter checks ran. The actual preflight reports the
missing full-checkout `pubspec.yaml`; SDK executables are also unavailable and the
SDK host could not be resolved. Authored tests are not passing application tests.
No formatting, type checking, widget/device execution or release is certified.

## Primary documentation checked

- Dart `num.toInt` truncation: https://api.dart.dev/dart-core/num/toInt.html
- Dart native/web integer precision: https://dart.dev/resources/language/number-representation
- Dart `DateTime.parse` timezone conversion and calendar overflow:
  https://api.dart.dev/dart-core/DateTime/parse.html
- UTC conversion: https://api.dart.dev/dart-core/DateTime/toUtc.html

Documentation inspection is not a substitute for executing the pinned application.
