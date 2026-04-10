import type { ParsedSms, RawSmsRecord } from "./ai_parser.ts";

export function asString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return null;
}

export function deriveLedgerScope(
  targetTable: string | null,
): "wallet" | "group" | "partner" {
  switch (targetTable) {
    case "group_contributions":
      return "group";
    case "partner_payment_routes":
      return "partner";
    default:
      return "wallet";
  }
}

export async function sendParsedPaymentNotification(options: {
  parsed: ParsedSms;
  rawSms: RawSmsRecord;
  rawSmsId: string;
}) {
  const { parsed, rawSms, rawSmsId } = options;
  if (
    parsed.parse_status !== "parsed" ||
    parsed.amount == null ||
    parsed.amount <= 0
  ) {
    return;
  }

  try {
    const { sendToUser } = await import("../_shared/fcm.ts");
    const amountStr = new Intl.NumberFormat("en-RW", {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    }).format(parsed.amount);
    const currency = parsed.currency ?? "RWF";
    const counterparty = parsed.counterparty_name ?? "MoMo";
    const direction = parsed.tx_direction === "credit"
      ? "received from"
      : "sent to";

    await sendToUser(rawSms.user_id, {
      title: parsed.tx_direction === "credit"
        ? "Payment Received 💰"
        : "Payment Sent",
      body: `${amountStr} ${currency} ${direction} ${counterparty}`,
    }, {
      route: "/momo",
      type: "momo_payment",
      raw_sms_id: rawSmsId,
    });
  } catch (notifError) {
    console.error("parse-momo-sms push notification failed:", notifError);
  }
}
