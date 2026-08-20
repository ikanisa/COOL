import {
  authErrorStatus,
  corsHeaders,
  jsonResponse,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireUser } from "../_shared/supabase.ts";
import { parseBankEvidence } from "../_shared/bank_evidence.ts";

const encoder = new TextEncoder();

function requiredString(value: unknown, name: string, maxBytes: number): string {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${name} is required`);
  const clean = value.trim();
  if (encoder.encode(clean).byteLength > maxBytes) throw new Error(`${name} exceeds the ingestion limit`);
  return clean;
}

function receivedAt(value: unknown): string {
  const date = new Date(typeof value === "string" || typeof value === "number" ? value : Date.now());
  const time = date.getTime();
  if (Number.isNaN(time) || time > Date.now() + 5 * 60_000 || time < Date.now() - 90 * 24 * 60 * 60_000) {
    throw new Error("received_at is outside the accepted window");
  }
  return date.toISOString();
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
  try {
    const { supabase, user } = await requireUser(request.headers.get("authorization"));
    const payload = await request.json();
    if (typeof payload !== "object" || payload == null || Array.isArray(payload)) {
      throw new Error("A JSON object is required");
    }
    const sourceUid = requiredString(payload.source_uid, "source_uid", 160);
    const sender = requiredString(payload.raw_sender, "raw_sender", 160);
    const body = requiredString(payload.raw_body, "raw_body", 16_384);
    const at = receivedAt(payload.received_at);
    const parsed = parseBankEvidence(sender, body, at);
    const { data, error } = await supabase.rpc("ingest_bank_evidence", {
      p_channel: "sms",
      p_source_uid: sourceUid,
      p_raw_sender: sender,
      p_raw_body: body,
      p_received_at: at,
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
        device_id: typeof payload.device_id === "string" ? payload.device_id.slice(0, 160) : null,
        ingested_by: user.id,
      },
    });
    if (error) throw error;
    return jsonResponse({ ok: true, ...data });
  } catch (error) {
    const authStatus = authErrorStatus(error);
    const message = safeErrorMessage(error);
    if (authStatus) return jsonResponse({ error: message }, authStatus);
    if (/permission|required|invalid|outside|exceeds|unsupported/i.test(message)) {
      return jsonResponse({ error: message }, /permission/i.test(message) ? 403 : 400);
    }
    console.error(JSON.stringify({ event: "ingest_bank_sms_failed", message }));
    return jsonResponse({ error: "Bank SMS evidence could not be recorded" }, 500);
  }
});

