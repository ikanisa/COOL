import { boundedJson } from "../_shared/production_contract.ts";
import {
  authErrorStatus,
  corsHeaders,
  jsonResponse,
  requireEnv,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireInternalRequest, serviceClient } from "../_shared/supabase.ts";
import {
  ApnsCredentials,
  createApnsJwt,
  sendApnsMessage,
} from "../_shared/apns.ts";
import {
  createFcmAccessToken,
  FcmCredentials,
  sendFcmMessage,
} from "../_shared/fcm.ts";
import { type ClaimedDelivery, dispatchNotifications } from "./dispatcher.ts";

function apnsCredentialsFromEnvironment(): ApnsCredentials {
  return {
    keyId: requireEnv("APNS_KEY_ID"),
    teamId: requireEnv("APNS_TEAM_ID"),
    bundleId: requireEnv("APNS_BUNDLE_ID"),
    privateKeyBase64: requireEnv("APNS_PRIVATE_KEY_BASE64"),
  };
}

function fcmCredentialsFromEnvironment(): FcmCredentials {
  return { serviceAccountJson: requireEnv("FCM_SERVICE_ACCOUNT_JSON") };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  try {
    requireInternalRequest(req);
    const rawPayload = await boundedJson(req);
    const requestedLimit = Number(
      (rawPayload as { limit?: unknown }).limit ?? 100,
    );
    const limit = Number.isFinite(requestedLimit)
      ? Math.min(500, Math.max(1, Math.trunc(requestedLimit)))
      : 100;
    const service = serviceClient();
    let apnsCredentials: ApnsCredentials | null = null;
    let apnsAuthorization: string | null = null;
    let fcmCredentials: FcmCredentials | null = null;
    let fcmAccessToken: string | null = null;
    const counts = await dispatchNotifications(limit, {
      claim: async () => {
        const { data, error } = await service.rpc(
          "claim_notification_deliveries",
          {
            p_contract_version: 2,
            p_limit: 1,
          },
        ).abortSignal(AbortSignal.timeout(8000));
        if (error) throw error;
        return ((data ?? []) as ClaimedDelivery[])[0] ?? null;
      },
      isCurrent: async (delivery) => {
        const validation = await service.rpc(
          "notification_delivery_is_current",
          {
            p_delivery_id: delivery.delivery_id,
            p_claim_token: delivery.claim_token,
            p_attempt_number: delivery.attempt_number,
          },
        ).abortSignal(AbortSignal.timeout(8000));
        if (validation.error) throw validation.error;
        return validation.data === true;
      },
      send: async (delivery) => {
        return delivery.provider === "apns"
          ? await (async () => {
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
              deepLink: delivery.deep_link,
            });
          })()
          : await (async () => {
            fcmCredentials ??= fcmCredentialsFromEnvironment();
            fcmAccessToken ??= await createFcmAccessToken(fcmCredentials);
            return await sendFcmMessage(fcmCredentials, fcmAccessToken, {
              token: delivery.token,
              title: delivery.title,
              body: delivery.body,
              recipientId: delivery.user_id,
              eventId: delivery.event_id,
              eventType: delivery.event_type,
              deepLink: delivery.deep_link,
            });
          })();
      },
      complete: async (delivery, result) => {
        const completion = await service.rpc("complete_notification_delivery", {
          p_delivery_id: delivery.delivery_id,
          p_claim_token: delivery.claim_token,
          p_attempt_number: delivery.attempt_number,
          p_success: result.ok,
          p_retryable: result.retryable,
          p_provider_message_id: result.messageId,
          p_error_code: result.errorCode,
          p_latency_ms: result.latencyMs,
          p_retry_after_seconds: result.retryAfterSeconds ?? null,
        }).abortSignal(AbortSignal.timeout(8000));
        if (completion.error) throw completion.error;
      },
    });

    return jsonResponse({
      ok: counts.completion_pending === 0 && counts.lease_lost === 0,
      ...counts,
    }, counts.completion_pending > 0 || counts.lease_lost > 0 ? 503 : 200);
  } catch (error) {
    const authStatus = authErrorStatus(error);
    if (authStatus) {
      return jsonResponse({ error: safeErrorMessage(error) }, authStatus);
    }
    return jsonResponse({ error: safeErrorMessage(error) }, 500);
  }
});
