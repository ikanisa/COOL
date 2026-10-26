package app.cool.mobile.receiver_sms

import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID

/** Capture policy only. Financial classification and account authorization are server-owned. */
object MomoGatewayPolicy {
    const val MAX_PENDING = 1_000
    const val MAX_SCAN_ROWS = 200
    const val MAX_UPLOAD_BATCH = 20

    enum class UploadFailure { AUTHORIZATION, SOURCE_CONFLICT, SOURCE_REJECTED, RETRY }
    fun uploadFailure(status: Int): UploadFailure = when (status) {
        401, 403 -> UploadFailure.AUTHORIZATION
        409 -> UploadFailure.SOURCE_CONFLICT
        408, 429 -> UploadFailure.RETRY
        in 400..499 -> UploadFailure.SOURCE_REJECTED
        else -> UploadFailure.RETRY
    }

    fun uploadEligible(sourceBinding: String, sourceVersion: Int, currentBinding: String, currentVersion: Int,
                       sourceUnresolved: Boolean, parked: Boolean): Boolean =
        !sourceUnresolved && !parked && sourceBinding == currentBinding && sourceVersion == currentVersion

    fun providerSource(sender: String): Boolean = sender.length in 2..96 &&
        Regex("(?:momo|m[- ]?money|mobile[- ]?money|mtn|airtel)", RegexOption.IGNORE_CASE)
            .containsMatchIn(sender)

    fun memberCaptureSupported(flavor: String): Boolean = flavor in setOf("production", "dev")

    /** Broad financial capture, independent of a wallet registry or receipt template. */
    fun memberSource(sender: String, body: String): Boolean = providerSource(sender) &&
        body.any { it.isDigit() } &&
        !Regex("(?:OTP|verification code|one[ -]time password|PIN\\s*(?:is|:|=)?\\s*\\d{3,8}\\b|buy\\s+(?:a\\s+)?bundle|promotion|promo\\b|airtime\\s+offer)",
            RegexOption.IGNORE_CASE).containsMatchIn(body) &&
        Regex("(?:RWF|FRW|UGX|KES|TZS|USD|EUR|transaction|txn|txid|reference|received|credited|paid|sent|revers|failed|pending|wakiriye|wahawe)",
            RegexOption.IGNORE_CASE).containsMatchIn(body)

    fun captureId(installation: String, binding: String, sender: String, body: String,
                  serviceCentreMillis: Long, subscription: Int?): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(
            listOf(installation, binding, sender, body, serviceCentreMillis.toString(),
                subscription?.toString().orEmpty()).joinToString("\u0000").toByteArray(Charsets.UTF_8),
        ).copyOf(16)
        digest[6] = ((digest[6].toInt() and 0x0f) or 0x50).toByte()
        digest[8] = ((digest[8].toInt() and 0x3f) or 0x80).toByte()
        return ByteBuffer.wrap(digest).let { UUID(it.long, it.long).toString() }
    }

    /** An enrollment-time inbox boundary is evidence; the scan/device clock alone is not. */
    fun historicalSourceResolved(inboxId: Long, baselineId: Long?,
                                 authorizedSubscription: Int?, observedSubscription: Int?,
                                 multipleSims: Boolean): Boolean {
        if (baselineId == null || inboxId <= baselineId) return false
        return sourceResolved(authorizedSubscription, observedSubscription, multipleSims)
    }

    fun sourceResolved(authorizedSubscription: Int?, observedSubscription: Int?, multipleSims: Boolean): Boolean {
        if (authorizedSubscription != null) return authorizedSubscription == observedSubscription
        return !multipleSims
    }

    fun completeParts(senders: List<String>, timestamps: List<Long>, bodies: List<String?>): Boolean =
        senders.isNotEmpty() && senders.distinct().size == 1 &&
            timestamps.size == senders.size && timestamps.all { it > 0 } &&
            timestamps.distinct().size == 1 && bodies.size == senders.size && bodies.all { it != null }
}
