# Payment-intent decoding — Increment 11 (27 September 2026)

## Source scope

This increment changes only the PaymentIntentModel JSON factory, wires in its
private helper part, adds two Dart test suites and a source-wiring suite, and
extends the existing candidate validation scope. The public constructors,
Contribution, ParsedPaymentEvent, and the isAwaitingTransfer getter are preserved.
There are no payment/ledger writes, provider calls, USSD launches, UI changes,
cache storage edits, dependency changes or backend migrations in this increment.
revolut-design remains the sole design authority.

## Accepted transport

A decoded intent must contain a nonblank id, collection_id and explicit status.
Unknown nonblank statuses remain readable and are not converted to pending.
The existing isAwaitingTransfer implementation still determines presentation
eligibility; decoding alone neither authorizes nor executes a payment.

amount_minor or expected_amount_rwf must supply a positive finite whole number.
Both non-null spellings, when present, must be individually valid and agree.
Integral doubles remain accepted; strings, booleans, fractions, zero/negative
amounts, NaN, infinities and values above 9,007,199,254,740,991 are rejected.
The upper bound is a native/web transport precision constraint, not a MoMo
or product contribution limit. It cannot detect rounding that already happened
before the decoder received a floating-point number.

created_at and expires_at must be explicit DateTime objects or zoned timestamp
strings with real calendar components. Strings use YYYY-MM-DD, a T or space,
HH:MM:SS, optional 1–6 fractional digits, and Z/z or signed HH, HHMM, HH:MM
offset. Local/date-only strings, calendar rollovers, bad time/offset components
and submicrosecond fractions are rejected. Typed DateTime objects preserve
their instant in UTC; normalization already performed by their caller cannot
be detected retrospectively. Expiry must be later than creation. An expired
historical intent with a valid lifetime remains readable. No current clock
value is substituted for a missing date and no freshness decision is made
by the JSON factory.

Optional rail/currency defaults (Rwanda MoMo/RWF), network fallback (mtn_momo),
and optional display-field defaults/trim behavior remain unchanged for existing
legacy inputs. Wrongly typed optional strings now raise a static FormatException.
This increment does not validate receiver ownership or provider routing.

## Cache boundary and compatibility

The cache serializer already writes UTC ISO timestamps and explicit status and
amount fields. Valid v4 snapshots and valid legacy amount-key snapshots are
covered by authored tests. A malformed cached intent continues to reject the
whole snapshot under the existing cache read policy; this may remove that cached
snapshot and require a fresh server read. It is NOT per-intent salvage. The
per-summary recovery from Increment 09 is unchanged. No old storage is migrated
or cleared merely by generating this source package.

Stricter rejection of malformed transport is intentional. Full-checkout tests
and endpoint contract validation must check actual server payloads and any test
fixtures before release. The original generic date helper remains in place for
unrelated models; those other decoders are not certified by this change.

## Verification boundary

The Dart/Flutter SDK is absent in this runtime. The new Dart suites have NOT run;
there is no compiler, formatter, widget, native/web build or live backend pass.
Python source-wiring tests inspect code strings only. Installer checks and file
hashes verify packaging/application of bytes, not application behavior.

Apply only after the filed Increment 10 source candidate, with the original
collect_payment_models.dart matching the recorded original hash. The installer
is not a cumulative one-step upgrade from an untouched original checkout.
Extract outside the full authorized checkout and stop concurrent writers:

```bash
python3 installer/apply_patch.py /path/to/COOL --check
python3 installer/apply_patch.py /path/to/COOL --apply
cd /path/to/COOL
python3 scripts/qa/verify_candidate.py --check
python3 scripts/qa/verify_candidate.py --run
bash scripts/qa/run_integrated_candidate_checks.sh
```

All existing targets remain in the candidate list, with new targets appended.
Use the complete pinned-SDK checkout with resolved locked dependencies, not this
partial overlay. Deployment and original Google Drive source changes are not
part of the delivery.

## Filing status

This increment is pending Google Drive filing. Only read actions were exposed
by the Google Drive connection during this execution. No new Drive folder, file
or index was created. File creation/upload is required to file the payload and
verify its remote bytes. A pending manifest is not an upload receipt.

## Official language references checked

- https://api.dart.dev/dart-core/num/toInt.html
- https://api.dart.dev/dart-core/DateTime/parse.html
- https://dart.dev/resources/language/number-representation

These references explain truncation, timestamp overflow parsing and differing
native/web number representations. They do not replace application execution.
