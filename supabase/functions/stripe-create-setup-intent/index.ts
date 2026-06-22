import {
  corsHeaders,
  jsonResponse,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireUser } from "../_shared/supabase.ts";
import {
  currencyForRegion,
  ensureStripeCustomer,
  stripeRequest,
} from "../_shared/stripe.ts";

type SetupIntentRequest = {
  region?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const { user } = await requireUser(req.headers.get("authorization"));
    const payload = await req.json() as SetupIntentRequest;
    const region = payload.region?.trim().toLowerCase() ?? "";
    if (region !== "us" && region !== "ca") {
      return jsonResponse({
        error: "Saved bank setup is only enabled for domestic bank debits",
      }, 400);
    }
    const currency = currencyForRegion(region);
    const customerId = await ensureStripeCustomer(user.id);
    const body = new URLSearchParams({
      customer: customerId,
      usage: "off_session",
      "metadata[collect_user_id]": user.id,
      "metadata[collect_region]": region,
      "metadata[collect_currency]": currency,
    });
    if (region === "ca") {
      body.append("payment_method_types[]", "acss_debit");
      body.set("payment_method_options[acss_debit][currency]", "cad");
      body.set(
        "payment_method_options[acss_debit][mandate_options][payment_schedule]",
        "sporadic",
      );
      body.set(
        "payment_method_options[acss_debit][mandate_options][transaction_type]",
        "personal",
      );
      body.set(
        "payment_method_options[acss_debit][verification_method]",
        "microdeposits",
      );
    } else {
      body.append("payment_method_types[]", "us_bank_account");
      body.set(
        "payment_method_options[us_bank_account][verification_method]",
        "microdeposits",
      );
    }
    const setupIntent = await stripeRequest<{
      id: string;
      client_secret: string;
      status: string;
    }>("setup_intents", body);
    return jsonResponse({
      setup_intent_id: setupIntent.id,
      client_secret: setupIntent.client_secret,
      status: setupIntent.status,
      method_type: region === "ca" ? "acss_debit" : "us_bank_account",
      payment_method_name: region === "ca"
        ? "Canadian Pre-authorized Debit"
        : "ACH Direct Debit",
      region,
      currency,
    });
  } catch (error) {
    const message = safeErrorMessage(error);
    if (message === "Authentication required") {
      return jsonResponse({ error: message }, 401);
    }
    if (message === "Unsupported diaspora region") {
      return jsonResponse({ error: message }, 400);
    }
    return jsonResponse({ error: "Stripe setup intent failed" }, 502);
  }
});
