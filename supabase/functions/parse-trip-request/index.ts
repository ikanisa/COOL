import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { createUserClient } from "../_shared/supabase.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.0-flash";
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

Deno.serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== "POST") return methodNotAllowed("POST");
  if (!GEMINI_API_KEY) return errorResponse("AI Service not configured.", 503);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return errorResponse("Missing authorization.", 401);

  const userClient = createUserClient(authHeader);
  const { data: { user }, error: authError } = await userClient.auth.getUser();

  if (authError || !user) return errorResponse("Unauthorized.", 401);

  let body;
  try {
    body = await req.json();
  } catch (_e) {
    return errorResponse("Invalid JSON body", 400);
  }

  const { text } = body;
  if (!text || typeof text !== "string") {
    return errorResponse("Missing 'text' in request body.", 400);
  }

  const today = new Date().toISOString();

  const systemPrompt = `You are a helpful mobility assistant for the COOL app in Rwanda.
Your job is to parse a user's natural language request for scheduling a trip into a structured JSON object.

Extract the following fields if present:
- origin: The pickup location (string)
- destination: The dropoff location (string)
- date: The date of the trip (YYYY-MM-DD format). If they say "tomorrow", "next tuesday", calculate it relative to today: ${today} (which is UTC). If not specified, leave null.
- time: The time of the trip (HH:mm format, 24-hour). If not specified, leave null.
- price_note: Any mention of price or negotiation (string, e.g., "5000 RWF", "Negotiable"). If not specified, leave null.
- seats: Number of seats requested (integer). If not specified, leave null.
- vehicle_preference: "moto", "cab", or "any". Default to "any".

Respond ONLY with valid JSON. Do not include markdown code block formatting like \`\`\`json.
Example output:
{
  "origin": "KGL airport",
  "destination": "Marriott",
  "date": "2023-10-28",
  "time": "17:00",
  "price_note": "5000 RWF",
  "seats": 1,
  "vehicle_preference": "any"
}`;

  try {
    const geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          { role: "user", parts: [{ text: systemPrompt + "\\n\\nUser Request: " + text }] }
        ],
        generationConfig: {
          temperature: 0.1,
          responseMimeType: "application/json",
        },
      }),
    });

    if (!geminiResponse.ok) {
      const errText = await geminiResponse.text();
      console.error("Gemini API error:", errText);
      throw new Error("Gemini API error");
    }

    const result = await geminiResponse.json();
    const replyText = result.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!replyText) {
      throw new Error("No text returned from Gemini");
    }

    let parsed;
    try {
      parsed = JSON.parse(replyText);
    } catch (e) {
      console.error("Failed to parse JSON:", replyText);
      parsed = {};
    }

    return jsonResponse({
      success: true,
      data: parsed,
    });
  } catch (err) {
    console.error("Trip Parse Error:", err);
    return errorResponse("Failed to parse trip request.", 500);
  }
});
