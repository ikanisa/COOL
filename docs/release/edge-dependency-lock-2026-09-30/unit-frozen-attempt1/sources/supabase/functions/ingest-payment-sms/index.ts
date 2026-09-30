import {corsHeaders,jsonResponse,requireEnv} from "../_shared/cors.ts";
import {requireUser,serviceClient} from "../_shared/supabase.ts";
import {acceptReceipt} from "../_shared/receipt_ingestion.ts";
import {PublicError,publicFailure,fetchJson} from "../_shared/production_contract.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok",{headers:corsHeaders});
  if (req.method !== "POST") return jsonResponse({error:"method_not_allowed"},405);
  try {
    const service=serviceClient();
    const ack=await acceptReceipt(req,{
      owner:async (r) => (await requireUser(r.headers.get("authorization"))).user.id,
      version:async () => {const r=await service.rpc("attested_sms_contract_version");if(r.error)throw new PublicError("receipt_contract_unavailable",503);return r.data;},
      accept:async (p) => {const r=await service.rpc("accept_attested_receipt_v2",p);if(r.error)throw new PublicError("receipt_acceptance_unavailable",503);return r.data;},
      process:async (id) => {
        const r=await fetchJson(`${requireEnv("SUPABASE_URL")}/functions/v1/parse-payment-sms`,{method:"POST",
          headers:{apikey:requireEnv("SUPABASE_SERVICE_ROLE_KEY"),"Content-Type":"application/json","x-collect-signature":requireEnv("INTERNAL_FUNCTION_SECRET")},
          body:JSON.stringify({raw_sms_id:id})});
        return r.ok && r.data!==null && typeof r.data==="object" && (r.data as Record<string,unknown>).ok===true;
      },
    });
    return jsonResponse({ok:true,receipt:ack,evidence_level:"sms_observed",processing:"accepted"});
  } catch(error) {const f=publicFailure(error);return jsonResponse({error:f.error},f.status);}
});
