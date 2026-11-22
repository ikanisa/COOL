package rw.ikanisa.burimunsi.foregroundtests

import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicInteger
import rw.ikanisa.burimunsi.ui.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.core.export.CsvEncoder
import rw.ikanisa.burimunsi.core.export.ExportFormat
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
    Fixture.supportFetch={"+250780000001"};m.onBackground();m.onForeground()
    withTimeout(2000){while(m.supportPhone==null)delay(2)}
    ck("foreground support comes from current runtime config",m.supportPhone=="+250780000001")
    m.onBackground();ck("background clears displayed support contact",m.supportPhone==null)
    Fixture.supportFetch={null};m.onForeground();idle()
    ck("offline or missing support config never invents a phone",m.supportPhone==null)
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
    val cadenceSessions=Fixture.sessionReads
    now+=30_001L;Fixture.recordSavedAt=now
    withTimeout(4000){while(Fixture.sessionReads==cadenceSessions||m.state.busy)delay(10)}
    ck("visible records refresh on a bounded cadence before the five-minute expiry",Fixture.sessionReads==cadenceSessions+1&&m.state.savedAt==now&&m.screenGate==ScreenGate.OPEN)
    val automaticSessions=Fixture.sessionReads;val automaticMutations=Fixture.mutations;val automaticChecks=Fixture.reconciles
    now+=SnapshotFreshness.TTL_MS+1;Fixture.recordSavedAt=now;m.checkVisibleFreshness()
    withTimeout(4000){while(m.screenGate!=ScreenGate.OPEN||Fixture.sessionReads==automaticSessions)delay(10)}
    ck("expired visible records re-fetch automatically without manual Refresh",Fixture.sessionReads==automaticSessions+1&&m.state.savedAt==now)
    ck("automatic refresh never submits or reconciles a financial command",Fixture.mutations==automaticMutations&&Fixture.reconciles==automaticChecks)
    m.onBackground();val backgroundReads=Fixture.sessionReads
    now+=SnapshotFreshness.TTL_MS+1;Fixture.recordSavedAt=now;delay(1100)
    ck("automatic reads stop while the app is backgrounded",Fixture.sessionReads==backgroundReads)
    m.onForeground();idle()
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
    ck("administrator cannot pause locked-on sync or erase the queue",GatewayFixture.changes==1&&m.state.gateway?.captureEnabled==true&&m.state.error!=null)

    m.closeSheet();m.refresh();idle();m.navigate(Route.MEMBER,"member-1");idle()
    val exportRoot = Files.createTempDirectory("burimunsi-foreground-exports").toFile()
    val exportDirectory = File(exportRoot, "burimunsi-exports")
    val exported = AtomicInteger()
    val aborted = AtomicInteger()
    m.configureDownloads(exportDirectory) { _, table, file, cancelled ->
        file.outputStream().use { CsvEncoder.write(table, it, cancelled) }
    }
    suspend fun returnFromCsvPicker() {
        m.prepareDownload(ExportFormat.CSV)
        idle()
        val request = checkNotNull(m.takeDownloadRequest())
        m.onBackground()
        check(m.downloadDestination(request.id, request.format, write = { file, verify ->
            verify()
            check(file.readText().contains("Member ledger"))
            exported.incrementAndGet()
        }, abort = { aborted.incrementAndGet() }))
    }
    try {
        returnFromCsvPicker()
        ck("document-picker return waits for foreground validation", exported.get() == 0 && m.screenGate == ScreenGate.BACKGROUND)
        m.onForeground();idle()
        ck("requested export completes after revalidation", exported.get() == 1 && m.exportFeedback?.phase == UiExportPhase.COMPLETE)

        returnFromCsvPicker()
        now += SnapshotFreshness.TTL_MS + 1
        Fixture.recordSavedAt = now
        m.onForeground();idle()
        ck("expired pending export is cancelled", exported.get() == 1 && aborted.get() == 1 && exportDirectory.listFiles().isNullOrEmpty())

        returnFromCsvPicker()
        m.logout();idle();m.onForeground();idle()
        ck("signout retains no guarded operator", m.state.operator == null && m.screenGate == ScreenGate.OPEN)
        withTimeout(2_000) { while (aborted.get() < 2) delay(2) }
        ck("signout drops pending export without writing", exported.get() == 1 && aborted.get() == 2 && exportDirectory.listFiles().isNullOrEmpty())
    } finally {
        exportRoot.deleteRecursively()
    }
    m.viewModelScope.cancel()
    Fixture.restoreEntered=CountDownLatch(1);Fixture.restoreBarrier=CountDownLatch(1);Fixture.restoreSignedOut=true
    val signedOut=BuriViewModel(Application()){now}
    withContext(Dispatchers.IO){check(Fixture.restoreEntered!!.await(2,java.util.concurrent.TimeUnit.SECONDS))}
    ck("initial restore retains branded splash state before signed-out decision",signedOut.state.starting&&signedOut.state.operator==null)
    Fixture.restoreBarrier!!.countDown()
    withTimeout(4000){while(signedOut.state.busy||signedOut.state.starting)delay(10)}
    ck("completed signed-out restore returns the original login",signedOut.state.route==Route.LOGIN&&!signedOut.state.savedSessionPending)
    signedOut.viewModelScope.cancel();Fixture.restoreBarrier=null;Fixture.restoreEntered=null;Fixture.restoreSignedOut=false
    println("RESULT: $checks foreground-controller checks passed; synthetic provider/platform, not Android lifecycle execution.")
}
