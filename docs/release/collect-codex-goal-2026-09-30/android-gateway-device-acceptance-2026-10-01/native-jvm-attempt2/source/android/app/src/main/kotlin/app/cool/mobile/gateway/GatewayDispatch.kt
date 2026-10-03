package app.cool.mobile.gateway

import java.time.Instant

internal enum class GatewayEnrollmentState { NOT_ENROLLED, PENDING, ACTIVE, PAUSED, REVOKED, UNKNOWN }

internal data class GatewayAuthority(
    val deviceId: String?,
    val state: GatewayEnrollmentState,
    val dispatchEnabled: Boolean = false,
    val checkedAt: Instant? = null,
)

internal data class GatewayObservations(
    val sendSmsPermission: Boolean,
    val readPhoneStatePermission: Boolean,
    val networkConnected: Boolean,
    val networkValidated: Boolean,
    val messagingSupported: Boolean,
    val simReady: Boolean,
    val telephonyInService: Boolean,
    val subscriptionId: Int?,
    val subscriptionUnambiguous: Boolean,
) {
    fun ready(): Boolean = sendSmsPermission && readPhoneStatePermission && networkConnected && networkValidated &&
        messagingSupported && simReady && telephonyInService && subscriptionUnambiguous && subscriptionId != null
}

/** This type is created from the authenticated fixed-host transport only.
 * It is never accepted as a Dart method argument or operator-auth credential. */
internal data class GatewayDispatchGrant(
    val deviceId: String,
    val jobId: String,
    val attemptId: String,
    val fence: Long,
    val destinationE164: String,
    val destinationSha256: String,
    val body: String,
    val bodySha256: String,
    val expiresAt: Instant,
    val segmentCount: Int,
) {
    fun validate(now: Instant, authority: GatewayAuthority) {
        if (!listOf(deviceId, jobId, attemptId).all(::validUuid) || deviceId != authority.deviceId ||
            fence !in 1..1_000_000_000L || !destinationE164.matches(Regex("\\+2507[2389][0-9]{7}")) ||
            body.isBlank() || body.length > 1000 || body.toByteArray(Charsets.UTF_8).size > 4000 ||
            body.any { it == '\u0000' || it == '\r' || (it.code < 32 && it != '\n' && it != '\t') } ||
            sha256(body) != bodySha256 || sha256(destinationE164) != destinationSha256 ||
            segmentCount !in 1..GatewayJournal.MAX_SEGMENTS || expiresAt <= now ||
            expiresAt.epochSecond - now.epochSecond > 120) throw GatewayStateException("gateway_grant_invalid")
    }
}

internal interface GatewayBackend {
    fun heartbeat(observations: GatewayObservations): GatewayAuthority
    /** Null means no authorized grant. Initial real backend issues none. */
    fun dispatchGrant(observations: GatewayObservations): GatewayDispatchGrant?
    fun reconcile(journal: GatewayJournalState)
}

internal interface GatewaySmsInvoker {
    fun divide(body: String, subscriptionId: Int): List<String>
    fun invoke(grant: GatewayDispatchGrant, record: GatewayAttempt, parts: List<String>, subscriptionId: Int)
}

internal class GatewayDispatchEngine(
    private val journal: GatewayJournal,
    private val backend: GatewayBackend,
    private val invoker: GatewaySmsInvoker,
    private val observe: () -> GatewayObservations,
    private val clock: () -> Instant = { Instant.now() },
) {
    fun dispatchOne(): GatewayAttempt? {
        if (journal.read().emergencyPaused) throw GatewayStateException("gateway_emergency_paused")
        val initial = observe()
        if (!initial.ready()) throw GatewayStateException("gateway_device_not_ready")
        val authority = backend.heartbeat(initial)
        requireAuthority(authority)
        val grant = backend.dispatchGrant(initial) ?: return null
        synchronized(GatewayJournal.PROCESS_LOCK) {
            // A pause or SIM/permission/network change while fetching the grant
            // wins before reservation. No default-SIM fallback is permitted.
            if (journal.read().emergencyPaused) throw GatewayStateException("gateway_emergency_paused")
            val current = observe()
            if (!current.ready() || current.subscriptionId != initial.subscriptionId) throw GatewayStateException("gateway_device_not_ready")
            requireAuthority(authority)
            grant.validate(clock(), authority)
            val subscription = current.subscriptionId ?: throw GatewayStateException("gateway_device_not_ready")
            val parts = invoker.divide(grant.body, subscription)
            if (parts.size != grant.segmentCount || parts.joinToString("") != grant.body || parts.any { it.isEmpty() }) {
                throw GatewayStateException("gateway_segment_count_mismatch")
            }
            val started = clock()
            grant.validate(started, authority)
            val record = GatewayAttempt(grant.deviceId, grant.jobId, grant.attemptId, grant.fence, grant.bodySha256,
                grant.destinationSha256, grant.expiresAt.toString(), started.toString(), GatewayCrypto.nonce(),
                List(parts.size) { SegmentEvidence() })
            journal.reserveInvocation(record)
            try {
                // Durable I/O may consume the lease or coincide with a local
                // permission/SIM change. The reservation is never reusable.
                requireAuthority(authority)
                grant.validate(clock(), authority)
                val last = observe()
                if (!last.ready() || last.subscriptionId != subscription) throw GatewayStateException("gateway_device_not_ready")
                // Exactly one app-level SmsManager invocation after fsync.
                invoker.invoke(grant, record, parts, subscription)
            } catch (_: Exception) {
                journal.markInvocationUnknown(record.attemptId)
                throw GatewayStateException("gateway_invocation_outcome_unknown")
            }
            return record
        }
    }

    private fun requireAuthority(value: GatewayAuthority) {
        val now = clock()
        if (value.state != GatewayEnrollmentState.ACTIVE || !value.dispatchEnabled || value.deviceId == null ||
            value.checkedAt == null || value.checkedAt > now.plusSeconds(5) || value.checkedAt <= now.minusSeconds(60)) {
            throw GatewayStateException("gateway_dispatch_not_authorized")
        }
    }
}
