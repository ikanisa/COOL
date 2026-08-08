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

type ClaimedDelivery = {
  delivery_id: string;
  event_id: string;
  device_id: string;
  token: string;
  provider: "apns" | "fcm";
  environment: "sandbox" | "production";
  title: string;
  body: string;
  deep_link: string | null;
  event_type: string;
  attempt_number: number;
};

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
    const rawPayload = await req.json().catch(() => ({}));
    const requestedLimit = Number(
      (rawPayload as { limit?: unknown }).limit ?? 100,
    );
    const limit = Number.isFinite(requestedLimit)
      ? Math.min(500, Math.max(1, Math.trunc(requestedLimit)))
      : 100;
    const service = serviceClient();
    const { data, error } = await service.rpc("claim_notification_deliveries", {
      p_limit: limit,
    });
    if (error) throw error;
    const deliveries = (data ?? []) as ClaimedDelivery[];
    let apnsCredentials: ApnsCredentials | null = null;
    let apnsAuthorization: string | null = null;
    let fcmCredentials: FcmCredentials | null = null;
    let fcmAccessToken: string | null = null;
    let sent = 0;
    let retrying = 0;
    let failed = 0;

    for (const delivery of deliveries) {
      try {
        const result = delivery.provider === "apns"
          ? await (async () => {
            apnsCredentials ??= apnsCredentialsFromEnvironment();
            apnsAuthorization ??= await createApnsJwt(apnsCredentials);
            return await sendApnsMessage(apnsCredentials, apnsAuthorization, {
              token: delivery.token,
              environment: delivery.environment,
              title: delivery.title,
              body: delivery.body,
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
              eventId: delivery.event_id,
              eventType: delivery.event_type,
              deepLink: delivery.deep_link,
            });
          })();
        const completion = await service.rpc("complete_notification_delivery", {
          p_delivery_id: delivery.delivery_id,
          p_success: result.ok,
          p_retryable: result.retryable,
          p_provider_message_id: result.messageId,
          p_error_code: result.errorCode,
          p_latency_ms: result.latencyMs,
        });
        if (completion.error) throw completion.error;
        if (result.ok) sent += 1;
        else if (result.retryable) retrying += 1;
        else failed += 1;
      } catch (deliveryError) {
        const completion = await service.rpc("complete_notification_delivery", {
          p_delivery_id: delivery.delivery_id,
          p_success: false,
          p_retryable: true,
          p_provider_message_id: null,
          p_error_code: "transport_exception",
          p_latency_ms: null,
        });
        if (completion.error) throw completion.error;
        retrying += 1;
        console.error("Push delivery deferred", {
          delivery_id: delivery.delivery_id,
          provider: delivery.provider,
          message: safeErrorMessage(deliveryError),
        });
      }
    }

    return jsonResponse({
      ok: true,
      claimed: deliveries.length,
      sent,
      retrying,
      failed,
    });
  } catch (error) {
    const authStatus = authErrorStatus(error);
    if (authStatus) {
      return jsonResponse({ error: safeErrorMessage(error) }, authStatus);
    }
    return jsonResponse({ error: safeErrorMessage(error) }, 500);
  }
});
