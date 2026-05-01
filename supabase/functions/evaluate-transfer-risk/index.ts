import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { logAiAudit } from "../_shared/google_workspace.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

const GEMINI_MODEL = "gemini-2.0-flash";
const GEMINI_ENDPOINT =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

type AdminClient = ReturnType<typeof createAdminClient>;
type UserClient = ReturnType<typeof createUserClient>;

export interface EvaluateTransferRiskDependencies {
  createAdminClient: () => AdminClient;
  createUserClient: (authorization: string) => UserClient;
  fetch: typeof fetch;
  getGeminiApiKey: () => string | undefined;
  logAiAudit: typeof logAiAudit;
  now: () => Date;
}

const defaultDependencies: EvaluateTransferRiskDependencies = {
  createAdminClient,
  createUserClient,
  fetch,
  getGeminiApiKey: () => Deno.env.get("GEMINI_API_KEY")?.trim(),
  logAiAudit,
  now: () => new Date(),
};

const riskSchema = {
  type: "object",
  properties: {
    risk_score: { type: "number", minimum: 0, maximum: 1 },
    is_anomaly: { type: "boolean" },
    reason: { type: "string" },
    warning_title: { type: "string" },
    warning_body: { type: "string" },
    trust_score: { type: "number", minimum: 0, maximum: 1 },
    action_suggestion: {
      type: "string",
      enum: ["allow", "warn", "review", "block"],
    },
  },
  required: [
    "risk_score",
    "is_anomaly",
    "reason",
    "warning_title",
    "warning_body",
    "trust_score",
    "action_suggestion",
  ],
};

type RiskRequest = {
  recipientNumber?: string;
  amount?: number | string;
  currency?: string;
};

type LedgerRiskRow = {
  amount?: number | null;
  counterparty_name?: string | null;
  description?: string | null;
  statement_label?: string | null;
  metadata?: Record<string, unknown> | null;
};

type RiskResult = {
  risk_score: number;
  is_anomaly: boolean;
  reason: string;
  warning_title: string;
  warning_body: string;
  trust_score: number;
  action_suggestion: "allow" | "warn" | "review" | "block";
};

function normalizeRecipientKey(value: string): string {
  return value.trim().replace(/\s+/g, " ").toLowerCase();
}

function normalizeDigits(value: string): string {
  return value.replace(/\D/g, "");
}

function matchesRecipient(candidate: string, recipient: string): boolean {
  const candidateDigits = normalizeDigits(candidate);
  const recipientDigits = normalizeDigits(recipient);
  if (candidateDigits && recipientDigits) {
    return candidateDigits === recipientDigits ||
      candidateDigits.endsWith(recipientDigits) ||
      recipientDigits.endsWith(candidateDigits);
  }

  return normalizeRecipientKey(candidate) === normalizeRecipientKey(recipient);
}

function asFiniteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function collectRecentRecipients(rows: LedgerRiskRow[]): string[] {
  const recipients = new Set<string>();

  for (const row of rows) {
    const metadata = row.metadata ?? {};
    const candidates = [
      row.counterparty_name,
      row.description,
      row.statement_label,
      typeof metadata["recipient_number"] === "string"
        ? metadata["recipient_number"]
        : null,
      typeof metadata["payee_number_or_code"] === "string"
        ? metadata["payee_number_or_code"]
        : null,
      typeof metadata["payer_number_full"] === "string"
        ? metadata["payer_number_full"]
        : null,
    ];

    for (const candidate of candidates) {
      if (typeof candidate !== "string") continue;
      const normalized = candidate.trim();
      if (normalized.length > 0) {
        recipients.add(normalized);
      }
    }
  }

  return [...recipients].slice(0, 10);
}

function averageAmount(rows: LedgerRiskRow[], fallback: number): number {
  const amounts = rows
    .map((row) => asFiniteNumber(row.amount))
    .filter((value): value is number => value !== null && value > 0);

  if (amounts.length === 0) {
    return fallback;
  }

  const total = amounts.reduce(
    (sum: number, value: number) => sum + value,
    0,
  );
  return total / amounts.length;
}

function extractGeminiText(responseBody: Record<string, unknown>): string {
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
        return text;
      }
    }
  }

  throw new Error("Gemini response did not contain JSON text output");
}

function buildRiskPrompt(
  transfer: { recipientNumber: string; amount: number; currency: string },
  context: {
    isKnown: boolean;
    isCoMember: boolean;
    avgAmount: number;
    recentRecipients: string[];
  },
): string {
  return [
    "You are COOL Guardian AI, a transfer-risk assistant for mobile money payments.",
    "Assess whether the pending transfer looks normal for this user.",
    "",
    "### TRANSFER",
    `Recipient: ${transfer.recipientNumber}`,
    `Amount: ${transfer.amount} ${transfer.currency}`,
    "",
    "### USER CONTEXT",
    `Known recipient: ${context.isKnown}`,
    `Co-member recipient: ${context.isCoMember}`,
    `Average outgoing amount: ${
      context.avgAmount.toFixed(2)
    } ${transfer.currency}`,
    `Recent recipients: ${
      context.recentRecipients.length > 0
        ? context.recentRecipients.join(", ")
        : "none"
    }`,
    "",
    "### OUTPUT RULES",
    "Return JSON only.",
    "risk_score is 0 to 1, where 1 is very risky.",
    "trust_score is 0 to 1, where 1 is very trusted.",
    "action_suggestion must be allow, warn, review, or block.",
    "Use warn or review when the payment is unusually large or recipient trust is low.",
  ].join("\n");
}

function buildGeminiUrl(apiKey: string): string {
  return `${GEMINI_ENDPOINT}?key=${encodeURIComponent(apiKey)}`;
}

function maskRecipient(value: string): string {
  const digits = normalizeDigits(value);
  if (digits.length >= 4) {
    return `***${digits.slice(-4)}`;
  }
  return "***";
}

function normalizeRiskResult(
  payload: Record<string, unknown>,
  context: { isKnown: boolean; amount: number; avgAmount: number },
): RiskResult {
  const fallbackRisk = context.isKnown ? 0.2 : 0.45;
  const fallbackTrust = context.isKnown ? 0.8 : 0.45;
  const aiRiskScore = asFiniteNumber(payload["risk_score"]);
  const aiTrustScore = asFiniteNumber(payload["trust_score"]);
  const riskScore = clamp(aiRiskScore ?? fallbackRisk, 0, 1);
  const trustScore = clamp(aiTrustScore ?? fallbackTrust, 0, 1);
  const amountRatio = context.avgAmount > 0
    ? context.amount / context.avgAmount
    : 1;
  const suggestedAction = typeof payload["action_suggestion"] === "string"
    ? payload["action_suggestion"].toLowerCase()
    : "";

  const actionSuggestion = (
    suggestedAction === "allow" ||
      suggestedAction === "warn" ||
      suggestedAction === "review" ||
      suggestedAction === "block"
      ? suggestedAction
      : riskScore >= 0.8 || amountRatio >= 5
      ? "review"
      : riskScore >= 0.55
      ? "warn"
      : "allow"
  ) as RiskResult["action_suggestion"];

  return {
    risk_score: riskScore,
    is_anomaly: typeof payload["is_anomaly"] === "boolean"
      ? payload["is_anomaly"]
      : riskScore >= 0.55 || amountRatio >= 3,
    reason: typeof payload["reason"] === "string" &&
        payload["reason"].trim().length > 0
      ? payload["reason"]
      : context.isKnown
      ? "Transfer aligns with recent recipient behavior."
      : "Recipient has limited history for this user.",
    warning_title: typeof payload["warning_title"] === "string"
      ? payload["warning_title"]
      : "",
    warning_body: typeof payload["warning_body"] === "string"
      ? payload["warning_body"]
      : "",
    trust_score: trustScore,
    action_suggestion: actionSuggestion,
  };
}

function buildReviewFallbackResult(
  context: { isKnown: boolean; amount: number; avgAmount: number },
): RiskResult {
  const amountRatio = context.avgAmount > 0
    ? context.amount / context.avgAmount
    : 1;
  const elevated = !context.isKnown || amountRatio >= 3;
  return {
    risk_score: elevated ? 0.85 : 0.65,
    is_anomaly: true,
    reason:
      "Guardian AI could not complete verification. Review this transfer before sending.",
    warning_title: "Review transfer",
    warning_body:
      "Risk verification is temporarily unavailable, so this payment needs manual review before approval.",
    trust_score: context.isKnown ? 0.45 : 0.25,
    action_suggestion: "review",
  };
}

export function createEvaluateTransferRiskHandler(
  dependencies: Partial<EvaluateTransferRiskDependencies> = {},
) {
  const deps: EvaluateTransferRiskDependencies = {
    ...defaultDependencies,
    ...dependencies,
  };

  return async (req: Request): Promise<Response> => {
    const startTime = deps.now().getTime();
    const cors = handleCors(req);
    if (cors) return cors;

    if (req.method !== "POST") return methodNotAllowed("POST", req);

    const geminiApiKey = deps.getGeminiApiKey()?.trim();
    if (!geminiApiKey) {
      return errorResponse("AI Service not configured.", 503, undefined, req);
    }

    const authHeader = req.headers.get("authorization")?.trim() ??
      req.headers.get("Authorization")?.trim();
    if (!authHeader) {
      return errorResponse("Missing authorization.", 401, undefined, req);
    }

    const adminClient = deps.createAdminClient();
    const userClient = deps.createUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth
      .getUser();

    if (authError || !user) {
      return errorResponse("Unauthorized.", 401, undefined, req);
    }

    let body: RiskRequest;
    try {
      body = await req.json() as RiskRequest;
    } catch {
      return errorResponse("Invalid JSON body.", 400, undefined, req);
    }

    const recipientNumber = body.recipientNumber?.trim() ?? "";
    const amount = asFiniteNumber(body.amount);
    const currency = body.currency?.trim() || "RWF";

    if (!recipientNumber || amount === null || amount <= 0) {
      return errorResponse(
        "Recipient and amount are required.",
        400,
        undefined,
        req,
      );
    }

    const ninetyDaysAgo = new Date(deps.now().getTime());
    ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

    const { data: recentTransfers } = await adminClient
      .from("momo_ledger_entries")
      .select(
        "amount, counterparty_name, description, statement_label, metadata",
      )
      .eq("user_id", user.id)
      .eq("ledger_status", "posted")
      .eq("entry_type", "debit")
      .gte("tx_datetime", ninetyDaysAgo.toISOString())
      .order("tx_datetime", { ascending: false })
      .limit(50);

    const rows = (recentTransfers ?? []) as LedgerRiskRow[];
    const recentRecipients = collectRecentRecipients(rows);
    const isKnown = recentRecipients.some((candidate) =>
      matchesRecipient(candidate, recipientNumber)
    );
    const avgAmount = averageAmount(rows, amount);
    const isCoMember = false;

    try {
      const prompt = buildRiskPrompt(
        { recipientNumber, amount, currency },
        {
          isKnown,
          isCoMember,
          avgAmount,
          recentRecipients,
        },
      );

      const geminiResponse = await deps.fetch(buildGeminiUrl(geminiApiKey), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: riskSchema,
            temperature: 0.1,
          },
        }),
      });

      if (!geminiResponse.ok) {
        throw new Error(`Gemini API error: ${await geminiResponse.text()}`);
      }

      const result = await geminiResponse.json() as Record<string, unknown>;
      const riskResult = normalizeRiskResult(
        JSON.parse(extractGeminiText(result)) as Record<string, unknown>,
        { isKnown, amount, avgAmount },
      );

      await deps.logAiAudit({
        function_name: "evaluate-transfer-risk",
        user_id: user.id,
        model: GEMINI_MODEL,
        confidence: 1 - riskResult.risk_score,
        decision: riskResult.action_suggestion.toUpperCase(),
        metadata: {
          amount,
          recipient: maskRecipient(recipientNumber),
          is_anomaly: riskResult.is_anomaly,
          reason: riskResult.reason,
        },
        latency_ms: deps.now().getTime() - startTime,
      });

      return jsonResponse(
        {
          success: true,
          data: riskResult,
        },
        200,
        {},
        req,
      );
    } catch (err) {
      console.error("Guardian AI Error:", err);
      const fallback = buildReviewFallbackResult({
        isKnown,
        amount,
        avgAmount,
      });

      await deps.logAiAudit({
        function_name: "evaluate-transfer-risk",
        user_id: user.id,
        model: GEMINI_MODEL,
        confidence: 1 - fallback.risk_score,
        decision: fallback.action_suggestion.toUpperCase(),
        metadata: {
          amount,
          recipient: maskRecipient(recipientNumber),
          is_anomaly: fallback.is_anomaly,
          reason: fallback.reason,
          ai_fallback: true,
        },
        latency_ms: deps.now().getTime() - startTime,
      });

      return jsonResponse(
        {
          success: true,
          data: fallback,
        },
        200,
        {},
        req,
      );
    }
  };
}

if (import.meta.main) {
  Deno.serve(createEvaluateTransferRiskHandler());
}
