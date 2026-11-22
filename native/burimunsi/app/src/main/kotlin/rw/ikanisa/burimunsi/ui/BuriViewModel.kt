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
import rw.ikanisa.burimunsi.core.export.ExportFormat
import rw.ikanisa.burimunsi.core.export.ExportTable
import java.io.File

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
    private val downloads by lazy {
        NativeListingDownloads(
            viewModelScope, ::repo, gateway, clock, { foreground }, io,
            runExport = { action -> work(kind = UiOperation.EXPORT, action = action) },
            setOperationLabel = { operationLabel = it },
            onSessionInvalid = {
                needsSessionCheck = true
                resumeQueued = true
            },
        )
    }
    override val exportFeedback: UiExportFeedback? get() = downloads.feedback
    val downloadRequest: DownloadRequest? get() = downloads.request

    private val listings = NativeListingQueries { repository?.boundCollectionId }
    override val listingTarget: ListingTarget? get() = listings.target(state)
    override val listingQuery: ListingQuery get() = listings.query(state)
    private fun queryFor(target: ListingTarget): ListingQuery = listings.queryFor(state, target)
    override val canExportListing:Boolean get(){
        val target=listingTarget?:return false
        return !downloads.pickerInFlight&&state.sheet!=Sheet.FILTERS&&screenGate==ScreenGate.OPEN&&!state.busy&&!state.offline&&!state.readbackRequired&&
            !state.pending&&hasAccess(if(target in setOf(ListingTarget.STAFF,ListingTarget.AUDIT))Capability.STAFF else if(target in setOf(ListingTarget.SMS,ListingTarget.OBSERVATIONS))Capability.SMS else Capability.READ)&&
            (target !in setOf(ListingTarget.SMS,ListingTarget.OBSERVATIONS)||smsAccessGranted&&state.smsListSearch.isBlank()&&state.queuedSearch.isBlank())
    }
    override fun applyListingQuery(query:ListingQuery){
        val target=listingTarget?:return
        if(state.busy||screenGate!=ScreenGate.OPEN)return
        val valid=try{query.validated(target)}catch(_:Exception){state=state.copy(error="Check the filters and try again.");return}
        val updated = listings.apply(state, target, valid)
        views.invalidateRecords()
        state = updated
        clearRawDisclosure()
        work(kind=UiOperation.REFRESH){if(state.sheet==null)refreshNow()else refreshPanelNow()}
    }
    override fun resetListingQuery(){
        val target=listingTarget?:return
        val defaults=ListingQuery.defaultsFor(target)
        if(state.sheet==Sheet.FILTERS){
            listings.resetDraft(defaults)
        }else applyListingQuery(defaults)
    }
    fun configureDownloads(directory: File, renderer: (ExportFormat, ExportTable, File, () -> Boolean) -> Unit) =
        downloads.configure(directory, renderer)

    fun prepareDownload(format: ExportFormat) {
        if (!canExportListing || format == ExportFormat.CSV && (state.route != Route.MEMBER || state.sheet != null)) return
        val visibleTarget = listingTarget ?: return
        val visibleQuery = listingQuery.validated(visibleTarget)
        val target = if (format == ExportFormat.CSV) ListingTarget.LEDGER else visibleTarget
        val query = if (format == ExportFormat.CSV) ListingQuery.defaultsFor(target) else visibleQuery
        val context = listings.context(state)
        val owner = state.operator?.id ?: return
        val memberId = state.member?.id.takeIf { state.route == Route.MEMBER }
        val paymentId = state.historyPaymentId ?: state.sheetId.takeIf { state.sheet == Sheet.HISTORY }
        downloads.prepare(
            format, ListingExportSelection(target, query, memberId, paymentId),
            contextCurrent = { state.operator?.id == owner && listings.context(state) == context },
            queryCurrent = { listingQuery == visibleQuery },
        )
    }

    fun restoreDownloadPicker(requestId: Long, format: ExportFormat) = downloads.restorePicker(requestId, format)
    fun takeDownloadRequest(): DownloadRequest? = downloads.takeRequest()

    fun downloadDestination(
        requestId: Long?, format: ExportFormat, write: ((File, () -> Unit) -> Unit)?, abort: () -> Unit = {},
    ): Boolean {
        val accepted = downloads.acceptDestination(requestId, format, write, abort)
        // The result may arrive before onResume. Foreground revalidation takes priority.
        if (accepted) drainDownload()
        return accepted
    }

    private fun drainDownload() {
        if (foreground && screenGate == ScreenGate.OPEN && !state.busy) downloads.drain()
    }

    override fun cancelExport() = downloads.clear(showCancelled = true)
    override fun dismissExportFeedback() = downloads.dismissFeedback()

    private val navigationCheckpoints = NativeNavigationCheckpoints(checkpoints, clock, viewModelScope)
    private fun checkpointNavigation(debounce: Boolean = false) =
        navigationCheckpoints.save(state, screenGate, repository?.boundCollectionId, debounce)

    private var exposureJob:Job?=null
    private var queueRefreshJob:Job?=null
    private var observationStatusJob:Job?=null
    private val observationRetryRequests=mutableMapOf<String,String>()
    private var lastQueueRefreshAt=0L
    private var signOutRetryJob:Job?=null
    private var lifecycleObserved=false
    private var foreground by mutableStateOf(true)
    private var needsSessionCheck by mutableStateOf(false)
    private var sessionChecking by mutableStateOf(false)
    private var visibleExpired by mutableStateOf(false)
    private var resumeQueued=false
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
    private val memberInputs = MemberImportInputs()
    private val memberRegistration = NativeMemberRegistration(::repo)
    /** Consult the process authority before claiming a result, even while its change callback is queued. */
    private fun withMemberInputScope(scope: MemberImportScope, use: () -> Unit = {}): Boolean {
        val operator = state.operator ?: return false
        if (state.sheet != Sheet.ENROLL || state.onboarding.step != SmartOnboardingStep.IMPORT ||
            operator.id != scope.operatorId) return false
        return try {
            repository?.withMemberImportScope(scope) { use(); true } == true
        } catch (_: ContractFailure) { false }
    }

    private fun memberInputScopeCurrent(scope: MemberImportScope) = withMemberInputScope(scope)

    internal fun beginMemberInput(kind: MemberInputKind): String? {
        if (state.busy || state.sheet != Sheet.ENROLL || state.onboarding.step != SmartOnboardingStep.IMPORT ||
            !allows(Capability.ENROLL) || importReviewStarted() ||
            state.onboarding.photoCaptureFlow != (kind == MemberInputKind.CAMERA)) return null
        val operator = state.operator ?: return null
        val repository = repository ?: return null
        return try {
            repository.withCurrentProfile(operator) { group, session -> memberInputs.begin(kind, operator.id, group, session) }
        } catch (_: ContractFailure) { null }
    }

    internal fun ownsMemberInput(launchId: String): Boolean =
        memberInputs.retainedScope(launchId)?.let(::memberInputScopeCurrent) == true

    /** Consume the exact launcher result. The result may arrive before foreground revalidation. */
    internal fun receiveMemberInput(
        launchId: String?, uri: String?, failure: MemberImportFailure? = null, detectMime: (() -> String?)? = null,
    ): Boolean {
        val result = memberInputs.receive(launchId, uri, failure, detectMime) ?: return false
        if (!memberInputScopeCurrent(result.scope)) {
            memberInputs.discard(result)
            return false
        }
        drainMemberDocument()
        return result.uri != null && result.failure == null
    }

    private fun drainMemberDocument() {
        if (!foreground || state.busy || screenGate != ScreenGate.OPEN) return
        val pending = memberInputs.pending ?: return
        if (!memberInputScopeCurrent(pending.scope) || !hasAccess(Capability.ENROLL)) {
            memberInputs.discard(pending)
            return
        }
        val capture = pending.kind == MemberInputKind.CAMERA
        if (pending.uri == null || pending.failure != null) {
            if (!memberInputs.discard(pending)) return
            if (pending.failure != null) memberInputError(pending.failure)
            else if (capture) {
                memberInputs.clear()
                state = state.copy(onboarding = SmartOnboardingState(), error = null)
            }
            return
        }
        work(kind = UiOperation.INITIAL_READ, preservePresentation = true) {
            val mime = try {
                io {
                    val repo = repo()
                    repo.validateMemberImportScope(pending.scope)
                    if (memberInputs.pending !== pending || !memberInputScopeCurrent(pending.scope) ||
                        !allows(Capability.ENROLL)) throw CancellationException()
                    val value = pending.detectMime?.invoke()
                    repo.validateMemberImportScope(pending.scope)
                    value
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (memberInputs.discard(pending) && e !is ContractFailure &&
                    memberInputScopeCurrent(pending.scope) && allows(Capability.ENROLL)) {
                    memberInputError(MemberImportFailure.UNREADABLE)
                }
                return@work
            }
            withMemberInputScope(pending.scope) {
                if (allows(Capability.ENROLL) && memberInputs.select(pending)) {
                    state = state.copy(onboarding = state.onboarding.copy(
                        documentRequestId = pending.launchId, documentUri = pending.uri,
                        documentMimeType = if (capture) "image/jpeg" else mime ?: if (pending.kind == MemberInputKind.PHOTO) "image/*" else null,
                        documentSelected = true, ocrConsent = capture, photoCaptureFlow = capture,
                        photoPreviewPending = capture, rows = emptyList(), sourceKind = null,
                    ), error = null)
                }
            }
        }
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
        receiverQueue.invalidate()
        checkpointNavigation()
        downloads.onBackground()
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
        val coalesceInitialRestore=sameTransition&&repository!=null&&sessionBootstrap.shareInitialForeground()
        lifecycleObserved=true;foreground=true;needsSessionCheck=true
        if(coalesceInitialRestore){
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
    private fun hasAccess(capability:Capability)=Access.allows(state.operator,capability,clock(),BuildConfig.IS_GATEWAY)

    override var state by mutableStateOf(UiState(pending=true,starting=true), ScreenStatePolicy);private set
    override val presentation:ScreenPresentation get()=state.presentation(screenGate,clock())
    private val views=ViewMemory<UiState>()
    private var initialDraft:Map<String,String> = emptyMap()
    private var afterDiscard:(()->Unit)?=null
    private fun resetPanelInputs() {
        initialDraft = emptyMap()
        afterDiscard = null
        memberInputs.clear()
    }
    private val smsDisclosure by lazy { NativeSmsDisclosure(::repo, io, clock) }

    private fun clearRawDisclosure(preserveSmsSearch:Boolean=false){
        smsDisclosure.invalidate()
        smsInbox.invalidate()
        state = smsDisclosure.redact(state, preserveSmsSearch)
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
        listings.discardFilters()
        clearRawDisclosure(preserveSmsSearch=state.route==Route.SMS&&state.sheet==Sheet.RAW)
        resetPanelInputs()
        state=state.copy(sheet=null,sheetId=null,rawSource=null,draft=emptyMap(),draftDirty=false,
            discardRequested=false,selectedMember=null,selectedStaff=null,raw=null,error=null,onboarding=SmartOnboardingState())
    }
    /** Clear records after a contradictory response while retaining context, drafts and journal warnings. */
    private fun withoutRecords(value:UiState)=smsDisclosure.redact(value).copy(home=null,payments=null,members=null,ledger=null,memberTransactions=null,
        payment=null,member=null,messages=null,observations=null,observationUnavailable=false,raw=null,rawSource=null,staff=null,selectedStaff=null,audit=null,history=null,
        historyPaymentId=null,gateway=null,selectedMember=null,savedAt=null,panelSavedAt=null,historySavedAt=null,
        readbackRequired=true)
    private fun quarantineRecords(){
        views.invalidateRecords()
        state=withoutRecords(state)
    }
    private fun key(route:Route=state.route,id:String?=state.routeId)=route.name+":"+(id?:"")
    private fun clearViews(){
        queuedNavigation=null;receiverStatus.invalidate();receiverQueue.invalidate()
        observationStatusJob?.cancel();observationStatusJob=null;observationRetryRequests.clear();downloads.clear()
        listings.clear();clearRawDisclosure();views.clear();resetPanelInputs();navigationCheckpoints.clear()
    }
    private fun rememberedContext(value:UiState)=UiState(operator=state.operator,route=value.route,routeId=value.routeId,
        search=value.search,filter=value.filter,listIndex=value.listIndex,listOffset=value.listOffset,
        pending=state.pending,busy=true,readbackRequired=value.readbackRequired,allocatedFromVersion=value.allocatedFromVersion,
        memberAnchorId=value.memberAnchorId,memberWindowStartId=value.memberWindowStartId,memberListing=value.memberListing)
    private fun reusable(value:UiState)=value.route!=Route.SMS&&!value.readbackRequired&&SnapshotFreshness.reusable(value.savedAt,clock())

    override fun listPosition(route: Route, id: String?, index: Int, offset: Int) {
        if (state.busy || screenGate != ScreenGate.OPEN || state.route != route || state.routeId != id ||
            index !in 0..100_000 || offset !in 0..100_000) return
        val header = if (route == Route.MEMBERS) PagedRestoration.headerItems(route) else 0
        val members = if (route == Route.MEMBERS) state.members?.items.orEmpty() else emptyList()
        val footer = members.isNotEmpty() && state.members?.nextCursor != null && index == header + members.size
        val savedIndex = if (footer) header + members.lastIndex else index
        val anchor = if (route == Route.MEMBERS) {
            members.getOrNull(savedIndex - header)?.id ?: state.memberWindowStartId
        } else null
        state = state.copy(listIndex = savedIndex, listOffset = if (footer) 0 else offset, memberAnchorId = anchor)
        checkpointNavigation(debounce = true)
    }

    override fun memberListPosition(revision: Long, index: Int, offset: Int, visibleKey: String?) {
        if (state.memberViewportRevision != revision) return
        val member = state.members?.items?.getOrNull(index - PagedRestoration.headerItems(Route.MEMBERS))
        if (member != null && member.id != visibleKey) return
        listPosition(Route.MEMBERS, null, index, offset)
    }

    override fun showFirstMemberPage() {
        if (state.route != Route.MEMBERS || state.sheet != null) return
        work(kind = UiOperation.REFRESH) {
            state = state.copy(listIndex = 0, listOffset = 0, memberAnchorId = null, memberWindowStartId = null)
            refreshMembers()
        }
    }
    override fun editDraft(key:String,value:String){
        if(state.busy||key !in setOf("name","phone","note","query","enroll","allocate"))return
        val maximum=when(key){"name"->100;"note"->500;"phone"->40;"query"->80;else->5}
        val valueInDraft=value.take(maximum)
        val next=state.draft+(key to valueInDraft)
        val onboarding=if(state.sheet==Sheet.ENROLL)
            SmartOnboardingPresentation.identityEdited(state.onboarding,key,state.draft[key],valueInDraft) else state.onboarding
        state=state.copy(draft=next,onboarding=onboarding,
            draftDirty=state.selectedMember!=null||next.any{(k,v)->v!=(initialDraft[k]?:"")})
    }
    override fun discardDraft(){if(!state.busy){val next=afterDiscard;afterDiscard=null;dismissPanel();checkVisibleFreshness();next?.invoke();if(next==null&&state.route==Route.SMS&&state.filter!="queued"){
        if(state.filter=="all"){queueRefreshJob?.cancel();queueRefreshJob=viewModelScope.launch{refreshQueuedNow()}}
        smsInbox.scanVisible()
    }}}
    override fun keepDraft(){afterDiscard=null;state=state.copy(discardRequested=false)}
    @Volatile private var generation=0
    private val io = NativeOperationIo { generation }
    private var workSerial=0L
    private var actionJob:Job?=null
    private var repository:NativeRepository?=null
    private val collectionPosting by lazy { NativeCollectionPosting(repo()) }
    private val sessionBootstrap by lazy { NativeSessionBootstrap(repo(),checkpoints,BuildConfig.IS_GATEWAY,clock,::journalKnowledge) }
    val gateway=GatewayFactory.create(app,{repository?.boundCollectionId},
        {code,replace->(repository?:throw ApiFailure("session_unavailable",401)).pairGateway(code,replace)},
        retirementPending={repository?.hasReceiverRetirementRecord()?:false},
        recoverRetirement={repository?.recoverReceiverRetirement()},
        // Factory independently checks the actual bound receiving collection.
        authorizeControl={Access.allows(state.operator,Capability.GATEWAY,clock(),BuildConfig.IS_GATEWAY)})
    private val receiverStatus by lazy {
        NativeReceiverStatus(BuildConfig.IS_GATEWAY, gateway, { repository }, { state }, { foreground }, clock, viewModelScope)
    }
    private val smsInbox by lazy {
        NativeSmsInboxScan(
            viewModelScope, ::repo, receiverStatus, { state }, { state = it },
            { screenGate == ScreenGate.OPEN }, { smsAccessGranted }, { queryFor(ListingTarget.SMS) },
            ::requestObservationProcessing,
        )
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
        receiverQueue.invalidate()
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
        val restored=try{io{sessionBootstrap.restore()}}catch(e:ApiFailure){
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
        val grant=restored.grant
        if(grant==null){
            state=UiState(busy=true,starting=starting,pending=restored.navigation.pending)
            navigationCheckpoints.clear()
        }else{
            try{
                sessionBootstrap.withCurrent(grant){
                    state=navigationCheckpoints.restoredContext(grant.operator,restored.navigation)
                    if(!resumeQueued)needsSessionCheck=false
                    operationLabel="Loading records"
                }
            }catch(changed:ContractFailure){
                if(changed.code!="session_changed")throw changed
                val recovery=io{sessionBootstrap.recover(grant.operator.id,grant.group)}
                val replacement=presentSessionRecovery(recovery,restored.navigation.pending,busy=true)
                if(replacement!=null)refreshSessionRecords(replacement)
                return
            }
            try{loadSessionRecords(grant)}catch(e:ApiFailure){
                if(retryableSessionFailure(e)){needsSessionCheck=true;sessionRetryPending=true;lastSessionRecoveryAttemptAt=clock()}
                throw e
            }
        }
        sessionRetryPending=false
        if(!resumeQueued)needsSessionCheck=false
    }
    private suspend fun loadSessionRecords(grant:NativeSessionBootstrap.Grant){
        if(BuildConfig.IS_GATEWAY)io{
            sessionBootstrap.requireCurrent(grant)
            try{gateway.start()}catch(e:CancellationException){throw e}catch(_:Exception){}
        }
        refreshSessionRecords(grant)
    }
    private suspend fun refreshSessionRecords(grant:NativeSessionBootstrap.Grant){
        sessionBootstrap.requireCurrent(grant)
        refreshNow()
        sessionBootstrap.requireCurrent(grant)
    }
    private fun presentSessionRecovery(recovery:NativeSessionBootstrap.Recovery,pending:Boolean,busy:Boolean):NativeSessionBootstrap.Grant?{
        val empty=UiState(pending=pending,busy=busy)
        restoreRetryPending=recovery==NativeSessionBootstrap.Recovery.PasscodePending||recovery==NativeSessionBootstrap.Recovery.Offline
        if(restoreRetryPending)lastRestoreAttemptAt=0L
        when(recovery){
            NativeSessionBootstrap.Recovery.PasscodePending->
                state=empty.copy(error=message("passcode_change_unconfirmed",true),passcodeChangePending=true,failure=DisplayFailure.UNCERTAIN)
            NativeSessionBootstrap.Recovery.Offline->state=empty.copy(error="Check your connection",savedSessionPending=true)
            NativeSessionBootstrap.Recovery.SignedOut->state=empty.copy(error="Sign in again.")
            is NativeSessionBootstrap.Recovery.Attached->try{
                sessionBootstrap.withCurrent(recovery.grant){state=empty.copy(operator=recovery.grant.operator,route=Route.HOME)}
                return recovery.grant
            }catch(_:ContractFailure){state=empty.copy(error="Sign in again.")}
        }
        return null
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
                val recovery=withContext(Dispatchers.IO){sessionBootstrap.recover(oldOwner,oldGroup)}
                if(generation!=ownerGeneration||state.busy)return@launch
                val grant=presentSessionRecovery(recovery,hadPending,busy=false)
                if(grant!=null)work(bypassGate=true){refreshSessionRecords(grant)}
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
            sessionBootstrap.beginInitialRestore()
            work(bypassGate=true,kind=UiOperation.INITIAL_READ){
                operationLabel="Checking access"
                var completed=false
                try{
                    if(recoverReceiverRetirement())return@work
                    restoreSavedSession();completed=true
                }finally{
                    if(sessionBootstrap.finishInitialRestore(completed))resumeQueued=true
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
    private fun work(bypassGate:Boolean=false,preservePresentation:Boolean=false,kind:UiOperation?=null,quietRefresh:Boolean=false,
        onFinished:(()->Unit)?=null,action:suspend ()->Unit){
        checkVisibleFreshness()
        if(state.busy||(!bypassGate&&screenGate!=ScreenGate.OPEN)){onFinished?.invoke();return}
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
                    drainDownload()
                    drainMemberDocument()
                    drainGatewayPermissionStatus()
                    checkpointNavigation()
                }
            }
        }.also { job -> if (onFinished != null) job.invokeOnCompletion { onFinished() } }
    }
    private val receiverQueue by lazy {
        NativeReceiverQueuePreview(receiverStatus, gateway, { state }, { state = it },
            { screenGate == ScreenGate.OPEN && smsAccessGranted }, { queryFor(ListingTarget.SMS) }, clock)
    }

    private suspend fun refreshQueuedNow() {
        if (receiverQueue.refresh()) lastQueueRefreshAt = clock()
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
        val grant=io{sessionBootstrap.login(phone,pin)}
        restoreRetryPending=false;clearViews()
        sessionBootstrap.withCurrent(grant){state=UiState(operator=grant.operator,route=Route.HOME,busy=true,pending=state.pending)}
        loadSessionRecords(grant)
        visibleExpired=false;if(!resumeQueued)needsSessionCheck=false
    }
    override fun logout(){
        downloads.clear()
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
            // Returning to a remembered route requires a fresh read.
            views.invalidateRecords()
            try{
                // The old native session may already be revoked by retirement.
                // Check the encrypted original proof before ordinary session validation.
                if(recoverReceiverRetirement())return@work
                val previous=state.operator?:run{needsSessionCheck=false;return@work}
                val grant=io{sessionBootstrap.refresh()}
                val current=grant.operator
                if(!previous.hasSameAccess(current)){
                    val allowed=previous.id==current.id&&Access.routeAllowed(current,state.route,clock(),BuildConfig.IS_GATEWAY)
                    val old=state;clearViews()
                    sessionBootstrap.withCurrent(grant){
                        state=UiState(operator=current,route=if(allowed)old.route else Route.HOME,
                            routeId=if(allowed)old.routeId else null,busy=true,pending=old.pending)
                    }
                }else sessionBootstrap.withCurrent(grant){state=state.copy(operator=current,offline=false)}
                refreshNow()
                if(state.sheet!=null){
                    if(panelAllowed(state.sheet))refreshPanelNow()
                    else{resetPanelInputs();state=state.copy(sheet=null,sheetId=null,raw=null,staff=null,audit=null,history=null,selectedStaff=null,selectedMember=null,draft=emptyMap(),draftDirty=false)}
                }
                sessionBootstrap.requireCurrent(grant)
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
        if(!Access.routeAllowed(state.operator,route,clock(),BuildConfig.IS_GATEWAY))return
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
            if(route!=state.route||id!=state.routeId)views.push(key(),smsDisclosure.redact(old).copy(gateway=null))
            val remembered=views.remembered(key(route,id))
            val fresh=remembered?.takeIf{views.isCurrent(it)&&reusable(it.value)}?.value
            resetPanelInputs()
            state=(fresh?:remembered?.value?.let{rememberedContext(it)}?:UiState(operator=state.operator,route=route,routeId=id)).copy(operator=state.operator,
                busy=true,pending=state.pending,failure=DisplayFailure.NONE,sheet=null,sheetId=null,error=null,selectedMember=null,draft=emptyMap(),draftDirty=false,discardRequested=false)
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
            work{resetPanelInputs();state=UiState(operator=state.operator,route=parent,busy=true,pending=state.pending);refreshNow()}
            return
        }
        if(!Access.routeAllowed(state.operator,previous.value.route,clock(),BuildConfig.IS_GATEWAY)){clearViews();navigate(Route.HOME);return}
        work{
            views.remember(key(),smsDisclosure.redact(state).copy(busy=false,gateway=null))
            val fresh=views.isCurrent(previous)&&reusable(previous.value)
            val restoredSheet=previous.value.sheet.takeIf{it!=Sheet.RAW&&panelAllowed(it)}
            val restoredId=previous.value.sheetId
            state=(if(fresh)previous.value else rememberedContext(previous.value)).copy(
                operator=state.operator,busy=true,error=null,pending=state.pending,failure=DisplayFailure.NONE,
                sheet=null,sheetId=null,raw=null,staff=null,audit=null,history=null,
                selectedStaff=null,selectedMember=null,draft=emptyMap(),draftDirty=false,discardRequested=false)
            resetPanelInputs()
            if(!fresh)refreshNow() else if(restoredSheet==null)refreshRememberedReceiverStatus()
            if(restoredSheet!=null){
                // Evidence is re-read, never redisplayed from a remembered privileged panel.
                state=state.copy(sheet=restoredSheet,sheetId=restoredId)
                refreshPanelNow()
            }
        }
    }
    override fun openUnallocated(){
        if(state.busy||!Access.routeAllowed(state.operator,Route.PAYMENTS,clock(),BuildConfig.IS_GATEWAY))return
        work(kind=UiOperation.INITIAL_READ){
            clearRawDisclosure()
            views.push(key(),smsDisclosure.redact(state).copy(busy=false,error=null,gateway=null))
            state=UiState(operator=state.operator,route=Route.PAYMENTS,busy=true,filter="unallocated",pending=state.pending)
            refreshNow()
        }
    }
    override fun search(value:String){
        if(state.busy||screenGate!=ScreenGate.OPEN)return
        val bounded=value.filter{!it.isISOControl()}.take(80)
        val query=if(bounded.lastOrNull()?.isHighSurrogate()==true)bounded.dropLast(1)else bounded
        if(state.route==Route.SMS&&state.filter=="queued"){
            if(state.queuedSearch!=query){
                receiverQueue.invalidate()
                state=state.copy(queuedSearch=query,queuedObservations=null,queuedUnavailable=false)
            }
        }else if(state.route==Route.SMS){
            if(state.smsListSearch!=query){
                smsInbox.searchChanged();receiverQueue.invalidate()
                state=state.copy(smsListSearch=query,queuedObservations=if(state.filter=="all")null else state.queuedObservations)
            }
        }
        else{state=state.copy(search=query);checkpointNavigation(debounce=true)}
    }
    override fun searchSubmit(){
        if(state.route==Route.SMS&&state.filter!="queued"){
            if(!state.busy&&screenGate==ScreenGate.OPEN){state=state.copy(listIndex=0,listOffset=0);smsInbox.scanVisible()
                if(state.filter=="all"){queueRefreshJob?.cancel();queueRefreshJob=viewModelScope.launch{refreshQueuedNow()}}}
            return
        }
        work(kind=UiOperation.REFRESH){state=state.copy(listIndex=0,listOffset=0,memberAnchorId=null,memberWindowStartId=null);if(state.sheet==null)refreshNow()else refreshPanelNow()}
    }
    override fun setFilter(value:String){
        if(state.busy||value !in NavigationCheckpoint.filters(state.route))return
        val clearSearch=state.route==Route.SMS&&(state.filter=="queued"||value=="queued")
        clearRawDisclosure();state=state.copy(filter=value,search=if(clearSearch)""else state.search,queuedSearch="",sheet=null,listIndex=0,listOffset=0)
        if(state.route==Route.SMS&&value!="queued")work{refreshNow()} else searchSubmit()
    }
    override fun refresh(){
        if(state.savedSessionPending||state.passcodeChangePending){retrySavedSession();return}
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
    private val pagedRestoration by lazy {
        NativePagedRestoration(::repo, { state }, { generation }, clock, BuildConfig.IS_GATEWAY)
    }
    private val memberDirectory = NativeMemberDirectory(::repo, clock)

    private suspend fun refreshMembers() {
        val listing = queryFor(ListingTarget.MEMBERS)
        val savedAnchor = state.memberAnchorId
        val read = io { memberDirectory.first(listing, savedAnchor) }
        state = memberDirectory.showFirst(state, listing, savedAnchor, read)
    }

    private suspend fun refreshRememberedReceiverStatus() {
        if (state.route == Route.HOME) refreshHomeGatewayStatus()
        if (state.route == Route.SETTINGS) {
            refreshReceiverPanel()
            receiverStatus.refreshHealth()
        }
    }

    private fun refreshHomeGatewayStatus() = receiverStatus.refreshHome { state=state.copy(gateway=it) }

    private fun showReceiverPanelStatus(status: GatewayStatus) {
        state=state.copy(gateway=status,panelSavedAt=clock())
    }

    private suspend fun refreshReceiverPanel() {
        receiverStatus.read(receiverStatus.request(), publish = ::showReceiverPanelStatus)
    }

    private suspend fun refreshNow(){
        when(state.route){
            Route.HOME->{val h=io{repo().home()};val cached=repo().lastReadFromCache;val saved=repo().lastReadSavedAt
                state=state.copy(home=h,gateway=null,offline=cached,savedAt=saved,readbackRequired=state.readbackRequired&&cached)
                if(state.sheet==null)refreshHomeGatewayStatus()}
            Route.PAYMENTS -> {
                val request = pagedRestoration.request()
                val listing = queryFor(ListingTarget.PAYMENTS)
                val first = pagedRestoration.read(request) { it.payments(listing) }
                val restored = pagedRestoration.restore(request, first, Payment::id) { cursor ->
                    pagedRestoration.read(request) { it.payments(listing, cursor) }
                }
                pagedRestoration.withCurrent(request) {
                    val (page, offline, savedAt) = restored.content
                    val position = restored.decision
                    state = it.copy(payments = page, offline = offline, savedAt = savedAt,
                        readbackRequired = it.readbackRequired && offline,
                        listIndex = position.index, listOffset = position.offset, listRestoration = position.stop)
                }
            }
            Route.MEMBERS -> refreshMembers()
            Route.SMS->{
                if(!hasAccess(Capability.SMS))throw ApiFailure("access_denied",403)
                if(state.filter=="queued"){
                    refreshQueuedNow()
                    return
                }
                val request = pagedRestoration.request()
                val listing = queryFor(ListingTarget.SMS)
                val paired=io{gateway.bound()}
                var unavailable=false;var disconnected=false
                fun unavailableRead(e:ApiFailure):Boolean=e.status==0||e.status in setOf(404,408,425,429)||e.status>=500
                suspend fun canonicalPage(cursor: String?) = pagedRestoration.read(request, cacheable = false) {
                    val page = it.sms(listing, cursor = cursor, limit = 5)
                    page.copy(items = page.items.map { row -> row.copy(sender = "", preview = "") })
                }
                val canonical=if(paired)try{
                    pagedRestoration.restore(request, canonicalPage(null), SmsRow::id, ::canonicalPage)
                }catch(e:ApiFailure){if(!unavailableRead(e))throw e;unavailable=true;disconnected=disconnected||e.status==0;null}else null
                // Revoking Android SMS access also revokes the corresponding
                // server consent. A restored SMS route must not query that
                // stream while permission is absent: the expected 403 would
                // otherwise strand the session-refresh gate and prevent the
                // user from reaching Settings to grant permission again.
                val observed=if(state.filter=="all"&&!smsAccessGranted){unavailable=true;null}
                    else if(state.filter=="all")try{
                        val page=pagedRestoration.read(request, cacheable = false) {
                            if(!smsAccessGranted)throw ApiFailure("access_denied",403)
                            it.observationPage(listing.copy(filter="all"),limit=5)
                        }
                        page.value.takeIf{smsAccessGranted}.also{if(it==null)unavailable=true}
                    }
                    catch(e:ApiFailure){
                        // Permission can be restored before asynchronous consent
                        // reconciliation finishes.  Keep the stream unavailable
                        // on a scoped 403; session and role checks still apply.
                        if(e.status!=403&&!unavailableRead(e))throw e
                        unavailable=true;disconnected=disconnected||e.status==0;null
                    }
                    else if(canonical==null)Page(emptyList(),null,0,"filtered",java.time.Instant.ofEpochMilli(clock()).toString()) else null
                pagedRestoration.withCurrent(request) {
                    state=it.copy(messages=canonical?.content?.value,observations=observed,observationProcessing=emptyMap(),observationRetryNotice=null,queuedObservations=null,queuedUnavailable=false,observationUnavailable=unavailable,
                        offline=disconnected||(canonical?.content?.offline?:false),savedAt=canonical?.content?.savedAt?:clock(),readbackRequired=false,
                        listIndex=canonical?.decision?.index?:0,listOffset=canonical?.decision?.offset?:0,listRestoration=canonical?.decision?.stop)
                }
                if(state.filter=="all")refreshQueuedNow()
                requestObservationProcessing()
                smsInbox.scanVisible()
            }
            Route.PAYMENT->{
                val id=state.routeId?:state.payment?.id?:return
                refreshPayment(id)
            }
            Route.MEMBER -> {
                val id = state.routeId ?: state.member?.id ?: return
                val request = pagedRestoration.request()
                val listing = queryFor(ListingTarget.PAYMENTS)
                val member = pagedRestoration.read(request) { it.member(id) }
                val payments = pagedRestoration.read(request) { it.payments(listing, memberId = id) }
                val first = payments.copy(offline = member.offline || payments.offline,
                    savedAt = SnapshotFreshness.oldest(clock(), member.savedAt, payments.savedAt))
                val restored = pagedRestoration.restore(request, first, Payment::id) { cursor ->
                    pagedRestoration.read(request) { it.payments(listing, cursor = cursor, memberId = id) }
                }
                pagedRestoration.withCurrent(request) {
                    val (page, offline, savedAt) = restored.content
                    val position = restored.decision
                    state = it.copy(member = member.value, ledger = null, memberTransactions = page,
                        offline = offline, savedAt = savedAt, readbackRequired = it.readbackRequired && offline,
                        listIndex = position.index, listOffset = position.offset, listRestoration = position.stop)
                }
            }
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
        if(state.route==Route.SMS&&state.sheet==null){smsInbox.moreCanonical();return}
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
            Sheet.ALLOCATE -> {
                val previous = state.members ?: return@work
                refreshAllocationMembers(state.allocationQuery, previous)
                return@work
            }
            else->Unit
        }
        when(state.route){
            Route.PAYMENTS, Route.MEMBER -> morePayments()
            Route.MEMBERS -> {
                val current = state.members ?: return@work
                val cursor = current.nextCursor ?: return@work
                val listing = queryFor(ListingTarget.MEMBERS)
                val next = io { memberDirectory.next(listing, cursor) }
                state = memberDirectory.append(state, current, next)
            }
            Route.SMS->Unit
            else->Unit
        }
        }
    }
    private suspend fun morePayments() {
        val onMember = state.route == Route.MEMBER
        val previous = (if (onMember) state.memberTransactions else state.payments) ?: return
        val cursor = previous.nextCursor ?: return
        val memberId = if (onMember) (state.routeId ?: throw ApiFailure("record_unavailable")) else null
        if (onMember) checkContract(state.member?.id == memberId, "invalid_api_response")
        val request = pagedRestoration.request()
        val listing = queryFor(ListingTarget.PAYMENTS)
        val current = NativePagedRestoration.Read(previous, state.offline, state.savedAt)
        val next = pagedRestoration.read(request) { it.payments(listing, cursor = cursor, memberId = memberId) }
        val (page, offline, savedAt) = pagedRestoration.append(current, next, Payment::id)
        pagedRestoration.withCurrent(request) {
            state = if (onMember) it.copy(memberTransactions = page, offline = offline, savedAt = savedAt)
                else it.copy(payments = page, offline = offline, savedAt = savedAt)
        }
    }
    override fun moreObservations(){
        smsInbox.moreObservations()
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
            listings.openFilters(state)?.let { state = it }
            return
        }
        listings.discardFilters()
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
            resetPanelInputs()
            val panel=state.copy(sheet=sheet,sheetId=if(sheet==Sheet.HISTORY)id?:state.payment?.id else id,rawSource=source,observationRetryNotice=null,
                error=null,selectedMember=null,raw=null,panelSavedAt=state.panelSavedAt,
                history=null,historyPaymentId=null,historyOffline=false,historySavedAt=null,
                allocationQuery="",draft=emptyMap(),draftDirty=false,discardRequested=false,onboarding=SmartOnboardingState())
            state=if(sheet==Sheet.ALLOCATE)collectionPosting.startCandidateSearch(panel,"")else panel
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
        if (!state.busy) {
            listings.closeFilters(state)?.let { state = it; return }
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
    private suspend fun loadRawForCurrentPanel(reason:String){
        val started = generation
        smsDisclosure.load(reason, { state }, { state = it }) {
            started == generation && foreground && screenGate == ScreenGate.OPEN && hasAccess(Capability.SMS)
        }
    }
    override fun selectMember(member:Member){
        checkVisibleFreshness()
        if(!state.busy&&state.sheet==Sheet.ALLOCATE&&allows(Capability.ALLOCATE))state=collectionPosting.select(state,member)
    }
    override fun allocationSearch(q:String){
        if(state.sheet==Sheet.ALLOCATE)work(kind=UiOperation.REFRESH){
            if(q!=state.allocationQuery)state=collectionPosting.startCandidateSearch(state,q)
            refreshAllocationMembers(state.allocationQuery)
        }
    }
    private suspend fun refreshAllocationMembers(query: String, previous: Page<Member>? = null) {
        val result = io { collectionPosting.candidates(query, previous) } ?: return
        state = collectionPosting.showCandidates(state, result, sessionChecking, clock())
    }
    /** Drop records and consumed form state before any post-command read can fail.
     * The durable journal is owned by the repository and is never edited here. */
    private fun invalidateCommandViews(notice:String?=null){
        downloads.clear();views.invalidateRecords();resetPanelInputs()
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
    private suspend fun refreshPayment(id: String) {
        val operator = state.operator ?: throw ApiFailure("session_unavailable", 401)
        val fromVersion = state.allocatedFromVersion
        val read = io { collectionPosting.readPayment(operator, id, fromVersion) }
        state = collectionPosting.showPayment(state, operator, read)
    }
    override fun allocate(note:String)=work{
        requireNoUnresolvedCommand()
        if(!allows(Capability.ALLOCATE)||state.offline)throw ApiFailure("access_denied",403)
        val selection=collectionPosting.allocation(state)
        command{collectionPosting.post(selection,note)}
        state=state.copy(allocatedFromVersion=selection.payment.version)
        refreshPayment(selection.payment.id)
    }
    override fun enroll(name:String,phone:String)=work{
        requireNoUnresolvedCommand()
        if(!allows(Capability.ENROLL)||state.offline)throw ApiFailure("access_denied",403)
        checkContract(Presentation.validName(name),"invalid_name")
        val result=command{repo().enroll(name,phone)}
        // The command has already committed. Navigate only to the acknowledged
        // member ID carried by its verified outcome, and re-read the ledger; never retry the
        // enrollment or infer an ID from the entered phone number.
        val memberId=memberRegistration.confirmedMemberId(result)
        if(memberId==null){
            state=state.copy(error="Member saved. Refresh the member list to open the record.",failure=DisplayFailure.UNAVAILABLE)
            return@work
        }
        val previous=state.copy(busy=false,error=null)
        views.push(key(),smsDisclosure.redact(previous).copy(gateway=null))
        state=UiState(operator=previous.operator,route=Route.MEMBER,routeId=memberId,busy=true,
            pending=previous.pending,commandNotice=previous.commandNotice)
        refreshNow()
    }
    override fun onboardingOptions(){
        if(state.busy||!allows(Capability.ENROLL))return
        memberInputs.clear()
        state=state.copy(onboarding=SmartOnboardingState(),draft=emptyMap(),draftDirty=false,error=null)
    }
    override fun onboardingManual(){
        if(state.busy||!allows(Capability.ENROLL)||importReviewStarted())return
        memberInputs.clear()
        state=state.copy(onboarding=SmartOnboardingState(step=SmartOnboardingStep.MEMBER),draft=emptyMap(),draftDirty=false,error=null)
    }
    override fun onboardingSearchQuery(value:String){
        if(value.length<=80&&!state.busy)state=state.copy(onboarding=state.onboarding.copy(query=value))
    }
    override fun onboardingSuggestions(query:String,cursor:String?){
        if(importReviewStarted())return
        if(cursor==null&&state.onboarding.step!=SmartOnboardingStep.SUGGESTIONS){
            if(state.busy||state.offline||!allows(Capability.ENROLL))return
            memberInputs.clear()
            state=state.copy(onboarding=SmartOnboardingState(step=SmartOnboardingStep.SUGGESTIONS),draft=emptyMap(),draftDirty=false,error=null)
        }
        work{
        if(!allows(Capability.ENROLL)||state.offline)throw ApiFailure("access_denied",403)
        val suggestions = io { memberRegistration.suggestions(query, cursor) }
        state=state.copy(
            onboarding=memberRegistration.showSuggestions(state.onboarding, suggestions, continuing=cursor!=null),
            error=null,
        )
        }
    }
    override fun onboardingChoose(candidateId:String){
        if(state.busy||!allows(Capability.ENROLL))return
        val candidate=state.onboarding.suggestions.singleOrNull{it.candidateId==candidateId}?:return
        state=state.copy(onboarding=state.onboarding.copy(step=SmartOnboardingStep.MEMBER,candidate=candidate,
            verifiedOwnership=false,acceptedTerms=false,consentRecorded=false),draft=mapOf("name" to candidate.momoName),draftDirty=false,error=null)
    }
    override fun onboardingImport(){
        if(state.busy||!allows(Capability.ENROLL)||state.sheet!=Sheet.ENROLL)return
        if(state.onboarding.step != SmartOnboardingStep.IMPORT) memberInputs.clear()
        state=state.copy(onboarding=state.onboarding.copy(step=SmartOnboardingStep.IMPORT,editingRow=null,photoPreviewPending=false),draft=emptyMap(),draftDirty=false,error=null)
    }
    override fun onboardingPhoto(){
        if(state.busy||!allows(Capability.ENROLL)||state.sheet!=Sheet.ENROLL||importReviewStarted())return
        memberInputs.clear()
        state=state.copy(onboarding=SmartOnboardingState(step=SmartOnboardingStep.IMPORT,photoCaptureFlow=true),
            draft=emptyMap(),draftDirty=false,error=null)
    }
    private fun importReviewStarted(): Boolean = state.onboarding.step == SmartOnboardingStep.IMPORT &&
        (state.onboarding.sourceKind != null || state.onboarding.rows.isNotEmpty())

    internal fun currentMemberSelection(requestId: String, automaticPhoto: Boolean): MemberInputSelection? {
        checkVisibleFreshness()
        val selection = memberInputs.currentSelection() ?: return null
        val onboarding = state.onboarding
        if (state.busy || state.offline || state.pending || !allows(Capability.ENROLL) ||
            requestId != selection.launchId || onboarding.documentRequestId != requestId ||
            onboarding.documentUri != selection.uri || !memberInputScopeCurrent(selection.scope) ||
            automaticPhoto && (selection.kind != MemberInputKind.CAMERA || !onboarding.photoPreviewPending || !onboarding.ocrConsent)) return null
        return selection
    }

    override fun onboardingDocumentConsent(requestId: String, value: Boolean) {
        val input = currentMemberSelection(requestId, false) ?: return
        withMemberInputScope(input.scope) {
            if (memberInputs.currentSelection() === input)
                state = state.copy(onboarding = state.onboarding.copy(ocrConsent = value))
        }
    }

    /** Cheap checks for each provider chunk. The protected repository check runs at the I/O boundaries. */
    internal fun checkMemberDocumentRead(selection: MemberInputSelection, requiresConsent: Boolean) {
        if (state.busy || state.offline || state.pending || !allows(Capability.ENROLL) ||
            memberInputs.currentSelection() !== selection || state.onboarding.documentRequestId != selection.launchId ||
            requiresConsent && !state.onboarding.ocrConsent || !memberInputScopeCurrent(selection.scope)) throw CancellationException()
    }

    internal fun validateMemberDocumentRead(selection: MemberInputSelection, requiresConsent: Boolean = false) {
        checkMemberDocumentRead(selection, requiresConsent)
        repo().validateMemberImportScope(selection.scope)
    }

    private fun memberInputError(failure: MemberImportFailure) {
        val message = when (failure) {
            MemberImportFailure.CAMERA_UNAVAILABLE -> "Camera unavailable. Choose a photo or file instead."
            MemberImportFailure.TOO_LARGE -> "This photo is too large. Choose a smaller photo."
            MemberImportFailure.UNREADABLE -> "Unable to read the selected file."
        }
        if (state.onboarding.photoCaptureFlow) {
            memberInputs.clear()
            state = state.copy(onboarding = SmartOnboardingState(), error = message, failure = DisplayFailure.UNAVAILABLE)
        } else state = state.copy(error = message, failure = DisplayFailure.UNAVAILABLE)
    }

    internal fun memberDocumentReadFailed(selection: MemberInputSelection, failure: MemberImportFailure) {
        if (currentMemberSelection(selection.launchId, false) === selection) memberInputError(failure)
    }

    internal fun previewMemberDocument(selection: MemberInputSelection, mimeType: String, bytes: ByteArray, automaticPhoto: Boolean) {
        if (currentMemberSelection(selection.launchId, automaticPhoto) !== selection) {
            bytes.fill(0)
            return
        }
        val consent = state.onboarding.ocrConsent
        if (SmartOnboardingPresentation.previewNeedsConsent(mimeType) && !consent) {
            bytes.fill(0)
            return
        }
        work(onFinished = { bytes.fill(0) }) {
            if (automaticPhoto) state = state.copy(onboarding = state.onboarding.copy(photoPreviewPending = false))
            val preview = try {
                io {
                    if (!memberInputScopeCurrent(selection.scope) || memberInputs.currentSelection() !== selection ||
                        !allows(Capability.ENROLL) || state.onboarding.ocrConsent != consent) throw CancellationException()
                    try { memberRegistration.preview(selection, mimeType, bytes, consent) } finally { bytes.fill(0) }
                }
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Exception) {
                if (!allows(Capability.ENROLL) || memberInputs.currentSelection() !== selection ||
                    !memberInputScopeCurrent(selection.scope)) return@work
                throw error
            }
            withMemberInputScope(selection.scope) {
                if (allows(Capability.ENROLL) && memberInputs.finish(selection)) {
                    state = state.copy(onboarding = state.onboarding.copy(sourceKind = preview.sourceKind, rows = preview.rows,
                        documentRequestId = null, documentUri = null, documentMimeType = null, documentSelected = false), error = null)
                }
            }
        }
    }
    override fun onboardingEditRow(row:Int){
        if(state.busy||state.sheet!=Sheet.ENROLL||state.onboarding.step!=SmartOnboardingStep.IMPORT||!allows(Capability.ENROLL))return
        val selected=state.onboarding.rows.singleOrNull{it.row==row}?:return
        state=state.copy(onboarding=SmartOnboardingPresentation.editRow(state.onboarding,row),
            draft=mapOf("name" to selected.name,"phone" to selected.phone.orEmpty()),draftDirty=false,error=null)
    }
    override fun onboardingConsent(field:String,value:Boolean,displayedDraft:Map<String,String>?){
        if(state.busy||state.sheet!=Sheet.ENROLL||!allows(Capability.ENROLL))return
        state=state.copy(onboarding=SmartOnboardingPresentation.consent(state.onboarding,state.draft,displayedDraft,field,value))
    }
    override fun onboardingSaveRow(name:String,phone:String){
        if(state.busy||state.sheet!=Sheet.ENROLL||!allows(Capability.ENROLL))return
        val saved=SmartOnboardingPresentation.saveRow(state.onboarding,state.draft,name,phone)
        if(saved!==state.onboarding)state=state.copy(onboarding=saved,draft=emptyMap(),draftDirty=false,error=null)
    }
    private suspend fun submitOnboarding(rows:JSONArray){
        requireNoUnresolvedCommand()
        if(!allows(Capability.ENROLL)||state.offline)throw ApiFailure("access_denied",403)
        val result=memberRegistration.importResult(command{repo().onboardingImport(rows)})
        refreshNow()
        state=state.copy(sheet=Sheet.ENROLL,onboarding=result,draft=emptyMap(),draftDirty=false)
    }
    override fun onboardingSubmit(name:String,phone:String){
        if(state.sheet!=Sheet.ENROLL||state.onboarding.step!=SmartOnboardingStep.MEMBER)return
        work { submitOnboarding(memberRegistration.singleRow(state.onboarding, state.draft, name, phone)) }
    }
    override fun onboardingSubmitBatch(){
        if(state.sheet!=Sheet.ENROLL||state.onboarding.step!=SmartOnboardingStep.IMPORT)return
        work { submitOnboarding(memberRegistration.selectedRows(state.onboarding)) }
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
        if(existing==null||pin.isNotBlank())body.put("pin",Values.pin(pin))
        val caps=JSONArray().put(Capability.READ.key);if(enroll)caps.put(Capability.ENROLL.key);if(allocate)caps.put(Capability.ALLOCATE.key);body.put("capabilities",caps)
        command{repo().staffAction(body,resolveBlankPhoneDenial)};val staff=io{repo().staff()};state=state.copy(sheet=Sheet.STAFF,sheetId=null,staff=staff,panelSavedAt=clock(),selectedStaff=null,draft=emptyMap(),draftDirty=false)
    }
    override fun staffAction(action:String,pin:String?)=work{
        requireNoUnresolvedCommand()
        if(!allows(Capability.STAFF))throw ApiFailure("access_denied",403)
        val s=state.selectedStaff?:throw ApiFailure("staff_unavailable")
        val body=JSONObject().put("action",action).put("id",s.id).put("expectedVersion",s.version)
        if(pin!=null)body.put("pin",Values.pin(pin))
        command{repo().staffAction(body)};val staff=io{repo().staff()};state=state.copy(sheet=Sheet.STAFF,sheetId=null,staff=staff,panelSavedAt=clock(),selectedStaff=null,draft=emptyMap(),draftDirty=false)
    }
    override fun requestRemoveStaff(){if(state.selectedStaff!=null&&allows(Capability.STAFF))openSheet(Sheet.REMOVE_STAFF,state.selectedStaff?.id)}
    override fun setMemberActive(active:Boolean)=work{requireNoUnresolvedCommand();if(state.operator?.role!=Role.ADMIN||!allows(Capability.ENROLL)||state.offline)throw ApiFailure("access_denied",403);val m=state.member?:throw ApiFailure("member_unavailable");command{repo().setMemberActive(m,active)};val v=io{repo().member(m.id)};state=state.copy(sheet=null,sheetId=null,member=v,offline=repo().lastReadFromCache,savedAt=repo().lastReadSavedAt)}
    override fun pair(code:String)=work{
        receiverStatus.pair(code, ::showReceiverPanelStatus)
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
            val ownerGeneration=generation
            val replacement=try {
                receiverStatus.replace(code)
            } catch(e:CancellationException){throw e}
            catch(e:Exception){
                val pending=try{io{gateway.retirementPending()}}catch(cancel:CancellationException){throw cancel}catch(_:Exception){true}
                if(ownerGeneration!=generation)throw CancellationException()
                if(pending||e is ApiFailure&&e.code=="gateway_retirement_unconfirmed")coverReceiverRetirement() else throw e
                return@work
            }
            if(ownerGeneration!=generation)throw CancellationException()
            if(replacement!=null)acceptReceiverRetirement(replacement)
        }
    }
    override fun syncReceiver()=work{
        if(!allows(Capability.GATEWAY))throw ApiFailure("access_denied",403)
        receiverStatus.sync(::showReceiverPanelStatus)
    }
    override fun setPaused(value:Boolean)=work{
        if(!allows(Capability.GATEWAY))throw ApiFailure("access_denied",403)
        receiverStatus.setPaused(value, ::showReceiverPanelStatus)
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
    private fun message(code:String,uncertain:Boolean):String=when{
        code=="smart_import_preview_unconfirmed"->"Preview unconfirmed. Open the same file again to check its result."
        code in setOf("smart_import_decoder_unavailable","smart_import_ocr_unavailable")->"This document format is not available yet. Choose a CSV file."
        code in setOf("smart_import_consent_required","smart_import_disclosure_required")->"Confirm the document processing consent before continuing."
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
