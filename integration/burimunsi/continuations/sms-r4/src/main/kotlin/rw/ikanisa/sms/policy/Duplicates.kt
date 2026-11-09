package rw.ikanisa.sms.policy

enum class AdmissionKind { NEW, DUPLICATE, CONFLICT, FULL, RESERVED, HOLD }
data class Admission(val kind: AdmissionKind,val retained: Original?,val incoming: Original,val reason: String)
object DuplicatePolicy {
    /** Include acknowledgement tombstones in retained. Both observations survive a conflict decision. */
    fun admit(incoming: Original,retained: List<Original>,pendingCount: Int,capacity: Int = 1000,liveReserve: Int = 100): Admission {
        require(pendingCount >= 0 && capacity > 0 && liveReserve in 0..capacity)
        fun r(kind: AdmissionKind,old: Original? = null,reason: String = kind.name) = Admission(kind,old,incoming,reason)
        if (!incoming.valid()) return r(AdmissionKind.HOLD,reason="INVALID_IDENTITY")
        if (retained.any { !it.valid() } || retained.map { it.key }.distinct().size != retained.size)
            return r(AdmissionKind.HOLD,reason="CORRUPT_INDEX")
        val scoped = retained.filter { it.scope == incoming.scope }
        scoped.find { it.captureId == incoming.captureId }?.let {
            return if (it.evidenceHash == incoming.evidenceHash) r(AdmissionKind.DUPLICATE,it)
                else r(AdmissionKind.CONFLICT,it,"CAPTURE_ID_REUSE")
        }
        if (incoming.scope.contract == Contract.MMONEY_LEDGER_V1 && incoming.body != null) {
            scoped.find { it.sourceId == incoming.sourceId && it.body == incoming.body }?.let {
                return if (it.binding == incoming.binding) r(AdmissionKind.DUPLICATE,it,"EXACT_SOURCE_BODY")
                    else r(AdmissionKind.CONFLICT,it,"SOURCE_BINDING_CHANGED")
            }
        }
        if (!incoming.eligible()) return r(AdmissionKind.HOLD,reason="INPUT_NOT_ELIGIBLE")
        if (pendingCount >= capacity) return r(AdmissionKind.FULL)
        if (incoming.assembly.input.mode == InputMode.PROVIDER && pendingCount >= capacity-liveReserve) return r(AdmissionKind.RESERVED)
        return r(AdmissionKind.NEW)
    }
}
