package app.cool.mobile.gateway

import android.content.Context
import android.util.AtomicFileFaults
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.*
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

/** Synthetic already-acknowledged historical objects are encrypted and checked
 * by the real cold parser. Their creation is fixture setup, never sender or
 * portable-restore authority. Every late append/page uses the actual store. */
internal class GatewayLateFixture {
    val root = Files.createTempDirectory("collect-late-retention-").toFile()
    val device = "00000000-0000-0000-0000-000000000001"
    val at = "2026-10-01T13:00:00Z"
    val directory = File(root, "collect_gateway_v1")
    private class LocalContext(private val root: File) : Context() { override val noBackupFilesDir get() = root }
    val context: Context = LocalContext(root)
    fun store() = GatewayEncryptedStore(context) { name -> crypto(name) }
    val storage = store()
    fun id() = UUID.randomUUID().toString()
    fun crypto(name: String) = GatewayCrypto(SecretKeySpec(ByteArray(32) { 29 }, "AES"), "CollectGateway/$name/v1")
    fun write(name: String, value: JSONObject) = File(directory, "$name.bin").writeBytes(crypto(name).encrypt(value.toString().toByteArray()))
    fun read(name: String): JSONObject = JSONObject(String(crypto(name).decrypt(File(directory, "$name.bin").readBytes())))
    init {
        write("cold-marker", JSONObject().put("contract_version", 3).put("established", true))
        write("cold-control", JSONObject().put("contract_version", 3).put("stopped", false).put("late_attempt_ids", JSONArray()).put("cold_shards", JSONArray()))
    }
    fun request(action: String, payload: JSONObject, version: Int): JSONObject {
        val id = id();val text = JSONObject().put("contract_version", version).put("action", action).put("device_id", device).put("request_id", id).put("issued_at", at).put("payload", payload).toString()
        return JSONObject().put("request_id", id).put("action", action).put("state", "outcome_unknown").put("callback_id", if (action == "callback") payload.getString("callback_id") else JSONObject.NULL)
            .put("request_sha256", sha256(text)).put("request_bytes_base64", Base64.getEncoder().encodeToString(text.toByteArray()))
    }
    fun seed(parts: Int = 1): GatewayAttempt {
        val a = GatewayAttempt(device, id(), id(), 1, "a".repeat(64), "b".repeat(64), "2026-10-01T13:01:00Z", at, "c".repeat(64),
            List(parts) { SegmentEvidence(id(), id(), SegmentOutcome.FRAMEWORK_SENT, SegmentOutcome.DELIVERY_CALLBACK_OBSERVED, -1, -1, at, at) })
        val rows = JSONArray();val refs = JSONArray()
        for ((i, s) in a.segments.withIndex()) for (kind in CallbackKind.entries) {
            val p = JSONObject().put("callback_id", if (kind == CallbackKind.SENT) s.sentCallbackId else s.deliveryCallbackId).put("attempt_id", a.attemptId)
                .put("fence_version", a.fence).put("segment_index", i).put("segment_count", parts).put("body_sha256", a.bodySha256).put("destination_sha256", a.destinationSha256)
                .put("callback_kind", if (kind == CallbackKind.SENT) "sent" else "delivery").put("result_code", -1).put("tp_status", JSONObject.NULL).put("occurred_at", at)
            val row = request("callback", p, 2);rows.put(row);refs.put(JSONObject().put("callback_id", row.getString("callback_id")).put("request_id", row.getString("request_id")).put("request_sha256", row.getString("request_sha256")))
        }
        val payload = JSONObject().put("attempt_id", a.attemptId).put("fence_version", a.fence).put("body_sha256", a.bodySha256).put("destination_sha256", a.destinationSha256).put("callback_requests", refs)
        val original = request("archive_attempt", payload, 3)
        val ack = JSONObject().put("request_id", original.getString("request_id")).put("device_id", device).put("attempt_id", a.attemptId).put("fence_version", a.fence)
            .put("ok", true).put("code", JSONObject.NULL).put("archive_ack_id", id()).put("receipt_id", a.jobId).put("body_sha256", a.bodySha256).put("destination_sha256", a.destinationSha256)
            .put("segment_count", parts).put("callback_requests", refs).put("recorded_at", at).put("replay", false).put("evidence_kind", "complete_framework_callback_observations")
            .put("carrier_proof", false).put("delivery_proven", false).put("send_authority", false)
        val cold = JSONObject().put("contract_version", 3).put("attempt", archiveAttemptJson(a)).put("archive_request", original).put("acknowledgement", ack).put("callback_requests", rows).put("archived_at", at)
        validateColdAttempt(cold);write("cold-${a.attemptId}", cold)
        assertEquals(a, archiveAttemptFromJson(storage.readColdAttempt(a.attemptId)!!.getJSONObject("attempt")))
        return a
    }
    fun callback(a: GatewayAttempt, code: Int = 1, tick: Int = code, part: Int = 0, kind: CallbackKind = CallbackKind.SENT): GatewayCallback = GatewayCallback(
        if (kind == CallbackKind.SENT) a.segments[part].sentCallbackId else a.segments[part].deliveryCallbackId, device, a.attemptId, a.fence, part, a.callbackNonce, kind, code,
        gatewayWireTime(Instant.parse(at).plusSeconds(tick.toLong() + 1)))
    fun append(a: GatewayAttempt, c: GatewayCallback = callback(a)) { assertTrue(GatewayJournal(storage).record(c)) }
    fun pages(): List<GatewayLateCallbackEvidence> {
        val all = mutableListOf<GatewayLateCallbackEvidence>();var cursor: String? = null
        do { val p = store().coldCallbackPage(cursor, 8);check(!p.migrationPending);all.addAll(p.entries);cursor = p.nextCursor } while (cursor != null)
        return all
    }
    fun dispose() { AtomicFileFaults.failFinishOnce = false;AtomicFileFaults.failFileOnce = null;AtomicFileFaults.failWriteNumberOnce = null;root.deleteRecursively() }
}

class GatewayLateRetentionTest {
    private fun test(action: (GatewayLateFixture) -> Unit) { val f = GatewayLateFixture();try { action(f) } finally { f.dispose() } }
    private fun refuse(action: () -> Unit) { try { action();fail("Expected refusal") } catch (_: GatewayStateException) {} }
    @Test fun continuousConflictsAcross257AttemptsHaveBoundedPagesAndNoLegacyCatalogGrowth() = test { f ->
        val original = f.read("cold-control").getJSONArray("late_attempt_ids").toString();val attempts = List(257) { f.seed() }
        for (a in attempts) f.append(a)
        val all = f.pages();assertEquals(257, all.size);assertEquals(attempts.map { it.attemptId }.toSet(), all.map { it.attempt.attemptId }.toSet())
        assertEquals(original, f.read("cold-control").getJSONArray("late_attempt_ids").toString());assertTrue(f.store().coldStop())
        assertTrue(f.directory.listFiles()!!.filter { it.name.startsWith("retention-index-late-") }.all { it.length() < 16384 })
    }
    @Test fun seventyExactContradictionsOnOneAttemptRetainBodiesAndDeduplicateOnlyExactData() = test { f ->
        val a = f.seed(3);val original = File(f.directory, "cold-${a.attemptId}.bin").readBytes()
        val callbacks = List(70) { f.callback(a, it, it, it % 3) }
        for (c in callbacks) { f.append(a, c);f.append(a, c) }
        assertEquals(callbacks.toSet(), f.pages().map { it.callback }.toSet());assertEquals(70, f.pages().size)
        assertArrayEquals(original, File(f.directory, "cold-${a.attemptId}.bin").readBytes())
        val exported = f.store().exportColdCallbackPage(null, 8);assertEquals(16, exported.encryptedParts.size);assertNotNull(exported.nextCursor)
    }
    @Test fun everyLatePublicationBoundaryKeepsStopAndRepairsOnlyThePendingOriginal() {
        val baseline = GatewayLateFixture();val writes: Int
        try { val a = baseline.seed();val start = AtomicFileFaults.writeCount;baseline.append(a);writes = AtomicFileFaults.writeCount - start } finally { baseline.dispose() }
        assertTrue(writes > 40)
        for (boundary in 1..writes) test { f ->
            val a = f.seed();val c = f.callback(a);AtomicFileFaults.failWriteNumberOnce = AtomicFileFaults.writeCount + boundary
            refuse { f.append(a, c) };AtomicFileFaults.failWriteNumberOnce = null
            // A failing first stop write cannot accept evidence. After any
            // subsequent failure the independent durable stop is still closed.
            if (boundary > 1) assertTrue(f.store().coldStop())
            f.append(a, c);assertEquals(listOf(c), f.pages().map { it.callback });assertTrue(f.store().coldStop())
            assertEquals(0, f.store().readRequests().getJSONArray("requests").length())
        }
    }
    @Test fun fixedCeilingWrapIncludesFreshRawDigestBehindPriorCursorAndCrashAdvancementOnlyDelays() = test { f ->
        val a = f.seed();repeat(18) { f.append(a, f.callback(a, it, it)) }
        val first = f.store().nextColdCallbackPage(8);assertEquals(8, first.entries.size);assertNotNull(first.nextCursor)
        val next = f.store().nextColdCallbackPage(8);assertEquals(8, next.entries.size)
        var fresh = f.callback(a, 100, 100)
        fun digest(c: GatewayCallback) = sha256(retentionCanonical(JSONObject().put("contract_version", 5).put("attempt_id", a.attemptId).put("callback", gatewayLateCallbackJson(c)))).take(32)
        var tick = 101
        while (digest(fresh) >= first.entries.first().evidenceKey) fresh = f.callback(a, 100, tick++)
        f.append(a, fresh)
        val last = f.store().nextColdCallbackPage(8);assertEquals(2, last.entries.size);assertNull(last.nextCursor)
        val visited = mutableSetOf<GatewayCallback>()
        repeat(3) { visited.addAll(f.store().nextColdCallbackPage(8).entries.map { it.callback }) }
        assertEquals(19, visited.size);assertTrue(fresh in visited);assertTrue(first.entries.all { it.callback in visited })
    }
    @Test fun legacyMigrationCopiesFourPerReadRetainsCiphertextAndDoesNotClaimDelivery() = test { f ->
        val a = f.seed();val callbacks = List(7) { f.callback(a, it, it) }
        f.write("cold-late-${a.attemptId}", JSONObject().put("contract_version", 3).put("attempt_id", a.attemptId).put("callbacks", JSONArray(callbacks.map(::gatewayLateCallbackJson))))
        val control = f.read("cold-control").put("stopped", true).put("late_attempt_ids", JSONArray(listOf(a.attemptId)));f.write("cold-control", control)
        val bytes = File(f.directory, "cold-late-${a.attemptId}.bin").readBytes()
        val first = f.store().nextColdCallbackPage(8);assertTrue(first.migrationPending);assertTrue(first.entries.isEmpty())
        assertEquals(4, f.read("late-retention-migration").getInt("callback_position"))
        val second = f.store().nextColdCallbackPage(8);assertFalse(second.migrationPending);assertEquals(7, second.entries.size)
        assertArrayEquals(bytes, File(f.directory, "cold-late-${a.attemptId}.bin").readBytes());assertTrue(f.store().coldStop())
    }
    @Test fun fullLegacyCatalogNeverPreventsNewStopOrExactEvidenceReservation() = test { f ->
        val a = f.seed();val ids = List(256) { f.id() };f.write("cold-control", f.read("cold-control").put("late_attempt_ids", JSONArray(ids)))
        f.append(a);assertTrue(f.store().coldStop());assertEquals(ids, (0 until 256).map { f.read("cold-control").getJSONArray("late_attempt_ids").getString(it) })
        refuse { f.store().nextColdCallbackPage(8) } // absent historical evidence cannot be skipped
        assertTrue(f.directory.list()!!.any { it.startsWith("retention-late-evidence-") })
    }
    @Test fun missingEvidenceWorkNodesControlsAndTamperedObjectsNeverBecomeEmptySuccessfulPages() {
        for (target in listOf("evidence", "work-node", "counter", "pending", "tamper")) test { f ->
            val a = f.seed();f.append(a);val row = f.pages().single()
            val name = when(target) { "evidence", "tamper" -> "retention-late-evidence-${row.evidenceKey}";"work-node" -> "retention-index-late-work-${row.cursorKey.take(2)}";"counter" -> "late-retention-control";else -> "late-retention-pending" }
            val file = File(f.directory, "$name.bin")
            if (target == "tamper") file.writeBytes(file.readBytes().also { it[it.lastIndex] = (it.last().toInt() xor 1).toByte() }) else assertTrue(file.delete())
            refuse { f.store().nextColdCallbackPage(8) };assertTrue(f.store().coldStop())
        }
    }
    @Test fun strictPagesCallbackBindingsAndFullDigestObjectChecksRefuseForgery() = test { f ->
        val a = f.seed();val c = f.callback(a)
        refuse { f.storage.appendColdConflict(a, c.copy(nonce = "d".repeat(64))) }
        refuse { f.storage.appendColdConflict(a, c.copy(deviceId = f.id())) }
        refuse { f.storage.appendColdConflict(a, c.copy(fence = 2)) }
        refuse { f.storage.appendColdConflict(a, c.copy(segmentIndex = 8)) }
        refuse { f.storage.appendColdConflict(a, c.copy(occurredAt = "2026-09-30T13:00:00Z")) }
        for (limit in listOf(0,9)) refuse { f.storage.coldCallbackPage(null, limit) }
        refuse { f.storage.coldCallbackPage("oops", 8) };assertFalse(f.storage.coldStop())
        f.append(a,c);val row=f.pages().single();val name="retention-late-evidence-${row.evidenceKey}"
        val old=f.read(name);old.getJSONObject("callback").put("result_code", 2);f.write(name,old)
        refuse { f.store().coldCallbackPage(null,8) };assertTrue(f.store().coldStop())
    }
}
