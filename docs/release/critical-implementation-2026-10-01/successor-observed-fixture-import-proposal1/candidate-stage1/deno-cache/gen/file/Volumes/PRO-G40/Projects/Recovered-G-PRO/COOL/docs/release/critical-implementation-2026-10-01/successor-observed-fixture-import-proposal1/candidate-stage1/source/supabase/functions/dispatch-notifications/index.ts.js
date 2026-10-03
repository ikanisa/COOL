import { boundedJson } from "../_shared/production_contract.ts";
import { authErrorStatus, corsHeaders, jsonResponse, requireEnv, safeErrorMessage } from "../_shared/cors.ts";
import { requireInternalRequest, serviceClient } from "../_shared/supabase.ts";
import { createApnsJwt, sendApnsMessage } from "../_shared/apns.ts";
import { createFcmAccessToken, sendFcmMessage } from "../_shared/fcm.ts";
import { dispatchNotifications } from "./dispatcher.ts";
function apnsCredentialsFromEnvironment() {
  return {
    keyId: requireEnv("APNS_KEY_ID"),
    teamId: requireEnv("APNS_TEAM_ID"),
    bundleId: requireEnv("APNS_BUNDLE_ID"),
    privateKeyBase64: requireEnv("APNS_PRIVATE_KEY_BASE64")
  };
}
function fcmCredentialsFromEnvironment() {
  return {
    serviceAccountJson: requireEnv("FCM_SERVICE_ACCOUNT_JSON")
  };
}
Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }
  if (req.method !== "POST") {
    return jsonResponse({
      error: "Method not allowed"
    }, 405);
  }
  try {
    requireInternalRequest(req);
    const rawPayload = await boundedJson(req);
    const requestedLimit = Number(rawPayload.limit ?? 100);
    const limit = Number.isFinite(requestedLimit) ? Math.min(500, Math.max(1, Math.trunc(requestedLimit))) : 100;
    const service = serviceClient();
    let apnsCredentials = null;
    let apnsAuthorization = null;
    let fcmCredentials = null;
    let fcmAccessToken = null;
    const counts = await dispatchNotifications(limit, {
      claim: async ()=>{
        const { data, error } = await service.rpc("claim_notification_deliveries", {
          p_contract_version: 2,
          p_limit: 1
        }).abortSignal(AbortSignal.timeout(8000));
        if (error) throw error;
        return (data ?? [])[0] ?? null;
      },
      isCurrent: async (delivery)=>{
        const validation = await service.rpc("notification_delivery_is_current", {
          p_delivery_id: delivery.delivery_id,
          p_claim_token: delivery.claim_token,
          p_attempt_number: delivery.attempt_number
        }).abortSignal(AbortSignal.timeout(8000));
        if (validation.error) throw validation.error;
        return validation.data === true;
      },
      send: async (delivery)=>{
        return delivery.provider === "apns" ? await (async ()=>{
          apnsCredentials ??= apnsCredentialsFromEnvironment();
          apnsAuthorization ??= await createApnsJwt(apnsCredentials);
          return await sendApnsMessage(apnsCredentials, apnsAuthorization, {
            token: delivery.token,
            environment: delivery.environment,
            title: delivery.title,
            body: delivery.body,
            recipientId: delivery.user_id,
            eventId: delivery.event_id,
            eventType: delivery.event_type,
            deepLink: delivery.deep_link
          });
        })() : await (async ()=>{
          fcmCredentials ??= fcmCredentialsFromEnvironment();
          fcmAccessToken ??= await createFcmAccessToken(fcmCredentials);
          return await sendFcmMessage(fcmCredentials, fcmAccessToken, {
            token: delivery.token,
            title: delivery.title,
            body: delivery.body,
            recipientId: delivery.user_id,
            eventId: delivery.event_id,
            eventType: delivery.event_type,
            deepLink: delivery.deep_link
          });
        })();
      },
      complete: async (delivery, result)=>{
        const completion = await service.rpc("complete_notification_delivery", {
          p_delivery_id: delivery.delivery_id,
          p_claim_token: delivery.claim_token,
          p_attempt_number: delivery.attempt_number,
          p_success: result.ok,
          p_retryable: result.retryable,
          p_provider_message_id: result.messageId,
          p_error_code: result.errorCode,
          p_latency_ms: result.latencyMs,
          p_retry_after_seconds: result.retryAfterSeconds ?? null
        }).abortSignal(AbortSignal.timeout(8000));
        if (completion.error) throw completion.error;
      }
    });
    return jsonResponse({
      ok: counts.completion_pending === 0 && counts.lease_lost === 0,
      ...counts
    }, counts.completion_pending > 0 || counts.lease_lost > 0 ? 503 : 200);
  } catch (error) {
    const authStatus = authErrorStatus(error);
    if (authStatus) {
      return jsonResponse({
        error: safeErrorMessage(error)
      }, authStatus);
    }
    return jsonResponse({
      error: safeErrorMessage(error)
    }, 500);
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2Rpc3BhdGNoLW5vdGlmaWNhdGlvbnMvaW5kZXgudHMiXSwic291cmNlc0NvbnRlbnQiOlsiaW1wb3J0IHsgYm91bmRlZEpzb24gfSBmcm9tIFwiLi4vX3NoYXJlZC9wcm9kdWN0aW9uX2NvbnRyYWN0LnRzXCI7XG5pbXBvcnQge1xuICBhdXRoRXJyb3JTdGF0dXMsXG4gIGNvcnNIZWFkZXJzLFxuICBqc29uUmVzcG9uc2UsXG4gIHJlcXVpcmVFbnYsXG4gIHNhZmVFcnJvck1lc3NhZ2UsXG59IGZyb20gXCIuLi9fc2hhcmVkL2NvcnMudHNcIjtcbmltcG9ydCB7IHJlcXVpcmVJbnRlcm5hbFJlcXVlc3QsIHNlcnZpY2VDbGllbnQgfSBmcm9tIFwiLi4vX3NoYXJlZC9zdXBhYmFzZS50c1wiO1xuaW1wb3J0IHtcbiAgQXBuc0NyZWRlbnRpYWxzLFxuICBjcmVhdGVBcG5zSnd0LFxuICBzZW5kQXBuc01lc3NhZ2UsXG59IGZyb20gXCIuLi9fc2hhcmVkL2FwbnMudHNcIjtcbmltcG9ydCB7XG4gIGNyZWF0ZUZjbUFjY2Vzc1Rva2VuLFxuICBGY21DcmVkZW50aWFscyxcbiAgc2VuZEZjbU1lc3NhZ2UsXG59IGZyb20gXCIuLi9fc2hhcmVkL2ZjbS50c1wiO1xuaW1wb3J0IHsgdHlwZSBDbGFpbWVkRGVsaXZlcnksIGRpc3BhdGNoTm90aWZpY2F0aW9ucyB9IGZyb20gXCIuL2Rpc3BhdGNoZXIudHNcIjtcblxuZnVuY3Rpb24gYXBuc0NyZWRlbnRpYWxzRnJvbUVudmlyb25tZW50KCk6IEFwbnNDcmVkZW50aWFscyB7XG4gIHJldHVybiB7XG4gICAga2V5SWQ6IHJlcXVpcmVFbnYoXCJBUE5TX0tFWV9JRFwiKSxcbiAgICB0ZWFtSWQ6IHJlcXVpcmVFbnYoXCJBUE5TX1RFQU1fSURcIiksXG4gICAgYnVuZGxlSWQ6IHJlcXVpcmVFbnYoXCJBUE5TX0JVTkRMRV9JRFwiKSxcbiAgICBwcml2YXRlS2V5QmFzZTY0OiByZXF1aXJlRW52KFwiQVBOU19QUklWQVRFX0tFWV9CQVNFNjRcIiksXG4gIH07XG59XG5cbmZ1bmN0aW9uIGZjbUNyZWRlbnRpYWxzRnJvbUVudmlyb25tZW50KCk6IEZjbUNyZWRlbnRpYWxzIHtcbiAgcmV0dXJuIHsgc2VydmljZUFjY291bnRKc29uOiByZXF1aXJlRW52KFwiRkNNX1NFUlZJQ0VfQUNDT1VOVF9KU09OXCIpIH07XG59XG5cbkRlbm8uc2VydmUoYXN5bmMgKHJlcSkgPT4ge1xuICBpZiAocmVxLm1ldGhvZCA9PT0gXCJPUFRJT05TXCIpIHtcbiAgICByZXR1cm4gbmV3IFJlc3BvbnNlKFwib2tcIiwgeyBoZWFkZXJzOiBjb3JzSGVhZGVycyB9KTtcbiAgfVxuICBpZiAocmVxLm1ldGhvZCAhPT0gXCJQT1NUXCIpIHtcbiAgICByZXR1cm4ganNvblJlc3BvbnNlKHsgZXJyb3I6IFwiTWV0aG9kIG5vdCBhbGxvd2VkXCIgfSwgNDA1KTtcbiAgfVxuICB0cnkge1xuICAgIHJlcXVpcmVJbnRlcm5hbFJlcXVlc3QocmVxKTtcbiAgICBjb25zdCByYXdQYXlsb2FkID0gYXdhaXQgYm91bmRlZEpzb24ocmVxKTtcbiAgICBjb25zdCByZXF1ZXN0ZWRMaW1pdCA9IE51bWJlcihcbiAgICAgIChyYXdQYXlsb2FkIGFzIHsgbGltaXQ/OiB1bmtub3duIH0pLmxpbWl0ID8/IDEwMCxcbiAgICApO1xuICAgIGNvbnN0IGxpbWl0ID0gTnVtYmVyLmlzRmluaXRlKHJlcXVlc3RlZExpbWl0KVxuICAgICAgPyBNYXRoLm1pbig1MDAsIE1hdGgubWF4KDEsIE1hdGgudHJ1bmMocmVxdWVzdGVkTGltaXQpKSlcbiAgICAgIDogMTAwO1xuICAgIGNvbnN0IHNlcnZpY2UgPSBzZXJ2aWNlQ2xpZW50KCk7XG4gICAgbGV0IGFwbnNDcmVkZW50aWFsczogQXBuc0NyZWRlbnRpYWxzIHwgbnVsbCA9IG51bGw7XG4gICAgbGV0IGFwbnNBdXRob3JpemF0aW9uOiBzdHJpbmcgfCBudWxsID0gbnVsbDtcbiAgICBsZXQgZmNtQ3JlZGVudGlhbHM6IEZjbUNyZWRlbnRpYWxzIHwgbnVsbCA9IG51bGw7XG4gICAgbGV0IGZjbUFjY2Vzc1Rva2VuOiBzdHJpbmcgfCBudWxsID0gbnVsbDtcbiAgICBjb25zdCBjb3VudHMgPSBhd2FpdCBkaXNwYXRjaE5vdGlmaWNhdGlvbnMobGltaXQsIHtcbiAgICAgIGNsYWltOiBhc3luYyAoKSA9PiB7XG4gICAgICAgIGNvbnN0IHsgZGF0YSwgZXJyb3IgfSA9IGF3YWl0IHNlcnZpY2UucnBjKFxuICAgICAgICAgIFwiY2xhaW1fbm90aWZpY2F0aW9uX2RlbGl2ZXJpZXNcIixcbiAgICAgICAgICB7XG4gICAgICAgICAgICBwX2NvbnRyYWN0X3ZlcnNpb246IDIsXG4gICAgICAgICAgICBwX2xpbWl0OiAxLFxuICAgICAgICAgIH0sXG4gICAgICAgICkuYWJvcnRTaWduYWwoQWJvcnRTaWduYWwudGltZW91dCg4MDAwKSk7XG4gICAgICAgIGlmIChlcnJvcikgdGhyb3cgZXJyb3I7XG4gICAgICAgIHJldHVybiAoKGRhdGEgPz8gW10pIGFzIENsYWltZWREZWxpdmVyeVtdKVswXSA/PyBudWxsO1xuICAgICAgfSxcbiAgICAgIGlzQ3VycmVudDogYXN5bmMgKGRlbGl2ZXJ5KSA9PiB7XG4gICAgICAgIGNvbnN0IHZhbGlkYXRpb24gPSBhd2FpdCBzZXJ2aWNlLnJwYyhcbiAgICAgICAgICBcIm5vdGlmaWNhdGlvbl9kZWxpdmVyeV9pc19jdXJyZW50XCIsXG4gICAgICAgICAge1xuICAgICAgICAgICAgcF9kZWxpdmVyeV9pZDogZGVsaXZlcnkuZGVsaXZlcnlfaWQsXG4gICAgICAgICAgICBwX2NsYWltX3Rva2VuOiBkZWxpdmVyeS5jbGFpbV90b2tlbixcbiAgICAgICAgICAgIHBfYXR0ZW1wdF9udW1iZXI6IGRlbGl2ZXJ5LmF0dGVtcHRfbnVtYmVyLFxuICAgICAgICAgIH0sXG4gICAgICAgICkuYWJvcnRTaWduYWwoQWJvcnRTaWduYWwudGltZW91dCg4MDAwKSk7XG4gICAgICAgIGlmICh2YWxpZGF0aW9uLmVycm9yKSB0aHJvdyB2YWxpZGF0aW9uLmVycm9yO1xuICAgICAgICByZXR1cm4gdmFsaWRhdGlvbi5kYXRhID09PSB0cnVlO1xuICAgICAgfSxcbiAgICAgIHNlbmQ6IGFzeW5jIChkZWxpdmVyeSkgPT4ge1xuICAgICAgICByZXR1cm4gZGVsaXZlcnkucHJvdmlkZXIgPT09IFwiYXBuc1wiXG4gICAgICAgICAgPyBhd2FpdCAoYXN5bmMgKCkgPT4ge1xuICAgICAgICAgICAgYXBuc0NyZWRlbnRpYWxzID8/PSBhcG5zQ3JlZGVudGlhbHNGcm9tRW52aXJvbm1lbnQoKTtcbiAgICAgICAgICAgIGFwbnNBdXRob3JpemF0aW9uID8/PSBhd2FpdCBjcmVhdGVBcG5zSnd0KGFwbnNDcmVkZW50aWFscyk7XG4gICAgICAgICAgICByZXR1cm4gYXdhaXQgc2VuZEFwbnNNZXNzYWdlKGFwbnNDcmVkZW50aWFscywgYXBuc0F1dGhvcml6YXRpb24sIHtcbiAgICAgICAgICAgICAgdG9rZW46IGRlbGl2ZXJ5LnRva2VuLFxuICAgICAgICAgICAgICBlbnZpcm9ubWVudDogZGVsaXZlcnkuZW52aXJvbm1lbnQsXG4gICAgICAgICAgICAgIHRpdGxlOiBkZWxpdmVyeS50aXRsZSxcbiAgICAgICAgICAgICAgYm9keTogZGVsaXZlcnkuYm9keSxcbiAgICAgICAgICAgICAgcmVjaXBpZW50SWQ6IGRlbGl2ZXJ5LnVzZXJfaWQsXG4gICAgICAgICAgICAgIGV2ZW50SWQ6IGRlbGl2ZXJ5LmV2ZW50X2lkLFxuICAgICAgICAgICAgICBldmVudFR5cGU6IGRlbGl2ZXJ5LmV2ZW50X3R5cGUsXG4gICAgICAgICAgICAgIGRlZXBMaW5rOiBkZWxpdmVyeS5kZWVwX2xpbmssXG4gICAgICAgICAgICB9KTtcbiAgICAgICAgICB9KSgpXG4gICAgICAgICAgOiBhd2FpdCAoYXN5bmMgKCkgPT4ge1xuICAgICAgICAgICAgZmNtQ3JlZGVudGlhbHMgPz89IGZjbUNyZWRlbnRpYWxzRnJvbUVudmlyb25tZW50KCk7XG4gICAgICAgICAgICBmY21BY2Nlc3NUb2tlbiA/Pz0gYXdhaXQgY3JlYXRlRmNtQWNjZXNzVG9rZW4oZmNtQ3JlZGVudGlhbHMpO1xuICAgICAgICAgICAgcmV0dXJuIGF3YWl0IHNlbmRGY21NZXNzYWdlKGZjbUNyZWRlbnRpYWxzLCBmY21BY2Nlc3NUb2tlbiwge1xuICAgICAgICAgICAgICB0b2tlbjogZGVsaXZlcnkudG9rZW4sXG4gICAgICAgICAgICAgIHRpdGxlOiBkZWxpdmVyeS50aXRsZSxcbiAgICAgICAgICAgICAgYm9keTogZGVsaXZlcnkuYm9keSxcbiAgICAgICAgICAgICAgcmVjaXBpZW50SWQ6IGRlbGl2ZXJ5LnVzZXJfaWQsXG4gICAgICAgICAgICAgIGV2ZW50SWQ6IGRlbGl2ZXJ5LmV2ZW50X2lkLFxuICAgICAgICAgICAgICBldmVudFR5cGU6IGRlbGl2ZXJ5LmV2ZW50X3R5cGUsXG4gICAgICAgICAgICAgIGRlZXBMaW5rOiBkZWxpdmVyeS5kZWVwX2xpbmssXG4gICAgICAgICAgICB9KTtcbiAgICAgICAgICB9KSgpO1xuICAgICAgfSxcbiAgICAgIGNvbXBsZXRlOiBhc3luYyAoZGVsaXZlcnksIHJlc3VsdCkgPT4ge1xuICAgICAgICBjb25zdCBjb21wbGV0aW9uID0gYXdhaXQgc2VydmljZS5ycGMoXCJjb21wbGV0ZV9ub3RpZmljYXRpb25fZGVsaXZlcnlcIiwge1xuICAgICAgICAgIHBfZGVsaXZlcnlfaWQ6IGRlbGl2ZXJ5LmRlbGl2ZXJ5X2lkLFxuICAgICAgICAgIHBfY2xhaW1fdG9rZW46IGRlbGl2ZXJ5LmNsYWltX3Rva2VuLFxuICAgICAgICAgIHBfYXR0ZW1wdF9udW1iZXI6IGRlbGl2ZXJ5LmF0dGVtcHRfbnVtYmVyLFxuICAgICAgICAgIHBfc3VjY2VzczogcmVzdWx0Lm9rLFxuICAgICAgICAgIHBfcmV0cnlhYmxlOiByZXN1bHQucmV0cnlhYmxlLFxuICAgICAgICAgIHBfcHJvdmlkZXJfbWVzc2FnZV9pZDogcmVzdWx0Lm1lc3NhZ2VJZCxcbiAgICAgICAgICBwX2Vycm9yX2NvZGU6IHJlc3VsdC5lcnJvckNvZGUsXG4gICAgICAgICAgcF9sYXRlbmN5X21zOiByZXN1bHQubGF0ZW5jeU1zLFxuICAgICAgICAgIHBfcmV0cnlfYWZ0ZXJfc2Vjb25kczogcmVzdWx0LnJldHJ5QWZ0ZXJTZWNvbmRzID8/IG51bGwsXG4gICAgICAgIH0pLmFib3J0U2lnbmFsKEFib3J0U2lnbmFsLnRpbWVvdXQoODAwMCkpO1xuICAgICAgICBpZiAoY29tcGxldGlvbi5lcnJvcikgdGhyb3cgY29tcGxldGlvbi5lcnJvcjtcbiAgICAgIH0sXG4gICAgfSk7XG5cbiAgICByZXR1cm4ganNvblJlc3BvbnNlKHtcbiAgICAgIG9rOiBjb3VudHMuY29tcGxldGlvbl9wZW5kaW5nID09PSAwICYmIGNvdW50cy5sZWFzZV9sb3N0ID09PSAwLFxuICAgICAgLi4uY291bnRzLFxuICAgIH0sIGNvdW50cy5jb21wbGV0aW9uX3BlbmRpbmcgPiAwIHx8IGNvdW50cy5sZWFzZV9sb3N0ID4gMCA/IDUwMyA6IDIwMCk7XG4gIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgY29uc3QgYXV0aFN0YXR1cyA9IGF1dGhFcnJvclN0YXR1cyhlcnJvcik7XG4gICAgaWYgKGF1dGhTdGF0dXMpIHtcbiAgICAgIHJldHVybiBqc29uUmVzcG9uc2UoeyBlcnJvcjogc2FmZUVycm9yTWVzc2FnZShlcnJvcikgfSwgYXV0aFN0YXR1cyk7XG4gICAgfVxuICAgIHJldHVybiBqc29uUmVzcG9uc2UoeyBlcnJvcjogc2FmZUVycm9yTWVzc2FnZShlcnJvcikgfSwgNTAwKTtcbiAgfVxufSk7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
// denoCacheMetadata=6321113176663450186,10181978538420989903