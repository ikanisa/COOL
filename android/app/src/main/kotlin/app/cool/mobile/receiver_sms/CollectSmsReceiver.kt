package app.cool.mobile.receiver_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
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
        if (messages.isEmpty()) return
        val sender = messages.firstOrNull()?.originatingAddress.orEmpty().trim()
        val body = messages.joinToString(separator = "") { it.messageBody.orEmpty() }.trim()
        if (body.isEmpty() || !isLikelyMobileMoney(sender, body)) return

        try {
            val store = SmsQueueStore(context.applicationContext)
            val pending = store.read()
            val bounded = JSONArray()
            val startIndex = maxOf(0, pending.length() - MAX_PENDING_SMS + 1)
            for (index in startIndex until pending.length()) {
                pending.optJSONObject(index)?.let(bounded::put)
            }
            bounded.put(
                JSONObject()
                    .put("id", UUID.randomUUID().toString())
                    .put("raw_sender", sender)
                    .put("raw_body", body)
                    .put(
                        "received_at_device",
                        messages.minOfOrNull { it.timestampMillis }
                            ?.takeIf { it > 0L }
                            ?.toString()
                            ?: System.currentTimeMillis().toString(),
                    ),
            )
            if (store.write(bounded)) {
                // Never log sender, message body, phone number, amount, or transaction ID.
                Log.i(TAG, "Consented mobile-money SMS queued for secure ingestion")
            } else {
                Log.w(TAG, "Unable to persist consented SMS queue item")
            }
        } catch (_: Exception) {
            // Android Keystore can be temporarily unavailable while a device is
            // locked or after key invalidation. Fail closed and let the provider
            // remain the source of truth instead of crashing the broadcast path.
            Log.w(TAG, "Secure SMS queue unavailable; message was not retained")
        }
    }

    internal fun isLikelyMobileMoney(sender: String, body: String): Boolean {
        val providerHint = PROVIDER_HINT.containsMatchIn(sender) ||
            PROVIDER_HINT.containsMatchIn(body)
        val currencyHint = body.contains("RWF", ignoreCase = true) ||
            body.contains("FRW", ignoreCase = true)
        val transactionHint = TRANSACTION_HINT.containsMatchIn(body)
        return providerHint && currencyHint && transactionHint
    }

    companion object {
        private const val TAG = "CollectSmsReceiver"
        private const val MAX_PENDING_SMS = 25
        private val PROVIDER_HINT = Regex("(?:momo|mobile\\s*money|mtn|airtel)", RegexOption.IGNORE_CASE)
        private val TRANSACTION_HINT = Regex(
            "(?:received|sent|paid|payment|transaction|transferred|cash[ -]?in|deposit|" +
                "re(?:c|ç)u|envoy(?:e|é)|paiement|versement|d(?:e|é)p(?:o|ô)t|" +
                "wakiriye|woherereje|wishyuye|yishyuwe)",
            RegexOption.IGNORE_CASE,
        )
    }
}
