import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { createUserClient } from "../_shared/supabase.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GOOGLE_MAPS_API_KEY = Deno.env.get("GOOGLE_MAPS_API_KEY") || GEMINI_API_KEY;
const GEMINI_MODEL = "gemini-2.0-flash";
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

async function geocodeLocation(query: string, near?: { lat: number; lng: number }): Promise<{
  label: string;
  lat: number;
  lng: number;
} | null> {
  if (!GOOGLE_MAPS_API_KEY || !query) return null;

  try {
    const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
    url.searchParams.set("address", query);
    url.searchParams.set("key", GOOGLE_MAPS_API_KEY);
    url.searchParams.set("region", "rw"); // Bias to Rwanda
    if (near) {
      url.searchParams.set("location", `${near.lat},${near.lng}`);
    }

    const res = await fetch(url.toString());
    const data = await res.json();

    if (data.status === "OK" && data.results?.[0]) {
      const result = data.results[0];
      return {
        label: result.formatted_address,
        lat: result.geometry.location.lat,
        lng: result.geometry.location.lng,
      };
    }
  } catch (err) {
    console.error(`Geocoding failed for ${query}:`, err);
  }
  return null;
}

// ── Rate limiting (10 requests/minute per user) ────────────────────────────
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 10;
const rateLimitMap = new Map<string, { count: number; windowStart: number }>();

function checkRateLimit(userId: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(userId);
  if (!entry || now - entry.windowStart > RATE_LIMIT_WINDOW_MS) {
    rateLimitMap.set(userId, { count: 1, windowStart: now });
    return true;
  }
  if (entry.count >= RATE_LIMIT_MAX) return false;
  entry.count++;
  return true;
}

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

  if (!checkRateLimit(user.id)) {
    return errorResponse("Rate limit exceeded. Max 10 requests per minute.", 429);
  }

  let body;
  try {
    body = await req.json();
  } catch (_e) {
    return errorResponse("Invalid JSON body", 400);
  }

  const { text, latitude, longitude, timezone } = body;
  if (!text || typeof text !== "string") {
    return errorResponse("Missing 'text' in request body.", 400);
  }

  const today = new Date().toISOString();
  const userLocationContext = (latitude && longitude) 
    ? `User is currently at latitude: ${latitude}, longitude: ${longitude}.` 
    : "User location is unknown.";
  const userTimezoneContext = timezone ? `User timezone: ${timezone}.` : "";

  const systemPrompt = `You are a helpful mobility assistant for the COOL app in Rwanda.
Your job is to parse a user's natural language request for scheduling a trip into a structured JSON object.
${userLocationContext}
${userTimezoneContext}

Extract the following fields:
- origin: The pickup location name.
- destination: The dropoff location name.
- date: The date of the trip (YYYY-MM-DD format). If they say "tomorrow", "next tuesday", calculate it relative to today: ${today} (UTC).
- time: The time of the trip (HH:mm format, 24-hour).
- price_note: Any mention of price or negotiation (e.g., "5000 RWF", "Negotiable").
- seats: Number of seats requested (integer).
- vehicle_preference: "moto", "cab", or "any". Default to "any".`;

  try {
    const geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          { role: "user", parts: [{ text: systemPrompt + "\n\nUser Request: " + text }] }
        ],
        generationConfig: {
          temperature: 0.1,
          responseMimeType: "application/json",
          responseSchema: {
            type: "OBJECT",
            properties: {
              origin: { type: "STRING" },
              destination: { type: "STRING" },
              date: { type: "STRING" },
              time: { type: "STRING" },
              price_note: { type: "STRING" },
              seats: { type: "INTEGER" },
              vehicle_preference: { 
                type: "STRING", 
                enum: ["moto", "cab", "any"] 
              }
            },
            required: ["origin", "destination", "vehicle_preference"]
          }
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

    const parsed = JSON.parse(replyText);

    // Geocode the extracted text to provide exact coordinates to the app
    const near = (latitude && longitude) ? { lat: latitude, lng: longitude } : undefined;
    const [resolvedOrigin, resolvedDest] = await Promise.all([
      geocodeLocation(parsed.origin, near),
      geocodeLocation(parsed.destination, near),
    ]);

    if (resolvedOrigin) {
      parsed.origin_label = resolvedOrigin.label;
      parsed.origin_lat = resolvedOrigin.lat;
      parsed.origin_lng = resolvedOrigin.lng;
    }

    if (resolvedDest) {
      parsed.destination_label = resolvedDest.label;
      parsed.destination_lat = resolvedDest.lat;
      parsed.destination_lng = resolvedDest.lng;
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
