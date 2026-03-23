import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";
import { upsertCalendarEvent, logAiAudit } from "../_shared/google_workspace.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.0-pro-exp-02-05"; 
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

// Strict schema for Future Commitment Extraction
const scheduleSchema = {
  type: "object",
  properties: {
    commitments: {
      type: "array",
      items: {
        type: "object",
        properties: {
          summary: { type: "string" },
          description: { type: "string" },
          category: { type: "string", enum: ["income", "bill", "group_contribution", "savings"] },
          predicted_date: { type: "string", description: "YYYY-MM-DD" },
          confidence: { type: "number" }
        },
        required: ["summary", "description", "category", "predicted_date", "confidence"]
      }
    },
    safe_spend_windows: {
      type: "array",
      items: {
        type: "object",
        properties: {
          start: { type: "string" },
          end: { type: "string" },
          reason: { type: "string" }
        }
      }
    }
  },
  required: ["commitments", "safe_spend_windows"]
};

function buildSchedulerPrompt(stats: any) {
  return [
    "You are the 'COOL Financial Planner'.",
    "Analyze the following recurring transaction patterns and predict the exact dates for the NEXT 30 days.",
    "",
    "### RECURRING PATTERNS (90-Day Analysis)",
    JSON.stringify(stats, null, 2),
    "",
    "### TASK",
    "1. Predict the likely date for the next Salary/Income deposit.",
    "2. Predict the next 4 Savings Group contribution deadlines.",
    "3. Identify regular utility bills (Water, Electricity, Internet) and their next due dates.",
    "4. Calculate 'Safe-to-Spend' windows (consecutive days with no predicted bills).",
    "",
    "Return JSON only matching the schema.",
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

  // 1. Fetch 90 days of categorized ledger entries
  const ninetyDaysAgo = new Date();
  ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

  const { data: txData } = await adminClient
    .from("momo_ledger_entries")
    .select("amount, entry_type, tx_category, tx_datetime, statement_label")
    .eq("user_id", user.id)
    .eq("ledger_status", "posted")
    .gte("tx_datetime", ninetyDaysAgo.toISOString());

  // 2. Pattern Analysis with Gemini 2.0 Pro
  try {
    const prompt = buildSchedulerPrompt(txData);
    const geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: scheduleSchema,
          temperature: 0.1,
        },
      }),
    });

    const result = await geminiResponse.json();
    const plannerData = JSON.parse(result.candidates[0].content.parts[0].text);

    // 3. Orchestrate Google Calendar (The "Planning" Flow)
    const eventIds: string[] = [];
    for (const commitment of plannerData.commitments) {
      if (commitment.confidence > 0.7) {
        const eventId = await upsertCalendarEvent({
          summary: commitment.summary,
          description: commitment.description,
          start_date: commitment.predicted_date,
          end_date: commitment.predicted_date,
          category: commitment.category
        });
        if (eventId) eventIds.push(eventId);
      }
    }

    // 4. Governance Audit
    await logAiAudit({
      function_name: "schedule-financial-future",
      user_id: user.id,
      model: GEMINI_MODEL,
      confidence: 0.9,
      decision: "SCHEDULED",
      metadata: { event_count: eventIds.length, windows: plannerData.safe_spend_windows.length },
      latency_ms: Date.now() - startTime
    });

    return jsonResponse({
      success: true,
      data: plannerData,
    });

  } catch (err) {
    console.error("Financial Planner Error:", err);
    return errorResponse("Failed to organize your financial calendar.", 500);
  }
});
