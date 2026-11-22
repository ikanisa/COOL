package rw.ikanisa.burimunsi.core

object SmartOnboardingLimits { const val MAX_BATCH_BYTES=524_288 }

/** Transient presentation state. Never store uploaded document bytes here. */
enum class SmartOnboardingStep { OPTIONS, SUGGESTIONS, MEMBER, IMPORT, IMPORT_MEMBER, RESULTS }
data class SmartCandidate(val candidateId:String,val momoName:String,val last3:String,val latestSeenAt:String?,val sourceCount:Int) {
    override fun toString()="SmartCandidate(redacted)"
}
data class SmartImportRow(
    val row:Int,val name:String,val phone:String?,val status:String,val issue:String?=null,val selected:Boolean=true,
    val verifiedOwnership:Boolean=false,val acceptedTerms:Boolean=false,val consentRecorded:Boolean=false,
    val candidateId:String?=null,
) {
    override fun toString()="SmartImportRow(redacted)"
    val verified:Boolean get()=selected&&verifiedOwnership&&acceptedTerms&&consentRecorded
}
data class SmartImportResult(val row:Int,val status:String,val memberId:String?) {
    override fun toString()="SmartImportResult(redacted)"
}
data class SmartOnboardingState(
    val step:SmartOnboardingStep=SmartOnboardingStep.OPTIONS,val query:String="",
    val suggestions:List<SmartCandidate> = emptyList(),val nextCursor:String?=null,val suggestionsLoaded:Boolean=false,
    val candidate:SmartCandidate?=null,val documentUri:String?=null,val documentMimeType:String?=null,
    val documentSelected:Boolean=false,val ocrConsent:Boolean=false,
    // A photo action carries consent only for its own captured image. No image bytes are stored here.
    val photoCaptureFlow:Boolean=false,val photoPreviewPending:Boolean=false,
    val sourceKind:String?=null,val rows:List<SmartImportRow> = emptyList(),val editingRow:Int?=null,
    val verifiedOwnership:Boolean=false,val acceptedTerms:Boolean=false,val consentRecorded:Boolean=false,
    val results:List<SmartImportResult> = emptyList(),val created:Int=0,
    val documentRequestId:String?=null,
) {
    override fun toString()="SmartOnboardingState(redacted)"
}

object SmartOnboardingPresentation {
    fun previewNeedsConsent(mime: String?): Boolean =
        mime == null || mime.startsWith("image/", ignoreCase = true) ||
            mime.equals("application/pdf", ignoreCase = true) || mime.equals("application/octet-stream", ignoreCase = true)

    private fun memberForm(step: SmartOnboardingStep) =
        step == SmartOnboardingStep.MEMBER || step == SmartOnboardingStep.IMPORT_MEMBER

    fun identityEdited(state: SmartOnboardingState, field: String, previous: String?, value: String): SmartOnboardingState {
        if (!memberForm(state.step) || (field != "name" && field != "phone") || previous.orEmpty() == value) return state
        return state.copy(verifiedOwnership = false, acceptedTerms = false, consentRecorded = false)
    }

    fun consent(state: SmartOnboardingState, draft: Map<String, String>, displayedDraft: Map<String, String>?,
                field: String, value: Boolean): SmartOnboardingState {
        if (!memberForm(state.step) || displayedDraft == null ||
            displayedDraft["name"] != draft["name"] || displayedDraft["phone"] != draft["phone"]) return state
        return when (field) {
            "ownership" -> state.copy(verifiedOwnership = value)
            "terms" -> state.copy(acceptedTerms = value)
            "consent" -> state.copy(consentRecorded = value)
            else -> state
        }
    }

    private fun confirmedNumber(state: SmartOnboardingState, draft: Map<String, String>, name: String, phone: String): String {
        checkContract(name == draft["name"] && phone == draft["phone"] && Presentation.validName(name) &&
            state.verifiedOwnership && state.acceptedTerms && state.consentRecorded, "invalid_import")
        return Values.phone(phone)
    }

    fun confirmedMember(state: SmartOnboardingState, draft: Map<String, String>, name: String, phone: String): SmartImportRow {
        checkContract(state.step == SmartOnboardingStep.MEMBER, "invalid_import")
        val number = confirmedNumber(state, draft, name, phone)
        val candidate = state.candidate
        checkContract(candidate == null || number.endsWith(candidate.last3), "candidate_changed")
        return SmartImportRow(1, name.trim(), number, "ready", verifiedOwnership = true,
            acceptedTerms = true, consentRecorded = true, candidateId = candidate?.candidateId)
    }

    fun editRow(state:SmartOnboardingState,row:Int):SmartOnboardingState {
        require(state.rows.any{it.row==row})
        val selected=state.rows.first{it.row==row}
        return state.copy(step=SmartOnboardingStep.IMPORT_MEMBER,editingRow=row,
            verifiedOwnership=selected.verifiedOwnership,acceptedTerms=selected.acceptedTerms,consentRecorded=selected.consentRecorded)
    }
    fun saveRow(state: SmartOnboardingState, draft: Map<String, String>, name: String, phone: String): SmartOnboardingState {
        if (state.step != SmartOnboardingStep.IMPORT_MEMBER) return state
        val index = state.editingRow ?: return state
        if (state.rows.none { it.row == index }) return state
        val number = try { confirmedNumber(state, draft, name, phone) } catch (_: ContractFailure) { return state }
        val next = state.rows.map { if (it.row != index) it else it.copy(name = name.trim(), phone = number, status = "ready",
            issue = null, selected = true, verifiedOwnership = true, acceptedTerms = true, consentRecorded = true) }
        return state.copy(step=SmartOnboardingStep.IMPORT,editingRow=null,rows=next,
            verifiedOwnership=false,acceptedTerms=false,consentRecorded=false)
    }
}
