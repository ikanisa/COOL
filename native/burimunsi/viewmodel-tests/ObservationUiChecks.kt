package rw.ikanisa.burimunsi.observationuitests

import android.app.Application
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import rw.ikanisa.burimunsi.core.*
import rw.ikanisa.burimunsi.data.Fixture
import rw.ikanisa.burimunsi.data.ApiFailure
import rw.ikanisa.burimunsi.gateway.GatewayFixture
import rw.ikanisa.burimunsi.ui.BuriViewModel
import rw.ikanisa.burimunsi.ui.Sheet

private class QueueCheckpoint:NavigationCheckpointStore {
    @Volatile var value:String?=null
    val writes=java.util.concurrent.CopyOnWriteArrayList<String>()
    override fun read()=value
    override fun write(value:String){this.value=value;writes.add(value)}
    override fun clear(){value=null}
}

/** Real ViewModel with synthetic repository and Android doubles, not a device test. */
fun main()=runBlocking {
    suspend fun idle(model:BuriViewModel){withTimeout(5_000){while(model.state.busy)delay(10)}}
    val body="You have received 1,000 RWF. FT Id: REF-1 😀"
    val amount="1,000 RWF";val reference="REF-1";val ai=body.indexOf(amount);val ri=body.indexOf(reference)
    val hints=ObservationHintSet(1,"partial_inbox_display_only","approved-v1","a".repeat(64),Values.sha256(body),
        listOf(ObservationHint("quoted_incoming_amount",amount,ai,ai+amount.length),ObservationHint("quoted_reference",reference,ri,ri+reference.length)))
    check(ObservationHintValidation.valid(body,hints))
    check(!ObservationHintValidation.valid(body,hints.copy(bodySha256="b".repeat(64))))
    check(!ObservationHintValidation.valid(body,hints.copy(hints=listOf(hints.hints.first().copy(text="9,000 RWF")))))
    check(!ObservationHintValidation.valid(body,hints.copy(hints=listOf(hints.hints.first(),hints.hints.first()))))
    check(!ObservationHintValidation.valid(body,hints.copy(hints=listOf(hints.hints.first().copy(kind="wallet")))))
    val emoji=body.indexOf("😀")
    check(!ObservationHintValidation.valid(body,hints.copy(hints=listOf(ObservationHint("quoted_reference",body.substring(emoji,emoji+1),emoji,emoji+1)))))
    println("PASS provisional hints require exact body digest, supported unique kinds and valid UTF-16 spans")
    Fixture.role=Role.ADMIN;Fixture.restoreSignedOut=false
    Fixture.observationReads=0;Fixture.observationRevealReads=0;Fixture.rawReads=0
    Fixture.observationBody=body;Fixture.observationHints=hints
    val source=SmsSourceRef.Observation("s-1")
    Fixture.observationRows=listOf(ObservationListRow(source,"synthetic-group","2026-11-09T00:00:00Z"))
    GatewayFixture.snapshot=GatewayStatus(false,false,null,0,null,null,null,"authorization_required",observationMode=true)
    val model=BuriViewModel(Application());idle(model)
    model.navigate(Route.SMS);idle(model)
    check(model.state.route==Route.SMS&&model.state.messages==null&&model.state.observations?.items?.single()?.source==source)
    model.openSms(source);idle(model)
    check(model.state.rawSource==source&&model.state.raw?.transactionId==null&&model.state.observationHints==hints&&Fixture.observationRevealReads==1&&Fixture.rawReads==0)
    model.closeSheet();model.openSms(SmsSourceRef.Canonical("s-1"));idle(model)
    check(Fixture.rawReads==1&&Fixture.observationRevealReads==1&&model.state.rawSource is SmsSourceRef.Canonical)
    model.onBackground();check(model.state.raw==null&&model.state.observationHints==null&&model.state.sheet==null)
    model.viewModelScope.cancel()
    println("PASS unpaired Admin sees typed observations and uses the separate audited reveal; matching IDs do not select the canonical endpoint")
    val app=Application();GatewayFixture.queueSession=ObservationSessionOwner(ObservationOwner("synthetic-group","operator"),1)
    val localQuery="PRIVATE_LOCAL_SEARCH_NEEDLE";val localBody="A".repeat(220)+localQuery
    val localPreview=QueuedObservationPreview.from(localBody)
    GatewayFixture.queueRevision=1;GatewayFixture.queueRows=listOf(QueuedObservationRow("request-1","SyntheticSender","2026-11-09T00:00:00Z",localPreview))
    GatewayFixture.queueBodies=mapOf("request-1" to localBody)
    val checkpoint=QueueCheckpoint();val queueModel=BuriViewModel(app,checkpoint){System.currentTimeMillis()};idle(queueModel);Fixture.observationFailure=ApiFailure("connection_unavailable",0)
    queueModel.navigate(Route.SMS);idle(queueModel)
    check(queueModel.state.observationUnavailable&&queueModel.state.offline&&queueModel.presentation.showRecords)
    val beforeReads=Fixture.observationReads
    queueModel.setFilter("queued");idle(queueModel)
    check(queueModel.state.queuedObservations?.single()?.id=="request-1"&&!queueModel.state.queuedUnavailable&&Fixture.observationReads==beforeReads)
    check(queueModel.state.queuedObservations?.single()?.preview==localPreview)
    Fixture.smsQueries.clear();Fixture.observationQueries.clear()
    queueModel.search(localQuery);queueModel.searchSubmit();idle(queueModel)
    check(queueModel.state.queuedSearch==localQuery&&queueModel.state.search==""&&queueModel.state.queuedObservations?.single()?.id=="request-1")
    check(Fixture.smsQueries.isEmpty()&&Fixture.observationQueries.isEmpty())
    check(!queueModel.state.toString().contains(localQuery)&&!queueModel.state.toString().contains(localPreview))
    check(!queueModel.state.queuedObservations!!.single().toString().contains(localPreview))
    queueModel.listPosition(Route.SMS,null,1,0)
    withTimeout(5_000){while(checkpoint.writes.none{NavigationCheckpoint.decode(it)?.filter=="queued"})delay(10)}
    check(checkpoint.writes.mapNotNull{NavigationCheckpoint.decode(it)}.all{it.query!=localQuery})
    check(checkpoint.writes.mapNotNull{NavigationCheckpoint.decode(it)}.filter{it.filter=="queued"}.all{it.query.isEmpty()})
    check(checkpoint.writes.none{it.contains(localQuery)||it.contains(localPreview)})
    val bounded="X".repeat(79)+"😀";queueModel.search(bounded)
    check(queueModel.state.queuedSearch=="X".repeat(79))
    queueModel.search(localQuery);queueModel.searchSubmit();idle(queueModel)
    Fixture.observationFailure=null;queueModel.setFilter("all");idle(queueModel)
    check(queueModel.state.queuedSearch.isEmpty()&&queueModel.state.search.isEmpty()&&queueModel.state.queuedObservations?.single()?.id=="request-1")
    check(Fixture.observationQueries.isNotEmpty()&&Fixture.observationQueries.all{it!=localQuery}&&Fixture.smsQueries.all{it!=localQuery})
    queueModel.setFilter("queued");idle(queueModel);queueModel.search(localQuery);queueModel.searchSubmit();idle(queueModel)
    queueModel.onBackground();check(queueModel.state.queuedSearch.isEmpty()&&queueModel.state.queuedObservations==null)
    queueModel.onForeground();idle(queueModel)
    GatewayFixture.queueRevision++;GatewayFixture.queueRows=listOf(QueuedObservationRow("request-2","SyntheticSender","2026-11-09T00:01:00Z","Synthetic preview"));GatewayFixture.queueBodies=mapOf("request-2" to localBody)
    queueModel.refresh();idle(queueModel);check(queueModel.state.queuedObservations?.single()?.id=="request-2")
    queueModel.search(localQuery);queueModel.searchSubmit();idle(queueModel)
    app.permissionResults[android.Manifest.permission.READ_SMS]=-1;queueModel.permissionsChanged()
    check(queueModel.state.queuedSearch.isEmpty()&&queueModel.state.queuedObservations==null)
    queueModel.refresh();idle(queueModel);check(queueModel.state.queuedObservations.isNullOrEmpty()&&queueModel.state.queuedUnavailable)
    app.permissionResults.clear();queueModel.permissionsChanged();queueModel.refresh();idle(queueModel)
    check(queueModel.state.queuedObservations?.single()?.id=="request-2")
    queueModel.search(localQuery);queueModel.searchSubmit();idle(queueModel)
    queueModel.logout();check(queueModel.state.queuedSearch.isEmpty()&&queueModel.state.queuedObservations==null);idle(queueModel);check(queueModel.state.operator==null)
    queueModel.viewModelScope.cancel();Fixture.observationFailure=null
    println("PASS local preview and full-body search stay out of remote queries, state rendering and navigation checkpoints; filter, background, permission and logout clear them")

    val oldCheckpoint=QueueCheckpoint()
    oldCheckpoint.write(NavigationCheckpoint("operator","synthetic-group",System.currentTimeMillis(),Route.SMS,query=localQuery,filter="queued").encode())
    val restored=BuriViewModel(Application(),oldCheckpoint){System.currentTimeMillis()};idle(restored)
    check(restored.state.route==Route.SMS&&restored.state.filter=="queued"&&restored.state.search.isEmpty()&&restored.state.queuedSearch.isEmpty())
    restored.viewModelScope.cancel()
    println("PASS an older queued bookmark cannot restore a local search")

    val invalidated=BuriViewModel(Application());idle(invalidated);invalidated.navigate(Route.SMS);idle(invalidated);invalidated.setFilter("queued");idle(invalidated)
    invalidated.search(localQuery);invalidated.searchSubmit();idle(invalidated)
    check(invalidated.state.queuedObservations?.single()?.id=="request-2")
    Fixture.invalidateProcessSession()
    withTimeout(5_000){while(invalidated.state.operator!=null)delay(10)}
    check(invalidated.state.queuedSearch.isEmpty()&&invalidated.state.queuedObservations==null)
    invalidated.viewModelScope.cancel();Fixture.processSessionInvalidated=false
    println("PASS session invalidation clears the local search and preview")

    val fenceApp=Application();GatewayFixture.queueSession=ObservationSessionOwner(ObservationOwner("synthetic-group","operator"),2)
    val fenced=BuriViewModel(fenceApp);idle(fenced);fenced.navigate(Route.SMS);idle(fenced)
    GatewayFixture.queueReadEntered=java.util.concurrent.CountDownLatch(1);GatewayFixture.queueReadRelease=java.util.concurrent.CountDownLatch(1)
    fenced.setFilter("queued");check(GatewayFixture.queueReadEntered!!.await(5,java.util.concurrent.TimeUnit.SECONDS))
    GatewayFixture.queueSession=ObservationSessionOwner(ObservationOwner("synthetic-group","other-operator"),3)
    GatewayFixture.queueReadRelease!!.countDown();idle(fenced)
    check(fenced.state.queuedObservations.isNullOrEmpty()&&fenced.state.queuedUnavailable)
    GatewayFixture.queueReadEntered=null;GatewayFixture.queueReadRelease=null;fenced.viewModelScope.cancel()
    println("PASS an account change during the local queue read cannot publish the prior account's rows")

    // Android may kill the process as a permission is revoked while the SMS
    // route is bookmarked. The server disables capture consent and denies its
    // observation page until permission and consent are restored.
    val revokedApp=Application().apply {
        permissionResults[android.Manifest.permission.READ_SMS]=-1
        permissionResults[android.Manifest.permission.RECEIVE_SMS]=-1
    }
    val revokedCheckpoint=QueueCheckpoint().apply {
        write(NavigationCheckpoint("operator","synthetic-group",System.currentTimeMillis(),Route.SMS).encode())
    }
    Fixture.observationFailure=ApiFailure("access_denied",403)
    val previousObservationReads=Fixture.observationReads
    val revoked=BuriViewModel(revokedApp,revokedCheckpoint){System.currentTimeMillis()};idle(revoked)
    revoked.onForeground();idle(revoked)
    check(Fixture.observationReads==previousObservationReads&&revoked.state.observationUnavailable)
    check(revoked.screenGate==ScreenGate.OPEN&&revoked.state.operator?.role==Role.ADMIN)
    revoked.navigate(Route.SETTINGS);idle(revoked)
    check(revoked.state.route==Route.SETTINGS&&!revoked.smsAccessGranted)
    // Granting permission can race the asynchronous consent update. Its 403
    // leaves the SMS stream unavailable but must not lock navigation.
    revokedApp.permissionResults.clear();revoked.permissionsChanged()
    revoked.navigate(Route.SMS);idle(revoked)
    revoked.onBackground();revoked.onForeground();idle(revoked)
    check(revoked.screenGate==ScreenGate.OPEN&&revoked.state.observationUnavailable)
    revoked.navigate(Route.SETTINGS);idle(revoked)
    check(revoked.state.route==Route.SETTINGS&&revoked.smsAccessGranted)
    revoked.viewModelScope.cancel();Fixture.observationFailure=null
    println("PASS SMS permission revocation and delayed consent keep Settings reachable")

    Fixture.role=Role.STAFF
    val staff=BuriViewModel(Application());idle(staff);val reads=Fixture.observationReads
    staff.navigate(Route.SMS);idle(staff);staff.openSms(source);idle(staff)
    check(staff.state.route!=Route.SMS&&staff.state.sheet!=Sheet.RAW&&Fixture.observationReads==reads)
    staff.viewModelScope.cancel()
    println("PASS the same receiver build denies Staff SMS navigation and disclosure")
}
