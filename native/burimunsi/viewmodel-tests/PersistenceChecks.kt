package rw.ikanisa.burimunsi.persistencetests

import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import rw.ikanisa.burimunsi.core.ScreenGate
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.Fixture
import rw.ikanisa.burimunsi.ui.BuriViewModel

/** Controller behavior against a synthetic repository; real Keystore is tested separately. */
fun main()=runBlocking {
    var now=System.currentTimeMillis()
    Fixture.restoreFailure=ApiFailure("connection_unavailable",0)
    Fixture.recordSavedAt=now
    val model=BuriViewModel(Application()){now}
    suspend fun idle(){withTimeout(10000){while(model.state.busy)delay(2)};delay(30)}
    idle()
    check(model.state.operator==null&&model.state.offline&&model.state.savedSessionPending&&!model.presentation.showRecords)
    model.onForeground();idle()
    val attempts=Fixture.restoreReads
    repeat(4){model.onNetworkAvailable();idle()}
    check(Fixture.restoreReads==attempts+1&&model.state.operator==null&&!model.presentation.showRecords)
    println("PASS repeated connectivity callbacks are rate limited while the backend is unavailable")
    val beforeTimer=Fixture.restoreReads;now+=10_000
    withTimeout(5000){while(Fixture.restoreReads==beforeTimer)delay(20)};idle()
    check(Fixture.restoreReads==beforeTimer+1&&model.state.operator==null&&!model.presentation.showRecords)
    println("PASS bounded foreground retry covers missed network callbacks without exposing saved data")
    Fixture.restoreFailure=null
    model.onNetworkAvailable();idle()
    check(model.state.operator!=null&&Fixture.restoreReads>attempts&&Fixture.loginCalls==0&&model.screenGate==ScreenGate.OPEN)
    println("PASS foreground reconnection restores the saved session without a PIN login")
    model.onBackground();Fixture.sessionFailure=ApiFailure("connection_unavailable",0);model.onForeground();idle()
    check(model.screenGate==ScreenGate.REVALIDATE&&!model.presentation.showRecords)
    val priorSessions=Fixture.sessionReads;now+=5_001;Fixture.sessionFailure=null;Fixture.recordSavedAt=now
    model.onNetworkAvailable();idle()
    check(Fixture.sessionReads==priorSessions+1&&model.screenGate==ScreenGate.OPEN&&Fixture.loginCalls==0)
    println("PASS reconnect revalidates an already-open session before exposing records")
    val prior=model.state.operator!!.expiresAt
    val refreshed=prior+3_600_000L
    val reads=Fixture.sessionReads
    now=prior-30_000L;Fixture.recordSavedAt=now;Fixture.renewedExpiry=refreshed
    withTimeout(5000){while(Fixture.sessionReads<=reads)delay(20)};idle()
    check(model.state.operator?.expiresAt==refreshed&&model.screenGate==ScreenGate.OPEN)
    println("PASS foreground session is renewed before its current deadline")
    now=refreshed+1;Fixture.sessionFailure=ApiFailure("connection_unavailable",0)
    val clears=Fixture.clearOperatorCalls
    model.checkVisibleFreshness();check(model.screenGate==ScreenGate.REVALIDATE)
    model.onBackground();model.onForeground();idle()
    check(model.state.operator!=null&&model.screenGate==ScreenGate.REVALIDATE&&Fixture.clearOperatorCalls==clears)
    println("PASS expired offline session hides records without deleting the saved login")
    Fixture.sessionFailure=null;Fixture.renewedExpiry=now+3_600_000L;Fixture.recordSavedAt=now
    model.onBackground();model.onForeground();idle()
    check(model.state.operator!=null&&model.screenGate==ScreenGate.OPEN)
    println("PASS revalidation restores the existing session after reconnecting")
    model.logout();idle();val afterLogout=Fixture.restoreReads
    model.onNetworkAvailable();model.onBackground();model.onNetworkAvailable();model.onForeground();idle()
    check(model.state.operator==null&&Fixture.restoreReads==afterLogout)
    println("PASS explicit logout never triggers restoration from network or lifecycle events")
    model.viewModelScope.cancel()

    now=System.currentTimeMillis();Fixture.restoreFailure=ApiFailure("connection_unavailable",0);Fixture.restoreSignedOut=false
    val restarted=BuriViewModel(Application()){now}
    suspend fun restartedIdle(){withTimeout(10000){while(restarted.state.busy)delay(2)};delay(30)}
    restartedIdle();restarted.onForeground();restartedIdle();restarted.onBackground()
    val stopped=Fixture.restoreReads;now+=30_000
    restarted.onNetworkAvailable();delay(1_100)
    check(Fixture.restoreReads==stopped&&restarted.screenGate==ScreenGate.BACKGROUND)
    println("PASS background cancellation ignores network events and periodic recovery")
    Fixture.restoreFailure=null;Fixture.recordSavedAt=now
    restarted.onForeground();restartedIdle()
    check(restarted.state.operator!=null&&Fixture.loginCalls==0)
    println("PASS recreated controller restores the same saved login after foregrounding")
    restarted.viewModelScope.cancel()

    Fixture.restoreFailure=ApiFailure("session_unavailable",401);now=System.currentTimeMillis()
    val denied=BuriViewModel(Application()){now}
    withTimeout(10000){while(denied.state.busy)delay(2)};delay(30);denied.onForeground()
    withTimeout(10000){while(denied.state.busy)delay(2)};val deniedCount=Fixture.restoreReads
    denied.onNetworkAvailable();now+=30_000;delay(1_100)
    check(Fixture.restoreReads==deniedCount&&denied.state.operator==null&&!denied.presentation.showRecords)
    println("PASS confirmed session denial is not retried as a connectivity failure")
    denied.viewModelScope.cancel();Fixture.restoreFailure=null

    now=System.currentTimeMillis();Fixture.restoreEntered=CountDownLatch(1);Fixture.restoreBarrier=CountDownLatch(1)
    val cancelled=BuriViewModel(Application()){now}
    check(Fixture.restoreEntered!!.await(5,TimeUnit.SECONDS));cancelled.viewModelScope.cancel()
    Fixture.restoreBarrier!!.countDown();delay(200)
    check(cancelled.state.operator==null&&!cancelled.presentation.showRecords&&Fixture.loginCalls==0)
    println("PASS cancellation cannot publish a late saved-session response")
    Fixture.restoreEntered=null;Fixture.restoreBarrier=null
}
