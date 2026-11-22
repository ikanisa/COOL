package app.cool.mobile.gateway

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class GatewayBackgroundCoordinatorTest {
    private val now = Instant.parse("2026-10-01T14:00:00Z")
    private val device = "ac120000-0000-4000-8000-000000000001"
    private val installation = "ac120000-0000-4000-8000-000000000002"
    private val receipt = "ac120000-0000-4000-8000-000000000003"
    private val attempt = "ac120000-0000-4000-8000-000000000004"
    private val ready = GatewayObservations(true, true, true, true, true, true, true, 1, true)
    private class Memory : GatewayJournalStorage, GatewayInvocationStorage by GatewayInvocationSyntheticStore() {
        var value = GatewayJournalState()
        var fail = false
        override fun read() = if (fail) throw GatewayStateException("gateway_storage_unavailable") else value
        override fun commit(state: GatewayJournalState) { value = state }
    }
    private inner class Backend : GatewayBackend {
        var health = 0; var reconcile = 0; var grants = 0; var failHealth = false; var failReconcile = false
        var duringHealth: () -> Unit = {}; var duringReconcile: () -> Unit = {}; var duringArm: () -> Unit = {}
        override fun heartbeat(observations: GatewayObservations): GatewayAuthority {
            health++; duringHealth(); if (failHealth) throw GatewayStateException("gateway_http_outcome_unknown")
            return GatewayAuthority(device, GatewayEnrollmentState.UNKNOWN, false, now)
        }
        override fun supportsPolicyDispatch() = true
        override fun dispatchGrant(observations: GatewayObservations): GatewayDispatchGrant? {
            grants++; return GatewayDispatchGrant(device, receipt, attempt, 1, "+250788000111", sha256("+250788000111"), "Synthetic receipt", sha256("Synthetic receipt"), now.plusSeconds(30), 1)
        }
        override fun armDispatch(grant: GatewayDispatchGrant, reservation: GatewayAttempt): GatewayDispatchArmAck {
            duringArm(); return GatewayDispatchArmAck(attempt, 1, gatewayReservationDigest(reservation), now, now.plusSeconds(30))
        }
        override fun reconcile(journal: GatewayJournalState) {
            reconcile++; duringReconcile(); if (failReconcile) throw GatewayStateException("gateway_http_outcome_unknown")
        }
    }
    private inner class Fixture {
        val memory = Memory(); val journal = GatewayJournal(memory); val backend = Backend(); var sends = 0
        var observations = ready; var configured = true; var verified = true; var elapsed = 0L
        val token = GatewayCycleToken { elapsed }
        val sender = object : GatewaySmsInvoker {
            override fun divide(body: String, subscriptionId: Int) = listOf(body)
            override fun invoke(grant: GatewayDispatchGrant, record: GatewayAttempt, parts: List<String>, subscriptionId: Int) {
                if (!token.active()) throw GatewayStateException("gateway_cycle_stopped")
                sends++
            }
        }
        val engine = GatewayDispatchEngine(journal, backend, sender, { if (token.active()) observations else observations.copy(networkValidated = false) }) { now }
        fun coordinator() = GatewayBackgroundCoordinator(journal, backend, { observations }, engine::dispatchOne, { configured }, {
            if (!verified) throw GatewayStateException("gateway_enrollment_invalid")
        }, token)
    }
    @Test fun defaultPauseRecordsHealthAndExistingEvidenceWithoutGrant() {
        val f = Fixture(); assertEquals("gateway_health_evidence_recorded", f.coordinator().cycle().reasonCode)
        assertEquals(1, f.backend.health); assertEquals(1, f.backend.reconcile); assertEquals(0, f.backend.grants); assertEquals(0, f.sends)
        assertTrue(f.journal.read().emergencyPaused)
    }
    @Test fun explicitAllowOnlyClearsLocalPauseAndMakesNoBackendOrSenderCall() {
        val f = Fixture(); assertEquals("gateway_local_dispatch_allowed", f.coordinator().allowGovernedDispatch().reasonCode)
        assertFalse(f.journal.read().emergencyPaused); assertEquals(0, f.backend.health); assertEquals(0, f.backend.grants); assertEquals(0, f.sends)
    }
    @Test fun installedEnrollmentAndConfigurationAreRequiredForLocalAllowance() {
        for (kind in listOf("enrollment", "configuration", "stopped")) {
            val f = Fixture(); if (kind == "enrollment") f.verified = false else if (kind == "configuration") f.configured = false else f.token.cancel()
            try { f.coordinator().allowGovernedDispatch(); fail("Expected refusal") } catch (_: GatewayStateException) { }
            assertTrue(f.journal.read().emergencyPaused); assertEquals(0, f.backend.grants)
        }
    }
    @Test fun unconfiguredCycleNeverCallsBackend() { val f = Fixture(); f.configured = false; assertTrue(f.coordinator().cycle().backoff); assertEquals(0, f.backend.health) }
    @Test fun corruptJournalNeverBecomesAnEmptyDispatchableJournal() { val f = Fixture(); f.memory.fail = true; assertEquals("gateway_storage_unavailable", f.coordinator().cycle().reasonCode); assertEquals(0, f.backend.health) }
    @Test fun unvalidatedNetworkDoesNotAttemptWritesOrSms() { val f = Fixture(); f.observations = ready.copy(networkValidated = false); assertEquals("gateway_network_unavailable", f.coordinator().cycle().reasonCode); assertEquals(0, f.backend.health); assertEquals(0, f.sends) }
    @Test fun revokedHealthFailureStillReconcilesPriorEvidenceAndNeverGrants() {
        val f = Fixture(); f.journal.resume(); f.backend.failHealth = true
        assertEquals("gateway_health_unavailable", f.coordinator().cycle().reasonCode); assertEquals(1, f.backend.reconcile); assertEquals(0, f.backend.grants)
    }
    @Test fun missingSmsAndSimStillRecordIndependentHealthAndReconcile() {
        val f = Fixture(); f.journal.resume(); f.observations = ready.copy(sendSmsPermission = false, subscriptionUnambiguous = false)
        assertEquals("gateway_device_not_ready", f.coordinator().cycle().reasonCode); assertEquals(1, f.backend.health); assertEquals(1, f.backend.reconcile); assertEquals(0, f.backend.grants)
    }
    @Test fun reconciliationUncertaintyPreventsNewGrant() { val f = Fixture(); f.journal.resume(); f.backend.failReconcile = true; assertTrue(f.coordinator().cycle().backoff); assertEquals(0, f.backend.grants) }
    @Test fun healthOnlyCycleNeverRequestsGrantEvenWithLocalAllowance() { val f = Fixture(); f.journal.resume(); f.coordinator().cycle(false); assertEquals(0, f.backend.grants); assertEquals(0, f.sends) }
    @Test fun healthyAllowedCycleUsesEngineAndOneDurableReservation() {
        val f = Fixture(); f.journal.resume(); assertEquals("gateway_invocation_reserved", f.coordinator().cycle().reasonCode)
        assertEquals(1, f.sends); assertEquals(1, f.backend.grants); assertEquals(1, f.journal.read().attempts.size)
    }
    @Test fun processRestartCannotInvokeAReservedAttemptAgain() {
        val f = Fixture(); f.journal.resume(); f.coordinator().cycle(); f.coordinator().cycle()
        assertEquals(1, f.sends); assertEquals(1, f.journal.read().attempts.size)
    }
    @Test fun stopOrDeadlineAfterHealthPreventsReconciliationAndDispatch() {
        for (cancel in listOf(true, false)) {
            val f = Fixture(); f.journal.resume(); f.backend.duringHealth = { if (cancel) f.token.cancel() else f.elapsed = 90_001 }
            assertEquals("gateway_cycle_stopped", f.coordinator().cycle().reasonCode); assertEquals(0, f.backend.reconcile); assertEquals(0, f.backend.grants)
        }
    }
    @Test fun cancellationDuringArmPreservesUnknownAndDoesNotInvoke() {
        val f = Fixture(); f.journal.resume(); f.backend.duringArm = { f.token.cancel() }; assertTrue(f.coordinator().cycle().backoff)
        assertEquals(0, f.sends); assertTrue(f.journal.read().attempts.single().invocationException)
    }
    @Test fun stopDuringEngineHeartbeatNeverRequestsLifetimeGrant() {
        val f = Fixture(); f.journal.resume(); var health = 0
        f.backend.duringHealth = { if (++health == 2) f.token.cancel() }
        assertTrue(f.coordinator().cycle().backoff); assertEquals(0, f.backend.grants); assertEquals(0, f.sends); assertTrue(f.journal.read().attempts.isEmpty())
    }
    @Test fun newerPauseInvalidatesOlderAllowanceEvenAfterVerificationDelay() {
        val f = Fixture(); val intents = GatewayLocalDispatchIntent(); val old = intents.generation()
        intents.pause(f.journal)
        try { f.coordinator().allowGovernedDispatch { intents.allow(old, f.journal) }; fail("Expected superseded intent") }
        catch (error: GatewayStateException) { assertEquals("gateway_local_intent_superseded", error.reasonCode) }
        assertTrue(f.journal.read().emergencyPaused); assertEquals(0, f.sends)
        f.coordinator().allowGovernedDispatch { intents.allow(intents.generation(), f.journal) }; assertFalse(f.journal.read().emergencyPaused)
    }
    @Test fun closingLifecycleInvalidatesQueuedAllowIntent() {
        val f = Fixture(); val intents = GatewayLocalDispatchIntent(); val queued = intents.generation(); intents.invalidate()
        try { intents.allow(queued, f.journal); fail("Expected lifecycle refusal") } catch (_: GatewayStateException) { }
        assertTrue(f.journal.read().emergencyPaused)
    }
    @Test fun guardedRealInvocationPortRefusesAfterLifecycleStop() {
        val f = Fixture(); var active = true; val guarded = GatewayGuardedSmsInvoker(f.sender) { active }
        val grant = f.backend.dispatchGrant(ready)!!
        val record = GatewayAttempt(device, receipt, attempt, 1, grant.bodySha256, grant.destinationSha256, grant.expiresAt.toString(), now.toString(), GatewayCrypto.nonce(), List(1) { SegmentEvidence() })
        active = false
        try { guarded.invoke(grant, record, listOf(grant.body), 1); fail("Expected stop") } catch (_: GatewayStateException) { }
        assertEquals(0, f.sends)
    }
    @Test fun stopReturnsOnlyAfterAlreadyAdmittedInvocationAndBlocksAnyLaterOne() {
        val f = Fixture(); val entered = CountDownLatch(1); val release = CountDownLatch(1)
        val delegate = object : GatewaySmsInvoker {
            override fun divide(body: String, subscriptionId: Int) = listOf(body)
            override fun invoke(grant: GatewayDispatchGrant, record: GatewayAttempt, parts: List<String>, subscriptionId: Int) {
                entered.countDown(); assertTrue(release.await(3, TimeUnit.SECONDS)); f.sends++
            }
        }
        val guarded = GatewayGuardedSmsInvoker(delegate, f.token::active)
        val grant = f.backend.dispatchGrant(ready)!!
        val record = GatewayAttempt(device, receipt, attempt, 1, grant.bodySha256, grant.destinationSha256, grant.expiresAt.toString(), now.toString(), GatewayCrypto.nonce(), List(1) { SegmentEvidence() })
        val threads = Executors.newFixedThreadPool(2)
        try {
            val invocation = threads.submit { guarded.invoke(grant, record, listOf(grant.body), 1) }; assertTrue(entered.await(3, TimeUnit.SECONDS))
            val stopping = threads.submit { f.token.cancel() }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(1)
            while (f.token.active() && System.nanoTime() < deadline) Thread.yield()
            assertFalse(f.token.active()); assertFalse(stopping.isDone)
            release.countDown(); invocation.get(3, TimeUnit.SECONDS); stopping.get(3, TimeUnit.SECONDS)
            try { guarded.invoke(grant, record, listOf(grant.body), 1); fail("Expected stopped admission") } catch (_: GatewayStateException) { }
            assertEquals(1, f.sends)
        } finally { release.countDown(); threads.shutdownNow() }
    }
    @Test fun separateThreadPauseDoesNotWaitForArmHttpAndWinsBeforeInvocation() {
        val f = Fixture(); f.journal.resume(); val entered = CountDownLatch(1); val release = CountDownLatch(1)
        f.backend.duringArm = { entered.countDown(); assertTrue(release.await(3, TimeUnit.SECONDS)) }
        val threads = Executors.newFixedThreadPool(2)
        try {
            val cycle = threads.submit<GatewayCycleResult> { f.coordinator().cycle() }; assertTrue(entered.await(3, TimeUnit.SECONDS))
            val pause = threads.submit { f.journal.pause() }; pause.get(1, TimeUnit.SECONDS)
            release.countDown(); assertTrue(cycle.get(3, TimeUnit.SECONDS).backoff)
            assertEquals(0, f.sends); assertTrue(f.journal.read().emergencyPaused); assertTrue(f.journal.read().attempts.single().invocationException)
        } finally { release.countDown(); threads.shutdownNow() }
    }
    @Test fun overlapRefusesWithoutDuplicateHealthGrantOrInvocation() {
        val f = Fixture(); val entered = CountDownLatch(1); val release = CountDownLatch(1)
        f.backend.duringHealth = { entered.countDown(); assertTrue(release.await(3, TimeUnit.SECONDS)) }
        val thread = Executors.newSingleThreadExecutor()
        try {
            val first = thread.submit<GatewayCycleResult> { f.coordinator().cycle() }; assertTrue(entered.await(3, TimeUnit.SECONDS))
            assertEquals("gateway_cycle_busy", f.coordinator().cycle().reasonCode); assertEquals(1, f.backend.health)
            release.countDown(); first.get(3, TimeUnit.SECONDS)
        } finally { release.countDown(); thread.shutdownNow() }
    }
    @Test fun boundedBackoffDoesNotGrowOrAcceptBadFailureCounters() {
        assertEquals(300_000L, GatewaySchedulePolicy.delayMillis(0)); assertEquals(120_000L, GatewaySchedulePolicy.delayMillis(1))
        assertEquals(1_800_000L, GatewaySchedulePolicy.delayMillis(Int.MAX_VALUE)); assertEquals(6, GatewaySchedulePolicy.failures(6, true))
        assertEquals(0, GatewaySchedulePolicy.failures(6, false)); assertEquals(1, GatewaySchedulePolicy.failures(-99, true))
    }
    private fun metadata() = JSONObject().put("contract_version", 1).put("installation_id", installation)
        .put("key_sha256", "a".repeat(64)).put("signing_certificate_sha256", "b".repeat(64)).put("public_key_spki_base64", "synthetic-public-key")
    private fun enrollment() = JSONObject().put("contract_version", 1).put("device_id", device).put("installation_id", installation)
        .put("key_sha256", "a".repeat(64)).put("signing_certificate_sha256", "b".repeat(64))
    @Test fun exactInstalledPublicIdentityIsRequiredNotJustAnyDocument() {
        assertEquals(device, GatewayInstalledEnrollment.verify(metadata(), enrollment(), "a".repeat(64), "synthetic-public-key", "b".repeat(64)))
        for (field in listOf("installation_id", "key_sha256", "signing_certificate_sha256")) {
            val changed = enrollment().put(field, if (field == "installation_id") receipt else "c".repeat(64))
            try { GatewayInstalledEnrollment.verify(metadata(), changed, "a".repeat(64), "synthetic-public-key", "b".repeat(64)); fail("Expected identity refusal") } catch (_: GatewayStateException) { }
        }
    }
    @Test fun missingOrExtraEnrollmentCannotClearLocalPause() {
        for (document in listOf<JSONObject?>(null, enrollment().put("endpoint", "https://arbitrary.test"))) {
            try { GatewayInstalledEnrollment.verify(metadata(), document, "a".repeat(64), "synthetic-public-key", "b".repeat(64)); fail("Expected identity refusal") } catch (_: GatewayStateException) { }
        }
    }
}
