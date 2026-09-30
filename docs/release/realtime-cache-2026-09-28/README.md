# D10 mobile realtime and cache review — 28 September 2026

## Implemented in the local checkout

- Realtime joins now request a scoped RPC reconciliation, including every successful rejoin. This closes the read-to-subscribe and disconnected-event gaps without treating the invalidation stream as financial data.
- A leading 350 ms debounce prevents continuous events from postponing refresh indefinitely. Each window runs at most one leading and one trailing refresh; events arriving during the trailing read wait for a new debounce window. Only one refresh runs at a time. The last 256 event IDs suppress duplicate deliveries without an unbounded in-memory set.
- Channel errors, closes and timeouts trigger a new binding after bounded exponential delays of 1–32 seconds. Callbacks from retired bindings are ignored. A connection that remains healthy for 30 seconds resets the retry delay.
- The mobile subscription is bound to its authenticated user. Sign-out or account change disposes the old subscription and clears in-memory member state before loading the next account. Profile RPC identity must match the authenticated user.
- A successful scoped catalogue read replaces removed groups; a narrowed catalogue clears the prior offline snapshot before writing the replacement. Permission errors and inconsistent profile or balance scope clear member state and suspend stale-cache restore until access is revalidated.

## Local evidence

- `flutter test --no-pub test/shared/realtime_invalidation_recovery_test.dart test/shared/member_history_pagination_test.dart test/shared/collect_repository_read_contract_test.dart test/shared/collect_offline_cache_test.dart`: 27 tests passed after the bounded burst change.
- `flutter analyze --no-pub lib/core/supabase/realtime_invalidation.dart lib/shared/repositories/collect_repository.dart lib/shared/repositories/collect_repository_live_reader.dart test/shared/realtime_invalidation_recovery_test.dart`: no issues.

The tests exercise the scheduling coordinator and synthetic scoped RPC responses, including a 403 response, a removed private group, a mismatched profile and an account switch. They do not simulate a real Supabase socket or prove deployed row policies.

## Remaining verification

1. On a staging backend with current migrations, revoke membership during a mobile session and verify the group and summaries disappear after its event, after a socket outage/rejoin, and after app restart. Confirm the revoked row never appears in the protected snapshot.
2. Repeat with two real accounts on one device and browser, including sign-out, offline restart, token refresh and an in-flight RPC from the prior account. Read back protected storage and rendered UI.
3. Load test the global invalidation table and client refresh rate under representative traffic. The mobile client caps concurrency, but the server currently publishes broad area events to all authenticated subscribers.
4. Confirm channel binding rejection, token expiry and recovery on the deployed Supabase version. The local retry behavior has synthetic coordinator tests and source review, not a live websocket integration result.
5. An offline device cannot learn about a server-side membership revocation until it reconnects. If instant offline revocation is a policy requirement, use a shorter cache validity rule or online-only access for sensitive screens and obtain product approval for that availability tradeoff.

**D10 status:** local hardening implemented and focused tests passed; deployed and device acceptance remain open. No production deployment or authorization is implied.
