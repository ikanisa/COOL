package rw.ikanisa.burimunsi.ui

import androidx.compose.runtime.SnapshotMutationPolicy
import rw.ikanisa.burimunsi.core.*

enum class Sheet { PROFILE, PIN, HELP, ALLOCATE, ENROLL, STAFF, STAFF_EDIT, REMOVE_STAFF, GATEWAY, RAW, MEMBER_DETAILS, HISTORY, AUDIT, FILTERS, REPLACE_DEVICE }
data class UiState(
    val operator:Operator?=null,val route:Route=Route.LOGIN,val sheet:Sheet?=null,val busy:Boolean=false,val error:String?=null,
    val home:Home?=null,val payments:Page<Payment>?=null,val members:Page<Member>?=null,val ledger:Page<LedgerRow>?=null,val memberTransactions:Page<Payment>?=null,
    val payment:Payment?=null,val allocatedFromVersion:Long?=null,val member:Member?=null,val messages:Page<SmsRow>?=null,val observations:Page<ObservationListRow>?=null,
    val queuedObservations:List<QueuedObservationRow>?=null,val queuedUnavailable:Boolean=false,
    val observationProcessing:Map<SmsSourceRef.Observation,ObservationProcessing> = emptyMap(),val observationRetryNotice:String?=null,
    val smsListContent:Map<SmsSourceRef,SmsListContent> = emptyMap(),val smsListSearch:String="",val smsScanRunning:Boolean=false,val smsScanError:Boolean=false,
    val observationUnavailable:Boolean=false,val raw:RawSms?=null,val rawSource:SmsSourceRef?=null,val observationHints:ObservationHintSet?=null,
    val rawDisclosure:RawDisclosureState=RawDisclosureState.AWAITING_REASON,val rawError:String?=null,val rawExposure:Long=0,
    val staff:Page<StaffAccount>?=null,val selectedStaff:StaffAccount?=null,val audit:Page<AuditRow>?=null,
    val panelSavedAt:Long?=null,
    val history:Page<PaymentEvent>?=null,val historyPaymentId:String?=null,val historyOffline:Boolean=false,val historySavedAt:Long?=null,
    val gateway:GatewayStatus?=null,val search:String="",val queuedSearch:String="",val filter:String="all",val selectedMember:Member?=null,
    val failure:DisplayFailure=DisplayFailure.NONE,
    val readbackRequired:Boolean=false,
    val pending:Boolean=false,val configurationRequired:Boolean=false,val offline:Boolean=false,val passcodeChangePending:Boolean=false,val savedSessionPending:Boolean=false,
    val receiverRetirementPending:Boolean=false,val starting:Boolean=false,
    val commandNotice:String?=null,
    val routeId:String?=null,val listIndex:Int=0,val listOffset:Int=0,val savedAt:Long?=null,
    val listRestoration:ListRestoreStop?=null,
    val memberAnchorId: String? = null, val memberWindowStartId: String? = null,
    val memberListing: ListingQuery? = null, val memberViewportRevision: Long = 0,
    val sheetId:String?=null,
    val allocationQuery:String="",val draft:Map<String,String> = emptyMap(),val draftDirty:Boolean=false,val discardRequested:Boolean=false,
    val onboarding:SmartOnboardingState=SmartOnboardingState(),
) { override fun toString()="UiState(redacted)" }
/** Route-aware projection of real ViewModel state. No side effects or provider calls. */
fun UiState.presentation(gate:ScreenGate,now:Long):ScreenPresentation {
    val loaded=when(route){
        Route.LOGIN->false;Route.HOME->home!=null;Route.PAYMENTS->payments!=null
        Route.PAYMENT->payment!=null;Route.MEMBERS->members!=null
        Route.MEMBER->member!=null&&memberTransactions!=null;Route.SMS->messages!=null||observations!=null||queuedObservations!=null||observationUnavailable;Route.SETTINGS->operator!=null
    }
    val count=when(route){
        Route.PAYMENTS->payments?.items?.size?:0;Route.MEMBERS->members?.items?.size?:0
        Route.SMS->if(filter=="queued")queuedObservations?.size?:0 else (messages?.items?.size?:0)+(observations?.items?.size?:0);else->if(loaded)1 else 0
    }
    // Panels have their own provenance. A current route cannot make an old panel current.
    val panelLoaded=when(sheet){
        Sheet.STAFF,Sheet.STAFF_EDIT,Sheet.REMOVE_STAFF->staff!=null||selectedStaff!=null
        Sheet.AUDIT->audit!=null;Sheet.RAW->raw!=null;Sheet.GATEWAY->gateway!=null
        Sheet.ALLOCATE->members!=null||selectedMember!=null;Sheet.HISTORY->history!=null
        else->false
    }
    val panelClock=if(sheet==Sheet.HISTORY)historySavedAt else panelSavedAt
    val fresh=!readbackRequired&&(route==Route.SETTINGS||!loaded||SnapshotFreshness.reusable(savedAt,now))&&
        (!panelLoaded||SnapshotFreshness.reusable(panelClock,now))
    return PresentationState.reduce(DisplayInput(operator!=null&&now<operator.expiresAt,gate,loaded,count,busy,
        offline||historyOffline&&sheet==Sheet.HISTORY,fresh,pending,
        if(readbackRequired&&failure==DisplayFailure.NONE)DisplayFailure.CONFLICT else failure))
}

internal val UiState.showSmsSearchNotice: Boolean
    get() = smsListSearch.isNotBlank() || queuedSearch.isNotBlank()

internal object ScreenStatePolicy : SnapshotMutationPolicy<UiState> {
    // Protected reads require the current repository profile, even if its visible fields are identical.
    override fun equivalent(a: UiState, b: UiState): Boolean = a.operator === b.operator && a == b
}
