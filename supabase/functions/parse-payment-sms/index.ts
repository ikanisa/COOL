import {
  authErrorStatus,
  corsHeaders,
  jsonResponse,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireInternalRequest, serviceClient } from "../_shared/supabase.ts";
import { hashPhone, sha256Hex } from "../_shared/hash.ts";
import { normalizeMomoName, parseMomoSms } from "../_shared/momo_sms_parser.ts";

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function finalizeIfAvailable(
  supabase: ReturnType<typeof serviceClient>,
  rawSmsId: string,
) {
  const contract = await supabase.rpc("attested_sms_contract_version");
  const contractMissing = contract.error?.code === "PGRST202" ||
    /could not find the function/i.test(contract.error?.message ?? "");
  if (contract.error && !contractMissing) throw contract.error;
  if (contract.data !== 1) return { status: "legacy_contract" };
  const { data, error } = await supabase.rpc(
    "finalize_attested_payment_sms",
    { p_raw_sms_id: rawSmsId },
  );
  if (error) throw error;
  return data;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  let rawSmsId: string | null = null;
  let leaseId: string | null = null;
  try {
    requireInternalRequest(req);
    const payload = await req.json();
    rawSmsId = typeof payload?.raw_sms_id === "string"
      ? payload.raw_sms_id.trim()
      : null;
    if (!rawSmsId || !uuidPattern.test(rawSmsId)) {
      return jsonResponse({ error: "raw_sms_id must be a UUID" }, 400);
    }
    const supabase = serviceClient();
    const { data: existing, error: existingError } = await supabase
      .from("parsed_payment_events")
      .select("id, allocation_status, parser_model")
      .eq("raw_sms_id", rawSmsId)
      .maybeSingle();
    if (existingError) throw existingError;
    if (existing) {
      const { data: allocation, error: allocationError } =
        existing.allocation_status === "unallocated"
          ? await supabase.rpc("allocate_parsed_payment_event", {
            event_id: existing.id,
          })
          : { data: existing.allocation_status, error: null };
      if (allocationError) throw allocationError;
      const finality = await finalizeIfAvailable(supabase, rawSmsId);
      return jsonResponse({
        ok: true,
        parsed_event_id: existing.id,
        allocation_status: allocation,
        finality,
        replay: true,
      });
    }

    leaseId = crypto.randomUUID();
    const { data: raw, error: claimError } = await supabase.rpc(
      "claim_raw_payment_sms_for_parse",
      { p_raw_sms_id: rawSmsId, p_lease_id: leaseId },
    );
    if (claimError) throw claimError;
    if (typeof raw !== "object" || raw == null || Array.isArray(raw)) {
      return jsonResponse({ ok: true, allocation_status: "processing" }, 202);
    }
    const parsed = parseMomoSms(
      String(raw.raw_sender ?? ""),
      String(raw.raw_body ?? ""),
    );
    const { data: event, error: insertError } = await supabase
      .from("parsed_payment_events")
      .insert({
        raw_sms_id: rawSmsId,
        collection_id: raw.collection_id ?? null,
        receiver_user_id: raw.receiver_user_id,
        is_mobile_money_payment: parsed.is_mobile_money_payment,
        network: parsed.network,
        direction: parsed.direction,
        amount_rwf: parsed.amount_rwf,
        currency: parsed.currency,
        transaction_id: parsed.transaction_id,
        sender_name: parsed.sender_name,
        payer_last3: parsed.payer_last3,
        payer_match_key: parsed.sender_name && parsed.payer_last3
          ? await sha256Hex(
            `${normalizeMomoName(parsed.sender_name)}|${parsed.payer_last3}`,
          )
          : null,
        wallet_balance_rwf: parsed.wallet_balance_rwf,
        sender_phone_hash: await hashPhone(parsed.sender_phone),
        receiver_phone_hash: raw.receiver_momo_number_hash ?? null,
        transaction_time: parsed.transaction_time ?? raw.received_at_device ??
          raw.ingested_at,
        detected_user_public_id: parsed.detected_user_public_id,
        confidence: parsed.confidence,
        parser_model: "collect-deterministic-momo-v2",
        parser_schema_version: "collect.sms_parser.v4",
        parsed_json: {
          ...parsed,
          sender_phone: parsed.sender_phone ? "[hashed]" : null,
          sender_name: parsed.sender_name ? "[private]" : null,
        },
        allocation_status: "unallocated",
      })
      .select("id")
      .single();
    if (insertError) throw insertError;
    const { error: completionError } = await supabase
      .from("raw_payment_sms")
      .update({
        parse_status: "parsed",
        parse_started_at: null,
        parse_lease_id: null,
      })
      .eq("id", rawSmsId)
      .eq("parse_lease_id", leaseId);
    if (completionError) throw completionError;
    const { data: allocation, error: allocationError } = await supabase.rpc(
      "allocate_parsed_payment_event",
      { event_id: event.id },
    );
    if (allocationError) throw allocationError;
    const finality = await finalizeIfAvailable(supabase, rawSmsId);
    return jsonResponse({
      ok: true,
      parsed_event_id: event.id,
      allocation_status: allocation,
      finality,
      parser_model: "collect-deterministic-momo-v2",
    });
  } catch (error) {
    if (rawSmsId && leaseId) {
      await serviceClient().from("raw_payment_sms").update({
        parse_status: "failed",
        parse_started_at: null,
        parse_lease_id: null,
      }).eq("id", rawSmsId).eq("parse_lease_id", leaseId);
    }
    const authStatus = authErrorStatus(error) ?? 502;
    return jsonResponse({ error: safeErrorMessage(error) }, authStatus);
  }
});
