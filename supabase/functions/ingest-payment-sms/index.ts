import {
  authErrorStatus,
  corsHeaders,
  jsonResponse,
  requireEnv,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import { hashPhone, sha256Hex } from "../_shared/hash.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const authorization = req.headers.get("authorization");
    const { user } = await requireUser(authorization);
    const payload = await req.json();
    const rawSender = String(payload.raw_sender ?? payload.sender ?? "").trim();
    const rawBody = String(payload.raw_body ?? payload.body ?? "").trim();
    const collectionId = payload.collection_id ?? null;
    if (!rawSender || !rawBody) {
      return jsonResponse(
        { error: "raw_sender and raw_body are required" },
        400,
      );
    }

    const receiverMomoHash = await hashPhone(payload.receiver_momo_number);
    if (!receiverMomoHash && !collectionId) {
      return jsonResponse({
        error: "receiver_momo_number or collection_id is required",
      }, 400);
    }
    const bodyHash = await sha256Hex(rawBody);
    const supabase = serviceClient();

    const { data: authorized, error: authError } = await supabase.rpc(
      "user_can_ingest_receiver_sms",
      {
        receiver_hash: receiverMomoHash,
        collection: collectionId,
        user_uuid: user.id,
      },
    );
    if (authError || authorized !== true) {
      return jsonResponse({
        error: "Receiver is not authorized for this MOMO number",
      }, 403);
    }

    const { data: rawSms, error } = await supabase
      .from("raw_payment_sms")
      .upsert({
        collection_id: collectionId,
        receiver_user_id: user.id,
        raw_sender: rawSender,
        raw_body: rawBody,
        body_hash: bodyHash,
        receiver_momo_number_hash: receiverMomoHash,
        received_at_device: payload.received_at_device ?? null,
        parse_status: "pending",
      }, { onConflict: "body_hash", ignoreDuplicates: false })
      .select("id")
      .single();

    if (error) throw error;

    await fetch(
      `${requireEnv("SUPABASE_URL")}/functions/v1/parse-payment-sms`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${requireEnv("SUPABASE_SERVICE_ROLE_KEY")}`,
          "Content-Type": "application/json",
          "x-collect-signature": requireEnv("INTERNAL_FUNCTION_SECRET"),
        },
        body: JSON.stringify({ raw_sms_id: rawSms.id }),
      },
    );

    return jsonResponse({ ok: true, raw_sms_id: rawSms.id, status: "queued" });
  } catch (error) {
    const authStatus = authErrorStatus(error);
    if (authStatus) {
      return jsonResponse({ error: safeErrorMessage(error) }, authStatus);
    }
    return jsonResponse({
      error: safeErrorMessage(error),
    }, 500);
  }
});
