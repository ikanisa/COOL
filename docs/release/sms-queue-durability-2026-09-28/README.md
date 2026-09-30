# Android SMS queue durability review — 2026-09-28

## Result

**Partial, release unverified.** Consented eligible SMS is written to an encrypted, owner-bound, device-local queue before the receiver finishes. Flutter reads it only for the signed-in owner and removes it only after a verified server acknowledgement. The Android process does not perform authenticated background ingestion. A daemon executor, a process-local event bus, and an SMS broadcast are not OS-durable network jobs.

## Implemented in this pass

- `SmsQueueWorker.executeCapture` gives the `SMS_RECEIVED` `goAsync()` persistence task its own serial executor. Flutter method-channel and protected-snapshot operations cannot hold the same executor lane ahead of SMS capture. `SmsQueueStore` still locks concurrent queue reads, appends, and acknowledgements.
- `CollectSmsReceiver` uses the capture lane. Existing consent, owner, sender/body eligibility, byte bounds, encryption, capacity, and acknowledgement rules remain in effect.
- When Flutter attaches its event stream, `MainActivity` replays the current metadata-only queue sequence. This closes the race where an SMS was committed before the stream attached. The event contains no sender, body, owner ID, or receipt ID. The Flutter host already attempts a drain on startup and resume; the read itself is owner gated.
- The signed-in Flutter host now coalesces events received during an active drain and retries failed drains in the foreground after 5 seconds, 15 seconds, 1 minute, 5 minutes, then at most once per 15 minutes. It holds only one timer, cancels it on backgrounding, disposal, or sign-out, and retries immediately on return or a new receipt event. The native encrypted queue remains the source of truth.
- No boot receiver, raw-SMS WorkManager payload, background token store, or network upload was added. Those would require a defined authenticated service contract and consent model. A boot broadcast alone cannot ingest a receipt.

## Recovery and limits

| Event | Current behavior | Remaining acceptance evidence |
|---|---|---|
| Process death after encrypted commit | Ciphertext remains in private preferences. Next authenticated app start reads the queue. | Installed-device kill/relaunch and ciphertext/readback test. |
| Process death before commit or broadcast timeout | Receipt may be lost; Android does not guarantee replay to this receiver. Dedicated lane lowers starvation risk but is not a delivery guarantee. | Burst and Keystore-delay device tests; define operator recovery for missing receipt. |
| Reboot | Committed ciphertext remains unless device storage/key is lost. Next authenticated launch attempts drain. | Physical reboot, locked/unlocked device, owner and key state tests. |
| Doze or offline | Queue remains local. A signed-in foreground app retries failed drains with capped backoff; launch, resume, and receipt events also trigger a drain. Background/Doze execution is not promised. | Physical-device Doze and network-restoration tests, including long offline and OEM battery restrictions. |
| Force stop | The package can remain stopped until user action; neither a boot receiver nor WorkManager should be described as bypassing it. Next user launch can drain a committed queue. | Force-stop, subsequent SMS behavior and user relaunch test on supported Android versions. |
| Full queue, revoked consent, inaccessible key | Existing code preserves earlier ciphertext, exposes queue attention state, and refuses unsafe reads/overwrites. New SMS may be lost at capacity or when the key is unavailable. | 100/101 boundary, account switch, consent revoke, key loss and recovery procedure. |

Android documents that `SMS_RECEIVED_ACTION` is an implicit-broadcast exception, while `goAsync()` still has a bounded receiver execution window. WorkManager persists scheduled work across reboot but may be delayed by Doze and cannot supply a signed-in session by itself. Android 15 also keeps a force-stopped package stopped until user interaction. Sources: [implicit broadcast exceptions](https://developer.android.com/develop/background-work/background-tasks/broadcasts/broadcast-exceptions), [BroadcastReceiver API](https://developer.android.com/reference/android/content/BroadcastReceiver), [persistent task scheduling](https://developer.android.com/develop/background-work/background-tasks/persistent), [power restrictions](https://developer.android.com/topic/performance/power/power-details), [Android 15 stopped state](https://developer.android.com/about/versions/15/behavior-changes-all).

## Checks

- `./gradlew :app:testDevDebugUnitTest --no-daemon` — PASS; 11 JVM tests, zero failures or skips. The new test proves capture starts while a Flutter-lane task is blocked; the event-bus test checks replay sequence monotonicity.
- `flutter test --no-pub test/app_shell_test.dart` — PASS; 40 tests, including bounded and capped retry timing, coalescing, pause/resume, sign-out cancellation and a successful retry stopping the timer.
- `flutter analyze --no-pub lib/app/app.dart test/app_shell_test.dart` — PASS, no issues.
- `git diff --check` on touched tracked Android paths — PASS.
- No installed-device, real-SIM, OEM restriction, or signed-build test was performed. These are required before M02 can be marked complete.
