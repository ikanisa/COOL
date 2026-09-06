# Rwanda group-photo integration

6 September 2026. **Implemented and tested locally; database migrations deployed and verified. Application distribution and full native acceptance remain pending.** This is a local QA candidate, not native design acceptance or production approval.

## Member experience

The actual group-creation and owner-edit screens now share the Rwanda photo picker. Suggestions follow the chosen group type. Members can browse themes, search English/Kinyarwanda/French catalogue terms, explicitly choose an occasion, select a photo and confirm with **Use photo**. Closing the picker discards its draft. The own-photo option and explicit removal remain available. No religion or sensitive occasion is inferred from a person's profile or group name.

The 44 concepts produce 88 bundled WebP files: 768 × 1024 covers and 192 × 256 thumbnails, **4,651,698 bytes combined**. The active six wedding images use version 2. Full-resolution originals, prompts and research are excluded from the app asset bundle. `scripts/assets/build_rwanda_group_runtime.mjs` builds the derivatives, their hash manifest and the Dart catalogue without changing source images.

Saved library selections use `collect-cover:<id>:v<version>` in the existing image field. Creation, editing, offline cache and group cards resolve the same reference. Existing uploaded photos remain first priority. Unknown versions fall back safely; removal clears the stored image.

Dedicated Buri munsi and Gikundiro covers remain outside the general library. Their default assignment requires the existing governed platform slug (`buri-munsi` or `gikundiro`) together with public and platform-sponsored status. A typed group name cannot obtain either identity. No existing live group record was rewritten.

## Persistence and deployment order

The new migration is `supabase/migrations/20260906160000_group_cover_bank_and_atomic_creation_media.sql`. It adds `create_private_group_with_owner_media_attested`, which calls the existing attested/geographic creation function and saves the chosen cover and colour in the same transaction. An invalid cover rolls back group creation and capability consumption. The existing payment-receiver handling and integrity request payload are retained.

The migration also validates the exact cover/version allowlist on writes and restricts dedicated covers to their governed groups. Authenticated callers receive the new RPC grant; anonymous callers do not. Existing upload formats remain supported.

Apply and verify this migration **before deploying an app build using the new RPC**. The previous creation RPC remains available to older clients. There is deliberately no client fallback that pretends unsaved media was persisted. The photo migration and preceding MoMo-code migration were applied to the linked COOL database and independently read back. All 124 migration versions now match. Four deployed function bodies match the reviewed SQL, anonymous photo-RPC execution returns HTTP 401 / SQLSTATE 42501, and collection RLS remains enabled. No customer record was rewritten, no production app was deployed, and no APK was distributed. See [deployment and native follow-up](DEPLOYMENT-AND-NATIVE-STATUS.md).

## Verification

- **Six native Android photo-journey checks passed** on the fresh dev fixture: portrait/landscape at 100% and 200% text, cancel and remove/save. The installed APK hash matches the tested build. See [native verification](NATIVE-VERIFICATION.json).
- **136 Flutter tests passed** across the photo-bank, editorial cards, repository, SQL contracts, mobile interactions and completion suites. This includes two added landscape-keyboard regressions. The short-viewport photo sheet scrolls its header and confirmation with its content to avoid the native 38-pixel overflow found during this follow-up.
- New checks cover type/context eligibility, reserved identities, version resolution, create/edit/remove and offline reload, deliberate selection/cancel, search and empty recovery, uploaded-image priority, and safe fallback.
- Layout checks cover 320-pixel width at 200% text, keyboard-open phone and landscape. These are widget tests, not native keyboard or device evidence.
- **Nine executable database checks passed** using the real new migration and existing capability/geographic functions in isolated PostgreSQL. Fixture auth, dependency tables and the base creation function are used; production RLS and live deployment are outside this harness. The harness uses [PGlite's documented JavaScript API](https://pglite.dev/docs/api).
- Focused Dart analysis reported no issues. Asset hashes, derivative counts and byte totals are recorded in `INTEGRATION-VERIFICATION.json` and `assets/group_covers/rwanda/runtime-manifest.json`.

The local widget capture is `.cache/group-cover-integration/picker-wedding.png`. The interactive fixture entry point is `integration_test/group_cover_review_app.dart`, opened at [the local photo journey](http://collect.localhost:4195/). It uses the real screens and cards with synthetic groups. A browser reload resets this fixture; durable database and cache behavior is tested separately above. The entry point requires `COLLECT_GROUP_COVER_QA=true` and refuses release mode.

Browser review confirmed the actual owner form, refreshed wedding suggestions, selection → **Use photo** → **Save**, the resulting wedding card, dedicated Buri munsi and Gikundiro cards, and the create-group first step. Search and the complete create journey passed widget tests; browser text automation did not enter the search term, so that specific browser interaction is not claimed as verified. A fresh compilation was needed to load the QA route's Material scaffold correctly.

Start the browser fixture with:

```sh
flutter run --no-pub -d web-server --web-hostname 127.0.0.1 --web-port 4195 --target integration_test/group_cover_review_app.dart --dart-define=COLLECT_GROUP_COVER_QA=true --dart-define=COLLECT_MOBILE_EVIDENCE_PLATFORM=android
```

## Design and outstanding acceptance

The picker adapts the selected native catalogue comparator `033-add-new-catalogue.jpg` for search, category navigation and a neutral task surface. Image choices and group cards use the owner's `Cards.png` editorial-photo reference through Collect's existing shared tokens. These source images were inspected; they are comparators, not runtime assets.

`make mobile-design-gate` remains **BLOCKED** by existing missing or stale acceptance/source records, native build and route/state evidence, and open findings. No score, required case, baseline or approval was altered to pass it. Local cultural/language review, full native crop and interaction acceptance, and application distribution remain outstanding. The database migrations are deployed and verified. Every catalogue asset therefore retains `runtime_ready: false` despite the local implementation.
