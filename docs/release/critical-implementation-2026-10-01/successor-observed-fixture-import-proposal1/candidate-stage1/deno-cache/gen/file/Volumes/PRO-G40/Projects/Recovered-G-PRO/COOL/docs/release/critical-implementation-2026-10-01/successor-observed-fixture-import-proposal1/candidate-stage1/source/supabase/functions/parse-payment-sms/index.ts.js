import { boundedJson, publicFailure, requireReceiptContract, PublicError } from "../_shared/production_contract.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { requireInternalRequest, serviceClient } from "../_shared/supabase.ts";
import { hashPhone, sha256Hex } from "../_shared/hash.ts";
import { normalizeMomoName, parseMomoSms } from "../_shared/momo_sms_parser.ts";
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
async function finalityStatus(supabase) {
  const contract = await supabase.rpc("attested_sms_contract_version");
  if (contract.error) throw new PublicError("receipt_contract_unavailable", 503);
  requireReceiptContract(contract.data);
  return {
    status: "awaiting_reconciliation",
    evidence_level: "sms_observed"
  };
}
Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }
  if (req.method !== "POST") {
    return jsonResponse({
      error: "Method not allowed"
    }, 405);
  }
  let rawSmsId = null;
  let leaseId = null;
  try {
    requireInternalRequest(req);
    const payload = await boundedJson(req);
    rawSmsId = typeof payload?.raw_sms_id === "string" ? payload.raw_sms_id.trim() : null;
    if (!rawSmsId || !uuidPattern.test(rawSmsId)) {
      return jsonResponse({
        error: "raw_sms_id must be a UUID"
      }, 400);
    }
    const supabase = serviceClient();
    await finalityStatus(supabase);
    const { data: existing, error: existingError } = await supabase.from("parsed_payment_events").select("id, allocation_status, parser_model").eq("raw_sms_id", rawSmsId).maybeSingle();
    if (existingError) throw existingError;
    if (existing) {
      // An event can commit just before a worker loses its parse lease. A
      // retry repairs the raw-row state from that durable event before ACK.
      const { data: repaired, error: repairError } = await supabase.from("raw_payment_sms").update({
        parse_status: "parsed",
        parse_started_at: null,
        parse_lease_id: null
      }).eq("id", rawSmsId).select("id").maybeSingle();
      if (repairError) throw repairError;
      if (repaired?.id !== rawSmsId) {
        throw new PublicError("receipt_parse_state_unavailable", 503);
      }
      const { data: allocation, error: allocationError } = existing.allocation_status === "unallocated" ? await supabase.rpc("allocate_parsed_payment_event", {
        event_id: existing.id
      }) : {
        data: existing.allocation_status,
        error: null
      };
      if (allocationError) throw allocationError;
      const finality = await finalityStatus(supabase);
      return jsonResponse({
        ok: true,
        parsed_event_id: existing.id,
        allocation_status: allocation,
        finality,
        replay: true
      });
    }
    leaseId = crypto.randomUUID();
    const { data: raw, error: claimError } = await supabase.rpc("claim_raw_payment_sms_for_parse", {
      p_raw_sms_id: rawSmsId,
      p_lease_id: leaseId
    });
    if (claimError) throw claimError;
    if (typeof raw !== "object" || raw == null || Array.isArray(raw)) {
      return jsonResponse({
        ok: true,
        allocation_status: "processing"
      }, 202);
    }
    const parsed = parseMomoSms(String(raw.raw_sender ?? ""), String(raw.raw_body ?? ""));
    const { data: event, error: insertError } = await supabase.from("parsed_payment_events").insert({
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
      payer_match_key: parsed.sender_name && parsed.payer_last3 ? await sha256Hex(`${normalizeMomoName(parsed.sender_name)}|${parsed.payer_last3}`) : null,
      wallet_balance_rwf: parsed.wallet_balance_rwf,
      sender_phone_hash: await hashPhone(parsed.sender_phone),
      receiver_phone_hash: raw.receiver_momo_number_hash ?? null,
      transaction_time: parsed.transaction_time ?? raw.received_at_device ?? raw.ingested_at,
      detected_user_public_id: parsed.detected_user_public_id,
      confidence: parsed.confidence,
      parser_model: "collect-deterministic-momo-v2",
      parser_schema_version: "collect.sms_parser.v4",
      parsed_json: {
        ...parsed,
        sender_phone: parsed.sender_phone ? "[hashed]" : null,
        sender_name: parsed.sender_name ? "[private]" : null
      },
      allocation_status: "unallocated"
    }).select("id").single();
    if (insertError) throw insertError;
    const { data: completed, error: completionError } = await supabase.from("raw_payment_sms").update({
      parse_status: "parsed",
      parse_started_at: null,
      parse_lease_id: null
    }).eq("id", rawSmsId).eq("parse_lease_id", leaseId).select("id").maybeSingle();
    if (completionError) throw completionError;
    // PostgREST reports zero matched rows as a successful UPDATE. A stale
    // worker must not return a completed parse after another worker owns it.
    if (completed?.id !== rawSmsId) {
      throw new PublicError("receipt_parse_lease_lost", 503);
    }
    const { data: allocation, error: allocationError } = await supabase.rpc("allocate_parsed_payment_event", {
      event_id: event.id
    });
    if (allocationError) throw allocationError;
    const finality = await finalityStatus(supabase);
    return jsonResponse({
      ok: true,
      parsed_event_id: event.id,
      allocation_status: allocation,
      finality,
      parser_model: "collect-deterministic-momo-v2"
    });
  } catch (error) {
    if (rawSmsId && leaseId) {
      await serviceClient().from("raw_payment_sms").update({
        parse_status: "failed",
        parse_started_at: null,
        parse_lease_id: null
      }).eq("id", rawSmsId).eq("parse_lease_id", leaseId);
    }
    const failure = publicFailure(error);
    return jsonResponse({
      error: failure.error
    }, failure.status);
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL3BhcnNlLXBheW1lbnQtc21zL2luZGV4LnRzIl0sInNvdXJjZXNDb250ZW50IjpbImltcG9ydCB7Ym91bmRlZEpzb24scHVibGljRmFpbHVyZSxyZXF1aXJlUmVjZWlwdENvbnRyYWN0LFB1YmxpY0Vycm9yfSBmcm9tIFwiLi4vX3NoYXJlZC9wcm9kdWN0aW9uX2NvbnRyYWN0LnRzXCI7XG5pbXBvcnQge1xuICBjb3JzSGVhZGVycyxcbiAganNvblJlc3BvbnNlLFxufSBmcm9tIFwiLi4vX3NoYXJlZC9jb3JzLnRzXCI7XG5pbXBvcnQgeyByZXF1aXJlSW50ZXJuYWxSZXF1ZXN0LCBzZXJ2aWNlQ2xpZW50IH0gZnJvbSBcIi4uL19zaGFyZWQvc3VwYWJhc2UudHNcIjtcbmltcG9ydCB7IGhhc2hQaG9uZSwgc2hhMjU2SGV4IH0gZnJvbSBcIi4uL19zaGFyZWQvaGFzaC50c1wiO1xuaW1wb3J0IHsgbm9ybWFsaXplTW9tb05hbWUsIHBhcnNlTW9tb1NtcyB9IGZyb20gXCIuLi9fc2hhcmVkL21vbW9fc21zX3BhcnNlci50c1wiO1xuXG5jb25zdCB1dWlkUGF0dGVybiA9XG4gIC9eWzAtOWEtZl17OH0tWzAtOWEtZl17NH0tWzEtNV1bMC05YS1mXXszfS1bODlhYl1bMC05YS1mXXszfS1bMC05YS1mXXsxMn0kL2k7XG5cbmFzeW5jIGZ1bmN0aW9uIGZpbmFsaXR5U3RhdHVzKHN1cGFiYXNlOiBSZXR1cm5UeXBlPHR5cGVvZiBzZXJ2aWNlQ2xpZW50Pikge1xuICBjb25zdCBjb250cmFjdD1hd2FpdCBzdXBhYmFzZS5ycGMoXCJhdHRlc3RlZF9zbXNfY29udHJhY3RfdmVyc2lvblwiKTtcbiAgaWYgKGNvbnRyYWN0LmVycm9yKSB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyZWNlaXB0X2NvbnRyYWN0X3VuYXZhaWxhYmxlXCIsNTAzKTtcbiAgcmVxdWlyZVJlY2VpcHRDb250cmFjdChjb250cmFjdC5kYXRhKTtcbiAgcmV0dXJuIHtzdGF0dXM6XCJhd2FpdGluZ19yZWNvbmNpbGlhdGlvblwiLGV2aWRlbmNlX2xldmVsOlwic21zX29ic2VydmVkXCJ9O1xufVxuXG5EZW5vLnNlcnZlKGFzeW5jIChyZXEpID0+IHtcbiAgaWYgKHJlcS5tZXRob2QgPT09IFwiT1BUSU9OU1wiKSB7XG4gICAgcmV0dXJuIG5ldyBSZXNwb25zZShcIm9rXCIsIHsgaGVhZGVyczogY29yc0hlYWRlcnMgfSk7XG4gIH1cbiAgaWYgKHJlcS5tZXRob2QgIT09IFwiUE9TVFwiKSB7XG4gICAgcmV0dXJuIGpzb25SZXNwb25zZSh7IGVycm9yOiBcIk1ldGhvZCBub3QgYWxsb3dlZFwiIH0sIDQwNSk7XG4gIH1cbiAgbGV0IHJhd1Ntc0lkOiBzdHJpbmcgfCBudWxsID0gbnVsbDtcbiAgbGV0IGxlYXNlSWQ6IHN0cmluZyB8IG51bGwgPSBudWxsO1xuICB0cnkge1xuICAgIHJlcXVpcmVJbnRlcm5hbFJlcXVlc3QocmVxKTtcbiAgICBjb25zdCBwYXlsb2FkID0gYXdhaXQgYm91bmRlZEpzb24ocmVxKTtcbiAgICByYXdTbXNJZCA9IHR5cGVvZiBwYXlsb2FkPy5yYXdfc21zX2lkID09PSBcInN0cmluZ1wiXG4gICAgICA/IHBheWxvYWQucmF3X3Ntc19pZC50cmltKClcbiAgICAgIDogbnVsbDtcbiAgICBpZiAoIXJhd1Ntc0lkIHx8ICF1dWlkUGF0dGVybi50ZXN0KHJhd1Ntc0lkKSkge1xuICAgICAgcmV0dXJuIGpzb25SZXNwb25zZSh7IGVycm9yOiBcInJhd19zbXNfaWQgbXVzdCBiZSBhIFVVSURcIiB9LCA0MDApO1xuICAgIH1cbiAgICBjb25zdCBzdXBhYmFzZSA9IHNlcnZpY2VDbGllbnQoKTtcbiAgICBhd2FpdCBmaW5hbGl0eVN0YXR1cyhzdXBhYmFzZSk7XG4gICAgY29uc3QgeyBkYXRhOiBleGlzdGluZywgZXJyb3I6IGV4aXN0aW5nRXJyb3IgfSA9IGF3YWl0IHN1cGFiYXNlXG4gICAgICAuZnJvbShcInBhcnNlZF9wYXltZW50X2V2ZW50c1wiKVxuICAgICAgLnNlbGVjdChcImlkLCBhbGxvY2F0aW9uX3N0YXR1cywgcGFyc2VyX21vZGVsXCIpXG4gICAgICAuZXEoXCJyYXdfc21zX2lkXCIsIHJhd1Ntc0lkKVxuICAgICAgLm1heWJlU2luZ2xlKCk7XG4gICAgaWYgKGV4aXN0aW5nRXJyb3IpIHRocm93IGV4aXN0aW5nRXJyb3I7XG4gICAgaWYgKGV4aXN0aW5nKSB7XG4gICAgICAvLyBBbiBldmVudCBjYW4gY29tbWl0IGp1c3QgYmVmb3JlIGEgd29ya2VyIGxvc2VzIGl0cyBwYXJzZSBsZWFzZS4gQVxuICAgICAgLy8gcmV0cnkgcmVwYWlycyB0aGUgcmF3LXJvdyBzdGF0ZSBmcm9tIHRoYXQgZHVyYWJsZSBldmVudCBiZWZvcmUgQUNLLlxuICAgICAgY29uc3QgeyBkYXRhOiByZXBhaXJlZCwgZXJyb3I6IHJlcGFpckVycm9yIH0gPSBhd2FpdCBzdXBhYmFzZVxuICAgICAgICAuZnJvbShcInJhd19wYXltZW50X3Ntc1wiKVxuICAgICAgICAudXBkYXRlKHsgcGFyc2Vfc3RhdHVzOiBcInBhcnNlZFwiLCBwYXJzZV9zdGFydGVkX2F0OiBudWxsLCBwYXJzZV9sZWFzZV9pZDogbnVsbCB9KVxuICAgICAgICAuZXEoXCJpZFwiLCByYXdTbXNJZClcbiAgICAgICAgLnNlbGVjdChcImlkXCIpXG4gICAgICAgIC5tYXliZVNpbmdsZSgpO1xuICAgICAgaWYgKHJlcGFpckVycm9yKSB0aHJvdyByZXBhaXJFcnJvcjtcbiAgICAgIGlmIChyZXBhaXJlZD8uaWQgIT09IHJhd1Ntc0lkKSB7XG4gICAgICAgIHRocm93IG5ldyBQdWJsaWNFcnJvcihcInJlY2VpcHRfcGFyc2Vfc3RhdGVfdW5hdmFpbGFibGVcIiwgNTAzKTtcbiAgICAgIH1cbiAgICAgIGNvbnN0IHsgZGF0YTogYWxsb2NhdGlvbiwgZXJyb3I6IGFsbG9jYXRpb25FcnJvciB9ID1cbiAgICAgICAgZXhpc3RpbmcuYWxsb2NhdGlvbl9zdGF0dXMgPT09IFwidW5hbGxvY2F0ZWRcIlxuICAgICAgICAgID8gYXdhaXQgc3VwYWJhc2UucnBjKFwiYWxsb2NhdGVfcGFyc2VkX3BheW1lbnRfZXZlbnRcIiwge1xuICAgICAgICAgICAgZXZlbnRfaWQ6IGV4aXN0aW5nLmlkLFxuICAgICAgICAgIH0pXG4gICAgICAgICAgOiB7IGRhdGE6IGV4aXN0aW5nLmFsbG9jYXRpb25fc3RhdHVzLCBlcnJvcjogbnVsbCB9O1xuICAgICAgaWYgKGFsbG9jYXRpb25FcnJvcikgdGhyb3cgYWxsb2NhdGlvbkVycm9yO1xuICAgICAgY29uc3QgZmluYWxpdHkgPSBhd2FpdCBmaW5hbGl0eVN0YXR1cyhzdXBhYmFzZSk7XG4gICAgICByZXR1cm4ganNvblJlc3BvbnNlKHtcbiAgICAgICAgb2s6IHRydWUsXG4gICAgICAgIHBhcnNlZF9ldmVudF9pZDogZXhpc3RpbmcuaWQsXG4gICAgICAgIGFsbG9jYXRpb25fc3RhdHVzOiBhbGxvY2F0aW9uLFxuICAgICAgICBmaW5hbGl0eSxcbiAgICAgICAgcmVwbGF5OiB0cnVlLFxuICAgICAgfSk7XG4gICAgfVxuXG4gICAgbGVhc2VJZCA9IGNyeXB0by5yYW5kb21VVUlEKCk7XG4gICAgY29uc3QgeyBkYXRhOiByYXcsIGVycm9yOiBjbGFpbUVycm9yIH0gPSBhd2FpdCBzdXBhYmFzZS5ycGMoXG4gICAgICBcImNsYWltX3Jhd19wYXltZW50X3Ntc19mb3JfcGFyc2VcIixcbiAgICAgIHsgcF9yYXdfc21zX2lkOiByYXdTbXNJZCwgcF9sZWFzZV9pZDogbGVhc2VJZCB9LFxuICAgICk7XG4gICAgaWYgKGNsYWltRXJyb3IpIHRocm93IGNsYWltRXJyb3I7XG4gICAgaWYgKHR5cGVvZiByYXcgIT09IFwib2JqZWN0XCIgfHwgcmF3ID09IG51bGwgfHwgQXJyYXkuaXNBcnJheShyYXcpKSB7XG4gICAgICByZXR1cm4ganNvblJlc3BvbnNlKHsgb2s6IHRydWUsIGFsbG9jYXRpb25fc3RhdHVzOiBcInByb2Nlc3NpbmdcIiB9LCAyMDIpO1xuICAgIH1cbiAgICBjb25zdCBwYXJzZWQgPSBwYXJzZU1vbW9TbXMoXG4gICAgICBTdHJpbmcocmF3LnJhd19zZW5kZXIgPz8gXCJcIiksXG4gICAgICBTdHJpbmcocmF3LnJhd19ib2R5ID8/IFwiXCIpLFxuICAgICk7XG4gICAgY29uc3QgeyBkYXRhOiBldmVudCwgZXJyb3I6IGluc2VydEVycm9yIH0gPSBhd2FpdCBzdXBhYmFzZVxuICAgICAgLmZyb20oXCJwYXJzZWRfcGF5bWVudF9ldmVudHNcIilcbiAgICAgIC5pbnNlcnQoe1xuICAgICAgICByYXdfc21zX2lkOiByYXdTbXNJZCxcbiAgICAgICAgY29sbGVjdGlvbl9pZDogcmF3LmNvbGxlY3Rpb25faWQgPz8gbnVsbCxcbiAgICAgICAgcmVjZWl2ZXJfdXNlcl9pZDogcmF3LnJlY2VpdmVyX3VzZXJfaWQsXG4gICAgICAgIGlzX21vYmlsZV9tb25leV9wYXltZW50OiBwYXJzZWQuaXNfbW9iaWxlX21vbmV5X3BheW1lbnQsXG4gICAgICAgIG5ldHdvcms6IHBhcnNlZC5uZXR3b3JrLFxuICAgICAgICBkaXJlY3Rpb246IHBhcnNlZC5kaXJlY3Rpb24sXG4gICAgICAgIGFtb3VudF9yd2Y6IHBhcnNlZC5hbW91bnRfcndmLFxuICAgICAgICBjdXJyZW5jeTogcGFyc2VkLmN1cnJlbmN5LFxuICAgICAgICB0cmFuc2FjdGlvbl9pZDogcGFyc2VkLnRyYW5zYWN0aW9uX2lkLFxuICAgICAgICBzZW5kZXJfbmFtZTogcGFyc2VkLnNlbmRlcl9uYW1lLFxuICAgICAgICBwYXllcl9sYXN0MzogcGFyc2VkLnBheWVyX2xhc3QzLFxuICAgICAgICBwYXllcl9tYXRjaF9rZXk6IHBhcnNlZC5zZW5kZXJfbmFtZSAmJiBwYXJzZWQucGF5ZXJfbGFzdDNcbiAgICAgICAgICA/IGF3YWl0IHNoYTI1NkhleChcbiAgICAgICAgICAgIGAke25vcm1hbGl6ZU1vbW9OYW1lKHBhcnNlZC5zZW5kZXJfbmFtZSl9fCR7cGFyc2VkLnBheWVyX2xhc3QzfWAsXG4gICAgICAgICAgKVxuICAgICAgICAgIDogbnVsbCxcbiAgICAgICAgd2FsbGV0X2JhbGFuY2VfcndmOiBwYXJzZWQud2FsbGV0X2JhbGFuY2VfcndmLFxuICAgICAgICBzZW5kZXJfcGhvbmVfaGFzaDogYXdhaXQgaGFzaFBob25lKHBhcnNlZC5zZW5kZXJfcGhvbmUpLFxuICAgICAgICByZWNlaXZlcl9waG9uZV9oYXNoOiByYXcucmVjZWl2ZXJfbW9tb19udW1iZXJfaGFzaCA/PyBudWxsLFxuICAgICAgICB0cmFuc2FjdGlvbl90aW1lOiBwYXJzZWQudHJhbnNhY3Rpb25fdGltZSA/PyByYXcucmVjZWl2ZWRfYXRfZGV2aWNlID8/XG4gICAgICAgICAgcmF3LmluZ2VzdGVkX2F0LFxuICAgICAgICBkZXRlY3RlZF91c2VyX3B1YmxpY19pZDogcGFyc2VkLmRldGVjdGVkX3VzZXJfcHVibGljX2lkLFxuICAgICAgICBjb25maWRlbmNlOiBwYXJzZWQuY29uZmlkZW5jZSxcbiAgICAgICAgcGFyc2VyX21vZGVsOiBcImNvbGxlY3QtZGV0ZXJtaW5pc3RpYy1tb21vLXYyXCIsXG4gICAgICAgIHBhcnNlcl9zY2hlbWFfdmVyc2lvbjogXCJjb2xsZWN0LnNtc19wYXJzZXIudjRcIixcbiAgICAgICAgcGFyc2VkX2pzb246IHtcbiAgICAgICAgICAuLi5wYXJzZWQsXG4gICAgICAgICAgc2VuZGVyX3Bob25lOiBwYXJzZWQuc2VuZGVyX3Bob25lID8gXCJbaGFzaGVkXVwiIDogbnVsbCxcbiAgICAgICAgICBzZW5kZXJfbmFtZTogcGFyc2VkLnNlbmRlcl9uYW1lID8gXCJbcHJpdmF0ZV1cIiA6IG51bGwsXG4gICAgICAgIH0sXG4gICAgICAgIGFsbG9jYXRpb25fc3RhdHVzOiBcInVuYWxsb2NhdGVkXCIsXG4gICAgICB9KVxuICAgICAgLnNlbGVjdChcImlkXCIpXG4gICAgICAuc2luZ2xlKCk7XG4gICAgaWYgKGluc2VydEVycm9yKSB0aHJvdyBpbnNlcnRFcnJvcjtcbiAgICBjb25zdCB7IGRhdGE6IGNvbXBsZXRlZCwgZXJyb3I6IGNvbXBsZXRpb25FcnJvciB9ID0gYXdhaXQgc3VwYWJhc2VcbiAgICAgIC5mcm9tKFwicmF3X3BheW1lbnRfc21zXCIpXG4gICAgICAudXBkYXRlKHtcbiAgICAgICAgcGFyc2Vfc3RhdHVzOiBcInBhcnNlZFwiLFxuICAgICAgICBwYXJzZV9zdGFydGVkX2F0OiBudWxsLFxuICAgICAgICBwYXJzZV9sZWFzZV9pZDogbnVsbCxcbiAgICAgIH0pXG4gICAgICAuZXEoXCJpZFwiLCByYXdTbXNJZClcbiAgICAgIC5lcShcInBhcnNlX2xlYXNlX2lkXCIsIGxlYXNlSWQpXG4gICAgICAuc2VsZWN0KFwiaWRcIilcbiAgICAgIC5tYXliZVNpbmdsZSgpO1xuICAgIGlmIChjb21wbGV0aW9uRXJyb3IpIHRocm93IGNvbXBsZXRpb25FcnJvcjtcbiAgICAvLyBQb3N0Z1JFU1QgcmVwb3J0cyB6ZXJvIG1hdGNoZWQgcm93cyBhcyBhIHN1Y2Nlc3NmdWwgVVBEQVRFLiBBIHN0YWxlXG4gICAgLy8gd29ya2VyIG11c3Qgbm90IHJldHVybiBhIGNvbXBsZXRlZCBwYXJzZSBhZnRlciBhbm90aGVyIHdvcmtlciBvd25zIGl0LlxuICAgIGlmIChjb21wbGV0ZWQ/LmlkICE9PSByYXdTbXNJZCkge1xuICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwicmVjZWlwdF9wYXJzZV9sZWFzZV9sb3N0XCIsIDUwMyk7XG4gICAgfVxuICAgIGNvbnN0IHsgZGF0YTogYWxsb2NhdGlvbiwgZXJyb3I6IGFsbG9jYXRpb25FcnJvciB9ID0gYXdhaXQgc3VwYWJhc2UucnBjKFxuICAgICAgXCJhbGxvY2F0ZV9wYXJzZWRfcGF5bWVudF9ldmVudFwiLFxuICAgICAgeyBldmVudF9pZDogZXZlbnQuaWQgfSxcbiAgICApO1xuICAgIGlmIChhbGxvY2F0aW9uRXJyb3IpIHRocm93IGFsbG9jYXRpb25FcnJvcjtcbiAgICBjb25zdCBmaW5hbGl0eSA9IGF3YWl0IGZpbmFsaXR5U3RhdHVzKHN1cGFiYXNlKTtcbiAgICByZXR1cm4ganNvblJlc3BvbnNlKHtcbiAgICAgIG9rOiB0cnVlLFxuICAgICAgcGFyc2VkX2V2ZW50X2lkOiBldmVudC5pZCxcbiAgICAgIGFsbG9jYXRpb25fc3RhdHVzOiBhbGxvY2F0aW9uLFxuICAgICAgZmluYWxpdHksXG4gICAgICBwYXJzZXJfbW9kZWw6IFwiY29sbGVjdC1kZXRlcm1pbmlzdGljLW1vbW8tdjJcIixcbiAgICB9KTtcbiAgfSBjYXRjaCAoZXJyb3IpIHtcbiAgICBpZiAocmF3U21zSWQgJiYgbGVhc2VJZCkge1xuICAgICAgYXdhaXQgc2VydmljZUNsaWVudCgpLmZyb20oXCJyYXdfcGF5bWVudF9zbXNcIikudXBkYXRlKHtcbiAgICAgICAgcGFyc2Vfc3RhdHVzOiBcImZhaWxlZFwiLFxuICAgICAgICBwYXJzZV9zdGFydGVkX2F0OiBudWxsLFxuICAgICAgICBwYXJzZV9sZWFzZV9pZDogbnVsbCxcbiAgICAgIH0pLmVxKFwiaWRcIiwgcmF3U21zSWQpLmVxKFwicGFyc2VfbGVhc2VfaWRcIiwgbGVhc2VJZCk7XG4gICAgfVxuICAgIGNvbnN0IGZhaWx1cmU9cHVibGljRmFpbHVyZShlcnJvcik7XG4gICAgcmV0dXJuIGpzb25SZXNwb25zZSh7ZXJyb3I6ZmFpbHVyZS5lcnJvcn0sZmFpbHVyZS5zdGF0dXMpO1xuICB9XG59KTtcbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQSxTQUFRLFdBQVcsRUFBQyxhQUFhLEVBQUMsc0JBQXNCLEVBQUMsV0FBVyxRQUFPLG9DQUFvQztBQUMvRyxTQUNFLFdBQVcsRUFDWCxZQUFZLFFBQ1AscUJBQXFCO0FBQzVCLFNBQVMs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
// denoCacheMetadata=1229397932374527406,12052721118394237177