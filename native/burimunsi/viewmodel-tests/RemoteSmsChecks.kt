package rw.ikanisa.burimunsi.remotesmstests

import android.app.Application
import app.cool.mobile.BuildConfig
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.snapshots.SnapshotApplyConflictException
import java.util.Base64
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.receiveAsFlow
import androidx.lifecycle.onFixtureMain
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.*
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.*
import rw.ikanisa.burimunsi.gateway.GatewayFixture
import rw.ikanisa.burimunsi.ui.BuriViewModel
import rw.ikanisa.burimunsi.ui.UiState

private class Checkpoints : NavigationCheckpointStore {
    @Volatile private var value: String? = null
    val writes = CopyOnWriteArrayList<String>()
    private val accepted = Channel<String>(Channel.UNLIMITED)
    override fun read() = value
    override fun write(value: String) {
        this.value = value
        writes.add(value)
        check(accepted.trySend(value).isSuccess)
    }
    override fun clear() { value = null }

    suspend fun awaitWrite(savedAt: Long): NavigationCheckpoint = withTimeout(5_000) {
        accepted.receiveAsFlow().map { checkNotNull(NavigationCheckpoint.decode(it)) }.first { it.savedAt == savedAt }
    }
}

private suspend fun BuriViewModel.awaitState(predicate: (UiState) -> Boolean) = withTimeout(10_000) {
    while (!onFixtureMain { predicate(state) }) delay(2)
}

private suspend fun idle(model: BuriViewModel) = model.awaitState { !it.starting && !it.busy }
private suspend fun scanned(model: BuriViewModel) =
    model.awaitState { !it.starting && !it.busy && !it.smsScanRunning }
private suspend fun BuriViewModel.dispose() = viewModelScope.coroutineContext[Job]!!.cancelAndJoin()

/** Reproduce the ordering seen when the queue IO publisher overlaps scan completion on Main. */
private suspend fun preserveCompletedScan() = coroutineScope {
    val screen = mutableStateOf(UiState(smsScanRunning=true))
    val read = CompletableDeferred<Unit>()
    val release = java.util.concurrent.CountDownLatch(1)
    val publication = async(Dispatchers.IO) {
        runCatching {
            Snapshot.withMutableSnapshot {
                val initial = screen.value
                read.complete(Unit)
                check(release.await(5, java.util.concurrent.TimeUnit.SECONDS))
                screen.value = initial.copy(queuedObservations=emptyList())
            }
        }.exceptionOrNull()
    }
    try {
        withTimeout(5_000) { read.await() }
        screen.value = screen.value.copy(smsScanRunning=false)
    } finally {
        release.countDown()
    }
    check(publication.await() is SnapshotApplyConflictException && !screen.value.smsScanRunning) {
        "A stale queue publication revived a completed disclosure scan"
    }
    println("PASS concurrent queue publication preserves the acknowledged scan completion")
}

/** Actual ViewModel with synthetic repository/session/platform doubles. */
fun main()=runBlocking {
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
 if (!BuildConfig.IS_GATEWAY) {
  for (role in listOf(Role.STAFF, Role.ADMIN)) {
   reset()
   Fixture.role = role
   val store = Checkpoints()
   val time = AtomicLong(System.currentTimeMillis())
   val staff = BuriViewModel(Application(), store) { time.get() }
   idle(staff)
   staff.onFixtureMain { navigate(Route.SMS); openSms(SmsSourceRef.Observation("forbidden")); permissionsChanged() }
   idle(staff)
   staff.onFixtureMain { time.incrementAndGet(); onBackground() }
   val saved = store.awaitWrite(time.get())
   check(saved.route == Route.HOME && saved.query.isEmpty())
   check(staff.state.raw == null && staff.state.smsListContent.isEmpty() && !staff.state.smsScanRunning)
   check(Fixture.smsQueries.isEmpty() && Fixture.observationQueries.isEmpty() && Fixture.listRevealSources.isEmpty())
   staff.dispose()
  }
  println("PASS Staff installation keeps both operator roles outside SMS queries, disclosure and checkpoint restoration")
  return@runBlocking
 }
 preserveCompletedScan()
 reset();Fixture.paged={route,cursor,_,_->if(route=="SMS")pageIds("sms-",cursor) else Fixture.page(emptyList())}
 Fixture.observationPaged={_,cursor->observationPage(cursor)}
 val query="PRIVATE_REMOTE_SEARCH_NEEDLE";Fixture.listBodies["sms-0"]="A".repeat(220)+query;Fixture.listBodies["obs-0"]="before $query after"
 val store=Checkpoints();val time=AtomicLong(System.currentTimeMillis())
 val m=BuriViewModel(Application(),store){time.get()};idle(m);m.onFixtureMain { navigate(Route.SMS) };scanned(m)
 check(Fixture.smsListRevealReads==5&&Fixture.observationListRevealReads==5&&m.state.smsListContent.size==10)
 check(Fixture.listRevealReasons.all{it=="Automatic SMS list preview"})
 check(SmsListSearch.matches("sms-0",m.state.smsListContent[SmsSourceRef.Canonical("sms-0")],query))
 check(SmsListSearch.matches("obs-0",m.state.smsListContent[SmsSourceRef.Observation("obs-0")],query))
 check(SmsListSearch.matches("sms-0",m.state.smsListContent[SmsSourceRef.Canonical("sms-0")],"sms-0 syntheticsender"))
 check(!SmsListSearch.matches("sms-0",m.state.smsListContent[SmsSourceRef.Canonical("sms-0")],"absent"))
 Fixture.listRevealEntered=java.util.concurrent.CountDownLatch(1);Fixture.listRevealRelease=java.util.concurrent.CountDownLatch(1)
 m.onFixtureMain { search(query); searchSubmit() };check(Fixture.listRevealEntered!!.await(5,java.util.concurrent.TimeUnit.SECONDS))
 m.onFixtureMain { searchSubmit() };Fixture.listRevealRelease!!.countDown();scanned(m)
 check(m.state.smsListSearch==query&&m.state.search.isEmpty()&&m.state.smsListContent.size<=30)
 val disclosedAtCap=Fixture.listRevealSources.size
 m.onFixtureMain { searchSubmit(); more(); moreObservations() };scanned(m)
 check(Fixture.listRevealSources.size==disclosedAtCap)
 check(m.state.messages?.nextCursor!=null||m.state.observations?.nextCursor!=null)
 check(Fixture.smsQueries.all{it.isEmpty()}&&Fixture.observationQueries.all{it.isEmpty()})
 check(!m.state.toString().contains(query)&&m.state.smsListContent.values.none{it.toString().contains(query)})
 m.onFixtureMain { time.incrementAndGet(); listPosition(Route.SMS,null,1,9) }
 val saved = store.awaitWrite(time.get())
 check(saved.ownerId=="operator" && saved.groupId=="synthetic-group" && saved.route==Route.SMS &&
       saved.query.isEmpty() && saved.index==0 && saved.offset==0)
 val writes = store.writes.toList()
 check(writes.map { checkNotNull(NavigationCheckpoint.decode(it)) }.filter { it.route == Route.SMS }.all { it.query.isEmpty() })
 check(writes.none { Base64.getDecoder().decode(it).toString(Charsets.ISO_8859_1).contains(query) })
 val disclosures = Fixture.listRevealSources.toList()
 check(disclosures.size == disclosures.distinct().size) { "A preview issued a second audited read" }
 m.onFixtureMain { openSms(SmsSourceRef.Observation("obs-0")) };idle(m)
 check(m.state.smsListSearch==query && m.state.smsListContent.isEmpty() && m.state.raw!=null)
 m.onFixtureMain { back() };scanned(m);check(m.state.sheet==null&&m.state.smsListSearch==query&&m.state.smsListContent.isNotEmpty())
 m.onFixtureMain { openSms(SmsSourceRef.Observation("obs-0")) };idle(m);m.onFixtureMain { closeSheet() };scanned(m);check(m.state.smsListSearch==query)
 m.onFixtureMain { onBackground() };check(m.state.smsListSearch.isEmpty()&&m.state.smsListContent.isEmpty());m.dispose()
 println("PASS scoped audited previews search full local bodies with bounded pages and no query in remote requests or checkpoints")

 for(change in listOf("background","permission","logout","owner")){
  reset();Fixture.observationRows=listOf(ObservationListRow(SmsSourceRef.Observation("obs-one"),"synthetic-group","2026-11-09T00:00:00Z"))
  Fixture.listRevealEntered=java.util.concurrent.CountDownLatch(1);Fixture.listRevealRelease=java.util.concurrent.CountDownLatch(1)
  val app=Application();val vm=BuriViewModel(app);idle(vm)
  val lifetimeJobs = vm.onFixtureMain { viewModelScope.coroutineContext[Job]!!.children.toSet() }
  vm.onFixtureMain { navigate(Route.SMS) };idle(vm)
  check(Fixture.listRevealEntered!!.await(5,java.util.concurrent.TimeUnit.SECONDS))
  val inFlight = vm.onFixtureMain {
   val jobs = viewModelScope.coroutineContext[Job]!!.children.filterNot { it in lifetimeJobs }.toList()
   check(jobs.isNotEmpty())
   when(change){"background"->onBackground();"permission"->permissionsChanged();"logout"->logout();else->Fixture.currentOwnerOverride="other"}
   jobs
  }
  Fixture.listRevealRelease!!.countDown();withTimeout(5_000) { inFlight.joinAll() };idle(vm)
  check(vm.state.smsListContent.isEmpty()&&vm.state.smsListSearch.isEmpty())
  vm.dispose()
 }
 println("PASS background, permission, logout and owner changes prevent late preview publication")

 reset();GatewayFixture.snapshot=GatewayStatus(false,false,null,0,null,null,null,"authorization_required",observationMode=true)
 Fixture.observationRows=listOf(ObservationListRow(SmsSourceRef.Observation("obs-permission"),"synthetic-group","2026-11-09T00:00:00Z"))
 Fixture.listRevealEntered=java.util.concurrent.CountDownLatch(1);Fixture.listRevealRelease=java.util.concurrent.CountDownLatch(1)
 val permissionApp=Application();val permissionVm=BuriViewModel(permissionApp);idle(permissionVm);permissionVm.onFixtureMain { navigate(Route.SMS) };idle(permissionVm)
 check(Fixture.listRevealEntered!!.await(5,java.util.concurrent.TimeUnit.SECONDS));permissionVm.onFixtureMain { permissionApp.permissionResults[android.Manifest.permission.READ_SMS]=-1 }
 Fixture.listRevealRelease!!.countDown();scanned(permissionVm)
 check(permissionVm.state.smsListContent.isEmpty()&&permissionVm.state.smsScanError)
 permissionVm.dispose()
 println("PASS OS permission loss during observation reveal fences late publication before consent sync")

 reset();GatewayFixture.snapshot=GatewayStatus(false,false,null,0,null,null,null,"authorization_required",observationMode=true)
 Fixture.observationRows=listOf(ObservationListRow(SmsSourceRef.Observation("obs-coalesce"),"synthetic-group","2026-11-09T00:00:00Z"))
 Fixture.listRevealEntered=java.util.concurrent.CountDownLatch(1);Fixture.listRevealRelease=java.util.concurrent.CountDownLatch(1)
 val coalesced=BuriViewModel(Application());idle(coalesced);coalesced.onFixtureMain { navigate(Route.SMS) };idle(coalesced)
 check(Fixture.listRevealEntered!!.await(5,java.util.concurrent.TimeUnit.SECONDS))
 coalesced.onFixtureMain { search("old query"); searchSubmit(); search("new query"); searchSubmit() };Fixture.listRevealRelease!!.countDown();scanned(coalesced)
 check(coalesced.state.smsListSearch=="new query"&&Fixture.listRevealSources==listOf("observation:obs-coalesce")&&Fixture.observationQueries.all{it.isEmpty()})
 coalesced.dispose()
 println("PASS rapid searches coalesce around one in-flight audited preview")

 for(failure in listOf("cursor_stale","session_revalidation_unavailable")){
  reset();GatewayFixture.snapshot=GatewayStatus(false,false,null,0,null,null,null,"authorization_required",observationMode=true)
  Fixture.observationPaged={_,cursor->
   if(cursor==null)Page(listOf(ObservationListRow(SmsSourceRef.Observation("obs-first"),"synthetic-group","2026-11-09T00:00:00Z")),"next",2,"v1","2026-11-09T00:00:00Z")
   else if(failure=="cursor_stale")Page(listOf(ObservationListRow(SmsSourceRef.Observation("obs-next"),"synthetic-group","2026-11-09T00:00:00Z")),null,2,"changed","2026-11-09T00:00:00Z")
   else throw ApiFailure(failure,503,false)
  }
  val vm=BuriViewModel(Application());idle(vm);vm.onFixtureMain { navigate(Route.SMS) };scanned(vm);check(vm.state.smsListContent.isNotEmpty())
  vm.onFixtureMain { search("missing"); searchSubmit() };scanned(vm)
  check(vm.state.smsScanError&&vm.state.smsListContent.isEmpty()&&vm.state.smsListSearch=="missing")
  vm.dispose()
 }
 println("PASS cursor invalidation or uncertain authority clears hydrated content and leaves search incomplete")

 val permissionFailures = mutableListOf<String>()
 for (revokeDuringRead in listOf(false, true)) {
  reset()
  GatewayFixture.snapshot = GatewayStatus(false, false, null, 0, null, null, null, "authorization_required", observationMode = true)
  val entered = CountDownLatch(1)
  val release = CountDownLatch(1)
  val nextReads = AtomicInteger()
  fun row(id: String) = ObservationListRow(SmsSourceRef.Observation(id), "synthetic-group", "2026-11-09T00:00:00Z")
  Fixture.observationPaged = { _, cursor ->
   if (cursor == null) Page(listOf(row("first")), "next", 2, "v1", "2026-11-09T00:00:00Z")
   else {
    nextReads.incrementAndGet()
    entered.countDown()
    check(release.await(5, TimeUnit.SECONDS))
    Page(listOf(row("next")), null, 2, "v1", "2026-11-09T00:00:00Z")
   }
  }
  val phone = Application()
  val inbox = BuriViewModel(phone)
  try {
   idle(inbox); inbox.onFixtureMain { navigate(Route.SMS) }; scanned(inbox)
   check(inbox.state.smsListContent.keys == setOf(SmsSourceRef.Observation("first")))
   inbox.onFixtureMain {
    if (!revokeDuringRead) {
     phone.permissionResults[android.Manifest.permission.READ_SMS] = -1
     release.countDown()
    }
    moreObservations()
   }
   if (revokeDuringRead) {
    check(entered.await(5, TimeUnit.SECONDS))
    inbox.onFixtureMain { phone.permissionResults[android.Manifest.permission.READ_SMS] = -1 }
    release.countDown()
   }
   scanned(inbox)
   val displayed = inbox.state.observations?.items.orEmpty().map { it.source.id }
   val expectedRequests = if (revokeDuringRead) 1 else 0
   if (nextReads.get() != expectedRequests || displayed != listOf("first") ||
       !inbox.state.smsScanError || inbox.state.smsListContent.isNotEmpty() ||
       "observation:next" in Fixture.listRevealSources) {
    permissionFailures += if (revokeDuringRead) "page published after permission loss" else "page read without permission"
   }
   inbox.onFixtureMain {
    phone.permissionResults[android.Manifest.permission.READ_SMS] = 0
    permissionsChanged()
    refresh()
   }
   scanned(inbox)
   inbox.onFixtureMain { moreObservations() }; scanned(inbox)
   check(inbox.state.observations?.items?.map { it.source.id } == listOf("first", "next"))
   check(inbox.state.smsListContent[SmsSourceRef.Observation("next")] != null && !inbox.state.smsScanError)
  } finally { release.countDown(); inbox.dispose() }
 }
 reset()
 GatewayFixture.snapshot = GatewayStatus(false, false, null, 0, null, null, null, "authorization_required", observationMode = true)
 val firstEntered = CountDownLatch(1)
 val firstRelease = CountDownLatch(1)
 Fixture.observationPaged = { _, cursor ->
  check(cursor == null)
  firstEntered.countDown()
  check(firstRelease.await(5, TimeUnit.SECONDS))
  observationPage(null)
 }
 val firstPhone = Application()
 val firstInbox = BuriViewModel(firstPhone)
 try {
  idle(firstInbox); firstInbox.onFixtureMain { navigate(Route.SMS) }
  check(firstEntered.await(5, TimeUnit.SECONDS))
  firstInbox.onFixtureMain { firstPhone.permissionResults[android.Manifest.permission.READ_SMS] = -1 }
  firstRelease.countDown()
  scanned(firstInbox)
  if (firstInbox.state.observations != null || !firstInbox.state.observationUnavailable ||
      firstInbox.state.smsListContent.isNotEmpty() || Fixture.listRevealSources.isNotEmpty()) {
   permissionFailures += "first page published after permission loss"
  }
 } finally { firstRelease.countDown(); firstInbox.dispose() }
 check(permissionFailures.isEmpty()) { permissionFailures.joinToString() }
 println("PASS observation pages check Android access before the request and before publication, then recover on grant")

 reset();Fixture.observationRows=listOf(ObservationListRow(SmsSourceRef.Observation("obs-denied"),"synthetic-group","2026-11-09T00:00:00Z"))
 Fixture.listRevealFailure=ApiFailure("access_denied",403,false)
 val denied=BuriViewModel(Application());idle(denied);denied.onFixtureMain { navigate(Route.SMS) };scanned(denied)
 check(denied.state.smsScanError&&denied.state.smsListContent.isEmpty())
 denied.onFixtureMain { search("missing") };check(denied.state.smsListSearch=="missing"&&denied.state.smsScanError)
 denied.dispose();Fixture.listRevealFailure=null
 println("PASS denied list disclosure remains unavailable and cannot claim an exhaustive empty search")

 reset();GatewayFixture.snapshot=GatewayStatus(false,false,null,0,null,null,null,"authorization_required",observationMode=true)
 GatewayFixture.queueRevision=1;GatewayFixture.queueRows=listOf(QueuedObservationRow("same-id","Local sender","2026-11-09T00:00:00Z","local preview"))
 GatewayFixture.queueBodies=mapOf("same-id" to ("A".repeat(220)+query))
 Fixture.observationRows=listOf(ObservationListRow(SmsSourceRef.Observation("same-id"),"synthetic-group","2026-11-09T00:00:00Z"))
 Fixture.listBodies["same-id"]="remote $query"
 val allApp=Application();val all=BuriViewModel(allApp);idle(all);all.onFixtureMain { navigate(Route.SMS) };scanned(all)
 check(all.state.filter=="all"&&all.state.queuedObservations?.single()?.id=="same-id"&&all.state.observations?.items?.single()?.source?.id=="same-id")
 all.onFixtureMain { search(query); searchSubmit() };all.awaitState { it.queuedObservations!=null && !it.smsScanRunning }
 check(all.state.queuedObservations?.single()?.id=="same-id"&&all.state.observations?.items?.single()?.source?.id=="same-id")
 check(Fixture.smsQueries.all{it.isEmpty()}&&Fixture.observationQueries.all{it.isEmpty()})
 all.onFixtureMain { allApp.permissionResults[android.Manifest.permission.READ_SMS]=-1; permissionsChanged() }
 check(all.state.queuedObservations==null);all.dispose()
 println("PASS All includes separately identified local and remote rows with local full-body search and permission fencing")
}
