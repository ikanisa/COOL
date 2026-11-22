# Verified Integration v2 — cache, financial display and release boundaries

This extends the filed 174-file hardening candidate. It does not replace the complete repository, deploy SQL, change public sharing or approve production. `revolut-design` remains the sole design authority. All files are delivered as new artifacts.

## Protected recovery snapshots

The production `CollectRepository` constructor uses `CollectOfflineCache.protected()`. The legacy adapter remains for explicit synthetic tests/migration tools, while the fixture repository retains its previous adapter. Do not override the production cache with that adapter. The source test checks the live-constructor binding; the complete application still needs an import/call-site review.

A live read passes the authenticated user ID and rejects a returned snapshot for another identity. Android stores only AES-GCM ciphertext beneath `noBackupFilesDir`; keys stay in Android Keystore. The cipher authenticates both schema and owner as additional authenticated data. Files are replaced with AtomicFile; corrupt/key-unavailable reads preserve their bytes and refuse to display financial data. iOS uses CryptoKit AES-GCM, a WhenUnlockedThisDeviceOnly Keychain key, atomic protected files and backup exclusion. iOS code is embedded in the existing AppDelegate so no project-file registration is silently required.

Legacy plaintext snapshot keys are discarded, not re-imported as trusted finance. The next successful server read repopulates the protected cache. This intentionally requires fresh network access after migration. Web/unsupported hosts do not persist a financial snapshot through the unavailable native bridge; there is no plaintext fallback. Supabase session-token storage and browser service-worker storage are separate issues and were not redesigned here.

The cache is optional, bounded to 1 MiB of UTF-8 JSON and never authoritative. No current-time value is invented when a saved timestamp is absent. Cache failures during unawaited successful server reads are handled without logging raw payloads. Logout clearing retains the repository's serial clear/epoch discipline. Platform clear failures surface; a failure is not a verified deletion. Cryptographic tests do not prove Keystore/Keychain availability, hardware backing, reinstall behavior or native application compilation.

## Truthful financial display

Home uses the whole-history aggregate maps and owned-group count, not a sum of a bounded recent list. Without those maps it shows `Not available`. Shared summary providers no longer reconstruct balances from partial transactions; editorial group cards accept absent summaries and distinguish absence from a supplied zero. The existing design components remain in use. Other legacy totals/pending-count providers and group detail consumers require a full-checkout review; this is not a claim that every data fallback has been removed.

## Reconciliation review binding

The staged review table now captures a SHA-256 fingerprint of the payment's economic identity, including amount, receiver, provider, transaction reference, collection and payer/member binding. Both approval and finalization recheck it under database locks. A changed candidate requires a new review. This does not prove that independent provider evidence is genuine or implement the still-required reviewer-role revocation fence/operator workflow. No SQL was executed here.

## Admin build headers

The CI Admin build runs the read-only-by-default `admin_headers.py` helper with explicit `--apply`. It only creates the reviewed policy when no policy exists, or accepts an exact match. A different existing policy fails without replacement. It does not weaken an existing stricter CSP by guessing how to merge it. The policy disables storage of new Admin HTTP responses and applies frame/base/object protections, nosniff and no-referrer. It deliberately does not invent a script/connect policy without the complete deployment inventory. Existing installed service workers may still hold older caches; their migration remains a separate gate.

## Execute before deployment

Run the full pinned Flutter formatter, analyzer and every test, including both new Dart suites, then native Android/iOS builds and the real Keystore/Keychain lifecycle tests. Run `run_snapshot_jvm_tests.sh`, `admin_headers_test.py` and `v2_source_test.py`; these isolated tests do not replace the application checks. Repeat real database proposal/approval/mutation/finalization tests with concurrent transactions, account revocation and expired approvals. Apply only newly generated migrations appropriate to the actual schema: do not re-register a create-table staging file over an already applied earlier version.

The full audit register is retained with 100 IDs, dependencies and acceptance criteria. No task is marked production-approved. Source sharing, live credentials/configuration, protected GitHub environments, complete backend integration, physical SIM tests, regulatory/vendor approvals and restore/pilot evidence remain external or full-checkout gates.

## Contract references

- https://developer.android.com/privacy-and-security/keystore
- https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly
- https://developers.cloudflare.com/workers/static-assets/headers/
