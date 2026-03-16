import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";
import {
  asString,
  kycOcrJsonSchema,
  normalizeKycExtraction,
  unwrapJsonText,
} from "./rules.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.0-flash";
const GEMINI_URL =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

type KycOcrRequest = {
  documentType?: string;
  frontImage?: string;
  frontMimeType?: string;
  backImage?: string;
  backMimeType?: string;
  image?: string;
  mimeType?: string;
};

function buildExtractionPrompt(documentTypeHint: string | null) {
  return [
    "You are an expert identity-document OCR system for regulated onboarding.",
    "Extract only fields that are clearly visible on the uploaded identity document images.",
    "Do not invent values. Return null for anything unreadable or missing.",
    "If the upload is not a valid government identity document, set confidence to 0.",
    "Prefer the document holder's legal full name exactly as shown.",
    "dateOfBirth and expiryDate must be YYYY-MM-DD when present.",
    "nationalIdNumber should contain the main document number shown on the card.",
    "gender should be a short visible marker such as M or F when shown.",
    documentTypeHint == null
      ? "No document type hint was provided."
      : `Document type hint: ${documentTypeHint}.`,
    "",
    "Return JSON only that matches the provided schema.",
  ].join("\n");
}

Deno.serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method !== "POST") {
    return methodNotAllowed();
  }

  if (!GEMINI_API_KEY) {
    return errorResponse("KYC OCR service is not configured.", 503);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse("Missing authorization header.", 401);
  }

  const adminClient = createAdminClient();

  const userClient = createUserClient(authHeader);
  const {
    data: { user },
    error: authError,
  } = await userClient.auth.getUser();

  if (authError || !user) {
    return errorResponse("Unauthorized.", 401);
  }

  let requestBody: KycOcrRequest;

  try {
    requestBody = await req.json() as KycOcrRequest;
  } catch {
    return errorResponse("Invalid JSON body.", 400);
  }

  const documentType = asString(requestBody.documentType);
  const frontImage = asString(requestBody.frontImage) ??
    asString(requestBody.image);
  const frontMimeType = asString(requestBody.frontMimeType) ??
    asString(requestBody.mimeType) ??
    "image/jpeg";
  const backImage = asString(requestBody.backImage);
  const backMimeType = asString(requestBody.backMimeType) ?? "image/jpeg";

  if (!frontImage) {
    return errorResponse("Missing frontImage field.", 400);
  }

  const totalBytesEstimate = frontImage.length + (backImage?.length ?? 0);
  if (totalBytesEstimate > 15 * 1024 * 1024 * 1.37) {
    return errorResponse(
      "Images too large. Maximum combined size is 15MB.",
      400,
    );
  }

  try {
    const geminiResponse = await fetch(GEMINI_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { text: buildExtractionPrompt(documentType) },
              {
                inlineData: {
                  mimeType: frontMimeType,
                  data: frontImage,
                },
              },
              ...(backImage == null ? [] : [{
                inlineData: {
                  mimeType: backMimeType,
                  data: backImage,
                },
              }]),
            ],
          },
        ],
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 1024,
          responseMimeType: "application/json",
          responseSchema: kycOcrJsonSchema,
        },
      }),
    });

    if (!geminiResponse.ok) {
      const errText = await geminiResponse.text();
      console.error("Gemini API error:", errText);
      return errorResponse("OCR service temporarily unavailable.", 502);
    }

    const geminiData = await geminiResponse.json();
    const rawText = (geminiData?.candidates?.[0]?.content?.parts ?? [])
      .map((part: { text?: string }) => part.text ?? "")
      .join("\n");

    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(unwrapJsonText(rawText)) as Record<string, unknown>;
    } catch {
      console.error("Failed to parse Gemini response:", rawText);
      return errorResponse(
        "Could not extract information from the image. Please try again with a clearer photo.",
        422,
      );
    }

    const extracted = normalizeKycExtraction(parsed, documentType);
    if (extracted.confidence < 0.35 || extracted.fullName == null) {
      return jsonResponse(
        {
          success: false,
          message:
            "This does not appear to be a valid identity document. Please take a clear photo of your ID card.",
          data: null,
        },
        200,
      );
    }

    const existingProfileResult = await adminClient
      .from("users")
      .select("phone, official_phone, identity_data")
      .eq("id", user.id)
      .single();
    if (existingProfileResult.error) {
      throw existingProfileResult.error;
    }

    const nowIso = new Date().toISOString();
    const existingIdentity = existingProfileResult.data.identity_data &&
        typeof existingProfileResult.data.identity_data === "object"
      ? existingProfileResult.data.identity_data as Record<string, unknown>
      : {};

    const updatedProfileResult = await adminClient
      .from("users")
      .update({
        full_name: extracted.fullName,
        official_name: extracted.fullName,
        official_phone: asString(existingProfileResult.data.official_phone) ??
          asString(existingProfileResult.data.phone) ??
          asString(user.phone),
        date_of_birth: extracted.dateOfBirth,
        national_id_number: extracted.nationalIdNumber,
        kyc_document_type: extracted.documentType,
        kyc_status: "pending_review",
        kyc_verified_at: null,
        kyc_extracted_at: nowIso,
        kyc_extraction_provider: "gemini",
        identity_data: {
          ...existingIdentity,
          provider: "gemini",
          extracted_at: nowIso,
          confidence: extracted.confidence,
          gender: extracted.gender,
          nationality: extracted.nationality,
          document_type: extracted.documentType,
          issuing_country: extracted.issuingCountry,
          expiry_date: extracted.expiryDate,
          requested_document_type: documentType,
          has_back_image: backImage != null,
        },
      })
      .eq("id", user.id)
      .select()
      .single();
    if (updatedProfileResult.error) {
      throw updatedProfileResult.error;
    }

    return jsonResponse({
      success: true,
      data: {
        extracted,
        profile: updatedProfileResult.data,
      },
    });
  } catch (err) {
    console.error("KYC OCR error:", err);
    await recordEdgeFunctionFailure(adminClient, {
      functionName: "kyc-ocr",
      error: err,
      userId: user.id,
      issueCode: "kyc_ocr_failed",
      metadata: {
        document_type: documentType,
        has_back_image: backImage != null,
      },
    });
    return errorResponse("An unexpected error occurred.", 500);
  }
});
