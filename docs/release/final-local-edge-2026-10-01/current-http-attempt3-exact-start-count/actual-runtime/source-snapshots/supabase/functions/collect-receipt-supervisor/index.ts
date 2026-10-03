import { serviceClient } from "../_shared/supabase.ts";
import { createSupervisorHandler } from "./handler.ts";

// This endpoint accepts only the dedicated principal's exact signed envelope.
// The fixed handler allowlist and current DB authority precede each action.
Deno.serve(createSupervisorHandler({
  rpc: async (name, args, signal) =>
    await serviceClient().rpc(name, args).abortSignal(signal),
}));
