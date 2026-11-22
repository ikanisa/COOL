package app.cool.mobile.receiver_sms

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class MomoGatewayRowEligibilityTest {
    private fun binding() = JSONObject().put("id", "binding-1").put("version", 1)
    private fun row() = JSONObject().put("id", "source-1").put("gateway_binding_id", "binding-1")
        .put("gateway_binding_version", 1).put("source_unresolved", false).put("source_mode", "live")
        .put("complete", true).put("raw_sender", "M-Money")
        .put("raw_body", "You received 500 RWF, transaction 123")

    @Test fun heldRowsStayUnchangedAndCannotBeReportedAsUploadable() {
        val source = row().put("source_mode", "catch_up") // Includes legacy complete=true rows.
        val before = source.toString()
        assertFalse(gatewayUploadEligible(source, binding(), JSONObject()))
        assertEquals(before, source.toString())
        assertFalse(gatewayUploadEligible(row().put("complete", false), binding(), JSONObject()))
        assertFalse(gatewayUploadEligible(row().put("complete", "true"), binding(), JSONObject()))
        assertFalse(gatewayUploadEligible(row().removeField("complete"), binding(), JSONObject()))
        assertFalse(gatewayUploadEligible(row().put("source_unresolved", true), binding(), JSONObject()))
        assertFalse(gatewayUploadEligible(row().put("source_unresolved", "false"), binding(), JSONObject()))
        assertFalse(gatewaySourceResolved(row().put("source_unresolved", "false"), binding()))
        assertFalse(gatewayUploadEligible(row().put("gateway_binding_version", "1"), binding(), JSONObject()))
        assertFalse(gatewayUploadEligible(row().put("gateway_binding_version", 1.1), binding(), JSONObject()))
        assertFalse(gatewaySourceResolved(row().put("gateway_binding_version", "1"), binding()))
        assertFalse(gatewaySourceResolved(row().put("gateway_binding_version", 0), binding().put("version", 0)))
    }

    @Test fun evenValidLiveRowsRemainHeldAndMalformedCasesStayUnavailable() {
        val source = row()
        assertTrue(gatewaySourceResolved(source, binding()))
        assertFalse(gatewaySourceResolved(source, binding().put("version", 2)))
        assertFalse(gatewaySourceResolved(row().put("gateway_binding_version", 1.1), binding()))
        assertFalse(JSONObject().sourceParked("source-1"))
        assertTrue(JSONObject().put("source-1", "malformed").sourceParked("source-1"))
        assertTrue(JSONObject().put("source-1", JSONObject().put("parked", "false")).sourceParked("source-1"))
        assertTrue(JSONObject().put("source-1", JSONObject().put("parked", true)).sourceParked("source-1"))
        assertFalse(JSONObject().put("source-1", JSONObject().put("parked", false)).sourceParked("source-1"))
        assertFalse(gatewayUploadEligible(source, binding(), JSONObject()))
        assertFalse(gatewayUploadEligible(source, binding().put("version", 2), JSONObject()))
        assertFalse(gatewayUploadEligible(source, binding(), JSONObject().put("source-1", JSONObject().put("parked", true))))
        assertFalse(gatewayUploadEligible(source, binding(), JSONObject().put("source-1", "malformed")))
        assertFalse(gatewayUploadEligible(source, binding(), JSONObject().put("source-1", JSONObject().put("parked", "false"))))
        assertFalse(gatewayUploadEligible(source, binding(), JSONObject().put("source-1", JSONObject().put("parked", false))))
        assertFalse(gatewayUploadEligible(source, binding(), gatewaySourceCases(JSONObject())))
        for (invalid in listOf("malformed", 4, JSONObject.NULL)) {
            val invalidCases = gatewaySourceCases(JSONObject().put("source_cases", invalid))
            assertNull(invalidCases)
            assertFalse(gatewayUploadEligible(source, binding(), invalidCases))
        }
        assertFalse(gatewayUploadEligible(row().put("raw_body", "Your login code is 123456; reference 42"), binding(), JSONObject()))
    }

    @Test fun inFlightFailureCannotReplaceMalformedSourceCaseData() {
        val invalidStates = listOf(
            JSONObject().put("source_cases", "malformed"),
            JSONObject().put("source_cases", JSONObject().put("source-1", "malformed")),
        )
        for (state in invalidStates) {
            val before = state.toString()
            try {
                gatewayCasesWithParkedSource(state, "source-1", 409, "capture_conflict", "2026-11-02T00:00:00Z")
                fail("Malformed source case must not be replaced")
            } catch (_: IllegalStateException) { }
            assertEquals(before, state.toString())
        }
        val parked = gatewayCasesWithParkedSource(JSONObject(), "source-1", 409, "capture_conflict", "2026-11-02T00:00:00Z")
        assertTrue(parked.sourceParked("source-1"))
        assertEquals("capture_conflict", parked.getJSONObject("source-1").getString("first_reason"))
    }

    @Test fun ingestHoldIsEnforcedBeforeAnyConnectionCanOpen() {
        var opened = false
        val http = MomoGatewayHttp {
            opened = true
            throw AssertionError("Network must not be reached")
        }
        try {
            http.request("ingest", "test-token", JSONObject().put("raw_body", "fixture"))
            fail("Gateway upload hold must reject ingest")
        } catch (_: IllegalStateException) { }
        assertFalse(opened)
    }

    private fun JSONObject.removeField(key: String): JSONObject = apply { remove(key) }
}
