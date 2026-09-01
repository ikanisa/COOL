package app.cool.mobile.receiver_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

class CollectSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val prefs = context.getSharedPreferences(
            SmsQueueStore.SMS_ACCESS_PREFS,
            Context.MODE_PRIVATE,
        )
        if (!prefs.getBoolean(SmsQueueStore.SMS_ACCESS_ENABLED_KEY, false)) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty() || messages.size > MAX_SMS_SEGMENTS) return
        val sender = messages.firstOrNull()?.originatingAddress.orEmpty().trim()
        val body = messages.joinToString(separator = "") { it.messageBody.orEmpty() }.trim()
        val ownerUserId = prefs.getString(
            SmsQueueStore.SMS_ACCESS_OWNER_USER_ID_KEY,
            null,
        ).orEmpty().trim()
        if (ownerUserId.isEmpty() || body.isEmpty() || body.length > MAX_SMS_BODY_CHARS ||
            !isLikelyMomoReceipt(sender, body)
        ) return

        val receivedAtMillis = messages.minOfOrNull { it.timestampMillis }
            ?.takeIf { it > 0L }
            ?: System.currentTimeMillis()
        val envelope = JSONObject()
            .put("id", envelopeIdFor(ownerUserId, sender, body, receivedAtMillis))
            .put("owner_user_id", ownerUserId)
            .put("raw_sender", sender)
            .put("raw_body", body)
            .put("received_at_device", Instant.ofEpochMilli(receivedAtMillis).toString())
        val pendingResult = goAsync()
        try {
            SmsQueueWorker.execute {
                try {
                    val result = SmsQueueStore(context.applicationContext).appendIfCapacity(
                        envelope,
                        MAX_PENDING_SMS,
                    )
                    when (result) {
                        SmsQueueStore.AppendResult.STORED -> {
                            // Never log sender, message body, phone number, amount,
                            // transaction ID, or the device-local envelope ID.
                            Log.i(TAG, "Consented MoMo receipt queued for secure ingestion")
                            SmsQueueEventBus.notifyQueueChanged()
                        }
                        SmsQueueStore.AppendResult.DUPLICATE -> {
                            // A duplicate broadcast may be the signal that wakes a
                            // foreground Flutter engine after an earlier event race.
                            SmsQueueEventBus.notifyQueueChanged()
                        }
                        SmsQueueStore.AppendResult.FULL ->
                            Log.w(TAG, "Secure SMS queue is full; existing evidence was preserved")
                        SmsQueueStore.AppendResult.DISABLED -> Unit
                        SmsQueueStore.AppendResult.FAILED ->
                            Log.w(TAG, "Unable to persist consented SMS queue item")
                    }
                } catch (_: Exception) {
                    // Android Keystore can be temporarily unavailable. Fail closed
                    // instead of crashing or exposing the protected broadcast path.
                    Log.w(TAG, "Secure SMS queue unavailable; message was not retained")
                } finally {
                    pendingResult.finish()
                }
            }
        } catch (_: RuntimeException) {
            pendingResult.finish()
            Log.w(TAG, "Secure SMS queue worker unavailable; message was not retained")
        }
    }

    internal fun envelopeIdFor(
        ownerUserId: String,
        sender: String,
        body: String,
        receivedAtMillis: Long,
    ): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(
            listOf(ownerUserId.trim(), sender.trim(), receivedAtMillis.toString(), body.trim())
                .joinToString("\u0000")
                .toByteArray(Charsets.UTF_8),
        ).copyOf(16)
        // Encode the deterministic transport fingerprint as an RFC 4122 version-5
        // UUID so the backend can use it as an idempotency key without raw SMS data.
        digest[6] = ((digest[6].toInt() and 0x0f) or 0x50).toByte()
        digest[8] = ((digest[8].toInt() and 0x3f) or 0x80).toByte()
        val bytes = ByteBuffer.wrap(digest)
        return UUID(bytes.long, bytes.long).toString()
    }

    internal fun isLikelyMomoReceipt(sender: String, body: String): Boolean {
        val allowedSender = sender.length in 2..160 &&
            (MOMO_SENDER_HINT.containsMatchIn(sender) || MOMO_CONTEXT_HINT.containsMatchIn(body))
        val moneyHint = CURRENCY_HINT.containsMatchIn(body) && AMOUNT_HINT.containsMatchIn(body)
        val transactionHint = TRANSACTION_ID_HINT.containsMatchIn(body)
        val incomingHint = INCOMING_HINT.containsMatchIn(body)
        val promotionalHint = PROMOTIONAL_HINT.containsMatchIn(body)
        return allowedSender && moneyHint && transactionHint && incomingHint && !promotionalHint
    }

    companion object {
        private const val TAG = "CollectSmsReceiver"
        private const val MAX_PENDING_SMS = 100
        private const val MAX_SMS_SEGMENTS = 10
        private const val MAX_SMS_BODY_CHARS = 2_000
        private val MOMO_SENDER_HINT = Regex(
            "(?:momo|m[- ]?money|mobile[- ]?money|mtn|airtel)",
            RegexOption.IGNORE_CASE,
        )
        private val MOMO_CONTEXT_HINT = Regex(
            "(?:momo|mobile money|mtn|airtel)",
            RegexOption.IGNORE_CASE,
        )
        private val CURRENCY_HINT = Regex("(?:RWF|FRW)", RegexOption.IGNORE_CASE)
        private val AMOUNT_HINT = Regex("(?:^|\\D)[0-9][0-9 ,.]{0,18}(?:$|\\D)")
        private val TRANSACTION_ID_HINT = Regex(
            "(?:transaction|trans(?:action)?\\s*id|txn|txid|financial transaction id|reference|ref\\b)",
            RegexOption.IGNORE_CASE,
        )
        private val INCOMING_HINT = Regex(
            "(?:received|credited|incoming|payment received|you have received|wakiriye|wahawe)",
            RegexOption.IGNORE_CASE,
        )
        private val PROMOTIONAL_HINT = Regex(
            "(?:buy\\s+(?:a\\s+)?bundle|airtime\\s+offer|promotion|promo\\b|bonus\\s+offer|" +
                "apply\\s+for\\s+(?:a\\s+)?loan)",
            RegexOption.IGNORE_CASE,
        )
    }
}
