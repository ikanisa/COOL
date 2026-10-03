package app.cool.mobile.gateway

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.time.Instant
import java.util.concurrent.Executors

class GatewaySmsCallbackReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val frameworkCode = resultCode
        worker.execute {
            try {
                val kind = CallbackKind.valueOf(intent.getStringExtra("callback_kind").orEmpty())
                if (intent.action != "app.cool.mobile.gateway.${kind.name}") return@execute
                val id = intent.getStringExtra("callback_id").orEmpty()
                if (intent.dataString != "collect-gateway://callback/$id") return@execute
                val callback = GatewayCallback(id, intent.getStringExtra("device_id").orEmpty(),
                    intent.getStringExtra("attempt_id").orEmpty(), intent.getLongExtra("fence", -1),
                    intent.getIntExtra("segment_index", -1), intent.getStringExtra("nonce").orEmpty(), kind,
                    frameworkCode, Instant.now().toString())
                GatewayJournal(GatewayEncryptedStore(context.applicationContext)).record(callback)
            } catch (_: Exception) {
                // Keep the pre-invocation reservation. Missing/corrupt callback
                // evidence remains unknown; no raw SMS/error or nonce logs.
            } finally { pending.finish() }
        }
    }
    companion object { private val worker = Executors.newSingleThreadExecutor() }
}
