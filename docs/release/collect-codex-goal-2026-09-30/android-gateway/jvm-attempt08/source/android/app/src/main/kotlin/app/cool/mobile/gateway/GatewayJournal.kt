package app.cool.mobile.gateway

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

/** Pure state machine. An invocation reservation is durable before the sender
 * seam is called. No transition authorizes a second invocation of an attempt. */
internal enum class SegmentOutcome { PENDING, FRAMEWORK_SENT, DELIVERY_CALLBACK_OBSERVED, UNKNOWN }
internal enum class CallbackKind { SENT, DELIVERY }
internal enum class AttemptOutcome { OUTCOME_UNKNOWN, FRAMEWORK_SENT, DELIVERY_CALLBACK_OBSERVED }

internal data class SegmentEvidence(
    val sentCallbackId: String = UUID.randomUUID().toString(),
    val deliveryCallbackId: String = UUID.randomUUID().toString(),
    val sent: SegmentOutcome = SegmentOutcome.PENDING,
    val delivery: SegmentOutcome = SegmentOutcome.PENDING,
    val sentCode: Int? = null,
    val deliveryCode: Int? = null,
    val sentObservedAt: String? = null,
    val deliveryObservedAt: String? = null,
)

internal data class GatewayAttempt(
    val deviceId: String,
    val jobId: String,
    val attemptId: String,
    val fence: Long,
    val bodySha256: String,
    val destinationSha256: String,
    val grantExpiresAt: String,
    val invocationStartedAt: String,
    val callbackNonce: String,
    val segments: List<SegmentEvidence>,
    val invocationException: Boolean = false,
) {
    fun outcome(): AttemptOutcome {
        if (invocationException || segments.any { it.sent != SegmentOutcome.FRAMEWORK_SENT }) {
            return AttemptOutcome.OUTCOME_UNKNOWN
        }
        if (segments.all { it.delivery == SegmentOutcome.DELIVERY_CALLBACK_OBSERVED }) {
            return AttemptOutcome.DELIVERY_CALLBACK_OBSERVED
        }
        return AttemptOutcome.FRAMEWORK_SENT
    }
}

internal data class GatewayJournalState(
    val emergencyPaused: Boolean = true,
    val attempts: List<GatewayAttempt> = emptyList(),
)

internal interface GatewayJournalStorage {
    /** Read failure/corruption is an error, never an empty successful journal. */
    fun read(): GatewayJournalState
    /** Must commit encrypted data and synchronously fsync before returning. */
    fun commit(state: GatewayJournalState)
}

internal data class GatewayCallback(
    val callbackId: String,
    val deviceId: String,
    val attemptId: String,
    val fence: Long,
    val segmentIndex: Int,
    val nonce: String,
    val kind: CallbackKind,
    val resultCode: Int,
    val occurredAt: String,
)

internal class GatewayStateException(val reasonCode: String) : IllegalStateException(reasonCode)

internal class GatewayJournal(private val storage: GatewayJournalStorage) {
    companion object {
        const val MAX_ATTEMPTS = 100
        const val MAX_SEGMENTS = 10
        // Shared within the process, including manifest receiver instances.
        val PROCESS_LOCK = Any()
    }

    fun read(): GatewayJournalState = synchronized(PROCESS_LOCK) { validated(storage.read()) }

    fun pause() = synchronized(PROCESS_LOCK) {
        storage.commit(validated(storage.read()).copy(emergencyPaused = true))
    }

    fun resume() = synchronized(PROCESS_LOCK) {
        // Resumption only opens the local gate. Fresh server authority and
        // independent device observations are still required for every call.
        storage.commit(validated(storage.read()).copy(emergencyPaused = false))
    }

    fun reserveInvocation(attempt: GatewayAttempt) = synchronized(PROCESS_LOCK) {
        validateAttempt(attempt)
        val state = validated(storage.read())
        if (state.emergencyPaused) throw GatewayStateException("gateway_emergency_paused")
        if (state.attempts.any { it.attemptId == attempt.attemptId }) {
            throw GatewayStateException("gateway_attempt_already_invoked")
        }
        if (state.attempts.size >= MAX_ATTEMPTS) throw GatewayStateException("gateway_journal_limit")
        if (attempt.segments.any { it.sent != SegmentOutcome.PENDING || it.delivery != SegmentOutcome.PENDING ||
                it.sentCode != null || it.deliveryCode != null || it.sentObservedAt != null || it.deliveryObservedAt != null } || attempt.invocationException) {
            throw GatewayStateException("gateway_invocation_invalid")
        }
        // The caller cannot cross the sender seam until this commit succeeds.
        storage.commit(state.copy(attempts = state.attempts + attempt))
    }

    fun markInvocationUnknown(attemptId: String) = synchronized(PROCESS_LOCK) {
        val state = validated(storage.read())
        if (state.attempts.none { it.attemptId == attemptId }) throw GatewayStateException("gateway_attempt_missing")
        storage.commit(state.copy(attempts = state.attempts.map {
            if (it.attemptId == attemptId) it.copy(invocationException = true) else it
        }))
    }

    fun record(callback: GatewayCallback): Boolean = synchronized(PROCESS_LOCK) {
        val state = validated(storage.read())
        val index = state.attempts.indexOfFirst { it.attemptId == callback.attemptId }
        if (index < 0) return@synchronized false
        val attempt = state.attempts[index]
        if (callback.deviceId != attempt.deviceId || callback.fence != attempt.fence ||
            callback.segmentIndex !in attempt.segments.indices || !sameNonce(callback.nonce, attempt.callbackNonce)) {
            return@synchronized false
        }
        val previous = attempt.segments[callback.segmentIndex]
        val sent = callback.kind == CallbackKind.SENT
        if (callback.callbackId != (if (sent) previous.sentCallbackId else previous.deliveryCallbackId)) return@synchronized false
        try {
            if (!callback.occurredAt.endsWith("Z") || Instant.parse(callback.occurredAt) < Instant.parse(attempt.invocationStartedAt)) return@synchronized false
        } catch (_: Exception) { return@synchronized false }
        val previousCode = if (sent) previous.sentCode else previous.deliveryCode
        if (previousCode == callback.resultCode) return@synchronized true
        val outcome = if (previousCode != null || callback.resultCode != -1) SegmentOutcome.UNKNOWN
            else if (sent) SegmentOutcome.FRAMEWORK_SENT else SegmentOutcome.DELIVERY_CALLBACK_OBSERVED
        val next = if (sent) previous.copy(sent = outcome, sentCode = callback.resultCode, sentObservedAt = callback.occurredAt)
            else previous.copy(delivery = outcome, deliveryCode = callback.resultCode, deliveryObservedAt = callback.occurredAt)
        val nextSegments = attempt.segments.toMutableList().also { it[callback.segmentIndex] = next }
        val updated = attempt.copy(segments = nextSegments)
        val nextAttempts = state.attempts.toMutableList().also { it[index] = updated }
        // Paused/revoked enrollment does not discard evidence for an already
        // armed attempt. It never grants permission for another invocation.
        storage.commit(state.copy(attempts = nextAttempts))
        true
    }

    private fun validated(state: GatewayJournalState): GatewayJournalState {
        if (state.attempts.size > MAX_ATTEMPTS || state.attempts.map { it.attemptId }.toSet().size != state.attempts.size) {
            throw GatewayStateException("gateway_journal_invalid")
        }
        state.attempts.forEach(::validateAttempt)
        return state
    }
}

internal fun validUuid(value: String): Boolean = try {
    value.matches(Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")) && UUID.fromString(value).toString() == value
} catch (_: IllegalArgumentException) { false }

internal fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
    .digest(value.toByteArray(StandardCharsets.UTF_8)).joinToString("") { "%02x".format(it) }

internal fun sameNonce(actual: String, expected: String): Boolean = MessageDigest.isEqual(
    actual.toByteArray(StandardCharsets.US_ASCII), expected.toByteArray(StandardCharsets.US_ASCII),
)

internal fun validateAttempt(value: GatewayAttempt) {
    if (!listOf(value.deviceId, value.jobId, value.attemptId).all(::validUuid) || value.fence !in 1..1_000_000_000L ||
        !listOf(value.bodySha256, value.destinationSha256, value.callbackNonce).all { it.matches(Regex("[0-9a-f]{64}")) } ||
        value.segments.size !in 1..GatewayJournal.MAX_SEGMENTS) throw GatewayStateException("gateway_attempt_invalid")
    try {
        val started = Instant.parse(value.invocationStartedAt)
        val expiry = Instant.parse(value.grantExpiresAt)
        if (!value.invocationStartedAt.endsWith("Z") || !value.grantExpiresAt.endsWith("Z") || started >= expiry || expiry.epochSecond - started.epochSecond > 120) throw IllegalArgumentException()
    } catch (_: Exception) { throw GatewayStateException("gateway_attempt_invalid") }
    value.segments.forEach {
        if (!validUuid(it.sentCallbackId) || !validUuid(it.deliveryCallbackId) || it.sentCallbackId == it.deliveryCallbackId ||
            it.sent !in setOf(SegmentOutcome.PENDING, SegmentOutcome.FRAMEWORK_SENT, SegmentOutcome.UNKNOWN) ||
            it.delivery !in setOf(SegmentOutcome.PENDING, SegmentOutcome.DELIVERY_CALLBACK_OBSERVED, SegmentOutcome.UNKNOWN) ||
            (it.sent == SegmentOutcome.PENDING) != (it.sentCode == null) ||
            (it.delivery == SegmentOutcome.PENDING) != (it.deliveryCode == null) ||
            (it.sentCode == null) != (it.sentObservedAt == null) || (it.deliveryCode == null) != (it.deliveryObservedAt == null)) {
            throw GatewayStateException("gateway_segment_invalid")
        }
        if ((it.sent == SegmentOutcome.FRAMEWORK_SENT && it.sentCode != -1) ||
            (it.delivery == SegmentOutcome.DELIVERY_CALLBACK_OBSERVED && it.deliveryCode != -1)) {
            throw GatewayStateException("gateway_segment_invalid")
        }
        listOfNotNull(it.sentObservedAt, it.deliveryObservedAt).forEach { timestamp ->
            try {
                if (!timestamp.endsWith("Z") || Instant.parse(timestamp) < Instant.parse(value.invocationStartedAt)) throw IllegalArgumentException()
            } catch (_: Exception) { throw GatewayStateException("gateway_segment_invalid") }
        }
    }
    val callbacks = value.segments.flatMap { listOf(it.sentCallbackId, it.deliveryCallbackId) }
    if (callbacks.toSet().size != callbacks.size) throw GatewayStateException("gateway_segment_invalid")
}
