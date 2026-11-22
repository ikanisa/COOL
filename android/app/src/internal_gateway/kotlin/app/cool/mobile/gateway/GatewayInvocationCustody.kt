package app.cool.mobile.gateway

import org.json.JSONObject
import java.time.Instant

/** Application invocation provenance. Neither a local abort nor an entered
 * marker revokes backend authority or establishes a carrier outcome. */
internal interface GatewayInvocationStorage {
    fun requireInvocationActive()
    fun invocationRealm(deviceId: String): JSONObject
    fun readInvocationRecord(kind: String, attemptId: String): JSONObject?
    fun invocationRecordIndexed(kind: String, attemptId: String): Boolean
    fun publishInvocationRecord(kind: String, attemptId: String, value: JSONObject)
}

internal class GatewayInvocationCustody(private val storage: GatewayInvocationStorage) {
    companion object {
        const val PREPARE = "invoke-prepare"
        const val TERMINAL = "invoke-terminal"
        private val reasons = setOf("local_pause", "health_changed", "operator_stop", "cycle_stopped", "authority_unavailable")
    }

    private fun binding(record: GatewayAttempt): JSONObject {
        validateAttempt(record)
        val realm = storage.invocationRealm(record.deviceId)
        requireKeys(realm, setOf("installation_id", "key_sha256", "signing_certificate_sha256"))
        requireUuid(realm, "installation_id")
        for (name in listOf("key_sha256", "signing_certificate_sha256"))
            if (!strictString(realm, name).matches(Regex("[0-9a-f]{64}"))) invalidArchive()
        val route = record.dispatchRoute
        val source = when (route) {
            is GatewayDispatchRoute.PrimaryV2 -> Triple("primary_android_v2", record.jobId, JSONObject.NULL)
            is GatewayDispatchRoute.ReceiptSuccessorV1 -> Triple("receipt_successor_v1", route.primaryReceiptId, successorRouteJson(route))
            is GatewayDispatchRoute.ReceiptNoticeV1 -> Triple("receipt_notice_v1", route.primaryReceiptId, noticeRouteJson(route))
        }
        return JSONObject().put("source_family", source.first)
            .put("root_receipt_id", source.second)
            .put("job_id", record.jobId).put("attempt_id", record.attemptId).put("device_id", record.deviceId)
            .put("fence_version", record.fence).put("body_sha256", record.bodySha256).put("destination_sha256", record.destinationSha256)
            .put("reservation_sha256", gatewayReservationDigest(record)).put("realm", JSONObject(realm.toString()))
            .put("dispatch_route", source.third)
    }

    private fun prepared(record: GatewayAttempt): JSONObject? {
        val value = storage.readInvocationRecord(PREPARE, record.attemptId) ?: return null
        requireKeys(value, setOf("contract_version", "phase", "binding", "initial_attempt"))
        if (strictInteger(value, "contract_version") != 1L || strictString(value, "phase") != "prepared") invalidArchive()
        val initial = archiveAttemptFromJson(value.getJSONObject("initial_attempt"))
        if (initial.invocationException || hasCallbacks(initial) || !archiveJsonEqual(value.getJSONObject("binding"), binding(initial)) ||
            !archiveJsonEqual(value.getJSONObject("binding"), binding(record))) throw GatewayStateException("gateway_invocation_custody_conflict")
        return value
    }

    private fun terminal(record: GatewayAttempt, prepare: JSONObject?): JSONObject? {
        val value = storage.readInvocationRecord(TERMINAL, record.attemptId) ?: return null
        if (prepare == null) throw GatewayStateException("gateway_invocation_custody_missing")
        requireKeys(value, setOf("contract_version", "phase", "attempt_id", "prepare_sha256", "recorded_at", "reason_code"))
        val phase = strictString(value, "phase")
        if (strictInteger(value, "contract_version") != 1L || phase !in setOf("invoke_entered", "aborted_uninvoked") ||
            requireUuid(value, "attempt_id") != record.attemptId || strictString(value, "prepare_sha256") != sha256(retentionCanonical(prepare))) invalidArchive()
        val at = strictTimestamp(value, "recorded_at")
        if (at < Instant.parse(record.invocationStartedAt)) invalidArchive()
        if (phase == "invoke_entered") { if (!value.isNull("reason_code")) invalidArchive() }
        else if (strictString(value, "reason_code") !in reasons) invalidArchive()
        return value
    }

    fun prepare(record: GatewayAttempt) = synchronized(GatewayJournal.PROCESS_LOCK) {
        storage.requireInvocationActive()
        if (storage.readInvocationRecord(PREPARE, record.attemptId) != null || storage.readInvocationRecord(TERMINAL, record.attemptId) != null)
            throw GatewayStateException("gateway_invocation_custody_exists")
        if (record.invocationException || hasCallbacks(record)) invalidArchive()
        val value = JSONObject().put("contract_version", 1).put("phase", "prepared").put("binding", binding(record))
            .put("initial_attempt", archiveAttemptJson(record))
        storage.publishInvocationRecord(PREPARE, record.attemptId, value)
        if (!archiveJsonEqual(prepared(record), value) || !storage.invocationRecordIndexed(PREPARE, record.attemptId)) invalidArchive()
    }

    fun enter(record: GatewayAttempt, at: Instant) = synchronized(GatewayJournal.PROCESS_LOCK) {
        storage.requireInvocationActive()
        val prepare = prepared(record) ?: throw GatewayStateException("gateway_invocation_custody_unavailable")
        val previous = terminal(record, prepare)
        if (previous != null) throw GatewayStateException(if (strictString(previous, "phase") == "aborted_uninvoked") "gateway_invocation_aborted" else "gateway_attempt_already_invoked")
        if (record.invocationException || hasCallbacks(record)) throw GatewayStateException("gateway_invocation_custody_conflict")
        if (!storage.invocationRecordIndexed(PREPARE, record.attemptId)) throw GatewayStateException("gateway_invocation_custody_pending")
        val value = phase(record, prepare, "invoke_entered", at, null)
        storage.publishInvocationRecord(TERMINAL, record.attemptId, value)
        requireEntered(record)
    }

    fun requireEntered(record: GatewayAttempt) = synchronized(GatewayJournal.PROCESS_LOCK) {
        storage.requireInvocationActive()
        val prepare = prepared(record) ?: throw GatewayStateException("gateway_invocation_custody_unavailable")
        val result = terminal(record, prepare) ?: throw GatewayStateException("gateway_invocation_custody_unavailable")
        if (strictString(result, "phase") != "invoke_entered") throw GatewayStateException("gateway_invocation_aborted")
        if (!storage.invocationRecordIndexed(PREPARE, record.attemptId) || !storage.invocationRecordIndexed(TERMINAL, record.attemptId))
            throw GatewayStateException("gateway_invocation_custody_pending")
    }

    fun abort(record: GatewayAttempt, reason: String, at: Instant): JSONObject = synchronized(GatewayJournal.PROCESS_LOCK) {
        storage.requireInvocationActive()
        if (reason !in reasons) throw GatewayStateException("gateway_invocation_abort_reason")
        val prepare = prepared(record) ?: throw GatewayStateException("gateway_invocation_custody_unavailable")
        if (hasCallbacks(record)) throw GatewayStateException("gateway_invocation_custody_conflict")
        val previous = terminal(record, prepare)
        if (previous != null) {
            if (strictString(previous, "phase") != "aborted_uninvoked") throw GatewayStateException("gateway_invocation_outcome_unknown")
            if (strictString(previous, "reason_code") != reason) throw GatewayStateException("gateway_invocation_custody_conflict")
            storage.publishInvocationRecord(TERMINAL, record.attemptId, previous) // repair only the original immutable object
            return@synchronized JSONObject(previous.toString())
        }
        if (!storage.invocationRecordIndexed(PREPARE, record.attemptId)) {
            storage.publishInvocationRecord(PREPARE, record.attemptId, prepare) // exact original repair, never a new preparation
            if (!storage.invocationRecordIndexed(PREPARE, record.attemptId)) throw GatewayStateException("gateway_invocation_custody_pending")
        }
        val value = phase(record, prepare, "aborted_uninvoked", at, reason)
        storage.publishInvocationRecord(TERMINAL, record.attemptId, value)
        if (!archiveJsonEqual(terminal(record, prepare), value) || !storage.invocationRecordIndexed(TERMINAL, record.attemptId)) invalidArchive()
        JSONObject(value.toString())
    }

    private fun phase(record: GatewayAttempt, prepare: JSONObject, phase: String, at: Instant, reason: String?) =
        JSONObject().put("contract_version", 1).put("phase", phase).put("attempt_id", record.attemptId)
            .put("prepare_sha256", sha256(retentionCanonical(prepare))).put("recorded_at", at.toString()).put("reason_code", reason ?: JSONObject.NULL)

    fun evidence(record: GatewayAttempt): JSONObject = synchronized(GatewayJournal.PROCESS_LOCK) {
        val prepare = prepared(record)
        val result = terminal(record, prepare)
        JSONObject().put("contract_version", 1).put("attempt_id", record.attemptId)
            .put("prepare", prepare ?: JSONObject.NULL).put("terminal", result ?: JSONObject.NULL)
            .put("prepare_indexed", prepare != null && storage.invocationRecordIndexed(PREPARE, record.attemptId))
            .put("terminal_indexed", result != null && storage.invocationRecordIndexed(TERMINAL, record.attemptId))
            .put("contradictory_callback", hasCallbacks(record) && (result == null && prepare != null || result?.optString("phase") == "aborted_uninvoked"))
            .put("application_seam_provenance_only", true).put("backend_authority_cancelled", false)
            .put("send_authority", false).put("carrier_proof", false).put("delivery_proven", false)
    }

    fun validateCompaction(record: GatewayAttempt) = synchronized(GatewayJournal.PROCESS_LOCK) {
        val prepare = prepared(record)
        val result = terminal(record, prepare)
        if (prepare != null && (result == null || strictString(result, "phase") != "invoke_entered" ||
            !storage.invocationRecordIndexed(PREPARE, record.attemptId) || !storage.invocationRecordIndexed(TERMINAL, record.attemptId)))
            throw GatewayStateException("gateway_invocation_custody_conflict")
    }

    fun validateRecord(attemptId: String): GatewayAttempt = synchronized(GatewayJournal.PROCESS_LOCK) {
        val value = storage.readInvocationRecord(PREPARE, attemptId) ?: throw GatewayStateException("gateway_invocation_custody_missing")
        val initial = archiveAttemptFromJson(value.getJSONObject("initial_attempt"))
        if (initial.attemptId != attemptId) invalidArchive()
        val prepare = prepared(initial) ?: invalidArchive()
        terminal(initial, prepare)
        initial
    }

    private fun hasCallbacks(record: GatewayAttempt) = record.segments.any {
        it.sent != SegmentOutcome.PENDING || it.delivery != SegmentOutcome.PENDING || it.sentCode != null || it.deliveryCode != null ||
            it.sentObservedAt != null || it.deliveryObservedAt != null
    }
}
