import { serviceClient } from "../_shared/supabase.ts";
import { createExceptionWorkerHandler } from "./handler.ts";

// This credential belongs only to the trusted scheduler and Edge environment.
// It is never provisioned to a supervisor identity, handset or Admin bundle.
Deno.serve(createExceptionWorkerHandler({
  secret: () =>
    Deno.env.get("SUPABASE_URL") === "https://lhbowpbcpwoiparwnwgt.supabase.co"
      ? Deno.env.get("COLLECT_RECEIPT_EXCEPTION_WORKER_SECRET") ?? ""
      : "",
  rpc: async (name, args, signal) =>
    await serviceClient().rpc(name, args).abortSignal(signal),
}));
