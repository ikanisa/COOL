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

type WhatsAppTemplateComponent = {
  type: string;
  sub_type?: string;
  index?: string;
  parameters: Array<{ type: "text"; text: string }>;
};

const otpDeliveryUnavailable =
  "WhatsApp OTP delivery is temporarily unavailable";
const defaultWhatsAppGraphApiVersion = "v25.0";
const defaultWhatsAppTemplateLanguage = "en_US";

class PublicHookError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = "PublicHookError";
  }
}

function envValue(...names: string[]): string | null {
  for (const name of names) {
    const value = Deno.env.get(name)?.trim();
    if (value) return value;
  }
  return null;
}

function requireAnyEnv(...names: string[]): string {
  const value = envValue(...names);
  if (!value) throw new Error(`Missing required env var: ${names[0]}`);
  return value;
}

function optionalBooleanEnv(name: string): boolean | null {
  const value = Deno.env.get(name)?.trim().toLowerCase();
  if (!value) return null;
  if (["1", "true", "yes", "on"].includes(value)) return true;
  if (["0", "false", "no", "off"].includes(value)) return false;
  return null;
}

function whatsappAuthTemplateComponents(otp: string, includeButton: boolean) {
  const otpText = String(otp);
  const components: WhatsAppTemplateComponent[] = [
    {
      type: "body",
      parameters: [{ type: "text", text: otpText }],
    },
  ];
  if (includeButton) {
    components.push({
      type: "button",
      sub_type: envValue("WHATSAPP_CLOUD_OTP_BUTTON_SUB_TYPE") ?? "url",
      index: "0",
      parameters: [{ type: "text", text: otpText }],
    });
  }
  return components;
}

function whatsappGraphApiVersion() {
  const configured = envValue(
    "WHATSAPP_GRAPH_API_VERSION",
    "WHATSAPP_CLOUD_API_VERSION",
  );
  if (!configured) return defaultWhatsAppGraphApiVersion;
  return configured.startsWith("v") ? configured : `v${configured}`;
}

function whatsappTemplateLanguage() {
  return envValue(
    "WHATSAPP_AUTH_TEMPLATE_LANGUAGE",
    "WHATSAPP_CLOUD_TEMPLATE_LANGUAGE_CODE",
  ) ?? defaultWhatsAppTemplateLanguage;
}

function shouldDryRun() {
  return optionalBooleanEnv("WHATSAPP_CLOUD_DRY_RUN") === true;
}

async function sendWhatsAppOtp({
  token,
  phoneNumberId,
  template,
  graphApiVersion,
  phone,
  otp,
  includeButton,
}: {
  token: string;
  phoneNumberId: string;
  template: string;
  graphApiVersion: string;
  phone: string;
  otp: string;
  includeButton: boolean;
}) {
  return await fetch(
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
          language: { code: whatsappTemplateLanguage() },
          components: whatsappAuthTemplateComponents(otp, includeButton),
        },
      }),
    },
  );
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

    const token = requireAnyEnv(
      "WHATSAPP_CLOUD_API_TOKEN",
      "WHATSAPP_CLOUD_ACCESS_TOKEN",
      "WABA_ACCESS_TOKEN",
      "WHATSAPP_ACCESS_TOKEN",
    );
    const phoneNumberId = requireAnyEnv(
      "WHATSAPP_PHONE_NUMBER_ID",
      "WHATSAPP_CLOUD_PHONE_NUMBER_ID",
      "WABA_PHONE_NUMBER_ID",
    );
    const template = requireAnyEnv(
      "WHATSAPP_AUTH_TEMPLATE_NAME",
      "WHATSAPP_CLOUD_OTP_TEMPLATE_NAME",
      "WABA_OTP_TEMPLATE_NAME",
    );
    const graphApiVersion = whatsappGraphApiVersion();
    const buttonSetting = optionalBooleanEnv("WHATSAPP_CLOUD_OTP_AUTH_BUTTON");
    const includeButton = buttonSetting !== false;

    if (shouldDryRun()) return jsonResponse({});

    let response = await sendWhatsAppOtp({
      token,
      phoneNumberId,
      template,
      graphApiVersion,
      phone,
      otp: String(otp),
      includeButton,
    });
    let responseBody = response.ok ? "" : await response.text();

    if (!response.ok && includeButton && buttonSetting === null) {
      response = await sendWhatsAppOtp({
        token,
        phoneNumberId,
        template,
        graphApiVersion,
        phone,
        otp: String(otp),
        includeButton: false,
      });
      responseBody = response.ok ? "" : await response.text();
    }

    if (!response.ok) {
      const safeStatus = response.status;
      console.error("WhatsApp OTP send failed", {
        status: safeStatus,
        phone_hash: phoneHash,
        graph_api_error: responseBody.slice(0, 1000),
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
