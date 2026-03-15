import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient } from "../_shared/supabase.ts";

type TranslateRequest = {
  text: string;
  targetLanguage: string;
  sourceLanguage?: string;
  format?: "text" | "html";
};

const GOOGLE_TRANSLATE_URL =
  "https://translation.googleapis.com/language/translate/v2";

Deno.serve(async (request: Request) => {
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method != "POST") {
    return methodNotAllowed("POST");
  }

  const apiKey = Deno.env.get("GOOGLE_TRANSLATE_API_KEY") ||
    Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return errorResponse("Google Translate API key not configured.", 500);
  }

  try {
    const { text, targetLanguage, sourceLanguage, format } =
      (await request.json()) as TranslateRequest;

    if (!text || !targetLanguage) {
      return errorResponse("text and targetLanguage are required.", 400);
    }

    const url = new URL(GOOGLE_TRANSLATE_URL);
    url.searchParams.set("key", apiKey);

    const response = await fetch(url.toString(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        q: text,
        target: targetLanguage,
        source: sourceLanguage,
        format: format || "text",
      }),
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(
        `Google Translate API failed: ${JSON.stringify(data.error)}`,
      );
    }

    const translation = data.data.translations[0];

    return jsonResponse({
      success: true,
      translatedText: translation.translatedText,
      detectedSourceLanguage: translation.detectedSourceLanguage,
    });
  } catch (error) {
    console.error("translate-content failed", error);
    await recordEdgeFunctionFailure(createAdminClient(), {
      functionName: "translate-content",
      error,
    });
    return errorResponse(
      error instanceof Error ? error.message : "Translation failed",
      500,
    );
  }
});
