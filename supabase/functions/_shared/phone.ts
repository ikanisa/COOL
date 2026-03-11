export class PhoneValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PhoneValidationError";
  }
}

export function normalizePhone(phone: string): string {
  const trimmed = phone.trim();
  if (trimmed.length === 0) {
    throw new PhoneValidationError("Phone is required");
  }

  let normalized = trimmed.replace(/[^\d+]/g, "");
  if (normalized.startsWith("00")) {
    normalized = `+${normalized.slice(2)}`;
  }

  normalized = normalized.replace(/(?!^)\+/g, "");
  if (!normalized.startsWith("+")) {
    normalized = `+${normalized}`;
  }

  if (!/^\+[1-9]\d{7,14}$/.test(normalized)) {
    throw new PhoneValidationError("Phone must be in international format");
  }

  return normalized;
}

export function toWhatsAppRecipient(phone: string): string {
  return normalizePhone(phone).replace("+", "");
}

export function toOtpTemplateLanguage(language: "en" | "fr"): "en_US" | "fr" {
  return language == "fr" ? "fr" : "en_US";
}
