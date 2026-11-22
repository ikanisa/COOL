package rw.ikanisa.burimunsi.ui

import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.snapshots.SnapshotApplyConflictException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import rw.ikanisa.burimunsi.core.Capability
import rw.ikanisa.burimunsi.core.ListingQuery
import rw.ikanisa.burimunsi.core.ListingSort
import rw.ikanisa.burimunsi.core.QueuedObservationRow
import rw.ikanisa.burimunsi.core.Route
import rw.ikanisa.burimunsi.gateway.GatewayPort
import java.time.Instant
import java.util.concurrent.atomic.AtomicLong

/** A receiving-phone queue preview belongs to one visible query and one local journal revision. */
internal class NativeReceiverQueuePreview(
    private val status: NativeReceiverStatus,
    private val gateway: GatewayPort,
    private val screen: () -> UiState,
    private val display: (UiState) -> Unit,
    private val readable: () -> Boolean,
    private val listing: () -> ListingQuery,
    private val clock: () -> Long,
) {
    private val revision = AtomicLong()

    fun invalidate() { revision.incrementAndGet() }

    suspend fun refresh(): Boolean {
        val read = revision.incrementAndGet()
        val initial = screen()
        val queuedOnly = initial.filter == "queued"
        val search = if (queuedOnly) initial.queuedSearch else initial.smsListSearch
        val query = listing()
        fun currentView(state: UiState) =
            read == revision.get() && state.operator === initial.operator && state.route == Route.SMS &&
                state.sheet == null && state.filter == initial.filter && listing() == query &&
                (if (queuedOnly) state.queuedSearch else state.smsListSearch) == search
        fun setRows(state: UiState, rows: List<QueuedObservationRow>, unavailable: Boolean) {
            display(if (queuedOnly) state.copy(
                messages = null, observations = null, queuedObservations = rows, queuedUnavailable = unavailable,
                observationUnavailable = false, savedAt = clock(), listRestoration = null,
                listIndex = if (unavailable) 0 else state.listIndex, listOffset = if (unavailable) 0 else state.listOffset,
            ) else state.copy(queuedObservations = rows, queuedUnavailable = unavailable))
        }

        val allowed = initial.route == Route.SMS && initial.sheet == null &&
            initial.filter in setOf("queued", "all") && readable()
        val applied = if (!allowed) false else try {
            withContext(Dispatchers.IO) {
                val ticket = status.request() ?: return@withContext false
                if (ticket.operator !== initial.operator || !currentView(screen()) ||
                    Capability.SMS.key !in ticket.operator.capabilities || Capability.GATEWAY.key !in ticket.operator.capabilities)
                    return@withContext false
                val snapshot = gateway.queuedObservations(search) ?: return@withContext false
                if (snapshot.session.owner.accountId != ticket.operator.id || snapshot.session.owner.collectionId != ticket.group)
                    return@withContext false
                val rows = filterRows(snapshot.items, query)
                val context = currentCoroutineContext()
                var published = false
                // The adapter rereads protected session state and verifies the journal revision. Commit the
                // display under those same locks, without waiting for the UI dispatcher while holding them.
                val admitted = gateway.publishQueued(snapshot) {
                    context.ensureActive()
                    status.current(ticket) {
                        published = Snapshot.withMutableSnapshot {
                            val state = screen()
                            if (!currentView(state) || !readable()) false else {
                                setRows(state, rows, false)
                                true
                            }
                        }
                    }
                }
                admitted && published
            }
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (_: SnapshotApplyConflictException) {
            // A concurrent screen update owns the visible state. The normal queue refresh can retry.
            return false
        } catch (_: Exception) {
            false
        }
        if (!applied) {
            val state = screen()
            if (currentView(state)) setRows(state, emptyList(), true)
        }
        return applied
    }

    private fun filterRows(rows: List<QueuedObservationRow>, query: ListingQuery): List<QueuedObservationRow> {
        val (from, until) = try {
            query.fromAt?.let(Instant::parse) to query.untilAt?.let(Instant::parse)
        } catch (_: java.time.format.DateTimeParseException) {
            return emptyList()
        }
        val eligible = rows.mapNotNull { row ->
            val at = try { Instant.parse(row.at) } catch (_: java.time.format.DateTimeParseException) { return@mapNotNull null }
            if (from != null && at < from || until != null && at >= until) null else at to row
        }.sortedWith(compareBy({ it.first }, { it.second.id }))
        return (if (query.sort == ListingSort.NEWEST) eligible.asReversed() else eligible).map { it.second }
    }
}
