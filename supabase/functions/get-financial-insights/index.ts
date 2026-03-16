import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.0-pro-exp-02-05"; // Optimum model for high-reasoning financial analysis
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

// Strict schema for Agentic Financial Insights
const insightsSchema = {
  type: "object",
  properties: {
    credit_readiness: {
      type: "string",
      enum: ["low", "medium", "high", "excellent"],
    },
    estimated_score_range: { type: "string" },
    key_strengths: {
      type: "array",
      items: { type: "string" },
    },
    improvement_areas: {
      type: "array",
      items: { type: "string" },
    },
    spending_analysis: {
      type: "string",
      description: "A professional yet empathetic summary of their cashflow habits.",
    },
    proactive_tips: {
      type: "array",
      items: { type: "string" },
      description: "3 actionable steps to improve their score in 30 days.",
    },
    savings_discipline_score: { type: "number", minimum: 0, maximum: 100 },
    income_stability_score: { type: "number", minimum: 0, maximum: 100 },
  },
  required: [
    "credit_readiness",
    "estimated_score_range",
    "key_strengths",
    "improvement_areas",
    "spending_analysis",
    "proactive_tips",
    "savings_discipline_score",
    "income_stability_score",
  ],
};

function buildInsightsPrompt(userData: any, transactions: any[], groupData: any) {
  return [
    "You are a Senior Credit Underwriter and Financial Coach for a community-led fintech app in Rwanda.",
    "Analyze the provided financial data to assess credit readiness and provide coaching.",
    "",
    "### USER PROFILE",
    `Name: ${userData.official_name || userData.full_name}`,
    `KYC Status: ${userData.kyc_status}`,
    `Savings Groups: Member of ${groupData.count} groups.`,
    "",
    "### AGGREGATED TRANSACTION DATA (Last 90 Days)",
    JSON.stringify(transactions, null, 2),
    "",
    "### TASK",
    "1. Evaluate credit readiness based on income consistency, savings discipline, and spending volatility.",
    "2. Identify specific behaviors (e.g., 'Consistent salary deposits', 'Frequent gambling', 'High airtime expense').",
    "3. Provide 3 highly actionable 'Proactive Tips' (e.g., 'Save 5k more per week', 'Reduce airtime spend by 10%').",
    "4. Be professional, empathetic, and 100% accurate. Avoid hallucinations.",
    "",
    "Return JSON only matching the schema.",
  ].join("\n");
}

Deno.serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== "POST") return methodNotAllowed();
  if (!GEMINI_API_KEY) return errorResponse("AI Service not configured.", 503);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return errorResponse("Missing authorization.", 401);

  const adminClient = createAdminClient();
  const userClient = createUserClient(authHeader);
  const { data: { user }, error: authError } = await userClient.auth.getUser();

  if (authError || !user) return errorResponse("Unauthorized.", 401);

  // 1. Fetch User Data
  const { data: userData } = await adminClient
    .from("users")
    .select("*")
    .eq("id", user.id)
    .single();

  // 2. Fetch Last 90 Days of Aggregated Transactions
  const ninetyDaysAgo = new Date();
  ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

  const { data: txData } = await adminClient
    .from("momo_ledger_entries")
    .select("amount, entry_type, tx_category, cashflow_bucket, counterparty_name, tx_datetime")
    .eq("user_id", user.id)
    .eq("ledger_status", "posted")
    .gte("tx_datetime", ninetyDaysAgo.toISOString())
    .order("tx_datetime", { ascending: false });

  // 3. Fetch Group Contribution Data
  const { count: groupCount } = await adminClient
    .from("group_members")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user.id);

  // 4. Summarize Data for AI (Minimize Tokens)
  const txSummary = txData?.reduce((acc: any, tx: any) => {
    const cat = tx.tx_category || "other";
    if (!acc[cat]) acc[cat] = { total: 0, count: 0, type: tx.entry_type };
    acc[cat].total += tx.amount;
    acc[cat].count += 1;
    return acc;
  }, {});

  // 5. Call Gemini 2.0 Pro
  try {
    const prompt = buildInsightsPrompt(userData, txSummary, { count: groupCount });
    const geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: insightsSchema,
          temperature: 0.2,
        },
      }),
    });

    if (!geminiResponse.ok) {
      throw new Error(`Gemini API error: ${await geminiResponse.text()}`);
    }

    const result = await geminiResponse.json();
    const insights = JSON.parse(result.candidates[0].content.parts[0].text);

    // 6. Persist Insight Summary (Optional but recommended for history)
    // We can store this in a new table later if needed.

    return jsonResponse({
      success: true,
      data: insights,
    });

  } catch (err) {
    console.error("Financial Insights Error:", err);
    return errorResponse("Could not generate insights at this time.", 500);
  }
});
