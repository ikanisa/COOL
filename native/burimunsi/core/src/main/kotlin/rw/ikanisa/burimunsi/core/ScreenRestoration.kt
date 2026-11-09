package rw.ikanisa.burimunsi.core

/** A failed journal read is not an empty journal. No command data belongs in a UI bookmark. */
enum class JournalKnowledge { UNREAD, CLEAR, UNRESOLVED, UNAVAILABLE }
enum class RestoreReason { SIGN_IN, NO_CHECKPOINT, OWNER_OR_GROUP_CHANGED, EXPIRED_OR_INVALID, ROUTE_DENIED, RESTORED }
data class RestorationDecision(
    val route: Route, val routeId: String? = null, val query: String = "", val filter: String = "all",
    val index: Int = 0, val offset: Int = 0, val pending: Boolean, val reason: RestoreReason,
) {
    val replayCommand: Boolean get() = false
    val clearJournal: Boolean get() = false
    val restoreDraft: Boolean get() = false
    val requiresReadback: Boolean get() = route != Route.LOGIN
}
object ScreenRestoration {
    fun decide(saved: NavigationCheckpoint?, operator: Operator?, groupId: String, now: Long,
        receiverVariant: Boolean, boundGateway: Boolean, journal: JournalKnowledge): RestorationDecision {
        val pending = journal != JournalKnowledge.CLEAR
        if (operator == null || now >= operator.expiresAt || now < 0)
            return RestorationDecision(Route.LOGIN, pending = pending, reason = RestoreReason.SIGN_IN)
        fun home(reason: RestoreReason) = RestorationDecision(Route.HOME, pending = pending, reason = reason)
        if (!Access.routeAllowed(operator, Route.HOME, now, receiverVariant, boundGateway))
            return RestorationDecision(Route.LOGIN, pending = pending, reason = RestoreReason.ROUTE_DENIED)
        if (saved == null) return home(RestoreReason.NO_CHECKPOINT)
        if (saved.ownerId != operator.id || saved.groupId != groupId) return home(RestoreReason.OWNER_OR_GROUP_CHANGED)
        if (!saved.validFor(operator.id, groupId, now)) return home(RestoreReason.EXPIRED_OR_INVALID)
        if (!Access.routeAllowed(operator, saved.route, now, receiverVariant, boundGateway)) return home(RestoreReason.ROUTE_DENIED)
        return RestorationDecision(saved.route, saved.routeId, saved.query, saved.filter, saved.index,
            saved.offset, pending, RestoreReason.RESTORED)
    }
}
