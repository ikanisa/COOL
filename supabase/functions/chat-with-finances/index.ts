import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.0-flash"; // Speed + Intelligence balance for Chat
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

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

  const { message, history } = await req.json();

  // 1. Fetch Context: Last 30 days of categorized transactions
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const { data: txData } = await adminClient
    .from("momo_ledger_entries")
    .select("amount, entry_type, tx_category, counterparty_name, tx_datetime, statement_label")
    .eq("user_id", user.id)
    .eq("ledger_status", "posted")
    .gte("tx_datetime", thirtyDaysAgo.toISOString())
    .order("tx_datetime", { ascending: false });

  // 2. Aggregate Context for Token Efficiency
  const txSummary = txData?.reduce((acc: any, tx: any) => {
    const cat = tx.tx_category || "other";
    if (!acc[cat]) acc[cat] = { total: 0, count: 0, type: tx.entry_type };
    acc[cat].total += tx.amount;
    acc[cat].count += 1;
    return acc;
  }, {});

  const recentTxs = txData?.slice(0, 10).map(t => ({
    date: t.tx_datetime.split('T')[0],
    amount: t.amount,
    type: t.entry_type,
    label: t.statement_label || t.counterparty_name,
    category: t.tx_category
  }));

  // 3. Build Agentic System Prompt
  const systemPrompt = [
    "You are the 'Cool Assistant', a smart financial agent for a user in Rwanda.",
    "You have access to the user's transaction history for the last 30 days.",
    "Your tone is helpful, professional, and concise. Use emojis occasionally (💸, 📈, ✅).",
    "",
    "### FINANCIAL CONTEXT",
    `Total Categorized Spend/Income: ${JSON.stringify(txSummary)}`,
    `10 Most Recent Transactions: ${JSON.stringify(recentTxs)}`,
    "",
    "### RULES",
    "1. Be 100% accurate with numbers. If you don't know, say so.",
    "2. If the user asks about a specific category, refer to the 'Total Categorized' data.",
    "3. Protect privacy. Do not mention full names of counterparties unless asked.",
    "4. Keep answers short (max 3 sentences) unless more detail is requested.",
  ].join("\n");

  // 4. Call Gemini 2.0 Flash
  try {
    const geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          { role: "user", parts: [{ text: systemPrompt }] },
          ...(history || []).map((h: any) => ({
            role: h.role === "user" ? "user" : "model",
            parts: [{ text: h.content }]
          })),
          { role: "user", parts: [{ text: message }] }
        ],
        generationConfig: {
          temperature: 0.3,
          maxOutputTokens: 512,
        },
      }),
    });

    if (!geminiResponse.ok) {
      throw new Error(`Gemini API error: ${await geminiResponse.text()}`);
    }

    const result = await geminiResponse.json();
    const reply = result.candidates[0].content.parts[0].text;

    return jsonResponse({
      success: true,
      data: { reply },
    });

  } catch (err) {
    console.error("Chat AI Error:", err);
    return errorResponse("Assistant is currently resting. Try again shortly.", 500);
  }
});
