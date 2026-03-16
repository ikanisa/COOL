export type KycDocumentType =
  | "national_id"
  | "passport"
  | "driving_license"
  | "residence_permit"
  | "other";

export type NormalizedKycExtraction = {
  fullName: string | null;
  dateOfBirth: string | null;
  nationalIdNumber: string | null;
  gender: string | null;
  nationality: string | null;
  documentType: KycDocumentType | null;
  issuingCountry: string | null;
  expiryDate: string | null;
  confidence: number;
};

export const kycOcrJsonSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    fullName: { type: ["string", "null"] },
    dateOfBirth: { type: ["string", "null"] },
    nationalIdNumber: { type: ["string", "null"] },
    gender: { type: ["string", "null"] },
    nationality: { type: ["string", "null"] },
    documentType: { type: ["string", "null"] },
    issuingCountry: { type: ["string", "null"] },
    expiryDate: { type: ["string", "null"] },
    confidence: {
      type: "number",
      minimum: 0,
      maximum: 1,
    },
  },
  required: [
    "fullName",
    "dateOfBirth",
    "nationalIdNumber",
    "gender",
    "nationality",
    "documentType",
    "issuingCountry",
    "expiryDate",
    "confidence",
  ],
};

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

export function normalizeDocumentType(
  value: unknown,
  fallback?: unknown,
): KycDocumentType | null {
  const raw = (asString(value) ?? asString(fallback) ?? "").toLowerCase();
  if (raw.length === 0) {
    return null;
  }
  if (raw.includes("passport")) {
    return "passport";
  }
  if (raw.includes("driving") || raw.includes("license")) {
    return "driving_license";
  }
  if (raw.includes("residence") || raw.includes("permit")) {
    return "residence_permit";
  }
  if (
    raw.includes("national") ||
    raw == "id" ||
    raw.includes(" identity") ||
    raw.includes("identity ")
  ) {
    return "national_id";
  }
  return raw == "other" ? "other" : null;
}

export function clampConfidence(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.min(1, value));
  }

  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return Math.max(0, Math.min(1, parsed));
    }
  }

  return 0;
}

function pad(number: number) {
  return String(number).padStart(2, "0");
}

export function normalizeIsoDate(value: unknown): string | null {
  const raw = asString(value);
  if (!raw) {
    return null;
  }

  const isoMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(raw);
  if (isoMatch) {
    return `${isoMatch[1]}-${isoMatch[2]}-${isoMatch[3]}`;
  }

  const slashMatch = /^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})$/.exec(raw);
  if (slashMatch) {
    const month = Number(slashMatch[1]);
    const day = Number(slashMatch[2]);
    const year = Number(slashMatch[3]);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return `${year}-${pad(month)}-${pad(day)}`;
    }
  }

  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }

  return `${parsed.getUTCFullYear()}-${pad(parsed.getUTCMonth() + 1)}-${
    pad(parsed.getUTCDate())
  }`;
}

export function unwrapJsonText(value: string): string {
  const trimmed = value.trim();
  if (!trimmed.startsWith("```")) {
    return trimmed;
  }

  return trimmed
    .replace(/^```(?:json)?/i, "")
    .replace(/```$/i, "")
    .trim();
}

export function normalizeKycExtraction(
  raw: Record<string, unknown>,
  requestedDocumentType?: unknown,
): NormalizedKycExtraction {
  return {
    fullName: asString(raw.fullName),
    dateOfBirth: normalizeIsoDate(raw.dateOfBirth),
    nationalIdNumber: asString(raw.nationalIdNumber),
    gender: asString(raw.gender)?.toUpperCase() ?? null,
    nationality: asString(raw.nationality),
    documentType: normalizeDocumentType(
      raw.documentType,
      requestedDocumentType,
    ),
    issuingCountry: asString(raw.issuingCountry),
    expiryDate: normalizeIsoDate(raw.expiryDate),
    confidence: clampConfidence(raw.confidence),
  };
}
