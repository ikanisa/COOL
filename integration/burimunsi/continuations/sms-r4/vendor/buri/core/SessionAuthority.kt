package rw.ikanisa.burimunsi.core

/** In-process ownership witness; not a credential or server authorization claim.
 * Generation changes defeat A -> B -> A races even when token bytes are reused. */
data class SessionWitness internal constructor(val generation: Long, val token: String)
class SessionAuthority {
    private var generation = 0L
    private var bearer: String? = null
    @Synchronized fun beginReplacement(clear: () -> Unit): Long {
        generation = Math.addExact(generation, 1L)
        bearer = null
        clear()
        return generation
    }
    @Synchronized fun install(ticket: Long, token: String, persist: () -> Unit) {
        checkContract(ticket == generation && bearer == null, "session_changed")
        checkContract(Regex("[a-f0-9]{64}").matches(token), "invalid_session")
        persist() // Failure leaves no usable in-process credential.
        bearer = token
    }
    @Synchronized fun capture(): SessionWitness = SessionWitness(generation,
        bearer ?: throw ContractFailure("session_unavailable"))
    @Synchronized fun <T> withCurrent(witness: SessionWitness, action: () -> T): T {
        checkContract(witness.generation == generation && witness.token == bearer, "session_changed")
        return action()
    }
    @Synchronized fun invalidateIfCurrent(witness: SessionWitness, clear: () -> Unit): Boolean {
        if (witness.generation != generation || witness.token != bearer) return false
        beginReplacement(clear)
        return true
    }
}
