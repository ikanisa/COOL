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
const MAX_SENDER_BYTES = 96;
const MAX_BODY_BYTES = 4_096;
const MAX_RECEIPT_AGE_MS = 30 * 24 * 60 * 60 * 1_000;
const MAX_FUTURE_SKEW_MS = 10 * 60 * 1_000;
const encoder = new TextEncoder();

function requiredString(
  value: unknown,
  name: string,
  maxBytes: number,
): string {
  if (typeof value !== "string") throw new Error(`${name} must be a string`);
  const clean = value.trim();
  if (!clean) throw new Error(`${name} is required`);
  if (encoder.encode(clean).byteLength > maxBytes) {
    throw new Error(`${name} exceeds the SMS ingestion limit`);
  }
  return clean;
}

function optionalString(
  value: unknown,
  name: string,
  maxBytes: number,
): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string") throw new Error(`${name} must be a string`);
  const clean = value.trim();
  if (!clean) return null;
  if (encoder.encode(clean).byteLength > maxBytes) {
    throw new Error(`${name} exceeds the SMS ingestion limit`);
  }
  return clean;
}

function optionalUuid(value: unknown, name: string): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string" || !uuidPattern.test(value.trim())) {
    throw new Error(`${name} must be a UUID`);
  }
  return value.trim();
}

function normalizeReceivedAtDevice(value: unknown): string | null {
  if (value == null || value === "") return null;
  if (typeof value !== "string" && typeof value !== "number") {
    throw new Error("received_at_device must be a timestamp");
  }
  const raw = String(value).trim();
  const epoch = /^\d{10,13}$/.test(raw) ? Number(raw) : Number.NaN;
  const date = Number.isFinite(epoch)
    ? new Date(raw.length === 10 ? epoch * 1000 : epoch)
    : new Date(raw);
  const timestamp = date.getTime();
  if (Number.isNaN(timestamp)) throw new Error("received_at_device is invalid");
  const now = Date.now();
  if (timestamp < now - MAX_RECEIPT_AGE_MS || timestamp > now + MAX_FUTURE_SKEW_MS) {
    throw new Error("received_at_device is outside the accepted window");
  }
  return date.toISOString();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const { user } = await requireUser(req.headers.get("authorization"));
    const payload = await req.json();
    if (typeof payload !== "object" || payload == null || Array.isArray(payload)) {
      return jsonResponse({ error: "A JSON object is required" }, 400);
    }

    const rawSender = requiredString(payload.raw_sender, "raw_sender", MAX_SENDER_BYTES);
    const rawBody = requiredString(payload.raw_body, "raw_body", MAX_BODY_BYTES);
    const receiverNumber = optionalString(
      payload.receiver_momo_number,
      "receiver_momo_number",
      40,
    );
    const collectionId = optionalUuid(payload.collection_id, "collection_id");
    const clientEnvelopeId = optionalUuid(
      payload.client_envelope_id,
      "client_envelope_id",
    );
    const receivedAtDevice = normalizeReceivedAtDevice(payload.received_at_device);
    const receiverMomoHash = receiverNumber == null
      ? null
      : await hashPhone(receiverNumber);
    if (receiverNumber != null && !receiverMomoHash) {
      return jsonResponse({ error: "The receiver route is invalid" }, 400);
    }
    const bodyHash = await sha256Hex(rawBody);
    const supabase = serviceClient();

    const { data: rawSms, error: ingestError } = await supabase.rpc(
      "ingest_raw_payment_sms",
      {
        p_receiver_user_id: user.id,
        p_collection_id: collectionId,
        p_raw_sender: rawSender,
        p_raw_body: rawBody,
        p_body_hash: bodyHash,
        p_client_envelope_id: clientEnvelopeId,
        p_receiver_momo_number_hash: receiverMomoHash,
        p_received_at_device: receivedAtDevice,
      },
    );
    if (ingestError) {
      if (ingestError.message.includes("not authorized")) {
        return jsonResponse(
          { error: "Receiver or SMS consent is not authorized" },
          403,
        );
      }
      if (ingestError.message.includes("rate limit")) {
        return jsonResponse({ error: "SMS ingestion rate limit exceeded" }, 429);
      }
      throw ingestError;
    }
    if (
      typeof rawSms !== "object" ||
      rawSms == null ||
      Array.isArray(rawSms) ||
      typeof rawSms.id !== "string"
    ) {
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
        body: JSON.stringify({ raw_sms_id: rawSms.id }),
      },
    );
    const parseResult = await parseResponse.json().catch(() => ({}));
    if (!parseResponse.ok) {
      return jsonResponse(
        { error: "SMS was stored but parsing must be retried", raw_sms_id: rawSms.id },
        502,
      );
    }

    return jsonResponse({
      ok: true,
      raw_sms_id: rawSms.id,
      status: "evidence_recorded",
      allocation_status: parseResult.allocation_status ?? "needs_review",
    });
  } catch (error) {
    const authStatus = authErrorStatus(error);
    if (authStatus) return jsonResponse({ error: safeErrorMessage(error) }, authStatus);
    const message = safeErrorMessage(error);
    const isInputError = /required|must be|invalid|outside|exceeds/i.test(message);
    return jsonResponse({ error: message }, isInputError ? 400 : 500);
  }
});
