package rw.ikanisa.burimunsi.coldstarttests

import android.app.Application
import androidx.lifecycle.viewModelScope
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import rw.ikanisa.burimunsi.core.ScreenGate
import rw.ikanisa.burimunsi.core.Route
import rw.ikanisa.burimunsi.core.SnapshotFreshness
import rw.ikanisa.burimunsi.gateway.GatewayFixture
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.Fixture
import rw.ikanisa.burimunsi.ui.BuriViewModel
import rw.ikanisa.burimunsi.ui.UiOperation

/** Actual controller with synthetic provider/platform doubles. */
fun main()=runBlocking {
    suspend fun idle(m:BuriViewModel){
        withTimeout(10_000){while(m.state.busy)delay(2)}
        delay(50)
        withTimeout(10_000){while(m.state.busy)delay(2)}
    }
    val now=System.currentTimeMillis();Fixture.recordSavedAt=now
    Fixture.restoreEntered=CountDownLatch(1);Fixture.restoreBarrier=CountDownLatch(1)
    val first=BuriViewModel(Application()){now}
    check(Fixture.restoreEntered!!.await(5,TimeUnit.SECONDS))
    first.onForeground();first.onForeground()
    Fixture.restoreBarrier!!.countDown();idle(first)
    check(Fixture.restoreReads==1&&Fixture.sessionReads==0&&Fixture.homeReads==1&&first.screenGate==ScreenGate.OPEN)
    println("PASS initial foreground shares the in-flight authoritative restore and records read")
    first.viewModelScope.cancel()

    Fixture.restoreEntered=CountDownLatch(1);Fixture.restoreBarrier=CountDownLatch(1)
    val restores=Fixture.restoreReads;val sessions=Fixture.sessionReads;val homes=Fixture.homeReads
    val reentered=BuriViewModel(Application()){now}
    check(Fixture.restoreEntered!!.await(5,TimeUnit.SECONDS))
    reentered.onForeground();reentered.onBackground();reentered.onForeground()
    Fixture.restoreBarrier!!.countDown();idle(reentered)
    check(Fixture.restoreReads==restores+1&&Fixture.sessionReads==sessions+1&&Fixture.homeReads==homes+2&&reentered.screenGate==ScreenGate.OPEN)
    println("PASS a real background and foreground during restore requires a fresh session and records read")
    reentered.viewModelScope.cancel()

    Fixture.restoreEntered=CountDownLatch(1);Fixture.restoreBarrier=CountDownLatch(1)
    Fixture.sessionFailure=ApiFailure("session_unavailable",401)
    val denied=BuriViewModel(Application()){now}
    check(Fixture.restoreEntered!!.await(5,TimeUnit.SECONDS))
    denied.onForeground();denied.onBackground();denied.onForeground()
    Fixture.restoreBarrier!!.countDown();idle(denied)
    check(denied.state.operator==null&&!denied.presentation.showRecords)
    println("PASS a revoked session after re-entry cannot expose the earlier restored records")
    denied.viewModelScope.cancel()
    Fixture.sessionFailure=null

    Fixture.restoreEntered=CountDownLatch(1);Fixture.restoreBarrier=CountDownLatch(1)
    Fixture.restoreFailure=ApiFailure("connection_unavailable",0)
    val attempts=Fixture.restoreReads
    val unavailable=BuriViewModel(Application()){now}
    check(Fixture.restoreEntered!!.await(5,TimeUnit.SECONDS))
    unavailable.onForeground();Fixture.restoreBarrier!!.countDown();idle(unavailable)
    check(Fixture.restoreReads>=attempts+2&&unavailable.state.operator==null&&
        unavailable.state.savedSessionPending&&!unavailable.presentation.showRecords)
    println("PASS an unsuccessful coalesced restore preserves recovery without exposing records")
    unavailable.viewModelScope.cancel()
    Fixture.restoreFailure=null;Fixture.restoreEntered=null;Fixture.restoreBarrier=null

    val blockedHome=CountDownLatch(1);Fixture.homeBarrier=blockedHome
    val homeBefore=Fixture.homeReads
    val loading=BuriViewModel(Application()){now}
    withTimeout(3_000){while(Fixture.homeReads==homeBefore)delay(2)}
    loading.onForeground()
    check(loading.state.operator!=null&&!loading.state.starting&&loading.state.busy&&
        loading.screenGate==ScreenGate.OPEN&&loading.operationLabel=="Loading records"&&!loading.presentation.showRecords)
    println("PASS validated startup shows a loading shell without exposing unread records")
    Fixture.homeBarrier=null;blockedHome.countDown();idle(loading);loading.viewModelScope.cancel()

    GatewayFixture.statusEntered=CountDownLatch(1);GatewayFixture.statusRelease=CountDownLatch(1)
    val diagnostic=BuriViewModel(Application()){now}
    check(GatewayFixture.statusEntered!!.await(3,TimeUnit.SECONDS));idle(diagnostic)
    check(diagnostic.state.home!=null&&diagnostic.presentation.showRecords&&!diagnostic.state.busy)
    diagnostic.navigate(Route.PAYMENTS);idle(diagnostic)
    GatewayFixture.statusRelease!!.countDown();delay(100)
    check(diagnostic.state.route==Route.PAYMENTS&&diagnostic.state.gateway==null)
    println("PASS Home is usable before receiver diagnostics finish and late status cannot enter a later route")
    diagnostic.viewModelScope.cancel();GatewayFixture.statusEntered=null;GatewayFixture.statusRelease=null

    val quiet=BuriViewModel(Application()){now};idle(quiet)
    val blockedRefresh=CountDownLatch(1);Fixture.homeBarrier=blockedRefresh
    val quietHomeBefore=Fixture.homeReads
    quiet.refreshSession(quiet=true)
    withTimeout(3_000){while(Fixture.homeReads==quietHomeBefore)delay(2)}
    val mutationsBefore=Fixture.enrollMutations
    check(!quiet.navigationBlocked)
    quiet.navigate(Route.PAYMENTS);quiet.enroll("Synthetic member","0780000001")
    check(quiet.requestedRoute==Route.PAYMENTS&&quiet.state.route==Route.HOME&&Fixture.enrollMutations==mutationsBefore)
    Fixture.homeBarrier=null;blockedRefresh.countDown();idle(quiet)
    check(quiet.requestedRoute==null&&quiet.state.route==Route.PAYMENTS&&quiet.state.payments!=null)
    println("PASS quiet refresh accepts navigation without concurrent records or financial commands")

    Fixture.sessionEntered=CountDownLatch(1);Fixture.sessionBarrier=CountDownLatch(1)
    Fixture.sessionFailure=ApiFailure("session_unavailable",401)
    quiet.refreshSession(quiet=true)
    check(Fixture.sessionEntered!!.await(3,TimeUnit.SECONDS))
    quiet.navigate(Route.HOME);check(quiet.requestedRoute==Route.HOME)
    Fixture.sessionBarrier!!.countDown();idle(quiet)
    check(quiet.state.operator==null&&quiet.state.home==null&&quiet.state.payments==null&&quiet.requestedRoute==null)
    println("PASS revocation discards a queued destination and all prior records")
    quiet.viewModelScope.cancel();Fixture.sessionEntered=null;Fixture.sessionBarrier=null;Fixture.sessionFailure=null

    val members=BuriViewModel(Application()){now};idle(members);members.onForeground();idle(members)
    val memberHomeReads=Fixture.homeReads
    val blockedUnusedHome=CountDownLatch(1);Fixture.homeBarrier=blockedUnusedHome
    members.navigate(Route.MEMBERS);idle(members)
    check(members.state.route==Route.MEMBERS&&members.state.members!=null&&members.state.home==null&&Fixture.homeReads==memberHomeReads)
    members.search("Example");members.searchSubmit();idle(members)
    check(members.state.search=="Example"&&members.state.members!=null&&Fixture.homeReads==memberHomeReads)
    println("PASS Members navigation and search do not issue an unrelated Home read")

    Fixture.membersCachedOverride=true;Fixture.membersSavedAtOverride=now-10_000
    members.refresh();idle(members)
    check(members.state.offline&&members.state.savedAt==now-10_000&&members.presentation.showRecords)
    Fixture.cached=true;Fixture.membersCachedOverride=false;Fixture.membersSavedAtOverride=now-2_000
    members.refresh();idle(members)
    check(!members.state.offline&&members.state.savedAt==now-2_000&&members.presentation.showRecords)
    Fixture.cached=false;Fixture.membersCachedOverride=true;Fixture.membersSavedAtOverride=now-SnapshotFreshness.TTL_MS-1
    members.refresh();idle(members)
    check(members.screenGate==ScreenGate.STALE&&!members.presentation.showRecords)
    Fixture.membersCachedOverride=false;Fixture.membersSavedAtOverride=now
    members.refresh();idle(members)
    check(members.screenGate==ScreenGate.OPEN&&!members.state.offline&&members.state.savedAt==now)
    println("PASS Members uses its own cache timestamp, offline status and freshness gate")

    members.onBackground();members.onForeground();idle(members)
    check(members.state.route==Route.MEMBERS&&Fixture.homeReads==memberHomeReads)
    Fixture.homeBarrier=null;blockedUnusedHome.countDown()
    members.back();idle(members)
    check(members.state.route==Route.HOME&&members.state.home!=null&&Fixture.homeReads==memberHomeReads+1)
    members.navigate(Route.MEMBERS);idle(members)
    Fixture.membersFailure=ApiFailure("session_unavailable",401)
    members.refresh();idle(members)
    check(members.state.operator==null&&members.state.members==null&&members.state.home==null&&!members.presentation.showRecords)
    println("PASS returning Home refreshes its own aggregate and a revoked member read clears private records")
    members.viewModelScope.cancel();Fixture.membersFailure=null;Fixture.membersCachedOverride=null;Fixture.membersSavedAtOverride=null

    Fixture.restoreSignedOut=true;Fixture.managedCollection=null
    val login=BuriViewModel(Application()){now};idle(login)
    Fixture.loginEntered=CountDownLatch(1);Fixture.loginBarrier=CountDownLatch(1)
    login.login("0780000001","1234");check(Fixture.loginEntered!!.await(3,TimeUnit.SECONDS))
    check(login.operation==UiOperation.SIGN_IN&&login.operationLabel=="Signing in…")
    Fixture.loginBarrier!!.countDown();idle(login)
    check(login.state.operator==null&&login.state.error=="Phone or passcode is incorrect.")
    println("PASS sign-in progress and incorrect credentials have specific, non-enumerating feedback")
    login.viewModelScope.cancel();Fixture.loginEntered=null;Fixture.loginBarrier=null
    Fixture.restoreSignedOut=false;Fixture.managedCollection="synthetic-group"
}
