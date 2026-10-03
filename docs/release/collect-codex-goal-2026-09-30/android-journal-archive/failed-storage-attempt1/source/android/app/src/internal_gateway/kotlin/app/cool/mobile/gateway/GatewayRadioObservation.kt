package app.cool.mobile.gateway

/** A callback from another subscription/listener or an expired observation
 * never establishes current radio readiness. All clocks are monotonic. */
internal class GatewayRadioObservation(private val maxAgeMillis: Long = 5_000) {
    internal data class Token(val generation: Long, val subscriptionId: Int)
    internal data class Read(val token: Token, val registrationRequired: Boolean, val inService: Boolean)
    private var generation = 0L
    private var subscription: Int? = null
    private var requestedAt = 0L
    private var observedAt: Long? = null
    private var inService = false

    @Synchronized
    fun read(subscriptionId: Int, now: Long): Read {
        require(subscriptionId in 0 until Int.MAX_VALUE && now >= 0)
        val stamp = observedAt ?: requestedAt
        val renew = subscription != subscriptionId || now < stamp || now - stamp > maxAgeMillis
        if (renew) {
            generation++
            subscription = subscriptionId
            requestedAt = now
            observedAt = null
            inService = false
        }
        return Read(Token(generation, subscriptionId), renew, observedAt != null && inService)
    }

    @Synchronized
    fun accept(token: Token, value: Boolean, now: Long): Boolean {
        if (subscription != token.subscriptionId || generation != token.generation ||
            now < requestedAt || now < (observedAt ?: requestedAt)) return false
        observedAt = now
        inService = value
        return true
    }

    @Synchronized
    fun clear() {
        generation++
        subscription = null
        observedAt = null
        inService = false
    }

    @Synchronized
    fun current(token: Token): Boolean = subscription == token.subscriptionId && generation == token.generation
}
