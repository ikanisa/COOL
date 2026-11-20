package rw.ikanisa.burimunsi.core

/** Local exposure guard only. Server authorization is still required on every request.
 * No transition here grants a session, creates a balance, or changes gateway authority. */
enum class ScreenGate { OPEN, BACKGROUND, REVALIDATE, CHECKING, STALE }

object VisibleDataFreshness {
    /** Check only timestamps for data actually present. An absent timestamp cannot
     * make an existing financial/evidence record fresh; an empty screen has no data to age. */
    fun expired(present:Boolean, savedAt:Long?, now:Long):Boolean =
        present && !SnapshotFreshness.reusable(savedAt,now)
}
