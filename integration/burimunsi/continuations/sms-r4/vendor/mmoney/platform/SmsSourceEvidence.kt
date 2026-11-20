package com.ikanisa.mmoney.platform

/** An installation-local observation, not SIM authentication. Slots never identify a source. */
internal data class SmsSourceEvidence(val subscriptionId: Int?, val slotIndex: Int?)

internal object SmsSourcePolicy {
    // MAX_VALUE is Android's default-subscription selector, not a particular subscription.
    fun subscription(value: Int?): Int? = value?.takeIf { it >= 0 && it < Int.MAX_VALUE }
    fun slot(value: Int?): Int? = value?.takeIf { it in 0..31 }

    private fun integral(value: Any?): Int? = when (value) {
        is Int -> value
        is Long -> value.takeIf { it in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong() }?.toInt()
        else -> null
    }

    private fun resolve(primary: Any?, legacy: Any?, normalize: (Int?) -> Int?): Int? {
        val supplied = listOfNotNull(primary, legacy)
        if (supplied.isEmpty()) return null
        // A conflicting or malformed supplied value cannot be hidden by a fallback.
        val parsed = supplied.map { normalize(integral(it)) ?: return null }
        return parsed.distinct().singleOrNull()
    }

    fun broadcast(subscriptionExtra: Any?, legacySubscription: Any?, slotExtra: Any?, legacySlot: Any?) =
        SmsSourceEvidence(resolve(subscriptionExtra, legacySubscription, ::subscription),
            resolve(slotExtra, legacySlot, ::slot))

    fun providerSubscription(literal: String?): Int? = literal?.takeIf { it.matches(Regex("[0-9]{1,10}")) }
        ?.toIntOrNull()?.let(::subscription)
}
