package rw.ikanisa.burimunsi.ui

import rw.ikanisa.burimunsi.core.*

enum class MemberImportFailure { UNREADABLE, CAMERA_UNAVAILABLE, TOO_LARGE }

/** UI contract; device, network and financial authority remain outside composables. */
interface BuriController {
    val state:UiState
    /** Non-secret, existing installation identity; never a token or a new registration. */
    val installationId:String get()=""
    val installationProfile:String get()="staff"
    /** Validated live public support contact, or null while unavailable. */
    val supportPhone:String? get()=null
    val presentation:ScreenPresentation get()=state.presentation(screenGate,System.currentTimeMillis())
    val screenGate:ScreenGate get()=ScreenGate.OPEN
    val receivingPermissionsRequired:Boolean get()=false
    val smsAccessGranted:Boolean get()=false
    val notificationAccessGranted:Boolean? get()=null
    val batteryExemptionGranted:Boolean? get()=null
    val continuousSyncRunning:Boolean? get()=null
    val continuousSyncProblem:String? get()=null
    val operation:UiOperation get()=UiOperation.NONE
    val operationLabel:String? get()=null
    /** Quiet reads may accept a navigation request without accepting a command. */
    val navigationBlocked:Boolean get()=state.busy||screenGate!=ScreenGate.OPEN
    val requestedRoute:Route? get()=null
    val exportFeedback:UiExportFeedback? get()=null
    val listingTarget:ListingTarget? get()=null
    val listingQuery:ListingQuery get()=ListingQuery()
    val canExportListing:Boolean get()=false
    fun applyListingQuery(query:ListingQuery) {}
    fun resetListingQuery() {}
    fun cancelExport() {}
    fun dismissExportFeedback() {}
    /** Only the original retirement outcome may be checked while this is true. */
    val receiverRetirementPending:Boolean get()=state.receiverRetirementPending
    fun allows(capability:Capability):Boolean
    fun login(phone:String,pin:String)
    fun logout()
    fun navigate(route:Route,id:String?=null)
    fun listPosition(route:Route,id:String?,index:Int,offset:Int) {}
    fun memberListPosition(revision: Long, index: Int, offset: Int, visibleKey: String?) {
        listPosition(Route.MEMBERS, null, index, offset)
    }
    fun showFirstMemberPage() {}
    fun editDraft(key:String,value:String) {}
    fun discardDraft() {}
    fun keepDraft() {}
    fun back()
    fun openUnallocated()
    fun search(value:String)
    fun searchSubmit()
    fun setFilter(value:String)
    fun refresh()
    fun more()
    fun openSheet(sheet:Sheet,id:String?=null)
    fun openSms(source:SmsSourceRef){openSheet(Sheet.RAW,source.id)}
    fun moreObservations() {}
    fun retryObservation() {}
    fun closeSheet()
    fun revealRaw(reason:String)
    fun selectMember(member:Member)
    fun allocationSearch(q:String)
    fun allocate(note:String)
    fun enroll(name:String,phone:String)
    /** Smart onboarding actions remain session-bound; implementations never retain document bytes. */
    fun onboardingOptions() {}
    fun onboardingManual() {}
    fun onboardingSearchQuery(value:String) {}
    fun onboardingSuggestions(query:String="",cursor:String?=null) {}
    fun onboardingChoose(candidateId:String) {}
    fun onboardingImport() {}
    fun onboardingPhoto(){onboardingImport()}
    fun onboardingEditRow(row:Int) {}
    fun onboardingConsent(field:String,value:Boolean,displayedDraft:Map<String,String>?=null) {}
    fun onboardingDocumentConsent(requestId:String, value:Boolean) {}
    fun onboardingSaveRow(name:String,phone:String) {}
    fun onboardingSubmit(name:String,phone:String) {}
    fun onboardingSubmitBatch() {}
    fun changePin(current:String,next:String,confirm:String)
    fun saveStaff(name:String,phone:String,pin:String,enroll:Boolean,allocate:Boolean)
    fun staffAction(action:String,pin:String?=null)
    fun requestRemoveStaff()
    fun setMemberActive(active:Boolean)
    fun pair(code:String)
    fun replaceReceiver(code:String)
    fun syncReceiver()
    fun setPaused(value:Boolean)
    fun retry()
}
