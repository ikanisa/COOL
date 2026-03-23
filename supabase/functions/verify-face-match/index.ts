import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.0-flash"; // Multimodal vision optimized
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

// Strict schema for Multimodal Face-Match
const matchSchema = {
  type: "object",
  properties: {
    is_match: { type: "boolean" },
    confidence: { type: "number", minimum: 0, maximum: 1 },
    reason: { type: "string" },
    facially_detected: { type: "boolean" },
    estimated_age_id: { type: "number" },
    estimated_age_selfie: { type: "number" },
    gender_consistent: { type: "boolean" },
    presentation_attack_detected: {
      type: "boolean",
      description:
        "True if the selfie looks like a photo of a screen or a printout.",
    },
  },
  required: [
    "is_match",
    "confidence",
    "reason",
    "facially_detected",
    "estimated_age_id",
    "estimated_age_selfie",
    "gender_consistent",
    "presentation_attack_detected",
  ],
};

function buildFaceMatchPrompt() {
  return [
    "You are an expert Biometric Verification Agent.",
    "Your task is to compare a person's face on a Government ID with a live Selfie.",
    "",
    "### ANALYSIS CRITERIA",
    "1. STRUCTURAL MATCH: Compare bone structure, eye distance, nose shape, and ear position.",
    "2. CONSISTENCY: Are the estimated age and gender consistent across both images?",
    "3. LIVENESS: Check the selfie for signs of fraud (e.g., moiré patterns from a screen, paper edges from a printout).",
    "4. ROBUSTNESS: Account for different lighting, hairstyles, glasses, or aging (IDs can be 10 years old).",
    "",
    "### OUTPUT RULES",
    "Set 'is_match' to true only if confidence is > 0.8.",
    "Set 'presentation_attack_detected' to true if you suspect the selfie is not a live person.",
    "",
    "Return JSON only matching the schema.",
  ].join("\n");
}

type FaceMatchResult = {
  confidence: number;
  is_match: boolean;
  presentation_attack_detected: boolean;
};

type FaceMatchRequest = {
  idImageBase64?: string;
  selfieBase64?: string;
  idMimeType?: string;
  selfieMimeType?: string;
};

export function mergeFaceMatchIdentityData(
  existingIdentity: Record<string, unknown>,
  matchResult: FaceMatchResult,
  nowIso: string,
): Record<string, unknown> {
  return {
    ...existingIdentity,
    face_match_confidence: matchResult.confidence,
    face_match_status: matchResult.is_match ? "matched" : "mismatch",
    liveness_detected: !matchResult.presentation_attack_detected,
    biometric_verified_at: nowIso,
  };
}

export function createVerifyFaceMatchHandler() {
  return async (req: Request) => {
    const cors = handleCors(req);
    if (cors) return cors;

    if (req.method !== "POST") return methodNotAllowed();
    if (!GEMINI_API_KEY) {
      return errorResponse("AI Service not configured.", 503);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return errorResponse("Missing authorization.", 401);

    const adminClient = createAdminClient();
    const userClient = createUserClient(authHeader);
    const { data: { user }, error: authError } = await userClient.auth
      .getUser();

    if (authError || !user) return errorResponse("Unauthorized.", 401);

    const {
      idImageBase64,
      selfieBase64,
      idMimeType,
      selfieMimeType,
    } = await req.json() as FaceMatchRequest;

    if (!idImageBase64 || !selfieBase64) {
      return errorResponse("Both ID and Selfie images are required.", 400);
    }

    try {
      const geminiResponse = await fetch(GEMINI_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [
            {
              parts: [
                { text: buildFaceMatchPrompt() },
                {
                  inlineData: {
                    mimeType: idMimeType || "image/jpeg",
                    data: idImageBase64,
                  },
                },
                {
                  inlineData: {
                    mimeType: selfieMimeType || "image/jpeg",
                    data: selfieBase64,
                  },
                },
              ],
            },
          ],
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: matchSchema,
            temperature: 0.1,
          },
        }),
      });

      if (!geminiResponse.ok) {
        throw new Error(`Gemini API error: ${await geminiResponse.text()}`);
      }

      const result = await geminiResponse.json();
      const matchResult = JSON.parse(
        result.candidates[0].content.parts[0].text,
      ) as FaceMatchResult;

      const existingProfileResult = await adminClient
        .from("users")
        .select("identity_data")
        .eq("id", user.id)
        .single();
      if (existingProfileResult.error) {
        throw existingProfileResult.error;
      }

      const existingIdentity = existingProfileResult.data.identity_data &&
          typeof existingProfileResult.data.identity_data === "object"
        ? existingProfileResult.data.identity_data as Record<string, unknown>
        : {};
      const nowIso = new Date().toISOString();

      const updateResult = await adminClient
        .from("users")
        .update({
          identity_data: mergeFaceMatchIdentityData(
            existingIdentity,
            matchResult,
            nowIso,
          ),
        })
        .eq("id", user.id);
      if (updateResult.error) {
        throw updateResult.error;
      }

      return jsonResponse({
        success: true,
        data: matchResult,
      });
    } catch (err) {
      console.error("Face-Match AI Error:", err);
      await recordEdgeFunctionFailure(adminClient, {
        functionName: "verify-face-match",
        error: err,
        userId: user.id,
        issueCode: "verify_face_match_failed",
      });
      return errorResponse(
        "Identity verification failed. Please ensure both photos are clear.",
        500,
      );
    }
  };
}

if (import.meta.main) {
  Deno.serve(createVerifyFaceMatchHandler());
}
