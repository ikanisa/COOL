package app.cool.mobile.gateway

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class GatewayWireTest {
    private val id = "00000000-0000-0000-0000-000000000001"
    private val device = "00000000-0000-0000-0000-000000000002"
    private val timestamp = "2026-09-30T21:00:00Z"
    private fun heartbeat() = JSONObject().put("observation_id", id).put("ingested_at", timestamp).put("replay", false).put("carrier_proof", false)
    private fun reject(action: String = "heartbeat", payload: JSONObject = JSONObject(), result: JSONObject) {
        try { validateGatewayResult(action, id, device, payload, result); fail("Expected invalid response") }
        catch (_: GatewayStateException) { }
    }
    @Test fun exactHeartbeatAcknowledgesOnlyKeyPossessionObservation() {
        validateGatewayResult("heartbeat", id, device, JSONObject(), heartbeat())
    }
    @Test fun addedContentOrInventedAuthorityIsRejected() {
        reject(result=heartbeat().put("destination", "+250788000101"))
        reject(result=heartbeat().put("dispatch_enabled", true))
        reject(result=heartbeat().put("carrier_proof", true))
    }
    @Test fun malformedTypesAreNeverCoerced() {
        reject(result=heartbeat().put("replay", "true"))
        reject(result=heartbeat().put("observation_id", 1))
        reject(result=heartbeat().put("ingested_at", 1))
        reject(result=heartbeat().put("carrier_proof", 0))
    }
    @Test fun nonUtcOrInvalidTimestampIsRejected() {
        reject(result=heartbeat().put("ingested_at", "2026-09-30T21:00:00+00:00"))
        reject(result=heartbeat().put("ingested_at", "invalidZ"))
        reject(result=heartbeat().put("ingested_at", "2026-09-30T21:00:00.123456789Z"))
    }
    @Test fun nativeNanosecondClocksAreNormalizedToTheSixDigitMaximumWireContract() {
        assertEquals("2026-09-30T21:00:00.123Z",gatewayWireTime(Instant.parse("2026-09-30T21:00:00.123456789Z")))
        assertEquals(timestamp,gatewayWireTime(Instant.parse(timestamp)))
    }
    @Test fun callbackAcknowledgmentMustMatchStableCallbackId() {
        val payload=JSONObject().put("callback_id", id)
        val result=JSONObject().put("callback_id", id).put("recorded_at", timestamp).put("replay", true).put("carrier_proof", false)
        validateGatewayResult("callback", id, device, payload, result)
        reject("callback",payload,result.put("callback_id",device))
    }
    @Test fun grantRefusalCannotBecomeADataDrivenSendGrant() {
        val result=JSONObject().put("ok",false).put("code","GATEWAY_DISPATCH_AUTHORITY_PENDING")
            .put("device_id",device).put("request_id",id).put("replay",false)
        validateGatewayResult("dispatch_grant", id, device, JSONObject(), result)
        reject("dispatch_grant",result=result.put("ok",true))
        reject("dispatch_grant",result=result.put("ok",false).put("body","synthetic"))
    }
    @Test fun refusalRequiresExactDeviceAndRequestBinding() {
        val result=JSONObject().put("ok",false).put("code","GATEWAY_DISPATCH_AUTHORITY_PENDING")
            .put("device_id",id).put("request_id",id).put("replay",false)
        reject("dispatch_grant",result=result)
        reject("dispatch_grant",result=result.put("device_id",device).put("request_id",device))
    }
    @Test fun unknownReconciliationCarriesNoUnverifiedResult() {
        val payload=JSONObject().put("target_request_id",id)
        val result=JSONObject().put("target_request_id",id).put("outcome","unknown")
            .put("recorded_action",JSONObject.NULL).put("recorded_result",JSONObject.NULL)
        validateGatewayResult("reconcile",id,device,payload,result)
        reject("reconcile",payload,result.put("recorded_action","heartbeat"))
    }
    @Test fun recordedReconciliationCannotInventAnActionOrPrivateField() {
        val payload=JSONObject().put("target_request_id",id)
        val result=JSONObject().put("target_request_id",id).put("outcome","recorded")
            .put("recorded_action","send_sms").put("recorded_result",heartbeat())
        reject("reconcile",payload,result)
        reject("reconcile",payload,result.put("recorded_action","heartbeat").put("raw_sms","forbidden"))
    }
    @Test fun integerParserRejectsFractionalAndStringValues() {
        assertEquals(1L,strictInteger(JSONObject().put("fence",1),"fence"))
        for (bad in listOf<Any>(1.0,"1",true)) {
            try { strictInteger(JSONObject().put("fence",bad),"fence"); fail("Expected exact integer") }
            catch (_: GatewayStateException) { }
        }
    }
}
