package rw.ikanisa.burimunsi.remotesmstests

import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.gateway.GatewayFixture
import rw.ikanisa.burimunsi.ui.BuriViewModel

private class Checkpoints:NavigationCheckpointStore {
 @Volatile var value:String?=null
 val writes=java.util.concurrent.CopyOnWriteArrayList<String>()
 override fun read()=value
 override fun write(value:String){this.value=value;writes.add(value)}
 override fun clear(){value=null}
}
/** Actual ViewModel with synthetic repository/session/platform doubles. */
fun main()=runBlocking {
 suspend fun idle(m:BuriViewModel){withTimeout(10_000){while(m.state.busy)delay(2)};delay(20)}
 suspend fun scanned(m:BuriViewModel){withTimeout(10_000){while(m.state.busy||m.state.smsScanRunning)delay(2)};delay(30);withTimeout(10_000){while(m.state.busy||m.state.smsScanRunning)delay(2)}}
 fun reset(){
  Fixture.role=Role.ADMIN;Fixture.restoreSignedOut=false;Fixture.processSessionInvalidated=false;Fixture.currentOwnerOverride=null
  Fixture.pendingFlag=false;Fixture.observationFailure=null;Fixture.listRevealFailure=null;Fixture.listRevealEntered=null;Fixture.listRevealRelease=null
  Fixture.smsQueries.clear();Fixture.observationQueries.clear();Fixture.listRevealReasons.clear();Fixture.listRevealSources.clear();Fixture.listBodies.clear()
  Fixture.smsListRevealReads=0;Fixture.observationListRevealReads=0;Fixture.paged=null;Fixture.observationPaged=null;Fixture.observationRows=emptyList()
  GatewayFixture.snapshot=GatewayStatus(true,true,1,0,null,null,null,null)
  GatewayFixture.queueSession=ObservationSessionOwner(ObservationOwner("synthetic-group","operator"),1)
  GatewayFixture.queueRows=emptyList();GatewayFixture.queueBodies=emptyMap();GatewayFixture.queueRevision=0
 }
 fun pageIds(prefix:String,cursor:String?):Page<String>{
  val start=cursor?.toIntOrNull()?:0;val end=minOf(start+5,50)
  return Page((start until end).map{"$prefix$it"},if(end<50)end.toString() else null,50,"$prefix-revision","2026-11-09T00:00:00Z")
 }
 fun observationPage(cursor:String?):Page<ObservationListRow>{
  val p=pageIds("obs-",cursor)
  return Page(p.items.map{ObservationListRow(SmsSourceRef.Observation(it),"synthetic-group","2026-11-09T00:00:00Z")},p.nextCursor,p.totalCount,p.revision,p.asOf)
 }
 reset();Fixture.paged={route,cursor,_,_->if(route=="SMS")pageIds("sms-",cursor) else Fixture.page(emptyList())}
 Fixture.observationPaged={_,cursor->observationPage(cursor)}
 val query="PRIVATE_REMOTE_SEARCH_NEEDLE";Fixture.listBodies["sms-0"]="A".repeat(220)+query;Fixture.listBodies["obs-0"]="before $query after"
 val store=Checkpoints();val m=BuriViewModel(Application(),store){System.currentTimeMillis()};idle(m);m.navigate(Route.SMS);idle(m);scanned(m)
 check(Fixture.smsListRevealReads==5&&Fixture.observationListRevealReads==5&&m.state.smsListContent.size==10)
 check(Fixture.listRevealReasons.all{it=="Automatic SMS list preview"})
 check(SmsListSearch.matches("sms-0",m.state.smsListContent[SmsSourceRef.Canonical("sms-0")],query))
 check(SmsListSearch.matches("obs-0",m.state.smsListContent[SmsSourceRef.Observation("obs-0")],query))
 check(SmsListSearch.matches("sms-0",m.state.smsListContent[SmsSourceRef.Canonical("sms-0")],"sms-0 syntheticsender"))
 check(!SmsListSearch.matches("sms-0",m.state.smsListContent[SmsSourceRef.Canonical("sms-0")],"absent"))
 Fixture.listRevealEntered=java.util.concurrent.CountDownLatch(1);Fixture.listRevealRelease=java.util.concurrent.CountDownLatch(1)
 m.search(query);m.searchSubmit();check(Fixture.listRevealEntered!!.await(5,java.util.concurrent.TimeUnit.SECONDS))
 m.searchSubmit();Fixture.listRevealRelease!!.countDown();scanned(m)
 check(m.state.smsListSearch==query&&m.state.search.isEmpty()&&m.state.smsListContent.size<=30)
 val disclosedAtCap=Fixture.listRevealSources.size;m.searchSubmit();m.more();m.moreObservations();delay(100)
 check(Fixture.listRevealSources.size==disclosedAtCap)
 check(m.state.messages?.nextCursor!=null||m.state.observations?.nextCursor!=null)
 check(Fixture.smsQueries.all{it.isEmpty()}&&Fixture.observationQueries.all{it.isEmpty()})
 check(!m.state.toString().contains(query)&&m.state.smsListContent.values.none{it.toString().contains(query)})
 val writesBefore=store.writes.size;m.listPosition(Route.SMS,null,1,9);withTimeout(5_000){while(store.writes.size<=writesBefore)delay(10)}
 check(store.writes.mapNotNull{NavigationCheckpoint.decode(it)}.filter{it.route==Route.SMS}.all{it.query.isEmpty()})
 check(NavigationCheckpoint.decode(store.value)?.let{it.route==Route.SMS&&it.index==0&&it.offset==0}==true)
 check(store.writes.none{it.contains(query)}&&Fixture.listRevealSources.size==Fixture.listRevealSources.toSet().size)
 m.openSms(SmsSourceRef.Observation("obs-0"));idle(m);check(m.state.smsListSearch==query&&m.state.smsListContent.isEmpty()&&m.state.raw!=null)
 m.back();idle(m);scanned(m);check(m.state.sheet==null&&m.state.smsListSearch==query&&m.state.smsListContent.isNotEmpty())
 m.openSms(SmsSourceRef.Observation("obs-0"));idle(m);m.closeSheet();idle(m);scanned(m);check(m.state.smsListSearch==query)
 m.onBackground();check(m.state.smsListSearch.isEmpty()&&m.state.smsListContent.isEmpty());m.viewModelScope.cancel()
 println("PASS scoped audited previews search full local bodies with bounded pages and no query in remote requests or checkpoints")

 for(change in listOf("background","permission","logout","owner")){
  reset();Fixture.observationRows=listOf(ObservationListRow(SmsSourceRef.Observation("obs-one"),"synthetic-group","2026-11-09T00:00:00Z"))
  Fixture.listRevealEntered=java.util.concurrent.CountDownLatch(1);Fixture.listRevealRelease=java.util.concurrent.CountDownLatch(1)
  val app=Application();val vm=BuriViewModel(app);idle(vm);vm.navigate(Route.SMS);idle(vm)
  check(Fixture.listRevealEntered!!.await(5,java.util.concurrent.TimeUnit.SECONDS))
  when(change){"background"->vm.onBackground();"permission"->vm.permissionsChanged();"logout"->vm.logout();else->Fixture.currentOwnerOverride="other"}
  Fixture.listRevealRelease!!.countDown();delay(100);idle(vm)
  check(vm.state.smsListContent.isEmpty()&&vm.state.smsListSearch.isEmpty())
  vm.viewModelScope.cancel()
 }
 println("PASS background, permission, logout and owner changes prevent late preview publication")

 reset();GatewayFixture.snapshot=GatewayStatus(false,false,null,0,null,null,null,"authorization_required",observationMode=true)
 Fixture.observationRows=listOf(ObservationListRow(SmsSourceRef.Observation("obs-permission"),"synthetic-group","2026-11-09T00:00:00Z"))
 Fixture.listRevealEntered=java.util.concurrent.CountDownLatch(1);Fixture.listRevealRelease=java.util.concurrent.CountDownLatch(1)
 val permissionApp=Application();val permissionVm=BuriViewModel(permissionApp);idle(permissionVm);permissionVm.navigate(Route.SMS);idle(permissionVm)
 check(Fixture.listRevealEntered!!.await(5,java.util.concurrent.TimeUnit.SECONDS));permissionApp.permissionResults[android.Manifest.permission.READ_SMS]=-1
 Fixture.listRevealRelease!!.countDown();delay(100);scanned(permissionVm)
 check(permissionVm.state.smsListContent.isEmpty()&&permissionVm.state.smsScanError)
 permissionVm.viewModelScope.cancel()
 println("PASS OS permission loss during observation reveal fences late publication before consent sync")

 reset();GatewayFixture.snapshot=GatewayStatus(false,false,null,0,null,null,null,"authorization_required",observationMode=true)
 Fixture.observationRows=listOf(ObservationListRow(SmsSourceRef.Observation("obs-coalesce"),"synthetic-group","2026-11-09T00:00:00Z"))
 Fixture.listRevealEntered=java.util.concurrent.CountDownLatch(1);Fixture.listRevealRelease=java.util.concurrent.CountDownLatch(1)
 val coalesced=BuriViewModel(Application());idle(coalesced);coalesced.navigate(Route.SMS);idle(coalesced)
 check(Fixture.listRevealEntered!!.await(5,java.util.concurrent.TimeUnit.SECONDS))
 coalesced.search("old query");coalesced.searchSubmit();coalesced.search("new query");coalesced.searchSubmit();Fixture.listRevealRelease!!.countDown();scanned(coalesced)
 check(coalesced.state.smsListSearch=="new query"&&Fixture.listRevealSources==listOf("observation:obs-coalesce")&&Fixture.observationQueries.all{it.isEmpty()})
 coalesced.viewModelScope.cancel()
 println("PASS rapid searches coalesce around one in-flight audited preview")

 for(failure in listOf("cursor_stale","session_revalidation_unavailable")){
  reset();GatewayFixture.snapshot=GatewayStatus(false,false,null,0,null,null,null,"authorization_required",observationMode=true)
  Fixture.observationPaged={_,cursor->
   if(cursor==null)Page(listOf(ObservationListRow(SmsSourceRef.Observation("obs-first"),"synthetic-group","2026-11-09T00:00:00Z")),"next",2,"v1","2026-11-09T00:00:00Z")
   else if(failure=="cursor_stale")Page(listOf(ObservationListRow(SmsSourceRef.Observation("obs-next"),"synthetic-group","2026-11-09T00:00:00Z")),null,2,"changed","2026-11-09T00:00:00Z")
   else throw ApiFailure(failure,503,false)
  }
  val vm=BuriViewModel(Application());idle(vm);vm.navigate(Route.SMS);idle(vm);scanned(vm);check(vm.state.smsListContent.isNotEmpty())
  vm.search("missing");vm.searchSubmit();scanned(vm)
  check(vm.state.smsScanError&&vm.state.smsListContent.isEmpty()&&vm.state.smsListSearch=="missing")
  vm.viewModelScope.cancel()
 }
 println("PASS cursor invalidation or uncertain authority clears hydrated content and leaves search incomplete")

 reset();Fixture.observationRows=listOf(ObservationListRow(SmsSourceRef.Observation("obs-denied"),"synthetic-group","2026-11-09T00:00:00Z"))
 Fixture.listRevealFailure=ApiFailure("access_denied",403,false)
 val denied=BuriViewModel(Application());idle(denied);denied.navigate(Route.SMS);idle(denied);scanned(denied)
 check(denied.state.smsScanError&&denied.state.smsListContent.isEmpty())
 denied.search("missing");check(denied.state.smsListSearch=="missing"&&denied.state.smsScanError)
 denied.viewModelScope.cancel();Fixture.listRevealFailure=null
 println("PASS denied list disclosure remains unavailable and cannot claim an exhaustive empty search")

 reset();GatewayFixture.snapshot=GatewayStatus(false,false,null,0,null,null,null,"authorization_required",observationMode=true)
 GatewayFixture.queueRevision=1;GatewayFixture.queueRows=listOf(QueuedObservationRow("same-id","Local sender","2026-11-09T00:00:00Z","local preview"))
 GatewayFixture.queueBodies=mapOf("same-id" to ("A".repeat(220)+query))
 Fixture.observationRows=listOf(ObservationListRow(SmsSourceRef.Observation("same-id"),"synthetic-group","2026-11-09T00:00:00Z"))
 Fixture.listBodies["same-id"]="remote $query"
 val allApp=Application();val all=BuriViewModel(allApp);idle(all);all.navigate(Route.SMS);idle(all);scanned(all)
 check(all.state.filter=="all"&&all.state.queuedObservations?.single()?.id=="same-id"&&all.state.observations?.items?.single()?.source?.id=="same-id")
 all.search(query);all.searchSubmit();withTimeout(5_000){while(all.state.queuedObservations==null)delay(5)};scanned(all)
 check(all.state.queuedObservations?.single()?.id=="same-id"&&all.state.observations?.items?.single()?.source?.id=="same-id")
 check(Fixture.smsQueries.all{it.isEmpty()}&&Fixture.observationQueries.all{it.isEmpty()})
 allApp.permissionResults[android.Manifest.permission.READ_SMS]=-1;all.permissionsChanged()
 check(all.state.queuedObservations==null);all.viewModelScope.cancel()
 println("PASS All includes separately identified local and remote rows with local full-body search and permission fencing")
}
