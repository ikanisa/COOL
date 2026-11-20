package rw.ikanisa.burimunsi.core

/** A navigation bookmark is a position, never an authority-bearing cursor or record snapshot.
 * Automatic readback is bounded. The operator can load further pages explicitly.
 */
enum class ListRestoreStop { POSITION_READY, END_REACHED, OFFLINE, STALE, BUDGET_REACHED }
data class ListRestoreDecision(val fetchNext: Boolean, val index: Int, val offset: Int,
    val stop: ListRestoreStop)
object PagedRestoration {
    const val MAX_PAGES = 16 // Includes the first page; no unbounded background crawl.
    const val MAX_ITEMS = 2_000
    // LazyColumn items preceding records. Kept in the executable source/resource contract.
    fun headerItems(route: Route): Int = when (route) {
        Route.PAYMENTS -> 2
        Route.MEMBERS -> 1
        Route.MEMBER -> 5
        Route.SMS -> 3
        else -> error("Route is not paginated")
    }
    fun decide(route: Route, targetIndex: Int, targetOffset: Int, loaded: Int,
        nextCursor: String?, pagesRead: Int, offline: Boolean, fresh: Boolean): ListRestoreDecision {
        require(targetIndex in 0..100_000 && targetOffset in 0..100_000)
        require(loaded in 0..PageIntegrity.MAX_RETAINED && pagesRead >= 1)
        val headers = headerItems(route)
        // Empty state occupies one item; never restore onto the Load more control.
        val last = headers + maxOf(loaded, 1) - 1
        val index = minOf(targetIndex, last)
        val offset = if (index == targetIndex) targetOffset else 0
        val stop = when {
            targetIndex < headers + loaded -> ListRestoreStop.POSITION_READY
            nextCursor == null -> ListRestoreStop.END_REACHED
            offline -> ListRestoreStop.OFFLINE
            !fresh -> ListRestoreStop.STALE
            pagesRead >= MAX_PAGES || loaded >= MAX_ITEMS -> ListRestoreStop.BUDGET_REACHED
            else -> null
        }
        return ListRestoreDecision(stop == null, index, offset, stop ?: ListRestoreStop.POSITION_READY)
    }
    fun label(stop: ListRestoreStop?): String? = when (stop) {
        null, ListRestoreStop.POSITION_READY -> null
        ListRestoreStop.END_REACHED -> "Saved position is beyond this list. Showing the nearest available position."
        ListRestoreStop.BUDGET_REACHED -> "More records are available. Use Load more to continue."
        ListRestoreStop.OFFLINE, ListRestoreStop.STALE -> "Saved position could not be fully restored. Refresh when connected."
    }
}
