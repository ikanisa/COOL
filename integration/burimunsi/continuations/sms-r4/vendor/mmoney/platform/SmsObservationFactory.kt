package com.ikanisa.mmoney.platform

import com.ikanisa.mmoney.core.digestBody

/** Transport time participates only in repeat-delivery identity; no receipt-time inference. */
internal object SmsObservationFactory {
    fun broadcast(message: SmsBroadcastDecision.Complete, source: SmsSourceEvidence, callbackAt: Long): IncomingSms {
        val delivery = digestBody(listOf(source.subscriptionId, message.sender, message.transportTimestamp,
            message.body).joinToString("\u0000"))
        return IncomingSms(message.sender, message.body, callbackAt, source.subscriptionId, source.slotIndex,
            null, "broadcast:$delivery", "broadcast")
    }
}
