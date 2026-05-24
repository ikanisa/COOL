import {
  corsHeaders,
  jsonResponse,
  requireEnv,
  safeErrorMessage,
} from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { hashPhone, normalizeRwandaPhone, sha256Hex } from "../_shared/hash.ts";
import { Webhook } from "npm:standardwebhooks@1.0.0";

type SmsHookPayload = {
  user?: { phone?: string };
  sms?: { otp?: string };
  phone?: string;
  otp?: string;
  code?: string;
  token?: string;
};

async function verifyHookPayload(req: Request): Promise<SmsHookPayload> {
  const hookSecret = requireEnv("SEND_SMS_HOOK_SECRET");
  const rawBody = await req.text();
  const directSecret = req.headers.get("x-hook-secret") ??
    req.headers.get("x-collect-signature");
  if (directSecret && directSecret === hookSecret) {
    return JSON.parse(rawBody);
  }

  const standardWebhookSecret = hookSecret.replace(/^v1,whsec_/, "");
  try {
    return new Webhook(standardWebhookSecret).verify(
      rawBody,
      Object.fromEntries(req.headers),
    ) as SmsHookPayload;
  } catch (_error) {
    throw new Error("Unauthorized");
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const payload = await verifyHookPayload(req);
    const phone = normalizeRwandaPhone(payload.phone ?? payload.user?.phone);
    const otp = payload.sms?.otp ?? payload.otp ?? payload.code ??
      payload.token;
    if (!phone || !otp) {
      return jsonResponse({ error: "Missing phone or OTP" }, 400);
    }

    const supabase = serviceClient();
    const phoneHash = await hashPhone(phone);
    const ipHash = await sha256Hex(
      req.headers.get("x-forwarded-for") ?? "unknown",
    );
    const since = new Date(Date.now() - 10 * 60 * 1000).toISOString();
    const { count } = await supabase
      .from("otp_rate_limits")
      .select("id", { count: "exact", head: true })
      .eq("phone_hash", phoneHash)
      .gte("requested_at", since);
    if ((count ?? 0) >= 5) {
      return jsonResponse({ error: "Too many OTP requests" }, 429);
    }

    await supabase.from("otp_rate_limits").insert({
      phone_hash: phoneHash,
      ip_hash: ipHash,
    });

    const token = requireEnv("WHATSAPP_CLOUD_API_TOKEN");
    const phoneNumberId = requireEnv("WHATSAPP_PHONE_NUMBER_ID");
    const template = requireEnv("WHATSAPP_AUTH_TEMPLATE_NAME");

    const response = await fetch(
      `https://graph.facebook.com/v19.0/${phoneNumberId}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          messaging_product: "whatsapp",
          to: phone.replace("+", ""),
          type: "template",
          template: {
            name: template,
            language: { code: "en_US" },
            components: [{
              type: "body",
              parameters: [{ type: "text", text: String(otp) }],
            }],
          },
        }),
      },
    );

    if (!response.ok) {
      const safeStatus = response.status;
      return jsonResponse({
        error: "WhatsApp OTP send failed",
        status: safeStatus,
      }, 502);
    }

    return jsonResponse({});
  } catch (error) {
    if (error instanceof Error && error.message === "Unauthorized") {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }
    return jsonResponse({
      error: safeErrorMessage(error),
    }, 500);
  }
});
