# Browser handled-diagnostic observation

Code-only verification, 2 October 2026. The new shared observer detects `CollectDiagnostics` failures written through `debugPrint`/`console.log`; browser console level no longer hides handled startup, framework or platform errors. Startup timeout and diagnostic suppression also fail acceptance. Info events remain observations and do not certify readiness.

The fixed JSON classifier permits exactly the eight current fields, the known codes and their correct severities, bounded integers and allowlisted surface/environment/build values. Unknown versions/codes, malformed/oversized declarations, duplicate keys and extra fields fail with fixed report data. Legacy console report paths sanitize declared diagnostic payloads so raw malformed text and arbitrary URL/detail fields are not retained. Ordinary existing console/page exceptions still follow their original failure rules.

Seven maintained consumers are integrated: Public Flutter media recorder, Admin browser QA, Admin CDP runtime smoke, current browser lifecycle, local browser lifecycle, Admin dialog flows and Admin PWA lifecycle. Existing pageerror and console checks remain. Lifecycle observers include all pages and the restarted installed context.

Four callers emit `diagnostic_observer_sources_before` and `diagnostic_observer_sources_after`, each containing exact helper and recorder SHA-256 entries, and fail source drift. The other three include the helper in their existing before/after source inventories. The Public reusable-compilation guard now refuses a prior artifact report without matching observer provenance.

Actual Node 24.19.0 verification passed all 58 tests with zero failures, cancellations, skips or todos. Tests execute the actual maintained CDP handler against synthetic console/exception messages, register and detach an EventEmitter observer at every console level, test all current Dart codes and field names, reject malformed/secret-bearing payloads, preserve favicon/error/assert semantics and refuse absent/changed artifact provenance. Ten changed/new MJS files passed `node --check`. This is local unit/source-contract and syntax evidence, not a browser execution. The displayed test output was truncated; the observed complete TAP summary and process exit are recorded without claiming a full retained TAP transcript.

No lib or CI source was edited. Parent ownership remains for CI test registration and PublicAppMedia Ruby receipt-validator/conservative-source-closure enforcement before recapture or publication. No browser build, live CDP session, render, capture, provider or deployment ran. Existing sealed media evidence remains historical.

See `result.json` for exact final source hashes, interface fields and limits; `captured-source/` and `seal.json` preserve the code readback.
