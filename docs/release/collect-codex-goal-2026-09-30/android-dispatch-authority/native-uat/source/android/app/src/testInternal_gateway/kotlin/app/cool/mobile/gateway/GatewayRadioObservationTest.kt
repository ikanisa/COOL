package app.cool.mobile.gateway

import org.junit.Assert.*
import org.junit.Test

class GatewayRadioObservationTest {
    @Test fun registrationStartsUnknownAndCurrentCallbackEstablishesReadiness() {
        val state = GatewayRadioObservation()
        val first = state.read(1, 100)
        assertTrue(first.registrationRequired)
        assertFalse(first.inService)
        assertTrue(state.accept(first.token, true, 110))
        val next = state.read(1, 120)
        assertFalse(next.registrationRequired)
        assertTrue(next.inService)
    }
    @Test fun switchedSubscriptionRefusesLateOldRadioState() {
        val state = GatewayRadioObservation()
        val old = state.read(1, 100).token
        state.accept(old, true, 110)
        val current = state.read(2, 120)
        assertFalse(current.inService)
        assertFalse(state.accept(old, true, 130))
        assertFalse(state.read(2, 140).inService)
        assertTrue(state.accept(current.token, true, 150))
        assertTrue(state.read(2, 160).inService)
    }
    @Test fun returningToSameSubscriptionDoesNotResurrectDepartedCallback() {
        val state = GatewayRadioObservation()
        val departed = state.read(1, 100).token
        state.read(2, 110)
        val current = state.read(1, 120)
        assertFalse(state.accept(departed, true, 130))
        assertFalse(current.inService)
        assertTrue(state.accept(current.token, true, 140))
    }
    @Test fun expiredRadioEvidenceRequiresFreshRegistration() {
        val state = GatewayRadioObservation()
        val old = state.read(1, 0).token
        state.accept(old, true, 100)
        assertTrue(state.read(1, 5_100).inService)
        val expired = state.read(1, 5_101)
        assertTrue(expired.registrationRequired)
        assertFalse(expired.inService)
        assertFalse(state.accept(old, true, 5_102))
    }
    @Test fun permissionDepartureAndCloseClearEveryOldObservation() {
        val state = GatewayRadioObservation()
        val old = state.read(1, 100).token
        state.accept(old, true, 110)
        state.clear()
        assertFalse(state.accept(old, true, 120))
        assertFalse(state.read(1, 130).inService)
    }
    @Test fun clockRollbackDoesNotTurnFutureStateIntoCurrentReadiness() {
        val state = GatewayRadioObservation()
        val old = state.read(1, 1_000).token
        state.accept(old, true, 1_010)
        val rolled = state.read(1, 100)
        assertTrue(rolled.registrationRequired)
        assertFalse(rolled.inService)
        assertFalse(state.accept(old, true, 110))
        assertFalse(state.accept(rolled.token, true, 99))
    }
    @Test fun outOfServiceCallbackClearsKnownReadiness() {
        val state = GatewayRadioObservation()
        val token = state.read(1, 100).token
        state.accept(token, true, 110)
        assertTrue(state.read(1, 120).inService)
        state.accept(token, false, 130)
        assertFalse(state.read(1, 140).inService)
    }
    @Test fun missingInitialCallbackTimesOutAndOldRegistrationCannotReply() {
        val state = GatewayRadioObservation()
        val old = state.read(1, 100).token
        assertFalse(state.read(1, 5_100).registrationRequired)
        val retry = state.read(1, 5_101)
        assertTrue(retry.registrationRequired)
        assertFalse(state.accept(old, true, 5_102))
        assertTrue(state.accept(retry.token, true, 5_103))
    }
    @Test fun invalidAndDefaultSentinelSubscriptionsNeverEnterTheGate() {
        for (id in listOf(-1, Int.MAX_VALUE)) {
            try { GatewayRadioObservation().read(id, 0); fail("Expected invalid subscription refusal") }
            catch (_: IllegalArgumentException) { }
        }
    }
}
