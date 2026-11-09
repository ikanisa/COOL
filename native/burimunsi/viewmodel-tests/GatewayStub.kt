package rw.ikanisa.burimunsi.gateway
import android.app.Application
import rw.ikanisa.burimunsi.core.GatewayStatus
object GatewayFixture{
 var snapshot=GatewayStatus(true,false,1,0,null,null,null,"uploads_on_hold")
 var failStatus=false;var changes=0
}
class FixtureGateway{
 fun start(){};fun bound()=GatewayFixture.snapshot.authorized
 fun status():GatewayStatus{check(!GatewayFixture.failStatus);return GatewayFixture.snapshot}
 fun pair(code:String){}
 fun setPaused(value:Boolean){GatewayFixture.changes++;GatewayFixture.snapshot=GatewayFixture.snapshot.copy(captureEnabled=!value)}
}
object GatewayFactory{fun create(app:Application)=FixtureGateway();fun installationId(app:Application)="fixture-device"}
