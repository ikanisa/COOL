package app.cool.mobile.gateway

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.time.Instant

/** Engine seam tests. Memory commits model the synchronous durable-storage
 * contract; these tests do not attest real Android fsync or radio behaviour. */
class GatewayDispatchArmTest {
    private val at = Instant.parse("2026-10-01T12:00:00Z")
    private val device = "aa760000-0000-4000-8000-000000000001"
    private val receipt = "aa760000-0000-4000-8000-000000000002"
    private val attempt = "aa760000-0000-4000-8000-000000000003"
    private val request = "aa760000-0000-4000-8000-000000000004"
    private val run = "aa760000-0000-4000-8000-000000000005"
    private val body = "Synthetic recorded savings receipt for arm-boundary tests"
    private val destination = "+250788000101"
    private fun grant() = GatewayDispatchGrant(device, receipt, attempt, 7, destination,
        sha256(destination), body, sha256(body), at.plusSeconds(30), 2)
    private fun ready() = GatewayObservations(true, true, true, true, true, true, true, 1, true)

    private class Memory(private val events: MutableList<String>) : GatewayJournalStorage {
        var state = GatewayJournalState(emergencyPaused = false)
        var commits = 0
        var durableCommitCompleted = false
        var failCommit = false
        var afterCommit: () -> Unit = {}
        override fun read(): GatewayJournalState = state
        override fun commit(state: GatewayJournalState) {
            if (failCommit) throw GatewayStateException("gateway_storage_unavailable")
            this.state = state
            commits++
            durableCommitCompleted = true
            events.add(if (state.attempts.any { it.invocationException }) "retain_unknown" else "durable_commit")
            afterCommit()
        }
    }

    private inner class Fixture {
        val events = mutableListOf<String>()
        val memory = Memory(events)
        val journal = GatewayJournal(memory)
        var time = at
        var observation = ready()
        var issued: GatewayDispatchGrant? = grant()
        var authority = GatewayAuthority(device, GatewayEnrollmentState.ACTIVE, true, at)
        var policyDispatch = false
        var grants = 0
        var arms = 0
        var invocations = 0
        var duringGrant: () -> Unit = {}
        var duringArm: () -> Unit = {}
        var duringObservation: () -> Unit = {}
        var armReply: (GatewayDispatchGrant, GatewayAttempt) -> GatewayDispatchArmAck? = { value, record -> ack(value, record) }
        val backend = object : GatewayBackend {
            override fun heartbeat(observations: GatewayObservations): GatewayAuthority {
                events.add("heartbeat")
                return authority
            }
            override fun dispatchGrant(observations: GatewayObservations): GatewayDispatchGrant? {
                events.add("grant")
                grants++
                duringGrant()
                return issued
            }
            override fun supportsPolicyDispatch(): Boolean = policyDispatch
            override fun armDispatch(grant: GatewayDispatchGrant, reservation: GatewayAttempt): GatewayDispatchArmAck? {
                arms++
                events.add("arm")
                assertTrue("The storage commit must complete before arming", memory.durableCommitCompleted)
                assertEquals("Arm must bind the reservation actually retained", reservation, memory.state.attempts.single())
                assertTrue(reservation.segments.all { it.sent == SegmentOutcome.PENDING && it.delivery == SegmentOutcome.PENDING })
                duringArm()
                return armReply(grant, reservation)
            }
            override fun reconcile(journal: GatewayJournalState) = Unit
        }
        val sender = object : GatewaySmsInvoker {
            override fun divide(body: String, subscriptionId: Int): List<String> {
                events.add("divide")
                assertEquals(1, subscriptionId)
                return listOf(body.substring(0, 20), body.substring(20))
            }
            override fun invoke(grant: GatewayDispatchGrant, record: GatewayAttempt, parts: List<String>, subscriptionId: Int) {
                events.add("invoke")
                invocations++
                assertTrue(memory.durableCommitCompleted)
                assertEquals(1, arms)
                assertEquals(record, memory.state.attempts.single())
                assertEquals(body, parts.joinToString(""))
                assertEquals(1, subscriptionId)
            }
        }
        val engine = GatewayDispatchEngine(journal, backend, sender, { duringObservation(); observation }, { time })
        fun ack(value: GatewayDispatchGrant, record: GatewayAttempt) = GatewayDispatchArmAck(record.attemptId, record.fence,
            gatewayReservationDigest(record), time, minOf(value.expiresAt, time.plusSeconds(30)))
    }

    private fun refused(code: String, action: () -> Unit) {
        try { action(); fail("Expected refusal: $code") }
        catch (error: GatewayStateException) { assertEquals(code, error.reasonCode) }
    }
    private fun assertRetainedUnknown(fixture: Fixture) {
        assertEquals(0, fixture.invocations)
        assertEquals(1, fixture.memory.state.attempts.size)
        val retained = fixture.memory.state.attempts.single()
        assertEquals(attempt, retained.attemptId)
        assertTrue(retained.invocationException)
        assertEquals(AttemptOutcome.OUTCOME_UNKNOWN, retained.outcome())
        assertEquals(2, retained.segments.size)
        assertTrue(retained.segments.all { it.sentCode == null && it.deliveryCode == null })
    }

    @Test fun synchronousDurableReservationCompletesBeforeArmAndSingleInvocation() {
        val f = Fixture()
        val record = f.engine.dispatchOne()!!
        assertEquals(listOf("heartbeat", "grant", "divide", "durable_commit", "arm", "invoke"), f.events)
        assertEquals(1, f.memory.commits)
        assertEquals(1, f.arms)
        assertEquals(1, f.invocations)
        assertEquals(record, f.memory.state.attempts.single())
        assertFalse(record.invocationException)
        // A permit and invocation do not fabricate successful SENT callbacks.
        assertEquals(AttemptOutcome.OUTCOME_UNKNOWN, record.outcome())
    }

    @Test fun missingArmAcknowledgementRetainsUnknownAndNeverInvokes() {
        val f = Fixture().also { it.armReply = { _, _ -> null } }
        refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
        assertRetainedUnknown(f)
        assertEquals(1, f.arms)
        assertEquals(listOf("heartbeat", "grant", "divide", "durable_commit", "arm", "retain_unknown"), f.events)
    }

    @Test fun armDisconnectOrBackendExceptionRetainsOriginalReservationWithoutInvocation() {
        for (failure in listOf<Exception>(IOException("Synthetic lost arm response"),
            GatewayStateException("gateway_http_outcome_unknown"), IllegalStateException("Synthetic malformed response"))) {
            val f = Fixture().also { it.armReply = { _, _ -> throw failure } }
            refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
            assertRetainedUnknown(f)
            assertEquals(1, f.arms)
            assertEquals(2, f.memory.commits)
        }
    }

    @Test fun replayedOriginalRequestRefusalCannotRecoverArmAuthority() {
        val f = Fixture()
        f.armReply = { _, record ->
            val payload = JSONObject().put("attempt_id", record.attemptId).put("fence_version", record.fence)
                .put("body_sha256", record.bodySha256).put("destination_sha256", record.destinationSha256)
                .put("callbacks", org.json.JSONArray(record.segments.mapIndexed { index, segment -> JSONObject()
                    .put("segment_index", index).put("sent_callback_id", segment.sentCallbackId).put("delivery_callback_id", segment.deliveryCallbackId) }))
                .put("reservation_sha256", gatewayReservationDigest(record))
            val replay = JSONObject().put("ok", false).put("code", "ORIGINAL_REQUEST_RECORDED")
                .put("device_id", device).put("request_id", request).put("replay", true)
            parseGatewayDispatchArmV2(request, device, payload, replay, record.let { Instant.parse(it.grantExpiresAt) }, f.time)
        }
        refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
        assertRetainedUnknown(f)
        assertEquals(1, f.arms)
    }

    @Test fun staleExpiredFutureOrExtendedArmAcknowledgementsNeverInvoke() {
        val invalid = listOf<(GatewayDispatchArmAck) -> GatewayDispatchArmAck>(
            { it.copy(expiresAt = at) },
            { it.copy(armedAt = at.minusSeconds(60)) },
            { it.copy(armedAt = at.plusSeconds(6)) },
            { it.copy(expiresAt = at.plusSeconds(31)) },
            { it.copy(armedAt = at.minusSeconds(1), expiresAt = at.plusSeconds(30)) },
        )
        for (change in invalid) {
            val f = Fixture()
            f.armReply = { value, record -> change(f.ack(value, record)) }
            refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
            assertRetainedUnknown(f)
            assertEquals(1, f.arms)
        }
    }

    @Test fun wrongAttemptFenceOrReservationDigestAcknowledgementNeverInvokes() {
        val invalid = listOf<(GatewayDispatchArmAck) -> GatewayDispatchArmAck>(
            { it.copy(attemptId = receipt) },
            { it.copy(fence = 8) },
            { it.copy(reservationSha256 = "0".repeat(64)) },
        )
        for (change in invalid) {
            val f = Fixture()
            f.armReply = { value, record -> change(f.ack(value, record)) }
            refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
            assertRetainedUnknown(f)
        }
    }

    @Test fun acknowledgementForAlteredCallbackPlanCannotAuthorizeRetainedReservation() {
        val f = Fixture()
        f.armReply = { value, record ->
            val changed = record.copy(segments = record.segments.map { it.copy(sentCallbackId = receipt) })
            f.ack(value, record).copy(reservationSha256 = gatewayReservationDigest(changed))
        }
        refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
        assertRetainedUnknown(f)
    }

    @Test fun localEmergencyPauseDuringArmWinsBeforeInvocationAndPreservesReservation() {
        val f = Fixture()
        f.duringArm = { f.journal.pause() }
        refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
        assertRetainedUnknown(f)
        assertTrue(f.memory.state.emergencyPaused)
        assertEquals(1, f.arms)
    }

    @Test fun subscriptionOrPermissionChangeWhileWaitingForArmClosesSenderBoundary() {
        for (changed in listOf(ready().copy(subscriptionId = 2), ready().copy(subscriptionId = null),
            ready().copy(sendSmsPermission = false), ready().copy(networkValidated = false))) {
            val f = Fixture()
            f.duringArm = { f.observation = changed }
            refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
            assertRetainedUnknown(f)
            assertEquals(1, f.arms)
        }
    }

    @Test fun grantExpiryConsumedDuringArmRetainsUnknownAndDoesNotInvoke() {
        val f = Fixture()
        f.armReply = { value, record ->
            val reply = f.ack(value, record)
            f.time = value.expiresAt
            reply
        }
        refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
        assertRetainedUnknown(f)
    }

    @Test fun finalDeviceObservationCannotConsumeLeaseBeforeInvocation() {
        val f = Fixture()
        f.duringObservation = { if (f.arms > 0) f.time = at.plusSeconds(30) }
        refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
        assertRetainedUnknown(f)
        assertEquals(1, f.arms)
    }

    @Test fun expiryConsumedByDurableCommitNeverRequestsArm() {
        val f = Fixture()
        f.memory.afterCommit = { f.time = at.plusSeconds(30) }
        refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
        assertRetainedUnknown(f)
        assertEquals(0, f.arms)
    }

    @Test fun failedDurableReservationNeverRequestsArmOrInvokes() {
        val f = Fixture()
        f.memory.failCommit = true
        refused("gateway_storage_unavailable") { f.engine.dispatchOne() }
        assertEquals(0, f.arms)
        assertEquals(0, f.invocations)
        assertTrue(f.memory.state.attempts.isEmpty())
    }

    @Test fun exactArmCanInvokeOnceButDuplicateAttemptCannotArmOrInvokeAgain() {
        val f = Fixture()
        f.engine.dispatchOne()
        val retained = f.memory.state.attempts.single()
        refused("gateway_attempt_already_invoked") { f.engine.dispatchOne() }
        assertEquals(1, f.invocations)
        assertEquals(1, f.arms)
        assertEquals(retained, f.memory.state.attempts.single())
        assertEquals(1, f.memory.commits)
    }

    @Test fun uncertainArmCannotBeRetriedWithSameAttemptAfterRestart() {
        val f = Fixture().also { it.armReply = { _, _ -> null } }
        refused("gateway_invocation_outcome_unknown") { f.engine.dispatchOne() }
        f.armReply = { value, record -> f.ack(value, record) }
        val restarted = GatewayDispatchEngine(f.journal, f.backend, f.sender, { f.observation }, { f.time })
        refused("gateway_attempt_already_invoked") { restarted.dispatchOne() }
        assertRetainedUnknown(f)
        assertEquals(1, f.arms)
        assertEquals(2, f.memory.commits)
    }

    @Test fun observationOnlyUnknownHeartbeatRequiresExplicitPolicyDispatchBackend() {
        val f = Fixture()
        f.authority = GatewayAuthority(device, GatewayEnrollmentState.UNKNOWN, false, at)
        refused("gateway_dispatch_not_authorized") { f.engine.dispatchOne() }
        assertEquals(0, f.grants)
        assertEquals(0, f.arms)
        assertEquals(0, f.invocations)
        assertTrue(f.memory.state.attempts.isEmpty())
    }

    @Test fun policyBackendObservedUnknownHealthUsesFreshParsedGrantBeforeArm() {
        val f = Fixture()
        f.policyDispatch = true
        f.authority = GatewayAuthority(device, GatewayEnrollmentState.UNKNOWN, false, at)
        val source = JSONObject().put("ok", true).put("code", "DISPATCH_GRANTED").put("device_id", device)
            .put("request_id", request).put("attempt_id", attempt).put("receipt_id", receipt).put("run_id", run)
            .put("fence_version", 7).put("policy_revision", 3).put("issued_at", at.toString()).put("expires_at", at.plusSeconds(30).toString())
            .put("segment_count", 2).put("body", body).put("destination_e164", destination).put("body_sha256", sha256(body))
            .put("destination_sha256", sha256(destination)).put("sim_revision_sha256", "e".repeat(64)).put("replay", false)
        f.issued = parseGatewayDispatchGrantV2(request, device, source, at)!!.grant
        f.engine.dispatchOne()
        assertEquals(1, f.grants)
        assertEquals(1, f.arms)
        assertEquals(1, f.invocations)
    }

    @Test fun policyBackendObservedHealthNeverBypassesPausedRevokedOrStaleEvidence() {
        for (authority in listOf(GatewayAuthority(device, GatewayEnrollmentState.PAUSED, false, at),
            GatewayAuthority(device, GatewayEnrollmentState.REVOKED, false, at),
            GatewayAuthority(device, GatewayEnrollmentState.UNKNOWN, false, at.minusSeconds(60)))) {
            val f = Fixture()
            f.policyDispatch = true
            f.authority = authority
            refused("gateway_dispatch_not_authorized") { f.engine.dispatchOne() }
            assertEquals(0, f.grants)
            assertEquals(0, f.arms)
            assertEquals(0, f.invocations)
            assertTrue(f.memory.state.attempts.isEmpty())
        }
    }

    @Test fun policyBackendNoGrantLeavesObservationWithoutInvocationReservation() {
        val f = Fixture()
        f.policyDispatch = true
        f.authority = GatewayAuthority(device, GatewayEnrollmentState.UNKNOWN, false, at)
        f.issued = null
        assertNull(f.engine.dispatchOne())
        assertEquals(1, f.grants)
        assertEquals(0, f.arms)
        assertEquals(0, f.invocations)
        assertTrue(f.memory.state.attempts.isEmpty())
    }
}
