import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import {
  buildManualReviewResult,
  confirmRayonPendingTransaction,
  resolvePendingTransactionByReference,
} from "../_shared/rayon_payments.ts";
import { verifyHmacSha256Hex } from "../_shared/security.ts";
import { createAdminClient } from "../_shared/supabase.ts";

type NormalizedWebhookPayload = {
  eventId: string;
  reference: string;
  status: string;
  amount: number | null;
  provider: string | null;
  transactionId: string | null;
  payeeNumberOrCode: string | null;
  merchantCode: string | null;
  raw: Record<string, unknown>;
};

function asString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return null;
}

function asNullableInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.round(value);
  }
  if (typeof value === "string") {
    const cleaned = value.replaceAll(/[^\d.-]/g, "");
    if (!cleaned) return null;
    const parsed = Number.parseFloat(cleaned);
    return Number.isFinite(parsed) ? Math.round(parsed) : null;
  }
  return null;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return null;
}

function normalizeProviderId(value: string | null | undefined): string | null {
  const normalized = value?.trim().toLowerCase();
  switch (normalized) {
    case "mtn":
    case "mtn rwanda":
    case "mtn_rwanda":
      return "mtn_rwanda";
    case "airtel":
      return "airtel";
    case "orange":
      return "orange";
    default:
      return normalized?.length ? normalized : null;
  }
}

function normalizeWebhookPayload(
  body: unknown,
): NormalizedWebhookPayload | null {
  const root = asRecord(body);
  if (!root) {
    return null;
  }

  const payment = asRecord(root.payment) ?? asRecord(root.data) ?? root;
  const reference = asString(
    payment.reference ??
      payment.external_reference ??
      payment.tx_ref ??
      payment.momo_reference,
  );
  const status = asString(
    payment.status ??
      payment.payment_status ??
      payment.event_status ??
      root.status ??
      root.event,
  )?.toLowerCase();
  const amount = asNullableInt(
    payment.amount ?? payment.amount_rwf ?? payment.total,
  );
  const provider = normalizeProviderId(
    asString(payment.provider ?? root.provider),
  );
  const transactionId = asString(
    payment.transaction_id ?? payment.momo_tx_id ?? payment.tx_id,
  );
  const merchantCode = asString(
    payment.merchant_code ?? payment.merchantCode,
  );
  const payeeNumberOrCode = asString(
    payment.payee_number_or_code ?? payment.recipient_momo ?? merchantCode,
  );
  const eventId = asString(
    payment.event_id ?? payment.id ?? root.event_id ?? root.id,
  ) ??
    [
      provider ?? "unknown-provider",
      reference ?? "unknown-reference",
      transactionId ?? "unknown-transaction",
      status ?? "unknown-status",
      amount ?? 0,
    ].join(":");

  if (!reference || !status) {
    return null;
  }

  return {
    eventId,
    reference,
    status,
    amount,
    provider,
    transactionId,
    payeeNumberOrCode,
    merchantCode,
    raw: root,
  };
}

function isSuccessStatus(status: string): boolean {
  return [
    "success",
    "successful",
    "confirmed",
    "completed",
    "complete",
    "paid",
  ].includes(status);
}

async function ensureWebhookSignature(
  request: Request,
  rawBody: string,
): Promise<boolean> {
  const secret = Deno.env.get("RAYON_MOMO_WEBHOOK_SECRET");
  if (!secret) {
    throw new Error("Missing environment variable: RAYON_MOMO_WEBHOOK_SECRET");
  }

  const signature = request.headers.get("x-cool-signature") ??
    request.headers.get("x-rayon-signature");

  return await verifyHmacSha256Hex({
    secret,
    value: rawBody,
    signature,
  });
}

async function loadExistingEvent(
  adminClient: ReturnType<typeof createAdminClient>,
  provider: string,
  eventId: string,
) {
  const result = await adminClient
    .from("momo_webhook_events")
    .select(
      "id, event_status, target_table, target_record_id, processed_at, reference",
    )
    .eq("provider", provider)
    .eq("provider_event_id", eventId)
    .maybeSingle();

  if (result.error) {
    throw result.error;
  }

  return result.data;
}

async function insertWebhookEvent(
  adminClient: ReturnType<typeof createAdminClient>,
  payload: NormalizedWebhookPayload,
  timestamp: string,
) {
  const result = await adminClient
    .from("momo_webhook_events")
    .insert({
      provider: payload.provider ?? "unknown",
      provider_event_id: payload.eventId,
      reference: payload.reference,
      transaction_id: payload.transactionId,
      event_status: "received",
      payload: payload.raw,
      received_at: timestamp,
    })
    .select("id")
    .single();

  if (!result.error) {
    return asString(result.data.id) ?? "";
  }

  if ((result.error as { code?: string }).code === "23505") {
    const existing = await loadExistingEvent(
      adminClient,
      payload.provider ?? "unknown",
      payload.eventId,
    );
    if (existing) {
      return asString(existing.id) ?? "";
    }
  }

  throw result.error;
}

async function updateWebhookEvent(
  adminClient: ReturnType<typeof createAdminClient>,
  eventId: string,
  values: Record<string, unknown>,
) {
  const result = await adminClient
    .from("momo_webhook_events")
    .update(values)
    .eq("id", eventId);

  if (result.error) {
    throw result.error;
  }
}

Deno.serve(async (request: Request) => {
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method !== "POST") {
    return methodNotAllowed("POST");
  }

  try {
    const rawBody = await request.text();
    const signatureValid = await ensureWebhookSignature(request, rawBody);
    if (!signatureValid) {
      return errorResponse("Invalid webhook signature.", 401);
    }

    const payload = normalizeWebhookPayload(JSON.parse(rawBody));
    if (!payload) {
      return errorResponse(
        "Webhook payload must include reference and status.",
        400,
      );
    }

    const adminClient = createAdminClient();
    const timestamp = new Date().toISOString();
    const provider = payload.provider ?? "unknown";
    const existingEvent = await loadExistingEvent(
      adminClient,
      provider,
      payload.eventId,
    );

    if (existingEvent) {
      return jsonResponse({
        success: true,
        duplicate: true,
        eventId: payload.eventId,
        reference: existingEvent.reference ?? payload.reference,
        eventStatus: existingEvent.event_status,
        targetTable: existingEvent.target_table ?? null,
        targetRecordId: existingEvent.target_record_id ?? null,
        processedAt: existingEvent.processed_at ?? null,
      });
    }

    const webhookEventId = await insertWebhookEvent(
      adminClient,
      payload,
      timestamp,
    );

    if (!isSuccessStatus(payload.status)) {
      await updateWebhookEvent(adminClient, webhookEventId, {
        event_status: "ignored",
        processed_at: timestamp,
      });
      return jsonResponse({
        success: true,
        duplicate: false,
        ignored: true,
        reason: `Unsupported payment status: ${payload.status}`,
        eventId: payload.eventId,
        reference: payload.reference,
      });
    }

    const pendingTransaction = await resolvePendingTransactionByReference(
      adminClient,
      payload.reference,
    );
    if (!pendingTransaction) {
      await updateWebhookEvent(adminClient, webhookEventId, {
        event_status: "failed",
        processed_at: timestamp,
      });
      return errorResponse(
        "No pending transaction matched the webhook reference.",
        404,
        {
          eventId: payload.eventId,
          reference: payload.reference,
        },
      );
    }

    if (
      payload.amount != null &&
      pendingTransaction.amount > 0 &&
      payload.amount !== pendingTransaction.amount
    ) {
      await updateWebhookEvent(adminClient, webhookEventId, {
        event_status: "failed",
        processed_at: timestamp,
      });
      return errorResponse(
        "Webhook amount did not match the pending transaction.",
        409,
        {
          eventId: payload.eventId,
          reference: payload.reference,
          expectedAmount: pendingTransaction.amount,
          receivedAmount: payload.amount,
        },
      );
    }

    const reconciliation = await confirmRayonPendingTransaction(
      adminClient,
      pendingTransaction,
      {
        source: "rs-momo-webhook",
        timestamp,
        provider: payload.provider,
        amount: payload.amount,
        transactionId: payload.transactionId,
        payeeNumberOrCode: payload.payeeNumberOrCode,
        merchantCode: payload.merchantCode,
        extraPayload: {
          webhook_event_id: payload.eventId,
          webhook_status: payload.status,
          webhook_received_at: timestamp,
          raw_event: payload.raw,
        },
      },
    );

    const eventStatus = reconciliation.matchStatus === "matched"
      ? "processed"
      : reconciliation.matchStatus === "manual_review"
      ? "failed"
      : "ignored";
    await updateWebhookEvent(adminClient, webhookEventId, {
      event_status: eventStatus,
      processed_at: timestamp,
      target_table: reconciliation.targetTable,
      target_record_id: reconciliation.targetRecordId,
      payload: {
        ...payload.raw,
        reconciliation,
      },
    });

    const httpStatus = reconciliation.matchStatus === "matched"
      ? 200
      : reconciliation.matchStatus === "manual_review"
      ? 409
      : 202;

    return jsonResponse(
      {
        success: reconciliation.matchStatus === "matched",
        duplicate: false,
        eventId: payload.eventId,
        reference: payload.reference,
        reconciliation,
      },
      httpStatus,
    );
  } catch (error) {
    console.error("rs-momo-webhook error:", error);
    const details = error instanceof Error ? error.message : String(error);
    return errorResponse("Webhook processing failed.", 500, { details });
  }
});
