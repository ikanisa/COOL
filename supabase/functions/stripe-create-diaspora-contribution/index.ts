import {
  corsHeaders,
  jsonResponse,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import {
  appendPaymentIntentRailOptions,
  bankRailForRegion,
  currencyForRegion,
  ensureStripeCustomer,
  stripeRequest,
} from "../_shared/stripe.ts";

type ContributionRequest = {
  collection_id?: string;
  amount_minor?: number;
  region?: string;
  stripe_payment_method_id?: string;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const { supabase: userSupabase, user } = await requireUser(
      req.headers.get("authorization"),
    );
    const payload = await req.json() as ContributionRequest;
    const collectionId = payload.collection_id?.trim();
    const amountMinor = Number(payload.amount_minor ?? 0);
    const region = payload.region?.trim().toLowerCase() ?? "";
    const rail = bankRailForRegion(region);
    const currency = currencyForRegion(region);
    if (!collectionId || amountMinor <= 0) {
      return jsonResponse({ error: "Invalid diaspora contribution" }, 400);
    }

    const collection = await userSupabase
      .from("member_collections_view")
      .select("id,title,collection_type,diaspora_enabled,diaspora_regions")
      .eq("id", collectionId)
      .maybeSingle();
    if (collection.error || !collection.data) {
      return jsonResponse({ error: "Group is not available" }, 404);
    }
    const group = collection.data as {
      collection_type: string;
      diaspora_enabled: boolean;
      diaspora_regions?: string[];
    };
    const allowedRegions = Array.isArray(group.diaspora_regions)
      ? group.diaspora_regions
      : [];
    if (!group.diaspora_enabled || !allowedRegions.includes(region)) {
      return jsonResponse(
        { error: "Diaspora contributions are not enabled" },
        403,
      );
    }

    const customerId = await ensureStripeCustomer(user.id);
    const body = new URLSearchParams({
      amount: String(amountMinor),
      currency: currency.toLowerCase(),
      customer: customerId,
      "metadata[collect_user_id]": user.id,
      "metadata[collect_collection_id]": collectionId,
      "metadata[collect_region]": region,
    });
    appendPaymentIntentRailOptions(body, rail);
    const canUseSavedBankMethod = rail === "us_bank_account" ||
      rail === "acss_debit";
    if (canUseSavedBankMethod && payload.stripe_payment_method_id?.trim()) {
      body.set("payment_method", payload.stripe_payment_method_id.trim());
    }

    const paymentIntent = await stripeRequest<{
      id: string;
      client_secret: string;
      status: string;
    }>("payment_intents", body);
    const service = serviceClient();
    const inserted = await service
      .from("diaspora_contribution_intents")
      .insert({
        collection_id: collectionId,
        contributor_user_id: user.id,
        stripe_customer_id: customerId,
        stripe_payment_method_id: canUseSavedBankMethod
          ? payload.stripe_payment_method_id?.trim() || null
          : null,
        stripe_payment_intent_id: paymentIntent.id,
        amount_minor: amountMinor,
        currency,
        region,
        method_type: rail,
        collection_type_snapshot: group.collection_type,
        status: paymentIntent.status === "processing"
          ? "processing"
          : paymentIntent.status === "succeeded"
          ? "succeeded"
          : "pending",
        livemode: Deno.env.get("STRIPE_LIVEMODE") === "true",
      })
      .select("id")
      .single();
    if (inserted.error || !inserted.data) {
      throw new Error("Diaspora contribution intent insert failed");
    }

    return jsonResponse({
      diaspora_contribution_intent_id: inserted.data.id,
      stripe_payment_intent_id: paymentIntent.id,
      client_secret: paymentIntent.client_secret,
      status: paymentIntent.status,
      method_type: rail,
      payment_method_name: rail === "us_bank_account"
        ? "ACH Direct Debit"
        : rail === "acss_debit"
        ? "Canadian Pre-authorized Debit"
        : rail === "customer_balance_gbp_bank_transfer"
        ? "GBP Bank Transfer"
        : "EUR Bank Transfer",
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
    return jsonResponse({ error: "Stripe diaspora contribution failed" }, 502);
  }
});
