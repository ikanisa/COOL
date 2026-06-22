import {
  corsHeaders,
  jsonResponse,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireUser } from "../_shared/supabase.ts";
import { ensureStripeCustomer } from "../_shared/stripe.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const { user } = await requireUser(req.headers.get("authorization"));
    const customerId = await ensureStripeCustomer(user.id);
    return jsonResponse({ stripe_customer_id: customerId });
  } catch (error) {
    const message = safeErrorMessage(error);
    if (message === "Authentication required") {
      return jsonResponse({ error: message }, 401);
    }
    return jsonResponse({ error: "Stripe customer setup failed" }, 502);
  }
});
