import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import {
  type AuthenticatedCaller,
  HttpError,
  requireAdminCaller,
  requireCronSecret,
} from "../_shared/auth.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");

const CONTENT_TEMPLATES = [
  {
    area: "mobile_money",
    prompt:
      "Generate a short, actionable financial tip about mobile money usage, spending tracking, or savings habits in Rwanda/East Africa. Keep it practical and encouraging.",
    icon: "📊",
    cta_action: "/momo",
    cta_label: "Open MoMo",
  },
  {
    area: "groups",
    prompt:
      "Generate a short, compelling recommendation about community group savings — why joining or creating a savings group is beneficial. Reference East African tontine/ikimina culture.",
    icon: "🤝",
    cta_action: "/groups",
    cta_label: "View Groups",
  },
  {
    area: "tokens",
    prompt:
      "Generate a short, motivating message about earning rewards through daily app engagement. Mention specific activities like scheduling rides, joining groups, or checking statements.",
    icon: "🪙",
    cta_action: "/tokens",
    cta_label: "Earn Tokens",
  },

  {
    area: "general",
    prompt:
      "Generate a short, inspiring message about personal finance growth, digital financial literacy, or making the most of fintech tools in daily life.",
    icon: "✨",
    cta_action: "/home",
    cta_label: "Explore",
  },
];

interface GeneratedContent {
  title: string;
  subtitle: string;
  body: string;
  rationale: string;
}

async function generateWithGemini(
  prompt: string,
): Promise<GeneratedContent | null> {
  if (!GEMINI_API_KEY) {
    console.error("GEMINI_API_KEY not set");
    return null;
  }

  const systemPrompt =
    `You are a fintech app content generator for COOL, a mobile-first super-app in Rwanda/Malta. 
Generate ONE content card with these fields as JSON:
- title: 6-10 words, catchy and actionable
- subtitle: 8-15 words, supporting detail
- body: 1-2 sentences, more detail about the value proposition
- rationale: 1 sentence starting with a stat or insight that explains why this matters

Rules:
- Be specific, not generic
- Use positive, encouraging tone
- Never mention competitors
- Keep it culturally relevant
- Output ONLY valid JSON, no markdown fences`;

  try {
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [
            {
              parts: [{ text: `${systemPrompt}\n\nTopic: ${prompt}` }],
            },
          ],
          generationConfig: {
            temperature: 0.9,
            maxOutputTokens: 300,
            responseMimeType: "application/json",
          },
        }),
      },
    );

    if (!res.ok) {
      console.error("Gemini API error:", res.status, await res.text());
      return null;
    }

    const data = await res.json();
    const text = data?.candidates?.[0]?.content?.parts?.[0]?.text?.trim() ?? "";
    if (!text) return null;

    return JSON.parse(text) as GeneratedContent;
  } catch (e) {
    console.error("Gemini generation error:", e);
    return null;
  }
}

type AdminClientLike = ReturnType<typeof createAdminClient>;

export type GenerateAiContentHandlerDependencies = {
  createAdminClient: () => AdminClientLike;
  requireAdminCaller: (request: Request) => Promise<AuthenticatedCaller>;
  requireCronSecret: (request: Request) => void;
  generateContent: (prompt: string) => Promise<GeneratedContent | null>;
  random: () => number;
  now: () => Date;
};

const defaultDependencies: GenerateAiContentHandlerDependencies = {
  createAdminClient,
  requireAdminCaller,
  requireCronSecret: (request) =>
    requireCronSecret(request, [
      "GENERATE_AI_CONTENT_CRON_SECRET",
      "CRON_JOB_SECRET",
    ]),
  generateContent: generateWithGemini,
  random: () => Math.random(),
  now: () => new Date(),
};

function pickRandomTemplate(random: () => number) {
  return CONTENT_TEMPLATES[Math.floor(random() * CONTENT_TEMPLATES.length)];
}

export function createGenerateAiContentHandler(
  dependencies: Partial<GenerateAiContentHandlerDependencies> = {},
) {
  const deps: GenerateAiContentHandlerDependencies = {
    ...defaultDependencies,
    ...dependencies,
  };

  return async (request: Request) => {
    const corsResponse = handleCors(request);
    if (corsResponse) {
      return corsResponse;
    }

    if (request.method !== "POST") {
      return methodNotAllowed("POST");
    }

    const adminClient = deps.createAdminClient();
    let actorUserId: string | null = null;

    try {
      const url = new URL(request.url);
      const isManual = url.searchParams.get("manual") === "true";

      if (isManual) {
        actorUserId = (await deps.requireAdminCaller(request)).userId;
      } else {
        deps.requireCronSecret(request);
      }

      const { data: config, error: configError } = await adminClient
        .from("ai_content_generation_config")
        .select("is_enabled")
        .limit(1)
        .maybeSingle();

      if (configError) {
        throw configError;
      }

      if (!isManual && !config?.is_enabled) {
        return jsonResponse({
          success: false,
          reason: "Auto-generation is disabled by admin",
        });
      }

      const template = pickRandomTemplate(deps.random);
      const generated = await deps.generateContent(template.prompt);

      if (!generated) {
        return jsonResponse({
          success: false,
          reason: "Generation failed",
        });
      }

      const { data: existing, error: duplicateCheckError } = await adminClient
        .from("ai_content")
        .select("id")
        .eq("title", generated.title)
        .limit(1);

      if (duplicateCheckError) {
        throw duplicateCheckError;
      }

      if (existing && existing.length > 0) {
        generated.title += ` (${deps.now().toISOString().slice(0, 10)})`;
      }

      const { error: insertError } = await adminClient.from("ai_content")
        .insert({
          title: generated.title,
          subtitle: generated.subtitle,
          body: generated.body,
          rationale: generated.rationale,
          content_type: "recommendation",
          status: "pending_review",
          icon_emoji: template.icon,
          cta_action: template.cta_action,
          cta_label: template.cta_label,
          sort_order: Math.floor(deps.random() * 100),
          is_active: false,
        });

      if (insertError) {
        throw insertError;
      }

      const nowIso = deps.now().toISOString();
      const { error: updateConfigError } = await adminClient
        .from("ai_content_generation_config")
        .update({
          last_generated_at: nowIso,
          updated_at: nowIso,
          updated_by: actorUserId,
        })
        .not("id", "is", null);

      if (updateConfigError) {
        throw updateConfigError;
      }

      return jsonResponse({
        success: true,
        title: generated.title,
        area: template.area,
        status: "pending_review",
      });
    } catch (error) {
      if (error instanceof HttpError) {
        return errorResponse(error.message, error.status);
      }

      console.error("generate-ai-content failed", error);
      await recordEdgeFunctionFailure(adminClient, {
        functionName: "generate-ai-content",
        error,
        userId: actorUserId,
        issueCode: "generate_ai_content_failed",
      });
      return errorResponse(
        error instanceof Error
          ? error.message
          : "Failed to generate AI content.",
        500,
      );
    }
  };
}

if (import.meta.main) {
  Deno.serve(createGenerateAiContentHandler());
}
