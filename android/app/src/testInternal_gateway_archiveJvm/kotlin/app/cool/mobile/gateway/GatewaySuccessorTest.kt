package app.cool.mobile.gateway

import android.content.Context
import android.util.AtomicFileFaults
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URL
import java.nio.file.Files
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.security.cert.Certificate
import java.security.spec.ECGenParameterSpec
import java.time.Instant
import java.util.Base64
import java.util.UUID
import javax.crypto.spec.SecretKeySpec
import javax.net.ssl.HttpsURLConnection

class GatewaySuccessorTest {
    private fun id() = UUID.randomUUID().toString()
    private fun observation(name:String) = File(System.getProperty("collect.successor.fixtures"),name).readText()
    private fun grant() = JSONObject(observation("observed-successor-grant.json"))
    private fun arm() = JSONObject(observation("observed-successor-arm.json"))
    private fun callbacks() = JSONArray(observation("observed-multipart-callbacks.json"))
    private fun ack() = JSONObject(observation("observed-exact-successor-archive-ack.json"))
    private fun failure(block:()->Unit) { try { block(); fail("Expected refusal") } catch(_:GatewayStateException) {} }
    private fun observations() = GatewayObservations(true,true,true,true,true,true,true,1,true)
    private fun payload(a:JSONObject) = JSONObject().put("route",a.getJSONObject("route")).put("attempt_id",a.getString("attempt_id")).put("fence_version",a.getLong("fence_version"))
        .put("body_sha256",a.getString("body_sha256")).put("destination_sha256",a.getString("destination_sha256")).put("callback_requests",a.getJSONArray("callback_requests"))
    private fun wrapper(e:JSONObject,r:JSONObject):JSONObject = JSONObject().put("contract_version",e.getInt("contract_version")).put("action",e.getString("action"))
        .put("device_id",e.getString("device_id")).put("request_id",e.getString("request_id")).put("result",r).also { if(isSuccessorEnvelope(e))it.put("protocol_family",SUCCESSOR_FAMILY).put("audience",SUCCESSOR_AUDIENCE) }
    @Test fun retainedSqlGrantAndArmCarrySeparateTupleThroughClosedDecoder() {
        val g=grant();val a=arm();val lease=parseSuccessorGrant(g.getString("request_id"),g.getString("device_id"),g,Instant.parse(g.getString("issued_at")))!!
        val rows=callbacks();val p=JSONObject().put("route",g.getJSONObject("route")).put("attempt_id",g.getString("attempt_id")).put("fence_version",g.getLong("fence_version"))
            .put("body_sha256",g.getString("body_sha256")).put("destination_sha256",g.getString("destination_sha256")).put("reservation_sha256",a.getString("reservation_sha256"))
            .put("callbacks",JSONArray().put(JSONObject().put("segment_index",0).put("sent_callback_id",rows.getJSONObject(0).getJSONObject("payload").getString("callback_id")).put("delivery_callback_id",rows.getJSONObject(1).getJSONObject("payload").getString("callback_id"))))
        val accepted=parseSuccessorArm(a.getString("request_id"),g.getString("device_id"),p,a,lease.grant.expiresAt,Instant.parse(a.getString("armed_at")))!!
        assertEquals(lease.grant.dispatchRoute,accepted.dispatchRoute);assertNotEquals((lease.grant.dispatchRoute as GatewayDispatchRoute.ReceiptSuccessorV1).primaryReceiptId,lease.grant.jobId)
        assertFalse(g.has("receipt_id"));failure { parseSuccessorGrant(g.getString("request_id"),g.getString("device_id"),JSONObject(g.toString()).put("receipt_id",lease.grant.jobId),Instant.parse(g.getString("issued_at"))) }
    }
    @Test fun retainedSqlCallbacksAndJournalAckRemainNonDeliveryEvidence() {
        val g=grant();val rows=callbacks()
        for(i in 0 until rows.length()) { val r=rows.getJSONObject(i);validateSuccessorResult("callback",r.getString("request_id"),g.getString("device_id"),r.getJSONObject("payload"),r.getJSONObject("result"),Instant.parse(g.getString("issued_at"))) }
        val a=ack();validateSuccessorArchiveAck(a,a.getString("request_id"),g.getString("device_id"),payload(a));assertTrue(a.getBoolean("journal_ack"));assertFalse(a.getBoolean("delivery_proven"))
        failure { validateSuccessorArchiveAck(JSONObject(a.toString()).put("receipt_id",g.getJSONObject("route").getString("dispatch_job_id")),a.getString("request_id"),g.getString("device_id"),payload(a)) }
    }
    @Test fun retainedSqlLateRecoveryRejectsNestedExtraAndRouteChangesAtOriginalConsumer() {
        val value=JSONObject(observation("observed-late-original-request-recovery.json"));val g=grant();val p=JSONObject().put("target_request_id",value.getString("target_request_id"))
        validateSuccessorResult("reconcile",id(),g.getString("device_id"),p,value,Instant.parse(g.getString("issued_at")))
        for(field in listOf("send_authority","extra")){val bad=JSONObject(value.toString());bad.getJSONObject("recorded_result").put(field,true);failure {validateSuccessorResult("reconcile",id(),g.getString("device_id"),p,bad,Instant.now())}}
    }
    private class TestContext(private val root:File):Context() { override val noBackupFilesDir get()=root }
    private inner class Fixture {
        val root=Files.createTempDirectory("collect-successor-native-").toFile();val context=TestContext(root)
        val key=KeyPairGenerator.getInstance("EC").apply {initialize(ECGenParameterSpec("secp256r1"))}.generateKeyPair()
        val fingerprint=MessageDigest.getInstance("SHA-256").digest(key.public.encoded).joinToString("") {"%02x".format(it)}
        val device=id();val attempt=id();val route=GatewayDispatchRoute.ReceiptSuccessorV1(id(),id(),id())
        val requests=mutableListOf<JSONObject>();val raw=mutableListOf<ByteArray>();val endpoints=mutableListOf<String>();val results=linkedMapOf<String,JSONObject>()
        var expiry=Instant.now().plusSeconds(25);var loseGrant=false;var loseArm=false;var loseArchive=false;var unknownLookup=false;var swapArm=false;var conflictAtAck=false;var activePrimary=false;var failReservation=false
        val store=GatewayEncryptedStore(context) {name->GatewayCrypto(SecretKeySpec(ByteArray(32){11},"AES"),"CollectGateway/$name/v1")}
        fun crypto(name:String)=GatewayCrypto(SecretKeySpec(ByteArray(32){11},"AES"),"CollectGateway/$name/v1")
        val backend:GatewaySignedBackend
        init {
            store.saveEnrollment(JSONObject().put("contract_version",1).put("device_id",device).put("installation_id",id()).put("key_sha256",fingerprint).put("signing_certificate_sha256","a".repeat(64)))
            val transport=GatewayHttpsTransport({fingerprint},{bytes->Base64.getEncoder().encodeToString(Signature.getInstance("SHA256withECDSA").run {initSign(key.private);update(bytes);sign()})},{url->
                assertEquals(GatewayHttpsTransport.HOST,url.host);endpoints.add(url.path)
                object:HttpsURLConnection(url) {
                    val out=ByteArrayOutputStream();var response:ByteArray?=null
                    override fun connect()=Unit;override fun disconnect()=Unit;override fun usingProxy()=false;override fun getCipherSuite()="synthetic"
                    override fun getLocalCertificates():Array<Certificate>?=null;override fun getServerCertificates():Array<Certificate> = emptyArray()
                    override fun getOutputStream()=out
                    override fun getResponseCode():Int {val bytes=out.toByteArray();assertTrue(Signature.getInstance("SHA256withECDSA").run {initVerify(key.public);update(bytes);verify(Base64.getDecoder().decode(getRequestProperty("X-Collect-Gateway-Signature")))})
                        assertNull(getRequestProperty("Authorization"));raw.add(bytes);val e=JSONObject(String(bytes,Charsets.UTF_8));requests.add(e);val r=respond(e);response=wrapper(e,r).toString().toByteArray();return 200}
                    override fun getInputStream()=ByteArrayInputStream(response!!)
                }
            });backend=GatewaySignedBackend(context,store,GatewayDeviceIdentity(),{fingerprint},transport)
        }
        private fun refuse(e:JSONObject,code:String) = JSONObject().put("ok",false).put("code",code).put("device_id",device).put("request_id",e.getString("request_id")).put("replay",code=="ORIGINAL_REQUEST_RECORDED")
            .also {if(isSuccessorEnvelope(e))it.put("contract_version",1).put("protocol_family",SUCCESSOR_FAMILY).put("send_authority",false).put("carrier_proof",false).put("delivery_proven",false)}
        private fun respond(e:JSONObject):JSONObject {
            val action=e.getString("action");val p=e.getJSONObject("payload")
            if(!isSuccessorEnvelope(e))return when(action) {
                "heartbeat" -> JSONObject().put("observation_id",id()).put("ingested_at",gatewayWireTime(Instant.now())).put("replay",false).put("carrier_proof",false)
                "dispatch_grant" -> refuse(e,if(activePrimary)"OPERATIONS_PAUSED" else "NO_ELIGIBLE_RECEIPT")
                "reconcile" -> {val target=p.getString("target_request_id");val original=requests.first {it.getString("request_id")==target};JSONObject().put("target_request_id",target).put("outcome","recorded").put("recorded_action",original.getString("action")).put("recorded_result",results[target] ?: refuse(original,"ORIGINAL_REQUEST_RECORDED"))}
                else -> error("Unsupported primary synthetic action")
            }
            val result=when(action) {
                "dispatch_grant" -> grant().put("device_id",device).put("request_id",e.getString("request_id")).put("route",successorRouteJson(route)).put("attempt_id",attempt).put("issued_at",gatewayWireTime(Instant.now())).put("expires_at",gatewayWireTime(expiry))
                    .put("sim_revision_sha256",sha256("android-subscription-selection:1"))
                "arm_dispatch" -> arm().put("device_id",device).put("request_id",e.getString("request_id")).put("route",successorRouteJson(if(swapArm)route.copy(approvalId=id())else route)).put("attempt_id",attempt)
                    .put("reservation_sha256",p.getString("reservation_sha256")).put("armed_at",gatewayWireTime(Instant.now())).put("expires_at",gatewayWireTime(expiry))
                "callback" -> callbacks().getJSONObject(if(p.getString("callback_kind")=="sent")0 else 1).getJSONObject("result").put("route",successorRouteJson(route)).put("attempt_id",attempt).put("callback_id",p.getString("callback_id")).put("recorded_at",gatewayWireTime(Instant.now()))
                    .also {if(p.getInt("result_code") != -1)it.put("state","uncertain").put("failed_observations",true).put("conflicting_observations",true)}
                "archive_attempt" -> ack().put("device_id",device).put("request_id",e.getString("request_id")).put("route",successorRouteJson(route)).put("attempt_id",attempt).put("callback_requests",p.getJSONArray("callback_requests")).put("recorded_at",gatewayWireTime(Instant.now()))
                "reconcile" -> {
                    val target=p.getString("target_request_id");val original=requests.first {it.getString("request_id")==target};val found=results[target];val recorded=if(found==null || original.getString("action") in setOf("dispatch_grant","arm_dispatch"))refuse(original,"ORIGINAL_REQUEST_RECORDED")else found
                    JSONObject().put("contract_version",1).put("protocol_family",SUCCESSOR_FAMILY).put("target_request_id",target).put("outcome",if(unknownLookup)"unknown"else"recorded").put("recorded_action",if(unknownLookup)JSONObject.NULL else original.getString("action"))
                        .put("recorded_route",if(unknownLookup)JSONObject.NULL else successorRouteJson(route)).put("recorded_result",if(unknownLookup)JSONObject.NULL else recorded).put("send_authority",false).put("carrier_proof",false).put("delivery_proven",false)
                }
                else -> error("Unsupported successor synthetic action")
            }
            if(action != "reconcile")results[e.getString("request_id")]=JSONObject(result.toString())
            if(action=="dispatch_grant"&&failReservation)AtomicFileFaults.failFileOnce="journal.bin"
            if(action=="archive_attempt" && conflictAtAck) {conflictAtAck=false;val a=store.read().attempts.single();GatewayJournal(store).record(GatewayCallback(a.segments[0].sentCallbackId,a.deviceId,a.attemptId,a.fence,0,a.callbackNonce,CallbackKind.SENT,1,gatewayWireTime(Instant.now())))}
            if((action=="dispatch_grant"&&loseGrant)||(action=="arm_dispatch"&&loseArm)||(action=="archive_attempt"&&loseArchive))throw java.io.IOException("Synthetic reply lost after recording")
            return result
        }
        fun dispatch(counter:()->Unit):GatewayAttempt? {GatewayJournal(store).resume();return GatewayDispatchEngine(GatewayJournal(store),backend,object:GatewaySmsInvoker {
            override fun divide(body:String,subscriptionId:Int)=listOf(body)
            override fun invoke(grant:GatewayDispatchGrant,record:GatewayAttempt,parts:List<String>,subscriptionId:Int) {assertEquals(route,record.dispatchRoute);assertEquals(record,store.read().attempts.single());counter()}
        },::observations).dispatchOne()}
        fun observe(a:GatewayAttempt) {for(kind in CallbackKind.entries){val s=a.segments[0];assertTrue(GatewayJournal(store).record(GatewayCallback(if(kind==CallbackKind.SENT)s.sentCallbackId else s.deliveryCallbackId,a.deviceId,a.attemptId,a.fence,0,a.callbackNonce,kind,-1,gatewayWireTime(Instant.now()))))}}
        fun archive(counter:()->Unit):GatewayAttempt {val a=dispatch(counter)!!;observe(a);val observed=store.read().attempts.single();assertEquals(a,observed.copy(segments=a.segments));backend.reconcile(store.read());return observed}
        fun dispose() {AtomicFileFaults.failFinishOnce=false;AtomicFileFaults.failFileOnce=null;root.deleteRecursively()}
    }
    private fun test(block:(Fixture)->Unit) {val f=Fixture();try {block(f)}finally {f.dispose()}}
    @Test fun oneSenderDurablyBindsRouteAndNeverAliasesPrimaryReceipt() = test {f->var n=0;val a=f.dispatch {n++}!!;assertEquals(1,n);assertEquals(f.route,a.dispatchRoute);assertEquals(1,f.requests.count {it.getString("action")=="arm_dispatch"});assertEquals(f.route,f.store.retainedSuccessorRoute(a.attemptId));assertFalse(f.store.retainedAttemptUsesV2(a.attemptId));assertEquals(listOf("/functions/v1/collect-android-gateway","/functions/v1/collect-android-gateway","/functions/v1/collect-receipt-successor-gateway","/functions/v1/collect-receipt-successor-gateway"),f.endpoints)}
    @Test fun definitePrimaryRefusalOtherThanEmptyDoesNotPollSuccessor() = test {f->f.activePrimary=true;assertNull(f.dispatch {});assertEquals(2,f.requests.size);assertFalse(f.requests.any {isSuccessorEnvelope(it)})}
    @Test fun routeFieldsEnterReservationDigestWhilePrimaryKeepsItsOwnDomain() = test {f->val a=f.dispatch {}!!;val d=gatewayReservationDigest(a);assertNotEquals(d,gatewayReservationDigest(a.copy(dispatchRoute=GatewayDispatchRoute.PrimaryV2)));for(r in listOf(f.route.copy(primaryReceiptId=id()),f.route.copy(approvalId=id()))){assertNotEquals(d,gatewayReservationDigest(a.copy(dispatchRoute=r)))};failure {gatewayReservationDigest(a.copy(dispatchRoute=f.route.copy(dispatchJobId=id())))}}
    @Test fun mixedJournalRecordsRoundtripAndVersionTwoIsSticky() = test {f->val a=f.dispatch {}!!;val primary=a.copy(jobId=id(),attemptId=id(),dispatchRoute=GatewayDispatchRoute.PrimaryV2) // bind explicitly below
        val p=primary.copy(dispatchRoute=GatewayDispatchRoute.PrimaryV2,segments=primary.segments.map {it.copy(sentCallbackId=id(),deliveryCallbackId=id())});f.store.commit(GatewayJournalState(false,listOf(a,p)));assertEquals(listOf(a,p),f.store.read().attempts);f.store.commit(GatewayJournalState(true,listOf(p)));assertEquals(listOf(p),f.store.read().attempts);assertEquals(11,archiveAttemptJson(p).length());assertEquals(13,archiveAttemptJson(a).length());assertEquals(a,archiveAttemptFromJson(archiveAttemptJson(a)))}
    @Test fun unknownGrantFencesFreshPollingUntilOriginalUuidRead() = test {f->f.loseGrant=true;failure {f.dispatch {fail("No invocation")}};val original=f.requests.last().getString("request_id");val count=f.requests.count {it.getString("action") in setOf("dispatch_grant","arm_dispatch")};failure {f.dispatch {fail("No invocation")}};assertEquals(count,f.requests.count {it.getString("action") in setOf("dispatch_grant","arm_dispatch")});f.unknownLookup=true;f.backend.reconcile(f.store.read());assertEquals(1,f.requests.count {isSuccessorEnvelope(it)&&it.getString("action")=="dispatch_grant"});assertTrue(f.requests.any {it.getString("action")=="reconcile"&&it.getJSONObject("payload").getString("target_request_id")==original});failure {f.dispatch {fail("No invocation")}}}
    @Test fun lostArmAndChangedRouteNeverInvokeOrReplay() = test {f->f.loseArm=true;failure {f.dispatch {fail("No invocation")}};val original=f.requests.last().getString("request_id");failure {f.dispatch {fail("No invocation")}};repeat(2){f.backend.reconcile(f.store.read())};assertEquals(1,f.requests.count {it.getString("action")=="arm_dispatch"});assertTrue(f.requests.any {it.getString("action")=="reconcile"&&it.getJSONObject("payload").getString("target_request_id")==original});assertEquals(1,f.store.read().attempts.size)}
    @Test fun finalArmSwappedApprovalCannotReachInvoker() = test {f->f.swapArm=true;failure {f.dispatch {fail("No invocation")}};assertEquals(1,f.store.read().attempts.size);assertEquals(1,f.requests.count {it.getString("action")=="arm_dispatch"})}
    @Test fun fsyncFailurePreventsFinalArmAndInvocation() = test {f->f.failReservation=true;failure {f.dispatch {fail("No invocation")}};assertEquals(0,f.requests.count {it.getString("action")=="arm_dispatch"});assertEquals(1,f.requests.count {isSuccessorEnvelope(it)&&it.getString("action")=="dispatch_grant"})}
    @Test fun completeCallbacksArchiveNewRouteAndExactOriginalRequests() = test {f->var n=0;val a=f.archive {n++};assertEquals(1,n);assertTrue(f.store.read().attempts.isEmpty());val cold=f.store.readColdAttempt(a.attemptId)!!;assertEquals(5,cold.getInt("contract_version"));assertEquals(a,archiveAttemptFromJson(cold.getJSONObject("attempt")));assertFalse(cold.getJSONObject("acknowledgement").has("receipt_id"));validateColdAttempt(cold);assertEquals(2,cold.getJSONArray("callback_requests").length());for(i in 0..1){val r=GatewayStoredRequest.parse(cold.getJSONArray("callback_requests").getJSONObject(i));assertTrue(requestMatchesRoute(r,f.route));requireSameRequest(r,f.store.readRetainedRequest(r.requestId)!!)}}
    @Test fun lostArchiveUsesSameUuidLookupAndDoesNotRepeatMutation() = test {f->var n=0;val a=f.dispatch {n++}!!;f.observe(a);f.loseArchive=true;failure {f.backend.reconcile(f.store.read())};val original=f.requests.single {it.getString("action")=="archive_attempt"}.getString("request_id");f.backend.reconcile(f.store.read());assertEquals(1,n);assertEquals(1,f.requests.count {it.getString("action")=="archive_attempt"});assertEquals(2,f.requests.count {it.getString("action")=="callback"});assertNotNull(f.store.readColdAttempt(a.attemptId));assertTrue(f.requests.any {it.getString("action")=="reconcile"&&it.getJSONObject("payload").getString("target_request_id")==original})}
    @Test fun contradictionWhileAckInFlightRetainsBothTruthsAndStops() = test {f->val a=f.dispatch {}!!;f.observe(a);f.conflictAtAck=true;f.backend.reconcile(f.store.read());assertNull(f.store.readColdAttempt(a.attemptId));assertNotNull(f.store.readUncompactableAck(a.attemptId));assertTrue(f.store.coldStop());assertEquals(AttemptOutcome.OUTCOME_UNKNOWN,f.store.read().attempts.single().outcome())}
    @Test fun lateContradictionUsesRouteAndNeverRewritesImmutableAck() = test {f->val a=f.archive {};val old=f.store.readColdAttempt(a.attemptId)!!.toString();val cb=GatewayCallback(a.segments[0].sentCallbackId,a.deviceId,a.attemptId,a.fence,0,a.callbackNonce,CallbackKind.SENT,1,gatewayWireTime(Instant.now()));assertTrue(GatewayJournal(f.store).record(cb));f.backend.reconcile(f.store.read());assertTrue(f.store.coldStop());assertEquals(old,f.store.readColdAttempt(a.attemptId)!!.toString());assertEquals(3,f.requests.count {it.getString("action")=="callback"});assertTrue(f.requests.filter {it.getString("action")=="callback"}.all {isSuccessorEnvelope(it)&&successorRouteFromJson(it.getJSONObject("payload").getJSONObject("route"))==f.route})}
    @Test fun archiveAndLateReceiptRestoreWithExactCiphertextsAndInactiveAuthority() = test {f->val a=f.archive {};val cb=GatewayCallback(a.segments[0].sentCallbackId,a.deviceId,a.attemptId,a.fence,0,a.callbackNonce,CallbackKind.SENT,1,gatewayWireTime(Instant.now()));GatewayJournal(f.store).record(cb);f.backend.reconcile(f.store.read());val export=f.store.exportRecovery(File(f.root,"export"));val restored=f.store.restoreRecovery(export.directory,export.manifestSha256,File(f.root,"restored"));assertTrue(File(restored.directory,"view").renameTo(File(restored.directory,"collect_gateway_v1")));val s=GatewayEncryptedStore(TestContext(restored.directory)){name->f.crypto(name)};assertEquals(f.route,s.retainedSuccessorRoute(a.attemptId));assertEquals(a,archiveAttemptFromJson(s.readColdAttempt(a.attemptId)!!.getJSONObject("attempt")));assertTrue(s.coldStop());assertTrue(GatewayJournal(s).read().emergencyPaused);failure {s.requireActiveInstallation()};assertEquals(cb,s.coldCallbackPage(null,8).entries.single().callback)}
    @Test fun globalRequestUuidCannotBeReclaimedUnderAnotherFamily() = test {f->f.dispatch {};val rows=f.store.readRequests().getJSONArray("requests");val old=GatewayStoredRequest.parse(rows.getJSONObject(0));val e=JSONObject().put("contract_version",1).put("protocol_family",SUCCESSOR_FAMILY).put("audience",SUCCESSOR_AUDIENCE).put("action","dispatch_grant").put("device_id",f.device).put("request_id",old.requestId).put("issued_at",gatewayWireTime(Instant.now())).put("payload",JSONObject());val text=e.toString();val row=JSONObject(old.row.toString()).put("request_sha256",sha256(text)).put("request_bytes_base64",Base64.getEncoder().encodeToString(text.toByteArray()));failure {f.store.saveRequests(JSONObject().put("contract_version",1).put("requests",JSONArray().put(row)))};requireSameRequest(old,f.store.readRetainedRequest(old.requestId)!!)}
    @Test fun successorRequestDuplicateKeysAndFamilyAliasesCannotEnterRetention() = test {f->f.dispatch {};val rows=f.store.readRequests().getJSONArray("requests");val r=GatewayStoredRequest.parse(rows.getJSONObject(1));val text=r.envelope.toString().replace("\"contract_version\":1","\"contract_version\":1,\"contract_version\":1");val bad=JSONObject(r.row.toString()).put("request_sha256",sha256(text)).put("request_bytes_base64",Base64.getEncoder().encodeToString(text.toByteArray()));failure {GatewayStoredRequest.parse(bad)};val alias=JSONObject(r.envelope.toString()).put("protocol_family","primary_v2").toString();failure {GatewayStoredRequest.parse(JSONObject(r.row.toString()).put("request_sha256",sha256(alias)).put("request_bytes_base64",Base64.getEncoder().encodeToString(alias.toByteArray())))} }
    @Test fun primaryCopyDerivesIdentityOnlyFromExistingJobWithoutDuplicatedRoute() = test {f->
        val a=f.dispatch {}!!.copy(dispatchRoute=GatewayDispatchRoute.PrimaryV2)
        val changed=a.copy(jobId=id(),attemptId=id())
        validateAttempt(changed)
        val bytes=archiveAttemptJson(changed)
        assertEquals(11,bytes.length());assertEquals(changed.jobId,bytes.getString("job_id"));assertEquals(changed,archiveAttemptFromJson(bytes))
        assertNotEquals(gatewayReservationDigest(a),gatewayReservationDigest(changed))
    }
    @Test fun primaryMarkerPreservesStrictPersistedIdentityAndClosedRows() = test {f->
        val a=f.dispatch {}!!.copy(dispatchRoute=GatewayDispatchRoute.PrimaryV2)
        failure {archiveAttemptFromJson(archiveAttemptJson(a).put("job_id","invalid"))}
        failure {archiveAttemptFromJson(archiveAttemptJson(a).put("route",successorRouteJson(f.route)))}
        failure {archiveAttemptFromJson(archiveAttemptJson(a).put("record_kind","receipt_successor_v1"))}
    }
    @Test fun successorCopyCannotDropOrRebindTheImmutableJobTuple() = test {f->
        val a=f.dispatch {}!!
        failure {validateAttempt(a.copy(jobId=id()))}
        failure {gatewayReservationDigest(a.copy(jobId=id()))}
        failure {archiveAttemptFromJson(archiveAttemptJson(a).put("job_id",id()))}
        assertEquals(a.dispatchRoute,archiveAttemptFromJson(archiveAttemptJson(a)).dispatchRoute)
    }

}
