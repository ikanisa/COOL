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

const otpDeliveryUnavailable =
  "WhatsApp OTP delivery is temporarily unavailable";
const defaultWhatsAppGraphApiVersion = "v25.0";

class PublicHookError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = "PublicHookError";
  }
}

function whatsappAuthTemplateComponents(otp: string) {
  const otpText = String(otp);
  return [
    {
      type: "body",
      parameters: [{ type: "text", text: otpText }],
    },
    {
      type: "button",
      sub_type: "url",
      index: "0",
      parameters: [{ type: "text", text: otpText }],
    },
  ];
}

function whatsappGraphApiVersion() {
  const configured = Deno.env.get("WHATSAPP_GRAPH_API_VERSION")?.trim();
  if (!configured) return defaultWhatsAppGraphApiVersion;
  return configured.startsWith("v") ? configured : `v${configured}`;
}

async function verifyHookPayload(req: Request): Promise<SmsHookPayload> {
  const hookSecret = requireEnv("SEND_SMS_HOOK_SECRET");
  const rawBody = await req.text();
  const directSecret = req.headers.get("x-hook-secret") ??
    req.headers.get("x-collect-signature");
  if (directSecret && directSecret === hookSecret) {
    try {
      return JSON.parse(rawBody);
    } catch (_error) {
      throw new PublicHookError("Invalid OTP hook payload", 400);
    }
  }

  const standardWebhookSecret = hookSecret.replace(/^v1,whsec_/, "");
  try {
    return new Webhook(standardWebhookSecret).verify(
      rawBody,
      Object.fromEntries(req.headers),
    ) as SmsHookPayload;
  } catch (_error) {
    throw new PublicHookError("Unauthorized", 401);
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
      return jsonResponse({ error: "Invalid OTP hook payload" }, 400);
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
    const graphApiVersion = whatsappGraphApiVersion();

    const response = await fetch(
      `https://graph.facebook.com/${graphApiVersion}/${phoneNumberId}/messages`,
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
            components: whatsappAuthTemplateComponents(String(otp)),
          },
        }),
      },
    );

    if (!response.ok) {
      const safeStatus = response.status;
      console.error("WhatsApp OTP send failed", {
        status: safeStatus,
        phone_hash: phoneHash,
      });
      return jsonResponse({
        error: otpDeliveryUnavailable,
        status: safeStatus,
      }, 502);
    }

    return jsonResponse({});
  } catch (error) {
    if (error instanceof PublicHookError) {
      if (error.status === 401 && error.message === "Unauthorized") {
        return jsonResponse({ error: "Unauthorized" }, 401);
      }
      return jsonResponse({ error: error.message }, error.status);
    }
    console.error("WhatsApp OTP hook failed", {
      message: safeErrorMessage(error),
    });
    return jsonResponse({
      error: otpDeliveryUnavailable,
    }, 502);
  }
});
