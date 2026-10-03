import { serviceClient } from "../_shared/supabase.ts";
import { createGatewayHandler } from "./handler.ts";

// No user authentication/bootstrap or handset credentials. Signature checks
// precede the one narrow service RPC selected by the fixed action allowlist.
Deno.serve(createGatewayHandler({
  rpc: async (name, args, signal) =>
    await serviceClient().rpc(name, args).abortSignal(signal),
}));
