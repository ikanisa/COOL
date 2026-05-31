package app.cool.mobile.receiver_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

class CollectSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val prefs = context.getSharedPreferences(SMS_ACCESS_PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(SMS_ACCESS_ENABLED_KEY, false)) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        val sender = messages.firstOrNull()?.originatingAddress.orEmpty()
        val body = messages.joinToString(separator = "") { it.messageBody.orEmpty() }
        val likelyMomo = sender.contains("momo", ignoreCase = true) ||
            sender.contains("mtn", ignoreCase = true) ||
            body.contains("RWF", ignoreCase = true)

        if (!likelyMomo) return

        val pending = JSONArray(prefs.getString(PENDING_SMS_KEY, "[]") ?: "[]")
        val trimmed = JSONArray()
        val startIndex = maxOf(0, pending.length() - MAX_PENDING_SMS + 1)
        for (index in startIndex until pending.length()) {
            trimmed.put(pending.getJSONObject(index))
        }
        trimmed.put(
            JSONObject()
                .put("raw_sender", sender)
                .put("raw_body", body)
                .put("received_at_device", System.currentTimeMillis().toString())
        )
        prefs.edit().putString(PENDING_SMS_KEY, trimmed.toString()).apply()

        // Do not log raw SMS body or sender. Flutter foreground code owns upload.
        Log.i("CollectSmsReceiver", "Consented mobile-money SMS queued for SMS access")
    }

    companion object {
        private const val SMS_ACCESS_PREFS = "collect_sms_access"
        private const val SMS_ACCESS_ENABLED_KEY = "enabled"
        private const val PENDING_SMS_KEY = "pending_sms"
        private const val MAX_PENDING_SMS = 25
    }
}
