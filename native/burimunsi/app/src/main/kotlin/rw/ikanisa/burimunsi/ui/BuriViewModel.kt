package rw.ikanisa.burimunsi.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import kotlinx.coroutines.*
import org.json.JSONObject
import org.json.JSONArray
import app.cool.mobile.BuildConfig
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.storage.*
import rw.ikanisa.burimunsi.gateway.*
import rw.ikanisa.burimunsi.core.export.*
import rw.ikanisa.burimunsi.export.ListingExportData
import java.io.File
import java.time.Instant
import java.time.ZoneId

enum class Sheet { PROFILE, PIN, HELP, ALLOCATE, ENROLL, STAFF, STAFF_EDIT, REMOVE_STAFF, GATEWAY, RAW, MEMBER_DETAILS, HISTORY, AUDIT, FILTERS, REPLACE_DEVICE }
data class UiState(
    val operator:Operator?=null,val route:Route=Route.LOGIN,val sheet:Sheet?=null,val busy:Boolean=false,val error:String?=null,
    val home:Home?=null,val payments:Page<Payment>?=null,val members:Page<Member>?=null,val ledger:Page<LedgerRow>?=null,val memberTransactions:Page<Payment>?=null,
    val payment:Payment?=null,val member:Member?=null,val messages:Page<SmsRow>?=null,val observations:Page<ObservationListRow>?=null,
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
    val sheetId:String?=null,val panelDepth:Int=0,
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
class BuriViewModel(private val app:Application,private val checkpoints:NavigationCheckpointStore,
    private val clock:()->Long
):AndroidViewModel(app),BuriController{
    // Keep the public Application-only constructor required by Android's ViewModel factory.
    constructor(app:Application):this(app,AndroidNavigationCheckpointStore(app),{System.currentTimeMillis()})
    constructor(app:Application,clock:()->Long):this(app,AndroidNavigationCheckpointStore(app),clock)
    override var operation:UiOperation by mutableStateOf(UiOperation.NONE);private set
    override var operationLabel:String? by mutableStateOf(null);private set
    private var quietRefreshInFlight by mutableStateOf(false)
    private var queuedNavigation by mutableStateOf<Pair<Route,String?>?>(null)
    override val navigationBlocked:Boolean get()=screenGate!=ScreenGate.OPEN||(state.busy&&(!quietRefreshInFlight||state.draftDirty))
    override val requestedRoute:Route? get()=queuedNavigation?.first
    override var exportFeedback:UiExportFeedback? by mutableStateOf(null);private set
    data class DownloadRequest(val id:Long,val fileName:String,val format:ExportFormat)
    var downloadRequest:DownloadRequest? by mutableStateOf(null);private set
    private val exportEpoch=java.util.concurrent.atomic.AtomicLong(0)
    private var exportDirectory:File?=null
    private var exportRenderer:((ExportFormat,ExportTable,File,()->Boolean)->Unit)?=null
    private data class PreparedDownload(val request:DownloadRequest,val file:File,val scope:RecordReadScope,
        val owner:String,val context:String,val createdAt:Long,val validateLocal:()->Unit)
    private var preparedDownload:PreparedDownload?=null
    private var downloadPickerInFlight=false
    private var outstandingPicker:DownloadRequest?=null
    private data class DownloadSave(val write:(File,()->Unit)->Unit,val abort:()->Unit)
    private var downloadSave:DownloadSave?=null
    private data class FilterOrigin(val sheet:Sheet?,val id:String?,val target:ListingTarget,val context:String)
    private var filterOrigin:FilterOrigin?=null
    private var filterDraftReset:ListingQuery?=null
    private var queries by mutableStateOf<Map<String,ListingQuery>>(emptyMap())
    private fun actualListingTarget():ListingTarget?=when(state.sheet){
        Sheet.STAFF->ListingTarget.STAFF;Sheet.AUDIT->ListingTarget.AUDIT;Sheet.HISTORY->ListingTarget.HISTORY
        null->when(state.route){Route.PAYMENTS,Route.MEMBER->ListingTarget.PAYMENTS;Route.MEMBERS->ListingTarget.MEMBERS;Route.SMS->ListingTarget.SMS;else->null}
        else->null
    }
    override val listingTarget:ListingTarget? get()=if(state.sheet==Sheet.FILTERS)filterOrigin?.target else actualListingTarget()
    private fun listingContext():String=if(state.sheet==Sheet.FILTERS)filterOrigin?.context.orEmpty()
        else listOf(repository?.boundCollectionId.orEmpty(),state.operator?.id.orEmpty(),state.route.name,state.routeId.orEmpty(),state.sheet?.name.orEmpty(),state.sheetId.orEmpty()).joinToString(":")
    private fun queryFor(target:ListingTarget,context:String=listingContext()):ListingQuery {
        val saved=queries[context]?:ListingQuery.defaultsFor(target)
        return if(target==ListingTarget.SMS)saved.copy(q="",filter=state.filter)
        else if(state.sheet==null&&state.route in setOf(Route.PAYMENTS,Route.MEMBERS))saved.copy(q=state.search,filter=if(target==ListingTarget.PAYMENTS)state.filter else "all") else saved
    }
    override val listingQuery:ListingQuery get()=if(state.sheet==Sheet.FILTERS&&filterDraftReset!=null)filterDraftReset!! else listingTarget?.let{queryFor(it)}?:ListingQuery()
    override val canExportListing:Boolean get(){
        val target=listingTarget?:return false
        return !downloadPickerInFlight&&state.sheet!=Sheet.FILTERS&&screenGate==ScreenGate.OPEN&&!state.busy&&!state.offline&&!state.readbackRequired&&
            !state.pending&&hasAccess(if(target in setOf(ListingTarget.STAFF,ListingTarget.AUDIT))Capability.STAFF else if(target in setOf(ListingTarget.SMS,ListingTarget.OBSERVATIONS))Capability.SMS else Capability.READ)&&
            (target !in setOf(ListingTarget.SMS,ListingTarget.OBSERVATIONS)||smsAccessGranted&&state.smsListSearch.isBlank()&&state.queuedSearch.isBlank())
    }
    override fun applyListingQuery(query:ListingQuery){
        val target=listingTarget?:return
        if(state.busy||screenGate!=ScreenGate.OPEN)return
        val valid=try{query.validated(target)}catch(_:Exception){state=state.copy(error="Check the filters and try again.");return}
        val context=listingContext()
        queries=queries+(context to valid)
        views.invalidateRecords()
        filterOrigin?.let{state=state.copy(sheet=it.sheet,sheetId=it.id);filterOrigin=null;filterDraftReset=null}
        state=state.copy(listIndex=0,listOffset=0,listRestoration=null,
            search=if(state.sheet==null&&state.route in setOf(Route.PAYMENTS,Route.MEMBERS))valid.q else state.search,
            filter=if(state.sheet==null&&state.route in setOf(Route.PAYMENTS,Route.SMS))valid.filter else state.filter)
        clearRawDisclosure()
        work(kind=UiOperation.REFRESH){if(state.sheet==null)refreshNow()else refreshPanelNow()}
    }
    override fun resetListingQuery(){
        val target=listingTarget?:return
        val defaults=ListingQuery.defaultsFor(target)
        if(state.sheet==Sheet.FILTERS){
            filterDraftReset=defaults
        }else applyListingQuery(defaults)
    }
    /** Only an app-private, owned temporary directory is cleaned; user downloads are never touched. */
    fun configureDownloads(directory:File,renderer:(ExportFormat,ExportTable,File,()->Boolean)->Unit){
        if(exportDirectory==null){
            require(directory.name=="burimunsi-exports")
            directory.mkdirs();require(directory.isDirectory)
            directory.listFiles()?.filter{it.isFile&&it.name.startsWith("download-")&&it.name.endsWith(".tmp")}?.forEach{it.delete()}
        }
        exportDirectory=directory;exportRenderer=renderer
    }
    fun prepareDownload(format:ExportFormat){
        if(!canExportListing)return
        if(format==ExportFormat.CSV&&(state.route!=Route.MEMBER||state.sheet!=null))return
        val visibleTarget=listingTarget?:return;val visibleQuery=listingQuery.validated(visibleTarget)
        val target=if(format==ExportFormat.CSV)ListingTarget.LEDGER else visibleTarget
        val query=if(format==ExportFormat.CSV)ListingQuery.defaultsFor(ListingTarget.LEDGER)else visibleQuery
        val context=listingContext();val owner=state.operator?.id?:return
        val memberId=state.member?.id.takeIf{state.route==Route.MEMBER}
        val paymentId=state.historyPaymentId?:state.sheetId.takeIf{state.sheet==Sheet.HISTORY}
        val directory=exportDirectory?:return
        val renderer=exportRenderer?:return
        clearDownload(false)
        val epoch=exportEpoch.incrementAndGet()
        exportFeedback=UiExportFeedback(UiExportPhase.PREPARING,format,canCancel=true)
        work(kind=UiOperation.EXPORT){
            var temporary:File?=null;var handedOff=false
            fun check(){
                if(exportEpoch.get()!=epoch||!foreground)throw ExportCancelledException()
                checkContract(state.operator?.id==owner&&listingContext()==context&&listingQuery==visibleQuery,"session_changed")
            }
            try{
                val scope=io{repo().recordReadScope()}
                val snapshot=io{ListingExportData(repo(),gateway).collect(target,query,memberId,paymentId,scope,
                    Instant.ofEpochMilli(clock()),ZoneId.of("Africa/Kigali"),::check){done,total->
                        viewModelScope.launch{if(exportEpoch.get()==epoch&&exportFeedback?.phase==UiExportPhase.PREPARING)exportFeedback=UiExportFeedback(UiExportPhase.PREPARING,format,completedRows=done,totalRows=total,canCancel=true)}
                    }}
                check()
                val file=io{File.createTempFile("download-",".tmp",directory)};temporary=file
                io{renderer(format,snapshot.table,file){exportEpoch.get()!=epoch||!foreground}}
                check();io{repo().validateRecordReadScope(scope);snapshot.validateLocal()}
                val name="BuriMunsi-${target.name.lowercase()}-${Instant.ofEpochMilli(clock()).atZone(ZoneId.of("Africa/Kigali")).toLocalDate()}.${format.extension}"
                val request=DownloadRequest(epoch,name,format)
                preparedDownload=PreparedDownload(request,file,scope,owner,context,clock(),snapshot.validateLocal)
                exportFeedback=UiExportFeedback(UiExportPhase.CHOOSING_DESTINATION,format,name,snapshot.table.rowCount,snapshot.table.rowCount,true)
                downloadRequest=request;handedOff=true
            }catch(e:Exception){
                if(e is CancellationException)throw e
                if(e is ApiFailure&&e.status==401||e is ContractFailure&&e.code in setOf("session_changed","session_unavailable")){needsSessionCheck=true;resumeQueued=true}
                if(exportEpoch.get()==epoch)exportFeedback=UiExportFeedback(if(e is ExportCancelledException)UiExportPhase.CANCELLED else UiExportPhase.FAILED,format,error=downloadError(e))
            }finally{if(!handedOff)temporary?.delete()}
        }
    }
    /** A recreated process restores only the outstanding picker identity, never private export bytes.
     * The retired request blocks replacement until its real Activity result is discarded. */
    fun restoreDownloadPicker(requestId:Long,format:ExportFormat){
        if(requestId<=0||requestId==Long.MAX_VALUE)return
        if(outstandingPicker?.let{it.id==requestId&&it.format==format}==true)return
        clearDownload(false)
        exportEpoch.updateAndGet{maxOf(it,requestId+1)}
        outstandingPicker=DownloadRequest(requestId,"",format);downloadPickerInFlight=true
    }
    /** Consume once before launching Android's document picker; rotation cannot launch a second picker. */
    fun takeDownloadRequest():DownloadRequest? {
        if(outstandingPicker!=null)return null
        val request=downloadRequest?:return null
        downloadRequest=null;downloadPickerInFlight=true;outstandingPicker=request;return request
    }
    fun downloadDestination(requestId:Long?,format:ExportFormat,write:((File,()->Unit)->Unit)?,abort:()->Unit={}):Boolean{
        val lease=outstandingPicker
        if(lease==null||lease.id!=requestId||lease.format!=format){
            viewModelScope.launch(Dispatchers.IO){runCatching{abort()}};return false
        }
        outstandingPicker=null;downloadPickerInFlight=false
        if(write==null){cancelExport();return true}
        if(preparedDownload?.request?.id!=lease.id){viewModelScope.launch(Dispatchers.IO){runCatching{abort()}};return false}
        downloadSave=DownloadSave(write,abort)
        // The result callback may arrive before Activity.onResume. Existing resume revalidation runs first.
        if(foreground&&screenGate==ScreenGate.OPEN&&!state.busy)drainDownload()
        return true
    }
    private fun drainDownload(){
        val save=downloadSave?:return
        val prepared=preparedDownload?:return
        if(!foreground||screenGate!=ScreenGate.OPEN||state.busy)return
        downloadSave=null;downloadPickerInFlight=false
        val epoch=prepared.request.id
        work(kind=UiOperation.EXPORT){
            var committed=false
            fun check(){
                if(exportEpoch.get()!=epoch||!foreground)throw ExportCancelledException()
                checkContract(state.operator?.id==prepared.owner&&listingContext()==prepared.context&&
                    SnapshotFreshness.reusable(prepared.createdAt,clock()),"session_changed")
                repo().validateRecordReadScope(prepared.scope)
            }
            try{
                exportFeedback=UiExportFeedback(UiExportPhase.WRITING,prepared.request.format,prepared.request.fileName,canCancel=true)
                operationLabel="Checking download access"
                io{check();repo().refreshSession();check();prepared.validateLocal()}
                operationLabel="Saving download"
                io{check();save.write(prepared.file,::check);check()}
                check() // Recheck on Main before publishing a terminal result after the IO suspension.
                committed=true
                exportFeedback=UiExportFeedback(UiExportPhase.COMPLETE,prepared.request.format,prepared.request.fileName)
            }catch(e:Exception){
                if(e is CancellationException)throw e
                if(e is ApiFailure&&e.status==401||e is ContractFailure&&e.code in setOf("session_changed","session_unavailable")){needsSessionCheck=true;resumeQueued=true}
                if(exportEpoch.get()==epoch)exportFeedback=UiExportFeedback(if(e is ExportCancelledException)UiExportPhase.CANCELLED else UiExportPhase.FAILED,prepared.request.format,error=downloadError(e))
            }finally{withContext(NonCancellable+Dispatchers.IO){if(!committed)runCatching{save.abort()};prepared.file.delete()};if(preparedDownload===prepared)preparedDownload=null}
        }
    }
    private fun downloadError(error:Exception):String=when{
        error is ExportCancelledException->"Download cancelled."
        error is ExportFailure->error.code.description
        error is ContractFailure&&error.code=="export_limit"->"This download is too large. Narrow the filters and try again."
        error is ContractFailure&&error.code in setOf("cursor_stale","invalid_page")->"Records changed. Refresh and try the download again."
        error is ApiFailure&&error.status==0->"Download unavailable. Reconnect and try again."
        else->"Unable to save download. Choose a destination and try again."
    }
    private fun clearDownload(showCancelled:Boolean){
        exportEpoch.incrementAndGet();downloadRequest=null;downloadSave?.let{pending->viewModelScope.launch(Dispatchers.IO){runCatching{pending.abort()}}};downloadSave=null;downloadPickerInFlight=outstandingPicker!=null
        preparedDownload?.file?.delete();preparedDownload=null
        if(showCancelled)exportFeedback=exportFeedback?.copy(phase=UiExportPhase.CANCELLED,canCancel=false,error=null)else exportFeedback=null
    }
    override fun cancelExport()=clearDownload(true)
    override fun dismissExportFeedback(){if(exportFeedback?.phase in setOf(UiExportPhase.COMPLETE,UiExportPhase.CANCELLED,UiExportPhase.FAILED))exportFeedback=null}
    private val checkpointLock=Any()
    private val checkpointEpoch=java.util.concurrent.atomic.AtomicLong(0)
    private var checkpointJob:Job?=null
    /** Best-effort UI convenience only; never writes a command or extends data/session freshness. */
    private fun checkpointNavigation(debounce:Boolean=false){
        val o=state.operator?:return
        if(state.route==Route.LOGIN||state.busy||screenGate!=ScreenGate.OPEN)return
        val group=repository?.boundCollectionId?:return
        val smsSearching=state.route==Route.SMS&&(state.smsListSearch.isNotBlank()||state.queuedSearch.isNotBlank())
        val bookmark=NavigationCheckpoint(o.id,group,clock(),state.route,state.routeId,
            if(state.route==Route.SMS)"" else state.search,state.filter,if(smsSearching)0 else state.listIndex,if(smsSearching)0 else state.listOffset)
        val encoded=runCatching{bookmark.encode()}.getOrNull()?:return
        val epoch=checkpointEpoch.incrementAndGet()
        checkpointJob?.cancel()
        checkpointJob=viewModelScope.launch(Dispatchers.IO){
            if(debounce)delay(250)
            synchronized(checkpointLock){
                if(checkpointEpoch.get()==epoch)runCatching{checkpoints.write(encoded)}
            }
        }
    }
    private fun forgetCheckpoint(){
        val epoch=checkpointEpoch.incrementAndGet();checkpointJob?.cancel()
        viewModelScope.launch(Dispatchers.IO){synchronized(checkpointLock){
            if(checkpointEpoch.get()==epoch)runCatching{checkpoints.clear()}
        }}
    }
    private suspend fun restoredContext(o:Operator):UiState{
        val saved=io{runCatching{NavigationCheckpoint.decode(checkpoints.read())}.getOrNull()}
        val journal=io{journalKnowledge()}
        val decision=ScreenRestoration.decide(saved,o,repo().collectionId,clock(),BuildConfig.IS_GATEWAY,gateway.bound(),journal)
        val staleSmsSearch=decision.route==Route.SMS&&decision.query.isNotEmpty()
        // No data, panel, credential, beneficiary, draft or command is reconstructed from the bookmark.
        return UiState(operator=o.takeUnless{decision.route==Route.LOGIN},route=decision.route,routeId=decision.routeId,
            search=if(decision.route==Route.SMS)"" else decision.query,filter=decision.filter,listIndex=if(staleSmsSearch)0 else decision.index,listOffset=if(staleSmsSearch)0 else decision.offset,
            busy=true,pending=decision.pending)
    }

    private var exposureJob:Job?=null
    private var queueRefreshJob:Job?=null
    private enum class SmsStream { CANONICAL, OBSERVATION }
    private data class SmsScanRequest(val search:Boolean=false,val manual:Boolean=false,val target:SmsStream?=null)
    private var smsScanJob:Job?=null
    private var observationStatusJob:Job?=null
    private val observationRetryRequests=mutableMapOf<String,String>()
    private var smsScanEpoch=0L
    private var smsSearchRevision=0L
    private var smsSearchBudgetEpoch=-1L
    private var smsSearchBudgetRevision=-1L
    private var smsPendingScan:SmsScanRequest?=null
    private var lastQueueRefreshAt=0L
    private var signOutRetryJob:Job?=null
    private var rawExposureEpoch=0L
    private var lifecycleObserved=false
    private var foreground by mutableStateOf(true)
    private var needsSessionCheck by mutableStateOf(false)
    private var sessionChecking by mutableStateOf(false)
    private var visibleExpired by mutableStateOf(false)
    private var resumeQueued=false
    // The first foreground callback can arrive while startup is already
    // restoring the saved session and visible records. That same transition
    // needs one authoritative read, not a second queued refresh.
    private var initialRestoreInFlight=false
    private var initialForegroundCoalesced=false
    private var restoreRetryPending=false
    private var sessionRetryPending=false
    private var lastRestoreAttemptAt=0L
    private var lastSessionRecoveryAttemptAt=0L
    private var lastConnectivityRetryAt=0L
    private var lastSessionRenewalAt=0L
    private var lastSignOutRetryAt=0L
    private var lastAutomaticReadAt=0L
    override var notificationAccessGranted:Boolean? by mutableStateOf(null);private set
    override var batteryExemptionGranted:Boolean? by mutableStateOf(null);private set
    override val continuousSyncRunning get() = receiverStatus.continuousHealth?.takeIf { it.supported }?.running
    override val continuousSyncProblem get() = receiverStatus.continuousHealth?.problem
    /** Public OS policy state only; no credential or receipt belongs in these values. */
    fun systemPolicyChanged(notifications:Boolean,batteryExempt:Boolean){
        notificationAccessGranted=notifications;batteryExemptionGranted=batteryExempt
        receiverStatus.refreshHealth()
    }
    private var supportJob:Job?=null
    private var supportClient:SupportContactClient?=null
    override var supportPhone:String? by mutableStateOf(null);private set
    private data class PendingExport(val operatorId:String,val memberId:String,val requestedAt:Long,val write:(String)->Unit)
    private data class PendingMemberDocument(val operatorId:String,val uri:String,val mimeType:String?,val capturedPhoto:Boolean=false)
    private var pendingMemberDocument:PendingMemberDocument?=null
    private var pendingExport:PendingExport?=null
    private fun drainExport(){
        val request=pendingExport?:return
        if(!foreground||state.busy||screenGate!=ScreenGate.OPEN)return
        pendingExport=null
        if(state.operator?.id!=request.operatorId||state.member?.id!=request.memberId||
            !SnapshotFreshness.reusable(request.requestedAt,clock())||!hasAccess(Capability.READ)){
            state=state.copy(error="Statement export cancelled. Open the member and try again.")
            return
        }
        work{
            val csv=io{repo().exportMember(request.memberId)}
            io{request.write(csv)}
        }
    }
    private fun drainMemberDocument(){
        if(!foreground||state.busy||screenGate!=ScreenGate.OPEN)return
        val pending=pendingMemberDocument?:return
        pendingMemberDocument=null
        if(state.operator?.id!=pending.operatorId||state.sheet!=Sheet.ENROLL||
            state.onboarding.step!=SmartOnboardingStep.IMPORT||
            (pending.capturedPhoto&&!state.onboarding.photoCaptureFlow))return
        if(!hasAccess(Capability.ENROLL)){
            if(pending.capturedPhoto)state=state.copy(onboarding=SmartOnboardingState(),
                error=message("access_denied",false),failure=DisplayFailure.UNAVAILABLE)
            return
        }
        state=state.copy(onboarding=state.onboarding.copy(documentUri=pending.uri,documentMimeType=pending.mimeType,
            documentSelected=true,ocrConsent=pending.capturedPhoto,photoCaptureFlow=pending.capturedPhoto,
            photoPreviewPending=pending.capturedPhoto,rows=emptyList(),sourceKind=null),error=null)
    }
    override val screenGate:ScreenGate get()=when {
        !foreground -> ScreenGate.BACKGROUND
        state.receiverRetirementPending -> ScreenGate.CHECKING
        state.operator==null -> ScreenGate.OPEN
        sessionChecking -> ScreenGate.CHECKING
        needsSessionCheck -> ScreenGate.REVALIDATE
        visibleExpired -> ScreenGate.STALE
        else -> ScreenGate.OPEN
    }
    /** Called by LifecycleResumeEffect. Does not cancel a dispatched operation. */
    fun onBackground(){
        queuedNavigation=null
        receiverStatus.invalidate()
        checkpointNavigation()
        if(!downloadPickerInFlight)clearDownload(exportFeedback?.phase in setOf(UiExportPhase.PREPARING,UiExportPhase.WRITING))
        clearRawDisclosure()
        queueRefreshJob?.cancel();queueRefreshJob=null
        state=state.copy(queuedObservations=null,queuedUnavailable=false,queuedSearch="")
        if(state.sheet==Sheet.RAW)dismissPanel()
        state=state.copy(gateway=null)
        lifecycleObserved=true;foreground=false;needsSessionCheck=true;resumeQueued=true
        gateway.foregroundChanged(false)
        supportJob?.cancel();supportJob=null;supportPhone=null
        exposureJob?.cancel();exposureJob=null
    }
    fun onForeground(){
        val sameTransition=!lifecycleObserved||foreground
        val coalesceInitialRestore=sameTransition&&initialRestoreInFlight
        lifecycleObserved=true;foreground=true;needsSessionCheck=true
        if(coalesceInitialRestore){
            initialForegroundCoalesced=true
            // If restoration has already validated the owner, this first
            // foreground callback is the same transition, not another resume.
            if(state.operator!=null&&!state.starting&&!resumeQueued)needsSessionCheck=false
        }else resumeQueued=true
        gateway.foregroundChanged(true)
        permissionsChanged()
        refreshSupport()
        startExposureChecks()
        drainResumeCheck()
        drainMemberDocument()
    }
    /** Called on the main thread when Android observes a usable network. A
     * saved session or covered screen is still revalidated by the server. */
    fun onNetworkAvailable(){
        if(!foreground||repository==null)return
        if(if(state.operator==null)!restoreRetryPending else !needsSessionCheck||!sessionRetryPending){
            automaticVisibleRefresh(force=true);return
        }
        val now=clock()
        if(lastConnectivityRetryAt>0L&&now>=lastConnectivityRetryAt&&now-lastConnectivityRetryAt<5_000L)return
        lastConnectivityRetryAt=now;resumeQueued=true;drainResumeCheck()
    }
    private fun refreshSupport(){
        supportJob?.cancel();supportPhone=null
        val client=supportClient?:return
        supportJob=viewModelScope.launch{
            val result=withContext(Dispatchers.IO){client.read()}
            if(foreground)supportPhone=result
        }
    }
    private fun drainResumeCheck(){
        if(!foreground||!resumeQueued||state.busy)return
        if(repository==null){resumeQueued=false;needsSessionCheck=false;return}
        resumeQueued=false
        if(state.operator==null&&restoreRetryPending)retrySavedSession()
        else if(BuildConfig.IS_GATEWAY||state.operator!=null)refreshSession() else needsSessionCheck=false
    }
    /** Evaluated while resumed, also synchronously before accepting any user action. */
    fun checkVisibleFreshness(){
        if(!lifecycleObserved||!foreground||state.operator==null)return
        if(clock()>=state.operator!!.expiresAt)needsSessionCheck=true
        if(visibleRecordsExpired(clock()))visibleExpired=true
    }
    /** Only server reads are retried here. Never replay a financial action or
     * extend a cached timestamp, and keep the existing freshness gate closed
     * until profile plus all visible scoped records have actually returned. */
    private fun automaticVisibleRefresh(force:Boolean=false){
        if(!foreground||state.busy||state.operator==null||sessionChecking||
            state.receiverRetirementPending||state.passcodeChangePending)return
        if(needsSessionCheck&&sessionRetryPending)return // Existing bounded authority-recovery loop owns this retry.
        val now=clock()
        val passive=state.sheet==null||state.sheet in setOf(Sheet.STAFF,Sheet.AUDIT,Sheet.GATEWAY,Sheet.HISTORY)
        val visibleAt=listOfNotNull(if(state.route==Route.SETTINGS)state.panelSavedAt else state.savedAt,
            if(state.sheet==Sheet.HISTORY)state.historySavedAt else if(state.sheet!=null&&passive)state.panelSavedAt else null).minOrNull()
        val cadenceDue=passive&&!state.draftDirty&&visibleAt!=null&&(now<visibleAt||now-visibleAt>=30_000L)
        if(!force&&!cadenceDue&&!visibleExpired&&!state.readbackRequired&&!state.offline&&!visibleRecordsExpired(now))return
        if(lastAutomaticReadAt>0L&&now>=lastAutomaticReadAt&&now-lastAutomaticReadAt<10_000L)return
        lastAutomaticReadAt=now
        refreshSession(quiet=screenGate==ScreenGate.OPEN&&!state.readbackRequired&&!state.offline&&!visibleRecordsExpired(now))
    }
    private fun visibleRecordsExpired(now:Long):Boolean {
        val base=when(state.route){
            Route.HOME->state.home!=null
            Route.PAYMENTS->state.payments!=null
            Route.MEMBERS->state.members!=null
            Route.PAYMENT->state.payment!=null
            Route.MEMBER->state.member!=null||state.memberTransactions!=null
            Route.SMS->state.messages!=null||state.observations!=null||state.queuedObservations!=null||state.observationUnavailable
            else->false
        }
        val panel=when(state.sheet){
            Sheet.STAFF,Sheet.STAFF_EDIT,Sheet.REMOVE_STAFF->state.staff!=null||state.selectedStaff!=null
            Sheet.AUDIT->state.audit!=null
            Sheet.RAW->state.raw!=null
            Sheet.GATEWAY->state.gateway!=null
            Sheet.ALLOCATE->state.members!=null||state.selectedMember!=null
            else->false
        }
        return VisibleDataFreshness.expired(base,state.savedAt,now)||
            VisibleDataFreshness.expired(panel,state.panelSavedAt,now)||
            VisibleDataFreshness.expired(state.sheet==Sheet.HISTORY&&state.history!=null,state.historySavedAt,now)
    }
    private fun hasAccess(capability:Capability)=Access.allows(state.operator,capability,clock(),BuildConfig.IS_GATEWAY,gateway.bound())

    override var state by mutableStateOf(UiState(pending=true,starting=true));private set
    override val presentation:ScreenPresentation get()=state.presentation(screenGate,clock())
    private val views=ViewMemory<UiState>()
    private var initialDraft:Map<String,String> = emptyMap()
    private data class PanelFrame(val value:UiState,val initialDraft:Map<String,String>)
    private val panels=mutableListOf<PanelFrame>()
    private var afterDiscard:(()->Unit)?=null
    private fun clearPanels(){panels.clear();initialDraft=emptyMap();afterDiscard=null}
    private fun withoutRaw(value:UiState)=value.copy(raw=null,observationHints=null,queuedObservations=null,queuedUnavailable=false,queuedSearch="",smsListContent=emptyMap(),smsListSearch="",smsScanRunning=false,smsScanError=false,rawDisclosure=RawDisclosureState.AWAITING_REASON,
        rawError=null,rawExposure=rawExposureEpoch,panelSavedAt=if(value.sheet==Sheet.RAW)null else value.panelSavedAt)
    /** Disclosure is never navigation memory, even while another panel is in front. */
    private fun clearRawDisclosure(preserveSmsSearch:Boolean=false){
        val returnSearch=state.smsListSearch.takeIf{preserveSmsSearch&&state.route==Route.SMS}
        rawExposureEpoch++
        smsScanEpoch++;smsSearchRevision++;smsPendingScan=null
        state=withoutRaw(state)
        if(returnSearch!=null)state=state.copy(smsListSearch=returnSearch)
        for(i in panels.indices)panels[i]=panels[i].copy(value=withoutRaw(panels[i].value))
    }
    private fun panelAllowed(sheet:Sheet?):Boolean=when(sheet){
        Sheet.STAFF,Sheet.STAFF_EDIT,Sheet.REMOVE_STAFF,Sheet.AUDIT->hasAccess(Capability.STAFF)
        Sheet.RAW->hasAccess(Capability.SMS)
        Sheet.GATEWAY,Sheet.REPLACE_DEVICE->BuildConfig.IS_GATEWAY&&state.operator?.role==Role.ADMIN
        Sheet.ENROLL->hasAccess(Capability.ENROLL)
        Sheet.ALLOCATE->hasAccess(Capability.ALLOCATE)&&state.payment?.let(PaymentPresentation::canAllocate)==true
        else->state.operator!=null
    }
    private fun dismissPanel(){
        filterOrigin=null
        clearRawDisclosure(preserveSmsSearch=state.route==Route.SMS&&state.sheet==Sheet.RAW)
        clearPanels()
        state=state.copy(sheet=null,sheetId=null,rawSource=null,panelDepth=0,draft=emptyMap(),draftDirty=false,
            discardRequested=false,selectedMember=null,selectedStaff=null,raw=null,error=null,onboarding=SmartOnboardingState())
    }
    /** Discard UI copies after a contradictory response; retain context, drafts and journal warnings.
     * Parent frames are fenced too, so closing a sheet cannot resurrect its old records.
     */
    private fun withoutRecords(value:UiState)=withoutRaw(value).copy(home=null,payments=null,members=null,ledger=null,memberTransactions=null,
        payment=null,member=null,messages=null,observations=null,observationUnavailable=false,raw=null,rawSource=null,staff=null,selectedStaff=null,audit=null,history=null,
        historyPaymentId=null,gateway=null,selectedMember=null,savedAt=null,panelSavedAt=null,historySavedAt=null,
        readbackRequired=true)
    private fun quarantineRecords(){
        views.invalidateRecords()
        for(i in panels.indices)panels[i]=panels[i].copy(value=withoutRecords(panels[i].value))
        state=withoutRecords(state)
    }
    private fun key(route:Route=state.route,id:String?=state.routeId)=route.name+":"+(id?:"")
    private fun clearViews(){queuedNavigation=null;receiverStatus.invalidate();observationStatusJob?.cancel();observationStatusJob=null;observationRetryRequests.clear();clearDownload(false);queries=emptyMap();filterOrigin=null;filterDraftReset=null;clearRawDisclosure();views.clear();clearPanels();pendingExport=null;pendingMemberDocument=null;forgetCheckpoint()}
    private fun rememberedContext(value:UiState)=UiState(operator=state.operator,route=value.route,routeId=value.routeId,
        search=value.search,filter=value.filter,listIndex=value.listIndex,listOffset=value.listOffset,
        pending=state.pending,busy=true,readbackRequired=value.readbackRequired)
    private fun reusable(value:UiState)=value.route!=Route.SMS&&!value.readbackRequired&&SnapshotFreshness.reusable(value.savedAt,clock())

    override fun listPosition(route:Route,id:String?,index:Int,offset:Int){if(!state.busy&&screenGate==ScreenGate.OPEN&&state.route==route&&state.routeId==id&&index in 0..100_000&&offset in 0..100_000){state=state.copy(listIndex=index,listOffset=offset);checkpointNavigation(debounce=true)}}
    override fun editDraft(key:String,value:String){
        if(state.busy||key !in setOf("name","phone","note","query","enroll","allocate"))return
        val maximum=when(key){"name"->100;"note"->500;"phone"->40;"query"->80;else->5}
        val next=state.draft+(key to value.take(maximum))
        state=state.copy(draft=next,draftDirty=state.selectedMember!=null||next.any{(k,v)->v!=(initialDraft[k]?:"")})
    }
    override fun discardDraft(){if(!state.busy){val next=afterDiscard;afterDiscard=null;dismissPanel();checkVisibleFreshness();next?.invoke();if(next==null&&state.route==Route.SMS&&state.filter!="queued"){
        if(state.filter=="all"){queueRefreshJob?.cancel();queueRefreshJob=viewModelScope.launch{refreshQueuedNow()}}
        requestSmsScan(SmsScanRequest(search=state.smsListSearch.isNotBlank()))
    }}}
    override fun keepDraft(){afterDiscard=null;state=state.copy(discardRequested=false)}
    private var generation=0
    private var workSerial=0L
    private var actionJob:Job?=null
    private var repository:NativeRepository?=null
    private val collectionPosting by lazy { NativeCollectionPosting(repo()) }
    val gateway=GatewayFactory.create(app,{repository?.boundCollectionId},
        {code,replace->(repository?:throw ApiFailure("session_unavailable",401)).pairGateway(code,replace)},
        retirementPending={repository?.hasReceiverRetirementRecord()?:false},
        recoverRetirement={repository?.recoverReceiverRetirement()},
        // Factory independently checks the actual bound receiving collection.
        authorizeControl={Access.allows(state.operator,Capability.GATEWAY,clock(),BuildConfig.IS_GATEWAY,true)})
    private val receiverStatus by lazy {
        NativeReceiverStatus(BuildConfig.IS_GATEWAY, gateway, { repository }, { state }, { foreground }, clock, viewModelScope)
    }
    private var install:DeviceProvisioning?=null
    override val installationId get()=install?.installationId.orEmpty()
    override val installationProfile get()=if(BuildConfig.IS_GATEWAY)"internal_receiver" else "staff"
    private var permissionRevision by mutableStateOf(0)
    private fun drainGatewayPermissionStatus() {
        if (!foreground || state.busy || screenGate != ScreenGate.OPEN) return
        val ticket = receiverStatus.takePermissionRefresh() ?: return
        work(kind=UiOperation.REFRESH,quietRefresh=true) {
            state=state.copy(gateway=null,panelSavedAt=if(ticket.sheet==Sheet.GATEWAY)null else state.panelSavedAt)
            receiverStatus.read(ticket) { refreshed ->
                state=state.copy(gateway=refreshed,panelSavedAt=if(ticket.sheet==Sheet.GATEWAY||ticket.route==Route.SETTINGS)clock()else state.panelSavedAt)
            }
        }
    }
    fun permissionsChanged(){
        permissionRevision++
        val currentPermissions=if(BuildConfig.IS_GATEWAY)listOf(
            android.Manifest.permission.RECEIVE_SMS, android.Manifest.permission.READ_SMS,
            android.Manifest.permission.READ_PHONE_STATE,
        ).map { it to app.checkSelfPermission(it) } else null
        clearRawDisclosure()
        state=state.copy(queuedObservations=null,queuedUnavailable=false,queuedSearch="")
        receiverStatus.permissionsChanged(currentPermissions, ::drainGatewayPermissionStatus)
    }
    override val smsAccessGranted get():Boolean {
        permissionRevision
        return BuildConfig.IS_GATEWAY&&listOf(android.Manifest.permission.RECEIVE_SMS,android.Manifest.permission.READ_SMS).all{
            app.checkSelfPermission(it)==android.content.pm.PackageManager.PERMISSION_GRANTED
        }
    }
    override val receivingPermissionsRequired get():Boolean {
        permissionRevision // Compose observes changes after an Android permission result.
        return receiverStatus.permissionsRequired { app.checkSelfPermission(it)==android.content.pm.PackageManager.PERMISSION_GRANTED }
    }
    fun requestReceivingPermissions(show: (Array<String>) -> Unit) {
        if (screenGate == ScreenGate.OPEN) receiverStatus.launchPermissions(show)
    }
    private fun retryableSessionFailure(e:ApiFailure)=e.status==0||e.status in listOf(408,425,429)||e.status>=500
    private suspend fun restoreSavedSession(){
        val starting=state.starting
        val o=try{io{repo().restore()}}catch(e:ApiFailure){
            restoreRetryPending=retryableSessionFailure(e)
            lastRestoreAttemptAt=clock()
            if(e.code=="passcode_change_unconfirmed")
                state=UiState(busy=true,error="Passcode change not confirmed. Checking securely; do not repeat it.",
                    failure=DisplayFailure.UNCERTAIN,passcodeChangePending=true,pending=state.pending)
            else if(restoreRetryPending&&io{repo().hasSavedSession()})
                state=UiState(busy=true,savedSessionPending=true,pending=state.pending)
            throw e
        }
        restoreRetryPending=false
        state=(if(o==null)UiState(busy=true,pending=io{journalKnowledge()!=JournalKnowledge.CLEAR}) else restoredContext(o)).copy(starting=starting)
        // A server-validated operator can see the authenticated loading shell;
        // no restored financial records are carried into that shell. A real
        // background/foreground transition remains covered until revalidation.
        if(state.operator!=null){
            if(!resumeQueued)needsSessionCheck=false
            state=state.copy(starting=false)
            operationLabel="Loading records"
        }
        if(o!=null&&BuildConfig.IS_GATEWAY)try{io{gateway.start()}}catch(e:CancellationException){throw e}catch(_:Exception){}
        if(state.operator!=null)try{refreshNow()}catch(e:ApiFailure){
            if(retryableSessionFailure(e)){needsSessionCheck=true;sessionRetryPending=true;lastSessionRecoveryAttemptAt=clock()}
            throw e
        }else forgetCheckpoint()
        sessionRetryPending=false
        if(!resumeQueued)needsSessionCheck=false
    }
    private fun retrySavedSession()=work(bypassGate=true){
        if(recoverReceiverRetirement()){restoreRetryPending=false;return@work}
        restoreSavedSession()
    }
    private fun observeProcessSession(){
        val observed=repo()
        val detach=observed.observeProcessSession{
            viewModelScope.launch{
                if(state.operator==null||observed.current()!=null)return@launch
                val oldOwner=state.operator?.id?:return@launch
                val oldGroup=observed.boundCollectionId
                val hadPending=state.pending
                generation++;clearViews();needsSessionCheck=false;visibleExpired=false;resumeQueued=false
                val ownerGeneration=generation
                // Clear old records before any network read. The existing
                // sign-out action remains available while reconnecting.
                state=UiState(savedSessionPending=true,pending=hadPending)
                val probe=withContext(Dispatchers.IO){
                    val pending=observed.hasPendingPasscode()
                    val attached=if(!pending&&oldGroup!=null)runCatching{observed.reattachSameOwner(oldOwner,oldGroup)} else Result.success(null)
                    pending to attached
                }
                if(generation!=ownerGeneration||state.busy)return@launch
                if(probe.first){
                    restoreRetryPending=true;lastRestoreAttemptAt=0L
                    state=UiState(error=message("passcode_change_unconfirmed",true),passcodeChangePending=true,
                        failure=DisplayFailure.UNCERTAIN,pending=hadPending)
                }else if(probe.second.getOrNull()!=null&&observed.current()!=null){
                    restoreRetryPending=false
                    state=UiState(operator=probe.second.getOrNull(),route=Route.HOME,pending=hadPending)
                    work(bypassGate=true){refreshNow()}
                }else if(probe.second.isFailure&&observed.hasSavedSession()){
                    restoreRetryPending=true;lastRestoreAttemptAt=0L
                    state=UiState(error="Check your connection",savedSessionPending=true,pending=hadPending)
                }else state=UiState(error="Sign in again.",pending=hadPending)
            }
        }
        viewModelScope.launch{try{awaitCancellation()}finally{detach()}}
    }
    init {
        try {
            install=DeviceProvisioning(app,GatewayFactory.installationId(app))
            Values.apiOrigin(BuildConfig.BURI_API_ORIGIN)
            supportClient=SupportContactClient(BuildConfig.BURI_API_ORIGIN,BuildConfig.BURI_API_PATH_PREFIX,BuildConfig.COLLECT_PUBLISHABLE_KEY)
            val api=ApiClient.phonePin(BuildConfig.BURI_API_ORIGIN,install!!.installationId,
                installationProfile,BuildConfig.BURI_API_PATH_PREFIX,BuildConfig.COLLECT_PUBLISHABLE_KEY){install!!.registrationToken()}
            repository=NativeRepository(app,api)
            observeProcessSession()
            // Phone/PIN login discovers scope on the server. A fresh installation
            // renders the original login immediately; no account/group is invented.
            initialRestoreInFlight=true
            work(bypassGate=true,kind=UiOperation.INITIAL_READ){
                operationLabel="Checking access"
                var completed=false
                try{
                    if(recoverReceiverRetirement())return@work
                    restoreSavedSession();completed=true
                }finally{
                    initialRestoreInFlight=false
                    // An unsuccessful or interrupted recovery cannot satisfy
                    // the foreground check. Preserve the existing retry path.
                    if(initialForegroundCoalesced&&!completed)resumeQueued=true
                    initialForegroundCoalesced=false
                }
            }
        }catch(_:Exception){state=UiState(error="Unable to sign in. Contact admin.",configurationRequired=true)}
    }
    private fun startExposureChecks(){
        exposureJob?.cancel()
        exposureJob=viewModelScope.launch{while(isActive&&foreground){
            delay(1_000)
            val o=state.operator;val now=clock()
            fun due(last:Long,interval:Long=30_000L)=last==0L||now<last||now-last>=interval
            if(o!=null&&sessionRetryPending&&needsSessionCheck&&!state.busy&&due(lastSessionRecoveryAttemptAt,10_000L)){
                lastSessionRecoveryAttemptAt=now;refreshSession()
            }else if(o!=null&&o.expiresAt-now<=60_000L){
                if(now>=o.expiresAt){clearRawDisclosure();if(state.sheet==Sheet.RAW)dismissPanel();needsSessionCheck=true}
                if(!state.busy&&due(lastSessionRenewalAt)){lastSessionRenewalAt=now;refreshSession()}
            }else if(o==null&&restoreRetryPending&&!state.busy&&due(lastRestoreAttemptAt,10_000L)){
                lastRestoreAttemptAt=now;retrySavedSession()
            }
            if(!state.busy&&due(lastSignOutRetryAt)&&signOutRetryJob?.isActive!=true){
                lastSignOutRetryAt=now
                signOutRetryJob=viewModelScope.launch(Dispatchers.IO){runCatching{repository?.retryPendingSignOuts()}}
            }
            if(state.route==Route.SMS&&state.filter in setOf("queued","all")&&!state.busy&&
                (lastQueueRefreshAt==0L||now<lastQueueRefreshAt||now-lastQueueRefreshAt>=3_000L)&&queueRefreshJob?.isActive!=true){
                lastQueueRefreshAt=now
                queueRefreshJob=viewModelScope.launch{refreshQueuedNow()}
            }
            checkVisibleFreshness()
            automaticVisibleRefresh()
            receiverStatus.refreshHealth()
        }}
    }

    private fun repo()=repository?:throw ApiFailure("configuration_required")
    private fun journalKnowledge():JournalKnowledge = try {
        val r=repository
        if(r==null)JournalKnowledge.UNAVAILABLE else if(r.pending()==null)JournalKnowledge.CLEAR else JournalKnowledge.UNRESOLVED
    }catch(_:Exception){JournalKnowledge.UNAVAILABLE}
    override fun allows(capability:Capability)=screenGate==ScreenGate.OPEN&&hasAccess(capability)
    private fun work(bypassGate:Boolean=false,preservePresentation:Boolean=false,kind:UiOperation?=null,quietRefresh:Boolean=false,action:suspend ()->Unit){
        checkVisibleFreshness()
        if(state.busy||(!bypassGate&&screenGate!=ScreenGate.OPEN))return
        state=if(preservePresentation)state.copy(busy=true) else state.copy(busy=true,error=null,failure=DisplayFailure.NONE)
        quietRefreshInFlight=quietRefresh
        operation=kind?:UiOperation.COMMAND
        operationLabel=when(operation){UiOperation.INITIAL_READ->"Loading records";UiOperation.SIGN_IN->"Signing in…";UiOperation.REFRESH->"Refreshing records";UiOperation.LOAD_MORE->"Loading more records";UiOperation.EXPORT->"Preparing download";UiOperation.COMMAND->"Saving changes";else->null}
        val started=generation
        val serial=++workSerial
        actionJob=viewModelScope.launch{
            try{action()}
            catch(e:CancellationException){throw e}
            catch(e:ApiFailure){
                if(started!=generation)throw CancellationException()
                if(e.code=="passcode_change_unconfirmed"){
                    clearViews();restoreRetryPending=true;lastRestoreAttemptAt=0L
                    state=UiState(error=message(e.code,true),busy=true,passcodeChangePending=true,failure=DisplayFailure.UNCERTAIN,pending=state.pending)
                }else if(e.status==401){
                    val error=if(kind==UiOperation.SIGN_IN&&state.operator==null&&e.code=="invalid_credentials")message(e.code,e.uncertain) else "Sign in again."
                    restoreRetryPending=false;sessionRetryPending=false;clearViews();state=UiState(error=error,busy=true,pending=state.pending||e.uncertain,failure=PresentationState.failure(e.code,e.uncertain))
                }
                else {
                    state=state.copy(error=message(e.code,e.uncertain),offline=e.status==0,failure=PresentationState.failure(e.code,e.uncertain))
                    if(state.failure==DisplayFailure.CONFLICT)quarantineRecords()
                }
            }catch(e:ContractFailure){
                if(started!=generation)throw CancellationException()
                val expiryCheck=e.code=="session_unavailable"&&state.operator?.let{clock()>=it.expiresAt}==true
                if(expiryCheck){restoreRetryPending=true;lastRestoreAttemptAt=0L}
                state=if(e.code=="session_unavailable"||e.code=="session_changed"){clearViews();UiState(error=if(expiryCheck)"Checking session and records" else "Sign in again.",busy=true,pending=state.pending)}
                    else state.copy(error=message(e.code,false),failure=PresentationState.failure(e.code))
                if(state.failure==DisplayFailure.CONFLICT)quarantineRecords()
            }catch(_:Exception){
                if(started!=generation)throw CancellationException()
                state=state.copy(error="Unable to complete. Refresh and try again.",failure=DisplayFailure.UNAVAILABLE)
            }finally{
                // Never construct a UiState copy before an IO suspension: expiry
                // during the journal read must not restore a signed-out screen.
                val pending=withContext(NonCancellable+Dispatchers.IO){journalKnowledge()!=JournalKnowledge.CLEAR}
                if(serial==workSerial)quietRefreshInFlight=false
                if(started==generation&&serial==workSerial){
                    state=state.copy(busy=false,pending=pending,starting=false)
                    operation=UiOperation.NONE;operationLabel=null
                    val requested=queuedNavigation;queuedNavigation=null
                    checkVisibleFreshness()
                    drainResumeCheck()
                    if(requested!=null&&!state.busy&&screenGate==ScreenGate.OPEN&&state.operator!=null)navigate(requested.first,requested.second)
                    drainExport()
                    drainDownload()
                    drainMemberDocument()
                    drainGatewayPermissionStatus()
                    checkpointNavigation()
                }
            }
        }
    }
    private suspend fun <T> io(action:()->T):T { val before=generation;val result=withContext(Dispatchers.IO){action()};if(before!=generation)throw CancellationException();return result }
    private fun mayPresentQueued():Boolean {
        val operator=state.operator?:return false
        return BuildConfig.IS_GATEWAY&&foreground&&screenGate==ScreenGate.OPEN&&state.route==Route.SMS&&state.sheet==null&&state.filter in setOf("queued","all")&&
            smsAccessGranted&&operator.role==Role.ADMIN&&clock()<operator.expiresAt&&
            setOf(Capability.SMS.key,Capability.GATEWAY.key).all{it in operator.capabilities}
    }
    /** No network is needed. The callback publishes under the owner and journal revision fences. */
    private suspend fun refreshQueuedNow(){
        val started=generation;val owner=state.operator?.id;val filter=state.filter;val query=if(filter=="queued")state.queuedSearch else state.smsListSearch
        fun sameView()=started==generation&&state.operator?.id==owner&&state.route==Route.SMS&&state.sheet==null&&state.filter==filter&&
            (if(filter=="queued")state.queuedSearch else state.smsListSearch)==query
        fun unavailable(){if(sameView())state=if(filter=="queued")state.copy(messages=null,observations=null,queuedObservations=emptyList(),queuedUnavailable=true,
            observationUnavailable=false,savedAt=clock(),listIndex=0,listOffset=0,listRestoration=null) else state.copy(queuedObservations=emptyList(),queuedUnavailable=true)}
        if(!mayPresentQueued()){unavailable();return}
        val snapshot=try{io{gateway.queuedObservations(query)}}catch(e:CancellationException){throw e}catch(_:Exception){null}
        if(snapshot==null){unavailable();return}
        var applied=false
        val admitted=try{gateway.publishQueued(snapshot){
            if(sameView()&&mayPresentQueued()&&snapshot.session.owner.accountId==owner&&
                snapshot.session.owner.collectionId==repository?.boundCollectionId){
                state=if(filter=="queued")state.copy(messages=null,observations=null,queuedObservations=filterQueued(snapshot.items),queuedUnavailable=false,
                    observationUnavailable=false,savedAt=clock(),listRestoration=null) else state.copy(queuedObservations=filterQueued(snapshot.items),queuedUnavailable=false)
                applied=true
            }
        }}catch(_:Exception){false}
        if(!admitted||!applied)unavailable() else lastQueueRefreshAt=clock()
    }
    private fun filterQueued(items:List<QueuedObservationRow>):List<QueuedObservationRow> {
        val query=queryFor(ListingTarget.SMS)
        val filtered=items.filter{v->runCatching{
            val at=Instant.parse(v.at)
            (query.fromAt==null||at>=Instant.parse(query.fromAt))&&(query.untilAt==null||at<Instant.parse(query.untilAt))
        }.getOrDefault(false)}.sortedWith(compareBy<QueuedObservationRow>{Instant.parse(it.at)}.thenBy{it.id})
        return if(query.sort==ListingSort.NEWEST)filtered.reversed() else filtered
    }
    /** Each source is disclosed through its existing audited endpoint. No query or
     * plaintext is sent in a list URL, persisted, or retained in navigation. */
    private fun requestSmsScan(request:SmsScanRequest=SmsScanRequest()) {
        fun admitted()=foreground&&screenGate==ScreenGate.OPEN&&state.route==Route.SMS&&state.filter!="queued"&&
            state.sheet==null&&hasAccess(Capability.SMS)&&state.operator?.role==Role.ADMIN
        if(!admitted())return
        // A repeated submit or pagination callback cannot renew the same query's budget.
        if(request.search&&smsSearchBudgetEpoch==smsScanEpoch&&smsSearchBudgetRevision==smsSearchRevision)return
        if(smsScanJob?.isActive==true){
            val previous=smsPendingScan
            smsPendingScan=if(request.search||previous?.search==true)SmsScanRequest(search=true) else if(request.manual)request else previous?:request
            return
        }
        val epoch=smsScanEpoch;val queryRevision=smsSearchRevision;val started=generation
        val operator=state.operator?:return;val group=repository?.boundCollectionId?:return;val filter=state.filter
        if(request.search){smsSearchBudgetEpoch=epoch;smsSearchBudgetRevision=queryRevision}
        fun current():Boolean {
            val live=runCatching{repository?.current()}.getOrNull()
            return epoch==smsScanEpoch&&started==generation&&admitted()&&state.filter==filter&&
                state.operator?.id==operator.id&&state.operator?.role==operator.role&&state.operator?.capabilities==operator.capabilities&&
                live?.id==operator.id&&live.role==operator.role&&live.capabilities==operator.capabilities&&clock()<operator.expiresAt&&
                clock()<live.expiresAt&&repository?.boundCollectionId==group
        }
        fun sources():List<SmsSourceRef> {
            val canonical=state.messages?.items.orEmpty().map{SmsSourceRef.Canonical(it.id)}
            val observations=state.observations?.items.orEmpty().map{it.source}
            return when(request.target){SmsStream.CANONICAL->canonical;SmsStream.OBSERVATION->observations;null->canonical+observations}
        }
        state=state.copy(smsScanRunning=true,smsScanError=false)
        smsScanJob=viewModelScope.launch{
            var count=0;var pages=0;var preferObservation=false;var failed=false
            val limit=if(request.search)20 else if(request.manual)5 else 10
            try{
                while(current()&&count<limit&&state.smsListContent.size<100){
                    if(request.search&&(smsSearchRevision!=queryRevision||state.smsListSearch.isBlank()))break
                    val missing=sources().firstOrNull{it !in state.smsListContent}
                    if(missing!=null){
                        if(missing is SmsSourceRef.Observation&&!smsAccessGranted){failed=true;state=state.copy(smsScanError=true,smsListContent=emptyMap());break}
                        val content=io{when(missing){
                            is SmsSourceRef.Canonical->repo().raw(missing.id,"Automatic SMS list preview").let{SmsListContent(it.sender,it.body)}
                            is SmsSourceRef.Observation->repo().revealObservation(missing,"Automatic SMS list preview").let{SmsListContent(it.sender,it.rawBody)}
                        }}
                        if(!current())break
                        if(missing is SmsSourceRef.Observation&&!smsAccessGranted){failed=true;state=state.copy(smsScanError=true,smsListContent=emptyMap());break}
                        state=state.copy(smsListContent=state.smsListContent+(missing to content));count++
                        continue
                    }
                    if(!(request.search||request.manual)||pages>=(if(request.search)4 else 1))break
                    val canonical=state.messages?.nextCursor.takeIf{request.target!=SmsStream.OBSERVATION}
                    val observation=state.observations?.nextCursor.takeIf{request.target!=SmsStream.CANONICAL}
                    val useObservation=observation!=null&&(canonical==null||preferObservation)
                    if(canonical==null&&observation==null)break
                    if(useObservation){
                        val old=state.observations?:break;val cursor=observation?:break
                        val next=io{repo().observationPage(queryFor(ListingTarget.SMS).copy(filter="all"),cursor=cursor,limit=5)}
                        if(!current())break
                        state=state.copy(observations=PageIntegrity.append(old,next){it.source.id});requestObservationProcessing();preferObservation=false
                    }else{
                        val old=state.messages?:break;val cursor=canonical?:break
                        val next=io{repo().sms(queryFor(ListingTarget.SMS),cursor=cursor,limit=5)}
                        if(!current())break
                        state=state.copy(messages=PageIntegrity.append(old,next.copy(items=next.items.map{it.copy(sender="",preview="")})){it.id});preferObservation=true
                    }
                    pages++
                }
            }catch(e:CancellationException){throw e}
            catch(e:Exception){
                failed=true
                if(current())state=state.copy(smsScanError=true,smsListContent=emptyMap())
            }finally{
                if(epoch==smsScanEpoch)state=if(current())state.copy(smsScanRunning=false)
                    else state.copy(smsListContent=emptyMap(),smsListSearch="",smsScanRunning=false,smsScanError=true)
                smsScanJob=null
                val pending=smsPendingScan;smsPendingScan=null
                if((!failed||epoch!=smsScanEpoch)&&pending!=null)requestSmsScan(pending)
            }
        }
    }
    /** One bounded metadata-only request for the currently loaded page(s). */
    private fun requestObservationProcessing(){
        val sources=state.observations?.items.orEmpty().map{it.source}.distinct().take(100)
        if(sources.isEmpty()||!BuildConfig.IS_GATEWAY||state.operator?.role!=Role.ADMIN||!smsAccessGranted)return
        val started=generation;val operatorId=state.operator?.id
        observationStatusJob?.cancel()
        observationStatusJob=viewModelScope.launch{
            val result=try{io{repo().observationProcessing(sources)}}
                catch(e:CancellationException){throw e}catch(_:Exception){emptyMap()}
            if(started==generation&&foreground&&state.route==Route.SMS&&state.filter=="all"&&
                state.operator?.id==operatorId&&state.operator?.role==Role.ADMIN&&smsAccessGranted&&hasAccess(Capability.SMS)){
                val live=state.observations?.items.orEmpty().map{it.source}.toSet()
                state=state.copy(observationProcessing=(state.observationProcessing-sources.toSet())+result.filterKeys{it in live})
            }
        }
    }
    override fun login(phone:String,pin:String)=work(kind=UiOperation.SIGN_IN){
        if(state.passcodeChangePending)throw ApiFailure("passcode_change_unconfirmed",503,true)
        if(state.savedSessionPending)throw ApiFailure("session_already_active",409)
        val o=io{repo().login(phone,pin)};restoreRetryPending=false;clearViews();state=UiState(operator=o,route=Route.HOME,busy=true,pending=state.pending)
        if(BuildConfig.IS_GATEWAY)try{io{gateway.start()}}catch(e:CancellationException){throw e}catch(_:Exception){}
        refreshNow();visibleExpired=false;if(!resumeQueued)needsSessionCheck=false
    }
    override fun logout(){
        clearDownload(false)
        queueRefreshJob?.cancel();queueRefreshJob=null
        state=state.copy(queuedObservations=null,queuedUnavailable=false,queuedSearch="")
        work(bypassGate=true){
        restoreRetryPending=false;sessionRetryPending=false
        gateway.stopContinuous()
        var unconfirmed:String?=null
        try{io{repo().logout()}}catch(e:ApiFailure){if(e.code in setOf("logout_unconfirmed","logout_unconfirmed_no_retry","logout_local_unconfirmed"))unconfirmed=e.code else throw e}
        finally{
            if(repository?.current()==null){
                generation++;clearViews();needsSessionCheck=false;visibleExpired=false;resumeQueued=false
                val notice=when(unconfirmed){
                    "logout_unconfirmed"->"Signed out on this phone. Server sign-out will retry when online."
                    "logout_unconfirmed_no_retry"->"Signed out on this phone. Server sign-out could not be confirmed."
                    "logout_local_unconfirmed"->"Sign-out could not be saved. Contact an administrator."
                    else->null
                }
                state=UiState(pending=state.pending,error=notice)
            }
        }
        }
    }
    fun refreshSession(quiet:Boolean=false){
        clearRawDisclosure()
        if(!quiet)needsSessionCheck=true
        if(state.busy){resumeQueued=true;return}
        if(!foreground)return
        work(bypassGate=true,kind=UiOperation.REFRESH,quietRefresh=quiet){
            sessionChecking=!quiet
            // Saved parent screens must be re-read too, not restored behind a child panel.
            views.invalidateRecords()
            for(i in panels.indices){val p=panels[i];panels[i]=p.copy(value=p.value.copy(savedAt=null,panelSavedAt=null,historySavedAt=null))}
            try{
                // The old native session may already be revoked by retirement.
                // Check the encrypted original proof before ordinary session validation.
                if(recoverReceiverRetirement())return@work
                if(state.operator==null){needsSessionCheck=false;return@work}
                val previous=state.operator
                val current=io{repo().refreshSession()}
                val accessChanged=previous?.id!=current.id||previous.role!=current.role||previous.capabilities!=current.capabilities
                if(accessChanged){
                    val allowed=Access.routeAllowed(current,state.route,clock(),BuildConfig.IS_GATEWAY,gateway.bound())
                    val old=state;clearViews()
                    state=UiState(operator=current,route=if(allowed)old.route else Route.HOME,
                        routeId=if(allowed)old.routeId else null,busy=true,pending=old.pending)
                }else state=state.copy(operator=current,offline=false)
                refreshNow()
                if(state.sheet!=null){
                    if(panelAllowed(state.sheet))refreshPanelNow()
                    else{clearPanels();state=state.copy(sheet=null,sheetId=null,panelDepth=0,raw=null,staff=null,audit=null,history=null,selectedStaff=null,selectedMember=null,draft=emptyMap(),draftDirty=false)}
                }
                // A successful profile request does not refresh any financial record by itself.
                if(visibleRecordsExpired(clock()))throw ApiFailure("fresh_records_required",409)
                if(state.route==Route.SETTINGS)state=state.copy(readbackRequired=false)
                visibleExpired=false;needsSessionCheck=false;sessionRetryPending=false
            }catch(e:ApiFailure){
                sessionRetryPending=retryableSessionFailure(e);lastSessionRecoveryAttemptAt=clock()
                throw e
            }finally{sessionChecking=false}
        }
    }
    override fun navigate(route:Route,id:String?){
        checkVisibleFreshness()
        if(screenGate!=ScreenGate.OPEN)return
        if(!Access.routeAllowed(state.operator,route,clock(),BuildConfig.IS_GATEWAY,gateway.bound()))return
        if(route in setOf(Route.PAYMENT,Route.MEMBER)&&id==null)return
        if(state.busy){
            // Preserve single-owner repository reads and do not interrupt a
            // financial command. The last requested route opens after the
            // current quiet refresh and only after its auth result is known.
            if(quietRefreshInFlight&&!state.draftDirty){queuedNavigation=route to id;operationLabel="Loading records"}
            return
        }
        clearRawDisclosure()
        if(state.draftDirty){afterDiscard={navigate(route,id)};state=state.copy(discardRequested=true);return}
        work(kind=UiOperation.INITIAL_READ){
            val old=state.copy(busy=false,error=null)
            if(route!=state.route||id!=state.routeId)views.push(key(),withoutRaw(old).copy(gateway=null))
            val remembered=views.remembered(key(route,id))
            val fresh=remembered?.takeIf{views.isCurrent(it)&&reusable(it.value)}?.value
            clearPanels()
            state=(fresh?:remembered?.value?.let{rememberedContext(it)}?:UiState(operator=state.operator,route=route,routeId=id)).copy(operator=state.operator,
                busy=true,pending=state.pending,failure=DisplayFailure.NONE,sheet=null,sheetId=null,panelDepth=0,error=null,selectedMember=null,draft=emptyMap(),draftDirty=false,discardRequested=false)
            if(fresh==null)refreshNow() else refreshRememberedReceiverStatus()
        }
    }
    override fun back(){
        if(state.receiverRetirementPending){closeSheet();return}
        checkVisibleFreshness();if(state.busy||screenGate!=ScreenGate.OPEN)return
        if(state.sheet!=null){if(state.sheet!=Sheet.RAW)clearRawDisclosure();closeSheet();return}
        clearRawDisclosure()
        val previous=views.previous()
        if(previous==null){
            // Process restoration deliberately has no serialized back stack or record snapshots.
            val parent=when(state.route){Route.PAYMENT->Route.PAYMENTS;Route.MEMBER->Route.MEMBERS;else->Route.HOME}
            work{clearPanels();state=UiState(operator=state.operator,route=parent,busy=true,pending=state.pending);refreshNow()}
            return
        }
        if(!Access.routeAllowed(state.operator,previous.value.route,clock(),BuildConfig.IS_GATEWAY,gateway.bound())){clearViews();navigate(Route.HOME);return}
        work{
            views.remember(key(),withoutRaw(state.copy(busy=false)).copy(gateway=null))
            val fresh=views.isCurrent(previous)&&reusable(previous.value)
            val restoredSheet=previous.value.sheet.takeIf{it!=Sheet.RAW&&panelAllowed(it)}
            val restoredId=previous.value.sheetId
            state=(if(fresh)previous.value else rememberedContext(previous.value)).copy(
                operator=state.operator,busy=true,error=null,pending=state.pending,failure=DisplayFailure.NONE,
                sheet=null,sheetId=null,panelDepth=0,raw=null,staff=null,audit=null,history=null,
                selectedStaff=null,selectedMember=null,draft=emptyMap(),draftDirty=false,discardRequested=false)
            clearPanels()
            if(!fresh)refreshNow() else if(restoredSheet==null)refreshRememberedReceiverStatus()
            if(restoredSheet!=null){
                // Evidence is re-read, never redisplayed from a remembered privileged panel.
                state=state.copy(sheet=restoredSheet,sheetId=restoredId,panelDepth=0)
                refreshPanelNow()
            }
        }
    }
    override fun openUnallocated(){
        if(state.busy||!Access.routeAllowed(state.operator,Route.PAYMENTS,clock(),BuildConfig.IS_GATEWAY,gateway.bound()))return
        work(kind=UiOperation.INITIAL_READ){
            clearRawDisclosure()
            views.push(key(),withoutRaw(state.copy(busy=false,error=null)).copy(gateway=null))
            state=UiState(operator=state.operator,route=Route.PAYMENTS,busy=true,filter="unallocated",pending=state.pending)
            refreshNow()
        }
    }
    override fun search(value:String){
        if(state.busy||screenGate!=ScreenGate.OPEN)return
        val bounded=value.filter{!it.isISOControl()}.take(80)
        val query=if(bounded.lastOrNull()?.isHighSurrogate()==true)bounded.dropLast(1)else bounded
        if(state.route==Route.SMS&&state.filter=="queued")state=state.copy(queuedSearch=query)
        else if(state.route==Route.SMS){if(state.smsListSearch!=query)smsSearchRevision++;state=state.copy(smsListSearch=query,queuedObservations=if(state.filter=="all")null else state.queuedObservations)}
        else{state=state.copy(search=query);checkpointNavigation(debounce=true)}
    }
    override fun searchSubmit(){
        if(state.route==Route.SMS&&state.filter!="queued"){
            if(!state.busy&&screenGate==ScreenGate.OPEN){state=state.copy(listIndex=0,listOffset=0);requestSmsScan(SmsScanRequest(search=state.smsListSearch.isNotBlank()))
                if(state.filter=="all"){queueRefreshJob?.cancel();queueRefreshJob=viewModelScope.launch{refreshQueuedNow()}}}
            return
        }
        work(kind=UiOperation.REFRESH){state=state.copy(listIndex=0,listOffset=0);if(state.sheet==null)refreshNow()else refreshPanelNow()}
    }
    override fun setFilter(value:String){
        if(state.busy||value !in NavigationCheckpoint.filters(state.route))return
        val clearSearch=state.route==Route.SMS&&(state.filter=="queued"||value=="queued")
        clearRawDisclosure();state=state.copy(filter=value,search=if(clearSearch)""else state.search,queuedSearch="",sheet=null,listIndex=0,listOffset=0)
        if(state.route==Route.SMS&&value!="queued")work{refreshNow()} else searchSubmit()
    }
    override fun refresh(){
        val localQuery=state.queuedSearch.takeIf{state.route==Route.SMS&&state.filter=="queued"}
        val remoteQuery=state.smsListSearch.takeIf{state.route==Route.SMS&&state.filter!="queued"}
        clearRawDisclosure()
        if(localQuery!=null)state=state.copy(queuedSearch=localQuery)
        if(remoteQuery!=null)state=state.copy(smsListSearch=remoteQuery)
        checkVisibleFreshness()
        if(state.receiverRetirementPending){refreshSession();return}
        if(screenGate!=ScreenGate.OPEN){refreshSession();return}
        if(state.readbackRequired&&state.route==Route.SETTINGS){refreshSession();return}
        work(kind=UiOperation.REFRESH){
            if(state.readbackRequired){refreshNow();if(state.sheet!=null)refreshPanelNow()}
            else if(state.sheet!=null)refreshPanelNow() else refreshNow()
        }
    }
    private suspend fun refreshPanelNow(){
        if(!panelAllowed(state.sheet))throw ApiFailure("access_denied",403)
        when(state.sheet){
            Sheet.ALLOCATE->refreshAllocationMembers(state.allocationQuery)
            Sheet.STAFF->{val v=io{repo().staff(queryFor(ListingTarget.STAFF))};state=state.copy(staff=v,panelSavedAt=clock())}
            Sheet.AUDIT->{val v=io{repo().audit(queryFor(ListingTarget.AUDIT))};state=state.copy(audit=v,panelSavedAt=clock())}
            Sheet.GATEWAY,Sheet.REPLACE_DEVICE->{state=state.copy(gateway=null,panelSavedAt=null);refreshReceiverPanel()}
            Sheet.RAW->clearRawDisclosure(preserveSmsSearch=state.route==Route.SMS) // A refresh is never an audited disclosure.
            Sheet.HISTORY->{
                val id=state.sheetId?:state.payment?.id?:throw ApiFailure("record_unavailable")
                val value=io{repo().paymentHistory(id,queryFor(ListingTarget.HISTORY))}
                state=state.copy(history=value,historyPaymentId=id,historyOffline=repo().lastReadFromCache,historySavedAt=repo().lastReadSavedAt)
            }
            Sheet.STAFF_EDIT,Sheet.REMOVE_STAFF->{
                // A refreshed version must never be attached to an old editing draft.
                // Reopen the account after refresh; the non-secret draft is retained for comparison.
                if(sessionChecking){
                    state=state.copy(selectedStaff=null,staff=null,panelSavedAt=null)
                    if(state.sheetId!=null)state=state.copy(error="Reopen this staff account from the refreshed list before saving. Your draft has not been submitted.")
                }
            }
            Sheet.MEMBER_DETAILS->refreshNow()
            else->Unit // Read retry must never submit a form or change a passcode.
        }
    }
    private data class RestoredPage<T>(val page:Page<T>,val offline:Boolean,val savedAt:Long?,val decision:ListRestoreDecision)
    /** Read-only reconstruction. Keep pages local until all selected pages pass integrity checks.
     * No operation/reconcile API is called here; command evidence stays owned by the repository.
     */
    private suspend fun <T> restorePages(first:Page<T>, id:(T)->String, cacheable:Boolean=true,
        firstOffline:Boolean=repo().lastReadFromCache, firstSavedAt:Long?=repo().lastReadSavedAt,
        read:(String)->Page<T>):RestoredPage<T>{
        val owner=state.operator?:throw ContractFailure("session_unavailable")
        val route=state.route;val routeId=state.routeId
        val targetIndex=state.listIndex;val targetOffset=state.listOffset
        fun checkScope(){
            val current=repo().current()
            checkContract(current?.id==owner.id&&current.role==owner.role&&current.capabilities==owner.capabilities&&
                state.operator?.id==owner.id&&state.route==route&&state.routeId==routeId,"session_changed")
            checkContract(clock()<owner.expiresAt&&clock()<current!!.expiresAt,"session_unavailable")
            if(!Access.routeAllowed(owner,route,clock(),BuildConfig.IS_GATEWAY,gateway.bound()))throw ApiFailure("access_denied",403)
        }
        var page=first;var offline=firstOffline;var saved=firstSavedAt;var pages=1
        val requestedCursors=mutableSetOf<String>()
        while(true){
            checkScope()
            val decision=PagedRestoration.decide(route,targetIndex,targetOffset,page.items.size,page.nextCursor,
                pages,offline,SnapshotFreshness.reusable(saved,clock()))
            if(!decision.fetchNext)return RestoredPage(page,offline,saved,decision)
            val cursor=page.nextCursor?:throw ContractFailure("invalid_page")
            checkContract(requestedCursors.add(cursor),"invalid_page")
            val next=io{read(cursor)}
            checkScope() // Expiry or owner changes during IO cannot publish a restored screen.
            checkContract(next.nextCursor==null||next.nextCursor !in requestedCursors,"invalid_page")
            val merged=PageIntegrity.append(page,next,id)
            // Validate the response before checking the memory budget; never ignore a conflict.
            if(merged.items.size>PagedRestoration.MAX_ITEMS){
                val limited=PagedRestoration.decide(route,targetIndex,targetOffset,page.items.size,page.nextCursor,
                    PagedRestoration.MAX_PAGES,offline,SnapshotFreshness.reusable(saved,clock()))
                return RestoredPage(page,offline,saved,limited)
            }
            page=merged;pages++
            offline=offline||(cacheable&&repo().lastReadFromCache)
            saved=SnapshotFreshness.oldest(clock(),saved,if(cacheable)repo().lastReadSavedAt else clock())
        }
    }
    private suspend fun refreshRememberedReceiverStatus() {
        if (state.route == Route.HOME) refreshHomeGatewayStatus()
        if (state.route == Route.SETTINGS) {
            refreshReceiverPanel()
            receiverStatus.refreshHealth()
        }
    }

    private fun refreshHomeGatewayStatus() = receiverStatus.refreshHome { state=state.copy(gateway=it) }

    private suspend fun refreshReceiverPanel(ticket: NativeReceiverStatus.Request? = receiverStatus.request()) {
        receiverStatus.read(ticket) { state=state.copy(gateway=it,panelSavedAt=clock()) }
    }

    private suspend fun refreshNow(){
        when(state.route){
            Route.HOME->{val h=io{repo().home()};val cached=repo().lastReadFromCache;val saved=repo().lastReadSavedAt
                state=state.copy(home=h,gateway=null,offline=cached,savedAt=saved,readbackRequired=state.readbackRequired&&cached)
                if(state.sheet==null)refreshHomeGatewayStatus()}
            Route.PAYMENTS->{val v=io{repo().payments(queryFor(ListingTarget.PAYMENTS))}
                val r=restorePages(v,{it.id}){cursor->repo().payments(queryFor(ListingTarget.PAYMENTS),cursor)}
                state=state.copy(payments=r.page,offline=r.offline,savedAt=r.savedAt,readbackRequired=state.readbackRequired&&r.offline,
                    listIndex=r.decision.index,listOffset=r.decision.offset,listRestoration=r.decision.stop)}
            Route.MEMBERS->{
                // This screen displays the matching list's own total, not the
                // independent Home aggregate. Its freshness is likewise owned
                // by the member pages that are actually displayed.
                val v=io{repo().members(queryFor(ListingTarget.MEMBERS))}
                val r=restorePages(v,{it.id}){cursor->repo().members(queryFor(ListingTarget.MEMBERS),cursor)}
                state=state.copy(home=null,members=r.page,offline=r.offline,savedAt=r.savedAt,readbackRequired=state.readbackRequired&&r.offline,
                    listIndex=r.decision.index,listOffset=r.decision.offset,listRestoration=r.decision.stop)}
            Route.SMS->{
                if(!hasAccess(Capability.SMS))throw ApiFailure("access_denied",403)
                if(state.filter=="queued"){
                    refreshQueuedNow()
                    return
                }
                val paired=io{gateway.bound()}
                var unavailable=false;var disconnected=false
                fun unavailableRead(e:ApiFailure):Boolean=e.status==0||e.status in setOf(404,408,425,429)||e.status>=500
                val canonical=if(paired)try{val v=io{repo().sms(queryFor(ListingTarget.SMS),limit=5)}.let{page->page.copy(items=page.items.map{it.copy(sender="",preview="")})}
                    restorePages(v,{it.id},cacheable=false,firstOffline=false,firstSavedAt=clock()){cursor->repo().sms(queryFor(ListingTarget.SMS),cursor=cursor,limit=5).let{page->page.copy(items=page.items.map{it.copy(sender="",preview="")})}}}
                    catch(e:ApiFailure){if(!unavailableRead(e))throw e;unavailable=true;disconnected=disconnected||e.status==0;null}else null
                // Revoking Android SMS access also revokes the corresponding
                // server consent. A restored SMS route must not query that
                // stream while permission is absent: the expected 403 would
                // otherwise strand the session-refresh gate and prevent the
                // user from reaching Settings to grant permission again.
                val observed=if(state.filter=="all"&&!smsAccessGranted){unavailable=true;null}
                    else if(state.filter=="all")try{io{repo().observationPage(queryFor(ListingTarget.SMS).copy(filter="all"),limit=5)}}
                    catch(e:ApiFailure){
                        // Permission can be restored before asynchronous consent
                        // reconciliation finishes.  Keep the stream unavailable
                        // on a scoped 403; session and role checks still apply.
                        if(e.status!=403&&!unavailableRead(e))throw e
                        unavailable=true;disconnected=disconnected||e.status==0;null
                    }
                    else if(canonical==null)Page(emptyList(),null,0,"filtered",java.time.Instant.ofEpochMilli(clock()).toString()) else null
                state=state.copy(messages=canonical?.page,observations=observed,observationProcessing=emptyMap(),observationRetryNotice=null,queuedObservations=null,queuedUnavailable=false,observationUnavailable=unavailable,
                    offline=disconnected||(canonical?.offline?:false),savedAt=canonical?.savedAt?:clock(),readbackRequired=false,
                    listIndex=canonical?.decision?.index?:0,listOffset=canonical?.decision?.offset?:0,listRestoration=canonical?.decision?.stop)
                if(state.filter=="all")refreshQueuedNow()
                requestObservationProcessing()
                requestSmsScan(SmsScanRequest(search=state.smsListSearch.isNotBlank()))
            }
            Route.PAYMENT->{val id=state.routeId?:state.payment?.id?:return;val v=io{repo().payment(id)};state=state.copy(payment=v,offline=repo().lastReadFromCache,savedAt=repo().lastReadSavedAt,readbackRequired=state.readbackRequired&&repo().lastReadFromCache)}
            Route.MEMBER->{val id=state.routeId?:state.member?.id?:return
                val member=io{repo().member(id)};val memberCached=repo().lastReadFromCache;val memberSaved=repo().lastReadSavedAt
                val payments=io{repo().payments(queryFor(ListingTarget.PAYMENTS),memberId=id)}
                val r=restorePages(payments,{it.id},firstOffline=memberCached||repo().lastReadFromCache,
                    firstSavedAt=SnapshotFreshness.oldest(clock(),memberSaved,repo().lastReadSavedAt)){cursor->repo().payments(queryFor(ListingTarget.PAYMENTS),cursor=cursor,memberId=id)}
                state=state.copy(member=member,ledger=null,memberTransactions=r.page,offline=r.offline,savedAt=r.savedAt,
                    readbackRequired=state.readbackRequired&&r.offline,
                    listIndex=r.decision.index,listOffset=r.decision.offset,listRestoration=r.decision.stop)}
            Route.SETTINGS->{
                val ticket=receiverStatus.request()
                state=state.copy(gateway=null)
                val staff=if(hasAccess(Capability.STAFF))io{repo().staff()}else null
                if(ticket==null){
                    state=state.copy(staff=staff,panelSavedAt=clock())
                }else receiverStatus.read(ticket) { receiving ->
                    state=state.copy(staff=staff,gateway=receiving,panelSavedAt=clock())
                }
                receiverStatus.refreshHealth()
            }
            else->Unit
        }
    }
    override fun more(){
        if(state.route==Route.SMS&&state.sheet==null){if(state.filter!="queued"&&state.smsListSearch.isBlank())requestSmsScan(SmsScanRequest(manual=true,target=SmsStream.CANONICAL));return}
        work(kind=UiOperation.LOAD_MORE){
        state=state.copy(listRestoration=null)
        when(state.sheet){
            Sheet.HISTORY->{state.history?.let{old->old.nextCursor?.let{c->
                val id=state.historyPaymentId?:throw ApiFailure("record_unavailable")
                val next=io{repo().paymentHistory(id,queryFor(ListingTarget.HISTORY),c)}
                state=state.copy(history=PageIntegrity.append(old,next){it.id},
                    historyOffline=state.historyOffline||repo().lastReadFromCache,
                    historySavedAt=SnapshotFreshness.oldest(clock(),state.historySavedAt,repo().lastReadSavedAt))
            }};return@work}
            Sheet.STAFF->{state.staff?.let{old->old.nextCursor?.let{c->val next=io{repo().staff(queryFor(ListingTarget.STAFF),c)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(staff=PageIntegrity.append(old,next){it.id})}};return@work}
            Sheet.AUDIT->{state.audit?.let{old->old.nextCursor?.let{c->val next=io{repo().audit(queryFor(ListingTarget.AUDIT),c)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(audit=PageIntegrity.append(old,next){it.id})}};return@work}
            Sheet.ALLOCATE->{state.members?.let{old->old.nextCursor?.let{c->val next=io{repo().members(state.allocationQuery,c)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(members=PageIntegrity.append(old,next){it.id},offline=state.offline||repo().lastReadFromCache,panelSavedAt=SnapshotFreshness.oldest(clock(),state.panelSavedAt,repo().lastReadSavedAt))}};return@work}
            else->Unit
        }
        when(state.route){
            Route.PAYMENTS->state.payments?.let{old->old.nextCursor?.let{c->val next=io{repo().payments(queryFor(ListingTarget.PAYMENTS),c)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(payments=PageIntegrity.append(old,next){it.id},offline=state.offline||repo().lastReadFromCache,savedAt=SnapshotFreshness.oldest(clock(),state.savedAt,repo().lastReadSavedAt))}}
            Route.MEMBERS->state.members?.let{old->old.nextCursor?.let{c->val next=io{repo().members(queryFor(ListingTarget.MEMBERS),c)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(members=PageIntegrity.append(old,next){it.id},offline=state.offline||repo().lastReadFromCache,savedAt=SnapshotFreshness.oldest(clock(),state.savedAt,repo().lastReadSavedAt))}}
            Route.MEMBER->state.memberTransactions?.let{old->old.nextCursor?.let{c->val next=io{repo().payments(queryFor(ListingTarget.PAYMENTS),cursor=c,memberId=state.member!!.id)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(memberTransactions=PageIntegrity.append(old,next){it.id},offline=state.offline||repo().lastReadFromCache,savedAt=SnapshotFreshness.oldest(clock(),state.savedAt,repo().lastReadSavedAt))}}
            Route.SMS->Unit
            else->Unit
        }
        }
    }
    override fun moreObservations(){
        if(state.route==Route.SMS&&state.sheet==null&&state.filter!="queued"&&state.smsListSearch.isBlank())requestSmsScan(SmsScanRequest(manual=true,target=SmsStream.OBSERVATION))
    }
    override fun retryObservation(){
        val source=state.rawSource as? SmsSourceRef.Observation?:return
        if(state.sheet!=Sheet.RAW||state.observationProcessing[source]?.canRetry!=true||
            !BuildConfig.IS_GATEWAY||state.operator?.role!=Role.ADMIN||!smsAccessGranted||!hasAccess(Capability.GATEWAY))return
        val requestId=observationRetryRequests.getOrPut(source.id){java.util.UUID.randomUUID().toString()}
        work{
            state=state.copy(observationRetryNotice=null)
            val result=io{repo().retryObservation(source,requestId)}
            observationRetryRequests.remove(source.id)
            val status=if(result=="scheduled")ObservationProcessing("retrying",false) else ObservationProcessing("unknown",false)
            state=state.copy(observationProcessing=state.observationProcessing+(source to status),
                observationRetryNotice=if(result=="scheduled")"Retry scheduled." else "This SMS cannot be retried.")
            requestObservationProcessing()
        }
    }
    override fun openSms(source:SmsSourceRef)=openSheetWithSource(Sheet.RAW,source.id,source)
    override fun openSheet(sheet:Sheet,id:String?)=openSheetWithSource(sheet,id,if(sheet==Sheet.RAW&&id!=null)SmsSourceRef.Canonical(id)else null)
    private fun openSheetWithSource(sheet:Sheet,id:String?,source:SmsSourceRef?){
        if(state.busy||!panelAllowed(sheet))return
        if(sheet==Sheet.FILTERS){
            val target=actualListingTarget()?:return
            filterDraftReset=null
            filterOrigin=FilterOrigin(state.sheet,state.sheetId,target,listingContext())
            state=state.copy(sheet=Sheet.FILTERS);return
        }
        filterOrigin=null
        if(sheet==Sheet.RAW&&(id==null||source==null||source.id!=id))return
        clearRawDisclosure(preserveSmsSearch=sheet==Sheet.RAW&&state.route==Route.SMS)
        // Re-opening a panel (e.g. returning from Android permissions) refreshes it,
        // without replacing its draft or creating a second back-stack entry.
        if(state.sheet==sheet&&state.sheetId==id&&state.rawSource==source){refresh();return}
        if(state.draftDirty&&sheet!=Sheet.REMOVE_STAFF){
            afterDiscard={openSheetWithSource(sheet,id,source)};state=state.copy(discardRequested=true);return
        }
        work(kind=UiOperation.INITIAL_READ){
            // The prototype replaces the current sheet; Close returns to the route.
            clearPanels()
            state=state.copy(sheet=sheet,sheetId=if(sheet==Sheet.HISTORY)id?:state.payment?.id else id,rawSource=source,observationRetryNotice=null,
                panelDepth=0,error=null,selectedMember=null,raw=null,panelSavedAt=state.panelSavedAt,
                history=null,historyPaymentId=null,historyOffline=false,historySavedAt=null,
                allocationQuery="",draft=emptyMap(),draftDirty=false,discardRequested=false,onboarding=SmartOnboardingState())
            if(sheet==Sheet.STAFF_EDIT){
                val selected=state.staff?.items?.find{it.id==id}
                state=state.copy(selectedStaff=null)
                if(id!=null&&selected==null)throw ApiFailure("record_unavailable")
                initialDraft=mapOf("name" to selected?.name.orEmpty(),"phone" to selected?.phone.orEmpty(),
                    "enroll" to (selected?.capabilities?.contains(Capability.ENROLL.key)?:false).toString(),
                    "allocate" to (selected?.capabilities?.contains(Capability.ALLOCATE.key)?:false).toString())
                state=state.copy(selectedStaff=selected,draft=initialDraft)
            }
            if(sheet==Sheet.RAW)loadRawForCurrentPanel("Review original SMS from the selected contribution or receipt")
            else refreshPanelNow()
        }
    }
    override fun closeSheet(){
        if(state.sheet==Sheet.FILTERS&&filterOrigin!=null&&!state.busy){
            val origin=filterOrigin!!;filterOrigin=null;filterDraftReset=null
            state=state.copy(sheet=origin.sheet,sheetId=origin.id);return
        }
        if(state.receiverRetirementPending){if(!state.busy)state=state.copy(sheet=null);return}
        checkVisibleFreshness();if(screenGate!=ScreenGate.OPEN)return;if(!state.busy){if(state.draftDirty)state=state.copy(discardRequested=true) else discardDraft()}
    }
    override fun revealRaw(reason:String){
        checkVisibleFreshness()
        if(state.busy||screenGate!=ScreenGate.OPEN||state.sheet!=Sheet.RAW||!hasAccess(Capability.SMS))return
        clearRawDisclosure(preserveSmsSearch=state.route==Route.SMS)
        val normalized=RawDisclosureInput.reason(reason)
        if(normalized==null){state=state.copy(rawDisclosure=RawDisclosureState.FAILURE,rawError="Original SMS unavailable.");return}
        work(preservePresentation=true){loadRawForCurrentPanel(normalized)}
    }
    /** Opening the original raw panel is the explicit audited disclosure action.
     * Keep server authorization, exposure epochs and background erasure intact. */
    private suspend fun loadRawForCurrentPanel(reason:String){
        val id=state.sheetId?:return
        val source=state.rawSource?:return
        if(source.id!=id)throw ContractFailure("invalid_observation_source")
        val normalized=RawDisclosureInput.reason(reason)?:throw ContractFailure("invalid_reason")
        val exposure=rawExposureEpoch;val owner=state.operator?.id;val started=generation
        fun current()=exposure==rawExposureEpoch&&started==generation&&foreground&&screenGate==ScreenGate.OPEN&&
            state.operator?.id==owner&&state.sheet==Sheet.RAW&&state.sheetId==id&&state.rawSource==source&&hasAccess(Capability.SMS)
        state=state.copy(rawDisclosure=RawDisclosureState.LOADING)
        try{
            val (value,hints)=io{when(source){
                is SmsSourceRef.Canonical->repo().raw(source.id,normalized) to null
                is SmsSourceRef.Observation->repo().revealObservation(source,normalized).let{
                    RawSms(it.source.id,it.sender,it.retainedAt,it.rawBody,null,null) to it.displayHints
                }
            }}
            if(current())state=state.copy(raw=value,observationHints=hints,rawDisclosure=RawDisclosureState.REVEALED,rawError=null,panelSavedAt=clock())
        }catch(error:CancellationException){throw error}
        catch(error:Exception){
            if(!current())return
            if(error is ApiFailure&&error.status==401||error is ContractFailure&&error.code in setOf("session_unavailable","session_changed"))throw error
            state=state.copy(raw=null,rawDisclosure=RawDisclosureState.FAILURE,rawError=when{
                error is ApiFailure&&error.uncertain->"Original SMS access is unconfirmed. Close and check before trying again."
                error is ApiFailure&&error.status==403->"Original SMS access requires current permission and recent sign-in."
                else->"Original SMS unavailable."
            })
        }
    }
    override fun selectMember(member:Member){
        checkVisibleFreshness()
        if(!state.busy&&state.sheet==Sheet.ALLOCATE&&allows(Capability.ALLOCATE))state=collectionPosting.select(state,member)
    }
    override fun allocationSearch(q:String){
        if(state.sheet==Sheet.ALLOCATE)work{refreshAllocationMembers(q)}
    }
    private suspend fun refreshAllocationMembers(query:String){
        val result=io{collectionPosting.candidates(query)}
        state=collectionPosting.showCandidates(state,query,result,sessionChecking)
    }
    /** Drop records and consumed form state before any post-command read can fail.
     * The durable journal is owned by the repository and is never edited here. */
    private fun invalidateCommandViews(notice:String?=null){
        clearDownload(false);views.invalidateRecords();clearPanels();pendingExport=null
        val old=state
        state=UiState(operator=old.operator,route=old.route,routeId=old.routeId,
            search=old.search,filter=old.filter,listIndex=old.listIndex,listOffset=old.listOffset,
            busy=true,pending=old.pending,commandNotice=notice)
    }
    /** A transport/cleanup failure may follow a committed server-side operation.
     * Invalidate presentation without interpreting uncertainty as rejection. */
    private suspend fun command(action:()->JSONObject):JSONObject {
        state=state.copy(commandNotice=null)
        return when(val submission=io{collectionPosting.submit(action)}){
            is NativeCollectionPosting.Submission.Committed->{
                invalidateCommandViews(NativeCollectionPosting.Outcome.COMMITTED.notice)
                submission.receipt
            }
            is NativeCollectionPosting.Submission.Failed->{
                if(submission.invalidate)invalidateCommandViews(submission.outcome?.notice)
                throw submission.error
            }
        }
    }
    private suspend fun requireNoUnresolvedCommand(){
        if(state.pending||io{repository?.pending()!=null})throw ApiFailure("pending_operation_requires_resolution",409)
        if(state.readbackRequired||!state.presentation(screenGate,clock()).showRecords)throw ApiFailure("fresh_records_required",409)
    }
    override fun allocate(note:String)=work{
        requireNoUnresolvedCommand()
        if(!allows(Capability.ALLOCATE)||state.offline)throw ApiFailure("access_denied",403)
        val selection=collectionPosting.allocation(state)
        command{collectionPosting.post(selection,note)}
        val refreshed=io{collectionPosting.readPosted(selection)}
        state=state.copy(sheet=null,sheetId=null,panelDepth=0,selectedMember=null,payment=refreshed.payment,home=null,
            draft=emptyMap(),draftDirty=false,offline=refreshed.cached,savedAt=refreshed.savedAt)
    }
    override fun enroll(name:String,phone:String)=work{
        requireNoUnresolvedCommand()
        if(!allows(Capability.ENROLL)||state.offline)throw ApiFailure("access_denied",403)
        checkContract(Presentation.validName(name),"invalid_name")
        val result=command{repo().enroll(name,phone)}
        // The command has already committed. Navigate only to the acknowledged
        // member ID carried by its verified outcome, and re-read the ledger; never retry the
        // enrollment or infer an ID from the entered phone number.
        val memberId=runCatching{
            checkContract(result.getString("groupId")==repo().collectionId,"scope_changed")
            Values.id(result.getString("createdMemberId"))
        }.getOrNull()
        if(memberId==null){
            state=state.copy(error="Member saved. Refresh the member list to open the record.",failure=DisplayFailure.UNAVAILABLE)
            return@work
        }
        val previous=state.copy(busy=false,error=null)
        views.push(key(),withoutRaw(previous).copy(gateway=null))
        state=UiState(operator=previous.operator,route=Route.MEMBER,routeId=memberId,busy=true,
            pending=previous.pending,commandNotice=previous.commandNotice)
        refreshNow()
    }
    override fun onboardingOptions(){
        if(state.busy||!allows(Capability.ENROLL))return
        pendingMemberDocument=null
        state=state.copy(onboarding=SmartOnboardingState(),draft=emptyMap(),draftDirty=false,error=null)
    }
    override fun onboardingManual(){
        if(state.busy||!allows(Capability.ENROLL)||importReviewStarted())return
        pendingMemberDocument=null
        state=state.copy(onboarding=SmartOnboardingState(step=SmartOnboardingStep.MEMBER),draft=emptyMap(),draftDirty=false,error=null)
    }
    override fun onboardingSearchQuery(value:String){
        if(value.length<=80&&!state.busy)state=state.copy(onboarding=state.onboarding.copy(query=value))
    }
    override fun onboardingSuggestions(query:String,cursor:String?){
        if(importReviewStarted())return
        if(cursor==null&&state.onboarding.step!=SmartOnboardingStep.SUGGESTIONS){
            if(state.busy||state.offline||!allows(Capability.ENROLL))return
            pendingMemberDocument=null
            state=state.copy(onboarding=SmartOnboardingState(step=SmartOnboardingStep.SUGGESTIONS),draft=emptyMap(),draftDirty=false,error=null)
        }
        work{
        if(!allows(Capability.ENROLL)||state.offline)throw ApiFailure("access_denied",403)
        val q=query.trim();checkContract(q.length<=80,"invalid_query")
        val result=io{repo().onboardingSuggestions(q,cursor)};val rows=result.getJSONArray("items")
        val parsed=(0 until rows.length()).map{i->val row=rows.getJSONObject(i)
            SmartCandidate(row.getString("candidateId"),row.getString("momoName"),row.getString("last3"),
                if(row.isNull("latestSeenAt"))null else row.getString("latestSeenAt"),row.getInt("sourceCount"))}
        val previous=if(cursor==null)emptyList() else state.onboarding.suggestions
        checkContract((previous+parsed).map{it.candidateId}.toSet().size==previous.size+parsed.size,"invalid_page")
        state=state.copy(onboarding=state.onboarding.copy(step=SmartOnboardingStep.SUGGESTIONS,query=q,
            suggestions=previous+parsed,nextCursor=if(result.isNull("nextCursor"))null else result.getString("nextCursor"),
            suggestionsLoaded=true),error=null)
        }
    }
    override fun onboardingChoose(candidateId:String){
        if(state.busy||!allows(Capability.ENROLL))return
        val candidate=state.onboarding.suggestions.singleOrNull{it.candidateId==candidateId}?:return
        state=state.copy(onboarding=state.onboarding.copy(step=SmartOnboardingStep.MEMBER,candidate=candidate,
            verifiedOwnership=false,acceptedTerms=false,consentRecorded=false),draft=mapOf("name" to candidate.momoName),draftDirty=false,error=null)
    }
    override fun onboardingImport(){
        if(state.busy||!allows(Capability.ENROLL))return
        state=state.copy(onboarding=state.onboarding.copy(step=SmartOnboardingStep.IMPORT,editingRow=null,photoPreviewPending=false),draft=emptyMap(),draftDirty=false,error=null)
    }
    override fun onboardingPhoto(){
        if(state.busy||!allows(Capability.ENROLL)||state.sheet!=Sheet.ENROLL||importReviewStarted())return
        pendingMemberDocument=null
        state=state.copy(onboarding=SmartOnboardingState(step=SmartOnboardingStep.IMPORT,photoCaptureFlow=true),
            draft=emptyMap(),draftDirty=false,error=null)
    }
    override fun onboardingFileSelected(uri:String?,mimeType:String?){
        val owner=state.operator?.id?:return
        if(state.sheet!=Sheet.ENROLL||state.onboarding.step!=SmartOnboardingStep.IMPORT||
            !hasAccess(Capability.ENROLL)||uri==null||!uri.startsWith("content://"))return
        pendingMemberDocument=PendingMemberDocument(owner,uri,mimeType)
        drainMemberDocument()
    }
    override fun onboardingPhotoSelected(uri:String?){
        val owner=state.operator?.id?:return
        if(state.sheet!=Sheet.ENROLL||state.onboarding.step!=SmartOnboardingStep.IMPORT||
            !state.onboarding.photoCaptureFlow||uri==null||!uri.startsWith("content://"))return
        pendingMemberDocument=PendingMemberDocument(owner,uri,"image/jpeg",capturedPhoto=true)
        drainMemberDocument()
    }
    private fun importReviewStarted():Boolean=state.onboarding.step==SmartOnboardingStep.IMPORT&&
        (state.onboarding.sourceKind!=null||state.onboarding.rows.isNotEmpty())
    override fun onboardingPhotoCancelled(){
        if(state.sheet!=Sheet.ENROLL||!state.onboarding.photoCaptureFlow)return
        pendingMemberDocument=null
        state=state.copy(onboarding=SmartOnboardingState(),error=null)
    }
    /** Consume this capture's consent only once, after foreground session and document checks. */
    fun takeOnboardingPhotoPreview(uri:String):Boolean{
        checkVisibleFreshness()
        val o=state.onboarding
        if(state.busy||state.offline||state.pending||screenGate!=ScreenGate.OPEN||!hasAccess(Capability.ENROLL)||
            state.sheet!=Sheet.ENROLL||o.step!=SmartOnboardingStep.IMPORT||!o.photoCaptureFlow||
            !o.photoPreviewPending||!o.ocrConsent||o.documentUri!=uri)return false
        state=state.copy(onboarding=o.copy(photoPreviewPending=false))
        return true
    }
    override fun onboardingFileError(failure:MemberImportFailure){
        if(state.sheet!=Sheet.ENROLL||state.onboarding.step!=SmartOnboardingStep.IMPORT||
            (!state.onboarding.photoCaptureFlow&&!hasAccess(Capability.ENROLL)))return
        val message=when(failure){
            MemberImportFailure.CAMERA_UNAVAILABLE->"Camera unavailable. Choose a photo or file instead."
            MemberImportFailure.TOO_LARGE->"This photo is too large. Choose a smaller photo."
            MemberImportFailure.UNREADABLE->"Unable to read the selected file."
        }
        if(state.onboarding.photoCaptureFlow){
            pendingMemberDocument=null
            state=state.copy(onboarding=SmartOnboardingState(),error=message,failure=DisplayFailure.UNAVAILABLE)
        }else state=state.copy(error=message,failure=DisplayFailure.UNAVAILABLE)
    }
    override fun onboardingPreview(mimeType:String,bytes:ByteArray){
        if(state.busy||screenGate!=ScreenGate.OPEN||!allows(Capability.ENROLL)){bytes.fill(0);return}
        val consent=state.onboarding.ocrConsent
        work{
            try{
                val data=io{repo().onboardingPreview(mimeType,bytes,consent)};val rows=data.getJSONArray("rows")
                val items=(0 until rows.length()).map{i->val row=rows.getJSONObject(i)
                    SmartImportRow(row.getInt("row"),row.getString("momoName"),row.getString("momoNumber"),
                        row.getString("status"),if(row.isNull("issue"))null else row.getString("issue"),row.getBoolean("selected"))}
                checkContract(items.map{it.row}.toSet().size==items.size,"invalid_api_response")
                state=state.copy(onboarding=state.onboarding.copy(sourceKind=data.getString("sourceKind"),rows=items,
                    documentUri=null,documentMimeType=null,documentSelected=false),error=null)
            }finally{bytes.fill(0)}
        }
    }
    override fun onboardingEditRow(row:Int){
        if(state.busy||!allows(Capability.ENROLL))return
        val selected=state.onboarding.rows.singleOrNull{it.row==row}?:return
        state=state.copy(onboarding=SmartOnboardingPresentation.editRow(state.onboarding,row),
            draft=mapOf("name" to selected.name,"phone" to selected.phone.orEmpty()),draftDirty=false,error=null)
    }
    override fun onboardingConsent(field:String,value:Boolean){
        if(state.busy||!allows(Capability.ENROLL))return
        val o=state.onboarding;val updated=when(field){"ownership"->o.copy(verifiedOwnership=value);"terms"->o.copy(acceptedTerms=value);
            "consent"->o.copy(consentRecorded=value);"ocr"->o.copy(ocrConsent=value);else->return}
        state=state.copy(onboarding=updated)
    }
    override fun onboardingSaveRow(name:String,phone:String){
        if(state.busy||!allows(Capability.ENROLL))return
        if(!Presentation.validName(name))return
        val normalized=runCatching{Values.phone(phone)}.getOrNull()?:return
        val o=state.onboarding;if(!o.verifiedOwnership||!o.acceptedTerms||!o.consentRecorded)return
        state=state.copy(onboarding=SmartOnboardingPresentation.saveRow(o,name.trim(),normalized),draft=emptyMap(),draftDirty=false,error=null)
    }
    private fun importRow(row:Int,name:String,phone:String,candidateId:String?=null)=JSONObject()
        .put("row",row).put("name",name.trim()).put("phone",Values.phone(phone))
        .put("verifiedOwnership",true).put("acceptedTerms",true).put("consentRecorded",true)
        .also{if(candidateId!=null)it.put("candidateId",candidateId)}
    private suspend fun submitOnboarding(rows:JSONArray){
        requireNoUnresolvedCommand()
        if(!allows(Capability.ENROLL)||state.offline)throw ApiFailure("access_denied",403)
        val result=command{repo().onboardingImport(rows)}.getJSONObject("importResult")
        val data=result.getJSONArray("results");val results=(0 until data.length()).map{i->val item=data.getJSONObject(i)
            SmartImportResult(item.getInt("row"),item.getString("status"),if(item.isNull("memberId"))null else item.getString("memberId"))}
        val created=result.getInt("created");refreshNow()
        state=state.copy(sheet=Sheet.ENROLL,onboarding=SmartOnboardingState(step=SmartOnboardingStep.RESULTS,
            results=results,created=created),draft=emptyMap(),draftDirty=false)
    }
    override fun onboardingSubmit(name:String,phone:String)=work{
        val o=state.onboarding;checkContract(Presentation.validName(name)&&o.verifiedOwnership&&o.acceptedTerms&&o.consentRecorded,"invalid_import")
        val normalized=Values.phone(phone);val candidate=o.candidate
        checkContract(candidate==null||normalized.endsWith(candidate.last3),"candidate_changed")
        submitOnboarding(JSONArray().put(importRow(1,name,normalized,candidate?.candidateId)))
    }
    override fun onboardingSubmitBatch()=work{
        val selected=state.onboarding.rows.filter{it.verified};checkContract(selected.isNotEmpty()&&selected.size<=500,"invalid_import")
        val rows=JSONArray();selected.forEach{rows.put(importRow(it.row,it.name,it.phone?:"",it.candidateId))};submitOnboarding(rows)
    }
    override fun changePin(current:String,next:String,confirm:String)=work{
        requireNoUnresolvedCommand()
        try{
            val updated=io{repo().changePin(current,next,confirm)}
            dismissPanel();state=state.copy(operator=updated,error=null,failure=DisplayFailure.NONE)
        }catch(e:ApiFailure){
            if(e.uncertain&&repository?.current()==null){
                clearViews();restoreRetryPending=true;lastRestoreAttemptAt=0L
                state=UiState(error="Passcode change not confirmed. Checking securely; do not repeat it.",busy=true,
                    failure=DisplayFailure.UNCERTAIN,passcodeChangePending=true)
            }
            throw e
        }
    }
    override fun saveStaff(name:String,phone:String,pin:String,enroll:Boolean,allocate:Boolean)=work{
        requireNoUnresolvedCommand()
        if(!allows(Capability.STAFF)||state.offline)throw ApiFailure("access_denied",403)
        checkContract(Presentation.validName(name),"invalid_name")
        val existing=state.selectedStaff
        if(state.sheetId!=null&&existing==null)throw ApiFailure("record_unavailable")
        val normalizedPhone=Values.phone(phone)
        val resolveBlankPhoneDenial=existing!=null&&pin.isBlank()&&normalizedPhone!=Values.phone(existing.phone)
        val body=JSONObject().put("action",if(existing==null)"create" else "edit").put("name",name.trim()).put("phone",normalizedPhone)
        if(existing!=null)body.put("id",existing.id).put("expectedVersion",existing.version)
        if(pin.isNotBlank())body.put("pin",Values.pin(pin))
        val caps=JSONArray().put(Capability.READ.key);if(enroll)caps.put(Capability.ENROLL.key);if(allocate)caps.put(Capability.ALLOCATE.key);body.put("capabilities",caps)
        command{repo().staffAction(body,resolveBlankPhoneDenial)};val staff=io{repo().staff()};state=state.copy(sheet=Sheet.STAFF,sheetId=null,panelDepth=0,staff=staff,panelSavedAt=clock(),selectedStaff=null,draft=emptyMap(),draftDirty=false)
    }
    override fun staffAction(action:String,pin:String?)=work{
        requireNoUnresolvedCommand()
        if(!allows(Capability.STAFF))throw ApiFailure("access_denied",403)
        val s=state.selectedStaff?:throw ApiFailure("staff_unavailable")
        val body=JSONObject().put("action",action).put("id",s.id).put("expectedVersion",s.version)
        if(pin!=null)body.put("pin",Values.pin(pin))
        command{repo().staffAction(body)};val staff=io{repo().staff()};state=state.copy(sheet=Sheet.STAFF,sheetId=null,panelDepth=0,staff=staff,panelSavedAt=clock(),selectedStaff=null,draft=emptyMap(),draftDirty=false)
    }
    override fun requestRemoveStaff(){if(state.selectedStaff!=null&&allows(Capability.STAFF))openSheet(Sheet.REMOVE_STAFF,state.selectedStaff?.id)}
    override fun setMemberActive(active:Boolean)=work{requireNoUnresolvedCommand();if(state.operator?.role!=Role.ADMIN||!allows(Capability.ENROLL)||state.offline)throw ApiFailure("access_denied",403);val m=state.member?:throw ApiFailure("member_unavailable");command{repo().setMemberActive(m,active)};val v=io{repo().member(m.id)};state=state.copy(sheet=null,sheetId=null,panelDepth=0,member=v,offline=repo().lastReadFromCache,savedAt=repo().lastReadSavedAt)}
    override fun pair(code:String)=work{
        val ticket=receiverStatus.request()?:throw ApiFailure("access_denied",403)
        if(!receiverStatus.control(ticket){gateway.pair(code)})return@work
        refreshReceiverPanel(ticket)
    }
    private fun coverReceiverRetirement(){
        val previous=state
        clearViews()
        state=UiState(operator=previous.operator,route=previous.route,routeId=previous.routeId,
            sheet=if(!previous.receiverRetirementPending||previous.sheet==Sheet.REPLACE_DEVICE)Sheet.REPLACE_DEVICE else null,
            busy=true,pending=previous.pending,receiverRetirementPending=true,
            error="Receiver replacement is unconfirmed. Check the original outcome; do not enter another code.")
    }
    private suspend fun acceptReceiverRetirement(ack:ReceiverRetirementAck){
        check(ack.retired&&ack.reauthenticationRequired)
        try{io{repo().clearOperator()}}
        finally{
            clearViews();needsSessionCheck=false;visibleExpired=false;resumeQueued=false
            state=UiState(busy=true,pending=state.pending,
                error="This receiving phone is retired. Sign in on the replacement phone.")
        }
    }
    /** Read-only recovery uses the original encrypted proof, not current operator authority. */
    private suspend fun recoverReceiverRetirement():Boolean{
        if(!BuildConfig.IS_GATEWAY)return false
        val pending=try{io{gateway.retirementPending()}}catch(e:CancellationException){throw e}catch(_:Exception){true}
        if(!pending&&!state.receiverRetirementPending)return false
        coverReceiverRetirement()
        val ack=try{io{gateway.recoverRetirement()}}catch(e:CancellationException){throw e}catch(_:Exception){null}
        if(ack!=null)acceptReceiverRetirement(ack)
        return true
    }
    override fun replaceReceiver(code:String){
        if(state.receiverRetirementPending){refreshSession();return}
        work{
            requireNoUnresolvedCommand()
            if(!allows(Capability.GATEWAY))throw ApiFailure("access_denied",403)
            try{acceptReceiverRetirement(io{gateway.replace(code)})}
            catch(e:CancellationException){throw e}
            catch(e:Exception){
                val pending=try{io{gateway.retirementPending()}}catch(cancel:CancellationException){throw cancel}catch(_:Exception){true}
                if(pending||e is ApiFailure&&e.code=="gateway_retirement_unconfirmed")coverReceiverRetirement() else throw e
            }
        }
    }
    override fun syncReceiver()=work{
        if(!allows(Capability.GATEWAY))throw ApiFailure("access_denied",403)
        val ticket=receiverStatus.request()?:throw ApiFailure("access_denied",403)
        if(!receiverStatus.control(ticket){gateway.sync()})return@work
        refreshReceiverPanel(ticket)
    }
    override fun setPaused(value:Boolean)=work{
        if(!allows(Capability.GATEWAY))throw ApiFailure("access_denied",403)
        // The administrator-facing sync setting is locked on. Recovery code
        // in the gateway may still stop capture when its authority is unsafe.
        if(value)throw ApiFailure("gateway_action_unavailable",409)
        val ticket=receiverStatus.request()?:throw ApiFailure("access_denied",403)
        var resumable=false
        if(!receiverStatus.read(ticket){resumable=GatewayHealth.describe(it).canResume})return@work
        if(!resumable)throw ApiFailure("gateway_action_unavailable",409)
        if(!receiverStatus.control(ticket){gateway.setPaused(value)})return@work
        refreshReceiverPanel(ticket)
    }
    override fun retry()=work{
        val outcome=io{collectionPosting.reconcile()}
        if(outcome==NativeCollectionPosting.Outcome.PENDING){
            state=state.copy(error=outcome.notice,failure=DisplayFailure.UNCERTAIN)
        }else{
            invalidateCommandViews(outcome.notice);refreshNow()
            // Retain the historical error text for rejection consumers; the independent
            // notice remains visible even when readback fails or a later action clears error.
            if(outcome==NativeCollectionPosting.Outcome.REJECTED)state=state.copy(error=outcome.notice,failure=DisplayFailure.REJECTED)
        }
    }
    fun export(write:(String)->Unit){
        val owner=state.operator?.id
        val member=state.member?.id
        if(owner==null||member==null){state=state.copy(error="Open the member before exporting.");return}
        // The document picker pauses the Activity. Remember only the explicit user's
        // destination callback, not statement data; revalidate before the authorized read.
        pendingExport=PendingExport(owner,member,clock(),write)
        checkVisibleFreshness()
        if(screenGate==ScreenGate.OPEN&&!state.busy)drainExport()
        else{resumeQueued=true;needsSessionCheck=true;drainResumeCheck()}
    }
    private fun message(code:String,uncertain:Boolean):String=when{
        code=="smart_import_preview_unconfirmed"->"Preview could not be confirmed. Try again to send the file again."
        code in setOf("smart_import_decoder_unavailable","smart_import_ocr_unavailable")->"This document format is not available yet. Choose a CSV file."
        code=="smart_import_consent_required"->"Confirm the document processing consent before continuing."
        code.startsWith("smart_import_")->"Unable to read this file. Check its format and try again."
        code=="fresh_auth_required"->"Check the previous action, then sign in again before adding staff."
        code=="passcode_change_unconfirmed"->"Passcode change not confirmed. Checking securely; do not repeat it."
        uncertain->"Outcome not confirmed. Check before retrying."
        code=="gateway_action_unavailable"->"Refresh the receiving-phone status and follow the displayed recovery steps."
        code=="fresh_records_required"->"These records have expired. Reconnect and refresh before continuing."
        code=="invalid_name"->"Use a name of 2–100 characters without control characters."
        code=="invalid_note"->"Use an identification note of 8–500 characters without control characters."
        code.startsWith("invalid_history")||code in setOf("invalid_page","invalid_api_response","invalid_member_payment_scope")->"Received inconsistent records. Refresh or contact support."
        code=="history_limit"->"This history is too large for the phone. Contact an administrator for a full extract."
        code=="record_unavailable"->"This record is unavailable. Go back or refresh."
        code=="invalid_credentials"->"Phone or passcode is incorrect."
        code=="invalid_current_pin"->"Current passcode is incorrect."
        code=="passcode_unchanged"->"Choose a different passcode."
        code=="session_already_active"->"Sign out before signing in with a different account."
        code=="session_revalidation_unavailable"->"Check your connection"
        code=="invalid_phone"->"Enter a valid phone number."
        code=="new_passcode_required"->"Enter a new passcode when changing the phone number."
        code=="invalid_passcode"->"Enter four digits."
        code=="passcodes_do_not_match"->"Passcodes do not match."
        code=="try_again_later"->"Too many attempts. Try again later."
        code in setOf("configuration_required","managed_setup_required")->"Unable to sign in. Contact admin."
        code in setOf("operation_recovery_unavailable","operation_recovery_denied")->"The original action could not be verified for this account and phone. Do not repeat it or clear app data; contact the administrator."
        code in setOf("invalid_recovery_response","invalid_recovery_proof","invalid_recovery_receipt")->"Recovery evidence is inconsistent. The action remains unresolved; contact the administrator."
        code in setOf("record_cache_unavailable","operation_store_unavailable")->"Local recovery storage is unavailable. Do not repeat the action or clear app data; contact the administrator."
        code=="pending_operation_requires_resolution"->"The previous action needs an authenticated outcome check. Sign in with the same operator on this phone and check it. Do not repeat the action."
        code=="operation_financially_changed"->"The original action committed, but its financial effect changed. Review the current ledger; do not repeat the original action."
        code=="recovery_check_in_progress"->"An outcome check is already running. Do not repeat the financial action."
        code=="recovery_retry_backoff"->"The next outcome check is not due yet. The original action remains unresolved."
        code in setOf("recovery_retry_exhausted","recovery_retry_stopped","recovery_clock_invalid")->"Outcome checks have stopped. Do not repeat the action or clear app data; contact the administrator."
        code=="recovery_authentication_required"->"Sign in again to check the original action. Do not submit it again."
        code in setOf("operation_identity_changed","operation_changed","operation_attempt_changed","conflicting_reconciliation","corrupt_operation")->"Recovery evidence changed or conflicts with the original action. Do not repeat the action or clear app data; contact the administrator."
        code=="operation_still_pending"->"A previous action is still pending. Check its authoritative result before doing anything else."
        code=="operation_rejected"->"The operation was rejected by the authoritative service. Refresh the records before continuing."
        code.contains("changed")||code=="cursor_stale"->"Records changed. Refresh before continuing."
        code=="access_denied"->"Access unavailable."
        code=="connection_unavailable"->"Offline. Reconnect and refresh."
        else->"Unable to complete. Refresh and try again."
    }
}
