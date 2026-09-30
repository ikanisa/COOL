import { serviceClient } from "../_shared/supabase.ts";
import { createOtpHandler } from "./handler.ts";

// verifySmsHook remains the signed Standard Webhooks boundary in handler.ts.
Deno.serve(createOtpHandler({
  env: (name) => Deno.env.get(name),
  service: () => serviceClient(),
  fetch: (url, init) => fetch(url, init),
  now: () => Date.now(),
}));
