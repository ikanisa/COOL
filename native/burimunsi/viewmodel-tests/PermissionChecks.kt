package rw.ikanisa.burimunsi.permissiontests
import android.app.Application
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.ui.BuriViewModel
import rw.ikanisa.burimunsi.ui.Sheet
import rw.ikanisa.burimunsi.gateway.GatewayFixture
import rw.ikanisa.burimunsi.core.*
import androidx.lifecycle.viewModelScope

fun main()=runBlocking {
    val app=Application();val model=BuriViewModel(app)
    withTimeout(10000){while(model.state.busy)delay(2)}
    check(model.smsAccessGranted)
    val callerThread=Thread.currentThread().id
    val starts=GatewayFixture.uploadStarts
    app.permissionResults[android.Manifest.permission.READ_SMS]=-1;model.permissionsChanged()
    withTimeout(10000){while(GatewayFixture.uploadStarts<=starts)delay(2)}
    check(GatewayFixture.lastStartThreadId!=callerThread)
    check(!model.smsAccessGranted)
    app.permissionResults[android.Manifest.permission.READ_SMS]=0
    app.permissionResults[android.Manifest.permission.RECEIVE_SMS]=-1;model.permissionsChanged()
    check(!model.smsAccessGranted)
    model.onBackground()
    app.permissionResults[android.Manifest.permission.RECEIVE_SMS]=0
    model.onForeground()
    withTimeout(10000){while(model.state.busy)delay(2)}
    check(model.smsAccessGranted&&model.state.sheet==null)
    println("PASS SMS permission reflects both permissions and refreshes on return without opening a sheet")
    app.permissionResults[android.Manifest.permission.READ_SMS]=-1
    GatewayFixture.snapshot=GatewayStatus(true,false,1,0,null,null,null,"permission_required")
    model.permissionsChanged()
    withTimeout(10000){while(model.state.gateway?.problem!="permission_required"||model.state.busy)delay(2)}
    model.openSheet(Sheet.GATEWAY)
    withTimeout(10000){while(model.state.busy)delay(2)}
    check(model.state.gateway?.problem=="permission_required")
    val changes=GatewayFixture.changes
    app.permissionResults[android.Manifest.permission.READ_SMS]=0
    GatewayFixture.snapshot=GatewayStatus(true,false,1,0,null,null,null,null)
    model.permissionsChanged()
    withTimeout(10000){while(model.state.gateway==null||model.state.gateway?.problem!=null||model.state.busy)delay(2)}
    check(model.state.sheet==Sheet.GATEWAY&&GatewayHealth.describe(model.state.gateway).canResume)
    check(GatewayFixture.changes==changes)
    println("PASS permission return refreshes the current gateway diagnosis without resuming it")
    val reads=GatewayFixture.statusReads;val startsAgain=GatewayFixture.uploadStarts
    model.permissionsChanged()
    withTimeout(10000){while(GatewayFixture.uploadStarts<=startsAgain)delay(2)}
    delay(100)
    check(GatewayFixture.statusReads==reads)
    println("PASS unchanged permissions do not trigger an extra gateway status refresh")
    GatewayFixture.statusEntered=java.util.concurrent.CountDownLatch(1)
    GatewayFixture.statusRelease=java.util.concurrent.CountDownLatch(1)
    app.permissionResults[android.Manifest.permission.RECEIVE_SMS]=-1
    model.permissionsChanged()
    withContext(Dispatchers.IO){check(GatewayFixture.statusEntered!!.await(5,java.util.concurrent.TimeUnit.SECONDS))}
    model.onBackground();GatewayFixture.statusRelease!!.countDown()
    withTimeout(10000){while(model.state.busy)delay(2)}
    check(model.state.gateway==null)
    GatewayFixture.statusEntered=null;GatewayFixture.statusRelease=null
    model.viewModelScope.cancel()
    println("PASS permission refresh cannot publish after the app leaves the foreground")
}
