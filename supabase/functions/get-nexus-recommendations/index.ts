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

// Strict schema for Nexus Opportunity Matching
const nexusSchema = {
  type: "object",
  properties: {
    recommendations: {
      type: "array",
      items: {
        type: "object",
        properties: {
          id: { type: "string" },
          type: { type: "string", enum: ["mission", "loan", "service", "upgrade"] },
          title: { type: "string" },
          subtitle: { type: "string" },
          rationale: { type: "string" },
          cta_label: { type: "string" },
          cta_route: { type: "string" },
          priority: { type: "number", minimum: 0, maximum: 1 },
          accent_color: { type: "string" }
        },
        required: ["id", "type", "title", "subtitle", "rationale", "cta_label", "cta_route", "priority"]
      }
    }
  },
  required: ["recommendations"]
};

function buildNexusPrompt(userData: any, insights: any, catalog: any) {
  return [
    "You are the 'COOL Nexus', a hyper-personalization agent.",
    "Match the user's financial profile to the best opportunities in our Partner Catalog.",
    "",
    "### USER PROFILE",
    `Name: ${userData.official_name || userData.full_name}`,
    `Credit Readiness: ${insights.credit_readiness}`,
    `Savings Scores: Discipline=${insights.savings_discipline_score}, Stability=${insights.income_stability_score}`,
    "",
    "### PARTNER CATALOG",
    JSON.stringify(catalog, null, 2),
    "",
    "### TASK",
    "1. Select 3 high-impact recommendations.",
    "2. If Credit Readiness is High/Excellent, prioritize Urwego Bank loans.",
    "3. If frequent mobility spend is detected, suggest a Moto Subscription.",
    "4. If they are a Rayon Sports fan but not a member, suggest joining.",
    "5. Provide a 'rationale' that uses their data (e.g., 'Because your discipline is 90%...').",
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

  // 1. Fetch Context: User Data + Latest Credit Insights
  const { data: userData } = await adminClient.from("users").select("*").eq("id", user.id).single();
  
  // Simulated: In a full app, we'd fetch from a 'credit_insights' table or re-invoke the insights function
  const insights = {
    credit_readiness: "high",
    savings_discipline_score: 88,
    income_stability_score: 75
  };

  // 2. Fetch Catalog (Partner Services + Active Missions)
  const { data: services } = await adminClient
    .from("partner_services")
    .select("title, subtitle, category, cta_label, cta_action")
    .limit(10);

  const { data: missions } = await adminClient
    .from("missions")
    .select("id, title, description, reward_points")
    .eq("is_active", true)
    .limit(5);

  const catalog = { services, missions };

  // 3. AI Opportunity Matching
  try {
    const prompt = buildNexusPrompt(userData, insights, catalog);
    const geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: nexusSchema,
          temperature: 0.2,
        },
      }),
    });

    if (!geminiResponse.ok) {
      throw new Error(`Gemini API error: ${await geminiResponse.text()}`);
    }

    const result = await geminiResponse.json();
    const recommendations = JSON.parse(result.candidates[0].content.parts[0].text);

    // 4. Audit
    await logAiAudit({
      function_name: "get-nexus-recommendations",
      user_id: user.id,
      model: GEMINI_MODEL,
      confidence: 0.95,
      decision: "MATCHED",
      metadata: { count: recommendations.recommendations.length },
      latency_ms: Date.now() - startTime
    });

    return jsonResponse({
      success: true,
      data: recommendations,
    });

  } catch (err) {
    console.error("Nexus Error:", err);
    return errorResponse("Could not find personalized opportunities right now.", 500);
  }
});
