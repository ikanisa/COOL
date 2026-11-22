package app.cool.mobile.gateway

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.util.Base64
import java.util.UUID
import javax.crypto.spec.SecretKeySpec

class GatewayJournalArchiveTest {
    private val now = Instant.parse("2026-10-01T13:00:00Z")
    private val device = "00000000-0000-0000-0000-000000000001"
    private fun id(): String = UUID.randomUUID().toString()
    private fun request(action: String = "heartbeat", payload: JSONObject = JSONObject(), requestId: String = id()): JSONObject {
        val envelope = JSONObject().put("contract_version", 1).put("action", action).put("device_id", device)
            .put("request_id", requestId).put("issued_at", now.toString()).put("payload", payload)
        val text = envelope.toString()
        return JSONObject().put("request_id", requestId).put("action", action).put("state", "outcome_unknown")
            .put("callback_id", if (action == "callback") payload.getString("callback_id") else JSONObject.NULL)
            .put("request_sha256", sha256(text)).put("request_bytes_base64", Base64.getEncoder().encodeToString(text.toByteArray()))
    }
    private fun result(request: JSONObject): JSONObject = when (request.getString("action")) {
        "heartbeat" -> JSONObject().put("observation_id", id()).put("ingested_at", now.toString()).put("replay", false).put("carrier_proof", false)
        "callback" -> JSONObject().put("callback_id", request.getString("callback_id")).put("recorded_at", now.toString()).put("replay", false).put("carrier_proof", false)
        else -> JSONObject().put("ok", false).put("code", "GATEWAY_DISPATCH_AUTHORITY_PENDING").put("device_id", device)
            .put("request_id", request.getString("request_id")).put("replay", false)
    }
    private fun reply(request: JSONObject, result: JSONObject = result(request)): JSONObject = JSONObject().put("contract_version", 1)
        .put("action", request.getString("action")).put("device_id", device).put("request_id", request.getString("request_id")).put("result", result)
    private fun reconciled(request: JSONObject, recorded: Boolean): JSONObject = JSONObject().put("contract_version", 1).put("action", "reconcile")
        .put("device_id", device).put("request_id", id()).put("result", JSONObject().put("target_request_id", request.getString("request_id"))
            .put("outcome", if (recorded) "recorded" else "unknown").put("recorded_action", if (recorded) request.getString("action") else JSONObject.NULL)
            .put("recorded_result", if (recorded) result(request) else JSONObject.NULL))
    private fun reject(reason: String? = null, block: () -> Unit) {
        try { block(); fail("Expected refusal") } catch (failure: GatewayStateException) {
            if (reason != null) assertEquals(reason, failure.reasonCode)
        }
    }
    private class Memory(rows: List<JSONObject>) : GatewayArchiveStorage {
        var active = JSONObject().put("contract_version", 1).put("requests", JSONArray(rows))
        var archive = GatewayJournalArchive.empty()
        var state = GatewayJournalState()
        var failArchive = false
        var failPrune = false
        val order = mutableListOf<String>()
        override fun readRequests() = JSONObject(active.toString())
        override fun saveRequests(value: JSONObject) { order.add("prune"); if (failPrune) throw GatewayStateException("synthetic_prune_failure"); active = JSONObject(value.toString()) }
        override fun readArchive() = JSONObject(archive.toString())
        override fun commitArchive(value: JSONObject) { order.add("archive"); if (failArchive) throw GatewayStateException("synthetic_archive_failure"); archive = JSONObject(value.toString()) }
        override fun read() = state
        override fun commit(state: GatewayJournalState) { this.state = state }
        override fun hasArchivedAttempt(attemptId: String): Boolean = archive.getJSONArray("attempts").let { rows ->
            (0 until rows.length()).any { rows.getJSONObject(it).getJSONObject("attempt").getString("attempt_id") == attemptId }
        }
    }
    @Test fun acknowledgementCommitsArchiveBeforeFreeingOnlyAcknowledgedRequest() {
        val known = request(); val unknown = request(); val storage = Memory(listOf(known, unknown))
        GatewayJournalArchive(storage) { now }.acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(known), reply(known)))
        assertEquals(listOf("archive", "prune"), storage.order)
        assertEquals(known.getString("request_sha256"), storage.archive.getJSONArray("requests").getJSONObject(0).getJSONObject("request").getString("request_sha256"))
        assertEquals(unknown.getString("request_id"), storage.active.getJSONArray("requests").getJSONObject(0).getString("request_id"))
    }
    @Test fun legacyRecordedFlagAloneCannotCompact() {
        val legacy = request().put("state", "recorded"); val storage = Memory(listOf(legacy))
        GatewayJournalArchive(storage).compactAcknowledgedRequests()
        assertEquals(1, storage.active.getJSONArray("requests").length()); assertTrue(storage.order.isEmpty())
    }
    @Test fun archiveFailureLeavesEveryActiveIdentityAndBody() {
        val row = request(); val storage = Memory(listOf(row)); storage.failArchive = true
        reject("synthetic_archive_failure") { GatewayJournalArchive(storage).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row))) }
        assertEquals(row.toString(), storage.active.getJSONArray("requests").getJSONObject(0).toString())
        assertEquals(listOf("archive"), storage.order)
    }
    @Test fun interruptedPruningRecoversFromDurableArchiveWithoutNetworkReplay() {
        val row = request(); val storage = Memory(listOf(row)); storage.failPrune = true
        val ack = GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row))
        reject("synthetic_prune_failure") { GatewayJournalArchive(storage).acknowledge(ack) }
        assertEquals(1, storage.archive.getJSONArray("requests").length())
        storage.failPrune = false; GatewayJournalArchive(storage).compactAcknowledgedRequests()
        assertEquals(0, storage.active.getJSONArray("requests").length()); assertEquals(1, storage.archive.getJSONArray("requests").length())
    }
    @Test fun unknownReconciliationNeverAllowsArchival() {
        val row = request(); val read = reconciled(row, false)
        reject("gateway_archive_acknowledgement_pending") { GatewayArchiveAcknowledgement.reconciled(GatewayStoredRequest.parse(row), read.getString("request_id"), read) }
    }
    @Test fun durableReconciliationCanArchiveTheOriginalRequest() {
        val row = request(); val storage = Memory(listOf(row)); val read = reconciled(row, true)
        GatewayJournalArchive(storage).acknowledge(GatewayArchiveAcknowledgement.reconciled(GatewayStoredRequest.parse(row), read.getString("request_id"), read))
        assertEquals(0, storage.active.getJSONArray("requests").length())
        assertEquals(row.getString("request_id"), storage.archive.getJSONArray("requests").getJSONObject(0).getJSONObject("request").getString("request_id"))
    }
    @Test fun mismatchedDeviceRequestOrActionAcknowledgementsAreRejected() {
        val row = request()
        for (field in listOf("device_id", "request_id", "action")) {
            val bad = reply(row).put(field, if (field == "action") "callback" else id())
            reject { GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), bad) }
        }
    }
    @Test fun malformedOrPrivateResultCannotAuthorizeCompaction() {
        val row = request()
        for (bad in listOf(result(row).put("carrier_proof", true), result(row).put("body", "private"), result(row).put("replay", "false"))) {
            reject { GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row, bad)) }
        }
    }
    @Test fun sameRequestChangedBodyDigestFailsBeforeArchiveOrPrune() {
        val original = request(); val changed = request(requestId = original.getString("request_id"), payload = JSONObject().put("changed", true))
        val storage = Memory(listOf(changed))
        reject("gateway_archive_source_conflict") { GatewayJournalArchive(storage).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(original), reply(original))) }
        assertTrue(storage.order.isEmpty())
    }
    @Test fun duplicateAcknowledgementPreservesFirstReceiptAndIdentity() {
        val row = request(); val storage = Memory(listOf(row)); val journal = GatewayJournalArchive(storage) { now }
        val first = result(row); val ack = GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row, first))
        journal.acknowledge(ack); val archive = storage.archive.toString()
        journal.acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row, JSONObject(first.toString()).put("replay", true))))
        assertEquals(archive, storage.archive.toString()); assertEquals(1, storage.archive.getJSONArray("requests").length())
    }
    @Test fun conflictingSecondServerReceiptIsRefused() {
        val row = request(); val storage = Memory(listOf(row)); val journal = GatewayJournalArchive(storage)
        journal.acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row)))
        reject { journal.acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row))) }
    }
    @Test fun refusalReceiptDoesNotCreateSendAuthority() {
        val row = request("dispatch_grant"); val storage = Memory(listOf(row))
        GatewayJournalArchive(storage).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row)))
        assertFalse(storage.archive.getJSONArray("requests").getJSONObject(0).getJSONObject("result").getBoolean("ok"))
        assertEquals(0, storage.active.getJSONArray("requests").length())
    }
    @Test fun archiveCapacityNeverEvictsOldEvidence() {
        val rows = (0 until GatewayJournalArchive.MAX_REQUESTS).map { request("dispatch_grant") }
        val storage = Memory(rows.take(1)); val journal = GatewayJournalArchive(storage) { now }
        for (row in rows) { storage.active.put("requests", JSONArray(listOf(row))); journal.acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row))) }
        val before = storage.archive.toString(); val extra = request(); storage.active.put("requests", JSONArray(listOf(extra)))
        reject("gateway_archive_limit") { journal.acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(extra), reply(extra))) }
        assertEquals(before, storage.archive.toString()); assertEquals(1, storage.active.getJSONArray("requests").length())
    }
    @Test fun byteCapacityFailureRetainsOriginalRequest() {
        val row = request(payload = JSONObject().put("bounded", "x".repeat(6 * 1024)))
        val storage = Memory(listOf(row)); val rows = storage.archive.getJSONArray("requests")
        while (true) {
            val index = rows.length()
            val other = request(payload = JSONObject().put("bounded", "x".repeat(6 * 1024)))
            rows.put(JSONObject().put("request", other).put("result", result(other)).put("evidence", reply(other)).put("acknowledged_at", now.toString()))
            // Ensure the duplicated synthetic receipt result has identical IDs.
            rows.getJSONObject(index).put("evidence", reply(other, rows.getJSONObject(index).getJSONObject("result")))
            if (storage.archive.toString().toByteArray().size > GatewayCrypto.MAX_BYTES) { rows.remove(index); break }
        }
        validatedArchive(storage.archive)
        reject("gateway_archive_limit") { GatewayJournalArchive(storage).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row))) }
        assertEquals(1, storage.active.getJSONArray("requests").length())
    }
    private fun attempt(known: Boolean): GatewayAttempt = GatewayAttempt(device, id(), id(), 1, "a".repeat(64), "b".repeat(64), now.plusSeconds(60).toString(),
        now.toString(), "c".repeat(64), listOf(if (known) SegmentEvidence(sent = SegmentOutcome.FRAMEWORK_SENT, delivery = SegmentOutcome.DELIVERY_CALLBACK_OBSERVED,
            sentCode = -1, deliveryCode = -1, sentObservedAt = now.toString(), deliveryObservedAt = now.toString()) else SegmentEvidence()))
    private fun callbackRequest(attempt: GatewayAttempt, kind: CallbackKind): JSONObject {
        val segment = attempt.segments.single()
        return request("callback", JSONObject().put("callback_id", if (kind == CallbackKind.SENT) segment.sentCallbackId else segment.deliveryCallbackId)
            .put("attempt_id", attempt.attemptId).put("fence_version", attempt.fence).put("segment_index", 0).put("segment_count", 1)
            .put("body_sha256", attempt.bodySha256).put("destination_sha256", attempt.destinationSha256).put("callback_kind", if (kind == CallbackKind.SENT) "sent" else "delivery")
            .put("result_code", -1).put("tp_status", JSONObject.NULL).put("occurred_at", now.toString()))
    }
    @Test fun callbackReceiptsRemainActiveForExistingDuplicateAndLateEvidenceChecks() {
        val attempt = attempt(true); val row = callbackRequest(attempt, CallbackKind.SENT); val storage = Memory(listOf(row))
        GatewayJournalArchive(storage).acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row)))
        assertEquals(1, storage.active.getJSONArray("requests").length()); assertEquals(1, storage.archive.getJSONArray("requests").length())
    }
    @Test fun unknownAndInvocationExceptionAttemptsNeverArchive() {
        val unknown = attempt(false); val knownException = attempt(true).copy(invocationException = true)
        for (attempt in listOf(unknown, knownException)) {
            val storage = Memory(emptyList()); storage.state = GatewayJournalState(attempts = listOf(attempt))
            reject("gateway_archive_attempt_unresolved") { GatewayJournalArchive(storage).archiveAcknowledgedAttempt(attempt.attemptId) }
            assertEquals(1, storage.state.attempts.size); assertEquals(0, storage.archive.getJSONArray("attempts").length())
        }
    }
    @Test fun localDeliveryCallbacksWithoutServerReceiptsNeverArchive() {
        val attempt = attempt(true); val storage = Memory(emptyList()); storage.state = GatewayJournalState(attempts = listOf(attempt))
        reject("gateway_archive_acknowledgement_pending") { GatewayJournalArchive(storage).archiveAcknowledgedAttempt(attempt.attemptId) }
        assertEquals(attempt, storage.state.attempts.single())
    }
    @Test fun fullyAcknowledgedAttemptArchiveKeepsOriginalActiveReservation() {
        val attempt = attempt(true); val rows = CallbackKind.entries.map { callbackRequest(attempt, it) }; val storage = Memory(rows)
        storage.state = GatewayJournalState(attempts = listOf(attempt)); val journal = GatewayJournalArchive(storage) { now }
        for (row in rows) journal.acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row)))
        journal.archiveAcknowledgedAttempt(attempt.attemptId)
        assertEquals(attempt, storage.state.attempts.single())
        assertEquals(attempt, archiveAttemptFromJson(storage.archive.getJSONArray("attempts").getJSONObject(0).getJSONObject("attempt")))
        reject("gateway_attempt_archive_authority_pending") { journal.compactAttempt(attempt.attemptId) }
    }
    @Test fun acknowledgedCallbackForWrongAttemptOrFenceCannotArchiveAttempt() {
        val attempt = attempt(true); val rows = CallbackKind.entries.map { kind ->
            val row = callbackRequest(attempt.copy(fence = 2), kind); row
        }; val storage = Memory(rows); storage.state = GatewayJournalState(attempts = listOf(attempt)); val journal = GatewayJournalArchive(storage)
        rows.forEach { journal.acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(it), reply(it))) }
        reject("gateway_archive_source_conflict") { journal.archiveAcknowledgedAttempt(attempt.attemptId) }
    }
    @Test fun archivedAttemptIdentityCannotBeReservedAgainEvenWithoutActiveCopy() {
        val attempt = attempt(true); val storage = Memory(CallbackKind.entries.map { callbackRequest(attempt, it) }); storage.state = GatewayJournalState(attempts = listOf(attempt))
        val journal = GatewayJournalArchive(storage); val requests = storage.active.getJSONArray("requests")
        for (index in 0 until requests.length()) { val row = requests.getJSONObject(index); journal.acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row))) }
        journal.archiveAcknowledgedAttempt(attempt.attemptId); storage.state = GatewayJournalState(emergencyPaused = false)
        reject("gateway_attempt_already_invoked") { GatewayJournal(storage).reserveInvocation(attempt.copy(segments = listOf(SegmentEvidence()))) }
    }
    @Test fun malformedArchiveOrDigestIsNeverAnEmptySuccessfulRead() {
        reject { validatedArchive(GatewayJournalArchive.empty().put("unexpected", true)) }
        val row = request().put("request_sha256", "a".repeat(64))
        reject { GatewayStoredRequest.parse(row) }
    }
    @Test fun encryptedArchiveTamperAndWrongFileContextFailClosed() {
        val key = SecretKeySpec(ByteArray(32) { 7 }, "AES"); val crypto = GatewayCrypto(key, "CollectGateway/archive/v1")
        val bytes = crypto.encrypt(GatewayJournalArchive.empty().toString().toByteArray())
        reject { crypto.decrypt(bytes.clone().also { it[it.lastIndex] = (it.last().toInt() xor 1).toByte() }) }
        reject { GatewayCrypto(key, "CollectGateway/requests/v1").decrypt(bytes) }
    }
    @Test fun concurrentAcknowledgementsDoNotLoseEitherReceipt() {
        val rows = listOf(request(), request()); val storage = Memory(rows); val journal = GatewayJournalArchive(storage)
        val threads = rows.map { row -> Thread { journal.acknowledge(GatewayArchiveAcknowledgement.direct(GatewayStoredRequest.parse(row), reply(row))) }.also { it.start() } }
        threads.forEach { it.join() }
        assertEquals(2, storage.archive.getJSONArray("requests").length()); assertEquals(0, storage.active.getJSONArray("requests").length())
    }
}
