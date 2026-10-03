# Member Realtime and cache authority review

## Demonstrated defect and correction

The prior valid-fixture run passed thirteen cases and retained four assertion failures plus one fixture error. Three failures were actual production behavior: a frame belonging to a departed topic caused an extra profile read after same-user session replacement, A to B to A, or account replacement. The locked SDK routes messages by topic, so reusing the static topic attached the departed frame to the new callback. This did not establish a private-row publication leak.

The repository now gives every authority scope a unique topic, captures its existing sticky session before subscribing, and requires that session to remain current before a callback refresh. The shared coordinator and valid same-session token refresh remain intact. The two other prior issues were fixture timing and a teardown helper reading disposed repository state; they remain distinct from the runtime defect.

## Accepted evidence

Strict current attempt4 passed **18 cases, zero failures/errors/skips**, with **fatal analysis clean**. Its 849 source inputs, 6,191 exported inputs and locked SDK remained unchanged. The completed packet recorded no live-source drift. The acceptance includes legitimate active joins, duplicate and irrelevant frames, failed-binding rejoin and missed membership reduction, same-user replacement, A to B to A, account replacement, supported token refresh, an old in-flight profile response, permission denial/private-cache cleanup, deliberate recovery, logout and disposal.

The current source readback in `accepted-current-proof.json` binds the repository, unchanged shared coordinator and both fixtures exactly. A full-byte comparison against the accepted Data22 repository permits only three reviewed substitutions inside `_ensureRealtimeSync`; all other repository bodies match. Data22's VM/Chrome data, mutation and staged-read results can therefore be retained for those unchanged bodies, while this SDK packet accepts the new Realtime behavior. The raw diff is preserved separately.

## Retained failures and limits

Attempt1 failed at fixture setup before the intended behavior; attempt2 reproduced the real static-topic issue. Attempt3 passed behavior but retained an analyzer information finding because its original gate did not fail on infos. Attempt4 adds the brace repair and a fatal-infos gate. Every original packet remains unchanged.

This is a scoped client acceptance. It does not certify signed JWTs, deployed RLS, provider delivery, every Admin/Gateway consumer, a physical device, or whole-system closure. Current generated-query performance and full application source integration remain separate local acceptance. No SQL, tests, browser or provider runs are executed by this review.
