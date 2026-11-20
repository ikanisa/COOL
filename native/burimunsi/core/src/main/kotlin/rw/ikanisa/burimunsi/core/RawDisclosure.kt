package rw.ikanisa.burimunsi.core

/** Ephemeral disclosure state; it is never a financial snapshot or journal entry. */
enum class RawDisclosureState { AWAITING_REASON, LOADING, REVEALED, FAILURE }

object RawDisclosureInput {
    /** Count Unicode code points, matching the shared JSON wire validators. */
    fun reason(value:String):String? {
        if(value.any{it.isISOControl()})return null
        val trimmed=value.trim()
        return trimmed.takeIf{it.codePointCount(0,it.length) in 8..1000}
    }
}
