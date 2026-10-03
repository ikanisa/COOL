import { corsHeaders, jsonResponse, requireEnv } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import { acceptReceipt } from "../_shared/receipt_ingestion.ts";
import { fetchJson, PublicError, publicFailure } from "../_shared/production_contract.ts";
import { elapsedReceiptMs, recordReceiptMetric } from "../_shared/operational_metrics.ts";
Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }
  if (req.method !== "POST") {
    return jsonResponse({
      error: "method_not_allowed"
    }, 405);
  }
  const started = performance.now();
  let authenticated = false, durableAccepted = false;
  let service;
  const metric = async (code, duration)=>{
    const recorded = await recordReceiptMetric(code, duration, async (event, ms, signal)=>{
      if (!service) return false;
      const result = await service.rpc("record_operational_metric_v1", {
        p_event_code: event,
        p_duration_ms: ms
      }).abortSignal(signal);
      return result.error === null && result.data === true;
    });
    if (!recorded) console.warn("collect_operational_metric_unavailable");
  };
  try {
    const backend = serviceClient();
    service = backend;
    const ack = await acceptReceipt(req, {
      owner: async (r)=>{
        const owner = (await requireUser(r.headers.get("authorization"))).user.id;
        authenticated = true;
        return owner;
      },
      version: async ()=>{
        const r = await backend.rpc("attested_sms_contract_version");
        if (r.error) throw new PublicError("receipt_contract_unavailable", 503);
        return r.data;
      },
      accept: async (p)=>{
        const r = await backend.rpc("accept_attested_receipt_v2", p);
        if (r.error) {
          throw new PublicError("receipt_acceptance_unavailable", 503);
        }
        return r.data;
      },
      process: async (id)=>{
        // Entry into process follows the validated durable acceptance receipt.
        durableAccepted = true;
        const parseStarted = performance.now();
        let accepted = false;
        try {
          const r = await fetchJson(`${requireEnv("SUPABASE_URL")}/functions/v1/parse-payment-sms`, {
            method: "POST",
            headers: {
              apikey: requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
              "Content-Type": "application/json",
              "x-collect-signature": requireEnv("INTERNAL_FUNCTION_SECRET")
            },
            body: JSON.stringify({
              raw_sms_id: id
            })
          });
          accepted = r.ok && r.data !== null && typeof r.data === "object" && r.data.ok === true;
          return accepted;
        } finally{
          await metric(accepted ? "receipt_processing_accepted" : "receipt_processing_deferred", elapsedReceiptMs(parseStarted));
        }
      }
    });
    await metric("receipt_ack_generated", elapsedReceiptMs(started));
    return jsonResponse({
      ok: true,
      receipt: ack,
      evidence_level: "sms_observed",
      processing: "accepted"
    });
  } catch (error) {
    if (authenticated && !durableAccepted) {
      await metric("receipt_rejected", elapsedReceiptMs(started));
    }
    const f = publicFailure(error);
    return jsonResponse({
      error: f.error
    }, f.status);
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2luZ2VzdC1wYXltZW50LXNtcy9pbmRleC50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgeyBjb3JzSGVhZGVycywganNvblJlc3BvbnNlLCByZXF1aXJlRW52IH0gZnJvbSBcIi4uL19zaGFyZWQvY29ycy50c1wiO1xuaW1wb3J0IHsgcmVxdWlyZVVzZXIsIHNlcnZpY2VDbGllbnQgfSBmcm9tIFwiLi4vX3NoYXJlZC9zdXBhYmFzZS50c1wiO1xuaW1wb3J0IHsgYWNjZXB0UmVjZWlwdCB9IGZyb20gXCIuLi9fc2hhcmVkL3JlY2VpcHRfaW5nZXN0aW9uLnRzXCI7XG5pbXBvcnQge1xuICBmZXRjaEpzb24sXG4gIFB1YmxpY0Vycm9yLFxuICBwdWJsaWNGYWlsdXJlLFxufSBmcm9tIFwiLi4vX3NoYXJlZC9wcm9kdWN0aW9uX2NvbnRyYWN0LnRzXCI7XG5pbXBvcnQge1xuICBlbGFwc2VkUmVjZWlwdE1zLFxuICBSZWNlaXB0TWV0cmljQ29kZSxcbiAgcmVjb3JkUmVjZWlwdE1ldHJpYyxcbn0gZnJvbSBcIi4uL19zaGFyZWQvb3BlcmF0aW9uYWxfbWV0cmljcy50c1wiO1xuXG5EZW5vLnNlcnZlKGFzeW5jIChyZXE6IFJlcXVlc3QpID0+IHtcbiAgaWYgKHJlcS5tZXRob2QgPT09IFwiT1BUSU9OU1wiKSB7XG4gICAgcmV0dXJuIG5ldyBSZXNwb25zZShcIm9rXCIsIHsgaGVhZGVyczogY29yc0hlYWRlcnMgfSk7XG4gIH1cbiAgaWYgKHJlcS5tZXRob2QgIT09IFwiUE9TVFwiKSB7XG4gICAgcmV0dXJuIGpzb25SZXNwb25zZSh7IGVycm9yOiBcIm1ldGhvZF9ub3RfYWxsb3dlZFwiIH0sIDQwNSk7XG4gIH1cbiAgY29uc3Qgc3RhcnRlZCA9IHBlcmZvcm1hbmNlLm5vdygpO1xuICBsZXQgYXV0aGVudGljYXRlZCA9IGZhbHNlLCBkdXJhYmxlQWNjZXB0ZWQgPSBmYWxzZTtcbiAgbGV0IHNlcnZpY2U6IFJldHVyblR5cGU8dHlwZW9mIHNlcnZpY2VDbGllbnQ+IHwgdW5kZWZpbmVkO1xuICBjb25zdCBtZXRyaWMgPSBhc3luYyAoY29kZTogUmVjZWlwdE1ldHJpY0NvZGUsIGR1cmF0aW9uOiBudW1iZXIgfCBudWxsKSA9PiB7XG4gICAgY29uc3QgcmVjb3JkZWQgPSBhd2FpdCByZWNvcmRSZWNlaXB0TWV0cmljKFxuICAgICAgY29kZSxcbiAgICAgIGR1cmF0aW9uLFxuICAgICAgYXN5bmMgKGV2ZW50LCBtcywgc2lnbmFsKSA9PiB7XG4gICAgICAgIGlmICghc2VydmljZSkgcmV0dXJuIGZhbHNlO1xuICAgICAgICBjb25zdCByZXN1bHQgPSBhd2FpdCBzZXJ2aWNlLnJwYyhcInJlY29yZF9vcGVyYXRpb25hbF9tZXRyaWNfdjFcIiwge1xuICAgICAgICAgIHBfZXZlbnRfY29kZTogZXZlbnQsXG4gICAgICAgICAgcF9kdXJhdGlvbl9tczogbXMsXG4gICAgICAgIH0pLmFib3J0U2lnbmFsKHNpZ25hbCk7XG4gICAgICAgIHJldHVybiByZXN1bHQuZXJyb3IgPT09IG51bGwgJiYgcmVzdWx0LmRhdGEgPT09IHRydWU7XG4gICAgICB9LFxuICAgICk7XG4gICAgaWYgKCFyZWNvcmRlZCkgY29uc29sZS53YXJuKFwiY29sbGVjdF9vcGVyYXRpb25hbF9tZXRyaWNfdW5hdmFpbGFibGVcIik7XG4gIH07XG4gIHRyeSB7XG4gICAgY29uc3QgYmFja2VuZCA9IHNlcnZpY2VDbGllbnQoKTtcbiAgICBzZXJ2aWNlID0gYmFja2VuZDtcbiAgICBjb25zdCBhY2sgPSBhd2FpdCBhY2NlcHRSZWNlaXB0KHJlcSwge1xuICAgICAgb3duZXI6IGFzeW5jIChyKSA9PiB7XG4gICAgICAgIGNvbnN0IG93bmVyID1cbiAgICAgICAgICAoYXdhaXQgcmVxdWlyZVVzZXIoci5oZWFkZXJzLmdldChcImF1dGhvcml6YXRpb25cIikpKS51c2VyLmlkO1xuICAgICAgICBhdXRoZW50aWNhdGVkID0gdHJ1ZTtcbiAgICAgICAgcmV0dXJuIG93bmVyO1xuICAgICAgfSxcbiAgICAgIHZlcnNpb246IGFzeW5jICgpID0+IHtcbiAgICAgICAgY29uc3QgciA9IGF3YWl0IGJhY2tlbmQucnBjKFwiYXR0ZXN0ZWRfc21zX2NvbnRyYWN0X3ZlcnNpb25cIik7XG4gICAgICAgIGlmIChyLmVycm9yKSB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyZWNlaXB0X2NvbnRyYWN0X3VuYXZhaWxhYmxlXCIsIDUwMyk7XG4gICAgICAgIHJldHVybiByLmRhdGE7XG4gICAgICB9LFxuICAgICAgYWNjZXB0OiBhc3luYyAocCkgPT4ge1xuICAgICAgICBjb25zdCByID0gYXdhaXQgYmFja2VuZC5ycGMoXCJhY2NlcHRfYXR0ZXN0ZWRfcmVjZWlwdF92MlwiLCBwKTtcbiAgICAgICAgaWYgKHIuZXJyb3IpIHtcbiAgICAgICAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyZWNlaXB0X2FjY2VwdGFuY2VfdW5hdmFpbGFibGVcIiwgNTAzKTtcbiAgICAgICAgfVxuICAgICAgICByZXR1cm4gci5kYXRhO1xuICAgICAgfSxcbiAgICAgIHByb2Nlc3M6IGFzeW5jIChpZCkgPT4ge1xuICAgICAgICAvLyBFbnRyeSBpbnRvIHByb2Nlc3MgZm9sbG93cyB0aGUgdmFsaWRhdGVkIGR1cmFibGUgYWNjZXB0YW5jZSByZWNlaXB0LlxuICAgICAgICBkdXJhYmxlQWNjZXB0ZWQgPSB0cnVlO1xuICAgICAgICBjb25zdCBwYXJzZVN0YXJ0ZWQgPSBwZXJmb3JtYW5jZS5ub3coKTtcbiAgICAgICAgbGV0IGFjY2VwdGVkID0gZmFsc2U7XG4gICAgICAgIHRyeSB7XG4gICAgICAgICAgY29uc3QgciA9IGF3YWl0IGZldGNoSnNvbihcbiAgICAgICAgICAgIGAke3JlcXVpcmVFbnYoXCJTVVBBQkFTRV9VUkxcIil9L2Z1bmN0aW9ucy92MS9wYXJzZS1wYXltZW50LXNtc2AsXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgICAgICAgICAgIGhlYWRlcnM6IHtcbiAgICAgICAgICAgICAgICBhcGlrZXk6IHJlcXVpcmVFbnYoXCJTVVBBQkFTRV9TRVJWSUNFX1JPTEVfS0VZXCIpLFxuICAgICAgICAgICAgICAgIFwiQ29udGVudC1UeXBlXCI6IFwiYXBwbGljYXRpb24vanNvblwiLFxuICAgICAgICAgICAgICAgIFwieC1jb2xsZWN0LXNpZ25hdHVyZVwiOiByZXF1aXJlRW52KFwiSU5URVJOQUxfRlVOQ1RJT05fU0VDUkVUXCIpLFxuICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICBib2R5OiBKU09OLnN0cmluZ2lmeSh7IHJhd19zbXNfaWQ6IGlkIH0pLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICApO1xuICAgICAgICAgIGFjY2VwdGVkID0gci5vayAmJiByLmRhdGEgIT09IG51bGwgJiYgdHlwZW9mIHIuZGF0YSA9PT0gXCJvYmplY3RcIiAmJlxuICAgICAgICAgICAgKHIuZGF0YSBhcyBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPikub2sgPT09IHRydWU7XG4gICAgICAgICAgcmV0dXJuIGFjY2VwdGVkO1xuICAgICAgICB9IGZpbmFsbHkge1xuICAgICAgICAgIGF3YWl0IG1ldHJpYyhcbiAgICAgICAgICAgIGFjY2VwdGVkXG4gICAgICAgICAgICAgID8gXCJyZWNlaXB0X3Byb2Nlc3NpbmdfYWNjZXB0ZWRcIlxuICAgICAgICAgICAgICA6IFwicmVjZWlwdF9wcm9jZXNzaW5nX2RlZmVycmVkXCIsXG4gICAgICAgICAgICBlbGFwc2VkUmVjZWlwdE1zKHBhcnNlU3RhcnRlZCksXG4gICAgICAgICAgKTtcbiAgICAgICAgfVxuICAgICAgfSxcbiAgICB9KTtcbiAgICBhd2FpdCBtZXRyaWMoXCJyZWNlaXB0X2Fja19nZW5lcmF0ZWRcIiwgZWxhcHNlZFJlY2VpcHRNcyhzdGFydGVkKSk7XG4gICAgcmV0dXJuIGpzb25SZXNwb25zZSh7XG4gICAgICBvazogdHJ1ZSxcbiAgICAgIHJlY2VpcHQ6IGFjayxcbiAgICAgIGV2aWRlbmNlX2xldmVsOiBcInNtc19vYnNlcnZlZFwiLFxuICAgICAgcHJvY2Vzc2luZzogXCJhY2NlcHRlZFwiLFxuICAgIH0pO1xuICB9IGNhdGNoIChlcnJvcikge1xuICAgIGlmIChhdXRoZW50aWNhdGVkICYmICFkdXJhYmxlQWNjZXB0ZWQpIHtcbiAgICAgIGF3YWl0IG1ldHJpYyhcInJlY2VpcHRfcmVqZWN0ZWRcIiwgZWxhcHNlZFJlY2VpcHRNcyhzdGFydGVkKSk7XG4gICAgfVxuICAgIGNvbnN0IGYgPSBwdWJsaWNGYWlsdXJlKGVycm9yKTtcbiAgICByZXR1cm4ganNvblJlc3BvbnNlKHsgZXJyb3I6IGYuZXJyb3IgfSwgZi5zdGF0dXMpO1xuICB9XG59KTtcbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQSxTQUFTLFdBQVcsRUFBRSxZQUFZLEVBQUUsVUFBVSxRQUFRLHFCQUFxQjtBQUMzRSxTQUFTLFdBQVcsRUFBRSxhQUFhLFFBQVEseUJBQXlCO0FBQ3BFLFNBQVMsYUFBYSxRQUFRLGtDQUFrQztBQUNoRSxTQUNFLFNBQVMsRUFDVCxXQUFXLEVBQ1gsYUFBYSxRQUNSLG9DQUFvQztBQUMzQyxTQUNFLGdCQUFnQixFQUVoQixtQkFBbUIsUUFDZCxvQ0FBb0M7QUFFM0MsS0FBSyxLQUFLLENBQUMsT0FBTztFQUNoQixJQUFJLElBQUksTUFBTSxLQUFLLFdBQVc7SUFDNUIsT0FBTyxJQUFJLFNBQVMsTUFBTTtNQUFFLFNBQVM7SUFBWTtFQUNuRDtFQUNBLElBQUksSUFBSSxNQUFNLEtBQUssUUFBUTtJQUN6QixPQUFPLGFBQWE7TUFBRSxPQUFPO0lBQXFCLEdBQUc7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
// denoCacheMetadata=12633030646299555040,5733539446990963155