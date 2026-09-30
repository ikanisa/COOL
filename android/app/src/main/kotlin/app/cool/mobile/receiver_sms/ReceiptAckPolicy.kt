package app.cool.mobile.receiver_sms

import java.security.MessageDigest

/** Pure policy; called inside the native queue's synchronization lock. */
object ReceiptAckPolicy {
    data class Envelope(val id: String, val ownerUserId: String, val rawBody: String)
    fun canAcknowledge(
        activeOwner: String,
        expectedOwner: String,
        requestedHashes: Map<String, String>,
        stored: List<Envelope>,
    ): Boolean {
        if (activeOwner.isBlank() || expectedOwner != activeOwner || requestedHashes.isEmpty()) return false
        if (stored.map { it.id }.toSet().size != stored.size) return false
        if (stored.any { it.id.isBlank() || it.ownerUserId != activeOwner || it.rawBody.isBlank() }) return false
        val byId = stored.associateBy { it.id }
        return requestedHashes.all { (id, digest) ->
            val item = byId[id]
            item != null && digest.matches(Regex("^[a-f0-9]{64}$")) && sha256(item.rawBody) == digest
        }
    }
    fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it.toInt() and 255) }
}
