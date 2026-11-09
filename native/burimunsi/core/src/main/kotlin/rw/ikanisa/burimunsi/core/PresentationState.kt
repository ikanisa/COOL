package rw.ikanisa.burimunsi.core

/** Display policy, not payment authority. No method sends, retries, resolves or deletes a command. */
enum class DisplayState { SIGN_IN, LOCKED, LOADING, EMPTY, CONTENT, OFFLINE, STALE, REJECTED, CONFLICT, UNCERTAIN, UNAVAILABLE }
enum class DisplayFailure { NONE, REJECTED, CONFLICT, UNCERTAIN, UNAVAILABLE }
data class DisplayInput(
    val authenticated: Boolean, val gate: ScreenGate = ScreenGate.OPEN,
    val loaded: Boolean = false, val itemCount: Int = 0, val busy: Boolean = false,
    val offline: Boolean = false, val fresh: Boolean = true,
    val unresolved: Boolean = false, val failure: DisplayFailure = DisplayFailure.NONE,
) { init { require(itemCount >= 0) } }
data class ScreenPresentation(
    val state: DisplayState, val showRecords: Boolean, val unresolvedWarning: Boolean,
    val mayStartCommand: Boolean, val mayCheckOutcome: Boolean, val mayRetryRead: Boolean,
)
object PresentationState {
    fun failure(code: String, uncertain: Boolean = false): DisplayFailure = when {
        uncertain || code in setOf("pending_operation_requires_resolution", "operation_still_pending",
            "operation_recovery_unavailable", "operation_recovery_denied", "invalid_recovery_response",
            "invalid_recovery_proof", "invalid_recovery_receipt", "operation_store_unavailable") -> DisplayFailure.UNCERTAIN
        code in setOf("operation_rejected", "access_denied", "invalid_name", "invalid_note", "invalid_phone",
            "invalid_passcode", "passcodes_do_not_match", "invalid_credentials", "try_again_later") -> DisplayFailure.REJECTED
        code.contains("changed") || code == "cursor_stale" || code.startsWith("invalid_history") ||
            code in setOf("invalid_page", "invalid_api_response", "conflict") -> DisplayFailure.CONFLICT
        else -> DisplayFailure.UNAVAILABLE
    }
    fun reduce(i: DisplayInput): ScreenPresentation {
        val pending = i.unresolved || i.failure == DisplayFailure.UNCERTAIN
        val visible = i.authenticated && i.gate == ScreenGate.OPEN
        val state = when {
            i.gate == ScreenGate.BACKGROUND -> DisplayState.LOCKED
            !i.authenticated -> if (i.busy) DisplayState.LOADING else DisplayState.SIGN_IN
            i.gate == ScreenGate.STALE -> DisplayState.STALE
            i.gate != ScreenGate.OPEN -> DisplayState.LOCKED
            pending -> DisplayState.UNCERTAIN
            i.failure == DisplayFailure.CONFLICT -> DisplayState.CONFLICT
            i.failure == DisplayFailure.REJECTED -> DisplayState.REJECTED
            i.loaded && !i.fresh -> DisplayState.STALE
            i.offline -> DisplayState.OFFLINE
            i.busy -> DisplayState.LOADING
            i.failure == DisplayFailure.UNAVAILABLE || !i.loaded -> DisplayState.UNAVAILABLE
            i.itemCount == 0 -> DisplayState.EMPTY
            else -> DisplayState.CONTENT
        }
        return ScreenPresentation(state,
            showRecords = visible && i.loaded && i.fresh && i.failure != DisplayFailure.CONFLICT,
            unresolvedWarning = pending,
            mayStartCommand = visible && i.loaded && i.fresh && !i.busy && !i.offline &&
                !pending && i.failure == DisplayFailure.NONE,
            // Offline is the last read result, not authority to forbid a new read-only probe.
            mayCheckOutcome = visible && pending && !i.busy,
            mayRetryRead = i.authenticated && i.gate !in setOf(ScreenGate.BACKGROUND, ScreenGate.CHECKING) && !i.busy)
    }
    /** English catalog source keys, translated only by the Android resource boundary. */
    fun label(state: DisplayState): String = when(state) {
        DisplayState.SIGN_IN -> "Sign in"
        DisplayState.LOCKED -> "Sign in again."
        DisplayState.LOADING -> "Working"
        DisplayState.EMPTY -> "No records to display."
        DisplayState.CONTENT -> "Records available."
        DisplayState.OFFLINE -> "Offline · read only"
        DisplayState.STALE -> "These records have expired. Reconnect and refresh before continuing."
        DisplayState.REJECTED -> "Action not accepted. Review the details."
        DisplayState.CONFLICT -> "Records changed. Refresh before continuing."
        DisplayState.UNCERTAIN -> "Previous action needs confirmation"
        DisplayState.UNAVAILABLE -> "This record is unavailable. Go back or refresh."
    }
}
