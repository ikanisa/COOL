package app.cool.mobile.gateway

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import javax.crypto.spec.SecretKeySpec

class GatewaySafetyTest {
    private val now = Instant.parse("2026-09-30T21:00:00Z")
    private val device = "00000000-0000-0000-0000-000000000001"
    private val job = "00000000-0000-0000-0000-000000000002"
    private val attempt = "00000000-0000-0000-0000-000000000003"
    private val body = "Synthetic receipt evidence only"
    private val destination = "+250788000101"
    private fun grant() = GatewayDispatchGrant(device, job, attempt, 1, destination, sha256(destination), body, sha256(body), now.plusSeconds(60), 2)
    private fun observation() = GatewayObservations(true, true, true, true, true, true, true, 1, true)
    private fun record() = GatewayAttempt(device, job, attempt, 1, sha256(body), sha256(destination), now.plusSeconds(60).toString(),
        now.toString(), "a".repeat(64), List(2) { SegmentEvidence() })

    private class Memory : GatewayJournalStorage {
        var state = GatewayJournalState(emergencyPaused = false)
        var failCommit = false
        var failRead = false
        var commits = 0
        var afterCommit: () -> Unit = {}
        override fun read(): GatewayJournalState {
            if (failRead) throw GatewayStateException("gateway_storage_unavailable")
            return state
        }
        override fun commit(state: GatewayJournalState) {
            if (failCommit) throw GatewayStateException("gateway_storage_unavailable")
            this.state = state
            commits++
            afterCommit()
        }
    }

    private inner class Backend(var issued: GatewayDispatchGrant? = grant()) : GatewayBackend {
        var authority = GatewayAuthority(device, GatewayEnrollmentState.ACTIVE, true, now)
        var calls = 0
        var duringGrant: () -> Unit = {}
        override fun heartbeat(observations: GatewayObservations): GatewayAuthority = authority
        override fun dispatchGrant(observations: GatewayObservations): GatewayDispatchGrant? { calls++; duringGrant(); return issued }
        var arms = 0
        var armReply: ((GatewayDispatchGrant, GatewayAttempt) -> GatewayDispatchArmAck?)? = null
        override fun armDispatch(grant: GatewayDispatchGrant, reservation: GatewayAttempt): GatewayDispatchArmAck? {
            arms++
            return armReply?.invoke(grant, reservation) ?: GatewayDispatchArmAck(reservation.attemptId, reservation.fence,
                gatewayReservationDigest(reservation), now, minOf(grant.expiresAt, now.plusSeconds(30)))
        }
        override fun reconcile(journal: GatewayJournalState) = Unit
    }
    private inner class Sender(private val memory: Memory) : GatewaySmsInvoker {
        var calls = 0
        var throwAfterInvocation = false
        var parts = listOf(body.substring(0, 10), body.substring(10))
        override fun divide(body: String, subscriptionId: Int): List<String> = parts
        override fun invoke(grant: GatewayDispatchGrant, record: GatewayAttempt, parts: List<String>, subscriptionId: Int) {
            assertEquals(1, memory.state.attempts.size)
            assertEquals(record, memory.state.attempts[0])
            assertTrue(memory.commits > 0)
            calls++
            if (throwAfterInvocation) throw RuntimeException("synthetic framework failure")
        }
    }
    private fun engine(memory: Memory, backend: Backend, sender: Sender, observe: () -> GatewayObservations = ::observation) =
        GatewayDispatchEngine(GatewayJournal(memory), backend, sender, observe) { now }
    private fun refused(code: String, action: () -> Unit) {
        try { action(); fail("Expected refusal") } catch (error: GatewayStateException) { assertEquals(code, error.reasonCode) }
    }
    private fun callback(value: GatewayAttempt, index: Int, kind: CallbackKind, code: Int = -1): GatewayCallback {
        val part = value.segments[index]
        return GatewayCallback(if (kind == CallbackKind.SENT) part.sentCallbackId else part.deliveryCallbackId,
            value.deviceId, value.attemptId, value.fence, index, value.callbackNonce, kind, code, now.plusSeconds(1).toString())
    }

    @Test fun reservationIsCommittedBeforeTheSingleSenderCall() {
        val memory = Memory(); val sender = Sender(memory); val backend = Backend()
        engine(memory, backend, sender).dispatchOne()
        assertEquals(1, sender.calls)
        assertEquals(AttemptOutcome.OUTCOME_UNKNOWN, memory.state.attempts.single().outcome())
    }
    @Test fun leaseConsumedByDurableCommitNeverInvokesAndReservationCannotBeReused() {
        val memory=Memory(); val sender=Sender(memory); var current=now
        memory.afterCommit={ current=now.plusSeconds(60) }
        val engine=GatewayDispatchEngine(GatewayJournal(memory),Backend(),sender,::observation) { current }
        refused("gateway_invocation_outcome_unknown") { engine.dispatchOne() }
        assertEquals(0,sender.calls); assertTrue(memory.state.attempts.single().invocationException)
    }
    @Test fun permissionRevokedAfterDurableCommitNeverInvokes() {
        val memory=Memory(); val sender=Sender(memory); var permitted=true
        memory.afterCommit={ permitted=false }
        val engine=engine(memory,Backend(),sender) { observation().copy(sendSmsPermission=permitted) }
        refused("gateway_invocation_outcome_unknown") { engine.dispatchOne() }
        assertEquals(0,sender.calls); assertTrue(memory.state.attempts.single().invocationException)
    }
    @Test fun journalCommitFailureNeverCrossesSenderSeam() {
        val memory = Memory().also { it.failCommit = true }; val sender = Sender(memory)
        refused("gateway_storage_unavailable") { engine(memory, Backend(), sender).dispatchOne() }
        assertEquals(0, sender.calls)
    }
    @Test fun corruptJournalNeverBecomesAnEmptyReadyJournal() {
        val memory = Memory().also { it.failRead = true }; val sender = Sender(memory)
        refused("gateway_storage_unavailable") { engine(memory, Backend(), sender).dispatchOne() }
        assertEquals(0, sender.calls)
    }
    @Test fun duplicateOrCrashReservedAttemptCannotBeInvokedAgain() {
        val memory = Memory(); GatewayJournal(memory).reserveInvocation(record()); val sender = Sender(memory)
        refused("gateway_attempt_already_invoked") { engine(memory, Backend(), sender).dispatchOne() }
        assertEquals(0, sender.calls)
    }
    @Test fun frameworkExceptionRemainsUnknownAndCannotBeRetried() {
        val memory = Memory(); val sender = Sender(memory).also { it.throwAfterInvocation = true }; val engine = engine(memory, Backend(), sender)
        refused("gateway_invocation_outcome_unknown") { engine.dispatchOne() }
        assertTrue(memory.state.attempts.single().invocationException)
        refused("gateway_attempt_already_invoked") { engine.dispatchOne() }
        assertEquals(1, sender.calls)
    }
    @Test fun emergencyPauseWhileFetchingGrantWinsBeforeInvocation() {
        val memory = Memory(); val sender = Sender(memory); val backend = Backend().also { it.duringGrant = { GatewayJournal(memory).pause() } }
        refused("gateway_emergency_paused") { engine(memory, backend, sender).dispatchOne() }
        assertEquals(0, sender.calls)
    }
    @Test fun initialPauseRejectsBeforeAnyBackendGrantRequest() {
        val memory = Memory().also { it.state = GatewayJournalState() }; val sender = Sender(memory); val backend = Backend()
        refused("gateway_emergency_paused") { engine(memory, backend, sender).dispatchOne() }
        assertEquals(0, backend.calls); assertEquals(0, sender.calls)
    }
    @Test fun independentMissingDeviceSignalsBlockSending() {
        val invalid = listOf(observation().copy(sendSmsPermission=false), observation().copy(readPhoneStatePermission=false),
            observation().copy(networkConnected=false), observation().copy(networkValidated=false), observation().copy(simReady=false),
            observation().copy(telephonyInService=false), observation().copy(subscriptionUnambiguous=false), observation().copy(subscriptionId=null))
        for (value in invalid) {
            val memory = Memory(); val sender = Sender(memory)
            refused("gateway_device_not_ready") { engine(memory, Backend(), sender) { value }.dispatchOne() }
            assertEquals(0, sender.calls)
        }
    }
    @Test fun changedSubscriptionBetweenGrantAndInvocationBlocksSending() {
        val memory = Memory(); val sender = Sender(memory); var read = 0
        refused("gateway_device_not_ready") { engine(memory, Backend(), sender) { observation().copy(subscriptionId=if (read++==0) 1 else 2) }.dispatchOne() }
        assertEquals(0, sender.calls)
    }
    @Test fun revokedPendingUnknownOrStaleAuthorityCannotDispatch() {
        for (state in listOf(GatewayEnrollmentState.REVOKED, GatewayEnrollmentState.PENDING, GatewayEnrollmentState.UNKNOWN)) {
            val memory=Memory(); val sender=Sender(memory); val backend=Backend().also { it.authority=it.authority.copy(state=state) }
            refused("gateway_dispatch_not_authorized") { engine(memory,backend,sender).dispatchOne() }; assertEquals(0,sender.calls)
        }
        val memory=Memory(); val sender=Sender(memory); val backend=Backend().also { it.authority=it.authority.copy(checkedAt=now.minusSeconds(60)) }
        refused("gateway_dispatch_not_authorized") { engine(memory,backend,sender).dispatchOne() }; assertEquals(0,sender.calls)
    }
    @Test fun absentGrantDoesNotCreateAnInvocation() {
        val memory=Memory(); val sender=Sender(memory)
        assertNull(engine(memory,Backend(null),sender).dispatchOne()); assertEquals(0,sender.calls); assertTrue(memory.state.attempts.isEmpty())
    }
    @Test fun expiredEqualExpiryHashMismatchOrWrongDeviceGrantIsRejected() {
        val invalid=listOf(grant().copy(expiresAt=now), grant().copy(bodySha256="b".repeat(64)),
            grant().copy(destinationSha256="b".repeat(64)), grant().copy(deviceId=job))
        for (value in invalid) {
            val memory=Memory(); val sender=Sender(memory)
            refused("gateway_grant_invalid") { engine(memory,Backend(value),sender).dispatchOne() }; assertEquals(0,sender.calls)
        }
    }
    @Test fun actualSegmentCountMismatchDoesNotInvokeSender() {
        val memory=Memory(); val sender=Sender(memory).also { it.parts=listOf(body) }
        refused("gateway_segment_count_mismatch") { engine(memory,Backend(),sender).dispatchOne() }; assertEquals(0,sender.calls)
    }
    @Test fun multipartSegmentsAreIndependentAndMissingCallbackIsUnknown() {
        val memory=Memory(); val journal=GatewayJournal(memory); val value=record(); journal.reserveInvocation(value)
        assertTrue(journal.record(callback(value,0,CallbackKind.SENT)))
        assertEquals(AttemptOutcome.OUTCOME_UNKNOWN,journal.read().attempts.single().outcome())
        assertTrue(journal.record(callback(value,1,CallbackKind.SENT)))
        assertEquals(AttemptOutcome.FRAMEWORK_SENT,journal.read().attempts.single().outcome())
        assertTrue(journal.record(callback(value,0,CallbackKind.DELIVERY)))
        assertEquals(AttemptOutcome.FRAMEWORK_SENT,journal.read().attempts.single().outcome())
        assertTrue(journal.record(callback(value,1,CallbackKind.DELIVERY)))
        assertEquals(AttemptOutcome.DELIVERY_CALLBACK_OBSERVED,journal.read().attempts.single().outcome())
    }
    @Test fun genericFailureOrConflictingCallbackNeverBecomesSuccessful() {
        val memory=Memory(); val journal=GatewayJournal(memory); val value=record(); journal.reserveInvocation(value)
        journal.record(callback(value,0,CallbackKind.SENT,1)); journal.record(callback(value,0,CallbackKind.SENT,-1));
        journal.record(callback(value,1,CallbackKind.SENT,-1))
        assertEquals(AttemptOutcome.OUTCOME_UNKNOWN,journal.read().attempts.single().outcome())
    }
    @Test fun correlatedCallbacksAreAcceptedDuringEmergencyPause() {
        val memory=Memory(); val journal=GatewayJournal(memory); val value=record(); journal.reserveInvocation(value); journal.pause()
        assertTrue(journal.record(callback(value,0,CallbackKind.SENT)))
        assertTrue(journal.read().emergencyPaused)
    }
    @Test fun wrongDeviceFenceIndexNonceCallbackIdentityOrTimeIsRefused() {
        val memory=Memory(); val journal=GatewayJournal(memory); val value=record(); journal.reserveInvocation(value)
        val original=callback(value,0,CallbackKind.SENT)
        for (invalid in listOf(original.copy(deviceId=job), original.copy(fence=2),original.copy(segmentIndex=9),
            original.copy(nonce="b".repeat(64)),original.copy(callbackId=job),original.copy(occurredAt=now.minusSeconds(1).toString()))) {
            assertFalse(journal.record(invalid))
        }
        assertEquals(AttemptOutcome.OUTCOME_UNKNOWN,journal.read().attempts.single().outcome())
    }
    @Test fun identicalCallbackReplayDoesNotRewriteEvidence() {
        val memory=Memory(); val journal=GatewayJournal(memory); val value=record(); journal.reserveInvocation(value)
        val callback=callback(value,0,CallbackKind.SENT); journal.record(callback); val count=memory.commits
        assertTrue(journal.record(callback)); assertEquals(count,memory.commits)
    }
    @Test fun encryptedJournalIsAuthenticatedAndBoundToItsPurpose() {
        val key=SecretKeySpec(ByteArray(32) { 5 },"AES"); val crypto=GatewayCrypto(key)
        val plain="synthetic encrypted journal metadata".toByteArray(); val cipher=crypto.encrypt(plain)
        assertArrayEquals(plain,crypto.decrypt(cipher)); assertFalse(String(cipher).contains("synthetic encrypted"))
        val changed=cipher.copyOf().also { it[it.lastIndex]=(it.last().toInt() xor 1).toByte() }
        refused("gateway_journal_unavailable") { crypto.decrypt(changed) }
        refused("gateway_journal_unavailable") { GatewayCrypto(key,"another-purpose").decrypt(cipher) }
        refused("gateway_journal_unavailable") { GatewayCrypto(SecretKeySpec(ByteArray(32) { 6 },"AES")).decrypt(cipher) }
    }
    @Test fun corruptedHeaderAndOversizedPlaintextFailClosed() {
        val crypto=GatewayCrypto(SecretKeySpec(ByteArray(32) { 5 },"AES"))
        refused("gateway_journal_invalid") { crypto.decrypt(ByteArray(1)) }
        refused("gateway_journal_limit") { crypto.encrypt(ByteArray(GatewayCrypto.MAX_BYTES+1)) }
    }
}
