package com.ikanisa.mmoney.platform

import com.ikanisa.mmoney.core.SmsPolicy

internal data class SmsBroadcastPart(val sender: String?, val body: String?, val transportTimestamp: Long)

internal sealed interface SmsBroadcastDecision {
    data object Ignore : SmsBroadcastDecision
    data object Recover : SmsBroadcastDecision
    data class Complete(val sender: String, val body: String, val transportTimestamp: Long) : SmsBroadcastDecision
}

/** The envelope checker supplies complete PDU sequence order; undecodable/count-mismatched groups never become partial originals. */
internal object SmsBroadcastPolicy {
    const val MAX_PARTS = 255
    const val MAX_MESSAGE_BYTES = 64 * 1024

    fun assemble(parts: List<SmsBroadcastPart?>, expectedParts: Int): SmsBroadcastDecision {
        if (expectedParts !in 1..MAX_PARTS || parts.size != expectedParts || parts.any { it == null }) return SmsBroadcastDecision.Recover
        val complete = parts.filterNotNull()
        // Ignore unrelated senders even if the supplied body is malformed; no body is persisted.
        if (complete.any { !SmsPolicy.isEligibleSender(it.sender) }) return SmsBroadcastDecision.Ignore
        val sender = complete.first().sender ?: return SmsBroadcastDecision.Recover
        if (complete.any { it.sender != sender || it.body == null }) return SmsBroadcastDecision.Recover
        val length = complete.sumOf { it.body!!.length.toLong() }
        if (length > MAX_MESSAGE_BYTES) return SmsBroadcastDecision.Recover
        val body = complete.joinToString("") { it.body!! }
        if (body.toByteArray(Charsets.UTF_8).size > MAX_MESSAGE_BYTES) return SmsBroadcastDecision.Recover
        return SmsBroadcastDecision.Complete(sender, body, complete.first().transportTimestamp)
    }
}
