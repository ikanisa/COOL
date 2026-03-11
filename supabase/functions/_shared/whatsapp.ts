import {
  normalizePhone,
  toOtpTemplateLanguage,
  toWhatsAppRecipient,
} from "./phone.ts";

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }

  return value;
}

async function postWhatsAppMessage(payload: Record<string, unknown>) {
  const phoneNumberId = requireEnv("WHATSAPP_PHONE_NUMBER_ID");
  const accessToken = requireEnv("WHATSAPP_ACCESS_TOKEN");
  const response = await fetch(
    `https://graph.facebook.com/v21.0/${phoneNumberId}/messages`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    },
  );

  if (response.ok) {
    return;
  }

  const errorBody = await response.text();
  throw new Error(
    `WhatsApp API request failed with ${response.status}: ${errorBody}`,
  );
}

export async function sendTextMessage(options: {
  phone: string;
  body: string;
}) {
  const normalizedPhone = normalizePhone(options.phone);
  await postWhatsAppMessage({
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: toWhatsAppRecipient(normalizedPhone),
    type: "text",
    text: {
      preview_url: false,
      body: options.body,
    },
  });
}

/**
 * Sends a WhatsApp OTP using the "gikundiro" Authentication template.
 *
 * Template format (with Copy Code button):
 *   "{{1}} is your verification code. Expires in 10 minutes."
 *   [Copy code]
 *
 * For WhatsApp Authentication templates with copy_code, the OTP goes in
 * a `button` component with sub_type `url` and the code as parameter,
 * AND in the `body` component as the {{1}} placeholder.
 */
export async function sendOtpTemplate(options: {
  phone: string;
  code: string;
  language: "en" | "fr";
}) {
  await postWhatsAppMessage({
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: toWhatsAppRecipient(options.phone),
    type: "template",
    template: {
      name: "gikundiro",
      language: {
        code: toOtpTemplateLanguage(options.language),
      },
      components: [
        {
          type: "body",
          parameters: [
            {
              type: "text",
              text: options.code,
            },
          ],
        },
        {
          type: "button",
          sub_type: "url",
          index: "0",
          parameters: [
            {
              type: "text",
              text: options.code,
            },
          ],
        },
      ],
    },
  });
}

export async function sendContributionConfirmation(options: {
  phone: string;
  amount: number;
  reference: string;
  groupName: string;
}) {
  await sendTextMessage({
    phone: options.phone,
    body:
      `✅ Your contribution of RWF ${options.amount} to ${options.groupName}\n` +
      `has been confirmed. Reference: ${options.reference}`,
  });
}
