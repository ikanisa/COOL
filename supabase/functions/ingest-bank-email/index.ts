import {
  corsHeaders,
  jsonResponse,
  requireEnv,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { parseBankEvidence } from "../_shared/bank_evidence.ts";
import { verifyTimestampedHmac } from "../_shared/hmac.ts";

const encoder = new TextEncoder();

function requiredString(value: unknown, name: string, maxBytes: number): string {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${name} is required`);
  const clean = value.trim();
  if (encoder.encode(clean).byteLength > maxBytes) throw new Error(`${name} exceeds the ingestion limit`);
  return clean;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
  try {
    const rawPayload = await request.text();
    if (encoder.encode(rawPayload).byteLength > 250_000) throw new Error("Email payload exceeds the 250 KB limit");
    const authorized = await verifyTimestampedHmac(
      requireEnv("BANK_EMAIL_INGEST_HMAC_SECRET"),
      request.headers.get("x-collect-timestamp"),
      request.headers.get("x-collect-email-signature"),
      rawPayload,
    );
    if (!authorized) return jsonResponse({ error: "Unauthorized" }, 401);
    const payload = JSON.parse(rawPayload);
    if (typeof payload !== "object" || payload == null || Array.isArray(payload)) {
      throw new Error("A JSON object is required");
    }
    const sourceUid = requiredString(payload.source_uid, "source_uid", 200);
    const sender = requiredString(payload.sender, "sender", 320);
    const subject = requiredString(payload.subject, "subject", 500);
    const emailBody = requiredString(payload.body, "body", 200_000);
    const combinedBody = `Subject: ${subject}\n${emailBody}`;
    const received = new Date(payload.received_at ?? Date.now());
    if (Number.isNaN(received.getTime()) || received.getTime() > Date.now() + 5 * 60_000 || received.getTime() < Date.now() - 90 * 24 * 60 * 60_000) {
      throw new Error("received_at is outside the accepted window");
    }
    const parsed = parseBankEvidence(sender, combinedBody, received.toISOString());
    const { data, error } = await serviceClient().rpc("ingest_bank_evidence", {
      p_channel: "email",
      p_source_uid: sourceUid,
      p_raw_sender: sender,
      p_raw_body: combinedBody,
      p_received_at: received.toISOString(),
      p_direction: parsed.direction,
      p_amount_minor: parsed.amount_minor,
      p_currency: parsed.currency,
      p_bank_transaction_id: parsed.bank_transaction_id,
      p_end_to_end_id: parsed.end_to_end_id,
      p_transfer_reference: parsed.transfer_reference,
      p_payer_name: parsed.payer_name,
      p_payer_account_last4: parsed.payer_account_last4,
      p_occurred_at: parsed.occurred_at,
      p_confidence: parsed.confidence,
      p_parser_name: parsed.parser_name,
      p_parsed_json: parsed,
      p_headers: {
        message_id: sourceUid,
        provider: typeof payload.provider === "string" ? payload.provider.slice(0, 80) : "email_webhook",
      },
    });
    if (error) throw error;
    return jsonResponse({ ok: true, ...data });
  } catch (error) {
    const message = safeErrorMessage(error);
    if (/required|invalid|outside|exceeds|JSON/i.test(message)) return jsonResponse({ error: message }, 400);
    console.error(JSON.stringify({ event: "ingest_bank_email_failed", message }));
    return jsonResponse({ error: "Bank email evidence could not be recorded" }, 500);
  }
});

