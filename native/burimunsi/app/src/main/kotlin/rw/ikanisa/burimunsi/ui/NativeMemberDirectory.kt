package rw.ikanisa.burimunsi.ui

import rw.ikanisa.burimunsi.core.ListRestoreDecision
import rw.ikanisa.burimunsi.core.ListRestoreStop
import rw.ikanisa.burimunsi.core.ListingQuery
import rw.ikanisa.burimunsi.core.Member
import rw.ikanisa.burimunsi.core.Page
import rw.ikanisa.burimunsi.core.PageIntegrity
import rw.ikanisa.burimunsi.core.PagedRestoration
import rw.ikanisa.burimunsi.core.Route
import rw.ikanisa.burimunsi.core.SnapshotFreshness
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository

/** Owns the member page and its provenance. The caller fences IO to the current screen. */
internal class NativeMemberDirectory(
    private val repository: () -> NativeRepository,
    private val now: () -> Long,
) {
    data class Read(val page: Page<Member>, val offline: Boolean, val savedAt: Long?)

    private var viewportRevision = 0L

    fun first(query: ListingQuery, anchor: String?): Read {
        val source = repository()
        val page = if (anchor == null) source.members(query) else try {
            source.members(query, anchorId = anchor)
        } catch (failure: ApiFailure) {
            // An older API may reject the optional anchor; an offline phone may retain only page one.
            val fallback = failure.status in setOf(400, 422) ||
                (failure.status == 0 && failure.code == "connection_unavailable")
            if (!fallback) throw failure
            source.members(query)
        }
        return Read(page, source.lastReadFromCache, source.lastReadSavedAt)
    }

    fun next(query: ListingQuery, cursor: String): Read {
        val source = repository()
        val page = source.members(query, cursor)
        return Read(page, source.lastReadFromCache, source.lastReadSavedAt)
    }

    fun showFirst(state: UiState, query: ListingQuery, savedAnchor: String?, read: Read): UiState {
        val restored = savedAnchor?.takeIf { read.page.items.firstOrNull()?.id == it }
        val position = when {
            restored != null -> ListRestoreDecision(
                false, minOf(state.listIndex, PagedRestoration.headerItems(Route.MEMBERS)),
                state.listOffset, ListRestoreStop.POSITION_READY,
            )
            savedAnchor != null -> ListRestoreDecision(
                false, 0, 0, if (read.offline) ListRestoreStop.OFFLINE else ListRestoreStop.END_REACHED,
            )
            else -> PagedRestoration.decide(
                Route.MEMBERS, state.listIndex, state.listOffset, read.page.items.size,
                read.page.nextCursor, PagedRestoration.MAX_PAGES, read.offline,
                SnapshotFreshness.reusable(read.savedAt, now()),
            )
        }
        return state.copy(
            home = null, members = read.page, offline = read.offline, savedAt = read.savedAt,
            readbackRequired = state.readbackRequired && read.offline,
            listIndex = position.index, listOffset = position.offset, listRestoration = position.stop,
            memberAnchorId = restored, memberWindowStartId = restored, memberListing = query,
            memberViewportRevision = ++viewportRevision,
        )
    }

    fun append(state: UiState, previous: Page<Member>, read: Read): UiState {
        checkContract(previous.revision == read.page.revision, "cursor_stale")
        return state.copy(
            members = PageIntegrity.append(previous, read.page) { it.id },
            offline = state.offline || read.offline,
            savedAt = SnapshotFreshness.oldest(now(), state.savedAt, read.savedAt),
        )
    }
}
