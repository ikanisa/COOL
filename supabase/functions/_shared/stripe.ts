import { requireEnv } from "./cors.ts";
import { serviceClient } from "./supabase.ts";

export const stripeApiVersion = "2026-02-25.clover";

export type StripeRegion = "eu" | "gb" | "us" | "ca";
export type StripeBankRail =
  | "customer_balance_eur_bank_transfer"
  | "customer_balance_gbp_bank_transfer"
  | "us_bank_account"
  | "acss_debit";

export function bankRailForRegion(region: string): StripeBankRail {
  switch (region.trim().toLowerCase()) {
    case "eu":
      return "customer_balance_eur_bank_transfer";
    case "gb":
    case "uk":
      return "customer_balance_gbp_bank_transfer";
    case "us":
      return "us_bank_account";
    case "ca":
      return "acss_debit";
    default:
      throw new Error("Unsupported diaspora region");
  }
}

export function currencyForRegion(region: string): string {
  switch (region.trim().toLowerCase()) {
    case "eu":
      return "EUR";
    case "gb":
    case "uk":
      return "GBP";
    case "us":
      return "USD";
    case "ca":
      return "CAD";
    default:
      throw new Error("Unsupported diaspora region");
  }
}

export function appendPaymentIntentRailOptions(
  body: URLSearchParams,
  rail: StripeBankRail,
) {
  if (rail === "us_bank_account") {
    body.append("payment_method_types[]", "us_bank_account");
    body.set(
      "payment_method_options[us_bank_account][verification_method]",
      "microdeposits",
    );
    return;
  }
  if (rail === "acss_debit") {
    body.append("payment_method_types[]", "acss_debit");
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
    return;
  }
  body.append("payment_method_types[]", "customer_balance");
  body.set(
    "payment_method_options[customer_balance][funding_type]",
    "bank_transfer",
  );
  const transferType = rail === "customer_balance_gbp_bank_transfer"
    ? "gb_bank_transfer"
    : "eu_bank_transfer";
  body.set(
    "payment_method_options[customer_balance][bank_transfer][type]",
    transferType,
  );
}

export async function stripeRequest<T>(
  path: string,
  body: URLSearchParams,
): Promise<T> {
  const response = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${requireEnv("STRIPE_SECRET_KEY")}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "Stripe-Version": stripeApiVersion,
    },
    body,
  });
  const payload = await response.json();
  if (!response.ok) {
    const message = payload?.error?.message ?? "Stripe request failed";
    throw new Error(String(message));
  }
  return payload as T;
}

export async function ensureStripeCustomer(userId: string): Promise<string> {
  const supabase = serviceClient();
  const existing = await supabase
    .from("stripe_customers")
    .select("stripe_customer_id")
    .eq("user_id", userId)
    .maybeSingle();
  if (existing.data?.stripe_customer_id) {
    return existing.data.stripe_customer_id as string;
  }

  const customer = await stripeRequest<{ id: string }>(
    "customers",
    new URLSearchParams({
      "metadata[collect_user_id]": userId,
    }),
  );

  await supabase.from("stripe_customers").upsert({
    user_id: userId,
    stripe_customer_id: customer.id,
    livemode: Deno.env.get("STRIPE_LIVEMODE") === "true",
    updated_at: new Date().toISOString(),
  });

  return customer.id;
}
