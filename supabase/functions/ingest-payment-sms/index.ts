import {
  authErrorStatus,
  corsHeaders,
  jsonResponse,
  requireEnv,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import { hashPhone, sha256Hex } from "../_shared/hash.ts";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const encoder = new TextEncoder();

function bounded(value: unknown, field: string, maxBytes: number): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`${field} is required`);
  }
  const clean = value.trim();
  if (encoder.encode(clean).byteLength > maxBytes) {
    throw new Error(`${field} exceeds the accepted limit`);
  }
  return clean;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
  try {
    const { user } = await requireUser(req.headers.get("authorization"));
    const payload = await req.json() as Record<string, unknown>;
    const rawSender = bounded(payload.raw_sender, "raw_sender", 96);
    const rawBody = bounded(payload.raw_body, "raw_body", 4_096);
    const receiver = bounded(
      payload.receiver_momo_number,
      "receiver_momo_number",
      40,
    );
    const envelope = typeof payload.client_envelope_id === "string" &&
        uuidPattern.test(payload.client_envelope_id)
      ? payload.client_envelope_id
      : crypto.randomUUID();
    const collectionId = typeof payload.collection_id === "string" &&
        uuidPattern.test(payload.collection_id)
      ? payload.collection_id
      : null;
    const receivedAt = typeof payload.received_at_device === "string" &&
        !Number.isNaN(Date.parse(payload.received_at_device))
      ? new Date(payload.received_at_device).toISOString()
      : null;
    const receiverHash = await hashPhone(receiver);
    if (!receiverHash) return jsonResponse({ error: "Invalid receiver" }, 400);

    const supabase = serviceClient();
    const { data, error } = await supabase.rpc("ingest_raw_payment_sms", {
      p_receiver_user_id: user.id,
      p_collection_id: collectionId,
      p_raw_sender: rawSender,
      p_raw_body: rawBody,
      p_body_hash: await sha256Hex(rawBody),
      p_client_envelope_id: envelope,
      p_receiver_momo_number_hash: receiverHash,
      p_received_at_device: receivedAt,
    });
    if (error) {
      if (/not authorized/i.test(error.message)) {
        return jsonResponse({ error: "Receiver or SMS consent is not authorized" }, 403);
      }
      if (/rate limit/i.test(error.message)) {
        return jsonResponse({ error: "SMS ingestion rate limit exceeded" }, 429);
      }
      throw error;
    }
    if (typeof data !== "object" || data == null || !("id" in data)) {
      throw new Error("SMS ingestion did not return a durable record");
    }
    const parseResponse = await fetch(
      `${requireEnv("SUPABASE_URL")}/functions/v1/parse-payment-sms`,
      {
        method: "POST",
        headers: {
          apikey: requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
          "Content-Type": "application/json",
          "x-collect-signature": requireEnv("INTERNAL_FUNCTION_SECRET"),
        },
        body: JSON.stringify({ raw_sms_id: data.id }),
      },
    );
    const parsed = await parseResponse.json().catch(() => ({}));
    return parseResponse.ok
      ? jsonResponse({ ok: true, raw_sms_id: data.id, ...parsed })
      : jsonResponse({
        error: "SMS was stored but parsing must be retried",
        raw_sms_id: data.id,
      }, 502);
  } catch (error) {
    const authStatus = authErrorStatus(error);
    if (authStatus) return jsonResponse({ error: safeErrorMessage(error) }, authStatus);
    const message = safeErrorMessage(error);
    return jsonResponse({ error: message }, /required|invalid|limit/i.test(message) ? 400 : 500);
  }
});
