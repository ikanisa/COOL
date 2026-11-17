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
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.data.Fixture
import rw.ikanisa.burimunsi.ui.BuriViewModel

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
}
