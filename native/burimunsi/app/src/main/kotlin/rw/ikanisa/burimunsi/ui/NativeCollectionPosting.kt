package rw.ikanisa.burimunsi.ui

import kotlinx.coroutines.CancellationException
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.Member
import rw.ikanisa.burimunsi.core.Operator
import rw.ikanisa.burimunsi.core.Page
import rw.ikanisa.burimunsi.core.PageIntegrity
import rw.ikanisa.burimunsi.core.Payment
import rw.ikanisa.burimunsi.core.Route
import rw.ikanisa.burimunsi.core.SnapshotFreshness
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.NativeRepository

/** Allocation selection and verified collection command outcomes. The repository owns the durable request. */
internal class NativeCollectionPosting(private val repository: NativeRepository) {
    enum class Outcome(val notice: String) {
        PENDING("Still awaiting an authoritative outcome. Do not repeat this action; contact the administrator if it remains unresolved."),
        COMMITTED("The original action committed. Refresh the records before starting another action; do not repeat it."),
        CHANGED("The original action committed, but its financial effect was reversed or corrected. Review the current ledger; do not repeat the original action."),
        CANCELLED("The previous action was cancelled before it was applied. Review the records before starting another action."),
        REJECTED("The previous action was rejected. Review the records before starting a different action."),
    }

    data class Allocation(val payment: Payment, val member: Member)

    private fun displayedPayment(state: UiState): Payment? = state.payment?.takeIf {
        state.sheet == Sheet.ALLOCATE && state.route == Route.PAYMENT && state.routeId == it.id
    }

    private fun currentMember(page: Page<Member>?, member: Member?): Member? {
        if (member?.active != true) return null
        return page?.items?.singleOrNull { it.active && it.id == member.id && it.version == member.version }
    }

    fun select(state: UiState, member: Member): UiState {
        if (displayedPayment(state) == null) return state
        val current = currentMember(state.members, member) ?: return state
        return state.copy(selectedMember = current, draftDirty = true)
    }

    fun allocation(state: UiState): Allocation {
        val payment = displayedPayment(state) ?: throw ApiFailure("record_unavailable")
        val member = currentMember(state.members, state.selectedMember) ?: throw ApiFailure("member_unavailable")
        return Allocation(payment, member)
    }

    fun post(allocation: Allocation, note: String): JSONObject =
        repository.allocate(allocation.payment, allocation.member, note)

    data class PaymentRead(val payment: Payment, val cached: Boolean, val savedAt: Long?, val allocatedFromVersion: Long?)

    fun readPayment(operator: Operator, id: String, allocatedFromVersion: Long?): PaymentRead {
        repository.withCurrentProfile(operator) { _, _ -> Unit }
        val payment = repository.payment(id)
        return repository.withCurrentProfile(operator) { _, _ ->
            if (payment.id != id || allocatedFromVersion != null && payment.version <= allocatedFromVersion) throw ApiFailure("record_unavailable")
            PaymentRead(payment, repository.lastReadFromCache, repository.lastReadSavedAt, allocatedFromVersion)
        }
    }

    fun showPayment(state: UiState, operator: Operator, read: PaymentRead): UiState {
        if (state.operator !== operator || state.route != Route.PAYMENT || (state.routeId ?: state.payment?.id) != read.payment.id) return state
        return state.copy(payment = read.payment, offline = read.cached, savedAt = read.savedAt,
            allocatedFromVersion = read.allocatedFromVersion, readbackRequired = state.readbackRequired && read.cached)
    }

    /** Accept the query before reading so a failed lookup cannot retain an earlier beneficiary. */
    fun startCandidateSearch(state: UiState, query: String): UiState =
        state.copy(
            allocationQuery = query, members = null, selectedMember = null, panelSavedAt = null,
            draftDirty = state.draft.values.any { it.isNotEmpty() },
        )

    data class Candidates(val query: String, val page: Page<Member>, val cached: Boolean, val savedAt: Long?, val continued: Boolean)

    fun candidates(query: String, previous: Page<Member>?): Candidates? {
        val cursor = if (previous == null) null else previous.nextCursor ?: return null
        val next = repository.members(query, cursor)
        val cached = repository.lastReadFromCache
        val savedAt = repository.lastReadSavedAt
        val page = if (previous == null) next else PageIntegrity.append(previous, next) { it.id }
        return Candidates(query, page, cached, savedAt, continued = previous != null)
    }

    fun showCandidates(state: UiState, result: Candidates, revalidating: Boolean, now: Long): UiState {
        if (displayedPayment(state) == null || state.allocationQuery != result.query) return state
        val savedAt = if (result.continued) SnapshotFreshness.oldest(now, state.panelSavedAt, result.savedAt) else result.savedAt
        val selected = when {
            result.continued -> state.selectedMember
            revalidating -> null
            else -> currentMember(result.page, state.selectedMember)
        }
        return state.copy(members = result.page, offline = state.offline || result.cached,
            panelSavedAt = savedAt, selectedMember = selected)
    }

    sealed interface Submission {
        data class Committed(val receipt: JSONObject) : Submission
        data class Failed(val error: Exception, val invalidate: Boolean, val outcome: Outcome?) : Submission
    }

    /** Called on IO. A failed response can follow a financial effect or a journal write. */
    fun submit(action: () -> JSONObject): Submission {
        return try {
            Submission.Committed(action())
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (error: Exception) {
            if (error is ApiFailure && error.code == "operation_financially_changed") {
                Submission.Failed(error, invalidate = true, outcome = Outcome.CHANGED)
            } else {
                val unresolved = try {
                    repository.pending() != null
                } catch (cancel: CancellationException) {
                    throw cancel
                } catch (_: Exception) {
                    true
                }
                Submission.Failed(error, unresolved, null)
            }
        }
    }

    /** Recovery asks for the original proof. It never calls the mutation again. */
    fun reconcile(): Outcome {
        val proof = repository.reconcilePending()
        return when (proof.getString("state")) {
            "pending" -> Outcome.PENDING
            "cancelled" -> Outcome.CANCELLED
            "rejected" -> Outcome.REJECTED
            "committed" -> if (proof.optString("financialState") in setOf("reversed", "corrected")) Outcome.CHANGED else Outcome.COMMITTED
            else -> throw ApiFailure("invalid_recovery_response")
        }
    }
}
