package app.cool.mobile.gateway

import android.content.Context
import android.util.AtomicFileFaults
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.time.Instant
import java.util.Base64
import java.util.UUID
import javax.crypto.spec.SecretKeySpec

class GatewayInvocationCustodyTest {
    private val at = Instant.parse("2026-10-03T12:00:00Z")
    private val device = "ad760000-0000-4000-8000-000000000001"
    private val receipt = "ad760000-0000-4000-8000-000000000002"
    private val attempt = "ad760000-0000-4000-8000-000000000003"
    private val installation = "ad760000-0000-4000-8000-000000000004"
    private val body = "Synthetic application invocation custody receipt."
    private val destination = "+250788000101"
    private class TestContext(private val root: File) : Context() { override val noBackupFilesDir get() = root }

    private inner class Fixture : AutoCloseable {
        val root = Files.createTempDirectory("collect-invocation-custody-").toFile()
        val context = TestContext(root)
        val factory: (String) -> GatewayCrypto = { name -> GatewayCrypto(SecretKeySpec(ByteArray(32) { 31 }, "AES"), "CollectGateway/$name/v1") }
        val store = GatewayEncryptedStore(context, factory)
        val journal = GatewayJournal(store)
        var arms = 0
        var sends = 0
        var onArm: (GatewayAttempt) -> Unit = {}
        var onInvoke: (GatewayAttempt) -> Unit = {}
        var route: GatewayDispatchRoute = GatewayDispatchRoute.PrimaryV2
        init { enroll(); journal.resume() }
        fun enroll(key: String = "a".repeat(64)) = store.saveEnrollment(JSONObject().put("contract_version", 1)
            .put("device_id", device).put("installation_id", installation).put("key_sha256", key).put("signing_certificate_sha256", "b".repeat(64)))
        fun record(): GatewayAttempt = GatewayAttempt(device, receipt, attempt, 1, sha256(body), sha256(destination),
            at.plusSeconds(30).toString(), at.toString(), "a".repeat(64), listOf(SegmentEvidence()), dispatchRoute = route)
        fun prepare(): GatewayAttempt = record().also { journal.reserveInvocation(it); journal.prepareInvocation(it) }
        fun file(kind: String) = File(root, "collect_gateway_v1/retention-$kind-${retentionUuidKey(attempt)}.bin")
        fun indexedFile(kind: String) = "retention-index-$kind-${retentionUuidKey(attempt)}.bin"
        val backend = object : GatewayBackend {
            override fun heartbeat(observations: GatewayObservations) = GatewayAuthority(device, GatewayEnrollmentState.ACTIVE, true, at)
            override fun dispatchGrant(observations: GatewayObservations): GatewayDispatchGrant {
                val job = (route as? GatewayDispatchRoute.ReceiptSuccessorV1)?.dispatchJobId ?: receipt
                return GatewayDispatchGrant(device, job, attempt, 1, destination, sha256(destination), body, sha256(body), at.plusSeconds(30), 1, route)
            }
            override fun armDispatch(grant: GatewayDispatchGrant, reservation: GatewayAttempt): GatewayDispatchArmAck {
                arms++; onArm(reservation)
                return GatewayDispatchArmAck(attempt, 1, gatewayReservationDigest(reservation), at, at.plusSeconds(30), route)
            }
            override fun reconcile(journal: GatewayJournalState) = Unit
        }
        fun engine(journal: GatewayJournal = this.journal) = GatewayDispatchEngine(journal, backend, object : GatewaySmsInvoker {
            override fun divide(body: String, subscriptionId: Int) = listOf(body)
            override fun invoke(grant: GatewayDispatchGrant, record: GatewayAttempt, parts: List<String>, subscriptionId: Int) {
                GatewayInvocationCustody(store).requireEntered(record)
                sends++; onInvoke(record)
            }
        }, { GatewayObservations(true, true, true, true, true, true, true, 1, true) }, { at })
        override fun close() { AtomicFileFaults.failFileOnce = null; AtomicFileFaults.failFinishOnce = false; AtomicFileFaults.failWriteNumberOnce = null; root.deleteRecursively() }
    }

    private fun refused(block: () -> Unit): Exception {
        try { block(); fail("Expected a closed custody gate") } catch (e: Exception) { return e }
        throw AssertionError()
    }

    @Test fun currentEngineReadsBackEnteredBeforeSenderAndBindsExactRealmAndRoot(): Unit = Fixture().use { f ->
        f.onInvoke = { record ->
            val proof = f.journal.invocationEvidence(record.attemptId)
            assertTrue(proof.getBoolean("prepare_indexed")); assertTrue(proof.getBoolean("terminal_indexed"))
            assertEquals("invoke_entered", proof.getJSONObject("terminal").getString("phase"))
            val bound = proof.getJSONObject("prepare").getJSONObject("binding")
            assertEquals("primary_android_v2", bound.getString("source_family")); assertEquals(receipt, bound.getString("root_receipt_id"))
            assertEquals(gatewayReservationDigest(record), bound.getString("reservation_sha256"))
            assertEquals(installation, bound.getJSONObject("realm").getString("installation_id"))
            assertEquals("a".repeat(64), bound.getJSONObject("realm").getString("key_sha256"))
            assertFalse(proof.getBoolean("backend_authority_cancelled")); assertFalse(proof.getBoolean("send_authority"))
        }
        f.engine().dispatchOne(); assertEquals(1, f.arms); assertEquals(1, f.sends)
    }

    @Test fun delayedArmAckCannotCrossIrrevocableLocalAbortOrRestart(): Unit = Fixture().use { f ->
        f.onArm = { f.journal.abortUninvoked(attempt, "operator_stop", at) }
        refused { f.engine().dispatchOne() }; assertEquals(0, f.sends)
        val terminal = f.journal.invocationEvidence(attempt).getJSONObject("terminal").toString()
        assertEquals("aborted_uninvoked", JSONObject(terminal).getString("phase"))
        refused { f.journal.resume() }; refused { f.engine(GatewayJournal(f.store)).dispatchOne() }
        refused { GatewayInvocationCustody(f.store).enter(f.journal.read().attempts.single(), at) }
        assertEquals(terminal, f.journal.invocationEvidence(attempt).getJSONObject("terminal").toString()); assertEquals(0, f.sends)
    }

    @Test fun senderExceptionAfterEnteredNeverBecomesUninvoked(): Unit = Fixture().use { f ->
        f.onInvoke = { throw IOException("Synthetic exception after sender entry") }
        refused { f.engine().dispatchOne() }; assertEquals(1, f.sends)
        assertTrue(f.journal.read().attempts.single().invocationException)
        refused { f.journal.abortUninvoked(attempt, "operator_stop", at) }
        assertEquals("invoke_entered", f.journal.invocationEvidence(attempt).getJSONObject("terminal").getString("phase"))
    }

    @Test fun historicalReservationAndOldTimestampCannotAcquirePreparationAfterRestart(): Unit = Fixture().use { f ->
        val record = f.record(); f.journal.reserveInvocation(record)
        val restarted = GatewayJournal(f.store)
        refused { restarted.prepareInvocation(record) }; refused { restarted.abortUninvoked(attempt, "operator_stop", at) }
        refused { GatewayInvocationCustody(f.store).requireEntered(record) }
        assertFalse(f.file(GatewayInvocationCustody.PREPARE).exists()); assertFalse(f.file(GatewayInvocationCustody.TERMINAL).exists())
    }

    @Test fun preparationEligibilityIsConsumedAndCannotBeReissued(): Unit = Fixture().use { f ->
        val record = f.prepare(); refused { f.journal.prepareInvocation(record) }
        refused { GatewayJournal(f.store).prepareInvocation(record) }; refused { f.journal.reserveInvocation(record) }
    }

    @Test fun absentEnrollmentRefusesBeforeArmOrSender(): Unit = Fixture().use { f ->
        File(f.root, "collect_gateway_v1/enrollment.bin").delete()
        refused { f.engine().dispatchOne() }; assertEquals(0, f.arms); assertEquals(0, f.sends)
        assertEquals(1, f.journal.read().attempts.size)
    }

    @Test fun changedKeyRealmCannotRebindOldPreparedSource(): Unit = Fixture().use { f ->
        val record = f.prepare(); val original = f.file(GatewayInvocationCustody.PREPARE).readBytes()
        f.enroll("c".repeat(64)); refused { GatewayInvocationCustody(f.store).enter(record, at) }
        refused { f.journal.abortUninvoked(attempt, "operator_stop", at) }
        assertArrayEquals(original, f.file(GatewayInvocationCustody.PREPARE).readBytes())
    }

    @Test fun damagedCipherCannotBecomeAnEmptySuccessfulCustodyView(): Unit = Fixture().use { f ->
        val record = f.prepare(); val damaged = f.file(GatewayInvocationCustody.PREPARE).readBytes().also { it[it.lastIndex] = (it.last().toInt() xor 1).toByte() }
        f.file(GatewayInvocationCustody.PREPARE).writeBytes(damaged)
        refused { GatewayInvocationCustody(f.store).enter(record, at) }; refused { f.journal.abortUninvoked(attempt, "operator_stop", at) }
        assertArrayEquals(damaged, f.file(GatewayInvocationCustody.PREPARE).readBytes()); assertEquals(0, f.sends)
    }

    @Test fun failedEnteredObjectPublicationDoesNotCallSender(): Unit = Fixture().use { f ->
        f.onArm = { AtomicFileFaults.failFileOnce = f.file(GatewayInvocationCustody.TERMINAL).name }
        refused { f.engine().dispatchOne() }; assertEquals(0, f.sends)
        assertFalse(f.file(GatewayInvocationCustody.TERMINAL).exists())
        f.journal.abortUninvoked(attempt, "operator_stop", at)
        assertEquals("aborted_uninvoked", f.journal.invocationEvidence(attempt).getJSONObject("terminal").getString("phase"))
    }

    @Test fun rawEnteredBeforeIndexPublicationRemainsUncertainAndCannotAbort(): Unit = Fixture().use { f ->
        f.onArm = { AtomicFileFaults.failFileOnce = f.indexedFile(GatewayInvocationCustody.TERMINAL) }
        refused { f.engine().dispatchOne() }; assertEquals(0, f.sends)
        val proof = f.journal.invocationEvidence(attempt)
        assertEquals("invoke_entered", proof.getJSONObject("terminal").getString("phase")); assertFalse(proof.getBoolean("terminal_indexed"))
        val original = f.file(GatewayInvocationCustody.TERMINAL).readBytes()
        refused { GatewayJournal(f.store).abortUninvoked(attempt, "operator_stop", at) }
        refused { GatewayInvocationCustody(f.store).requireEntered(f.journal.read().attempts.single()) }
        assertArrayEquals(original, f.file(GatewayInvocationCustody.TERMINAL).readBytes())
    }

    @Test fun rawAbortRepairsOnlyOriginalTerminalAfterRestart(): Unit = Fixture().use { f ->
        val record = f.prepare(); AtomicFileFaults.failFileOnce = f.indexedFile(GatewayInvocationCustody.TERMINAL)
        refused { f.journal.abortUninvoked(attempt, "operator_stop", at) }
        val original = f.file(GatewayInvocationCustody.TERMINAL).readBytes()
        refused { GatewayInvocationCustody(f.store).enter(record, at) }
        GatewayJournal(f.store).abortUninvoked(attempt, "operator_stop", at.plusSeconds(2))
        assertArrayEquals(original, f.file(GatewayInvocationCustody.TERMINAL).readBytes())
        assertTrue(f.journal.invocationEvidence(attempt).getBoolean("terminal_indexed")); refused { f.journal.resume() }
    }

    @Test fun rawPrepareCanRepairOnlyForSafeAbortWithoutInventingNewSource(): Unit = Fixture().use { f ->
        val record = f.record(); f.journal.reserveInvocation(record)
        AtomicFileFaults.failFileOnce = f.indexedFile(GatewayInvocationCustody.PREPARE)
        refused { f.journal.prepareInvocation(record) }
        val original = f.file(GatewayInvocationCustody.PREPARE).readBytes()
        refused { GatewayInvocationCustody(f.store).enter(record, at) }
        GatewayJournal(f.store).abortUninvoked(attempt, "operator_stop", at)
        assertArrayEquals(original, f.file(GatewayInvocationCustody.PREPARE).readBytes())
        assertTrue(f.journal.invocationEvidence(attempt).getBoolean("prepare_indexed")); assertEquals(0, f.sends)
    }

    @Test fun unindexedInvocationObjectWithMissingControlCannotBecomeANewNamespace(): Unit = Fixture().use { f ->
        val record = f.record(); f.journal.reserveInvocation(record)
        AtomicFileFaults.failFileOnce = f.indexedFile(GatewayInvocationCustody.PREPARE)
        refused { f.journal.prepareInvocation(record) }
        val original = f.file(GatewayInvocationCustody.PREPARE).readBytes()
        assertFalse(File(f.root, "collect_gateway_v1/${f.indexedFile(GatewayInvocationCustody.PREPARE)}").exists())
        val control = File(f.root, "collect_gateway_v1/retention-control.bin"); assertTrue(control.delete())
        assertEquals("gateway_retention_missing", (refused { GatewayInvocationCustody(f.store).evidence(record) } as GatewayStateException).reasonCode)
        refused { GatewayJournal(f.store).abortUninvoked(attempt, "operator_stop", at) }
        assertFalse(control.exists()); assertFalse(f.file(GatewayInvocationCustody.TERMINAL).exists())
        assertArrayEquals(original, f.file(GatewayInvocationCustody.PREPARE).readBytes()); assertEquals(0, f.sends)
    }

    @Test fun callbacksAfterAbortStayContradictoryAndCannotEraseTerminal(): Unit = Fixture().use { f ->
        val record = f.prepare(); f.journal.abortUninvoked(attempt, "operator_stop", at)
        val original = f.file(GatewayInvocationCustody.TERMINAL).readBytes(); val segment = record.segments.single()
        assertTrue(f.journal.record(GatewayCallback(segment.sentCallbackId, device, attempt, 1, 0, record.callbackNonce, CallbackKind.SENT, -1, at.toString())))
        val proof = f.journal.invocationEvidence(attempt); assertTrue(proof.getBoolean("contradictory_callback"))
        assertTrue(f.journal.read().emergencyPaused); assertArrayEquals(original, f.file(GatewayInvocationCustody.TERMINAL).readBytes())
        refused { GatewayInvocationCustody(f.store).validateCompaction(f.journal.read().attempts.single()) }
    }

    @Test fun enteredEvidenceRestoresOnlyInactive(): Unit = Fixture().use { f ->
        val record = f.prepare(); GatewayInvocationCustody(f.store).enter(record, at)
        val snapshot = f.store.exportRecovery(File(f.root, "snapshot"))
        val restored = f.store.restoreRecovery(snapshot.directory, snapshot.manifestSha256, File(f.root, "inactive"))
        assertTrue(restored.keyValidated); assertTrue(restored.requiresReEnrollment)
        val original = f.file(GatewayInvocationCustody.TERMINAL).readBytes()
        assertArrayEquals(original, File(restored.directory, "original/${f.file(GatewayInvocationCustody.TERMINAL).name}").readBytes())
        assertTrue(File(restored.directory, GatewayRecovery.INACTIVE).isFile)
    }

    @Test fun abortedEvidenceRestoresOnlyInactiveWithoutClearingPause(): Unit = Fixture().use { f ->
        f.prepare(); f.journal.abortUninvoked(attempt, "operator_stop", at)
        val snapshot = f.store.exportRecovery(File(f.root, "snapshot-aborted"))
        val restored = f.store.restoreRecovery(snapshot.directory, snapshot.manifestSha256, File(f.root, "inactive-aborted"))
        assertTrue(restored.keyValidated); assertTrue(restored.requiresReEnrollment)
        for (kind in listOf(GatewayInvocationCustody.PREPARE, GatewayInvocationCustody.TERMINAL))
            assertArrayEquals(f.file(kind).readBytes(), File(restored.directory, "original/${f.file(kind).name}").readBytes())
        assertTrue(f.journal.read().emergencyPaused); refused { f.journal.resume() }
    }

    @Test fun strictTerminalAndSourceBindingAreCheckedAtInactiveRestore(): Unit = Fixture().use { f ->
        f.prepare(); f.journal.abortUninvoked(attempt, "operator_stop", at)
        val name = f.file(GatewayInvocationCustody.TERMINAL).name.removeSuffix(".bin")
        val value = JSONObject(String(f.factory(name).decrypt(f.file(GatewayInvocationCustody.TERMINAL).readBytes()), Charsets.UTF_8)).put("unexpected", true)
        f.file(GatewayInvocationCustody.TERMINAL).writeBytes(f.factory(name).encrypt(value.toString().toByteArray()))
        val snapshot = f.store.exportRecovery(File(f.root, "opaque"))
        refused { f.store.restoreRecovery(snapshot.directory, snapshot.manifestSha256, File(f.root, "inactive-damaged")) }
        assertTrue(File(f.root, "inactive-damaged/${GatewayRecovery.INACTIVE}").isFile)
        assertTrue(f.file(GatewayInvocationCustody.TERMINAL).exists())
    }

    @Test fun successorKeepsDistinctRootRouteApprovalAndDigest(): Unit = Fixture().use { f ->
        val job = "ad760000-0000-4000-8000-000000000005"
        val approval = "ad760000-0000-4000-8000-000000000006"
        f.route = GatewayDispatchRoute.ReceiptSuccessorV1(receipt, job, approval)
        f.engine().dispatchOne()
        val binding = f.journal.invocationEvidence(attempt).getJSONObject("prepare").getJSONObject("binding")
        assertEquals("receipt_successor_v1", binding.getString("source_family")); assertEquals(receipt, binding.getString("root_receipt_id"))
        assertEquals(job, binding.getString("job_id")); assertEquals(approval, binding.getJSONObject("dispatch_route").getString("approval_id"))
        assertEquals(1, f.sends)
    }

    @Test fun enteredCustodySurvivesActualColdCompactionSelectedExportAndInactiveRecovery(): Unit = Fixture().use { f ->
        val initial = f.prepare(); GatewayInvocationCustody(f.store).enter(initial, at)
        val segment = initial.segments.single()
        for (kind in CallbackKind.entries) assertTrue(f.journal.record(GatewayCallback(
            if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId,
            device, attempt, 1, 0, initial.callbackNonce, kind, -1, at.toString())))
        val observed = f.journal.read().attempts.single()
        fun row(action: String, payload: JSONObject, version: Int): JSONObject {
            val id = UUID.randomUUID().toString()
            val text = JSONObject().put("contract_version", version).put("action", action).put("device_id", device)
                .put("request_id", id).put("issued_at", at.toString()).put("payload", payload).toString()
            return JSONObject().put("request_id", id).put("action", action).put("state", "recorded")
                .put("callback_id", if (action == "callback") payload.getString("callback_id") else JSONObject.NULL)
                .put("request_sha256", sha256(text)).put("request_bytes_base64", Base64.getEncoder().encodeToString(text.toByteArray()))
        }
        // Synthetic authenticated callback/ACK observations; no carrier proof.
        val rows = JSONArray()
        for (kind in CallbackKind.entries) rows.put(row("callback", JSONObject()
            .put("callback_id", if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId)
            .put("attempt_id", attempt).put("fence_version", 1).put("segment_index", 0).put("segment_count", 1)
            .put("body_sha256", observed.bodySha256).put("destination_sha256", observed.destinationSha256)
            .put("callback_kind", if (kind == CallbackKind.SENT) "sent" else "delivery")
            .put("result_code", -1).put("tp_status", JSONObject.NULL).put("occurred_at", at.toString()), 2))
        f.store.saveRequests(JSONObject().put("contract_version", 1).put("requests", rows))
        val payload = GatewayAttemptArchive(f.store).payload(observed)
        val original = GatewayStoredRequest.parse(row("archive_attempt", payload, 3))
        rows.put(original.row); f.store.saveRequests(JSONObject().put("contract_version", 1).put("requests", rows))
        val ack = JSONObject().put("request_id", original.requestId).put("device_id", device).put("attempt_id", attempt).put("fence_version", 1)
            .put("ok", true).put("code", JSONObject.NULL).put("archive_ack_id", UUID.randomUUID().toString()).put("receipt_id", receipt)
            .put("body_sha256", observed.bodySha256).put("destination_sha256", observed.destinationSha256).put("segment_count", 1)
            .put("callback_requests", payload.getJSONArray("callback_requests")).put("recorded_at", at.toString()).put("replay", false)
            .put("evidence_kind", "complete_framework_callback_observations").put("carrier_proof", false).put("delivery_proven", false).put("send_authority", false)
        val originals = listOf(GatewayInvocationCustody.PREPARE, GatewayInvocationCustody.TERMINAL).associateWith { f.file(it).readBytes() }
        GatewayAttemptArchive(f.store).acknowledge(original, ack)
        assertTrue(f.store.read().attempts.isEmpty()); assertEquals(0, f.store.readRequests().getJSONArray("requests").length())
        val reopened = GatewayEncryptedStore(f.context, f.factory)
        val cold = archiveAttemptFromJson(reopened.readColdAttempt(attempt)!!.getJSONObject("attempt"))
        assertEquals(observed, cold)
        assertEquals("invoke_entered", GatewayInvocationCustody(reopened).evidence(cold).getJSONObject("terminal").getString("phase"))
        refused { GatewayJournal(reopened).reserveInvocation(initial) }
        val selected = reopened.exportColdAttempt(attempt)
        for ((kind, bytes) in originals) assertArrayEquals(bytes, selected.encryptedParts[f.file(kind).name])
        val snapshot = reopened.exportRecovery(File(f.root, "cold-custody-snapshot"))
        val restored = reopened.restoreRecovery(snapshot.directory, snapshot.manifestSha256, File(f.root, "cold-custody-inactive"))
        assertTrue(restored.keyValidated); assertTrue(restored.requiresReEnrollment)
        for ((kind, bytes) in originals) assertArrayEquals(bytes, File(restored.directory, "original/${f.file(kind).name}").readBytes())
    }
}
