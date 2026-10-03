# Pending local Admin checkpoint 04

This checkpoint waits for root's exception-SQL stable signal and Admin's gateway
page stable/focused-validation signal. No checkpoint04 source export or Flutter
build has started. The recorded prerequisite metadata is timestamp-bound and
will be replaced by the actual export manifest inventory.

The source export will select the existing tool's tracked plus nonignored
untracked runtime/test/tooling scope, verify migration timestamp uniqueness,
exclude private/build/cache/QA payload sources under its declared policy, copy
and read back exact bytes and modes, and compare the original source again.
It will use a fresh isolated destination:

`/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-04`

The derived build workspace will be separately created and verified:

`/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-admin-build-04`

The actual export's externally recorded manifest SHA256 will bind the copy,
installed Flutter pin, six locks and build runner. The app and three dependency
forks must resolve inside that work copy; other packages must resolve only to
the existing offline cache or pinned SDK. Plain compilation uses:

`flutter pub get --offline --enforce-lockfile`

`flutter build web --release --no-pub --no-wasm-dry-run --target lib/main_admin.dart`

No production backend Dart configuration is supplied. `AppEnv` defaults the
Supabase URL/key to empty and runtime initialization stays unavailable. A passing
plain build would be backend-unconfigured compilation, not live email sign-in,
owner approval, hosted readback, deployment, provider access or production
acceptance. Any separate evidence build sets `ADMIN_PWA_EVIDENCE_MODE=true` and
has its own output/hash/receipt and explicit synthetic classification.

The intended source binding includes email access/approval, investigations,
Android gateway Admin operations and supervisor run history. Actual bindings must
come from the final manifest, not this planned inventory. Original-tree changes
after capture will be reported as dated path/hash drift; compilation from an
exact retained copy cannot establish an original-tree freeze or source review.

The pristine source snapshot will receive a final exact artifact/source readback.
The configured MCP bridge, installation metadata and exact five-read host allowlist
may be checked through credential-free initialize/tools-list only. No tools/call,
OTP, SMS, hosted lifecycle or business mutation is part of this checkpoint.

The completed gateway packet remains separate at `../../android-gateway` with
38 JVM and 18 Flutter tests, incremental current API binding and no accepted APK.
Those focused results are not aggregated into this build's acceptance count.
