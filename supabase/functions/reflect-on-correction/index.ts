import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import { logAiAudit } from "../_shared/google_workspace.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.0-pro-exp-02-05"; 
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

// Schema for the "Lesson Learned"
const lessonSchema = {
  type: "object",
  properties: {
    failure_reason: { type: "string" },
    key_missed_pattern: { type: "string", description: "The specific keyword or phrase missed." },
    new_rule_instruction: { 
      type: "string", 
      description: "A one-sentence instruction for future prompts." 
    },
    confidence_in_lesson: { type: "number" }
  },
  required: ["failure_reason", "key_missed_pattern", "new_rule_instruction", "confidence_in_lesson"]
};

function buildReflectionPrompt(rawSms: string, original: any, correction: any) {
  return [
    "You are an AI Meta-Cognition Agent.",
    "You previously parsed a MoMo SMS, but the user manually corrected your categorization.",
    "Analyze the discrepancy and derive a lesson to prevent this error in the future.",
    "",
    "### RAW SMS",
    rawSms,
    "",
    "### YOUR ORIGINAL PREDICTION",
    JSON.stringify(original),
    "",
    "### USER'S CORRECTION",
    JSON.stringify(correction),
    "",
    "### TASK",
    "1. Identify the linguistic pattern or keyword in the SMS that justifies the User's Correction.",
    "2. Formulate a 'New Rule' (e.g., 'If SMS contains keyword X, always categorize as Y').",
    "3. Be extremely precise. Do not over-generalize.",
    "",
    "Return JSON only matching the schema.",
  ].join("\n");
}

Deno.serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== "POST") return methodNotAllowed();
  if (!GEMINI_API_KEY) return errorResponse("AI Service not configured.", 503);

  const { recordId, rawInput, originalPayload, correctedPayload } = await req.json();

  const adminClient = createAdminClient();

  try {
    // 1. Ask Gemini to reflect on its own mistake
    const prompt = buildReflectionPrompt(rawInput, originalPayload, correctedPayload);
    const geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: lessonSchema,
          temperature: 0.1,
        },
      }),
    });

    if (!geminiResponse.ok) throw new Error("Gemini Reflection failed.");

    const result = await geminiResponse.json();
    const lesson = JSON.parse(result.candidates[0].content.parts[0].text);

    // 2. Persist Lesson to "AI Lesson Vault" (Google Sheets via Audit tool)
    await logAiAudit({
      function_name: "reflect-on-correction",
      user_id: "system",
      model: GEMINI_MODEL,
      confidence: lesson.confidence_in_lesson,
      decision: "LEARNED",
      metadata: {
        record_id: recordId,
        failure: lesson.failure_reason,
        rule: lesson.new_rule_instruction,
        pattern: lesson.key_missed_pattern
      },
      latency_ms: 0
    });

    // 3. Optional: Store in Postgres for hot-path few-shot prompting
    // We would insert into an 'ai_lessons' table here.

    return jsonResponse({
      success: true,
      data: lesson
    });

  } catch (err) {
    console.error("Reflection Error:", err);
    return errorResponse("Failed to learn from correction.", 500);
  }
});
