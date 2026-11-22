package rw.ikanisa.burimunsi.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import rw.ikanisa.burimunsi.core.ListingQuery
import rw.ikanisa.burimunsi.core.ListingTarget
import rw.ikanisa.burimunsi.core.Route

/** Keeps listing filters associated with the record surface and operator that set them. */
internal class NativeListingQueries(private val collectionId: () -> String?) {
    data class Context(
        val collectionId: String?,
        val operatorId: String?,
        val route: Route,
        val routeId: String?,
        val sheet: Sheet?,
        val sheetId: String?,
    )

    private data class FilterOrigin(val target: ListingTarget, val context: Context)

    private var origin: FilterOrigin? = null
    private var draftReset: ListingQuery? = null
    private var queries by mutableStateOf<Map<Context, ListingQuery>>(emptyMap())

    fun target(state: UiState): ListingTarget? = when (state.sheet) {
        Sheet.STAFF -> ListingTarget.STAFF
        Sheet.AUDIT -> ListingTarget.AUDIT
        Sheet.HISTORY -> ListingTarget.HISTORY
        Sheet.FILTERS -> origin?.target
        null -> when (state.route) {
            Route.PAYMENTS, Route.MEMBER -> ListingTarget.PAYMENTS
            Route.MEMBERS -> ListingTarget.MEMBERS
            Route.SMS -> ListingTarget.SMS
            else -> null
        }
        else -> null
    }

    fun context(state: UiState): Context? = if (state.sheet == Sheet.FILTERS) origin?.context else
        Context(collectionId(), state.operator?.id, state.route, state.routeId, state.sheet, state.sheetId)

    fun query(state: UiState): ListingQuery = draftReset?.takeIf { state.sheet == Sheet.FILTERS }
        ?: target(state)?.let { queryFor(state, it) } ?: ListingQuery()

    fun queryFor(state: UiState, target: ListingTarget): ListingQuery {
        val restored = state.memberListing.takeIf { target == ListingTarget.MEMBERS && state.route == Route.MEMBERS }
        val saved = context(state)?.let(queries::get) ?: restored ?: ListingQuery.defaultsFor(target)
        return when {
            target == ListingTarget.SMS -> saved.copy(q = "", filter = state.filter)
            state.sheet == null && state.route in setOf(Route.PAYMENTS, Route.MEMBERS) ->
                saved.copy(q = state.search, filter = if (target == ListingTarget.PAYMENTS) state.filter else "all")
            else -> saved
        }
    }

    fun openFilters(state: UiState): UiState? {
        if (state.sheet == Sheet.FILTERS) return null
        val target = target(state) ?: return null
        val context = context(state) ?: return null
        origin = FilterOrigin(target, context)
        draftReset = null
        return state.copy(sheet = Sheet.FILTERS)
    }

    fun closeFilters(state: UiState): UiState? =
        if (state.sheet == Sheet.FILTERS) restoreOrigin(state) else null

    private fun restoreOrigin(state: UiState): UiState? {
        val context = origin?.context ?: return null
        discardFilters()
        return state.copy(sheet = context.sheet, sheetId = context.sheetId)
    }

    fun discardFilters() {
        origin = null
        draftReset = null
    }

    fun resetDraft(defaults: ListingQuery) {
        draftReset = defaults
    }

    fun apply(state: UiState, target: ListingTarget, query: ListingQuery): UiState {
        context(state)?.let { queries = queries + (it to query) }
        val surface = restoreOrigin(state) ?: state
        return surface.copy(
            listIndex = 0,
            listOffset = 0,
            listRestoration = null,
            memberAnchorId = surface.memberAnchorId.takeUnless { target == ListingTarget.MEMBERS },
            memberWindowStartId = surface.memberWindowStartId.takeUnless { target == ListingTarget.MEMBERS },
            search = if (surface.sheet == null && surface.route in setOf(Route.PAYMENTS, Route.MEMBERS)) query.q else surface.search,
            filter = if (surface.sheet == null && surface.route in setOf(Route.PAYMENTS, Route.SMS)) query.filter else surface.filter,
        )
    }

    fun clear() {
        queries = emptyMap()
        discardFilters()
    }
}
