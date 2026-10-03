package app.cool.mobile.gateway

import java.io.ByteArrayOutputStream
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.net.ssl.HttpsURLConnection

/** Bounded exact-byte HTTPS transport. Injectable connection factory exists
 * solely for offline tests; Android uses the fixed governed URL. */
internal class GatewayHttpsTransport(
    private val keyId: () -> String,
    private val signExact: (ByteArray) -> String,
    private val connect: (URL) -> HttpsURLConnection = { it.openConnection() as HttpsURLConnection },
    private val deadlineMs: Long = 15_000,
) {
    companion object {
        const val HOST = "lhbowpbcpwoiparwnwgt.supabase.co"
        const val MAX_REQUEST_BYTES = 32 * 1024
        const val MAX_RESPONSE_BYTES = 64 * 1024
        private val executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "CollectGatewayHttps").apply { isDaemon = true }
        }
    }
    @Volatile private var active: HttpsURLConnection? = null

    fun postExact(bytes: ByteArray): ByteArray {
        if (bytes.isEmpty() || bytes.size > MAX_REQUEST_BYTES || deadlineMs !in 1..15_000) throw GatewayStateException("gateway_request_invalid")
        val fingerprint = keyId()
        if (!fingerprint.matches(Regex("[0-9a-f]{64}"))) throw GatewayStateException("gateway_identity_invalid")
        val signature = signExact(bytes)
        val task = executor.submit<ByteArray> {
            val connection = connect(URL("https://$HOST/functions/v1/collect-android-gateway"))
            active = connection
            try {
                connection.instanceFollowRedirects = false
                connection.useCaches = false
                connection.connectTimeout = minOf(7000, deadlineMs.toInt())
                connection.readTimeout = minOf(7000, deadlineMs.toInt())
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(bytes.size)
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                connection.setRequestProperty("X-Collect-Gateway-Key-Id", fingerprint)
                connection.setRequestProperty("X-Collect-Gateway-Signature", signature)
                connection.outputStream.use { it.write(bytes) }
                if (connection.responseCode !in 200..299) throw GatewayStateException("gateway_http_outcome_unknown")
                connection.inputStream.use { stream ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(4096)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        if (output.size() + count > MAX_RESPONSE_BYTES) throw GatewayStateException("gateway_response_limit")
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
            } finally {
                connection.disconnect()
                active = null
            }
        }
        try { return task.get(deadlineMs, TimeUnit.MILLISECONDS) }
        catch (_: Exception) {
            active?.disconnect()
            task.cancel(true)
            // No retry: a write may already have reached the backend.
            throw GatewayStateException("gateway_http_outcome_unknown")
        }
    }
}
