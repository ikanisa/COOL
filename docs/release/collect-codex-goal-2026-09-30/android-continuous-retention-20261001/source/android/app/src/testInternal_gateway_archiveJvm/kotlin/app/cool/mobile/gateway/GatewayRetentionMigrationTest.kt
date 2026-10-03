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

/** Exact pre-upgrade encrypted fixtures and bounded restart migration. No
 * network, handset, provider or real storage-quota acceptance is inferred. */
class GatewayRetentionMigrationTest {
    private val device = "00000000-0000-0000-0000-000000000001"
    private val at = "2026-10-01T13:00:00Z"
    private fun id() = UUID.randomUUID().toString()
    private class LocalContext(private val root: File) : Context() { override val noBackupFilesDir get() = root }
    private fun withStore(test: (GatewayEncryptedStore, File, () -> GatewayEncryptedStore) -> Unit) {
        val root = Files.createTempDirectory("collect-retention-migration-").toFile()
        val create = { GatewayEncryptedStore(LocalContext(root)) { name -> GatewayCrypto(SecretKeySpec(ByteArray(32) { 19 }, "AES"), "CollectGateway/$name/v1") } }
        try { test(create(), File(root, "collect_gateway_v1"), create) }
        finally { AtomicFileFaults.failFinishOnce = false;AtomicFileFaults.failFileOnce = null;root.deleteRecursively() }
    }
    private fun refuse(reason: String, action: () -> Unit) {
        try { action();fail("Expected refusal") } catch (e: GatewayStateException) { assertEquals(reason, e.reasonCode) }
    }
    private fun row(action: String, payload: JSONObject, version: Int, requestId: String = id()): JSONObject {
        val body = JSONObject().put("contract_version", version).put("action", action).put("device_id", device).put("request_id", requestId).put("issued_at", at).put("payload", payload).toString()
        return JSONObject().put("request_id", requestId).put("action", action).put("state", "outcome_unknown")
            .put("callback_id", if (action == "callback") payload.getString("callback_id") else JSONObject.NULL)
            .put("request_sha256", sha256(body)).put("request_bytes_base64", Base64.getEncoder().encodeToString(body.toByteArray()))
    }
    private fun writeLegacy(directory: File, name: String, value: JSONObject) {
        File(directory, "$name.bin").writeBytes(GatewayCrypto(SecretKeySpec(ByteArray(32) { 19 }, "AES"), "CollectGateway/$name/v1").encrypt(value.toString().toByteArray()))
    }
    private fun retainOnlyLegacyFiles(directory: File) {
        // Reconstruct the older installed layout, rather than treating erased
        // current control metadata as an acceptable live recovery operation.
        directory.listFiles()!!.filter { it.name.startsWith("retention-") }.forEach { assertTrue(it.delete()) }
    }
    @Test fun preUpgradeHotOriginalsMigrateFourAtATimeBeforeNewAdmissionAndRejectChangedAttempt() = withStore { store, directory, reopen ->
        val originals = (0 until 6).map { row("arm_dispatch", JSONObject().put("attempt_id", id()), 2) }
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(originals)))
        val oldBytes = File(directory, "requests.bin").readBytes()
        retainOnlyLegacyFiles(directory)
        val fresh = row("heartbeat", JSONObject(), 1)
        refuse("gateway_retention_migration_pending") { reopen().saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(originals + fresh))) }
        assertEquals(4, originals.count { reopen().readRetainedRequest(it.getString("request_id")) != null })
        val changed = row("arm_dispatch", JSONObject().put("attempt_id", id()), 2, originals.last().getString("request_id"))
        refuse("gateway_archive_source_conflict") { reopen().saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(originals.dropLast(1) + changed + fresh))) }
        assertEquals(6, originals.count { reopen().readRetainedRequest(it.getString("request_id")) != null })
        assertArrayEquals(oldBytes, File(directory, "requests.bin").readBytes())
        for (original in originals) assertEquals(original.getString("request_bytes_base64"), reopen().readRetainedRequest(original.getString("request_id"))!!.row.getString("request_bytes_base64"))
    }
    private fun createLegacyCold(store: GatewayEncryptedStore, directory: File): Pair<GatewayAttempt, GatewayStoredRequest> {
        val attempt = GatewayAttempt(device, id(), id(), 1, "a".repeat(64), "b".repeat(64), gatewayWireTime(Instant.parse(at).plusSeconds(30)), at, "c".repeat(64),
            listOf(SegmentEvidence(id(), id(), SegmentOutcome.FRAMEWORK_SENT, SegmentOutcome.DELIVERY_CALLBACK_OBSERVED, -1, -1, at, at)))
        store.commit(GatewayJournalState(false, listOf(attempt)))
        val callbacks = CallbackKind.entries.map { kind -> row("callback", JSONObject().put("callback_id", if (kind == CallbackKind.SENT) attempt.segments[0].sentCallbackId else attempt.segments[0].deliveryCallbackId)
            .put("attempt_id", attempt.attemptId).put("fence_version", 1).put("segment_index", 0).put("segment_count", 1).put("body_sha256", attempt.bodySha256)
            .put("destination_sha256", attempt.destinationSha256).put("callback_kind", if (kind == CallbackKind.SENT) "sent" else "delivery").put("result_code", -1).put("tp_status", JSONObject.NULL).put("occurred_at", at), 2) }
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(callbacks)))
        val payload = GatewayAttemptArchive(store).payload(attempt)
        val original = GatewayStoredRequest.parse(row("archive_attempt", payload, 3))
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(callbacks + original.row)))
        val ack = JSONObject().put("request_id", original.requestId).put("device_id", device).put("attempt_id", attempt.attemptId).put("fence_version", 1)
            .put("ok", true).put("code", JSONObject.NULL).put("archive_ack_id", id()).put("receipt_id", attempt.jobId).put("body_sha256", attempt.bodySha256)
            .put("destination_sha256", attempt.destinationSha256).put("segment_count", 1).put("callback_requests", payload.getJSONArray("callback_requests"))
            .put("recorded_at", at).put("replay", false).put("evidence_kind", "complete_framework_callback_observations").put("carrier_proof", false).put("delivery_proven", false).put("send_authority", false)
        GatewayAttemptArchive(store).acknowledge(original, ack)
        retainOnlyLegacyFiles(directory)
        val shard = sha256(attempt.attemptId).take(2)
        writeLegacy(directory, "cold-index-$shard", JSONObject().put("contract_version", 3).put("attempt_ids", JSONArray(listOf(attempt.attemptId))))
        writeLegacy(directory, "cold-control", JSONObject().put("contract_version", 3).put("stopped", false).put("late_attempt_ids", JSONArray()).put("cold_shards", JSONArray(listOf(shard))))
        return attempt to original
    }
    @Test fun legacyColdMigrationReservesOriginalUuidAcrossActionsWithoutChangingCiphertext() = withStore { store, directory, reopen ->
        val (attempt, original) = createLegacyCold(store, directory)
        val before = File(directory, "cold-${attempt.attemptId}.bin").readBytes()
        assertTrue(reopen().migrateLegacyRetention())
        requireSameRequest(original, reopen().readRetainedRequest(original.requestId)!!)
        val changed = row("heartbeat", JSONObject(), 1, original.requestId)
        refuse("gateway_archive_source_conflict") { reopen().saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(changed)))) }
        assertArrayEquals(before, File(directory, "cold-${attempt.attemptId}.bin").readBytes())
    }
    @Test fun interruptedLegacyColdMigrationRepeatsOnlyLocalOriginalPublication() = withStore { store, directory, reopen ->
        val (attempt, original) = createLegacyCold(store, directory)
        val before = File(directory, "cold-${attempt.attemptId}.bin").readBytes()
        AtomicFileFaults.failFileOnce = "retention-terminal-${retentionUuidKey(original.requestId)}.bin"
        refuse("gateway_storage_unavailable") { reopen().migrateLegacyRetention() }
        assertTrue(reopen().migrateLegacyRetention())
        assertTrue(reopen().requestAcknowledged(original))
        requireSameRequest(original, reopen().readRetainedRequest(original.requestId)!!)
        assertArrayEquals(before, File(directory, "cold-${attempt.attemptId}.bin").readBytes())
        assertFalse(directory.list()!!.any { it.endsWith(".new") })
    }    @Test fun everyFirstPublicationWriteBoundaryRepairsOnlyTheSameImmutableObject() {
        val key = retentionUuidKey(id());val value = JSONObject().put("original", "exact bytes")
        val baseline = linkedMapOf<String, JSONObject>();var writes = 0
        val count = GatewayRetentionIndex({ name -> baseline[name]?.let { JSONObject(it.toString()) } }, { name, objectValue -> writes++;baseline[name] = JSONObject(objectValue.toString()) },
            { baseline.keys.any { it.startsWith("retention-index-") || it.startsWith("retention-request-") } })
        count.publish("request", key, value)
        assertEquals(21, writes)
        for (boundary in 1..writes) {
            val objects = linkedMapOf<String, JSONObject>();var position = 0;var fail = true
            val index = GatewayRetentionIndex({ name -> objects[name]?.let { JSONObject(it.toString()) } }, { name, objectValue ->
                if (++position == boundary && fail) { fail = false;throw GatewayStateException("gateway_storage_unavailable") }
                objects[name] = JSONObject(objectValue.toString())
            }, { objects.keys.any { it.startsWith("retention-index-") || it.startsWith("retention-request-") } })
            refuse("gateway_storage_unavailable") { index.publish("request", key, value) }
            index.publish("request", key, value)
            assertTrue(index.indexed("request", key));assertEquals(value.toString(), index.read("request", key)!!.toString())
            refuse("gateway_archive_immutable") { index.publish("request", key, JSONObject().put("original", "different bytes")) }
        }
    }
    @Test fun interruptedCallbackAliasIsRecoveredFromPendingOriginalBeforeAnyReceiptCanPrune() = withStore { store, _, reopen ->
        val callbackId = id();val payload = JSONObject().put("callback_id", callbackId).put("attempt_id", id())
        val original = row("callback", payload, 2)
        val aliasKey = sha256(callbackId + "\n" + retentionCanonical(payload)).take(32)
        AtomicFileFaults.failFileOnce = "retention-callback-body-$aliasKey.bin"
        refuse("gateway_storage_unavailable") { store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(original)))) }
        val pending = reopen().readRequests().getJSONArray("requests").getJSONObject(0)
        assertEquals(original.getString("request_bytes_base64"), pending.getString("request_bytes_base64"))
        assertTrue(reopen().retainedCallbackRequest(callbackId, payload, true))
        assertNull(reopen().readRequestReceipt(original.getString("request_id")))
        refuse("gateway_unresolved_request_prune") { reopen().saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray())) }
    }

}
