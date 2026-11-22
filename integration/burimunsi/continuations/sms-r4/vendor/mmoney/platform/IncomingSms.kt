package com.ikanisa.mmoney.platform

/** Receipt time is callback time or provider DATE, never service-centre or financial-event time. */
data class IncomingSms(
    val sender: String?, val body: String, val receivedAt: Long?, val subscriptionId: Int?,
    val slotIndex: Int?, val providerRowId: String?, val deliveryKey: String, val method: String,
)
