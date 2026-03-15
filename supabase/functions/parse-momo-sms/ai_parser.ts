export type AiProvider = "openai" | "gemini";

export type RawSmsRecord = {
  id: string;
  user_id: string;
  sender: string;
  sms_body: string;
  provider: string | null;
  country: string | null;
  sms_received_at: string;
  detected_tx_type: string | null;
  detected_amount: number | null;
  detected_tx_id: string | null;
};

export type ParsedSms = {
  parse_status: "parsed" | "needs_review" | "failed";
  confidence: number;
  tx_direction: "credit" | "debit" | "unknown";
  tx_type: string;
  tx_category: string;
  cashflow_bucket:
    | "income"
    | "expense"
    | "savings"
    | "transfer"
    | "loan"
    | "fees"
    | "unknown";
  momo_tx_id: string | null;
  amount: number | null;
  currency: string;
  tx_date: string | null;
  tx_time: string | null;
  tx_datetime_iso: string | null;
  payer_name: string | null;
  payer_number_last3: string | null;
  payer_number_full: string | null;
  payee_name: string | null;
  payee_number_or_code: string | null;
  merchant_code: string | null;
  fee_amount: number | null;
  balance_after: number | null;
  counterparty_name: string | null;
  ai_summary: string | null;
  recurring_pattern_hint: "recurring" | "seasonal" | "one_off" | "unknown";
  narrative: string | null;
  notes: string | null;
};

type AiCallOptions = {
  apiKey?: string;
  model?: string;
  fetchFn?: typeof fetch;
};

export const parsedSmsJsonSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    parse_status: {
      type: "string",
      enum: ["parsed", "needs_review", "failed"],
    },
    confidence: {
      type: "number",
      minimum: 0,
      maximum: 1,
    },
    tx_direction: {
      type: "string",
      enum: ["credit", "debit", "unknown"],
    },
    tx_type: { type: "string" },
    tx_category: { type: "string" },
    cashflow_bucket: {
      type: "string",
      enum: [
        "income",
        "expense",
        "savings",
        "transfer",
        "loan",
        "fees",
        "unknown",
      ],
    },
    momo_tx_id: { type: ["string", "null"] },
    amount: { type: ["integer", "null"] },
    currency: { type: "string" },
    tx_date: { type: ["string", "null"] },
    tx_time: { type: ["string", "null"] },
    tx_datetime_iso: { type: ["string", "null"] },
    payer_name: { type: ["string", "null"] },
    payer_number_last3: { type: ["string", "null"] },
    payer_number_full: { type: ["string", "null"] },
    payee_name: { type: ["string", "null"] },
    payee_number_or_code: { type: ["string", "null"] },
    merchant_code: { type: ["string", "null"] },
    fee_amount: { type: ["integer", "null"] },
    balance_after: { type: ["integer", "null"] },
    counterparty_name: { type: ["string", "null"] },
    ai_summary: { type: ["string", "null"] },
    recurring_pattern_hint: {
      type: "string",
      enum: ["recurring", "seasonal", "one_off", "unknown"],
    },
    narrative: { type: ["string", "null"] },
    notes: { type: ["string", "null"] },
  },
  required: [
    "parse_status",
    "confidence",
    "tx_direction",
    "tx_type",
    "tx_category",
    "cashflow_bucket",
    "momo_tx_id",
    "amount",
    "currency",
    "tx_date",
    "tx_time",
    "tx_datetime_iso",
    "payer_name",
    "payer_number_last3",
    "payer_number_full",
    "payee_name",
    "payee_number_or_code",
    "merchant_code",
    "fee_amount",
    "balance_after",
    "counterparty_name",
    "ai_summary",
    "recurring_pattern_hint",
    "narrative",
    "notes",
  ],
};

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing environment variable: ${name}`);
  }
  return value;
}

function optionalEnv(name: string): string {
  try {
    return Deno.env.get(name) ?? "";
  } catch (_) {
    return "";
  }
}

export function getAiProvider(explicit?: string): AiProvider {
  const configured = (explicit ?? optionalEnv("AI_SMS_PARSE_PROVIDER") ?? "")
    .trim()
    .toLowerCase();
  if (configured === "gemini") {
    return "gemini";
  }
  if (configured === "openai") {
    return "openai";
  }
  if (optionalEnv("GEMINI_API_KEY").trim().length > 0) {
    return "gemini";
  }
  if (optionalEnv("OPENAI_API_KEY").trim().length > 0) {
    return "openai";
  }
  return "gemini";
}

export function getModel(provider: AiProvider): string {
  if (provider === "gemini") {
    // default to gemini-3.1-pro as the most authoritative parsing model.
    return Deno.env.get("GEMINI_SMS_PARSE_MODEL") ?? "gemini-3.1-pro";
  }
  // OpenAI fallback remains on gpt-4.1-mini or equivalent.
  return Deno.env.get("OPENAI_SMS_PARSE_MODEL") ?? "gpt-4.1-mini";
}

export function buildPrompt(record: RawSmsRecord): string {
  return [
    "You are parsing a Mobile Money SMS into a normalized finance record for lending analysis.",
    "Extract exact fields when present. Do not guess hidden digits.",
    "Return JSON only matching the schema.",
    "",
    `User ID: ${record.user_id}`,
    `Sender: ${record.sender}`,
    `Provider hint: ${record.provider ?? "unknown"}`,
    `Country hint: ${record.country ?? "unknown"}`,
    `SMS received at: ${record.sms_received_at}`,
    `Detected tx type: ${record.detected_tx_type ?? "unknown"}`,
    `Detected amount: ${record.detected_amount ?? "unknown"}`,
    `Detected tx id: ${record.detected_tx_id ?? "unknown"}`,
    "",
    "SMS body:",
    record.sms_body,
    "",
    "Important field rules:",
    "- amount is an integer in RWF if possible",
    "- tx_date format: YYYY-MM-DD or null",
    "- tx_time format: HH:MM:SS or null",
    "- tx_datetime_iso format: ISO-8601 or null",
    "- tx_category should be concrete, for example: salary, transfer_in, transfer_out, merchant_payment, group_contribution, cash_in, cash_out, airtime, fees, loan_disbursement, loan_repayment, uncategorized",
    "- cashflow_bucket must be one of income, expense, savings, transfer, loan, fees, unknown",
    "- counterparty_name should contain the official sender or receiver name shown in the SMS",
    "- ai_summary should be a short user-facing summary of the transaction in one sentence",
    "- recurring_pattern_hint must be one of recurring, seasonal, one_off, unknown",
    "- payer_number_last3 must contain only the visible last 3 digits when available",
    "- payee_number_or_code can contain a phone number, merchant code, or paybill code",
    "- parse_status should be 'needs_review' when confidence is low or key values are missing",
  ].join("\n");
}

export async function callOpenAi(
  prompt: string,
  options: AiCallOptions = {},
) {
  const apiKey = options.apiKey ?? requireEnv("OPENAI_API_KEY");
  const model = options.model ?? getModel("openai");
  const fetchFn = options.fetchFn ?? fetch;
  const requestPayload = {
    model,
    input: [
      {
        role: "user",
        content: [
          {
            type: "input_text",
            text: prompt,
          },
        ],
      },
    ],
    text: {
      format: {
        type: "json_schema",
        name: "momo_sms_parse",
        schema: parsedSmsJsonSchema,
        strict: true,
      },
    },
  };

  const response = await fetchFn("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(requestPayload),
  });

  const responseBody = await response.json();
  if (!response.ok) {
    throw new Error(
      `OpenAI SMS parse failed with ${response.status}: ${
        JSON.stringify(responseBody)
      }`,
    );
  }

  return {
    model,
    requestPayload,
    responseBody,
    text: extractOpenAiText(responseBody),
  };
}

export function extractOpenAiText(
  responseBody: Record<string, unknown>,
): string {
  const outputText = responseBody["output_text"];
  if (typeof outputText === "string" && outputText.trim().length > 0) {
    return outputText;
  }

  const output = responseBody["output"];
  if (Array.isArray(output)) {
    for (const item of output) {
      if (!item || typeof item !== "object") continue;
      const content = (item as Record<string, unknown>)["content"];
      if (!Array.isArray(content)) continue;
      for (const part of content) {
        if (!part || typeof part !== "object") continue;
        const text = (part as Record<string, unknown>)["text"] ??
          (part as Record<string, unknown>)["output_text"];
        if (typeof text === "string" && text.trim().length > 0) {
          return text;
        }
      }
    }
  }

  throw new Error("OpenAI response did not contain structured output text");
}

export async function callGemini(
  prompt: string,
  options: AiCallOptions = {},
) {
  const apiKey = options.apiKey ?? requireEnv("GEMINI_API_KEY");
  const model = options.model ?? getModel("gemini");
  const fetchFn = options.fetchFn ?? fetch;
  const requestPayload = {
    contents: [
      {
        role: "user",
        parts: [{ text: prompt }],
      },
    ],
    generationConfig: {
      responseMimeType: "application/json",
    },
  };

  const response = await fetchFn(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(requestPayload),
    },
  );

  const responseBody = await response.json();
  if (!response.ok) {
    throw new Error(
      `Gemini SMS parse failed with ${response.status}: ${
        JSON.stringify(responseBody)
      }`,
    );
  }

  return {
    model,
    requestPayload,
    responseBody,
    text: extractGeminiText(responseBody),
  };
}

export function extractGeminiText(
  responseBody: Record<string, unknown>,
): string {
  const candidates = responseBody["candidates"];
  if (!Array.isArray(candidates) || candidates.length === 0) {
    throw new Error("Gemini response did not contain candidates");
  }

  for (const candidate of candidates) {
    if (!candidate || typeof candidate !== "object") continue;
    const content = (candidate as Record<string, unknown>)["content"];
    if (!content || typeof content !== "object") continue;
    const parts = (content as Record<string, unknown>)["parts"];
    if (!Array.isArray(parts)) continue;
    for (const part of parts) {
      if (!part || typeof part !== "object") continue;
      const text = (part as Record<string, unknown>)["text"];
      if (typeof text === "string" && text.trim().length > 0) {
        return normalizeJsonText(text);
      }
    }
  }

  throw new Error("Gemini response did not contain JSON text output");
}

function normalizeJsonText(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) {
    return trimmed;
  }

  const unfenced = trimmed
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  const objectStart = unfenced.indexOf("{");
  const objectEnd = unfenced.lastIndexOf("}");
  if (objectStart >= 0 && objectEnd > objectStart) {
    return unfenced.slice(objectStart, objectEnd + 1);
  }

  return unfenced;
}

export function normalizeParsedSms(
  payload: Record<string, unknown>,
): ParsedSms {
  const parseStatus = oneOf(
    payload["parse_status"],
    ["parsed", "needs_review", "failed"],
    "needs_review",
  ) as ParsedSms["parse_status"];
  const txDirection = oneOf(
    payload["tx_direction"],
    ["credit", "debit", "unknown"],
    "unknown",
  ) as ParsedSms["tx_direction"];
  const txCategory = asString(payload["tx_category"]) ??
    asString(payload["tx_type"]) ??
    "uncategorized";

  return {
    parse_status: parseStatus,
    confidence: clampNumber(payload["confidence"], 0, 1, 0),
    tx_direction: txDirection,
    tx_type: asString(payload["tx_type"]) ?? "unknown",
    tx_category: txCategory,
    cashflow_bucket: oneOf(
      payload["cashflow_bucket"],
      ["income", "expense", "savings", "transfer", "loan", "fees", "unknown"],
      "unknown",
    ) as ParsedSms["cashflow_bucket"],
    momo_tx_id: asString(payload["momo_tx_id"]),
    amount: asNullableInt(payload["amount"]),
    currency: asString(payload["currency"]) ?? "RWF",
    tx_date: asString(payload["tx_date"]),
    tx_time: asString(payload["tx_time"]),
    tx_datetime_iso: asString(payload["tx_datetime_iso"]),
    payer_name: asString(payload["payer_name"]),
    payer_number_last3: normalizeLast3(asString(payload["payer_number_last3"])),
    payer_number_full: asString(payload["payer_number_full"]),
    payee_name: asString(payload["payee_name"]),
    payee_number_or_code: asString(payload["payee_number_or_code"]),
    merchant_code: asString(payload["merchant_code"]),
    fee_amount: asNullableInt(payload["fee_amount"]),
    balance_after: asNullableInt(payload["balance_after"]),
    counterparty_name: asString(payload["counterparty_name"]) ??
      (txDirection == "credit"
        ? asString(payload["payer_name"]) ?? asString(payload["payee_name"])
        : asString(payload["payee_name"]) ?? asString(payload["payer_name"])),
    ai_summary: asString(payload["ai_summary"]) ??
      asString(payload["narrative"]),
    recurring_pattern_hint: oneOf(
      payload["recurring_pattern_hint"],
      ["recurring", "seasonal", "one_off", "unknown"],
      "unknown",
    ) as ParsedSms["recurring_pattern_hint"],
    narrative: asString(payload["narrative"]),
    notes: asString(payload["notes"]),
  };
}

function asString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return null;
}

function asNullableInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.round(value);
  }
  if (typeof value === "string") {
    const cleaned = value.replaceAll(/[^\d.-]/g, "");
    if (!cleaned) return null;
    const parsed = Number.parseFloat(cleaned);
    return Number.isFinite(parsed) ? Math.round(parsed) : null;
  }
  return null;
}

function oneOf(
  value: unknown,
  allowed: string[],
  fallback: string,
): string {
  const normalized = asString(value)?.toLowerCase();
  if (normalized && allowed.includes(normalized)) {
    return normalized;
  }
  return fallback;
}

function clampNumber(
  value: unknown,
  min: number,
  max: number,
  fallback: number,
): number {
  const numeric = typeof value === "number"
    ? value
    : typeof value === "string"
    ? Number.parseFloat(value)
    : Number.NaN;
  if (!Number.isFinite(numeric)) {
    return fallback;
  }
  return Math.min(max, Math.max(min, numeric));
}

function normalizeLast3(value: string | null): string | null {
  if (!value) return null;
  const digits = value.replaceAll(/\D/g, "");
  if (!digits) return null;
  return digits.slice(-3);
}
