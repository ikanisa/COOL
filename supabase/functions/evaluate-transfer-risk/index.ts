import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";
import { logAiAudit } from "../_shared/google_workspace.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.0-flash"; 
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

// ... existing schema and prompt logic ...

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

  const { recipientNumber, amount, currency } = await req.json();

  if (!recipientNumber || !amount) {
    return errorResponse("Recipient and amount are required.", 400);
  }

  // ... existing context fetching logic ...

  // 3. Call Gemini 2.0 Flash for Risk Logic
  try {
    const prompt = buildRiskPrompt(
      { recipientNumber, amount, currency },
      { isKnown, isCoMember, avgAmount, recentRecipients: recentRecipients.slice(0, 10) }
    );

    const geminiResponse = await fetch(GEMINI_URL, {
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

    const result = await geminiResponse.json();
    const riskResult = JSON.parse(result.candidates[0].content.parts[0].text);

    // 4. Audit Decision to Google Workspace (Critical Governance)
    await logAiAudit({
      function_name: "evaluate-transfer-risk",
      user_id: user.id,
      model: GEMINI_MODEL,
      confidence: 1 - riskResult.risk_score,
      decision: riskResult.action_suggestion.toUpperCase(),
      metadata: {
        amount,
        recipient: recipientNumber,
        is_anomaly: riskResult.is_anomaly,
        reason: riskResult.reason
      },
      latency_ms: Date.now() - startTime
    });

    return jsonResponse({
      success: true,
      data: riskResult,
    });

  } catch (err) {
    console.error("Guardian AI Error:", err);
    // Fail-safe: Low risk if AI is down but mark as unverified
    return jsonResponse({
      success: true,
      data: {
        risk_score: 0.1,
        is_anomaly: false,
        reason: "Guardian AI is currently offline. Verification skipped.",
        warning_title: "",
        warning_body: "",
        trust_score: 0.5,
        action_suggestion: "allow"
      }
    });
  }
});
