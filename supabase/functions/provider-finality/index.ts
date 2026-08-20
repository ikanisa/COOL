import { handleProviderFinalityRequest } from "../_shared/provider_finality_handler.ts";

Deno.serve((req) => handleProviderFinalityRequest(req));
