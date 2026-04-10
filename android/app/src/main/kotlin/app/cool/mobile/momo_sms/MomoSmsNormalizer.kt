package app.cool.mobile.momo_sms

import java.security.MessageDigest
import java.time.Instant
import java.time.format.DateTimeFormatter

object MomoSmsNormalizer {
    private val isoFormatter: DateTimeFormatter = DateTimeFormatter.ISO_INSTANT

    fun normalizeSender(value: String?): String {
        return value
            ?.lowercase()
            ?.trim()
            ?.replace(Regex("[^a-z0-9]"), "")
            .orEmpty()
    }

    fun normalizeWhitespace(value: String?): String {
        return value
            ?.replace(Regex("\\s+"), " ")
            ?.trim()
            .orEmpty()
    }

    fun buildDeviceMessageKey(
        sender: String,
        body: String,
        receivedAt: Instant,
    ): String {
        val payload = listOf(
            normalizeSender(sender),
            isoFormatter.format(receivedAt),
            normalizeWhitespace(body),
        ).joinToString("|")
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(payload.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { byte -> "%02x".format(byte) }
    }
}
