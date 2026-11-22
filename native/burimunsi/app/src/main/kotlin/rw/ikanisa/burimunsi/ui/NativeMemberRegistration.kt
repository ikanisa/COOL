package rw.ikanisa.burimunsi.ui

import org.json.JSONArray
import org.json.JSONObject
import rw.ikanisa.burimunsi.core.SmartCandidate
import rw.ikanisa.burimunsi.core.SmartImportResult
import rw.ikanisa.burimunsi.core.SmartImportRow
import rw.ikanisa.burimunsi.core.SmartOnboardingPresentation
import rw.ikanisa.burimunsi.core.SmartOnboardingState
import rw.ikanisa.burimunsi.core.SmartOnboardingStep
import rw.ikanisa.burimunsi.core.Values
import rw.ikanisa.burimunsi.core.checkContract
import rw.ikanisa.burimunsi.data.NativeRepository

/** Translates the registration wire contract for both native product flavors. */
internal class NativeMemberRegistration(private val repository: () -> NativeRepository) {
    data class Suggestions(val query: String, val items: List<SmartCandidate>, val nextCursor: String?)

    fun suggestions(query: String, cursor: String?): Suggestions {
        val normalized = query.trim()
        checkContract(normalized.length <= 80, "invalid_query")
        val result = repository().onboardingSuggestions(normalized, cursor)
        val rows = result.getJSONArray("items")
        val items = (0 until rows.length()).map { index ->
            val row = rows.getJSONObject(index)
            SmartCandidate(
                row.getString("candidateId"), row.getString("momoName"), row.getString("last3"),
                if (row.isNull("latestSeenAt")) null else row.getString("latestSeenAt"),
                row.getInt("sourceCount"),
            )
        }
        return Suggestions(normalized, items, if (result.isNull("nextCursor")) null else result.getString("nextCursor"))
    }

    fun showSuggestions(state: SmartOnboardingState, page: Suggestions, continuing: Boolean): SmartOnboardingState {
        val items = (if (continuing) state.suggestions else emptyList()) + page.items
        checkContract(items.map { it.candidateId }.toSet().size == items.size, "invalid_page")
        return state.copy(
            step = SmartOnboardingStep.SUGGESTIONS, query = page.query, suggestions = items,
            nextCursor = page.nextCursor, suggestionsLoaded = true,
        )
    }

    data class Preview(val sourceKind: String, val rows: List<SmartImportRow>)

    fun preview(input: MemberInputSelection, mime: String, bytes: ByteArray, consent: Boolean): Preview {
        val result = repository().onboardingPreview(mime, bytes, consent, input.scope)
        val rows = result.getJSONArray("rows")
        val items = (0 until rows.length()).map { index ->
            val row = rows.getJSONObject(index)
            SmartImportRow(row.getInt("row"), row.getString("momoName"), row.getString("momoNumber"),
                row.getString("status"), if (row.isNull("issue")) null else row.getString("issue"), row.getBoolean("selected"))
        }
        checkContract(items.map { it.row }.toSet().size == items.size, "invalid_api_response")
        return Preview(result.getString("sourceKind"), items)
    }

    fun confirmedMemberId(result: JSONObject): String? = runCatching {
        checkContract(result.getString("groupId") == repository().collectionId, "scope_changed")
        Values.id(result.getString("createdMemberId"))
    }.getOrNull()

    fun singleRow(state: SmartOnboardingState, draft: Map<String, String>, name: String, phone: String): JSONArray =
        JSONArray().put(importRow(SmartOnboardingPresentation.confirmedMember(state, draft, name, phone)))

    fun selectedRows(state: SmartOnboardingState): JSONArray {
        val selected = state.rows.filter { it.verified }
        checkContract(selected.isNotEmpty() && selected.size <= 500, "invalid_import")
        return JSONArray().also { rows -> selected.forEach { rows.put(importRow(it)) } }
    }

    private fun importRow(member: SmartImportRow): JSONObject = JSONObject()
        .put("row", member.row).put("name", member.name.trim()).put("phone", Values.phone(member.phone.orEmpty()))
        .put("verifiedOwnership", member.verifiedOwnership).put("acceptedTerms", member.acceptedTerms)
        .put("consentRecorded", member.consentRecorded)
        .also { if (member.candidateId != null) it.put("candidateId", member.candidateId) }

    fun importResult(response: JSONObject): SmartOnboardingState {
        val result = response.getJSONObject("importResult")
        val rows = result.getJSONArray("results")
        val items = (0 until rows.length()).map { index ->
            val row = rows.getJSONObject(index)
            SmartImportResult(row.getInt("row"), row.getString("status"), if (row.isNull("memberId")) null else row.getString("memberId"))
        }
        return SmartOnboardingState(step = SmartOnboardingStep.RESULTS, results = items, created = result.getInt("created"))
    }
}
