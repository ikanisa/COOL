package rw.ikanisa.burimunsi.ui

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.burimunsi.core.ListingQuery
import rw.ikanisa.burimunsi.core.PageIntegrity
import rw.ikanisa.burimunsi.core.Route
import rw.ikanisa.burimunsi.core.SmsListContent
import rw.ikanisa.burimunsi.core.SmsSourceRef
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository

/** Owns one bounded, audited inbox scan at a time. Search and bodies stay on the visible screen. */
internal class NativeSmsInboxScan(
    private val scope: CoroutineScope,
    private val repository: () -> NativeRepository,
    private val receiver: NativeReceiverStatus,
    private val screen: () -> UiState,
    private val display: (UiState) -> Unit,
    private val gateOpen: () -> Boolean,
    private val observationAccess: () -> Boolean,
    private val listing: () -> ListingQuery,
    private val observationPageAdded: () -> Unit,
) {
    private enum class Mode(val bodies: Int, val pages: Int) {
        PREVIEW(10, 0), SEARCH(20, 4), MORE_CANONICAL(5, 1), MORE_OBSERVATIONS(5, 1)
    }

    private data class Request(
        val mode: Mode,
        val owner: NativeReceiverStatus.Request,
        val listing: ListingQuery,
        val exposure: Long,
        val queryRevision: Long,
    )

    @Volatile private var exposure = 0L
    private var queryRevision = 0L
    private var searchedRevision: Long? = null
    private var scanning = false
    private var pending: Request? = null

    fun invalidate() {
        exposure++
        queryRevision++
        searchedRevision = null
        pending = null
    }

    fun searchChanged() { queryRevision++ }

    fun scanVisible() = request(if (screen().smsListSearch.isBlank()) Mode.PREVIEW else Mode.SEARCH)
    fun moreCanonical() { if (screen().smsListSearch.isBlank()) request(Mode.MORE_CANONICAL) }
    fun moreObservations() { if (screen().smsListSearch.isBlank()) request(Mode.MORE_OBSERVATIONS) }

    private fun visible(state: UiState) =
        gateOpen() && state.route == Route.SMS && state.sheet == null && state.filter != "queued"

    private fun request(mode: Mode) {
        if (!visible(screen())) return
        val owner = receiver.request() ?: return
        admit(Request(mode, owner, listing().copy(q = ""), exposure, queryRevision))
    }

    private fun current(request: Request, publish: (UiState) -> Unit = {}): Boolean {
        val state = screen()
        if (request.exposure != exposure || !visible(state) || state.filter != request.listing.filter) return false
        return receiver.current(request.owner) { publish(screen()) }
    }

    private fun admit(request: Request) {
        if (!scope.isActive || !current(request)) return
        if (request.mode == Mode.SEARCH && searchedRevision == request.queryRevision) return
        if (scanning) {
            val queued = pending
            pending = when {
                request.mode == Mode.SEARCH || queued?.mode == Mode.SEARCH -> request.copy(mode = Mode.SEARCH)
                request.mode == Mode.PREVIEW && queued != null -> queued
                else -> request
            }
            return
        }
        if (request.mode == Mode.SEARCH) searchedRevision = request.queryRevision
        scanning = true
        display(screen().copy(smsScanRunning = true, smsScanError = false))
        scope.launch {
            var failed = false
            try {
                scan(request)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                failed = true
                current(request) { display(it.copy(smsScanError = true, smsListContent = emptyMap())) }
            } finally {
                if (request.exposure == exposure && !current(request) { display(it.copy(smsScanRunning = false)) }) {
                    display(screen().copy(smsListContent = emptyMap(), smsListSearch = "", smsScanRunning = false, smsScanError = true))
                }
                scanning = false
                val next = pending
                pending = null
                if (next != null && (!failed || request.exposure != exposure)) admit(next)
            }
        }
    }

    private fun sources(state: UiState, mode: Mode): List<SmsSourceRef> {
        val canonical = if (mode == Mode.MORE_OBSERVATIONS) emptyList() else
            state.messages?.items.orEmpty().map { SmsSourceRef.Canonical(it.id) }
        val observations = if (mode == Mode.MORE_CANONICAL) emptyList() else
            state.observations?.items.orEmpty().map { it.source }
        return canonical + observations
    }

    private fun requireObservationAccess() {
        if (!observationAccess()) throw ApiFailure("access_denied", 403)
    }

    private suspend fun <T> read(request: Request, observation: Boolean, fetch: () -> T): T =
        withContext(Dispatchers.IO) {
            if (!current(request)) throw ContractFailure("session_changed")
            if (observation) requireObservationAccess()
            fetch()
        }

    private suspend fun reveal(request: Request, source: SmsSourceRef): Boolean {
        val observation = source is SmsSourceRef.Observation
        val content = read(request, observation) {
            val reason = "Automatic SMS list preview"
            when (source) {
                is SmsSourceRef.Canonical -> repository().raw(source.id, reason).let { SmsListContent(it.sender, it.body) }
                is SmsSourceRef.Observation -> repository().revealObservation(source, reason).let { SmsListContent(it.sender, it.rawBody) }
            }
        }
        return current(request) { state ->
            if (observation) requireObservationAccess()
            display(state.copy(smsListContent = state.smsListContent + (source to content)))
        }
    }

    private suspend fun scan(request: Request) {
        var bodies = 0
        var pages = 0
        var preferObservation = false
        while (current(request) && bodies < request.mode.bodies && screen().smsListContent.size < 100) {
            val state = screen()
            if (request.mode == Mode.SEARCH && (request.queryRevision != queryRevision || state.smsListSearch.isBlank())) return
            val missing = sources(state, request.mode).firstOrNull { it !in state.smsListContent }
            if (missing != null) {
                if (!reveal(request, missing)) return
                bodies++
                continue
            }
            if (pages >= request.mode.pages) return
            val canonical = state.messages?.nextCursor.takeUnless { request.mode == Mode.MORE_OBSERVATIONS }
            val observation = state.observations?.nextCursor.takeUnless { request.mode == Mode.MORE_CANONICAL }
            if (observation != null && (canonical == null || preferObservation)) {
                val old = state.observations ?: return
                val next = read(request, observation = true) {
                    repository().observationPage(request.listing.copy(filter = "all"), cursor = observation, limit = 5)
                }
                val page = PageIntegrity.append(old, next) { it.source.id }
                if (!current(request) { visible ->
                    requireObservationAccess()
                    display(visible.copy(observations = page))
                }) return
                observationPageAdded()
                preferObservation = false
            } else if (canonical != null) {
                val old = state.messages ?: return
                val next = read(request, observation = false) {
                    repository().sms(request.listing, cursor = canonical, limit = 5)
                }
                val summaries = next.copy(items = next.items.map { it.copy(sender = "", preview = "") })
                val page = PageIntegrity.append(old, summaries) { it.id }
                if (!current(request) { display(it.copy(messages = page)) }) return
                preferObservation = true
            } else return
            pages++
        }
    }
}
