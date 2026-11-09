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

enum class Sheet { PROFILE, PIN, HELP, ALLOCATE, ENROLL, STAFF, STAFF_EDIT, REMOVE_STAFF, GATEWAY, RAW, MEMBER_DETAILS, HISTORY, AUDIT, FILTERS }
data class UiState(
    val operator:Operator?=null,val route:Route=Route.LOGIN,val sheet:Sheet?=null,val busy:Boolean=false,val error:String?=null,
    val home:Home?=null,val payments:Page<Payment>?=null,val members:Page<Member>?=null,val ledger:Page<LedgerRow>?=null,
    val payment:Payment?=null,val member:Member?=null,val messages:Page<SmsRow>?=null,val raw:RawSms?=null,
    val staff:Page<StaffAccount>?=null,val selectedStaff:StaffAccount?=null,val audit:Page<AuditRow>?=null,
    val panelSavedAt:Long?=null,
    val history:Page<PaymentEvent>?=null,val historyPaymentId:String?=null,val historyOffline:Boolean=false,val historySavedAt:Long?=null,
    val gateway:GatewayStatus?=null,val search:String="",val filter:String="all",val selectedMember:Member?=null,
    val failure:DisplayFailure=DisplayFailure.NONE,
    val readbackRequired:Boolean=false,
    val pending:Boolean=false,val configurationRequired:Boolean=false,val offline:Boolean=false,
    val commandNotice:String?=null,
    val routeId:String?=null,val listIndex:Int=0,val listOffset:Int=0,val savedAt:Long?=null,
    val listRestoration:ListRestoreStop?=null,
    val sheetId:String?=null,val panelDepth:Int=0,
    val allocationQuery:String="",val draft:Map<String,String> = emptyMap(),val draftDirty:Boolean=false,val discardRequested:Boolean=false,
)
/** Route-aware projection of real ViewModel state. No side effects or provider calls. */
fun UiState.presentation(gate:ScreenGate,now:Long):ScreenPresentation {
    val loaded=when(route){
        Route.LOGIN->false;Route.HOME->home!=null;Route.PAYMENTS->payments!=null
        Route.PAYMENT->payment!=null;Route.MEMBERS->members!=null
        Route.MEMBER->member!=null&&ledger!=null;Route.SMS->messages!=null;Route.SETTINGS->operator!=null
    }
    val count=when(route){
        Route.PAYMENTS->payments?.items?.size?:0;Route.MEMBERS->members?.items?.size?:0
        Route.SMS->messages?.items?.size?:0;else->if(loaded)1 else 0
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
class BuriViewModel(app:Application,private val checkpoints:NavigationCheckpointStore,
    private val clock:()->Long
):AndroidViewModel(app),BuriController{
    // Keep the public Application-only constructor required by Android's ViewModel factory.
    constructor(app:Application):this(app,AndroidNavigationCheckpointStore(app),{System.currentTimeMillis()})
    constructor(app:Application,clock:()->Long):this(app,AndroidNavigationCheckpointStore(app),clock)
    private val checkpointLock=Any()
    private val checkpointEpoch=java.util.concurrent.atomic.AtomicLong(0)
    private var checkpointJob:Job?=null
    /** Best-effort UI convenience only; never writes a command or extends data/session freshness. */
    private fun checkpointNavigation(debounce:Boolean=false){
        val o=state.operator?:return
        if(state.route==Route.LOGIN||state.busy||screenGate!=ScreenGate.OPEN)return
        val bookmark=NavigationCheckpoint(o.id,BuildConfig.BURI_GROUP_ID,clock(),state.route,state.routeId,
            state.search,state.filter,state.listIndex,state.listOffset)
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
        val decision=ScreenRestoration.decide(saved,o,BuildConfig.BURI_GROUP_ID,clock(),BuildConfig.IS_GATEWAY,gateway.bound(),journal)
        // No data, panel, credential, beneficiary, draft or command is reconstructed from the bookmark.
        return UiState(operator=o.takeUnless{decision.route==Route.LOGIN},route=decision.route,routeId=decision.routeId,
            search=decision.query,filter=decision.filter,listIndex=decision.index,listOffset=decision.offset,
            busy=true,pending=decision.pending)
    }

    private var exposureJob:Job?=null
    private var lifecycleObserved=false
    private var foreground by mutableStateOf(true)
    private var needsSessionCheck by mutableStateOf(false)
    private var sessionChecking by mutableStateOf(false)
    private var visibleExpired by mutableStateOf(false)
    private var resumeQueued=false
    private data class PendingExport(val operatorId:String,val memberId:String,val requestedAt:Long,val write:(String)->Unit)
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
    override val screenGate:ScreenGate get()=when {
        !foreground -> ScreenGate.BACKGROUND
        state.operator==null -> ScreenGate.OPEN
        sessionChecking -> ScreenGate.CHECKING
        needsSessionCheck -> ScreenGate.REVALIDATE
        visibleExpired -> ScreenGate.STALE
        else -> ScreenGate.OPEN
    }
    /** Called by LifecycleResumeEffect. Does not cancel a dispatched operation. */
    fun onBackground(){
        checkpointNavigation()
        lifecycleObserved=true;foreground=false;needsSessionCheck=true;resumeQueued=true
        exposureJob?.cancel();exposureJob=null
    }
    fun onForeground(){
        lifecycleObserved=true;foreground=true;needsSessionCheck=true;resumeQueued=true
        try{gateway.start()}catch(_:Exception){/* Gateway queue is independent of operator UI. */}
        startExposureChecks()
        drainResumeCheck()
    }
    private fun drainResumeCheck(){
        if(!foreground||!resumeQueued||state.busy)return
        resumeQueued=false
        if(state.operator!=null)refreshSession() else needsSessionCheck=false
    }
    /** Evaluated while resumed, also synchronously before accepting any user action. */
    fun checkVisibleFreshness(){
        if(!lifecycleObserved||!foreground||state.operator==null)return
        if(clock()>=state.operator!!.expiresAt)needsSessionCheck=true
        if(visibleRecordsExpired(clock()))visibleExpired=true
    }
    private fun visibleRecordsExpired(now:Long):Boolean {
        val base=when(state.route){
            Route.HOME->state.home!=null
            Route.PAYMENTS->state.payments!=null
            Route.MEMBERS->state.members!=null
            Route.PAYMENT->state.payment!=null
            Route.MEMBER->state.member!=null||state.ledger!=null
            Route.SMS->state.messages!=null
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

    override var state by mutableStateOf(UiState(pending=true));private set
    override val presentation:ScreenPresentation get()=state.presentation(screenGate,clock())
    private val views=ViewMemory<UiState>()
    private var initialDraft:Map<String,String> = emptyMap()
    private data class PanelFrame(val value:UiState,val initialDraft:Map<String,String>)
    private val panels=mutableListOf<PanelFrame>()
    private var afterDiscard:(()->Unit)?=null
    private fun clearPanels(){panels.clear();initialDraft=emptyMap();afterDiscard=null}
    private fun panelAllowed(sheet:Sheet?):Boolean=when(sheet){
        Sheet.STAFF,Sheet.STAFF_EDIT,Sheet.REMOVE_STAFF,Sheet.AUDIT->hasAccess(Capability.STAFF)
        Sheet.RAW->hasAccess(Capability.SMS)
        Sheet.GATEWAY->BuildConfig.IS_GATEWAY&&state.operator?.role==Role.ADMIN
        Sheet.ENROLL->hasAccess(Capability.ENROLL)
        Sheet.ALLOCATE->hasAccess(Capability.ALLOCATE)
        else->state.operator!=null
    }
    private fun dismissPanel(){
        val parent=if(panels.isEmpty())null else panels.removeAt(panels.lastIndex)
        if(parent!=null&&panelAllowed(parent.value.sheet)){
            initialDraft=parent.initialDraft
            state=parent.value.copy(operator=state.operator,busy=false,pending=state.pending,failure=state.failure,
                offline=state.offline||parent.value.offline,error=null,discardRequested=false,panelDepth=panels.size)
        }else{
            clearPanels();state=state.copy(sheet=null,sheetId=null,panelDepth=0,draft=emptyMap(),draftDirty=false,
                discardRequested=false,selectedMember=null,selectedStaff=null,raw=null,error=null)
        }
    }
    /** Discard UI copies after a contradictory response; retain context, drafts and journal warnings.
     * Parent frames are fenced too, so closing a sheet cannot resurrect its old records.
     */
    private fun withoutRecords(value:UiState)=value.copy(home=null,payments=null,members=null,ledger=null,
        payment=null,member=null,messages=null,raw=null,staff=null,selectedStaff=null,audit=null,history=null,
        historyPaymentId=null,gateway=null,selectedMember=null,savedAt=null,panelSavedAt=null,historySavedAt=null,
        readbackRequired=true)
    private fun quarantineRecords(){
        views.invalidateRecords()
        for(i in panels.indices)panels[i]=panels[i].copy(value=withoutRecords(panels[i].value))
        state=withoutRecords(state)
    }
    private fun key(route:Route=state.route,id:String?=state.routeId)=route.name+":"+(id?:"")
    private fun clearViews(){views.clear();clearPanels();pendingExport=null;forgetCheckpoint()}
    private fun rememberedContext(value:UiState)=UiState(operator=state.operator,route=value.route,routeId=value.routeId,
        search=value.search,filter=value.filter,listIndex=value.listIndex,listOffset=value.listOffset,
        pending=state.pending,busy=true,readbackRequired=value.readbackRequired)
    private fun reusable(value:UiState)=!value.readbackRequired&&SnapshotFreshness.reusable(value.savedAt,clock())

    override fun listPosition(route:Route,id:String?,index:Int,offset:Int){if(!state.busy&&screenGate==ScreenGate.OPEN&&state.route==route&&state.routeId==id&&index in 0..100_000&&offset in 0..100_000){state=state.copy(listIndex=index,listOffset=offset);checkpointNavigation(debounce=true)}}
    override fun editDraft(key:String,value:String){
        if(state.busy||key !in setOf("name","phone","note","query","enroll","allocate"))return
        val maximum=when(key){"name"->100;"note"->500;"phone"->40;"query"->80;else->5}
        val next=state.draft+(key to value.take(maximum))
        state=state.copy(draft=next,draftDirty=state.selectedMember!=null||next.any{(k,v)->v!=(initialDraft[k]?:"")})
    }
    override fun discardDraft(){if(!state.busy){val next=afterDiscard;afterDiscard=null;dismissPanel();checkVisibleFreshness();next?.invoke()}}
    override fun keepDraft(){afterDiscard=null;state=state.copy(discardRequested=false)}
    private var generation=0
    private var actionJob:Job?=null
    private var repository:NativeRepository?=null
    private val managedSessionHost=app as? ManagedSessionHost
    val gateway=GatewayFactory.create(app)
    private var install:DeviceProvisioning?=null
    val installationId get()=install?.installationId.orEmpty()
    init {
        try {
            install=DeviceProvisioning(app,GatewayFactory.installationId(app))
            if(BuildConfig.BURI_GROUP_ID.isBlank())throw ContractFailure("configuration_required")
            val managed=managedSessionHost?.managedSessionTokenProvider
            val api=if(managed==null)ApiClient(BuildConfig.BURI_API_ORIGIN,install!!.installationId,BuildConfig.BURI_API_PATH_PREFIX){install!!.token()}
                else ApiClient(BuildConfig.BURI_API_ORIGIN,install!!.installationId,managed,BuildConfig.BURI_API_PATH_PREFIX){install!!.token()}
            repository=NativeRepository(app,api,BuildConfig.BURI_GROUP_ID)
            work{val o=io{repo().restore()};state=if(o==null)UiState(busy=true,pending=io{journalKnowledge()!=JournalKnowledge.CLEAR}) else restoredContext(o)
                if(state.operator!=null)refreshNow() else forgetCheckpoint()}
        }catch(_:Exception){state=state.copy(configurationRequired=true,error="Managed setup required.")}
    }
    private fun startExposureChecks(){
        exposureJob?.cancel()
        exposureJob=viewModelScope.launch{while(isActive&&foreground){
            delay(1_000)
            val o=state.operator
            if(o!=null&&clock()>=o.expiresAt){
                generation++;clearViews();actionJob?.cancel()
                withContext(Dispatchers.IO){repository?.clearOperator()}
                state=UiState(error="Sign in again.",pending=state.pending||state.busy);needsSessionCheck=false;visibleExpired=false
            }
            checkVisibleFreshness()
        }}
    }

    private fun repo()=repository?:throw ApiFailure("configuration_required")
    private fun journalKnowledge():JournalKnowledge = try {
        val r=repository
        if(r==null)JournalKnowledge.UNAVAILABLE else if(r.pending()==null)JournalKnowledge.CLEAR else JournalKnowledge.UNRESOLVED
    }catch(_:Exception){JournalKnowledge.UNAVAILABLE}
    override fun allows(capability:Capability)=screenGate==ScreenGate.OPEN&&hasAccess(capability)
    private fun work(bypassGate:Boolean=false,action:suspend ()->Unit){
        checkVisibleFreshness()
        if(state.busy||(!bypassGate&&screenGate!=ScreenGate.OPEN))return
        state=state.copy(busy=true,error=null,failure=DisplayFailure.NONE)
        val started=generation
        actionJob=viewModelScope.launch{
            try{action()}
            catch(e:CancellationException){throw e}
            catch(e:ApiFailure){
                if(started!=generation)throw CancellationException()
                if(e.status==401){clearViews();state=UiState(error="Sign in again.",busy=true,pending=state.pending||e.uncertain,failure=PresentationState.failure(e.code,e.uncertain))}
                else {
                    state=state.copy(error=message(e.code,e.uncertain),offline=e.status==0,failure=PresentationState.failure(e.code,e.uncertain))
                    if(state.failure==DisplayFailure.CONFLICT)quarantineRecords()
                }
            }catch(e:ContractFailure){
                if(started!=generation)throw CancellationException()
                state=if(e.code=="session_unavailable"||e.code=="session_changed"){clearViews();UiState(error="Sign in again.",busy=true,pending=state.pending)}
                    else state.copy(error=message(e.code,false),failure=PresentationState.failure(e.code))
                if(state.failure==DisplayFailure.CONFLICT)quarantineRecords()
            }catch(_:Exception){
                if(started!=generation)throw CancellationException()
                state=state.copy(error="Unable to complete. Refresh and try again.",failure=DisplayFailure.UNAVAILABLE)
            }finally{
                // Never construct a UiState copy before an IO suspension: expiry
                // during the journal read must not restore a signed-out screen.
                val pending=withContext(NonCancellable+Dispatchers.IO){journalKnowledge()!=JournalKnowledge.CLEAR}
                if(started==generation){
                    state=state.copy(busy=false,pending=pending)
                    checkVisibleFreshness()
                    drainResumeCheck()
                    drainExport()
                    checkpointNavigation()
                }
            }
        }
    }
    private suspend fun <T> io(action:()->T):T { val before=generation;val result=withContext(Dispatchers.IO){action()};if(before!=generation)throw CancellationException();return result }
    override fun login(phone:String,pin:String)=work{
        val o=io{repo().login(phone,pin)};clearViews();state=UiState(operator=o,route=Route.HOME,busy=true,pending=state.pending);refreshNow();visibleExpired=false;if(!resumeQueued)needsSessionCheck=false
    }
    override fun logout()=work(bypassGate=true){
        try{io{repo().logout()}}
        finally{
            try{io{managedSessionHost?.signOutManagedSession()}}
            finally{generation++;clearViews();needsSessionCheck=false;visibleExpired=false;resumeQueued=false;state=UiState(pending=state.pending)}
        }
    }
    fun refreshSession(){
        needsSessionCheck=true
        if(state.busy){resumeQueued=true;return}
        if(!foreground)return
        work(bypassGate=true){
            sessionChecking=true
            // Saved parent screens must be re-read too, not restored behind a child panel.
            views.invalidateRecords()
            for(i in panels.indices){val p=panels[i];panels[i]=p.copy(value=p.value.copy(savedAt=null,panelSavedAt=null,historySavedAt=null))}
            try{
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
                visibleExpired=false;needsSessionCheck=false
            }finally{sessionChecking=false}
        }
    }
    override fun navigate(route:Route,id:String?){
        checkVisibleFreshness()
        if(screenGate!=ScreenGate.OPEN)return
        if(state.busy||!Access.routeAllowed(state.operator,route,clock(),BuildConfig.IS_GATEWAY,gateway.bound()))return
        if(route in setOf(Route.PAYMENT,Route.MEMBER)&&id==null)return
        if(state.draftDirty){afterDiscard={navigate(route,id)};state=state.copy(discardRequested=true);return}
        work{
            val old=state.copy(busy=false,error=null)
            if(route!=state.route||id!=state.routeId)views.push(key(),old)
            val remembered=views.remembered(key(route,id))
            val fresh=remembered?.takeIf{views.isCurrent(it)&&reusable(it.value)}?.value
            clearPanels()
            state=(fresh?:remembered?.value?.let{rememberedContext(it)}?:UiState(operator=state.operator,route=route,routeId=id)).copy(operator=state.operator,
                busy=true,pending=state.pending,failure=DisplayFailure.NONE,sheet=null,sheetId=null,panelDepth=0,error=null,selectedMember=null,draft=emptyMap(),draftDirty=false,discardRequested=false)
            if(fresh==null)refreshNow()
        }
    }
    override fun back(){
        checkVisibleFreshness();if(state.busy||screenGate!=ScreenGate.OPEN)return
        if(state.sheet!=null){closeSheet();return}
        val previous=views.previous()
        if(previous==null){
            // Process restoration deliberately has no serialized back stack or record snapshots.
            val parent=when(state.route){Route.PAYMENT->Route.PAYMENTS;Route.MEMBER->Route.MEMBERS;else->Route.HOME}
            work{clearPanels();state=UiState(operator=state.operator,route=parent,busy=true,pending=state.pending);refreshNow()}
            return
        }
        if(!Access.routeAllowed(state.operator,previous.value.route,clock(),BuildConfig.IS_GATEWAY,gateway.bound())){clearViews();navigate(Route.HOME);return}
        work{
            views.remember(key(),state.copy(busy=false))
            val fresh=views.isCurrent(previous)&&reusable(previous.value)
            val restoredSheet=previous.value.sheet.takeIf{panelAllowed(it)}
            val restoredId=previous.value.sheetId
            state=(if(fresh)previous.value else rememberedContext(previous.value)).copy(
                operator=state.operator,busy=true,error=null,pending=state.pending,failure=DisplayFailure.NONE,
                sheet=null,sheetId=null,panelDepth=0,raw=null,staff=null,audit=null,history=null,
                selectedStaff=null,selectedMember=null,draft=emptyMap(),draftDirty=false,discardRequested=false)
            clearPanels()
            if(!fresh)refreshNow()
            if(restoredSheet!=null){
                // Evidence is re-read, never redisplayed from a remembered privileged panel.
                state=state.copy(sheet=restoredSheet,sheetId=restoredId,panelDepth=0)
                refreshPanelNow()
            }
        }
    }
    override fun openUnallocated(){
        if(state.busy||!Access.routeAllowed(state.operator,Route.PAYMENTS,clock(),BuildConfig.IS_GATEWAY,gateway.bound()))return
        work{
            views.push(key(),state.copy(busy=false,error=null))
            state=UiState(operator=state.operator,route=Route.PAYMENTS,busy=true,filter="unallocated",pending=state.pending)
            refreshNow()
        }
    }
    override fun search(value:String){
        if(state.busy||screenGate!=ScreenGate.OPEN)return
        state=state.copy(search=value.filter{!it.isISOControl()}.take(80));checkpointNavigation(debounce=true)
    }
    override fun searchSubmit()=work{state=state.copy(listIndex=0,listOffset=0);refreshNow()}
    override fun setFilter(value:String){if(state.busy||value !in NavigationCheckpoint.filters(state.route))return;state=state.copy(filter=value,sheet=null,listIndex=0,listOffset=0);searchSubmit()}
    override fun refresh(){
        checkVisibleFreshness()
        if(screenGate!=ScreenGate.OPEN){refreshSession();return}
        if(state.readbackRequired&&state.route==Route.SETTINGS){refreshSession();return}
        work{
            if(state.readbackRequired){refreshNow();if(state.sheet!=null)refreshPanelNow()}
            else if(state.sheet!=null)refreshPanelNow() else refreshNow()
        }
    }
    private suspend fun refreshPanelNow(){
        if(!panelAllowed(state.sheet))throw ApiFailure("access_denied",403)
        when(state.sheet){
            Sheet.ALLOCATE->{
                val v=io{repo().members(state.allocationQuery)}
                state=state.copy(members=v,offline=state.offline||repo().lastReadFromCache,panelSavedAt=repo().lastReadSavedAt)
                // Never silently carry a previously selected beneficiary across revalidation.
                if(sessionChecking)state=state.copy(selectedMember=null)
            }
            Sheet.STAFF->{val v=io{repo().staff()};state=state.copy(staff=v,panelSavedAt=clock())}
            Sheet.AUDIT->{val v=io{repo().audit()};state=state.copy(audit=v,panelSavedAt=clock())}
            Sheet.GATEWAY->{state=state.copy(gateway=null,panelSavedAt=null);val v=io{gateway.status()};state=state.copy(gateway=v,panelSavedAt=clock())}
            Sheet.RAW->{val id=state.sheetId?:state.raw?.id?:throw ApiFailure("record_unavailable");val v=io{repo().raw(id)};state=state.copy(raw=v,panelSavedAt=clock())}
            Sheet.HISTORY->{
                val id=state.sheetId?:state.payment?.id?:throw ApiFailure("record_unavailable")
                val value=io{repo().paymentHistory(id)}
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
    private suspend fun refreshNow(){
        when(state.route){
            Route.HOME->{val h=io{repo().home()};val cached=repo().lastReadFromCache;val saved=repo().lastReadSavedAt
                val g=if(BuildConfig.IS_GATEWAY&&state.operator?.role==Role.ADMIN)io{try{gateway.status()}catch(_:Exception){GatewayStatus(false,false,null,-1,null,null,null,"queue_unavailable")}}else null
                state=state.copy(home=h,gateway=g,offline=cached,savedAt=saved,readbackRequired=state.readbackRequired&&cached)}
            Route.PAYMENTS->{val v=io{repo().payments(state.search,state.filter)}
                val r=restorePages(v,{it.id}){cursor->repo().payments(state.search,state.filter,cursor)}
                state=state.copy(payments=r.page,offline=r.offline,savedAt=r.savedAt,readbackRequired=state.readbackRequired&&r.offline,
                    listIndex=r.decision.index,listOffset=r.decision.offset,listRestoration=r.decision.stop)}
            Route.MEMBERS->{val v=io{repo().members(state.search)}
                val r=restorePages(v,{it.id}){cursor->repo().members(state.search,cursor)}
                state=state.copy(members=r.page,offline=r.offline,savedAt=r.savedAt,readbackRequired=state.readbackRequired&&r.offline,
                    listIndex=r.decision.index,listOffset=r.decision.offset,listRestoration=r.decision.stop)}
            Route.SMS->{if(!hasAccess(Capability.SMS))throw ApiFailure("access_denied",403);val v=io{repo().sms(state.search,filter=state.filter)}
                val r=restorePages(v,{it.id},cacheable=false,firstOffline=false,firstSavedAt=clock()){cursor->repo().sms(state.search,cursor,state.filter)}
                state=state.copy(messages=r.page,offline=r.offline,savedAt=r.savedAt,readbackRequired=false,
                    listIndex=r.decision.index,listOffset=r.decision.offset,listRestoration=r.decision.stop)}
            Route.PAYMENT->{val id=state.routeId?:state.payment?.id?:return;val v=io{repo().payment(id)};state=state.copy(payment=v,offline=repo().lastReadFromCache,savedAt=repo().lastReadSavedAt,readbackRequired=state.readbackRequired&&repo().lastReadFromCache)}
            Route.MEMBER->{val id=state.routeId?:state.member?.id?:return
                val member=io{repo().member(id)};val memberCached=repo().lastReadFromCache;val memberSaved=repo().lastReadSavedAt
                val ledger=io{repo().ledger(id)}
                val r=restorePages(ledger,{it.id},firstOffline=memberCached||repo().lastReadFromCache,
                    firstSavedAt=SnapshotFreshness.oldest(clock(),memberSaved,repo().lastReadSavedAt)){cursor->repo().ledger(id,cursor)}
                state=state.copy(member=member,ledger=r.page,offline=r.offline,savedAt=r.savedAt,
                    readbackRequired=state.readbackRequired&&r.offline,
                    listIndex=r.decision.index,listOffset=r.decision.offset,listRestoration=r.decision.stop)}
            else->Unit
        }
    }
    override fun more()=work{
        state=state.copy(listRestoration=null)
        when(state.sheet){
            Sheet.HISTORY->{state.history?.let{old->old.nextCursor?.let{c->
                val id=state.historyPaymentId?:throw ApiFailure("record_unavailable")
                val next=io{repo().paymentHistory(id,c)}
                state=state.copy(history=PageIntegrity.append(old,next){it.id},
                    historyOffline=state.historyOffline||repo().lastReadFromCache,
                    historySavedAt=SnapshotFreshness.oldest(clock(),state.historySavedAt,repo().lastReadSavedAt))
            }};return@work}
            Sheet.STAFF->{state.staff?.let{old->old.nextCursor?.let{c->val next=io{repo().staff(c)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(staff=PageIntegrity.append(old,next){it.id})}};return@work}
            Sheet.AUDIT->{state.audit?.let{old->old.nextCursor?.let{c->val next=io{repo().audit(c)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(audit=PageIntegrity.append(old,next){it.id})}};return@work}
            Sheet.ALLOCATE->{state.members?.let{old->old.nextCursor?.let{c->val next=io{repo().members(state.allocationQuery,c)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(members=PageIntegrity.append(old,next){it.id},offline=state.offline||repo().lastReadFromCache,panelSavedAt=SnapshotFreshness.oldest(clock(),state.panelSavedAt,repo().lastReadSavedAt))}};return@work}
            else->Unit
        }
        when(state.route){
            Route.PAYMENTS->state.payments?.let{old->old.nextCursor?.let{c->val next=io{repo().payments(state.search,state.filter,c)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(payments=PageIntegrity.append(old,next){it.id},offline=state.offline||repo().lastReadFromCache,savedAt=SnapshotFreshness.oldest(clock(),state.savedAt,repo().lastReadSavedAt))}}
            Route.MEMBERS->state.members?.let{old->old.nextCursor?.let{c->val next=io{repo().members(state.search,c)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(members=PageIntegrity.append(old,next){it.id},offline=state.offline||repo().lastReadFromCache,savedAt=SnapshotFreshness.oldest(clock(),state.savedAt,repo().lastReadSavedAt))}}
            Route.MEMBER->state.ledger?.let{old->old.nextCursor?.let{c->val next=io{repo().ledger(state.member!!.id,c)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(ledger=PageIntegrity.append(old,next){it.id},offline=state.offline||repo().lastReadFromCache,savedAt=SnapshotFreshness.oldest(clock(),state.savedAt,repo().lastReadSavedAt))}}
            Route.SMS->state.messages?.let{old->old.nextCursor?.let{c->val next=io{repo().sms(state.search,c,state.filter)};checkContract(old.revision==next.revision,"cursor_stale");state=state.copy(messages=PageIntegrity.append(old,next){it.id},offline=false)}}
            else->Unit
        }
    }
    override fun openSheet(sheet:Sheet,id:String?){
        if(state.busy||!panelAllowed(sheet))return
        if(sheet==Sheet.RAW&&id==null)return
        // Re-opening a panel (e.g. returning from Android permissions) refreshes it,
        // without replacing its draft or creating a second back-stack entry.
        if(state.sheet==sheet&&state.sheetId==id){refresh();return}
        if(state.draftDirty&&sheet!=Sheet.REMOVE_STAFF){
            afterDiscard={openSheet(sheet,id)};state=state.copy(discardRequested=true);return
        }
        work{
            if(panels.size>=8)throw ApiFailure("navigation_limit")
            panels.add(PanelFrame(state.copy(busy=false,error=null),initialDraft.toMap()))
            initialDraft=emptyMap()
            state=state.copy(sheet=sheet,sheetId=if(sheet==Sheet.HISTORY)id?:state.payment?.id else id,
                panelDepth=panels.size,error=null,selectedMember=null,raw=null,panelSavedAt=state.panelSavedAt,
                history=null,historyPaymentId=null,historyOffline=false,historySavedAt=null,
                allocationQuery="",draft=emptyMap(),draftDirty=false,discardRequested=false)
            if(sheet==Sheet.STAFF_EDIT){
                val selected=state.staff?.items?.find{it.id==id}
                state=state.copy(selectedStaff=null)
                if(id!=null&&selected==null)throw ApiFailure("record_unavailable")
                initialDraft=mapOf("name" to selected?.name.orEmpty(),"phone" to selected?.phone.orEmpty(),
                    "enroll" to (selected?.capabilities?.contains(Capability.ENROLL.key)?:false).toString(),
                    "allocate" to (selected?.capabilities?.contains(Capability.ALLOCATE.key)?:false).toString())
                state=state.copy(selectedStaff=selected,draft=initialDraft)
            }
            refreshPanelNow()
        }
    }
    override fun closeSheet(){checkVisibleFreshness();if(screenGate!=ScreenGate.OPEN)return;if(!state.busy){if(state.draftDirty)state=state.copy(discardRequested=true) else discardDraft()}}
    override fun selectMember(member:Member){checkVisibleFreshness();if(screenGate==ScreenGate.OPEN&&member.active&&!state.busy)state=state.copy(selectedMember=member,draftDirty=true)}
    override fun allocationSearch(q:String)=work{val v=io{repo().members(q)};state=state.copy(members=v,allocationQuery=q,offline=state.offline||repo().lastReadFromCache,panelSavedAt=repo().lastReadSavedAt)}
    /** Drop records and consumed form state before any post-command read can fail.
     * The durable journal is owned by the repository and is never edited here. */
    private fun invalidateCommandViews(notice:String?=null){
        views.invalidateRecords();clearPanels();pendingExport=null
        val old=state
        state=UiState(operator=old.operator,route=old.route,routeId=old.routeId,
            search=old.search,filter=old.filter,listIndex=old.listIndex,listOffset=old.listOffset,
            busy=true,pending=old.pending,commandNotice=notice)
    }
    /** A transport/cleanup failure may follow a committed server-side operation.
     * Invalidate presentation without interpreting uncertainty as rejection. */
    private suspend fun command(action:()->JSONObject):JSONObject {
        state=state.copy(commandNotice=null)
        try{
            val result=io(action)
            invalidateCommandViews("The original action committed. Refresh the records before starting another action; do not repeat it.")
            return result
        }catch(e:CancellationException){throw e}
        catch(e:Exception){
            val changed=e is ApiFailure&&e.code=="operation_financially_changed"
            val unresolved=try{io{repo().pending()!=null}}catch(cancel:CancellationException){throw cancel}catch(_:Exception){true}
            if(changed||unresolved)invalidateCommandViews(if(changed)
                "The original action committed, but its financial effect was reversed or corrected. Review the current ledger; do not repeat the original action."
                else null)
            throw e
        }
    }
    private fun requireNoUnresolvedCommand(){
        if(state.pending||repository?.pending()!=null)throw ApiFailure("pending_operation_requires_resolution",409)
        if(state.readbackRequired||!state.presentation(screenGate,clock()).showRecords)throw ApiFailure("fresh_records_required",409)
    }
    override fun allocate(note:String)=work{
        requireNoUnresolvedCommand()
        if(!allows(Capability.ALLOCATE)||state.offline)throw ApiFailure("access_denied",403)
        val p=state.payment?:throw ApiFailure("record_unavailable");val m=state.selectedMember?:throw ApiFailure("member_unavailable")
        command{repo().allocate(p,m,note)};val v=io{repo().payment(p.id)};state=state.copy(sheet=null,sheetId=null,panelDepth=0,selectedMember=null,payment=v,home=null,draft=emptyMap(),draftDirty=false,offline=repo().lastReadFromCache,savedAt=repo().lastReadSavedAt)
    }
    override fun enroll(name:String,phone:String)=work{
        requireNoUnresolvedCommand()
        if(!allows(Capability.ENROLL)||state.offline)throw ApiFailure("access_denied",403)
        checkContract(Presentation.validName(name),"invalid_name");command{repo().enroll(name,phone)};state=state.copy(sheet=null,sheetId=null,panelDepth=0,draft=emptyMap(),draftDirty=false);refreshNow()
    }
    override fun changePin(current:String,next:String,confirm:String)=work{
        requireNoUnresolvedCommand()
        var confirmed=false
        try{io{repo().changePin(current,next,confirm)};confirmed=true}
        finally{
            // Repository clears the session after dispatch, including a lost response.
            // Validation errors before dispatch preserve the current operator instead.
            if(repository?.current()==null){generation++;clearViews();state=UiState(error=if(confirmed)"Passcode changed. Sign in again." else "Passcode change not confirmed. Sign in again.",pending=state.pending||!confirmed,failure=if(confirmed)DisplayFailure.NONE else DisplayFailure.UNCERTAIN)}
        }
    }
    override fun saveStaff(name:String,phone:String,pin:String,enroll:Boolean,allocate:Boolean)=work{
        requireNoUnresolvedCommand()
        if(!allows(Capability.STAFF)||state.offline)throw ApiFailure("access_denied",403)
        checkContract(Presentation.validName(name),"invalid_name")
        val existing=state.selectedStaff
        if(state.sheetId!=null&&existing==null)throw ApiFailure("record_unavailable")
        val body=JSONObject().put("action",if(existing==null)"create" else "edit").put("name",name.trim()).put("phone",Values.phone(phone))
        if(existing!=null)body.put("id",existing.id).put("expectedVersion",existing.version)
        if(pin.isNotBlank()||existing==null)body.put("pin",Values.pin(pin))
        val caps=JSONArray().put(Capability.READ.key);if(enroll)caps.put(Capability.ENROLL.key);if(allocate)caps.put(Capability.ALLOCATE.key);body.put("capabilities",caps)
        command{repo().staffAction(body)};val staff=io{repo().staff()};state=state.copy(sheet=Sheet.STAFF,sheetId=null,panelDepth=0,staff=staff,panelSavedAt=clock(),selectedStaff=null,draft=emptyMap(),draftDirty=false)
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
    override fun pair(code:String)=work{if(!BuildConfig.IS_GATEWAY||state.operator?.role!=Role.ADMIN)throw ApiFailure("access_denied",403);io{gateway.pair(code)};val updated=io{gateway.status()};state=state.copy(gateway=updated,panelSavedAt=clock())}
    override fun setPaused(value:Boolean)=work{
        if(!allows(Capability.GATEWAY))throw ApiFailure("access_denied",403)
        val current=io{gateway.status()};val diagnosis=GatewayHealth.describe(current)
        if(if(value)!diagnosis.canPause else !diagnosis.canResume)throw ApiFailure("gateway_action_unavailable",409)
        io{gateway.setPaused(value)}
        val updated=io{gateway.status()};state=state.copy(gateway=updated,panelSavedAt=clock())
    }
    override fun retry()=work{
        val outcome=io{repo().reconcilePending()}
        if(outcome.getString("state")=="pending"){
            state=state.copy(error="Still awaiting an authoritative outcome. Do not repeat this action; contact the administrator if it remains unresolved.",failure=DisplayFailure.UNCERTAIN)
        }else{
            // Capture the verified outcome before a separate record refresh can fail.
            // Clearing panel bookkeeping alone does not clear the visible draft/selection.
            val notice=when {
                outcome.getString("state")=="rejected"->"The previous action was rejected. Review the records before starting a different action."
                outcome.optString("financialState") in setOf("reversed","corrected")->"The original action committed, but its financial effect was reversed or corrected. Review the current ledger; do not repeat the original action."
                else->"The original action committed. Refresh the records before starting another action; do not repeat it."
            }
            invalidateCommandViews(notice);refreshNow()
            // Retain the historical error text for rejection consumers; the independent
            // notice remains visible even when readback fails or a later action clears error.
            if(outcome.getString("state")=="rejected")state=state.copy(error=notice,failure=DisplayFailure.REJECTED)
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
        uncertain->"Outcome not confirmed. Check before retrying."
        code=="gateway_action_unavailable"->"Refresh the receiving-phone status and follow the displayed recovery steps."
        code=="fresh_records_required"->"These records have expired. Reconnect and refresh before continuing."
        code=="invalid_name"->"Use a name of 2–100 characters without control characters."
        code=="invalid_note"->"Use an identification note of 8–500 characters without control characters."
        code.startsWith("invalid_history")||code in setOf("invalid_page","invalid_api_response")->"Received inconsistent records. Refresh or contact support."
        code=="history_limit"->"This history is too large for the phone. Contact an administrator for a full extract."
        code=="record_unavailable"->"This record is unavailable. Go back or refresh."
        code=="invalid_credentials"->"Phone or passcode is incorrect."
        code=="invalid_phone"->"Enter a valid phone number."
        code=="invalid_passcode"->"Enter four digits."
        code=="passcodes_do_not_match"->"Passcodes do not match."
        code=="try_again_later"->"Too many attempts. Try again later."
        code in setOf("configuration_required","managed_setup_required")->"Managed setup required. Contact your admin."
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
