import { jsonResponse, requireEnv, safeErrorMessage } from "./cors.ts";
import {
  parseProviderFinalityEvent,
  ProviderFinalityPayloadError,
} from "./provider_finality_payload.ts";
import {
  ProviderFinalityAuthError,
  sha256Hex,
  verifyProviderFinalitySignature,
} from "./provider_finality_signature.ts";
import { serviceClient } from "./supabase.ts";

const MAX_BODY_BYTES = 64 * 1024;

type RpcResult = {
  data: unknown;
  error: unknown | null;
};

export type ProviderFinalityHandlerDependencies = {
  currentSecret: string;
  previousSecret?: string | null;
  processEvent: (arguments_: Record<string, unknown>) => Promise<RpcResult>;
};

function productionDependencies(): ProviderFinalityHandlerDependencies {
  return {
    currentSecret: requireEnv("PAYMENT_PROVIDER_FINALITY_SECRET_CURRENT"),
    previousSecret: Deno.env.get("PAYMENT_PROVIDER_FINALITY_SECRET_PREVIOUS"),
    processEvent: async (arguments_) => {
      const { data, error } = await serviceClient().rpc(
        "process_provider_finality_event",
        arguments_,
      );
      return { data, error };
    },
  };
}

export async function handleProviderFinalityRequest(
  req: Request,
  dependencies?: ProviderFinalityHandlerDependencies,
): Promise<Response> {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const contentLength = Number(req.headers.get("content-length") ?? "0");
  if (
    !Number.isFinite(contentLength) || contentLength < 0 ||
    contentLength > MAX_BODY_BYTES
  ) {
    return jsonResponse({ error: "Payload too large" }, 413);
  }

  let requestId: string | null = null;
  try {
    const rawBody = await req.text();
    if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
      return jsonResponse({ error: "Payload too large" }, 413);
    }

    const resolvedDependencies = dependencies ?? productionDependencies();
    const verified = await verifyProviderFinalitySignature(
      rawBody,
      req.headers.get("x-provider-finality-timestamp"),
      req.headers.get("x-provider-finality-request-id"),
      req.headers.get("x-provider-finality-signature"),
      resolvedDependencies.previousSecret
        ? [
          resolvedDependencies.currentSecret,
          resolvedDependencies.previousSecret,
        ]
        : [resolvedDependencies.currentSecret],
    );
    requestId = verified.requestId;
    const event = parseProviderFinalityEvent(rawBody, verified.requestId);
    const payloadSha256 = await sha256Hex(rawBody);

    const confirmation = event.eventType === "payment.confirmed" ? event : null;
    const rejection = event.eventType === "payment.rejected" ? event : null;
    const { data, error } = await resolvedDependencies.processEvent({
      p_request_id: event.eventId,
      p_event_type: event.eventType,
      p_payload_sha256: payloadSha256,
      p_payment_id: event.paymentId,
      p_provider_network: confirmation?.providerNetwork ?? null,
      p_transaction_id: confirmation?.transactionId ?? null,
      p_provider_confirmation_id: confirmation?.providerConfirmationId ?? null,
      p_receiver_momo_number_hash: confirmation?.receiverMomoNumberHash ?? null,
      p_amount_rwf: confirmation?.amountRwf ?? null,
      p_occurred_at: confirmation?.occurredAt ?? null,
      p_evidence_sha256: confirmation?.evidenceSha256 ?? null,
      p_rejection_reason: rejection?.reason ?? null,
      p_provider_reference: rejection?.providerReference ?? null,
    });
    if (error) throw error;

    const result = data as {
      payment_id?: string;
      replayed?: boolean;
    } | null;
    return jsonResponse({
      received: true,
      request_id: event.eventId,
      payment_id: result?.payment_id ?? event.paymentId,
      replayed: result?.replayed === true,
    });
  } catch (error) {
    if (error instanceof ProviderFinalityAuthError) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }
    if (error instanceof ProviderFinalityPayloadError) {
      return jsonResponse({ error: "Invalid provider finality payload" }, 400);
    }
    const message = safeErrorMessage(error);
    console.error("Provider finality event failed", {
      requestId,
      code: typeof error === "object" && error !== null && "code" in error
        ? String((error as { code?: unknown }).code ?? "")
        : "",
      configurationError: message.startsWith("Missing required env var:"),
    });
    return jsonResponse(
      {
        error: message.startsWith("Missing required env var:")
          ? "Provider finality service is not configured"
          : "Provider finality event rejected",
      },
      message.startsWith("Missing required env var:") ? 500 : 409,
    );
  }
}
