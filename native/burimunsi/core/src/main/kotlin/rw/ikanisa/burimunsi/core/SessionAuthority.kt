package rw.ikanisa.burimunsi.core

/** In-process ownership witness; not a credential or server authorization claim.
 * Generation changes defeat A -> B -> A races even when token bytes are reused. */
@ConsistentCopyVisibility
data class SessionWitness internal constructor(val generation: Long, val token: String) {
    override fun toString() = "SessionWitness(redacted)"
}
class SessionAuthority {
    private var generation = 0L
    private var bearer: String? = null
    // An unattached cold process may use a still-valid protected observation
    // lease. Once this process knows authority was invalidated, merely
    // reattaching that saved bearer must not reopen local SMS custody.
    private var observationBlocked = false
    private val listeners = mutableSetOf<() -> Unit>()
    @Synchronized fun observe(listener: () -> Unit): () -> Unit {
        listeners.add(listener)
        return { synchronized(this) { listeners.remove(listener) } }
    }
    private fun changed() { listeners.toList().forEach { listener -> runCatching { listener() } } }
    @Synchronized fun revision():Long=generation
    @Synchronized fun hasActive():Boolean=bearer!=null
    @Synchronized fun observationAdmitted():Boolean=!observationBlocked
    @Synchronized fun blockObservationIfCurrent(witness:SessionWitness):Boolean {
        if(witness.generation!=generation||witness.token!=bearer)return false
        if(!observationBlocked){observationBlocked=true;changed()}
        return true
    }
    /** Call only after a current server profile has been saved durably. */
    @Synchronized fun confirmObservationCurrent(witness:SessionWitness) {
        withCurrent(witness){if(observationBlocked){observationBlocked=false;changed()}}
    }
    /** Join an identical protected session without disturbing another activity. */
    @Synchronized fun attach(token:String,persist:(SessionWitness)->Unit):SessionWitness {
        checkContract(Regex("[a-f0-9]{64}").matches(token),"invalid_session")
        checkContract(bearer==null||bearer==token,"session_changed")
        val attachingEmpty=bearer==null
        val witness=SessionWitness(if(attachingEmpty)Math.addExact(generation,1L) else generation,token)
        persist(witness)
        if(attachingEmpty){generation=witness.generation;bearer=token;changed()}
        return witness
    }
    /** Replace only after successful sign-in and only if no logout or other
     * session change happened since authentication began. */
    @Synchronized fun installRevision(ticket:Long,token:String,persist:(SessionWitness)->Unit) {
        checkContract(ticket==generation,"session_changed")
        checkContract(Regex("[a-f0-9]{64}").matches(token),"invalid_session")
        val next=Math.addExact(generation,1L)
        persist(SessionWitness(next,token))
        generation=next;bearer=token;observationBlocked=false;changed()
    }
    @Synchronized fun beginReplacement(clear: () -> Unit): Long {
        generation = Math.addExact(generation, 1L)
        bearer = null
        observationBlocked = true
        try { clear() } finally { changed() }
        return generation
    }
    @Synchronized fun install(ticket: Long, token: String, persist: () -> Unit) {
        installWithWitness(ticket,token){persist()}
    }
    @Synchronized fun installWithWitness(ticket: Long, token: String, persist: (SessionWitness) -> Unit) {
        checkContract(ticket == generation && bearer == null, "session_changed")
        checkContract(Regex("[a-f0-9]{64}").matches(token), "invalid_session")
        persist(SessionWitness(generation,token)) // Failure leaves no usable in-process credential.
        bearer = token
        observationBlocked = false
        changed()
    }
    /** Discard an invalid saved record only while its restore still owns the slot. */
    @Synchronized fun discardReplacement(ticket: Long, clear: () -> Unit): Boolean {
        if (ticket != generation || bearer != null) return false
        clear()
        return true
    }
    @Synchronized fun capture(): SessionWitness = SessionWitness(generation,
        bearer ?: throw ContractFailure("session_unavailable"))
    @Synchronized fun <T> withCurrent(witness: SessionWitness, action: () -> T): T {
        checkContract(witness.generation == generation && witness.token == bearer, "session_changed")
        return action()
    }
    /** A server-confirmed grant change supersedes work held by other activities using the same credential. */
    @Synchronized fun renewGrant(witness: SessionWitness, install: (SessionWitness) -> Unit) {
        withCurrent(witness) {
            val next = SessionWitness(Math.addExact(generation, 1L), witness.token)
            install(next)
            generation = next.generation
            observationBlocked = false
            changed()
        }
    }
    /** Install a server-approved replacement only while its predecessor owns
     * this slot. Persist before publishing the new in-process credential. */
    @Synchronized fun replaceCurrent(witness: SessionWitness, token: String, persist: () -> Unit) {
        replaceCurrentWithWitness(witness,token){persist()}
    }
    @Synchronized fun replaceCurrentWithWitness(witness: SessionWitness, token: String, persist: (SessionWitness) -> Unit) {
        checkContract(witness.generation == generation && witness.token == bearer, "session_changed")
        checkContract(Regex("[a-f0-9]{64}").matches(token) && token != bearer, "invalid_session")
        val next = Math.addExact(generation, 1L)
        persist(SessionWitness(next,token))
        generation = next
        bearer = token
        observationBlocked = false
        changed()
    }
    /** Prepare durable revocation and discard local data while excluding any
     * concurrent login, renewal, or credential replacement callback. */
    @Synchronized fun retire(prepareAndClear: () -> Unit) {
        val next = Math.addExact(generation, 1L)
        generation = next
        bearer = null
        observationBlocked = true
        try { prepareAndClear() } finally { changed() }
    }
    /** An old repository instance cannot sign out a newer instance's login. */
    @Synchronized fun retireOwned(witness: SessionWitness?, prepareAndClear: () -> Unit) {
        if(witness==null)checkContract(bearer==null,"session_changed")
        else checkContract(witness.generation==generation&&witness.token==bearer,"session_changed")
        retire(prepareAndClear)
    }
    @Synchronized fun invalidateIfCurrent(witness: SessionWitness, clear: () -> Unit): Boolean {
        if (witness.generation != generation || witness.token != bearer) return false
        beginReplacement(clear)
        return true
    }
}
