package app.cool.mobile.receiver_sms

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Telephony
import android.telephony.TelephonyManager
import org.json.JSONObject
import java.time.Instant

class MomoGatewayRecovery(private val context: Context) {
    private val state = MomoGatewayStore(context)
    fun inboxAvailable() = context.checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED

    fun latestInboxId(): Long? {
        if (!inboxAvailable()) return null
        return context.contentResolver.query(Telephony.Sms.Inbox.CONTENT_URI, arrayOf("_id"), null, null, "_id DESC LIMIT 1")
            ?.use { if (it.moveToFirst()) it.getLong(0) else 0L }
    }

    @Suppress("DEPRECATION")
    fun multipleSims(): Boolean = try {
        (context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager)?.phoneCount?.let { it > 1 } ?: true
    } catch (_: Exception) { true }

    /** Copies before advancing. Re-reading overlap rows is harmless through stable source identities. */
    fun catchUp(): Boolean = synchronized(scanLock) { catchUpLocked() }

    private fun catchUpLocked(): Boolean {
        if (!state.active() || !inboxAvailable()) return false
        val snapshot = state.read() ?: return false
        val binding = snapshot.getJSONObject("binding")
        val owner = binding.getString("owner_user_id")
        val cursorId = snapshot.optLong("inbox_checkpoint", 0L)
        val baseline = if (snapshot.has("inbox_binding_baseline")) snapshot.getLong("inbox_binding_baseline") else null
        val selected = binding.optionalInt("subscription_id")
        // The overlap permits interrupted scans and duplicate broadcast/inbox paths.
        val after = (cursorId - 20L).coerceAtLeast(0L)
        var scanned = 0
        var advanced = cursorId
        context.contentResolver.query(Telephony.Sms.Inbox.CONTENT_URI, null, "_id > ?", arrayOf(after.toString()),
            "_id ASC LIMIT ${MomoGatewayPolicy.MAX_SCAN_ROWS}")?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow("_id")
            val addressColumn = cursor.getColumnIndexOrThrow("address")
            val bodyColumn = cursor.getColumnIndexOrThrow("body")
            val receivedColumn = cursor.getColumnIndexOrThrow("date")
            val sentColumn = cursor.getColumnIndex("date_sent")
            val subscriptionColumn = cursor.getColumnIndex("sub_id")
            while (cursor.moveToNext()) {
                scanned++
                val id = cursor.getLong(idColumn)
                val sender = cursor.getString(addressColumn).orEmpty()
                val body = cursor.getString(bodyColumn).orEmpty()
                if (MomoGatewayPolicy.providerSource(sender) && body.isNotEmpty()) {
                    val received = cursor.getLong(receivedColumn)
                    val sent = if (sentColumn >= 0) cursor.getLong(sentColumn).takeIf { it > 0L } ?: received else received
                    val subscription = if (subscriptionColumn < 0 || cursor.isNull(subscriptionColumn)) null else cursor.getInt(subscriptionColumn).takeIf { it >= 0 }
                    val bindingCreated = try { Instant.parse(binding.optString("created_at")).toEpochMilli() } catch (_: Exception) { null }
                    val resolved = bindingCreated != null && received >= bindingCreated &&
                        MomoGatewayPolicy.historicalSourceResolved(id, baseline, selected, subscription, multipleSims())
                    if (!resolved && SmsQueueStore(context).readForGateway(owner).length() >= MomoGatewayPolicy.MAX_PENDING - 100) {
                        // Reserve room for live captures while older sources await review.
                        // Do not checkpoint this uncopied inbox row.
                        state.update { it.put("historical_backlog_paused", true).put("catch_up_pending", false) }
                        return false
                    }
                    val capture = JSONObject()
                        .put("id", MomoGatewayPolicy.captureId(state.installationId(), binding.getString("id"), sender, body, sent, subscription))
                        .put("owner_user_id", owner).put("raw_sender", sender).put("raw_body", body)
                        .put("gateway_binding_id", binding.getString("id")).put("gateway_binding_version", binding.getInt("version"))
                        .put("service_centre_at", instant(sent)).put("received_at_device", instant(sent))
                        .put("captured_at", Instant.now().toString()).put("inbox_received_at", instant(received))
                        .put("subscription_id", subscription ?: JSONObject.NULL).put("source_mode", "catch_up")
                        .put("source_unresolved", !resolved).put("inbox_row_id", id).put("complete", true)
                    when (SmsQueueStore(context).appendIfCapacity(capture, MomoGatewayPolicy.MAX_PENDING)) {
                        SmsQueueStore.AppendResult.STORED, SmsQueueStore.AppendResult.DUPLICATE -> Unit
                        else -> return false // Never checkpoint an uncopied source.
                    }
                }
                advanced = maxOf(advanced, id)
            }
        } ?: throw IllegalStateException("SMS inbox is unavailable")
        state.update {
            val current = it.getJSONObject("binding")
            check(current.getString("id") == binding.getString("id") && current.getInt("version") == binding.getInt("version"))
            it.put("inbox_checkpoint", maxOf(it.optLong("inbox_checkpoint"), advanced))
                .put("historical_backlog_paused", false).put("catch_up_pending", scanned == MomoGatewayPolicy.MAX_SCAN_ROWS)
        }
        SmsQueueEventBus.notifyQueueChanged()
        return scanned == MomoGatewayPolicy.MAX_SCAN_ROWS
    }

    private fun instant(value: Long): Any = if (value > 0) Instant.ofEpochMilli(value).toString() else JSONObject.NULL
    companion object { private val scanLock = Any() }
}

internal fun JSONObject.optionalInt(key: String): Int? = if (has(key) && !isNull(key)) optInt(key, -1).takeIf { it >= 0 } else null
