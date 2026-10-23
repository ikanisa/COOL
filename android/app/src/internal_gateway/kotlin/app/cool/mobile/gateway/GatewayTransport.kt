package app.cool.mobile.gateway

import app.cool.mobile.BuildConfig

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.URL
import java.security.GeneralSecurityException
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLException

/** Bounded exact-byte HTTPS transport. Injectable connection factory exists
 * solely for offline tests; Android uses the fixed governed URL. */
internal class GatewayHttpsTransport(
    private val keyId: () -> String,
    private val signExact: (ByteArray) -> String,
    private val connect: (URL) -> HttpsURLConnection = { it.openConnection() as HttpsURLConnection },
    private val deadlineMs: Long = 15_000,
) {
    companion object {
        val HOST = BuildConfig.COLLECT_API_HOST
        const val MAX_REQUEST_BYTES = 32 * 1024
        const val MAX_RESPONSE_BYTES = 64 * 1024
        private val executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "CollectGatewayHttps").apply { isDaemon = true }
        }
    }
    @Volatile private var active: HttpsURLConnection? = null
    private class LookupUnavailable : IllegalStateException()
    private fun recoverableIo(error: IOException): Boolean {
        var cause: Throwable? = error
        repeat(8) {
            val current = cause ?: return true
            if (current is SSLException || current is GeneralSecurityException || current is SecurityException) return false
            cause = current.cause
        }
        return false
    }

    fun postExact(bytes: ByteArray, readOnly: Boolean = false): ByteArray = postFixed(bytes, readOnly, false)
    fun postSuccessorExact(bytes: ByteArray, readOnly: Boolean = false): ByteArray = postFixed(bytes, readOnly, true)
    fun postNoticeExact(bytes: ByteArray, readOnly: Boolean = false): ByteArray = postFixed(bytes, readOnly, false, true)
    private fun postFixed(bytes: ByteArray, readOnly: Boolean, successor: Boolean, notice: Boolean = false): ByteArray {
        if (bytes.isEmpty() || bytes.size > MAX_REQUEST_BYTES || deadlineMs !in 1..15_000) throw GatewayStateException("gateway_request_invalid")
        val abandoned = AtomicBoolean(false)
        val networkPhase = AtomicBoolean(false)
        val task = executor.submit<ByteArray> {
            val fingerprint = keyId()
            if (!fingerprint.matches(Regex("[0-9a-f]{64}"))) throw GatewayStateException("gateway_identity_invalid")
            val signature = signExact(bytes)
            if (abandoned.get() || Thread.currentThread().isInterrupted) throw GatewayStateException("gateway_http_outcome_unknown")
            // Credential/signing failures are outside the recoverable network
            // phase, even when their underlying exception is an IOException.
            networkPhase.set(true)
            val endpoint = if (notice) "collect-receipt-notice-gateway" else if (successor) "collect-receipt-successor-gateway" else "collect-android-gateway"
            val connection = try { connect(URL("https://$HOST${BuildConfig.COLLECT_API_PATH_PREFIX}/v1/functions/$endpoint")) }
                catch (e: IOException) { if (readOnly && recoverableIo(e)) throw LookupUnavailable() else throw e }
            active = connection
            try {
                if (abandoned.get() || Thread.currentThread().isInterrupted) throw GatewayStateException("gateway_http_outcome_unknown")
                connection.instanceFollowRedirects = false
                connection.useCaches = false
                connection.connectTimeout = minOf(7000, deadlineMs.toInt())
                connection.readTimeout = minOf(7000, deadlineMs.toInt())
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(bytes.size)
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                if (BuildConfig.COLLECT_PUBLISHABLE_KEY.isNotEmpty()) connection.setRequestProperty("apikey", BuildConfig.COLLECT_PUBLISHABLE_KEY)
                connection.setRequestProperty("X-Collect-Gateway-Key-Id", fingerprint)
                connection.setRequestProperty("X-Collect-Gateway-Signature", signature)
                connection.outputStream.use {
                    if (abandoned.get() || Thread.currentThread().isInterrupted) throw GatewayStateException("gateway_http_outcome_unknown")
                    it.write(bytes)
                }
                val status = connection.responseCode
                if (status !in 200..299) {
                    if (readOnly && (status == 408 || status == 429 || status in 500..599)) throw LookupUnavailable()
                    throw GatewayStateException("gateway_http_outcome_unknown")
                }
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
            } catch (e: IOException) {
                if (readOnly && recoverableIo(e)) throw LookupUnavailable() else throw e
            } finally {
                connection.disconnect()
                active = null
            }
        }
        try { return task.get(deadlineMs, TimeUnit.MILLISECONDS) }
        catch (e: Exception) {
            abandoned.set(true)
            active?.disconnect()
            task.cancel(true)
            if (e is InterruptedException) Thread.currentThread().interrupt()
            if (readOnly) {
                val cause = if (e is ExecutionException) e.cause else e
                if (cause is LookupUnavailable || (e is TimeoutException && networkPhase.get())) throw GatewayStateException("gateway_lookup_transport_unavailable")
                if (cause is GatewayStateException) throw cause
            }
            // No retry: a write may already have reached the backend.
            throw GatewayStateException("gateway_http_outcome_unknown")
        }
    }
}
