package rw.ikanisa.burimunsi.ui

import kotlinx.coroutines.CancellationException
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.Member
import rw.ikanisa.burimunsi.core.Page
import rw.ikanisa.burimunsi.core.Payment
import rw.ikanisa.burimunsi.core.Route
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

    private fun currentMember(page: Page<Member>?, member: Member?): Member? {
        if (member?.active != true) return null
        return page?.items?.singleOrNull { it.active && it.id == member.id && it.version == member.version }
    }

    fun select(state: UiState, member: Member): UiState {
        if (state.sheet != Sheet.ALLOCATE || state.route != Route.PAYMENT || state.payment?.id == null || state.routeId != state.payment.id) return state
        val current = currentMember(state.members, member) ?: return state
        return state.copy(selectedMember = current, draftDirty = true)
    }

    fun allocation(state: UiState): Allocation {
        val payment = state.payment?.takeIf { state.sheet == Sheet.ALLOCATE && state.route == Route.PAYMENT && it.id == state.routeId }
            ?: throw ApiFailure("record_unavailable")
        val member = currentMember(state.members, state.selectedMember) ?: throw ApiFailure("member_unavailable")
        return Allocation(payment, member)
    }

    fun post(allocation: Allocation, note: String): JSONObject =
        repository.allocate(allocation.payment, allocation.member, note)

    data class PostedPayment(val payment: Payment, val cached: Boolean, val savedAt: Long?)

    fun readPosted(allocation: Allocation): PostedPayment {
        val id = allocation.payment.id
        val payment = repository.payment(id)
        if (payment.id != id) throw ApiFailure("record_unavailable")
        return PostedPayment(payment, repository.lastReadFromCache, repository.lastReadSavedAt)
    }

    data class Candidates(val page: Page<Member>, val cached: Boolean, val savedAt: Long?)

    fun candidates(query: String): Candidates {
        val members = repository.members(query)
        return Candidates(members, repository.lastReadFromCache, repository.lastReadSavedAt)
    }

    fun showCandidates(state: UiState, query: String, result: Candidates, revalidating: Boolean): UiState =
        state.copy(members = result.page, allocationQuery = query, offline = state.offline || result.cached,
            panelSavedAt = result.savedAt, selectedMember = if (revalidating) null else currentMember(result.page, state.selectedMember))

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
