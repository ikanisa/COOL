# Current additive native history receipt

The actual native PostgreSQL run passed ten scenario groups. Its current
source-bound packet contains 22 requests, 15 successful pages and 41 actual SQL
statements. The six Flutter receipt-consumer tests passed against the exact
captured bytes and current source.

The profile is `current16_plus_admission_archive_and_history_v2`, with packet
format `collect.selfhost.actual-member-history-sql.v1`. It is separate from the
unchanged historical current14 and current16 profiles. Source identity is
`01887d9b750beda9ca6590ed17636b12e4926ab9e1eb3887e47b8afd6431701c`;
`INPUTS.json` lists every bound input. Source changes cause the consumer to fail
until a new real capture is produced; these files must not be rebound to changed
source.

From the repository root, use the exact Flutter version pinned in `.fvmrc`:

```sh
make test-history-selfhost FLUTTER=/absolute/path/to/flutter \
  DEFINES=docs/implementation/self-hosted-20261101/history/DEFINES.json
```

Only the three file-path values in the copied `DEFINES.json` were rebased from
the original execution directory to this retained repository folder. The
original SQL, packet, source inventory and their digests are unchanged.
`FLUTTER-EXECUTION.log` records the original command and six successful cases;
`FLUTTER-RESULT.json` and `NATIVE-RESULT.json` record the exact evidence scope.

The first run completed its ten native checks but failed exact-source parity
because `curated-platform-fixture.mjs` changed during execution. Its original
inputs and explicit failure remain under `previous-source-drift/`. A different
fresh original16 database clone produced the passing packet; the failed run's
rows and source inventory were not reused or relabeled.

All financial rows and Auth claims were synthetic, with actual SQL constraints,
the restricted normal owner and runtime role. There were zero external provider
calls. Managed GoTrue, financial posting, settlement, hosted service behavior and
production acceptance remain outside this receipt.
