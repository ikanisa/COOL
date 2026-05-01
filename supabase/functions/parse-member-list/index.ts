import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import { HttpError, requireAdminCaller } from "../_shared/auth.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const MAX_MEMBER_LIST_BYTES = 5 * 1024 * 1024;
const ALLOWED_MEMBER_LIST_MIME_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/pdf",
]);

interface ParsedMember {
  name: string;
  phone: string;
}

type ValidatedMemberListUpload = {
  imageBase64: string;
  mimeType: string;
};

function validateMemberListUpload(
  imageBase64: unknown,
  mimeType: unknown,
): ValidatedMemberListUpload {
  if (typeof imageBase64 !== "string" || imageBase64.trim().length === 0) {
    throw new HttpError(
      400,
      "image_base64 is required (base64-encoded image or PDF).",
    );
  }

  const resolvedMimeType =
    typeof mimeType === "string" && mimeType.trim().length > 0
      ? mimeType.trim().toLowerCase()
      : "image/jpeg";

  if (!ALLOWED_MEMBER_LIST_MIME_TYPES.has(resolvedMimeType)) {
    throw new HttpError(
      400,
      "Unsupported member-list file type.",
    );
  }

  const base64Payload = imageBase64.includes(",")
    ? imageBase64.slice(imageBase64.indexOf(",") + 1)
    : imageBase64;
  const normalizedBase64 = base64Payload.replace(/\s/g, "");

  if (
    normalizedBase64.length % 4 === 1 ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(normalizedBase64)
  ) {
    throw new HttpError(400, "Invalid base64 upload payload.");
  }

  const estimatedBytes = Math.floor((normalizedBase64.length * 3) / 4);
  if (estimatedBytes > MAX_MEMBER_LIST_BYTES) {
    throw new HttpError(413, "Member-list upload exceeds the 5 MiB limit.");
  }

  return {
    imageBase64: normalizedBase64,
    mimeType: resolvedMimeType,
  };
}

/**
 * Sends an image (base64) to Gemini Vision to extract a member list table.
 * Returns structured [{ name, phone }] array.
 */
async function parseWithGemini(
  imageBase64: string,
  mimeType: string,
): Promise<ParsedMember[]> {
  if (!GEMINI_API_KEY) {
    throw new Error("GEMINI_API_KEY not configured");
  }

  const systemPrompt =
    `You are a document parser for a Rwandan fintech app called COOL.
You will receive an image of a member list — it may be a handwritten table, a printed sheet, a screenshot, or a PDF page.

Extract ALL members from the document. For each member, extract:
- name: the person's full name
- phone: their phone number (preferably in E.164 format starting with +250, but accept any format)

Rules:
- If phone numbers don't have a country code, assume Rwanda (+250)
- Clean up phone numbers: remove spaces, dashes, parentheses
- If a phone starts with "0", convert to "+250" prefix (e.g., "0788123456" → "+250788123456")
- Skip empty rows or rows with no discernible name+phone
- Output ONLY a valid JSON array, no markdown fences
- If you cannot parse any members, return an empty array []

Example output:
[{"name": "Jean Bosco", "phone": "+250788123456"}, {"name": "Marie Claire", "phone": "+250789654321"}]`;

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { text: systemPrompt },
              {
                inlineData: {
                  mimeType: mimeType,
                  data: imageBase64,
                },
              },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 4096,
          responseMimeType: "application/json",
        },
      }),
    },
  );

  if (!res.ok) {
    await res.body?.cancel();
    console.error("Gemini API error:", res.status);
    throw new Error(`Gemini API returned ${res.status}`);
  }

  const data = await res.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? "";
  if (!text) {
    return [];
  }

  const parsed = JSON.parse(text);
  if (!Array.isArray(parsed)) {
    return [];
  }

  // Validate and clean each entry
  return parsed
    .filter(
      (entry: Record<string, unknown>) =>
        typeof entry.name === "string" && typeof entry.phone === "string",
    )
    .map((entry: Record<string, string>) => ({
      name: entry.name.trim(),
      phone: normalizePhone(entry.phone.trim()),
    }))
    .filter((entry: ParsedMember) => entry.name && entry.phone);
}

/** Normalize a Rwandan phone number to E.164 */
function normalizePhone(phone: string): string {
  // Remove spaces, dashes, parens
  let cleaned = phone.replace(/[\s\-()]/g, "");

  // Convert 07xx to +25007xx or 078x to +25078x
  if (cleaned.startsWith("0") && cleaned.length >= 10) {
    cleaned = "+250" + cleaned.slice(1);
  }

  // Add + if missing
  if (cleaned.startsWith("250") && !cleaned.startsWith("+")) {
    cleaned = "+" + cleaned;
  }

  return cleaned;
}

async function handler(request: Request): Promise<Response> {
  const corsResponse = handleCors(request);
  if (corsResponse) return corsResponse;

  if (request.method !== "POST") {
    return methodNotAllowed("POST", request);
  }

  const adminClient = createAdminClient();

  try {
    // Require admin authentication
    await requireAdminCaller(request);

    const body = await request.json();
    const { image_base64, mime_type } = body;

    const upload = validateMemberListUpload(image_base64, mime_type);
    const members = await parseWithGemini(upload.imageBase64, upload.mimeType);

    return jsonResponse(
      {
        success: true,
        members,
        count: members.length,
      },
      200,
      {},
      request,
    );
  } catch (error) {
    if (error instanceof HttpError) {
      return errorResponse(error.message, error.status, undefined, request);
    }

    console.error("parse-member-list failed:", error);
    await recordEdgeFunctionFailure(adminClient, {
      functionName: "parse-member-list",
      error,
      userId: null,
      issueCode: "parse_member_list_failed",
    });

    return errorResponse(
      "Failed to parse member list.",
      500,
      undefined,
      request,
    );
  }
}

Deno.serve(handler);
