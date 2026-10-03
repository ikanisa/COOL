# Refactor integration after Overview fix

The existing37-file SDK/widget suite passed1066 tests with zero failures and three retained SQL-evidence-dependent skips. The two earlier Overview failures are corrected; the original failed batch remains retained. All captured library, test, asset, lock and resolved package inputs stayed unchanged during this62.5-second run. Counts overlap the25-test Overview suite and must not be added together.

The three skipped cases require actual current rollback SQL receipts for roster status/read/recovery. They are unverified here; mock or dated decoder packets do not close those requirements. Analysis, API preservation, module-size and source-consumer checks in the responsibility-based refactor packet remain scoped proof. Hosted CI and the one final immutable integrated candidate remain open.

Commands, all source hashes, exact skip reasons and log/event hashes are in `refactor-integration-run.json`.
