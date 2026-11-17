package rw.ikanisa.burimunsi.retryfreshnesstests
import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.data.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

private class MemoryStore:NavigationCheckpointStore {
    var value:String?=null
    override fun read()=value
    override fun write(value:String){this.value=value}
    override fun clear(){value=null}
}
fun main()=runBlocking {
    var checks=0
    fun ck(label:String,ok:Boolean){check(ok){label};checks++;println("PASS $label")}
    suspend fun idle(vm:BuriViewModel){withTimeout(10_000){while(vm.state.busy)delay(2)}}
    val now=System.currentTimeMillis()
    fun reset(){
        Fixture.pendingFlag=false;Fixture.journalFailure=false;Fixture.restoreSignedOut=false;Fixture.ownerId="operator"
        Fixture.readFailure=null;Fixture.readEmpty=false;Fixture.cached=false;Fixture.role=Role.ADMIN
        Fixture.recordSavedAt=now;Fixture.sessionFailure=null;Fixture.refreshedRole=null;Fixture.refreshedCaps=null
        Fixture.homeBarrier=null;Fixture.paymentsBarrier=null;Fixture.paymentsEntered=null;Fixture.missingReadTimestamp=false
    }
    reset()
    val vm=BuriViewModel(Application(),MemoryStore()){now};idle(vm)
    vm.navigate(Route.PAYMENTS);idle(vm)
    ck("initial list is readable",vm.presentation.showRecords)
    Fixture.pendingFlag=true;Fixture.readFailure=ApiFailure("cursor_stale",409)
    vm.refresh();idle(vm)
    ck("conflicting list is hidden and unresolved retained",!vm.presentation.showRecords&&vm.state.pending)
    Fixture.readFailure=null;Fixture.paymentsBarrier=CountDownLatch(1);Fixture.paymentsEntered=CountDownLatch(1)
    vm.refresh()
    ck("read retry entered repository",Fixture.paymentsEntered!!.await(5,TimeUnit.SECONDS))
    try {
        ck("retry never re-exposes conflicting records while waiting",!vm.presentation.showRecords)
        ck("waiting retry preserves original command warning",vm.presentation.unresolvedWarning&&Fixture.pendingFlag)
    } finally {Fixture.paymentsBarrier!!.countDown()}
    idle(vm);Fixture.paymentsBarrier=null;Fixture.paymentsEntered=null
    ck("fresh online read can display records without resolving command",vm.presentation.showRecords&&vm.state.pending)
    ck("read retry did not submit or reconcile commands",Fixture.mutations==0&&Fixture.enrollMutations==0&&Fixture.reconciles==0)
    vm.viewModelScope.cancel()

    for(kind in listOf("older","unknown","future","expired")){
        reset();val v=BuriViewModel(Application(),MemoryStore()){now};idle(v);v.navigate(Route.PAYMENTS);idle(v)
        when(kind){
            "older"->Fixture.recordSavedAt=now-100_000
            "unknown"->Fixture.missingReadTimestamp=true
            "future"->Fixture.recordSavedAt=now+1
            "expired"->Fixture.recordSavedAt=now-SnapshotFreshness.TTL_MS-1
        }
        v.more();idle(v)
        if(kind=="older")ck("pagination retains oldest timestamp",v.state.savedAt==now-100_000)
        else ck("$kind appended timestamp cannot become fresh",!v.presentation.showRecords&&!v.presentation.mayStartCommand)
        v.viewModelScope.cancel()
    }

    reset()
    val cacheVm=BuriViewModel(Application(),MemoryStore()){now};idle(cacheVm);cacheVm.navigate(Route.PAYMENTS);idle(cacheVm)
    Fixture.readFailure=ApiFailure("cursor_stale",409);cacheVm.refresh();idle(cacheVm)
    Fixture.readFailure=null;Fixture.cached=true;cacheVm.refresh();idle(cacheVm)
    ck("cache fallback does not lift conflict readback guard",cacheVm.state.readbackRequired&&!cacheVm.presentation.showRecords)
    cacheVm.more();idle(cacheVm)
    ck("another action cannot lift quarantine",cacheVm.state.readbackRequired&&!cacheVm.presentation.showRecords)
    val enrollBefore=Fixture.enrollMutations
    cacheVm.enroll("Example name","0780000001");idle(cacheVm)
    ck("quarantine blocks a direct mutation call",Fixture.enrollMutations==enrollBefore)
    Fixture.cached=false;cacheVm.refresh();idle(cacheVm)
    ck("authoritative route refresh clears quarantine",!cacheVm.state.readbackRequired&&cacheVm.presentation.showRecords)
    cacheVm.viewModelScope.cancel()

    reset()
    val parentVm=BuriViewModel(Application(),MemoryStore()){now};idle(parentVm)
    parentVm.navigate(Route.PAYMENT,"tx-1");idle(parentVm);parentVm.openSheet(Sheet.HISTORY);idle(parentVm)
    Fixture.historyRevision="changed";parentVm.more();idle(parentVm)
    ck("invalid history clears route and panel copies",parentVm.state.history==null&&parentVm.state.payment==null&&parentVm.state.readbackRequired)
    parentVm.closeSheet()
    ck("closing panel cannot resurrect a quarantined parent",parentVm.state.sheet==null&&parentVm.state.payment==null&&parentVm.state.readbackRequired&&!parentVm.presentation.showRecords)
    Fixture.historyRevision="history-v1";parentVm.refresh();idle(parentVm)
    ck("readback recovers exact parent identity",parentVm.state.payment?.id=="tx-1"&&parentVm.presentation.showRecords)
    parentVm.viewModelScope.cancel()

    reset()
    val home=Home(1,1,1,0,emptyList(),"at")
    val panelBase=UiState(operator=Fixture.operator(),route=Route.HOME,home=home,savedAt=now,
        sheet=Sheet.ALLOCATE,members=Fixture.page(listOf(Fixture.member)),panelSavedAt=now)
    for(timestamp in listOf<Long?>(null,now+1,now-SnapshotFreshness.TTL_MS-1)){
        val projected=panelBase.copy(panelSavedAt=timestamp).presentation(ScreenGate.OPEN,now)
        ck("panel timestamp $timestamp cannot borrow route freshness",!projected.showRecords&&!projected.mayStartCommand)
    }
    ck("fresh panel and route can display together",panelBase.presentation(ScreenGate.OPEN,now).showRecords)
    val pendingPanel=panelBase.copy(pending=true,panelSavedAt=null).presentation(ScreenGate.OPEN,now)
    ck("stale panel retains unresolved warning",pendingPanel.unresolvedWarning&&!pendingPanel.showRecords)
    ck("exact TTL boundary preserved",SnapshotFreshness.oldest(now,now-SnapshotFreshness.TTL_MS,now)==now-SnapshotFreshness.TTL_MS)
    ck("expired original clock retained rather than renewed",SnapshotFreshness.oldest(now,now-SnapshotFreshness.TTL_MS-1,now)==now-SnapshotFreshness.TTL_MS-1)
    ck("missing constituent not discarded",SnapshotFreshness.oldest(now,null,now)==null)
    ck("future constituent not hidden by older clock",SnapshotFreshness.oldest(now,now-1,now+1)==null)
    ck("negative constituent refused",SnapshotFreshness.oldest(now,-1,now)==null)
    ck("empty provenance is not current",SnapshotFreshness.oldest(now)==null)
    reset();Fixture.recordSavedAt=now-100_000
    val memberVm=BuriViewModel(Application(),MemoryStore()){now};idle(memberVm)
    memberVm.navigate(Route.MEMBER,"member-1");idle(memberVm)
    Fixture.recordSavedAt=now;memberVm.setMemberActive(false);idle(memberVm)
    // A04 invalidates consumed financial views before optional readback. There is
    // no retained ledger whose old clock can be renewed by this member-only read.
    ck("membership update discards old transactions before publishing fresh member",memberVm.state.memberTransactions==null&&memberVm.state.savedAt==now&&memberVm.state.member?.id=="member-1")
    memberVm.viewModelScope.cancel()
    println("RESULT: $checks retry/freshness actual ViewModel checks passed; isolated repository and platform doubles only.")
}
