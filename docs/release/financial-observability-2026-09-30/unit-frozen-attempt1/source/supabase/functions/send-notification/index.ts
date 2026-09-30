import { requireInternalRequest, serviceClient } from "../_shared/supabase.ts";
import { createNotificationHandler, requestDispatch } from "./handler.ts";

Deno.serve(createNotificationHandler({
  authorize: requireInternalRequest,
  enqueue: (name, parameters, signal) =>
    serviceClient().rpc(name, parameters).abortSignal(signal),
  dispatch: (signal) =>
    requestDispatch(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      Deno.env.get("INTERNAL_FUNCTION_SECRET") ?? "",
      signal,
    ),
}));
