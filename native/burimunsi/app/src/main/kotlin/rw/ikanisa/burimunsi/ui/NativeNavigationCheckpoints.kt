package rw.ikanisa.burimunsi.ui

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import rw.ikanisa.burimunsi.core.NavigationCheckpoint
import rw.ikanisa.burimunsi.core.NavigationCheckpointStore
import rw.ikanisa.burimunsi.core.NavigationCheckpointWriter
import rw.ikanisa.burimunsi.core.Operator
import rw.ikanisa.burimunsi.core.RestorationDecision
import rw.ikanisa.burimunsi.core.Route
import rw.ikanisa.burimunsi.core.ScreenGate

/** Persists a bounded navigation bookmark after the visible route is admitted. */
internal class NativeNavigationCheckpoints(
    store: NavigationCheckpointStore,
    private val clock: () -> Long,
    private val scope: CoroutineScope,
) {
    private val writer = NavigationCheckpointWriter(store)
    private var saveJob: Job? = null

    fun save(state: UiState, gate: ScreenGate, group: String?, debounce: Boolean) {
        val operator = state.operator ?: return
        if (state.route == Route.LOGIN || state.busy || gate != ScreenGate.OPEN || group == null) return
        val sms = state.route == Route.SMS
        val smsSearching = sms && state.showSmsSearchNotice
        val members = state.route == Route.MEMBERS
        val memberListing = state.memberListing.takeIf { members }
        val bookmark = NavigationCheckpoint(
            operator.id, group, clock(), state.route, state.routeId,
            if (sms) "" else memberListing?.q ?: state.search,
            state.filter, if (smsSearching) 0 else state.listIndex, if (smsSearching) 0 else state.listOffset,
            memberAnchorId = state.memberAnchorId.takeIf { members }, memberListing = memberListing,
        )
        val write = runCatching { writer.prepare(bookmark) }.getOrNull() ?: return
        saveJob?.cancel()
        saveJob = scope.launch(Dispatchers.IO) {
            if (debounce) delay(250)
            runCatching(write)
        }
    }

    fun clear() {
        val clear = writer.prepare(null)
        saveJob?.cancel()
        scope.launch(Dispatchers.IO) { runCatching(clear) }
    }

    fun restoredContext(operator: Operator, decision: RestorationDecision): UiState {
        val sms = decision.route == Route.SMS
        val staleSmsSearch = sms && decision.query.isNotEmpty()
        // Restoration reconstructs navigation only. Records and authority are read again.
        return UiState(
            operator = operator, route = decision.route, routeId = decision.routeId,
            search = if (sms) "" else decision.query, filter = decision.filter,
            listIndex = if (staleSmsSearch) 0 else decision.index,
            listOffset = if (staleSmsSearch) 0 else decision.offset,
            busy = true, pending = decision.pending, memberAnchorId = decision.memberAnchorId,
            memberListing = decision.memberListing,
        )
    }
}
