# Runtime-control client acceptance

The final worker client packet is `client-runtime-attempt2/validation.json`, SHA256 `800ae3340f9c180ad4c07fda3ca178cea75f2583ec6f2e27dbdd9a9d454d948c`. All205 tests pass; nine scoped analyzer inputs report no issues. Flutter3.44.4/Dart3.12.2 versions, exact commands, stdout and log hashes are retained.332 lib/test/lock/SQL/contract/gate source hashes match before and after execution. This is a dated source packet; root's following settings-screen changes require their own current-source acceptance.

## Implemented behavior

Admin feature toggles read `row.extra.runtime_revision`, refuse a missing/malformed revision before opening the action, and send `admin_set_feature_flag_v2` with the exact key, boolean, revision and operator reason. The exact eight-field ACK binds key/state/history to the request. The legacy unversioned receipt is no longer accepted. Conflicts request a refresh/review; no action is automatically resent. Existing Admin session and provider-scope fences remain active.

Preference reads use `get_notification_preferences_v2` with a captured session Bearer token. Exactly six fields and the four actual boolean choices are accepted. Cached/default state never invents a server revision. Only a valid fresh absent-row receipt grants revision0. Saves send `set_notification_preferences_v2` with all four booleans and the loaded revision, then require the exact seven-field ACK bound to the captured user and expected revision. Changed and unchanged acknowledgments use different exact revision relationships.

Saved state changes only after acknowledgment. A conflict, uncertain error or malformed receipt invalidates the local revision and retains the intended edit. Background reloads cannot authorize a retry or silently replace that saved choice. An explicit refresh obtains a new revision and preserves the intended edit for review. Late reads begun either before or during a pending write cannot overwrite the later acknowledged save. Earlier-session failures and A→B→A replies are rejected before private error text/state escapes.

Repository helpers for the root-owned settings UI:

- `notificationPreferencesNeedsRefresh`: live saves require a valid fresh revision. The authorized no-backend fixture constructor alone permits preview choices without inventing a revision; production offline writes fail closed.
- `notificationPreferencesRevision`: nullable server revision; never persist or synthesize it from local defaults.
- `pendingNotificationPreferences`: retained dirty intent, separate from the acknowledged saved choice.
- `refreshNotificationPreferences()`: explicit read only; preserves dirty intent and never retries a save.
- `discardPendingNotificationPreferences()`: local intent discard; refuses an in-flight save and preserves any null revision/refresh requirement after uncertainty.
- `updateNotificationPreferences(...)`: one versioned request; no automatic retry/rebase. Concurrent saves are refused; a newer local intent remains available when an earlier save completes.

## Actual local coverage and limits

The two new HTTP test files exercise the real pinned Supabase Dart SDK through MockClient, including exact requests, null/array/missing/unknown responses, strict integer/version/bool types, wrong identities, mismatched revisions, invalid calendar timestamps, changed/no-change ACKs,40001, explicit refresh/retry, local discard, preview versus production offline behavior, concurrent intent and delayed responses. Session changes use the SDK's actual verifyOTP/Auth event path; all Auth/HTTP records are synthetic. Existing Admin contracts, shared session fencing, realtime membership revocation and account-switch regressions are also preserved. Two old realtime fixtures were migrated only from direct preference-table responses to the exact v2 read receipt.

No database, provider or hosted calls are made by this client gate. Real SQL semantics and concurrency are the independent root147 packets. This packet does not verify the subsequent settings UI, whole-app production readiness, hosted deployment or provider accuracy.

Reproduce locally with a new unused output directory:

```sh
python3 scripts/tests/runtime_control_client_gate.py \
  --flutter /Volumes/PRO-G40/Development/Flutter/flutter/bin/flutter \
  --output docs/release/runtime-controls-2026-09-30/client-runtime-next
```
