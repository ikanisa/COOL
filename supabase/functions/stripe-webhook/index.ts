import {
  corsHeaders,
  jsonResponse,
  requireEnv,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";

type StripeEvent = {
  id: string;
  type: string;
  livemode?: boolean;
  data?: { object?: Record<string, unknown> };
};

function hex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function hmacSha256(secret: string, payload: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload)),
  );
}

async function verifyStripeSignature(
  rawBody: string,
  signature: string | null,
) {
  if (!signature) throw new Error("Missing Stripe signature");
  const parts = Object.fromEntries(
    signature.split(",").map((part) => {
      const [key, value] = part.split("=", 2);
      return [key, value];
    }),
  );
  const timestamp = parts.t;
  const expected = parts.v1;
  if (!timestamp || !expected) throw new Error("Invalid Stripe signature");
  const computed = await hmacSha256(
    requireEnv("STRIPE_WEBHOOK_SECRET"),
    `${timestamp}.${rawBody}`,
  );
  if (computed !== expected) throw new Error("Invalid Stripe signature");
}

function localStatusFor(event: StripeEvent): string {
  switch (event.type) {
    case "payment_intent.succeeded":
      return "succeeded";
    case "payment_intent.processing":
      return "processing";
    case "payment_intent.payment_failed":
      return "failed";
    case "payment_intent.canceled":
      return "cancelled";
    case "charge.dispute.created":
      return "disputed";
    default:
      return "needs_review";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const rawBody = await req.text();
    await verifyStripeSignature(rawBody, req.headers.get("stripe-signature"));
    const event = JSON.parse(rawBody) as StripeEvent;
    const stripeObject = event.data?.object ?? {};
    const paymentIntentId = String(stripeObject.id ?? "");
    const service = serviceClient();
    let relatedId: string | null = null;
    if (paymentIntentId.startsWith("pi_")) {
      const current = await service
        .from("diaspora_contribution_intents")
        .select("id")
        .eq("stripe_payment_intent_id", paymentIntentId)
        .maybeSingle();
      relatedId = current.data?.id ?? null;
      if (relatedId) {
        await service
          .from("diaspora_contribution_intents")
          .update({
            status: localStatusFor(event),
            updated_at: new Date().toISOString(),
          })
          .eq("id", relatedId);
      }
    }

    await service.from("stripe_webhook_events").upsert({
      event_id: event.id,
      event_type: event.type,
      livemode: event.livemode === true,
      related_contribution_intent_id: relatedId,
      processing_status: relatedId || event.type.startsWith("setup_intent.")
        ? "processed"
        : "needs_review",
      processed_at: new Date().toISOString(),
      payload: event,
    });
    return jsonResponse({ received: true });
  } catch (error) {
    console.error("Stripe webhook failed", {
      message: safeErrorMessage(error),
    });
    return jsonResponse({ error: "Stripe webhook verification failed" }, 400);
  }
});
