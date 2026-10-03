package app.cool.mobile.gateway

import android.content.Context
import android.util.AtomicFileFaults
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.Base64
import java.util.UUID
import javax.crypto.spec.SecretKeySpec

/** Executes real AES-GCM, immutable cold files and journal pruning with filesystem
 * shims. No real Keystore, power loss, transport, handset or carrier. */
class GatewayAttemptArchiveTest {
    private val device = "00000000-0000-0000-0000-000000000001"
    private val at = gatewayWireTime(Instant.now())
    private fun id() = UUID.randomUUID().toString()
    private class TestContext(private val root: File) : Context() { override val noBackupFilesDir get() = root }
    private fun withStore(test: (GatewayEncryptedStore, File, () -> GatewayEncryptedStore) -> Unit) {
        val root = Files.createTempDirectory("collect-cold-attempt-").toFile()
        val create = { GatewayEncryptedStore(TestContext(root)) { name -> GatewayCrypto(SecretKeySpec(ByteArray(32) { 18 }, "AES"), "CollectGateway/$name/v1") } }
        try { test(create(), File(root, "collect_gateway_v1"), create) }
        finally { AtomicFileFaults.failFinishOnce = false;root.deleteRecursively() }
    }
    private fun refuse(reason: String? = null, block: () -> Unit) {
        try { block();fail("Expected archive refusal") } catch (e: GatewayStateException) { if (reason != null) assertEquals(reason, e.reasonCode) }
    }
    private fun attempt(parts: Int = 1): GatewayAttempt = GatewayAttempt(device, id(), id(), 1, "a".repeat(64), "b".repeat(64),
        gatewayWireTime(Instant.parse(at).plusSeconds(30)), at, "c".repeat(64), List(parts) { SegmentEvidence(id(), id(), SegmentOutcome.FRAMEWORK_SENT, SegmentOutcome.DELIVERY_CALLBACK_OBSERVED, -1, -1, at, at) })
    private fun row(action: String, payload: JSONObject, version: Int = 2): JSONObject {
        val request = id();val text = JSONObject().put("contract_version", version).put("action", action).put("device_id", device).put("request_id", request).put("issued_at", at).put("payload", payload).toString()
        return JSONObject().put("request_id", request).put("action", action).put("state", "recorded").put("callback_id", if (action == "callback") payload.getString("callback_id") else JSONObject.NULL)
            .put("request_sha256", sha256(text)).put("request_bytes_base64", Base64.getEncoder().encodeToString(text.toByteArray()))
    }
    private fun callbacks(a: GatewayAttempt): List<JSONObject> = a.segments.flatMapIndexed { index, segment -> CallbackKind.entries.map { kind ->
        row("callback", JSONObject().put("callback_id", if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId)
            .put("attempt_id", a.attemptId).put("fence_version", a.fence).put("segment_index", index).put("segment_count", a.segments.size)
            .put("body_sha256", a.bodySha256).put("destination_sha256", a.destinationSha256).put("callback_kind", if (kind == CallbackKind.SENT) "sent" else "delivery")
            .put("result_code", -1).put("tp_status", JSONObject.NULL).put("occurred_at", at))
    } }
    private data class Proof(val original: GatewayStoredRequest, val ack: JSONObject)
    private fun prepare(store: GatewayEncryptedStore, a: GatewayAttempt = attempt(), extra: List<JSONObject> = emptyList()): Proof {
        store.commit(GatewayJournalState(emergencyPaused = false, attempts = listOf(a)))
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(callbacks(a) + extra)))
        val payload = GatewayAttemptArchive(store).payload(a);val r = row("archive_attempt", payload, 3)
        val original = GatewayStoredRequest.parse(r)
        val rows = store.readRequests().getJSONArray("requests");rows.put(r);store.saveRequests(JSONObject().put("contract_version", 1).put("requests", rows))
        val ack = JSONObject().put("request_id", original.requestId).put("device_id", device).put("attempt_id", a.attemptId).put("fence_version", a.fence)
            .put("ok", true).put("code", JSONObject.NULL).put("archive_ack_id", id()).put("receipt_id", a.jobId).put("body_sha256", a.bodySha256)
            .put("destination_sha256", a.destinationSha256).put("segment_count", a.segments.size).put("callback_requests", payload.getJSONArray("callback_requests"))
            .put("recorded_at", at).put("replay", false).put("evidence_kind", "complete_framework_callback_observations").put("carrier_proof", false).put("delivery_proven", false).put("send_authority", false)
        return Proof(original, ack)
    }
    private fun acknowledge(store: GatewayEncryptedStore, proof: Proof) = GatewayAttemptArchive(store).acknowledge(proof.original, proof.ack)
    private fun callback(a: GatewayAttempt, code: Int = 1, nonce: String = a.callbackNonce, callbackId: String = a.segments[0].sentCallbackId) =
        GatewayCallback(callbackId, a.deviceId, a.attemptId, a.fence, 0, nonce, CallbackKind.SENT, code, gatewayWireTime(Instant.parse(at).plusSeconds(1)))

    private fun cold(a: GatewayAttempt, p: Proof, store: GatewayEncryptedStore) = JSONObject().put("contract_version", 3)
        .put("attempt", archiveAttemptJson(a)).put("archive_request", p.original.row).put("acknowledgement", p.ack)
        .put("callback_requests", JSONArray(callbacksFromStore(store))).put("archived_at", at)
    private fun fixtureWrite(directory: File, name: String, value: JSONObject) {
        val crypto = GatewayCrypto(SecretKeySpec(ByteArray(32) { 18 }, "AES"), "CollectGateway/$name/v1")
        File(directory, "$name.bin").writeBytes(crypto.encrypt(value.toString().toByteArray()))
    }
    private fun orphan(directory: File, a: GatewayAttempt, p: Proof, store: GatewayEncryptedStore) {
        // Actual encrypted bytes for the exact crash interval: object durable,
        // established control durable, shard/catalog append not committed.
        fixtureWrite(directory, "cold-marker", JSONObject().put("contract_version", 3).put("established", true))
        fixtureWrite(directory, "cold-control", JSONObject().put("contract_version", 3).put("stopped", false)
            .put("late_attempt_ids", JSONArray()).put("cold_shards", JSONArray()))
        fixtureWrite(directory, "cold-${a.attemptId}", cold(a, p, store))
    }

    @Test fun objectBeforeIndexCrashRetainsOriginalsThenExactLookupRepairsCapacityMetadata() = withStore { store, directory, reopen ->
        val a = attempt();val p = prepare(store, a);orphan(directory, a, p, store)
        assertEquals(listOf(a), reopen().read().attempts);assertEquals(3, reopen().readRequests().getJSONArray("requests").length())
        assertTrue(reopen().hasArchivedAttempt(a.attemptId))
        acknowledge(reopen(), p)
        assertTrue(File(directory, "retention-index-attempt-${retentionUuidKey(a.attemptId).take(2)}.bin").isFile)
        assertTrue(reopen().read().attempts.isEmpty());assertEquals(0, reopen().readRequests().getJSONArray("requests").length())
        File(directory, "retention-index-attempt-${retentionUuidKey(a.attemptId).take(2)}.bin").delete()
        refuse("gateway_retention_missing") { reopen().readColdAttempt(a.attemptId) }
    }
    @Test fun objectBeforeIndexLateConflictIsRetainedAndStopSurvivesRepair() = withStore { store, directory, reopen ->
        val a = attempt();val p = prepare(store, a);orphan(directory, a, p, store)
        assertTrue(GatewayJournal(reopen()).record(callback(a)));assertTrue(reopen().coldStop())
        assertEquals(listOf(a), reopen().read().attempts)
        acknowledge(reopen(), p)
        assertTrue(reopen().read().attempts.isEmpty());assertTrue(GatewayJournal(reopen()).read().emergencyPaused)
        assertEquals(1, reopen().coldPendingCallbacks().size)
    }
    @Test fun legacyShardWithMissingReferencedEvidenceCannotBecomeNewCapacity() = withStore { store, directory, reopen ->
        val a = attempt();val p = prepare(store, a);orphan(directory, a, p, store)
        val shard = sha256(a.attemptId).take(2);val ids = JSONArray()
        while (ids.length() < GatewayEncryptedStore.MAX_COLD_SHARD) {
            val candidate = id();if (candidate != a.attemptId && sha256(candidate).take(2) == shard) ids.put(candidate)
        }
        fixtureWrite(directory, "cold-index-$shard", JSONObject().put("contract_version", 3).put("attempt_ids", ids))
        fixtureWrite(directory, "cold-control", JSONObject().put("contract_version", 3).put("stopped", false)
            .put("late_attempt_ids", JSONArray()).put("cold_shards", JSONArray(listOf(shard))))
        val journalBytes = File(directory, "journal.bin").readBytes()
        val requestBytes = File(directory, "requests.bin").readBytes()
        refuse { acknowledge(reopen(), p) }
        // The catalog deliberately references missing old objects. New global
        // identity admission stays closed, and original evidence stays exact.
        assertArrayEquals(journalBytes, File(directory, "journal.bin").readBytes())
        assertArrayEquals(requestBytes, File(directory, "requests.bin").readBytes())
        refuse { reopen().readRequests() }
    }
    private fun ackBytes(p: Proof): String = JSONObject().put("contract_version", 3).put("action", "archive_attempt")
        .put("device_id", device).put("request_id", p.original.requestId).put("result", p.ack).toString()
    private fun parse(p: Proof, text: String) = parseGatewayArchiveReply("archive_attempt", p.original.requestId, device,
        p.original.envelope.getJSONObject("payload"), text.toByteArray())
    @Test fun duplicateAndEscapedDuplicateAckKeysNeverBecomeCompactionAuthority() = withStore { store, _, _ ->
        val p = prepare(store);val text = ackBytes(p)
        for (key in listOf("contract_version", "result", "ok", "request_id")) {
            val marker = "\"$key\":";val value = if (key == "result") p.ack.toString() else if (key == "ok") "true" else if (key == "contract_version") "3" else "\"${p.original.requestId}\""
            refuse { parse(p, text.replaceFirst(marker, "$marker$value,$marker")) }
        }
        refuse { parse(p, text.replaceFirst("\"ok\":", "\"\\u006fk\":false,\"ok\":")) }
        assertEquals(1, store.read().attempts.size)
    }
    @Test fun permissiveJsonCommentsSingleQuotesAndTrailingContentAreRejected() = withStore { store, _, _ ->
        val p = prepare(store);val text = ackBytes(p)
        for (bad in listOf(text.replaceFirst("{", "{/*x*/"), text.replaceFirst("\"ok\"", "'ok'"), text.replaceFirst("\"ok\":", "ok:"), text + "{}", "\uFEFF" + text)) {
            refuse { parse(p, bad) }
        };assertEquals(1, store.read().attempts.size)
    }
    @Test fun exactStrictAckByteParserAcceptsOnlyBoundedUtf8() = withStore { store, _, _ ->
        val p = prepare(store);assertEquals(p.original.requestId, parse(p, ackBytes(p)).getString("request_id"))
        refuse { parseGatewayArchiveReply("archive_attempt", p.original.requestId, device, p.original.envelope.getJSONObject("payload"), byteArrayOf(0xc0.toByte(), 0xaf.toByte())) }
        refuse { parse(p, " ".repeat(32769)) }
    }

    @Test fun exactMultipartAckColdReadbackThenPrunesOnlyKnownActiveEvidence() = withStore { store, _, reopen ->
        val a = attempt(2);val unknown = row("heartbeat", JSONObject(), 1).put("state", "outcome_unknown")
        val p = prepare(store, a, listOf(unknown));acknowledge(store, p)
        assertTrue(reopen().read().attempts.isEmpty());assertEquals(1, reopen().readRequests().getJSONArray("requests").length())
        assertEquals(unknown.toString(), reopen().readRequests().getJSONArray("requests").getJSONObject(0).toString())
        assertEquals(a, archiveAttemptFromJson(reopen().readColdAttempt(a.attemptId)!!.getJSONObject("attempt")))
    }
    @Test fun coldIdentityCanNeverReserveAnotherInvocation() = withStore { store, _, _ ->
        val a = attempt();acknowledge(store, prepare(store, a))
        refuse("gateway_attempt_already_invoked") { GatewayJournal(store).reserveInvocation(a.copy(segments = listOf(SegmentEvidence()))) }
    }
    @Test fun localUnknownAttemptCannotPrepareArchiveEvenWithLocalCallbackFlags() = withStore { store, _, _ ->
        val a = attempt().copy(invocationException = true);store.commit(GatewayJournalState(attempts = listOf(a)))
        refuse("gateway_archive_attempt_unresolved") { GatewayAttemptArchive(store).payload(a) }
    }
    @Test fun incompleteMultipartEvidenceStaysActive() = withStore { store, _, _ ->
        val a = attempt(2).copy(segments = listOf(attempt().segments[0], SegmentEvidence()))
        store.commit(GatewayJournalState(attempts = listOf(a)))
        refuse("gateway_archive_attempt_unresolved") { GatewayAttemptArchive(store).payload(a) };assertEquals(1, store.read().attempts.size)
    }
    @Test fun missingOriginalSignedCallbackRequestNeverUsesLocalFlagsAsAck() = withStore { store, _, _ ->
        val a = attempt();store.commit(GatewayJournalState(attempts = listOf(a)))
        refuse("gateway_archive_acknowledgement_pending") { GatewayAttemptArchive(store).payload(a) }
    }
    @Test fun rejectedOrReplayedAckNeverPrunesEvidence() = withStore { store, _, _ ->
        val p = prepare(store);p.ack.put("replay", true)
        refuse("gateway_archive_acknowledgement_pending") { acknowledge(store, p) };assertEquals(1, store.read().attempts.size)
    }
    @Test fun inventedDeliveryProofOrSendAuthorityIsRejected() = withStore { store, _, _ ->
        val p = prepare(store)
        for (key in listOf("carrier_proof", "delivery_proven", "send_authority")) {
            val bad = JSONObject(p.ack.toString()).put(key, true)
            refuse { GatewayAttemptArchive(store).acknowledge(p.original, bad) }
        };assertEquals(1, store.read().attempts.size)
    }
    @Test fun wrongReceiptFenceDigestAndOriginalUuidCannotCompact() = withStore { store, _, _ ->
        val p = prepare(store)
        for ((key, value) in listOf("receipt_id" to id(), "fence_version" to 2, "body_sha256" to "f".repeat(64), "request_id" to id())) {
            refuse { GatewayAttemptArchive(store).acknowledge(p.original, JSONObject(p.ack.toString()).put(key, value)) }
        };assertEquals(1, store.read().attempts.size)
    }
    @Test fun callbacksArrivingBeforeCompactionInvalidateSnapshot() = withStore { store, _, _ ->
        val a = attempt();val p = prepare(store, a);assertTrue(GatewayJournal(store).record(callback(a)))
        acknowledge(store, p)
        assertEquals(1, store.read().attempts.size);assertEquals(3, store.readRequests().getJSONArray("requests").length())
        assertNull(store.readColdAttempt(a.attemptId));assertTrue(store.coldStop())
        assertEquals(p.original.requestId, GatewayStoredRequest.parse(store.readUncompactableAck(a.attemptId)!!.getJSONObject("archive_request")).requestId)
        refuse("gateway_archived_conflict_pending") { GatewayJournal(store).resume() }
    }
    @Test fun staleKnownSnapshotCannotPrepareAnArchiveAfterCurrentSourceContradicts() = withStore { store, _, _ ->
        val a = attempt();prepare(store, a);assertTrue(GatewayJournal(store).record(callback(a)))
        refuse("gateway_archive_source_conflict") { GatewayAttemptArchive(store).payload(a) }
        assertEquals(1, store.read().attempts.size);assertTrue(store.coldStop())
    }
    @Test fun atomicFailurePreservesOriginalUnknownIdentityAndActiveAttempt() = withStore { store, _, reopen ->
        val p = prepare(store);AtomicFileFaults.failFinishOnce = true
        refuse("gateway_storage_unavailable") { acknowledge(store, p) }
        assertEquals(1, reopen().read().attempts.size);assertEquals(3, reopen().readRequests().getJSONArray("requests").length())
    }
    @Test fun coldCommitBeforePruneCrashIsRecoverableWithoutMutationReplay() = withStore { store, _, reopen ->
        val a = attempt();val p = prepare(store, a)
        val cold = JSONObject().put("contract_version", 3).put("attempt", archiveAttemptJson(a)).put("archive_request", p.original.row).put("acknowledgement", p.ack)
            .put("callback_requests", JSONArray(callbacksFromStore(store))).put("archived_at", at)
        store.commitColdAttempt(a.attemptId, cold)
        assertEquals(0, reopen().read().attempts.size);assertEquals(0, reopen().readRequests().getJSONArray("requests").length())
        GatewayAttemptArchive(reopen()).acknowledge(p.original, p.ack);assertTrue(reopen().read().attempts.isEmpty())
    }
    private fun callbacksFromStore(store: GatewayEncryptedStore) = store.readRequests().getJSONArray("requests").let { rows ->
        (0 until rows.length()).map { rows.getJSONObject(it) }.filter { it.getString("action") == "callback" }
    }
    @Test fun knownLateCallbackDuplicateNeedsNoNewUploadOrUnpause() = withStore { store, _, _ ->
        val a = attempt();acknowledge(store, prepare(store, a));assertTrue(GatewayJournal(store).record(callback(a, -1)))
        assertTrue(store.coldPendingCallbacks().isEmpty());assertFalse(store.coldStop())
    }
    @Test fun lateContradictionDurablyStopsAndCannotResumeOrReserve() = withStore { store, _, reopen ->
        val a = attempt();acknowledge(store, prepare(store, a));assertTrue(GatewayJournal(store).record(callback(a)))
        assertTrue(GatewayJournal(reopen()).read().emergencyPaused);assertEquals(1, reopen().coldPendingCallbacks().size)
        refuse("gateway_archived_conflict_pending") { GatewayJournal(reopen()).resume() }
        refuse("gateway_archived_conflict_pending") { GatewayJournal(reopen()).reserveInvocation(attempt().copy(segments = listOf(SegmentEvidence()))) }
    }
    @Test fun duplicateContradictionNeverOverwritesOriginalOrAddsAnotherEvent() = withStore { store, _, _ ->
        val a = attempt();acknowledge(store, prepare(store, a));val before = store.exportColdAttempt(a.attemptId).encryptedParts.values.first()
        GatewayJournal(store).record(callback(a));GatewayJournal(store).record(callback(a))
        assertEquals(1, store.coldPendingCallbacks().size);assertArrayEquals(before, store.exportColdAttempt(a.attemptId).encryptedParts.values.first())
    }
    @Test fun forgedArchivedCallbackNonceOrIdentityIsIgnored() = withStore { store, _, _ ->
        val a = attempt();acknowledge(store, prepare(store, a))
        assertFalse(GatewayJournal(store).record(callback(a, nonce = "f".repeat(64))))
        assertFalse(GatewayJournal(store).record(callback(a, callbackId = id())))
        assertFalse(store.coldStop());assertTrue(store.coldPendingCallbacks().isEmpty())
    }
    @Test fun encryptedExportIsExactLosslessAndDoesNotEvictTombstone() = withStore { store, directory, reopen ->
        val a = attempt();acknowledge(store, prepare(store, a));GatewayJournal(store).record(callback(a))
        val export = store.exportColdAttempt(a.attemptId);assertEquals(2, export.encryptedParts.size)
        for ((name, bytes) in export.encryptedParts) {
            assertArrayEquals(File(directory, name).readBytes(), bytes);assertFalse(String(bytes).contains(a.attemptId))
        }
        assertTrue(reopen().hasArchivedAttempt(a.attemptId));assertEquals(1, reopen().coldPendingCallbacks().size)
    }
    @Test fun coldCiphertextTamperFailsClosedOnLookupAndExport() = withStore { store, directory, reopen ->
        val a = attempt();acknowledge(store, prepare(store, a));val f = File(directory, "cold-${a.attemptId}.bin")
        f.writeBytes(f.readBytes().also { it[it.lastIndex] = (it.last().toInt() xor 1).toByte() })
        refuse("gateway_storage_unavailable") { reopen().hasArchivedAttempt(a.attemptId) }
        refuse("gateway_storage_unavailable") { reopen().exportColdAttempt(a.attemptId) }
    }
    @Test fun missingIndexedColdEvidenceNeverLooksLikeUnusedIdentity() = withStore { store, directory, reopen ->
        val a = attempt();acknowledge(store, prepare(store, a));File(directory, "cold-${a.attemptId}.bin").delete()
        refuse("gateway_cold_archive_missing") { reopen().hasArchivedAttempt(a.attemptId) }
    }
    @Test fun missingEstablishedShardIndexNeverResetsCapacityOrIdentity() = withStore { store, directory, reopen ->
        val a = attempt();acknowledge(store, prepare(store, a));File(directory, "retention-index-attempt-${retentionUuidKey(a.attemptId).take(2)}.bin").delete()
        refuse("gateway_retention_missing") { reopen().hasArchivedAttempt(a.attemptId) }
    }
    @Test fun missingBothControlFilesNeverErasesEstablishedLateConflictStop() = withStore { store, directory, reopen ->
        val a = attempt();acknowledge(store, prepare(store, a));GatewayJournal(store).record(callback(a))
        File(directory, "cold-marker.bin").delete();File(directory, "cold-control.bin").delete()
        refuse("gateway_cold_archive_missing") { reopen().coldStop() }
        refuse("gateway_cold_archive_missing") { GatewayJournal(reopen()).resume() }
    }
    @Test fun lateConflictOnArchiveFirstRestartRoutesToDurableColdEvidence() = withStore { store, _, reopen ->
        val a = attempt();val p = prepare(store, a)
        val cold = JSONObject().put("contract_version", 3).put("attempt", archiveAttemptJson(a)).put("archive_request", p.original.row).put("acknowledgement", p.ack)
            .put("callback_requests", JSONArray(callbacksFromStore(store))).put("archived_at", at)
        store.commitColdAttempt(a.attemptId, cold)
        assertTrue(GatewayJournal(reopen()).record(callback(a)));assertTrue(GatewayJournal(reopen()).read().emergencyPaused)
        assertEquals(1, reopen().coldPendingCallbacks().size);assertTrue(reopen().read().attempts.isEmpty())
    }
    @Test fun immutableColdObjectCannotBeChangedAfterCompaction() = withStore { store, _, _ ->
        val a = attempt();acknowledge(store, prepare(store, a));val cold = store.readColdAttempt(a.attemptId)!!
        cold.put("archived_at", gatewayWireTime(Instant.parse(at).plusSeconds(1)))
        refuse("gateway_archive_immutable") { store.commitColdAttempt(a.attemptId, cold) }
    }
    @Test fun segmentedColdStorageSurvivesMoreThanOneHundredAttempts() = withStore { store, _, reopen ->
        val ids = ArrayList<String>()
        repeat(102) { val a = attempt();ids.add(a.attemptId);acknowledge(store, prepare(store, a)) }
        assertTrue(reopen().read().attempts.isEmpty());assertTrue(reopen().readRequests().getJSONArray("requests").length() == 0)
        for (id in ids) assertTrue(reopen().hasArchivedAttempt(id))
        assertTrue(reopen().readArchive().getJSONArray("attempts").length() == 0)
    }
    @Test fun sourceMutationCannotReplaceArchivedOriginalSignedBytes() = withStore { store, _, _ ->
        val a = attempt();val p = prepare(store, a);acknowledge(store, p)
        refuse { store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(p.original.row)))) }
    }
    @Test fun unknownLookupNeverCreatesArchiveAuthority() {
        val req = id();val target = id();val payload = JSONObject().put("target_request_id", target)
        val result = JSONObject().put("target_request_id", target).put("outcome", "unknown").put("recorded_result", JSONObject.NULL)
        validateGatewayArchiveResult("archive_lookup", req, device, payload, result)
        refuse { validateGatewayArchiveResult("archive_lookup", req, device, payload, result.put("recorded_result", JSONObject())) }
    }
    @Test fun attemptsContinueBeyondOneLegacyHashShardWithoutGrowingIndexObjects() = withStore { store, directory, reopen ->
        val chosen = "ab";val retained = mutableListOf<GatewayAttempt>()
        repeat(129) {
            var candidate = attempt()
            while (sha256(candidate.attemptId).take(2) != chosen) candidate = attempt()
            acknowledge(store, prepare(store, candidate));retained.add(candidate)
        }
        assertTrue(reopen().read().attempts.isEmpty())
        for (attempt in retained) assertEquals(attempt, archiveAttemptFromJson(reopen().readColdAttempt(attempt.attemptId)!!.getJSONObject("attempt")))
        assertFalse(File(directory, "cold-index-$chosen.bin").exists())
        assertTrue(directory.listFiles()!!.filter { it.name.startsWith("retention-index-") }.all { it.length() < 16384 })
    }
    @Test fun compactedUuidCannotChangeActionOrAttemptAndMissingTerminalIsCorruption() = withStore { store, directory, reopen ->
        val a = attempt();val p = prepare(store, a);val original = callbacksFromStore(store).first();acknowledge(store, p)
        val id = original.getString("request_id")
        fun changed(action: String, payload: JSONObject, version: Int): JSONObject {
            val body = JSONObject().put("contract_version", version).put("action", action).put("device_id", device).put("request_id", id).put("issued_at", at).put("payload", payload).toString()
            return JSONObject().put("request_id", id).put("action", action).put("state", "outcome_unknown").put("callback_id", if (action == "callback") payload.getString("callback_id") else JSONObject.NULL)
                .put("request_sha256", sha256(body)).put("request_bytes_base64", Base64.getEncoder().encodeToString(body.toByteArray()))
        }
        refuse("gateway_archive_source_conflict") { store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(changed("heartbeat", JSONObject(), 1))))) }
        val payload = JSONObject(GatewayStoredRequest.parse(original).envelope.getJSONObject("payload").toString()).put("attempt_id", id())
        refuse("gateway_archive_source_conflict") { store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(changed("callback", payload, 2))))) }
        File(directory, "retention-terminal-${retentionUuidKey(id)}.bin").delete()
        refuse("gateway_retention_missing") { reopen().saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(original)))) }
    }
    @Test fun retainedProtocolAndCallbackAliasesSurviveCompactionAndMissingAliasFailsClosed() = withStore { store, directory, reopen ->
        val a = attempt();val arm = row("arm_dispatch", JSONObject().put("attempt_id", a.attemptId))
        val p = prepare(store, a, listOf(arm));val callbacks = callbacksFromStore(store);acknowledge(store, p)
        assertTrue(reopen().retainedAttemptUsesV2(a.attemptId))
        for (r in callbacks) { val request = GatewayStoredRequest.parse(r);assertTrue(reopen().retainedCallbackRequest(request.callbackId!!, request.envelope.getJSONObject("payload"), true)) }
        val callback = GatewayStoredRequest.parse(callbacks.first());val payload = callback.envelope.getJSONObject("payload")
        val key = sha256(callback.callbackId + "\n" + retentionCanonical(payload)).take(32)
        File(directory, "retention-callback-body-$key.bin").delete()
        refuse("gateway_retention_missing") { reopen().retainedCallbackRequest(callback.callbackId!!, payload, true) }
    }
    @Test fun callbackReceiptAcknowledgementsStayHotUntilActualAttemptArchiveClosesThem() = withStore { store, _, reopen ->
        val a = attempt();store.commit(GatewayJournalState(false, listOf(a)))
        val callbacks = callbacks(a)
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(callbacks)))
        for (row in callbacks) {
            val original = GatewayStoredRequest.parse(row)
            val result = JSONObject().put("callback_id", original.callbackId).put("recorded_at", at).put("replay", false).put("carrier_proof", false)
                .put("state", "observed_sent").put("sent_observations", 1)
                .put("delivery_observations", if (original.envelope.getJSONObject("payload").getString("callback_kind") == "delivery") 1 else 0)
                .put("conflicting_observations", false)
            val reply = JSONObject().put("contract_version", 2).put("action", "callback").put("device_id", device).put("request_id", original.requestId).put("result", result)
            GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(original, reply))
        }
        assertEquals(2, reopen().readRequests().getJSONArray("requests").length())
        GatewayJournalArchive(reopen()).archiveAcknowledgedAttempt(a.attemptId)
        assertNotNull(reopen().readObservedAttempt(a.attemptId))
        val payload = GatewayAttemptArchive(reopen()).payload(a)
        val original = GatewayStoredRequest.parse(row("archive_attempt", payload, 3))
        val active = reopen().readRequests();active.getJSONArray("requests").put(original.row);reopen().saveRequests(active)
        val ack = JSONObject().put("request_id", original.requestId).put("device_id", device).put("attempt_id", a.attemptId).put("fence_version", a.fence)
            .put("ok", true).put("code", JSONObject.NULL).put("archive_ack_id", id()).put("receipt_id", a.jobId).put("body_sha256", a.bodySha256)
            .put("destination_sha256", a.destinationSha256).put("segment_count", 1).put("callback_requests", payload.getJSONArray("callback_requests"))
            .put("recorded_at", at).put("replay", false).put("evidence_kind", "complete_framework_callback_observations").put("carrier_proof", false).put("delivery_proven", false).put("send_authority", false)
        GatewayAttemptArchive(reopen()).acknowledge(original, ack)
        assertTrue(reopen().read().attempts.isEmpty());assertEquals(0, reopen().readRequests().getJSONArray("requests").length())
        for (callback in callbacks) assertNotNull(reopen().readRequestReceipt(callback.getString("request_id")))
    }
    @Test fun continuousV1CallbackReceiptsSupportObservationalArchiveWithoutTerminalAuthority() = withStore { store, _, reopen ->
        val a = attempt();store.commit(GatewayJournalState(false, listOf(a)))
        val callbacks = callbacks(a).map { old -> row("callback", GatewayStoredRequest.parse(old).envelope.getJSONObject("payload"), 1) }
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(callbacks)))
        for (row in callbacks) {
            val original = GatewayStoredRequest.parse(row)
            val result = JSONObject().put("callback_id", original.callbackId).put("recorded_at", at).put("replay", false).put("carrier_proof", false)
            val reply = JSONObject().put("contract_version", 1).put("action", "callback").put("device_id", device).put("request_id", original.requestId).put("result", result)
            GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(original, reply))
        }
        GatewayJournalArchive(reopen()).archiveAcknowledgedAttempt(a.attemptId)
        assertNotNull(reopen().readObservedAttempt(a.attemptId));assertEquals(listOf(a), reopen().read().attempts)
        assertEquals(2, reopen().readRequests().getJSONArray("requests").length())
        assertFalse(reopen().terminalArchivedAttempt(a.attemptId))
        refuse("gateway_attempt_archive_authority_pending") { GatewayJournalArchive(reopen()).compactAttempt(a.attemptId) }
        val before = reopen().readObservedAttempt(a.attemptId)!!.toString()
        assertTrue(GatewayJournal(reopen()).record(callback(a)))
        assertTrue(reopen().coldStop());assertTrue(GatewayJournal(reopen()).read().emergencyPaused)
        assertEquals(listOf(a), reopen().read().attempts);assertEquals(before, reopen().readObservedAttempt(a.attemptId)!!.toString())
        assertEquals(1, reopen().coldPendingCallbacks().size)
        refuse("gateway_archived_conflict_pending") { GatewayJournal(reopen()).resume() }
        refuse("gateway_attempt_archive_authority_pending") { reopen().commit(GatewayJournalState(true, emptyList())) }
    }

}
