import { parsedSmsJsonSchema } from "./parsed_sms_schema.ts";

export { tryHeuristicParse } from "./ai_parser_heuristics.ts";

export type AiProvider = "openai" | "gemini";
export type ParseProvider = AiProvider | "heuristic";

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

export type HeuristicParseResult = {
  model: string;
  parsed: ParsedSms;
  requestPayload: Record<string, unknown>;
  responsePayload: Record<string, unknown>;
};

type AiCallOptions = {
  apiKey?: string;
  model?: string;
  fetchFn?: typeof fetch;
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
    // gemini-2.0-flash is the optimum production model for speed and parsing precision.
    return Deno.env.get("GEMINI_SMS_PARSE_MODEL") ?? "gemini-2.0-flash";
  }
  // OpenAI fallback remains on gpt-4o-mini for optimum cost/performance.
  return Deno.env.get("OPENAI_SMS_PARSE_MODEL") ?? "gpt-4o-mini";
}

export function buildPrompt(
  record: RawSmsRecord,
  lessons: string[] = [],
): string {
  return [
    "You are an expert financial analyst parsing Mobile Money SMS into normalized records.",
    "Your goal is 100% accuracy for lending risk assessment.",
    "Extract exact fields. Do not guess or hallucinate hidden data.",
    "If a field is missing, return null.",
    "",
    "### LEARNED RULES FROM USER FEEDBACK",
    ...(lessons.length > 0 ? lessons : ["No specific overrides learned yet."]),
    "",
    "### CONTEXT",
    `User ID: ${record.user_id}`,
    `Sender: ${record.sender}`,
    `Provider: ${record.provider ?? "unknown"}`,
    `Country: ${record.country ?? "unknown"}`,
    `Timestamp: ${record.sms_received_at}`,
    "",
    "### SMS BODY",
    record.sms_body,
    "",
    "### EXTRACTION RULES",
    "1. MATHEMATICAL INTEGRITY: Ensure (amount + fee_amount) logic is consistent with the text.",
    "2. CATEGORIZATION: Use precise categories (salary, merchant_payment, cash_out, airtime, loan_repayment).",
    "3. BUCKETING: Assign to income, expense, savings, transfer, loan, or fees.",
    "4. DATETIME: Extract tx_date as YYYY-MM-DD and tx_time as HH:MM:SS.",
    "5. CONFIDENCE: Set confidence to < 0.8 if the text is ambiguous or truncated.",
    "6. SUMMARY: Provide a concise user-facing summary in one sentence.",
    "",
    "Return JSON only matching the schema.",
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
        content: prompt,
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
  const output = responseBody["output"];
  if (!Array.isArray(output)) {
    throw new Error("OpenAI response did not contain structured output text");
  }

  for (const item of output) {
    if (!item || typeof item !== "object") continue;
    const content = (item as Record<string, unknown>)["content"];
    if (!Array.isArray(content)) continue;

    for (const part of content) {
      if (!part || typeof part !== "object") continue;
      const record = part as Record<string, unknown>;
      const text = record["text"];
      if (typeof text === "string" && text.trim().length > 0) {
        return normalizeJsonText(text);
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
      temperature: 0.1,
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
  let parseStatus = oneOf(
    payload["parse_status"],
    ["parsed", "needs_review", "failed"],
    "needs_review",
  ) as ParsedSms["parse_status"];

  const txDirection = oneOf(
    payload["tx_direction"],
    ["credit", "debit", "unknown"],
    "unknown",
  ) as ParsedSms["tx_direction"];

  const amount = asNullableInt(payload["amount"]);
  const feeAmount = asNullableInt(payload["fee_amount"]);
  const balanceAfter = asNullableInt(payload["balance_after"]);

  // OPTIMUM ROBUSTNESS: Mathematical Cross-Check
  // If we have amount and fee but they aren't consistent with other fields, flag for review.
  let confidence = clampNumber(payload["confidence"], 0, 1, 0);
  if (amount === null || amount <= 0) {
    parseStatus = "needs_review";
    confidence = Math.min(confidence, 0.4);
  }

  const txCategory = asString(payload["tx_category"]) ??
    asString(payload["tx_type"]) ??
    "uncategorized";

  return {
    parse_status: parseStatus,
    confidence: confidence,
    tx_direction: txDirection,
    tx_type: asString(payload["tx_type"]) ?? "unknown",
    tx_category: txCategory,
    cashflow_bucket: oneOf(
      payload["cashflow_bucket"],
      ["income", "expense", "savings", "transfer", "loan", "fees", "unknown"],
      "unknown",
    ) as ParsedSms["cashflow_bucket"],
    momo_tx_id: asString(payload["momo_tx_id"]),
    amount: amount,
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
    fee_amount: feeAmount,
    balance_after: balanceAfter,
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
