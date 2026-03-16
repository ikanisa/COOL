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
const encoder = new TextEncoder();

async function getWorkspaceAccessToken(): Promise<string> {
  const saRaw = Deno.env.get("GOOGLE_WALLET_SERVICE_ACCOUNT_JSON");
  if (!saRaw) throw new Error("Missing GOOGLE_WALLET_SERVICE_ACCOUNT_JSON");
  const sa = JSON.parse(saRaw);

  const issuedAt = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/calendar.readonly",
    aud: "https://oauth2.googleapis.com/token",
    iat: issuedAt,
    exp: issuedAt + 3600,
  };

  const b64UrlEncodeBytes = (bytes: Uint8Array) =>
    btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const b64UrlEncodeJson = (json: unknown) =>
    b64UrlEncodeBytes(encoder.encode(JSON.stringify(json)));

  const encodedHeader = b64UrlEncodeJson(header);
  const encodedPayload = b64UrlEncodeJson(payload);
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  const normalized = sa.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");

  const binary = Uint8Array.from(atob(normalized), (char) => char.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    binary.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(signingInput));
  const assertion = `${signingInput}.${b64UrlEncodeBytes(new Uint8Array(signature))}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  const data = await response.json();
  if (!response.ok) {
    console.error("Token error:", data);
    throw new Error("Failed to get Google Access Token");
  }

  return data.access_token;
}

Deno.serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== "POST") return methodNotAllowed("POST");

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return errorResponse("Missing authorization.", 401);

  const userClient = createUserClient(authHeader);
  const { data: { user }, error: authError } = await userClient.auth.getUser();

  if (authError || !user) return errorResponse("Unauthorized.", 401);

  let body;
  try {
    body = await req.json();
  } catch (_e) {
    body = {};
  }

  const { latitude, longitude, timezone } = body;
  const userLocationContext = (latitude && longitude) 
    ? `User is currently at latitude: ${latitude}, longitude: ${longitude}.` 
    : "User location is unknown.";
  const userTimezoneContext = timezone ? `User timezone: ${timezone}.` : "";

  // In production, we'd map this dynamically per-user. 
  // For demo/admin purposes we query the primary authenticated account.
  const CALENDAR_ID = "info@ikanisa.com";

  try {
    const token = await getWorkspaceAccessToken();
    const timeMin = new Date().toISOString();
    
    // Fetch from Calendar API
    const calUrl = `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(CALENDAR_ID)}/events?maxResults=5&singleEvents=true&orderBy=startTime&timeMin=${encodeURIComponent(timeMin)}`;
    const calRes = await fetch(calUrl, {
      headers: { Authorization: `Bearer ${token}` }
    });

    if (!calRes.ok) {
      console.error("Calendar API returned non-OK:", await calRes.text());
      return errorResponse(`Failed to fetch calendar for ${CALENDAR_ID}`, 502);
    }

    const calData = await calRes.json();
    const rawEvents = (calData.items || []).slice(0, 3).map((e: Record<string, any>) => ({
      summary: e.summary,
      start: e.start?.dateTime || e.start?.date,
      location: e.location || "",
    }));

    if (rawEvents.length === 0) {
      return jsonResponse({ success: true, data: [] });
    }

    const systemPrompt = `You are a helpful mobility assistant for the COOL app in Rwanda.
I will provide you with a list of upcoming calendar events. 
Convert them into an array of TripSuggestion objects.
${userLocationContext}
${userTimezoneContext}

A TripSuggestion object has:
- title: A short title for the trip (e.g. "Meeting at Marriott"). Maximum 25 chars.
- promptText: A natural language request that someone would say to a driver or taxi app to get there at that time (e.g. "Take me to Marriott Hotel tomorrow at 9am"). Include the specific location from the event if possible.
- timeLabel: A formatted friendly time string relative to now (e.g. "Tomorrow, 9:00 AM", or "Today, 14:30").

List of events:
${JSON.stringify(rawEvents, null, 2)}`;

    const geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          { role: "user", parts: [{ text: systemPrompt }] }
        ],
        generationConfig: {
          temperature: 0.1,
          responseMimeType: "application/json",
          responseSchema: {
            type: "ARRAY",
            items: {
              type: "OBJECT",
              properties: {
                title: { type: "STRING" },
                promptText: { type: "STRING" },
                timeLabel: { type: "STRING" }
              },
              required: ["title", "promptText", "timeLabel"]
            }
          }
        },
      }),
    });

    if (!geminiResponse.ok) {
      console.error("Gemini API error", await geminiResponse.text());
      throw new Error("Gemini API error");
    }

    const result = await geminiResponse.json();
    const replyText = result.candidates?.[0]?.content?.parts?.[0]?.text;

    let parsed = [];
    if (replyText) {
      parsed = JSON.parse(replyText);
    }

    return jsonResponse({
      success: true,
      data: parsed,
    });

  } catch (err) {
    console.error("Workspace Calendar Error:", err);
    return errorResponse("Failed to fetch and parse workspace calendar.", 500);
  }
});
