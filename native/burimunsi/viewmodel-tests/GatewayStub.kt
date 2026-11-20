package rw.ikanisa.burimunsi.gateway
import android.app.Application
import rw.ikanisa.burimunsi.core.*
object GatewayFixture{
 @Volatile var permissionsEntered:java.util.concurrent.CountDownLatch?=null
 @Volatile var permissionsRelease:java.util.concurrent.CountDownLatch?=null
 val permissionReadFinished=java.util.concurrent.CountDownLatch(1)
 @Volatile var healthEntered:java.util.concurrent.CountDownLatch?=null
 @Volatile var healthRelease:java.util.concurrent.CountDownLatch?=null
 val healthReadFinished=java.util.concurrent.CountDownLatch(1)
 var snapshot=GatewayStatus(true,false,1,0,null,null,null,"uploads_on_hold")
 var failStatus=false;var changes=0;var statusReads=0;var retired=false
 @Volatile var uploadStarts=0
 @Volatile var lastStartThreadId=0L
 var queuedReceipts=4
 @Volatile var queueSession:ObservationSessionOwner?=ObservationSessionOwner(ObservationOwner("synthetic-group","operator"),1)
 @Volatile var queueRevision=0L
 @Volatile var queueRows:List<QueuedObservationRow> = emptyList()
 @Volatile var queueBodies:Map<String,String> = emptyMap()
 @Volatile var queueReadEntered:java.util.concurrent.CountDownLatch?=null
 @Volatile var queueReadRelease:java.util.concurrent.CountDownLatch?=null
 @Volatile var statusEntered:java.util.concurrent.CountDownLatch?=null
 @Volatile var statusRelease:java.util.concurrent.CountDownLatch?=null
}
class FixtureGateway(private val app:Application,private val pairer:(String,Boolean)->org.json.JSONObject,
 private val pending:()->Boolean,private val recover:()->org.json.JSONObject?):GatewayPort{
 override fun foregroundChanged(resumed:Boolean){}
 override fun continuousHealth():ContinuousReceiverHealth{
  val release=GatewayFixture.healthRelease?:return ContinuousReceiverHealth()
  GatewayFixture.healthEntered?.countDown()
  check(release.await(5,java.util.concurrent.TimeUnit.SECONDS))
  GatewayFixture.healthReadFinished.countDown()
  return ContinuousReceiverHealth(true,false,"previous_operator")
 }
 override fun stopContinuous(){}
 override fun start(){if(!pending()&&!GatewayFixture.retired){GatewayFixture.lastStartThreadId=Thread.currentThread().id;GatewayFixture.uploadStarts++}};override fun bound()=!GatewayFixture.retired&&GatewayFixture.snapshot.authorized
 override fun status():GatewayStatus{
  GatewayFixture.statusReads++;GatewayFixture.statusEntered?.countDown()
  check(GatewayFixture.statusRelease?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false)
  check(!GatewayFixture.failStatus);return GatewayFixture.snapshot
 }
 override fun pair(code:String){pairer(code,false);GatewayFixture.snapshot=GatewayFixture.snapshot.copy(authorized=true)}
 private fun park(value:org.json.JSONObject):ReceiverRetirementAck{
  GatewayFixture.retired=true;GatewayFixture.snapshot=GatewayFixture.snapshot.copy(captureEnabled=false)
  return ReceiverRetirementAck(value.getString("handoffId"),value.getString("requestId"))
 }
 override fun replace(code:String):ReceiverRetirementAck=park(pairer(code,true))
 override fun retirementPending()=pending()&&!GatewayFixture.retired
 override fun recoverRetirement():ReceiverRetirementAck?=recover()?.let(::park)
 override fun sync(){}
 override fun requiredPermissions():Array<String>{
  GatewayFixture.permissionsRelease?.let { release ->
   GatewayFixture.permissionsEntered?.countDown()
   check(release.await(5,java.util.concurrent.TimeUnit.SECONDS))
   GatewayFixture.permissionReadFinished.countDown()
  }
  return arrayOf(android.Manifest.permission.RECEIVE_SMS,android.Manifest.permission.READ_SMS)
 }
 override fun queuedObservations(query:String):QueuedObservationSnapshot?{
  val session=GatewayFixture.queueSession?:return null
  val snapshot=QueuedObservationSnapshot(session,GatewayFixture.queueRevision,GatewayFixture.queueRows.filter{SmsListSearch.matches(it.id,SmsListContent(it.sender,GatewayFixture.queueBodies[it.id].orEmpty()),query)})
  GatewayFixture.queueReadEntered?.countDown()
  check(GatewayFixture.queueReadRelease?.await(5,java.util.concurrent.TimeUnit.SECONDS)!=false)
  return snapshot
 }
 override fun publishQueued(snapshot:QueuedObservationSnapshot,publish:()->Unit):Boolean{
  if(GatewayFixture.queueSession!=snapshot.session||GatewayFixture.queueRevision!=snapshot.revision||
      app.checkSelfPermission(android.Manifest.permission.READ_SMS)!=0||app.checkSelfPermission(android.Manifest.permission.RECEIVE_SMS)!=0)return false
  publish();return true
 }
 override fun setPaused(value:Boolean){GatewayFixture.changes++;GatewayFixture.snapshot=GatewayFixture.snapshot.copy(captureEnabled=!value)}
}
object GatewayFactory{fun create(app:Application,managedCollection:()->String?={null},pairer:(String,Boolean)->org.json.JSONObject={_,_->org.json.JSONObject()},retirementPending:()->Boolean={false},recoverRetirement:()->org.json.JSONObject?={null},authorizeControl:()->Boolean={false})=FixtureGateway(app,pairer,retirementPending,recoverRetirement);fun installationId(app:Application)="fixture-device"}
