package rw.ikanisa.burimunsi.ui

import kotlinx.coroutines.CancellationException
import rw.ikanisa.burimunsi.core.ContractFailure
import rw.ikanisa.burimunsi.core.RawDisclosureInput
import rw.ikanisa.burimunsi.core.RawDisclosureState
import rw.ikanisa.burimunsi.core.RawSms
import rw.ikanisa.burimunsi.core.Route
import rw.ikanisa.burimunsi.core.SmsSourceRef
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository

/** Keeps audited SMS plaintext scoped to its visible panel and current operator. */
internal class NativeSmsDisclosure(
    private val repository: () -> NativeRepository,
    private val io: NativeOperationIo,
    private val clock: () -> Long,
) {
    private var exposure = 0L

    fun invalidate() {
        exposure++
    }

    fun redact(state: UiState, preserveSmsSearch: Boolean = false): UiState = state.copy(
        raw = null,
        observationHints = null,
        queuedObservations = null,
        queuedUnavailable = false,
        queuedSearch = "",
        smsListContent = emptyMap(),
        smsListSearch = state.smsListSearch.takeIf { preserveSmsSearch && state.route == Route.SMS }.orEmpty(),
        smsScanRunning = false,
        smsScanError = false,
        rawDisclosure = RawDisclosureState.AWAITING_REASON,
        rawError = null,
        rawExposure = exposure,
        panelSavedAt = state.panelSavedAt.takeUnless { state.sheet == Sheet.RAW },
    )

    suspend fun load(
        reason: String,
        screen: () -> UiState,
        display: (UiState) -> Unit,
        authorized: () -> Boolean,
    ) {
        val panel = screen()
        val id = panel.sheetId ?: return
        val source = panel.rawSource ?: return
        if (source.id != id) throw ContractFailure("invalid_observation_source")
        val normalized = RawDisclosureInput.reason(reason) ?: throw ContractFailure("invalid_reason")
        val initialExposure = exposure
        val owner = panel.operator?.id
        fun current(): UiState? = screen().takeIf {
            initialExposure == exposure && authorized() && it.operator?.id == owner &&
                it.sheet == Sheet.RAW && it.sheetId == id && it.rawSource == source
        }

        display(panel.copy(rawDisclosure = RawDisclosureState.LOADING))
        try {
            val (raw, hints) = io {
                when (source) {
                    is SmsSourceRef.Canonical -> repository().raw(source.id, normalized) to null
                    is SmsSourceRef.Observation -> repository().revealObservation(source, normalized).let {
                        RawSms(it.source.id, it.sender, it.retainedAt, it.rawBody, null, null) to it.displayHints
                    }
                }
            }
            val visible = current() ?: return
            display(visible.copy(raw = raw, observationHints = hints, rawDisclosure = RawDisclosureState.REVEALED,
                rawError = null, panelSavedAt = clock()))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            val visible = current() ?: return
            if (error is ApiFailure && error.status == 401 ||
                error is ContractFailure && error.code in setOf("session_unavailable", "session_changed")) throw error
            val message = when {
                error is ApiFailure && error.uncertain -> "Original SMS access is unconfirmed. Close and check before trying again."
                error is ApiFailure && error.status == 403 -> "Original SMS access requires current permission and recent sign-in."
                else -> "Original SMS unavailable."
            }
            display(visible.copy(raw = null, rawDisclosure = RawDisclosureState.FAILURE, rawError = message))
        }
    }
}
