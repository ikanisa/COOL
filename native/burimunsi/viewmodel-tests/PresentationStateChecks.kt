package rw.ikanisa.burimunsi.presentationstatetests
import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.data.*
import app.cool.mobile.BuildConfig

private class MemoryStore(var value:String?=null):NavigationCheckpointStore {
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
        Fixture.readFailure=null;Fixture.readEmpty=false;Fixture.pinUncertain=false;Fixture.recoveryFailure=null;Fixture.resolveOnCheck=false
        Fixture.cached=false;Fixture.role=Role.ADMIN;Fixture.recordSavedAt=now;Fixture.sessionFailure=null
        Fixture.refreshedRole=null;Fixture.refreshedCaps=null;Fixture.homeBarrier=null;Fixture.outcomeState="committed"
    }
    reset()
    val bookmark=NavigationCheckpoint("operator",BuildConfig.BURI_GROUP_ID,now,Route.PAYMENTS,query="old",filter="unallocated",index=3)
    Fixture.pendingFlag=true
    val restored=BuriViewModel(Application(),MemoryStore(bookmark.encode())){now};idle(restored)
    ck("restoration retains original unresolved command",restored.state.pending&&Fixture.pendingFlag&&Fixture.reconciles==0&&Fixture.mutations==0)
    ck("actual restored projection is uncertain",restored.presentation.state==DisplayState.UNCERTAIN&&!restored.presentation.mayStartCommand)
    restored.logout();idle(restored)
    ck("logout clears data without clearing unresolved warning",restored.state.route==Route.LOGIN&&restored.state.payments==null&&restored.state.pending)
    Fixture.ownerId="different-operator";restored.login("0780000001","2468");idle(restored)
    ck("changed operator does not erase unresolved journal",restored.state.operator?.id=="different-operator"&&restored.state.pending)
    val before=Fixture.enrollMutations;restored.enroll("Another Member","0780000002");idle(restored)
    ck("new operator cannot bypass unresolved guard",Fixture.enrollMutations==before&&Fixture.pendingFlag)
    Fixture.recoveryFailure=ApiFailure("operation_recovery_denied",403);restored.retry();idle(restored)
    ck("denied status recovery remains uncertain",restored.state.pending&&restored.presentation.state==DisplayState.UNCERTAIN&&Fixture.pendingFlag)
    Fixture.recoveryFailure=null;Fixture.outcomeState="pending";restored.retry();idle(restored)
    ck("pending recovery neither replays nor clears",restored.state.pending&&Fixture.mutations==0&&Fixture.enrollMutations==before)
    Fixture.outcomeState="committed";Fixture.resolveOnCheck=true;restored.retry();idle(restored)
    ck("only repository-confirmed resolution clears warning",!restored.state.pending&&!Fixture.pendingFlag&&restored.presentation.state==DisplayState.CONTENT)
    restored.viewModelScope.cancel()

    reset();Fixture.journalFailure=true
    val failedStore=BuriViewModel(Application(),MemoryStore(bookmark.encode())){now};idle(failedStore)
    ck("failed journal read is not empty",failedStore.state.pending&&failedStore.presentation.state==DisplayState.UNCERTAIN)
    val enrolls=Fixture.enrollMutations;failedStore.enroll("Example Member","0780000002");idle(failedStore)
    ck("unreadable journal blocks dispatch",Fixture.enrollMutations==enrolls&&failedStore.state.pending)
    failedStore.logout();idle(failedStore)
    ck("failed journal survives sign-out",failedStore.state.pending&&failedStore.state.operator==null)
    failedStore.viewModelScope.cancel()

    reset();Fixture.pinUncertain=true
    val pin=BuriViewModel(Application(),MemoryStore()){now};idle(pin)
    pin.changePin("2468","8642","8642");idle(pin)
    ck("lost PIN response preserves pending across generation change",pin.state.pending&&pin.state.operator==null&&pin.state.failure==DisplayFailure.UNCERTAIN&&Fixture.pendingFlag)
    pin.login("0780000001","8642");idle(pin)
    ck("relogin cannot clear uncertain PIN operation",pin.state.pending&&pin.presentation.state==DisplayState.UNCERTAIN)
    pin.viewModelScope.cancel()

    reset();Fixture.pendingFlag=true
    val denied=BuriViewModel(Application(),MemoryStore()){now};idle(denied)
    Fixture.sessionFailure=ApiFailure("invalid_session",401);denied.refreshSession();idle(denied)
    ck("401 keeps pending without protected records",denied.state.pending&&denied.state.operator==null&&denied.state.home==null)
    denied.viewModelScope.cancel()

    reset()
    val view=BuriViewModel(Application(),MemoryStore()){now};idle(view)
    view.navigate(Route.PAYMENTS);idle(view)
    ck("loaded list projects content",view.presentation.state==DisplayState.CONTENT)
    Fixture.readEmpty=true;view.refresh();idle(view)
    ck("successful zero rows projects empty",view.presentation.state==DisplayState.EMPTY)
    Fixture.readFailure=ApiFailure("connection_unavailable",0);view.refresh();idle(view)
    ck("network failure projects offline not empty",view.presentation.state==DisplayState.OFFLINE&&!view.presentation.mayStartCommand)
    Fixture.readFailure=ApiFailure("cursor_stale",409);view.refresh();idle(view)
    ck("changed snapshot projects conflict",view.presentation.state==DisplayState.CONFLICT&&!view.presentation.showRecords)
    Fixture.readFailure=ApiFailure("operation_rejected",422);view.refresh();idle(view)
    ck("known refusal projects rejected",view.presentation.state==DisplayState.REJECTED)
    Fixture.readFailure=null;Fixture.readEmpty=false;view.refresh();idle(view)
    ck("successful refresh removes old failure",view.presentation.state==DisplayState.CONTENT&&view.state.failure==DisplayFailure.NONE)
    view.viewModelScope.cancel()

    reset();Fixture.homeBarrier=java.util.concurrent.CountDownLatch(1)
    val loading=BuriViewModel(Application(),MemoryStore()){now}
    withTimeout(10_000){while(loading.state.operator==null)delay(2)}
    ck("actual outstanding read projects loading",loading.presentation.state==DisplayState.LOADING&&!loading.presentation.mayStartCommand)
    Fixture.homeBarrier!!.countDown();idle(loading);loading.viewModelScope.cancel()
    reset()
    val who=Fixture.operator();val page=Fixture.page(listOf(Fixture.payment()))
    fun project(route:Route,requested:DisplayState):ScreenPresentation {
        val base=UiState(operator=if(route==Route.LOGIN)null else who,route=route,savedAt=now,
            home=Home(1,1,1,0,emptyList(),"at"),payments=page,payment=Fixture.payment(),members=Fixture.page(listOf(Fixture.member)),
            member=Fixture.member,ledger=Page(emptyList(),null,0,"r","at"),messages=Fixture.page(listOf(SmsRow("s-1","M-Money","at","unchanged","queued",null))))
        val sample=when(requested){
            DisplayState.SIGN_IN->base.copy(operator=null)
            DisplayState.LOADING->base.copy(busy=true)
            DisplayState.EMPTY->base.copy(payments=Page(emptyList(),null,0,"r","at"),members=Page(emptyList(),null,0,"r","at"),messages=Page(emptyList(),null,0,"r","at"))
            DisplayState.OFFLINE->base.copy(offline=true)
            DisplayState.STALE->base.copy(savedAt=now-SnapshotFreshness.TTL_MS-1)
            DisplayState.REJECTED->base.copy(failure=DisplayFailure.REJECTED)
            DisplayState.CONFLICT->base.copy(failure=DisplayFailure.CONFLICT)
            DisplayState.UNCERTAIN->base.copy(pending=true)
            DisplayState.UNAVAILABLE->base.copy(failure=DisplayFailure.UNAVAILABLE)
            else->base
        }
        val gate=if(requested==DisplayState.LOCKED)ScreenGate.BACKGROUND else ScreenGate.OPEN
        val result=sample.presentation(gate,now)
        val expected=when {
            requested==DisplayState.LOCKED->DisplayState.LOCKED
            requested==DisplayState.SIGN_IN->DisplayState.SIGN_IN
            route==Route.LOGIN->if(requested==DisplayState.LOADING)DisplayState.LOADING else DisplayState.SIGN_IN
            requested==DisplayState.EMPTY&&route !in setOf(Route.PAYMENTS,Route.MEMBERS,Route.SMS)->DisplayState.CONTENT
            requested==DisplayState.STALE&&route==Route.SETTINGS->DisplayState.CONTENT
            else->requested
        }
        check(result.state==expected){"$route $requested: ${result.state} != $expected"}
        if(requested==DisplayState.UNCERTAIN)check(result.unresolvedWarning&&!result.mayStartCommand)
        if(requested in setOf(DisplayState.SIGN_IN,DisplayState.CONFLICT,DisplayState.LOCKED))check(!result.showRecords)
        return result
    }
    for(route in Route.entries){
        for(state in DisplayState.entries){
            val projected=project(route,state)
            println("COVERAGE route=${route.name} input=${state.name} projected=${projected.state.name}")
        }
        ck("route ${route.name} presentation safety matrix",true)
    }
    // Projection coverage of the routes used by each executed operational journey.
    // This is not a claim that every fault was injected through the real Android journey.
    val journeyRoutes=mapOf(
        "J01" to listOf(Route.LOGIN,Route.HOME),
        "J02" to listOf(Route.HOME,Route.PAYMENTS),
        "J03" to listOf(Route.PAYMENTS,Route.PAYMENT),
        "J04" to listOf(Route.PAYMENT),
        "J05" to listOf(Route.PAYMENT,Route.MEMBERS),
        "J06" to listOf(Route.MEMBERS),
        "J07" to listOf(Route.MEMBER),
        "J08" to listOf(Route.SETTINGS),
        "J09" to listOf(Route.SETTINGS),
        "J10" to listOf(Route.SETTINGS),
        "J11" to listOf(Route.SMS),
        "J12" to listOf(Route.HOME)
    )
    for((journey,routes) in journeyRoutes){
        for(route in routes)for(state in DisplayState.entries){
            val projected=project(route,state)
            println("COVERAGE journey=$journey route=${route.name} input=${state.name} projected=${projected.state.name}")
        }
        ck("journey $journey route-to-state projection",true)
    }
    println("RESULT: $checks actual ViewModel/state checks passed; 88 route/state projections; platform and repository doubles only.")
}
