package app.cool.mobile.momo_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * Native BroadcastReceiver for incoming SMS.
 *
 * Privacy-first entry point for MoMo SMS ingestion:
 *
 * 1. Assembles multipart SMS from the broadcast intent.
 * 2. Checks opt-in consent from [MomoSmsPrefs].
 * 3. Filters sender against approved sender ID list BEFORE Flutter sees anything.
 * 4. Non-matching SMS is discarded immediately (< 1ms, no network, no queue).
 * 5. Matching SMS is written to SQLite offline queue.
 * 6. Enqueues WorkManager sync job.
 *
 * Uses [goAsync] to extend receiver lifecycle for the SQLite insert coroutine.
 *
 * Replaces the `another_telephony` plugin receiver that forwarded
 * ALL SMS to Flutter before any sender filtering occurred.
 */
class MomoSmsReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "MomoSmsReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        // 1. Assemble multipart SMS
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        val fullBody = messages.joinToString("") { it.messageBody ?: "" }
        val sender = messages.firstOrNull()?.originatingAddress ?: return
        if (fullBody.isBlank()) return

        // 2. Check opt-in consent + user session
        val prefs = MomoSmsPrefs.getInstance(context)
        if (!prefs.isEnabled()) return

        val userId = prefs.currentUserId()
        if (userId.isNullOrBlank()) return

        // 3. NATIVE SENDER FILTER — the key privacy fix
        //    Non-MoMo SMS is discarded here, before Flutter, before queue, before network.
        if (!prefs.isApprovedSender(sender)) return

        // 4. Extend receiver lifecycle for async work
        val pendingResult = goAsync()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val now = Instant.now()
                val normalizedBody = MomoSmsNormalizer.normalizeWhitespace(fullBody)
                if (normalizedBody.isBlank()) return@launch

                val capture = MomoSmsCapture(
                    sender = sender.trim(),
                    body = normalizedBody,
                    receivedAt = now,
                    deviceMessageKey = MomoSmsNormalizer.buildDeviceMessageKey(
                        sender = sender,
                        body = normalizedBody,
                        receivedAt = now,
                    ),
                    ingestionSource = "native_sms_receiver",
                )

                val queueRepo = MomoSmsQueueRepository.getInstance(context)
                val rowId = queueRepo.insertIfAbsent(userId, capture)

                if (rowId != -1L) {
                    Log.d(TAG, "Queued MoMo SMS (sender=$sender)")
                    MomoSmsSyncWorker.enqueue(context)
                } else {
                    Log.d(TAG, "Duplicate SMS skipped (sender=$sender)")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to queue SMS", e)
            } finally {
                pendingResult.finish()
            }
        }
    }
}
