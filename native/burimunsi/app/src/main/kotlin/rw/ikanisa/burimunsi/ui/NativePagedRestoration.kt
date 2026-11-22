package rw.ikanisa.burimunsi.ui

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import rw.ikanisa.burimunsi.core.Access
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.burimunsi.core.ListRestoreDecision
import rw.ikanisa.burimunsi.core.Operator
import rw.ikanisa.burimunsi.core.Page
import rw.ikanisa.burimunsi.core.PageIntegrity
import rw.ikanisa.burimunsi.core.PagedRestoration
import rw.ikanisa.burimunsi.core.Route
import rw.ikanisa.burimunsi.core.SnapshotFreshness
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository

/** Read-only page reconstruction for one visible route and one exact repository grant. */
internal class NativePagedRestoration(
    private val repository: () -> NativeRepository,
    private val screen: () -> UiState,
    private val generation: () -> Int,
    private val clock: () -> Long,
    private val receiver: Boolean,
) {
    class Request internal constructor(
        val owner: Operator, val collection: String, val session: Long, val generation: Int,
        val route: Route, val routeId: String?, val filter: String,
        val index: Int, val offset: Int, val smsSearchNotice: Boolean,
    )

    data class Read<T>(val value: T, val offline: Boolean, val savedAt: Long?)
    data class Restored<T>(val content: Read<Page<T>>, val decision: ListRestoreDecision)

    fun request(): Request {
        val state = screen()
        val owner = state.operator ?: throw ApiFailure("session_unavailable", 401)
        val epoch = generation()
        requireAccess(owner, state.route)
        return repository().withCurrentProfile(owner) { group, revision ->
            Request(owner, group, revision, epoch, state.route, state.routeId, state.filter,
                state.listIndex, state.listOffset, state.showSmsSearchNotice)
        }
    }

    private fun requireAccess(owner: Operator, route: Route) {
        val now = clock()
        checkContract(now < owner.expiresAt, "session_unavailable")
        if (!Access.routeAllowed(owner, route, now, receiver)) throw ApiFailure("access_denied", 403)
    }

    /** The callback takes the latest same-scope screen while the grant still owns publication. */
    fun <T> withCurrent(request: Request, use: (UiState) -> T): T =
        repository().withCurrentProfile(request.owner) { group, revision ->
            if (request.generation != generation()) throw CancellationException()
            val state = screen()
            checkContract(group == request.collection && revision == request.session &&
                state.operator === request.owner && state.route == request.route &&
                state.routeId == request.routeId && state.filter == request.filter, "session_changed")
            requireAccess(request.owner, request.route)
            use(state)
        }

    suspend fun <T> read(request: Request, cacheable: Boolean = true, load: (NativeRepository) -> T): Read<T> =
        withContext(Dispatchers.IO) {
            val source = repository()
            withCurrent(request) {}
            val value = load(source)
            withCurrent(request) {
                Read(value, cacheable && source.lastReadFromCache, if (cacheable) source.lastReadSavedAt else clock())
            }
        }

    fun <T> append(current: Read<Page<T>>, next: Read<Page<T>>, id: (T) -> String): Read<Page<T>> =
        Read(PageIntegrity.append(current.value, next.value, id),
            current.offline || next.offline, SnapshotFreshness.oldest(clock(), current.savedAt, next.savedAt))

    suspend fun <T> restore(
        request: Request,
        first: Read<Page<T>>,
        id: (T) -> String,
        readNext: suspend (String) -> Read<Page<T>>,
    ): Restored<T> {
        var content = first
        var pages = 1
        val usedCursors = mutableSetOf<String>()
        fun position(pageCount: Int) = PagedRestoration.decide(
            request.route, request.index, request.offset, content.value.items.size, content.value.nextCursor,
            pageCount, content.offline, SnapshotFreshness.reusable(content.savedAt, clock()), request.smsSearchNotice,
        )
        while (true) {
            withCurrent(request) {}
            val decision = position(pages)
            if (!decision.fetchNext) return Restored(content, decision)
            val cursor = content.value.nextCursor ?: throw ContractFailure("invalid_page")
            checkContract(usedCursors.add(cursor), "invalid_page")
            val next = readNext(cursor)
            checkContract(next.value.nextCursor == null || next.value.nextCursor !in usedCursors, "invalid_page")
            val merged = append(content, next, id)
            // A conflicted page must still be rejected when it exceeds the restore budget.
            if (merged.value.items.size > PagedRestoration.MAX_ITEMS)
                return Restored(content, position(PagedRestoration.MAX_PAGES))
            content = merged
            pages++
        }
    }
}
