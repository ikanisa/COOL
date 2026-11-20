package rw.ikanisa.burimunsi.core

/** Mirrors Collect gateway v2; the receiving queue itself is reused unchanged. */
data class CaptureEnvelope(val id: String, val ownerId: String, val body: String)
data class DurableAck(val ok: Boolean, val contractVersion: Int, val stored: Boolean, val ownerId: String, val clientEnvelopeId: String, val rawSmsId: String, val bodySha256: String)
object Acknowledgements {
    fun matches(pending: CaptureEnvelope, ack: DurableAck): Boolean = ack.ok && ack.contractVersion == 2 && ack.stored &&
        pending.id.isNotBlank() && pending.ownerId.isNotBlank() && ack.rawSmsId.isNotBlank() &&
        ack.ownerId == pending.ownerId && ack.clientEnvelopeId == pending.id && ack.bodySha256 == Values.sha256(pending.body)
}
