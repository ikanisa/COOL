package rw.ikanisa.burimunsi.foregroundtests

import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import java.util.concurrent.CountDownLatch
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.gateway.GatewayFixture

/** Executes actual controller code with explicit fake Android/repository boundaries. */
fun main()=runBlocking {
    var checks=0
    fun ck(label:String,value:Boolean){check(value){label};println("PASS $label");checks++}
    var now=System.currentTimeMillis()
    Fixture.recordSavedAt=now
    val m=BuriViewModel(Application()){now}
    suspend fun idle(){withTimeout(10000){while(m.state.busy)delay(2)};delay(20);withTimeout(10000){while(m.state.busy)delay(2)}}
    idle();m.onForeground();idle()
    ck("initial foreground revalidates session",Fixture.sessionReads==1&&m.screenGate==ScreenGate.OPEN)
    m.navigate(Route.PAYMENTS);idle();m.search("payer");m.searchSubmit();idle();m.listPosition(Route.PAYMENTS,null,3,11)
    val reads=Fixture.sessionReads
    m.onBackground()
    ck("paused app is covered without a network request",m.screenGate==ScreenGate.BACKGROUND&&Fixture.sessionReads==reads)
    ck("paused actions have no capabilities",!m.allows(Capability.READ)&&!m.allows(Capability.ALLOCATE))
    m.enroll("Example Member","0780000001");idle()
    ck("background direct mutation call is blocked",Fixture.enrollMutations==0)
    Fixture.sessionFailure=ApiFailure("connection_unavailable",0)
    m.onForeground();idle()
    ck("failed resume remains covered",m.screenGate==ScreenGate.REVALIDATE&&m.state.error!=null)
    ck("resume preserves search and scroll context",m.state.search=="payer"&&m.state.listIndex==3&&m.state.listOffset==11)
    val failures=Fixture.sessionReads;delay(1100)
    ck("failed resume does not poll the backend repeatedly",Fixture.sessionReads==failures)
    m.more();m.enroll("Example Member","0780000001");idle()
    ck("gate blocks pagination and mutation",m.state.payments?.items?.size==1&&Fixture.enrollMutations==0)
    Fixture.sessionFailure=null;m.refresh();idle()
    ck("explicit retry opens after fresh profile and records",m.screenGate==ScreenGate.OPEN)
    now+=SnapshotFreshness.TTL_MS+1;m.checkVisibleFreshness()
    ck("already-visible records expire",m.screenGate==ScreenGate.STALE)
    ck("expiry disables actions without inventing a balance",!m.allows(Capability.READ)&&m.state.payments?.items?.first()?.amountRwf==10000L)
    m.refresh();idle()
    ck("profile success alone cannot renew expired data",m.screenGate==ScreenGate.REVALIDATE&&m.state.error?.contains("expired")==true)
    Fixture.recordSavedAt=now;m.refresh();idle()
    ck("fresh read unlocks expired screen",m.screenGate==ScreenGate.OPEN)
    now-=1;m.checkVisibleFreshness()
    ck("clock rollback closes active screen",m.screenGate==ScreenGate.STALE)
    Fixture.recordSavedAt=now;m.refresh();idle()
    m.navigate(Route.PAYMENT,"tx-1");idle();m.openSheet(Sheet.ALLOCATE);idle()
    m.selectMember(Fixture.member);m.editDraft("note","A non-secret identity explanation")
    m.onBackground();m.onForeground();idle()
    ck("non-secret allocation draft survives revalidation",m.state.draft["note"]=="A non-secret identity explanation")
    ck("beneficiary must be selected again after revalidation",m.state.selectedMember==null)
    ck("resume never submits a draft",Fixture.mutations==0&&Fixture.reconciles==0)
    m.discardDraft();m.refresh();idle();m.openSheet(Sheet.HISTORY);idle()
    Fixture.historySavedAt=now-SnapshotFreshness.TTL_MS-1;m.refresh();idle()
    ck("history expires independently of fresh payment",m.screenGate==ScreenGate.STALE&&m.state.savedAt==now)
    Fixture.historySavedAt=now;m.refresh();idle()
    ck("history refresh restores correct scoped panel",m.screenGate==ScreenGate.OPEN&&m.state.historyPaymentId=="tx-1")
    m.closeSheet();m.refresh();idle();m.navigate(Route.HOME);idle()
    // A resume during an already running read is queued, not skipped or parallelized.
    val homeBefore=Fixture.homeReads;val sessionBefore=Fixture.sessionReads
    val readLatch=CountDownLatch(1);Fixture.homeBarrier=readLatch;m.refresh()
    withTimeout(2000){while(Fixture.homeReads==homeBefore)delay(2)}
    m.onBackground();m.onForeground()
    ck("busy resume waits for current read",m.state.busy&&m.screenGate==ScreenGate.REVALIDATE&&Fixture.sessionReads==sessionBefore)
    Fixture.homeBarrier=null;readLatch.countDown();idle()
    ck("deferred resume executes exactly one profile check",Fixture.sessionReads==sessionBefore+1&&m.screenGate==ScreenGate.OPEN)
    // A submitted financial operation is not cancelled, repeated, or inferred to have failed.
    m.navigate(Route.PAYMENT,"tx-1");idle();m.openSheet(Sheet.ALLOCATE);idle();m.selectMember(Fixture.member)
    val mutationLatch=CountDownLatch(1);Fixture.allocateBarrier=mutationLatch
    m.allocate("Verified identity and membership")
    withTimeout(2000){while(Fixture.mutations==0)delay(2)}
    val sessionsDuring=Fixture.sessionReads;m.onBackground();m.onForeground()
    ck("dispatched mutation is not cancelled on pause",Fixture.mutations==1&&m.state.busy&&Fixture.sessionReads==sessionsDuring)
    Fixture.allocateBarrier=null;mutationLatch.countDown();idle()
    ck("mutation completes once before deferred revalidation",Fixture.mutations==1&&Fixture.sessionReads==sessionsDuring+1&&m.screenGate==ScreenGate.OPEN)
    ck("resume does not replay operation journal",Fixture.reconciles==0)
    m.openSheet(Sheet.STAFF);idle();m.openSheet(Sheet.STAFF_EDIT,"staff-1");idle();m.editDraft("name","Unsubmitted staff edit")
    m.onBackground();m.onForeground();idle()
    ck("old staff version cannot survive fresh session",m.state.selectedStaff==null&&m.state.draft["name"]=="Unsubmitted staff edit")
    m.saveStaff("Unsubmitted staff edit","0780000002","",false,false);idle()
    ck("invalidated staff edit never becomes create",Fixture.staffMutations==0)
    m.discardDraft();m.refresh();idle()
    m.onBackground();Fixture.refreshedRole=Role.STAFF;Fixture.refreshedCaps=setOf(Capability.READ.key);m.onForeground();idle()
    ck("permission downgrade clears privileged panels",m.state.sheet==null&&m.state.staff==null&&m.state.raw==null&&m.state.operator?.role==Role.STAFF)
    m.onBackground();Fixture.sessionFailure=ApiFailure("session_unavailable",401);m.onForeground();idle()
    ck("revocation returns to sign in without old records",m.state.operator==null&&m.state.home==null&&m.state.payments==null&&m.screenGate==ScreenGate.OPEN)
    Fixture.sessionFailure=null;Fixture.refreshedRole=null;Fixture.refreshedCaps=null;Fixture.recordSavedAt=now
    m.login("0780000001","2468");idle()
    ck("fresh explicit login clears previous guards",m.state.operator!=null&&m.screenGate==ScreenGate.OPEN)
    m.navigate(Route.SETTINGS);idle();m.onBackground();Fixture.sessionFailure=ApiFailure("connection_unavailable",0);m.onForeground();idle()
    ck("Settings failed session check remains guarded",m.screenGate==ScreenGate.REVALIDATE&&m.state.offline)
    Fixture.sessionFailure=null;m.refresh();idle()
    ck("fresh Settings session clears an old offline flag",m.screenGate==ScreenGate.OPEN&&!m.state.offline)
    m.navigate(Route.MEMBER,"member-1");idle()
    var exported=0
    m.onBackground();m.export{check(it=="synthetic csv");exported++}
    ck("document-picker return waits for foreground validation",exported==0&&Fixture.exportReads==0)
    m.onForeground();idle()
    ck("requested export completes after revalidation",exported==1&&Fixture.exportReads==1&&Fixture.lastExportMember=="member-1")
    m.onBackground();m.export{exported++};now+=SnapshotFreshness.TTL_MS+1;Fixture.recordSavedAt=now;m.onForeground();idle()
    ck("expired pending export is cancelled",exported==1&&Fixture.exportReads==1)
    m.navigate(Route.HOME);idle();m.openSheet(Sheet.GATEWAY);idle()
    ck("gateway status read has its own timestamp",m.state.gateway!=null&&m.state.panelSavedAt==now)
    GatewayFixture.failStatus=true;m.refresh();idle()
    ck("failed status refresh does not display old healthy status",m.state.gateway==null&&m.state.error!=null)
    GatewayFixture.failStatus=false;m.refresh();idle()
    GatewayFixture.snapshot=GatewayFixture.snapshot.copy(problem="permission_required",captureEnabled=false)
    m.setPaused(false);idle()
    ck("missing permission cannot resume through controller",GatewayFixture.changes==0&&m.state.error!=null)
    GatewayFixture.snapshot=GatewayFixture.snapshot.copy(problem="unexpected_reason")
    m.setPaused(false);idle()
    ck("unknown receiving state cannot resume through controller",GatewayFixture.changes==0)
    GatewayFixture.snapshot=GatewayFixture.snapshot.copy(problem="uploads_on_hold")
    m.setPaused(false);idle()
    ck("local capture resume does not clear upload hold",GatewayFixture.changes==1&&m.state.gateway?.captureEnabled==true&&m.state.gateway?.problem=="uploads_on_hold")
    m.setPaused(true);idle()
    ck("capture pause is available without deleting queue",GatewayFixture.changes==2&&m.state.gateway?.captureEnabled==false)
    m.closeSheet();m.refresh();idle();m.navigate(Route.MEMBER,"member-1");idle();m.onBackground();m.export{exported++}
    m.onBackground();m.logout();idle();m.onForeground();idle()
    ck("signout retains no guarded operator",m.state.operator==null&&m.screenGate==ScreenGate.OPEN)
    ck("signout drops pending export without writing",exported==1&&Fixture.exportReads==1)
    m.viewModelScope.cancel()
    println("RESULT: $checks foreground-controller checks passed; synthetic provider/platform, not Android lifecycle execution.")
}
