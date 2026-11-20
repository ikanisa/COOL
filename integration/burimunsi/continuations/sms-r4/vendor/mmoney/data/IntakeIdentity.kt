package com.ikanisa.mmoney.data

import com.ikanisa.mmoney.core.digestBody
import com.ikanisa.mmoney.platform.IncomingSms
import com.ikanisa.mmoney.platform.SmsSourcePolicy

object IntakeIdentity {
    /** Subscription identifiers are installation-local observations, never authentication. */
    fun sourceKey(message: IncomingSms): String = SmsSourcePolicy.subscription(message.subscriptionId)?.let { "subscription:$it" }
        ?: message.providerRowId?.let { "unresolved:provider:$it" }
        ?: "unresolved:delivery:${digestBody(message.deliveryKey)}"

    fun hasResolvedSource(message: IncomingSms): Boolean = SmsSourcePolicy.subscription(message.subscriptionId) != null
}
