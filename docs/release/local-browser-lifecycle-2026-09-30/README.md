# Local browser lifecycle — local acceptance passed

The normal Admin production entrypoint and the separate public static builder are exercised against isolated loopback origins with synthetic Auth/RPC transport. The real Supabase Auth SDK, Flutter browser runtime and production service worker are used. Database semantics are verified separately through the root-owned142/143/144/145 fixtures; this harness makes no database, provider or hosted calls.

## Corrections already supported by actual evidence

- Normal production Admin OTP verification recreated the router and selected public marketing at a configured noncanonical Admin origin. Diagnostic8 preserves this browser failure. Production Admin, CI compile and local evidence build callers now explicitly compile `COLLECT_PUBLIC_LANDING_HOME=false`. `test/admin_entrypoint_rebuild_test.dart` passes the signed-out → authorized → signed-out router transition; the final normal-build browser run will verify the configured-origin behavior.
- Browser discovery now accepts `ADMIN_PWA_CHROME` and discovers the installed Chromium runtime. Attempts1/2 preserve public-media/build and unavailable-browser failures. Diagnostics3–8 preserve real Flutter semantics/input observations.
- Actual Chromium warm update retained `flutter-app-cache`, `flutter-temp-cache` and `flutter-app-manifest`. Activation now removes these exact legacy names, removes previous Collect Admin versions, and preserves unrelated caches. Diagnostic12 preserves the failure; subsequent actual runs pass migration, worker claim, failed-install rollback and offline reload.
- Actual production logout emitted signed-out and disposed its shell before the awaited SDK call returned. The callback then invalidated providers through a disposed `WidgetRef`. The callback now checks `context.mounted` before further ref access. The same focused actual-router regression fails against the preserved old shell with `Cannot use ref after the widget was disposed` and passes on current source. The normal browser rerun must also show zero uncaught errors.

## Preserved attempt4

[Attempt4 report](attempt4-uncaught-logout/report.json) records all16 declared browser cases and every interaction assertion passing, all seven command gates passing with the exact project pin Flutter3.44.4, and507 source inputs unchanged. Acceptance remained **PARTIAL** because one uncaught logout error was observed. All507 exact source bytes, build hashes and command logs are preserved under `attempt4-uncaught-logout`; the isolated profile with synthetic Auth storage remains outside the report packet. Diagnostic18 retains the release stack locating the invalid provider access. Later evidence must supersede this attempt on current source.

## Current acceptance

[Attempt5 current-source report](attempt5-current-logout/report.json) **PASS**:37 assertions, all16 declared lifecycle cases, zero uncaught errors observed across every tab and installed window, and557 before/after source hashes unchanged. All seven command gates passed. The exact toolchain is Flutter3.44.4/ad70ec4617166f1c38e5d2bfd388af71fda14f06 and Chromium151.0.7922.34. The current production public builder accepted refreshed screenshot provenance runtime `aa22e9fdc2826af2480d7c4e2e4563d1209f5a49cbd2277ea9a3eec994acc382`.

The packet contains557 verified source copies,155 normal Admin build files and55 separate public build files. Its report SHA-256 is `d05af058a5aa01324cea35e8db16e36acab3bfe2d1433e3fa77a77483878fdfe`. The isolated synthetic Auth browser profile is excluded from the report packet. Alternative update artifacts remain hash-bound and retained in the task cache. All preceding failures and their source evidence remain preserved.

Passed cases include full page reload, server-only private editor restoration, reference-only sessionStorage, actual popup tabs/CAS, lost review/commit responses, staged commit recovery requiring fresh affirmation, static cache privacy, warm/failed updates, exact legacy cache migration, offline static launch/API failure, live revocation, actual SDK A→B→A, browser-enforced sessionStorage quota, missing unacknowledged source, cross-tab logout/SDK Auth storage cleanup and actual standalone PWA installation/offline reload. Public/Admin separation passed through distinct builds/origins, no Admin bundle in public, public storage isolation and404 private paths. Twelve external requests were blocked; authenticated application transport remained loopback only.

The current shell was also rebound to the root-owned actual144 SQL receipt packet:91 integrated roster tests including actual142/144 receipt decoding with no skip,57 file/XLSX regressions,1 actual Chromium bookmark test, clean eight-item analysis and Ruby source syntax passed with213 bound inputs unchanged. See the separate [current roster validation](../admin-roster-reload-2026-09-30/attempt3-current-logout/validation.json).

Run with the pinned Node runtime:

```sh
/Users/jeanbosco/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node scripts/qa/local_browser_lifecycle.mjs .cache/local-browser-lifecycle-20260930/NEW_ATTEMPT
```

The output must be new. A diagnostic reuse option (`COLLECT_BROWSER_REUSE_ARTIFACT`) requires a prior successful Admin build receipt and verifies every artifact hash; such a run cannot satisfy the final current-source acceptance gate. Normal runs hash runtime/web/fonts/locks/build callers/harness/tests before and after execution, bind every copied build file, retain screenshots/failure DOM and record observed coverage.

## Limits

Synthetic loopback Auth tokens are confined to the isolated browser profile and test transport. Roster bookmarks contain references/digests only; Supabase intentionally persists synthetic Auth sessions separately through its actual SDK. Public storage isolation is tested through distinct origins. The warm-update scenario changes static shell version metadata using the production postprocessor while retaining the same compiled runtime bytes; it does not certify an arbitrary breaking application/storage upgrade. Chromium local installation is separate from iOS/Android/physical-device/store acceptance. No design equivalence or100% claim is made.
