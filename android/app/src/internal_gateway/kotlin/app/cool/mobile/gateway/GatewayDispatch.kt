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
    val dispatchRoute: GatewayDispatchRoute = GatewayDispatchRoute.PrimaryV2,
) {
    fun validate(now: Instant, authority: GatewayAuthority) {
        validateDispatchRoute(dispatchRoute, jobId)
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
    /** Production v2 grant validation establishes current policy/device authority.
     * The heartbeat itself remains only a recorded device observation. */
    fun supportsPolicyDispatch(): Boolean = false
    /** Called exactly once after the durable local invocation reservation.
     * Null/timeout/replayed/expired acknowledgement never permits a send. */
    fun armDispatch(grant: GatewayDispatchGrant, reservation: GatewayAttempt): GatewayDispatchArmAck? = null
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
        if (backend.supportsPolicyDispatch()) requireObservedHealth(authority) else requireAuthority(authority)
        // Stop, pause or local health changes during heartbeat must win before
        // requesting a lifetime server reservation, not just before invocation.
        if (journal.read().emergencyPaused) throw GatewayStateException("gateway_emergency_paused")
        val afterHealth = observe()
        if (!afterHealth.ready() || afterHealth.subscriptionId != initial.subscriptionId) throw GatewayStateException("gateway_device_not_ready")
        val grant = backend.dispatchGrant(initial) ?: return null
        val grantAuthority = if (backend.supportsPolicyDispatch()) GatewayAuthority(grant.deviceId,
            GatewayEnrollmentState.ACTIVE, true, clock()) else authority
        val reservation = synchronized(GatewayJournal.PROCESS_LOCK) {
            // A pause or SIM/permission/network change while fetching the grant
            // wins before reservation. No default-SIM fallback is permitted.
            if (journal.read().emergencyPaused) throw GatewayStateException("gateway_emergency_paused")
            val current = observe()
            if (!current.ready() || current.subscriptionId != initial.subscriptionId) throw GatewayStateException("gateway_device_not_ready")
            requireAuthority(grantAuthority)
            grant.validate(clock(), grantAuthority)
            val subscription = current.subscriptionId ?: throw GatewayStateException("gateway_device_not_ready")
            val parts = invoker.divide(grant.body, subscription)
            if (parts.size != grant.segmentCount || parts.joinToString("") != grant.body || parts.any { it.isEmpty() }) {
                throw GatewayStateException("gateway_segment_count_mismatch")
            }
            val started = clock()
            grant.validate(started, grantAuthority)
            val record = GatewayAttempt(grant.deviceId, grant.jobId, grant.attemptId, grant.fence, grant.bodySha256,
                grant.destinationSha256, grant.expiresAt.toString(), started.toString(), GatewayCrypto.nonce(),
                List(parts.size) { SegmentEvidence() }, dispatchRoute = grant.dispatchRoute)
            journal.reserveInvocation(record)
            journal.prepareInvocation(record)
            Triple(record, parts, subscription)
        }
        val (record, parts, subscription) = reservation
        try {
                // Durable I/O may consume the lease or coincide with a local
                // permission/SIM change. The reservation is never reusable.
                requireAuthority(grantAuthority)
                grant.validate(clock(), grantAuthority)
                val last = observe()
                if (!last.ready() || last.subscriptionId != subscription) throw GatewayStateException("gateway_device_not_ready")
                val arm = backend.armDispatch(grant, record) ?: throw GatewayStateException("gateway_arm_not_acknowledged")
            synchronized(GatewayJournal.PROCESS_LOCK) {
                val at = clock()
                if (((record.dispatchRoute is GatewayDispatchRoute.ReceiptSuccessorV1 || record.dispatchRoute is GatewayDispatchRoute.ReceiptNoticeV1) && arm.dispatchRoute != record.dispatchRoute) ||
                    arm.attemptId != record.attemptId || arm.fence != record.fence ||
                    arm.reservationSha256 != gatewayReservationDigest(record) || arm.armedAt > at.plusSeconds(5) ||
                    arm.expiresAt <= at || arm.expiresAt > grant.expiresAt || arm.expiresAt > arm.armedAt.plusSeconds(30)) {
                    throw GatewayStateException("gateway_arm_not_acknowledged")
                }
                val final = observe()
                if (journal.read().emergencyPaused || !final.ready() || final.subscriptionId != subscription) {
                    throw GatewayStateException("gateway_device_not_ready")
                }
                val invokeAt = clock()
                if (arm.expiresAt <= invokeAt) throw GatewayStateException("gateway_arm_not_acknowledged")
                grant.validate(invokeAt, grantAuthority)
                // The permanent application-entry record is read back before
                // crossing the sender seam. A crash afterwards stays unknown.
                journal.enterInvocation(record, invokeAt)
                invoker.invoke(grant, record, parts, subscription)
            }
        } catch (_: Exception) {
            journal.markInvocationUnknown(record.attemptId)
            throw GatewayStateException("gateway_invocation_outcome_unknown")
        }
        return record
    }

    private fun requireObservedHealth(value: GatewayAuthority) {
        val now = clock()
        if (!validUuid(value.deviceId ?: "") || value.checkedAt == null || value.checkedAt > now.plusSeconds(5) ||
            value.checkedAt <= now.minusSeconds(60) || value.state in setOf(GatewayEnrollmentState.NOT_ENROLLED,
                GatewayEnrollmentState.PAUSED, GatewayEnrollmentState.REVOKED)) throw GatewayStateException("gateway_dispatch_not_authorized")
    }

    private fun requireAuthority(value: GatewayAuthority) {
        val now = clock()
        if (value.state != GatewayEnrollmentState.ACTIVE || !value.dispatchEnabled || value.deviceId == null ||
            value.checkedAt == null || value.checkedAt > now.plusSeconds(5) || value.checkedAt <= now.minusSeconds(60)) {
            throw GatewayStateException("gateway_dispatch_not_authorized")
        }
    }
}

/** Stable hash of the exact immutable reservation fields and callback plan.
 * It binds signed handset evidence; the server does not independently attest fsync. */
private fun primaryReservationDigest(record: GatewayAttempt): String = sha256(listOf(
    record.deviceId, record.jobId, record.attemptId, record.fence.toString(), record.bodySha256,
    record.destinationSha256, record.grantExpiresAt, record.invocationStartedAt, record.callbackNonce,
    record.segments.joinToString("|") { it.sentCallbackId + "|" + it.deliveryCallbackId }
).joinToString("|"))

internal fun gatewayReservationDigest(record: GatewayAttempt): String {
    validateDispatchRoute(record.dispatchRoute, record.jobId)
    val original = primaryReservationDigest(record)
    return when (record.dispatchRoute) {
        is GatewayDispatchRoute.ReceiptNoticeV1 -> noticeReservationDigest(record, original)
        is GatewayDispatchRoute.ReceiptSuccessorV1 -> successorReservationDigest(record, original)
        is GatewayDispatchRoute.PrimaryV2 -> original
    }
}
