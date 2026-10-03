import { corsHeaders, jsonResponse, requireEnv } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import { acceptReceipt } from "../_shared/receipt_ingestion.ts";
import {
  fetchJson,
  PublicError,
  publicFailure,
} from "../_shared/production_contract.ts";
import {
  elapsedReceiptMs,
  ReceiptMetricCode,
  recordReceiptMetric,
} from "../_shared/operational_metrics.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }
  const started = performance.now();
  let authenticated = false, durableAccepted = false;
  let service: ReturnType<typeof serviceClient> | undefined;
  const metric = async (code: ReceiptMetricCode, duration: number | null) => {
    const recorded = await recordReceiptMetric(
      code,
      duration,
      async (event, ms, signal) => {
        if (!service) return false;
        const result = await service.rpc("record_operational_metric_v1", {
          p_event_code: event,
          p_duration_ms: ms,
        }).abortSignal(signal);
        return result.error === null && result.data === true;
      },
    );
    if (!recorded) console.warn("collect_operational_metric_unavailable");
  };
  try {
    const backend = serviceClient();
    service = backend;
    const ack = await acceptReceipt(req, {
      owner: async (r) => {
        const owner =
          (await requireUser(r.headers.get("authorization"))).user.id;
        authenticated = true;
        return owner;
      },
      version: async () => {
        const r = await backend.rpc("attested_sms_contract_version");
        if (r.error) throw new PublicError("receipt_contract_unavailable", 503);
        return r.data;
      },
      accept: async (p) => {
        const r = await backend.rpc("accept_attested_receipt_v2", p);
        if (r.error) {
          throw new PublicError("receipt_acceptance_unavailable", 503);
        }
        return r.data;
      },
      process: async (id) => {
        // Entry into process follows the validated durable acceptance receipt.
        durableAccepted = true;
        const parseStarted = performance.now();
        let accepted = false;
        try {
          const r = await fetchJson(
            `${requireEnv("SUPABASE_URL")}/functions/v1/parse-payment-sms`,
            {
              method: "POST",
              headers: {
                apikey: requireEnv("SUPABASE_SERVICE_ROLE_KEY"),
                "Content-Type": "application/json",
                "x-collect-signature": requireEnv("INTERNAL_FUNCTION_SECRET"),
              },
              body: JSON.stringify({ raw_sms_id: id }),
            },
          );
          accepted = r.ok && r.data !== null && typeof r.data === "object" &&
            (r.data as Record<string, unknown>).ok === true;
          return accepted;
        } finally {
          await metric(
            accepted
              ? "receipt_processing_accepted"
              : "receipt_processing_deferred",
            elapsedReceiptMs(parseStarted),
          );
        }
      },
    });
    await metric("receipt_ack_generated", elapsedReceiptMs(started));
    return jsonResponse({
      ok: true,
      receipt: ack,
      evidence_level: "sms_observed",
      processing: "accepted",
    });
  } catch (error) {
    if (authenticated && !durableAccepted) {
      await metric("receipt_rejected", elapsedReceiptMs(started));
    }
    const f = publicFailure(error);
    return jsonResponse({ error: f.error }, f.status);
  }
});
