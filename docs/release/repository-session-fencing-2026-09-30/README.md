# P07 repository session fencing — local verification

Date: 30 September 2026. Scope: client notification registration, account-change
cleanup and sign-out in `lib/shared/repositories/collect_repository.dart`.
This packet records local implementation and focused mocked HTTP checks. P07
production acceptance remains open.

## Implemented

- Auth identity includes both user ID and JWT session ID. A replacement session
  for the same user invalidates prior loads, registration bookkeeping and
  account-change cleanup. Refreshing a token for the same session preserves its
  identity. Local JWT decoding only distinguishes lifecycle operations; server
  Auth and RLS remain authoritative.
- Registration captures the identity, token and operation generation before its
  RPC. Explicit Authorization pins the request to that token. A late response
  cannot overwrite a newer registration. A successful response for a replaced
  session receives best-effort unregister using its original token and tuple.
- The stable server error `notification_registration_session_stale` becomes the
  safe repository error “Sign in again to register notifications on this
  device.” Superseded requests cannot change the new account's error state.
- Sign-out captures its original identity, token, profile and registration. It
  disables native capture using the original owner, pins unregister and consent
  RPC credentials, and checks the identity and operation after each await.
  When another session has appeared, only the original token is sent to Auth
  logout with explicit `scope=local`; no new-account native or cache cleanup is
  started afterward.
- Local Auth clear is invoked only while the captured session is still current.
  The repository performs no local reset after the Auth HTTP await. Native
  shutdown and cache-clear failures fail closed with safe errors. Cache restore
  is suspended following a current-account clear failure.

## Verified SDK behavior

The installed pinned source was inspected, and its fingerprints are retained in
`verification.json`:

- GoTrue 2.27.1 `GoTrueClient.signOut` defaults to local scope, captures the token
  and removes its local session synchronously before the PKCE storage await and
  HTTP call. It does not clear the local session again after the HTTP response.
- `GoTrueAdminApi.signOut(jwt)` defaults to **global** scope. This implementation
  explicitly passes `SignOutScope.local` when revoking a captured old session.
  That API uses the supplied JWT and does not mutate local Auth state. No service
  role key is supplied or required for this self-session logout call.
- Supabase 2.16.0 `AuthHttpClient` uses `putIfAbsent` for Authorization, preserving
  the captured token explicitly supplied to the PostgREST builder.

## Checks

Runtime: Flutter **3.44.4**, Dart **3.12.2**, from
`/Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter`. `runtime.json` retains
the exact revision. No dependency upgrades or global runtime changes were made.

```sh
PUB_CACHE="$PWD/.cache/pub-cache-qa-20260929" \
  /Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter test --no-pub \
  test/shared/repository_session_fencing_test.dart \
  test/shared/member_history_pagination_test.dart --reporter expanded

PUB_CACHE="$PWD/.cache/pub-cache-qa-20260929" \
  /Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter analyze --no-pub \
  --fatal-infos lib/shared/repositories/collect_repository.dart \
  test/shared/repository_session_fencing_test.dart \
  test/shared/member_history_pagination_test.dart
```

Results: **35 passing tests** (24 new session-race tests and 11 existing history /
cache / auth-change regressions); analyzer **no issues**. Both commands exited
zero. Source and manifest fingerprints were unchanged across these checks.

The new tests execute the actual repository and pinned Supabase/GoTrue HTTP
paths through `http` MockClient with response barriers. They cover different-user
and same-user replacement sessions, token refresh, out-of-order registration,
registration versus logout, same-device cleanup, stale rejection, native/cache
failures, cleanup RPC failures, delayed Auth HTTP and PKCE storage, auth-change
cleanup supersession, and disposal. Native and bootstrap reads are test doubles;
cache serialization uses the actual cache with mocked SharedPreferences.

## Limits and remaining work

- No provider, live Auth, database, device, push-delivery or deployment calls were
  made. The same-device cleanup test models the server's exact-session predicate;
  it does not prove SQL transaction ordering. Migration 141's live-session check,
  monotonic session-age binding and exact-session unregister require their
  separate database evidence and deployment verification.
- An already-sent HTTP request cannot be cancelled by local generation checks.
  Offline cleanup may fail. Server session revocation and registration ordering
  remain necessary, including after process termination.
- The notification service currently catches registration failures. The safe
  repository error is tested; a dedicated visible member-settings recovery and
  retry flow is not implemented or verified by this packet.
- Physical Android/iOS lifecycle, native method-channel timing, APNs/FCM token
  rotation and delivery, account switching across process death, and cold-start
  behavior still require device/provider tests. These tests do not establish
  whole-app or P07 release acceptance.
- `pubspec.yaml` and `pubspec.lock` hashes identify the test-time graph. They are
  evidence of this run, not a claim that future concurrent manifest edits have
  been reverified. Package-cache source is fingerprinted, not copied.

`verification.json` contains exact commands, exit codes, before/after source
SHA-256 values and log SHA-256 values. Synthetic tokens in tests identify no real
users or credentials. The historical working tree contains other changes;
this packet does not attribute the entire repository diff to this task.
