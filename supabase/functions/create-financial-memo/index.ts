import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";
import { createGoogleDoc, logAiAudit } from "../_shared/google_workspace.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.0-pro-exp-02-05"; 
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

function buildMemoPrompt(userData: any, txSummary: any) {
  return [
    "You are a Senior Credit Officer generating a formal 'Financial Position Memo' for a bank loan application.",
    "The user is a community member in Rwanda using the COOL platform.",
    "Write a professional, narrative-style report based on their transaction data.",
    "",
    "### DATA CONTEXT",
    `Name: ${userData.official_name || userData.full_name}`,
    `Platform ID: ${userData.public_user_id}`,
    `90-Day Summary: ${JSON.stringify(txSummary)}`,
    "",
    "### MEMO STRUCTURE",
    "1. EXECUTIVE SUMMARY: A high-level overview of their financial activity.",
    "2. CASHFLOW ANALYSIS: Analysis of income consistency and primary spending buckets.",
    "3. SAVINGS DISCIPLINE: Evidence of group contributions and financial planning.",
    "4. CREDITWORTHINESS STATEMENT: A professional conclusion on their readiness for formal credit.",
    "",
    "Use formal, banking-appropriate English. Avoid conversational AI filler.",
  ].join("\n");
}

Deno.serve(async (req: Request) => {
  const startTime = Date.now();
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

  // 1. Fetch User and History
  const { data: userData } = await adminClient.from("users").select("*").eq("id", user.id).single();
  
  const ninetyDaysAgo = new Date();
  ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

  const { data: txData } = await adminClient
    .from("momo_ledger_entries")
    .select("amount, entry_type, tx_category")
    .eq("user_id", user.id)
    .eq("ledger_status", "posted")
    .gte("tx_datetime", ninetyDaysAgo.toISOString());

  const txSummary = txData?.reduce((acc: any, tx: any) => {
    const cat = tx.tx_category || "other";
    if (!acc[cat]) acc[cat] = { total: 0, count: 0 };
    acc[cat].total += tx.amount;
    acc[cat].count += 1;
    return acc;
  }, {});

  // 2. Generate Narrative with Gemini 2.0 Pro
  try {
    const prompt = buildMemoPrompt(userData, txSummary);
    const geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.1 },
      }),
    });

    const result = await geminiResponse.json();
    const memoNarrative = result.candidates[0].content.parts[0].text;

    // 3. Create Google Doc
    const docTitle = `Financial Memo - ${userData.official_name || userData.full_name} - ${new Date().toLocaleDateString()}`;
    const docUrl = await createGoogleDoc(docTitle, memoNarrative);

    // 4. Audit decision
    await logAiAudit({
      function_name: "create-financial-memo",
      user_id: user.id,
      model: GEMINI_MODEL,
      confidence: 1.0,
      decision: "GENERATED",
      metadata: { doc_title: docTitle },
      latency_ms: Date.now() - startTime
    });

    return jsonResponse({
      success: true,
      data: {
        doc_url: docUrl,
        title: docTitle
      }
    });

  } catch (err) {
    console.error("Memo Generation Error:", err);
    return errorResponse("Failed to generate financial memo.", 500);
  }
});
