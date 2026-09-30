# Admin PWA cache and account isolation review — 2026-09-28

## Implemented in the local candidate

- The install-time service worker requests the static shell and bundle without credentials, rejects redirects, and rejects a response whose final URL differs from the requested asset. A failed install deletes its partial cache. Runtime requests are still admitted to the cache only for the installed static asset URLs or navigation shell; API responses are never added.
- The generated-build and deployed-URL gates now require those worker controls. The deployed gate expects the current root shell (`./`) rather than the retired `./index.html` cache entry.
- The browser lifecycle QA now opens two tabs and checks that an account-specific, no-store endpoint changes from account A to B in both, is absent from Cache Storage, fails while offline, and remains fresh through a worker upgrade. This is a synthetic endpoint, not an authenticated account switch.
- Admin repository-derived state now keys off the active auth user ID. The identity provider accepts only an identity whose user ID matches that session; signed-out events yield no active user. This prevents an old account identity result from being rendered as the new account and rebuilds repository-derived providers when an operator changes.

## Local evidence

| Check | Result |
| --- | --- |
| `node scripts/tests/admin_pwa_worker_cache_test.mjs` | Pass; install request policy, static navigation/asset cache, private request bypass, old cache retirement and failed redirect cleanup. |
| `flutter test test/admin_session_scope_test.dart test/admin_pwa_test.dart` | 29/29 pass; account-switch identity binding and repository invalidation included. |
| `flutter test test/admin_*.dart` | 233/233 pass after aligning mocked signed-in sessions with explicit user IDs. |
| Targeted `dart analyze` | Clean for touched Dart source and new test. |
| `node --check` for worker template, lifecycle QA and VM test | Pass. |
| Full browser lifecycle QA | Not run: no current hash-verified, backend-free synthetic Admin build report was available in this checkout. |

## Required deployment acceptance

U08 remains **unverified** until an isolated, hash-pinned release candidate and the deployed Admin origin are exercised in real browsers. Test a warm old-to-new worker upgrade, partial update failure, closed and open tabs, installed PWA restart, offline navigation, account A sign-out and account B sign-in, revoked Admin access, and no previous account financial records in either tab or Cache Storage. Repeat on the supported desktop and mobile browsers. Read back the deployed worker, bootstrap and response headers; local source and synthetic account tokens do not prove live session isolation.

The current worker intentionally keeps an offline static sign-in shell. It does not cache authenticated API data. An already rendered page can remain visible until auth-state propagation or navigation, so real cross-tab logout and server-side revocation visibility need explicit browser acceptance.
