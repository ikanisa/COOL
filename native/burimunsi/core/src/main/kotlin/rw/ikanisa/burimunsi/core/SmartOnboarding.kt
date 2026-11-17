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
) {
    override fun toString()="SmartOnboardingState(redacted)"
}

/** Preserve preview and previously reviewed rows when entering/leaving the row editor. */
object SmartOnboardingPresentation {
    fun editRow(state:SmartOnboardingState,row:Int):SmartOnboardingState {
        require(state.rows.any{it.row==row})
        val selected=state.rows.first{it.row==row}
        return state.copy(step=SmartOnboardingStep.IMPORT_MEMBER,editingRow=row,
            verifiedOwnership=selected.verifiedOwnership,acceptedTerms=selected.acceptedTerms,consentRecorded=selected.consentRecorded)
    }
    fun saveRow(state:SmartOnboardingState,name:String,phone:String):SmartOnboardingState {
        val index=state.editingRow?:error("No import row selected")
        require(state.rows.any{it.row==index})
        val next=state.rows.map{if(it.row!=index)it else it.copy(name=name,phone=phone,status="ready",issue=null,selected=true,
            verifiedOwnership=state.verifiedOwnership,acceptedTerms=state.acceptedTerms,consentRecorded=state.consentRecorded)}
        return state.copy(step=SmartOnboardingStep.IMPORT,editingRow=null,rows=next,
            verifiedOwnership=false,acceptedTerms=false,consentRecorded=false)
    }
}
