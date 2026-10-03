import { serviceClient } from "../_shared/supabase.ts";
import { createSuccessorGatewayHandler } from "./handler.ts";
// Fixed family/action allowlist and device signature precede each service RPC.
// This endpoint prepares the same physical Android sender; it is not a sender.
Deno.serve(createSuccessorGatewayHandler({rpc: async (name, args, signal) => await serviceClient().rpc(name, args).abortSignal(signal)}));
