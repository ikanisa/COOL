package app.cool.mobile.gateway

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File

/** Synthetic archived replies are historical fixture setup. Restore invokes
 * the actual encrypted readers/repair services, never transport or delivery. */
class GatewayRecoveryHistoryTest {
    private class LocalContext(private val root:File):Context() { override val noBackupFilesDir get()=root }
    private fun test(action:(GatewayLateFixture)->Unit) { val f=GatewayLateFixture();try { action(f) } finally { f.dispose() } }
    private fun restore(f:GatewayLateFixture):Pair<GatewayRecoveryResult,GatewayEncryptedStore> {
        val archive=f.store().exportRecovery(File(f.root,"archive-${f.id()}"))
        val result=f.store().restoreRecovery(archive.directory,archive.manifestSha256,File(f.root,"restored-${f.id()}"))
        assertTrue(File(result.directory,"view").renameTo(File(result.directory,"collect_gateway_v1")))
        return result to GatewayEncryptedStore(LocalContext(result.directory)) { name -> f.crypto(name) }
    }
    private fun ack(f:GatewayLateFixture,row:JSONObject,result:JSONObject) {
        val original=GatewayStoredRequest.parse(row)
        val reply=JSONObject().put("contract_version",original.envelope.getInt("contract_version")).put("action",original.action).put("device_id",original.deviceId).put("request_id",original.requestId).put("result",result)
        GatewayJournalArchive(f.storage).acknowledge(GatewayArchiveAcknowledgement.direct(original,reply))
    }
    @Test fun v1ObservationalReceiptsRetainHotAttemptAndExactCallbackOriginalsWithoutTerminalAuthority() = test { f ->
        val a=GatewayAttempt(f.device,f.id(),f.id(),1,"a".repeat(64),"b".repeat(64),"2026-10-01T13:01:00Z",f.at,"c".repeat(64),
            listOf(SegmentEvidence(f.id(),f.id(),SegmentOutcome.FRAMEWORK_SENT,SegmentOutcome.DELIVERY_CALLBACK_OBSERVED,-1,-1,f.at,f.at)))
        f.storage.commit(GatewayJournalState(false,listOf(a)))
        val rows=CallbackKind.entries.map { kind ->
            val payload=JSONObject().put("callback_id",if(kind==CallbackKind.SENT)a.segments[0].sentCallbackId else a.segments[0].deliveryCallbackId).put("attempt_id",a.attemptId).put("fence_version",a.fence)
                .put("segment_index",0).put("segment_count",1).put("body_sha256",a.bodySha256).put("destination_sha256",a.destinationSha256).put("callback_kind",if(kind==CallbackKind.SENT)"sent" else "delivery").put("result_code",-1).put("occurred_at",f.at)
            f.request("callback",payload,1)
        }
        f.storage.saveRequests(JSONObject().put("contract_version",1).put("requests",JSONArray(rows)))
        for(row in rows) ack(f,row,JSONObject().put("callback_id",row.getString("callback_id")).put("recorded_at",f.at).put("replay",false).put("carrier_proof",false))
        val receipts=JSONArray(rows.map { f.store().readRequestReceipt(it.getString("request_id"))!! })
        f.store().commitObservedAttempt(JSONObject().put("contract_version",4).put("attempt",archiveAttemptJson(a)).put("callback_receipts",receipts).put("archived_at",f.at))
        val hot=File(f.directory,"journal.bin").readBytes();val requests=File(f.directory,"requests.bin").readBytes()
        val (result,recovered)=restore(f)
        assertArrayEquals(hot,File(result.directory,"original/journal.bin").readBytes());assertArrayEquals(requests,File(result.directory,"original/requests.bin").readBytes())
        assertEquals(listOf(a),recovered.read().attempts);assertNotNull(recovered.readObservedAttempt(a.attemptId));assertNull(recovered.readColdAttempt(a.attemptId))
        assertEquals(2,recovered.readRequests().getJSONArray("requests").length())
        for(row in rows) { val original=GatewayStoredRequest.parse(row);assertFalse(recovered.requestAcknowledged(original));requireSameRequest(original,recovered.readRetainedRequest(original.requestId)!!);assertNotNull(recovered.readRequestReceipt(original.requestId)) }
        assertTrue(recovered.coldStop());assertTrue(GatewayJournal(recovered).read().emergencyPaused)
    }
    @Test fun v2LateReceiptClosureRestoresOnlyExactTransportMarkerAndKeepsRawObservation() = test { f ->
        val a=f.seed();val callback=f.callback(a);f.append(a,callback)
        val row=f.request("callback",gatewayLatePayload(a,callback),2)
        f.storage.saveRequests(JSONObject().put("contract_version",1).put("requests",JSONArray().put(row)))
        ack(f,row,JSONObject().put("callback_id",callback.callbackId).put("recorded_at",f.at).put("replay",false).put("carrier_proof",false).put("state","uncertain").put("sent_observations",1).put("delivery_observations",1).put("conflicting_observations",true))
        val receipt=f.store().readRequestReceipt(row.getString("request_id"))!!.toString()
        val (_,recovered)=restore(f);val original=GatewayStoredRequest.parse(row)
        requireSameRequest(original,recovered.readRetainedRequest(original.requestId)!!);assertEquals(receipt,recovered.readRequestReceipt(original.requestId)!!.toString());assertTrue(recovered.requestAcknowledged(original))
        assertEquals(callback,recovered.coldCallbackPage(null,8).entries.single().callback);assertTrue(recovered.coldStop());assertEquals(a,archiveAttemptFromJson(recovered.readColdAttempt(a.attemptId)!!.getJSONObject("attempt")))
    }
    @Test fun unindexedFutureLateWorkOrTerminalDtoCannotHideBehindUnrelatedAuthenticatedReceipt() {
        for(fault in listOf("future-work","terminal")) test { f ->
            val a=f.seed();f.append(a);val entry=f.pages().single()
            when(fault) {
                "future-work" -> {
                    val work=f.read("retention-late-work-${entry.cursorKey}").put("sequence","0".repeat(31)+"9")
                    f.write("retention-late-work-${"0".repeat(31)+"9"}",work)
                }
                else -> {
                    val row=f.request("heartbeat",JSONObject(),1);f.storage.saveRequests(JSONObject().put("contract_version",1).put("requests",JSONArray().put(row)))
                    ack(f,row,JSONObject().put("observation_id",f.id()).put("ingested_at",f.at).put("replay",false).put("carrier_proof",false))
                    f.write("retention-terminal-${retentionUuidKey(row.getString("request_id"))}",JSONObject().put("malformed","must not bypass"))
                }
            }
            val archive=f.store().exportRecovery(File(f.root,"archive-${f.id()}"));val target=File(f.root,"denied-${f.id()}")
            try { f.store().restoreRecovery(archive.directory,archive.manifestSha256,target);fail("Expected integrity refusal") }
            catch(_:GatewayStateException) { }
            assertTrue(File(target,GatewayRecovery.INACTIVE).isFile);assertFalse(File(target,"RESULT.json").exists())
        }
    }
    @Test fun cancelledPartialRestoreRetainsArchiveAndPublishesOnlyInactiveIncompleteTarget() = test { f ->
        f.storage.commit(GatewayJournalState(false));val archive=f.store().exportRecovery(File(f.root,"archive-${f.id()}"));val target=File(f.root,"cancelled-${f.id()}")
        val originals=File(archive.directory,"objects").listFiles()!!.associate { it.name to it.readBytes() };var steps=0
        try { f.store().restoreRecovery(archive.directory,archive.manifestSha256,target) { ++steps==2 };fail("Expected cancellation") }
        catch(e:GatewayStateException) { assertEquals("gateway_recovery_cancelled",e.reasonCode) }
        assertTrue(File(target,GatewayRecovery.INACTIVE).isFile);assertTrue(File(target,"view/${GatewayRecovery.INACTIVE}").isFile);assertFalse(File(target,"RESULT.json").exists())
        for((name,bytes) in originals) assertArrayEquals(bytes,File(archive.directory,"objects/$name").readBytes())
        // Recovery retries only into a fresh target; it never merges partial files.
        val result=f.store().restoreRecovery(archive.directory,archive.manifestSha256,File(f.root,"fresh-${f.id()}"));assertTrue(result.keyValidated)
    }
}
