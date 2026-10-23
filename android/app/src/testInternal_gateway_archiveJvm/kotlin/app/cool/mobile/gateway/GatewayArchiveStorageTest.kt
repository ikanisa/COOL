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

/** Dedicated offline runner supplies narrow Android filesystem API shims.
 * These tests execute the actual encrypted store, AES-GCM and archive classes;
 * Android Keystore/filesystem/power-loss acceptance remains a device gate. */
class GatewayArchiveStorageTest {
    private val time = "2026-10-01T13:00:00Z"
    private val device = "00000000-0000-0000-0000-000000000001"
    private fun row(): JSONObject {
        val id = UUID.randomUUID().toString()
        val body = JSONObject().put("contract_version", 1).put("action", "heartbeat").put("device_id", device)
            .put("request_id", id).put("issued_at", time).put("payload", JSONObject()).toString()
        return JSONObject().put("request_id", id).put("action", "heartbeat").put("state", "outcome_unknown").put("callback_id", JSONObject.NULL)
            .put("request_sha256", sha256(body)).put("request_bytes_base64", Base64.getEncoder().encodeToString(body.toByteArray()))
    }
    private fun reply(row: JSONObject): JSONObject = JSONObject().put("contract_version", 1).put("action", "heartbeat").put("device_id", device)
        .put("request_id", row.getString("request_id")).put("result", JSONObject().put("observation_id", UUID.randomUUID().toString())
            .put("ingested_at", time).put("replay", false).put("carrier_proof", false))
    private fun reject(reason: String? = null, block: () -> Unit) {
        try { block(); fail("Expected refusal") } catch (failure: GatewayStateException) { if (reason != null) assertEquals(reason, failure.reasonCode) }
    }
    private class TestContext(private val directory: File) : Context() { override val noBackupFilesDir: File get() = directory }
    private fun withStore(test: (GatewayEncryptedStore, File, () -> GatewayEncryptedStore) -> Unit) {
        val root = Files.createTempDirectory("collect-gateway-archive-test-").toFile()
        val key = SecretKeySpec(ByteArray(32) { 17 }, "AES")
        val create = { GatewayEncryptedStore(TestContext(root)) { name -> GatewayCrypto(key, "CollectGateway/$name/v1") } }
        try { test(create(), File(root, "collect_gateway_v1"), create) }
        finally { AtomicFileFaults.failFinishOnce = false; root.deleteRecursively() }
    }
    @Test fun encryptedArchiveSurvivesReopenWithExactOriginalBodyAndReceipt() = withStore { store, directory, reopen ->
        val known = row(); val unknown = row()
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(known, unknown))))
        GatewayJournalArchive(store) { Instant.parse(time) }.acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(known), reply(known)))
        val reopened = reopen(); assertEquals(unknown.getString("request_id"), reopened.readRequests().getJSONArray("requests").getJSONObject(0).getString("request_id"))
        assertEquals(known.toString(), reopened.readRequestReceipt(known.getString("request_id"))!!.getJSONObject("request").toString())
        for (name in listOf("retention-receipt-${retentionUuidKey(known.getString("request_id"))}.bin", "requests.bin")) assertFalse(String(File(directory, name).readBytes()).contains(known.getString("request_id")))
    }
    @Test fun archiveFirstRecoveryFiltersOldActiveFileOnlyAfterExactDigestComparison() = withStore { store, directory, reopen ->
        val known = row(); val unknown = row()
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(known, unknown))))
        val before = File(directory, "requests.bin").readBytes()
        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(known), reply(known)))
        // Reproduce a crash after archive commit, before active-file pruning.
        File(directory, "requests.bin").writeBytes(before)
        assertEquals(unknown.getString("request_id"), reopen().readRequests().getJSONArray("requests").getJSONObject(0).getString("request_id"))
    }
    @Test fun archiveMarkerWithoutDataNeverBecomesAnEmptyArchive() = withStore { store, directory, reopen ->
        val known = row(); store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(known))))
        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(known), reply(known)))
        File(directory, "retention-receipt-${retentionUuidKey(known.getString("request_id"))}.bin").delete()
        reject("gateway_retention_missing") { reopen().readRequestReceipt(known.getString("request_id")) }
        reject("gateway_retention_missing") { reopen().saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(known)))) }
    }
    @Test fun ciphertextTamperFailsBeforeReadingOrMutatingJournal() = withStore { store, directory, reopen ->
        val known = row(); store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(known))))
        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(known), reply(known)))
        val file = File(directory, "retention-receipt-${retentionUuidKey(known.getString("request_id"))}.bin"); file.writeBytes(file.readBytes().also { it[it.lastIndex] = (it.last().toInt() xor 4).toByte() })
        reject("gateway_storage_unavailable") { reopen().readRequestReceipt(known.getString("request_id")) }
        reject("gateway_storage_unavailable") { reopen().saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(known)))) }
    }
    @Test fun removedOrChangedLegacyArchiveRowsAreRejectedWithoutChangingCiphertext() = withStore { store, directory, _ ->
        val known = row()
        val entry = JSONObject().put("request", known).put("result", reply(known).getJSONObject("result")).put("evidence", reply(known)).put("acknowledged_at", time)
        // Use the same authenticated result in receipt and evidence.
        entry.put("result", entry.getJSONObject("evidence").getJSONObject("result"))
        store.commitArchive(GatewayJournalArchive.empty().put("requests", JSONArray(listOf(entry))))
        val before = File(directory, "archive.bin").readBytes()
        reject("gateway_archive_immutable") { store.commitArchive(GatewayJournalArchive.empty()) }
        val changed = store.readArchive(); changed.getJSONArray("requests").getJSONObject(0).put("acknowledged_at", "2026-10-01T13:00:01Z")
        reject("gateway_archive_immutable") { store.commitArchive(changed) }
        assertArrayEquals(before, File(directory, "archive.bin").readBytes())
    }
    @Test fun compactedRequestUuidCannotBeReintroducedAsANewNetworkIntent() = withStore { store, _, _ ->
        val known = row(); store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(known))))
        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(known), reply(known)))
        reject("gateway_request_already_archived") { store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(known)))) }
        assertEquals(0, store.readRequests().getJSONArray("requests").length())
    }
    @Test fun fsyncedAtomicWriteFailureLeavesUnknownRequestAndDurablePriorArchive() = withStore { store, directory, reopen ->
        val first = row(); store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(first))))
        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(first), reply(first)))
        val second = row(); store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(second))))
        val priorFile = File(directory, "retention-receipt-${retentionUuidKey(first.getString("request_id"))}.bin")
        val before = priorFile.readBytes(); AtomicFileFaults.failFinishOnce = true
        reject("gateway_storage_unavailable") { GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(second), reply(second))) }
        assertArrayEquals(before, priorFile.readBytes())
        assertEquals(second.getString("request_id"), reopen().readRequests().getJSONArray("requests").getJSONObject(0).getString("request_id"))
        assertFalse(File(directory, "archive.bin.new").exists())
    }
    @Test fun activeCapacityCanBeFreedWithoutDiscardingAnyUnknownRequest() = withStore { store, _, reopen ->
        val rows = (0 until GatewayEncryptedStore.MAX_REQUESTS).map { row() }
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(rows)))
        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(rows.first()), reply(rows.first())))
        val active = reopen().readRequests(); assertEquals(63, active.getJSONArray("requests").length())
        active.getJSONArray("requests").put(row()); store.saveRequests(active)
        assertEquals(64, reopen().readRequests().getJSONArray("requests").length()); assertNotNull(reopen().readRequestReceipt(rows.first().getString("request_id")))
    }
    private fun rebody(original: JSONObject, action: String, payload: JSONObject, version: Int = 1): JSONObject {
        val id = original.getString("request_id")
        val text = JSONObject().put("contract_version", version).put("action", action).put("device_id", device).put("request_id", id)
            .put("issued_at", time).put("payload", payload).toString()
        return JSONObject().put("request_id", id).put("action", action).put("state", "outcome_unknown")
            .put("callback_id", if (action == "callback") payload.getString("callback_id") else JSONObject.NULL)
            .put("request_sha256", sha256(text)).put("request_bytes_base64", Base64.getEncoder().encodeToString(text.toByteArray()))
    }
    @Test fun acknowledgedUuidCannotSwitchActionAndUnresolvedUuidCannotSwitchAttempt() = withStore { store, _, _ ->
        val known = row();store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(known))))
        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(known), reply(known)))
        val changedAction = rebody(known, "arm_dispatch", JSONObject().put("attempt_id", UUID.randomUUID().toString()), 2)
        reject("gateway_archive_source_conflict") { store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(changedAction)))) }
        val original = rebody(row(), "arm_dispatch", JSONObject().put("attempt_id", UUID.randomUUID().toString()), 2)
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(original))))
        val changedAttempt = rebody(original, "arm_dispatch", JSONObject().put("attempt_id", UUID.randomUUID().toString()), 2)
        reject("gateway_archive_source_conflict") { store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(changedAttempt)))) }
    }
    @Test fun hotPublicationAndOriginalAliasCrashesRecoverOnlyExactPendingBodies() = withStore { store, directory, reopen ->
        for (boundary in listOf("retention-request", "retention-index-request", "requests.bin")) {
            val request = row();val id = request.getString("request_id");val key = retentionUuidKey(id)
            AtomicFileFaults.failFileOnce = when (boundary) { "retention-request" -> "retention-request-$key.bin";"retention-index-request" -> "retention-index-request-$key.bin";else -> boundary }
            reject("gateway_storage_unavailable") { store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(request)))) }
            val restored = reopen().readRequests().getJSONArray("requests").getJSONObject(0)
            assertEquals(id, restored.getString("request_id"));assertEquals(request.getString("request_bytes_base64"), restored.getString("request_bytes_base64"))
            assertNotNull(reopen().readRetainedRequest(id))
            GatewayJournalArchive(reopen()).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(restored), reply(restored)))
            store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray()))
        }
        assertFalse(directory.list()!!.any { it.endsWith(".new") })
    }
    @Test fun missingIndexedOriginalReceiptAndChildNeverBecomeUnusedIdentity() = withStore { store, directory, reopen ->
        val request = row();val id = request.getString("request_id");val key = retentionUuidKey(id)
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(request))))
        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(request), reply(request)))
        val original = File(directory, "retention-request-$key.bin");val bytes = original.readBytes();original.delete()
        reject("gateway_retention_missing") { reopen().readRetainedRequest(id) };original.writeBytes(bytes)
        val child = File(directory, "retention-index-request-${key.take(2)}.bin");val node = child.readBytes();child.delete()
        reject("gateway_retention_missing") { reopen().readRetainedRequest(id) };child.writeBytes(node)
        File(directory, "retention-receipt-$key.bin").delete()
        reject("gateway_retention_missing") { reopen().saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(request)))) }
    }
    @Test fun boundedLegacyMigrationPreservesCiphertextAndClosesNewAdmissionUntilCopied() = withStore { store, directory, reopen ->
        val requests = (0 until 9).map { row() };val entries = requests.map { request ->
            val evidence = reply(request)
            JSONObject().put("request", request).put("result", evidence.getJSONObject("result")).put("evidence", evidence).put("acknowledged_at", time)
        }
        store.commitArchive(GatewayJournalArchive.empty().put("requests", JSONArray(entries)))
        val legacy = File(directory, "archive.bin").readBytes()
        val fresh = row()
        reject("gateway_retention_migration_pending") { store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(fresh)))) }
        assertEquals(4, requests.count { store.readRequestReceipt(it.getString("request_id")) != null })
        reject("gateway_retention_migration_pending") { reopen().saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(fresh)))) }
        assertEquals(8, requests.count { store.readRequestReceipt(it.getString("request_id")) != null })
        reopen().saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(fresh))))
        assertEquals(9, requests.count { store.readRequestReceipt(it.getString("request_id")) != null })
        assertArrayEquals(legacy, File(directory, "archive.bin").readBytes())
    }

}
