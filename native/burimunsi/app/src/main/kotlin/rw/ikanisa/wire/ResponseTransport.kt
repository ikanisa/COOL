package rw.ikanisa.wire

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.Locale

/** Identity-encoded application bytes only. HTTP chunk framing is decoded by the HTTP stack.
 * No successful read authorizes an ACK, cursor update, retry or new operation ID. */
object ResponseTransport {
    data class Metadata(val contentType: String?, val contentLength: Long?)

    /** Reject duplicates even when values agree. An HTTP stack may already have coalesced fields;
     * comma-joined singleton fields also fail this profile. Headers must be read before body use. */
    fun metadata(headers: Map<out String?, List<String>?>, maxBytes: Int): Metadata {
        require(maxBytes > 0)
        fun single(name: String): String? {
            val entries = headers.entries.filter { it.key?.lowercase(Locale.ROOT) == name }
            if (entries.isEmpty()) return null
            if (entries.size != 1 || entries.single().value?.size != 1) reject("CONTRACT_RESPONSE_HEADER")
            val value = entries.single().value!!.single()
            if (value.length > 256 || value.any { it == '\r' || it == '\n' || it == '\u0000' }) reject("CONTRACT_RESPONSE_HEADER")
            return value.trim(' ', '\t')
        }
        val contentType = single("content-type")
        val encoding = single("content-encoding")
        if (encoding != null && !encoding.equals("identity", ignoreCase = true)) reject("CONTRACT_CONTENT_ENCODING")
        val length = single("content-length")
        val transfer = single("transfer-encoding")
        if (transfer != null && (!transfer.equals("chunked", ignoreCase = true) || length != null)) reject("CONTRACT_TRANSFER_ENCODING")
        // Leading zeros are legal in HTTP's 1*DIGIT syntax. No signs, lists or coercions.
        val count = length?.let {
            if (!Regex("[0-9]{1,20}").matches(it)) reject("CONTRACT_CONTENT_LENGTH")
            it.toLongOrNull() ?: reject("CONTRACT_CONTENT_LENGTH")
        }
        if (count != null && count > maxBytes) reject("CONTRACT_RESPONSE_SIZE")
        return Metadata(contentType, count)
    }

    /** Owns [stream]. Check deadlines before and after every read, including EOF; do not reset
     * the budget for progress. [beforeRead] must set the real transport timeout to the remaining
     * budget. This cannot forcibly interrupt a nonconforming stream/close that ignores timeouts.
     * Callers sanitize IOException/provider failures; no partial bytes are returned on failure. */
    fun read(stream: InputStream, maxBytes: Int, expectedBytes: Long? = null,
        timeoutMillis: Long = 20_000, nanoTime: () -> Long = System::nanoTime,
        cancelled: () -> Boolean = { Thread.currentThread().isInterrupted },
        beforeRead: (Int) -> Unit = {}): ByteArray {
        require(maxBytes > 0 && timeoutMillis in 1..60_000)
        val start = nanoTime()
        val budget = timeoutMillis * 1_000_000
        fun remaining(): Int {
            if (cancelled()) reject("CONTRACT_RESPONSE_CANCELLED")
            // Elapsed subtraction also works across the nanoTime signed wrap boundary.
            val elapsed = nanoTime() - start
            if (elapsed < 0 || elapsed >= budget) reject("CONTRACT_RESPONSE_TIMEOUT")
            return ((budget - elapsed + 999_999) / 1_000_000).toInt().coerceAtLeast(1)
        }
        val bytes = stream.use { input ->
            if (expectedBytes != null && (expectedBytes < 0 || expectedBytes > maxBytes)) reject("CONTRACT_RESPONSE_SIZE")
            val output = ByteArrayOutputStream(minOf(maxBytes, 8192))
            val buffer = ByteArray(8192)
            try {
                while (true) {
                    beforeRead(remaining())
                    val count = input.read(buffer)
                    remaining()
                    if (count == -1) break
                    if (count <= 0 || count > buffer.size) reject("CONTRACT_RESPONSE_STREAM")
                    val nextSize = output.size().toLong() + count
                    if (nextSize > maxBytes) reject("CONTRACT_RESPONSE_SIZE")
                    if (expectedBytes != null && nextSize > expectedBytes) reject("CONTRACT_CONTENT_LENGTH")
                    output.write(buffer, 0, count)
                }
                if (expectedBytes != null && output.size().toLong() != expectedBytes) reject("CONTRACT_RESPONSE_TRUNCATED")
                output.toByteArray()
            } finally { buffer.fill(0) }
        }
        // A late cleanup also cannot yield a successful result. IO failures propagate for sanitizing.
        try { remaining() } catch (error: Exception) { bytes.fill(0); throw error }
        return bytes
    }
}
