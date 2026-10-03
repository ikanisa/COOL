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
        assertEquals(known.toString(), reopened.readArchive().getJSONArray("requests").getJSONObject(0).getJSONObject("request").toString())
        for (name in listOf("archive.bin", "requests.bin")) assertFalse(String(File(directory, name).readBytes()).contains(known.getString("request_id")))
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
        File(directory, "archive.bin").delete()
        reject("gateway_archive_missing") { reopen().readRequests() }
        reject("gateway_archive_missing") { reopen().read() }
    }
    @Test fun ciphertextTamperFailsBeforeReadingOrMutatingJournal() = withStore { store, directory, reopen ->
        val known = row(); store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(known))))
        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(known), reply(known)))
        val file = File(directory, "archive.bin"); file.writeBytes(file.readBytes().also { it[it.lastIndex] = (it.last().toInt() xor 4).toByte() })
        reject("gateway_storage_unavailable") { reopen().readRequests() }
        reject("gateway_storage_unavailable") { GatewayJournal(reopen()).pause() }
    }
    @Test fun removedOrChangedArchiveRowsAreRejectedWithoutChangingCiphertext() = withStore { store, directory, _ ->
        val known = row(); store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(listOf(known))))
        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(known), reply(known)))
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
        val before = File(directory, "archive.bin").readBytes(); AtomicFileFaults.failFinishOnce = true
        reject("gateway_storage_unavailable") { GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(second), reply(second))) }
        assertArrayEquals(before, File(directory, "archive.bin").readBytes())
        assertEquals(second.getString("request_id"), reopen().readRequests().getJSONArray("requests").getJSONObject(0).getString("request_id"))
        assertFalse(File(directory, "archive.bin.new").exists())
    }
    @Test fun activeCapacityCanBeFreedWithoutDiscardingAnyUnknownRequest() = withStore { store, _, reopen ->
        val rows = (0 until GatewayEncryptedStore.MAX_REQUESTS).map { row() }
        store.saveRequests(JSONObject().put("contract_version", 1).put("requests", JSONArray(rows)))
        GatewayJournalArchive(store).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(rows.first()), reply(rows.first())))
        val active = reopen().readRequests(); assertEquals(63, active.getJSONArray("requests").length())
        active.getJSONArray("requests").put(row()); store.saveRequests(active)
        assertEquals(64, reopen().readRequests().getJSONArray("requests").length()); assertEquals(1, reopen().readArchive().getJSONArray("requests").length())
    }
}
