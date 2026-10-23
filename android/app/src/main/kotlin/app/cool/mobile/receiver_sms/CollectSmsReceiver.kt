package app.cool.mobile.receiver_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import app.cool.mobile.BuildConfig
import org.json.JSONObject
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

class CollectSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION ||
            (BuildConfig.FLAVOR != "internal_receiver" && !MomoGatewayPolicy.memberCaptureSupported(BuildConfig.FLAVOR))) return
        val pendingResult = goAsync()
        try {
            SmsQueueWorker.executeCapture {
                try {
                    val queue = SmsQueueStore(context.applicationContext)
                    val gateway = if (BuildConfig.FLAVOR == "internal_receiver")
                        MomoGatewayStore(context.applicationContext) else null
                    if (gateway != null && !gateway.active()) return@executeCapture
                    val binding = gateway?.read()?.getJSONObject("binding")
                    if (gateway != null && binding == null) return@executeCapture
                    val owner = binding?.getString("owner_user_id") ?: queue.activeCaptureOwner()
                        ?: return@executeCapture
                    val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
                    if (messages.isEmpty()) return@executeCapture
                    val sender = messages.first().originatingAddress.orEmpty()
                    if (!MomoGatewayPolicy.providerSource(sender)) return@executeCapture
                    val serviceCentre = messages.minOfOrNull { it.timestampMillis }?.takeIf { it > 0 }
                    val capturedAt = Instant.now().toString()
                    val subscription = listOf("subscription", "subscription_id", "android.telephony.extra.SUBSCRIPTION_INDEX")
                        .firstNotNullOfOrNull { key -> if (intent.hasExtra(key)) intent.getIntExtra(key, -1).takeIf { it >= 0 } else null }
                    val pdus = intent.extras?.get("pdus") as? Array<*>
                    val parts = pdus?.map { (it as? ByteArray)?.let { pdu -> MomoMultipartPolicy.part(pdu, intent.getStringExtra("format")) } }.orEmpty()
                    val complete = MomoGatewayPolicy.completeParts(messages.map { it.originatingAddress.orEmpty() },
                        messages.map { it.timestampMillis }, messages.map { it.messageBody }) &&
                        parts.size == messages.size && MomoMultipartPolicy.complete(parts)
                    val body = if (complete) messages.indices.sortedBy { parts[it]!!.sequence }
                        .joinToString("") { messages[it].messageBody.orEmpty() }
                        else messages.joinToString("") { it.messageBody.orEmpty() }
                    if (body.isEmpty()) return@executeCapture
                    if (gateway == null && !MomoGatewayPolicy.memberSource(sender, body)) return@executeCapture
                    val envelope = JSONObject()
                        .put("id", if (gateway != null && binding != null)
                            MomoGatewayPolicy.captureId(gateway.installationId(), binding.getString("id"), sender, body,
                                serviceCentre ?: 0L, subscription)
                            else envelopeIdFor(owner, sender, body, serviceCentre ?: 0L))
                        .put("owner_user_id", owner)
                        .put("raw_sender", sender).put("raw_body", body)
                        .put("received_at_device", serviceCentre?.let { Instant.ofEpochMilli(it).toString() } ?: "")
                        .put("captured_at", capturedAt)
                        .put("completeness", if (complete) "complete" else "incomplete")
                    if (gateway != null && binding != null) {
                        val resolved = MomoGatewayPolicy.sourceResolved(binding.optionalInt("subscription_id"), subscription,
                            MomoGatewayRecovery(context).multipleSims())
                        envelope.put("gateway_binding_id", binding.getString("id"))
                            .put("gateway_binding_version", binding.getInt("version"))
                            .put("service_centre_at", serviceCentre?.let { Instant.ofEpochMilli(it).toString() } ?: JSONObject.NULL)
                            .put("inbox_received_at", JSONObject.NULL).put("source_mode", "live")
                            .put("subscription_id", subscription ?: JSONObject.NULL)
                            .put("complete", complete).put("source_unresolved", !resolved)
                    }
                    val result = queue.appendIfCapacity(
                        envelope,
                        MomoGatewayPolicy.MAX_PENDING,
                    )
                    when (result) {
                        SmsQueueStore.AppendResult.STORED -> {
                            // Never log sender, message body, phone number, amount,
                            // transaction ID, or the device-local envelope ID.
                            Log.i(TAG, "Consented MoMo receipt queued for secure ingestion")
                            gateway?.update { it.put("last_sms_at", capturedAt) }
                            if (gateway != null) MomoGatewayJobs.signal(context.applicationContext)
                            else MemberSmsJobs.ensure(context.applicationContext)
                            SmsQueueEventBus.notifyQueueChanged()
                        }
                        SmsQueueStore.AppendResult.DUPLICATE -> {
                            if (gateway != null) MomoGatewayJobs.signal(context.applicationContext)
                            else MemberSmsJobs.ensure(context.applicationContext)
                            // A duplicate broadcast may be the signal that wakes a
                            // foreground Flutter engine after an earlier event race.
                            SmsQueueEventBus.notifyQueueChanged()
                        }
                        SmsQueueStore.AppendResult.FULL -> {
                            Log.w(TAG, "Secure SMS queue is full; existing evidence was preserved")
                            SmsQueueEventBus.notifyQueueChanged()
                        }
                        SmsQueueStore.AppendResult.DISABLED -> Unit
                        SmsQueueStore.AppendResult.FAILED -> {
                            Log.w(TAG, "Unable to persist consented SMS queue item")
                            SmsQueueEventBus.notifyQueueChanged()
                        }
                    }
                } catch (_: Exception) {
                    // Android Keystore can be temporarily unavailable. Fail closed
                    // instead of crashing or exposing the protected broadcast path.
                    Log.w(TAG, "Secure SMS queue unavailable; message was not retained")
                    SmsQueueEventBus.notifyQueueChanged()
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
            listOf(ownerUserId.trim(), sender, receivedAtMillis.toString(), body)
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
        val allowedSender = sender.toByteArray(Charsets.UTF_8).size in 2..96 &&
            MOMO_SENDER_HINT.containsMatchIn(sender)
        val moneyHint = CURRENCY_HINT.containsMatchIn(body) && AMOUNT_HINT.containsMatchIn(body)
        val transactionHint = TRANSACTION_ID_HINT.containsMatchIn(body)
        val maskedReceiptHint = MASKED_PAYER_HINT.containsMatchIn(body) &&
            WALLET_BALANCE_HINT.containsMatchIn(body)
        val incomingHint = INCOMING_HINT.containsMatchIn(body)
        val promotionalHint = PROMOTIONAL_HINT.containsMatchIn(body)
        return allowedSender && moneyHint && (transactionHint || maskedReceiptHint) &&
            incomingHint && !promotionalHint && !EXCLUDED_HINT.containsMatchIn(body)
    }

    companion object {
        private const val TAG = "CollectSmsReceiver"
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
        // Capture eligibility only. The server validates amounts, identity and
        // route before posting; a provider reference is optional for this form.
        private val MASKED_PAYER_HINT = Regex(
            "\\bfrom\\s+[^()\\r\\n]{2,120}\\s*\\(\\s*\\*{3,}[0-9]{3}\\s*\\)",
            RegexOption.IGNORE_CASE,
        )
        private val WALLET_BALANCE_HINT = Regex(
            "\\bbalance\\s*(?:is|:|=)?\\s*(?:(?:RWF|FRW)\\s+[0-9]|[0-9][0-9 ,.]*\\s*(?:RWF|FRW))",
            RegexOption.IGNORE_CASE,
        )
        private val EXCLUDED_HINT = Regex(
            "\\b(?:failed|reversed|reversal|cancelled|pending|declined|you have sent|" +
                "transferred to|cash.?out|withdraw(?:al|n)?|OTP|verification code|one.time password)\\b",
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
